## world_terrain_mapping_contract.gd — cell_context_to_terrain 3→7 地形映射契约（P1-4）。
## 覆盖：代表性 CellContext → 期望地形逐例断言 + 真实 TerrainSampler 经
## WorldToChapter.world_to_chapter 的端到端断言。
extends SceneTree

const WorldToChapter = preload("res://scripts/core/world_to_chapter.gd")
const CellContext = preload("res://scripts/world/cell_context.gd")
const TerrainSamplerScript = preload("res://scripts/world/terrain_sampler.gd")

const ECOSYSTEM_CONFIG_PATH := "res://config/ecosystems.json"

const DESERT_SCRIPT := "res://scripts/world/biomes/desert_biome.gd"
const SNOW_SCRIPT := "res://scripts/world/biomes/snow_biome.gd"
const TEMPERATE_SCRIPT := "res://scripts/world/biomes/temperate_biome.gd"

## 世界层可映射到的战棋地形全集（11 种中 village/fort/wall/forest 无世界数据源）
const MAPPED_TERRAINS: Array[StringName] = [
	&"water", &"mountain", &"snow", &"sand", &"rocky", &"grass", &"plain",
]

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _mk_ctx(
		biome: StringName, surface: StringName, landform: StringName,
		height: int, is_water: bool = false
) -> RefCounted:
	return CellContext.new(
		Vector2i(17, 23), height, biome, -1, landform, -1,
		maxi(0, 6 - height) if is_water else 0, is_water, false, surface,
		Vector2i(2, 2), []
	)


func _test_unit_mapping() -> void:
	# 1) null → plain（缺采样时兜底）
	_expect(WorldToChapter.cell_context_to_terrain(null) == &"plain", "null ctx 应返回 plain")
	# 2) 水：is_water 或 height <= 5
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"plains", &"water", &"ocean", 3, true)) == &"water",
		"is_water 应返回 water")
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"plains", &"moist_soil", &"swamp", 4)) == &"water",
		"height<=5 应返回 water")
	# 3) 山：landform mountain 或 height >= 12（优先于雪/沙）
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"plains", &"grass", &"mountain", 7)) == &"mountain",
		"landform=mountain 应返回 mountain")
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"snow", &"snow", &"hills", 13)) == &"mountain",
		"height>=12 应优先返回 mountain（即使雪原）")
	# 4) 雪原：biome snow 或 surface snow
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"snow", &"snow", &"plains", 8)) == &"snow",
		"biome=snow 应返回 snow")
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"plains", &"snow", &"hills", 8)) == &"snow",
		"surface=snow 应返回 snow")
	# 5) 沙地：desert / desert_transition biome 或 surface sand
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"desert", &"sand", &"plains", 8)) == &"sand",
		"biome=desert 应返回 sand")
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"desert_transition", &"sparse_grass", &"plains", 8)) == &"sand",
		"biome=desert_transition 应优先于 grass 返回 sand")
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"plains", &"sand", &"ocean", 8)) == &"sand",
		"surface=sand 应返回 sand")
	# 6) 岩地：rock / mossy_rock / rock_grass
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"plains", &"rock", &"hills", 8)) == &"rocky",
		"surface=rock 应返回 rocky")
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"plains", &"mossy_rock", &"hills", 9)) == &"rocky",
		"surface=mossy_rock 应返回 rocky")
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"plains", &"rock_grass", &"hills", 9)) == &"rocky",
		"surface=rock_grass 应返回 rocky")
	# 7) 草地：grass / sparse_grass
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"plains", &"grass", &"plains", 7)) == &"grass",
		"surface=grass 应返回 grass")
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"plains", &"sparse_grass", &"plains", 7)) == &"grass",
		"surface=sparse_grass 应返回 grass")
	# 8) 兜底 plain：soil / moist_soil / parched_soil / 岸线
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"plains", &"soil", &"hills", 7)) == &"plain",
		"surface=soil 应返回 plain")
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"plains", &"moist_soil", &"swamp", 6)) == &"plain",
		"岸线 moist_soil 应返回 plain")
	_expect(
		WorldToChapter.cell_context_to_terrain(
			_mk_ctx(&"desert", &"parched_soil", &"plains", 8)) == &"sand",
		"desert biome 的 parched_soil 仍应返回 sand")
	# 9) 确定性：同 ctx 重复调用结果一致
	var ctx := _mk_ctx(&"plains", &"grass", &"hills", 9)
	_expect(
		WorldToChapter.cell_context_to_terrain(ctx)
			== WorldToChapter.cell_context_to_terrain(ctx),
		"同 ctx 重复调用结果应一致（确定性）")


func _build_sampler() -> RefCounted:
	var file := FileAccess.open(ECOSYSTEM_CONFIG_PATH, FileAccess.READ)
	if file == null:
		failures.append("无法读取 ecosystems.json")
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		failures.append("ecosystems.json 不是 Dictionary")
		return null
	var config: Dictionary = parsed
	var profiles: Dictionary = config.get("generation", {}).get("biome_profiles", {})
	var climate: Dictionary = config.get("generation", {}).get("climate", {})
	var generation: Dictionary = (config.get("generation", {}) as Dictionary).duplicate(true)
	generation["biome_index_order"] = ["plains", "desert", "snow", "desert_transition"]
	var definitions := [
		{
			"id": "desert", "script": DESERT_SCRIPT, "priority": 300,
			"transition_id": "desert_transition",
			"profile": (profiles.get("desert", {}) as Dictionary).duplicate(true),
		},
		{
			"id": "snow", "script": SNOW_SCRIPT, "priority": 200,
			"profile": (climate.get("snow", {}) as Dictionary).duplicate(true),
		},
		{
			"id": "temperate", "script": TEMPERATE_SCRIPT, "priority": -1000,
			"classification_id": "plains", "aliases": ["plains"],
			"tags": ["temperate", "mild"],
		},
	]
	var sampler = TerrainSamplerScript.new()
	if not sampler.configure(generation, definitions, 42):
		failures.append("TerrainSampler configure 失败")
		return null
	return sampler


func _test_end_to_end() -> void:
	var sampler := _build_sampler()
	if sampler == null:
		return
	# 1) 逐格 parity：world_to_chapter 的 map 每格 == cell_context_to_terrain(该世界 cell)
	var chapter: Dictionary = WorldToChapter.world_to_chapter(sampler, Vector2i.ZERO, 10, 42, 4)
	var terrain_map: Array = chapter["map"]
	var size: int = chapter["width"]
	var origin: Vector2i = chapter["world_origin"]
	var mismatch := 0
	for by in range(size):
		for bx in range(size):
			var ctx = sampler.sample(origin + Vector2i(bx, by))
			var expected := WorldToChapter.cell_context_to_terrain(ctx)
			if terrain_map[by][bx] != expected:
				mismatch += 1
	_expect(mismatch == 0, "world_to_chapter map 与逐格映射不一致数: %d" % mismatch)
	# 2) 值域：map 只含 11 种合法战棋地形
	for by in range(size):
		for bx in range(size):
			var t: StringName = terrain_map[by][bx]
			if not TerrainData.TERRAIN.has(t):
				_expect(false, "非法地形 %s 出现在 chapter map" % t)
	# 3) 多样性：大范围采样下应出现 >= 5 种映射地形（3 种旧映射不可能达到）
	var seen := {}
	for y in range(-384, 385, 8):
		for x in range(-384, 385, 8):
			var ctx = sampler.sample(Vector2i(x, y))
			seen[WorldToChapter.cell_context_to_terrain(ctx)] = true
	var distinct: int = seen.size()
	_expect(
		distinct >= 5,
		"seed=42 大范围采样应出现 >=5 种映射地形，实际 %d: %s" % [distinct, str(seen.keys())])
	# 4) 站立性：玩家单位所在格必须 standable
	var player_pos: Vector2i = chapter["playerUnits"][0]["position"]
	var pt: StringName = terrain_map[player_pos.y][player_pos.x]
	var tile := TerrainData.get_tile(pt)
	var cost: int = int(tile[&"move_cost"].get(&"foot", 99))
	_expect(
		bool(tile[&"walkable"]) and cost < 99,
		"玩家单位站在不可通行地形 %s 上" % pt)
	print("WORLD_TERRAIN_MAPPING distinct=%d" % distinct)


func _run() -> void:
	_test_unit_mapping()
	_test_end_to_end()
	if failures.is_empty():
		print("WORLD_TERRAIN_MAPPING_CONTRACT_OK checks=%d" % checks)
		quit(0)
	else:
		push_error("world_terrain_mapping 契约失败 %d/%d" % [failures.size(), checks])
		quit(1)
