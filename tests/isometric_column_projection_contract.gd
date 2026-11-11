extends SceneTree

## isometric_column_projection_contract.gd — 验证旋转地形的顶面拼缝、侧壁邻接与包围盒。

const ColumnBatchScript = preload("res://scripts/isometric_column_batch.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _texture() -> ImageTexture:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.4, 0.8, 0.3, 1.0))
	return ImageTexture.create_from_image(image)


func _run() -> void:
	var column := ColumnBatchScript.new()
	root.add_child(column)
	var blocks: Array[Dictionary] = [{
		"level": 0,
		"texture": _texture(),
		"modulate": Color.WHITE,
		"render_offset": Vector2.ZERO,
		"occluder_class": &"terrain",
	}]
	column.configure(Vector2i.ZERO, blocks, Vector2.ZERO, 0.0, 10.0)
	var default_corners: PackedVector2Array = column._terrain_top_corners(Vector2.ZERO)
	_expect(default_corners == PackedVector2Array([
		Vector2(0, -10), Vector2(16, -2), Vector2(0, 6), Vector2(-16, -2),
	]), "默认顶面角点必须保持原贴图布局")
	_expect(
		column._block_visual_rect(blocks[0]) == Rect2(-16, -16, 32, 32),
		"默认地形包围盒必须保持原32×32布局"
	)

	_expect(
		"screen_y_offset" not in ColumnBatchScript.PROJECTED_TERRAIN_SHADER.code,
		"共享旋转材质不得保存单列Y-sort偏移，偏移只能来自draw_mesh变换"
	)

	column.update_sort_position(
		Vector2(40, 200),
		1600.0,
		Vector2(16, 8).rotated(PI * 0.25),
		Vector2(-16, 8).rotated(PI * 0.25)
	)
	var visual_top_center := (
		Vector2(0, column._screen_y_offset) + ColumnBatchScript.TOP_CENTER_OFFSET
	)
	_expect(
		column._draw_cull_rect.has_point(visual_top_center),
		"Y-sort原点在视口外时，自定义剔除矩形仍必须覆盖draw_mesh的真实顶面位置"
	)

	for degrees in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
		var angle := deg_to_rad(degrees)
		var basis_x := Vector2(16, 8).rotated(angle)
		var basis_y := Vector2(-16, 8).rotated(angle)
		column.update_sort_position(Vector2.ZERO, 0.0, basis_x, basis_y)
		var corners: PackedVector2Array = column._terrain_top_corners(Vector2.ZERO)
		var plus_x: PackedVector2Array = column._terrain_top_corners(basis_x)
		var plus_y: PackedVector2Array = column._terrain_top_corners(basis_y)
		_expect(
			corners[1].is_equal_approx(plus_x[0]) and corners[2].is_equal_approx(plus_x[3]),
			"%.0f°：+x 同层方块必须共享完整边" % degrees
		)
		_expect(
			corners[2].is_equal_approx(plus_y[1]) and corners[3].is_equal_approx(plus_y[0]),
			"%.0f°：+y 同层方块必须共享完整边" % degrees
		)
		var minus_x: PackedVector2Array = column._terrain_top_corners(-basis_x)
		var minus_y: PackedVector2Array = column._terrain_top_corners(-basis_y)
		_expect(
			corners[0].is_equal_approx(minus_x[1]) and corners[3].is_equal_approx(minus_x[2]),
			"%.0f°：-x 同层方块必须共享完整边" % degrees
		)
		_expect(
			corners[0].is_equal_approx(minus_y[3]) and corners[1].is_equal_approx(minus_y[2]),
			"%.0f°：-y 同层方块必须共享完整边" % degrees
		)
		var extents := (basis_x.abs() + basis_y.abs()) * 0.5
		var expected_rect := Rect2(-16, -16, 32, 32)
		if not column._is_default_projection():
			expected_rect = Rect2(
				Vector2(0, -2) - extents,
				extents * 2.0 + Vector2(0, 10)
			)
		var actual_rect: Rect2 = column._block_visual_rect(blocks[0])
		_expect(
			actual_rect.position.is_equal_approx(expected_rect.position)
				and actual_rect.size.is_equal_approx(expected_rect.size),
			"%.0f°：旋转地形包围盒必须覆盖顶面与侧壁" % degrees
		)
		if degrees != 0.0:
			var sector := (1 if basis_x.y < 0.0 else 0) | (2 if basis_y.y < 0.0 else 0)
			var plan: Array = column._build_projected_draw_plan(sector)
			_expect(not plan.is_empty() and plan[0]["kind"] == &"mesh", "%.0f°：地形必须生成可见网格" % degrees)
			var mesh: ArrayMesh = plan[0]["mesh"]
			var arrays := mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var customs: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
			_expect(vertices.size() == 18, "%.0f°：一个完整地形块必须有两个侧面和一个顶面" % degrees)
			var expected_top := [corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]]
			for corner_index in 6:
				var vertex_index := 12 + corner_index
				var custom_offset := vertex_index * 4
				var center := Vector2(customs[custom_offset], customs[custom_offset + 1])
				var vertical := customs[custom_offset + 3]
				var source_vertex := vertices[vertex_index]
				var relative := Vector2(source_vertex.x, source_vertex.y) - center - Vector2(0, vertical)
				var transformed := center + relative.rotated(angle) + Vector2(0, vertical)
				_expect(
					transformed.is_equal_approx(expected_top[corner_index]),
					"%.0f°：GPU顶面顶点必须等于CPU投影角点" % degrees
				)
		column.queue_redraw()
		await process_frame

	var flat_neighbors := func(_neighbor: Vector2i) -> int: return 0
	column.configure(
		Vector2i.ZERO,
		blocks,
		Vector2.ZERO,
		0.0,
		10.0,
		ColumnBatchScript.DEFAULT_BASIS_X,
		ColumnBatchScript.DEFAULT_BASIS_Y,
		flat_neighbors
	)
	column.update_sort_position(
		Vector2.ZERO, 0.0, Vector2(16, 8).rotated(PI * 0.25), Vector2(-16, 8).rotated(PI * 0.25)
	)
	column.queue_redraw()
	await process_frame
	var plan: Array = column._projected_draw_plan_cache.get(column._projected_sector, [])
	var mesh_arrays: Array = plan[0]["mesh"].surface_get_arrays(0)
	_expect(
		mesh_arrays[Mesh.ARRAY_VERTEX].size() == 6,
		"平地四邻同层时必须只绘制顶面，不能暴露柱间内部侧面"
	)

	var stacked_blocks: Array[Dictionary] = [blocks[0].duplicate(), blocks[0].duplicate()]
	stacked_blocks[0]["level"] = 0
	stacked_blocks[1]["level"] = 6
	flat_neighbors = func(_neighbor: Vector2i) -> int: return 6
	column.configure(
		Vector2i.ZERO,
		stacked_blocks,
		Vector2.ZERO,
		0.0,
		10.0,
		ColumnBatchScript.DEFAULT_BASIS_X,
		ColumnBatchScript.DEFAULT_BASIS_Y,
		flat_neighbors
	)
	column.update_sort_position(
		Vector2.ZERO, 0.0, Vector2(16, 8).rotated(PI * 0.25), Vector2(-16, 8).rotated(PI * 0.25)
	)
	column.queue_redraw()
	await process_frame
	plan = column._projected_draw_plan_cache.get(column._projected_sector, [])
	mesh_arrays = plan[0]["mesh"].surface_get_arrays(0)
	_expect(
		mesh_arrays[Mesh.ARRAY_VERTEX].size() == 6,
		"多层平地柱只能绘制最上方顶面，柱内低层的顶面与侧面都必须剔除"
	)

	var low_neighbors := func(_neighbor: Vector2i) -> int: return 5
	column.configure(
		Vector2i.ZERO,
		stacked_blocks,
		Vector2.ZERO,
		0.0,
		10.0,
		ColumnBatchScript.DEFAULT_BASIS_X,
		ColumnBatchScript.DEFAULT_BASIS_Y,
		low_neighbors
	)
	column.update_sort_position(
		Vector2.ZERO, 0.0, Vector2(16, 8).rotated(PI * 0.25), Vector2(-16, 8).rotated(PI * 0.25)
	)
	column.queue_redraw()
	await process_frame
	plan = column._projected_draw_plan_cache.get(column._projected_sector, [])
	mesh_arrays = plan[0]["mesh"].surface_get_arrays(0)
	_expect(
		mesh_arrays[Mesh.ARRAY_VERTEX].size() == 18,
		"多层柱在低邻格方向只暴露最高方块的外侧壁，隐藏更低内部面"
	)

	column.queue_free()
	await process_frame
	if _failures.is_empty():
		print("ISOMETRIC_COLUMN_PROJECTION_CONTRACT_OK")
		quit(0)
	else:
		push_error("ISOMETRIC_COLUMN_PROJECTION_CONTRACT_FAILED: %d" % _failures.size())
		quit(1)
