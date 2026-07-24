class_name SnowBiome
extends "res://scripts/world/biomes/biome_module.gd"

var _temperature_field := &"temperature"
var _base_level := 14
var _temperature_level_scale := 3.0


func configure(
	initial_definition: Dictionary,
	initial_noise_registry: RefCounted
) -> bool:
	if not super.configure(initial_definition, initial_noise_registry):
		return false
	var climate := _profile()
	var top_level_climate: Variant = definition.get("climate", {})
	if top_level_climate is Dictionary and not top_level_climate.is_empty():
		climate = top_level_climate
	if climate.has("snow") and climate["snow"] is Dictionary:
		climate = climate["snow"]
	_temperature_field = StringName(String(
		climate.get("temperature_noise_field", _temperature_field)
	))
	_base_level = int(climate.get("base_level", _base_level))
	_temperature_level_scale = float(
		climate.get("temperature_level_scale", _temperature_level_scale)
	)
	if _base_level < 0:
		return _fail("snow biome '%s' base level cannot be negative" % id)
	if _temperature_level_scale < 0.0:
		return _fail("snow biome '%s' temperature level scale cannot be negative" % id)
	if not _has_noise(_temperature_field):
		return _fail("snow biome '%s' requires noise field '%s'" % [id, _temperature_field])
	return true


func classify(cell: Variant, quantized_height: int) -> StringName:
	if not enabled:
		return &""
	var temperature := _noise(_temperature_field, cell)
	var snow_line := _base_level + int(temperature * _temperature_level_scale)
	return id if quantized_height >= snow_line else &""


func surface_kind(
	_cell: Variant,
	_quantized_height: int,
	biome_id: StringName
) -> StringName:
	return &"snow" if owns_biome(biome_id) else &""


func tags(
	_cell: Variant,
	_quantized_height: int,
	biome_id: StringName
) -> Array[StringName]:
	if not owns_biome(biome_id):
		return []
	if definition.has("tags"):
		return _string_name_array(definition["tags"])
	return [&"snow", &"cold", &"high_altitude"]


func minimap_color(
	_cell: Variant,
	_quantized_height: int,
	biome_id: StringName
) -> Color:
	if not owns_biome(biome_id):
		return Color(0.0, 0.0, 0.0, 0.0)
	return _color_from_value(
		definition.get("minimap_color", [0.88, 0.90, 0.95]),
		Color(0.88, 0.90, 0.95)
	)


func weather_tags(
	_cell: Variant,
	_quantized_height: int,
	biome_id: StringName
) -> Array[StringName]:
	if not owns_biome(biome_id):
		return []
	if definition.has("weather_tags"):
		return _string_name_array(definition["weather_tags"])
	return [&"cold", &"snow_capable"]
