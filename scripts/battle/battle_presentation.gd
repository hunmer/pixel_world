## battle/battle_presentation.gd — 开战对峙演出（单位滑入、定格、滑回真实格）
## 只改变 UnitSprite3D 的显示位置/透明度与 B2 相机取景；绝不写 unit.position。
extends Node

signal standoff_started
signal standoff_finished

const ENTER_DURATION := 0.32
const HOLD_DURATION := 0.38
const RETURN_DURATION := 0.30
const SLIDE_DISTANCE := 4.8
const SLIDE_LIFT := 2.4
const STANDOFF_SHIFT := 0.85
const STANDOFF_LIFT := 0.28

## 契约测试可缩短等待；正常战斗始终为 1。
var duration_scale := 1.0
var _playing := false


## B1/B2 都显式传当前 Camera3D；相机只提供屏幕方向，B1 不改变取景。
func play_standoff(
	unit_sprites: Dictionary,
	camera: Camera3D = null,
	animate_camera: bool = true
) -> void:
	if _playing:
		return
	_playing = true
	standoff_started.emit()
	print("[BattlePresentation] standoff start units=%d" % unit_sprites.size())
	var right := Vector3.RIGHT
	var up := Vector3.UP
	if camera != null and camera.is_inside_tree():
		right = camera.global_basis.x.normalized()
		up = camera.global_basis.y.normalized()

	var records: Array[Dictionary] = []
	var focus_sum := Vector3.ZERO
	for sprite_value in unit_sprites.values():
		var sprite := sprite_value as Node3D
		if sprite == null or not is_instance_valid(sprite):
			continue
		var unit_value: Variant = sprite.get("unit")
		var faction: StringName = &"player"
		if unit_value is Dictionary:
			faction = (unit_value as Dictionary).get(&"faction", &"player")
		var side := -1.0 if faction == &"player" or faction == &"ally" else 1.0
		var real_position := sprite.global_position
		var stage_position := real_position + (
			right * side * STANDOFF_SHIFT + up * side * STANDOFF_LIFT
		)
		var start_position := real_position + (
			right * side * SLIDE_DISTANCE + up * side * SLIDE_LIFT
		)
		records.append({
			"sprite": sprite,
			"real_position": real_position,
			"stage_position": stage_position,
		})
		focus_sum += real_position
		sprite.global_position = start_position
		sprite.call("fade_alpha", 0.0)

	if records.is_empty():
		_playing = false
		standoff_finished.emit()
		return

	var camera_state := _capture_camera(camera, animate_camera)
	if not camera_state.is_empty():
		var focus := focus_sum / float(records.size())
		var tween_camera := create_tween().set_parallel(true)
		tween_camera.tween_property(
			camera, "focus_position", focus, _scaled(ENTER_DURATION)
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween_camera.tween_method(
			Callable(self, "_set_camera_elevation").bind(camera),
			float(camera_state["elevation"]),
			float(camera_state["elevation"]) + deg_to_rad(4.0),
			_scaled(ENTER_DURATION)
		)
		# zoom 与原像素倍率保持不变，避免非整数缩放造成像素抖动。

	var enter := create_tween().set_parallel(true)
	for record in records:
		var sprite := record["sprite"] as Node3D
		enter.tween_property(
			sprite, "global_position", record["stage_position"], _scaled(ENTER_DURATION)
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		enter.tween_method(
			Callable(sprite, "fade_alpha"), 0.0, 1.0, _scaled(ENTER_DURATION)
		)
	await enter.finished
	await get_tree().create_timer(_scaled(HOLD_DURATION)).timeout

	var restore := create_tween().set_parallel(true)
	for record in records:
		var sprite := record["sprite"] as Node3D
		if not is_instance_valid(sprite):
			continue
		restore.tween_property(
			sprite, "global_position", record["real_position"], _scaled(RETURN_DURATION)
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not camera_state.is_empty():
		restore.tween_property(
			camera, "focus_position", camera_state["focus"], _scaled(RETURN_DURATION)
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		restore.tween_method(
			Callable(self, "_set_camera_elevation").bind(camera),
			float(camera_state["elevation"]) + deg_to_rad(4.0),
			float(camera_state["elevation"]),
			_scaled(RETURN_DURATION)
		)
	await restore.finished

	# 以权威 unit.position 重新求值，消除浮点残差并恢复 HP/名称/透明度状态。
	for record in records:
		var sprite := record["sprite"] as Node3D
		if is_instance_valid(sprite):
			sprite.call("update_state")
	_playing = false
	print("[BattlePresentation] standoff finish")
	standoff_finished.emit()


func is_playing() -> bool:
	return _playing


func _scaled(duration: float) -> float:
	return maxf(0.001, duration * duration_scale)


func _capture_camera(camera: Camera3D, animate_camera: bool) -> Dictionary:
	if camera == null or not animate_camera or not camera.is_inside_tree():
		return {}
	return {
		"focus": camera.get("focus_position") as Vector3,
		"elevation": float(camera.get("elevation_radians")),
	}


func _set_camera_elevation(value: float, camera: Camera3D) -> void:
	if not is_instance_valid(camera):
		return
	camera.set("elevation_radians", value)
	camera.set("target_elevation_radians", value)
	# 并行 focus/elevation 两条 tween 的最后一帧顺序不保证；角度写入后必须同步变换，
	# 否则属性虽已还原，advance() 又因无角度差而不再刷新，下一次 size/offset 才暴露残差。
	if camera.has_method(&"_apply_view"):
		camera.call(&"_apply_view")
