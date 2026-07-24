extends RefCounted

const MemberComposer = preload("res://scripts/ecology/member_composer.gd")

## Deterministic spatial planner for reusable ecological communities.
##
## Supported placement modes:
## - `scatter`: independently scattered cells inside a territory radius.
## - `patch`: compact cells expanding from the anchor.
## - `solitary`: one fauna member at one anchor.
## - `social_group`: a composed fauna group inside a shared radius.
##
## `definition.distribution` controls `anchor_spacing`, `anchor_jitter`,
## `anchor_search_radius`, `radius`, `chance`, `count`, and optional
## `single_species` fauna composition. These keys may also be placed directly
## on the definition for small modules. No world state is read here.
##
## Injected callables:
##     rand01(position: Vector2i, stream_key: String) -> float in [0, 1)
##     habitat_valid(anchor: Vector2i) -> bool
##     cell_valid(candidate: Vector2i) -> bool

const SUPPORTED_MODES := [&"scatter", &"patch", &"solitary", &"social_group"]


static func plan_community(
	definition: Dictionary,
	bucket: Vector2i,
	rand01: Callable,
	habitat_valid := Callable(),
	cell_valid := Callable()
) -> Dictionary:
	var distribution := _distribution_for(definition)
	var mode := StringName(
		distribution.get(
			"strategy",
			distribution.get(
				"mode",
				distribution.get(
					"placement",
					definition.get("strategy", definition.get("placement", "scatter"))
				)
			)
		)
	)
	var community_id := String(definition.get("id", definition.get("community_id", "")))
	var result := _empty_result(community_id, mode, bucket)
	if mode not in SUPPORTED_MODES:
		result["reason"] = "unsupported_mode"
		return result

	var stream_prefix := String(
		definition.get("stream_key", community_id if not community_id.is_empty() else "community")
	)
	var anchor_result := resolve_anchor(
		definition,
		bucket,
		rand01,
		habitat_valid
	)
	var anchor: Vector2i = anchor_result["anchor"]
	result["anchor"] = anchor
	if not bool(anchor_result["valid"]):
		result["reason"] = "invalid_habitat"
		return result

	var chance := clampf(float(distribution.get("chance", definition.get("chance", 1.0))), 0.0, 1.0)
	if chance <= 0.0 or (
		chance < 1.0
		and _random(rand01, anchor, stream_prefix + "/chance") >= chance
	):
		result["reason"] = "chance_miss"
		return result

	var radius := maxi(0, int(distribution.get("radius", 0)))
	var is_fauna := String(definition.get("kind", "")) == "fauna" or (
		mode == &"solitary" or mode == &"social_group"
	)
	var members: Array[Dictionary] = []
	var target_count := 1
	if is_fauna:
		var population_range: Variant = [1, 1] if mode == &"solitary" else distribution.get("count", [1, 1])
		var composition: Dictionary = MemberComposer.compose_fauna(
			_member_specs_for(definition),
			population_range,
			anchor,
			rand01,
			stream_prefix + "/composition",
			bool(distribution.get("single_species", false))
		)
		result["population"] = composition
		if not bool(composition.get("complete", false)):
			result["reason"] = "incomplete_composition"
			return result
		members.assign(composition.get("members", []))
		target_count = members.size()
		if mode == &"solitary" and target_count != 1:
			result["reason"] = "solitary_requires_one_member"
			return result
	else:
		target_count = _sample_count(
			distribution.get("count", [1, 1]),
			anchor,
			rand01,
			stream_prefix + "/cell_count"
		)
	result["target_count"] = target_count
	if target_count <= 0:
		result["reason"] = "empty_community"
		return result

	var cells := _select_cells(
		anchor,
		radius,
		target_count,
		mode,
		rand01,
		stream_prefix + "/cells",
		cell_valid
	)
	result["cells"] = cells
	if cells.size() < target_count:
		result["reason"] = "insufficient_valid_cells"
		return result

	if not is_fauna:
		members = MemberComposer.compose_weighted_flora(
			_member_specs_for(definition),
			cells,
			rand01,
			stream_prefix + "/composition"
		)
		if members.size() != cells.size():
			result["reason"] = "incomplete_composition"
			return result
	for index in members.size():
		members[index]["cell"] = cells[index]
	result["members"] = members
	result["active"] = true
	result["complete"] = true
	result["reason"] = ""
	return result


## Short alias for callers that treat a community plan as a generated value.
static func generate(
	definition: Dictionary,
	bucket: Vector2i,
	rand01: Callable,
	habitat_valid := Callable(),
	cell_valid := Callable()
) -> Dictionary:
	return plan_community(definition, bucket, rand01, habitat_valid, cell_valid)


static func anchor_for_bucket(
	bucket: Vector2i,
	anchor_spacing: int,
	anchor_jitter: float,
	rand01: Callable,
	stream_key := "community/anchor"
) -> Vector2i:
	var spacing := maxi(1, anchor_spacing)
	var jitter := clampf(anchor_jitter, 0.0, 1.0)
	var inset := floori(float(spacing) * (1.0 - jitter) * 0.5)
	var usable := maxi(1, spacing - inset * 2)
	var offset_x := inset + mini(
		usable - 1,
		floori(_random(rand01, bucket, stream_key + "/x") * float(usable))
	)
	var offset_y := inset + mini(
		usable - 1,
		floori(_random(rand01, bucket, stream_key + "/y") * float(usable))
	)
	return bucket * spacing + Vector2i(offset_x, offset_y)


## Keeps sparse territory buckets stable while allowing habitats such as rivers
## to claim the nearest valid cell around a bucket anchor. Without this step a
## narrow water biome would multiply its low area ratio by the community chance.
static func resolve_anchor(
	definition: Dictionary,
	bucket: Vector2i,
	rand01: Callable,
	habitat_valid := Callable()
) -> Dictionary:
	var distribution := _distribution_for(definition)
	var spacing := maxi(1, int(distribution.get("anchor_spacing", 1)))
	var jitter := clampf(
		float(distribution.get("anchor_jitter", distribution.get("jitter", 1.0))),
		0.0,
		1.0
	)
	var stream_prefix := String(
		definition.get("stream_key", definition.get("id", "community"))
	)
	var original := anchor_for_bucket(
		bucket,
		spacing,
		jitter,
		rand01,
		stream_prefix + "/anchor"
	)
	if _predicate_passes(habitat_valid, original):
		return {"valid": true, "anchor": original, "relocated": false}
	var search_radius := maxi(0, int(distribution.get("anchor_search_radius", 0)))
	if search_radius <= 0:
		return {"valid": false, "anchor": original, "relocated": false}
	for distance in range(1, search_radius + 1):
		var nearest_candidates: Array[Dictionary] = []
		for offset_y in range(-distance, distance + 1):
			var offset_x_abs := distance - absi(offset_y)
			var x_offsets := [0] if offset_x_abs == 0 else [-offset_x_abs, offset_x_abs]
			for offset_x in x_offsets:
				var candidate := original + Vector2i(offset_x, offset_y)
				if not _predicate_passes(habitat_valid, candidate):
					continue
				nearest_candidates.append({
					"cell": candidate,
					"rank": _random(
						rand01,
						candidate,
						stream_prefix + "/anchor_search"
					),
				})
		if nearest_candidates.is_empty():
			continue
		nearest_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(float(a["rank"]), float(b["rank"])):
				return float(a["rank"]) < float(b["rank"])
			var a_cell: Vector2i = a["cell"]
			var b_cell: Vector2i = b["cell"]
			return a_cell.y < b_cell.y or (a_cell.y == b_cell.y and a_cell.x < b_cell.x)
		)
		return {
			"valid": true,
			"anchor": nearest_candidates[0]["cell"],
			"relocated": true,
		}
	return {"valid": false, "anchor": original, "relocated": false}


static func bucket_for_cell(cell: Vector2i, anchor_spacing: int) -> Vector2i:
	var spacing := maxi(1, anchor_spacing)
	return Vector2i(
		floori(float(cell.x) / float(spacing)),
		floori(float(cell.y) / float(spacing))
	)


static func _select_cells(
	anchor: Vector2i,
	radius: int,
	target_count: int,
	mode: StringName,
	rand01: Callable,
	stream_key: String,
	cell_valid: Callable
) -> Array[Vector2i]:
	var candidates: Array[Dictionary] = []
	var safe_radius := maxi(0, radius)
	for offset_y in range(-safe_radius, safe_radius + 1):
		for offset_x in range(-safe_radius, safe_radius + 1):
			if offset_x * offset_x + offset_y * offset_y > safe_radius * safe_radius:
				continue
			var cell := anchor + Vector2i(offset_x, offset_y)
			if not _predicate_passes(cell_valid, cell):
				continue
			var distance := absi(offset_x) + absi(offset_y)
			var random_score := _random(
				rand01,
				cell,
				stream_key + "/rank"
			)
			var score := random_score
			if mode == &"patch":
				# Distance bands keep patches compact; randomness only shapes each rim.
				score += float(distance) * 2.0
			elif cell == anchor:
				# A scatter/social territory still has a stable representative anchor.
				score = -1.0
			candidates.append({"cell": cell, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score := float(a["score"])
		var b_score := float(b["score"])
		if not is_equal_approx(a_score, b_score):
			return a_score < b_score
		var a_cell: Vector2i = a["cell"]
		var b_cell: Vector2i = b["cell"]
		return a_cell.y < b_cell.y or (a_cell.y == b_cell.y and a_cell.x < b_cell.x)
	)
	var result: Array[Vector2i] = []
	for candidate in candidates:
		if result.size() >= target_count:
			break
		result.append(candidate["cell"])
	return result


static func _distribution_for(definition: Dictionary) -> Dictionary:
	var distribution_value: Variant = definition.get("distribution", {})
	if distribution_value is Dictionary:
		var distribution: Dictionary = (distribution_value as Dictionary).duplicate(true)
		for key in [
			"strategy",
			"mode",
			"placement",
			"anchor_spacing",
			"anchor_jitter",
			"jitter",
			"radius",
			"anchor_search_radius",
			"chance",
			"count",
		]:
			if not distribution.has(key) and definition.has(key):
				distribution[key] = definition[key]
		return distribution
	return definition.duplicate(true)


static func _member_specs_for(definition: Dictionary) -> Array:
	var value: Variant = definition.get("members", definition.get("species", []))
	return value if value is Array else []


static func _empty_result(
	community_id: String,
	mode: StringName,
	bucket: Vector2i
) -> Dictionary:
	return {
		"community_id": community_id,
		"mode": mode,
		"bucket": bucket,
		"anchor": Vector2i.ZERO,
		"active": false,
		"complete": false,
		"target_count": 0,
		"cells": [] as Array[Vector2i],
		"members": [] as Array[Dictionary],
		"reason": "",
	}


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


static func _predicate_passes(predicate: Callable, position: Vector2i) -> bool:
	return not predicate.is_valid() or bool(predicate.call(position))


static func _random(rand01: Callable, position: Vector2i, stream_key: String) -> float:
	if not rand01.is_valid():
		return 0.0
	return clampf(float(rand01.call(position, stream_key)), 0.0, 0.99999994)
