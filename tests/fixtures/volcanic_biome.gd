extends "res://scripts/world/biomes/biome_module.gd"

## External fixture proving a new biome implementation is a script + data, not
## a BiomeRegistry branch.

var _heat_field := &"fixture_volcanic_heat"
var _minimum_heat := -1.0
var _minimum_level := 0
var _height_bias := 0.0
var _peak_multiplier := 1.0


func configure(
	initial_definition: Dictionary,
	initial_noise_registry: RefCounted
) -> bool:
	if not super.configure(initial_definition, initial_noise_registry):
		return false
	var profile := _profile()
	_heat_field = StringName(String(profile.get("heat_noise_field", _heat_field)))
	_minimum_heat = float(profile.get("minimum_heat", _minimum_heat))
	_minimum_level = int(profile.get("minimum_level", _minimum_level))
	_height_bias = float(profile.get("height_bias", _height_bias))
	_peak_multiplier = float(profile.get("peak_scale", _peak_multiplier))
	if not _has_noise(_heat_field):
		return _fail("fixture volcanic biome requires '%s'" % _heat_field)
	return true


func modify_height(cell: Variant, normalized_height: float) -> float:
	if _noise(_heat_field, cell) < _minimum_heat:
		return normalized_height
	return normalized_height + _height_bias


func peak_scale(cell: Variant) -> float:
	return _peak_multiplier if _noise(_heat_field, cell) >= _minimum_heat else 1.0


func classify(cell: Variant, quantized_height: int) -> StringName:
	if quantized_height < _minimum_level:
		return &""
	return id if _noise(_heat_field, cell) >= _minimum_heat else &""


func surface_kind(
	_cell: Variant,
	_quantized_height: int,
	biome_id: StringName
) -> StringName:
	return &"basalt" if owns_biome(biome_id) else &""
