class_name TemperateBiome
extends "res://scripts/world/biomes/biome_module.gd"

## The temperate module is the normal low-priority fallback. It is also useful
## as a fixture/default module because its public id comes entirely from data.

var classification_id: StringName = &""


func configure(
	initial_definition: Dictionary,
	initial_noise_registry: RefCounted
) -> bool:
	if not super.configure(initial_definition, initial_noise_registry):
		return false
	classification_id = StringName(String(definition.get("classification_id", id)))
	if classification_id.is_empty():
		return _fail("temperate biome '%s' classification_id cannot be empty" % id)
	return true

func classify(_cell: Variant, _quantized_height: int) -> StringName:
	return classification_id if enabled else &""


func owns_biome(biome_id: StringName) -> bool:
	return biome_id == classification_id or super.owns_biome(biome_id)


func surface_kind(
	_cell: Variant,
	_quantized_height: int,
	biome_id: StringName
) -> StringName:
	if not owns_biome(biome_id):
		return &""
	# Empty means the shared terrain sampler chooses grass/rock from elevation.
	return StringName(String(definition.get("surface_kind", "")))


func tags(
	_cell: Variant,
	_quantized_height: int,
	biome_id: StringName
) -> Array[StringName]:
	if not owns_biome(biome_id):
		return []
	if definition.has("tags"):
		return _string_name_array(definition["tags"])
	return [&"temperate", &"mild"]


func minimap_color(
	_cell: Variant,
	quantized_height: int,
	biome_id: StringName
) -> Color:
	if not owns_biome(biome_id):
		return Color(0.0, 0.0, 0.0, 0.0)
	var profile := _profile()
	var water_max := int(profile.get("water_max", 5))
	var level_count := maxi(water_max + 3, int(profile.get("levels", 16)))
	var blend := (
		float(quantized_height - water_max - 2)
		/ float(level_count - water_max - 2)
	)
	var low_color := _color_from_value(
		profile.get("minimap_low_color", [0.35, 0.60, 0.20]),
		Color(0.35, 0.60, 0.20)
	)
	var high_color := _color_from_value(
		profile.get("minimap_high_color", [0.70, 0.85, 0.35]),
		Color(0.70, 0.85, 0.35)
	)
	return low_color.lerp(high_color, clampf(blend, 0.0, 1.0))


func weather_tags(
	_cell: Variant,
	_quantized_height: int,
	biome_id: StringName
) -> Array[StringName]:
	if not owns_biome(biome_id):
		return []
	if definition.has("weather_tags"):
		return _string_name_array(definition["weather_tags"])
	return [&"mild", &"rain_capable"]
