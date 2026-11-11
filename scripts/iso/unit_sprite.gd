## iso/unit_sprite.gd — 等距单位视觉（从 phaserjs 的 Node3D 版重写为 Node2D）
##
## pixel_world 是 2D 项目，单位改用 Node2D + Sprite2D（立绘）+ Label（头顶文本）+
## ColorRect/Polygon2D（HP 条）。**保留原 API 签名**（setup/update_state/move_along_path/fade_alpha），
## 让 battle.gd / turn_director.gd 的状态机和演出逻辑不用改。
##
## Y-sort：本类不直接参与 main.gd 的 Y-sort（战棋是独立场景，Battle.tscn 根 Node2D
## 不开 y_sort_enabled）；移动时直接用 position = cell_to_screen(cell)。
##
## 坐标：global_position 由 update_state() 从 unit.position(Vector2i) 算出屏幕坐标。
## 原 Node3D 版的 global_position(Vector3) 赋值在 Node2D 上 Godot 会自动取 xy。

class_name UnitSprite3D
extends Node2D

## 兼容旧类名（外部代码引用 UnitSprite3D）。
## 2D 下立绘显示的目标像素高度。地块整块 32×26（顶面菱形 16px + 侧壁 10px），
## 立绘缩到约 1 格高，避免越界到相邻格。
const UNIT_VISUAL_PX := 32.0

var unit: Dictionary
var portrait: Sprite2D           # 职业立绘
var _board: IsoBoard             # B2 模式：IsoBoard 引用
var _hp_bg: ColorRect            # HP 条背景（深色）
var _hp_bar: ColorRect           # HP 条前景（绿/黄/红）
var _name_label: Label           # 头顶文本

# ---- B1 就地模式字段（B2 时全为 null/0，走 _board 路径）----
var _world: Node2D = null        # main.gd 引用（替代 _board）
var _stand_level: int = 0        # 单位当前 cell 的站立层（来自 CellContext.height）
var _world_origin: Vector2i = Vector2i.ZERO  # 战场 (0,0) 对应的世界 cell
# 单位内部视觉位置（B1 双轨用：position.y=sort_y, offset 补偿到 _visual_pos）
var _visual_pos: Vector2 = Vector2.ZERO
# B2 等距方块模式：注入 BattlefieldRenderer.stand_level（缺省无效 = 平面 level 0）
var _level_fn: Callable = Callable()


## 当前模式：true=B1 就地（有 _world），false=B2 切场景（有 _board）
func is_world_mode() -> bool:
	return _world != null


## 阵营 → 颜色（与原版一致）
const FACTION_COLOR := {
	player = Color(0.376, 0.647, 0.980),
	enemy = Color(0.973, 0.443, 0.443),
	ally = Color(0.290, 0.867, 0.502),
	other = Color(0.984, 0.749, 0.141),
}

const FACTION_NAME := {
	player = "我方",
	enemy = "敌方",
	ally = "友军",
	other = "中立",
}

# HP 条布局（像素，相对单位中心）
const _HP_BAR_W := 40.0
const _HP_BAR_H := 4.0
const _HP_BAR_Y := -56.0    # HP 条中心 Y（立绘上方）
const _LABEL_Y := -66.0     # 头顶文本 Y（HP 条上方）


func setup(p_unit: Dictionary, board: IsoBoard, p_level_fn := Callable()) -> void:
	unit = p_unit
	_board = board
	_level_fn = p_level_fn
	# 等距方块地形下单位画在地形(z=0)和范围标记(z=5)之上
	z_index = 10
	_build_visual()


## B2 屏幕坐标（可选注入 level_fn 支持柱顶站立高度；缺省 level 0 向后兼容）
func _b2_cell_screen(pos: Vector2i) -> Vector2:
	var lvl := 0
	if _level_fn.is_valid():
		lvl = int(_level_fn.call(pos.x, pos.y))
	return IsoCoords.to_screen(pos.x, pos.y, lvl)


## B1 就地模式入口：注入 main.gd 引用 + 战场世界原点。
## stand_level 由 battle.gd 在 spawn 时通过 main.gd.cell_stand_level(world_cell) 算好传入。
func setup_world(p_unit: Dictionary, p_world: Node2D, p_stand_level: int, p_world_origin: Vector2i) -> void:
	unit = p_unit
	_world = p_world
	_stand_level = p_stand_level
	_world_origin = p_world_origin
	z_index = 10  # B1 模式：单位画在地形(z=0)和范围标记(z=5)之上
	_build_visual()


## B1 双轨定位：position=sort_y（参与父节点 y_sort），offset 补偿到真实屏幕位置。
## 仿 wandering_animal._apply_render_proxy 和 main.gd._set_player_render_position。
## 注意：Node2D 没有 offset 属性（不像 Sprite2D），简化方案用 position = 屏幕坐标 + z_index 保证层级。
func _apply_render_proxy() -> void:
	var pos: Vector2i = unit[&"position"]
	# 战场局部 cell → 世界 cell
	var world_cell: Vector2i = _world_origin + pos
	# 实时更新 stand_level（单位可能移动到不同高度的格子）
	_stand_level = _world.cell_stand_level(world_cell)
	_visual_pos = _world._grid_to_screen(world_cell, float(_stand_level))
	position = _visual_pos


## 编辑器入口（保留原 API，但 pixel_world 不带编辑器，这里仅占位兼容）。
func setup_placed(placed: Dictionary, board: IsoBoard) -> void:
	var stats: Dictionary = placed.get(&"stats", {})
	var adapted := {
		id = placed.get(&"id"),
		classId = placed.get(&"classId"),
		faction = placed.get(&"faction"),
		stats = stats,
		hp = placed.get(&"currentHp", stats.get(&"hp", 1)),
		position = Vector2i(int(placed.get(&"cellX", 0)), int(placed.get(&"cellY", 0))),
		hasActed = false,
		isDead = false,
	}
	setup(adapted, board)


func _build_visual() -> void:
	# 1) 职业立绘（Sprite2D，缺图跳过）
	if ProfessionVisual.portrait_exists(unit[&"classId"]):
		portrait = Sprite2D.new()
		portrait.texture = load(ProfessionVisual.portrait_path(unit[&"classId"]))
		portrait.centered = true
		# 缩放到 UNIT_VISUAL_PX 高度（按纹理高度比例）
		var tex_h := (portrait.texture as Texture2D).get_height()
		if tex_h > 0:
			portrait.scale = Vector2.ONE * (UNIT_VISUAL_PX / tex_h)
		# 立绘底部贴 cell 中心：centered 时纹理中心在原点，抬升半个高度
		portrait.position = Vector2(0, -UNIT_VISUAL_PX * 0.5)
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(portrait)
	# 2) HP 条背景（深色底条，全长）
	_hp_bg = ColorRect.new()
	_hp_bg.color = Color(0.07, 0.07, 0.07, 0.85)
	_hp_bg.size = Vector2(_HP_BAR_W, _HP_BAR_H)
	_hp_bg.position = Vector2(-_HP_BAR_W * 0.5, _HP_BAR_Y - _HP_BAR_H * 0.5)
	add_child(_hp_bg)
	# 3) HP 条前景（按比例收缩，update_state 里设宽度和颜色）
	_hp_bar = ColorRect.new()
	_hp_bar.color = Color(0.290, 0.867, 0.502)
	_hp_bar.size = Vector2(_HP_BAR_W, _HP_BAR_H)
	_hp_bar.position = Vector2(-_HP_BAR_W * 0.5, _HP_BAR_Y - _HP_BAR_H * 0.5)
	add_child(_hp_bar)
	# 4) 头顶文本：阵营 + 职位名 + 等级
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.add_theme_color_override("font_color", FACTION_COLOR.get(unit[&"faction"], Color.WHITE))
	_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_name_label.add_theme_constant_override("outline_size", 3)
	_name_label.position = Vector2(-60, _LABEL_Y - 8)
	_name_label.size = Vector2(120, 16)
	add_child(_name_label)
	update_state()


## 血量比例 → HP 条颜色
func _hp_bar_color(ratio: float) -> Color:
	if ratio <= 0.25:
		return Color(0.973, 0.302, 0.302)
	if ratio <= 0.5:
		return Color(0.984, 0.749, 0.141)
	return Color(0.290, 0.867, 0.502)


## 头顶文本
func _build_name_label(u: Dictionary) -> String:
	var faction_key: StringName = u[&"faction"]
	var faction_text: String = FACTION_NAME.get(faction_key, "")
	var prof_name: String = ProfessionData.profession_name(u[&"classId"])
	var lv: int = int(u.get(&"level", 1))
	return "%s · %s Lv.%d" % [faction_text, prof_name, lv]


## 按 unit 当前状态刷新（位置、HP 条宽度、已行动半透、死亡隐藏）。
func update_state() -> void:
	if is_world_mode():
		# B1 就地模式：双轨定位
		_apply_render_proxy()
	elif _board != null:
		# B2 切场景模式：直接设 global_position（注入 level_fn 时含柱顶高度）
		var pos_b2: Vector2i = unit[&"position"]
		global_position = _b2_cell_screen(pos_b2)
	else:
		return
	# HP 条
	var stats: Dictionary = unit[&"stats"]
	var ratio: float = clampf(float(unit[&"hp"]) / float(max(1, stats[&"hp"])), 0.0, 1.0)
	var fill_w := _HP_BAR_W * ratio
	_hp_bar.color = _hp_bar_color(ratio)
	_hp_bar.size = Vector2(fill_w, _HP_BAR_H)
	# 左对齐：从左锚 (_HP_BAR_W*0.5) 开始向右画 fill_w
	_hp_bar.position = Vector2(-_HP_BAR_W * 0.5, _HP_BAR_Y - _HP_BAR_H * 0.5)
	_hp_bar.modulate.a = 1.0 if ratio < 1.0 else 0.7
	# 头顶文本
	var faction_key: StringName = unit[&"faction"]
	_name_label.add_theme_color_override("font_color", FACTION_COLOR.get(faction_key, Color.WHITE))
	_name_label.text = _build_name_label(unit)
	# 已行动半透
	var alpha := 0.5 if bool(unit[&"hasActed"]) else 1.0
	_set_children_alpha(alpha)
	visible = not bool(unit[&"isDead"])


func _set_children_alpha(a: float) -> void:
	for c in get_children():
		if c is CanvasItem:
			(c as CanvasItem).modulate.a = a


## 公开接口：供 tween_method 调用做死亡淡出。
func fade_alpha(a: float) -> void:
	_set_children_alpha(a)


## 平滑移动到新 cell（沿 A* 路径，逐格 tween）。
func move_along_path(path: Array, on_done: Callable) -> void:
	if path.is_empty():
		on_done.call()
		return
	var tween := create_tween()
	if is_world_mode():
		# B1 就地模式：tween _visual_pos，每步 method 调 _apply_render_proxy 更新双轨
		for cell in path:
			var world_cell: Vector2i = _world_origin + cell
			# 临时把 unit.position 设到该 cell（_apply_render_proxy 读 unit.position）
			unit[&"position"] = cell
			tween.tween_method(_apply_render_proxy, _visual_pos, _world._grid_to_screen(world_cell, float(_world.cell_stand_level(world_cell))), 0.18)
		tween.tween_callback(func():
			update_state()
			on_done.call()
		)
	else:
		# B2 切场景模式：tween global_position（含柱顶高度）
		for cell in path:
			tween.tween_property(self, "global_position", _b2_cell_screen(cell), 0.18)
		tween.tween_callback(func():
			update_state()
			on_done.call()
		)
