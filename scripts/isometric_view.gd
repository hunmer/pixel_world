extends RefCounted
## isometric_view.gd — 可旋转等距投影、反投影与帧率无关的旋转控制器。

var _tile_w := 32.0
var _tile_h := 16.0
var _level_h := 10.0

var _view_angle := 0.0
var _target_angle := 0.0
var _basis_x := Vector2.ZERO
var _basis_y := Vector2.ZERO

## 以下参数可直接调整：连续旋转速度、插值速度、步进角度、拖拽灵敏度。
var _rotation_speed := 180.0
var _smooth_speed := 8.0
var _step_angle := 45.0
var _drag_sensitivity := 0.5


func _init(tile_width := 32.0, tile_height := 16.0, level_height := 10.0) -> void:
	_tile_w = tile_width
	_tile_h = tile_height
	_level_h = level_height
	_update_basis()


func set_view_angle(degrees: float) -> void:
	_view_angle = deg_to_rad(degrees)
	_target_angle = _view_angle
	_update_basis()


func snap_to_angle(degrees: float) -> void:
	set_view_angle(degrees)


func rotate_step(direction: int) -> void:
	_target_angle += deg_to_rad(_step_angle * signi(direction))


func drag_by(pixel_delta_x: float) -> void:
	_target_angle += deg_to_rad(pixel_delta_x * _drag_sensitivity)


func reset_rotation() -> void:
	_target_angle = 0.0


## continuous_direction：-1 逆时针、0 不连续旋转、1 顺时针。
## 返回本帧投影是否变化，调用方据此刷新地图渲染代理。
func advance(delta: float, continuous_direction := 0) -> bool:
	var safe_delta := maxf(delta, 0.0)
	if continuous_direction != 0:
		_target_angle += (
			deg_to_rad(_rotation_speed * signi(continuous_direction)) * safe_delta
		)
	var difference := wrapf(_target_angle - _view_angle, -PI, PI)
	if absf(difference) <= 0.0001:
		if not is_equal_approx(_view_angle, _target_angle):
			_view_angle = _target_angle
			_update_basis()
			return true
		return false
	var blend := 1.0 - exp(-maxf(_smooth_speed, 0.0) * safe_delta)
	_view_angle = lerp_angle(_view_angle, _target_angle, blend)
	if absf(wrapf(_target_angle - _view_angle, -PI, PI)) <= 0.0001:
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
