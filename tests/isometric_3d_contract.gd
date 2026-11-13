extends SceneTree
## isometric_3d_contract.gd — Camera3D 投影、四向旋转、缩放与 chunk 流式契约。

const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
const TerrainScript = preload("res://scripts/iso/isometric_terrain_3d.gd")
const CameraScript = preload("res://scripts/iso/isometric_camera_3d.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _l1(message: String) -> void:
	var bridge := root.get_node_or_null("BreakpointRuntimeBridge")
	if bridge != null:
		bridge.push_log("info", "[L1][Iso3D] " + message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene = load("res://scenes/Isometric3DTest.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var camera: Camera3D = scene.camera
	var terrain = scene.terrain
	assert(camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	assert(terrain.mesh_instance_count() > 0)
	var center := root.get_visible_rect().size * 0.5
	var origin_screen: Vector2 = camera.unproject_position(IsoProjection.grid_to_world(Vector2i.ZERO, 1.0))
	_expect(origin_screen.distance_to(center) < 0.01, "正交相机没有把焦点投影到视口中心")
	var x_screen: Vector2 = camera.unproject_position(IsoProjection.grid_to_world(Vector2i(1, 0), 1.0))
	var y_screen: Vector2 = camera.unproject_position(IsoProjection.grid_to_world(Vector2i(0, 1), 1.0))
	_expect((x_screen - origin_screen).distance_to(Vector2(16, 8)) < 0.02, "X 格不再投影为 (16,8)")
	_expect((y_screen - origin_screen).distance_to(Vector2(-16, 8)) < 0.02, "Y 格不再投影为 (-16,8)")
	var high_screen: Vector2 = camera.unproject_position(IsoProjection.grid_to_world(Vector2i.ZERO, 3.0))
	_expect((high_screen - origin_screen).distance_to(Vector2(0, -20)) < 0.02, "LEVEL_H=10 像素映射失效")
	for angle in [0.0, 90.0, 180.0, 270.0]:
		camera.snap_to_angle(angle)
		await process_frame
		var cell := Vector2i(2, 3)
		var screen := camera.unproject_position(IsoProjection.grid_to_world(cell, 2.0))
		var picked: Variant = IsoProjection.screen_to_grid(camera, screen, 2.0)
		_expect(picked != null and (picked as Vector2).distance_to(Vector2(cell)) < 0.001, "%d° 视角投影/射线往返失败" % int(angle))
		_expect(not camera.is_position_behind(IsoProjection.grid_to_world(cell, 2.0)), "%d° 视角把地形放到相机背面" % int(angle))
	camera.snap_to_angle(0.0)
	camera.rotate_step(1, false)
	_expect(is_equal_approx(camera.target_yaw_radians, PI * 0.5), "90° 旋转目标错误")
	camera.drag_by(Vector2(1000, 0), false)
	_expect(camera.yaw_radians >= 0.0 and camera.yaw_radians < TAU, "拖转 yaw 未归一化")
	camera.reset_rotation(false)
	var before_zoom: Vector2 = camera.unproject_position(IsoProjection.grid_to_world(Vector2i(1, 0), 1.0)) - center
	camera.zoom = 2.0
	var after_zoom: Vector2 = camera.unproject_position(IsoProjection.grid_to_world(Vector2i(1, 0), 1.0)) - center
	_expect((after_zoom - before_zoom * 2.0).length() < 0.03, "正交 size 缩放不是 2 倍屏幕距离")

	# 非中心像素、任意 yaw 和多层遮挡：必须选真实射线上最近的方格顶面。
	var high_cell := Vector2i(2, 3)
	var high_point := IsoProjection.visual_to_world(Vector2(high_cell) + Vector2(0.19, -0.22), 5)
	var levels: Dictionary = {high_cell: 5.0}
	var level_for_cell := func(cell: Vector2i) -> float:
		return float(levels.get(cell, -1.0))
	for angle in [23.0, 77.0, 141.0, 236.0, 318.0]:
		camera.snap_to_angle(angle)
		levels[high_cell] = 5.0
		var screen := camera.unproject_position(high_point)
		var low_cell: Vector2i = IsoProjection.screen_to_grid(camera, screen, 2.0).round()
		levels[low_cell] = 2.0
		var hit := IsoProjection.pick_top_face(camera, screen, 0, 12, level_for_cell)
		_expect(hit.get("cell", Vector2i(-99, -99)) == high_cell, "ray pick chooses the nearest occluding top at yaw %.0f" % angle)
		_expect(float(hit.get("distance", -1.0)) > 0.0, "ray hit remains in front of the camera")
		levels.erase(high_cell)
		var uncovered := IsoProjection.pick_top_face(camera, screen, 0, 12, level_for_cell)
		_expect(uncovered.get("cell", Vector2i(-99, -99)) == low_cell, "removing the high top reveals the lower grid cell")
		levels[high_cell] = 5.0
		levels.erase(low_cell)
		var outside := IsoProjection.pick_top_face(
			camera, camera.unproject_position(IsoProjection.visual_to_world(Vector2(high_cell) + Vector2(0.55, 0), 5)),
			5, 5, level_for_cell
		)
		_expect(outside.is_empty(), "ray pick rejects a square outside the occupied top face")
		levels.erase(high_cell)

	camera.reset_rotation(false)
	var resize_viewport:=SubViewport.new()
	resize_viewport.size=Vector2i(640,400)
	root.add_child(resize_viewport)
	var resize_camera:=CameraScript.new()
	resize_camera.focus_position=IsoProjection.grid_to_world(Vector2i.ZERO,1)
	resize_viewport.add_child(resize_camera)
	resize_viewport.size=Vector2i(960,640)
	await process_frame
	await process_frame
	_expect(resize_camera._viewport_size==Vector2(960,640),"viewport size_changed updates the camera")
	_expect(absf(resize_camera.size-640.0/(32.0*resize_camera.zoom))<0.0001,"resize preserves pixel scale")
	var resized_center:=resize_camera.unproject_position(resize_camera.focus_position)
	var resized_cell:=resize_camera.unproject_position(IsoProjection.grid_to_world(Vector2i(1,0),1))
	_expect(resized_cell.distance_to(resized_center+Vector2(16,8)*resize_camera.zoom)<0.01,"resize actual=%s center=%s zoom=%s size=%s" % [resized_cell,resized_center,resize_camera.zoom,resize_camera.size])
	resize_viewport.queue_free()

	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	for index in range(1, 18):
		terrain.set_cell(Vector2i(index, 0), [{
			"level": 0, "texture": texture, "modulate": Color.WHITE,
			"render_offset": Vector2.ZERO,
		}], 0.0)
	terrain.flush()
	_expect(terrain.cell_count() == 18, "流式 add 未保留全部 cell")
	_expect(terrain.chunk_count() == 9, "2×2 chunk 未按边界拆分")
	var mesh_before: int = terrain.get_child(0).get_child(0).get_instance_id()
	camera.snap_to_angle(90.0)
	_expect(terrain.get_child(0).get_child(0).get_instance_id() == mesh_before, "相机旋转重建了地形 MeshInstance")
	terrain.remove_cell(Vector2i(1, 0))
	terrain.flush()
	_expect(terrain.cell_count() == 17 and not terrain.has_cell(Vector2i(1, 0)), "流式 remove 未生效")
	var probe = TerrainScript.new()
	root.add_child(probe)
	probe.set_cell(Vector2i.ZERO, [{
		"level": 1, "texture": texture, "modulate": Color.WHITE,
		"render_offset": Vector2(0, -16), "occluder_class": &"none",
		"flora_species_id": "contract_flora",
	}], 1.0)
	probe.flush()
	var probe_chunk: Node3D = probe.get_child(0)
	_expect(probe_chunk.get_child_count() == 1 and probe_chunk.get_child(0) is MultiMeshInstance3D,
		"地被/flora 被错误生成为实心柱而非 billboard")
	# 植物遮挡淡化契约：注册、隐藏原实例、代理缓动、恢复、重建/移除清理。
	var fade_probe = TerrainScript.new()
	root.add_child(fade_probe)
	fade_probe.set_cell(Vector2i(0, 0), [{
		"level": 1, "texture": texture, "modulate": Color.WHITE,
		"render_offset": Vector2(0, -16),
		"flora_species_id": "contract_flora",
	}], 1.0)
	fade_probe.set_cell(Vector2i(1, 0), [{
		"level": 1, "texture": texture, "modulate": Color(1, 1, 1, 0.8),
		"render_offset": Vector2(0, -16),
		"flora_species_id": "contract_flora",
	}], 1.0)
	fade_probe.flush()
	var cell_a := Vector2i(0, 0)
	var cell_b := Vector2i(1, 0)
	_expect(fade_probe.get_prop_cells().size() == 2, "prop 实例注册表漏登记")
	var fade_data: Array = fade_probe.get_prop_block_occlusion_data(cell_a)
	_expect(fade_data.size() == 1 and (fade_data[0]["size_px"] as Vector2) == Vector2(32, 32),
		"prop 遮挡数据缺贴图尺寸")
	fade_probe.set_prop_fade_target(cell_a, 0.2)
	var fade_entries: Array = fade_probe.get_prop_block_occlusion_data(cell_a)
	# Godot 的 MultiMesh.get_instance_color 读回不可信（返回恒值），用 hidden 记账验证。
	_expect(fade_entries[0]["hidden"] == true, "淡化格原 multimesh 实例未被隐藏")
	var neighbor_entries: Array = fade_probe.get_prop_block_occlusion_data(cell_b)
	_expect(neighbor_entries[0]["hidden"] == false, "共享 multimesh 的其他植物实例被连带隐藏")
	var fade_layer: Node3D = fade_probe.get_node("PropFadeLayer")
	_expect(fade_layer.get_child_count() == 1, "淡化代理 Sprite3D 未创建")
	_expect(fade_probe.get_prop_fade_alpha(cell_a) == 1.0, "淡化起始透明度应为 1.0")
	fade_probe.advance_prop_fades(0.5)
	var proxy: Sprite3D = fade_layer.get_child(0)
	_expect(absf(fade_probe.get_prop_fade_alpha(cell_a) - 0.2) < 0.02, "淡出未在 0.5s 内逼近 0.2")
	_expect(absf(proxy.modulate.a - 0.2) < 0.02, "代理透明度未跟随缓动")
	fade_probe.set_prop_fade_target(cell_a, 1.0)
	for index in range(120):
		fade_probe.advance_prop_fades(1.0 / 30.0)
	_expect(fade_probe.get_prop_fade_alpha(cell_a) == 1.0, "恢复后透明度未回到 1.0")
	_expect(fade_entries[0]["hidden"] == false, "恢复后原实例未解除隐藏")
	await process_frame
	_expect(fade_layer.get_child_count() == 0, "恢复后代理 Sprite3D 未释放")
	# chunk 重建必须清理该格的注册与代理，不泄漏。
	fade_probe.set_prop_fade_target(cell_a, 0.2)
	fade_probe.set_cell(cell_a, [{
		"level": 1, "texture": texture, "modulate": Color.WHITE,
		"render_offset": Vector2(0, -16),
		"flora_species_id": "contract_flora",
	}], 1.0)
	fade_probe.flush()
	await process_frame
	_expect(fade_probe.get_prop_fade_alpha(cell_a) == 1.0, "chunk 重建后残留淡化状态")
	_expect(fade_probe.get_prop_cells().has(cell_a), "chunk 重建后 prop 注册表丢失")
	fade_probe.remove_cell(cell_b)
	fade_probe.flush()
	_expect(not fade_probe.get_prop_cells().has(cell_b), "remove_cell 未清理 prop 注册表")
	fade_probe.clear()
	_expect(fade_probe.get_prop_cells().is_empty(), "clear 未清空 prop 注册表")
	fade_probe.queue_free()
	await process_frame
	probe.clear()
	probe.set_cell(Vector2i.ZERO, [{
		"level": 6, "texture": texture, "modulate": Color(1, 1, 1, 0.6),
		"render_offset": Vector2.ZERO, "water_part": &"right_side",
	}], 6.0)
	probe.flush()
	var water_mesh: MeshInstance3D = probe.get_child(0).get_child(0)
	var water_vertices: PackedVector3Array = water_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_expect(water_vertices.size() == 6, "水侧壁仍多画了顶面或其他侧面")
	probe.clear()
	probe.set_cell(Vector2i.ZERO, [{
		"level": 1, "texture": texture, "modulate": Color.WHITE,
		"render_offset": Vector2.ZERO,
	}], 1.0)
	probe.flush()
	var solid_mesh: MeshInstance3D = probe.get_child(0).get_child(0)
	var solid_vertices: PackedVector3Array = solid_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_expect(solid_vertices.size() == 30, "实心柱必须包含一个顶面与四个真实侧面")
	probe.set_cell(Vector2i(2,3),[],6.0)
	probe.spawn_water_ripple(Vector2i(2,3),Vector2(0.25,-0.5),&"rain",1.0,32.0)
	probe._advance_water_ripples(1.0/30.0)
	var ripple_mesh:MultiMeshInstance3D=probe.get_node("WaterRipples")
	var ripple_origin:Vector3=probe._water_ripples[0]["position"]
	var expected_origin:=IsoProjection.visual_to_world(Vector2(2.25,2.5),6.0)+Vector3(0,0.004,0)
	_expect(ripple_origin.distance_to(expected_origin)<0.001,"ripple local offset actual=%s expected=%s" % [ripple_origin,expected_origin])
	for index in range(5):
		probe.spawn_water_ripple(Vector2i(2,3),Vector2.ZERO,&"rain",1.0,32.0)
	probe._advance_water_ripples(1.0/30.0)
	_expect(probe.active_water_ripple_count()==4,"per-cell ripple budget")
	for index in range(60):
		probe.set_cell(Vector2i(index,8),[],6.0)
		probe.spawn_water_ripple(Vector2i(index,8),Vector2.ZERO,&"rain",1.0,32.0)
	probe._advance_water_ripples(1.0/30.0)
	_expect(probe.active_water_ripple_count()==48,"global ripple budget")
	probe._advance_water_ripples(1.2)
	_expect(probe.active_water_ripple_count()==0 and probe._water_ripples.is_empty(),"ripple cleanup")
	probe.queue_free()
	_l1("projection/four-views/zoom/streaming checks completed; failures=%d" % failures.size())
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("ISOMETRIC_3D_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
			if OS.has_feature("l3"):
				breakpoint
		quit(1)
