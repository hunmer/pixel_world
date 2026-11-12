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

	var viewport_center: Vector2 = world.get_viewport_rect().size * 0.5
	world._cam.zoom = 2.0
	for i in mini(12, samples.size()):
		var cell := samples[i]
		var center: Vector2 = world._grid_to_screen(cell, float(world.cell_stand_level(cell)))
		world._cam.focus_position = IsoProjection.grid_to_world(cell, float(world.cell_stand_level(cell)))
		var picked: Vector2i = world.screen_to_cell(viewport_center)
		if picked != cell:
			push_error("战旗高地拾取偏移: cell=%s picked=%s level=%d" % [
				str(cell), str(picked), world.cell_stand_level(cell)
			])
			quit(1)
			return
		var rect_picked: Vector2i = world.screen_to_cell_in_rect(
			viewport_center,
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
