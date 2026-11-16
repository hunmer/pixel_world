## test_animal_behavior_registry.gd — gdtest 试点：与 tests/animal_behavior_registry_contract.gd 等价的最小断言（内置行为齐备 + 组合评分决策）
extends GdTest

const AnimalBehaviorRegistry = preload("res://scripts/animals/animal_behavior_registry.gd")


func _species() -> Dictionary:
	return {
		"behaviors": [
			{
				"type": "allowed_surfaces",
				"surfaces": ["land", "shore"],
			},
			{"type": "max_step_height", "value": 1},
			{
				"type": "flee_player",
				"radius": 3.0,
				"speed_multiplier": 1.75,
				"weight": 2.0,
			},
			{"type": "prefer_tag", "tag": "meadow", "weight": 1.25},
			{"type": "avoid_tag", "tag": "snow", "weight": 4.0},
			{"type": "near_tag", "tag": "water", "radius": 6.0, "weight": 3.0},
			{"type": "pack_cohesion", "radius": 2.0, "weight": 1.5},
		],
	}


func _context() -> Dictionary:
	return {
		"current": {
			"cell": Vector2i.ZERO,
			"height": 3,
			"surface_id": "land",
			"tags": ["grassland"],
		},
		"player_cell": Vector2i(-1, 0),
		"pack_members": [
			{"cell": Vector2i.ZERO},
			{"cell": Vector2i(0, 2)},
		],
		"distance_to_tag": func(cell_data: Dictionary, tag: StringName) -> float:
			return (
				float(cell_data.get("water_distance", 99.0))
				if tag == &"water"
				else 99.0
			),
	}


func test_builtin_types_have_scorers() -> void:
	var registry := AnimalBehaviorRegistry.new()
	for behavior_type: StringName in AnimalBehaviorRegistry.BUILTIN_TYPES:
		assert_true(
			registry.has_scorer(behavior_type),
			"缺少内置行为 scorer: %s" % behavior_type
		)


func test_evaluate_species_decision() -> void:
	var registry := AnimalBehaviorRegistry.new()
	var candidate := {
		"cell": Vector2i(1, 0),
		"height": 4,
		"surface_id": "land",
		"tags": ["meadow"],
		"water_distance": 1.0,
	}
	var decision: Dictionary = registry.evaluate_species(_species(), candidate, _context())
	assert_true(bool(decision["allowed"]), "合法陆地一步被硬约束拒绝")
	assert_gt(float(decision["score"]), 0.0, "组合偏好未产生正向分数")
	assert_almost_eq(float(decision["speed_multiplier"]), 1.75, 1e-6, "物种逃跑倍率未生效")
	assert_true(bool(decision["state"].get("fleeing", false)), "进入半径未触发逃跑")
	assert_eq(
		decision["contributions"].size(),
		_species()["behaviors"].size(),
		"贡献数与行为数不一致"
	)


func test_rejects_water_step_for_land_species() -> void:
	var registry := AnimalBehaviorRegistry.new()
	var water_candidate := {
		"cell": Vector2i(1, 0),
		"height": 4,
		"surface_id": "water",
		"tags": ["deep"],
		"water_distance": 0.0,
	}
	var decision: Dictionary = registry.evaluate_species(_species(), water_candidate, _context())
	assert_false(bool(decision["allowed"]), "allowed_surfaces 硬约束未拒绝水面格")
