## ecosystem_match.gd — 生态区匹配：五键匹配规则、legacy CellContext 转换与机会值提取。
##
## 从 main.gd 簇7 前段迁出的无状态静态函数集（结构性拆分，行为不变）。
## 所有依赖（生态顺序表、地物 ID 表、采样器、水位常量）经参数显式传入。
class_name EcosystemMatch
extends RefCounted

const CellContextScript = preload("res://scripts/world/cell_context.gd")

## 旧整数地物枚举（确定性契约：legacy 存档与 placement 语义依赖这些值）。
enum Landform { OCEAN, PLAINS, HILLS, MOUNTAIN, SWAMP }


static func ecosystem_id_for_cell(
	community_runtime: CommunityRuntime,
	ecosystem_order: Array,
	default_ecosystem_id: String,
	landform_ids: Array,
	terrain_sampler: TerrainSampler,
	water_surface_level: int,
	water_max: int,
	q: int,
	biome: int,
	beach: bool,
	lf: int
) -> String:
	if community_runtime != null and community_runtime.is_configured():
		return community_runtime.legacy_ecosystem_id(
			legacy_cell_context(
				landform_ids,
				terrain_sampler,
				water_surface_level,
				water_max,
				q,
				biome,
				beach,
				lf
			)
		)
	for ecosystem in ecosystem_order:
		var match_rule: Dictionary = ecosystem.get("match", {})
		if ecosystem_matches(
			match_rule,
			landform_ids,
			terrain_sampler,
			water_max,
			q,
			biome,
			beach,
			lf
		):
			return String(ecosystem["id"])
	return default_ecosystem_id


## 旧测试与存档仍使用整数 biome/landform；在边界处转换成统一 CellContext。
## 新生态链始终直接消费 TerrainSampler 产生的动态 ID。
static func legacy_cell_context(
	landform_ids: Array,
	terrain_sampler: TerrainSampler,
	water_surface_level: int,
	water_max: int,
	q: int,
	biome: int,
	beach: bool,
	lf: int
) -> CellContext:
	var landform_id := ""
	if lf >= 0 and lf < landform_ids.size():
		landform_id = landform_ids[lf]
	return CellContextScript.new(
		Vector2i.ZERO,
		q,
		StringName(biome_id(terrain_sampler, biome)),
		biome,
		StringName(landform_id),
		lf,
		maxi(0, water_surface_level - q),
		q <= water_max,
		beach,
		&"water" if q <= water_max else &"",
		Vector2i.ZERO
	)


static func ecosystem_matches(
	match_rule: Dictionary,
	landform_ids: Array,
	terrain_sampler: TerrainSampler,
	water_max: int,
	q: int,
	biome: int,
	beach: bool,
	lf: int
) -> bool:
	if match_rule.has("water") and bool(match_rule["water"]) != (q <= water_max):
		return false
	if match_rule.has("shore") and bool(match_rule["shore"]) != beach:
		return false
	if match_rule.has("biome") and String(match_rule["biome"]) != biome_id(terrain_sampler, biome):
		return false
	if match_rule.has("landform"):
		var configured_landform: Variant = match_rule["landform"]
		if configured_landform is Array:
			if not configured_landform.has(landform_ids[lf]):
				return false
		elif String(configured_landform) != landform_ids[lf]:
			return false
	if match_rule.has("minimum_level") and q < int(match_rule["minimum_level"]):
		return false
	if match_rule.has("maximum_level") and q > int(match_rule["maximum_level"]):
		return false
	return true


static func biome_id(terrain_sampler: TerrainSampler, biome: int) -> String:
	return String(terrain_sampler.biome_id_for_index(biome))


static func ecology_chance(chance_value: Variant, rock_level: int, lf: int, q: int) -> float:
	if chance_value is float or chance_value is int:
		return float(chance_value)
	if not chance_value is Dictionary:
		return 0.0
	var chances: Dictionary = chance_value
	if lf == Landform.MOUNTAIN or q >= rock_level:
		return float(chances.get("mountain_or_rock", chances.get("default", 0.0)))
	if lf == Landform.SWAMP:
		return float(chances.get("swamp", chances.get("default", 0.0)))
	if lf == Landform.HILLS:
		return float(chances.get("hills", chances.get("default", 0.0)))
	return float(chances.get("default", 0.0))
