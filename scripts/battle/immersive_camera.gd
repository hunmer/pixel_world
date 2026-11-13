## battle/immersive_camera.gd — B1/B2 共用的可等待式沉浸式交战镜头。
##
## 接管现有 IsometricCamera3D，不创建替代场景、不改单位格位或战斗结算。
## presentation_offset 平移有效焦点，避开 main/IsoBoard 每帧取景；yaw 仍只取四个正交方向。
class_name ImmersiveBattleCamera
extends Node

signal state_changed

const ENTER_SECONDS := 0.45
const RESTORE_SECONDS := 0.36
const IMMERSIVE_ELEVATION := deg_to_rad(10.0)
const CHARACTER_CENTER_Y := 0.45
const CHARACTER_HEIGHT := 0.90

# 数值与 State 名称供运行态断言使用，不依赖全局 class cache。
enum State { INACTIVE, ENTERING, ACTIVE, RESTORING }

var enabled := true
var _camera: Camera3D = null
var _state: State = State.INACTIVE
var _snapshot: Dictionary = {}
var _from: Dictionary = {}
var _to: Dictionary = {}
var _current: Dictionary = {}
var _transition: Tween = null
var _animation_speed := 1.0
var _skip_requested := false


func setup(camera: Camera3D) -> void:
	_camera = camera
	# main.gd / IsoBoard 先完成常规 advance，再由本模块刷新有效焦点。
	process_priority = 100


func is_engaged() -> bool:
	return _state != State.INACTIVE


func get_state() -> int:
	return _state


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	# ACTIVE 时 ActionAnim 仍持有 size 快照；等当前完整动作在 end() 收尾再恢复，
	# 避免它的 return/_restore_camera_immediate 在恢复 tween 之后写回中间值。
	if not enabled and _state == State.ENTERING:
		_start_restore()


## 在 ActionAnim.play 前 await。预先 skip 的托管事件不做无意义的双向转场。
func begin(
	event: Dictionary,
	unit_sprites: Dictionary,
	animation_speed: float = 1.0,
	skipped: bool = false
) -> void:
	if not enabled or skipped or not is_instance_valid(_camera):
		return
	if _state != State.INACTIVE:
		cancel()
	var points := _participation_points(event, unit_sprites)
	if points.is_empty():
		return
	_animation_speed = clampf(animation_speed, 0.25, 4.0)
	_skip_requested = false
	_snapshot = _capture_camera()
	_from = _snapshot.duplicate(true)
	_to = _make_shot(points, event, unit_sprites, _snapshot)
	_current = _snapshot.duplicate(true)
	_kill_transition()
	_state = State.ENTERING
	_transition = create_tween()
	_transition.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition.tween_method(
		_apply_enter_progress,
		0.0,
		1.0,
		ENTER_SECONDS / _animation_speed
	)
	_transition.tween_callback(_finish_enter)
	print("[ImmersiveCamera] Begin participants=%d size=%.3f elevation=%.1f" % [
		points.size(),
		float(_to["size"]),
		rad_to_deg(float(_to["elevation"])),
	])
	while _state == State.ENTERING and is_inside_tree():
		await state_changed
	# 进入期关闭时，先让战术相机恢复完成再启动普通 ActionAnim；否则两套 size
	# tween 会竞争。主动 skip 是例外：skipped ActionAnim 不触碰相机，可与恢复并行。
	if _state == State.RESTORING and not _skip_requested:
		while _state == State.RESTORING and is_inside_tree():
			await state_changed


## 在同一个 attack_event 的反击/追击/全部 impacts 完成后 await，恢复演出前快照。
func end() -> void:
	if _state == State.INACTIVE:
		return
	if _state != State.RESTORING:
		_start_restore()
	while _state == State.RESTORING and is_inside_tree():
		await state_changed


## 进入转场期间 ActionAnim 尚未 play，Battle 的跳过输入先写到这里。
func request_skip() -> void:
	if not is_engaged():
		return
	_skip_requested = true
	if _state == State.ENTERING:
		_start_restore()


## Battle 在随后调用 ActionAnim.play 时消费一次，保证进入期按跳过也不会再播放完整动作。
func consume_skip_request() -> bool:
	var requested := _skip_requested
	_skip_requested = false
	return requested


## 退出/场景中断：立即恢复，不能留下一个仍在等待 tween 的战斗协程。
func cancel() -> void:
	if _state == State.INACTIVE and _snapshot.is_empty():
		return
	_kill_transition()
	_finish_restore()


func _exit_tree() -> void:
	cancel()


func _process(_delta: float) -> void:
	if not is_engaged() or not is_instance_valid(_camera) or _current.is_empty():
		return
	# B1 主循环可重写 focus_position；只重算附加位移，不覆盖 ActionAnim 的 size 推近。
	var logical_focus: Vector3 = _camera.get("focus_position")
	var effective_focus: Vector3 = _current["focus"]
	_camera.set("presentation_offset", effective_focus - logical_focus)


func _participation_points(event: Dictionary, unit_sprites: Dictionary) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var ids: Dictionary = {}
	ids[StringName(event.get(&"attacker_id", &""))] = true
	ids[StringName(event.get(&"primary_target_id", &""))] = true
	for raw_impact in event.get(&"impacts", []):
		var impact: Dictionary = raw_impact
		ids[StringName(impact.get(&"source_id", &""))] = true
		ids[StringName(impact.get(&"target_id", &""))] = true
	for unit_id in ids:
		if unit_id == &"":
			continue
		var sprite: Node3D = unit_sprites.get(unit_id)
		if not is_instance_valid(sprite) or not sprite.is_inside_tree():
			continue
		points.append(sprite.global_position + Vector3(0.0, CHARACTER_CENTER_Y, 0.0))
	return points


func _capture_camera() -> Dictionary:
	var logical_focus: Vector3 = _camera.get("focus_position")
	var presentation: Vector3 = _camera.get("presentation_offset")
	return {
		"focus": logical_focus + presentation,
		"yaw": float(_camera.get("yaw_radians")),
		"target_yaw": float(_camera.get("target_yaw_radians")),
		"elevation": float(_camera.get("elevation_radians")),
		"target_elevation": float(_camera.get("target_elevation_radians")),
		"distance": float(_camera.get("presentation_distance")),
		"presentation": presentation,
		"size": _camera.size,
		"projection": _camera.projection,
		"near": _camera.near,
		"far": _camera.far,
		"transform": _camera.global_transform,
	}


func _make_shot(
	points: Array[Vector3],
	event: Dictionary,
	unit_sprites: Dictionary,
	base: Dictionary
) -> Dictionary:
	var bounds_min := points[0]
	var bounds_max := points[0]
	for point in points:
		bounds_min = bounds_min.min(point)
		bounds_max = bounds_max.max(point)
	var focus := (bounds_min + bounds_max) * 0.5
	var attacker: Node3D = unit_sprites.get(StringName(event.get(&"attacker_id", &"")))
	var target: Node3D = unit_sprites.get(StringName(event.get(&"primary_target_id", &"")))
	var direction := Vector3.ZERO
	if is_instance_valid(attacker) and is_instance_valid(target):
		direction = target.global_position - attacker.global_position
		direction.y = 0.0
	var yaw := _choose_quarter_yaw(float(base["yaw"]), direction)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var horizontal_min := INF
	var horizontal_max := -INF
	for point in points:
		var projected := point.dot(right)
		horizontal_min = minf(horizontal_min, projected)
		horizontal_max = maxf(horizontal_max, projected)
	var horizontal_span := horizontal_max - horizontal_min
	var vertical_span := bounds_max.y - bounds_min.y + CHARACTER_HEIGHT
	var viewport_size := _camera.get_viewport().get_visible_rect().size
	var reserved := float(_camera.get("reserved_left_px")) + float(_camera.get("reserved_right_px"))
	var stage_aspect := maxf(0.75, (viewport_size.x - reserved) / maxf(1.0, viewport_size.y))
	var shot_size := clampf(maxf(3.4, maxf(
		vertical_span + 1.0,
		horizontal_span / stage_aspect + 1.0
	)), 3.4, 12.0)
	return {
		"focus": focus,
		"yaw": yaw,
		"elevation": IMMERSIVE_ELEVATION,
		"distance": clampf(4.8 + horizontal_span * 0.35, 4.8, 7.5),
		"size": shot_size,
	}


## 只在素材支持的四个正交 yaw 中选双方横向分离最大的方向；近似同分时少旋转。
func _choose_quarter_yaw(base_yaw: float, direction: Vector3) -> float:
	if direction.length_squared() < 0.000001:
		return base_yaw
	var normalized := direction.normalized()
	var best_yaw := base_yaw
	var best_score := -INF
	for quarter in [0, 1, -1, 2]:
		var candidate := base_yaw + float(quarter) * PI * 0.5
		var right := Vector3(cos(candidate), 0.0, -sin(candidate))
		var score := absf(right.dot(normalized)) - absf(float(quarter)) * 0.03
		if score > best_score:
			best_score = score
			best_yaw = candidate
	return best_yaw


func _apply_enter_progress(progress: float) -> void:
	_interpolate_state(_from, _to, progress)
	_write_current(true)


func _apply_restore_progress(progress: float) -> void:
	_interpolate_state(_from, _snapshot, progress)
	_write_current(true)


func _interpolate_state(from: Dictionary, to: Dictionary, progress: float) -> void:
	var from_focus: Vector3 = from["focus"]
	var to_focus: Vector3 = to["focus"]
	_current = {
		"focus": from_focus.lerp(to_focus, progress),
		"yaw": lerp_angle(float(from["yaw"]), float(to["yaw"]), progress),
		"elevation": lerpf(float(from["elevation"]), float(to["elevation"]), progress),
		"distance": lerpf(float(from["distance"]), float(to["distance"]), progress),
		"size": lerpf(float(from["size"]), float(to["size"]), progress),
	}


func _write_current(write_size: bool) -> void:
	if not is_instance_valid(_camera):
		return
	_camera.set("yaw_radians", float(_current["yaw"]))
	_camera.set("target_yaw_radians", float(_current["yaw"]))
	_camera.set("elevation_radians", float(_current["elevation"]))
	_camera.set("target_elevation_radians", float(_current["elevation"]))
	_camera.set("presentation_distance", float(_current["distance"]))
	if write_size:
		_camera.size = float(_current["size"])
	var logical_focus: Vector3 = _camera.get("focus_position")
	var effective_focus: Vector3 = _current["focus"]
	_camera.set("presentation_offset", effective_focus - logical_focus)


func _finish_enter() -> void:
	_transition = null
	if _state != State.ENTERING:
		return
	_state = State.ACTIVE
	print("[ImmersiveCamera] Engaged")
	state_changed.emit()


func _start_restore() -> void:
	if _state == State.INACTIVE or _state == State.RESTORING or _snapshot.is_empty():
		return
	_from = _current.duplicate(true)
	# 若用户在 ActionAnim 推近途中关闭，恢复从实际 size 开始，不跳回推近前。
	_from["size"] = _camera.size
	_kill_transition()
	_state = State.RESTORING
	# 释放可能正在 await begin 的协程；关闭设置后原演出可按普通战术视角继续。
	state_changed.emit()
	_transition = create_tween()
	_transition.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition.tween_method(
		_apply_restore_progress,
		0.0,
		1.0,
		RESTORE_SECONDS / _animation_speed
	)
	_transition.tween_callback(_finish_restore)
	print("[ImmersiveCamera] Restore")


func _finish_restore() -> void:
	if is_instance_valid(_camera) and not _snapshot.is_empty():
		_camera.set("yaw_radians", float(_snapshot["yaw"]))
		_camera.set("target_yaw_radians", float(_snapshot["target_yaw"]))
		_camera.set("elevation_radians", float(_snapshot["elevation"]))
		_camera.set("target_elevation_radians", float(_snapshot["target_elevation"]))
		_camera.set("presentation_distance", float(_snapshot["distance"]))
		_camera.size = float(_snapshot["size"])
		_camera.projection = int(_snapshot["projection"])
		_camera.near = float(_snapshot["near"])
		_camera.far = float(_snapshot["far"])
		_camera.set("presentation_offset", _snapshot["presentation"])
		# 快照最后落一次，消除浮点/外部 advance 造成的微小偏差。
		_camera.global_transform = _snapshot["transform"]
	_transition = null
	_state = State.INACTIVE
	_current.clear()
	_snapshot.clear()
	print("[ImmersiveCamera] Restored")
	state_changed.emit()


func _kill_transition() -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null
