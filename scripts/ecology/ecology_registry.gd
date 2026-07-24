class_name EcologyRegistry
extends RefCounted

## Pure-data loader for modular ecology configuration.
##
## A manifest declares one or more JSON modules. Modules are merged by stable IDs
## into a catalog before any cross-reference is validated, so definitions may be
## split across files without becoming order-dependent.

const SCHEMA_VERSION := 1
const MODULE_KINDS := ["world", "species", "communities", "biomes"]
const SPECIES_CATEGORIES := ["plants", "animals", "ambient"]

const MANIFEST_FIELDS := ["version", "modules"]
const MODULE_REFERENCE_FIELDS := ["kind", "path"]
const MODULE_FIELDS := {
	"world": ["version", "kind", "world"],
	"species": ["version", "kind", "species"],
	"communities": ["version", "kind", "communities"],
	"biomes": ["version", "kind", "biomes"],
}
const WORLD_FIELDS := [
	"default_biome_id",
	"generation",
	"pool_selection",
	"metadata",
]
const PLANT_FIELDS := ["layer", "texture", "habitat", "tags", "traits", "metadata"]
const PLANT_HABITAT_FIELDS := ["near_flora_layer", "radius", "fallback_species"]
const ANIMAL_FIELDS := [
	"directory",
	"behavior",
	"behaviors",
	"allowed_surfaces",
	"max_step_height",
	"foot_offset_y",
	"movement",
	"actions",
	"tags",
	"traits",
	"metadata",
]
const ANIMAL_MOVEMENT_FIELDS := [
	"idle_action",
	"move_action",
	"duration",
	"move_steps",
	"step_pause_seconds",
	"source_faces_right",
	"direction_persistence",
	"sort_switch_progress",
	"allowed_surfaces",
	"max_step_height",
]
const ANIMAL_ACTION_FIELDS := [
	"file",
	"frame_size",
	"columns",
	"frames",
	"fps",
	"loop",
]
const AMBIENT_FIELDS := [
	"cluster_size",
	"max_visible",
	"max_lights",
	"renderer_script",
	"renderer_alias",
	"renderer_profile",
	"renderer_config",
	"profile",
	"tags",
	"traits",
	"metadata",
]
const COMMUNITY_FIELDS := [
	"id",
	"kind",
	"habitat",
	"distribution",
	"members",
	"community_refs",
	"strategy",
	"placement",
	"stream_key",
	"chance",
	"anchor_spacing",
	"anchor_jitter",
	"jitter",
	"radius",
	"count",
	"render_priority",
	"conflict_weight",
	"species",
	"flora",
	"fauna",
	"ambient",
	"tags",
	"metadata",
]
const COMMUNITY_MEMBER_FIELDS := [
	"species_id",
	"species",
	"category",
	"role",
	"count",
	"weight",
	"chance",
	"required",
	"consumes_population",
	"fill_remaining",
	"placement",
	"overrides",
	"metadata",
]
const BIOME_FIELDS := [
	"id",
	"classification_id",
	"script",
	"priority",
	"enabled",
	"aliases",
	"profile",
	"config",
	"noise_fields",
	"noise_defaults",
	"match",
	"community_refs",
	"attachments",
	"generation",
	"surface",
	"climate",
	"weather",
	"minimap_color",
	"minimap_colors",
	"weather_tags",
	"transition_id",
	"transition_tags",
	"transition_weather_tags",
	"tags",
	"metadata",
]
const BIOME_ATTACHMENT_FIELDS := ["community_id", "weight", "enabled", "overrides"]
const BIOME_MATCH_FIELDS := [
	"water",
	"shore",
	"biome",
	"landform",
	"minimum_level",
	"maximum_level",
]
const LEGACY_ROOT_FIELDS := [
	"version",
	"default_ecosystem",
	"generation",
	"species",
	"pool_selection",
	"ecosystems",
]
const LEGACY_ECOSYSTEM_FIELDS := ["id", "match", "flora", "fauna", "ambient"]
const FLORA_RULE_FIELDS := [
	"layer",
	"pool_id",
	"selection_seed_key",
	"species",
	"chance",
	"placement_seed",
	"max_water_depth",
	"placement",
	"render_priority",
	"noise_above",
	"conflict_weight",
]
const FAUNA_RULE_FIELDS := [
	"pool_id",
	"selection_seed_key",
	"species",
	"chance",
	"placement_seed",
	"only_if_flora_missed",
	"distribution",
]
const AMBIENT_RULE_FIELDS := [
	"pool_id",
	"selection_seed_key",
	"species",
	"chance",
	"placement_seed",
	"requires_ground_flora",
]
const FAUNA_SUBSTITUTION_FIELDS := ["species", "chance", "max_count"]

var _catalog: Dictionary = {}
var _errors: Array[String] = []
var _loaded := false
var _loaded_kinds: Dictionary = {}
var _legacy_original: Dictionary = {}


func _init() -> void:
	_reset()


func load_manifest(manifest_path: String) -> bool:
	_reset()
	var manifest := _read_json_object(manifest_path, "manifest")
	if manifest.is_empty() and not _errors.is_empty():
		return false
	if not _validate_version(manifest, manifest_path):
		return false
	if not _reject_unknown_fields(manifest, MANIFEST_FIELDS, manifest_path, "manifest"):
		return false
	var modules_value: Variant = manifest.get("modules", null)
	if not modules_value is Array or modules_value.is_empty():
		_add_error(manifest_path, "manifest.modules must be a non-empty Array")
		return false

	_catalog["source_paths"]["manifest"] = manifest_path
	var seen_module_paths := {}
	for index in modules_value.size():
		var reference_value: Variant = modules_value[index]
		if not reference_value is Dictionary:
			_add_error(manifest_path, "manifest.modules[%d] must be a Dictionary" % index)
			continue
		var reference: Dictionary = reference_value
		if not _reject_unknown_fields(
			reference,
			MODULE_REFERENCE_FIELDS,
			manifest_path,
			"manifest.modules[%d]" % index
		):
			continue
		var expected_kind := String(reference.get("kind", ""))
		var raw_path := String(reference.get("path", ""))
		if expected_kind not in MODULE_KINDS:
			_add_error(manifest_path, "unknown module kind at modules[%d]: %s" % [index, expected_kind])
			continue
		if raw_path.is_empty():
			_add_error(manifest_path, "manifest.modules[%d].path is empty" % index)
			continue
		var module_path := _resolve_path(raw_path, manifest_path)
		if seen_module_paths.has(module_path):
			_add_error(manifest_path, "module path is declared more than once: %s" % module_path)
			continue
		seen_module_paths[module_path] = true
		_load_module(module_path, expected_kind)

	for required_kind in MODULE_KINDS:
		if not _loaded_kinds.has(required_kind):
			_add_error(manifest_path, "manifest is missing required module kind: %s" % required_kind)
	if not _errors.is_empty():
		return false
	_validate_catalog(manifest_path)
	_loaded = _errors.is_empty()
	return _loaded


## Compatibility entry point for the current monolithic ecosystems.json.
## It adapts every legacy ecosystem to a biome plus a `legacy_bundle` community.
func load_legacy(config_path: String) -> bool:
	_reset()
	var legacy := _read_json_object(config_path, "legacy ecosystem config")
	if legacy.is_empty() and not _errors.is_empty():
		return false
	if not _validate_version(legacy, config_path):
		return false
	if not _reject_unknown_fields(legacy, LEGACY_ROOT_FIELDS, config_path, "legacy root"):
		return false

	var default_biome_id := String(legacy.get("default_ecosystem", ""))
	_catalog["world"] = {
		"default_biome_id": default_biome_id,
		"generation": _deep_copy(legacy.get("generation", {})),
		"pool_selection": _deep_copy(legacy.get("pool_selection", {})),
	}
	_catalog["default_biome_id"] = default_biome_id
	_catalog["source_paths"]["manifest"] = config_path
	_catalog["source_paths"]["world"] = config_path
	_loaded_kinds["world"] = true

	var species_value: Variant = legacy.get("species", null)
	if not species_value is Dictionary:
		_add_error(config_path, "legacy species must be a Dictionary")
	else:
		_merge_species_payload(species_value, config_path)
	_loaded_kinds["species"] = true

	var ecosystems_value: Variant = legacy.get("ecosystems", null)
	if not ecosystems_value is Array:
		_add_error(config_path, "legacy ecosystems must be an Array")
	else:
		for index in ecosystems_value.size():
			var ecosystem_value: Variant = ecosystems_value[index]
			if not ecosystem_value is Dictionary:
				_add_error(config_path, "legacy ecosystems[%d] must be a Dictionary" % index)
				continue
			var ecosystem: Dictionary = ecosystem_value
			if not _reject_unknown_fields(
				ecosystem,
				LEGACY_ECOSYSTEM_FIELDS,
				config_path,
				"legacy ecosystems[%d]" % index
			):
				continue
			var ecosystem_id := String(ecosystem.get("id", ""))
			if ecosystem_id.is_empty():
				_add_error(config_path, "legacy ecosystems[%d].id is empty" % index)
				continue
			var community := {
				"id": ecosystem_id,
				"kind": "legacy_bundle",
				"flora": _deep_copy(ecosystem.get("flora", [])),
				"fauna": _deep_copy(ecosystem.get("fauna", [])),
				"ambient": _deep_copy(ecosystem.get("ambient", [])),
			}
			_merge_community(community, config_path)
			var biome := {
				"id": ecosystem_id,
				"match": _deep_copy(ecosystem.get("match", {})),
				"community_refs": [ecosystem_id],
				"attachments": [],
			}
			_merge_biome(biome, config_path)
	_loaded_kinds["communities"] = true
	_loaded_kinds["biomes"] = true

	if not _errors.is_empty():
		return false
	_validate_catalog(config_path)
	_loaded = _errors.is_empty()
	if _loaded:
		_legacy_original = _deep_copy(legacy)
	return _loaded


func is_loaded() -> bool:
	return _loaded


func get_catalog() -> Dictionary:
	return _deep_copy(_catalog)


func get_errors() -> Array[String]:
	return _errors.duplicate()


func get_error_text() -> String:
	return "\n".join(_errors)


func get_world() -> Dictionary:
	return _deep_copy(_catalog.get("world", {}))


func get_species(category: String, species_id: String) -> Dictionary:
	var categories: Dictionary = _catalog.get("species", {})
	var category_catalog: Dictionary = categories.get(category, {})
	return _deep_copy(category_catalog.get(species_id, {}))


func get_community(community_id: String) -> Dictionary:
	return _deep_copy((_catalog.get("communities", {}) as Dictionary).get(community_id, {}))


func get_biome(biome_id: String) -> Dictionary:
	return _deep_copy((_catalog.get("biomes", {}) as Dictionary).get(biome_id, {}))


## Flattens modular communities back into the current runtime shape. This lets
## main.gd migrate independently from configuration file layout.
func to_legacy_config() -> Dictionary:
	if not _loaded:
		return {}
	if not _legacy_original.is_empty():
		return _deep_copy(_legacy_original)
	var world: Dictionary = _catalog.get("world", {})
	var result := {
		"version": SCHEMA_VERSION,
		"default_ecosystem": String(_catalog.get("default_biome_id", "")),
		"generation": _deep_copy(world.get("generation", {})),
		"species": _deep_copy(_catalog.get("species", {})),
		"pool_selection": _deep_copy(world.get("pool_selection", {})),
		"ecosystems": [],
	}
	var communities: Dictionary = _catalog.get("communities", {})
	var biomes: Dictionary = _catalog.get("biomes", {})
	for biome_id_value in _catalog.get("biome_order", []):
		var biome_id := String(biome_id_value)
		var biome: Dictionary = biomes[biome_id]
		var ecosystem := {
			"id": biome_id,
			"match": _deep_copy(biome.get("match", {})),
			"flora": [],
			"fauna": [],
			"ambient": [],
		}
		for community_id in _community_ids_for_biome(biome):
			var community: Dictionary = communities.get(community_id, {})
			for rule_kind in ["flora", "fauna", "ambient"]:
				for rule in community.get(rule_kind, []):
					ecosystem[rule_kind].append(_deep_copy(rule))
		result["ecosystems"].append(ecosystem)
	return result


func _reset() -> void:
	_errors.clear()
	_loaded = false
	_loaded_kinds.clear()
	_legacy_original.clear()
	_catalog = {
		"version": SCHEMA_VERSION,
		"world": {},
		"species": {"plants": {}, "animals": {}, "ambient": {}},
		"communities": {},
		"community_order": [],
		"biomes": {},
		"biome_order": [],
		"default_biome_id": "",
		"source_paths": {
			"manifest": "",
			"world": "",
			"species": {},
			"communities": {},
			"biomes": {},
		},
	}


func _load_module(module_path: String, expected_kind: String) -> void:
	var module := _read_json_object(module_path, "%s module" % expected_kind)
	if module.is_empty() and not _errors.is_empty():
		return
	if not _validate_version(module, module_path):
		return
	var actual_kind := String(module.get("kind", ""))
	if actual_kind not in MODULE_KINDS:
		_add_error(module_path, "unknown module kind: %s" % actual_kind)
		return
	if actual_kind != expected_kind:
		_add_error(
			module_path,
			"module kind does not match manifest: expected %s, got %s"
			% [expected_kind, actual_kind]
		)
		return
	if not _reject_unknown_fields(
		module,
		MODULE_FIELDS[actual_kind],
		module_path,
		"%s module" % actual_kind
	):
		return

	match actual_kind:
		"world":
			_merge_world(module.get("world", null), module_path)
		"species":
			_merge_species_payload(module.get("species", null), module_path)
		"communities":
			_merge_entities(module.get("communities", null), module_path, "communities")
		"biomes":
			_merge_entities(module.get("biomes", null), module_path, "biomes")
	_loaded_kinds[actual_kind] = true


func _merge_world(world_value: Variant, source_path: String) -> void:
	if _loaded_kinds.has("world") or not (_catalog.get("world", {}) as Dictionary).is_empty():
		_add_error(source_path, "only one world module may be declared")
		return
	if not world_value is Dictionary:
		_add_error(source_path, "world module field `world` must be a Dictionary")
		return
	var world: Dictionary = _deep_copy(world_value)
	if not _reject_unknown_fields(world, WORLD_FIELDS, source_path, "world"):
		return
	var default_biome_id := String(world.get("default_biome_id", ""))
	if default_biome_id.is_empty():
		_add_error(source_path, "world.default_biome_id is empty")
		return
	for dictionary_field in ["generation", "pool_selection", "metadata"]:
		if world.has(dictionary_field) and not world[dictionary_field] is Dictionary:
			_add_error(source_path, "world.%s must be a Dictionary" % dictionary_field)
	_catalog["world"] = world
	_catalog["default_biome_id"] = default_biome_id
	_catalog["source_paths"]["world"] = source_path


func _merge_species_payload(species_value: Variant, source_path: String) -> void:
	if not species_value is Dictionary:
		_add_error(source_path, "species module field `species` must be a Dictionary")
		return
	var species_payload: Dictionary = species_value
	if not _reject_unknown_fields(
		species_payload,
		SPECIES_CATEGORIES,
		source_path,
		"species"
	):
		return
	for category in SPECIES_CATEGORIES:
		var entries_value: Variant = species_payload.get(category, {})
		if not entries_value is Dictionary:
			_add_error(source_path, "species.%s must be a Dictionary" % category)
			continue
		for species_id_value in entries_value:
			var species_id := String(species_id_value)
			var definition_value: Variant = entries_value[species_id_value]
			if species_id.is_empty():
				_add_error(source_path, "species.%s contains an empty ID" % category)
				continue
			if not definition_value is Dictionary:
				_add_error(source_path, "species.%s.%s must be a Dictionary" % [category, species_id])
				continue
			if _find_species_category(species_id) != "":
				_add_error(source_path, "duplicate species ID: %s" % species_id)
				continue
			var definition: Dictionary = _deep_copy(definition_value)
			_validate_and_normalize_species_definition(
				category, species_id, definition, source_path
			)
			_catalog["species"][category][species_id] = definition
			_catalog["source_paths"]["species"][species_id] = source_path


func _merge_entities(value: Variant, source_path: String, entity_namespace: String) -> void:
	var entities := _normalize_entity_collection(value, source_path, entity_namespace)
	for entity_value in entities:
		if entity_namespace == "communities":
			_merge_community(entity_value, source_path)
		else:
			_merge_biome(entity_value, source_path)


func _normalize_entity_collection(
	value: Variant,
	source_path: String,
	entity_namespace: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for index in value.size():
			var entity_value: Variant = value[index]
			if not entity_value is Dictionary:
				_add_error(source_path, "%s[%d] must be a Dictionary" % [entity_namespace, index])
				continue
			result.append(_deep_copy(entity_value))
		return result
	if value is Dictionary:
		for id_value in value:
			var entity_value: Variant = value[id_value]
			if not entity_value is Dictionary:
				_add_error(source_path, "%s.%s must be a Dictionary" % [entity_namespace, id_value])
				continue
			var entity: Dictionary = _deep_copy(entity_value)
			if entity.has("id") and String(entity["id"]) != String(id_value):
				_add_error(
					source_path,
					"%s.%s ID does not match embedded ID %s"
					% [entity_namespace, id_value, entity["id"]]
				)
				continue
			entity["id"] = String(id_value)
			result.append(entity)
		return result
	_add_error(
		source_path,
		"%s module field `%s` must be an Array or Dictionary"
		% [entity_namespace, entity_namespace]
	)
	return result


func _merge_community(community_value: Variant, source_path: String) -> void:
	if not community_value is Dictionary:
		_add_error(source_path, "community must be a Dictionary")
		return
	var community: Dictionary = _deep_copy(community_value)
	if not _reject_unknown_fields(
		community,
		COMMUNITY_FIELDS,
		source_path,
		"community"
	):
		return
	var community_id := String(community.get("id", ""))
	if community_id.is_empty():
		_add_error(source_path, "community.id is empty")
		return
	if (_catalog.get("communities", {}) as Dictionary).has(community_id):
		_add_error(source_path, "duplicate community ID: %s" % community_id)
		return
	var kind := String(community.get("kind", ""))
	if kind.is_empty():
		_add_error(source_path, "community %s has an empty kind" % community_id)
	for dictionary_field in ["habitat", "distribution", "metadata"]:
		if community.has(dictionary_field) and not community[dictionary_field] is Dictionary:
			_add_error(source_path, "community %s.%s must be a Dictionary" % [community_id, dictionary_field])
	for array_field in ["members", "community_refs", "flora", "fauna", "ambient", "tags"]:
		if community.has(array_field) and not community[array_field] is Array:
			_add_error(source_path, "community %s.%s must be an Array" % [community_id, array_field])
	_catalog["communities"][community_id] = community
	_catalog["community_order"].append(community_id)
	_catalog["source_paths"]["communities"][community_id] = source_path


func _merge_biome(biome_value: Variant, source_path: String) -> void:
	if not biome_value is Dictionary:
		_add_error(source_path, "biome must be a Dictionary")
		return
	var biome: Dictionary = _deep_copy(biome_value)
	if not _reject_unknown_fields(biome, BIOME_FIELDS, source_path, "biome"):
		return
	var biome_id := String(biome.get("id", ""))
	if biome_id.is_empty():
		_add_error(source_path, "biome.id is empty")
		return
	if (_catalog.get("biomes", {}) as Dictionary).has(biome_id):
		_add_error(source_path, "duplicate biome ID: %s" % biome_id)
		return
	for dictionary_field in [
		"match",
		"profile",
		"config",
		"noise_fields",
		"noise_defaults",
		"generation",
		"surface",
		"climate",
		"weather",
		"minimap_colors",
		"metadata",
	]:
		if biome.has(dictionary_field) and not biome[dictionary_field] is Dictionary:
			_add_error(source_path, "biome %s.%s must be a Dictionary" % [biome_id, dictionary_field])
	for array_field in [
		"aliases",
		"community_refs",
		"attachments",
		"weather_tags",
		"transition_tags",
		"transition_weather_tags",
		"tags",
	]:
		if biome.has(array_field) and not biome[array_field] is Array:
			_add_error(source_path, "biome %s.%s must be an Array" % [biome_id, array_field])
	if biome.has("match") and biome["match"] is Dictionary:
		_reject_unknown_fields(
			biome["match"],
			BIOME_MATCH_FIELDS,
			source_path,
			"biome %s.match" % biome_id
		)
	if biome.has("script"):
		var script_path := _resolve_path(String(biome.get("script", "")), source_path)
		biome["script"] = script_path
		_validate_resource_path(script_path, source_path, "biome %s.script" % biome_id, false)
	_catalog["biomes"][biome_id] = biome
	_catalog["biome_order"].append(biome_id)
	_catalog["source_paths"]["biomes"][biome_id] = source_path


func _validate_catalog(fallback_source: String) -> void:
	var world: Dictionary = _catalog.get("world", {})
	if world.is_empty():
		_add_error(fallback_source, "catalog has no world definition")
	var default_biome_id := String(_catalog.get("default_biome_id", ""))
	if default_biome_id.is_empty():
		_add_error(_source_for_world(fallback_source), "default_biome_id is empty")
	elif not (_catalog.get("biomes", {}) as Dictionary).has(default_biome_id):
		_add_error(
			_source_for_world(fallback_source),
			"default_biome_id references unknown biome: %s" % default_biome_id
		)

	_validate_species_references(fallback_source)
	var communities: Dictionary = _catalog.get("communities", {})
	for community_id_value in _catalog.get("community_order", []):
		var community_id := String(community_id_value)
		_validate_community(
			communities[community_id],
			_source_for("communities", community_id, fallback_source)
		)
	var biomes: Dictionary = _catalog.get("biomes", {})
	for biome_id_value in _catalog.get("biome_order", []):
		var biome_id := String(biome_id_value)
		_validate_biome(
			biomes[biome_id],
			_source_for("biomes", biome_id, fallback_source)
		)
	_validate_biome_match_references(fallback_source)


func _validate_biome_match_references(fallback_source: String) -> void:
	var biomes: Dictionary = _catalog.get("biomes", {})
	var known_biome_ids := {}
	for biome_id_value in _catalog.get("biome_order", []):
		var biome_id := String(biome_id_value)
		var biome: Dictionary = biomes.get(biome_id, {})
		for candidate in (
			[biome_id, String(biome.get("classification_id", ""))]
			+ (biome.get("aliases", []) as Array)
		):
			var candidate_id := String(candidate)
			if not candidate_id.is_empty():
				known_biome_ids[candidate_id] = true

	var known_landform_ids := {}
	var generation: Dictionary = (_catalog.get("world", {}) as Dictionary).get(
		"generation", {}
	)
	for classification_value in generation.get("biome_index_order", []):
		var classification_id := String(classification_value)
		if not classification_id.is_empty():
			known_biome_ids[classification_id] = true
	var regions_value: Variant = generation.get("regions", {})
	if regions_value is Dictionary:
		for profile_value in (regions_value as Dictionary).get("landforms", []):
			if profile_value is Dictionary:
				var landform_id := String((profile_value as Dictionary).get("id", ""))
				if not landform_id.is_empty():
					known_landform_ids[landform_id] = true

	for biome_id_value in _catalog.get("biome_order", []):
		var biome_id := String(biome_id_value)
		var biome: Dictionary = biomes.get(biome_id, {})
		var match_value: Variant = biome.get("match", {})
		if not match_value is Dictionary:
			continue
		var match_rule: Dictionary = match_value
		if match_rule.has("biome"):
			for matched_id in _value_as_array(match_rule["biome"]):
				if not known_biome_ids.has(String(matched_id)):
					_add_error(
						_source_for("biomes", biome_id, fallback_source),
						"biome %s.match references unknown biome classification: %s"
						% [biome_id, matched_id]
					)
		if match_rule.has("landform") and not known_landform_ids.is_empty():
			for matched_id in _value_as_array(match_rule["landform"]):
				if not known_landform_ids.has(String(matched_id)):
					_add_error(
						_source_for("biomes", biome_id, fallback_source),
						"biome %s.match references unknown landform: %s"
						% [biome_id, matched_id]
					)


func _validate_species_references(fallback_source: String) -> void:
	var plants: Dictionary = _catalog["species"]["plants"]
	for plant_id_value in plants:
		var plant_id := String(plant_id_value)
		var plant: Dictionary = plants[plant_id]
		var habitat: Dictionary = plant.get("habitat", {})
		if habitat.is_empty():
			continue
		var fallback_species := String(habitat.get("fallback_species", ""))
		if fallback_species.is_empty():
			continue
		if not plants.has(fallback_species):
			_add_error(
				_source_for("species", plant_id, fallback_source),
				"plant %s habitat references unknown fallback species: %s"
				% [plant_id, fallback_species]
			)


func _validate_community(community: Dictionary, source_path: String) -> void:
	var community_id := String(community.get("id", ""))
	var members_value: Variant = community.get("members", [])
	if members_value is Array:
		for index in members_value.size():
			var member_value: Variant = members_value[index]
			if not member_value is Dictionary:
				_add_error(source_path, "community %s.members[%d] must be a Dictionary" % [community_id, index])
				continue
			var member: Dictionary = member_value
			if not _reject_unknown_fields(
				member,
				COMMUNITY_MEMBER_FIELDS,
				source_path,
				"community %s.members[%d]" % [community_id, index]
			):
				continue
			var species_id := String(member.get("species_id", ""))
			var category := _canonical_species_category(String(member.get("category", "")))
			_validate_species_reference(species_id, category, source_path, "community %s member" % community_id)

	var nested_refs_value: Variant = community.get("community_refs", [])
	if nested_refs_value is Array:
		for ref_value in nested_refs_value:
			_validate_community_reference(String(ref_value), source_path, "community %s" % community_id)

	_validate_legacy_rules(community, source_path, community_id)


func _validate_legacy_rules(
	community: Dictionary,
	source_path: String,
	community_id: String
) -> void:
	var rule_specs := {
		"flora": {"fields": FLORA_RULE_FIELDS, "category": "plants"},
		"fauna": {"fields": FAUNA_RULE_FIELDS, "category": "animals"},
		"ambient": {"fields": AMBIENT_RULE_FIELDS, "category": "ambient"},
	}
	for rule_kind in rule_specs:
		var rules_value: Variant = community.get(rule_kind, [])
		if not rules_value is Array:
			continue
		for index in rules_value.size():
			var rule_value: Variant = rules_value[index]
			if not rule_value is Dictionary:
				_add_error(source_path, "community %s.%s[%d] must be a Dictionary" % [community_id, rule_kind, index])
				continue
			var rule: Dictionary = rule_value
			if not _reject_unknown_fields(
				rule,
				rule_specs[rule_kind]["fields"],
				source_path,
				"community %s.%s[%d]" % [community_id, rule_kind, index]
			):
				continue
			var species_pool: Variant = rule.get("species", null)
			if not species_pool is Array or species_pool.is_empty():
				_add_error(source_path, "community %s.%s[%d].species must be a non-empty Array" % [community_id, rule_kind, index])
				continue
			for species_id_value in species_pool:
				_validate_species_reference(
					String(species_id_value),
					String(rule_specs[rule_kind]["category"]),
					source_path,
					"community %s.%s[%d]" % [community_id, rule_kind, index]
				)
			if rule_kind == "fauna" and rule.get("distribution", {}) is Dictionary:
				var distribution: Dictionary = rule.get("distribution", {})
				var substitution_value: Variant = distribution.get("substitution", {})
				if substitution_value is Dictionary and not substitution_value.is_empty():
					var substitution: Dictionary = substitution_value
					if _reject_unknown_fields(
						substitution,
						FAUNA_SUBSTITUTION_FIELDS,
						source_path,
						"community %s.%s[%d].distribution.substitution"
						% [community_id, rule_kind, index]
					):
						_validate_species_reference(
							String(substitution.get("species", "")),
							"animals",
							source_path,
							"community %s fauna substitution" % community_id
						)


func _validate_biome(biome: Dictionary, source_path: String) -> void:
	var biome_id := String(biome.get("id", ""))
	var refs_value: Variant = biome.get("community_refs", [])
	if refs_value is Array:
		for ref_value in refs_value:
			_validate_community_reference(String(ref_value), source_path, "biome %s" % biome_id)
	var attachments_value: Variant = biome.get("attachments", [])
	if not attachments_value is Array:
		return
	for index in attachments_value.size():
		var attachment_value: Variant = attachments_value[index]
		if attachment_value is String:
			_validate_community_reference(attachment_value, source_path, "biome %s attachment" % biome_id)
			continue
		if not attachment_value is Dictionary:
			_add_error(source_path, "biome %s.attachments[%d] must be a String or Dictionary" % [biome_id, index])
			continue
		var attachment: Dictionary = attachment_value
		if not _reject_unknown_fields(
			attachment,
			BIOME_ATTACHMENT_FIELDS,
			source_path,
			"biome %s.attachments[%d]" % [biome_id, index]
		):
			continue
		_validate_community_reference(
			String(attachment.get("community_id", "")),
			source_path,
			"biome %s attachment" % biome_id
		)


func _validate_and_normalize_species_definition(
	category: String,
	species_id: String,
	definition: Dictionary,
	source_path: String
) -> void:
	match category:
		"plants":
			if not _reject_unknown_fields(definition, PLANT_FIELDS, source_path, "plant %s" % species_id):
				return
			var texture_path := _resolve_path(String(definition.get("texture", "")), source_path)
			definition["texture"] = texture_path
			_validate_resource_path(texture_path, source_path, "plant %s.texture" % species_id, false)
			if definition.has("habitat"):
				if not definition["habitat"] is Dictionary:
					_add_error(source_path, "plant %s.habitat must be a Dictionary" % species_id)
				else:
					_reject_unknown_fields(
						definition["habitat"],
						PLANT_HABITAT_FIELDS,
						source_path,
						"plant %s.habitat" % species_id
					)
		"animals":
			if not _reject_unknown_fields(definition, ANIMAL_FIELDS, source_path, "animal %s" % species_id):
				return
			var directory := _resolve_path(String(definition.get("directory", "")), source_path)
			definition["directory"] = directory
			_validate_resource_path(directory, source_path, "animal %s.directory" % species_id, true)
			_validate_animal_definition(species_id, definition, source_path)
		"ambient":
			_reject_unknown_fields(definition, AMBIENT_FIELDS, source_path, "ambient species %s" % species_id)


func _validate_animal_definition(
	species_id: String,
	definition: Dictionary,
	source_path: String
) -> void:
	var actions_value: Variant = definition.get("actions", null)
	if not actions_value is Dictionary or actions_value.is_empty():
		_add_error(source_path, "animal %s.actions must be a non-empty Dictionary" % species_id)
		return
	var directory := String(definition.get("directory", ""))
	for action_id_value in actions_value:
		var action_id := String(action_id_value)
		var action_value: Variant = actions_value[action_id_value]
		if not action_value is Dictionary:
			_add_error(source_path, "animal %s action %s must be a Dictionary" % [species_id, action_id])
			continue
		var action: Dictionary = action_value
		if not _reject_unknown_fields(
			action,
			ANIMAL_ACTION_FIELDS,
			source_path,
			"animal %s action %s" % [species_id, action_id]
		):
			continue
		var action_file := String(action.get("file", ""))
		var action_path := directory.path_join(action_file) if not action_file.is_empty() else ""
		_validate_resource_path(
			action_path,
			source_path,
			"animal %s action %s.file" % [species_id, action_id],
			false
		)
	if definition.has("movement"):
		if not definition["movement"] is Dictionary:
			_add_error(source_path, "animal %s.movement must be a Dictionary" % species_id)
			return
		var movement: Dictionary = definition["movement"]
		_reject_unknown_fields(
			movement,
			ANIMAL_MOVEMENT_FIELDS,
			source_path,
			"animal %s.movement" % species_id
		)
		for action_field in ["idle_action", "move_action"]:
			if movement.has(action_field) and not actions_value.has(String(movement[action_field])):
				_add_error(
					source_path,
					"animal %s.movement.%s references unknown action: %s"
					% [species_id, action_field, movement[action_field]]
				)


func _validate_species_reference(
	species_id: String,
	expected_category: String,
	source_path: String,
	context: String
) -> void:
	if species_id.is_empty():
		_add_error(source_path, "%s has an empty species reference" % context)
		return
	var actual_category := _find_species_category(species_id)
	if actual_category.is_empty():
		_add_error(source_path, "%s references unknown species: %s" % [context, species_id])
		return
	if not expected_category.is_empty() and actual_category != expected_category:
		_add_error(
			source_path,
			"%s references species %s from category %s, expected %s"
			% [context, species_id, actual_category, expected_category]
		)


func _validate_community_reference(
	community_id: String,
	source_path: String,
	context: String
) -> void:
	if community_id.is_empty():
		_add_error(source_path, "%s has an empty community reference" % context)
	elif not (_catalog.get("communities", {}) as Dictionary).has(community_id):
		_add_error(source_path, "%s references unknown community: %s" % [context, community_id])


func _community_ids_for_biome(biome: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for ref_value in biome.get("community_refs", []):
		var community_id := String(ref_value)
		if not result.has(community_id):
			result.append(community_id)
	for attachment_value in biome.get("attachments", []):
		var community_id := ""
		if attachment_value is String:
			community_id = attachment_value
		elif attachment_value is Dictionary:
			community_id = String(attachment_value.get("community_id", ""))
		if not community_id.is_empty() and not result.has(community_id):
			result.append(community_id)
	return result


func _find_species_category(species_id: String) -> String:
	var categories: Dictionary = _catalog.get("species", {})
	for category in SPECIES_CATEGORIES:
		if (categories.get(category, {}) as Dictionary).has(species_id):
			return category
	return ""


func _canonical_species_category(raw_category: String) -> String:
	match raw_category:
		"", "any":
			return ""
		"plant", "plants", "flora":
			return "plants"
		"animal", "animals", "fauna":
			return "animals"
		"ambient":
			return "ambient"
		_:
			return raw_category


func _read_json_object(path: String, label: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_add_error(path, "%s does not exist" % label)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_add_error(path, "cannot read %s" % label)
		return {}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		_add_error(
			path,
			"invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		)
		return {}
	if not json.data is Dictionary:
		_add_error(path, "%s root must be a Dictionary" % label)
		return {}
	return json.data


func _validate_version(document: Dictionary, source_path: String) -> bool:
	var version_value: Variant = document.get("version", null)
	if not (version_value is int or version_value is float):
		_add_error(source_path, "version must be the number %d" % SCHEMA_VERSION)
		return false
	if int(version_value) != SCHEMA_VERSION or float(version_value) != float(SCHEMA_VERSION):
		_add_error(
			source_path,
			"unsupported version %s; expected %d" % [version_value, SCHEMA_VERSION]
		)
		return false
	return true


func _reject_unknown_fields(
	value: Dictionary,
	allowed_fields: Array,
	source_path: String,
	context: String
) -> bool:
	var valid := true
	for key_value in value:
		var key := String(key_value)
		if key not in allowed_fields:
			_add_error(source_path, "%s contains unknown field: %s" % [context, key])
			valid = false
	return valid


func _validate_resource_path(
	path: String,
	source_path: String,
	context: String,
	expect_directory: bool
) -> void:
	if path.is_empty():
		_add_error(source_path, "%s has an empty resource path" % context)
		return
	if not (path.begins_with("res://") or path.begins_with("user://")):
		_add_error(source_path, "%s must resolve to res:// or user://: %s" % [context, path])
		return
	var exists := false
	if expect_directory:
		exists = DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))
	else:
		exists = ResourceLoader.exists(path) or FileAccess.file_exists(path)
	if not exists:
		_add_error(source_path, "%s resource does not exist: %s" % [context, path])


func _resolve_path(raw_path: String, declaring_path: String) -> String:
	if raw_path.is_empty():
		return ""
	if (
		raw_path.begins_with("res://")
		or raw_path.begins_with("user://")
		or raw_path.begins_with("/")
	):
		return raw_path.simplify_path()
	return declaring_path.get_base_dir().path_join(raw_path).simplify_path()


func _source_for(entity_namespace: String, entity_id: String, fallback_source: String) -> String:
	var sources: Dictionary = _catalog.get("source_paths", {})
	var namespace_sources: Dictionary = sources.get(entity_namespace, {})
	return String(namespace_sources.get(entity_id, fallback_source))


func _source_for_world(fallback_source: String) -> String:
	return String((_catalog.get("source_paths", {}) as Dictionary).get("world", fallback_source))


func _add_error(source_path: String, message: String) -> void:
	_errors.append("%s: %s" % [source_path, message])


func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


func _value_as_array(value: Variant) -> Array:
	return (value as Array).duplicate(true) if value is Array else [value]
