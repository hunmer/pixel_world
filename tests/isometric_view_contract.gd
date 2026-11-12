extends SceneTree
## Camera3D 主世界投影、旋转输入与真实地形拾取契约。

const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _close(actual: float, expected: float, tolerance := 0.001) -> bool:
	return absf(actual - expected) <= tolerance


func _initialize() -> void:
	call_deferred("_run")


func _target_degrees(camera: Camera3D) -> float:
	return rad_to_deg(camera.target_yaw_radians)


func _key_event(code: Key, pressed: bool, ctrl := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.ctrl_pressed = ctrl
	return event


func _mesh_instance_ids(terrain: Node3D) -> Array:
	var result: Array = []
	for chunk in terrain._chunks.values():
		for child in chunk.get_children():
			if child is MeshInstance3D or child is MultiMeshInstance3D:
				result.append(child.get_instance_id())
	return result


func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	world.seed = 42
	world.stream_extent = 3
	world.sight_radius = 2
	root.add_child(world)
	await process_frame
	world.set_process(false)

	var sample := Vector2i(1, 1)
	var viewport_center: Vector2 = world.get_viewport_rect().size * 0.5
	world._cam.zoom = 2.0
	var initial_meshes := _mesh_instance_ids(world._terrain)
	for angle in [0.0, 37.0, 90.0, 181.0, 275.0]:
		world._cam.snap_to_angle(angle)
		world._refresh_view_projection()
		var level: float = world.cell_stand_level(sample)
		var expected := IsoProjection.world_to_screen(
			world._cam, IsoProjection.grid_to_world(sample, level)
		)
		_expect(world._grid_to_screen(sample, level).distance_to(expected) < 0.001,
			"主地图未使用 Camera3D 投影")
		_expect(_mesh_instance_ids(world._terrain) == initial_meshes,
			"旋转重建了地形 mesh")
		_expect(world._player_visual_position.is_equal_approx(world._cell_feet_pos(world._player_cell)),
			"旋转改变了玩家连续网格状态")
		world._cam.focus_position = IsoProjection.grid_to_world(sample, level)
		var picked: Vector2i = world.screen_to_cell(viewport_center)
		_expect(picked == sample, "角度 %.1f 的鼠标拾取偏移: %s != %s" % [angle, picked, sample])
		var rect_picked: Vector2i = world.screen_to_cell_in_rect(
			viewport_center, sample - Vector2i.ONE * 2, Vector2i.ONE * 5
		)
		_expect(rect_picked == sample, "角度 %.1f 的范围拾取偏移" % angle)

	world._cam.snap_to_angle(0.0)
	world._unhandled_input(_key_event(KEY_X, true))
	_expect(_close(_target_degrees(world._cam), 90.0), "世界 X 键没有步进旋转")
	world._unhandled_input(_key_event(KEY_Z, true))
	_expect(_close(_target_degrees(world._cam), 0.0), "世界 Z 键没有反向步进")
	world._unhandled_input(_key_event(KEY_X, true))
	world._unhandled_input(_key_event(KEY_R, true))
	_expect(_close(_target_degrees(world._cam), rad_to_deg(IsoProjection.CAMERA_YAW)),
		"世界 R 键没有复位视角")

	world._cam.snap_to_angle(0.0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.position = Vector2(100.0, 0.0)
	world._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(190.0, 0.0)
	world._unhandled_input(motion)
	_expect(_close(_target_degrees(world._cam), 360.0 - rad_to_deg(90.0 * 0.008)), "世界中键拖转没有按像素连续旋转")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_MIDDLE
	release.pressed = false
	release.position = motion.position
	world._unhandled_input(release)
	_expect(not world._view_dragging, "中键释放后仍在拖拽")

	world._cam.snap_to_angle(0.0)
	world._unhandled_input(_key_event(KEY_Q, true))
	_expect(_close(_target_degrees(world._cam), 270.0), "Q 没有离散逆时针切换")
	world._unhandled_input(_key_event(KEY_E, true))
	_expect(_close(_target_degrees(world._cam), 0.0), "E 没有离散顺时针切换")
	world._unhandled_input(_key_event(KEY_RIGHT, true))
	_expect(_close(_target_degrees(world._cam), 90.0), "右方向键没有离散切换")
	world._unhandled_input(_key_event(KEY_LEFT, true))
	_expect(_close(_target_degrees(world._cam), 0.0), "左方向键没有离散切换")

	var follow_target := Vector2(2.0, 3.0)
	world._player_visual_position = follow_target
	world._camera_smooth_position = Vector2.ZERO
	world._process(0.5)
	_expect(world._camera_smooth_position.distance_to(follow_target) < 2.0,
		"相机平滑跟随没有接近玩家连续网格位置")
	var expected_focus := IsoProjection.visual_to_world(
		world._camera_smooth_position, world._player_current_stand_level()
	)
	_expect(world._cam.focus_position.distance_to(expected_focus) < 0.001,
		"Camera3D 焦点没有跟随平滑网格位置")

	world._stream_center = Vector2i(24, -18)
	world._update_streaming()
	_expect(world._terrain.cell_count() == 49, "主世界流式 add 数量错误")
	_expect(not world._terrain.has_cell(Vector2i.ZERO), "主世界离开旧中心后未 remove 旧地形")
	_expect(world._terrain.has_cell(Vector2i(24, -18)), "主世界未生成新中心真实地形")
	var frozen_cells: Array = world._terrain._cells.keys()
	world._battle_active = true
	world._stream_center += Vector2i.ONE * 20
	world._update_streaming()
	_expect(world._terrain._cells.keys() == frozen_cells, "B1 冻结期间流式窗口仍发生变化")
	world._battle_active = false

	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("ISOMETRIC_VIEW_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
