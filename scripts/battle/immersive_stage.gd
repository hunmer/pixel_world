## battle/immersive_stage.gd — 独立沉浸战斗舞台（SubViewport 内的对角阵营演出场景）。
##
## 职责：把一次结算事件(AttackEvent)搬进隔离 World3D 的独立舞台演出——
##   - 参战者 = 出手者 + 主目标 + 每个 impact 的 source/target 去重（含真实夹击友军与反击方）；
##   - 我方/友军站屏幕左下角、敌方站右上角（faction 固定，不因敌方先手换侧）；
##   - 代理单位 = 真实单位深拷贝；HP 用各自首个作为目标的 impact.hp_before 重建，
##     逐 impact 推进（含死亡），绝不写回真实战斗数据；
##   - 严格按原 impacts 顺序逐次出手：每次 run_strike 一个 impact，
##     反击/连击/追击分别以出手模板（按实际 source 武器）、飘字标签与金色高亮可辨识；
##   - 特效/飘字/伤害数字经舞台内自建的 BattleFx + ActionAnim 实例渲染在舞台视口内，
##     声音经信号回交宿主（BattleSfx），真实战场相机与演出链路完全不被驱动。
##
## 用法：battle.gd 在 battle_ui 内挂 SubViewportContainer，把本场景实例加入容器，
## set_enabled 跟随沉浸开关；should_present 通过后 await present(...)。
##
## 复用说明：出手循环内核直接复用 scripts/battle/action_anim.gd 的
## prepare_event / run_strike / finish_event 事件级 API（同一份视觉时序与模板特效）。
class_name ImmersiveStage
extends SubViewport

signal presentation_started(event: Dictionary)
signal presentation_finished(event: Dictionary, skipped: bool)
## 每次出手循环开始前发出（pseudo_event.anim 已按实际 source 武器解析），
## 宿主接 BattleSfx.play_strike；impact_presented 宿主接 BattleSfx.play_impact。
signal strike_scheduled(pseudo_event: Dictionary)
signal impact_presented(impact: Dictionary)

const ImmersiveStageLayoutScript = preload("res://scripts/battle/immersive_stage_layout.gd")
const ActionAnimScript = preload("res://scripts/battle/action_anim.gd")
const BattleFxScript = preload("res://scripts/battle/battle_fx.gd")
const UnitSpriteScript = preload("res://scripts/iso/unit_sprite.gd")
const IsoCameraScript = preload("res://scripts/iso/isometric_camera_3d.gd")
const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")

const CharacterSheet = preload("res://scripts/iso/character_sheet.gd")

## 舞台取景：近平视正交（四角 yaw 之一），两阵营对角分立画面两侧。
## 取景自适应：以参战者脚/头采样点的实际投影为准，内容溢出视口时按比例缩小
## zoom（正交投影线性缩放，一次换算即可），不裁切任何参战者。
const STAGE_YAW := IsoProjection.CAMERA_YAW
const STAGE_ELEVATION := deg_to_rad(24.0)
const STAGE_ZOOM := 3.6
const STAGE_ZOOM_FIT_FLOOR := 0.75
## 采样余量：横向/纵向视口安全边（像素）与代理身位（世界单位）。
const FRAME_MARGIN_X_PX := 48.0
const FRAME_MARGIN_Y_PX := 56.0
const SPRITE_HALF_WIDTH := 0.35
const HEAD_SAMPLE_HEIGHT := 1.45
## 转场时长（秒，基准速度）；按演出倍速缩短。
const ENTER_FADE := 0.16
const EXIT_FADE := 0.16
## 转场基准帧率（帧数换算用，与引擎实际帧率无关）。
const TRANSITION_FPS := 60.0
const DEATH_FADE := 0.32

var _camera: Camera3D = null
var _unit_root: Node3D = null
var _floor_root: Node3D = null
var _ui_layer: CanvasLayer = null
var _float_container: Control = null
var _fade_rect: ColorRect = null
var _anim: Node = null
var _fx: Node = null

## 演出状态（真实单位引用仅只读：武器/职业查询）。
var _enabled := false
var _presenting := false
var _skip_requested := false
var _cancelled := false
var _speed := 1.0
var _skipped := false
var _last_event: Dictionary = {}
var _real_units := {}      ## id -> 真实单位 dict（只读）
var _stage_units := {}     ## id -> 代理单位 dict（HP 推进）
var _sprites := {}         ## id -> 代理 UnitSprite3D
var _slots := {}           ## id -> {cell, side, facing}
var _death_tweens: Array = []
## 命中帧推进：impact_presented（出手循环的 HIT 帧）时同步推进代理 HP/死亡，
## 出手循环结束后的兜底推进只在信号未发生（被 skip 截断）时补一次，绝不双推。
var _current_impact_index := -1
var _impact_applied := false


func _init() -> void:
	own_world_3d = true
	world_3d = World3D.new()
	## 音频监听不跟随舞台：声音仍由宿主 BattleSfx 在主视口播放。
	audio_listener_enable_3d = false
	render_target_update_mode = SubViewport.UPDATE_ALWAYS


func set_enabled(value: bool) -> void:
	_enabled = value
	if not value and _presenting:
		request_skip()


func is_enabled() -> bool:
	return _enabled


func is_presenting() -> bool:
	return _presenting


## 是否走舞台路径：开关开启、非整体 skip、事件有 impact 且存在可站上舞台的参战者。
func should_present(event: Dictionary, unit_sprites: Dictionary, skipped: bool) -> bool:
	if not _enabled or skipped:
		return false
	if event.get(&"impacts", []).is_empty():
		return false
	var source := {}
	for unit_id in unit_sprites.keys():
		var sprite: Node = unit_sprites[unit_id]
		if sprite != null and is_instance_valid(sprite):
			source[unit_id] = sprite.unit
	return not ImmersiveStageLayoutScript.participants_for(event, source).is_empty()


## 主入口：await 至整场演出结束（含退出淡出）。
func present(event: Dictionary, unit_sprites: Dictionary, anim_speed: float = 1.0, skipped: bool = false) -> void:
	if _presenting:
		push_error("ImmersiveStage.present: 上一场演出尚未结束")
		return
	_presenting = true
	_skip_requested = false
	_skipped = skipped
	_speed = clampf(anim_speed, 0.1, 8.0)
	_last_event = event
	_real_units = {}
	for unit_id in unit_sprites.keys():
		var sprite: Node = unit_sprites[unit_id]
		if sprite != null and is_instance_valid(sprite):
			_real_units[unit_id] = sprite.unit
	presentation_started.emit(event)
	_build_stage(event)
	await get_tree().process_frame
	if not is_inside_tree():
		_teardown()
		return
	await _play_enter()
	if _cancelled:
		return
	# 出手序列：严格原 impacts 顺序；每个 impact 一次完整出手循环。
	var impacts: Array = event.get(&"impacts", [])
	if _anim.prepare_event(event, _speed, skipped):
		for i in range(impacts.size()):
			var impact: Dictionary = impacts[i]
			if _skip_requested:
				_apply_impact_state(impact)
				continue
			_current_impact_index = i
			_impact_applied = false
			var pseudo := _build_strike_event(event, impact, i)
			strike_scheduled.emit(pseudo)
			_announce_label(pseudo)
			await _anim.run_strike(pseudo)
			_current_impact_index = -1
			if not is_inside_tree():
				_teardown()
				return
			# 兜底：HIT 帧信号被 skip 截断（未发生）时才补推，绝不双推。
			if not _impact_applied:
				_apply_impact_state(impact)
			if not _anim.is_playing():
				break
		_anim.finish_event()
		# finish_event 会恢复参战者演出前视觉（含倒地姿态），死亡终态在此重放。
		_reassert_deaths()
	if _cancelled:
		return
	await _play_exit()
	if _cancelled:
		return
	var was_skipped := _skip_requested or skipped
	presentation_finished.emit(event, was_skipped)
	_teardown()


## 整体跳过请求（宿主 skip 输入）：当前出手立即收尾，剩余 impact 只推进状态不再演出。
func request_skip() -> void:
	_skip_requested = true
	if _anim != null and _anim.is_playing():
		_anim.skip()


## 强制中止（宿主 _exit_tree）：立即清理，present 协程的后续 await 检查
## _cancelled 后直接返回——不补发 presentation_finished（宿主本身正在退出树）。
func cancel() -> void:
	_cancelled = true
	_skip_requested = true
	if _anim != null and is_instance_valid(_anim) and _anim.is_playing():
		_anim.skip()
		_anim.finish_event()
	_teardown()


func _exit_tree() -> void:
	_cancelled = true
	_teardown()


## ————— 舞台搭建 —————


## 搭建代理单位/站位/地板。代理 = 真实单位深拷贝，不写回。
func _build_stage(event: Dictionary) -> void:
	_ensure_nodes()
	_teardown_dynamic()
	var participants: Array = ImmersiveStageLayoutScript.participants_for(event, _real_units)
	_slots = ImmersiveStageLayoutScript.build_slots(event, participants)
	var participants_units := {}
	for unit in participants:
		participants_units[unit[&"id"]] = unit
	var hp_map: Dictionary = ImmersiveStageLayoutScript.initial_hp_map(event, participants_units)
	for unit_id in _slots.keys():
		var real_unit: Dictionary = participants_units[unit_id]
		var slot: Dictionary = _slots[unit_id]
		var proxy: Dictionary = real_unit.duplicate(true)
		proxy[&"hp"] = int(hp_map[unit_id][&"hp"])
		proxy[&"isDead"] = false
		proxy[&"hasActed"] = false
		proxy[&"position"] = slot[&"cell"]
		_stage_units[unit_id] = proxy
		var sprite: UnitSprite3D = UnitSpriteScript.new()
		_unit_root.add_child(sprite)
		sprite.setup_stage(proxy, _camera)
		sprite.set_facing_world(slot[&"facing"])
		_sprites[unit_id] = sprite
		_spawn_floor_slot(slot)
	_spawn_floor_backdrop()
	_fx.setup(
		{&"units": _stage_units},
		_sprites,
		null,
		Callable(self, "_cell_to_screen"),
		Callable(self, "_stage_camera"),
		Callable(self, "_get_float_container")
	)
	_center_camera()


func _ensure_nodes() -> void:
	if _camera != null and is_instance_valid(_camera):
		return
	var camera_node := Node3D.new()
	camera_node.name = "StageCameraRig"
	add_child(camera_node)
	_camera = Camera3D.new()
	_camera.set_script(IsoCameraScript)
	camera_node.add_child(_camera)
	_unit_root = Node3D.new()
	_unit_root.name = "StageUnits"
	add_child(_unit_root)
	_floor_root = Node3D.new()
	_floor_root.name = "StageFloor"
	add_child(_floor_root)
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "StageUI"
	_ui_layer.layer = 10
	add_child(_ui_layer)
	_float_container = Control.new()
	_float_container.name = "StageFloats"
	_float_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_float_container)
	_fade_rect = ColorRect.new()
	_fade_rect.name = "StageFade"
	_fade_rect.color = Color(0.02, 0.02, 0.04, 1.0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_fade_rect)
	_anim = ActionAnimScript.new()
	_anim.name = "StageActionAnim"
	add_child(_anim)
	_anim.setup(_sprites, _camera, Callable(self, "_on_float_text"))
	_anim.impact_presented.connect(_on_impact_presented)
	_fx = BattleFxScript.new()
	_fx.name = "StageBattleFx"
	add_child(_fx)


func _teardown_dynamic() -> void:
	for tween in _death_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_death_tweens.clear()
	for sprite in _sprites.values():
		if sprite != null and is_instance_valid(sprite):
			sprite.queue_free()
	_sprites.clear()
	_stage_units.clear()
	_slots.clear()
	for child in _floor_root.get_children():
		child.queue_free()


func _teardown() -> void:
	_teardown_dynamic()
	_presenting = false
	_current_impact_index = -1
	_impact_applied = false


## ————— 演出流程 —————


## 进入/退出转场：逐帧步进，时长随演出倍速缩短（speed=8 时约 1 帧），
## skip/取消（_cancelled）立即跳出，不挂任何 await 补等待。
func _play_enter() -> void:
	if _fade_rect == null or not is_instance_valid(_fade_rect):
		return
	_fade_rect.color.a = 1.0
	var frames := maxi(1, int(round(ENTER_FADE * TRANSITION_FPS / _speed)))
	for i in range(frames):
		if _cancelled or not is_inside_tree():
			_fade_rect.color.a = 0.0
			return
		await get_tree().process_frame
		_fade_rect.color.a = 1.0 - float(i + 1) / float(frames)
	_fade_rect.color.a = 0.0


func _play_exit() -> void:
	if _fade_rect == null or not is_instance_valid(_fade_rect):
		return
	_fade_rect.color.a = 0.0
	var frames := maxi(1, int(round(EXIT_FADE * TRANSITION_FPS / _speed)))
	for i in range(frames):
		if _cancelled or not is_inside_tree():
			_fade_rect.color.a = 1.0
			return
		await get_tree().process_frame
		_fade_rect.color.a = float(i + 1) / float(frames)
	_fade_rect.color.a = 1.0


## 逐 impact 出手事件：anim 按实际 source 武器解析（反击/追击不再冒用主出手者模板）。
func _build_strike_event(event: Dictionary, impact: Dictionary, index: int) -> Dictionary:
	var source_id := StringName(impact.get(&"source_id", &""))
	var source: Dictionary = _stage_units.get(source_id, {})
	var pseudo := {
		&"version": 1,
		&"kind": StringName(event.get(&"kind", &"normal")),
		&"attacker_id": source_id,
		&"primary_target_id": StringName(impact.get(&"target_id", &"")),
		&"anim": ImmersiveStageLayoutScript.strike_anim_for(event, source),
		&"element": StringName(impact.get(&"element", &"physical")),
		&"impacts": [impact.duplicate(true)],
		&"hitstop": float(event.get(&"hitstop", 0.0)),
		&"weakness": bool(impact.get(&"weakness", false)),
		&"double_attack": false,
		&"statuses": impact.get(&"statuses", []).duplicate(true),
	}
	var label: String = ImmersiveStageLayoutScript.strike_label(event, index, impact)
	if label != "":
		pseudo[&"_stage_label"] = label
	return pseudo


## 出手循环开始前由 sequencer 主动调用（strike_scheduled 之后）：打出标签飘字。
func _announce_label(pseudo: Dictionary) -> void:
	var label := String(pseudo.get(&"_stage_label", ""))
	if label == "":
		return
	var source_id := StringName(pseudo.get(&"attacker_id", &""))
	if not _stage_units.has(source_id):
		return
	_fx.spawn_float_text(_stage_units[source_id], label, Color(1.0, 0.85, 0.35), 22)


## 逐 impact 状态推进：HP/死亡以 impact 权威值回写代理（命中帧或 skip 兜底各一次）。
func _apply_impact_state(impact: Dictionary) -> void:
	var target_id := StringName(impact.get(&"target_id", &""))
	if not _stage_units.has(target_id):
		return
	var proxy: Dictionary = _stage_units[target_id]
	proxy[&"hp"] = int(impact.get(&"hp_after", proxy.get(&"hp", 0)))
	var died := bool(impact.get(&"died", false))
	if died:
		# 数据态立即落地（演出读的是权威值）；视觉隐藏等渐隐结束。
		proxy[&"isDead"] = true
	var sprite: UnitSprite3D = _sprites.get(target_id)
	if sprite == null or not is_instance_valid(sprite):
		return
	if died and not _skip_requested:
		# 先倒地渐隐，再隐藏（update_state 见 isDead 会立即 visible=false，抢先了渐隐）。
		sprite.set_pose(CharacterSheet.POSE_DOWNED)
		var tween := sprite.create_tween()
		tween.tween_method(sprite.fade_alpha, 1.0, 0.0, DEATH_FADE)
		tween.tween_callback(func() -> void:
			if is_instance_valid(sprite):
				sprite.update_state())
		_death_tweens.append(tween)
	else:
		sprite.update_state()


## 出手循环收尾后重放死亡终态：finish_event/_restore_visuals 会把参战者
## 恢复到演出前视觉（含倒地姿态被还原、alpha 被复原），死亡单位须重新落地。
func _reassert_deaths() -> void:
	for unit_id in _stage_units.keys():
		var proxy: Dictionary = _stage_units[unit_id]
		if not bool(proxy.get(&"isDead", false)):
			continue
		var sprite: UnitSprite3D = _sprites.get(unit_id)
		if sprite == null or not is_instance_valid(sprite):
			continue
		sprite.set_pose(CharacterSheet.POSE_DOWNED)
		sprite.update_state()


## ————— 回交/坐标 —————


func _on_float_text(unit_id: StringName, text: String, color: Color, font_size: int) -> void:
	if _fx != null:
		_fx.spawn_action_float_text(unit_id, text, color, font_size)


## HIT 帧回调：先推进代理 HP/死亡（飘字/伤害数字读到的是受击后血条），
## 再生成伤害特效并回交宿主（音效/外部断言）。同一 impact 只推进一次。
func _on_impact_presented(impact: Dictionary) -> void:
	if _current_impact_index >= 0 and not _impact_applied:
		_apply_impact_state(impact)
		_impact_applied = true
	_fx.spawn_damage_from_impact(impact)
	impact_presented.emit(impact)


func _stage_camera() -> Camera3D:
	return _camera


func _get_float_container() -> Control:
	return _float_container


func _cell_to_screen(x: int, y: int) -> Vector2:
	if _camera == null:
		return Vector2.ZERO
	return _camera.unproject_position(IsoProjection.grid_to_world(Vector2i(x, y), 0.0) + Vector3(0.0, 0.5, 0.0))


## ————— 视觉装配 —————


## 焦点 = 全部站位包围盒水平中心（对角分立时即两阵营锚点中点）；取景自适应：
## 先按基准 zoom 放好相机，再把每个参战者脚/头采样点经实际投影比对视口安全框，
## 溢出则按比例缩小 zoom（正交线性换算，一次到位），保证任何窗口比例/人数不裁切。
func _center_camera() -> void:
	var script: Object = _camera
	script.yaw_radians = STAGE_YAW
	script.target_yaw_radians = STAGE_YAW
	script.elevation_radians = STAGE_ELEVATION
	script.target_elevation_radians = STAGE_ELEVATION
	script.presentation_distance = IsoCameraScript.CAMERA_DISTANCE
	var min_v := Vector3.INF
	var max_v := -Vector3.INF
	for slot in _slots.values():
		var world := IsoProjection.grid_to_world(slot[&"cell"], 0.0)
		min_v = min_v.min(world - Vector3(SPRITE_HALF_WIDTH, 0.0, SPRITE_HALF_WIDTH))
		max_v = max_v.max(world + Vector3(SPRITE_HALF_WIDTH, 0.0, SPRITE_HALF_WIDTH))
	var focus := Vector3.ZERO
	if min_v.x <= max_v.x:
		focus = Vector3((min_v.x + max_v.x) * 0.5, 0.0, (min_v.z + max_v.z) * 0.5)
	script.focus_position = focus
	script.zoom = STAGE_ZOOM
	var overflow := _projected_overflow()
	if overflow > 1.0:
		script.zoom = clampf(STAGE_ZOOM / overflow, STAGE_ZOOM_FIT_FLOOR, STAGE_ZOOM)


## 采样点实际投影相对视口安全框的溢出倍率（1.0 = 恰好贴合）。
## 采样：每个站位的四向脚点（含身位半宽）+ 头顶点（立绘+血条高度）。
func _projected_overflow() -> float:
	var rect: Rect2 = get_visible_rect()
	var half_w := rect.size.x * 0.5 - FRAME_MARGIN_X_PX
	var half_h := rect.size.y * 0.5 - FRAME_MARGIN_Y_PX
	if half_w <= 1.0 or half_h <= 1.0:
		return 1.0
	var worst := 1.0
	for slot in _slots.values():
		var ground := IsoProjection.grid_to_world(slot[&"cell"], 0.0)
		for offset in _framing_samples():
			var screen: Vector2 = _camera.unproject_position(ground + offset)
			worst = maxf(worst, absf(screen.x - rect.size.x * 0.5) / half_w)
			worst = maxf(worst, absf(screen.y - rect.size.y * 0.5) / half_h)
	return worst


func _framing_samples() -> Array:
	return [
		Vector3(SPRITE_HALF_WIDTH, 0.05, 0.0),
		Vector3(-SPRITE_HALF_WIDTH, 0.05, 0.0),
		Vector3(0.0, 0.05, SPRITE_HALF_WIDTH),
		Vector3(0.0, 0.05, -SPRITE_HALF_WIDTH),
		Vector3(0.0, HEAD_SAMPLE_HEIGHT, 0.0),
	]


func _spawn_floor_backdrop() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(30.0, 30.0)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = Vector3(0.0, -0.02, 0.0)
	instance.material_override = _flat_material(Color(0.07, 0.08, 0.11))
	_floor_root.add_child(instance)


func _spawn_floor_slot(slot: Dictionary) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.62, 0.62)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var world := IsoProjection.grid_to_world(slot[&"cell"], 0.0)
	instance.position = Vector3(world.x, 0.001, world.z)
	var tint := Color(0.16, 0.22, 0.30) if slot[&"side"] == ImmersiveStageLayoutScript.SIDE_ALLY else Color(0.30, 0.16, 0.16)
	instance.material_override = _flat_material(tint)
	_floor_root.add_child(instance)


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
