## battle/battle_fx.gd — 战斗演出特效（伤害数字 / 血条受击 / 飘字 / 抖动）+ PixelFx 预热
##
## 职责：
##   - 通用飘字（治疗绿 / buff 黄 / 回 MP 蓝；伤害红已由 pixelfx damage-number 接管）
##   - 受击特效：damage-number 头顶数字 + health-bar-hit 血条闪减（含 impact 分发门控）
##   - 单位受击抖动（相机右方向 4 美术像素）
##   - 演出前预热：impacts 的动态变体提前烘焙进 PixelFx2D 静态缓存；
##     首次沉浸预热经 LoadingScreen 遮罩覆盖烘焙卡顿
##
## 设计：从 scenes/battle.gd 抽出的 Node（create_tween/await 需要 Node）。
## 不持有父场景引用：grid / unit_sprites / immersive_camera 由 battle.gd 在 setup() 注入；
## 单位脚点屏幕坐标（cell_screen_fn）/ 取景相机（camera_fn）/ 飘字容器（float_container_fn）
## 经 Callable 回交，B1/B2 差异由 battle.gd 的适配方法吸收（与拆分前分支逐行等价）。
##
## 公开 API（battle.gd 调用）：
##   setup(grid, unit_sprites, immersive_camera, cell_screen_fn, camera_fn, float_container_fn)
##   spawn_action_float_text(unit_id, text, color, font_size)  # ActionAnim 飘字回调
##   spawn_float_text(u, text, color, font_size)
##   spawn_damage_from_impact(impact)                          # impact → 伤害特效（含门控）
##   spawn_damage_fx(u, damage, hp_before, hp_after)
##   shake_sprite(us)
##   prewarm_action_fx(event, impacts, skipped) -> bool        # await；false=等待期间战斗已退出
##   prewarm_item_damage_fx(result)

class_name BattleFx
extends Node

const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const PixelFx2DScript = preload("res://addons/pixelfx/nodes/pixel_fx_2d.gd")
const PixelFxBakerScript = preload("res://addons/pixelfx/bake/baker.gd")

## grid 允许 duck-type：真实 GridSystem 或舞台代理网格（只需 units: {id -> unit dict}）。
var grid
var unit_sprites: Dictionary
var immersive_camera: Node = null
## 战场局部 cell → 屏幕坐标（默认站立/可见顶面层；battle.gd 的 _float_cell_to_screen）。
var cell_screen_fn: Callable
## 当前取景 Camera3D（battle.gd 的 _damage_camera；B1 世界相机 / B2 战场相机）。
var camera_fn: Callable
## 飘字/特效容器（battle_ui.get_float_text_container）。
var float_container_fn: Callable


func setup(
	p_grid,
	p_unit_sprites: Dictionary,
	p_immersive_camera: Node,
	p_cell_screen_fn: Callable,
	p_camera_fn: Callable,
	p_float_container_fn: Callable
) -> void:
	grid = p_grid
	unit_sprites = p_unit_sprites
	immersive_camera = p_immersive_camera
	cell_screen_fn = p_cell_screen_fn
	camera_fn = p_camera_fn
	float_container_fn = p_float_container_fn


## ActionAnim 每个 impact 只回调一次，按权威单位 id 取当前格位，避免重复订阅飘字信号。
func spawn_action_float_text(unit_id: StringName, text: String, color: Color, font_size: int) -> void:
	var unit: Dictionary = grid.units.get(unit_id, {})
	if unit.is_empty():
		return
	spawn_float_text(unit, text, color, font_size)


## 通用飘字（ActionAnim/物品用：治疗绿、buff 黄、回 MP 蓝；伤害红已由 pixelfx 接管）。
func spawn_float_text(u: Dictionary, text: String, color: Color, font_size: int = 18) -> void:
	# 伤害数字（"-N"）统一走 pixelfx damage-number + health-bar-hit，不再叠标签飘字。
	if text.begins_with("-"):
		return
	var lbl := UIFactoryScript.outline_label(text, font_size, color, 4)
	# 单位脚点由注入的坐标适配投影到屏幕，再抬升 50px。
	var screen: Vector2 = cell_screen_fn.call(u.position.x, u.position.y)
	lbl.position = screen + Vector2(0, -50) - Vector2(20, 30)
	(float_container_fn.call() as CanvasItem).add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 30, 0.7)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.7)
	tw.tween_callback(lbl.queue_free)


## ActionAnim 每次 impact 回调一次的分发（battle.gd _on_impact_presented 的特效半段）：
## 实际受伤（命中且 damage>0）播 pixelfx 伤害数字 + 血条受击特效。零伤害 / 未命中 / 治疗 / 纯 buff 均不触发。
func spawn_damage_from_impact(impact: Dictionary) -> void:
	if not bool(impact.get(&"hit", false)):
		return
	var damage := int(impact.get(&"damage", 0))
	if damage <= 0:
		return
	var unit_id := StringName(impact.get(&"target_id", &""))
	var u: Dictionary = grid.units.get(unit_id, {})
	if u.is_empty():
		return
	spawn_damage_fx(u, damage, int(impact.get(&"hp_before", int(u.get(&"hp", 0)))), int(impact.get(&"hp_after", int(u.get(&"hp", 0)))))


## 演出前预热：把 impacts 的动态变体（伤害数字 text / 血条 from/to）提前烘焙进 PixelFx2D 静态缓存。
## BAKED 缓存键 = 脚本路径|JSON.stringify(options)|layer —— 动态参数几乎每个伤害值/血量比都是冷变体，
## 冷播放要逐帧 CPU 渲染 + ImageTexture 创建上传（headless 实测约 120~194ms/帧，拖垮整个 2s 动画）；
## 在 action_anim.play 的走位窗口里同步预热（单变体毫秒级），受伤瞬间即为热重放（≤1.7ms/帧）。
func prewarm_damage_fx_variants(impacts: Array) -> void:
	for impact_value in impacts:
		var impact: Dictionary = impact_value
		if not bool(impact.get(&"hit", false)) or int(impact.get(&"damage", 0)) <= 0:
			continue
		var u: Dictionary = grid.units.get(StringName(impact.get(&"target_id", &"")), {})
		if u.is_empty():
			continue
		var damage := int(impact.get(&"damage", 0))
		var max_hp: int = max(1, int((u.get(&"stats", {}) as Dictionary).get(&"hp", 1)))
		var hp_before := int(impact.get(&"hp_before", int(u.get(&"hp", 0))))
		var hp_after := int(impact.get(&"hp_after", int(u.get(&"hp", 0))))
		prewarm_fx_variant("ui/damage-number", {"text": "-%d" % damage})
		prewarm_fx_variant("ui/health-bar-hit", {
			"from": clampf(float(hp_before) / float(max_hp), 0.0, 1.0),
			"to": clampf(float(hp_after) / float(max_hp), 0.0, 1.0),
		})


## 遮罩只在本场战斗首次预热时展示：缓存键含伤害值文本，几乎每个伤害值都是冷变体，
## 每次出手都真烘焙；但玩家只需第一次感知"加载"，之后静默烘焙不再闪遮罩。
var _mask_shown := false


## 演出前预热（含可选全局加载遮罩）：沉浸镜头确认会接管时，先弹 LoadingScreen 并
## await 2 帧让遮罩真正上屏，再在遮罩下同步预烘焙特效变体（烘焙卡顿由遮罩覆盖），随后立即隐藏。
## 默认关闭/空事件/预先跳过时走原同步预热路径，不弹遮罩。返回 false = 等待期间战斗已退出。
func prewarm_action_fx(event: Dictionary, impacts: Array, skipped: bool) -> bool:
	var use_loading_screen: bool = (
		immersive_camera.would_begin(event, unit_sprites, skipped)
		and not _mask_shown
	)
	if use_loading_screen:
		_mask_shown = true
		LoadingScreen.show_loading()
		# 同步烘焙会卡住当前帧渲染；必须等遮罩先绘制出来，否则卡顿期间全屏无反馈。
		await get_tree().process_frame
		await get_tree().process_frame
		if not is_inside_tree():
			LoadingScreen.hide_loading()
			return false
	prewarm_damage_fx_variants(impacts)
	if use_loading_screen:
		LoadingScreen.hide_loading()
	return true


## 单变体烘焙：缓存未命中才创建 Track 并强制渲染全部帧（Track 是懒渲染，get_textures(n-1) 一次拉全）。
func prewarm_fx_variant(effect_name: String, opts: Dictionary) -> void:
	var path := "res://addons/pixelfx/fx/%s.gd" % effect_name
	# 与 PixelFx2D._reload 的缓存键构造保持一致（layer 默认 ""，故键以 "|" 结尾）。
	var key := "%s|%s|" % [path, JSON.stringify(opts)]
	if PixelFx2D._cache.has(key):
		return
	var mod: Script = load(path)
	if mod == null:
		return
	var track = PixelFxBakerScript.track(mod, opts)
	track.get_textures(track.n - 1)
	PixelFx2D._cache[key] = track


## 物品路径预热：由 hp_deltas 反推伤害变体（与 _resolve_item 的 spawn_damage_fx 参数一致）。
func prewarm_item_damage_fx(result: Dictionary) -> void:
	for h in result.get(&"hp_deltas", []):
		var t: Dictionary = h[&"unit"]
		var delta: int = int(h[&"delta"])
		if delta >= 0:
			continue
		var hp_after := int(t.get(&"hp", 0))
		var u: Dictionary = grid.units.get(StringName(t.get(&"id", &"")), t)
		var max_hp: int = max(1, int((u.get(&"stats", {}) as Dictionary).get(&"hp", 1)))
		prewarm_fx_variant("ui/damage-number", {"text": "-%d" % -delta})
		prewarm_fx_variant("ui/health-bar-hit", {
			"from": clampf(float(hp_after - delta) / float(max_hp), 0.0, 1.0),
			"to": clampf(float(hp_after) / float(max_hp), 0.0, 1.0),
		})


## 伤害特效：damage-number 绑头顶（实际伤害数字），health-bar-hit 绑同锚点（from=伤前 to=伤后 占最大生命比）。
func spawn_damage_fx(u: Dictionary, damage: int, hp_before: int, hp_after: int) -> void:
	if damage <= 0:
		return
	var us: UnitSprite3D = unit_sprites.get(u.get(&"id", &""))
	if us == null:
		return
	var camera: Camera3D = camera_fn.call()
	if camera == null:
		return
	var head := camera.unproject_position(us.global_position + Vector3(0.0, us.get_head_y(), 0.0))
	var dn: Node2D = PixelFx2DScript.new()
	dn.effect = "ui/damage-number"
	dn.options = {"text": "-%d" % damage}
	dn.free_when_done = true
	dn.position = head + Vector2(0, -10)
	(float_container_fn.call() as CanvasItem).add_child(dn)
	var hit_fx: Node2D = PixelFx2DScript.new()
	hit_fx.effect = "ui/health-bar-hit"
	var max_hp: int = max(1, int((u.get(&"stats", {}) as Dictionary).get(&"hp", 1)))
	hit_fx.options = {
		"from": clampf(float(hp_before) / float(max_hp), 0.0, 1.0),
		"to": clampf(float(hp_after) / float(max_hp), 0.0, 1.0),
	}
	var faction_color: Color = UnitSprite3D.FACTION_COLOR.get(u.get(&"faction", &"other"), Color.WHITE)
	hit_fx.options["palette"] = [
		"#" + faction_color.darkened(0.9).to_html(false),
		"#" + faction_color.darkened(0.7).to_html(false),
		"#" + faction_color.darkened(0.4).to_html(false),
		"#" + faction_color.darkened(0.2).to_html(false),
		"#" + faction_color.to_html(false),
		"#" + faction_color.lightened(0.3).to_html(false),
		"#" + faction_color.lightened(0.65).to_html(false),
		"#ffffff",
	]
	hit_fx.free_when_done = true
	# 原特效填充条宽 104px，缩至 24px 并对齐脚底血条；伤害数字保持头顶锚点。
	var bar_scale := 24.0 / 104.0
	hit_fx.scale = Vector2.ONE * bar_scale
	var feet := camera.unproject_position(us.global_position + Vector3.UP * us.get_bar_y())
	hit_fx.position = feet + Vector2(0, 4) - Vector2(84, 30) * bar_scale
	(float_container_fn.call() as CanvasItem).add_child(hit_fx)


func shake_sprite(us: Node3D) -> void:
	# 在相机右方向水平抖动 4 个美术像素。
	var orig: Vector3 = us.global_position
	var camera := get_viewport().get_camera_3d()
	var right := camera.global_basis.x if camera != null else Vector3.RIGHT
	var tw := create_tween()
	for i in range(4):
		tw.tween_property(us, "global_position", orig + right * (4.0 / 32.0) * (1.0 if i % 2 == 0 else -1.0), 0.04)
	tw.tween_property(us, "global_position", orig, 0.04)
