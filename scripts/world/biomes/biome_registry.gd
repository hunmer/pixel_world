class_name BiomeRegistry
extends RefCounted

## Loads biome implementations exclusively from definition script paths.
## Adding a biome never requires adding an id, enum, or match branch here.

const REQUIRED_METHODS := [
	"configure",
	"modify_height",
	"peak_scale",
	"classify",
	"surface_kind",
	"tags",
	"minimap_color",
	"weather_tags",
]

var last_error: String = ""
var modules: Array[RefCounted] = []

var _modules_by_id: Dictionary = {}
var _registration_order: Dictionary = {}
var _noise_registry: RefCounted


func configure(definitions: Variant, noise_registry: RefCounted) -> bool:
	last_error = ""
	modules.clear()
	_modules_by_id.clear()
	_registration_order.clear()
	_noise_registry = noise_registry
	if _noise_registry == null:
		return _fail("BiomeRegistry requires a NoiseRegistry")

	var normalized := _normalize_definitions(definitions)
	if normalized.is_empty():
		return _fail("BiomeRegistry requires at least one biome definition")

	for index in normalized.size():
		var definition: Dictionary = normalized[index]
		if not bool(definition.get("enabled", true)):
			continue
		if not _register_definition(definition, index):
			modules.clear()
			_modules_by_id.clear()
			return false
	if modules.is_empty():
		return _fail("BiomeRegistry has no enabled biome modules")

	modules.sort_custom(_higher_priority_first)
	return true


func classify(cell: Variant, quantized_height: int) -> StringName:
	for module in modules:
		var result: Variant = module.call("classify", cell, quantized_height)
		var biome_id := StringName(String(result))
		if not biome_id.is_empty():
			return biome_id
	return &""


## Height modifiers intentionally compose. This supports future combinations
## such as a volcanic plateau whose high elevations also receive glacial bias.
func apply_height_modifiers(cell: Variant, normalized_height: float) -> float:
	var result := normalized_height
	for module in modules:
		result = float(module.call("modify_height", cell, result))
	return result


func peak_scale(cell: Variant) -> float:
	var result := 1.0
	for module in modules:
		result *= float(module.call("peak_scale", cell))
	return maxf(0.0, result)


func surface_kind(
	cell: Variant,
	quantized_height: int,
	biome_id: StringName = &""
) -> StringName:
	var resolved_biome := biome_id
	if resolved_biome.is_empty():
		resolved_biome = classify(cell, quantized_height)
	var module := module_for_biome(resolved_biome)
	if module == null:
		return &""
	return StringName(String(module.call(
		"surface_kind",
		cell,
		quantized_height,
		resolved_biome
	)))


func tags(
	cell: Variant,
	quantized_height: int,
	biome_id: StringName = &""
) -> Array[StringName]:
	var resolved_biome := biome_id
	if resolved_biome.is_empty():
		resolved_biome = classify(cell, quantized_height)
	var module := module_for_biome(resolved_biome)
	if module == null:
		return []
	return _string_name_array(module.call(
		"tags",
		cell,
		quantized_height,
		resolved_biome
	))


func minimap_color(
	cell: Variant,
	quantized_height: int,
	biome_id: StringName = &""
) -> Color:
	var resolved_biome := biome_id
	if resolved_biome.is_empty():
		resolved_biome = classify(cell, quantized_height)
	var module := module_for_biome(resolved_biome)
	if module == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	var result: Variant = module.call(
		"minimap_color",
		cell,
		quantized_height,
		resolved_biome
	)
	return result if result is Color else Color(0.0, 0.0, 0.0, 0.0)


func weather_tags(
	cell: Variant,
	quantized_height: int,
	biome_id: StringName = &""
) -> Array[StringName]:
	var resolved_biome := biome_id
	if resolved_biome.is_empty():
		resolved_biome = classify(cell, quantized_height)
	var module := module_for_biome(resolved_biome)
	if module == null:
		return []
	return _string_name_array(module.call(
		"weather_tags",
		cell,
		quantized_height,
		resolved_biome
	))


func module_for_biome(biome_id: StringName) -> RefCounted:
	if _modules_by_id.has(biome_id):
		return _modules_by_id[biome_id]
	for module in modules:
		if module.has_method("owns_biome") and bool(module.call("owns_biome", biome_id)):
			_modules_by_id[biome_id] = module
			return module
	return null


func module_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for module in modules:
		result.append(StringName(String(module.get("id"))))
	return result


func _register_definition(definition: Dictionary, registration_index: int) -> bool:
	var script_path := String(definition.get("script", ""))
	if script_path.is_empty():
		return _fail("biome '%s' has no script path" % definition.get("id", ""))
	if not ResourceLoader.exists(script_path, "Script"):
		return _fail("biome script does not exist: %s" % script_path)

	var noise_fields_value: Variant = definition.get("noise_fields", {})
	if not noise_fields_value is Dictionary:
		return _fail("biome '%s' noise_fields must be a Dictionary" % definition.get("id", ""))
	if not noise_fields_value.is_empty():
		if not _noise_registry.has_method("register_fields"):
			return _fail("NoiseRegistry does not support module-local fields")
		var noise_defaults_value: Variant = definition.get("noise_defaults", {})
		var noise_defaults: Dictionary = (
			noise_defaults_value if noise_defaults_value is Dictionary else {}
		)
		if not bool(_noise_registry.call(
			"register_fields",
			noise_fields_value,
			noise_defaults
		)):
			return _fail("failed to register noise fields for biome '%s'" % definition.get("id", ""))

	var script_resource: Script = load(script_path)
	var module_value: Variant = script_resource.new()
	if not module_value is RefCounted:
		return _fail("biome script must create a RefCounted module: %s" % script_path)
	var module: RefCounted = module_value
	for method_name in REQUIRED_METHODS:
		if not module.has_method(method_name):
			return _fail("biome script '%s' is missing %s()" % [script_path, method_name])
	if not bool(module.call("configure", definition, _noise_registry)):
		var module_error := String(module.get("last_error"))
		return _fail(
			module_error
			if not module_error.is_empty()
			else "biome module configure failed: %s" % script_path
		)

	var biome_id := StringName(String(module.get("id")))
	if biome_id.is_empty():
		return _fail("biome script '%s' produced an empty id" % script_path)
	if _modules_by_id.has(biome_id):
		return _fail("duplicate biome id: %s" % biome_id)
	modules.append(module)
	_modules_by_id[biome_id] = module
	_registration_order[module.get_instance_id()] = registration_index
	return true


func _normalize_definitions(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for definition_value in value:
			if definition_value is Dictionary:
				result.append((definition_value as Dictionary).duplicate(true))
		return result
	if not value is Dictionary:
		return result
	var dictionary: Dictionary = value
	if dictionary.has("biomes"):
		return _normalize_definitions(dictionary["biomes"])
	for raw_biome_id in dictionary:
		var definition_value: Variant = dictionary[raw_biome_id]
		if not definition_value is Dictionary:
			continue
		var definition: Dictionary = definition_value.duplicate(true)
		if not definition.has("id"):
			definition["id"] = String(raw_biome_id)
		result.append(definition)
	return result


func _higher_priority_first(left: RefCounted, right: RefCounted) -> bool:
	var left_priority := int(left.get("priority"))
	var right_priority := int(right.get("priority"))
	if left_priority != right_priority:
		return left_priority > right_priority
	return (
		int(_registration_order[left.get_instance_id()])
		< int(_registration_order[right.get_instance_id()])
	)


func _string_name_array(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if value is Array:
		for item in value:
			var item_id := StringName(String(item))
			if not item_id.is_empty() and item_id not in result:
				result.append(item_id)
	return result


func _fail(message: String) -> bool:
	last_error = message
	push_error(message)
	return false
