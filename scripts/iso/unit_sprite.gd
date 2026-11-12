## iso/unit_sprite.gd — 真实 3D 等距单位立绘、HP 条与头顶文本
##
## 保留 UnitSprite3D 类名及 setup/update_state/move_along_path/fade_alpha API。
## 立绘、HP 与 Label3D 均进入深度缓冲，B1/B2 共用 Camera3D 投影。
class_name UnitSprite3D
extends Node3D

const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
const UNIT_VISUAL_PX := 32.0
const SCREEN_HORIZONTAL_EPSILON := 0.001
# 职业立绘与鱼类旧素材一致，原图朝左；转向只看相机投影后的屏幕水平位移。
const SOURCE_FACES_RIGHT := false

var unit: Dictionary
var portrait: Sprite3D
var _board: IsoBoard
var _hp_bg: Sprite3D
var _hp_bar: Sprite3D
var _name_label: Label3D
var _world: Node2D = null
var _stand_level: int = 0
var _world_origin: Vector2i = Vector2i.ZERO
var _visual_pos: Vector3 = Vector3.ZERO
var _level_fn: Callable = Callable()

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
const _HP_BAR_W := 40.0
const _HP_BAR_H := 4.0
const _HP_BAR_Y := 56.0
const _LABEL_Y := 66.0

static var _white_texture: ImageTexture = null

func is_world_mode() -> bool:
	return _world != null

func setup(p_unit: Dictionary, board: IsoBoard, p_level_fn := Callable()) -> void:
	unit = p_unit
	_board = board
	_level_fn = p_level_fn
	_build_visual()

func setup_world(p_unit: Dictionary, p_world: Node2D, p_stand_level: int, p_world_origin: Vector2i) -> void:
	unit = p_unit
	_world = p_world
	_stand_level = p_stand_level
	_world_origin = p_world_origin
	_build_visual()

func _b2_cell_world(pos: Vector2i) -> Vector3:
	var lvl := 0
	if _level_fn.is_valid():
		lvl = int(_level_fn.call(pos.x, pos.y))
	return IsoProjection.grid_to_world(pos, float(lvl))

func _world_cell_world(pos: Vector2i) -> Vector3:
	var world_cell := _world_origin + pos
	_stand_level = _world.cell_stand_level(world_cell)
	return IsoProjection.grid_to_world(world_cell, float(_stand_level))

func _apply_render_proxy() -> void:
	global_position = _world_cell_world(unit[&"position"])
	_visual_pos = global_position

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

func _configure_billboard(sprite: Sprite3D) -> void:
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false

func _build_visual() -> void:
	if ProfessionVisual.portrait_exists(unit[&"classId"]):
		portrait = Sprite3D.new()
		portrait.texture = load(ProfessionVisual.portrait_path(unit[&"classId"]))
		var tex_h := (portrait.texture as Texture2D).get_height()
		if tex_h > 0:
			portrait.pixel_size = 1.0 / float(tex_h)
			# offset 不改变深度位置；抬高节点本身，避免立绘陷入地形柱。
			portrait.position = Vector3(0.0, 0.5, 0.0)
		_configure_billboard(portrait)
		add_child(portrait)
	if _white_texture == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_white_texture = ImageTexture.create_from_image(image)
	_hp_bg = Sprite3D.new()
	_hp_bg.texture = _white_texture
	_hp_bg.pixel_size = 1.0 / 32.0
	_hp_bg.scale = Vector3(_HP_BAR_W, _HP_BAR_H, 1.0)
	_hp_bg.position = Vector3(0.0, _HP_BAR_Y / 32.0, 0.0)
	_hp_bg.modulate = Color(0.07, 0.07, 0.07, 0.85)
	_configure_billboard(_hp_bg)
	add_child(_hp_bg)
	_hp_bar = Sprite3D.new()
	_hp_bar.texture = _white_texture
	_hp_bar.pixel_size = 1.0 / 32.0
	_hp_bar.scale = Vector3(_HP_BAR_W, _HP_BAR_H, 1.0)
	_hp_bar.position = Vector3(0.0, _HP_BAR_Y / 32.0, 0.0)
	_configure_billboard(_hp_bar)
	add_child(_hp_bar)
	_name_label = Label3D.new()
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = false
	_name_label.pixel_size = 1.0 / 32.0
	_name_label.font_size = 12
	_name_label.outline_size = 3
	_name_label.outline_modulate = Color.BLACK
	_name_label.position = Vector3(0.0, _LABEL_Y / 32.0, 0.0)
	add_child(_name_label)
	update_state()

func _hp_bar_color(ratio: float) -> Color:
	if ratio <= 0.25:
		return Color(0.973, 0.302, 0.302)
	if ratio <= 0.5:
		return Color(0.984, 0.749, 0.141)
	return Color(0.290, 0.867, 0.502)

func _build_name_label(u: Dictionary) -> String:
	var faction_key: StringName = u[&"faction"]
	var faction_text: String = FACTION_NAME.get(faction_key, "")
	var prof_name: String = ProfessionData.profession_name(u[&"classId"])
	var lv: int = int(u.get(&"level", 1))
	return "%s · %s Lv.%d" % [faction_text, prof_name, lv]

func _process(_delta: float) -> void:
	_update_hp_depth()


func _active_camera() -> Camera3D:
	if is_world_mode() and is_instance_valid(_world):
		return _world._cam as Camera3D
	if _board != null:
		return _board.camera
	return null


func _update_hp_depth() -> void:
	if _hp_bg == null or _hp_bar == null:
		return
	var camera := _active_camera()
	var toward_camera := Vector3.FORWARD * 0.002
	if camera != null:
		toward_camera = (camera.global_position - global_position).normalized() * 0.002
	_hp_bg.position = Vector3(0.0, _HP_BAR_Y / 32.0, 0.0)
	_hp_bar.position = _hp_bg.position + toward_camera


func update_state() -> void:
	if is_world_mode():
		_apply_render_proxy()
	elif _board != null:
		global_position = _b2_cell_world(unit[&"position"])
	else:
		return
	var stats: Dictionary = unit[&"stats"]
	var ratio: float = clampf(float(unit[&"hp"]) / float(max(1, stats[&"hp"])), 0.0, 1.0)
	var fill_w := _HP_BAR_W * ratio
	_hp_bar.modulate = _hp_bar_color(ratio)
	_hp_bar.visible = fill_w > 0.0
	_hp_bar.scale.x = fill_w
	# Sprite3D.offset 也受 scale.x 影响，除回去才能保持左边缘固定。
	_hp_bar.offset = Vector2(-(40.0 - fill_w) * 0.5 / maxf(fill_w, 0.0001), 0.0)
	_hp_bg.modulate.a = 1.0 if ratio < 1.0 else 0.7
	var faction_key: StringName = unit[&"faction"]
	_name_label.modulate = FACTION_COLOR.get(faction_key, Color.WHITE)
	_name_label.text = _build_name_label(unit)
	# ALPHA_CUT_DISCARD 会裁掉半透明像素；存活单位始终不透明，仅用RGB区分已行动。
	_set_children_alpha(1.0)
	portrait.modulate = Color(0.58, 0.58, 0.58, 1.0) if bool(unit[&"hasActed"]) else Color.WHITE
	visible = not bool(unit[&"isDead"])

func _set_children_alpha(a: float) -> void:
	for c in get_children():
		if c is Sprite3D or c is Label3D:
			c.modulate.a = a

func fade_alpha(a: float) -> void:
	_set_children_alpha(a)

## 与鱼类移动一致：按相机投影后的屏幕水平位移转向，近零位移保留原朝向。
func face_movement(target: Vector3) -> void:
	var camera := _active_camera()
	if camera == null:
		return
	var screen_delta := IsoProjection.world_to_screen(camera, target).x - IsoProjection.world_to_screen(camera, global_position).x
	if absf(screen_delta) <= SCREEN_HORIZONTAL_EPSILON:
		return
	portrait.flip_h = (screen_delta > 0.0) != SOURCE_FACES_RIGHT


func move_along_path(path: Array, on_done: Callable) -> void:
	if path.is_empty():
		on_done.call()
		return
	var tween := create_tween()
	for cell in path:
		var target := _world_cell_world(cell) if is_world_mode() else _b2_cell_world(cell)
		tween.tween_callback(func(): face_movement(target))
		tween.tween_property(self, "global_position", target, 0.18)
		if is_world_mode():
			tween.tween_callback(func(): unit[&"position"] = cell)
	tween.tween_callback(func():
		update_state()
		on_done.call()
	)
