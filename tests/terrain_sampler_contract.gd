extends SceneTree

const TerrainSamplerScript = preload("res://scripts/world/terrain_sampler.gd")
const EcologyRegistryScript = preload("res://scripts/ecology/ecology_registry.gd")

const ECOSYSTEM_CONFIG_PATH := "res://config/ecosystems.json"
const MODULAR_MANIFEST_PATH := "res://config/ecology/manifest.json"
const EXPECTED_SEED_42_HEIGHT_BIOME_HASH := "51547fc0aadd5eaabd0c12ced2e8bd301efb829be4a84f8e449eb97c2d032203"
const SAMPLE_RADIUS := 256
const SAMPLE_STEP := 4

const DESERT_SCRIPT := "res://scripts/world/biomes/desert_biome.gd"
const SNOW_SCRIPT := "res://scripts/world/biomes/snow_biome.gd"
const TEMPERATE_SCRIPT := "res://scripts/world/biomes/temperate_biome.gd"
const VOLCANIC_FIXTURE_SCRIPT := "res://tests/fixtures/volcanic_biome.gd"

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _read_config() -> Dictionary:
	var file := FileAccess.open(ECOSYSTEM_CONFIG_PATH, FileAccess.READ)
	if file == null:
		failures.append("无法读取 ecosystems.json")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		failures.append("ecosystems.json 不是 Dictionary")
		return {}
	return parsed


func _biome_definitions(generation: Dictionary) -> Array:
	var profiles: Dictionary = generation.get("biome_profiles", {})
	var climate: Dictionary = generation.get("climate", {})
	# Definition order is deliberately not legacy index order. The explicit
	# generation.biome_index_order owns that compatibility contract.
	return [
		{
			"id": "desert",
			"script": DESERT_SCRIPT,
			"priority": 300,
			"transition_id": "desert_transition",
			"profile": (profiles.get("desert", {}) as Dictionary).duplicate(true),
		},
		{
			"id": "snow",
			"script": SNOW_SCRIPT,
			"priority": 200,
			"profile": (climate.get("snow", {}) as Dictionary).duplicate(true),
		},
		{
			"id": "temperate",
			"script": TEMPERATE_SCRIPT,
			"priority": -1000,
			"classification_id": "plains",
			"aliases": ["plains"],
			"tags": ["temperate", "mild"],
		},
		# A legacy habitat/ecosystem rule can coexist in the catalog, but must not
		# be sent to BiomeRegistry because it has no terrain script.
		{
			"id": "legacy_water_rule",
			"enabled": false,
			"match": {"water": true},
		},
	]


func _generation_with_legacy_index_order(config: Dictionary) -> Dictionary:
	var generation: Dictionary = (config.get("generation", {}) as Dictionary).duplicate(true)
	generation["biome_index_order"] = [
		"plains",
		"desert",
		"snow",
		"desert_transition",
	]
	return generation


func _snapshot_hash(sampler: RefCounted) -> String:
	var samples := PackedStringArray()
	for y in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, SAMPLE_STEP):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, SAMPLE_STEP):
			var cell := Vector2i(x, y)
			var height: int = sampler.quantize(cell)
			var id: StringName = sampler.biome_id(cell, height)
			samples.append("%d,%d" % [height, sampler.biome_index(id)])
	return "|".join(samples).sha256_text()


func _compact_snapshot_hash(sampler: RefCounted) -> String:
	var samples := PackedStringArray()
	for y in range(-48, 49, 6):
		for x in range(-48, 49, 6):
			var cell := Vector2i(x, y)
			var height: int = sampler.quantize(cell)
			samples.append("%d:%s" % [height, sampler.biome_id(cell, height)])
	return "|".join(samples).sha256_text()


func _test_main_parity(
	sampler: RefCounted,
	world: Node
) -> String:
	var samples := PackedStringArray()
	var mismatch_count := 0
	for y in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, SAMPLE_STEP):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, SAMPLE_STEP):
			var cell := Vector2i(x, y)
			var expected_height: int = world._quantize(x, y)
			var expected_biome: int = world._biome(x, y, expected_height)
			var actual_height: int = sampler.quantize(cell)
			var actual_id: StringName = sampler.biome_id(cell, actual_height)
			var actual_biome: int = sampler.biome_index(actual_id)
			if expected_height != actual_height or expected_biome != actual_biome:
				mismatch_count += 1
				if mismatch_count <= 3:
					failures.append(
						"TerrainSampler 与 main 不一致 %s: (%d,%d) != (%d,%d)"
						% [cell, actual_height, actual_biome, expected_height, expected_biome]
					)
			samples.append("%d,%d" % [actual_height, actual_biome])
	_expect(mismatch_count == 0, "TerrainSampler parity mismatch 总数: %d" % mismatch_count)
	return "|".join(samples).sha256_text()


func _test_context_and_legacy_adapter(sampler: RefCounted, world: Node) -> void:
	var found_water = null
	var found_shore = null
	var found_snow = null
	var found_transition = null
	for y in range(-256, 257, 4):
		for x in range(-256, 257, 4):
			var context = sampler.sample(Vector2i(x, y))
			if context.is_water and found_water == null:
				found_water = context
			if context.is_shore and found_shore == null:
				found_shore = context
			if context.biome_id == &"snow" and found_snow == null:
				found_snow = context
			if context.biome_id == &"desert_transition" and found_transition == null:
				found_transition = context
			if (
				found_water != null
				and found_shore != null
				and found_snow != null
				and found_transition != null
			):
				break
		if (
			found_water != null
			and found_shore != null
			and found_snow != null
			and found_transition != null
		):
			break

	_expect(found_water != null, "sample() 没有产生水域 CellContext")
	_expect(found_shore != null, "sample() 没有产生岸边 CellContext")
	_expect(found_snow != null, "sample() 没有产生雪原 CellContext")
	_expect(found_transition != null, "sample() 没有产生沙漠过渡 CellContext")
	if found_water != null:
		_expect(found_water.surface_id == &"water", "水域 surface_id 错误")
		_expect(found_water.water_depth > 0, "水域 water_depth 没有写入")
		_expect(found_water.has_tag(&"water"), "水域 context 缺少 water tag")
	if found_shore != null:
		_expect(found_shore.surface_id == &"moist_soil", "岸边 surface_id 错误")
		_expect(found_shore.has_tag(&"shore"), "岸边 context 缺少 shore tag")
	if found_snow != null:
		_expect(found_snow.surface_id == &"snow", "雪原 surface_id 错误")
		_expect(found_snow.has_tag(&"cold"), "雪原 module tags 没有进入 CellContext")
	if found_transition != null:
		_expect(
			found_transition.surface_id in [&"sand", &"rock", &"parched_soil", &"sparse_grass"],
			"沙漠过渡 surface_id 错误"
		)

	var probe := Vector2i(37, -91)
	var legacy_modules: Array = sampler.modules(probe)
	var old_modules: Array = world._modules(probe.x, probe.y)
	_expect(legacy_modules.size() == 8, "modules legacy adapter 长度不为 8")
	for index in range(1, 7):
		_expect(
			is_equal_approx(float(legacy_modules[index]), float(old_modules[index])),
			"modules legacy adapter 参数 %d 与 main 不一致" % index
		)
	_expect(legacy_modules[7] == old_modules[7], "modules legacy adapter region anchor 不一致")
	var probe_context = sampler.sample(probe)
	_expect(probe_context.region_anchor == legacy_modules[7], "CellContext region anchor 错误")
	_expect(
		probe_context.landform_index == int(legacy_modules[0]),
		"CellContext landform index 没有使用动态配置索引"
	)
	_expect(
		probe_context.has_tag(StringName("landform:%s" % probe_context.landform_id)),
		"CellContext 缺少动态 landform tag"
	)


func _renamed_generation(generation: Dictionary) -> Dictionary:
	var renamed := generation.duplicate(true)
	var noise_config: Dictionary = renamed["noise"]
	var fields: Dictionary = noise_config["fields"]
	var names := {
		"land": "fixture_continent_base",
		"detail": "fixture_height_detail",
		"roughness": "fixture_relief_mask",
		"peaks": "fixture_peak_ridges",
	}
	for old_id in names:
		fields[names[old_id]] = fields[old_id]
		fields.erase(old_id)
	var height: Dictionary = renamed["height"]
	height["noise_fields"] = {
		"base": names["land"],
		"detail": names["detail"],
		"roughness": names["roughness"],
		"peaks": names["peaks"],
	}
	var regions: Dictionary = renamed["regions"]
	for landform_value in regions["landforms"]:
		var landform: Dictionary = landform_value
		landform["id"] = "fixture_%s" % landform["id"]
	return renamed


func _test_dynamic_ids(
	base_sampler: RefCounted,
	generation: Dictionary,
	definitions: Array
) -> void:
	var renamed_generation := _renamed_generation(generation)
	var renamed_sampler = TerrainSamplerScript.new()
	_expect(
		renamed_sampler.configure(renamed_generation, definitions, 42),
		"重命名 noise/landform 后 TerrainSampler 配置失败: %s" % renamed_sampler.last_error
	)
	for y in range(-96, 97, 12):
		for x in range(-96, 97, 12):
			var cell := Vector2i(x, y)
			_expect(
				renamed_sampler.quantize(cell) == base_sampler.quantize(cell),
				"动态 noise/landform ID 改变了地形公式: %s" % cell
			)
	var renamed_context = renamed_sampler.sample(Vector2i(11, 23))
	_expect(
		String(renamed_context.landform_id).begins_with("fixture_"),
		"TerrainSampler 仍依赖固定 landform enum/id"
	)
	_expect(
		renamed_sampler.noise(&"fixture_height_detail", Vector2i(9, 9))
		== base_sampler.noise(&"detail", Vector2i(9, 9)),
		"noise(field) 没有使用动态字段注册表"
	)


func _test_modular_catalog(base_sampler: RefCounted) -> void:
	var ecology_registry = EcologyRegistryScript.new()
	_expect(
		ecology_registry.load_manifest(MODULAR_MANIFEST_PATH),
		"模块化生态 manifest 加载失败: %s" % ecology_registry.get_error_text()
	)
	if not ecology_registry.is_loaded():
		return
	var catalog: Dictionary = ecology_registry.get_catalog()
	var catalog_sampler = TerrainSamplerScript.new()
	_expect(
		catalog_sampler.configure(
			catalog.get("world", {}),
			catalog.get("biomes", {}),
			42
		),
		"TerrainSampler 无法直接消费模块化 catalog: %s" % catalog_sampler.last_error
	)
	if not catalog_sampler.configured:
		return
	_expect(
		catalog_sampler.biome_index(&"plains") == 0
		and catalog_sampler.biome_index(&"desert") == 1
		and catalog_sampler.biome_index(&"snow") == 2
		and catalog_sampler.biome_index(&"desert_transition") == 3,
		"模块化 catalog 没有遵守 generation.biome_index_order"
	)
	for y in range(-96, 97, 12):
		for x in range(-96, 97, 12):
			var cell := Vector2i(x, y)
			var base_height: int = base_sampler.quantize(cell)
			var catalog_height: int = catalog_sampler.quantize(cell)
			_expect(catalog_height == base_height, "模块化 catalog 改变地形高度: %s" % cell)
			_expect(
				catalog_sampler.biome_index(catalog_sampler.biome_id(cell, catalog_height))
				== base_sampler.biome_index(base_sampler.biome_id(cell, base_height)),
				"模块化 catalog 改变 biome 分类: %s" % cell
			)


func _test_cache_and_reseed(sampler: RefCounted) -> void:
	var seed_42_digest := _compact_snapshot_hash(sampler)
	sampler.set_cache_capacity(12)
	for index in 80:
		sampler.sample(Vector2i(index * 3, -index * 2))
	var sizes: Dictionary = sampler.cache_sizes()
	for cache_id in sizes:
		_expect(int(sizes[cache_id]) <= 12, "cache '%s' 超过配置上限" % cache_id)
	sampler.clear_cache()
	sizes = sampler.cache_sizes()
	_expect(
		int(sizes["modules"]) == 0 and int(sizes["height"]) == 0 and int(sizes["samples"]) == 0,
		"clear_cache() 没有清空所有缓存"
	)
	sampler.reseed(777)
	var other_seed_digest := _compact_snapshot_hash(sampler)
	_expect(other_seed_digest != seed_42_digest, "reseed() 没有改变世界采样")
	sampler.reseed(42)
	_expect(
		_compact_snapshot_hash(sampler) == seed_42_digest,
		"reseed(42) 没有恢复确定性世界"
	)


func _test_fixture_biome(
	generation: Dictionary,
	base_definitions: Array
) -> void:
	var definitions := base_definitions.duplicate(true)
	definitions.append({
		"id": "volcanic_fixture",
		"script": VOLCANIC_FIXTURE_SCRIPT,
		"priority": 9000,
		"tags": ["volcanic", "geothermal"],
		"weather_tags": ["ash_capable"],
		"profile": {
			"heat_noise_field": "fixture_volcanic_heat",
			"minimum_heat": -1.0,
			"minimum_level": 0,
			"height_bias": 0.0,
			"peak_scale": 1.0,
		},
		"noise_fields": {
			"fixture_volcanic_heat": {
				"seed_offset": 2201,
				"frequency": 0.009,
			},
		},
	})
	var sampler = TerrainSamplerScript.new()
	_expect(
		sampler.configure(generation, definitions, 42),
		"新增 volcanic fixture 后 sampler 配置失败: %s" % sampler.last_error
	)
	var context = sampler.sample(Vector2i.ZERO)
	if context.is_water:
		for x in range(1, 100):
			context = sampler.sample(Vector2i(x * 7, x * 11))
			if not context.is_water:
				break
	_expect(context.biome_id == &"volcanic_fixture", "新增脚本 biome 没有参与 sampler classify")
	_expect(context.surface_id == &"basalt", "新增脚本 biome 没有接管 sampler surface")
	_expect(context.has_tag(&"volcanic"), "新增脚本 biome tags 没有进入 CellContext")
	_expect(
		sampler.noise_registry.has_field(&"fixture_volcanic_heat"),
		"新增脚本 biome 的 noise field 没有动态生效"
	)


func _run() -> void:
	var config := _read_config()
	if config.is_empty():
		quit(1)
		return
	var generation := _generation_with_legacy_index_order(config)
	var definitions := _biome_definitions(generation)
	var sampler = TerrainSamplerScript.new()
	_expect(
		sampler.configure(generation, definitions, 42),
		"TerrainSampler 配置失败: %s" % sampler.last_error
	)
	if not sampler.configured:
		for failure in failures:
			push_error(failure)
		quit(1)
		return

	var world = load("res://main.tscn").instantiate()
	world.seed = 42
	root.add_child(world)
	await process_frame
	world.set_process(false)
	var snapshot_hash := _test_main_parity(sampler, world)
	print(
		"TERRAIN_SAMPLER_SEED_42_HEIGHT_BIOME_HASH ",
		snapshot_hash,
		" samples=",
		int(pow((SAMPLE_RADIUS * 2) / SAMPLE_STEP + 1, 2))
	)
	if (
		not EXPECTED_SEED_42_HEIGHT_BIOME_HASH.is_empty()
		and snapshot_hash != EXPECTED_SEED_42_HEIGHT_BIOME_HASH
	):
		failures.append(
			"TerrainSampler seed 42 hash 回归: %s != %s"
			% [snapshot_hash, EXPECTED_SEED_42_HEIGHT_BIOME_HASH]
		)
	_test_context_and_legacy_adapter(sampler, world)
	_test_dynamic_ids(sampler, generation, definitions)
	_test_modular_catalog(sampler)
	_test_cache_and_reseed(sampler)
	_test_fixture_biome(generation, definitions)
	world.queue_free()

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("TERRAIN_SAMPLER_CONTRACT_OK")
	quit(0)
