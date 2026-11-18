## free_character_animator.gd — 网格移动 run/idle 与单次编号预览的独立时间状态
class_name FreeCharacterAnimator
extends RefCounted

signal preview_finished

const Sheet = preload("res://scripts/characters/free_character_sheet.gd")

var character_id: StringName = &"002"
var mode: StringName = &"idle"
var direction: StringName = &"down"
var preview_id: StringName = &""
var frame_index: int = 0

var _preview_elapsed: float = 0.0
var _run_elapsed: float = 0.0


func _init(initial_character: StringName = &"002") -> void:
	character_id = initial_character


func set_character(next_character: StringName) -> bool:
	if not Sheet.sheet_exists(next_character):
		return false
	character_id = next_character
	mode = &"idle"
	preview_id = &""
	frame_index = 0
	_preview_elapsed = 0.0
	_run_elapsed = 0.0
	return true


func is_preview_active() -> bool:
	return mode == &"preview"


func set_locomotion(moving: bool, screen_delta: Vector2) -> void:
	if is_preview_active():
		return
	if screen_delta.length_squared() > 0.000001:
		var resolved := Sheet.resolve_direction(screen_delta)
		var next_direction := StringName(resolved.get(&"direction", &"down"))
		if next_direction != direction:
			direction = next_direction
			_run_elapsed = 0.0
			frame_index = 0
	mode = &"run" if moving else &"idle"
	if mode == &"idle":
		frame_index = 0
	else:
		frame_index = _run_frame(_run_elapsed)


## 单次动作播放期间拒绝重入；编号仅对应原始图集行，不附加战斗语义。
func start_preview(next_preview: StringName) -> bool:
	if is_preview_active() or not Sheet.preview_ids().has(next_preview):
		return false
	var spec := Sheet.animation_spec(next_preview)
	if spec.is_empty() or bool(spec.get("loop", true)):
		return false
	mode = &"preview"
	preview_id = next_preview
	frame_index = 0
	_preview_elapsed = 0.0
	return true


func cancel_preview() -> bool:
	if not is_preview_active():
		return false
	mode = &"idle"
	preview_id = &""
	frame_index = 0
	_preview_elapsed = 0.0
	return true


## 返回可见状态是否变化。run 相位跨单格停顿时保留，持续按方向不会反复从 0 帧重启。
func advance(delta: float) -> bool:
	if delta <= 0.0:
		return false
	var previous_mode := mode
	var previous_frame := frame_index
	if mode == &"run":
		_run_elapsed += delta
		frame_index = _run_frame(_run_elapsed)
	elif mode == &"preview":
		_preview_elapsed += delta
		var spec := Sheet.animation_spec(preview_id)
		var frames: Array = spec.get("valid_frames", [])
		var fps := float(spec.get("fps", 8.0))
		var next_frame := int(floor(_preview_elapsed * fps))
		if next_frame >= frames.size():
			cancel_preview()
			preview_finished.emit()
		else:
			frame_index = next_frame
	return previous_mode != mode or previous_frame != frame_index


func current_row() -> int:
	if is_preview_active():
		return int(Sheet.animation_spec(preview_id).get("row", Sheet.RUN_DOWN_ROW))
	var resolved := Sheet.direction_spec(direction)
	return int(resolved.get("row", Sheet.RUN_DOWN_ROW))


func current_texture() -> AtlasTexture:
	return Sheet.frame_texture(character_id, current_row(), frame_index)


func current_flip_h() -> bool:
	return not is_preview_active() and direction == &"right"


func _run_frame(elapsed: float) -> int:
	var spec := Sheet.row_spec(current_row())
	var frames: Array = spec.get("valid_frames", [0, 1, 2, 3, 4, 5])
	if frames.is_empty():
		return 0
	var fps := float(spec.get("fps", 8.0))
	return posmod(int(floor(elapsed * fps)), frames.size())
