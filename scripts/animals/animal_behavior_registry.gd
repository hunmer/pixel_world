class_name AnimalBehaviorRegistry
extends RefCounted

## Composes data-driven animal movement behaviors without reading the scene tree.
##
## A species supplies a `behaviors` array. Each behavior is either a canonical
## dictionary (`{"type": "near_tag", ...}`) or a legacy behavior string. The
## registry evaluates one candidate at a time and merges every scorer into a
## single decision:
##
##     {
##         "allowed": true,          # all hard constraints passed
##         "score": 3.5,             # additive movement preference
##         "speed_multiplier": 1.8, # multiplicative runtime hint
##         "state": {"fleeing": true},
##         "contributions": [...],
##         "errors": [],
##     }
##
## Candidate facts may be supplied directly (`cell`, `height`, `surface_id`,
## `tags`) or by pure context callables. Supported providers are:
##
##     surface_at(candidate: Dictionary) -> StringName
##     height_at(candidate: Dictionary) -> float
##     has_tag(candidate: Dictionary, tag: StringName) -> bool
##     distance_to_tag(candidate: Dictionary, tag: StringName) -> float
##     distance_between(a, b) -> float
##     pack_center(candidate: Dictionary) -> Vector2/Vector2i
##
## `context.current`, `context.player_cell`, and `context.pack_members` are the
## direct-data equivalents. Callers therefore inject world knowledge without
## coupling behaviors to Main, renderer nodes, or private runtime dictionaries.

const BUILTIN_TYPES: Array[StringName] = [
	&"allowed_surfaces",
	&"max_step_height",
	&"water_depth_range",
	&"water_clearance",
	&"flee_player",
	&"prefer_tag",
	&"avoid_tag",
	&"near_tag",
	&"pack_cohesion",
]

const LEGACY_BEHAVIOR_DEFAULTS := {
	"wander": [],
	"near_water": [
		{
			"type": "near_tag",
			"tag": "water",
			"radius": 13.0,
			"query_radius": 12.0,
			# Equivalent ranking to the old -distance * 20 scorer.
			"weight": 260.0,
		},
	],
	"avoid_snow": [
		{
			"type": "avoid_tag",
			"tag": "snow",
			"weight": 200.0,
		},
		{
			"type": "near_tag",
			"tag": "snow",
			"radius": 7.0,
			"query_radius": 6.0,
			"weight": -140.0,
		},
	],
	"prefer_snow": [
		{
			"type": "prefer_tag",
			"tag": "snow",
			"weight": 200.0,
		},
		{
			"type": "near_tag",
			"tag": "snow",
			"radius": 7.0,
			"query_radius": 6.0,
			"weight": 140.0,
		},
	],
}

var _scorers: Dictionary = {}
var _scorer_owners: Dictionary = {}


func _init(register_builtins := true) -> void:
	if register_builtins:
		_register_builtin_scorers()


## Registers a behavior implementation without changing this registry file.
## `scorer_or_script` may be:
## - a Callable with `(behavior, candidate, context) -> float/Dictionary`,
## - an object exposing `score_candidate`, or
## - a Script whose instances expose `score_candidate`.
func register_scorer(
	behavior_type: StringName,
	scorer_or_script: Variant,
	replace_existing := false
) -> bool:
	if behavior_type.is_empty():
		return false
	if _scorers.has(behavior_type) and not replace_existing:
		return false
	var scorer_value: Variant = scorer_or_script
	if scorer_value is Script:
		scorer_value = (scorer_value as Script).new()
	var scorer := Callable()
	if scorer_value is Callable:
		scorer = scorer_value as Callable
	elif scorer_value is Object and (scorer_value as Object).has_method("score_candidate"):
		scorer = Callable(scorer_value, "score_candidate")
	if not scorer.is_valid():
		return false
	_scorers[behavior_type] = scorer
	# Callable does not retain a RefCounted target. Keep scorer instances alive
	# for as long as their registered type exists.
	if scorer_value is Object:
		_scorer_owners[behavior_type] = scorer_value
	else:
		_scorer_owners.erase(behavior_type)
	return true


func unregister_scorer(behavior_type: StringName) -> bool:
	_scorer_owners.erase(behavior_type)
	return _scorers.erase(behavior_type)


func has_scorer(behavior_type: StringName) -> bool:
	return _scorers.has(behavior_type)


func registered_types() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_scorers.keys())
	result.sort()
	return result


## Builds the canonical behavior stack for one species.
##
## Explicit `behaviors` are authoritative. A legacy `behavior` string is used
## only when the array is absent or empty. Existing top-level/movement
## `allowed_surfaces` and `max_step_height` fields become hard constraints, so
## species can migrate incrementally.
func behaviors_for_species(species: Dictionary) -> Array[Dictionary]:
	var stack: Array[Dictionary] = []
	var raw_behaviors: Variant = species.get("behaviors", [])
	if raw_behaviors is Array:
		for raw_behavior in raw_behaviors:
			stack.append_array(_normalize_behavior(raw_behavior))
	elif raw_behaviors is String or raw_behaviors is StringName:
		stack.append_array(_normalize_behavior(raw_behaviors))

	if stack.is_empty() and species.has("behavior"):
		stack.append_array(legacy_behavior_stack(species.get("behavior", "wander")))

	var movement_value: Variant = species.get("movement", {})
	var movement: Dictionary = movement_value if movement_value is Dictionary else {}
	var allowed_surfaces: Variant = species.get(
		"allowed_surfaces",
		movement.get("allowed_surfaces", null)
	)
	if allowed_surfaces != null and not _stack_has_type(stack, &"allowed_surfaces"):
		stack.push_front({
			"type": "allowed_surfaces",
			"surfaces": _as_array(allowed_surfaces),
		})
	var max_step_height: Variant = species.get(
		"max_step_height",
		movement.get("max_step_height", null)
	)
	if max_step_height != null and not _stack_has_type(stack, &"max_step_height"):
		stack.push_front({
			"type": "max_step_height",
			"value": max_step_height,
		})
	return stack


## Converts the old single-string behavior contract to composable entries.
## Unknown strings are treated as canonical external scorer types, allowing a
## gradual migration where a custom type can already be registered.
func legacy_behavior_stack(legacy_behavior: Variant) -> Array[Dictionary]:
	var legacy_name := String(legacy_behavior).strip_edges()
	if LEGACY_BEHAVIOR_DEFAULTS.has(legacy_name):
		var mapped: Array[Dictionary] = []
		for entry: Dictionary in LEGACY_BEHAVIOR_DEFAULTS[legacy_name]:
			mapped.append(entry.duplicate(true))
		return mapped
	if legacy_name.is_empty():
		return []
	return [{"type": legacy_name}]


## Evaluates the species stack for a movement candidate.
func evaluate_species(
	species: Dictionary,
	candidate: Dictionary,
	context: Dictionary = {}
) -> Dictionary:
	return evaluate_stack(behaviors_for_species(species), candidate, context)


## Evaluates an already-canonical stack. Custom scorer results may be a number
## (score only) or a Dictionary with `allowed`, `score`, `speed_multiplier`,
## `state`, and `reason`.
func evaluate_stack(
	behaviors: Array[Dictionary],
	candidate: Dictionary,
	context: Dictionary = {}
) -> Dictionary:
	var result := {
		"allowed": true,
		"score": 0.0,
		"speed_multiplier": 1.0,
		"state": {},
		"contributions": [],
		"errors": [],
	}
	for behavior: Dictionary in behaviors:
		if not bool(behavior.get("enabled", true)):
			continue
		var behavior_type := StringName(behavior.get("type", ""))
		if behavior_type.is_empty():
			result["allowed"] = false
			result["errors"].append("behavior_missing_type")
			continue
		if not _scorers.has(behavior_type):
			result["allowed"] = false
			result["errors"].append("unknown_behavior:%s" % behavior_type)
			continue
		var scorer: Callable = _scorers[behavior_type]
		var raw_contribution: Variant = scorer.call(behavior, candidate, context)
		var contribution := _normalize_contribution(raw_contribution)
		contribution["type"] = behavior_type
		result["contributions"].append(contribution)
		result["score"] += float(contribution["score"])
		result["speed_multiplier"] *= maxf(
			0.0,
			float(contribution["speed_multiplier"])
		)
		if not bool(contribution["allowed"]):
			result["allowed"] = false
		var contribution_state: Dictionary = contribution["state"]
		for state_key in contribution_state:
			result["state"][state_key] = contribution_state[state_key]
		var reason := String(contribution["reason"])
		if not reason.is_empty() and not bool(contribution["allowed"]):
			result["errors"].append(reason)
	return result


func _register_builtin_scorers() -> void:
	register_scorer(&"allowed_surfaces", _score_allowed_surfaces)
	register_scorer(&"max_step_height", _score_max_step_height)
	register_scorer(&"water_depth_range", _score_water_depth_range)
	register_scorer(&"water_clearance", _score_water_clearance)
	register_scorer(&"flee_player", _score_flee_player)
	register_scorer(&"prefer_tag", _score_prefer_tag)
	register_scorer(&"avoid_tag", _score_avoid_tag)
	register_scorer(&"near_tag", _score_near_tag)
	register_scorer(&"pack_cohesion", _score_pack_cohesion)


func _score_allowed_surfaces(
	behavior: Dictionary,
	candidate: Dictionary,
	context: Dictionary
) -> Dictionary:
	var allowed_values: Variant = behavior.get(
		"surfaces",
		behavior.get("allowed_surfaces", behavior.get("values", []))
	)
	var allowed_surfaces := _as_string_names(allowed_values)
	var surface: Variant = _candidate_surface(candidate, context)
	var allowed := surface != null and StringName(surface) in allowed_surfaces
	return {
		"allowed": allowed,
		"reason": "" if allowed else (
			"surface_not_allowed:%s" % String(surface)
			if surface != null
			else "surface_not_available"
		),
	}


func _score_max_step_height(
	behavior: Dictionary,
	candidate: Dictionary,
	context: Dictionary
) -> Dictionary:
	var current_value: Variant = context.get("current", null)
	if not current_value is Dictionary:
		return {"allowed": false, "reason": "current_cell_not_available"}
	var current: Dictionary = current_value
	var from_height: Variant = _candidate_height(current, context)
	var to_height: Variant = _candidate_height(candidate, context)
	if from_height == null or to_height == null:
		return {"allowed": false, "reason": "height_not_available"}
	var max_height := maxf(
		0.0,
		float(behavior.get("value", behavior.get("max_step_height", 0.0)))
	)
	var height_delta := absf(float(to_height) - float(from_height))
	var allowed := height_delta <= max_height + 0.00001
	return {
		"allowed": allowed,
		"reason": "" if allowed else "max_step_height_exceeded",
		"state": {"step_height": height_delta},
	}


func _score_water_depth_range(
	behavior: Dictionary,
	candidate: Dictionary,
	_context: Dictionary
) -> Dictionary:
	if not candidate.has("water_depth"):
		return {"allowed": false, "reason": "water_depth_not_available"}
	var depth := float(candidate["water_depth"])
	var minimum := maxf(
		0.0,
		float(behavior.get("minimum", behavior.get("min_depth", 0.0)))
	)
	var maximum := maxf(
		minimum,
		float(behavior.get("maximum", behavior.get("max_depth", INF)))
	)
	var allowed := depth >= minimum and depth <= maximum
	return {
		"allowed": allowed,
		"reason": "" if allowed else "water_depth_out_of_range",
		"state": {"water_depth": depth},
	}


func _score_water_clearance(
	behavior: Dictionary,
	candidate: Dictionary,
	_context: Dictionary
) -> Dictionary:
	if not candidate.has("water_clearance"):
		return {"allowed": false, "reason": "water_clearance_not_available"}
	var clearance := maxi(0, int(candidate["water_clearance"]))
	var minimum := maxi(
		0,
		int(behavior.get("minimum", behavior.get("minimum_clearance", 1)))
	)
	var allowed := clearance >= minimum
	return {
		"allowed": allowed,
		"reason": "" if allowed else "water_clearance_too_small",
		"state": {"water_clearance": clearance},
	}


func _score_flee_player(
	behavior: Dictionary,
	candidate: Dictionary,
	context: Dictionary
) -> Dictionary:
	var current_value: Variant = context.get("current", null)
	var player_value: Variant = context.get("player_cell", context.get("player", null))
	if not current_value is Dictionary or player_value == null:
		return {}
	var current: Dictionary = current_value
	var current_position: Variant = _candidate_position(current)
	var candidate_position: Variant = _candidate_position(candidate)
	var player_position: Variant = _spatial_value(player_value)
	if current_position == null or candidate_position == null or player_position == null:
		return {}
	var current_distance := _distance_between(current_position, player_position, context)
	var radius := maxf(0.0, float(behavior.get("radius", 0.0)))
	if current_distance > radius:
		return {"state": {"fleeing": false}}
	var candidate_distance := _distance_between(candidate_position, player_position, context)
	var weight := float(behavior.get("weight", 1.0))
	return {
		"score": (candidate_distance - current_distance) * weight,
		"speed_multiplier": maxf(
			0.0,
			float(behavior.get("speed_multiplier", behavior.get("speed", 1.0)))
		),
		"state": {"fleeing": true},
	}


func _score_prefer_tag(
	behavior: Dictionary,
	candidate: Dictionary,
	context: Dictionary
) -> Dictionary:
	var matches := _matches_behavior_tags(behavior, candidate, context)
	return {"score": float(behavior.get("weight", 1.0)) if matches else 0.0}


func _score_avoid_tag(
	behavior: Dictionary,
	candidate: Dictionary,
	context: Dictionary
) -> Dictionary:
	var matches := _matches_behavior_tags(behavior, candidate, context)
	return {"score": -float(behavior.get("weight", 1.0)) if matches else 0.0}


func _score_near_tag(
	behavior: Dictionary,
	candidate: Dictionary,
	context: Dictionary
) -> Dictionary:
	var tags := _behavior_tags(behavior)
	if tags.is_empty():
		return {}
	var nearest := INF
	var provider: Callable = context.get("distance_to_tag", Callable())
	if provider.is_valid():
		for tag in tags:
			nearest = minf(nearest, float(provider.call(candidate, tag)))
	else:
		for tag in tags:
			if _candidate_has_tag(candidate, tag, context):
				nearest = 0.0
				break
	if is_inf(nearest):
		return {}
	var radius := maxf(
		0.00001,
		float(behavior.get("radius", behavior.get("max_distance", 1.0)))
	)
	var affinity := 1.0 - clampf(nearest / radius, 0.0, 1.0)
	return {
		"score": affinity * float(behavior.get("weight", 1.0)),
		"state": {"near_tag_distance": nearest},
	}


func _score_pack_cohesion(
	behavior: Dictionary,
	candidate: Dictionary,
	context: Dictionary
) -> Dictionary:
	var center: Variant = null
	var configured_center: Variant = context.get("pack_center", null)
	if configured_center is Callable and (configured_center as Callable).is_valid():
		center = (configured_center as Callable).call(candidate)
	elif configured_center != null:
		center = configured_center
	else:
		center = _average_pack_position(context.get("pack_members", []))
	center = _spatial_value(center)
	var candidate_position: Variant = _candidate_position(candidate)
	if center == null or candidate_position == null:
		return {}
	var distance := _distance_between(candidate_position, center, context)
	var radius := maxf(
		0.0,
		float(behavior.get("radius", behavior.get("cohesion_radius", 0.0)))
	)
	var weight := float(behavior.get("weight", 1.0))
	var penalty := maxf(0.0, distance - radius) * weight
	if behavior.has("preferred_distance"):
		penalty += absf(
			distance - maxf(0.0, float(behavior["preferred_distance"]))
		) * maxf(0.0, float(behavior.get("preferred_distance_weight", weight)))
	return {
		"score": -penalty,
		"state": {"pack_distance": distance},
	}


func _normalize_behavior(raw_behavior: Variant) -> Array[Dictionary]:
	if raw_behavior is String or raw_behavior is StringName:
		return legacy_behavior_stack(raw_behavior)
	if not raw_behavior is Dictionary:
		return []
	var behavior: Dictionary = (raw_behavior as Dictionary).duplicate(true)
	var behavior_type := String(behavior.get("type", ""))
	if (
		behavior_type in ["constraint", "constraints", "movement_constraints"]
		or (
			behavior_type.is_empty()
			and (behavior.has("allowed_surfaces") or behavior.has("max_step_height"))
		)
	):
		var constraints: Array[Dictionary] = []
		if behavior.has("allowed_surfaces"):
			constraints.append({
				"type": "allowed_surfaces",
				"surfaces": _as_array(behavior["allowed_surfaces"]),
				"enabled": behavior.get("enabled", true),
			})
		if behavior.has("max_step_height"):
			constraints.append({
				"type": "max_step_height",
				"value": behavior["max_step_height"],
				"enabled": behavior.get("enabled", true),
			})
		return constraints
	return [behavior]


func _normalize_contribution(raw_contribution: Variant) -> Dictionary:
	var contribution := {
		"allowed": true,
		"score": 0.0,
		"speed_multiplier": 1.0,
		"state": {},
		"reason": "",
	}
	if raw_contribution is float or raw_contribution is int:
		contribution["score"] = float(raw_contribution)
		return contribution
	if not raw_contribution is Dictionary:
		return contribution
	var raw: Dictionary = raw_contribution
	contribution["allowed"] = bool(raw.get("allowed", true))
	contribution["score"] = float(raw.get("score", 0.0))
	contribution["speed_multiplier"] = float(raw.get("speed_multiplier", 1.0))
	contribution["reason"] = String(raw.get("reason", ""))
	var state_value: Variant = raw.get("state", {})
	contribution["state"] = (
		(state_value as Dictionary).duplicate(true)
		if state_value is Dictionary
		else {}
	)
	return contribution


func _candidate_surface(candidate: Dictionary, context: Dictionary) -> Variant:
	var provider: Callable = context.get("surface_at", Callable())
	if provider.is_valid():
		return provider.call(candidate)
	return candidate.get("surface_id", candidate.get("surface", null))


func _candidate_height(candidate: Dictionary, context: Dictionary) -> Variant:
	var provider: Callable = context.get("height_at", Callable())
	if provider.is_valid():
		return provider.call(candidate)
	return candidate.get("height", null)


func _candidate_has_tag(
	candidate: Dictionary,
	tag: StringName,
	context: Dictionary
) -> bool:
	var provider: Callable = context.get("has_tag", Callable())
	if provider.is_valid():
		return bool(provider.call(candidate, tag))
	var tags_value: Variant = candidate.get("tags", [])
	if tags_value is Dictionary:
		return bool((tags_value as Dictionary).get(tag, (tags_value as Dictionary).get(String(tag), false)))
	if tags_value is Array or tags_value is PackedStringArray:
		for candidate_tag in tags_value:
			if StringName(candidate_tag) == tag:
				return true
	return false


func _candidate_position(candidate: Dictionary) -> Variant:
	return _spatial_value(candidate.get("cell", candidate.get("position", null)))


func _spatial_value(value: Variant) -> Variant:
	if value is Dictionary:
		var value_dictionary: Dictionary = value
		return value_dictionary.get("cell", value_dictionary.get("position", null))
	if value is Vector2 or value is Vector2i:
		return value
	return null


func _distance_between(a: Variant, b: Variant, context: Dictionary) -> float:
	var provider: Callable = context.get("distance_between", Callable())
	if provider.is_valid():
		return float(provider.call(a, b))
	return Vector2(a).distance_to(Vector2(b))


func _average_pack_position(members_value: Variant) -> Variant:
	if not members_value is Array or (members_value as Array).is_empty():
		return null
	var total := Vector2.ZERO
	var count := 0
	for member in members_value:
		var position: Variant = _spatial_value(member)
		if position == null:
			continue
		total += Vector2(position)
		count += 1
	return total / float(count) if count > 0 else null


func _behavior_tags(behavior: Dictionary) -> Array[StringName]:
	var tag_values: Variant = behavior.get("tags", behavior.get("tag", []))
	return _as_string_names(tag_values)


func _matches_behavior_tags(
	behavior: Dictionary,
	candidate: Dictionary,
	context: Dictionary
) -> bool:
	for tag in _behavior_tags(behavior):
		if _candidate_has_tag(candidate, tag, context):
			return true
	return false


func _stack_has_type(stack: Array[Dictionary], behavior_type: StringName) -> bool:
	for behavior: Dictionary in stack:
		if StringName(behavior.get("type", "")) == behavior_type:
			return true
	return false


func _as_array(value: Variant) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	if value is PackedStringArray:
		return Array(value)
	if value == null:
		return []
	return [value]


func _as_string_names(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	for item in _as_array(value):
		var string_name := StringName(item)
		if not string_name.is_empty() and string_name not in result:
			result.append(string_name)
	return result
