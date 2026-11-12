extends SceneTree

const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	world.seed = 42
	root.add_child(world)
	await process_frame
	world.set_process(false)

	var samples: Array[Vector2i] = []
	for y in range(-24, 25, 3):
		for x in range(-24, 25, 3):
			var cell := Vector2i(x, y)
			if world._quantize(x, y) > world.WATER_MAX:
				samples.append(cell)
	samples.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return world.cell_stand_level(a) > world.cell_stand_level(b)
	)

	world._cam.zoom = 2.0
	for i in mini(12, samples.size()):
		var cell := samples[i]
		world._cam.focus_position = IsoProjection.grid_to_world(cell, float(world.cell_stand_level(cell)))
		# 侧栏会平移正交相机；点击目标的真实投影中心，而非窗口几何中心。
		var center: Vector2 = world._grid_to_screen(cell, float(world.cell_stand_level(cell)))
		var picked: Vector2i = world.screen_to_cell(center)
		if picked != cell:
			var hit := IsoProjection.pick_top_face(
				world._cam, center, 0, world.LEVELS * 3 - 1,
				Callable(world, "cell_stand_level")
			)
			push_error("战旗高地拾取偏移: cell=%s picked=%s level=%d picked_level=%d hit=%s" % [
				str(cell), str(picked), world.cell_stand_level(cell),
				world.cell_stand_level(picked), str(hit)
			])
			quit(1)
			return
		var rect_picked: Vector2i = world.screen_to_cell_in_rect(
			center,
			cell - Vector2i(10, 10),
			Vector2i(21, 21)
		)
		if rect_picked != cell:
			push_error("战旗范围拾取偏移: cell=%s picked=%s level=%d" % [
				str(cell), str(rect_picked), world.cell_stand_level(cell)
			])
			quit(1)
			return

	print("BATTLE_SCREEN_PICK_CONTRACT_OK")
	quit(0)
