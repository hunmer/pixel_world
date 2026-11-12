## world_camera_navigation_contract.gd — 主世界抓取平移、鼠标缩放锚点与 B1 集成回归。
extends SceneTree

const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
const WorldToChapter = preload("res://scripts/core/world_to_chapter.gd")

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)
		if OS.has_feature("l3"):
			breakpoint


func _space(world: Node, pressed: bool) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = pressed
	world._unhandled_input(key)


func _button(world: Node, pressed: bool, position: Vector2) -> void:
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = pressed
	button.position = position
	world._unhandled_input(button)


func _motion(world: Node, position: Vector2, relative: Vector2, held: bool = true) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.relative = relative
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	world._unhandled_input(motion)


func _wheel(world: Node, position: Vector2, up: bool) -> void:
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = position
	world._unhandled_input(wheel)


func _run() -> void:
	var world: Node = load("res://main.tscn").instantiate()
	world.set("seed", 42)
	world.set("stream_extent", 16)
	root.add_child(world)
	await process_frame
	world.set_process(false)
	var camera: Camera3D = world.get("_cam")
	var navigation: RefCounted = world.get("_world_camera_navigation")
	var viewport_size: Vector2 = root.get_visible_rect().size
	var start := Vector2(viewport_size.x * 0.42, viewport_size.y * 0.48)
	var drag := Vector2(57.0, -29.0)

	# 通过视口完整输入链验证，避免只测直接调用而遗漏 GUI 吞事件。
	var routed_space := InputEventKey.new()
	routed_space.physical_keycode = KEY_SPACE
	routed_space.pressed = true
	root.push_input(routed_space, true)
	var routed_press := InputEventMouseButton.new()
	routed_press.button_index = MOUSE_BUTTON_LEFT
	routed_press.pressed = true
	routed_press.position = start
	root.push_input(routed_press, true)
	var routed_motion := InputEventMouseMotion.new()
	routed_motion.position = start + drag
	routed_motion.relative = drag
	routed_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(routed_motion, true)
	_expect((navigation.get("offset") as Vector2).length() > 0.1, "viewport input route delivers Space+left drag to the world")
	routed_press.pressed = false
	routed_press.position = start + drag
	root.push_input(routed_press, true)
	routed_space.pressed = false
	root.push_input(routed_space, true)
	var routed_wheel := InputEventMouseButton.new()
	routed_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	routed_wheel.pressed = true
	routed_wheel.position = start
	var initial_zoom: int = world.get("_zoom_index")
	root.push_input(routed_wheel, true)
	_expect(int(world.get("_zoom_index")) == initial_zoom + 1, "viewport input route delivers wheel zoom to the world")
	var runtime_bridge: Node = root.get_node("BreakpointRuntimeBridge")
	var zoom_assertion: Dictionary = runtime_bridge.call("_dispatch", "runtime.assert_node_state", {
		"path": str(world.get_path()), "expect": {"_zoom_index": initial_zoom + 1}
	})
	_expect(bool(zoom_assertion.get("ok", false)) and bool(zoom_assertion.get("result", {}).get("ok", false)),
		"runtime_assert_node_state confirms the actual world zoom index")
	var camera_assertion: Dictionary = runtime_bridge.call("_dispatch", "runtime.assert_node_state", {
		"path": str(camera.get_path()), "expect": {"zoom": camera.get("zoom"), "projection": Camera3D.PROJECTION_ORTHOGONAL}
	})
	_expect(bool(camera_assertion.get("ok", false)) and bool(camera_assertion.get("result", {}).get("ok", false)),
		"runtime_assert_node_state confirms the active orthographic camera zoom")

	for angle: float in [0.0, 90.0, 180.0, 270.0]:
		camera.snap_to_angle(angle)
		var level: float = camera.focus_position.y / IsoProjection.LEVEL_HEIGHT
		var grabbed: Vector3 = IsoProjection.screen_to_world(camera, start, level) as Vector3
		_space(world, true)
		_button(world, true, start)
		_motion(world, start + drag, drag)
		_expect(camera.unproject_position(grabbed).distance_to(start + drag) < 0.05,
			"%d° Space+drag must move terrain by the mouse displacement" % int(angle))
		_button(world, false, start + drag)
		_space(world, false)
		var offset: Vector2 = navigation.get("offset")
		var focus: Vector3 = camera.get("focus_position")
		_motion(world, start + drag * 2.0, drag, false)
		_expect((navigation.get("offset") as Vector2).is_equal_approx(offset), "release stops map dragging")
		world._process(0.016)
		_expect((camera.get("focus_position") as Vector3).distance_to(focus) < 0.001,
			"follow update must retain the dragged camera position")

		for up: bool in [true, true, true, false, false, false, false, false]:
			var anchor_level: float = float(world.cell_stand_level(world.screen_to_cell(start)))
			var anchor: Vector3 = IsoProjection.screen_to_world(camera, start, anchor_level) as Vector3
			_wheel(world, start, up)
			_expect(camera.unproject_position(anchor).distance_to(start) < 0.05,
				"%d° wheel zoom must preserve cursor terrain anchor immediately" % int(angle))
			world._process(0.016)
			_expect(camera.unproject_position(anchor).distance_to(start) < 0.05,
				"%d° wheel zoom anchor must survive camera follow update" % int(angle))

	_space(world, true)
	_button(world, true, start)
	_space(world, false)
	var released_offset: Vector2 = navigation.get("offset")
	_motion(world, start + drag, drag)
	_expect((navigation.get("offset") as Vector2).is_equal_approx(released_offset), "Space release cancels dragging")
	_button(world, false, start)
	_button(world, true, start)
	_motion(world, start + drag, drag)
	_expect((navigation.get("offset") as Vector2).is_equal_approx(released_offset), "plain left drag must not pan the world")
	_button(world, false, start)

	var chapter: Dictionary = WorldToChapter.world_to_chapter(
		world.get("_terrain_sampler"), world.get("_player_cell"), 4, 42
	)
	world._enter_battle_inline(chapter)
	world.set("_battle_cam_offset", Vector2(48.0, -24.0))
	world._set_camera_position(world._battle_camera_focus())
	for up: bool in [true, false, false, true]:
		var level: float = float(world.cell_stand_level(world.screen_to_cell(start)))
		var anchor: Vector3 = IsoProjection.screen_to_world(camera, start, level) as Vector3
		_wheel(world, start, up)
		_expect(camera.unproject_position(anchor).distance_to(start) < 0.05,
			"B1 zoom after pan must preserve cursor terrain anchor")
		world._set_camera_position(world._battle_camera_focus())
		_expect(camera.unproject_position(anchor).distance_to(start) < 0.05,
			"B1 camera update must preserve cursor terrain anchor")
	world._exit_battle(&"contract")
	var restored_focus: Vector3 = camera.get("focus_position")
	world._process(0.016)
	_expect((camera.get("focus_position") as Vector3).distance_to(restored_focus) < 0.001, "B1 exit must not jump on the next camera update")
	_expect((navigation.get("offset") as Vector2).is_equal_approx(released_offset), "B1 exit preserves exploration pan offset")

	world.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("WORLD_CAMERA_NAVIGATION_CONTRACT_OK checks=%d" % checks)
	else:
		push_error("WORLD_CAMERA_NAVIGATION_CONTRACT_FAILED checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
