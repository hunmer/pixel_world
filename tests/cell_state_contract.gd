extends SceneTree

const DeterministicRngScript = preload("res://scripts/world/deterministic_rng.gd")
const CellContextScript = preload("res://scripts/world/cell_context.gd")
const CellStateScript = preload("res://scripts/world/cell_state.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _legacy_hash_u32(value: int) -> int:
	value = (value ^ (value >> 16)) & 0xFFFFFFFF
	value = (value * 0x7FEB352D) & 0xFFFFFFFF
	value = (value ^ (value >> 15)) & 0xFFFFFFFF
	value = (value * 0x846CA68B) & 0xFFFFFFFF
	value = (value ^ (value >> 16)) & 0xFFFFFFFF
	return value


func _legacy_cell_rand(world_seed: int, cell: Vector2i, salt: int) -> float:
	return _legacy_hash_u32(
		cell.x * 0x8DA6B343
		^ cell.y * 0xD8163841
		^ (world_seed + salt)
	) / 4294967295.0


func _test_deterministic_rng() -> void:
	var rng = DeterministicRngScript.new(42)
	var same_rng = DeterministicRngScript.new(42)
	var cell := Vector2i(-17, 29)
	var legacy_expected := _legacy_cell_rand(42, cell, 640)
	var migrated_value: float = rng.cell_float(cell, &"flora.conflict", 640)
	_expect(
		migrated_value == legacy_expected,
		"显式 legacy salt 没有保持旧世界随机结果"
	)
	_expect(
		rng.cell_float(cell, &"flora.conflict")
		== same_rng.cell_float(cell, &"flora.conflict"),
		"命名随机流在相同 seed/cell 下不稳定"
	)
	_expect(
		rng.cell_float(cell, &"flora.conflict")
		!= rng.cell_float(cell, &"fauna.group"),
		"不同命名随机流发生意外复用"
	)
	_expect(
		rng.cell_u32(cell, &"flora.conflict", null, 0)
		!= rng.cell_u32(cell, &"flora.conflict", null, 1),
		"同一随机流的样本索引没有产生独立样本"
	)
	for sample_index in 32:
		var ranged: int = rng.cell_int(
			cell,
			&"contract.range",
			3,
			8,
			null,
			sample_index
		)
		_expect(ranged >= 3 and ranged < 8, "cell_int 超出半开区间")


func _temperate_context() -> RefCounted:
	var habitat_tags: Array[StringName] = [&"humid", &"near_water"]
	var context = CellContextScript.new(
		Vector2i(12, -4),
		7,
		&"temperate",
		0,
		&"hills",
		1,
		0,
		false,
		true,
		&"soil",
		Vector2i(8, -8),
		habitat_tags
	)
	return context


func _test_cell_context() -> void:
	var context = _temperate_context()
	var expected_tags: Array[StringName] = [&"humid", &"near_water"]
	_expect(context.cell == Vector2i(12, -4), "CellContext 没有保存 cell")
	_expect(context.height == 7, "CellContext 没有保存 height")
	_expect(context.biome_id == &"temperate" and context.biome_index == 0, "biome 字段错误")
	_expect(context.landform_id == &"hills" and context.landform_index == 1, "landform 字段错误")
	_expect(context.water_depth == 0 and not context.is_water, "water 字段错误")
	_expect(context.is_shore and context.surface_id == &"soil", "surface/shore 字段错误")
	_expect(context.region_anchor == Vector2i(8, -8), "region_anchor 字段错误")
	_expect(context.has_all_tags(expected_tags), "tags 字段错误")
	context.remove_tag(&"humid")
	_expect(not context.has_tag(&"humid"), "CellContext tag 无法移除")


func _test_cell_state() -> void:
	var state = CellStateScript.new(_temperate_context())
	_expect(state.can_spawn_fauna(), "空的陆地逻辑格应该允许动物生成")

	# Render metadata intentionally looks occupied. It must have no gameplay effect.
	state.add_render_block({
		"render_priority": 999,
		"flora_species_id": "fake_render_only_tree",
		"blocks_movement": true,
	})
	_expect(not state.blocks_movement(), "移动判定错误依赖了 render_blocks")
	_expect(not state.has_static_flora(), "植物判定错误依赖了 render_blocks")
	_expect(state.can_spawn_fauna(), "动物出生判定错误依赖了 render_blocks")

	state.add_static_object({
		"id": &"oak_01",
		"category": &"flora",
		"species_id": &"oak",
		"blocks_movement": true,
	})
	_expect(state.has_static_flora(), "静态植物没有写入逻辑占用")
	_expect(state.blocks_movement(), "阻挡物没有写入逻辑占用")
	_expect(not state.can_spawn_fauna(), "动物生成没有尊重静态逻辑占用")

	var water_context = CellContextScript.new()
	water_context.is_water = true
	var water_state = CellStateScript.new(water_context)
	_expect(not water_state.can_spawn_fauna(), "陆生动物默认可以生成在水中")
	_expect(water_state.can_spawn_fauna(true), "水生动物无法显式允许水域出生")
	water_state.add_occupancy_tag(CellStateScript.OCCUPANCY_BLOCKS_FAUNA_SPAWN)
	_expect(not water_state.can_spawn_fauna(true), "水域出生忽略了显式占用标签")


func _run() -> void:
	_test_deterministic_rng()
	_test_cell_context()
	_test_cell_state()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("CELL_STATE_CONTRACT_OK")
	quit(0)
