extends SceneTree

const EcologyRegistryScript = preload("res://scripts/ecology/ecology_registry.gd")
const EcologyResolverScript = preload("res://scripts/ecology/ecology_resolver.gd")
const CellContextScript = preload("res://scripts/world/cell_context.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var registry = EcologyRegistryScript.new()
	_expect(
		registry.load_manifest("res://config/ecology/manifest.json"),
		"无法加载 modular ecology catalog: %s" % registry.get_error_text()
	)
	if registry.is_loaded():
		var catalog: Dictionary = registry.get_catalog()
		_test_additive_desert_water(catalog)
		_test_reusable_pond_attachment(catalog)
		_test_kind_filtered_resolution(catalog)
		_test_attachment_override_and_order(catalog)
		_test_definition_driven_volcanic_extension(catalog)
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("ECOLOGY_RESOLVER_CONTRACT_OK")
	quit(0)


func _configured_resolver(catalog: Dictionary) -> RefCounted:
	var resolver = EcologyResolverScript.new()
	_expect(resolver.configure(catalog), "EcologyResolver 配置失败: %s" % resolver.last_error)
	return resolver


func _context(
	biome_id: StringName,
	landform_id: StringName,
	height: int,
	water_depth: int,
	is_water: bool,
	is_shore: bool,
	surface_id: StringName,
	tags: Array[StringName] = []
) -> RefCounted:
	return CellContextScript.new(
		Vector2i(11, -7),
		height,
		biome_id,
		-1,
		landform_id,
		-1,
		water_depth,
		is_water,
		is_shore,
		surface_id,
		Vector2i.ZERO,
		tags
	)


func _test_additive_desert_water(catalog: Dictionary) -> void:
	var resolver = _configured_resolver(catalog)
	var desert_water = _context(&"desert", &"hills", 8, 1, true, false, &"sand")
	var resolved: Dictionary = resolver.resolve(desert_water)
	_expect(String(resolved["base_biome_id"]) == "desert", "沙漠水格丢失基础 desert biome")
	_expect("desert" in resolved["matched_biome_ids"], "沙漠基础层没有参与 additive resolution")
	_expect("desert_water" in resolved["matched_biome_ids"], "desert_water habitat 层没有匹配")
	_expect("water" in resolved["matched_biome_ids"], "通用 water habitat 层没有与沙漠组合")
	_expect("pond_lilies" in resolved["community_ids"], "浅水 attachment 没有叠加到 desert+water")
	for legacy_id in ["desert", "desert_water", "water"]:
		_expect(legacy_id not in resolved["community_ids"], "legacy_bundle 混入 additive communities: %s" % legacy_id)
	for expected_tag in [&"desert", &"arid", &"water", &"shallow_water", &"hills", &"sand"]:
		_expect(expected_tag in resolved["tags"], "沙漠水格缺少 tag: %s" % expected_tag)

	var legacy: Dictionary = resolver.resolve_legacy_first_match(desert_water)
	_expect(bool(legacy["matched"]), "legacy first-match 没有结果")
	_expect(String(legacy["biome_rule_id"]) == "desert_water", "legacy first-match 顺序发生变化")
	_expect(String(legacy["community_id"]) == "desert_water", "legacy bundle 映射错误")


func _test_reusable_pond_attachment(catalog: Dictionary) -> void:
	var resolver = _configured_resolver(catalog)
	var desert_water = _context(&"desert", &"hills", 8, 2, true, false, &"sand")
	var temperate_water = _context(&"plains", &"plains", 7, 2, true, false, &"soil")
	var deep_temperate_water = _context(&"plains", &"plains", 7, 3, true, false, &"soil")
	var desert_result: Dictionary = resolver.resolve(desert_water)
	var temperate_result: Dictionary = resolver.resolve(temperate_water)
	var deep_result: Dictionary = resolver.resolve(deep_temperate_water)
	_expect("pond_lilies" in desert_result["community_ids"], "pond_lilies 无法复用于沙漠浅水")
	_expect("pond_lilies" in temperate_result["community_ids"], "pond_lilies 无法复用于温带浅水")
	_expect("pond_lilies" not in deep_result["community_ids"], "pond_lilies 忽略 maximum_water_depth")
	_expect(
		String(desert_result["community_sources"].get("pond_lilies", "")) == "water"
		and String(temperate_result["community_sources"].get("pond_lilies", "")) == "water",
		"同一 pond_lilies definition 没有通过通用 water attachment 复用"
	)
	_expect(String(temperate_result["base_biome_id"]) == "temperate", "plains classification 没有解析到温带模块")


func _test_kind_filtered_resolution(catalog: Dictionary) -> void:
	var resolver = _configured_resolver(catalog)
	var shallow_water = _context(&"plains", &"plains", 7, 2, true, false, &"soil")
	var query_state := {"calls": 0}
	var near_tag_query: Callable = func(_cell, _tag, _radius):
		query_state["calls"] = int(query_state["calls"]) + 1
		return false
	var flora_result: Dictionary = resolver.resolve_kind(
		shallow_water,
		&"flora",
		near_tag_query
	)
	_expect(
		flora_result["community_ids"] == ["pond_lilies"],
		"flora-only resolution 混入了其他层级: %s" % [flora_result["community_ids"]]
	)
	_expect(
		int(query_state["calls"]) == 0,
		"flora-only resolution 仍然评估了青蛙等 fauna 的 near_tag habitat"
	)


func _test_attachment_override_and_order(catalog: Dictionary) -> void:
	var customized := catalog.duplicate(true)
	var temperate: Dictionary = customized["biomes"]["temperate"]
	temperate["attachments"].push_front({
		"community_id": "pond_lilies",
		"enabled": true,
		"weight": 0.25,
		"overrides": {
			"habitat": {
				"required_tags": ["water"],
				"maximum_water_depth": 9,
			},
			"distribution": {"chance": 0.95},
		},
	})
	# Disabled attachments never enter the candidate stream.
	temperate["attachments"].append({
		"community_id": "wolf_pack",
		"enabled": false,
	})
	var resolver = _configured_resolver(customized)
	var context = _context(&"plains", &"plains", 7, 4, true, false, &"soil")
	var result: Dictionary = resolver.resolve(context)
	_expect(result["community_ids"].count("pond_lilies") == 1, "多个 attachment 没有稳定去重")
	_expect(String(result["community_ids"][0]) == "pond_lilies", "基础 biome attachment 没有优先于 habitat 层")
	_expect(
		result["community_weights"].has("pond_lilies")
		and is_equal_approx(float(result["community_weights"]["pond_lilies"]), 0.25),
		"attachment weight 丢失"
	)
	var pond := _definition_by_id(result["community_definitions"], "pond_lilies")
	_expect(is_equal_approx(float(pond["distribution"]["chance"]), 0.95), "attachment distribution override 未合并")
	_expect(String(pond["distribution"]["strategy"]) == "patch", "深度 override 覆盖掉未修改字段")
	_expect("wolf_pack" not in result["community_ids"], "disabled attachment 仍然生效")

	var land_context = _context(&"plains", &"plains", 7, 0, false, false, &"soil")
	var no_near_tag: Callable = func(_cell, _tag, _radius): return false
	var land_result: Dictionary = resolver.resolve(land_context, no_near_tag)
	_expect(
		land_result["community_ids"] == [
			"dog_solitary",
			"fox_solitary",
			"pig_family",
			"temperate_ground_birds",
		],
		"community 声明顺序不稳定或 near_tag 过滤错误: %s" % [land_result["community_ids"]]
	)


func _test_definition_driven_volcanic_extension(catalog: Dictionary) -> void:
	var extended := catalog.duplicate(true)
	extended["communities"]["fixture_volcanic_bloom"] = {
		"id": "fixture_volcanic_bloom",
		"kind": "flora",
		"habitat": {
			"required_tags": ["volcanic", "rocky"],
			"excluded_tags": ["water"],
			"biome_ids": ["fixture_volcanic"],
			"landform_ids": ["mountain"],
			"min_height": 10,
			"max_height": 20,
			"min_water_depth": 0,
			"max_water_depth": 0,
			"near_tag": "geothermal",
			"near_tag_radius": 6,
		},
		"distribution": {"strategy": "patch", "chance": 0.2, "count": [2, 4], "radius": 2},
		"members": [{"species_id": "fixture_volcanic_flower", "category": "plant"}],
	}
	extended["community_order"].append("fixture_volcanic_bloom")
	extended["biomes"]["fixture_volcanic"] = {
		"id": "fixture_volcanic",
		"match": {"biome": "fixture_volcanic"},
		"tags": ["volcanic", "hot"],
		"community_refs": [],
		"attachments": [
			{
				"community_id": "fixture_volcanic_bloom",
				"weight": 0.4,
				"overrides": {"distribution": {"chance": 0.8}},
			},
		],
	}
	extended["biome_order"].append("fixture_volcanic")
	var resolver = _configured_resolver(extended)
	var volcanic = _context(
		&"fixture_volcanic",
		&"mountain",
		12,
		0,
		false,
		false,
		&"basalt"
	)
	var near_geothermal: Callable = func(_cell, tag: StringName, radius: float):
		return tag == &"geothermal" and is_equal_approx(radius, 6.0)
	var result: Dictionary = resolver.resolve(volcanic, near_geothermal)
	_expect("fixture_volcanic_bloom" in result["community_ids"], "新增 volcanic community 需要修改 resolver")
	_expect(&"volcanic" in result["tags"] and &"rocky" in result["tags"], "新增 biome tags 没有参与 habitat")
	_expect(is_equal_approx(float(result["community_weights"]["fixture_volcanic_bloom"]), 0.4), "volcanic attachment weight 丢失")
	var bloom := _definition_by_id(result["community_definitions"], "fixture_volcanic_bloom")
	_expect(is_equal_approx(float(bloom["distribution"]["chance"]), 0.8), "volcanic attachment override 丢失")

	var no_near_tag: Callable = func(_cell, _tag, _radius): return false
	_expect(
		"fixture_volcanic_bloom" not in resolver.resolve(volcanic, no_near_tag)["community_ids"],
		"near_tag Callable 没有约束 community"
	)
	var too_low = _context(&"fixture_volcanic", &"mountain", 9, 0, false, false, &"basalt")
	_expect(
		"fixture_volcanic_bloom" not in resolver.resolve(too_low, near_geothermal)["community_ids"],
		"min_height 没有约束 community"
	)
	var flooded = _context(&"fixture_volcanic", &"mountain", 12, 1, true, false, &"basalt")
	_expect(
		"fixture_volcanic_bloom" not in resolver.resolve(flooded, near_geothermal)["community_ids"],
		"excluded_tags/max_water_depth 没有约束 community"
	)


func _definition_by_id(definitions: Array, community_id: String) -> Dictionary:
	for definition_value in definitions:
		if definition_value is Dictionary and String(definition_value.get("id", "")) == community_id:
			return definition_value
	return {}
