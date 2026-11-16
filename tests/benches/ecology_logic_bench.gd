## ecology_logic_bench.gd — 生态解析纯逻辑基准（不依赖场景/帧/渲染）
##
## 用固定配方表批量构造 CellContext，测量 EcologyResolver.resolve() 的微秒级吞吐。
## 只读使用 scripts/ecology/* 与 config/ecology/manifest.json，不改变任何游戏逻辑。
## 确定性：无随机源，输入由迭代下标算术派生；同规模两次运行的 checksum 必须一致。

extends RefCounted

const EcologyRegistryScript := preload("res://scripts/ecology/ecology_registry.gd")
const EcologyResolverScript := preload("res://scripts/ecology/ecology_resolver.gd")
const CellContextScript := preload("res://scripts/world/cell_context.gd")

const MANIFEST_PATH := "res://config/ecology/manifest.json"
const WARMUP_ITERATIONS := 256

## 固定配方（覆盖基础 biome / habitat / attachment / 深水分层路径）
## 每项：biome_id, landform_id, height, water_depth, is_water, is_shore, surface_id, tags
const RECIPES: Array[Array] = [
	[&"temperate", &"plains", 7, 0, false, false, &"soil", []],
	[&"desert", &"hills", 8, 1, true, false, &"sand", []],
	[&"desert", &"dunes", 5, 0, false, false, &"sand", [&"arid"]],
	[&"snow", &"mountains", 12, 0, false, false, &"rock", []],
	[&"temperate", &"plains", 7, 2, true, false, &"soil", []],
	[&"temperate", &"plains", 6, 3, true, false, &"soil", []],
	[&"temperate", &"plains", 4, 0, false, true, &"soil", []],
	[&"snow", &"valley", 3, 0, false, false, &"snow", []],
]


static func _context_for(index: int) -> RefCounted:
	var recipe: Array = RECIPES[index % RECIPES.size()]
	var drift: int = (index / RECIPES.size()) % 5
	# CellContext 构造器要求 tags 为 Array[StringName]；RECIPES 存无类型数组，这里显式转型
	var tags: Array[StringName] = []
	for tag_variant: Variant in recipe[7]:
		tags.append(StringName(String(tag_variant)))
	return CellContextScript.new(
		Vector2i((index % 257) - 128, ((index * 7) % 241) - 120),
		int(recipe[2]) + drift,
		recipe[0],
		-1,
		recipe[1],
		-1,
		int(recipe[3]),
		recipe[4],
		recipe[5],
		recipe[6],
		Vector2i.ZERO,
		tags
	)


## 跑一轮基准。返回：
## {iterations, resolve_us, us_per_resolve, checksum, biome_count, community_count, non_empty_hits}
static func run(iterations: int) -> Dictionary:
	var registry := EcologyRegistryScript.new()
	if not registry.load_manifest(MANIFEST_PATH):
		return {"error": "manifest 加载失败: %s" % registry.get_error_text()}
	var catalog: Dictionary = registry.get_catalog()
	var resolver := EcologyResolverScript.new()
	if not resolver.configure(catalog):
		return {"error": "resolver 配置失败: %s" % resolver.last_error}

	var contexts: Array[RefCounted] = []
	contexts.resize(iterations)
	for i: int in iterations:
		contexts[i] = _context_for(i)

	# 预热：稳定 dictionary/字符串驻留，避免把首访问抖动计入
	for i: int in mini(WARMUP_ITERATIONS, iterations):
		resolver.resolve(contexts[i])

	var checksum: int = 0
	var non_empty_hits: int = 0
	var start_usec := Time.get_ticks_usec()
	for ctx: RefCounted in contexts:
		var resolved: Dictionary = resolver.resolve(ctx)
		var id_text := ""
		var ids: Array = resolved.get("community_ids", [])
		for id_variant: Variant in ids:
			id_text += String(id_variant) + ","
		if not ids.is_empty():
			non_empty_hits += 1
		checksum = hash(
			checksum * 31
			+ hash(String(resolved.get("base_biome_id", &"")))
			+ hash(id_text)
		)
	var resolve_us := Time.get_ticks_usec() - start_usec

	var biomes: Dictionary = catalog.get("biomes", {})
	var communities: Dictionary = catalog.get("communities", {})
	return {
		"iterations": iterations,
		"resolve_us": resolve_us,
		"us_per_resolve": float(resolve_us) / float(maxi(iterations, 1)),
		"checksum": checksum,
		"biome_count": biomes.size(),
		"community_count": communities.size(),
		"non_empty_hits": non_empty_hits,
	}
