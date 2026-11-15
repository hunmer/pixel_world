## flora_spawner.gd — 植被与 ambient 的候选产生、冲突消解与放置。
##
## 从 main.gd 簇7 主体迁出（结构性拆分，行为不变）：三个静态生态层的
## 候选规则、habitat 替换、空间群落（CommunitySpawner）候选、同格唯一
## 消解与最终放置，以及 ambient 簇生成。确定性契约：placement_seed 盐、
## salt 偏移（50/100/101/101+i）、_flora_conflict_seed、hash_u32 组合、
## WATER_SURFACE_LEVEL 语义全部逐字保留。依赖（物种表、层配置、群落运行时、
## 噪声采样）经 configure 显式注入；main 侧回调经 Callable 传入，
## 模块不反向依赖 main.gd。
class_name FloraSpawner
extends RefCounted

const TerrainTextureCatalogScript = preload("res://scripts/world/terrain_texture_catalog.gd")
const EcosystemMatchScript = preload("res://scripts/world/ecosystem_match.gd")
const SpeciesPickerScript = preload("res://scripts/world/species_picker.gd")
const CommunitySpawnerScript = preload("res://scripts/ecology/community_spawner.gd")
const DeterministicRngScript = preload("res://scripts/world/deterministic_rng.gd")

var _plant_species: Dictionary = {}
var _ambient_species: Dictionary = {}
var _flora_layer_configs: Dictionary = {}
var _dominant_species_chance := 0.0
var _flora_conflict_seed := 0
var _rock_level := 0
var _water_surface_level := 6
var _landform_id_to_type: Dictionary = {}
var _spatial_flora_sources: Array[Dictionary] = []
var _community_runtime
var _ambient_registry
var _terrain_sampler: TerrainSampler

var _cell_rand: Callable
var _cell_context_for_query: Callable
var _ecology_near_tag: Callable
var _community_rand01: Callable
var _render_block: Callable

var _flora_cache := {}
var _raw_selected_flora_cache := {}
var _spatial_flora_plan_cache := {}


func configure(
	plant_species: Dictionary,
	ambient_species: Dictionary,
	flora_layer_configs: Dictionary,
	dominant_species_chance: float,
	flora_conflict_seed: int,
	rock_level: int,
	water_surface_level: int,
	landform_id_to_type: Dictionary,
	spatial_flora_sources: Array,
	community_runtime,
	ambient_registry,
	terrain_sampler,
	cell_rand: Callable,
	cell_context_for_query: Callable,
	ecology_near_tag: Callable,
	community_rand01: Callable,
	render_block: Callable
) -> void:
	_plant_species = plant_species
	_ambient_species = ambient_species
	_flora_layer_configs = flora_layer_configs
	_dominant_species_chance = dominant_species_chance
	_flora_conflict_seed = flora_conflict_seed
	_rock_level = rock_level
	_water_surface_level = water_surface_level
	_landform_id_to_type = landform_id_to_type
	_spatial_flora_sources = spatial_flora_sources
	_community_runtime = community_runtime
	_ambient_registry = ambient_registry
	_terrain_sampler = terrain_sampler
	_cell_rand = cell_rand
	_cell_context_for_query = cell_context_for_query
	_ecology_near_tag = ecology_near_tag
	_community_rand01 = community_rand01
	_render_block = render_block


func clear_caches() -> void:
	_raw_selected_flora_cache.clear()
	_spatial_flora_plan_cache.clear()


func plant_tex(species_id: String) -> Texture2D:
	if not _flora_cache.has(species_id):
		if not _plant_species.has(species_id):
			push_error("生态配置引用了未知植物: " + species_id)
			return null
		var species: Dictionary = _plant_species[species_id]
		_flora_cache[species_id] = load(String(species.get("texture", "")))
	return _flora_cache[species_id]


func noise_instance_for_field(field_id: String) -> FastNoiseLite:
	if _terrain_sampler != null and _terrain_sampler.noise_registry != null:
		var registered: FastNoiseLite = _terrain_sampler.noise_registry.get_field(
			StringName(field_id)
		)
		if registered != null:
			return registered
	push_error("未知 noise field: " + field_id)
	return null


## 三个静态生态层分别使用独立噪声。所有命中的规则只先产生候选，同格最终只绘制一个。
func raw_flora_candidates_for_rules(
	cell: Vector2i,
	q: int,
	lf: int,
	gc: Vector2i,
	rules: Array
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var water_depth := _water_surface_level - q
	for rule_value in rules:
		var rule: Dictionary = rule_value
		var layer_id := String(rule.get("layer", ""))
		var layer: Dictionary = _flora_layer_configs[layer_id]
		var noise_field_id := String(layer.get("noise_field", ""))
		var layer_noise := noise_instance_for_field(noise_field_id).get_noise_2d(cell.x, cell.y)
		var noise_above := float(
			rule.get("noise_above", layer.get("default_noise_above", 0.0))
		)
		if layer_noise < noise_above:
			continue
		if rule.has("max_water_depth") and water_depth > int(rule["max_water_depth"]):
			continue
		var placement_seed := int(rule.get("placement_seed", 0))
		var chance := EcosystemMatchScript.ecology_chance(
			rule.get("chance", 0.0), _rock_level, lf, q
		)
		if _cell_rand.call(cell, placement_seed) >= chance:
			continue
		var plant_id := pick_species(rule, gc, cell)
		if plant_id.is_empty():
			continue
		var placement := String(rule.get("placement", "ground"))
		candidates.append({
			"sort_key": "%s/%s/%s" % [layer_id, String(rule.get("pool_id", "")), plant_id],
			"species_id": plant_id,
			"layer": layer_id,
			"placement": placement,
			"level": _water_surface_level if placement == "water_surface" else q,
			"render_priority": int(rule.get("render_priority", 8)),
			"modulate": (
				TerrainTextureCatalogScript.underwater_flora_modulate(water_depth)
				if placement == "lakebed"
				else Color.WHITE
			),
			"conflict_weight": float(rule.get("conflict_weight", 1.0)),
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["sort_key"]) < String(b["sort_key"])
	)
	return candidates


func pick_species(rule: Dictionary, gc: Vector2i, cell: Vector2i) -> String:
	return SpeciesPickerScript.pick_species(
		rule, gc, cell, _cell_rand, _dominant_species_chance, _flora_layer_configs
	)


## 旧契约的兼容入口；正式生成链由 CommunityRuntime 提供加法合并后的 rules。
func raw_flora_candidates_for_cell(
	cell: Vector2i,
	q: int,
	lf: int,
	gc: Vector2i,
	ecosystem: Dictionary
) -> Array[Dictionary]:
	return raw_flora_candidates_for_rules(
		cell, q, lf, gc, ecosystem.get("flora", [])
	)


## 带 habitat 的物种只改变候选最终显示的品种，不删除候选或改变冲突权重。
## 因此空旷处的蘑菇会被同层草丛接替，但已经调好的地被总密度保持不变。
func flora_candidates_for_cell(
	cell: Vector2i,
	q: int,
	lf: int,
	gc: Vector2i,
	ecosystem: Dictionary
) -> Array[Dictionary]:
	return flora_candidates_for_rules(
		cell, q, lf, gc, ecosystem.get("flora", [])
	)


func flora_candidates_for_rules(
	cell: Vector2i,
	q: int,
	lf: int,
	gc: Vector2i,
	rules: Array
) -> Array[Dictionary]:
	var candidates := raw_flora_candidates_for_rules(cell, q, lf, gc, rules)
	for index in candidates.size():
		var candidate: Dictionary = candidates[index]
		candidate["species_id"] = resolve_flora_habitat_species(
			cell,
			String(candidate["species_id"])
		)
		candidates[index] = candidate
	return candidates


func resolve_flora_habitat_species(cell: Vector2i, species_id: String) -> String:
	var species: Dictionary = _plant_species.get(species_id, {})
	var habitat: Dictionary = species.get("habitat", {})
	if habitat.is_empty():
		return species_id
	var near_layer := String(habitat.get("near_flora_layer", ""))
	var radius := int(habitat.get("radius", 0))
	if has_raw_selected_flora_layer_within(cell, near_layer, radius):
		return species_id
	return String(habitat.get("fallback_species", species_id))


## 邻近查询必须基于未应用 habitat 的确定性最终候选，不能读取流式 `_cells`。
## 这样结果不依赖格子的生成先后，也不会在蘑菇查询树木时递归调用自身。
func raw_selected_flora_for_cell(cell: Vector2i) -> Dictionary:
	if _raw_selected_flora_cache.has(cell):
		return _raw_selected_flora_cache[cell]
	var context = _cell_context_for_query.call(cell)
	var rules: Array = _community_runtime.cell_flora_rules_for_cell(
		context,
		_ecology_near_tag
	)
	var candidates := raw_flora_candidates_for_rules(
		cell,
		context.height,
		int(_landform_id_to_type.get(
			String(context.landform_id),
			EcosystemMatchScript.Landform.PLAINS
		)),
		context.region_anchor,
		rules
	)
	candidates.append_array(spatial_flora_candidates_for_cell(context))
	var selected := select_flora_candidate(cell, candidates)
	_raw_selected_flora_cache[cell] = selected
	return selected


func has_raw_selected_flora_layer_within(
	cell: Vector2i,
	layer_id: String,
	radius: int
) -> bool:
	for offset_y in range(-radius, radius + 1):
		for offset_x in range(-radius, radius + 1):
			if offset_x == 0 and offset_y == 0:
				continue
			var selected := raw_selected_flora_for_cell(
				cell + Vector2i(offset_x, offset_y)
			)
			if String(selected.get("layer", "")) == layer_id:
				return true
	return false


func select_flora_candidate(cell: Vector2i, candidates: Array[Dictionary]) -> Dictionary:
	if candidates.is_empty():
		return {}
	var total_weight := 0.0
	for candidate in candidates:
		total_weight += float(candidate.get("conflict_weight", 1.0))
	var cursor: float = _cell_rand.call(cell, _flora_conflict_seed) * total_weight
	for candidate in candidates:
		cursor -= float(candidate.get("conflict_weight", 1.0))
		if cursor <= 0.0:
			return candidate
	return candidates.back()


## 动植物定义由 ecology manifest 与 CommunityRuntime 驱动；这里只保留候选冲突与放置机制。
func spawn_flora(
	cell: Vector2i,
	q: int,
	lf: int,
	gc: Vector2i,
	state
) -> void:
	var rules: Array = _community_runtime.cell_flora_rules_for_cell(
		state.context,
		_ecology_near_tag
	)
	var selected := select_flora_candidate(
		cell,
		flora_candidates_with_spatial(cell, q, lf, gc, rules, state.context)
	)
	if not selected.is_empty():
		place_flora(
			String(selected["species_id"]),
			String(selected["layer"]),
			String(selected["placement"]),
			int(selected["level"]),
			state,
			int(selected["render_priority"]),
			selected.get("modulate", Color.WHITE)
		)


func flora_candidates_with_spatial(
	cell: Vector2i,
	q: int,
	lf: int,
	gc: Vector2i,
	rules: Array,
	context
) -> Array[Dictionary]:
	var candidates := flora_candidates_for_rules(cell, q, lf, gc, rules)
	for candidate_value in spatial_flora_candidates_for_cell(context):
		var candidate: Dictionary = candidate_value
		candidate["species_id"] = resolve_flora_habitat_species(
			cell,
			String(candidate.get("species_id", ""))
		)
		candidates.append(candidate)
	return candidates


func spatial_flora_candidates_for_cell(context) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if context == null:
		return candidates
	var cell: Vector2i = context.cell
	for source in _spatial_flora_sources:
		var definition: Dictionary = source.get("definition", {})
		var distribution: Dictionary = definition.get("distribution", {})
		var spacing := maxi(1, int(distribution.get("anchor_spacing", 1)))
		var radius := maxi(0, int(distribution.get("radius", 0)))
		var minimum_bucket := CommunitySpawnerScript.bucket_for_cell(
			cell - Vector2i(radius, radius), spacing
		)
		var maximum_bucket := CommunitySpawnerScript.bucket_for_cell(
			cell + Vector2i(radius, radius), spacing
		)
		for bucket_y in range(minimum_bucket.y, maximum_bucket.y + 1):
			for bucket_x in range(minimum_bucket.x, maximum_bucket.x + 1):
				var plan := spatial_flora_plan(
					source,
					Vector2i(bucket_x, bucket_y)
				)
				if not bool(plan.get("complete", false)):
					continue
				for member_value in plan.get("members", []):
					var member: Dictionary = member_value
					if member.get("cell", Vector2i.ZERO) != cell:
						continue
					var candidate := spatial_flora_candidate(
						definition,
						member,
						context
					)
					if not candidate.is_empty():
						candidates.append(candidate)
	return candidates


func spatial_flora_plan(source: Dictionary, bucket: Vector2i) -> Dictionary:
	var cache_key := "%s/%s/%d/%d" % [
		String(source.get("source_biome_id", "")),
		String(source.get("community_id", "")),
		bucket.x,
		bucket.y,
	]
	if _spatial_flora_plan_cache.has(cache_key):
		return _spatial_flora_plan_cache[cache_key]
	var habitat_valid: Callable = func(candidate: Vector2i) -> bool:
		return _community_runtime.flora_source_matches_context(
			source,
			_cell_context_for_query.call(candidate),
			_ecology_near_tag
		)
	var plan: Dictionary = CommunitySpawnerScript.plan_community(
		source.get("definition", {}),
		bucket,
		_community_rand01,
		habitat_valid,
		habitat_valid
	)
	_spatial_flora_plan_cache[cache_key] = plan
	return plan


func spatial_flora_candidate(
	definition: Dictionary,
	member: Dictionary,
	context
) -> Dictionary:
	var species_id := String(member.get("species", member.get("species_id", "")))
	var species: Dictionary = _plant_species.get(species_id, {})
	var layer_id := String(species.get("layer", ""))
	if species_id.is_empty() or layer_id.is_empty():
		return {}
	var habitat_value: Variant = definition.get("habitat", {})
	var habitat: Dictionary = habitat_value if habitat_value is Dictionary else {}
	var placement := String(habitat.get("placement", "ground"))
	for spec_value in definition.get("members", []):
		if not spec_value is Dictionary:
			continue
		var spec: Dictionary = spec_value
		if String(spec.get("species_id", spec.get("species", ""))) == species_id:
			placement = String(spec.get("placement", placement))
			break
	var render_priority := int(definition.get(
		"render_priority",
		12 if placement == "water_surface" else 0 if placement == "lakebed" else 8
	))
	return {
		"sort_key": "%s/%s/%s" % [
			layer_id,
			String(definition.get("id", "community")),
			species_id,
		],
		"species_id": species_id,
		"layer": layer_id,
		"placement": placement,
		"level": _water_surface_level if placement == "water_surface" else context.height,
		"render_priority": render_priority,
		"modulate": (
			TerrainTextureCatalogScript.underwater_flora_modulate(context.water_depth)
			if placement == "lakebed"
			else Color.WHITE
		),
		"conflict_weight": float(definition.get("conflict_weight", 1.0)),
	}


## 静态生态对象和所属地块柱一起绘制；地被不参与玩家遮挡，树木与装饰物仍可遮挡。
func place_flora(
	species_id: String,
	layer_id: String,
	placement: String,
	level: int,
	state,
	z_bias := 8,
	modulate := Color.WHITE
) -> bool:
	var tex := plant_tex(species_id)
	if tex == null:
		return false
	var occluder_class := (
		&"prop"
		if placement == "ground" and layer_id in ["tree", "decoration"]
		else &"none"
	)
	var block: Dictionary = _render_block.call(
		tex,
		level,
		modulate,
		z_bias,
		Vector2(0, -tex.get_height() / 2.0),
		occluder_class
	)
	block["flora_species_id"] = species_id
	block["flora_layer"] = layer_id
	block["flora_placement"] = placement
	state.add_render_block(block)
	var species: Dictionary = _plant_species.get(species_id, {})
	var traits_value: Variant = species.get("traits", {})
	var traits: Dictionary = traits_value if traits_value is Dictionary else {}
	var blocks_movement_default := (
		placement == "ground" and layer_id in ["tree", "decoration"]
	)
	state.add_static_object({
		"id": species_id,
		"category": "flora",
		"layer": layer_id,
		"placement": placement,
		"blocks_movement": bool(
			traits.get("blocks_movement", blocks_movement_default)
		),
		"blocks_fauna_spawn": bool(traits.get("blocks_fauna_spawn", false)),
		"tags": species.get("tags", []),
	})
	return true


## Ambient 是纯表现插件，不占动物格，也不参与移动或地图生成。
## 候选格与物种完全由生态规则决定；主场景不认识 firefly/butterfly 等具体类型。
func spawn_ambient_for_cell(
	cell: Vector2i,
	q: int,
	lf: int,
	gc: Vector2i,
	state,
	host: Node2D,
	current_seed: int
) -> void:
	if _ambient_registry == null:
		return
	var rules: Array = _community_runtime.ambient_rules_for_cell(
		state.context,
		_ecology_near_tag
	)
	var has_ground_flora := false
	for object_value in state.static_objects:
		var object_data: Dictionary = object_value
		if (
			String(object_data.get("placement", "")) == "ground"
			and String(object_data.get("layer", "")) in ["tree", "ground_cover"]
		):
			has_ground_flora = true
			break
	for rule_value in rules:
		var rule: Dictionary = rule_value
		if bool(rule.get("requires_ground_flora", false)) and not has_ground_flora:
			continue
		var placement_seed := int(rule.get("placement_seed", 0))
		var chance := EcosystemMatchScript.ecology_chance(
			rule.get("chance", 0.0), _rock_level, lf, q
		)
		if _cell_rand.call(cell, placement_seed) >= chance:
			continue
		var ambient_id := pick_species(rule, gc, cell)
		if (
			not _ambient_species.has(ambient_id)
			or not _ambient_registry.has_species(StringName(ambient_id))
		):
			continue
		var ambient: Dictionary = _ambient_species[ambient_id]
		var cluster_range: Array = ambient.get("cluster_size", [2, 3])
		var cluster_min := int(cluster_range[0])
		var cluster_max := int(cluster_range[1])
		var count_span := cluster_max - cluster_min + 1
		var count := clampi(
			cluster_min + int(_cell_rand.call(cell, placement_seed + 1) * count_span),
			cluster_min,
			cluster_max
		)
		var deterministic_seed := DeterministicRngScript.hash_u32(
			cell.x * 0x8da6b343
			^ cell.y * 0xd8163841
			^ (current_seed + placement_seed)
		)
		var local_surface_position := Vector2(cell)
		_ambient_registry.add_cluster(
			StringName(ambient_id),
			cell,
			host,
			local_surface_position,
			count,
			deterministic_seed
		)
		break
