extends RefCounted

## Contract fixture proving external behavior types do not require registry edits.


func score_candidate(
	behavior: Dictionary,
	candidate: Dictionary,
	context: Dictionary
) -> Dictionary:
	var active_season := String(context.get("season", ""))
	var desired_season := String(behavior.get("season", ""))
	var candidate_tags: Array = candidate.get("tags", [])
	var required_tag := String(behavior.get("tag", ""))
	var matches_tag := required_tag.is_empty() or required_tag in candidate_tags
	return {
		"score": (
			float(behavior.get("weight", 1.0))
			if active_season == desired_season and matches_tag
			else 0.0
		),
		"state": {"custom_scorer_ran": true},
	}
