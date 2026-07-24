class_name DesertBiome
extends "res://scripts/world/biomes/biome_module.gd"

const DeterministicRngScript = preload("res://scripts/world/deterministic_rng.gd")

const SURFACE_SAND := &"sand"
const SURFACE_ROCK := &"rock"
const SURFACE_TRANSITION_PARCHED := &"transition_parched"
const SURFACE_TRANSITION_SPARSE_GRASS := &"transition_sparse_grass"

var transition_id: StringName = &"desert_transition"

var _region_field := &"desert_regions"
var _edge_field := &"desert_edges"
var _dune_field := &"desert_dunes"
var _rock_field := &"desert_rocks"

var _transition_threshold := 0.14
var _core_threshold := 0.22
var _edge_amplitude := 0.05
var _transition_grass_fraction := 0.35
var _transition_grass_chance := 0.10
var _transition_sand_enter := 0.68
var _transition_rock_noise_above := 0.40
var _rock_noise_above := 0.30
var _rock_level := 12
var _elevation_bias := 0.14
var _relief_scale := 0.55
var _dune_amplitude := 0.07
var _desert_peak_scale := 0.20
var _surface_random_salt := 913


func configure(
	initial_definition: Dictionary,
	initial_noise_registry: RefCounted
) -> bool:
	if not super.configure(initial_definition, initial_noise_registry):
		return false
	transition_id = StringName(String(
		definition.get("transition_id", "%s_transition" % id)
	))

	var region := _profile_section(&"region")
	var surface := _profile_section(&"surface")
	var terrain := _profile_section(&"terrain")
	_region_field = StringName(String(region.get("noise_field", _region_field)))
	_edge_field = StringName(String(region.get("edge_noise_field", _edge_field)))
	_dune_field = StringName(String(terrain.get("dune_noise_field", _dune_field)))
	_rock_field = StringName(String(surface.get("rock_noise_field", _rock_field)))
	_transition_threshold = float(region.get("transition_threshold", _transition_threshold))
	_core_threshold = float(region.get("core_threshold", _core_threshold))
	_edge_amplitude = float(region.get("edge_amplitude", _edge_amplitude))
	_transition_grass_fraction = float(
		surface.get("transition_grass_fraction", _transition_grass_fraction)
	)
	_transition_grass_chance = float(
		surface.get("transition_grass_chance", _transition_grass_chance)
	)
	_transition_sand_enter = float(
		surface.get("transition_sand_enter", _transition_sand_enter)
	)
	_transition_rock_noise_above = float(
		surface.get("transition_rock_noise_above", _transition_rock_noise_above)
	)
	_rock_noise_above = float(surface.get("rock_noise_above", _rock_noise_above))
	_rock_level = int(surface.get("rock_level", _rock_level))
	_surface_random_salt = int(surface.get("random_salt", _surface_random_salt))
	_elevation_bias = float(terrain.get("elevation_bias", _elevation_bias))
	_relief_scale = float(terrain.get("relief_scale", _relief_scale))
	_dune_amplitude = float(terrain.get("dune_amplitude", _dune_amplitude))
	_desert_peak_scale = float(terrain.get("peak_scale", _desert_peak_scale))

	if not _validate_profile():
		return false
	for field_id in [_region_field, _edge_field, _dune_field, _rock_field]:
		if not _has_noise(field_id):
			return _fail("desert biome '%s' requires noise field '%s'" % [id, field_id])
	return true


func modify_height(cell: Variant, normalized_height: float) -> float:
	if not enabled:
		return normalized_height
	var strength := terrain_strength(cell)
	if strength <= 0.0:
		return normalized_height
	var desert_height := (
		0.5
		+ (normalized_height - 0.5) * _relief_scale
		+ _noise(_dune_field, cell) * _dune_amplitude
		+ _elevation_bias
	)
	return lerpf(normalized_height, desert_height, strength)


func peak_scale(cell: Variant) -> float:
	if not enabled:
		return 1.0
	return lerpf(1.0, _desert_peak_scale, terrain_strength(cell))


func classify(cell: Variant, _quantized_height: int) -> StringName:
	if not enabled:
		return &""
	var score := region_score(cell)
	if score >= _core_threshold:
		return id
	if score >= _transition_threshold:
		return transition_id
	return &""


func surface_kind(
	cell: Variant,
	quantized_height: int,
	biome_id: StringName
) -> StringName:
	if biome_id == id:
		if (
			quantized_height >= _rock_level
			or _noise(_rock_field, cell) >= _rock_noise_above
		):
			return SURFACE_ROCK
		return SURFACE_SAND
	if biome_id != transition_id:
		return &""

	var transition_progress := clampf(inverse_lerp(
		_transition_threshold,
		_core_threshold,
		region_score(cell)
	), 0.0, 1.0)
	var rock_noise := _noise(_rock_field, cell)
	var rock_threshold := lerpf(
		_transition_rock_noise_above,
		_rock_noise_above,
		smoothstep(0.15, 1.0, transition_progress)
	)
	if rock_noise >= rock_threshold:
		return SURFACE_ROCK
	var sand_score := (
		transition_progress
		+ _noise(_edge_field, cell) * 0.28
		+ _noise(_dune_field, cell) * 0.18
	)
	if sand_score >= _transition_sand_enter:
		return SURFACE_SAND
	if (
		transition_progress < _transition_grass_fraction
		and _cell_rand(_cell_position(cell), _surface_random_salt)
		< _transition_grass_chance
	):
		return SURFACE_TRANSITION_SPARSE_GRASS
	return SURFACE_TRANSITION_PARCHED


func tags(
	_cell: Variant,
	_quantized_height: int,
	biome_id: StringName
) -> Array[StringName]:
	if biome_id == id:
		return _definition_tags("tags", [&"desert", &"arid"])
	if biome_id == transition_id:
		return _definition_tags(
			"transition_tags",
			[&"desert_transition", &"semi_arid"]
		)
	return []


func minimap_color(
	_cell: Variant,
	_quantized_height: int,
	biome_id: StringName
) -> Color:
	var colors_value: Variant = definition.get("minimap_colors", {})
	var colors: Dictionary = colors_value if colors_value is Dictionary else {}
	if biome_id == id:
		return _color_from_value(
			colors.get("core", definition.get("minimap_color", [0.85, 0.72, 0.42])),
			Color(0.85, 0.72, 0.42)
		)
	if biome_id == transition_id:
		return _color_from_value(
			colors.get("transition", [0.48, 0.34, 0.22]),
			Color(0.48, 0.34, 0.22)
		)
	return Color(0.0, 0.0, 0.0, 0.0)


func weather_tags(
	_cell: Variant,
	_quantized_height: int,
	biome_id: StringName
) -> Array[StringName]:
	if biome_id == id:
		return _definition_tags("weather_tags", [&"dry"])
	if biome_id == transition_id:
		return _definition_tags("transition_weather_tags", [&"semi_dry"])
	return []


func owns_biome(biome_id: StringName) -> bool:
	return biome_id == id or biome_id == transition_id or super.owns_biome(biome_id)


func region_score(cell: Variant) -> float:
	var macro_score := _noise(_region_field, cell)
	var threshold_gap := _core_threshold - _transition_threshold
	var enter_weight := smoothstep(
		_transition_threshold - threshold_gap * 0.5,
		_transition_threshold + threshold_gap / 6.0,
		macro_score
	)
	var leave_weight := 1.0 - smoothstep(
		_core_threshold + threshold_gap / 6.0,
		_core_threshold + threshold_gap * 2.0 / 3.0,
		macro_score
	)
	return (
		macro_score
		+ _noise(_edge_field, cell)
		* _edge_amplitude
		* enter_weight
		* leave_weight
	)


func terrain_strength(cell: Variant) -> float:
	var score := region_score(cell)
	if score <= _transition_threshold:
		return 0.0
	return smoothstep(_transition_threshold, _core_threshold, score)


func _cell_rand(cell: Vector2i, salt: int) -> float:
	var registry_seed := int(noise_registry.get("world_seed"))
	return (
		float(DeterministicRngScript.hash_u32(
			cell.x * DeterministicRngScript.CELL_X_FACTOR
			^ cell.y * DeterministicRngScript.CELL_Y_FACTOR
			^ (registry_seed + salt)
		))
		/ DeterministicRngScript.U32_MAX_FLOAT
	)


func _definition_tags(key: String, fallback: Array[StringName]) -> Array[StringName]:
	if definition.has(key):
		return _string_name_array(definition[key])
	return fallback.duplicate()


func _validate_profile() -> bool:
	if _transition_threshold < -1.0 or _transition_threshold > 1.0:
		return _fail("desert transition threshold must be within -1..1")
	if _core_threshold <= _transition_threshold or _core_threshold > 1.0:
		return _fail("desert core threshold must be above transition threshold")
	if _edge_amplitude < 0.0 or _edge_amplitude > 0.055:
		return _fail("desert edge amplitude must be within 0..0.055")
	if _transition_grass_fraction < 0.0 or _transition_grass_fraction > 1.0:
		return _fail("desert transition grass fraction must be within 0..1")
	if _transition_grass_chance < 0.0 or _transition_grass_chance > 1.0:
		return _fail("desert transition grass chance must be within 0..1")
	if _transition_sand_enter < 0.0 or _transition_sand_enter > 1.0:
		return _fail("desert transition sand threshold must be within 0..1")
	if (
		_transition_rock_noise_above < _rock_noise_above
		or _transition_rock_noise_above > 1.0
		or _rock_noise_above < -1.0
		or _rock_noise_above > 1.0
	):
		return _fail("desert rock thresholds are invalid")
	if _rock_level < 0:
		return _fail("desert rock level cannot be negative")
	if _elevation_bias < -0.5 or _elevation_bias > 0.5:
		return _fail("desert elevation bias must be within -0.5..0.5")
	if _relief_scale < 0.0 or _relief_scale > 1.5:
		return _fail("desert relief scale must be within 0..1.5")
	if _dune_amplitude < 0.0 or _dune_amplitude > 0.5:
		return _fail("desert dune amplitude must be within 0..0.5")
	if _desert_peak_scale < 0.0 or _desert_peak_scale > 1.0:
		return _fail("desert peak scale must be within 0..1")
	return true
