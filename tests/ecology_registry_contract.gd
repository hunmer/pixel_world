extends SceneTree

const EcologyRegistryScript = preload("res://scripts/ecology/ecology_registry.gd")
const FIXTURE_ROOT := "user://ecology_registry_contract"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_ROOT))
	_test_modular_catalog()
	_test_legacy_adapter()
	_test_strict_failures()

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("ECOLOGY_REGISTRY_CONTRACT_OK")
	quit(0)


func _test_modular_catalog() -> void:
	var case_path := _write_case("valid", _valid_documents())
	var registry = EcologyRegistryScript.new()
	_expect(registry.load_manifest(case_path), "模块化生态清单加载失败: %s" % registry.get_error_text())
	if not registry.is_loaded():
		return
	var catalog: Dictionary = registry.get_catalog()
	_expect(String(catalog["default_biome_id"]) == "wetland", "默认 biome 未归一化")
	_expect((catalog["species"]["plants"] as Dictionary).size() == 2, "多个 species 模块没有合并")
	_expect((catalog["species"]["animals"] as Dictionary).has("wolf"), "动物物种未进入 catalog")
	_expect((catalog["species"]["ambient"] as Dictionary).has("firefly"), "环境物种未进入 catalog")
	_expect((catalog["communities"] as Dictionary).has("lotus_patch"), "莲花群落未进入 catalog")
	_expect((catalog["communities"] as Dictionary).has("wolf_pack"), "狼群未进入 catalog")
	_expect((catalog["biomes"] as Dictionary).has("wetland"), "biome 未进入 catalog")
	_expect(
		String(catalog["source_paths"]["communities"]["lotus_patch"]).ends_with("communities.json"),
		"catalog 没有保留 community 来源路径"
	)
	var lotus_patch: Dictionary = registry.get_community("lotus_patch")
	_expect(String(lotus_patch.get("kind", "")) == "patch", "一等 community kind 丢失")
	_expect((lotus_patch.get("members", []) as Array).size() == 2, "community members 丢失")
	var wetland: Dictionary = registry.get_biome("wetland")
	_expect(wetland.get("community_refs", []) == ["lotus_patch", "wetland_life"], "biome community_refs 丢失")
	_expect((wetland.get("attachments", []) as Array).size() == 1, "biome attachments 丢失")

	# Returned values are snapshots; callers cannot mutate the registry in place.
	lotus_patch["kind"] = "broken"
	_expect(String(registry.get_community("lotus_patch")["kind"]) == "patch", "registry 暴露了可变内部数据")

	var flattened := registry.to_legacy_config()
	_expect(String(flattened.get("default_ecosystem", "")) == "wetland", "模块配置无法导出旧 runtime 形状")
	_expect((flattened.get("ecosystems", []) as Array).size() == 1, "模块 biome 导出数量错误")


func _test_legacy_adapter() -> void:
	var registry = EcologyRegistryScript.new()
	_expect(
		registry.load_legacy("res://config/ecosystems.json"),
		"现有 ecosystems.json 无法通过兼容入口: %s" % registry.get_error_text()
	)
	if not registry.is_loaded():
		return
	var catalog: Dictionary = registry.get_catalog()
	_expect(String(catalog["default_biome_id"]) == "temperate", "旧配置默认生态映射错误")
	_expect(
		(catalog["communities"] as Dictionary).size() == (catalog["biomes"] as Dictionary).size(),
		"旧 ecosystem 没有一一拆分为 biome/community"
	)
	_expect(
		String(catalog["communities"]["water"]["kind"]) == "legacy_bundle",
		"旧生态没有标记为 legacy_bundle"
	)
	var legacy_round_trip := registry.to_legacy_config()
	_expect(int(legacy_round_trip.get("version", 0)) == 1, "旧配置 round-trip 丢失版本")
	_expect(
		(legacy_round_trip.get("ecosystems", []) as Array).size() == (catalog["biomes"] as Dictionary).size(),
		"旧配置 round-trip 丢失 ecosystems"
	)


func _test_strict_failures() -> void:
	var documents := _valid_documents()
	documents["world.json"]["version"] = 2
	_expect_failure("bad_version", documents, "unsupported version", "world.json")

	documents = _valid_documents()
	documents["species_a.json"]["kind"] = "unknown_kind"
	_expect_failure("unknown_kind", documents, "unknown module kind", "species_a.json")

	documents = _valid_documents()
	documents["species_a.json"]["species"]["animals"]["lotus_leaf"] = _valid_wolf_definition()
	_expect_failure("duplicate_species", documents, "duplicate species ID", "species_a.json")

	documents = _valid_documents()
	documents["communities.json"]["communities"][0]["members"][0]["species_id"] = "missing_lotus"
	_expect_failure("dangling_species", documents, "references unknown species", "communities.json")

	documents = _valid_documents()
	documents["biomes.json"]["biomes"][0]["community_refs"].append("missing_community")
	_expect_failure("dangling_community", documents, "references unknown community", "biomes.json")

	documents = _valid_documents()
	documents["species_b.json"]["species"]["plants"]["lotus_flower"]["texture"] = "res://missing/lotus.png"
	_expect_failure("missing_resource", documents, "resource does not exist", "species_b.json")

	documents = _valid_documents()
	documents["communities.json"]["communities"][0]["density"] = 0.5
	_expect_failure("unknown_field", documents, "contains unknown field: density", "communities.json")

	documents = _valid_documents()
	documents["biomes.json"]["biomes"][0]["attachments"][0]["community_id"] = "missing_pack"
	_expect_failure("dangling_attachment", documents, "references unknown community", "biomes.json")


func _expect_failure(
	case_id: String,
	documents: Dictionary,
	message_fragment: String,
	source_filename: String
) -> void:
	var manifest_path := _write_case(case_id, documents)
	var registry = EcologyRegistryScript.new()
	_expect(not registry.load_manifest(manifest_path), "非法配置意外通过: %s" % case_id)
	var error_text := registry.get_error_text()
	_expect(
		error_text.contains(message_fragment),
		"错误信息缺少原因 [%s]: %s" % [case_id, error_text]
	)
	_expect(
		error_text.contains(source_filename),
		"错误信息缺少模块路径 [%s]: %s" % [case_id, error_text]
	)


func _valid_documents() -> Dictionary:
	return {
		"world.json": {
			"version": 1,
			"kind": "world",
			"world": {
				"default_biome_id": "wetland",
				"generation": {"height": {"sea_threshold": 0.4}},
				"pool_selection": {"dominant_chance": 0.8},
			},
		},
		"species_a.json": {
			"version": 1,
			"kind": "species",
			"species": {
				"plants": {
					"lotus_leaf": {
						"layer": "ground_cover",
						"texture": "res://icon.svg",
					},
				},
				"animals": {"wolf": _valid_wolf_definition()},
				"ambient": {
					"firefly": {"cluster_size": [2, 3], "max_visible": 8, "max_lights": 2},
				},
			},
		},
		"species_b.json": {
			"version": 1,
			"kind": "species",
			"species": {
				"plants": {
					"lotus_flower": {
						"layer": "ground_cover",
						"texture": "res://icon.svg",
					},
				},
				"animals": {},
				"ambient": {},
			},
		},
		"communities.json": {
			"version": 1,
			"kind": "communities",
			"communities": [
				{
					"id": "lotus_patch",
					"kind": "patch",
					"habitat": {"required_tags": ["water", "shallow"]},
					"distribution": {"strategy": "patch", "radius": 4, "count": [3, 8]},
					"members": [
						{"species_id": "lotus_leaf", "category": "plant", "count": [3, 8]},
						{"species_id": "lotus_flower", "category": "plant", "count": [0, 2]},
					],
				},
				{
					"id": "wolf_pack",
					"kind": "social_group",
					"distribution": {
						"strategy": "social_group",
						"radius": 4,
						"social_radius": 5,
						"count": [7, 8],
					},
					"members": [
						{"species_id": "wolf", "category": "animal", "count": [7, 8]},
					],
				},
				{
					"id": "wetland_life",
					"kind": "composition",
					"community_refs": ["lotus_patch"],
					"members": [
						{"species_id": "firefly", "category": "ambient", "count": [1, 2]},
					],
				},
			],
		},
		"biomes.json": {
			"version": 1,
			"kind": "biomes",
			"biomes": [
				{
					"id": "wetland",
					"script": "res://scripts/world/biomes/temperate_biome.gd",
					"match": {"biome": "wetland"},
					"community_refs": ["lotus_patch", "wetland_life"],
					"attachments": [
						{"community_id": "wolf_pack", "weight": 0.1, "enabled": true},
					],
				},
			],
		},
	}


func _valid_wolf_definition() -> Dictionary:
	return {
		"directory": "res://meowa_tiles/animals/wolf",
		"behavior": "prefer_snow",
		"movement": {
			"idle_action": "idle",
			"move_action": "idle",
			"duration": 0.8,
		},
		"actions": {
			"idle": {"file": "idle.png", "fps": 6.0, "loop": true},
		},
	}


func _write_case(case_id: String, documents: Dictionary) -> String:
	var case_root := FIXTURE_ROOT.path_join(case_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(case_root))
	for filename in documents:
		_write_json(case_root.path_join(String(filename)), documents[filename])
	var modules := [
		{"kind": "world", "path": "world.json"},
		{"kind": "species", "path": "species_a.json"},
		{"kind": "species", "path": "species_b.json"},
		{"kind": "communities", "path": "communities.json"},
		{"kind": "biomes", "path": "biomes.json"},
	]
	var manifest_path := case_root.path_join("manifest.json")
	_write_json(manifest_path, {"version": 1, "modules": modules})
	return manifest_path


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("无法写入测试 fixture: %s" % path)
		return
	file.store_string(JSON.stringify(value, "  "))
