extends Camera3D
## isometric_camera_3d.gd — 正交 dimetric 相机；旋转只改变相机，不重建地形。

const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
const MIN_ZOOM := 0.5
const MAX_ZOOM := 4.0
const MIN_ELEVATION := deg_to_rad(20.0)
const MAX_ELEVATION := deg_to_rad(70.0)
const CAMERA_DISTANCE := 64.0

var zoom: float = 2.0:
	set(value):
		zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
		_update_projection_size()
var focus_position := Vector3.ZERO:
	set(value):
		focus_position = value
		_apply_view()
var yaw_radians: float = IsoProjection.CAMERA_YAW
var target_yaw_radians: float = IsoProjection.CAMERA_YAW
var elevation_radians: float = IsoProjection.CAMERA_ELEVATION
var target_elevation_radians: float = IsoProjection.CAMERA_ELEVATION
var rotation_smoothing: float = 14.0
var _viewport_size := Vector2(1280.0, 800.0)


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	near = 0.05
	far = 256.0
	current = true
	_viewport_size = get_viewport().get_visible_rect().size
	var resize_callable := Callable(self, "_on_viewport_size_changed")
	if not get_viewport().size_changed.is_connected(resize_callable):
		get_viewport().size_changed.connect(resize_callable)
	_update_projection_size()
	_apply_view()


func _on_viewport_size_changed() -> void:
	set_viewport_size(get_viewport().get_visible_rect().size)


func set_view_angle(angle_degrees: float, animate: bool = true) -> void:
	target_yaw_radians = wrapf(deg_to_rad(angle_degrees), 0.0, TAU)
	if not animate:
		yaw_radians = target_yaw_radians
		_apply_view()


func snap_to_angle(angle_degrees: float) -> void:
	set_view_angle(angle_degrees, false)


func rotate_step(direction: int, animate: bool = true) -> void:
	var quarter_turn := PI * 0.5
	var snapped := roundf(target_yaw_radians / quarter_turn) * quarter_turn
	var iso_aligned := IsoProjection.CAMERA_YAW + roundf(
		(target_yaw_radians - IsoProjection.CAMERA_YAW) / quarter_turn) * quarter_turn
	if absf(angle_difference(target_yaw_radians, iso_aligned)) < 0.000001:
		snapped = target_yaw_radians
	set_view_angle(rad_to_deg(snapped + float(signi(direction)) * quarter_turn), animate)


func drag_by(relative: Vector2, animate: bool = false) -> void:
	target_yaw_radians = wrapf(target_yaw_radians - relative.x * 0.008, 0.0, TAU)
	target_elevation_radians = clampf(
		target_elevation_radians + relative.y * 0.004,
		MIN_ELEVATION,
		MAX_ELEVATION
	)
	if not animate:
		yaw_radians = target_yaw_radians
		elevation_radians = target_elevation_radians
		_apply_view()


func reset_rotation(animate: bool = true) -> void:
	target_yaw_radians = IsoProjection.CAMERA_YAW
	target_elevation_radians = IsoProjection.CAMERA_ELEVATION
	if not animate:
		yaw_radians = target_yaw_radians
		elevation_radians = target_elevation_radians
		_apply_view()


func advance(delta: float) -> bool:
	var blend := 1.0 - exp(-rotation_smoothing * maxf(delta, 0.0))
	var next_yaw := lerp_angle(yaw_radians, target_yaw_radians, blend)
	var next_elevation := lerpf(elevation_radians, target_elevation_radians, blend)
	var changed := (
		absf(angle_difference(yaw_radians, next_yaw)) > 0.000001
		or absf(next_elevation - elevation_radians) > 0.000001
	)
	yaw_radians = wrapf(next_yaw, 0.0, TAU)
	elevation_radians = next_elevation
	if changed:
		_apply_view()
	return changed


func set_viewport_size(value: Vector2) -> void:
	_viewport_size = value
	_update_projection_size()


func world_to_screen(point: Vector3) -> Vector2:
	return unproject_position(point)


func screen_to_world(screen_position: Vector2, level: float = 0.0) -> Variant:
	return IsoProjection.screen_to_world(self, screen_position, level)


func screen_to_grid(screen_position: Vector2, level: float = 0.0) -> Variant:
	return IsoProjection.screen_to_grid(self, screen_position, level)


func _update_projection_size() -> void:
	size = _viewport_size.y / (IsoProjection.TILE_PIXELS * zoom)


func _apply_view() -> void:
	if not is_inside_tree():
		return
	var horizontal := cos(elevation_radians)
	var offset := Vector3(
		sin(yaw_radians) * horizontal,
		sin(elevation_radians),
		cos(yaw_radians) * horizontal
	) * CAMERA_DISTANCE
	position = focus_position + offset
	if position.distance_squared_to(focus_position) > 0.000001:
		look_at(focus_position, Vector3.UP)
