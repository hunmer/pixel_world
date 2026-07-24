class_name BiomeModule
extends RefCounted

## Base contract for configuration-loaded biome modules.
##
## Returning an empty StringName from `classify()` means "not matched". This
## lets BiomeRegistry evaluate modules by priority without knowing any biome id.

var definition: Dictionary = {}
var noise_registry: RefCounted
var id: StringName = &""
var priority: int = 0
var enabled: bool = true
var last_error: String = ""


func configure(
	initial_definition: Dictionary,
	initial_noise_registry: RefCounted
) -> bool:
	definition = initial_definition.duplicate(true)
	noise_registry = initial_noise_registry
	id = StringName(String(definition.get("id", "")))
	priority = int(definition.get("priority", 0))
	enabled = bool(definition.get("enabled", true))
	last_error = ""
	if id.is_empty():
		return _fail("biome definition id cannot be empty")
	if noise_registry == null:
		return _fail("biome '%s' requires a NoiseRegistry" % id)
	return true


## Height modifiers are applied in registry priority order. A module must leave
## cells outside its influence unchanged.
func modify_height(_cell: Variant, normalized_height: float) -> float:
	return normalized_height


## Multiplier for the shared sparse-peak layer at this cell.
func peak_scale(_cell: Variant) -> float:
	return 1.0


## Returns this module's public biome id (or an alias such as a transition id),
## and returns &"" when it does not classify the cell.
func classify(_cell: Variant, _quantized_height: int) -> StringName:
	return &""


func surface_kind(
	_cell: Variant,
	_quantized_height: int,
	_biome_id: StringName
) -> StringName:
	return &""


func tags(
	_cell: Variant,
	_quantized_height: int,
	biome_id: StringName
) -> Array[StringName]:
	if not owns_biome(biome_id):
		return []
	return _string_name_array(definition.get("tags", []))


func minimap_color(
	_cell: Variant,
	_quantized_height: int,
	biome_id: StringName
) -> Color:
	if not owns_biome(biome_id):
		return Color(0.0, 0.0, 0.0, 0.0)
	return _color_from_value(
		definition.get("minimap_color", Color(0.45, 0.65, 0.3)),
		Color(0.45, 0.65, 0.3)
	)


func weather_tags(
	_cell: Variant,
	_quantized_height: int,
	biome_id: StringName
) -> Array[StringName]:
	if not owns_biome(biome_id):
		return []
	return _string_name_array(definition.get("weather_tags", []))


func owns_biome(biome_id: StringName) -> bool:
	if biome_id == id:
		return true
	for alias in definition.get("aliases", []):
		if biome_id == StringName(String(alias)):
			return true
	return false


func _profile() -> Dictionary:
	var profile_value: Variant = definition.get(
		"profile",
		definition.get("config", {})
	)
	return profile_value if profile_value is Dictionary else {}


func _profile_section(section_id: StringName) -> Dictionary:
	var profile := _profile()
	var section_key := String(section_id)
	var generation_value: Variant = definition.get("generation", {})
	var generation: Dictionary = (
		generation_value if generation_value is Dictionary else {}
	)
	var section_value: Variant = profile.get(
		section_key,
		definition.get(section_key, generation.get(section_key, {}))
	)
	return section_value if section_value is Dictionary else {}


func _cell_position(cell: Variant) -> Vector2i:
	if cell is Vector2i:
		return cell
	if cell is Vector2:
		return Vector2i(cell)
	if cell is Dictionary:
		var dictionary: Dictionary = cell
		var position_value: Variant = dictionary.get(
			"cell",
			dictionary.get("position", Vector2i.ZERO)
		)
		if position_value is Vector2i:
			return position_value
		if position_value is Vector2:
			return Vector2i(position_value)
		if dictionary.has("x") and dictionary.has("y"):
			return Vector2i(int(dictionary["x"]), int(dictionary["y"]))
	if cell is Object:
		var position_value: Variant = cell.get("cell")
		if position_value is Vector2i:
			return position_value
		if position_value is Vector2:
			return Vector2i(position_value)
	return Vector2i.ZERO


func _noise(field_id: StringName, cell: Variant) -> float:
	if noise_registry == null or not noise_registry.has_method("sample_2d"):
		return 0.0
	return float(noise_registry.call("sample_2d", field_id, _cell_position(cell)))


func _has_noise(field_id: StringName) -> bool:
	return (
		noise_registry != null
		and noise_registry.has_method("has_field")
		and bool(noise_registry.call("has_field", field_id))
	)


func _string_name_array(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if value is Array:
		for item in value:
			var item_id := StringName(String(item))
			if not item_id.is_empty() and item_id not in result:
				result.append(item_id)
	return result


func _color_from_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String and Color.html_is_valid(value):
		return Color.from_string(value, fallback)
	if value is Array and value.size() in [3, 4]:
		return Color(
			float(value[0]),
			float(value[1]),
			float(value[2]),
			float(value[3]) if value.size() == 4 else 1.0
		)
	return fallback


func _fail(message: String) -> bool:
	last_error = message
	push_error(message)
	return false
