extends SceneTree
## 可旋转等距投影：数学往返、全部交互与真实地图拾取契约。

const IsometricViewScript = preload("res://scripts/isometric_view.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _close(actual: float, expected: float, tolerance := 0.001) -> bool:
	return absf(actual - expected) <= tolerance


func _initialize() -> void:
	call_deferred("_run")


func _test_controller() -> void:
	var view = IsometricViewScript.new(32.0, 16.0, 10.0)
	_expect(
		view.grid_to_screen(Vector2i(3, 2), 4.0).is_equal_approx(Vector2(16.0, 0.0)),
		"默认等距投影不兼容"
	)
	for angle in [0.0, 37.0, 90.0, 181.0, 275.0, -45.0]:
		view.set_view_angle(angle)
		for cell in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(-7, 12)]:
			var projected: Vector2 = view.grid_to_screen(cell, 3.0)
			var restored: Vector2 = view.screen_to_grid(projected, 3.0)
			_expect(
				restored.distance_to(Vector2(cell)) < 0.001,
				"角度 %.1f 的投影/反投影未闭合: %s -> %s" % [angle, cell, restored]
			)
		_expect(
			_close(view.get_depth_key(Vector2i(2, 3), 1.5), view.grid_to_screen(Vector2i(2, 3), 1.5).y),
			"深度键没有使用旋转后的投影 y"
		)

	view.set_view_angle(0.0)
	view.advance(0.25, 1)
	_expect(_close(view.get_target_degrees(), 45.0), "按住旋转没有按 delta 累积角度")
	_expect(view.get_view_degrees() > 0.0 and view.get_view_degrees() < 45.0, "连续旋转没有平滑插值")
	view.advance(0.25, -1)
	_expect(_close(view.get_target_degrees(), 0.0), "反向连续旋转没有抵消目标角度")

	view.set_view_angle(0.0)
	view.rotate_step(1)
	_expect(_close(view.get_target_degrees(), 45.0), "离散顺时针步进不是 45°")
	view.rotate_step(-1)
	_expect(_close(view.get_target_degrees(), 0.0), "离散逆时针步进不是 45°")
	view.drag_by(90.0)
	_expect(_close(view.get_target_degrees(), 45.0), "鼠标拖拽灵敏度不是 0.5°/px")
	view.reset_rotation()
	_expect(_close(view.get_target_degrees(), 0.0), "一键复位没有归零目标角")
	for i in 120:
		view.advance(1.0 / 60.0)
	_expect(_close(view.get_view_degrees(), 0.0), "复位后没有平滑收敛到默认角")
	view.snap_to_angle(123.0)
	_expect(_close(view.get_view_degrees(), 123.0), "snap_to_angle 没有立即生效")

	var single = IsometricViewScript.new()
	var stepped = IsometricViewScript.new()
	single.rotate_step(1)
	stepped.rotate_step(1)
	single.advance(1.0)
	for i in 60:
		stepped.advance(1.0 / 60.0)
	_expect(
		_close(single.get_view_degrees(), stepped.get_view_degrees(), 0.01),
		"平滑插值受帧率影响"
	)


func _key_event(code: Key, pressed: bool, ctrl := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.ctrl_pressed = ctrl
	return event


func _test_world() -> void:
	var world = load("res://main.tscn").instantiate()
	world.seed = 42
	world.stream_extent = 3
	world.sight_radius = 2
	root.add_child(world)
	await process_frame
	world.set_process(false)

	var sample := Vector2i(1, 1)
	var viewport_center: Vector2 = world.get_viewport_rect().size * 0.5
	world._cam.zoom = Vector2(2.0, 2.0)
	for angle in [0.0, 37.0, 90.0, 181.0, 275.0]:
		world._iso_view.set_view_angle(angle)
		world._refresh_view_projection()
		var level: float = world.cell_stand_level(sample)
		var expected: Vector2 = world._iso_view.grid_to_screen(sample, level)
		_expect(world._grid_to_screen(sample, level).is_equal_approx(expected), "主地图未使用旋转投影")
		var column = world._cells[sample]
		var base_expected: Vector2 = world._iso_view.grid_to_screen(sample)
		var actual := Vector2(column.position.x, column.position.y + column._screen_y_offset)
		_expect(
			actual.is_equal_approx(base_expected),
			"地块渲染代理未随角度刷新: angle=%.1f actual=%s expected=%s" % [
				angle, actual, base_expected
			]
		)
		_expect(
			world._player_visual_position.is_equal_approx(world._cell_feet_pos(world._player_cell)),
			"玩家脚点未随角度刷新"
		)
		world._cam.position = expected
		var picked: Vector2i = world.screen_to_cell(viewport_center)
		_expect(picked == sample, "角度 %.1f 的鼠标拾取偏移: %s != %s" % [angle, picked, sample])
		var rect_picked: Vector2i = world.screen_to_cell_in_rect(
			viewport_center, sample - Vector2i.ONE * 2, Vector2i.ONE * 5
		)
		_expect(rect_picked == sample, "角度 %.1f 的范围拾取偏移" % angle)

	world._iso_view.set_view_angle(0.0)
	world._unhandled_input(_key_event(KEY_X, true))
	_expect(_close(world._iso_view.get_target_degrees(), 45.0), "世界 X 键没有步进旋转")
	world._unhandled_input(_key_event(KEY_Z, true))
	_expect(_close(world._iso_view.get_target_degrees(), 0.0), "世界 Z 键没有反向步进")
	world._unhandled_input(_key_event(KEY_X, true))
	world._unhandled_input(_key_event(KEY_R, true))
	_expect(_close(world._iso_view.get_target_degrees(), 0.0), "世界 R 键没有复位视角")

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.position = Vector2(100.0, 0.0)
	world._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(190.0, 0.0)
	world._unhandled_input(motion)
	_expect(_close(world._iso_view.get_target_degrees(), 45.0), "世界中键拖拽没有旋转")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_MIDDLE
	release.pressed = false
	release.position = motion.position
	world._unhandled_input(release)
	_expect(not world._view_dragging, "中键释放后仍在拖拽")

	Input.parse_input_event(_key_event(KEY_E, true))
	await process_frame
	_expect(world._continuous_view_rotation() == 1, "按住 E 没有进入连续顺时针旋转")
	Input.parse_input_event(_key_event(KEY_E, false))
	Input.parse_input_event(_key_event(KEY_Q, true))
	await process_frame
	_expect(world._continuous_view_rotation() == -1, "按住 Q 没有进入连续逆时针旋转")
	Input.parse_input_event(_key_event(KEY_Q, false))
	await process_frame
	_expect(world._continuous_view_rotation() == 0, "旋转键释放后仍持续旋转")

	world.queue_free()
	await process_frame


func _run() -> void:
	_test_controller()
	await _test_world()
	if failures.is_empty():
		print("ISOMETRIC_VIEW_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
