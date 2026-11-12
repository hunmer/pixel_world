## world_camera_navigation.gd — 主世界抓取平移与持久化网格偏移。
extends RefCounted

const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")

var offset: Vector2 = Vector2.ZERO
var _panning: bool = false
var _space_held: bool = false
var _last_position: Vector2 = Vector2.ZERO


func reset() -> void:
	offset = Vector2.ZERO
	cancel_drag()


func cancel_drag() -> void:
	_panning = false
	_space_held = false


func handle_input(event: InputEvent, camera: Camera3D) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_SPACE or key.keycode == KEY_SPACE:
			_space_held = key.pressed
			if not key.pressed:
				_panning = false
			return true
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return false
		if not button.pressed:
			var was_panning: bool = _panning
			_panning = false
			return was_panning
		if _space_held or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_SPACE):
			_panning = true
			_last_position = button.position
			return true
	if event is InputEventMouseMotion and _panning:
		var motion := event as InputEventMouseMotion
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_panning = false
			return false
		var level: float = camera.focus_position.y / IsoProjection.LEVEL_HEIGHT
		var from: Variant = IsoProjection.screen_to_world(camera, _last_position, level)
		var to: Variant = IsoProjection.screen_to_world(camera, motion.position, level)
		_last_position = motion.position
		if from != null and to != null:
			var displacement: Vector3 = (from as Vector3) - (to as Vector3)
			offset += IsoProjection.world_to_grid_position(displacement)
			camera.focus_position += displacement
		return true
	return false
