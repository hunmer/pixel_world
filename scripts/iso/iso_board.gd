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
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0
## 平滑缩放速率（1/s）：指数趋近时间常数 ≈ 1/ZOOM_SMOOTH_RATE 秒。
const ZOOM_SMOOTH_RATE := 8.0
var _target_zoom: float = ZOOM_LEVELS[DEFAULT_ZOOM_INDEX]
## 缩放动画期间锚定的屏幕点（视口坐标）：逐帧保持该点下的世界坐标不动。
var _zoom_anchor: Vector2 = Vector2.INF

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
	camera.zoom = _target_zoom

func _process(delta: float) -> void:
	if camera != null:
		camera.advance(delta)
	if camera == null or is_equal_approx(camera.zoom, _target_zoom):
		_zoom_anchor = Vector2.INF
		return
	# 指数缓动逼近目标倍率，期间锚点（手势/滚轮中心）下的世界坐标保持不动。
	var level: float = camera.focus_position.y / IsoProjection.LEVEL_HEIGHT
	var anchor_world: Variant = null
	if _zoom_anchor.is_finite():
		anchor_world = IsoProjection.screen_to_world(camera, _zoom_anchor, level)
	var t := 1.0 - exp(-ZOOM_SMOOTH_RATE * delta)
	camera.zoom = lerpf(camera.zoom, _target_zoom, t)
	if anchor_world != null:
		var moved: Variant = IsoProjection.screen_to_world(camera, _zoom_anchor, level)
		if moved != null:
			camera.focus_position += (anchor_world as Vector3) - (moved as Vector3)

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
	# factor<1 = 放大（调用方约定：滚轮上/捏合张开传 1/factor<1），与世界 _zoom_step(+1) 同向。
	# 连续倍率 + 指数缓动：捏合小 delta 累积为平滑缩放，滚轮一档约 ±10%。
	_target_zoom = clampf(_target_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_zoom_anchor = anchor_screen

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	var level: float = camera.focus_position.y / IsoProjection.LEVEL_HEIGHT
	return IsoProjection.screen_to_world(camera, screen_pos, level) as Vector3

func _world_to_screen(world_pos: Vector3) -> Vector2:
	return camera.unproject_position(world_pos)

func pick_cell(screen_pos: Vector2, _viewport_size: Vector2) -> Vector2i:
	return IsoProjection.screen_to_grid(camera, screen_pos, 0.0).round()

func cell_to_screen(x: int, y: int, level: float = 0.0) -> Vector2:
	return IsoProjection.world_to_screen(camera, IsoProjection.grid_to_world(Vector2i(x, y), level))
