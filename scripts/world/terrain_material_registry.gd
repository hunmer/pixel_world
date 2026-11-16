class_name TerrainMaterialRegistry
extends RefCounted

## terrain_material_registry.gd — 配置驱动的地形表面/材质目录（装配层）。
##
## 注册表拥有校验、biome override、fallback 解析与贴图缓存；纯解析/规范化逻辑拆至
## terrain_material_parser.gd（经 reporter / texture_loader 回调注入，错误码与顺序不变）。
## 它刻意不包含 biome 名称分支，也不使用 Main 的 preload 或贴图 padding helper。
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

const MaterialParser = preload("res://scripts/world/terrain_material_parser.gd")

const CONTAINER_FIELDS: Array = MaterialParser.CONTAINER_FIELDS
const MATERIAL_FIELDS: Array = MaterialParser.MATERIAL_FIELDS
const OVERRIDE_FIELDS: Array = MaterialParser.OVERRIDE_FIELDS
const TEXTURE_ROLES: Array[StringName] = [&"top", &"column", &"underwater"]

var _materials: Dictionary = {}
var _fallback_surface_id := &""
var _errors: Array[Dictionary] = []
var _reported_error_keys: Dictionary = {}
var _raw_texture_cache: Dictionary = {}
var _processed_texture_cache: Dictionary = {}
var _texture_processor := Callable()
var _parser_reporter := Callable()
var _parser_texture_loader := Callable()


func _init() -> void:
	_parser_reporter = Callable(self, "_report")
	_parser_texture_loader = Callable(self, "_load_texture")


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
	var collected := MaterialParser.collect_material_entries(
		materials_config,
		source_name,
		_parser_reporter
	)
	if not bool(collected["ok"]):
		return false
	for entry: Dictionary in collected["entries"]:
		register_surface(
			entry["definition"],
			entry["declared_id"],
			source_name
		)
	_apply_requested_fallback(collected["fallback"], source_name)
	return _errors.size() == error_count_before


func _apply_requested_fallback(
	requested_fallback: StringName,
	source_name: String
) -> void:
	if requested_fallback.is_empty():
		return
	if not _materials.has(requested_fallback):
		_report(
			&"unknown_fallback_surface",
			requested_fallback,
			"fallback_surface_id",
			source_name,
			"fallback surface is not registered"
		)
		return
	_fallback_surface_id = requested_fallback


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

	var canonical := MaterialParser.canonicalize_definition(
		definition,
		surface_id,
		source_name,
		false,
		_parser_reporter,
		_parser_texture_loader
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
		material = MaterialParser.merge_override(material, overrides[biome_id])
	material.erase("biome_overrides")
	material["surface_id"] = resolved_id
	material["requested_surface_id"] = surface_id
	material["biome_id"] = biome_id
	material["used_fallback"] = used_fallback
	material["column_texture_path"] = MaterialParser.resolve_texture_spec(
		material.get("column_texture_spec", {"mode": "top"}),
		String(material.get("top_texture_path", "")),
		""
	)
	material["underwater_texture_path"] = MaterialParser.resolve_texture_spec(
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


func _reject_unknown_fields(
	value: Dictionary,
	allowed_fields: Array,
	surface_id: StringName,
	source_name: String
) -> bool:
	return MaterialParser.reject_unknown_fields(
		value, allowed_fields, surface_id, source_name, _parser_reporter
	)


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
