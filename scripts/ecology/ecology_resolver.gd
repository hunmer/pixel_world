class_name EcologyResolver
extends RefCounted

## Resolves additive ecological communities from immutable CellContext facts.
##
## New ecology resolution is deliberately additive: one base biome contributes
## facts, while every matching habitat layer may attach more communities. Legacy
## first-match ecosystem behavior remains available through
## `resolve_legacy_first_match()` only for migration and regression checks.

const DEFAULT_HIGH_ALTITUDE_LEVEL := 14
const DEFAULT_SHALLOW_WATER_DEPTH := 2

var last_error: String = ""

var _catalog: Dictionary = {}
var _communities: Dictionary = {}
var _biomes: Dictionary = {}
var _community_order: Array = []
var _biome_order: Array = []
var _default_biome_id := ""
var _high_altitude_level := DEFAULT_HIGH_ALTITUDE_LEVEL


func configure(catalog: Dictionary) -> bool:
	last_error = ""
	_catalog = catalog.duplicate(true)
	var communities_value: Variant = _catalog.get("communities", null)
	var biomes_value: Variant = _catalog.get("biomes", null)
	if not communities_value is Dictionary:
		return _fail("ecology catalog communities must be a Dictionary")
	if not biomes_value is Dictionary:
		return _fail("ecology catalog biomes must be a Dictionary")
	_communities = communities_value
	_biomes = biomes_value
	_community_order = _catalog.get("community_order", _communities.keys()).duplicate()
	_biome_order = _catalog.get("biome_order", _biomes.keys()).duplicate()
	_default_biome_id = String(_catalog.get("default_biome_id", ""))
	if _default_biome_id.is_empty() or not _biomes.has(_default_biome_id):
		return _fail("ecology catalog default_biome_id is missing or unknown")
	for community_id_value in _community_order:
		if not _communities.has(String(community_id_value)):
			return _fail("community_order references unknown community: %s" % community_id_value)
	for biome_id_value in _biome_order:
		if not _biomes.has(String(biome_id_value)):
			return _fail("biome_order references unknown biome: %s" % biome_id_value)
	_high_altitude_level = _configured_high_altitude_level()
	return true


## Returns stable, de-duplicated, additive community definitions for one cell.
##
## `near_tag_query` is optional and, when used by a community habitat, receives:
##     (context, tag: StringName, radius: float) -> bool
func resolve(context: Variant, near_tag_query: Callable = Callable()) -> Dictionary:
	return _resolve(context, near_tag_query, &"", false)


## Resolves only one community kind. Cell flora and ambient generation use this
## entry point so unrelated fauna habitats (for example a frog's near-water
## query) are not evaluated thousands of times while the terrain is starting.
func resolve_kind(
	context: Variant,
	kind: StringName,
	near_tag_query: Callable = Callable()
) -> Dictionary:
	if kind not in [&"flora", &"fauna", &"ambient"]:
		return _empty_resolution()
	return _resolve(context, near_tag_query, kind, true)


func _resolve(
	context: Variant,
	near_tag_query: Callable,
	kind_filter: StringName,
	share_immutable_definitions: bool
) -> Dictionary:
	var empty_result := _empty_resolution()
	if _catalog.is_empty() or context == null:
		return empty_result
	var base_biome_id := _base_biome_id_for(context)
	if base_biome_id.is_empty():
		return empty_result
	var tags := _tags_for_context(context, base_biome_id)
	var matching_biome_ids := _matching_biome_ids(context, base_biome_id)
	var candidate_records: Array[Dictionary] = []
	for biome_id in matching_biome_ids:
		_append_biome_candidates(
			candidate_records,
			String(biome_id),
			_biomes[String(biome_id)]
		)

	var community_ids: Array[String] = []
	var community_definitions: Array[Dictionary] = []
	var community_weights := {}
	var community_sources := {}
	var seen_ids := {}
	for record in candidate_records:
		var community_id := String(record.get("community_id", ""))
		if community_id.is_empty() or seen_ids.has(community_id):
			continue
		var community_value: Variant = _communities.get(community_id, null)
		if not community_value is Dictionary:
			continue
		var community: Dictionary = community_value
		# Compatibility bundles are intentionally excluded from additive resolution.
		if String(community.get("kind", "")) == "legacy_bundle":
			continue
		if not kind_filter.is_empty() and StringName(community.get("kind", "")) != kind_filter:
			continue
		var weight := float(record.get("weight", 1.0))
		if weight <= 0.0:
			continue
		var effective_definition := _definition_with_overrides(
			community,
			record.get("overrides", {}),
			share_immutable_definitions
		)
		if not _habitat_matches(
			effective_definition.get("habitat", {}),
			context,
			base_biome_id,
			tags,
			near_tag_query
		):
			continue
		seen_ids[community_id] = true
		community_ids.append(community_id)
		community_definitions.append(effective_definition)
		community_weights[community_id] = weight
		community_sources[community_id] = String(record.get("source_biome_id", ""))

	return {
		"base_biome_id": base_biome_id,
		"tags": _sorted_tag_list(tags),
		"matched_biome_ids": matching_biome_ids,
		"community_ids": community_ids,
		"community_definitions": community_definitions,
		"community_weights": community_weights,
		"community_sources": community_sources,
	}


func resolve_ids(context: Variant, near_tag_query: Callable = Callable()) -> Array[String]:
	var result: Array[String] = []
	result.assign(resolve(context, near_tag_query).get("community_ids", []))
	return result


## Current ecosystems.json compatibility. This intentionally returns only the
## first matching legacy bundle and must not be used by new additive ecology.
func resolve_legacy_first_match(context: Variant) -> Dictionary:
	var empty_result := {
		"matched": false,
		"biome_rule_id": "",
		"community_id": "",
		"community": {},
	}
	if _catalog.is_empty() or context == null:
		return empty_result
	var biome_rule_id := resolve_legacy_id(context)
	if biome_rule_id.is_empty():
		return empty_result
	var legacy_id := _first_legacy_community_id(_biomes.get(biome_rule_id, {}))
	if legacy_id.is_empty():
		return empty_result
	return {
		"matched": true,
		"biome_rule_id": biome_rule_id,
		"community_id": legacy_id,
		"community": (_communities[legacy_id] as Dictionary).duplicate(true),
	}


## Fast identity-only compatibility lookup. Hot cell-generation paths do not
## need a deep copy of the complete legacy community bundle.
func resolve_legacy_id(context: Variant) -> String:
	if _catalog.is_empty() or context == null:
		return ""
	var base_biome_id := _base_biome_id_for(context)
	for biome_id_value in _biome_order:
		var biome_id := String(biome_id_value)
		var biome: Dictionary = _biomes[biome_id]
		if (
			_biome_match(biome.get("match", {}), context, base_biome_id)
			and not _first_legacy_community_id(biome).is_empty()
		):
			return biome_id
	var fallback_biome: Dictionary = _biomes.get(_default_biome_id, {})
	return (
		_default_biome_id
		if not _first_legacy_community_id(fallback_biome).is_empty()
		else ""
	)


func _base_biome_id_for(context: Variant) -> String:
	var context_biome_id := String(context.get("biome_id"))
	if _biomes.has(context_biome_id):
		var exact: Dictionary = _biomes[context_biome_id]
		if _is_base_biome_definition(exact):
			return context_biome_id
	for biome_id_value in _biome_order:
		var biome_id := String(biome_id_value)
		var biome: Dictionary = _biomes[biome_id]
		if not _is_base_biome_definition(biome):
			continue
		if String(biome.get("classification_id", "")) == context_biome_id:
			return biome_id
		if context_biome_id in _string_array(biome.get("aliases", [])):
			return biome_id
	for biome_id_value in _biome_order:
		var biome_id := String(biome_id_value)
		var biome: Dictionary = _biomes[biome_id]
		var match_value: Variant = biome.get("match", {})
		if not match_value is Dictionary:
			continue
		var match_rule: Dictionary = match_value
		if (
			_is_base_biome_definition(biome)
			and String(match_rule.get("biome", "")) == context_biome_id
		):
			return biome_id
	return _default_biome_id


func _is_base_biome_definition(biome: Dictionary) -> bool:
	if biome.has("script") or biome.has("classification_id"):
		return true
	var match_value: Variant = biome.get("match", {})
	if not match_value is Dictionary:
		return false
	var match_rule: Dictionary = match_value
	return (
		match_rule.has("biome")
		and not match_rule.has("water")
		and not match_rule.has("shore")
		and not match_rule.has("landform")
	)


func _tags_for_context(context: Variant, base_biome_id: String) -> Dictionary:
	var tags := {}
	var context_tags_value: Variant = context.get("tags")
	if context_tags_value is Dictionary:
		for tag_value in context_tags_value:
			_add_tag(tags, tag_value)
	elif context.has_method("tag_list"):
		for tag_value in context.call("tag_list"):
			_add_tag(tags, tag_value)

	var context_biome_id := String(context.get("biome_id"))
	_add_tag(tags, context_biome_id)
	_add_tag(tags, base_biome_id)
	var landform_id := String(context.get("landform_id"))
	var surface_id := String(context.get("surface_id"))
	_add_tag(tags, landform_id)
	_add_tag(tags, surface_id)
	if bool(context.get("is_water")):
		_add_tag(tags, "water")
		var water_depth := int(context.get("water_depth"))
		if water_depth <= DEFAULT_SHALLOW_WATER_DEPTH:
			_add_tag(tags, "shallow_water")
		else:
			_add_tag(tags, "deep_water")
	else:
		_add_tag(tags, "land")
	if bool(context.get("is_shore")):
		_add_tag(tags, "shore")
	if int(context.get("height")) >= _high_altitude_level:
		_add_tag(tags, "high_altitude")
	var surface_lower := surface_id.to_lower()
	if (
		"rock" in surface_lower
		or "stone" in surface_lower
		or "basalt" in surface_lower
		or landform_id in ["mountain", "mountains"]
	):
		_add_tag(tags, "rocky")
	var base_biome: Dictionary = _biomes.get(base_biome_id, {})
	for tag_value in base_biome.get("tags", []):
		_add_tag(tags, tag_value)
	return tags


func _matching_biome_ids(context: Variant, base_biome_id: String) -> Array[String]:
	var result: Array[String] = [base_biome_id]
	for biome_id_value in _biome_order:
		var biome_id := String(biome_id_value)
		if biome_id == base_biome_id:
			continue
		var biome: Dictionary = _biomes[biome_id]
		if _biome_match(biome.get("match", {}), context, base_biome_id):
			result.append(biome_id)
	return result


func _biome_match(match_value: Variant, context: Variant, base_biome_id: String) -> bool:
	if not match_value is Dictionary:
		return false
	var match_rule: Dictionary = match_value
	if match_rule.has("water") and bool(match_rule["water"]) != bool(context.get("is_water")):
		return false
	if match_rule.has("shore") and bool(match_rule["shore"]) != bool(context.get("is_shore")):
		return false
	if match_rule.has("biome"):
		var allowed_biomes := _string_array(match_rule["biome"])
		var candidates := _context_biome_candidates(context, base_biome_id)
		if not _arrays_intersect(allowed_biomes, candidates):
			return false
	if match_rule.has("landform"):
		var allowed_landforms := _string_array(match_rule["landform"])
		if String(context.get("landform_id")) not in allowed_landforms:
			return false
	var height := float(context.get("height"))
	if match_rule.has("minimum_level") and height < float(match_rule["minimum_level"]):
		return false
	if match_rule.has("maximum_level") and height > float(match_rule["maximum_level"]):
		return false
	return true


func _append_biome_candidates(
	records: Array[Dictionary],
	biome_id: String,
	biome: Dictionary
) -> void:
	for ref_value in biome.get("community_refs", []):
		records.append({
			"community_id": String(ref_value),
			"weight": 1.0,
			"overrides": {},
			"source_biome_id": biome_id,
		})
	for attachment_value in biome.get("attachments", []):
		if attachment_value is String:
			records.append({
				"community_id": String(attachment_value),
				"weight": 1.0,
				"overrides": {},
				"source_biome_id": biome_id,
			})
		elif attachment_value is Dictionary:
			var attachment: Dictionary = attachment_value
			if not bool(attachment.get("enabled", true)):
				continue
			records.append({
				"community_id": String(attachment.get("community_id", "")),
				"weight": float(attachment.get("weight", 1.0)),
				"overrides": attachment.get("overrides", {}),
				"source_biome_id": biome_id,
			})


func _habitat_matches(
	habitat_value: Variant,
	context: Variant,
	base_biome_id: String,
	tags: Dictionary,
	near_tag_query: Callable
) -> bool:
	if not habitat_value is Dictionary:
		return false
	var habitat: Dictionary = habitat_value
	for required_tag in _string_array(habitat.get("required_tags", [])):
		if not tags.has(StringName(required_tag)):
			return false
	for excluded_tag in _string_array(habitat.get("excluded_tags", [])):
		if tags.has(StringName(excluded_tag)):
			return false
	if habitat.has("biome_ids"):
		var allowed_biomes := _string_array(habitat["biome_ids"])
		if not _arrays_intersect(
			allowed_biomes,
			_context_biome_candidates(context, base_biome_id)
		):
			return false
	if habitat.has("landform_ids"):
		var allowed_landforms := _string_array(habitat["landform_ids"])
		if String(context.get("landform_id")) not in allowed_landforms:
			return false
	if habitat.has("water") and bool(habitat["water"]) != bool(context.get("is_water")):
		return false
	if habitat.has("shore") and bool(habitat["shore"]) != bool(context.get("is_shore")):
		return false
	var height := float(context.get("height"))
	if height < _minimum_value(habitat, ["min_height", "minimum_height"], -INF):
		return false
	if height > _maximum_value(habitat, ["max_height", "maximum_height"], INF):
		return false
	var water_depth := float(context.get("water_depth"))
	if water_depth < _minimum_value(
		habitat,
		["min_water_depth", "minimum_water_depth"],
		-INF
	):
		return false
	if water_depth > _maximum_value(
		habitat,
		["max_water_depth", "maximum_water_depth"],
		INF
	):
		return false
	var near_tags := _string_array(habitat.get("near_tags", habitat.get("near_tag", [])))
	var near_radius := float(habitat.get("near_tag_radius", habitat.get("radius", 1.0)))
	for tag_value in near_tags:
		var tag := StringName(tag_value)
		if tags.has(tag):
			continue
		if not near_tag_query.is_valid():
			return false
		if not bool(near_tag_query.call(context, tag, near_radius)):
			return false
	return true


func _definition_with_overrides(
	definition: Dictionary,
	overrides_value: Variant,
	allow_shared := false
) -> Dictionary:
	if allow_shared and (not overrides_value is Dictionary or overrides_value.is_empty()):
		# Catalog definitions are immutable after configure(); sharing them avoids
		# deep-copying every attached animal definition for every terrain cell.
		return definition
	var result := definition.duplicate(true)
	if overrides_value is Dictionary:
		_deep_merge(result, overrides_value)
	# An attachment may tune a community but cannot change its stable identity.
	result["id"] = definition.get("id", "")
	return result


func _deep_merge(target: Dictionary, overrides: Dictionary) -> void:
	for key in overrides:
		var override_value: Variant = overrides[key]
		if (
			target.get(key) is Dictionary
			and override_value is Dictionary
		):
			_deep_merge(target[key], override_value)
		else:
			target[key] = override_value.duplicate(true) if (
				override_value is Dictionary or override_value is Array
			) else override_value


func _first_legacy_community_id(biome: Dictionary) -> String:
	for community_id_value in biome.get("community_refs", []):
		var community_id := String(community_id_value)
		if (
			_communities.has(community_id)
			and String(_communities[community_id].get("kind", "")) == "legacy_bundle"
		):
			return community_id
	return ""


func _context_biome_candidates(context: Variant, base_biome_id: String) -> Array[String]:
	var result: Array[String] = []
	for value in [String(context.get("biome_id")), base_biome_id]:
		if not value.is_empty() and value not in result:
			result.append(value)
	var base_biome: Dictionary = _biomes.get(base_biome_id, {})
	for value in [String(base_biome.get("classification_id", ""))]:
		if not value.is_empty() and value not in result:
			result.append(value)
	for alias_value in base_biome.get("aliases", []):
		var alias := String(alias_value)
		if not alias.is_empty() and alias not in result:
			result.append(alias)
	return result


func _configured_high_altitude_level() -> int:
	var world_value: Variant = _catalog.get("world", {})
	if not world_value is Dictionary:
		return DEFAULT_HIGH_ALTITUDE_LEVEL
	var world: Dictionary = world_value
	var generation_value: Variant = world.get("generation", {})
	if not generation_value is Dictionary:
		return DEFAULT_HIGH_ALTITUDE_LEVEL
	var generation: Dictionary = generation_value
	var climate_value: Variant = generation.get("climate", {})
	if not climate_value is Dictionary:
		return DEFAULT_HIGH_ALTITUDE_LEVEL
	var climate: Dictionary = climate_value
	var snow_value: Variant = climate.get("snow", {})
	if not snow_value is Dictionary:
		return DEFAULT_HIGH_ALTITUDE_LEVEL
	return int(snow_value.get("base_level", DEFAULT_HIGH_ALTITUDE_LEVEL))


func _minimum_value(values: Dictionary, keys: Array, fallback: float) -> float:
	for key in keys:
		if values.has(key):
			return float(values[key])
	return fallback


func _maximum_value(values: Dictionary, keys: Array, fallback: float) -> float:
	for key in keys:
		if values.has(key):
			return float(values[key])
	return fallback


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	var values: Array = value if value is Array else [value]
	for item in values:
		var string_value := String(item)
		if not string_value.is_empty() and string_value not in result:
			result.append(string_value)
	return result


func _arrays_intersect(left: Array[String], right: Array[String]) -> bool:
	for value in left:
		if value in right:
			return true
	return false


func _add_tag(tags: Dictionary, value: Variant) -> void:
	var tag := StringName(String(value))
	if not tag.is_empty():
		tags[tag] = true


func _sorted_tag_list(tags: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(tags.keys())
	result.sort()
	return result


func _empty_resolution() -> Dictionary:
	return {
		"base_biome_id": "",
		"tags": [] as Array[StringName],
		"matched_biome_ids": [] as Array[String],
		"community_ids": [] as Array[String],
		"community_definitions": [] as Array[Dictionary],
		"community_weights": {},
		"community_sources": {},
	}


func _fail(message: String) -> bool:
	last_error = message
	return false
