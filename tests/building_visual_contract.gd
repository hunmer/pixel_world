## tests/building_visual_contract.gd — 建筑烘焙、前/背图、单实例占地与素材面板契约
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
	var front_image := _solid_image(100, 50, Color(0.8, 0.3, 0.2, 1.0))
	var back_image := _solid_image(80, 60, Color(0.2, 0.4, 0.9, 1.0))
	front_image.save_png(tmp_root + "/front.png")
	back_image.save_png(tmp_root + "/back.png")

	var service := ServiceScript.new(tmp_root)
	service.remote_enabled = false
	root.add_child(service)
	var adapter := AdapterScript.new(tmp_root)
	var front_result: Dictionary = service.import_local_file(tmp_root + "/front.png", "building")
	var back_result: Dictionary = service.import_local_file(tmp_root + "/back.png", "building")
	_expect(bool(front_result.get("ok", false)) and bool(back_result.get("ok", false)),
		"两幅建筑素材可导入独立临时库")
	if not bool(front_result.get("ok", false)) or not bool(back_result.get("ok", false)):
		_finish(tmp_root)
		return
	var front_id := String(front_result.get("asset_id", ""))
	var back_id := String(back_result.get("asset_id", ""))
	var front_descriptor: Dictionary = service.find_by_id(front_id)
	var back_descriptor: Dictionary = service.find_by_id(back_id)

	# 素材面板：真实 service + adapter，验证 building 控件最终落到持久化 descriptor。
	var panel := PanelScript.new()
	root.add_child(panel)
	panel.setup(service, adapter)
	panel._selected_id = front_id
	panel._fill_detail(front_descriptor)
	_expect(panel._ground_width_row.visible and panel._back_mode_row.visible,
		"建筑详情显示底座宽与前/背图配置")
	_expect(panel._back_mode_option.item_count == 2 and panel._kind_filter.item_count == 3,
		"图向含 single/front_back，分类含建筑")
	panel._fp_w.value = 2
	panel._fp_h.value = 3
	panel._pivot_x.value = 0.25
	panel._pivot_y.value = 0.75
	panel._ground_width_box.value = 50.0
	panel._back_mode_option.select(1)
	panel._on_back_mode_selected(1)
	var selected_back := -1
	for index in panel._back_asset_option.item_count:
		if String(panel._back_asset_option.get_item_metadata(index)) == back_id:
			selected_back = index
			panel._back_asset_option.select(index)
	_expect(selected_back >= 0 and panel._back_asset_row.visible,
		"front_back 模式可选择库内另一建筑背图")
	panel._on_apply_pressed()
	front_descriptor = service.find_by_id(front_id)
	var render: Dictionary = front_descriptor.get("render", {})
	_expect(int((render.get("footprint", {}) as Dictionary).get("w", 0)) == 2
		and int((render.get("footprint", {}) as Dictionary).get("h", 0)) == 3,
		"面板保存 2x3 占地")
	_expect(String(render.get("back_mode", "")) == "front_back"
		and String(render.get("back_asset_id", "")) == back_id
		and is_equal_approx(float(render.get("ground_width_px", 0.0)), 50.0),
		"面板保存背图引用与底座宽")
	_expect(is_equal_approx(float((render.get("pivot", {}) as Dictionary).get("x", 0.0)), 0.25)
		and is_equal_approx(float((render.get("pivot", {}) as Dictionary).get("y", 0.0)), 0.75),
		"面板保存建筑底座中心 pivot")

	# 烘焙：目标宽 16*(2+3)=80；ground_width=50 时 100x50 → 160x80。
	var baked := adapter.bake_image(front_descriptor, front_image)
	_expect(baked.get_width() == 160 and baked.get_height() == 80,
		"建筑按 ground_width_px 等比标定，不限制高度")
	var visual := adapter.build_visual(front_descriptor, front_image)
	_expect((visual.get("canvas_size", Vector2.ZERO) as Vector2) == Vector2(160, 80)
		and (visual.get("render_offset", Vector2.ZERO) as Vector2).distance_to(Vector2(40, -20)) < 0.001,
		"建筑 pivot 按烘焙后 alpha 内容盒计算")
	var automatic := front_descriptor.duplicate(true)
	(automatic["render"] as Dictionary)["ground_width_px"] = 0.0
	var automatic_baked := adapter.bake_image(automatic, front_image)
	_expect(automatic_baked.get_width() == 80 and automatic_baked.get_height() == 40,
		"ground_width_px=0 自动按内容宽标定")

	var snapshots := {front_id: front_descriptor, back_id: back_descriptor}
	var entries: Array = adapter.visual_for_buildings([{
		"instance_id": "tower_1", "asset_id": front_id,
		"x": 1, "y": 1, "rotation": 1,
	}], snapshots)
	_expect(entries.size() == 1 and not (entries[0] as Dictionary).get("back_visual", {}).is_empty(),
		"visual_for_buildings 输出单实例及依赖背图")
	if entries.is_empty():
		_finish(tmp_root)
		return
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
	var initial_back: Dictionary = (entries[0] as Dictionary)["back_visual"]
	var initial_offset: Vector2 = initial_back.get("render_offset", Vector2.ZERO)
	_expect((initial_building.get("render_offset", Vector2.ZERO) as Vector2).distance_to(initial_offset) < 0.001,
		"首次 3D setup 不混入 2D 占地中心/TOP_CENTER 偏移")
	_expect((initial_building.get("grid_anchor", Vector2.ZERO) as Vector2).distance_to(Vector2(2.0, 1.5)) < 0.001,
		"rotation=1 交换占地并锚定旋转后包围矩形中心")
	_expect(_building_block(renderer, Vector2i(2, 1)).is_empty()
		and _building_block(renderer, Vector2i(1, 2)).is_empty(),
		"多格占地不逐格复制建筑")

	# rotation=1：相机 0/1/2/3 的相对象限 3/0/1/2 → 背/前/前/背。
	var expected_ids := [back_id, front_id, front_id, back_id]
	for quadrant in 4:
		renderer.set_camera_quadrant(quadrant)
		var block := _building_block(renderer, origin)
		_expect(String(block.get("asset_id", "")) == String(expected_ids[quadrant]),
			"相机象限 %d 实际切换正确前/背图 asset_id" % quadrant)
		_expect((block.get("grid_anchor", Vector2.ZERO) as Vector2).distance_to(Vector2(2.0, 1.5)) < 0.001,
			"相机象限 %d 不改变占地锚点" % quadrant)

	var single_entries: Array = entries.duplicate(true)
	((single_entries[0] as Dictionary)["visual"] as Dictionary)["back_mode"] = "single"
	renderer.set_building_visuals(single_entries)
	renderer.set_camera_quadrant(0)
	_expect(String(_building_block(renderer, origin).get("asset_id", "")) == front_id,
		"single 分类在背面象限仍显示正面")

	# 缺前图仍保留配置，可在背面象限显示有效背图；缺背图则回退前图。
	var missing_front := front_descriptor.duplicate(true)
	missing_front["sha256"] = "0".repeat(64)
	var missing_entries: Array = adapter.visual_for_buildings([{
		"instance_id": "tower_1", "asset_id": front_id,
		"x": 1, "y": 1, "rotation": 1,
	}], {front_id: missing_front, back_id: back_descriptor})
	_expect(not missing_entries.is_empty()
		and bool(((missing_entries[0] as Dictionary)["visual"] as Dictionary).get("missing", false))
		and not ((missing_entries[0] as Dictionary)["back_visual"] as Dictionary).is_empty(),
		"缺前图占位仍保留 front_back 元数据与背图")
	renderer.set_building_visuals(missing_entries)
	renderer.set_camera_quadrant(0)
	_expect(String(_building_block(renderer, origin).get("asset_id", "")) == back_id,
		"缺前图时背面象限仍可使用背图")
	var missing_back := back_descriptor.duplicate(true)
	missing_back["sha256"] = "f".repeat(64)
	var fallback_entries: Array = adapter.visual_for_buildings([{
		"instance_id": "tower_1", "asset_id": front_id,
		"x": 1, "y": 1, "rotation": 1,
	}], {front_id: front_descriptor, back_id: missing_back})
	renderer.set_building_visuals(fallback_entries)
	renderer.set_camera_quadrant(0)
	_expect(String(_building_block(renderer, origin).get("asset_id", "")) == front_id,
		"缺背图时背面象限回退前图")

	# 真实正交 Camera3D 数值验收：非 0.5 pivot 的屏幕偏移四向保持一致。
	renderer.set_building_visuals(entries)
	var terrain := Terrain3DScript.new()
	var projection_ok := true
	var depth_ok := true
	for quadrant in 4:
		renderer.set_camera_quadrant(quadrant)
		camera.snap_to_angle(45.0 + float(quadrant) * 90.0)
		var block := _building_block(renderer, origin)
		var selected_visual: Dictionary = (entries[0] as Dictionary)["visual"]
		if String(block.get("asset_id", "")) == back_id:
			selected_visual = (entries[0] as Dictionary)["back_visual"]
		var offset: Vector2 = selected_visual.get("render_offset", Vector2.ZERO)
		var anchor := IsoProjection.visual_to_world(
			block.get("grid_anchor", Vector2.ZERO) as Vector2, float(block.get("level", 0)))
		var right: Vector3 = block.get("camera_right", Vector3.ZERO)
		var center := anchor + terrain._screen_offset_world(offset, right)
		var delta := camera.unproject_position(center) - camera.unproject_position(anchor)
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
	_expect(String(_building_block(canvas._renderer, Vector2i(1, 1)).get("asset_id", "")) == back_id,
		"EditorCanvas 相机旋转实际刷新悬停预览背图")
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
