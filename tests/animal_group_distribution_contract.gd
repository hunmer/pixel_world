extends SceneTree

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _rule_by_pool(world, ecosystem_id: String, pool_id: String) -> Dictionary:
	var ecosystem: Dictionary = world._ecosystems_by_id[ecosystem_id]
	for rule_value in ecosystem.get("fauna", []):
		var rule: Dictionary = rule_value
		if String(rule.get("pool_id", "")) == pool_id:
			return rule
	return {}


func _find_group_anchor(
	world,
	ecosystem_id: String,
	rule: Dictionary,
	minimum_count: int
) -> Vector2i:
	var cells: Array = world._cells.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	var distribution: Dictionary = rule["distribution"]
	var water_radius := int(distribution.get("requires_water_within", 0))
	for cell_value in cells:
		var cell: Vector2i = cell_value
		var q: int = world._quantize(cell.x, cell.y)
		var biome: int = world._biome(cell.x, cell.y, q)
		var beach: bool = world._is_beach(cell, q)
		var landform: int = world._modules(cell.x, cell.y)[0]
		if world._ecosystem_id_for_cell(q, biome, beach, landform) != ecosystem_id:
			continue
		if water_radius > 0 and not world._has_water_within(cell, water_radius):
			continue
		var candidates: Array[Vector2i] = world._animal_group_spawn_cells(
			cell,
			q,
			ecosystem_id,
			distribution,
			int(distribution["count"][1]),
			int(rule["placement_seed"])
		)
		if candidates.size() >= minimum_count:
			return cell
	return Vector2i(1000000, 1000000)


func _bucket_for_substitution(world, rule: Dictionary) -> Vector2i:
	var placement_seed := int(rule["placement_seed"])
	var chance := float(rule["distribution"]["substitution"]["chance"])
	for y in range(-16, 17):
		for x in range(-16, 17):
			var bucket := Vector2i(x, y)
			if world._cell_rand(bucket, placement_seed + 5) < chance:
				return bucket
	return Vector2i.ZERO


func _free_test_animals(world) -> void:
	for animal_value in world._animals.values():
		var animal: Node = animal_value
		if not is_instance_valid(animal):
			continue
		if animal.get_parent() != null:
			animal.get_parent().remove_child(animal)
		animal.free()
	world._animals.clear()
	world._animal_groups.clear()


func _assert_group(
	world,
	ecosystem_id: String,
	pool_id: String,
	expected_min: int,
	expected_max: int
) -> void:
	_free_test_animals(world)
	var rule := _rule_by_pool(world, ecosystem_id, pool_id)
	_expect(not rule.is_empty(), "缺少 fauna 规则: " + pool_id)
	if rule.is_empty():
		return
	var anchor := _find_group_anchor(world, ecosystem_id, rule, expected_min)
	_expect(anchor.x < 1000000, "当前真实地图找不到可容纳群体的地块: " + pool_id)
	if anchor.x >= 1000000:
		return
	var bucket := (
		_bucket_for_substitution(world, rule)
		if pool_id == "wolf_pack"
		else Vector2i(3, -2)
	)
	var group_id := "contract/" + pool_id
	world._create_animal_group(
		group_id,
		ecosystem_id,
		rule,
		rule["distribution"],
		bucket,
		anchor,
		world._quantize(anchor.x, anchor.y)
	)
	_expect(world._animal_groups.has(group_id), "群体没有原子生成: " + pool_id)
	if not world._animal_groups.has(group_id):
		return
	var members: Array = world._animal_groups[group_id]["members"]
	_expect(
		members.size() >= expected_min and members.size() <= expected_max,
		"群体数量超出范围 [%s]: %d" % [pool_id, members.size()]
	)
	var origins := {}
	var species_counts := {}
	for member_value in members:
		var member: Dictionary = member_value
		var origin: Vector2i = member["origin"]
		var species_id := String(member["species"])
		origins[origin] = true
		species_counts[species_id] = int(species_counts.get(species_id, 0)) + 1
		_expect(world._quantize(origin.x, origin.y) > world.WATER_MAX, "动物群成员生成到水中")
		if world._animals.has(origin):
			var animal = world._animals[origin]
			_expect(
				animal.social_group_id == (group_id if members.size() > 1 else ""),
				"动物节点没有获得正确的社会群 ID: " + pool_id
			)
	_expect(origins.size() == members.size(), "动物群成员出生格发生重叠: " + pool_id)
	if pool_id == "wolf_pack":
		_expect(int(species_counts.get("husky", 0)) == 1, "狼群混入哈士奇时必须恰好一只")
		_expect(
			int(species_counts.get("wolf", 0)) == members.size() - 1,
			"哈士奇必须替换狼而不是增加狼群总数"
		)
	elif pool_id in ["dog_solitary", "fox_solitary"]:
		_expect(members.size() == 1, "狗和狐狸必须保持独居: " + pool_id)

	# 模拟流式卸载一个成员；回到该领地时必须按原出生格和原物种恢复，不能补出新成员。
	if not members.is_empty():
		var restore_member: Dictionary = members[0]
		var restore_origin: Vector2i = restore_member["origin"]
		if world._animals.has(restore_origin):
			var removed_animal: Node = world._animals[restore_origin]
			world._animals.erase(restore_origin)
			world.remove_child(removed_animal)
			removed_animal.free()
		var saved_player_cell: Vector2i = world._player_cell
		world._player_cell = restore_origin
		world._restore_animal_group(group_id)
		_expect(
			not world._animals.has(restore_origin),
			"玩家脚下仍然实例化了群成员: " + pool_id
		)
		world._player_cell = saved_player_cell
		world._restore_animal_group(group_id)
		_expect(world._animals.has(restore_origin), "流式返回后群成员没有恢复: " + pool_id)
		if world._animals.has(restore_origin):
			_expect(
				world._animals[restore_origin].species_id == String(restore_member["species"]),
				"流式返回后群成员物种发生变化: " + pool_id
			)


func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	world.seed = 42
	root.add_child(world)
	await process_frame
	world.set_process(false)
	var initial_group_count: int = world._animal_groups.size()
	var initial_animal_count: int = world._animals.size()
	_expect(initial_animal_count <= 12, "seed 42 初始视窗动物仍然过密: %d" % initial_animal_count)

	var expected_rules := {
		"wolf_pack": ["snow", 7, 8],
		"dog_solitary": ["temperate", 1, 1],
		"fox_solitary": ["temperate", 1, 1],
		"pig_family": ["temperate", 2, 4],
		"frog_cluster": ["temperate", 2, 4],
	}
	var temperate_expected_density := 0.0
	for pool_id in expected_rules:
		var expected: Array = expected_rules[pool_id]
		var rule := _rule_by_pool(world, String(expected[0]), pool_id)
		_expect(not rule.is_empty(), "配置缺少群落规则: " + pool_id)
		if rule.is_empty():
			continue
		var distribution: Dictionary = rule["distribution"]
		_expect(
			int(distribution["count"][0]) == int(expected[1])
			and int(distribution["count"][1]) == int(expected[2]),
			"群落数量配置错误: " + pool_id
		)
		var average_count := (
			float(distribution["count"][0]) + float(distribution["count"][1])
		) * 0.5
		var spacing := float(distribution["anchor_spacing"])
		var expected_density := float(rule["chance"]) * average_count / (spacing * spacing)
		if String(expected[0]) == "temperate":
			temperate_expected_density += expected_density
		else:
			_expect(expected_density < 0.002, "雪地动物期望密度仍然过高")
	_expect(temperate_expected_density < 0.0025, "温带动物总体期望密度仍然过高")

	# 固定 bucket 的群锚点必须完全确定，流式刷新不能改变其出生位置。
	var dog_rule := _rule_by_pool(world, "temperate", "dog_solitary")
	var anchor_once: Vector2i = world._fauna_anchor_for_bucket(dog_rule, Vector2i(-3, 5))
	var anchor_twice: Vector2i = world._fauna_anchor_for_bucket(dog_rule, Vector2i(-3, 5))
	_expect(anchor_once == anchor_twice, "群落锚点不确定")
	_expect(
		world._fauna_anchor_fully_loaded(world._stream_center, 4),
		"视窗中心没有被识别为完整群出生区域"
	)
	_expect(
		not world._fauna_anchor_fully_loaded(
			world._stream_center + Vector2i(world.stream_extent, 0), 4
		),
		"视窗边缘仍允许缓存被裁切的动物群"
	)

	# 群成员名单只能由地形、生态和种子决定；玩家站位与路过动物只会
	# 暂缓节点实例化，不能永久改变缓存中的出生格或群体数量。
	_free_test_animals(world)
	var deterministic_anchor := _find_group_anchor(world, "temperate", dog_rule, 1)
	_expect(deterministic_anchor.x < 1000000, "找不到确定性群成员测试锚点")
	if deterministic_anchor.x < 1000000:
		var deterministic_q: int = world._quantize(
			deterministic_anchor.x, deterministic_anchor.y
		)
		var deterministic_distribution: Dictionary = dog_rule["distribution"]
		var deterministic_before: Array[Vector2i] = world._animal_group_spawn_cells(
			deterministic_anchor,
			deterministic_q,
			"temperate",
			deterministic_distribution,
			1,
			int(dog_rule["placement_seed"])
		)
		if not deterministic_before.is_empty():
			var saved_player_cell: Vector2i = world._player_cell
			world._player_cell = deterministic_before[0]
			var blocker = world._spawn_animal(
				"dog", deterministic_before[0], deterministic_q
			)
			var deterministic_after: Array[Vector2i] = world._animal_group_spawn_cells(
				deterministic_anchor,
				deterministic_q,
				"temperate",
				deterministic_distribution,
				1,
				int(dog_rule["placement_seed"])
			)
			_expect(
				deterministic_after == deterministic_before,
				"玩家或动态动物改变了同一群落的确定性成员名单"
			)
			world._player_cell = saved_player_cell
			if blocker != null:
				world._animals.erase(deterministic_before[0])
				world.remove_child(blocker)
				blocker.free()

	_assert_group(world, "snow", "wolf_pack", 7, 8)
	_assert_group(world, "temperate", "dog_solitary", 1, 1)
	_assert_group(world, "temperate", "fox_solitary", 1, 1)
	_assert_group(world, "temperate", "pig_family", 2, 4)
	_assert_group(world, "temperate", "frog_cluster", 2, 4)

	print("ANIMAL_GROUP_METRICS initial_groups=", initial_group_count,
		" initial_animals=", initial_animal_count,
		" expected_temperate_density=", temperate_expected_density)
	world.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("ANIMAL_GROUP_DISTRIBUTION_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
