extends SceneTree

const WanderingAnimalScript = preload("res://scripts/wandering_animal.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _make_texture() -> ImageTexture:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


func _make_frames(move_action: StringName, move_loops: bool) -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	var texture := _make_texture()
	for action in [&"idle", move_action]:
		frames.add_animation(action)
		frames.set_animation_speed(action, 8.0)
		frames.set_animation_loop(action, action == &"idle" or move_loops)
		for _frame in 4:
			frames.add_frame(action, texture)
	return frames


func _configure_animal(
	species_id: String,
	move_action: StringName,
	move_loops: bool,
	move_steps: Array,
	source_faces_right := false,
	direction_persistence := 0.0
):
	var animal = WanderingAnimalScript.new()
	root.add_child(animal)
	animal.configure(
		species_id,
		Vector2i.ZERO,
		_make_frames(move_action, move_loops),
		Vector2.ZERO,
		0.0,
		0.0,
		&"wander",
		{
			"idle_action": "idle",
			"move_action": String(move_action),
			"duration": 0.1,
			"move_steps": move_steps,
			"step_pause_seconds": [0.08, 0.16],
			"source_faces_right": source_faces_right,
			"direction_persistence": direction_persistence,
		},
		0.0
	)
	return animal


func _complete_step(animal, next_cell: Vector2i) -> void:
	animal.begin_move(
		next_cell,
		Vector2(animal.grid_cell),
		Vector2(next_cell),
		0.0,
		1.0,
		0.1,
		1.0,
		0.0,
		0.0
	)
	_expect(animal.tick(0.2), "测试移动未在预期时间内完成")
	animal.consume_move_bout_step()


func _cell_is_open(world, cell: Vector2i) -> bool:
	var q: int = world._quantize(cell.x, cell.y)
	if q <= world.WATER_MAX or not world._cells.has(cell):
		return false
	for block in world._cell_states[cell].render_blocks:
		if int(block["render_priority"]) >= 8:
			return false
	return true


func _find_open_bout_cell(world) -> Vector2i:
	for cell_value in world._cells.keys():
		var cell: Vector2i = cell_value
		if not _cell_is_open(world, cell):
			continue
		var open_neighbors := 0
		for direction_value in world.ANIMAL_DIRECTIONS:
			var direction: Vector2i = direction_value
			var neighbor: Vector2i = cell + direction
			if (
				_cell_is_open(world, neighbor)
				and absi(
					world._stand_level(world._quantize(neighbor.x, neighbor.y))
					- world._stand_level(world._quantize(cell.x, cell.y))
				) <= 1
			):
				open_neighbors += 1
		if open_neighbors >= 2:
			return cell
	return Vector2i(1000000, 1000000)


func _run() -> void:
	var walker = _configure_animal("dog", &"walk", true, [3, 3])
	_expect(walker.animation == &"idle", "动物初始状态不是 idle")
	walker.start_move_bout(3)
	_complete_step(walker, Vector2i.RIGHT)
	_expect(walker.animation == &"walk", "走完第一格后错误切回 idle")
	_expect(walker.move_steps_remaining == 2, "行动段剩余步数错误")
	walker.frame = 2
	walker.begin_move(
		Vector2i(2, 0),
		Vector2(1, 0),
		Vector2(2, 0),
		1.0,
		2.0,
		0.1,
		1.0,
		0.0,
		0.0
	)
	_expect(walker.animation == &"walk", "连续移动没有保持 walk")
	_expect(walker.frame == 2, "连续移动重新播放了 walk 首帧")
	_expect(walker.tick(0.2), "第二格移动未完成")
	walker.consume_move_bout_step()
	_complete_step(walker, Vector2i(3, 0))
	_expect(walker.move_steps_remaining == 0, "三格行动段没有正确结束计数")
	_expect(walker.animation == &"walk", "行动段结束前提前切换姿态")
	walker.finish_move_bout()
	_expect(walker.animation == &"idle", "行动段结束后没有回到 idle")

	var fish = _configure_animal(
		"goldfish",
		&"swim",
		true,
		[8, 12],
		true,
		6.0
	)
	fish.start_move_bout(8)
	fish.begin_move(
		Vector2i.RIGHT,
		Vector2.ZERO,
		Vector2.RIGHT,
		0.0,
		1.0,
		0.1,
		1.0,
		0.0,
		0.0
	)
	_expect(not fish.flip_h, "原图朝右的鱼向右游时被错误镜像")
	_expect(fish.tick(0.2), "鱼向右测试移动未完成")
	_expect(
		fish.direction_persistence_score(Vector2i(2, 0), Vector2i.RIGHT)
		> fish.direction_persistence_score(Vector2i(1, 1), Vector2i.RIGHT),
		"鱼在连续行动段中没有偏好保持原方向"
	)
	fish.begin_move(
		Vector2i.ZERO,
		Vector2.RIGHT,
		Vector2.ZERO,
		1.0,
		0.0,
		0.1,
		1.0,
		0.0,
		0.0
	)
	_expect(fish.flip_h, "原图朝右的鱼向左游前没有先镜像")

	var frog = _configure_animal("frog", &"jump", false, [1, 1])
	frog.start_move_bout(1)
	_complete_step(frog, Vector2i.DOWN)
	_expect(not frog.move_action_loops(), "青蛙 jump 不应被视为循环动作")
	_expect(frog.animation == &"jump", "青蛙落地结算前丢失 jump 姿态")
	frog.finish_move_bout()
	_expect(frog.animation == &"idle", "青蛙单次落地后没有回到 idle")

	var world = load("res://main.tscn").instantiate()
	world.seed = 42
	root.add_child(world)
	await process_frame
	world.set_process(false)
	world._clear_animals()
	var spawn_cell := _find_open_bout_cell(world)
	_expect(spawn_cell.x < 1000000, "真实地图中没有找到可连续移动的测试格")
	if spawn_cell.x < 1000000:
		world._spawn_animal("dog", spawn_cell, world._quantize(spawn_cell.x, spawn_cell.y))
		var actual = world._animals[spawn_cell]
		world._player_cell = Vector2i(10000, 10000)
		actual.wait_remaining = 0.0
		world._update_animals(0.0)
		_expect(actual.moving, "真实动物没有开始行动段")
		_expect(actual.animation == &"walk", "真实动物起步没有进入 walk")
		var starting_steps: int = actual.move_steps_remaining
		world._update_animals(1.0)
		_expect(not actual.moving, "真实动物第一格没有完成")
		_expect(actual.move_bout_active, "真实动物走一格后错误结束行动段")
		_expect(actual.move_steps_remaining == starting_steps - 1, "真实行动段没有消费一步")
		_expect(actual.animation == &"walk", "真实动物走一格后闪回 idle")
		world._update_animals(0.2)
		_expect(actual.moving, "真实动物没有在短暂停顿后继续下一格")
		_expect(actual.animation == &"walk", "真实动物连续移动时重置了姿态")

	walker.queue_free()
	fish.queue_free()
	frog.queue_free()
	world.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("ANIMAL_ANIMATION_STATE_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
