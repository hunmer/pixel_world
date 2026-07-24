extends SceneTree

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	world.seed = 42
	root.add_child(world)
	await process_frame
	world.set_process(false)

	_expect(
		world._cell_states.size() == world._cells.size(),
		"每个流式渲染格都必须有且只有一个逻辑 CellState"
	)
	var ground_cover_cell := Vector2i(1000000, 1000000)
	var blocking_cell := Vector2i(1000000, 1000000)
	var water_cell := Vector2i(1000000, 1000000)
	for cell_value in world._cell_states:
		var cell: Vector2i = cell_value
		var state = world._cell_states[cell]
		_expect(state.static_objects.size() <= 1, "同格静态对象冲突没有被消解: %s" % cell)
		if state.context.is_water and water_cell.x == 1000000:
			water_cell = cell
		if state.static_objects.is_empty():
			continue
		var object_data: Dictionary = state.static_objects[0]
		if (
			String(object_data.get("layer", "")) == "ground_cover"
			and not state.blocks_movement()
			and ground_cover_cell.x == 1000000
		):
			ground_cover_cell = cell
		if state.blocks_movement() and blocking_cell.x == 1000000:
			blocking_cell = cell

	_expect(ground_cover_cell.x < 1000000, "seed 42 视窗没有找到可通行地被样本")
	_expect(blocking_cell.x < 1000000, "seed 42 视窗没有找到树木或装饰阻挡样本")
	_expect(water_cell.x < 1000000, "seed 42 视窗没有找到水格样本")

	if ground_cover_cell.x < 1000000:
		var ground_state = world._cell_states[ground_cover_cell]
		_expect(
			not ground_state.can_spawn_fauna(false, true),
			"only_if_flora_missed=true 时地被格错误允许动物出生"
		)
		_expect(
			ground_state.can_spawn_fauna(false, false),
			"only_if_flora_missed=false 时可通行地被格仍拒绝动物出生"
		)
		var before: bool = ground_state.blocks_movement()
		var view = world._cells[ground_cover_cell]
		for block in view.get("_blocks"):
			block["render_priority"] = 99999
		_expect(
			ground_state.blocks_movement() == before,
			"修改 render_priority 意外改变了逻辑移动占用"
		)

	if water_cell.x < 1000000:
		_expect(
			not world._cell_states[water_cell].can_spawn_fauna(false, false),
			"陆生动物错误允许生成在水格"
		)

	if blocking_cell.x < 1000000:
		_expect(
			world._cell_states[blocking_cell].blocks_movement(),
			"阻挡物没有进入逻辑占用"
		)

	var free_cell: Vector2i = world._cell_states.keys()[0]
	world._free_cell(free_cell)
	_expect(not world._cell_states.has(free_cell), "流式卸载没有同步释放 CellState")

	world.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("CELL_STATE_INTEGRATION_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
