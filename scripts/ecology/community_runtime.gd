class_name CommunityRuntime
extends RefCounted

## Migration adapter between first-class CommunityDefinition data and the
## existing ecosystem loops in main.gd.
##
## The resolver remains the source of habitat matching. This class only owns
## compatibility concerns: selecting the legacy first-match bundle, converting
## matching first-class definitions to the current rule shape, and suppressing
## a legacy pool when a first-class community explicitly takes it over through
## metadata.legacy_pool_id.

const EcologyResolverScript = preload("res://scripts/ecology/ecology_resolver.gd")

const RULE_KINDS := [&"flora", &"fauna", &"ambient"]
const MAX_WEIGHTED_POOL_SIZE := 96
const WEIGHT_PRECISION := 1000

var last_error := ""
var warnings: Array[String] = []

var _catalog: Dictionary = {}
var _communities: Dictionary = {}
var _biomes: Dictionary = {}
var _species: Dictionary = {}
var _biome_order: Array = []
var _community_order: Array = []
var _resolver: RefCounted
var _legacy_rules: Dictionary = {}
var _legacy_community_by_ecosystem: Dictionary = {}
var _fauna_source_cache: Array[Dictionary] = []
var _spatial_flora_source_cache: Array[Dictionary] = []
var _cell_rule_cache: Dictionary = {}
var _context_rule_cache: Dictionary = {}
var _kind_uses_near_tag := {
	&"flora": false,
	&"fauna": false,
	&"ambient": false,
}
var _kind_has_first_class := {
	&"flora": false,
	&"fauna": false,
	&"ambient": false,
}
var _configured := false


func configure(catalog: Dictionary) -> bool:
	_reset()
	if catalog.is_empty():
		return _fail("community runtime catalog is empty")
	if not catalog.get("communities", null) is Dictionary:
		return _fail("community runtime catalog.communities must be a Dictionary")
	if not catalog.get("biomes", null) is Dictionary:
		return _fail("community runtime catalog.biomes must be a Dictionary")
	if not catalog.get("species", {}) is Dictionary:
		return _fail("community runtime catalog.species must be a Dictionary")

	_catalog = catalog.duplicate(true)
	_communities = _catalog["communities"]
	_biomes = _catalog["biomes"]
	_species = _catalog.get("species", {})
	_biome_order = _catalog.get("biome_order", _biomes.keys()).duplicate()
	_community_order = _catalog.get("community_order", _communities.keys()).duplicate()

	_resolver = EcologyResolverScript.new()
	if not _resolver.configure(_catalog):
		return _fail("community runtime resolver configuration failed: %s" % _resolver.last_error)

	_index_legacy_bundles()
	_collect_compatibility_warnings()
	_index_near_tag_usage()
	_fauna_source_cache = _build_fauna_sources()
	_spatial_flora_source_cache = _build_spatial_flora_sources()
	_configured = true
	return true


func is_configured() -> bool:
	return _configured


## Returns the additive resolver result together with the compatibility
## ecosystem selected by the old first-match rules.
func resolve(context: Variant, near_tag_query: Callable = Callable()) -> Dictionary:
	if not _configured or context == null:
		return {}
	var result: Dictionary = _resolver.resolve(context, near_tag_query)
	var legacy: Dictionary = _resolver.resolve_legacy_first_match(context)
	result["legacy_ecosystem_id"] = String(legacy.get("biome_rule_id", ""))
	result["legacy_community_id"] = String(legacy.get("community_id", ""))
	return result


## Existing cell flora loop adapter. Legacy rules remain first in declaration
## order. A matching first-class definition then replaces the legacy pool named
## by metadata.legacy_pool_id (or by its own community ID when omitted).
func flora_rules_for_cell(
	context: Variant,
	near_tag_query: Callable = Callable()
) -> Array[Dictionary]:
	return _rules_for_cell(&"flora", context, near_tag_query, false)


## Rules consumed by the legacy one-cell placement loop. Generic spatial
## definitions are omitted here because spatial_flora_sources() owns them.
func cell_flora_rules_for_cell(
	context: Variant,
	near_tag_query: Callable = Callable()
) -> Array[Dictionary]:
	return _rules_for_cell(&"flora", context, near_tag_query, true)


## Existing cell ambient loop adapter. It has the same takeover semantics as
## flora_rules_for_cell().
func ambient_rules_for_cell(
	context: Variant,
	near_tag_query: Callable = Callable()
) -> Array[Dictionary]:
	return _rules_for_cell(&"ambient", context, near_tag_query)


## Stable sources consumable by the current sparse territory loop. Each entry:
##     {source_biome_id, community_id, first_class, rule}
##
## First-class fauna attached to a biome owns its legacy pool, so the old fauna
## rule is not also emitted for that source biome.
func fauna_sources() -> Array[Dictionary]:
	return _fauna_source_cache.duplicate(true)


## First-class flora without a legacy placement seed uses CommunitySpawner.
## Existing migrated pools remain in flora_rules_for_cell() to preserve their
## established random stream and density.
func spatial_flora_sources() -> Array[Dictionary]:
	return _spatial_flora_source_cache.duplicate(true)


func flora_source_matches_context(
	source: Dictionary,
	context: Variant,
	near_tag_query: Callable = Callable()
) -> bool:
	return _first_class_source_matches_context(source, context, near_tag_query)


## Tests whether a normalized fauna source applies to one immutable cell.
## First-class definitions use additive habitat resolution; compatibility
## bundles retain the old first-match ecosystem identity.
func fauna_source_matches_context(
	source: Dictionary,
	context: Variant,
	near_tag_query: Callable = Callable()
) -> bool:
	if not _configured or context == null:
		return false
	if bool(source.get("first_class", false)):
		return _first_class_source_matches_context(source, context, near_tag_query)
	return legacy_ecosystem_id(context) == String(source.get("source_biome_id", ""))


func _first_class_source_matches_context(
	source: Dictionary,
	context: Variant,
	near_tag_query: Callable
) -> bool:
	if not _configured or context == null:
		return false
	var community_id := String(source.get("community_id", ""))
	var resolution := resolve(context, near_tag_query)
	if community_id not in (resolution.get("community_ids", []) as Array):
		return false
	return String(
		(resolution.get("community_sources", {}) as Dictionary).get(community_id, "")
	) == String(source.get("source_biome_id", ""))


## Compatibility identity used by movement/group state while main.gd migrates
## away from integer ecosystem enums.
func legacy_ecosystem_id(context: Variant) -> String:
	if not _configured or context == null:
		return ""
	return _resolver.resolve_legacy_id(context)


## Raw legacy bundle rules indexed by ecosystem ID. This intentionally does not
## add first-class communities; callers that need effective fauna must use
## fauna_sources(), and cell callers must use the two *_rules_for_cell methods.
func legacy_rules_by_ecosystem(kind: StringName) -> Dictionary:
	if kind not in RULE_KINDS:
		return {}
	var result := {}
	for ecosystem_id_value in _biome_order:
		var ecosystem_id := String(ecosystem_id_value)
		result[ecosystem_id] = (
			(_legacy_rules.get(ecosystem_id, {}) as Dictionary)
			.get(String(kind), [])
			.duplicate(true)
		)
	return result


func _rules_for_cell(
	kind: StringName,
	context: Variant,
	near_tag_query: Callable,
	exclude_spatial_flora := false
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _configured or context == null or kind not in RULE_KINDS:
		return result
	if not bool(_kind_has_first_class.get(kind, false)):
		var legacy_only_id: String = _resolver.resolve_legacy_id(context)
		var legacy_only_key := "legacy-only|%s|%s" % [kind, legacy_only_id]
		if _cell_rule_cache.has(legacy_only_key):
			return (_cell_rule_cache[legacy_only_key] as Array).duplicate()
		for rule_value in (
			(_legacy_rules.get(legacy_only_id, {}) as Dictionary)
			.get(String(kind), [])
		):
			if rule_value is Dictionary:
				result.append((rule_value as Dictionary).duplicate(true))
		_cell_rule_cache[legacy_only_key] = result
		return result.duplicate()
	var context_cache_key := ""
	if not bool(_kind_uses_near_tag.get(kind, false)):
		context_cache_key = _context_rule_cache_key(
			kind, exclude_spatial_flora, context
		)
		if _context_rule_cache.has(context_cache_key):
			return (_context_rule_cache[context_cache_key] as Array).duplicate()

	var legacy_ecosystem: String = _resolver.resolve_legacy_id(context)
	var legacy_rules: Array = (
		(_legacy_rules.get(legacy_ecosystem, {}) as Dictionary)
		.get(String(kind), [])
	)
	# Resolve only the requested layer. Resolving every attached community here
	# made flora generation evaluate fauna-only habitat scans for every cell.
	var additive: Dictionary = _resolver.resolve_kind(context, kind, near_tag_query)
	var definitions: Array = additive.get("community_definitions", [])
	var sources: Dictionary = additive.get("community_sources", {})
	var cache_key := _cell_rule_cache_key(
		kind,
		exclude_spatial_flora,
		legacy_ecosystem,
		definitions,
		sources
	)
	if _cell_rule_cache.has(cache_key):
		return (_cell_rule_cache[cache_key] as Array).duplicate()
	var owned_keys := {}
	var emitted_keys := {}
	var normalized_rules: Array[Dictionary] = []
	for definition_value in definitions:
		if not definition_value is Dictionary:
			continue
		var definition: Dictionary = definition_value
		if _rule_kind_for(definition) != kind:
			continue
		var community_id := String(definition.get("id", ""))
		var ownership := _ownership_keys(definition)
		if _has_any_key(emitted_keys, ownership):
			continue
		if (
			kind == &"flora"
			and exclude_spatial_flora
			and _uses_generic_spatial_flora(definition)
		):
			_mark_keys(emitted_keys, ownership)
			_mark_keys(owned_keys, ownership)
			continue
		var source_biome_id := String(sources.get(community_id, ""))
		var template := _legacy_template_for(
			kind,
			_pool_id_for(definition),
			[legacy_ecosystem, source_biome_id]
		)
		var rule := _normalize_definition(definition, kind, template)
		if rule.is_empty():
			continue
		_mark_keys(emitted_keys, ownership)
		_mark_keys(owned_keys, ownership)
		normalized_rules.append(rule)

	for rule_value in legacy_rules:
		if not rule_value is Dictionary:
			continue
		var rule: Dictionary = rule_value
		if owned_keys.has(String(rule.get("pool_id", ""))):
			continue
		result.append(rule.duplicate(true))
	result.append_array(normalized_rules)
	_cell_rule_cache[cache_key] = result
	if not context_cache_key.is_empty():
		_context_rule_cache[context_cache_key] = result
	return result.duplicate()


func _context_rule_cache_key(
	kind: StringName,
	exclude_spatial_flora: bool,
	context: Variant
) -> String:
	return "%s|%d|%s" % [
		kind,
		1 if exclude_spatial_flora else 0,
		context.ecology_signature(),
	]


func _index_near_tag_usage() -> void:
	for kind in RULE_KINDS:
		_kind_uses_near_tag[kind] = false
		_kind_has_first_class[kind] = false
	for definition_value in _communities.values():
		if not definition_value is Dictionary:
			continue
		var definition: Dictionary = definition_value
		var kind := _rule_kind_for(definition)
		if kind not in RULE_KINDS:
			continue
		_kind_has_first_class[kind] = true
		var habitat_value: Variant = definition.get("habitat", {})
		if not habitat_value is Dictionary:
			continue
		var habitat: Dictionary = habitat_value
		if not _string_array(
			habitat.get("near_tags", habitat.get("near_tag", []))
		).is_empty():
			_kind_uses_near_tag[kind] = true


func _cell_rule_cache_key(
	kind: StringName,
	exclude_spatial_flora: bool,
	legacy_ecosystem: String,
	definitions: Array,
	sources: Dictionary
) -> String:
	var parts: Array[String] = [
		String(kind),
		"spatial_excluded" if exclude_spatial_flora else "spatial_included",
		legacy_ecosystem,
	]
	for definition_value in definitions:
		if not definition_value is Dictionary:
			continue
		var definition: Dictionary = definition_value
		var community_id := String(definition.get("id", ""))
		parts.append("%s@%s#%d" % [
			community_id,
			String(sources.get(community_id, "")),
			hash(definition),
		])
	return "|".join(parts)


func _build_fauna_sources() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for biome_id_value in _biome_order:
		var biome_id := String(biome_id_value)
		if not _biomes.has(biome_id):
			continue
		var biome: Dictionary = _biomes[biome_id]
		var definitions := _first_class_definitions_for_biome(biome, &"fauna")
		var owned_keys := {}
		var emitted_keys := {}
		var normalized_entries: Array[Dictionary] = []
		for definition in definitions:
			var ownership := _ownership_keys(definition)
			if _has_any_key(emitted_keys, ownership):
				continue
			var template := _legacy_template_for(
				&"fauna", _pool_id_for(definition), [biome_id]
			)
			var rule := _normalize_definition(definition, &"fauna", template)
			if rule.is_empty():
				continue
			_mark_keys(emitted_keys, ownership)
			_mark_keys(owned_keys, ownership)
			normalized_entries.append({
				"source_biome_id": biome_id,
				"community_id": String(definition.get("id", "")),
				"first_class": true,
				"definition": definition.duplicate(true),
				"rule": rule,
			})

		var legacy_community_id := String(
			_legacy_community_by_ecosystem.get(biome_id, "")
		)
		var legacy_fauna: Array = (
			(_legacy_rules.get(biome_id, {}) as Dictionary).get("fauna", [])
		)
		for rule_value in legacy_fauna:
			if not rule_value is Dictionary:
				continue
			var legacy_rule: Dictionary = rule_value
			if owned_keys.has(String(legacy_rule.get("pool_id", ""))):
				continue
			result.append({
				"source_biome_id": biome_id,
				"community_id": legacy_community_id,
				"first_class": false,
				"rule": legacy_rule.duplicate(true),
			})
		result.append_array(normalized_entries)
	return result


func _build_spatial_flora_sources() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for biome_id_value in _biome_order:
		var biome_id := String(biome_id_value)
		if not _biomes.has(biome_id):
			continue
		var biome: Dictionary = _biomes[biome_id]
		var emitted := {}
		for definition in _first_class_definitions_for_biome(biome, &"flora"):
			var community_id := String(definition.get("id", ""))
			if (
				community_id.is_empty()
				or emitted.has(community_id)
				or not _uses_generic_spatial_flora(definition)
			):
				continue
			emitted[community_id] = true
			result.append({
				"source_biome_id": biome_id,
				"community_id": community_id,
				"first_class": true,
				"definition": definition.duplicate(true),
			})
	return result


func _uses_generic_spatial_flora(definition: Dictionary) -> bool:
	var metadata_value: Variant = definition.get("metadata", {})
	var metadata: Dictionary = metadata_value if metadata_value is Dictionary else {}
	return _rule_kind_for(definition) == &"flora" and not metadata.has(
		"legacy_placement_seed"
	)


func _first_class_definitions_for_biome(
	biome: Dictionary,
	kind: StringName
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for community_id_value in biome.get("community_refs", []):
		var community_id := String(community_id_value)
		var definition_value: Variant = _communities.get(community_id, null)
		if not definition_value is Dictionary:
			continue
		var definition: Dictionary = definition_value
		if String(definition.get("kind", "")) == "legacy_bundle":
			continue
		if _rule_kind_for(definition) == kind:
			result.append(definition.duplicate(true))
	for attachment_value in biome.get("attachments", []):
		var community_id := ""
		var overrides: Dictionary = {}
		var weight := 1.0
		if attachment_value is String:
			community_id = String(attachment_value)
		elif attachment_value is Dictionary:
			var attachment: Dictionary = attachment_value
			if not bool(attachment.get("enabled", true)):
				continue
			community_id = String(attachment.get("community_id", ""))
			weight = float(attachment.get("weight", 1.0))
			var overrides_value: Variant = attachment.get("overrides", {})
			if overrides_value is Dictionary:
				overrides = overrides_value
		if weight <= 0.0:
			continue
		var definition_value: Variant = _communities.get(community_id, null)
		if not definition_value is Dictionary:
			continue
		var definition: Dictionary = (definition_value as Dictionary).duplicate(true)
		if String(definition.get("kind", "")) == "legacy_bundle":
			continue
		_deep_merge(definition, overrides)
		definition["id"] = community_id
		if _rule_kind_for(definition) == kind:
			result.append(definition)
	return result


func _normalize_definition(
	definition: Dictionary,
	kind: StringName,
	legacy_template: Dictionary = {}
) -> Dictionary:
	var rule := legacy_template.duplicate(true)
	var community_id := String(definition.get("id", ""))
	if community_id.is_empty():
		return {}
	var distribution := _distribution_for(definition)
	var metadata_value: Variant = definition.get("metadata", {})
	var metadata: Dictionary = metadata_value if metadata_value is Dictionary else {}
	var stream_key := String(definition.get("stream_key", community_id))
	if stream_key.is_empty():
		stream_key = community_id

	rule["pool_id"] = _pool_id_for(definition)
	rule["selection_seed_key"] = String(
		metadata.get("legacy_selection_seed_key", stream_key)
	)
	rule["placement_seed"] = int(
		metadata.get(
			"legacy_placement_seed",
			_stable_seed(stream_key + "/placement")
		)
	)
	if distribution.has("chance") or definition.has("chance"):
		rule["chance"] = (
			distribution.get("chance", definition.get("chance", 1.0))
		)
	elif not rule.has("chance"):
		rule["chance"] = 1.0

	match kind:
		&"flora":
			_normalize_flora_rule(rule, definition)
		&"fauna":
			_normalize_fauna_rule(rule, definition, distribution, metadata)
		&"ambient":
			_normalize_ambient_rule(rule, definition, metadata)
		_:
			return {}
	if (rule.get("species", []) as Array).is_empty():
		return {}
	return rule


func _normalize_flora_rule(rule: Dictionary, definition: Dictionary) -> void:
	var members := _members_for_kind(definition, &"flora")
	rule["species"] = _weighted_species_pool(members)
	var layer := String(rule.get("layer", ""))
	if layer.is_empty():
		layer = _flora_layer_for_members(members)
	if layer.is_empty():
		layer = "ground_cover"
	rule["layer"] = layer

	var habitat_value: Variant = definition.get("habitat", {})
	var habitat: Dictionary = habitat_value if habitat_value is Dictionary else {}
	var placement := String(habitat.get("placement", rule.get("placement", "")))
	for member in members:
		if member.has("placement"):
			placement = String(member["placement"])
			break
	if placement.is_empty():
		placement = "ground"
	rule["placement"] = placement
	if habitat.has("maximum_water_depth") or habitat.has("max_water_depth"):
		rule["max_water_depth"] = int(
			habitat.get("maximum_water_depth", habitat.get("max_water_depth", 0))
		)
	if not rule.has("render_priority"):
		rule["render_priority"] = 12 if placement == "water_surface" else 0 if placement == "lakebed" else 8


func _normalize_fauna_rule(
	rule: Dictionary,
	definition: Dictionary,
	distribution: Dictionary,
	metadata: Dictionary
) -> void:
	var members := _members_for_kind(definition, &"fauna")
	var fill_members: Array[Dictionary] = []
	var companion_members: Array[Dictionary] = []
	for member in members:
		if bool(member.get("fill_remaining", false)):
			fill_members.append(member)
		elif String(member.get("role", "")) == "companion":
			companion_members.append(member)
	if fill_members.is_empty():
		for member in members:
			if member not in companion_members:
				fill_members.append(member)
	rule["species"] = _weighted_species_pool(fill_members)
	rule["only_if_flora_missed"] = bool(
		metadata.get(
			"only_if_flora_missed",
			rule.get("only_if_flora_missed", true)
		)
	)

	var habitat_value: Variant = definition.get("habitat", {})
	var habitat: Dictionary = habitat_value if habitat_value is Dictionary else {}
	var normalized_distribution: Dictionary = rule.get("distribution", {}).duplicate(true)
	normalized_distribution["anchor_spacing"] = maxi(
		1, int(distribution.get("anchor_spacing", 1))
	)
	normalized_distribution["anchor_jitter"] = clampf(
		float(distribution.get("anchor_jitter", distribution.get("jitter", 1.0))),
		0.0,
		1.0
	)
	normalized_distribution["count"] = _count_range(distribution.get("count", [1, 1]))
	normalized_distribution["radius"] = maxi(0, int(distribution.get("radius", 0)))
	normalized_distribution["social_radius"] = maxf(
		0.0,
		float(distribution.get("social_radius", distribution.get("radius", 0)))
	)
	normalized_distribution["same_ecosystem"] = bool(
		distribution.get(
			"same_ecosystem",
			distribution.get("same_biome", habitat.get("same_biome", true))
		)
	)
	var near_tags := _string_array(habitat.get("near_tags", habitat.get("near_tag", [])))
	if "water" in near_tags:
		normalized_distribution["requires_water_within"] = maxi(
			0,
			int(habitat.get("near_tag_radius", habitat.get("radius", 1)))
		)
	if companion_members.size() == 1:
		var companion: Dictionary = companion_members[0]
		var companion_count := _count_range(companion.get("count", 1))
		normalized_distribution["substitution"] = {
			"species": _species_id_for_member(companion),
			"chance": clampf(float(companion.get("chance", 1.0)), 0.0, 1.0),
			"max_count": maxi(1, int(companion_count[1])),
		}
	rule["distribution"] = normalized_distribution


func _normalize_ambient_rule(
	rule: Dictionary,
	definition: Dictionary,
	metadata: Dictionary
) -> void:
	rule["species"] = _weighted_species_pool(
		_members_for_kind(definition, &"ambient")
	)
	rule["requires_ground_flora"] = bool(
		metadata.get(
			"requires_ground_flora",
			rule.get("requires_ground_flora", false)
		)
	)


func _members_for_kind(definition: Dictionary, kind: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for member_value in definition.get("members", definition.get("species", [])):
		var member: Dictionary
		if member_value is String or member_value is StringName:
			member = {"species_id": String(member_value), "weight": 1.0}
		elif member_value is Dictionary:
			member = (member_value as Dictionary).duplicate(true)
		else:
			continue
		var category := _category_to_rule_kind(String(member.get("category", "")))
		if not category.is_empty() and category != kind:
			continue
		if _species_id_for_member(member).is_empty():
			continue
		result.append(member)
	return result


func _weighted_species_pool(members: Array[Dictionary]) -> Array[String]:
	var weighted: Array[Dictionary] = []
	var divisor := 0
	for member in members:
		var species_id := _species_id_for_member(member)
		var weight := maxf(0.0, float(member.get("weight", 1.0)))
		if species_id.is_empty() or weight <= 0.0:
			continue
		var integer_weight := maxi(1, roundi(weight * WEIGHT_PRECISION))
		divisor = integer_weight if divisor == 0 else _greatest_common_divisor(divisor, integer_weight)
		weighted.append({"species_id": species_id, "integer_weight": integer_weight})
	if weighted.is_empty():
		return []

	var counts: Array[int] = []
	var total_count := 0
	for value in weighted:
		var count := maxi(1, int(value["integer_weight"]) / maxi(1, divisor))
		counts.append(count)
		total_count += count
	if total_count > MAX_WEIGHTED_POOL_SIZE:
		var scale := float(MAX_WEIGHTED_POOL_SIZE) / float(total_count)
		total_count = 0
		for index in counts.size():
			counts[index] = maxi(1, roundi(float(counts[index]) * scale))
			total_count += counts[index]

	var result: Array[String] = []
	for index in weighted.size():
		for unused_repeat in counts[index]:
			result.append(String(weighted[index]["species_id"]))
	return result


func _flora_layer_for_members(members: Array[Dictionary]) -> String:
	var layer := ""
	for member in members:
		var species_id := _species_id_for_member(member)
		var plant_value: Variant = (
			(_species.get("plants", {}) as Dictionary).get(species_id, {})
		)
		if not plant_value is Dictionary:
			continue
		var member_layer := String((plant_value as Dictionary).get("layer", ""))
		if member_layer.is_empty():
			continue
		if layer.is_empty():
			layer = member_layer
		elif member_layer != layer:
			return layer
	return layer


func _rule_kind_for(definition: Dictionary) -> StringName:
	var explicit_kind := StringName(String(definition.get("kind", "")))
	if explicit_kind in RULE_KINDS:
		return explicit_kind
	for member_value in definition.get("members", []):
		if member_value is Dictionary:
			var inferred := _category_to_rule_kind(String(member_value.get("category", "")))
			if not inferred.is_empty():
				return inferred
	return &""


func _category_to_rule_kind(category: String) -> StringName:
	match category:
		"plant", "plants", "flora":
			return &"flora"
		"animal", "animals", "fauna":
			return &"fauna"
		"ambient":
			return &"ambient"
	return &""


func _distribution_for(definition: Dictionary) -> Dictionary:
	var distribution_value: Variant = definition.get("distribution", {})
	var result: Dictionary = (
		distribution_value.duplicate(true)
		if distribution_value is Dictionary
		else {}
	)
	for key in [
		"chance",
		"anchor_spacing",
		"anchor_jitter",
		"jitter",
		"count",
		"radius",
	]:
		if not result.has(key) and definition.has(key):
			result[key] = definition[key]
	return result


func _pool_id_for(definition: Dictionary) -> String:
	var metadata_value: Variant = definition.get("metadata", {})
	var metadata: Dictionary = metadata_value if metadata_value is Dictionary else {}
	var community_id := String(definition.get("id", ""))
	var pool_id := String(metadata.get("legacy_pool_id", community_id))
	return pool_id if not pool_id.is_empty() else community_id


func _ownership_keys(definition: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value in [String(definition.get("id", "")), _pool_id_for(definition)]:
		if not value.is_empty() and value not in result:
			result.append(value)
	return result


func _legacy_template_for(
	kind: StringName,
	pool_id: String,
	preferred_ecosystems: Array
) -> Dictionary:
	if pool_id.is_empty():
		return {}
	var searched := {}
	for ecosystem_id_value in preferred_ecosystems + _biome_order:
		var ecosystem_id := String(ecosystem_id_value)
		if ecosystem_id.is_empty() or searched.has(ecosystem_id):
			continue
		searched[ecosystem_id] = true
		var rules: Array = (
			(_legacy_rules.get(ecosystem_id, {}) as Dictionary)
			.get(String(kind), [])
		)
		for rule_value in rules:
			if (
				rule_value is Dictionary
				and String(rule_value.get("pool_id", "")) == pool_id
			):
				return (rule_value as Dictionary).duplicate(true)
	return {}


func _index_legacy_bundles() -> void:
	for biome_id_value in _biome_order:
		var biome_id := String(biome_id_value)
		var kind_rules := {"flora": [], "fauna": [], "ambient": []}
		var legacy_community_id := ""
		var biome_value: Variant = _biomes.get(biome_id, null)
		if biome_value is Dictionary:
			for community_id_value in biome_value.get("community_refs", []):
				var community_id := String(community_id_value)
				var community_value: Variant = _communities.get(community_id, null)
				if (
					community_value is Dictionary
					and String(community_value.get("kind", "")) == "legacy_bundle"
				):
					legacy_community_id = community_id
					for kind in RULE_KINDS:
						kind_rules[String(kind)] = (
							community_value.get(String(kind), []) as Array
						).duplicate(true)
					break
		_legacy_rules[biome_id] = kind_rules
		_legacy_community_by_ecosystem[biome_id] = legacy_community_id


func _collect_compatibility_warnings() -> void:
	for community_id_value in _community_order:
		var community_id := String(community_id_value)
		var definition_value: Variant = _communities.get(community_id, null)
		if not definition_value is Dictionary:
			continue
		var definition: Dictionary = definition_value
		if String(definition.get("kind", "")) == "legacy_bundle":
			continue
		if _rule_kind_for(definition) != &"flora":
			continue
		var distribution := _distribution_for(definition)
		if (
			String(distribution.get("strategy", "scatter")) == "patch"
			or distribution.has("anchor_spacing")
			or distribution.has("count")
			or distribution.has("radius")
		):
			warnings.append(
				(
					"flora community %s keeps chance/members in the legacy cell rule, "
					+ "but patch anchor/count/radius require CommunitySpawner integration"
				) % community_id
			)


func _has_any_key(seen: Dictionary, keys: Array[String]) -> bool:
	for key in keys:
		if seen.has(key):
			return true
	return false


func _mark_keys(seen: Dictionary, keys: Array[String]) -> void:
	for key in keys:
		seen[key] = true


func _species_id_for_member(member: Dictionary) -> String:
	return String(member.get("species_id", member.get("species", "")))


func _count_range(value: Variant) -> Array[int]:
	if value is Array and value.size() >= 2:
		var minimum_count := maxi(1, int(value[0]))
		return [minimum_count, maxi(minimum_count, int(value[1]))]
	var count := maxi(1, int(value))
	return [count, count]


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	var values: Array = value if value is Array else [value]
	for item in values:
		var string_value := String(item)
		if not string_value.is_empty() and string_value not in result:
			result.append(string_value)
	return result


func _greatest_common_divisor(left: int, right: int) -> int:
	var a := absi(left)
	var b := absi(right)
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return maxi(1, a)


func _stable_seed(value: String) -> int:
	var hash_value: int = 2166136261
	for byte_value in value.to_utf8_buffer():
		hash_value = int((hash_value ^ int(byte_value)) * 16777619) & 0x7fffffff
	return hash_value if hash_value != 0 else 1


func _deep_merge(target: Dictionary, overrides: Dictionary) -> void:
	for key in overrides:
		var override_value: Variant = overrides[key]
		if target.get(key) is Dictionary and override_value is Dictionary:
			_deep_merge(target[key], override_value)
		else:
			target[key] = (
				override_value.duplicate(true)
				if override_value is Dictionary or override_value is Array
				else override_value
			)


func _reset() -> void:
	last_error = ""
	warnings.clear()
	_catalog.clear()
	_communities.clear()
	_biomes.clear()
	_species.clear()
	_biome_order.clear()
	_community_order.clear()
	_resolver = null
	_legacy_rules.clear()
	_legacy_community_by_ecosystem.clear()
	_fauna_source_cache.clear()
	_spatial_flora_source_cache.clear()
	_cell_rule_cache.clear()
	_context_rule_cache.clear()
	for kind in RULE_KINDS:
		_kind_uses_near_tag[kind] = false
		_kind_has_first_class[kind] = false
	_configured = false


func _fail(message: String) -> bool:
	last_error = message
	return false
