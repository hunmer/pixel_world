## iso/iso_board.gd — 等距棋盘 2D 控制器（相机 + 屏幕拾取）
##
## pixel_world 是 Node2D + Camera2D 项目。地形渲染已由 BattlefieldRenderer
## （ColumnBatch 等距方块柱）接管；本类只保留：
##   - Camera2D 管理：pan / zoom 档位 / center_on_map
##   - 屏幕坐标 ↔ 世界坐标 ↔ cell 拾取（level 0 反投影；含高度的拾取走
##     BattlefieldRenderer.pick_cell）
##
## 节点结构：board(Node2D) └ camera(Camera2D)

class_name IsoBoard
extends Node2D

## 暴露给外部（原 API：camera）。类型从 Camera3D 改为 Camera2D。
var camera: Camera2D

## 缩放档位（与 main.gd 一致，像素安全）。
const ZOOM_LEVELS: Array[float] = [0.5, 1.0, 2.0, 3.0, 4.0]
const DEFAULT_ZOOM_INDEX := 2   # 默认 2.0x
var _zoom_index: int = DEFAULT_ZOOM_INDEX


func _ready() -> void:
	_setup_camera()


func _setup_camera() -> void:
	if camera == null:
		camera = Camera2D.new()
		camera.name = "IsoCamera"
		camera.position_smoothing_enabled = false
		camera.rotation_smoothing_enabled = false
		add_child(camera)
		camera.make_current()
		_apply_zoom()


func _apply_zoom() -> void:
	var v := ZOOM_LEVELS[_zoom_index]
	camera.zoom = Vector2(v, v)


# ============================================================
# 相机控制
# ============================================================

## 居中相机到地图中心（cell 坐标）。原 API：center_on_map(width, height)。
func center_on_map(width: int, height: int) -> void:
	var cx := int(width / 2.0)
	var cy := int(height / 2.0)
	camera.position = IsoCoords.to_screen(cx, cy)


## pan：移动相机（屏幕方向像素 → 世界方向平移）。原 API：pan(dx_screen, dy_screen)。
func pan(dx_screen: float, dy_screen: float) -> void:
	var z := camera.zoom.x
	# 拖拽地图：屏幕移动反方向施加到相机（与原 Node3D 版语义一致）
	camera.position -= Vector2(dx_screen, dy_screen) / z


## zoom：调 Camera2D.zoom 档位。原 API：zoom_by(factor, anchor_screen, viewport_size)。
## factor<1 放大（zoom 档位+），>1 缩小（zoom 档位-）；以 anchor 为锚保持该世界点不动。
func zoom_by(factor: float, anchor_screen: Vector2, _viewport_size: Vector2) -> void:
	# 简单实现：按 factor 方向调档位（步进 1）
	var step := -1 if factor < 1.0 else 1
	var new_idx := clampi(_zoom_index + step, 0, ZOOM_LEVELS.size() - 1)
	if new_idx == _zoom_index:
		return
	# 锚点保持：先记录 anchor 对应的世界点，改 zoom 后再平移相机让该点屏幕位置不变
	var anchor_world := _screen_to_world(anchor_screen)
	_zoom_index = new_idx
	_apply_zoom()
	var new_screen := _world_to_screen(anchor_world)
	# 相机位置补偿 = (原屏幕 - 新屏幕) / zoom
	camera.position += (anchor_screen - new_screen) / camera.zoom.x


# ============================================================
# 屏幕坐标 ↔ 世界坐标 ↔ cell
# ============================================================

## 屏幕坐标（viewport） → 世界坐标（Node2D 局部）。
func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var canvas := get_viewport().get_canvas_transform()
	return canvas.affine_inverse() * screen_pos


## 世界坐标 → 屏幕坐标（viewport）。
func _world_to_screen(world_pos: Vector2) -> Vector2:
	var canvas := get_viewport().get_canvas_transform()
	return canvas * world_pos


## 屏幕坐标 → cell（level 0 反投影）。原 API：pick_cell(screen_pos, viewport_size)。
## 注意：不含高度感知；等距方块地形请用 BattlefieldRenderer.pick_cell。
func pick_cell(screen_pos: Vector2, _viewport_size: Vector2) -> Vector2i:
	var world := _screen_to_world(screen_pos)
	return IsoCoords.to_cell(world)


## cell → 屏幕像素（公开，供 battle_ui / battle.gd 飘字定位用）。
func cell_to_screen(x: int, y: int) -> Vector2:
	return IsoCoords.to_screen(x, y)
