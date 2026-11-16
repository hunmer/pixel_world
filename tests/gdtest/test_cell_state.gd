## test_cell_state.gd — gdtest 试点：与 tests/cell_state_contract.gd 等价的最小断言（确定性 RNG legacy salt + 逻辑占用）
extends GdTest

const DeterministicRngScript = preload("res://scripts/world/deterministic_rng.gd")
const CellContextScript = preload("res://scripts/world/cell_context.gd")
const CellStateScript = preload("res://scripts/world/cell_state.gd")


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


func test_deterministic_rng_legacy_salt() -> void:
	var rng = DeterministicRngScript.new(42)
	var cell := Vector2i(-17, 29)
	assert_eq(
		rng.cell_float(cell, &"flora.conflict", 640),
		_legacy_cell_rand(42, cell, 640),
		"legacy salt 未保持旧世界随机结果"
	)
	assert_ne(
		rng.cell_float(cell, &"flora.conflict"),
		rng.cell_float(cell, &"fauna.group"),
		"命名随机流发生复用"
	)


func test_render_blocks_do_not_affect_gameplay() -> void:
	var tags: Array[StringName] = [&"humid", &"near_water"]
	var context = CellContextScript.new(
		Vector2i(12, -4), 7, &"temperate", 0, &"hills", 1,
		0, false, true, &"soil", Vector2i(8, -8), tags
	)
	var state = CellStateScript.new(context)
	assert_true(state.can_spawn_fauna(), "空陆地格应允许生成")
	state.add_render_block({
		"render_priority": 999,
		"flora_species_id": "fake_render_only_tree",
		"blocks_movement": true,
	})
	assert_false(state.blocks_movement(), "移动判定误依赖 render_blocks")
	assert_false(state.has_static_flora(), "植物判定误依赖 render_blocks")
	assert_true(state.can_spawn_fauna(), "出生判定误依赖 render_blocks")


func test_static_object_occupancy() -> void:
	var tags: Array[StringName] = []
	var context = CellContextScript.new(
		Vector2i(0, 0), 5, &"temperate", 0, &"plains", 0,
		0, false, false, &"soil", Vector2i.ZERO, tags
	)
	var state = CellStateScript.new(context)
	state.add_static_object({
		"id": &"oak_01",
		"category": &"flora",
		"species_id": &"oak",
		"blocks_movement": true,
	})
	assert_true(state.has_static_flora(), "静态植物未写入逻辑占用")
	assert_true(state.blocks_movement(), "阻挡未写入逻辑占用")
	assert_false(state.can_spawn_fauna(), "生成未尊重静态占用")
	var water_context = CellContextScript.new()
	water_context.is_water = true
	var water_state = CellStateScript.new(water_context)
	assert_false(water_state.can_spawn_fauna(), "陆生动物默认可生成在水中")
	assert_true(water_state.can_spawn_fauna(true), "水生无法显式允许水域出生")
