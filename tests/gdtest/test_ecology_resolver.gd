## test_ecology_resolver.gd — gdtest 试点：与 tests/ecology_resolver_contract.gd 等价的最小断言（additive 沙漠水格解析）
extends GdTest

const EcologyRegistryScript = preload("res://scripts/ecology/ecology_registry.gd")
const EcologyResolverScript = preload("res://scripts/ecology/ecology_resolver.gd")
const CellContextScript = preload("res://scripts/world/cell_context.gd")


func _context(
	biome_id: StringName,
	landform_id: StringName,
	height: int,
	water_depth: int,
	is_water: bool,
	is_shore: bool,
	surface_id: StringName
) -> RefCounted:
	var tags: Array[StringName] = []
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


func test_manifest_loads_and_resolver_configures() -> void:
	var registry = EcologyRegistryScript.new()
	assert_true(
		registry.load_manifest("res://config/ecology/manifest.json"),
		"manifest 加载失败: %s" % registry.get_error_text()
	)
	var catalog: Dictionary = registry.get_catalog()
	assert_false(catalog.is_empty(), "catalog 为空")
	var resolver = EcologyResolverScript.new()
	assert_true(resolver.configure(catalog), "resolver 配置失败: %s" % resolver.last_error)


func test_additive_desert_water_resolution() -> void:
	var registry = EcologyRegistryScript.new()
	assert_true(registry.load_manifest("res://config/ecology/manifest.json"))
	var resolver = EcologyResolverScript.new()
	assert_true(resolver.configure(registry.get_catalog()))
	var desert_water = _context(&"desert", &"hills", 8, 1, true, false, &"sand")
	var resolved: Dictionary = resolver.resolve(desert_water)
	assert_eq(String(resolved["base_biome_id"]), "desert", "base biome 丢失")
	assert_true("desert_water" in resolved["matched_biome_ids"], "habitat 层未匹配")
	assert_true("water" in resolved["matched_biome_ids"], "通用 water 层未叠加")
	assert_true("pond_lilies" in resolved["community_ids"], "浅水 attachment 未叠加")
	assert_false("desert" in resolved["community_ids"], "legacy bundle 混入 communities")
