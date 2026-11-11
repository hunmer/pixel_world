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

	_expect(
		IsometricViewScript.SUPPORTED_ANGLES == [0.0, 90.0, 180.0, 270.0],
		"支持角度必须只包含已验收的四个正交视角"
	)
	view.set_view_angle(0.0)
	view.advance(0.25, 1)
	_expect(_close(view.get_target_degrees(), 0.0), "连续旋转输入仍能改变目标角")
	_expect(_close(view.get_view_degrees(), 0.0), "连续旋转输入仍能改变当前角")

	view.rotate_step(1)
	_expect(_close(view.get_target_degrees(), 90.0), "离散顺时针步进不是 90°")
	_expect(_close(view.get_view_degrees(), 0.0), "目标角在 advance 前不同步")
	_expect(view.advance(0.001), "离散目标角没有触发投影刷新")
	_expect(_close(view.get_view_degrees(), 90.0), "离散步进仍在平滑插值")
	_expect(not view.advance(1.0), "稳定离散视角重复触发刷新")
	view.rotate_step(-1)
	view.advance(0.001)
	_expect(_close(view.get_view_degrees(), 0.0), "离散逆时针步进没有回到 0°")

	view.drag_by(90.0)
	_expect(_close(view.get_target_degrees(), 0.0), "拖拽不足一个档位就改变了视角")
	view.drag_by(90.0)
	_expect(_close(view.get_target_degrees(), 90.0), "拖拽累积 180px 没有切换 90°")
	view.advance(0.001)
	view.reset_rotation()
	_expect(_close(view.get_target_degrees(), 0.0), "一键复位没有归零目标角")
	view.advance(0.001)
	_expect(_close(view.get_view_degrees(), 0.0), "复位后当前角没有立即同步")
	view.snap_to_angle(123.0)
	_expect(_close(view.get_view_degrees(), 90.0), "snap_to_angle 没有吸附到最近支持角")
	view.snap_to_angle(191.0)
	_expect(_close(view.get_target_degrees(), 180.0), "目标角与吸附后的当前角不同步")
	view.set_view_angle(270.0)
	view.rotate_step(1)
	view.advance(0.001)
	_expect(_close(view.get_view_degrees(), 0.0), "离散视角没有从 270° 环绕到 0°")

	for angle in IsometricViewScript.SUPPORTED_ANGLES:
		view.snap_to_angle(angle)
		_expect(_close(view.get_view_degrees(), angle), "支持角无法立即生效: %.0f" % angle)
		_expect(_close(view.get_target_degrees(), angle), "支持角目标状态不同步: %.0f" % angle)


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
	_expect(_close(world._iso_view.get_target_degrees(), 90.0), "世界 X 键没有步进旋转")
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
	_expect(_close(world._iso_view.get_target_degrees(), 0.0), "世界拖拽不足一档就旋转")
	motion = InputEventMouseMotion.new()
	motion.position = Vector2(280.0, 0.0)
	world._unhandled_input(motion)
	_expect(_close(world._iso_view.get_target_degrees(), 90.0), "世界中键拖拽没有按档位旋转")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_MIDDLE
	release.pressed = false
	release.position = motion.position
	world._unhandled_input(release)
	_expect(not world._view_dragging, "中键释放后仍在拖拽")

	world._iso_view.set_view_angle(0.0)
	world._unhandled_input(_key_event(KEY_Q, true))
	_expect(_close(world._iso_view.get_target_degrees(), 270.0), "Q 没有离散逆时针切换")
	world._unhandled_input(_key_event(KEY_E, true))
	_expect(_close(world._iso_view.get_target_degrees(), 0.0), "E 没有离散顺时针切换")
	world._unhandled_input(_key_event(KEY_RIGHT, true))
	_expect(_close(world._iso_view.get_target_degrees(), 90.0), "右方向键没有离散切换")
	world._unhandled_input(_key_event(KEY_LEFT, true))
	_expect(_close(world._iso_view.get_target_degrees(), 0.0), "左方向键没有离散切换")

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
