## tests/character_movement_test_contract.gd — 独立场景复用真实生态、网格移动、守卫与清理契约
extends SceneTree

const ACTION_LEFT := &"character_test_left"
const ACTION_RIGHT := &"character_test_right"
const ACTION_UP := &"character_test_up"
const ACTION_DOWN := &"character_test_down"
const Sheet = preload("res://scripts/characters/free_character_sheet.gd")

var failures: Array[String] = []
var checks: int = 0


class BlockingState:
	extends RefCounted

	func blocks_movement() -> bool:
		return true


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _key(keycode: int, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = pressed
	return event


func _open_direction(world: Node) -> Vector2i:
	var cell: Vector2i = world.get("_player_cell")
	var states: Dictionary = world.get("_cell_states")
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var target := cell + direction
		if states.has(target) and not states[target].blocks_movement():
			return direction
	return Vector2i.ZERO


func _action_for_direction(direction: Vector2i) -> StringName:
	if direction == Vector2i.RIGHT:
		return ACTION_RIGHT
	if direction == Vector2i.LEFT:
		return ACTION_LEFT
	if direction == Vector2i.UP:
		return ACTION_UP
	return ACTION_DOWN


func _expect_drawable_sprite(world: Node, label: String) -> void:
	var sprite: Sprite3D = world.get("_player")
	var animator: RefCounted = world.get("_animator")
	var character_id: StringName = animator.get("character_id")
	var row := int(animator.call("current_row"))
	var frame := int(animator.get("frame_index"))
	var expected_region := Sheet.frame_region(row, frame)
	_expect(sprite.is_visible_in_tree() and sprite.transparency < 1.0 and sprite.modulate.a > 0.0,
		"%s is visible with non-transparent draw state" % label)
	_expect(sprite.texture == Sheet.sheet_texture(character_id),
		"%s draws the selected character's full source sheet" % label)
	_expect(sprite.region_enabled and sprite.region_rect == expected_region,
		"%s uses the animator's native Sprite3D source region" % label)
	_expect(sprite.hframes == 1 and sprite.vframes == 1 and sprite.frame == 0
		and sprite.frame_coords == Vector2i.ZERO,
		"%s cannot inherit a stale frame override" % label)
	var region := Rect2i(Vector2i(sprite.region_rect.position), Vector2i(sprite.region_rect.size))
	_expect(Rect2i(Vector2i.ZERO, Vector2i(sprite.texture.get_size())).encloses(region),
		"%s source region stays inside the 384x832 sheet" % label)
	var opaque_rect := sprite.texture.get_image().get_region(region).get_used_rect()
	_expect(opaque_rect.size.x > 0 and opaque_rect.size.y > 0,
		"%s source region contains opaque character pixels" % label)
	var item_rect := sprite.get_item_rect()
	_expect(item_rect.size.is_equal_approx(Vector2(64, 64)) and item_rect.position == Vector2(-32, -1),
		"%s has a 64x64 draw rectangle with its bottom-center at the feet" % label)
	var local_opaque_rect := Rect2(item_rect.position + Vector2(opaque_rect.position), Vector2(opaque_rect.size))
	_expect(item_rect.encloses(local_opaque_rect),
		"%s opaque geometry lies inside the Sprite3D draw rectangle" % label)
	# Sprite3D 本地 Y 向上，源图像素 Y 向下；脚底世界位置就是地形支撑面。
	var support_y := sprite.global_position.y
	var opaque_top_y := support_y + (item_rect.end.y - float(opaque_rect.position.y)) * sprite.pixel_size
	var opaque_bottom_y := support_y + (item_rect.end.y - float(opaque_rect.end.y)) * sprite.pixel_size
	_expect(opaque_top_y > support_y and opaque_bottom_y >= support_y - 0.0001,
		"%s opaque geometry rises above the support plane instead of sinking below it (top=%.4f bottom=%.4f ground=%.4f)" % [label, opaque_top_y, opaque_bottom_y, support_y])
	var camera: Camera3D = world.get("_cam")
	var screen_point := camera.unproject_position(sprite.global_position)
	_expect(not camera.is_position_behind(sprite.global_position)
		and Rect2(Vector2.ZERO, root.get_visible_rect().size).has_point(screen_point),
		"%s feet project inside the active camera viewport" % label)


func _release_test_audio() -> void:
	# 真实 _try_move 会触发 Sfx 脚步；退出前停回放并清测试进程内的流引用。
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null:
		for child in sfx.get_children():
			if child is AudioStreamPlayer:
				child.stop()
				child.stream = null
		sfx.set("_streams", {})
	for index in 6:
		await process_frame
	# headless 可快于实时音频混音线程；留一个混音周期释放 MP3 playback。
	OS.delay_msec(100)


func _check_terrain_flush_budget() -> void:
	var terrain_script := load("res://scripts/scenes/character_movement_terrain_3d.gd") as Script
	_expect(terrain_script != null, "incremental terrain test script loads")
	if terrain_script == null:
		return
	var terrain := terrain_script.new() as Node3D
	root.add_child(terrain)
	terrain.set_process(false)
	for index in range(25):
		terrain.set_cell(Vector2i(index * 2, 0), [], 0.0)
	terrain.set_incremental_flush(true, 1000000)
	_expect(terrain.pending_chunk_count() == 25, "terrain test prepares 25 dirty chunks")
	_expect(terrain.flush() == 12 and terrain.pending_chunk_count() == 13,
		"terrain flush submits at most one bounded chunk batch")
	_expect(terrain.flush() == 0 and terrain.pending_chunk_count() == 13,
		"explicit flush and Terrain._process cannot double-submit in one frame")
	terrain.clear()
	terrain.queue_free()


func _drain_character_world(world: Node) -> int:
	var fauna: RefCounted = world.get("_fauna")
	for frame in range(600):
		if (
			(world.get("_pending_stream_cells") as Dictionary).is_empty()
			and not bool(world.get("_fauna_refresh_pending"))
			and not bool(fauna.call("is_scan_active"))
		):
			return frame
		world._process(0.025)
	_expect(false, "incremental cells and fauna converge within 600 parent-process steps")
	return 600


func _cell_state_signature(state: RefCounted) -> String:
	var context: RefCounted = state.get("context")
	return "%s|%s|%s|%s|%d" % [
		str(context.get("cell")),
		String(context.call("ecology_signature")),
		str(context.get("region_anchor")),
		str(state.get("occupancy_tags")),
		hash(state.get("static_objects")),
	]


func _active_group_signatures(world: Node) -> Dictionary:
	var store: RefCounted = world.get("_animal_groups")
	var result: Dictionary = {}
	var keys: Array = store.call("keys")
	keys.sort()
	for key in keys:
		if int(store.call("active_member_count", key)) <= 0:
			continue
		var group: Dictionary = store.call("get_value", key, {})
		var members: Array[String] = []
		for member: Dictionary in group.get("members", []):
			members.append("%s:%s:%s" % [
				str(member.get("origin", Vector2i.ZERO)),
				String(member.get("species", "")),
				String(member.get("role", "")),
			])
		members.sort()
		result[str(key)] = "%s|%s|%s|%.6f|%s" % [
			str(group.get("anchor", Vector2i.ZERO)),
			String(group.get("ecosystem_id", "")),
			String(group.get("community_id", "")),
			float(group.get("social_radius", 0.0)),
			";".join(members),
		]
	return result


func _exercise_continuous_movement(world: Node) -> void:
	_check_terrain_flush_budget()
	_expect(world.get("_terrain").has_method("pending_chunk_count"),
		"test scene owns bounded terrain without changing shared terrain")
	_expect(world.get("_fauna").has_method("is_scan_active"),
		"test scene owns incremental fauna without changing shared fauna")
	# _regenerate 保留当前格；对照实验显式从同一真实出生格开始。
	world.set("_player_cell", Vector2i.ZERO)
	world._regenerate(20261119)
	world.set_process(false)
	var start_cell: Vector2i = world.get("_player_cell")
	var camera: Camera3D = world.get("_cam")
	var previous_smooth: Vector2 = world.get("_camera_smooth_position")
	var previous_cell := start_cell
	var previous_elapsed := -1.0
	var cell_changes := 0
	var camera_samples := 0
	var max_pending := 0
	var saw_idle := false
	var frames_seen: Dictionary = {}
	var directions_seen: Dictionary = {}
	Input.action_press(ACTION_RIGHT)
	for frame in range(200):
		if cell_changes >= 10:
			break
		world._process(0.025)
		var animator: RefCounted = world.get("_animator")
		var mode: StringName = animator.get("mode")
		saw_idle = saw_idle or mode != &"run"
		if mode == &"run":
			var elapsed := float(animator.get("_run_elapsed"))
			if previous_elapsed >= 0.0:
				_expect(elapsed + 0.00001 >= previous_elapsed,
					"continuous parent-loop run_elapsed never resets between cells")
			previous_elapsed = elapsed
			frames_seen[int(animator.get("frame_index"))] = true
			directions_seen[animator.get("direction")] = true
		var current_cell: Vector2i = world.get("_player_cell")
		if current_cell != previous_cell:
			cell_changes += 1
			previous_cell = current_cell
		var smooth: Vector2 = world.get("_camera_smooth_position")
		if not smooth.is_equal_approx(previous_smooth):
			camera_samples += 1
		previous_smooth = smooth
		max_pending = maxi(max_pending, (world.get("_pending_stream_cells") as Dictionary).size())
	Input.action_release(ACTION_RIGHT)
	_expect(cell_changes == 10, "real parent loop completes ten consecutive passable cells")
	_expect(not saw_idle, "held direction has no one-frame idle at cell boundaries")
	_expect(frames_seen.size() == 6, "continuous parent loop renders all six run frame indices")
	_expect(directions_seen.size() == 1, "continuous same-direction movement keeps a stable facing")
	_expect(camera_samples >= cell_changes, "inherited camera follows a continuous smoothed trajectory")
	_expect(max_pending <= 68, "far-edge generation queue remains bounded while moving")
	world._process(0.2)
	_expect((world.get("_animator") as RefCounted).get("mode") == &"idle",
		"release after continuous movement settles to idle")
	_drain_character_world(world)
	var states: Dictionary = world.get("_cell_states")
	var center: Vector2i = world.get("_player_cell")
	var extent := int(world.get("stream_extent"))
	_expect(states.size() == (extent * 2 + 1) * (extent * 2 + 1),
		"drained stream has exactly the full square window")
	var missing := 0
	for y in range(center.y - extent, center.y + extent + 1):
		for x in range(center.x - extent, center.x + extent + 1):
			if not states.has(Vector2i(x, y)):
				missing += 1
	_expect(missing == 0, "every queued far-edge cell eventually generates")

	# 同种子、同路径的父世界同步流式结果作为权威对照。
	var reference_scene := load("res://main.tscn") as PackedScene
	_expect(reference_scene != null, "synchronous reference world loads")
	if reference_scene == null:
		return
	var reference := reference_scene.instantiate()
	reference.seed = 20261119
	reference.stream_extent = extent
	reference.move_time = 0.1
	root.add_child(reference)
	await process_frame
	reference.set_process(false)
	for step in range(10):
		reference._try_move(Vector2i.RIGHT)
		reference._process(0.2)
	_expect(reference.get("_player_cell") == center,
		"incremental and synchronous worlds follow the same ten-cell path")
	var reference_states: Dictionary = reference.get("_cell_states")
	var mismatches := 0
	for cell: Vector2i in states:
		if not reference_states.has(cell):
			mismatches += 1
			continue
		if _cell_state_signature(states[cell]) != _cell_state_signature(reference_states[cell]):
			mismatches += 1
	_expect(mismatches == 0 and states.size() == reference_states.size(),
		"incremental CellContext/occupancy/static flora match synchronous generation")
	var test_groups := _active_group_signatures(world)
	var reference_groups := _active_group_signatures(reference)
	_expect(test_groups == reference_groups,
		"active fauna anchors/members match synchronous generation (test=%d reference=%d)" % [test_groups.size(), reference_groups.size()])
	reference.queue_free()
	await process_frame
	await process_frame

	# 运行中旋转四个直角只改方向帧，不退出 run；八帧计时由动画器按方向切换自理。
	Input.action_press(ACTION_RIGHT)
	world._process(0.025)
	for quarter in range(4):
		camera.rotate_step(1, false)
		world._refresh_player_visual()
		var animator: RefCounted = world.get("_animator")
		var spec := Sheet.direction_spec(animator.get("direction"))
		_expect(animator.get("mode") == &"run"
			and int(animator.call("current_row")) == int(spec.get("row", -1))
			and (world.get("_player") as Sprite3D).flip_h == bool(spec.get("flip_h", false)),
			"running camera quarter %d keeps a valid directional animation" % quarter)
	Input.action_release(ACTION_RIGHT)
	world._process(0.2)
	_drain_character_world(world)


func _run() -> void:
	# autoload 就绪后再动态加载主场景，避免顶层 preload 抢在 Settings/Sfx 前编译。
	var test_scene := load("res://scenes/CharacterMovementTest.tscn") as PackedScene
	_expect(test_scene != null, "inherited CharacterMovementTest scene loads after autoload setup")
	if test_scene == null:
		quit(1)
		return
	# 路由表在不启动世界生成时可独立验收。
	var routes := test_scene.instantiate()
	var key_route: Dictionary = routes._key_route()
	var entry_route: Dictionary = routes._entry_key_route()
	for keycode: int in [KEY_LEFT, KEY_RIGHT, KEY_P, KEY_O, KEY_E]:
		_expect(not key_route.has(keycode), "physical route removes movement/entry conflict %d" % keycode)
	for keycode: int in [KEY_P, KEY_O, KEY_E]:
		_expect(not entry_route.has(keycode), "logical fallback also blocks old entry %d" % keycode)
	for keycode: int in [KEY_J, KEY_H, KEY_K, KEY_L, KEY_U, KEY_I]:
		_expect(key_route.has(keycode) and entry_route.has(keycode), "test action key is routed %d" % keycode)
	_expect(key_route.has(KEY_Q) and key_route.has(KEY_X), "Q/X retain quarter-turn camera navigation")
	_expect(routes.resolve_grid_direction(Vector2.ZERO) == Vector2i.ZERO, "deadzone has no grid movement")
	_expect(routes.resolve_grid_direction(Vector2(1, 0)) == Vector2i.RIGHT, "right resolves one cell")
	_expect(routes.resolve_grid_direction(Vector2(0, -1)) == Vector2i.UP, "up resolves one cell")
	_expect(routes.resolve_grid_direction(Vector2(0.7, -0.7), 0) == Vector2i.RIGHT,
		"diagonal held keys use latest horizontal axis without diagonal speed")
	_expect(routes.resolve_grid_direction(Vector2(0.7, -0.7), 1) == Vector2i.UP,
		"diagonal held keys use latest vertical axis without diagonal speed")
	routes._enter_battle()
	routes._enter_battlefield("res://unused.json")
	routes._open_map_editor()
	_expect(int(routes.get("_blocked_entry_attempts")) == 3, "direct old entry APIs are isolated")
	_expect(not bool(routes.get("_battle_transition_pending")) and routes.get("_battle_system") == null,
		"isolated entries never create battle state")
	routes.free()

	# 预置一个同名外部动作，验证场景只移除自己注册的事件和动作。
	InputMap.add_action(ACTION_LEFT, 0.2)
	var external_event := _key(KEY_F10)
	InputMap.action_add_event(ACTION_LEFT, external_event)
	var world := test_scene.instantiate()
	world.seed = 42
	world.stream_extent = 8
	world.move_time = 0.1
	root.add_child(world)
	await process_frame
	world.set_process(false)

	_expect(world.get("_terrain") != null and world.get("_cam") != null,
		"inherited scene creates real terrain and Camera3D")
	_expect((world.get("_cell_states") as Dictionary).size() > 0,
		"real ecology generates cell states instead of a mock world")
	_expect((world.get("_ecosystem_order") as Array).size() > 0,
		"inherited ecology registry remains active")
	var sprite: Sprite3D = world.get("_player")
	_expect(sprite != null, "inherited scene creates the Sprite3D player")
	_expect(sprite.offset == Vector2(0, 31), "runtime sprite raises the feet anchor along Sprite3D positive local Y")
	_expect(is_equal_approx(sprite.pixel_size, 1.0 / 36.0), "runtime sprite uses new pixel scale")
	_expect_drawable_sprite(world, "idle character 002")
	for action_name: StringName in [ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN]:
		_expect(InputMap.has_action(action_name), "scene registers %s" % action_name)
	_expect(InputMap.action_has_event(ACTION_LEFT, external_event),
		"registration preserves pre-existing external event")

	var camera: Camera3D = world.get("_cam")
	var start_yaw: float = camera.get("target_yaw_radians")
	world._handle_key_input(_key(KEY_X))
	_expect(not is_equal_approx(float(camera.get("target_yaw_radians")), start_yaw),
		"X rotates the inherited camera")
	world._handle_key_input(_key(KEY_Q))
	_expect(is_equal_approx(float(camera.get("target_yaw_radians")), start_yaw),
		"Q rotates back by one quarter turn")
	world._handle_key_input(_key(KEY_LEFT))
	world._handle_key_input(_key(KEY_RIGHT))
	_expect(is_equal_approx(float(camera.get("target_yaw_radians")), start_yaw),
		"left/right arrows no longer rotate camera")
	var initial_camera_yaw := float(camera.get("yaw_radians"))
	var directions_seen: Array[StringName] = []
	for quarter in range(4):
		camera.rotate_step(1, false)
		world._refresh_player_visual()
		var facing: StringName = (world.get("_animator") as RefCounted).get("direction")
		directions_seen.append(facing)
		var direction_spec := Sheet.direction_spec(facing)
		_expect(int((world.get("_animator") as RefCounted).call("current_row")) == int(direction_spec.get("row", -1))
			and sprite.flip_h == bool(direction_spec.get("flip_h", false)),
			"camera quarter %d selects matching directional row and mirror" % quarter)
		_expect_drawable_sprite(world, "idle at camera quarter %d" % quarter)
	for direction_name: StringName in [&"down", &"left", &"up", &"right"]:
		_expect(directions_seen.has(direction_name), "four camera angles cover %s" % direction_name)
	camera.set_view_angle(rad_to_deg(initial_camera_yaw), false)
	world._refresh_player_visual()

	var navigation: RefCounted = world.get("_world_camera_navigation")
	world._unhandled_input(_key(KEY_SPACE))
	_expect(bool(navigation.get("_space_held")), "Space grab remains routed")
	world._unhandled_input(_key(KEY_SPACE, false))
	_expect(not bool(navigation.get("_space_held")), "Space release clears grab state")

	var direction := _open_direction(world)
	_expect(direction != Vector2i.ZERO, "seeded world exposes a passable adjacent cell")
	if direction != Vector2i.ZERO:
		var start_cell: Vector2i = world.get("_player_cell")
		var action_name := _action_for_direction(direction)
		Input.action_press(action_name)
		_expect(world._input_dir() == direction, "named movement action feeds real grid input")
		world._process(0.016)
		_expect(world.get("_player_cell") == start_cell + direction,
			"inherited _try_move enters the adjacent cell")
		_expect(float(world.get("_move_t")) < 1.0, "movement still interpolates one grid step")
		_expect((world.get("_animator") as RefCounted).get("mode") == &"run",
			"grid movement drives run animation")
		_expect_drawable_sprite(world, "running character 002")
		_expect(not world.trigger_selected_preview(), "preview cannot restart/teleport during a grid step")
		Input.action_release(action_name)
		world._process(0.2)
		_expect(float(world.get("_move_t")) >= 1.0, "one grid step completes")
		var animator: RefCounted = world.get("_animator")
		var facing: StringName = animator.get("direction")
		_expect(animator.get("mode") == &"idle" and animator.get("direction") == facing,
			"release stops at idle and preserves facing")

	# 直接对父类占用守卫放入测试替身，确认阻挡时不改格位或插值。
	var blocked_cell: Vector2i = (world.get("_player_cell") as Vector2i) + Vector2i.LEFT
	var states: Dictionary = world.get("_cell_states")
	var had_state := states.has(blocked_cell)
	var previous_state: Variant = states.get(blocked_cell)
	states[blocked_cell] = BlockingState.new()
	var before_blocked: Vector2i = world.get("_player_cell")
	var before_move_t: float = world.get("_move_t")
	world._try_move(Vector2i.LEFT)
	_expect(world.get("_player_cell") == before_blocked and is_equal_approx(float(world.get("_move_t")), before_move_t),
		"blocks_movement rejects the step without movement or teleport")
	if had_state:
		states[blocked_cell] = previous_state
	else:
		states.erase(blocked_cell)

	var before_switch: Texture2D = sprite.texture
	_expect(world.cycle_character(1), "K/L character operation succeeds while idle")
	_expect((world.get("_animator") as RefCounted).get("character_id") == &"003",
		"next character has stable id 003")
	_expect(sprite.texture != before_switch, "switch updates the selected source sheet")
	_expect_drawable_sprite(world, "idle character 003")
	world.cycle_character(-1)
	_expect_drawable_sprite(world, "idle character 002 after switching back")
	var animator: RefCounted = world.get("_animator")
	var previews := Sheet.preview_ids()
	world.set("_preview_index", previews.find(&"preview_04"))
	_expect(world.trigger_selected_preview(), "J operation starts a non-moving preview while idle")
	var action_cell: Vector2i = world.get("_player_cell")
	_expect(animator.get("mode") == &"preview" and int(animator.call("current_row")) == 4,
		"selected numbered preview drives source row")
	_expect_drawable_sprite(world, "numbered preview frame")
	_expect(not world.trigger_selected_preview(), "J cannot repeatedly restart active action")
	world._process(0.25)
	_expect(world.get("_player_cell") == action_cell and float(world.get("_move_t")) >= 1.0,
		"preview never changes grid position or starts movement")
	world._process(0.125)
	_expect(animator.get("mode") == &"idle" and world.get("_player_cell") == action_cell,
		"one-shot ends idle without blank tail frames")
	world.trigger_selected_preview()
	world._key_reset_preview(_key(KEY_H))
	_expect(animator.get("mode") == &"idle", "H explicitly resets an active preview")

	# 地图、Control 焦点、暂停、失焦都同时禁止移动和测试动作。
	Input.action_press(ACTION_UP)
	world._toggle_world_map()
	_expect(world._input_dir() == Vector2i.ZERO and not world.cycle_character(1)
		and not world.trigger_selected_preview(), "world map modal blocks movement and actions")
	world.get("_world_map").close_map()
	_expect(world._input_dir() == Vector2i.UP, "closing map restores allowed input")
	var focus := LineEdit.new()
	world.add_child(focus)
	focus.grab_focus()
	_expect(world._input_dir() == Vector2i.ZERO and not world.cycle_character(1),
		"Control text focus blocks movement and actions")
	focus.free()
	paused = true
	_expect(world._input_dir() == Vector2i.ZERO and not world.trigger_selected_preview(),
		"SceneTree pause blocks movement and actions")
	paused = false
	world.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_expect(not Input.is_action_pressed(ACTION_UP), "focus loss releases owned movement actions")
	_expect(world._input_dir() == Vector2i.ZERO and not world.cycle_character(1),
		"window focus loss blocks movement and actions")
	world.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	Input.action_release(ACTION_UP)

	var attempts_before: int = world.get("_blocked_entry_attempts")
	for keycode: int in [KEY_P, KEY_O, KEY_E]:
		world._handle_key_input(_key(keycode))
	_expect(int(world.get("_blocked_entry_attempts")) == attempts_before,
		"P/O/E physical and logical routes cannot reach old entries")
	_expect(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/Campaign.tscn",
		"default application entry remains Campaign.tscn")

	await _exercise_continuous_movement(world)
	world.queue_free()
	await process_frame
	await process_frame
	_expect(InputMap.has_action(ACTION_LEFT), "pre-existing action survives scene cleanup")
	_expect(InputMap.action_has_event(ACTION_LEFT, external_event),
		"pre-existing external event survives scene cleanup")
	_expect(not InputMap.action_has_event(ACTION_LEFT, _key(KEY_A))
		and not InputMap.action_has_event(ACTION_LEFT, _key(KEY_LEFT)),
		"scene removes only its own events from pre-existing action")
	for action_name: StringName in [ACTION_RIGHT, ACTION_UP, ACTION_DOWN]:
		_expect(not InputMap.has_action(action_name), "scene-owned %s is removed on exit" % action_name)
	InputMap.erase_action(ACTION_LEFT)
	await _release_test_audio()

	if failures.is_empty():
		print("CHARACTER_MOVEMENT_TEST_CONTRACT_OK checks=%d" % checks)
	else:
		push_error("CHARACTER_MOVEMENT_TEST_CONTRACT_FAILED checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
