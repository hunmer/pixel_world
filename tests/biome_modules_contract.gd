extends SceneTree

const NoiseRegistryScript = preload("res://scripts/world/noise_registry.gd")
const BiomeRegistryScript = preload("res://scripts/world/biomes/biome_registry.gd")

const DESERT_SCRIPT := "res://scripts/world/biomes/desert_biome.gd"
const SNOW_SCRIPT := "res://scripts/world/biomes/snow_biome.gd"
const TEMPERATE_SCRIPT := "res://scripts/world/biomes/temperate_biome.gd"
const FIXTURE_VOLCANIC_SCRIPT := "res://tests/fixtures/volcanic_biome.gd"

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _noise_definition() -> Dictionary:
	return {
		"type": "perlin",
		"fractal": "fbm",
		"octaves": 4,
		"fields": {
			# Intentionally arbitrary names: NoiseRegistry has no field id list.
			"fixture_custom_field": {
				"seed_offset": 17,
				"frequency": 0.041,
				"type": "simplex_smooth",
			},
			"temperature": {"seed_offset": 303, "frequency": 0.035},
			"desert_dunes": {"seed_offset": 707, "frequency": 0.018},
			"desert_regions": {
				"seed_offset": 808,
				"frequency": 0.004,
				"octaves": 1,
			},
			"desert_rocks": {
				"seed_offset": 909,
				"frequency": 0.022,
				"octaves": 2,
			},
			"desert_edges": {
				"seed_offset": 1001,
				"frequency": 0.018,
				"octaves": 2,
			},
		},
	}


func _biome_definitions() -> Array:
	return [
		{
			"id": "desert",
			"script": DESERT_SCRIPT,
			"priority": 300,
			"transition_id": "desert_transition",
			"profile": {
				"region": {
					"transition_threshold": 0.14,
					"core_threshold": 0.22,
					"edge_amplitude": 0.05,
				},
				"surface": {
					"transition_grass_fraction": 0.35,
					"transition_grass_chance": 0.10,
					"transition_sand_enter": 0.68,
					"transition_rock_noise_above": 0.40,
					"rock_noise_above": 0.30,
					"rock_level": 12,
				},
				"terrain": {
					"elevation_bias": 0.14,
					"relief_scale": 0.55,
					"dune_amplitude": 0.07,
					"peak_scale": 0.20,
				},
			},
		},
		{
			"id": "snow",
			"script": SNOW_SCRIPT,
			"priority": 200,
			"profile": {
				"base_level": 14,
				"temperature_level_scale": 3.0,
			},
		},
		{
			"id": "temperate",
			"script": TEMPERATE_SCRIPT,
			"priority": -1000,
			"profile": {"water_max": 5, "levels": 16},
		},
	]


func _test_dynamic_noise_registry() -> RefCounted:
	var registry = NoiseRegistryScript.new()
	_expect(registry.configure(_noise_definition(), 42), "NoiseRegistry 配置失败")
	_expect(
		registry.has_field(&"fixture_custom_field"),
		"任意命名的 noise field 没有被动态注册"
	)
	_expect(
		registry.field_ids().size() == _noise_definition()["fields"].size(),
		"NoiseRegistry 隐式要求了固定 fields 或遗漏了动态 field"
	)
	var position := Vector2i(19, -7)
	var first := registry.sample_2d(&"fixture_custom_field", position)
	var identical_registry = NoiseRegistryScript.new()
	_expect(identical_registry.configure(_noise_definition(), 42), "第二个 NoiseRegistry 配置失败")
	_expect(
		is_equal_approx(
			first,
			identical_registry.sample_2d(&"fixture_custom_field", position)
		),
		"NoiseRegistry 相同 seed 的采样不确定"
	)
	registry.reseed(314159)
	_expect(
		not is_equal_approx(first, registry.sample_2d(&"fixture_custom_field", position)),
		"NoiseRegistry reseed 没有更新动态 field"
	)
	registry.reseed(42)
	return registry


func _find_classified_cell(module: RefCounted, target_id: StringName) -> Variant:
	for x in range(-480, 481, 4):
		for y in range(-480, 481, 4):
			var cell := Vector2i(x, y)
			if StringName(String(module.classify(cell, 8))) == target_id:
				return cell
	return null


func _test_builtin_modules(noise_registry: RefCounted) -> void:
	var registry = BiomeRegistryScript.new()
	_expect(
		registry.configure(_biome_definitions(), noise_registry),
		"BiomeRegistry 无法加载内建模块: %s" % registry.last_error
	)
	_expect(
		registry.module_ids() == [&"desert", &"snow", &"temperate"],
		"BiomeRegistry 没有按 priority 排列模块"
	)

	var desert = registry.module_for_biome(&"desert")
	var snow = registry.module_for_biome(&"snow")
	var temperate = registry.module_for_biome(&"temperate")
	_expect(desert != null and snow != null and temperate != null, "无法按 biome id 查找模块")
	_expect(
		registry.module_for_biome(&"desert_transition") == desert,
		"沙漠过渡 id 没有归属到沙漠模块"
	)

	var desert_cell: Variant = _find_classified_cell(desert, &"desert")
	var transition_cell: Variant = _find_classified_cell(desert, &"desert_transition")
	_expect(desert_cell != null, "沙漠大陆区域公式没有产生核心区")
	_expect(transition_cell != null, "沙漠大陆区域公式没有产生过渡区")
	if desert_cell != null:
		_expect(
			registry.classify(desert_cell, 100) == &"desert",
			"高优先级沙漠没有先于雪线完成 classify"
		)
		_expect(
			registry.surface_kind(desert_cell, 8, &"desert")
			in [&"sand", &"rock"],
			"沙漠 surface_kind 没有迁移沙/石公式"
		)
		_expect(&"arid" in registry.tags(desert_cell, 8, &"desert"), "沙漠 tags 缺失")
		_expect(&"dry" in registry.weather_tags(desert_cell, 8, &"desert"), "沙漠 weather_tags 缺失")
		_expect(registry.minimap_color(desert_cell, 8, &"desert").a > 0.0, "沙漠小地图颜色缺失")
		var source_height := 0.42
		var manual_height := source_height
		var manual_peak_scale := 1.0
		for module in registry.modules:
			manual_height = module.modify_height(desert_cell, manual_height)
			manual_peak_scale *= module.peak_scale(desert_cell)
		_expect(
			is_equal_approx(
				registry.apply_height_modifiers(desert_cell, source_height),
				manual_height
			),
			"BiomeRegistry 没有顺序组合 height modifiers"
		)
		_expect(
			is_equal_approx(registry.peak_scale(desert_cell), manual_peak_scale),
			"BiomeRegistry 没有组合 peak scale"
		)
	if transition_cell != null:
		_expect(
			registry.surface_kind(transition_cell, 8, &"desert_transition")
			in [
				&"sand",
				&"rock",
				&"transition_parched",
				&"transition_sparse_grass",
			],
			"沙漠过渡 surface_kind 没有迁移现有公式"
		)

	var non_desert_cell := Vector2i.ZERO
	while desert.classify(non_desert_cell, 8) != &"":
		non_desert_cell += Vector2i(17, 29)
	_expect(
		registry.classify(non_desert_cell, 100) == &"snow",
		"雪原模块没有使用 temperature 扰动的海拔雪线"
	)
	_expect(
		registry.classify(non_desert_cell, 0) == &"temperate",
		"温带模块没有作为低优先级 fallback"
	)
	_expect(
		registry.surface_kind(non_desert_cell, 100, &"snow") == &"snow",
		"雪原 surface_kind 错误"
	)
	_expect(&"snow_capable" in registry.weather_tags(non_desert_cell, 100, &"snow"), "雪原 weather_tags 缺失")


func _test_definition_loaded_fixture(noise_registry: RefCounted) -> void:
	# This id, noise field, and script are all unknown to BiomeRegistry. Only this
	# definition and the fixture script are needed; the registry stays unchanged.
	var definitions := {
		"future_volcanic_fixture": {
			"script": FIXTURE_VOLCANIC_SCRIPT,
			"priority": 9000,
			"tags": ["volcanic", "geothermal"],
			"weather_tags": ["ash_capable"],
			"minimap_color": [0.18, 0.12, 0.10],
			"profile": {
				"heat_noise_field": "fixture_volcanic_heat",
				"minimum_heat": -1.0,
				"minimum_level": 0,
				"height_bias": 0.07,
				"peak_scale": 1.25,
			},
			"noise_fields": {
				"fixture_volcanic_heat": {
					"seed_offset": 2201,
					"frequency": 0.009,
				},
			},
		},
		"temperate": {
			"script": TEMPERATE_SCRIPT,
			"priority": -1000,
		},
	}
	var registry = BiomeRegistryScript.new()
	_expect(
		registry.configure(definitions, noise_registry),
		"定义驱动的 fixture biome 加载失败: %s" % registry.last_error
	)
	_expect(
		noise_registry.has_field(&"fixture_volcanic_heat"),
		"biome 定义没有动态追加自身 noise field"
	)
	var fixture_id := registry.classify(Vector2i(3, 5), 7)
	_expect(
		fixture_id == &"future_volcanic_fixture",
		"registry 仍依赖内建 biome id，而不是 priority + 脚本"
	)
	_expect(
		registry.surface_kind(Vector2i(3, 5), 7, fixture_id) == &"basalt",
		"fixture biome 脚本没有接管 surface_kind"
	)
	_expect(
		is_equal_approx(registry.apply_height_modifiers(Vector2i(3, 5), 0.4), 0.47),
		"fixture biome 脚本没有接入顺序 height modifier"
	)
	_expect(
		is_equal_approx(registry.peak_scale(Vector2i(3, 5)), 1.25),
		"fixture biome 脚本没有接入 peak scale"
	)
	_expect(
		&"volcanic" in registry.tags(Vector2i(3, 5), 7, fixture_id),
		"fixture biome tags 没有从定义生效"
	)
	_expect(
		&"ash_capable" in registry.weather_tags(Vector2i(3, 5), 7, fixture_id),
		"fixture biome weather_tags 没有从定义生效"
	)


func _run() -> void:
	var noise_registry := _test_dynamic_noise_registry()
	_test_builtin_modules(noise_registry)
	_test_definition_loaded_fixture(noise_registry)
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("BIOME_MODULES_CONTRACT_OK")
	quit(0)
