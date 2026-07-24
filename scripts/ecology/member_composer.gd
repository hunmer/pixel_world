extends RefCounted

## Pure, deterministic member composition for ecology communities.
##
## Randomness is supplied by the caller as:
##     rand01.call(position: Vector2i, stream_key: String) -> float in [0, 1)
##
## Flora member entries accept `species` (or `species_id`) and `weight`.
## Fauna entries additionally accept:
## - `count`: an integer or inclusive [minimum, maximum] range.
## - `chance`: chance that this entry participates in the composition.
## - `consumes_population`: whether members count toward the configured population.
## - `fill_remaining`: fill all population still unclaimed by fixed-count entries.
## `compose_fauna(..., single_species=true)` chooses one weighted fill entry for
## the entire group, useful for visually coherent schools or herds.


static func compose_weighted_flora(
	member_specs: Array,
	positions: Array,
	rand01: Callable,
	stream_key := "flora"
) -> Array[Dictionary]:
	var normalized := _normalized_specs(member_specs)
	var result: Array[Dictionary] = []
	if normalized.is_empty():
		return result
	for index in positions.size():
		var position: Vector2i = positions[index]
		var picked := _pick_weighted(
			normalized,
			position,
			rand01,
			"%s/species/%d" % [stream_key, index]
		)
		if picked.is_empty():
			continue
		result.append(_member_from_spec(picked, true))
	return result


static func compose_fauna(
	member_specs: Array,
	population_range: Variant,
	position: Vector2i,
	rand01: Callable,
	stream_key := "fauna",
	single_species := false
) -> Dictionary:
	var target_population := _sample_count(
		population_range,
		position,
		rand01,
		stream_key + "/population"
	)
	var result := {
		"target_population": target_population,
		"consumed_population": 0,
		"remaining_population": target_population,
		"members": [] as Array[Dictionary],
		"complete": target_population == 0,
	}
	if target_population <= 0:
		return result

	var normalized := _normalized_specs(member_specs)
	var fill_specs: Array[Dictionary] = []
	var consumed_population := 0
	var members: Array[Dictionary] = []
	for spec_index in normalized.size():
		var spec: Dictionary = normalized[spec_index]
		if bool(spec.get("fill_remaining", false)):
			if _passes_chance(
				spec,
				position,
				rand01,
				"%s/fill/%d/chance" % [stream_key, spec_index]
			):
				fill_specs.append(spec)
			continue
		if not _passes_chance(
			spec,
			position,
			rand01,
			"%s/fixed/%d/chance" % [stream_key, spec_index]
		):
			continue
		var member_count := _sample_count(
			spec.get("count", 1),
			position,
			rand01,
			"%s/fixed/%d/count" % [stream_key, spec_index]
		)
		var consumes_population := bool(spec.get("consumes_population", true))
		if consumes_population:
			member_count = mini(member_count, target_population - consumed_population)
		for unused_member_index in member_count:
			members.append(_member_from_spec(spec, consumes_population))
		if consumes_population:
			consumed_population += member_count
	if single_species and fill_specs.size() > 1:
		var school_species := _pick_weighted(
			fill_specs,
			position,
			rand01,
			stream_key + "/fill/group_species"
		)
		fill_specs.clear()
		if not school_species.is_empty():
			fill_specs.append(school_species)

	var fill_index := 0
	while consumed_population < target_population and not fill_specs.is_empty():
		var fill_spec := _pick_weighted(
			fill_specs,
			position,
			rand01,
			"%s/fill/species/%d" % [stream_key, fill_index]
		)
		if fill_spec.is_empty():
			break
		var consumes_population := bool(fill_spec.get("consumes_population", true))
		members.append(_member_from_spec(fill_spec, consumes_population))
		fill_index += 1
		if consumes_population:
			consumed_population += 1
		else:
			# A non-consuming fill entry is meaningful as a single companion, but it
			# cannot close the population budget by itself. Remove it to guarantee
			# termination and let another consuming fill entry handle the remainder.
			fill_specs.erase(fill_spec)

	result["consumed_population"] = consumed_population
	result["remaining_population"] = target_population - consumed_population
	result["members"] = members
	result["complete"] = consumed_population == target_population
	return result


static func _normalized_specs(member_specs: Array) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	for value in member_specs:
		var spec: Dictionary
		if value is String or value is StringName:
			spec = {"species": String(value), "weight": 1.0}
		elif value is Dictionary:
			spec = (value as Dictionary).duplicate(true)
		else:
			continue
		var species := String(spec.get("species", spec.get("species_id", "")))
		var weight := float(spec.get("weight", 1.0))
		if species.is_empty() or weight <= 0.0:
			continue
		spec["species"] = species
		spec["weight"] = weight
		normalized.append(spec)
	return normalized


static func _pick_weighted(
	specs: Array[Dictionary],
	position: Vector2i,
	rand01: Callable,
	stream_key: String
) -> Dictionary:
	var total_weight := 0.0
	for spec in specs:
		total_weight += maxf(0.0, float(spec.get("weight", 1.0)))
	if total_weight <= 0.0:
		return {}
	var cursor := _random(rand01, position, stream_key) * total_weight
	for spec in specs:
		cursor -= maxf(0.0, float(spec.get("weight", 1.0)))
		if cursor < 0.0:
			return spec
	return specs.back()


static func _passes_chance(
	spec: Dictionary,
	position: Vector2i,
	rand01: Callable,
	stream_key: String
) -> bool:
	var chance := clampf(float(spec.get("chance", 1.0)), 0.0, 1.0)
	return chance >= 1.0 or (
		chance > 0.0 and _random(rand01, position, stream_key) < chance
	)


static func _sample_count(
	count_value: Variant,
	position: Vector2i,
	rand01: Callable,
	stream_key: String
) -> int:
	var minimum_count: int
	var maximum_count: int
	if count_value is Array and count_value.size() >= 2:
		minimum_count = maxi(0, int(count_value[0]))
		maximum_count = maxi(minimum_count, int(count_value[1]))
	else:
		minimum_count = maxi(0, int(count_value))
		maximum_count = minimum_count
	var span := maximum_count - minimum_count + 1
	if span <= 1:
		return minimum_count
	return minimum_count + mini(
		span - 1,
		floori(_random(rand01, position, stream_key) * float(span))
	)


static func _member_from_spec(spec: Dictionary, consumes_population: bool) -> Dictionary:
	var species := String(spec.get("species", spec.get("species_id", "")))
	var member := {
		"species": species,
		"species_id": species,
		"consumes_population": consumes_population,
	}
	if spec.has("role"):
		member["role"] = spec["role"]
	if spec.has("metadata"):
		member["metadata"] = spec["metadata"]
	return member


static func _random(rand01: Callable, position: Vector2i, stream_key: String) -> float:
	if not rand01.is_valid():
		return 0.0
	return clampf(float(rand01.call(position, stream_key)), 0.0, 0.99999994)
