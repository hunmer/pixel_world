## iso/iso_board.gd — 正交等距棋盘相机与屏幕拾取
##
## 保留 Node2D 外壳以兼容战棋 UI；地形与单位位于真实 3D 世界，Camera3D
## 负责全部旋转、缩放与屏幕投影。
class_name IsoBoard
extends Node2D

const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
const IsometricCamera3DScript = preload("res://scripts/iso/isometric_camera_3d.gd")

var camera: Camera3D

const ZOOM_LEVELS: Array[float] = [0.5, 1.0, 2.0, 3.0, 4.0]
const DEFAULT_ZOOM_INDEX := 2
var _zoom_index: int = DEFAULT_ZOOM_INDEX

func _ready() -> void:
	_setup_camera()

func _setup_camera() -> void:
	if camera != null:
		return
	camera = IsometricCamera3DScript.new()
	camera.name = "IsoCamera3D"
	add_child(camera)
	camera.make_current()
	camera.focus_position = Vector3.ZERO
	camera.reset_rotation(false)
	_apply_zoom()

func _apply_zoom() -> void:
	camera.zoom = ZOOM_LEVELS[_zoom_index]

func _process(delta: float) -> void:
	if camera != null:
		camera.advance(delta)

func center_on_map(width: int, height: int) -> void:
	var cx := int(width / 2.0)
	var cy := int(height / 2.0)
	camera.focus_position = IsoProjection.grid_to_world(Vector2i(cx, cy), 0.0)

func pan(dx_screen: float, dy_screen: float) -> void:
	var level: float = camera.focus_position.y / IsoProjection.LEVEL_HEIGHT
	var from: Vector3 = IsoProjection.screen_to_world(camera, Vector2.ZERO, level) as Vector3
	var to: Vector3 = IsoProjection.screen_to_world(camera, Vector2(dx_screen, dy_screen), level) as Vector3
	camera.focus_position -= to - from

func zoom_by(factor: float, anchor_screen: Vector2, _viewport_size: Vector2) -> void:
	var step := -1 if factor < 1.0 else 1
	var new_idx := clampi(_zoom_index + step, 0, ZOOM_LEVELS.size() - 1)
	if new_idx == _zoom_index:
		return
	var level: float = camera.focus_position.y / IsoProjection.LEVEL_HEIGHT
	var anchor_world: Vector3 = IsoProjection.screen_to_world(camera, anchor_screen, level) as Vector3
	_zoom_index = new_idx
	_apply_zoom()
	var moved_anchor: Vector3 = IsoProjection.screen_to_world(camera, anchor_screen, level) as Vector3
	camera.focus_position += anchor_world - moved_anchor

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	var level: float = camera.focus_position.y / IsoProjection.LEVEL_HEIGHT
	return IsoProjection.screen_to_world(camera, screen_pos, level) as Vector3

func _world_to_screen(world_pos: Vector3) -> Vector2:
	return camera.unproject_position(world_pos)

func pick_cell(screen_pos: Vector2, _viewport_size: Vector2) -> Vector2i:
	return IsoProjection.screen_to_grid(camera, screen_pos, 0.0).round()

func cell_to_screen(x: int, y: int, level: float = 0.0) -> Vector2:
	return IsoProjection.world_to_screen(camera, IsoProjection.grid_to_world(Vector2i(x, y), level))
