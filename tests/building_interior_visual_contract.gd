## building_interior_visual_contract.gd — 房屋实际四向外观、剖面几何及缩放滞回。
extends SceneTree
const Renderer = preload("res://scripts/iso/battlefield_renderer.gd")
const Adapter = preload("res://scripts/assets/user_asset_visual_adapter.gd")
const Camera = preload("res://scripts/iso/isometric_camera_3d.gd")
const House = preload("res://scripts/assets/builtin_house_assets.gd")
const Interior = preload("res://scripts/core/building_interior.gd")
const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _run() -> void:
	var camera := Camera.new()
	root.add_child(camera)
	camera.zoom = 1.0
	await process_frame
	var renderer := Renderer.new()
	root.add_child(renderer)
	renderer.set_process(false)
	var descriptor: Dictionary = House.snapshot()
	var id: String = descriptor["id"]
	var adapter := Adapter.new("user://tmp/interior_visual_empty")
	var map: Array = []
	for y in 12:
		var row: Array = []
		for x in 12:
			row.append(&"plain")
		map.append(row)
	var grid := GridSystem.new(12, 12, map)
	var origin := Vector2i(2, 2)
	for rotation in 4:
		var entry := {"instance_id": "home", "asset_id": id, "x": origin.x, "y": origin.y, "rotation": rotation}
		var visuals: Array = adapter.visual_for_buildings([entry], {id: descriptor})
		_expect(visuals[0]["visual"]["interior"] == House.INTERIOR, "四向%d适配器完整保留室内数据" % rotation)
		renderer.set_building_visuals(visuals, false)
		renderer.setup(grid)
		camera.zoom = 1.0
		renderer._process(0.016)
		_expect(renderer.interior_revealed_count == 0 and renderer._interior_view.visible_room_count == 0, "四向%d远景隐藏室内" % rotation)
		_expect(renderer._terrain_3d.get_prop_block_occlusion_data(origin).size() == 1, "四向%d远景真实外观存在" % rotation)
		camera.zoom = 1.8
		renderer._process(0.016)
		_expect(renderer.interior_revealed_count == 1 and renderer._interior_view.visible_room_count == 1, "四向%d阈值展开室内" % rotation)
		_expect(renderer._terrain_3d.get_prop_block_occlusion_data(origin).is_empty(), "四向%d近景移除外壳且不残留遮挡代理" % rotation)
		var room: Node3D = renderer._interior_view._rooms["home"]
		var doors: Array[Vector2i] = []
		var walls := 0
		var tables := 0
		for mesh: MeshInstance3D in room.get_children():
			var cell: Vector2i = mesh.get_meta("cell")
			if mesh.get_meta("kind") == "Door":
				doors.append(cell)
			if mesh.get_meta("kind") == "Wall":
				walls += 1
			if mesh.get_meta("kind") == "Furniture":
				tables += 1
			if mesh.get_meta("kind") in ["Door", "Floor"]:
				var base: Vector3 = IsoProjection.grid_to_world(cell, renderer.visual_top_level(cell.x, cell.y))
				_expect(mesh.position.distance_to(base + Vector3(0, 0.006, 0)) < 0.0001, "真实地板贴当前格柱顶而非高一层")
		_expect(doors.size() == 2 and doors.has(Interior.cell_at(entry, Vector2i(2, 5), Vector2i(6, 6))) and doors.has(Interior.cell_at(entry, Vector2i(3, 5), Vector2i(6, 6))), "四向%d门与逻辑旋转格一致" % rotation)
		_expect(walls == 18 and tables == 1, "四向%d生成真实低墙与桌子" % rotation)
		for quadrant in 4:
			camera.snap_to_angle(45.0 + quadrant * 90.0)
			renderer.set_camera_quadrant(quadrant)
			renderer._process(0.016)
			_expect(renderer._terrain_3d.get_prop_block_occlusion_data(origin).is_empty() and room.visible, "相机%d旋转%d室内不被外观重新覆盖" % [quadrant, rotation])
		camera.zoom = 1.65
		renderer._process(0.016)
		_expect(renderer.interior_revealed_count == 1, "缓冲区内保持展开")
		renderer.rebuild_all()
		renderer._process(0.016)
		_expect(renderer._interior_view.visible_room_count == 1, "整图重建恢复剖面状态")
		camera.zoom = 1.5
		renderer._process(0.016)
		_expect(renderer.interior_revealed_count == 0 and renderer._terrain_3d.get_prop_block_occlusion_data(origin).size() == 1, "缩小至关闭阈值恢复整栋外观")
		camera.zoom = 1.65
		renderer._process(0.016)
		_expect(renderer.interior_revealed_count == 0, "缓冲区内保持外观不闪烁")
		_expect(descriptor["render"]["interior"] == House.INTERIOR, "镜头切换不修改素材快照")
	renderer.set_building_visuals([], true)
	renderer._process(0.016)
	_expect(renderer._interior_view.room_count == 0, "删除建筑清除室内几何")
	renderer.queue_free()
	camera.queue_free()
	await process_frame
	print("BUILDING_INTERIOR_VISUAL %s checks=%d" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
