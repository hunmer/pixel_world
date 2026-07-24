class_name NoiseRegistry
extends RefCounted

## Configuration-driven FastNoiseLite registry.
##
## Noise fields are deliberately not enumerated here. A biome can introduce a
## new field by adding it to its definition; no central switch or member needs
## to change.

var world_seed: int = 0
var last_error: String = ""

var _defaults: Dictionary = {}
var _field_definitions: Dictionary = {}
var _fields: Dictionary = {}


func configure(noise_definition: Dictionary, initial_world_seed: int = 0) -> bool:
	world_seed = initial_world_seed
	last_error = ""
	_defaults = noise_definition.duplicate(true)
	_defaults.erase("fields")
	_field_definitions.clear()
	_fields.clear()

	var fields_value: Variant = noise_definition.get("fields", {})
	if not fields_value is Dictionary:
		return _fail("noise.fields must be a Dictionary")
	return register_fields(fields_value)


## Adds or replaces fields while retaining the registry-wide defaults.
## This is used by BiomeRegistry for module-local `noise_fields` definitions.
func register_fields(
	field_definitions: Dictionary,
	additional_defaults: Dictionary = {}
) -> bool:
	last_error = ""
	var effective_defaults := _defaults.duplicate(true)
	for key in additional_defaults:
		effective_defaults[key] = additional_defaults[key]

	for raw_field_id in field_definitions:
		var field_id := StringName(String(raw_field_id))
		if field_id.is_empty():
			return _fail("noise field id cannot be empty")
		var field_value: Variant = field_definitions[raw_field_id]
		if not field_value is Dictionary:
			return _fail("noise field '%s' must be a Dictionary" % field_id)
		var definition: Dictionary = field_value
		var noise := _build_noise(field_id, definition, effective_defaults)
		if noise == null:
			return false
		_field_definitions[field_id] = definition.duplicate(true)
		_fields[field_id] = noise
	return true


func reseed(new_world_seed: int) -> void:
	world_seed = new_world_seed
	for field_id in _fields:
		var noise: FastNoiseLite = _fields[field_id]
		var definition: Dictionary = _field_definitions[field_id]
		noise.seed = world_seed + int(definition.get("seed_offset", 0))


func has_field(field_id: StringName) -> bool:
	return _fields.has(field_id)


func get_field(field_id: StringName) -> FastNoiseLite:
	if not _fields.has(field_id):
		return null
	return _fields[field_id]


func field_definition(field_id: StringName) -> Dictionary:
	if not _field_definitions.has(field_id):
		return {}
	return (_field_definitions[field_id] as Dictionary).duplicate(true)


func field_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for field_id in _fields:
		result.append(StringName(field_id))
	result.sort()
	return result


func sample_2d(field_id: StringName, cell: Vector2i) -> float:
	var noise := get_field(field_id)
	if noise == null:
		push_error("Unknown noise field: %s" % field_id)
		return 0.0
	return noise.get_noise_2d(cell.x, cell.y)


func _build_noise(
	field_id: StringName,
	definition: Dictionary,
	defaults: Dictionary
) -> FastNoiseLite:
	var frequency := float(definition.get("frequency", defaults.get("frequency", 0.01)))
	var octaves := int(definition.get("octaves", defaults.get("octaves", 4)))
	if frequency <= 0.0:
		_fail("noise field '%s' frequency must be greater than zero" % field_id)
		return null
	if octaves <= 0:
		_fail("noise field '%s' octaves must be greater than zero" % field_id)
		return null

	var noise_type_name := String(
		definition.get("type", defaults.get("type", "perlin"))
	).to_lower()
	var fractal_type_name := String(
		definition.get("fractal", defaults.get("fractal", "fbm"))
	).to_lower()
	var noise_type := _noise_type_from_name(noise_type_name)
	if noise_type < 0:
		_fail("noise field '%s' has unknown type '%s'" % [field_id, noise_type_name])
		return null
	var fractal_type := _fractal_type_from_name(fractal_type_name)
	if fractal_type < 0:
		_fail("noise field '%s' has unknown fractal '%s'" % [field_id, fractal_type_name])
		return null

	var noise := FastNoiseLite.new()
	noise.seed = world_seed + int(definition.get("seed_offset", 0))
	noise.noise_type = noise_type
	noise.frequency = frequency
	noise.fractal_type = fractal_type
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = float(
		definition.get("lacunarity", defaults.get("lacunarity", 2.0))
	)
	noise.fractal_gain = float(definition.get("gain", defaults.get("gain", 0.5)))
	noise.fractal_weighted_strength = float(
		definition.get("weighted_strength", defaults.get("weighted_strength", 0.0))
	)
	noise.fractal_ping_pong_strength = float(
		definition.get("ping_pong_strength", defaults.get("ping_pong_strength", 2.0))
	)
	return noise


func _noise_type_from_name(value: String) -> int:
	match value:
		"simplex":
			return FastNoiseLite.TYPE_SIMPLEX
		"simplex_smooth":
			return FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		"value":
			return FastNoiseLite.TYPE_VALUE
		"value_cubic":
			return FastNoiseLite.TYPE_VALUE_CUBIC
		"perlin":
			return FastNoiseLite.TYPE_PERLIN
		_:
			return -1


func _fractal_type_from_name(value: String) -> int:
	match value:
		"fbm":
			return FastNoiseLite.FRACTAL_FBM
		"ridged":
			return FastNoiseLite.FRACTAL_RIDGED
		"ping_pong":
			return FastNoiseLite.FRACTAL_PING_PONG
		_:
			return -1


func _fail(message: String) -> bool:
	last_error = message
	push_error(message)
	return false
