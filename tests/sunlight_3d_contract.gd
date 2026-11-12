extends SceneTree
## sunlight_3d_contract.gd — 日照时钟、真实灯参数、阴影 flags 与相机旋转隔离契约。

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _l1(message: String) -> void:
	var bridge := root.get_node_or_null("BreakpointRuntimeBridge")
	if bridge != null:
		bridge.push_log("info", "[L1][Sunlight3D] " + message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	world.seed = 42
	root.add_child(world)
	await process_frame
	world.set_process(false)
	world._day_night.set_process(false)

	var sunlight = world._sunlight
	_expect(sunlight != null, "主世界没有初始化 3D 日照系统")
	if sunlight == null:
		_finish(world)
		return
	var sun: DirectionalLight3D = sunlight.sun
	_expect(sun != null and sun.shadow_enabled, "DirectionalLight3D 未启用真实阴影")
	_expect(
		sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL,
		"正交相机未使用单张正交方向光阴影"
	)
	_expect(sunlight.world_environment.environment.ambient_light_energy > 0.0, "环境光缺失")

	world._day_night.set_auto_mode()
	world._day_night.set_cycle_progress(0.27, true)
	sunlight._process(0.0)
	var morning_direction: Vector3 = sunlight.sun_direction(0.27)
	var morning_energy: float = sun.light_energy
	var morning_color: Color = sun.light_color
	_expect(morning_direction.y > 0.0 and morning_direction.y < 0.25, "上午太阳高度角错误")
	_expect(morning_energy > 0.0, "上午方向光强度仍为零")
	world._day_night.set_cycle_progress(0.5, true)
	sunlight._process(0.0)
	_expect(sunlight.sun_direction(0.5).y > 0.999, "正午太阳没有到达天顶")
	_expect(sun.light_energy > morning_energy, "正午方向光没有强于低角度上午")
	_expect(not sun.light_color.is_equal_approx(morning_color), "日照色温没有随太阳高度变化")
	world._day_night.set_cycle_progress(0.0, true)
	sunlight._process(0.0)
	_expect(sun.light_energy < 0.0001, "午夜仍在发射白天直射光")
	_expect(
		sunlight.world_environment.environment.ambient_light_energy
		< float(sunlight._parameters["day_ambient_energy"]),
		"午夜环境光没有降低"
	)

	# 与 --time day/night 共用的人工模式必须覆盖午夜太阳位置，并在恢复自动后沿用原进度。
	world._day_night.set_manual_night(false)
	world._day_night.snap_transition()
	_expect(sun.light_energy > 0.0, "午夜切 --time day 对应的人工白天仍未恢复直射光")
	_expect(sun.global_basis.z.y > 0.0, "人工白天在自动午夜仍把太阳留在地平线以下")
	world._day_night.set_manual_night(true)
	world._day_night.snap_transition()
	_expect(sun.light_energy < 0.0001, "--time night 对应的人工夜晚未关闭直射光")
	world._day_night.set_manual_night(false)
	world._day_night.snap_transition()
	_expect(sun.light_energy > 0.0, "人工夜晚切回白天未恢复直射光")
	world._day_night.set_auto_mode()
	sunlight._process(0.0)
	_expect(sun.light_energy < 0.0001, "人工白天切回自动午夜后仍残留直射光")
	_expect(
		sun.global_basis.z.is_equal_approx(sunlight.sun_direction(0.0)),
		"切回自动模式没有恢复原午夜进度对应的太阳方向"
	)
	world._day_night.set_cycle_progress(0.35, true)
	sunlight._process(0.0)
	var auto_direction := sun.global_basis.z
	var auto_progress := float(world._day_night._cycle_progress)
	world._day_night._process(0.48)
	sunlight._process(0.0)
	_expect(is_equal_approx(
		float(world._day_night._cycle_progress),
		auto_progress + 0.48 / float(world._day_night._cycle_seconds)
	), "恢复自动后原480秒时钟没有继续推进")
	_expect(not sun.global_basis.z.is_equal_approx(auto_direction), "自动时钟推进后太阳没有连续运动")

	var solid_count := 0
	var water_count := 0
	for chunk in world._terrain._chunks.values():
		for instance in chunk.get_children():
			if instance is MeshInstance3D:
				var material := instance.mesh.surface_get_material(0) as StandardMaterial3D
				if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
					water_count += 1
					_expect(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "透明水面错误接收光照")
					_expect(instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "透明水面仍投射阴影")
				else:
					solid_count += 1
					_expect(material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "实心地形仍为 unshaded")
					_expect(instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "实心地形未投射阴影")
					var normals := instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array
					var horizontal_normals := 0
					for normal in normals:
						if absf(normal.y) > 0.99:
							horizontal_normals += 1
							_expect(normal.y > 0.0, "实心柱顶面法线朝内，真实日照/阴影会失效")
					_expect(horizontal_normals > 0, "实心地形缺少可验证的顶面法线")
			elif instance is MultiMeshInstance3D:
				_expect(instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "透明 atlas props 未关闭投影")
	_expect(solid_count > 0, "主世界没有可验证的实心地形")
	_expect(water_count > 0, "主世界没有可验证的透明水面")

	world._day_night.set_cycle_progress(0.35, true)
	sunlight._process(0.0)
	var light_basis := sun.global_basis
	var chunk_count: int = world._terrain.chunk_count()
	var mesh_count: int = world._terrain.mesh_instance_count()
	var light_child_count: int = sunlight.get_child_count()
	for yaw in [45.0, 135.0, 233.0, 317.0]:
		world._cam.snap_to_angle(yaw)
		await process_frame
		_expect(sun.global_basis.is_equal_approx(light_basis), "相机 yaw=%.0f 改变了世界太阳方向" % yaw)
		_expect(world._terrain.chunk_count() == chunk_count, "相机 yaw 重建了 chunk")
		_expect(world._terrain.mesh_instance_count() == mesh_count, "相机 yaw 重建了地形网格")
		_expect(sunlight.get_child_count() == light_child_count, "相机 yaw 创建了额外灯光节点")
	_l1("cycle/day-night/material-shadow/four-yaw checks completed; failures=%d" % failures.size())
	_finish(world)


func _finish(world: Node) -> void:
	world.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("SUNLIGHT_3D_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
			if OS.has_feature("l3"):
				breakpoint
		quit(1)
