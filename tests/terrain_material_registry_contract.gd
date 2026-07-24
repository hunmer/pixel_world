extends SceneTree

const TerrainMaterialRegistry = preload(
	"res://scripts/world/terrain_material_registry.gd"
)
const VOLCANIC_FIXTURE_PATH := (
	"res://tests/fixtures/volcanic_terrain_materials.json"
)

var failures: Array[String] = []
var processor_call_count := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _has_error(
	registry,
	code: StringName,
	surface_id: StringName = &""
) -> bool:
	for error: Dictionary in registry.get_errors():
		if StringName(error.get("code", "")) != code:
			continue
		if surface_id.is_empty() or StringName(error.get("surface_id", "")) == surface_id:
			return true
	return false


func _process_texture(texture: Texture2D, _path: String) -> Texture2D:
	processor_call_count += 1
	# A real renderer can return its independently padded ImageTexture here.
	return texture


func _load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return JSON.parse_string(file.get_as_text())


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture_value: Variant = _load_json(VOLCANIC_FIXTURE_PATH)
	_expect(fixture_value is Dictionary, "volcanic material fixture 无法读取")
	if not fixture_value is Dictionary:
		_finish()
		return

	var registry := TerrainMaterialRegistry.new()
	var generation := {"materials": fixture_value}
	_expect(
		registry.load_from_generation(generation, VOLCANIC_FIXTURE_PATH),
		"generation.materials 加载失败"
	)
	_expect(registry.is_valid(), "合法 volcanic fixture 产生校验错误")
	_expect(registry.has_surface(&"volcanic_basalt"), "配置新增 surface 未注册")
	var registered_ids: Array[StringName] = registry.registered_surface_ids()
	_expect(
		registered_ids.size() == 2
		and registered_ids[0] == &"temperate_soil"
		and registered_ids[1] == &"volcanic_basalt",
		"surface id 列表不稳定"
	)
	_expect(
		registry.fallback_surface_id() == &"temperate_soil",
		"配置 fallback_surface_id 未生效"
	)

	# No volcanic branch exists in the registry: fixture data alone supplies the
	# surface, biome override, tags, traits, textures, and minimap appearance.
	var volcanic: Dictionary = registry.resolve(&"volcanic_basalt", &"volcanic")
	_expect(not volcanic.is_empty(), "volcanic surface 无法 resolve")
	_expect(
		StringName(volcanic.get("surface_id", "")) == &"volcanic_basalt",
		"resolve 返回了错误 surface"
	)
	_expect(not bool(volcanic.get("used_fallback", true)), "已知 surface 错误使用 fallback")
	_expect(&"rocky" in volcanic["tags"], "基础 surface tag 丢失")
	_expect(&"hot" in volcanic["tags"], "biome override tag 没有合并")
	_expect(&"igneous" in volcanic["tags"], "多个 override tag 没有合并")
	_expect(bool(volcanic["traits"].get("emits_heat", false)), "override trait 没有生效")
	_expect(
		is_equal_approx(float(volcanic["traits"].get("movement_cost", 0.0)), 1.35),
		"基础 trait 在 override 合并中丢失"
	)
	_expect(
		volcanic["minimap_color"].is_equal_approx(Color(0.12, 0.07, 0.08, 1.0)),
		"biome override minimap color 没有生效"
	)
	_expect(
		String(volcanic["column_texture_path"]) == String(volcanic["top_texture_path"]),
		"column reuse_top 未解析为当前 top texture"
	)
	_expect(
		String(volcanic["underwater_texture_path"]) == String(volcanic["column_texture_path"]),
		"underwater reuse_column 未解析"
	)

	var cold_volcano: Dictionary = registry.resolve(&"volcanic_basalt", &"ice_volcano")
	_expect(&"cold" in cold_volcano["tags"], "第二个 biome override 未按 id 解析")
	_expect(
		not bool(cold_volcano["traits"].get("emits_heat", true)),
		"biome override 未覆盖基础/其他 biome trait"
	)
	var ordinary_basalt: Dictionary = registry.resolve(&"volcanic_basalt", &"temperate")
	_expect(not ordinary_basalt["traits"].has("emits_heat"), "无关 biome 错误应用 override")

	# Texture loading and renderer-owned post-processing each have independent
	# path caches. Reused faces return the same Texture2D without another load.
	var top_texture: Texture2D = registry.get_texture(
		&"volcanic_basalt",
		&"top",
		&"volcanic"
	)
	var column_texture: Texture2D = registry.get_texture(
		&"volcanic_basalt",
		&"column",
		&"volcanic"
	)
	_expect(top_texture != null, "top Texture2D 加载失败")
	_expect(top_texture == column_texture, "reuse_top 没有复用 Texture2D cache")
	registry.set_texture_processor(_process_texture)
	var processed_first: Texture2D = registry.get_texture(&"volcanic_basalt", &"top")
	var processed_second: Texture2D = registry.get_texture(&"volcanic_basalt", &"column")
	_expect(processed_first == processed_second, "注入 texture processor 后未复用缓存")
	_expect(processor_call_count == 1, "同路径重复执行 texture processor")
	_expect(registry.processed_texture_cache_size() == 1, "processed texture cache 数量错误")

	# Unknown surfaces are never silent. The explicit fallback is returned while
	# retaining both requested and resolved IDs for diagnostics.
	registry.clear_errors()
	var fallback: Dictionary = registry.resolve(&"future_crystal", &"volcanic")
	_expect(not fallback.is_empty(), "未知 surface 没有返回显式 fallback")
	_expect(bool(fallback.get("used_fallback", false)), "未知 surface 未标记 fallback")
	_expect(
		StringName(fallback.get("requested_surface_id", "")) == &"future_crystal",
		"fallback 丢失原始 surface id"
	)
	_expect(
		StringName(fallback.get("surface_id", "")) == &"temperate_soil",
		"fallback resolve 到错误 surface"
	)
	_expect(_has_error(registry, &"unknown_surface", &"future_crystal"), "未知 surface 未报告")
	var error_count := registry.get_errors().size()
	registry.resolve(&"future_crystal", &"volcanic")
	_expect(registry.get_errors().size() == error_count, "高频 resolve 重复刷同一 unknown error")
	_expect(
		registry.resolve(&"future_crystal", &"", false).is_empty(),
		"禁用 fallback 后未知 surface 仍返回材质"
	)

	# Strict schema/resource/type checks use separate registries so failures do
	# not obscure the valid fixture contract above.
	var invalid := TerrainMaterialRegistry.new()
	_expect(
		not invalid.register_surface(
			{
				"surface_id": "unknown_field",
				"top_texture": "res://meowa_tiles/terrain/soil.png",
				"minimap_color": [0.2, 0.2, 0.2],
				"magic_shader": true,
			},
			&"",
			"invalid-contract"
		),
		"未知字段未被拒绝"
	)
	_expect(_has_error(invalid, &"unknown_material_field"), "未知字段缺少错误码")
	_expect(
		not invalid.register_surface(
			{
				"surface_id": "missing_texture",
				"top_texture": "res://tests/fixtures/no_surface.png",
				"minimap_color": [0.2, 0.2, 0.2],
			},
			&"",
			"invalid-contract"
		),
		"不存在的 texture resource 未被拒绝"
	)
	_expect(
		_has_error(invalid, &"missing_texture_resource", &"missing_texture"),
		"缺失 texture resource 没有明确错误"
	)
	_expect(
		not invalid.register_surface(
			{
				"surface_id": "bad_color",
				"top_texture": "res://meowa_tiles/terrain/soil.png",
				"minimap_color": [1.4, 0.2, 0.2],
			},
			&"",
			"invalid-contract"
		),
		"超范围 minimap color 未被拒绝"
	)
	_expect(_has_error(invalid, &"invalid_minimap_color", &"bad_color"), "颜色错误不清晰")
	_expect(
		not invalid.register_surface(
			{
				"surface_id": "bad_tags",
				"top_texture": "res://meowa_tiles/terrain/soil.png",
				"minimap_color": [0.2, 0.2, 0.2],
				"tags": "land",
			},
			&"",
			"invalid-contract"
		),
		"非数组 tags 未被拒绝"
	)
	_expect(_has_error(invalid, &"invalid_material_tags", &"bad_tags"), "tags 错误不清晰")
	_expect(
		not invalid.register_surface(
			{
				"surface_id": "missing_top",
				"minimap_color": [0.2, 0.2, 0.2],
			},
			&"",
			"invalid-contract"
		),
		"缺 top_texture 的 surface 未被拒绝"
	)
	_expect(
		_has_error(invalid, &"missing_top_texture", &"missing_top"),
		"缺 top_texture 没有明确错误"
	)
	_expect(
		not invalid.register_surface(
			{
				"surface_id": "bad_texture_spec",
				"top_texture": "res://meowa_tiles/terrain/soil.png",
				"column_texture": {"reuse": "top", "unexpected": true},
				"minimap_color": [0.2, 0.2, 0.2],
			},
			&"",
			"invalid-contract"
		),
		"含未知字段的 texture spec 未被拒绝"
	)
	_expect(
		_has_error(invalid, &"invalid_texture_spec", &"bad_texture_spec"),
		"texture spec 错误不清晰"
	)
	var invalid_list := TerrainMaterialRegistry.new()
	_expect(
		not invalid_list.load_materials([42], "invalid-list"),
		"数组中的非 Dictionary material 未使加载失败"
	)
	_expect(
		_has_error(invalid_list, &"invalid_material_definition"),
		"非法数组 material 缺少明确错误"
	)

	var duplicate := TerrainMaterialRegistry.new()
	var minimal_valid := {
		"surface_id": "duplicate",
		"top_texture": "res://meowa_tiles/terrain/soil.png",
		"minimap_color": [0.2, 0.2, 0.2],
	}
	_expect(duplicate.register_surface(minimal_valid), "最小合法 surface 注册失败")
	_expect(not duplicate.register_surface(minimal_valid), "重复 surface id 覆盖成功")
	_expect(
		_has_error(duplicate, &"duplicate_surface_id", &"duplicate"),
		"重复 surface id 没有明确错误"
	)
	var missing_generation := TerrainMaterialRegistry.new()
	_expect(
		not missing_generation.load_from_generation({"height": {}}),
		"缺 generation.materials 被接受"
	)
	_expect(
		_has_error(missing_generation, &"missing_materials_config"),
		"缺 generation.materials 没有明确错误"
	)

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("TERRAIN_MATERIAL_REGISTRY_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
