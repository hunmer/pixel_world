## fauna_streamer.gd — 动物群落的流式生成（簇8：领地锚点 / 群体规划 / 成员恢复）
## 从 main.gd 原样迁出；确定性盐（placement_seed+1/+2/+3/+4/+5/+6/+101）逐字保留。
## 宿主状态经 configure 注入（字典按引用同步）；stream_center/stream_extent/player_cell
## 随每次入口调用传入（流式批次内视为常量，与原 main 语义一致）。
class_name FaunaStreamer
extends RefCounted

const CommunitySpawnerScript = preload("res://scripts/ecology/community_spawner.gd")
const EcosystemMatchScript = preload("res://scripts/world/ecosystem_match.gd")

var _community_runtime
var _animal_groups
var _cells: Dictionary
var _cell_states: Dictionary
var _animals: Dictionary
var _water_max: int
var _water_surface_level: int
var _landform_id_to_type: Dictionary

var _cell_rand: Callable
var _community_rand01: Callable
var _ecology_near_tag: Callable
var _ecology_chance: Callable
var _pick_species: Callable
var _quantize: Callable
var _cell_context_for_query: Callable
var _community_water_clearance_valid: Callable
var _spawn_animal: Callable
var _animal_cell_reserved: Callable

# 每个流式批次入口刷新（原 main.gd 同名字段语义）。
var _stream_center := Vector2i.ZERO
var _stream_extent := 32
var _player_cell := Vector2i.ZERO


func configure(
	community_runtime,
	animal_groups,
	cells: Dictionary,
	cell_states: Dictionary,
	animals: Dictionary,
	water_max: int,
	water_surface_level: int,
	landform_id_to_type: Dictionary,
	cell_rand: Callable,
	community_rand01: Callable,
	ecology_near_tag: Callable,
	ecology_chance: Callable,
	pick_species: Callable,
	quantize: Callable,
	cell_context_for_query: Callable,
	community_water_clearance_valid: Callable,
	spawn_animal: Callable,
	animal_cell_reserved: Callable
) -> void:
	_community_runtime = community_runtime
	_animal_groups = animal_groups
	_cells = cells
	_cell_states = cell_states
	_animals = animals
	_water_max = water_max
	_water_surface_level = water_surface_level
	_landform_id_to_type = landform_id_to_type
	_cell_rand = cell_rand
	_community_rand01 = community_rand01
	_ecology_near_tag = ecology_near_tag
	_ecology_chance = ecology_chance
	_pick_species = pick_species
	_quantize = quantize
	_cell_context_for_query = cell_context_for_query
	_community_water_clearance_valid = community_water_clearance_valid
	_spawn_animal = spawn_animal
	_animal_cell_reserved = animal_cell_reserved


## 由宿主薄委托在入口刷新当前流式帧（与原 main 字段语义一致）。
func sync_stream_frame(stream_center: Vector2i, stream_extent_value: int, player_cell: Vector2i) -> void:
	_stream_center = stream_center
	_stream_extent = stream_extent_value
	_player_cell = player_cell


## fauna 的 chance 是“每个稀疏领地是否存在一个社会单元”，不再逐地块掷概率。
## 这样既能降低全局密度，也能把狼、猪和青蛙组织成真正的群体。
func spawn_fauna_for_stream(
	stream_center: Vector2i,
	stream_extent_value: int,
	player_cell: Vector2i
) -> void:
	_stream_center = stream_center
	_stream_extent = stream_extent_value
	_player_cell = player_cell
	for source_value in _community_runtime.fauna_sources():
		var source: Dictionary = source_value
		var ecosystem_id := String(source.get("source_biome_id", ""))
		var rule: Dictionary = source.get("rule", {})
		if ecosystem_id.is_empty() or rule.is_empty():
			continue
		var distribution: Dictionary = rule.get("distribution", {})
		var spacing := maxi(1, int(distribution.get("anchor_spacing", 1)))
		var radius := maxi(0, int(distribution.get("radius", 0)))
		var minimum_bucket := Vector2i(
			floori(float(_stream_center.x - _stream_extent - radius) / spacing),
			floori(float(_stream_center.y - _stream_extent - radius) / spacing)
		)
		var maximum_bucket := Vector2i(
			floori(float(_stream_center.x + _stream_extent + radius) / spacing),
			floori(float(_stream_center.y + _stream_extent + radius) / spacing)
		)
		for bucket_y in range(minimum_bucket.y, maximum_bucket.y + 1):
			for bucket_x in range(minimum_bucket.x, maximum_bucket.x + 1):
				var bucket := Vector2i(bucket_x, bucket_y)
				var generic_spawner := fauna_source_uses_generic_spawner(source)
				var anchor := (
					community_anchor_for_source(source, bucket)
					if generic_spawner
					else fauna_anchor_for_bucket(rule, bucket)
				)
				var group_id := animal_group_id(ecosystem_id, rule, bucket)
				if _animal_groups.has(group_id):
					restore_animal_group(group_id)
					continue
				# 首次发现必须等完整出生半径进入视窗，避免从不同方向接近时
				# 因边缘裁切得到不同的群成员位置或把 8 只狼永久截成 7 只。
				var anchor_search_radius := int(distribution.get("anchor_search_radius", 0))
				if (
					not fauna_anchor_fully_loaded(anchor, radius + anchor_search_radius)
					or not _cells.has(anchor)
				):
					continue
				if generic_spawner:
					create_first_class_animal_group(group_id, source, bucket)
					continue
				var anchor_context = _cell_context_for_query.call(anchor)
				var anchor_q: int = anchor_context.height
				var anchor_landform := int(_landform_id_to_type.get(
					String(anchor_context.landform_id),
					EcosystemMatchScript.Landform.PLAINS
				))
				if not _community_runtime.fauna_source_matches_context(
					source,
					anchor_context,
					_ecology_near_tag
				):
					continue
				var placement_seed := int(rule.get("placement_seed", 0))
				var chance: float = _ecology_chance.call(
					rule.get("chance", 0.0), anchor_landform, anchor_q
				)
				if _cell_rand.call(bucket, placement_seed + 3) >= chance:
					continue
				var water_radius := int(distribution.get("requires_water_within", 0))
				if water_radius > 0 and not has_water_within(anchor, water_radius):
					continue
				create_animal_group(
					group_id,
					ecosystem_id,
					rule,
					distribution,
					bucket,
					anchor,
					anchor_q,
					source
				)


func fauna_anchor_fully_loaded(
	anchor: Vector2i, radius: int, stream_center: Vector2i = _stream_center,
	stream_extent_value: int = _stream_extent
) -> bool:
	var safe_extent := stream_extent_value - maxi(0, radius)
	return (
		safe_extent >= 0
		and absi(anchor.x - stream_center.x) <= safe_extent
		and absi(anchor.y - stream_center.y) <= safe_extent
	)


func fauna_anchor_for_bucket(rule: Dictionary, bucket: Vector2i) -> Vector2i:
	var distribution: Dictionary = rule.get("distribution", {})
	var spacing := maxi(1, int(distribution.get("anchor_spacing", 1)))
	var jitter := clampf(float(distribution.get("anchor_jitter", 1.0)), 0.0, 1.0)
	var inset := floori(spacing * (1.0 - jitter) * 0.5)
	var usable := maxi(1, spacing - inset * 2)
	var placement_seed := int(rule.get("placement_seed", 0))
	var offset_x := inset + mini(
		usable - 1,
		int(_cell_rand.call(bucket, placement_seed + 1) * usable)
	)
	var offset_y := inset + mini(
		usable - 1,
		int(_cell_rand.call(bucket, placement_seed + 2) * usable)
	)
	return bucket * spacing + Vector2i(offset_x, offset_y)


func animal_group_id(ecosystem_id: String, rule: Dictionary, bucket: Vector2i) -> String:
	return "%s/%s/%d/%d" % [
		ecosystem_id,
		String(rule.get("pool_id", "fauna")),
		bucket.x,
		bucket.y,
	]


## 已迁移的内置群落继续走 legacy salt 适配器，确保现有世界与调好的密度不漂移；
## 没有 legacy seed 的新定义自动使用通用 CommunitySpawner。
func fauna_source_uses_generic_spawner(source: Dictionary) -> bool:
	if not bool(source.get("first_class", false)):
		return false
	var definition: Dictionary = source.get("definition", {})
	var metadata_value: Variant = definition.get("metadata", {})
	var metadata: Dictionary = metadata_value if metadata_value is Dictionary else {}
	return not metadata.has("legacy_placement_seed")


func community_anchor_for_source(source: Dictionary, bucket: Vector2i) -> Vector2i:
	var definition: Dictionary = source.get("definition", {})
	var distribution: Dictionary = definition.get("distribution", {})
	var spacing := maxi(1, int(distribution.get("anchor_spacing", 1)))
	var jitter := clampf(
		float(distribution.get("anchor_jitter", distribution.get("jitter", 1.0))),
		0.0,
		1.0
	)
	var stream_prefix := String(
		definition.get("stream_key", definition.get("id", "community"))
	)
	return CommunitySpawnerScript.anchor_for_bucket(
		bucket,
		spacing,
		jitter,
		_community_rand01,
		stream_prefix + "/anchor"
	)


func create_first_class_animal_group(
	group_id: String,
	source: Dictionary,
	bucket: Vector2i
) -> void:
	var definition: Dictionary = source.get("definition", {})
	if definition.is_empty():
		return
	var rule: Dictionary = source.get("rule", {})
	var distribution: Dictionary = definition.get("distribution", {})
	var same_ecosystem := bool(distribution.get(
		"same_ecosystem",
		distribution.get(
			"same_biome",
			(definition.get("habitat", {}) as Dictionary).get("same_biome", true)
		)
	))
	var only_if_flora_missed := bool(rule.get("only_if_flora_missed", true))
	var habitat: Dictionary = definition.get("habitat", {})
	var required_tags: Array = habitat.get("required_tags", [])
	var allow_water := bool(
		(definition.get("metadata", {}) as Dictionary).get(
			"allow_water",
			"water" in required_tags and "land" not in required_tags
		)
	)
	var habitat_valid: Callable = func(candidate: Vector2i) -> bool:
		var candidate_context = _cell_context_for_query.call(candidate)
		return _community_runtime.fauna_source_matches_context(
			source,
			candidate_context,
			_ecology_near_tag
		) and _community_water_clearance_valid.call(definition, candidate_context)
	var anchor_result := CommunitySpawnerScript.resolve_anchor(
		definition,
		bucket,
		_community_rand01,
		habitat_valid
	)
	if not bool(anchor_result.get("valid", false)):
		cache_inactive_animal_group(group_id, source, anchor_result["anchor"], "invalid_habitat")
		return
	var anchor: Vector2i = anchor_result["anchor"]
	var anchor_context = _cell_context_for_query.call(anchor)
	var anchor_q: int = anchor_context.height
	var cell_valid: Callable = func(candidate: Vector2i) -> bool:
		if not _cells.has(candidate) or not _cell_states.has(candidate):
			return false
		var candidate_context = _cell_context_for_query.call(candidate)
		if absi(_stand_level(candidate_context.height) - _stand_level(anchor_q)) > 1:
			return false
		if same_ecosystem and not _community_runtime.fauna_source_matches_context(
			source,
			candidate_context,
			_ecology_near_tag
		):
			return false
		if not _community_water_clearance_valid.call(definition, candidate_context):
			return false
		return _cell_states[candidate].can_spawn_fauna(
			allow_water,
			only_if_flora_missed
		)
	var plan: Dictionary = CommunitySpawnerScript.plan_community(
		definition,
		bucket,
		_community_rand01,
		habitat_valid,
		cell_valid
	)
	if not bool(plan.get("complete", false)):
		cache_inactive_animal_group(
			group_id,
			source,
			anchor,
			String(plan.get("reason", "incomplete_plan"))
		)
		return
	var members: Array[Dictionary] = []
	for member_value in plan.get("members", []):
		var member: Dictionary = member_value
		members.append({
			"origin": member.get("cell", Vector2i.ZERO),
			"species": String(member.get("species", member.get("species_id", ""))),
			"role": String(member.get("role", "")),
		})
	if members.is_empty():
		cache_inactive_animal_group(group_id, source, anchor, "empty_members")
		return
	_animal_groups.set_or_put(group_id, {
		"anchor": anchor,
		"ecosystem_id": String(source.get("source_biome_id", "")),
		"community_id": String(source.get("community_id", "")),
		"social_radius": float(distribution.get("social_radius", distribution.get("radius", 0.0))),
		"members": members,
	}, true)
	restore_animal_group(group_id)
	_animal_groups.unpin(group_id)


func cache_inactive_animal_group(
	group_id: String,
	source: Dictionary,
	anchor: Vector2i,
	reason: String
) -> void:
	# Fully loaded group territories are deterministic. Caching an empty result
	# prevents every one-cell streaming update from repeating habitat searches
	# for the same dry/invalid bucket. CommunityStateStore keeps this negative
	# cache bounded and evicts it before active groups.
	_animal_groups.set_or_put(group_id, {
		"anchor": anchor,
		"ecosystem_id": String(source.get("source_biome_id", "")),
		"community_id": String(source.get("community_id", "")),
		"social_radius": 0.0,
		"members": [],
		"inactive_reason": reason,
	})


func create_animal_group(
	group_id: String,
	ecosystem_id: String,
	rule: Dictionary,
	distribution: Dictionary,
	bucket: Vector2i,
	anchor: Vector2i,
	anchor_q: int,
	source: Dictionary = {}
) -> void:
	var count_range: Array = distribution.get("count", [1, 1])
	var minimum_count := int(count_range[0])
	var maximum_count := int(count_range[1])
	var count_span := maximum_count - minimum_count + 1
	var placement_seed := int(rule.get("placement_seed", 0))
	var desired_count := minimum_count + int(
		_cell_rand.call(bucket, placement_seed + 4) * count_span
	) % count_span
	var spawn_cells := animal_group_spawn_cells(
		anchor,
		anchor_q,
		ecosystem_id,
		distribution,
		desired_count,
		placement_seed,
		bool(rule.get("only_if_flora_missed", true)),
		source
	)
	if spawn_cells.size() < minimum_count:
		return
	var primary_species: String = _pick_species.call(rule, bucket, anchor)
	if primary_species.is_empty():
		return
	var members: Array[Dictionary] = []
	for spawn_cell in spawn_cells:
		members.append({"origin": spawn_cell, "species": primary_species})

	# substitution 替换群内成员而不是额外添加，狼群总数始终保持 7–8。
	var substitution: Dictionary = distribution.get("substitution", {})
	if not substitution.is_empty():
		var substitute_chance := float(substitution.get("chance", 0.0))
		if _cell_rand.call(bucket, placement_seed + 5) < substitute_chance:
			var substitute_count := mini(
				int(substitution.get("max_count", 1)),
				members.size()
			)
			var start_index := int(
				_cell_rand.call(bucket, placement_seed + 6) * members.size()
			) % members.size()
			for offset in substitute_count:
				var member_index := (start_index + offset) % members.size()
				members[member_index]["species"] = String(substitution.get("species", ""))

	_animal_groups.set_or_put(group_id, {
		"anchor": anchor,
		"ecosystem_id": ecosystem_id,
		"social_radius": float(distribution.get("social_radius", 0.0)),
		"members": members,
	}, true)
	restore_animal_group(group_id)
	_animal_groups.unpin(group_id)


func animal_group_spawn_cells(
	anchor: Vector2i,
	anchor_q: int,
	ecosystem_id: String,
	distribution: Dictionary,
	desired_count: int,
	placement_seed: int,
	only_if_flora_missed := true,
	source: Dictionary = {}
) -> Array[Vector2i]:
	var candidates: Array[Dictionary] = []
	var radius := maxi(0, int(distribution.get("radius", 0)))
	var same_ecosystem := bool(distribution.get("same_ecosystem", true))
	for offset_y in range(-radius, radius + 1):
		var row_radius := radius - absi(offset_y)
		for offset_x in range(-row_radius, row_radius + 1):
			var cell := anchor + Vector2i(offset_x, offset_y)
			if not animal_group_cell_is_valid(
				cell,
				anchor_q,
				ecosystem_id,
				same_ecosystem,
				only_if_flora_missed,
				source
			):
				continue
			candidates.append({
				"cell": cell,
				"anchor_first": 0 if cell == anchor else 1,
				"rank": _cell_rand.call(cell, placement_seed + 101),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["anchor_first"]) != int(b["anchor_first"]):
			return int(a["anchor_first"]) < int(b["anchor_first"])
		if not is_equal_approx(float(a["rank"]), float(b["rank"])):
			return float(a["rank"]) < float(b["rank"])
		var a_cell: Vector2i = a["cell"]
		var b_cell: Vector2i = b["cell"]
		return a_cell.y < b_cell.y or (a_cell.y == b_cell.y and a_cell.x < b_cell.x)
	)
	var result: Array[Vector2i] = []
	for candidate in candidates:
		if result.size() >= desired_count:
			break
		result.append(candidate["cell"])
	return result


func animal_group_cell_is_valid(
	cell: Vector2i,
	anchor_q: int,
	ecosystem_id: String,
	same_ecosystem: bool,
	only_if_flora_missed := true,
	source: Dictionary = {}
) -> bool:
	if (
		not _in_stream(cell)
		or not _cells.has(cell)
		or not _cell_states.has(cell)
	):
		return false
	var q: int = _quantize.call(cell.x, cell.y)
	if q <= _water_max or absi(_stand_level(q) - _stand_level(anchor_q)) > 1:
		return false
	if same_ecosystem:
		var context = _cell_context_for_query.call(cell)
		if not source.is_empty():
			if not _community_runtime.fauna_source_matches_context(
				source,
				context,
				_ecology_near_tag
			):
				return false
		elif _community_runtime.legacy_ecosystem_id(context) != ecosystem_id:
			return false
	var state = _cell_states[cell]
	return state.can_spawn_fauna(false, only_if_flora_missed)


func has_water_within(center: Vector2i, radius: int) -> bool:
	for offset_y in range(-radius, radius + 1):
		var row_radius := radius - absi(offset_y)
		for offset_x in range(-row_radius, row_radius + 1):
			if _quantize.call(center.x + offset_x, center.y + offset_y) <= _water_max:
				return true
	return false


func restore_animal_group(group_id: String) -> void:
	# 入口同步当前流式帧（宿主委托路径下字段可能滞后于 main 实时值）。
	if not _animal_groups.has(group_id):
		return
	var group: Dictionary = _animal_groups[group_id]
	var members: Array = group.get("members", [])
	var social_group_id := group_id if members.size() > 1 else ""
	for member_value in members:
		var member: Dictionary = member_value
		var origin: Vector2i = member["origin"]
		if _animals.has(origin) or not _in_stream(origin):
			continue
		if (
			origin == _player_cell
			or not _cells.has(origin)
			or _animal_cell_reserved.call(origin)
		):
			continue
		var animal: AnimatedSprite3D = _spawn_animal.call(
			String(member["species"]),
			origin,
			_quantize.call(origin.x, origin.y)
		)
		if animal == null:
			continue
		animal.community_group_id = group_id
		animal.social_group_id = social_group_id
		animal.social_radius = float(group.get("social_radius", 0.0))
	_animal_groups.set_active_member_count(
		group_id,
		active_animal_count_for_group(group_id)
	)


func active_animal_count_for_group(group_id: String) -> int:
	var count := 0
	for animal_value in _animals.values():
		var animal: AnimatedSprite3D = animal_value
		if (
			is_instance_valid(animal)
			and String(animal.community_group_id) == group_id
		):
			count += 1
	return count


func release_animal_group_member(animal: AnimatedSprite3D) -> void:
	var group_id := String(animal.community_group_id)
	if group_id.is_empty() or not _animal_groups.has(group_id):
		return
	_animal_groups.decrement_active_members(group_id)


func _stand_level(q: int) -> int:
	return maxi(q, _water_surface_level)


func _in_stream(cell: Vector2i) -> bool:
	return (
		absi(cell.x - _stream_center.x) <= _stream_extent
		and absi(cell.y - _stream_center.y) <= _stream_extent
	)
