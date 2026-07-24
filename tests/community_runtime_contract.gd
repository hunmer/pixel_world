extends SceneTree

const EcologyRegistryScript = preload("res://scripts/ecology/ecology_registry.gd")
const CommunityRuntimeScript = preload("res://scripts/ecology/community_runtime.gd")
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
		_test_pond_takeover(catalog)
		_test_fauna_takeover(catalog)
		_test_aquatic_fauna(catalog)
		_test_temperate_birds(catalog)
		_test_definition_only_extension(catalog)
		_test_no_species_specific_runtime_branches()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("COMMUNITY_RUNTIME_CONTRACT_OK")
	quit(0)


func _configured_runtime(catalog: Dictionary) -> RefCounted:
	var runtime = CommunityRuntimeScript.new()
	_expect(runtime.configure(catalog), "CommunityRuntime 配置失败: %s" % runtime.last_error)
	return runtime


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
		Vector2i(19, -23),
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


func _test_pond_takeover(catalog: Dictionary) -> void:
	var runtime = _configured_runtime(catalog)
	if not runtime.is_configured():
		return
	var shallow_water = _context(&"plains", &"plains", 7, 2, true, false, &"soil")
	var resolved: Dictionary = runtime.resolve(shallow_water)
	_expect("pond_lilies" in resolved.get("community_ids", []), "pond_lilies 未经 resolver 命中")
	_expect(String(resolved.get("legacy_ecosystem_id", "")) == "water", "浅水 legacy ecosystem 错误")
	_expect(runtime.legacy_ecosystem_id(shallow_water) == "water", "legacy_ecosystem_id 兼容接口错误")

	var rules: Array[Dictionary] = runtime.flora_rules_for_cell(shallow_water)
	var water_rules := _rules_by_pool(rules, "water")
	_expect(water_rules.size() == 1, "first-class pond 与 legacy water pool 重复: %d" % water_rules.size())
	_expect(_rules_by_pool(rules, "underwater").size() == 1, "接管 pond 时误删 underwater legacy rule")
	if water_rules.size() == 1:
		var pond: Dictionary = water_rules[0]
		var pool: Array = pond.get("species", [])
		_expect(pool.count("lily_pad_stemmed") == 3, "weighted flora 未保留 stemmed 权重")
		_expect(pool.count("lily_pad_cluster") == 4, "weighted flora 未保留 cluster 权重")
		_expect(pool.count("pink_lotus") == 1, "weighted flora 未保留 lotus 权重")
		_expect(is_equal_approx(float(pond.get("chance", -1.0)), 0.06), "pond chance 未来自 first-class distribution")
		_expect(int(pond.get("placement_seed", -1)) == 502, "pond legacy placement seed 未保留")
		_expect(String(pond.get("selection_seed_key", "")) == "water", "pond stream_key 未成为 selection seed")
		_expect(int(pond.get("render_priority", -1)) == 12, "pond 未继承 legacy render compatibility 参数")
		_expect(int(pond.get("max_water_depth", -1)) == 2, "pond habitat water depth 未归一化")

	var raw_legacy: Dictionary = runtime.legacy_rules_by_ecosystem(&"flora")
	var raw_water: Array = raw_legacy.get("water", [])
	var raw_ponds := _rules_by_pool(raw_water, "water")
	_expect(raw_ponds.size() == 1, "raw legacy compatibility lookup 丢失 water pool")
	if raw_ponds.size() == 1:
		_expect(
			(raw_ponds[0].get("species", []) as Array).size() == 3,
			"legacy_rules_by_ecosystem 不应偷偷改写原始 bundle"
		)
	_expect(not runtime.warnings.is_empty(), "flora patch 到 legacy cell rule 的兼容差异未显式报告")


func _test_fauna_takeover(catalog: Dictionary) -> void:
	var runtime = _configured_runtime(catalog)
	if not runtime.is_configured():
		return
	var matching: Array[Dictionary] = []
	for source in runtime.fauna_sources():
		var rule: Dictionary = source.get("rule", {})
		if (
			String(source.get("source_biome_id", "")) == "snow"
			and String(rule.get("pool_id", "")) == "wolf_pack"
		):
			matching.append(source)
	_expect(matching.size() == 1, "wolf_pack first-class/legacy 重复: %d" % matching.size())
	if matching.size() != 1:
		return
	var source: Dictionary = matching[0]
	var rule: Dictionary = source["rule"]
	var distribution: Dictionary = rule.get("distribution", {})
	_expect(String(source.get("community_id", "")) == "wolf_pack", "wolf territory 未标记 first-class community source")
	_expect(bool(source.get("first_class", false)), "wolf_pack 未标记为 first-class source")
	var snow_context = _context(&"snow", &"mountain", 15, 0, false, false, &"snow")
	_expect(
		runtime.fauna_source_matches_context(source, snow_context),
		"first-class fauna source 未通过统一 habitat matcher"
	)
	_expect(rule.get("species", []) == ["wolf"], "fill_remaining 主物种未归一化")
	_expect(distribution.get("count", []) == [7, 8], "fauna count 丢失")
	_expect(int(distribution.get("anchor_spacing", 0)) == 36, "fauna anchor spacing 丢失")
	_expect(is_equal_approx(float(distribution.get("anchor_jitter", 0.0)), 0.45), "fauna anchor jitter 丢失")
	_expect(int(distribution.get("radius", -1)) == 4, "fauna radius 丢失")
	_expect(is_equal_approx(float(distribution.get("social_radius", -1.0)), 5.0), "fauna social radius 丢失")
	_expect(bool(distribution.get("same_ecosystem", false)), "habitat.same_biome 未映射为 same_ecosystem")
	var substitution: Dictionary = distribution.get("substitution", {})
	_expect(String(substitution.get("species", "")) == "husky", "single companion 未转为 substitution")
	_expect(is_equal_approx(float(substitution.get("chance", -1.0)), 0.35), "companion chance 丢失")
	_expect(int(substitution.get("max_count", 0)) == 1, "companion count 丢失")
	_expect(int(rule.get("placement_seed", 0)) == 508, "fauna metadata placement seed 丢失")

	var frog_sources: Array[Dictionary] = []
	for fauna_source in runtime.fauna_sources():
		var fauna_rule: Dictionary = fauna_source.get("rule", {})
		if String(fauna_rule.get("pool_id", "")) == "frog_cluster":
			frog_sources.append(fauna_source)
	_expect(frog_sources.size() == 1, "frog_cluster first-class/legacy 重复")
	if frog_sources.size() == 1:
		_expect(
			int((frog_sources[0]["rule"]["distribution"] as Dictionary).get("requires_water_within", 0)) == 10,
			"near_tag water 未映射到 legacy requires_water_within"
		)


func _test_aquatic_fauna(catalog: Dictionary) -> void:
	var runtime = _configured_runtime(catalog)
	if not runtime.is_configured():
		return
	var sources := {}
	for source_value in runtime.fauna_sources():
		var source: Dictionary = source_value
		var community_id := String(source.get("community_id", ""))
		if community_id in [
			"temperate_goldfish_school",
			"temperate_carp_school",
			"cold_salmon_school",
		]:
			sources[community_id] = source
	_expect(sources.size() == 3, "水域鱼群没有全部进入 fauna source")
	if sources.size() != 3:
		return
	var shallow_temperate = _context(
		&"plains", &"plains", 5, 1, true, false, &"water", [&"water", &"temperate"]
	)
	var deep_temperate = _context(
		&"plains", &"plains", 2, 4, true, false, &"water", [&"water", &"temperate"]
	)
	var cold_water = _context(
		&"snow", &"mountain", 2, 4, true, false, &"water", [&"water", &"snow", &"cold"]
	)
	_expect(
		runtime.fauna_source_matches_context(
			sources["temperate_goldfish_school"], shallow_temperate
		),
		"金鱼群没有命中温带浅水"
	)
	_expect(
		not runtime.fauna_source_matches_context(
			sources["temperate_goldfish_school"], deep_temperate
		),
		"金鱼群错误命中深水"
	)
	_expect(
		runtime.fauna_source_matches_context(
			sources["temperate_carp_school"], deep_temperate
		),
		"鲫鱼群没有命中温带较深水域"
	)
	_expect(
		runtime.fauna_source_matches_context(
			sources["cold_salmon_school"], cold_water
		),
		"鲑鱼群没有命中寒冷深水"
	)
	_expect(
		not runtime.fauna_source_matches_context(
			sources["cold_salmon_school"], deep_temperate
		),
		"鲑鱼群错误命中温带水域"
	)
	var goldfish_definition: Dictionary = sources["temperate_goldfish_school"]["definition"]
	_expect(
		bool((goldfish_definition["distribution"] as Dictionary).get("single_species", false)),
		"金鱼群没有启用单群单鱼种组合"
	)
	_expect(
		bool((goldfish_definition["metadata"] as Dictionary).get("allow_water", false)),
		"水域群落没有显式允许水格出生"
	)
	var goldfish_distribution: Dictionary = goldfish_definition["distribution"]
	var carp_distribution: Dictionary = (
		sources["temperate_carp_school"]["definition"]["distribution"]
	)
	_expect(
		int(goldfish_distribution.get("anchor_spacing", 0)) >= 20
		and int((goldfish_distribution.get("count", []) as Array)[1]) <= 3,
		"金鱼群密度仍会塞满小池塘"
	)
	_expect(
		int(carp_distribution.get("anchor_spacing", 0)) >= 30
		and float(carp_distribution.get("chance", 1.0)) <= 0.25,
		"鲫鱼群仍会与金鱼群频繁叠加"
	)


func _test_temperate_birds(catalog: Dictionary) -> void:
	var runtime = _configured_runtime(catalog)
	if not runtime.is_configured():
		return
	var temperate_land = _context(
		&"plains",
		&"plains",
		8,
		0,
		false,
		false,
		&"grass",
		[&"temperate", &"mild"]
	)
	var temperate_water = _context(
		&"plains",
		&"plains",
		5,
		1,
		true,
		false,
		&"water",
		[&"temperate", &"water"]
	)
	var land_rules := _rules_by_pool(
		runtime.ambient_rules_for_cell(temperate_land),
		"temperate_ground_birds"
	)
	var water_rules := _rules_by_pool(
		runtime.ambient_rules_for_cell(temperate_water),
		"temperate_ground_birds"
	)
	_expect(land_rules.size() == 1, "温带陆地没有解析出地面鸟群落")
	_expect(water_rules.is_empty(), "地面鸟群落错误生成在水面")
	if land_rules.size() == 1:
		_expect(land_rules[0].get("species", []) == ["bird"], "鸟群落没有只引用 bird 模块")
		_expect(
			float(land_rules[0].get("chance", 1.0)) <= 0.003,
			"地面鸟逐格概率过高"
		)
	var bird_species: Dictionary = catalog["species"]["ambient"].get("bird", {})
	_expect(
		String(bird_species.get("renderer_script", "")).ends_with("bird_renderer.gd"),
		"bird 没有独立 renderer 模块"
	)
	var bird_cluster_size: Array = bird_species.get("cluster_size", [])
	_expect(
		bird_cluster_size.size() == 2
		and int(bird_cluster_size[0]) == 1
		and int(bird_cluster_size[1]) == 1,
		"地面鸟仍允许在同一地块生成两个重叠成员: %s" % [
			JSON.stringify(bird_species.get("cluster_size", null))
		]
	)
	var bird_profile: Dictionary = bird_species.get("renderer_profile", {})
	var flyover_group_size: Array = bird_profile.get("flyover_group_size", [])
	_expect(
		float(bird_profile.get("flyover_group_chance", 0.0)) >= 0.70
		and flyover_group_size.size() == 2
		and int(flyover_group_size[0]) == 3
		and int(flyover_group_size[1]) == 6,
		"飞越鸟群概率或规模没有进入生态配置: %s" % [
			JSON.stringify(bird_profile)
		]
	)


func _test_definition_only_extension(catalog: Dictionary) -> void:
	var extended := catalog.duplicate(true)
	extended["species"]["plants"]["fixture_ash_bloom"] = {
		"layer": "decoration",
		"texture": "res://icon.svg",
	}
	extended["species"]["ambient"]["fixture_ember_mote"] = {
		"cluster_size": [2, 3],
		"max_visible": 10,
		"max_lights": 2,
	}
	extended["communities"]["fixture_volcanic_bloom"] = {
		"id": "fixture_volcanic_bloom",
		"kind": "flora",
		"stream_key": "fixture/volcanic/bloom",
		"habitat": {
			"required_tags": ["volcanic", "rocky"],
			"excluded_tags": ["water"],
			"near_tag": "geothermal",
			"near_tag_radius": 6,
		},
		"distribution": {"strategy": "scatter", "chance": 0.31},
		"members": [{
			"species_id": "fixture_ash_bloom",
			"category": "plant",
			"weight": 2.0,
		}],
	}
	extended["communities"]["fixture_volcanic_motes"] = {
		"id": "fixture_volcanic_motes",
		"kind": "ambient",
		"stream_key": "fixture/volcanic/motes",
		"habitat": {"required_tags": ["volcanic"], "excluded_tags": ["water"]},
		"distribution": {"chance": 0.27},
		"members": [{"species_id": "fixture_ember_mote", "category": "ambient"}],
	}
	extended["community_order"].append("fixture_volcanic_bloom")
	extended["community_order"].append("fixture_volcanic_motes")
	extended["biomes"]["fixture_volcanic"] = {
		"id": "fixture_volcanic",
		"classification_id": "fixture_volcanic",
		"match": {"biome": "fixture_volcanic"},
		"tags": ["volcanic", "hot"],
		"community_refs": [],
		"attachments": [
			{"community_id": "fixture_volcanic_bloom", "enabled": true},
			{"community_id": "fixture_volcanic_motes", "enabled": true},
		],
	}
	extended["biome_order"].append("fixture_volcanic")

	var runtime = _configured_runtime(extended)
	var second_runtime = _configured_runtime(extended)
	if not runtime.is_configured() or not second_runtime.is_configured():
		return
	var volcanic = _context(
		&"fixture_volcanic",
		&"mountain",
		13,
		0,
		false,
		false,
		&"basalt",
		[&"geothermal"]
	)
	var near_geothermal: Callable = func(_context_value, tag: StringName, _radius: float):
		return tag == &"geothermal"
	var flora: Array = runtime.flora_rules_for_cell(volcanic, near_geothermal)
	var blooms := _rules_by_pool(flora, "fixture_volcanic_bloom")
	_expect(blooms.size() == 1, "只新增 definition+attachment 的 volcanic flora 未进入 runtime")
	if blooms.size() == 1:
		_expect(blooms[0].get("species", []) == ["fixture_ash_bloom"], "volcanic flora member 未归一化")
		_expect(String(blooms[0].get("layer", "")) == "decoration", "volcanic species layer 未从 catalog 推导")
		_expect(is_equal_approx(float(blooms[0].get("chance", -1.0)), 0.31), "volcanic chance 丢失")
		var second_bloom := _rules_by_pool(
			second_runtime.flora_rules_for_cell(volcanic, near_geothermal),
			"fixture_volcanic_bloom"
		)
		_expect(second_bloom.size() == 1, "第二个 runtime 未生成 volcanic flora")
		if second_bloom.size() == 1:
			_expect(
				int(blooms[0].get("placement_seed", 0)) == int(second_bloom[0].get("placement_seed", -1))
				and int(blooms[0].get("placement_seed", 0)) != 0,
				"无 legacy metadata 时 placement seed 不稳定"
			)
	var spatial_sources: Array[Dictionary] = []
	for source_value in runtime.spatial_flora_sources():
		var source: Dictionary = source_value
		if String(source.get("community_id", "")) == "fixture_volcanic_bloom":
			spatial_sources.append(source)
	_expect(spatial_sources.size() == 1, "新 flora definition 未进入通用 spatial source")
	if spatial_sources.size() == 1:
		_expect(
			runtime.flora_source_matches_context(
				spatial_sources[0], volcanic, near_geothermal
			),
			"spatial flora source 未复用统一 habitat matcher"
		)
		_expect(
			_rules_by_pool(
				runtime.cell_flora_rules_for_cell(volcanic, near_geothermal),
				"fixture_volcanic_bloom"
			).is_empty(),
			"spatial flora 同时进入 legacy cell loop，可能重复生成"
		)
	var ambient: Array = runtime.ambient_rules_for_cell(volcanic, near_geothermal)
	var motes := _rules_by_pool(ambient, "fixture_volcanic_motes")
	_expect(motes.size() == 1, "只新增 definition+attachment 的 volcanic ambient 未进入 runtime")
	if motes.size() == 1:
		_expect(motes[0].get("species", []) == ["fixture_ember_mote"], "volcanic ambient member 未归一化")


func _test_no_species_specific_runtime_branches() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ecology/community_runtime.gd").to_lower()
	for forbidden_id in ["wolf", "firefly", "lily"]:
		_expect(
			not source.contains(forbidden_id),
			"CommunityRuntime 包含物种/群落特判: %s" % forbidden_id
		)


func _rules_by_pool(rules: Array, pool_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rule_value in rules:
		if (
			rule_value is Dictionary
			and String(rule_value.get("pool_id", "")) == pool_id
		):
			result.append(rule_value)
	return result
