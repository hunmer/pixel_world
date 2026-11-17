## tests/building_visual_contract.gd — 建筑四帧烘焙、方向选择、单实例占地与素材面板契约
## 跑法：godot --headless --path . --script res://tests/building_visual_contract.gd
## 无数值截图：只检查像素尺寸、渲染 blocks 与 Camera3D 投影数值。
extends SceneTree

const AdapterScript = preload("res://scripts/assets/user_asset_visual_adapter.gd")
const ServiceScript = preload("res://scripts/assets/user_asset_service.gd")
const PanelScript = preload("res://scripts/editor/asset_library_panel.gd")
const RendererScript = preload("res://scripts/iso/battlefield_renderer.gd")
const Terrain3DScript = preload("res://scripts/iso/isometric_terrain_3d.gd")
const CameraScript = preload("res://scripts/iso/isometric_camera_3d.gd")
const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
const EditorCanvasScript = preload("res://scripts/editor/editor_canvas.gd")
const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok: %s" % message)
	else:
		failures += 1
		printerr("  FAIL: %s" % message)


func _solid_image(width: int, height: int, color: Color) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _make_grid() -> GridSystem:
	var map: Array = []
	for y in 4:
		var row: Array = []
		for x in 4:
			row.append(&"plain")
		map.append(row)
	return GridSystem.new(4, 4, map)


func _building_block(renderer: Node2D, cell: Vector2i) -> Dictionary:
	for raw in renderer.cell_blocks_snapshot(cell):
		if raw is Dictionary and bool((raw as Dictionary).get("building", false)):
			return raw
	return {}


func _run() -> void:
	print("== building_visual_contract ==")
	var tmp_root := "user://tmp/building_visual_contract_%d" % OS.get_process_id()
	_remove_recursive(tmp_root)
	DirAccess.make_dir_recursive_absolute(tmp_root)
	var colors: Array[Color] = [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW]
	var sheet := Image.create(400, 100, false, Image.FORMAT_RGBA8)
	for direction: int in 4:
		sheet.fill_rect(Rect2i(direction * 100, 0, 100, 100), colors[direction])
	sheet.save_png(tmp_root + "/sheet.png")
	var service := ServiceScript.new(tmp_root)
	service.remote_enabled = false
	root.add_child(service)
	var adapter := AdapterScript.new(tmp_root)
	# 发货示例在未注册用户库、没有内容 blob 时也能直接解析工程内原始 sheet。
	var demo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/battlefields/building_demo.json"))
	var builtin: Dictionary = (demo["user_assets"] as Dictionary).values()[0]
	var builtin_visual: Dictionary = adapter.resolve_snapshot(builtin)
	_expect(not bool(builtin_visual.get("missing", true)) and builtin_visual.get("directions", []).size() == 4,
		"内置示例在空素材库中离线读取原图并拆成四方向")
	var builtin_frames: Array = builtin_visual.get("directions", [])
	for direction: int in builtin_frames.size():
		var frame: Dictionary = builtin_frames[direction]
		var size: Vector2 = frame["canvas_size"]
		var texture: Texture2D = frame["texture"]
		_expect(texture.get_size() == Vector2(512, 512), "真实dir_%d保留512px源纹理" % direction)
		_expect(absf(float(frame["display_scale"]) * 232.44195804706033 - 64.0) < 0.0001,
			"真实dir_%d底座显示宽度仍为64px" % direction)
		# CLI投影地基中心 (259.49485,416.90407) 应投影到占地中心，容许最近邻缩放的1px误差。
		var ground_in_texture := Vector2(259.4948508540325, 416.9040716792189) * size.y / 512.0
		var ground_from_anchor: Vector2 = ground_in_texture - size * 0.5 + frame["render_offset"]
		_expect(ground_from_anchor.length() <= 1.0, "真实dir_%d地面中心与占地锚点误差不超过1px，实际%s" % [direction, ground_from_anchor])
	var old_builtin: Dictionary = builtin.duplicate(true)
	old_builtin["render"]["pivot"] = {"x": 0.5, "y": 0.87}
	old_builtin["render"].erase("pivot_space")
	var corrected: Dictionary = adapter.resolve_snapshot(old_builtin)
	_expect(corrected["directions"][0]["render_offset"] == builtin_frames[0]["render_offset"], "旧地图默认快照自动纠正锚点")
	_expect(old_builtin["render"]["pivot"] == {"x": 0.5, "y": 0.87}, "渲染修复不修改原地图数据")
	var imported: Dictionary = service.import_local_file(tmp_root + "/sheet.png", "building")
	_expect(bool(imported.get("ok", false)), "横排四帧建筑可导入")
	if not bool(imported.get("ok", false)):
		_finish(tmp_root)
		return
	var front_id: String = String(imported.get("asset_id", ""))
	var descriptor: Dictionary = service.find_by_id(front_id)
	var panel := PanelScript.new()
	root.add_child(panel)
	panel.setup(service, adapter)
	var frame_render: Dictionary = descriptor["render"].duplicate(true)
	frame_render["pivot_space"] = "frame"
	service.update_asset(front_id, {"render": frame_render})
	descriptor = service.find_by_id(front_id)
	panel._selected_id = front_id
	panel._fill_detail(descriptor)
	panel._fp_w.value = 2
	panel._fp_h.value = 3
	panel._pivot_x.value = 0.25
	panel._pivot_y.value = 0.75
	panel._ground_width_box.value = 50.0
	panel._on_apply_pressed()
	descriptor = service.find_by_id(front_id)
	_expect(descriptor["render"].get("pivot_space", "") == "frame", "素材面板保存后保留单帧画布坐标系")
	_expect(String(descriptor.get("render", {}).get("direction_mode", "")) == "four_directions", "面板保存四方向模式")
	var baked: Image = adapter.bake_image(descriptor, sheet)
	_expect(baked.get_size() == sheet.get_size() and baked.get_data() == sheet.get_data(), "建筑烘焙保留原始尺寸与全部像素，不预先重采样")
	var visual: Dictionary = adapter.build_visual(descriptor, sheet)
	var frames: Array = visual.get("directions", [])
	_expect(frames.size() == 4, "烘焙输出四个独立方向")
	for direction: int in 4:
		var texture: Texture2D = frames[direction].get("texture")
		_expect(texture.get_image().get_pixel(80, 80).is_equal_approx(colors[direction]), "dir_%d 精确对应横排第%d帧" % [direction, direction])
		_expect((frames[direction].get("render_offset", Vector2.ZERO) as Vector2).distance_to(Vector2(40, -40)) < 0.001, "dir_%d pivot 按单帧内容计算" % direction)
	var detailed: Image = sheet.duplicate()
	for x: int in 100:
		detailed.set_pixel(x, 50, Color.WHITE if x % 2 == 0 else Color.BLACK)
	var tiny: Dictionary = descriptor.duplicate(true)
	tiny["render"]["ground_width_px"] = 500.0
	var sharp: Dictionary = adapter.build_visual(tiny, detailed)
	var sharp_image: Image = sharp["directions"][0]["texture"].get_image()
	_expect(sharp_image.get_width() == 100 and sharp_image.get_pixel(50, 50) == Color.WHITE
		and sharp_image.get_pixel(51, 50) == Color.BLACK, "缩小显示仍保留相邻1px细节供镜头放大采样")
	var snapshots: Dictionary = {front_id: descriptor}
	var entries: Array = adapter.visual_for_buildings([{
		"instance_id": "tower_1", "asset_id": front_id, "x": 1, "y": 1, "rotation": 1,
	}], snapshots)
	_expect(entries.size() == 1 and not entries[0].has("back_visual"), "单实例自包含四方向，无背图依赖")
	var legacy: Dictionary = descriptor.duplicate(true)
	legacy["render"].erase("direction_mode")
	_expect(adapter.visual_for_buildings([{"asset_id": front_id, "x": 0, "y": 0}], {front_id: legacy}).is_empty(), "旧单图建筑不进入渲染通路")
	var camera := CameraScript.new()
	root.add_child(camera)
	await process_frame
	var renderer := RendererScript.new()
	root.add_child(renderer)
	renderer.set_building_visuals(entries, false)
	renderer.setup(_make_grid())
	var origin := Vector2i(1, 1)
	var initial_blocks: Array = renderer.cell_blocks_snapshot(origin)
	var initial_building := _building_block(renderer, origin)
	_expect(initial_blocks.size() > 1 and not initial_building.is_empty(),
		"建筑追加到 origin 列且保留原地形 blocks")
	_expect(renderer._terrain_3d != null, "相机先于 setup 存在时建筑进入真实 3D 通路")
	var initial_offset: Vector2 = frames[3].get("render_offset", Vector2.ZERO)
	_expect((initial_building.get("render_offset", Vector2.ZERO) as Vector2).distance_to(initial_offset) < 0.001,
		"首次3D setup不混入2D占地中心偏移")
	_expect((initial_building.get("grid_anchor", Vector2.ZERO) as Vector2).distance_to(Vector2(2.0, 1.5)) < 0.001,
		"rotation=1交换占地并锚定包围矩形中心")
	_expect(_building_block(renderer, Vector2i(2, 1)).is_empty(), "多格占地只绘制一栋建筑")
	for rotation: int in 4:
		entries[0]["rotation"] = rotation
		renderer.set_building_visuals(entries)
		for quadrant: int in 4:
			renderer.set_camera_quadrant(quadrant)
			var block: Dictionary = _building_block(renderer, origin)
			var expected: int = posmod(quadrant - rotation, 4)
			var texture: Texture2D = block.get("texture")
			_expect(int(block.get("building_direction", -1)) == expected and texture.get_image().get_pixel(0, 0).is_equal_approx(colors[expected]),
				"相机%d/旋转%d正确选择dir_%d像素" % [quadrant, rotation, expected])
	entries[0]["rotation"] = 1
	var missing: Dictionary = descriptor.duplicate(true)
	missing["sha256"] = "0".repeat(64)
	var missing_entries: Array = adapter.visual_for_buildings([{"asset_id": front_id, "x": 1, "y": 1}], {front_id: missing})
	_expect(missing_entries.size() == 1 and missing_entries[0]["visual"]["directions"].size() == 4, "缺失sheet四方向均保留占位和占地")
	# 真实正交 Camera3D 数值验收：非 0.5 pivot 的屏幕偏移四向保持一致。
	renderer.set_building_visuals(entries)
	var terrain := Terrain3DScript.new()
	var projection_ok := true
	var depth_ok := true
	for quadrant in 4:
		renderer.set_camera_quadrant(quadrant)
		camera.snap_to_angle(45.0 + float(quadrant) * 90.0)
		var block := _building_block(renderer, origin)
		var selected_visual: Dictionary = frames[posmod(quadrant - 1, 4)]
		var offset: Vector2 = selected_visual.get("render_offset", Vector2.ZERO)
		var anchor := IsoProjection.visual_to_world(
			block.get("grid_anchor", Vector2.ZERO) as Vector2, float(block.get("level", 0)))
		var right: Vector3 = block.get("camera_right", Vector3.ZERO)
		var center := anchor + terrain._screen_offset_world(offset, right)
		var delta := camera.unproject_position(center) - camera.unproject_position(anchor)
		var texture: Texture2D = selected_visual["texture"]
		var shifted := center + terrain._building_depth_offset(texture, center, anchor, right, float(selected_visual["display_scale"]))
		_expect(camera.unproject_position(shifted).distance_to(camera.unproject_position(center)) < 0.01,
			"象限%d深度修正不移动屏幕锚点" % quadrant)
		var bottom_px := float(texture.get_image().get_used_rect().end.y) - float(texture.get_height()) * 0.5
		_expect(shifted.y - bottom_px * float(selected_visual["display_scale"]) / 32.0 * cos(IsoProjection.CAMERA_ELEVATION) >= anchor.y,
			"象限%d底座全部不透明像素位于地面上方" % quadrant)
		var props: Dictionary = {}
		terrain._append_prop(props, origin, block)
		var actual_center: Vector3 = props.values()[0]["metas"][0]["center"]
		_expect(actual_center.distance_to(shifted) < 0.0001, "象限%d实际渲染路径应用深度修正" % quadrant)
		var chunk := Node3D.new()
		terrain._commit_prop_group(chunk, props.values()[0])
		var mesh_instance: MultiMeshInstance3D = chunk.get_child(0)
		var quad: QuadMesh = mesh_instance.multimesh.mesh
		_expect(quad.size.distance_to(selected_visual["canvas_size"] / 32.0) < 0.0001,
			"象限%d完整源纹理的实际quad尺寸与标定一致" % quadrant)
		var proxy: Sprite3D = terrain._make_prop_proxy(terrain._prop_instances[origin].back())
		_expect(absf(proxy.pixel_size * 32.0 - float(selected_visual["display_scale"])) < 0.0001,
			"象限%d遮挡淡化代理继承同一显示比例" % quadrant)
		proxy.free()
		chunk.free()
		if delta.distance_to(offset * camera.zoom) > 0.05:
			projection_ok = false
		if absf(right.dot(-camera.global_transform.basis.z)) > 0.0001:
			depth_ok = false
	_expect(projection_ok, "四向建筑 pivot 屏幕位移恒等于 render_offset*zoom（含 x≠0）")
	_expect(depth_ok, "建筑 camera_right 四向均与相机前向正交，不引入横向深度漂移")
	var legacy_offset: Vector3 = terrain._screen_offset_world(Vector2(7, -11))
	var legacy_expected := Vector3(IsoProjection.GRID_STEP, 0, -IsoProjection.GRID_STEP) * (7.0 / 32.0)
	legacy_expected += Vector3.UP * (11.0 / (32.0 * cos(IsoProjection.CAMERA_ELEVATION)))
	_expect(legacy_offset.distance_to(legacy_expected) < 0.0001,
		"旧 flora 未传 camera_right 时固定屏幕轴保持不变")
	terrain.free()

	# 实际 EditorCanvas：悬停预览必须进入共享 renderer，旋转/清屏/模型重建都刷新真实 blocks。
	renderer.queue_free()
	camera.queue_free()
	await process_frame
	var canvas := EditorCanvasScript.new()
	canvas.asset_adapter = adapter
	root.add_child(canvas)
	await process_frame
	var document: Dictionary = BattlefieldDocScript.create_empty(4, 4)
	document["user_assets"] = snapshots
	(document["units"] as Array).append({
		"class": "warrior", "name": "旧职业占位", "level": 1,
		"x": 3, "y": 3, "faction": "player",
	})
	canvas.model = document
	_expect(canvas._unit_markers.size() == 1
		and String(document["units"][0]["class"]) == "warrior",
		"EditorCanvas 未知职业保留文档数据且只生成一个单位标记")
	if canvas._unit_markers.size() == 1:
		var marker: UnitSprite3D = canvas._unit_markers[0]
		_expect(marker.portrait != null and marker.unit["classId"] == &"swordsman",
			"EditorCanvas 无立绘旧职业仅在显示层回退 swordsman，避免 portrait Nil")
	canvas.set_building_preview(front_id, Vector2i(1, 1), 0)
	var preview_block := _building_block(canvas._renderer, Vector2i(1, 1))
	_expect(String(preview_block.get("building_instance_id", "")) == "__building_preview__"
		and String(preview_block.get("asset_id", "")) == front_id
		and canvas.asset_preview_visual.is_empty(),
		"EditorCanvas 建筑悬停预览实际写入 3D blocks，无双份 2D 预览")
	canvas.rotate_view(1)
	canvas.rotate_view(1)
	_expect(int(_building_block(canvas._renderer, Vector2i(1, 1)).get("building_direction", -1)) == 2,
		"EditorCanvas 相机旋转实际刷新悬停预览方向帧")
	canvas.clear_building_preview()
	_expect(_building_block(canvas._renderer, Vector2i(1, 1)).is_empty()
		and canvas._renderer.building_visuals_snapshot().is_empty(),
		"EditorCanvas 清除预览立即移除建筑 block 且保留地形")
	canvas.set_building_preview(front_id, Vector2i(0, 1), 0)
	canvas.model = document
	_expect(String(_building_block(canvas._renderer, Vector2i(0, 1)).get("building_instance_id", "")) == "__building_preview__",
		"EditorCanvas 整图 model 重建后仍按当前悬停重注入预览")
	canvas.clear_building_preview()

	_finish(tmp_root)


func _finish(tmp_root: String) -> void:
	for child in root.get_children():
		child.queue_free()
	await process_frame
	_remove_recursive(tmp_root)
	print("== building_visual_contract: %s ==" % ("PASS" if failures == 0 else "FAIL %d" % failures))
	quit(0 if failures == 0 else 1)


func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := path + "/" + entry
			if dir.current_is_dir():
				_remove_recursive(child)
			else:
				DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
