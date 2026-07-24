class_name TerrainSampler
extends RefCounted

## Pure deterministic world sampler.
##
## This class owns no scene nodes and knows no renderer enums. Landform IDs,
## biome IDs, and noise field IDs all come from configuration. The legacy Array
## returned by `modules()` exists only as a narrow migration adapter.

const NoiseRegistryScript = preload("res://scripts/world/noise_registry.gd")
const BiomeRegistryScript = preload("res://scripts/world/biomes/biome_registry.gd")
const DeterministicRngScript = preload("res://scripts/world/deterministic_rng.gd")
const CellContextScript = preload("res://scripts/world/cell_context.gd")

const DEFAULT_CACHE_CAPACITY := 4096
const REQUIRED_TERRAIN_NOISE_ROLES := [&"base", &"detail", &"roughness", &"peaks"]

var last_error: String = ""
var configured := false
var world_seed: int = 0
var cache_capacity := DEFAULT_CACHE_CAPACITY

var noise_registry: RefCounted
var biome_registry: RefCounted
var deterministic_rng: RefCounted

var _generation: Dictionary = {}
var _height_config: Dictionary = {}
var _height_noise_fields: Dictionary = {}
var _landforms: Array[Dictionary] = []
var _landform_index_by_id: Dictionary = {}
var _landform_total_weight := 0.0
var _default_landform_index := 0
var _biome_index_by_id: Dictionary = {}
var _biome_id_by_index: Dictionary = {}
var _surface_aliases: Dictionary = {}

var _levels := 16
var _water_max := 5
var _water_surface_level := 6
var _rock_level := 12
var _rock_grass_level := 8
var _peak_extra_levels := 10
var _sea_threshold := 6.0 / 16.0
var _mountain_threshold := 0.65
var _terrace_period := 0.3
var _region_cell_size := 128.0
var _region_jitter := 0.9
var _region_blend_width := 14.0
var _seed_salt_x := 11
var _seed_salt_y := 22
var _landform_salt := 33

var _module_cache: Dictionary = {}
var _module_cache_order: Array[Vector2i] = []
var _height_cache: Dictionary = {}
var _height_cache_order: Array[Vector2i] = []
var _sample_cache: Dictionary = {}
var _sample_cache_order: Array[Vector2i] = []


func configure(
	world_generation: Dictionary,
	biome_definitions: Variant,
	seed: int
) -> bool:
	configured = false
	last_error = ""
	clear_cache()
	_generation = _resolve_generation(world_generation)
	world_seed = seed
	if _generation.is_empty():
		return _fail("TerrainSampler requires world generation configuration")

	var cache_value: Variant = _generation.get("cache", {})
	var cache_config: Dictionary = cache_value if cache_value is Dictionary else {}
	cache_capacity = maxi(1, int(
		cache_config.get(
			"max_entries",
			_generation.get("cache_capacity", DEFAULT_CACHE_CAPACITY)
		)
	))

	var noise_value: Variant = _generation.get("noise", {})
	if not noise_value is Dictionary:
		return _fail("generation.noise must be a Dictionary")
	noise_registry = NoiseRegistryScript.new()
	if not noise_registry.configure(noise_value, world_seed):
		return _fail("NoiseRegistry configure failed: %s" % noise_registry.last_error)
	deterministic_rng = DeterministicRngScript.new(world_seed)

	if not _compile_height():
		return false
	if not _compile_regions():
		return false
	var module_definitions := _active_module_definitions(biome_definitions)
	if module_definitions.is_empty():
		return _fail("TerrainSampler requires at least one enabled scripted biome")
	if not _compile_biome_indices(module_definitions):
		return false

	biome_registry = BiomeRegistryScript.new()
	if not biome_registry.configure(module_definitions, noise_registry):
		return _fail("BiomeRegistry configure failed: %s" % biome_registry.last_error)
	configured = true
	return true


func reseed(seed: int) -> void:
	world_seed = seed
	if noise_registry != null:
		noise_registry.reseed(seed)
	if deterministic_rng == null:
		deterministic_rng = DeterministicRngScript.new(seed)
	else:
		deterministic_rng.world_seed = seed
	clear_cache()


func set_cache_capacity(max_entries: int) -> void:
	cache_capacity = maxi(1, max_entries)
	_trim_cache(_module_cache, _module_cache_order)
	_trim_cache(_height_cache, _height_cache_order)
	_trim_cache(_sample_cache, _sample_cache_order)


func clear_cache() -> void:
	_module_cache.clear()
	_module_cache_order.clear()
	_height_cache.clear()
	_height_cache_order.clear()
	_sample_cache.clear()
	_sample_cache_order.clear()


func cache_sizes() -> Dictionary:
	return {
		"modules": _module_cache.size(),
		"height": _height_cache.size(),
		"samples": _sample_cache.size(),
	}


func sample(cell_value: Variant, y_value: Variant = null) -> RefCounted:
	var cell := _cell_position(cell_value, y_value)
	if _sample_cache.has(cell):
		return _sample_cache[cell]
	var quantized_height := quantize(cell)
	var resolved_biome_id := biome_id(cell, quantized_height)
	var shore := is_shore(cell, quantized_height)
	var module_values := modules(cell)
	var primary_landform_index := int(module_values[0])
	var primary_landform: Dictionary = _landforms[primary_landform_index]
	var primary_landform_id := StringName(String(primary_landform["id"]))
	var surface_id := _surface_id(
		cell,
		quantized_height,
		resolved_biome_id,
		shore
	)
	var habitat_tags: Array[StringName] = []
	_append_tag(habitat_tags, resolved_biome_id)
	_append_tag(habitat_tags, StringName("biome:%s" % resolved_biome_id))
	_append_tag(habitat_tags, primary_landform_id)
	_append_tag(habitat_tags, StringName("landform:%s" % primary_landform_id))
	_append_tag(habitat_tags, surface_id)
	_append_tag(habitat_tags, &"water" if quantized_height <= _water_max else &"land")
	if shore:
		_append_tag(habitat_tags, &"shore")
	if quantized_height >= _rock_level:
		_append_tag(habitat_tags, &"high_altitude")
		_append_tag(habitat_tags, &"rocky")
	for module_tag in biome_registry.tags(cell, quantized_height, resolved_biome_id):
		_append_tag(habitat_tags, module_tag)

	var context = CellContextScript.new(
		cell,
		quantized_height,
		resolved_biome_id,
		biome_index(resolved_biome_id),
		primary_landform_id,
		primary_landform_index,
		maxi(0, _water_surface_level - quantized_height),
		quantized_height <= _water_max,
		shore,
		surface_id,
		module_values[7],
		habitat_tags
	)
	_cache_put(_sample_cache, _sample_cache_order, cell, context)
	return context


func noise(
	field_id: StringName,
	cell_value: Variant,
	y_value: Variant = null
) -> float:
	if noise_registry == null:
		return 0.0
	return noise_registry.sample_2d(field_id, _cell_position(cell_value, y_value))


## Deterministic jittered seed point for a logical Voronoi region cell.
func seed_point(region_cell: Vector2i) -> Vector2:
	return (
		Vector2(region_cell)
		+ Vector2(0.5, 0.5)
		+ (
			Vector2(
				deterministic_rng.cell_float(region_cell, &"terrain.region.seed_x", _seed_salt_x),
				deterministic_rng.cell_float(region_cell, &"terrain.region.seed_y", _seed_salt_y)
			)
			- Vector2(0.5, 0.5)
		) * _region_jitter
	) * _region_cell_size


## Dynamic config-order index. No landform id is known to this class.
func landform_index_for_region(region_cell: Vector2i) -> int:
	var random_weight: float = (
		deterministic_rng.cell_float(
			region_cell,
			&"terrain.region.landform",
			_landform_salt
		)
		* _landform_total_weight
	)
	var accumulated := 0.0
	for index in _landforms.size():
		accumulated += float(_landforms[index]["weight"])
		if random_weight < accumulated:
			return index
	return _default_landform_index


func landform_id_for_region(region_cell: Vector2i) -> StringName:
	return StringName(String(_landforms[landform_index_for_region(region_cell)]["id"]))


func landform_id_for_index(index: int) -> StringName:
	if index < 0 or index >= _landforms.size():
		return &""
	return StringName(String(_landforms[index]["id"]))


## Legacy shape: [nearest landform index, second index, w2, nearest region].
func voronoi(cell_value: Variant, y_value: Variant = null) -> Array:
	var cell := _cell_position(cell_value, y_value)
	var point := Vector2(cell)
	var region_cell := Vector2i(
		floori(cell.x / _region_cell_size),
		floori(cell.y / _region_cell_size)
	)
	var first_distance := INF
	var second_distance := INF
	var first_type := _default_landform_index
	var second_type := _default_landform_index
	var first_region := region_cell
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var candidate_region := region_cell + Vector2i(dx, dy)
			var distance := point.distance_squared_to(seed_point(candidate_region))
			if distance < first_distance:
				second_distance = first_distance
				second_type = first_type
				first_distance = distance
				first_type = landform_index_for_region(candidate_region)
				first_region = candidate_region
			elif distance < second_distance:
				second_distance = distance
				second_type = landform_index_for_region(candidate_region)
	var second_weight := (
		1.0
		- clampf(
			(sqrt(second_distance) - sqrt(first_distance)) / _region_blend_width,
			0.0,
			1.0
		)
	) * 0.5
	return [first_type, second_type, second_weight, first_region]


## Legacy adapter shape:
## [landform index, offset, amp, ridge, steep, peak, terrace, region anchor].
func modules(cell_value: Variant, y_value: Variant = null) -> Array:
	var cell := _cell_position(cell_value, y_value)
	if _module_cache.has(cell):
		return (_module_cache[cell] as Array).duplicate()
	var result := voronoi(cell)
	var primary: Dictionary = _landforms[int(result[0])]
	var secondary: Dictionary = _landforms[int(result[1])]
	var second_weight := float(result[2])
	var legacy := [
		int(result[0]),
		lerpf(float(primary["offset"]), float(secondary["offset"]), second_weight),
		lerpf(float(primary["amp"]), float(secondary["amp"]), second_weight),
		lerpf(float(primary["ridge"]), float(secondary["ridge"]), second_weight),
		lerpf(float(primary["steep"]), float(secondary["steep"]), second_weight),
		lerpf(float(primary["peak"]), float(secondary["peak"]), second_weight),
		lerpf(float(primary["terrace"]), float(secondary["terrace"]), second_weight),
		result[3],
	]
	_cache_put(_module_cache, _module_cache_order, cell, legacy)
	return legacy.duplicate()


func quantize(cell_value: Variant, y_value: Variant = null) -> int:
	var cell := _cell_position(cell_value, y_value)
	if _height_cache.has(cell):
		return int(_height_cache[cell])
	var module_values := modules(cell)
	var base := noise(_height_noise_fields[&"base"], cell)
	var roughness_01 := (
		noise(_height_noise_fields[&"roughness"], cell) + 1.0
	) * 0.5
	var amplitude := float(module_values[2]) * lerpf(
		0.75,
		1.25,
		smoothstep(0.35, 0.65, roughness_01)
	)
	var detail := noise(_height_noise_fields[&"detail"], cell)
	var ridge := (1.0 - absf(detail)) * 2.0 - 1.0
	detail = lerpf(detail, ridge, float(module_values[3]) * 0.75)
	var height := clampf(
		float(module_values[1]) + base * 0.2 + detail * amplitude * 0.25,
		-1.0,
		1.0
	)
	if float(module_values[6]) > 0.0:
		var terrace_position: float = height / _terrace_period
		var terraced_height: float = (
			floor(terrace_position)
			+ smoothstep(0.3, 0.7, terrace_position - floor(terrace_position))
		) * _terrace_period
		height = lerpf(height, terraced_height, float(module_values[6]))
	var normalized_height := (height + 1.0) * 0.5
	if normalized_height < _sea_threshold:
		normalized_height = maxf(
			0.0,
			_sea_threshold
			- (_sea_threshold - normalized_height) * float(module_values[4])
		)
	if normalized_height > _mountain_threshold:
		normalized_height = (
			_mountain_threshold
			+ (normalized_height - _mountain_threshold)
			* lerpf(1.0, 2.5, float(module_values[3]))
		)
	normalized_height = biome_registry.apply_height_modifiers(cell, normalized_height)
	var quantized_height := int(
		clampf(normalized_height, 0.0, 0.99999) * _levels
	)
	var peak_ridge := maxf(
		0.0,
		(1.0 - absf(noise(_height_noise_fields[&"peaks"], cell))) - 0.65
	) / 0.35
	quantized_height += int(
		pow(peak_ridge, 2.0)
		* _peak_extra_levels
		* float(module_values[5])
		* biome_registry.peak_scale(cell)
	)
	_cache_put(_height_cache, _height_cache_order, cell, quantized_height)
	return quantized_height


func biome_id(
	cell_value: Variant,
	quantized_height: int = -1,
	y_value: Variant = null
) -> StringName:
	var cell := _cell_position(cell_value, y_value)
	var resolved_height := quantized_height
	if resolved_height < 0:
		resolved_height = quantize(cell)
	return biome_registry.classify(cell, resolved_height)


func biome_index(resolved_biome_id: StringName) -> int:
	return int(_biome_index_by_id.get(resolved_biome_id, -1))


func biome_id_for_index(index: int) -> StringName:
	return StringName(_biome_id_by_index.get(index, &""))


func is_shore(
	cell_value: Variant,
	quantized_height: int = -1,
	y_value: Variant = null
) -> bool:
	var cell := _cell_position(cell_value, y_value)
	var resolved_height := quantized_height
	if resolved_height < 0:
		resolved_height = quantize(cell)
	if resolved_height != _water_max + 1:
		return false
	for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		if quantize(cell + direction) <= _water_max:
			return true
	return false


func _compile_height() -> bool:
	var height_value: Variant = _generation.get("height", {})
	if not height_value is Dictionary:
		return _fail("generation.height must be a Dictionary")
	_height_config = height_value
	_levels = int(_height_config.get("levels", 16))
	_water_max = int(_height_config.get("water_max", 5))
	_water_surface_level = int(
		_height_config.get("water_surface_level", _water_max + 1)
	)
	_rock_level = int(_height_config.get("rock_level", 12))
	_rock_grass_level = int(_height_config.get("rock_grass_level", 8))
	_peak_extra_levels = int(_height_config.get("peak_extra_levels", 10))
	_sea_threshold = float(_height_config.get("sea_threshold", 6.0 / _levels))
	_mountain_threshold = float(_height_config.get("mountain_threshold", 0.65))
	_terrace_period = float(_height_config.get("terrace_period", 0.3))
	if (
		_levels <= 0
		or _water_max < 0
		or _water_max >= _levels
		or _water_surface_level <= _water_max
		or _rock_level < 0
		or _peak_extra_levels < 0
		or _sea_threshold <= 0.0
		or _sea_threshold >= 1.0
		or _mountain_threshold <= _sea_threshold
		or _mountain_threshold >= 1.0
		or _terrace_period <= 0.0
	):
		return _fail("generation.height values are invalid")

	var roles_value: Variant = _height_config.get(
		"noise_fields",
		_generation.get("terrain_noise_fields", {})
	)
	var roles: Dictionary = roles_value if roles_value is Dictionary else {}
	var legacy_defaults := {
		&"base": &"land",
		&"detail": &"detail",
		&"roughness": &"roughness",
		&"peaks": &"peaks",
	}
	_height_noise_fields.clear()
	for role in REQUIRED_TERRAIN_NOISE_ROLES:
		var field_id := StringName(String(roles.get(role, legacy_defaults[role])))
		if field_id.is_empty() or not noise_registry.has_field(field_id):
			return _fail("terrain noise role '%s' references unknown field '%s'" % [role, field_id])
		_height_noise_fields[role] = field_id

	_surface_aliases = {
		&"transition_parched": &"parched_soil",
		&"transition_sparse_grass": &"sparse_grass",
	}
	var aliases_value: Variant = _height_config.get("surface_aliases", {})
	if aliases_value is Dictionary:
		for source_id in aliases_value:
			_surface_aliases[StringName(String(source_id))] = StringName(String(aliases_value[source_id]))
	return true


func _compile_regions() -> bool:
	var regions_value: Variant = _generation.get("regions", {})
	if not regions_value is Dictionary:
		return _fail("generation.regions must be a Dictionary")
	var regions: Dictionary = regions_value
	_region_cell_size = float(regions.get("cell_size", 128.0))
	_region_jitter = float(regions.get("jitter", 0.9))
	_region_blend_width = float(regions.get("blend_width", 14.0))
	var salts_value: Variant = regions.get("legacy_salts", {})
	var salts: Dictionary = salts_value if salts_value is Dictionary else {}
	_seed_salt_x = int(salts.get("seed_x", 11))
	_seed_salt_y = int(salts.get("seed_y", 22))
	_landform_salt = int(salts.get("landform", 33))
	if _region_cell_size <= 0.0 or _region_jitter < 0.0 or _region_blend_width <= 0.0:
		return _fail("generation.regions values are invalid")

	var landforms_value: Variant = regions.get("landforms", [])
	if not landforms_value is Array or landforms_value.is_empty():
		return _fail("generation.regions.landforms must be a non-empty Array")
	_landforms.clear()
	_landform_index_by_id.clear()
	_landform_total_weight = 0.0
	for landform_value in landforms_value:
		if not landform_value is Dictionary:
			return _fail("landform definition must be a Dictionary")
		var definition: Dictionary = landform_value
		var landform_id := StringName(String(definition.get("id", "")))
		if landform_id.is_empty() or _landform_index_by_id.has(landform_id):
			return _fail("landform id is empty or duplicated: %s" % landform_id)
		var weight := float(definition.get("weight", 0.0))
		if weight <= 0.0:
			return _fail("landform '%s' weight must be greater than zero" % landform_id)
		var terrain_value: Variant = definition.get("terrain", {})
		if not terrain_value is Dictionary:
			return _fail("landform '%s' terrain must be a Dictionary" % landform_id)
		var terrain: Dictionary = terrain_value
		var compiled := {
			"id": landform_id,
			"name": String(definition.get("name_zh", definition.get("name", landform_id))),
			"weight": weight,
			"offset": float(terrain.get("offset", 0.0)),
			"amp": float(terrain.get("amplitude", 1.0)),
			"ridge": float(terrain.get("ridge", 0.0)),
			"steep": float(terrain.get("underwater_steepness", 1.0)),
			"peak": float(terrain.get("peak", 0.0)),
			"terrace": float(terrain.get("terrace", 0.0)),
		}
		var index := _landforms.size()
		_landforms.append(compiled)
		_landform_index_by_id[landform_id] = index
		_landform_total_weight += weight
	var default_landform_id := StringName(String(
		regions.get("default_landform", _landforms[0]["id"])
	))
	if not _landform_index_by_id.has(default_landform_id):
		return _fail("default landform is unknown: %s" % default_landform_id)
	_default_landform_index = int(_landform_index_by_id[default_landform_id])
	return true


func _compile_biome_indices(definitions: Variant) -> bool:
	var normalized := _normalize_biome_definitions(definitions)
	if normalized.is_empty():
		return _fail("TerrainSampler requires biome definitions")
	_biome_index_by_id.clear()
	_biome_id_by_index.clear()
	var next_index := 0
	var primary_order: Array[StringName] = []
	var definitions_by_id: Dictionary = {}
	for definition in normalized:
		var biome_id := StringName(String(definition.get("id", "")))
		if biome_id.is_empty() or definitions_by_id.has(biome_id):
			return _fail("biome id is empty or duplicated: %s" % biome_id)
		definitions_by_id[biome_id] = definition

	var explicit_order_value: Variant = _generation.get("biome_index_order", [])
	if explicit_order_value is Array and not explicit_order_value.is_empty():
		for raw_biome_id in explicit_order_value:
			var ordered_id := StringName(String(raw_biome_id))
			if ordered_id.is_empty() or ordered_id in primary_order:
				return _fail("generation.biome_index_order contains an empty or duplicate id")
			primary_order.append(ordered_id)
	else:
		# The lowest-priority classifier is the fallback and receives index zero.
		# Remaining primary IDs preserve module definition order.
		var fallback_definition: Dictionary = normalized[0]
		for definition in normalized:
			if int(definition.get("priority", 0)) < int(fallback_definition.get("priority", 0)):
				fallback_definition = definition
		_append_tag(primary_order, _classification_id(fallback_definition))
		for definition in normalized:
			_append_tag(primary_order, _classification_id(definition))

	# Explicit order may include an alias (for example desert_transition). Primary
	# and alias IDs not listed there are appended deterministically afterwards.
	var all_known_ids: Array[StringName] = []
	for definition in normalized:
		_append_tag(all_known_ids, _classification_id(definition))
		for alias_value in definition.get("aliases", []):
			_append_tag(all_known_ids, StringName(String(alias_value)))
		_append_tag(all_known_ids, StringName(String(definition.get("transition_id", ""))))
	for ordered_id in primary_order:
		if ordered_id not in all_known_ids:
			return _fail("generation.biome_index_order references unknown biome '%s'" % ordered_id)
		_biome_index_by_id[ordered_id] = next_index
		_biome_id_by_index[next_index] = ordered_id
		next_index += 1
	for known_id in all_known_ids:
		if _biome_index_by_id.has(known_id):
			continue
		_biome_index_by_id[known_id] = next_index
		_biome_id_by_index[next_index] = known_id
		next_index += 1

	# Alias indices are assigned only after primary IDs. This preserves stable
	# primary indices while allowing optional explicit legacy alias indices.
	for definition in normalized:
		var alias_indices_value: Variant = definition.get("alias_indices", {})
		var alias_indices: Dictionary = (
			alias_indices_value if alias_indices_value is Dictionary else {}
		)
		var aliases: Array[StringName] = []
		for alias_value in definition.get("aliases", []):
			_append_tag(aliases, StringName(String(alias_value)))
		var transition_id := StringName(String(definition.get("transition_id", "")))
		_append_tag(aliases, transition_id)
		for alias_id in aliases:
			var requested_index := int(alias_indices.get(alias_id, -1))
			if requested_index < 0:
				continue
			var old_index := int(_biome_index_by_id.get(alias_id, -1))
			if old_index == requested_index:
				continue
			if _biome_id_by_index.has(requested_index):
				return _fail("biome alias index is already occupied: %d" % requested_index)
			if old_index >= 0:
				_biome_id_by_index.erase(old_index)
			_biome_index_by_id[alias_id] = requested_index
			_biome_id_by_index[requested_index] = alias_id
	return true


func _surface_id(
	cell: Vector2i,
	quantized_height: int,
	resolved_biome_id: StringName,
	shore: bool
) -> StringName:
	if quantized_height <= _water_max:
		return &"water"
	if shore:
		return &"moist_soil"
	var module_surface: StringName = biome_registry.surface_kind(
		cell,
		quantized_height,
		resolved_biome_id
	)
	if _surface_aliases.has(module_surface):
		module_surface = _surface_aliases[module_surface]
	if not module_surface.is_empty():
		return module_surface
	if quantized_height >= _rock_level:
		return &"rock"
	return &"rock_grass" if quantized_height >= _rock_grass_level else &"grass"


func _normalize_biome_definitions(value: Variant) -> Array[Dictionary]:
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
		return _normalize_biome_definitions(dictionary["biomes"])
	for raw_id in dictionary:
		var definition_value: Variant = dictionary[raw_id]
		if not definition_value is Dictionary:
			continue
		var definition: Dictionary = definition_value.duplicate(true)
		if not definition.has("id"):
			definition["id"] = String(raw_id)
		result.append(definition)
	return result


func _active_module_definitions(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition in _normalize_biome_definitions(value):
		if not bool(definition.get("enabled", true)):
			continue
		if String(definition.get("script", "")).is_empty():
			continue
		result.append(definition)
	return result


func _classification_id(definition: Dictionary) -> StringName:
	return StringName(String(
		definition.get("classification_id", definition.get("id", ""))
	))


func _resolve_generation(value: Dictionary) -> Dictionary:
	var nested_value: Variant = value.get("generation", null)
	if nested_value is Dictionary:
		return (nested_value as Dictionary).duplicate(true)
	return value.duplicate(true)


func _cell_position(value: Variant, y_value: Variant = null) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(value)
	if (value is int or value is float) and (y_value is int or y_value is float):
		return Vector2i(int(value), int(y_value))
	if value is Dictionary:
		var dictionary: Dictionary = value
		var position_value: Variant = dictionary.get(
			"cell",
			dictionary.get("position", Vector2i.ZERO)
		)
		if position_value is Vector2i:
			return position_value
		if position_value is Vector2:
			return Vector2i(position_value)
	return Vector2i.ZERO


func _append_tag(target: Array[StringName], tag: StringName) -> void:
	if not tag.is_empty() and tag not in target:
		target.append(tag)


func _cache_put(
	cache: Dictionary,
	order: Array[Vector2i],
	key: Vector2i,
	value: Variant
) -> void:
	if cache.has(key):
		cache[key] = value
		return
	cache[key] = value
	order.append(key)
	_trim_cache(cache, order)


func _trim_cache(cache: Dictionary, order: Array[Vector2i]) -> void:
	while order.size() > cache_capacity:
		var expired: Vector2i = order.pop_front()
		cache.erase(expired)


func _fail(message: String) -> bool:
	last_error = message
	push_error(message)
	return false
