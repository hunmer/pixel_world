extends SceneTree

const EcologyRegistryScript = preload("res://scripts/ecology/ecology_registry.gd")
const NoiseRegistryScript = preload("res://scripts/world/noise_registry.gd")
const BiomeRegistryScript = preload("res://scripts/world/biomes/biome_registry.gd")
const MANIFEST_PATH := "res://config/ecology/manifest.json"
const LEGACY_PATH := "res://config/ecosystems.json"
const REQUIRED_COMMUNITIES := [
	"pond_lilies",
	"wolf_pack",
	"dog_solitary",
	"fox_solitary",
	"pig_family",
	"frog_cluster",
	"temperate_ground_birds",
]
const EXPECTED_ATTACHMENTS := {
	"water": ["pond_lilies"],
	"snow": ["wolf_pack"],
	"temperate": [
		"dog_solitary",
		"fox_solitary",
		"pig_family",
		"frog_cluster",
		"temperate_ground_birds",
	],
}
const FIXTURE_ROOT := "user://config_manifest_contract"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	_test_real_manifest()
	_test_extension_modules()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("CONFIG_MANIFEST_CONTRACT_OK")
	quit(0)


func _test_real_manifest() -> void:
	var registry = EcologyRegistryScript.new()
	_expect(
		registry.load_manifest(MANIFEST_PATH),
		"真实 modular manifest 无法加载: %s" % registry.get_error_text()
	)
	if not registry.is_loaded():
		return

	var legacy := _read_json(LEGACY_PATH)
	var exported: Dictionary = registry.to_legacy_config()
	for runtime_field in [
		"version",
		"default_ecosystem",
		"generation",
		"species",
		"pool_selection",
		"ecosystems",
	]:
		_expect(
			exported.get(runtime_field) == legacy.get(runtime_field),
			"模块化 round-trip 改变了运行时字段: %s" % runtime_field
		)

	var catalog: Dictionary = registry.get_catalog()
	_expect(String(catalog.get("default_biome_id", "")) == "temperate", "默认 biome ID 错误")
	for community_id in REQUIRED_COMMUNITIES:
		_expect(
			(catalog["communities"] as Dictionary).has(community_id),
			"缺少一等 community: %s" % community_id
		)
		if (catalog["communities"] as Dictionary).has(community_id):
			var community: Dictionary = catalog["communities"][community_id]
			_expect(not String(community.get("kind", "")).is_empty(), "community kind 为空: %s" % community_id)
			_expect(not (community.get("members", []) as Array).is_empty(), "community 没有 members: %s" % community_id)

	for biome_id in EXPECTED_ATTACHMENTS:
		var biome: Dictionary = catalog["biomes"].get(biome_id, {})
		var attached_ids := _attachment_ids(biome)
		for community_id in EXPECTED_ATTACHMENTS[biome_id]:
			_expect(
				community_id in attached_ids,
				"biome %s 没有 attachment %s" % [biome_id, community_id]
			)

	var desert: Dictionary = catalog["biomes"].get("desert", {})
	var snow: Dictionary = catalog["biomes"].get("snow", {})
	var temperate: Dictionary = catalog["biomes"].get("temperate", {})
	_expect(String(desert.get("script", "")).ends_with("desert_biome.gd"), "沙漠 terrain module 未接入")
	_expect(int(desert.get("priority", 0)) == 300, "沙漠 terrain module priority 错误")
	_expect(String(desert.get("transition_id", "")) == "desert_transition", "沙漠过渡 ID 丢失")
	_expect(desert.get("profile", {}) == legacy["generation"]["biome_profiles"]["desert"], "沙漠 profile 与旧配置不一致")
	_expect(String(snow.get("script", "")).ends_with("snow_biome.gd"), "雪地 terrain module 未接入")
	_expect(int(snow.get("priority", 0)) == 200, "雪地 terrain module priority 错误")
	_expect(snow.get("profile", {}) == legacy["generation"]["climate"], "雪地 profile 与旧配置不一致")
	_expect(String(temperate.get("script", "")).ends_with("temperate_biome.gd"), "温带 terrain module 未接入")
	_expect(int(temperate.get("priority", 0)) == -100, "温带 terrain module priority 错误")
	_expect(String(temperate.get("classification_id", "")) == "plains", "温带 classification_id 错误")

	var noise_registry = NoiseRegistryScript.new()
	_expect(
		noise_registry.configure(catalog["world"]["generation"]["noise"], 42),
		"真实 world noise 配置无法装载: %s" % noise_registry.last_error
	)
	var biome_registry = BiomeRegistryScript.new()
	_expect(
		biome_registry.configure(catalog["biomes"], noise_registry),
		"真实 terrain biome modules 无法装载: %s" % biome_registry.last_error
	)
	_expect(
		biome_registry.module_ids() == [&"desert", &"snow", &"temperate"],
		"terrain biome module priority/启用状态错误: %s" % [biome_registry.module_ids()]
	)


func _test_extension_modules() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_ROOT))
	var fixture_species_path := FIXTURE_ROOT.path_join("volcanic_species.json")
	var fixture_community_path := FIXTURE_ROOT.path_join("volcanic_community.json")
	var fixture_biome_path := FIXTURE_ROOT.path_join("volcanic_biome.json")
	_write_json(fixture_species_path, {
		"version": 1,
		"kind": "species",
		"species": {
			"plants": {
				"fixture_volcanic_flower": {
					"layer": "ground_cover",
					"texture": "res://icon.svg",
				},
			},
			"animals": {},
			"ambient": {},
		},
	})
	_write_json(fixture_community_path, {
		"version": 1,
		"kind": "communities",
		"communities": [
			{
				"id": "fixture_volcanic_bloom",
				"kind": "flora",
				"habitat": {"required_tags": ["volcanic"]},
				"distribution": {"strategy": "patch", "count": [2, 4], "radius": 2},
				"members": [
					{"species_id": "fixture_volcanic_flower", "category": "plant", "weight": 1.0},
				],
			},
		],
	})
	_write_json(fixture_biome_path, {
		"version": 1,
		"kind": "biomes",
		"biomes": [
			{
				"id": "fixture_volcanic",
				"script": "res://tests/fixtures/volcanic_biome.gd",
				"priority": 9000,
				"match": {"biome": "fixture_volcanic"},
				"community_refs": [],
				"attachments": [{"community_id": "fixture_volcanic_bloom", "enabled": true}],
				"tags": ["volcanic", "hot"],
				"weather_tags": ["ash_capable"],
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
		],
	})

	var base_manifest := _read_json(MANIFEST_PATH)
	var extended_modules: Array = []
	for module_value in base_manifest.get("modules", []):
		var module: Dictionary = module_value.duplicate(true)
		module["path"] = "res://config/ecology".path_join(String(module["path"]))
		extended_modules.append(module)
	extended_modules.append({"kind": "species", "path": fixture_species_path})
	extended_modules.append({"kind": "communities", "path": fixture_community_path})
	extended_modules.append({"kind": "biomes", "path": fixture_biome_path})
	var extended_manifest_path := FIXTURE_ROOT.path_join("manifest.json")
	_write_json(extended_manifest_path, {"version": 1, "modules": extended_modules})

	var registry = EcologyRegistryScript.new()
	_expect(
		registry.load_manifest(extended_manifest_path),
		"新增 biome/community/species 模块需要修改主程序: %s" % registry.get_error_text()
	)
	if not registry.is_loaded():
		return
	var catalog: Dictionary = registry.get_catalog()
	_expect(
		(catalog["species"]["plants"] as Dictionary).has("fixture_volcanic_flower"),
		"扩展 species 未注册"
	)
	_expect(
		(catalog["communities"] as Dictionary).has("fixture_volcanic_bloom"),
		"扩展 community 未注册"
	)
	_expect(
		(catalog["biomes"] as Dictionary).has("fixture_volcanic"),
		"扩展 biome 未注册"
	)
	var noise_registry = NoiseRegistryScript.new()
	_expect(
		noise_registry.configure(catalog["world"]["generation"]["noise"], 42),
		"扩展测试 noise registry 初始化失败: %s" % noise_registry.last_error
	)
	var biome_registry = BiomeRegistryScript.new()
	_expect(
		biome_registry.configure(catalog["biomes"], noise_registry),
		"新增 terrain biome 仍需要修改 registry/main: %s" % biome_registry.last_error
	)
	_expect(
		&"fixture_volcanic" in biome_registry.module_ids(),
		"fixture volcanic module 没有由定义动态注册"
	)
	_expect(
		noise_registry.has_field(&"fixture_volcanic_heat"),
		"fixture biome 没有动态注册自己的 noise field"
	)


func _attachment_ids(biome: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for attachment_value in biome.get("attachments", []):
		if attachment_value is String:
			result.append(attachment_value)
		elif attachment_value is Dictionary:
			result.append(String(attachment_value.get("community_id", "")))
	return result


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		failures.append("无法读取 JSON: %s" % path)
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		failures.append("无效 JSON: %s" % path)
		return {}
	return json.data


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("无法写入 fixture: %s" % path)
		return
	file.store_string(JSON.stringify(value, "  "))
