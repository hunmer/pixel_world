extends SceneTree

const EcologyRegistryScript = preload("res://scripts/ecology/ecology_registry.gd")
const TerrainSamplerScript = preload("res://scripts/world/terrain_sampler.gd")
const TerrainMaterialRegistryScript = preload(
	"res://scripts/world/terrain_material_registry.gd"
)
const CommunityRuntimeScript = preload("res://scripts/ecology/community_runtime.gd")
const AnimalBehaviorRegistryScript = preload(
	"res://scripts/animals/animal_behavior_registry.gd"
)
const HeatAffinityScorerScript = preload(
	"res://tests/fixtures/module_extension_heat_affinity_scorer.gd"
)

const MANIFEST_PATH := "res://tests/fixtures/module_extension_manifest.json"
const BIOME_ID := &"fixture_volcanic_caldera"
const LANDFORM_ID := &"fixture_caldera_plateau"
const NOISE_FIELD_ID := &"fixture_caldera_heat"
const SURFACE_ID := &"fixture_basalt_crust"
const FLORA_COMMUNITY_ID := "fixture_ash_fern_patch"
const AMBIENT_COMMUNITY_ID := "fixture_ember_cloud"
const FAUNA_COMMUNITY_ID := "fixture_lava_skink_colony"
const ANIMAL_ID := "fixture_lava_skink"
const BEHAVIOR_ID := &"fixture_heat_affinity"

const CORE_EXTENSION_POINTS := [
	"res://scripts/ecology/ecology_registry.gd",
	"res://scripts/world/terrain_sampler.gd",
	"res://scripts/world/terrain_material_registry.gd",
	"res://scripts/ecology/community_runtime.gd",
	"res://scripts/animals/animal_behavior_registry.gd",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var ecology_registry = EcologyRegistryScript.new()
	_expect(
		ecology_registry.load_manifest(MANIFEST_PATH),
		"test-only volcanic manifest 加载失败: %s" % ecology_registry.get_error_text()
	)
	if not ecology_registry.is_loaded():
		_finish()
		return

	var catalog: Dictionary = ecology_registry.get_catalog()
	_test_catalog_loaded(catalog)
	var terrain_result := _test_terrain_pipeline(catalog)
	var volcanic_context: Variant = terrain_result.get("context", null)
	if volcanic_context != null:
		_test_material_pipeline(catalog, volcanic_context)
		_test_community_pipeline(catalog, volcanic_context)
		_test_behavior_pipeline(catalog, volcanic_context)
	_test_core_has_no_extension_ids()
	_finish()


func _test_catalog_loaded(catalog: Dictionary) -> void:
	_expect(
		(catalog.get("biomes", {}) as Dictionary).has(String(BIOME_ID)),
		"EcologyRegistry 未从 fixture catalog 注册 volcanic biome"
	)
	_expect(
		(catalog.get("communities", {}) as Dictionary).has(FLORA_COMMUNITY_ID)
		and (catalog.get("communities", {}) as Dictionary).has(AMBIENT_COMMUNITY_ID)
		and (catalog.get("communities", {}) as Dictionary).has(FAUNA_COMMUNITY_ID),
		"EcologyRegistry 未加载 volcanic flora/ambient/fauna communities"
	)
	_expect(
		(catalog.get("species", {}) as Dictionary)
		.get("animals", {})
		.has(ANIMAL_ID),
		"EcologyRegistry 未加载 volcanic animal species"
	)
	var biome: Dictionary = (catalog.get("biomes", {}) as Dictionary).get(
		String(BIOME_ID),
		{}
	)
	_expect(
		String(biome.get("script", ""))
		== "res://tests/fixtures/module_extension_volcanic_biome.gd",
		"biome module script path 未经 manifest 正确解析"
	)
	_expect(
		String(catalog.get("default_biome_id", "")) == String(BIOME_ID),
		"fixture world default_biome_id 未保留"
	)


func _test_terrain_pipeline(catalog: Dictionary) -> Dictionary:
	var world: Dictionary = catalog.get("world", {})
	var generation: Dictionary = world.get("generation", {})
	var central_noise_fields: Dictionary = (
		(generation.get("noise", {}) as Dictionary).get("fields", {})
	)
	_expect(
		not central_noise_fields.has(String(NOISE_FIELD_ID)),
		"volcanic heat field 错误放进 world central noise config"
	)

	var sampler = TerrainSamplerScript.new()
	_expect(
		sampler.configure(generation, catalog.get("biomes", {}), 424242),
		"TerrainSampler 无法加载外部 volcanic module: %s" % sampler.last_error
	)
	if not sampler.configured:
		return {}
	_expect(
		sampler.noise_registry.has_field(NOISE_FIELD_ID),
		"BiomeRegistry 未把 module-local volcanic heat field 注册进 NoiseRegistry"
	)
	var heat_definition: Dictionary = sampler.noise_registry.field_definition(NOISE_FIELD_ID)
	_expect(
		int(heat_definition.get("seed_offset", 0)) == 2201,
		"module-local heat noise definition 未保留"
	)
	_expect(
		sampler.biome_registry.module_for_biome(BIOME_ID) != null,
		"TerrainSampler 的 BiomeRegistry 无法按动态 id 找到 volcanic module"
	)

	var volcanic_context: Variant = _find_surface_context(sampler, SURFACE_ID)
	_expect(volcanic_context != null, "volcanic module 未在 TerrainSampler 中生成 basalt surface")
	if volcanic_context == null:
		return {}
	_expect(
		StringName(volcanic_context.get("biome_id")) == BIOME_ID,
		"TerrainSampler 未使用 volcanic module classification"
	)
	_expect(
		StringName(volcanic_context.get("landform_id")) == LANDFORM_ID,
		"配置新增的 landform id 未进入 CellContext"
	)
	_expect(
		StringName(volcanic_context.get("surface_id")) == SURFACE_ID,
		"volcanic module 的自定义 surface id 未进入 CellContext"
	)
	_expect(volcanic_context.has_tag(&"volcanic"), "biome definition tags 未进入 CellContext")
	_expect(volcanic_context.has_tag(&"geothermal"), "volcanic geothermal tag 未进入 CellContext")

	var second_sampler = TerrainSamplerScript.new()
	_expect(
		second_sampler.configure(generation, catalog.get("biomes", {}), 424242),
		"同 seed 第二个 TerrainSampler 配置失败"
	)
	if second_sampler.configured:
		var cell: Vector2i = volcanic_context.get("cell")
		var second_context = second_sampler.sample(cell)
		_expect(
			int(second_context.get("height")) == int(volcanic_context.get("height"))
			and StringName(second_context.get("biome_id")) == BIOME_ID
			and StringName(second_context.get("surface_id")) == SURFACE_ID,
			"外部 biome module 的同 seed 采样不确定"
		)
		_expect(
			is_equal_approx(
				sampler.noise(NOISE_FIELD_ID, cell),
				second_sampler.noise(NOISE_FIELD_ID, cell)
			),
			"module-local noise field 的同 seed 采样不确定"
		)
	return {"context": volcanic_context}


func _test_material_pipeline(catalog: Dictionary, volcanic_context: Variant) -> void:
	var registry = TerrainMaterialRegistryScript.new()
	var generation: Dictionary = (
		(catalog.get("world", {}) as Dictionary).get("generation", {})
	)
	_expect(
		registry.load_from_generation(generation, "fixture world materials"),
		"TerrainMaterialRegistry 无法加载 fixture world materials"
	)
	_expect(
		not registry.has_surface(SURFACE_ID),
		"volcanic basalt surface 错误出现在 central world materials"
	)
	_expect(
		registry.load_biome_catalog(
			catalog.get("biomes", {}),
			catalog.get("biome_order", []),
			"fixture biome catalog"
		),
		"TerrainMaterialRegistry 无法加载 biome-local material: %s"
		% str(registry.get_errors())
	)
	_expect(registry.has_surface(SURFACE_ID), "biome-local basalt material 未注册")
	var material: Dictionary = registry.resolve(
		StringName(volcanic_context.get("surface_id")),
		StringName(volcanic_context.get("biome_id"))
	)
	_expect(not material.is_empty(), "CellContext surface 无法解析为材质")
	_expect(not bool(material.get("used_fallback", true)), "已注册 basalt 错误走 fallback")
	_expect(&"igneous" in material.get("tags", []), "basalt material tags 丢失")
	_expect(bool((material.get("traits", {}) as Dictionary).get("emits_heat", false)), "basalt trait 丢失")
	_expect(
		(material.get("minimap_color") as Color).is_equal_approx(
			Color(0.12, 0.07, 0.08, 1.0)
		),
		"biome-local basalt minimap color 未生效"
	)


func _test_community_pipeline(catalog: Dictionary, volcanic_context: Variant) -> void:
	var runtime = CommunityRuntimeScript.new()
	_expect(
		runtime.configure(catalog),
		"CommunityRuntime 无法配置 volcanic catalog: %s" % runtime.last_error
	)
	if not runtime.is_configured():
		return
	var resolution: Dictionary = runtime.resolve(volcanic_context)
	var community_ids: Array = resolution.get("community_ids", [])
	for expected_id in [FLORA_COMMUNITY_ID, AMBIENT_COMMUNITY_ID, FAUNA_COMMUNITY_ID]:
		_expect(
			expected_id in community_ids,
			"volcanic attachment 未经统一 resolver 命中: %s" % expected_id
		)

	var flora_rules: Array[Dictionary] = runtime.flora_rules_for_cell(volcanic_context)
	var flora_rule := _rule_for_pool(flora_rules, FLORA_COMMUNITY_ID)
	_expect(not flora_rule.is_empty(), "volcanic flora community 未归一化为 spawn rule")
	_expect(
		flora_rule.get("species", []) == ["fixture_ash_fern"],
		"volcanic flora member 未进入 spawn rule"
	)
	_expect(
		String(flora_rule.get("layer", "")) == "ground_cover",
		"volcanic flora layer 未从 species catalog 推导"
	)
	var spatial_flora_sources: Array[Dictionary] = []
	for source_value in runtime.spatial_flora_sources():
		var source: Dictionary = source_value
		if String(source.get("community_id", "")) == FLORA_COMMUNITY_ID:
			spatial_flora_sources.append(source)
	_expect(spatial_flora_sources.size() == 1, "volcanic flora 未进入通用 spatial planner source")
	if spatial_flora_sources.size() == 1:
		_expect(
			runtime.flora_source_matches_context(
				spatial_flora_sources[0], volcanic_context
			),
			"volcanic spatial flora source 未通过 habitat matcher"
		)

	var ambient_rules: Array[Dictionary] = runtime.ambient_rules_for_cell(volcanic_context)
	var ambient_rule := _rule_for_pool(ambient_rules, AMBIENT_COMMUNITY_ID)
	_expect(not ambient_rule.is_empty(), "volcanic ambient community 未归一化")
	_expect(
		ambient_rule.get("species", []) == ["fixture_ember_swarm"],
		"volcanic ambient member 未进入 spawn rule"
	)

	var fauna_sources: Array[Dictionary] = []
	for source in runtime.fauna_sources():
		if (
			String(source.get("source_biome_id", "")) == String(BIOME_ID)
			and String(source.get("community_id", "")) == FAUNA_COMMUNITY_ID
		):
			fauna_sources.append(source)
	_expect(fauna_sources.size() == 1, "volcanic fauna attachment 未生成唯一 source")
	if fauna_sources.size() == 1:
		var source: Dictionary = fauna_sources[0]
		_expect(bool(source.get("first_class", false)), "volcanic fauna 未标记 first-class")
		_expect(
			source.get("definition", {}) is Dictionary
			and not (source.get("definition", {}) as Dictionary).is_empty(),
			"volcanic fauna source 未携带通用群落定义"
		)
		_expect(
			runtime.fauna_source_matches_context(source, volcanic_context),
			"volcanic fauna source 未复用统一 habitat matcher"
		)
		var rule: Dictionary = source.get("rule", {})
		_expect(rule.get("species", []) == [ANIMAL_ID], "volcanic fauna member 未归一化")
		_expect(
			(rule.get("distribution", {}) as Dictionary).get("count", []) == [2, 4],
			"volcanic fauna distribution 丢失"
		)


func _test_behavior_pipeline(catalog: Dictionary, volcanic_context: Variant) -> void:
	var animal: Dictionary = (
		(catalog.get("species", {}) as Dictionary)
		.get("animals", {})
		.get(ANIMAL_ID, {})
	)
	var candidate := {
		"cell": volcanic_context.get("cell"),
		"height": volcanic_context.get("height"),
		"surface_id": volcanic_context.get("surface_id"),
		"tags": volcanic_context.tag_list(),
	}
	var context := {"current": candidate.duplicate(true)}
	var registry = AnimalBehaviorRegistryScript.new()
	_expect(not registry.has_scorer(BEHAVIOR_ID), "fixture behavior 意外成为内置 scorer")
	var before_registration: Dictionary = registry.evaluate_species(animal, candidate, context)
	_expect(
		not bool(before_registration.get("allowed", true))
		and "unknown_behavior:%s" % String(BEHAVIOR_ID)
		in before_registration.get("errors", []),
		"未注册 custom behavior 没有明确拒绝"
	)
	_expect(
		registry.register_scorer(BEHAVIOR_ID, HeatAffinityScorerScript),
		"外部 volcanic behavior Script 注册失败"
	)
	var decision: Dictionary = registry.evaluate_species(animal, candidate, context)
	_expect(bool(decision.get("allowed", false)), "注册 custom behavior 后合法 basalt 候选被拒绝")
	_expect(
		is_equal_approx(float(decision.get("score", 0.0)), 6.0),
		"custom heat affinity scorer 未贡献配置权重"
	)
	_expect(
		bool((decision.get("state", {}) as Dictionary).get("fixture_heat_affinity_ran", false)),
		"custom volcanic behavior scorer 未执行"
	)
	_expect(
		decision.get("contributions", []).size() == 3,
		"custom behavior 与已有 surface/step constraints 未组合成行为栈"
	)


func _test_core_has_no_extension_ids() -> void:
	var extension_ids := [
		String(BIOME_ID),
		String(LANDFORM_ID),
		String(NOISE_FIELD_ID),
		String(SURFACE_ID),
		FLORA_COMMUNITY_ID,
		AMBIENT_COMMUNITY_ID,
		FAUNA_COMMUNITY_ID,
		ANIMAL_ID,
		String(BEHAVIOR_ID),
	]
	for path in CORE_EXTENSION_POINTS:
		var source := FileAccess.get_file_as_string(path)
		for extension_id in extension_ids:
			_expect(
				not source.contains(extension_id),
				"核心扩展点含 volcanic fixture 特判: %s -> %s" % [path, extension_id]
			)


func _find_surface_context(sampler: RefCounted, surface_id: StringName) -> Variant:
	for x in range(-64, 65, 4):
		for y in range(-64, 65, 4):
			var context = sampler.sample(Vector2i(x, y))
			if StringName(context.get("surface_id")) == surface_id:
				return context
	return null


func _rule_for_pool(rules: Array[Dictionary], pool_id: String) -> Dictionary:
	for rule in rules:
		if String(rule.get("pool_id", "")) == pool_id:
			return rule
	return {}


func _finish() -> void:
	if failures.is_empty():
		print("MODULE_EXTENSION_CONTRACT_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
