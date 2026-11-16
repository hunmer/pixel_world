extends RefCounted

## terrain_material_parser.gd — 地形材质定义的纯解析/规范化逻辑（从 terrain_material_registry.gd 拆出）。
##
## 无状态、无节点依赖：materials 容器拆分、条目收集、定义规范化、贴图 spec/颜色/tags
## 解析、biome override 合并等全部集中在此。错误经 reporter 回调上报（参数与
## TerrainMaterialRegistry._report 一致：code/surface_id/field/source/message），
## 贴图存在性经 texture_loader 回调校验（参数同 _load_texture：path/surface_id/field/source，
## 返回 Texture2D 或 null），保证注册表对外 API、错误码、错误顺序与解析结果逐字节等价。

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


## 将 materials 配置解析为待注册条目。返回
## {"ok": bool, "entries": Array[Dictionary], "fallback": StringName}；
## "ok" 为 false 时错误已全部上报（fallback 仅为诊断信息）。
static func collect_material_entries(
	materials_config: Variant,
	source_name: String,
	reporter: Callable
) -> Dictionary:
	var entries: Array[Dictionary] = []
	if materials_config is Array:
		_collect_array_entries(materials_config, entries, source_name, reporter)
		return {"ok": true, "entries": entries, "fallback": &""}
	if materials_config is Dictionary:
		return _collect_dictionary_entries(
			materials_config, entries, source_name, reporter
		)
	reporter.call(
		&"invalid_materials_config",
		&"",
		"materials",
		source_name,
		"materials must be a Dictionary or Array"
	)
	return {"ok": false, "entries": entries, "fallback": &""}


static func collect_entries(
	definitions_value: Variant,
	entries: Array[Dictionary],
	source_name: String,
	reporter: Callable
) -> bool:
	if definitions_value is Dictionary:
		return _collect_keyed_entries(definitions_value, entries, source_name, reporter)
	if definitions_value is Array:
		_collect_array_entries(definitions_value, entries, source_name, reporter)
		return true
	reporter.call(
		&"invalid_material_definitions",
		&"",
		"surfaces",
		source_name,
		"surface definitions must be a Dictionary or Array"
	)
	return false


## 规范化单个材质定义。失败返回 {}（错误已上报）；is_override=true 时缺省字段不补默认值。
static func canonicalize_definition(
	definition: Dictionary,
	surface_id: StringName,
	source_name: String,
	is_override: bool,
	reporter: Callable,
	texture_loader: Callable
) -> Dictionary:
	var allowed_fields := OVERRIDE_FIELDS if is_override else MATERIAL_FIELDS
	if not reject_unknown_fields(definition, allowed_fields, surface_id, source_name, reporter):
		return {}
	var canonical := {}
	if not _canonical_texture_fields(
		definition, canonical, surface_id, source_name, is_override, reporter, texture_loader
	):
		return {}
	if not _canonical_scalar_fields(
		definition, canonical, surface_id, source_name, is_override, reporter
	):
		return {}
	if not is_override:
		var overrides: Variant = _canonical_biome_overrides(
			definition, surface_id, source_name, reporter, texture_loader
		)
		if overrides == null:
			return {}
		canonical["biome_overrides"] = overrides
	return canonical


## 解析一个贴图字段（object 形式或 *_path 别名）。
## 返回 {"valid": bool, "present": bool, "path": String, "spec": Dictionary}。
static func texture_field(
	definition: Dictionary,
	field_name: String,
	path_alias: String,
	surface_id: StringName,
	source_name: String,
	allowed_modes: Array[String],
	reporter: Callable,
	texture_loader: Callable
) -> Dictionary:
	if definition.has(field_name) and definition.has(path_alias):
		reporter.call(
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
	var spec := parse_texture_spec(
		value, allowed_modes, surface_id, field_name, source_name, reporter, texture_loader
	)
	if spec.is_empty():
		return {"valid": false, "present": true}
	return {
		"valid": true,
		"present": true,
		"path": spec.get("path", ""),
		"spec": spec,
	}


## 贴图 spec：字符串（reuse_top/top/@top/reuse_column/column/@column/none/路径）或
## {"path": ...} / {"reuse": ...}。失败返回 {}（错误已上报）。
static func parse_texture_spec(
	value: Variant,
	allowed_modes: Array[String],
	surface_id: StringName,
	field_name: String,
	source_name: String,
	reporter: Callable,
	texture_loader: Callable
) -> Dictionary:
	var parts := _texture_spec_parts(value)
	var mode: String = parts["mode"]
	var texture_path: String = parts["path"]
	if mode not in allowed_modes:
		reporter.call(
			&"invalid_texture_spec",
			surface_id,
			field_name,
			source_name,
			"texture must be a path or one of: %s" % ", ".join(allowed_modes)
		)
		return {}
	if mode != "path":
		return {"mode": mode}
	if texture_path.is_empty():
		reporter.call(
			&"invalid_texture_path",
			surface_id,
			field_name,
			source_name,
			"texture path cannot be empty"
		)
		return {}
	if texture_loader.call(texture_path, surface_id, field_name, source_name) == null:
		return {}
	return {"mode": "path", "path": texture_path}


## minimap_color：Color / 合法 HTML 字符串 / 3-4 元数值数组。失败返回 null（错误已上报）。
static func parse_color(
	value: Variant,
	surface_id: StringName,
	source_name: String,
	reporter: Callable
) -> Variant:
	var color: Variant = _color_from_value(value, surface_id, source_name, reporter)
	if color == null:
		return null
	var parsed_color: Color = color
	if _color_out_of_range(parsed_color):
		reporter.call(
			&"invalid_minimap_color",
			surface_id,
			"minimap_color",
			source_name,
			"minimap_color components must be in 0..1"
		)
		return null
	return parsed_color


## tags：非空字符串数组（自动去重）。失败返回 null（错误已上报）。
static func parse_tags(
	value: Variant,
	surface_id: StringName,
	source_name: String,
	reporter: Callable
) -> Variant:
	if not value is Array and not value is PackedStringArray:
		reporter.call(
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
			reporter.call(
				&"invalid_material_tags",
				surface_id,
				"tags",
				source_name,
				"tags must contain only strings"
			)
			return null
		var tag := StringName(item)
		if tag.is_empty():
			reporter.call(
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


## biome override 浅合并：4 个展示字段覆盖 + traits 深合并 + tags 去重追加。
static func merge_override(base: Dictionary, override: Dictionary) -> Dictionary:
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


## 规范化后的 spec → 实际贴图路径（top/column 引用解析；非法 spec 返回 ""）。
static func resolve_texture_spec(
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


static func reject_unknown_fields(
	value: Dictionary,
	allowed_fields: Array,
	surface_id: StringName,
	source_name: String,
	reporter: Callable
) -> bool:
	var success := true
	for field_value in value:
		var field := String(field_value)
		if field not in allowed_fields:
			reporter.call(
				&"unknown_material_field",
				surface_id,
				field,
				source_name,
				"unknown material field: %s" % field
			)
			success = false
	return success


static func fallback_value_is_valid(
	value: Variant,
	source_name: String,
	reporter: Callable
) -> bool:
	if value is String or value is StringName:
		return true
	reporter.call(
		&"invalid_fallback_surface",
		&"",
		"fallback_surface_id",
		source_name,
		"fallback_surface_id must be a String"
	)
	return false


static func _collect_dictionary_entries(
	config: Dictionary,
	entries: Array[Dictionary],
	source_name: String,
	reporter: Callable
) -> Dictionary:
	if config.has("surface_id"):
		entries.append({"declared_id": &"", "definition": config})
		return {"ok": true, "entries": entries, "fallback": &""}
	var split := _split_definitions_container(config, source_name, reporter)
	if split.is_empty():
		return {"ok": false, "entries": entries, "fallback": &""}
	if not collect_entries(split["definitions"], entries, source_name, reporter):
		return {"ok": false, "entries": entries, "fallback": split["fallback"]}
	return {"ok": true, "entries": entries, "fallback": split["fallback"]}


## 容器（surfaces/definitions 键或直接键值表）→
## {"definitions": Variant, "fallback": StringName}；失败返回 {}（错误已上报）。
static func _split_definitions_container(
	config: Dictionary,
	source_name: String,
	reporter: Callable
) -> Dictionary:
	if config.has("surfaces") or config.has("definitions"):
		return _split_explicit_container(config, source_name, reporter)
	var direct_definitions := config.duplicate(true)
	var fallback_value: Variant = direct_definitions.get("fallback_surface_id", "")
	if not fallback_value_is_valid(fallback_value, source_name, reporter):
		return {}
	direct_definitions.erase("fallback_surface_id")
	return {
		"definitions": direct_definitions,
		"fallback": StringName(fallback_value),
	}


static func _split_explicit_container(
	config: Dictionary,
	source_name: String,
	reporter: Callable
) -> Dictionary:
	if not reject_unknown_fields(config, CONTAINER_FIELDS, &"", source_name, reporter):
		return {}
	if config.has("surfaces") and config.has("definitions"):
		reporter.call(
			&"ambiguous_material_container",
			&"",
			"surfaces",
			source_name,
			"use either surfaces or definitions, not both"
		)
		return {}
	var fallback_value: Variant = config.get("fallback_surface_id", "")
	if not fallback_value_is_valid(fallback_value, source_name, reporter):
		return {}
	return {
		"definitions": config.get("surfaces", config.get("definitions", {})),
		"fallback": StringName(fallback_value),
	}


static func _collect_array_entries(
	values: Array,
	entries: Array[Dictionary],
	source_name: String,
	reporter: Callable
) -> void:
	for index in values.size():
		var value: Variant = values[index]
		if not value is Dictionary:
			reporter.call(
				&"invalid_material_definition",
				&"",
				"[%d]" % index,
				source_name,
				"material entry must be a Dictionary"
			)
			continue
		entries.append({"declared_id": &"", "definition": value})


static func _collect_keyed_entries(
	definitions: Dictionary,
	entries: Array[Dictionary],
	source_name: String,
	reporter: Callable
) -> bool:
	for surface_id_value in definitions:
		var definition_value: Variant = definitions[surface_id_value]
		if not _keyed_entry_valid(surface_id_value, definition_value, source_name, reporter):
			continue
		entries.append({
			"declared_id": StringName(surface_id_value),
			"definition": definition_value,
		})
	return true


static func _keyed_entry_valid(
	surface_id_value: Variant,
	definition_value: Variant,
	source_name: String,
	reporter: Callable
) -> bool:
	if not surface_id_value is String and not surface_id_value is StringName:
		reporter.call(
			&"invalid_surface_id",
			&"",
			String(surface_id_value),
			source_name,
			"surface dictionary keys must be non-empty strings"
		)
		return false
	if not definition_value is Dictionary:
		reporter.call(
			&"invalid_material_definition",
			StringName(surface_id_value),
			String(surface_id_value),
			source_name,
			"material definition must be a Dictionary"
		)
		return false
	return true


static func _canonical_texture_fields(
	definition: Dictionary,
	canonical: Dictionary,
	surface_id: StringName,
	source_name: String,
	is_override: bool,
	reporter: Callable,
	texture_loader: Callable
) -> bool:
	var top := texture_field(
		definition, "top_texture", "top_texture_path", surface_id, source_name,
		["path"], reporter, texture_loader
	)
	if not bool(top["valid"]):
		return false
	if bool(top["present"]):
		canonical["top_texture_path"] = top["path"]
	elif not is_override:
		reporter.call(
			&"missing_top_texture",
			surface_id,
			"top_texture",
			source_name,
			"top_texture is required"
		)
		return false
	if not _apply_optional_texture_field(
		definition, canonical, "column_texture", "column_texture_path",
		"column_texture_spec", "top", ["path", "top"],
		surface_id, source_name, is_override, reporter, texture_loader
	):
		return false
	return _apply_optional_texture_field(
		definition, canonical, "underwater_texture", "underwater_texture_path",
		"underwater_texture_spec", "none", ["path", "top", "column", "none"],
		surface_id, source_name, is_override, reporter, texture_loader
	)


static func _apply_optional_texture_field(
	definition: Dictionary,
	canonical: Dictionary,
	field_name: String,
	path_alias: String,
	spec_key: String,
	default_mode: String,
	allowed_modes: Array[String],
	surface_id: StringName,
	source_name: String,
	is_override: bool,
	reporter: Callable,
	texture_loader: Callable
) -> bool:
	var result := texture_field(
		definition, field_name, path_alias, surface_id, source_name,
		allowed_modes, reporter, texture_loader
	)
	if not bool(result["valid"]):
		return false
	if bool(result["present"]):
		canonical[spec_key] = result["spec"]
	elif not is_override:
		canonical[spec_key] = {"mode": default_mode}
	return true


static func _canonical_scalar_fields(
	definition: Dictionary,
	canonical: Dictionary,
	surface_id: StringName,
	source_name: String,
	is_override: bool,
	reporter: Callable
) -> bool:
	if definition.has("minimap_color"):
		var color_value: Variant = parse_color(
			definition["minimap_color"], surface_id, source_name, reporter
		)
		if color_value == null:
			return false
		canonical["minimap_color"] = color_value
	elif not is_override:
		reporter.call(
			&"missing_minimap_color",
			surface_id,
			"minimap_color",
			source_name,
			"minimap_color is required"
		)
		return false
	if definition.has("tags"):
		var tags_value: Variant = parse_tags(
			definition["tags"], surface_id, source_name, reporter
		)
		if tags_value == null:
			return false
		canonical["tags"] = tags_value
	elif not is_override:
		canonical["tags"] = []
	return _canonical_traits(
		definition, canonical, surface_id, source_name, is_override, reporter
	)


static func _canonical_traits(
	definition: Dictionary,
	canonical: Dictionary,
	surface_id: StringName,
	source_name: String,
	is_override: bool,
	reporter: Callable
) -> bool:
	if not definition.has("traits"):
		if not is_override:
			canonical["traits"] = {}
		return true
	if not definition["traits"] is Dictionary:
		reporter.call(
			&"invalid_material_traits",
			surface_id,
			"traits",
			source_name,
			"traits must be a Dictionary"
		)
		return false
	canonical["traits"] = (definition["traits"] as Dictionary).duplicate(true)
	return true


## biome_overrides/biome_override → 逐 id 递归规范化。成功返回字典（可为空），
## 失败返回 null（错误已上报）。
static func _canonical_biome_overrides(
	definition: Dictionary,
	surface_id: StringName,
	source_name: String,
	reporter: Callable,
	texture_loader: Callable
) -> Variant:
	if definition.has("biome_overrides") and definition.has("biome_override"):
		reporter.call(
			&"ambiguous_biome_overrides",
			surface_id,
			"biome_overrides",
			source_name,
			"use biome_overrides or biome_override, not both"
		)
		return null
	var overrides_value: Variant = definition.get(
		"biome_overrides",
		definition.get("biome_override", {})
	)
	if not overrides_value is Dictionary:
		reporter.call(
			&"invalid_biome_overrides",
			surface_id,
			"biome_overrides",
			source_name,
			"biome overrides must be a Dictionary"
		)
		return null
	return _canonicalize_override_entries(
		overrides_value, surface_id, source_name, reporter, texture_loader
	)


static func _canonicalize_override_entries(
	overrides_value: Dictionary,
	surface_id: StringName,
	source_name: String,
	reporter: Callable,
	texture_loader: Callable
) -> Variant:
	var overrides := {}
	for biome_id_value in overrides_value:
		var override_value: Variant = overrides_value[biome_id_value]
		var biome_id := _validated_override_id(
			biome_id_value, override_value, surface_id, source_name, reporter
		)
		if biome_id.is_empty():
			return null
		var canonical_override: Variant = canonicalize_definition(
			override_value,
			surface_id,
			"%s[%s]" % [source_name, biome_id],
			true,
			reporter,
			texture_loader
		)
		if canonical_override.is_empty() and not (override_value as Dictionary).is_empty():
			return null
		overrides[biome_id] = canonical_override
	return overrides


## 校验 biome override 键值对；非法时上报错误并返回 &""。
static func _validated_override_id(
	biome_id_value: Variant,
	override_value: Variant,
	surface_id: StringName,
	source_name: String,
	reporter: Callable
) -> StringName:
	if not biome_id_value is String and not biome_id_value is StringName:
		reporter.call(
			&"invalid_biome_override",
			surface_id,
			"biome_overrides",
			source_name,
			"biome override ids must be non-empty strings"
		)
		return &""
	var biome_id := StringName(biome_id_value)
	if biome_id.is_empty() or not override_value is Dictionary:
		reporter.call(
			&"invalid_biome_override",
			surface_id,
			"biome_overrides.%s" % biome_id,
			source_name,
			"biome override requires a non-empty id and Dictionary"
		)
		return &""
	return biome_id


## 任意 spec 值 → {"mode": String, "path": String}（mode=="invalid" 表示结构非法，
## 后续由 allowed_modes / 空路径检查统一上报）。
static func _texture_spec_parts(value: Variant) -> Dictionary:
	if value is String or value is StringName:
		return _texture_spec_from_string(String(value).strip_edges())
	if value is Dictionary:
		return _texture_spec_from_dictionary(value)
	return {"mode": "invalid", "path": ""}


static func _texture_spec_from_string(text: String) -> Dictionary:
	match text:
		"reuse_top", "top", "@top":
			return {"mode": "top", "path": ""}
		"reuse_column", "column", "@column":
			return {"mode": "column", "path": ""}
		"none", "":
			return {"mode": "none", "path": ""}
		_:
			return {"mode": "path", "path": text}


static func _texture_spec_from_dictionary(dictionary: Dictionary) -> Dictionary:
	for key_value in dictionary:
		if String(key_value) not in ["path", "reuse"]:
			return {"mode": "invalid", "path": ""}
	if dictionary.has("path") and dictionary.has("reuse"):
		return {"mode": "invalid", "path": ""}
	if dictionary.has("path"):
		return _texture_spec_from_path_value(dictionary["path"])
	if dictionary.has("reuse"):
		return _texture_spec_from_reuse_value(dictionary["reuse"])
	return {"mode": "invalid", "path": ""}


static func _texture_spec_from_path_value(value: Variant) -> Dictionary:
	if not value is String and not value is StringName:
		return {"mode": "invalid", "path": ""}
	return {"mode": "path", "path": String(value)}


static func _texture_spec_from_reuse_value(value: Variant) -> Dictionary:
	if not value is String and not value is StringName:
		return {"mode": "invalid", "path": ""}
	match String(value):
		"reuse_top", "top", "@top":
			return {"mode": "top", "path": ""}
		"reuse_column", "column", "@column":
			return {"mode": "column", "path": ""}
		"none":
			return {"mode": "none", "path": ""}
	return {"mode": "invalid", "path": ""}


static func _color_from_value(
	value: Variant,
	surface_id: StringName,
	source_name: String,
	reporter: Callable
) -> Variant:
	if value is Color:
		return value
	if value is String and Color.html_is_valid(value):
		return Color.from_string(value, Color.MAGENTA)
	if value is Array:
		return _color_from_array(value, surface_id, source_name, reporter)
	reporter.call(
		&"invalid_minimap_color",
		surface_id,
		"minimap_color",
		source_name,
		"minimap_color must be Color, HTML string, or RGB/RGBA array"
	)
	return null


static func _color_from_array(
	value: Array,
	surface_id: StringName,
	source_name: String,
	reporter: Callable
) -> Variant:
	if value.size() not in [3, 4]:
		reporter.call(
			&"invalid_minimap_color",
			surface_id,
			"minimap_color",
			source_name,
			"minimap_color must be Color, HTML string, or RGB/RGBA array"
		)
		return null
	for component in value:
		if not component is float and not component is int:
			reporter.call(
				&"invalid_minimap_color",
				surface_id,
				"minimap_color",
				source_name,
				"color components must be numeric"
			)
			return null
	return Color(
		float(value[0]),
		float(value[1]),
		float(value[2]),
		float(value[3]) if value.size() == 4 else 1.0
	)


static func _color_out_of_range(color: Color) -> bool:
	return (
		color.r < 0.0 or color.r > 1.0
		or color.g < 0.0 or color.g > 1.0
		or color.b < 0.0 or color.b > 1.0
		or color.a < 0.0 or color.a > 1.0
	)
