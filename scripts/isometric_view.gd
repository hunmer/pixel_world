extends RefCounted
## isometric_view.gd — 可旋转等距投影、反投影与离散视角控制器。

## 现有素材逐角度验收仅通过四个正交视角；其余角度会出现地形拼缝。
const SUPPORTED_ANGLES: Array[float] = [0.0, 90.0, 180.0, 270.0]

var _tile_w := 32.0
var _tile_h := 16.0
var _level_h := 10.0

var _view_angle := 0.0
var _target_angle := 0.0
var _basis_x := Vector2.ZERO
var _basis_y := Vector2.ZERO
var _drag_accumulator := 0.0

## 拖拽每累积 180px 切换一个 90° 档位，不产生中间视角。
var _drag_sensitivity := 0.5


func _init(tile_width := 32.0, tile_height := 16.0, level_height := 10.0) -> void:
	_tile_w = tile_width
	_tile_h = tile_height
	_level_h = level_height
	_update_basis()


func set_view_angle(degrees: float) -> void:
	_view_angle = deg_to_rad(degrees)
	_target_angle = _view_angle
	_drag_accumulator = 0.0
	_update_basis()


func snap_to_angle(degrees: float) -> void:
	var index := _nearest_supported_index(deg_to_rad(degrees))
	set_view_angle(SUPPORTED_ANGLES[index])


func rotate_step(direction: int) -> void:
	if direction == 0:
		return
	var current := _nearest_supported_index(_target_angle)
	var count := SUPPORTED_ANGLES.size()
	var step := 1 if direction > 0 else -1
	var next := posmod(current + step, count)
	_target_angle = deg_to_rad(SUPPORTED_ANGLES[next])


func drag_by(pixel_delta_x: float) -> void:
	if _drag_sensitivity <= 0.0:
		return
	_drag_accumulator += pixel_delta_x
	var pixels_per_step := 90.0 / _drag_sensitivity
	while absf(_drag_accumulator) >= pixels_per_step:
		var direction := 1 if _drag_accumulator > 0.0 else -1
		rotate_step(direction)
		_drag_accumulator -= pixels_per_step * direction


func reset_rotation() -> void:
	_target_angle = 0.0
	_drag_accumulator = 0.0


func _nearest_supported_index(angle: float) -> int:
	var degrees := rad_to_deg(angle)
	var best := 0
	var best_distance := INF
	for index in SUPPORTED_ANGLES.size():
		var distance := absf(wrapf(degrees - SUPPORTED_ANGLES[index], -180.0, 180.0))
		if distance < best_distance:
			best = index
			best_distance = distance
	return best


## 保留旧参数以兼容调用方；连续旋转输入不再改变角度，目标角在下一帧立即生效。
## 返回本帧投影是否变化，调用方据此刷新地图渲染代理。
func advance(_delta: float, _continuous_direction := 0) -> bool:
	if is_equal_approx(_view_angle, _target_angle):
		return false
	_view_angle = _target_angle
	_update_basis()
	return true


func _update_basis() -> void:
	var ox := Vector2(_tile_w * 0.5, _tile_h * 0.5)
	var oy := Vector2(-_tile_w * 0.5, _tile_h * 0.5)
	var c := cos(_view_angle)
	var s := sin(_view_angle)
	_basis_x = Vector2(ox.x * c - ox.y * s, ox.x * s + ox.y * c)
	_basis_y = Vector2(oy.x * c - oy.y * s, oy.x * s + oy.y * c)


func grid_to_screen(cell: Vector2i, level := 0.0) -> Vector2:
	return cell.x * _basis_x + cell.y * _basis_y - Vector2(0.0, level * _level_h)


func screen_to_grid(screen_pos: Vector2, level := 0.0) -> Vector2:
	var adjusted := screen_pos + Vector2(0.0, level * _level_h)
	var det := _basis_x.x * _basis_y.y - _basis_x.y * _basis_y.x
	if absf(det) < 0.0001:
		return Vector2.ZERO
	var x := (adjusted.x * _basis_y.y - adjusted.y * _basis_y.x) / det
	var y := (_basis_x.x * adjusted.y - _basis_x.y * adjusted.x) / det
	return Vector2(x, y)


func get_depth_key(cell: Vector2i, level := 0.0) -> float:
	return grid_to_screen(cell, level).y


func get_view_degrees() -> float:
	return rad_to_deg(_view_angle)


func get_target_degrees() -> float:
	return rad_to_deg(_target_angle)
