extends RefCounted

## Test-only behavior plugin. The animal definition opts into this scorer by ID;
## AnimalBehaviorRegistry only supplies the generic registration/evaluation API.


func score_candidate(
	behavior: Dictionary,
	candidate: Dictionary,
	_context: Dictionary
) -> Dictionary:
	var required_tag := StringName(String(behavior.get("required_tag", "hot")))
	var tags_value: Variant = candidate.get("tags", [])
	var matches := false
	if tags_value is Dictionary:
		matches = bool(tags_value.get(required_tag, tags_value.get(String(required_tag), false)))
	elif tags_value is Array:
		for tag_value in tags_value:
			if StringName(String(tag_value)) == required_tag:
				matches = true
				break
	return {
		"score": float(behavior.get("weight", 1.0)) if matches else 0.0,
		"state": {"fixture_heat_affinity_ran": true},
	}
