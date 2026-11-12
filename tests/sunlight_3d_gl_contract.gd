extends SceneTree
## sunlight_3d_gl_contract.gd — 真实 GL 下高柱向低顶面投影的像素读回契约。
## 运行：godot --path . --rendering-method gl_compatibility --script res://tests/sunlight_3d_gl_contract.gd

const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
const TerrainScript = preload("res://scripts/iso/isometric_terrain_3d.gd")
const CameraScript = preload("res://scripts/iso/isometric_camera_3d.gd")
const SunlightScript = preload("res://scripts/sunlight_system.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _l1(message: String) -> void:
	var bridge := root.get_node_or_null("BreakpointRuntimeBridge")
	if bridge != null:
		bridge.push_log("info", "[L1][SunlightGL] " + message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("SUNLIGHT_GL_CONTRACT 需要非 headless 的 gl_compatibility 运行")
		quit(2)
		return
	root.size = Vector2i(640, 400)
	print("SUNLIGHT_GL_ADAPTER ", RenderingServer.get_video_adapter_name())
	print("SUNLIGHT_GL_API ", RenderingServer.get_video_adapter_api_version())

	var scene := Node3D.new()
	root.add_child(scene)
	var sunlight = SunlightScript.new()
	scene.add_child(sunlight)
	sunlight.set_process(false)
	sunlight.apply_time(0.35, 0.0)
	var terrain = TerrainScript.new()
	scene.add_child(terrain)
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var high_blocks: Array = []
	for level in range(1, 7):
		high_blocks.append({
			"level": level, "texture": texture, "modulate": Color.WHITE,
			"render_offset": Vector2.ZERO, "occluder_class": &"terrain",
		})
	terrain.set_cell(Vector2i.ZERO, high_blocks, 6.0)

	# 从高柱顶中心沿光线求低顶面交点，采样点必定位于真实投影内部。
	var progress := 0.35
	var high_top := IsoProjection.grid_to_world(Vector2i.ZERO, 6.0)
	var low_level := 1.0
	var ground_to_sun: Vector3 = sunlight.sun_direction(progress)
	var height := high_top.y - low_level * IsoProjection.LEVEL_HEIGHT
	var shadow_point := Vector3(
		high_top.x - ground_to_sun.x * height / ground_to_sun.y,
		low_level * IsoProjection.LEVEL_HEIGHT,
		high_top.z - ground_to_sun.z * height / ground_to_sun.y
	)
	var low_cell := IsoProjection.world_to_grid(shadow_point)
	terrain.set_cell(low_cell, [{
		"level": 1, "texture": texture, "modulate": Color.WHITE,
		"render_offset": Vector2.ZERO, "occluder_class": &"terrain",
	}], low_level)
	terrain.flush()
	print("SUNLIGHT_GL_GEOMETRY low_cell=", low_cell, " shadow_point=", shadow_point,
		" build_ms=", snappedf(terrain._last_build_ms, 0.001))

	var camera = CameraScript.new()
	camera.zoom = 2.0
	camera.focus_position = shadow_point
	scene.add_child(camera)
	camera.set_viewport_size(root.get_visible_rect().size)
	print("SUNLIGHT_GL_VIEWPORT root=", root.size, " visible=", root.get_visible_rect(),
		" camera=", camera._viewport_size)
	for _frame in 3:
		await RenderingServer.frame_post_draw

	var day_lit_luma := 0.0
	for yaw in [135.0, 225.0, 315.0, 45.0]:
		camera.snap_to_angle(yaw)
		sunlight.sun.shadow_enabled = false
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var lit := root.get_texture().get_image()
		var sample := _image_pixel(camera.unproject_position(shadow_point), lit)
		var lit_luma := _sample_luma(lit, sample)
		sunlight.sun.shadow_enabled = true
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var shaded := root.get_texture().get_image()
		var shaded_luma := _sample_luma(shaded, sample)
		var contrast := lit_luma - shaded_luma
		print("SUNLIGHT_GL_YAW yaw=", yaw, " pixel=", sample,
			" lit=", snappedf(lit_luma, 0.0001), " shadow=", snappedf(shaded_luma, 0.0001),
			" contrast=", snappedf(contrast, 0.0001))
		_expect(contrast > 0.06, "真实 GL 在 yaw=%.0f 没有高柱→低格阴影（差值 %.4f）" % [yaw, contrast])
		if is_equal_approx(yaw, 225.0):
			day_lit_luma = lit_luma
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://sunlight_3d_gl"))
			lit.save_png("user://sunlight_3d_gl/shadow_off.png")
			shaded.save_png("user://sunlight_3d_gl/shadow_on.png")

	# 人工夜晚的参数与 --time night 相同；直射消失且环境光真实变暗。
	sunlight.sun.shadow_enabled = false
	sunlight.apply_time(progress, 1.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var night := root.get_texture().get_image()
	var night_luma := _sample_luma(night, _image_pixel(camera.unproject_position(shadow_point), night))
	print("SUNLIGHT_GL_NIGHT day=", snappedf(day_lit_luma, 0.0001),
		" night=", snappedf(night_luma, 0.0001))
	_expect(night_luma < day_lit_luma - 0.04, "真实 GL 夜晚画面没有变暗")
	_expect(sunlight.sun.light_energy == 0.0, "真实 GL 夜晚仍有直射光")
	night.save_png("user://sunlight_3d_gl/night.png")

	# 90 帧窗口记录稳态开销；阴影始终为一张正交方向光 shadow map。
	sunlight.apply_time(progress, 0.0)
	sunlight.sun.shadow_enabled = true
	var started := Time.get_ticks_usec()
	for _frame in 90:
		await process_frame
	var wall_ms := float(Time.get_ticks_usec() - started) / 1000.0
	print("SUNLIGHT_GL_PERF frames=90 avg_wall_ms=", snappedf(wall_ms / 90.0, 0.001),
		" draw_calls=", int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		" chunks=", terrain.chunk_count(), " mesh_instances=", terrain.mesh_instance_count())
	_l1("real-GL cross-height shadow/day-night/performance checks completed; failures=%d" % failures.size())
	scene.queue_free()
	await process_frame
	await _measure_main_world()
	if failures.is_empty():
		print("SUNLIGHT_3D_GL_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
			if OS.has_feature("l3"):
				breakpoint
		quit(1)


func _measure_main_world() -> void:
	var world = load("res://main.tscn").instantiate()
	world.seed = 42
	root.add_child(world)
	for _frame in 15:
		await process_frame
	world._day_night.set_auto_mode()
	world._day_night.set_cycle_progress(0.3, true)
	world._sunlight._process(0.0)
	var initial_progress: float = world._day_night.get("_cycle_progress")
	var initial_light_basis: Basis = world._sunlight.sun.global_basis
	var terrain = world._terrain
	var initial_chunks: int = terrain.chunk_count()
	var initial_meshes: int = terrain.mesh_instance_count()
	var started := Time.get_ticks_usec()
	for _frame in 90:
		await process_frame
	var wall_ms := float(Time.get_ticks_usec() - started) / 1000.0
	print("SUNLIGHT_GL_WORLD_PERF frames=90 avg_wall_ms=", snappedf(wall_ms / 90.0, 0.001),
		" draw_calls=", int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		" chunks=", terrain.chunk_count(), " mesh_instances=", terrain.mesh_instance_count(),
		" last_build_ms=", snappedf(terrain._last_build_ms, 0.001),
		" cycle_delta=", snappedf(float(world._day_night.get("_cycle_progress")) - initial_progress, 0.000001))
	_expect(float(world._day_night.get("_cycle_progress")) > initial_progress, "真实 GL 自动昼夜时钟没有推进")
	_expect(not world._sunlight.sun.global_basis.is_equal_approx(initial_light_basis), "真实 GL 自动时钟没有驱动太阳方向")
	_expect(terrain.chunk_count() == initial_chunks, "静止主世界 90 帧内 chunk 数量无界增长")
	_expect(terrain.mesh_instance_count() == initial_meshes, "静止主世界 90 帧内 mesh 数量无界增长")
	_expect(world._sunlight.sun.shadow_enabled, "主世界真实 GL 未启用方向光阴影")
	world.queue_free()
	await process_frame
	await process_frame


func _image_pixel(viewport_point: Vector2, image: Image) -> Vector2:
	var viewport_size := root.get_visible_rect().size
	return Vector2(
		viewport_point.x * image.get_width() / viewport_size.x,
		viewport_point.y * image.get_height() / viewport_size.y
	)


func _sample_luma(image: Image, point: Vector2) -> float:
	var total := 0.0
	var count := 0
	var center := Vector2i(point.round())
	for y in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var color := image.get_pixel(x, y)
			total += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			count += 1
	return total / maxi(count, 1)
