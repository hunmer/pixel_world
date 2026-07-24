class_name TerrainMaterialRegistry
extends RefCounted

## Configuration-driven terrain surface/material catalog.
##
## The registry owns validation, biome overrides, fallback resolution, and
## texture caching. It deliberately has no biome name branches and does not use
## Main's preload or texture-padding helpers.
##
## Supported material shape:
##
##     {
##         "surface_id": "basalt",
##         "top_texture": "res://...png",
##         "column_texture": "reuse_top", # or a resource path
##         "underwater_texture": "reuse_top", # optional
##         "minimap_color": [0.15, 0.12, 0.12, 1.0],
##         "tags": ["rocky"],
##         "traits": {"movement_cost": 1.2},
##         "biome_overrides": {
##             "volcanic": {"tags": ["hot"], "traits": {"heat": 1.0}}
##         }
##     }
##
## `load_from_generation()` reads `generation.materials`; `load_materials()`
## also accepts a standalone material container, keyed definitions, an array of
## definitions, or one definition containing `surface_id`.

const CONTAINER_FIELDS := [
	"fallback_surface_id",
	"surfaces",
	"definitions",
]
const MATERIAL_FIELDS := [
	"surface_id",
	"top_texture",
	"top_texture_path",
	"column_texture",
	"column_texture_path",
	"underwater_texture",
	"underwater_texture_path",
	"minimap_color",
	"tags",
	"traits",
	"biome_overrides",
	"biome_override",
]
const OVERRIDE_FIELDS := [
	"top_texture",
	"top_texture_path",
	"column_texture",
	"column_texture_path",
	"underwater_texture",
	"underwater_texture_path",
	"minimap_color",
	"tags",
	"traits",
]
const TEXTURE_ROLES: Array[StringName] = [&"top", &"column", &"underwater"]

var _materials: Dictionary = {}
var _fallback_surface_id := &""
var _errors: Array[Dictionary] = []
var _reported_error_keys: Dictionary = {}
var _raw_texture_cache: Dictionary = {}
var _processed_texture_cache: Dictionary = {}
var _texture_processor := Callable()


## Loads the `materials` section without validating unrelated generation keys.
func load_from_generation(
	generation: Dictionary,
	source_name := "generation.materials"
) -> bool:
	if not generation.has("materials"):
		_report(
			&"missing_materials_config",
			&"",
			"materials",
			source_name,
			"generation.materials is missing"
		)
		return false
	return load_materials(generation["materials"], source_name)


## Loads optional material contributions owned by biome modules. A biome may
## declare them at `generation.materials`, keeping a future volcanic/ice module
## self-contained instead of editing a central renderer switch.
func load_biome_catalog(
	biomes: Dictionary,
	biome_order: Array = [],
	source_name := "biomes"
) -> bool:
	var ordered_ids: Array = biome_order.duplicate()
	if ordered_ids.is_empty():
		ordered_ids.assign(biomes.keys())
		ordered_ids.sort_custom(func(a: Variant, b: Variant) -> bool:
			return String(a) < String(b)
		)
	var success := true
	for biome_id_value in ordered_ids:
		var biome_id := String(biome_id_value)
		var definition_value: Variant = biomes.get(biome_id, null)
		if not definition_value is Dictionary:
			_report(
				&"invalid_biome_material_source",
				&"",
				biome_id,
				source_name,
				"biome definition must be a Dictionary"
			)
			success = false
			continue
		var generation_value: Variant = definition_value.get("generation", {})
		if not generation_value is Dictionary:
			_report(
				&"invalid_biome_material_source",
				&"",
				"%s.generation" % biome_id,
				source_name,
				"biome generation must be a Dictionary"
			)
			success = false
			continue
		var generation: Dictionary = generation_value
		if not generation.has("materials"):
			continue
		success = load_materials(
			generation["materials"],
			"%s.%s.generation.materials" % [source_name, biome_id]
		) and success
	return success


func load_materials(
	materials_config: Variant,
	source_name := "materials"
) -> bool:
	var error_count_before := _errors.size()
	var entries: Array[Dictionary] = []
	var requested_fallback := &""
	if materials_config is Array:
		for index in (materials_config as Array).size():
			var value: Variant = materials_config[index]
			if not value is Dictionary:
				_report(
					&"invalid_material_definition",
					&"",
					"[%d]" % index,
					source_name,
					"material entry must be a Dictionary"
				)
				continue
			entries.append({"declared_id": &"", "definition": value})
	elif materials_config is Dictionary:
		var config: Dictionary = materials_config
		if config.has("surface_id"):
			entries.append({"declared_id": &"", "definition": config})
		else:
			var definitions_value: Variant
			var is_container := config.has("surfaces") or config.has("definitions")
			if is_container:
				if not _reject_unknown_fields(
					config,
					CONTAINER_FIELDS,
					&"",
					source_name
				):
					return false
				if config.has("surfaces") and config.has("definitions"):
					_report(
						&"ambiguous_material_container",
						&"",
						"surfaces",
						source_name,
						"use either surfaces or definitions, not both"
					)
					return false
				definitions_value = config.get("surfaces", config.get("definitions", {}))
				var fallback_value: Variant = config.get("fallback_surface_id", "")
				if not _fallback_value_is_valid(fallback_value, source_name):
					return false
				requested_fallback = StringName(fallback_value)
			else:
				var direct_definitions := config.duplicate(true)
				var fallback_value: Variant = direct_definitions.get("fallback_surface_id", "")
				if not _fallback_value_is_valid(fallback_value, source_name):
					return false
				requested_fallback = StringName(fallback_value)
				direct_definitions.erase("fallback_surface_id")
				definitions_value = direct_definitions
			if not _collect_entries(definitions_value, entries, source_name):
				return false
	else:
		_report(
			&"invalid_materials_config",
			&"",
			"materials",
			source_name,
			"materials must be a Dictionary or Array"
		)
		return false

	for entry: Dictionary in entries:
		register_surface(
			entry["definition"],
			entry["declared_id"],
			source_name
		)
	if not requested_fallback.is_empty():
		if not _materials.has(requested_fallback):
			_report(
				&"unknown_fallback_surface",
				requested_fallback,
				"fallback_surface_id",
				source_name,
				"fallback surface is not registered"
			)
		else:
			_fallback_surface_id = requested_fallback
	return _errors.size() == error_count_before


func register_surface(
	definition: Dictionary,
	declared_id: StringName = &"",
	source_name := "runtime"
) -> bool:
	if definition.has("surface_id") and (
		not definition["surface_id"] is String
		and not definition["surface_id"] is StringName
	):
		_report(
			&"invalid_surface_id",
			declared_id,
			"surface_id",
			source_name,
			"surface_id must be a non-empty String"
		)
		return false
	var surface_id := StringName(definition.get("surface_id", declared_id))
	if surface_id.is_empty():
		_report(
			&"missing_surface_id",
			&"",
			"surface_id",
			source_name,
			"surface_id is required"
		)
		return false
	if not declared_id.is_empty() and definition.has("surface_id"):
		if StringName(definition["surface_id"]) != declared_id:
			_report(
				&"surface_id_mismatch",
				surface_id,
				"surface_id",
				source_name,
				"dictionary key and surface_id disagree"
			)
			return false
	if _materials.has(surface_id):
		_report(
			&"duplicate_surface_id",
			surface_id,
			"surface_id",
			source_name,
			"surface_id is already registered"
		)
		return false
	if not _reject_unknown_fields(
		definition,
		MATERIAL_FIELDS,
		surface_id,
		source_name
	):
		return false

	var canonical := _canonicalize_definition(
		definition,
		surface_id,
		source_name,
		false
	)
	if canonical.is_empty():
		return false
	canonical["surface_id"] = surface_id
	_materials[surface_id] = canonical
	return true


func set_fallback_surface(surface_id: StringName, source_name := "runtime") -> bool:
	if not _materials.has(surface_id):
		_report(
			&"unknown_fallback_surface",
			surface_id,
			"fallback_surface_id",
			source_name,
			"fallback surface is not registered"
		)
		return false
	_fallback_surface_id = surface_id
	return true


func fallback_surface_id() -> StringName:
	return _fallback_surface_id


func has_surface(surface_id: StringName) -> bool:
	return _materials.has(surface_id)


func registered_surface_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_materials.keys())
	result.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return result


## Resolves a base surface plus an optional biome-specific partial override.
## Unknown surfaces emit a deduplicated `unknown_surface` error. If a fallback
## exists, it is returned with `used_fallback=true`; otherwise the result is empty.
func resolve(
	surface_id: StringName,
	biome_id: StringName = &"",
	allow_fallback := true
) -> Dictionary:
	var resolved_id := surface_id
	var used_fallback := false
	if not _materials.has(resolved_id):
		_report_once(
			&"unknown_surface",
			surface_id,
			"surface_id",
			"resolve",
			"surface is not registered: %s" % surface_id,
			"unknown_surface:%s" % surface_id
		)
		if not allow_fallback or _fallback_surface_id.is_empty():
			return {}
		resolved_id = _fallback_surface_id
		used_fallback = true

	var base: Dictionary = _materials[resolved_id]
	var material := base.duplicate(true)
	var overrides: Dictionary = base.get("biome_overrides", {})
	if not biome_id.is_empty() and overrides.has(biome_id):
		material = _merge_override(material, overrides[biome_id])
	material.erase("biome_overrides")
	material["surface_id"] = resolved_id
	material["requested_surface_id"] = surface_id
	material["biome_id"] = biome_id
	material["used_fallback"] = used_fallback
	material["column_texture_path"] = _resolve_texture_spec(
		material.get("column_texture_spec", {"mode": "top"}),
		String(material.get("top_texture_path", "")),
		""
	)
	material["underwater_texture_path"] = _resolve_texture_spec(
		material.get("underwater_texture_spec", {"mode": "none"}),
		String(material.get("top_texture_path", "")),
		String(material.get("column_texture_path", ""))
	)
	material.erase("column_texture_spec")
	material.erase("underwater_texture_spec")
	return material


func get_minimap_color(
	surface_id: StringName,
	biome_id: StringName = &"",
	allow_fallback := true
) -> Color:
	var material := resolve(surface_id, biome_id, allow_fallback)
	return material.get("minimap_color", Color.MAGENTA)


## Loads one resolved role and caches both the raw Texture2D and the optional
## processed result. A renderer can inject a path-stable processor (for example,
## padding every source to 32x32) without depending on Main.
func get_texture(
	surface_id: StringName,
	role: StringName = &"top",
	biome_id: StringName = &"",
	allow_fallback := true
) -> Texture2D:
	if role not in TEXTURE_ROLES:
		_report_once(
			&"unknown_texture_role",
			surface_id,
			String(role),
			"get_texture",
			"unknown texture role: %s" % role,
			"unknown_texture_role:%s:%s" % [surface_id, role]
		)
		return null
	var material := resolve(surface_id, biome_id, allow_fallback)
	if material.is_empty():
		return null
	var path_field := "%s_texture_path" % role
	var texture_path := String(material.get(path_field, ""))
	if texture_path.is_empty():
		return null
	var raw_texture := _load_texture(texture_path, surface_id, path_field, "get_texture")
	if raw_texture == null or not _texture_processor.is_valid():
		return raw_texture
	if _processed_texture_cache.has(texture_path):
		return _processed_texture_cache[texture_path]
	var processed_value: Variant = _texture_processor.call(raw_texture, texture_path)
	if not processed_value is Texture2D:
		_report_once(
			&"invalid_texture_processor_result",
			surface_id,
			path_field,
			"get_texture",
			"texture processor must return Texture2D",
			"invalid_texture_processor_result:%s" % texture_path
		)
		return null
	_processed_texture_cache[texture_path] = processed_value
	return processed_value


func set_texture_processor(processor: Callable) -> void:
	_texture_processor = processor
	_processed_texture_cache.clear()


func clear_texture_processor() -> void:
	_texture_processor = Callable()
	_processed_texture_cache.clear()


func clear_texture_cache() -> void:
	_raw_texture_cache.clear()
	_processed_texture_cache.clear()


func raw_texture_cache_size() -> int:
	return _raw_texture_cache.size()


func processed_texture_cache_size() -> int:
	return _processed_texture_cache.size()


func get_errors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for error: Dictionary in _errors:
		result.append(error.duplicate(true))
	return result


func clear_errors() -> void:
	_errors.clear()
	_reported_error_keys.clear()


func is_valid() -> bool:
	return _errors.is_empty()


func _collect_entries(
	definitions_value: Variant,
	entries: Array[Dictionary],
	source_name: String
) -> bool:
	if definitions_value is Dictionary:
		for surface_id_value in definitions_value:
			if (
				not surface_id_value is String
				and not surface_id_value is StringName
			):
				_report(
					&"invalid_surface_id",
					&"",
					String(surface_id_value),
					source_name,
					"surface dictionary keys must be non-empty strings"
				)
				continue
			var definition_value: Variant = definitions_value[surface_id_value]
			if not definition_value is Dictionary:
				_report(
					&"invalid_material_definition",
					StringName(surface_id_value),
					String(surface_id_value),
					source_name,
					"material definition must be a Dictionary"
				)
				continue
			entries.append({
				"declared_id": StringName(surface_id_value),
				"definition": definition_value,
			})
		return true
	if definitions_value is Array:
		for index in (definitions_value as Array).size():
			var definition_value: Variant = definitions_value[index]
			if not definition_value is Dictionary:
				_report(
					&"invalid_material_definition",
					&"",
					"[%d]" % index,
					source_name,
					"material definition must be a Dictionary"
				)
				continue
			entries.append({"declared_id": &"", "definition": definition_value})
		return true
	_report(
		&"invalid_material_definitions",
		&"",
		"surfaces",
		source_name,
		"surface definitions must be a Dictionary or Array"
	)
	return false


func _canonicalize_definition(
	definition: Dictionary,
	surface_id: StringName,
	source_name: String,
	is_override: bool
) -> Dictionary:
	var allowed_fields := OVERRIDE_FIELDS if is_override else MATERIAL_FIELDS
	if not _reject_unknown_fields(
		definition,
		allowed_fields,
		surface_id,
		source_name
	):
		return {}
	var canonical := {}

	var top_result := _texture_field(
		definition,
		"top_texture",
		"top_texture_path",
		surface_id,
		source_name,
		is_override,
		["path"]
	)
	if not bool(top_result["valid"]):
		return {}
	if bool(top_result["present"]):
		canonical["top_texture_path"] = top_result["path"]
	elif not is_override:
		_report(
			&"missing_top_texture",
			surface_id,
			"top_texture",
			source_name,
			"top_texture is required"
		)
		return {}

	var column_result := _texture_field(
		definition,
		"column_texture",
		"column_texture_path",
		surface_id,
		source_name,
		true,
		["path", "top"]
	)
	if not bool(column_result["valid"]):
		return {}
	if bool(column_result["present"]):
		canonical["column_texture_spec"] = column_result["spec"]
	elif not is_override:
		canonical["column_texture_spec"] = {"mode": "top"}

	var underwater_result := _texture_field(
		definition,
		"underwater_texture",
		"underwater_texture_path",
		surface_id,
		source_name,
		true,
		["path", "top", "column", "none"]
	)
	if not bool(underwater_result["valid"]):
		return {}
	if bool(underwater_result["present"]):
		canonical["underwater_texture_spec"] = underwater_result["spec"]
	elif not is_override:
		canonical["underwater_texture_spec"] = {"mode": "none"}

	if definition.has("minimap_color"):
		var color_value: Variant = _parse_color(
			definition["minimap_color"],
			surface_id,
			source_name
		)
		if color_value == null:
			return {}
		canonical["minimap_color"] = color_value
	elif not is_override:
		_report(
			&"missing_minimap_color",
			surface_id,
			"minimap_color",
			source_name,
			"minimap_color is required"
		)
		return {}

	if definition.has("tags"):
		var tags_value: Variant = _parse_tags(
			definition["tags"],
			surface_id,
			source_name
		)
		if tags_value == null:
			return {}
		canonical["tags"] = tags_value
	elif not is_override:
		canonical["tags"] = []

	if definition.has("traits"):
		if not definition["traits"] is Dictionary:
			_report(
				&"invalid_material_traits",
				surface_id,
				"traits",
				source_name,
				"traits must be a Dictionary"
			)
			return {}
		canonical["traits"] = (definition["traits"] as Dictionary).duplicate(true)
	elif not is_override:
		canonical["traits"] = {}

	if not is_override:
		if definition.has("biome_overrides") and definition.has("biome_override"):
			_report(
				&"ambiguous_biome_overrides",
				surface_id,
				"biome_overrides",
				source_name,
				"use biome_overrides or biome_override, not both"
			)
			return {}
		var overrides_value: Variant = definition.get(
			"biome_overrides",
			definition.get("biome_override", {})
		)
		if not overrides_value is Dictionary:
			_report(
				&"invalid_biome_overrides",
				surface_id,
				"biome_overrides",
				source_name,
				"biome overrides must be a Dictionary"
			)
			return {}
		var overrides := {}
		for biome_id_value in overrides_value:
			if (
				not biome_id_value is String
				and not biome_id_value is StringName
			):
				_report(
					&"invalid_biome_override",
					surface_id,
					"biome_overrides",
					source_name,
					"biome override ids must be non-empty strings"
				)
				return {}
			var biome_id := StringName(biome_id_value)
			var override_value: Variant = overrides_value[biome_id_value]
			if biome_id.is_empty() or not override_value is Dictionary:
				_report(
					&"invalid_biome_override",
					surface_id,
					"biome_overrides.%s" % biome_id,
					source_name,
					"biome override requires a non-empty id and Dictionary"
				)
				return {}
			var canonical_override := _canonicalize_definition(
				override_value,
				surface_id,
				"%s[%s]" % [source_name, biome_id],
				true
			)
			if canonical_override.is_empty() and not override_value.is_empty():
				return {}
			overrides[biome_id] = canonical_override
		canonical["biome_overrides"] = overrides
	return canonical


func _texture_field(
	definition: Dictionary,
	field_name: String,
	path_alias: String,
	surface_id: StringName,
	source_name: String,
	_optional: bool,
	allowed_modes: Array[String]
) -> Dictionary:
	if definition.has(field_name) and definition.has(path_alias):
		_report(
			&"ambiguous_texture_field",
			surface_id,
			field_name,
			source_name,
			"use %s or %s, not both" % [field_name, path_alias]
		)
		return {"valid": false, "present": true}
	if not definition.has(field_name) and not definition.has(path_alias):
		return {"valid": true, "present": false}
	var value: Variant = definition.get(field_name, definition.get(path_alias))
	var spec := _parse_texture_spec(
		value,
		allowed_modes,
		surface_id,
		field_name,
		source_name
	)
	if spec.is_empty():
		return {"valid": false, "present": true}
	return {
		"valid": true,
		"present": true,
		"path": spec.get("path", ""),
		"spec": spec,
	}


func _parse_texture_spec(
	value: Variant,
	allowed_modes: Array[String],
	surface_id: StringName,
	field_name: String,
	source_name: String
) -> Dictionary:
	var mode := ""
	var texture_path := ""
	if value is String or value is StringName:
		var text := String(value).strip_edges()
		match text:
			"reuse_top", "top", "@top":
				mode = "top"
			"reuse_column", "column", "@column":
				mode = "column"
			"none", "":
				mode = "none"
			_:
				mode = "path"
				texture_path = text
	elif value is Dictionary:
		var dictionary: Dictionary = value
		var dictionary_fields_valid := true
		for key_value in dictionary:
			if String(key_value) not in ["path", "reuse"]:
				dictionary_fields_valid = false
				break
		if not dictionary_fields_valid:
			mode = "invalid"
		elif dictionary.has("path") and dictionary.has("reuse"):
			mode = "invalid"
		elif dictionary.has("path"):
			if dictionary["path"] is String or dictionary["path"] is StringName:
				mode = "path"
				texture_path = String(dictionary["path"])
			else:
				mode = "invalid"
		elif dictionary.has("reuse"):
			if dictionary["reuse"] is String or dictionary["reuse"] is StringName:
				match String(dictionary["reuse"]):
					"reuse_top", "top", "@top":
						mode = "top"
					"reuse_column", "column", "@column":
						mode = "column"
					"none":
						mode = "none"
					_:
						mode = "invalid"
			else:
				mode = "invalid"
		else:
			mode = "invalid"
	else:
		mode = "invalid"
	if mode not in allowed_modes:
		_report(
			&"invalid_texture_spec",
			surface_id,
			field_name,
			source_name,
			"texture must be a path or one of: %s" % ", ".join(allowed_modes)
		)
		return {}
	if mode == "path":
		if texture_path.is_empty():
			_report(
				&"invalid_texture_path",
				surface_id,
				field_name,
				source_name,
				"texture path cannot be empty"
			)
			return {}
		if _load_texture(texture_path, surface_id, field_name, source_name) == null:
			return {}
		return {"mode": "path", "path": texture_path}
	return {"mode": mode}


func _parse_color(
	value: Variant,
	surface_id: StringName,
	source_name: String
) -> Variant:
	var color: Color
	if value is Color:
		color = value
	elif value is String and Color.html_is_valid(value):
		color = Color.from_string(value, Color.MAGENTA)
	elif value is Array and value.size() in [3, 4]:
		for component in value:
			if not component is float and not component is int:
				_report(
					&"invalid_minimap_color",
					surface_id,
					"minimap_color",
					source_name,
					"color components must be numeric"
				)
				return null
		color = Color(
			float(value[0]),
			float(value[1]),
			float(value[2]),
			float(value[3]) if value.size() == 4 else 1.0
		)
	else:
		_report(
			&"invalid_minimap_color",
			surface_id,
			"minimap_color",
			source_name,
			"minimap_color must be Color, HTML string, or RGB/RGBA array"
		)
		return null
	if (
		color.r < 0.0 or color.r > 1.0
		or color.g < 0.0 or color.g > 1.0
		or color.b < 0.0 or color.b > 1.0
		or color.a < 0.0 or color.a > 1.0
	):
		_report(
			&"invalid_minimap_color",
			surface_id,
			"minimap_color",
			source_name,
			"minimap_color components must be in 0..1"
		)
		return null
	return color


func _parse_tags(
	value: Variant,
	surface_id: StringName,
	source_name: String
) -> Variant:
	if not value is Array and not value is PackedStringArray:
		_report(
			&"invalid_material_tags",
			surface_id,
			"tags",
			source_name,
			"tags must be an Array of non-empty strings"
		)
		return null
	var tags: Array[StringName] = []
	for item in value:
		if not item is String and not item is StringName:
			_report(
				&"invalid_material_tags",
				surface_id,
				"tags",
				source_name,
				"tags must contain only strings"
			)
			return null
		var tag := StringName(item)
		if tag.is_empty():
			_report(
				&"invalid_material_tags",
				surface_id,
				"tags",
				source_name,
				"tags cannot contain empty values"
			)
			return null
		if tag not in tags:
			tags.append(tag)
	return tags


func _merge_override(base: Dictionary, override: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for field in [
		"top_texture_path",
		"column_texture_spec",
		"underwater_texture_spec",
		"minimap_color",
	]:
		if override.has(field):
			result[field] = override[field]
	if override.has("traits"):
		var merged_traits: Dictionary = result.get("traits", {}).duplicate(true)
		merged_traits.merge(override["traits"], true)
		result["traits"] = merged_traits
	if override.has("tags"):
		var merged_tags: Array = result.get("tags", []).duplicate()
		for tag in override["tags"]:
			if tag not in merged_tags:
				merged_tags.append(tag)
		result["tags"] = merged_tags
	return result


func _resolve_texture_spec(
	spec_value: Variant,
	top_path: String,
	column_path: String
) -> String:
	if not spec_value is Dictionary:
		return ""
	var spec: Dictionary = spec_value
	match String(spec.get("mode", "none")):
		"path":
			return String(spec.get("path", ""))
		"top":
			return top_path
		"column":
			return column_path
	return ""


func _load_texture(
	texture_path: String,
	surface_id: StringName,
	field_name: String,
	source_name: String
) -> Texture2D:
	if _raw_texture_cache.has(texture_path):
		return _raw_texture_cache[texture_path]
	if not ResourceLoader.exists(texture_path):
		_report_once(
			&"missing_texture_resource",
			surface_id,
			field_name,
			source_name,
			"texture resource does not exist: %s" % texture_path,
			"missing_texture_resource:%s" % texture_path
		)
		return null
	var resource := load(texture_path)
	if not resource is Texture2D:
		_report_once(
			&"invalid_texture_resource",
			surface_id,
			field_name,
			source_name,
			"resource is not Texture2D: %s" % texture_path,
			"invalid_texture_resource:%s" % texture_path
		)
		return null
	_raw_texture_cache[texture_path] = resource
	return resource


func _reject_unknown_fields(
	value: Dictionary,
	allowed_fields: Array,
	surface_id: StringName,
	source_name: String
) -> bool:
	var success := true
	for field_value in value:
		var field := String(field_value)
		if field not in allowed_fields:
			_report(
				&"unknown_material_field",
				surface_id,
				field,
				source_name,
				"unknown material field: %s" % field
			)
			success = false
	return success


func _fallback_value_is_valid(value: Variant, source_name: String) -> bool:
	if value is String or value is StringName:
		return true
	_report(
		&"invalid_fallback_surface",
		&"",
		"fallback_surface_id",
		source_name,
		"fallback_surface_id must be a String"
	)
	return false


func _report(
	code: StringName,
	surface_id: StringName,
	field: String,
	source_name: String,
	message: String
) -> void:
	_errors.append({
		"code": code,
		"surface_id": surface_id,
		"field": field,
		"source": source_name,
		"message": message,
	})


func _report_once(
	code: StringName,
	surface_id: StringName,
	field: String,
	source_name: String,
	message: String,
	deduplication_key: String
) -> void:
	if _reported_error_keys.has(deduplication_key):
		return
	_reported_error_keys[deduplication_key] = true
	_report(code, surface_id, field, source_name, message)
