extends SceneTree

const AnimalBehaviorRegistry = preload("res://scripts/animals/animal_behavior_registry.gd")
const CustomAnimalBehaviorScorer = preload(
	"res://tests/fixtures/custom_animal_behavior_scorer.gd"
)

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := AnimalBehaviorRegistry.new()
	for behavior_type: StringName in AnimalBehaviorRegistry.BUILTIN_TYPES:
		_expect(registry.has_scorer(behavior_type), "缺少内置行为：%s" % behavior_type)

	var species := {
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
	var current := {
		"cell": Vector2i.ZERO,
		"height": 3,
		"surface_id": "land",
		"tags": ["grassland"],
	}
	var candidate := {
		"cell": Vector2i(1, 0),
		"height": 4,
		"surface_id": "land",
		"tags": ["meadow"],
		"water_distance": 1.0,
	}
	var context := {
		"current": current,
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
	var decision: Dictionary = registry.evaluate_species(species, candidate, context)
	_expect(bool(decision["allowed"]), "合法的陆地一步被硬约束拒绝")
	_expect(float(decision["score"]) > 0.0, "组合偏好没有产生正向分数")
	_expect(
		is_equal_approx(float(decision["speed_multiplier"]), 1.75),
		"物种自己的逃跑速度倍率没有生效"
	)
	_expect(bool(decision["state"].get("fleeing", false)), "玩家进入物种半径后没有触发逃跑")
	_expect(
		decision["contributions"].size() == species["behaviors"].size(),
		"行为栈没有逐项组合"
	)

	var invalid_surface := candidate.duplicate(true)
	invalid_surface["surface_id"] = "water"
	var invalid_surface_decision: Dictionary = registry.evaluate_species(
		species,
		invalid_surface,
		context
	)
	_expect(not bool(invalid_surface_decision["allowed"]), "allowed_surfaces 没有作为硬约束")
	_expect(
		"surface_not_allowed:water" in invalid_surface_decision["errors"],
		"非法地表缺少可诊断原因"
	)

	var shallow_fish := {
		"allowed_surfaces": ["water"],
		"behaviors": [
			{
				"type": "water_depth_range",
				"minimum": 1,
				"maximum": 2,
			},
			{"type": "water_clearance", "minimum": 1},
		],
	}
	var shallow_water := {
		"cell": Vector2i.ZERO,
		"height": 6,
		"surface_id": "water",
		"water_depth": 2,
		"water_clearance": 1,
		"tags": ["water"],
	}
	var deep_water := shallow_water.duplicate(true)
	deep_water["water_depth"] = 4
	_expect(
		bool(registry.evaluate_species(shallow_fish, shallow_water)["allowed"]),
		"浅水鱼拒绝了配置深度内的水格"
	)
	var deep_water_decision: Dictionary = registry.evaluate_species(
		shallow_fish,
		deep_water
	)
	_expect(not bool(deep_water_decision["allowed"]), "浅水鱼可以游入深水区")
	_expect(
		"water_depth_out_of_range" in deep_water_decision["errors"],
		"水深越界缺少可诊断原因"
	)
	var shore_water := shallow_water.duplicate(true)
	shore_water["water_clearance"] = 0
	var shore_water_decision: Dictionary = registry.evaluate_species(
		shallow_fish,
		shore_water
	)
	_expect(not bool(shore_water_decision["allowed"]), "鱼可以游到紧贴岸边的水格")
	_expect(
		"water_clearance_too_small" in shore_water_decision["errors"],
		"近岸水格拒绝原因不可诊断"
	)

	var invalid_height := candidate.duplicate(true)
	invalid_height["height"] = 5
	var invalid_height_decision: Dictionary = registry.evaluate_species(
		species,
		invalid_height,
		context
	)
	_expect(not bool(invalid_height_decision["allowed"]), "max_step_height 没有作为硬约束")
	_expect(
		"max_step_height_exceeded" in invalid_height_decision["errors"],
		"过高台阶缺少可诊断原因"
	)

	# Per-species flee radius and speed are data, not global constants.
	var timid_species := {
		"behaviors": [{
			"type": "flee_player",
			"radius": 4.0,
			"speed_multiplier": 2.2,
		}],
	}
	var calm_species := {
		"behaviors": [{
			"type": "flee_player",
			"radius": 0.5,
			"speed_multiplier": 3.0,
		}],
	}
	var timid_decision: Dictionary = registry.evaluate_species(timid_species, candidate, context)
	var calm_decision: Dictionary = registry.evaluate_species(calm_species, candidate, context)
	_expect(bool(timid_decision["state"].get("fleeing", false)), "较大物种逃跑半径未生效")
	_expect(not bool(calm_decision["state"].get("fleeing", false)), "较小物种逃跑半径未生效")
	_expect(
		is_equal_approx(float(timid_decision["speed_multiplier"]), 2.2),
		"触发逃跑时没有应用该物种速度"
	)
	_expect(
		is_equal_approx(float(calm_decision["speed_multiplier"]), 1.0),
		"未触发逃跑时错误应用了速度"
	)

	# Every world fact may be injected through callables instead of renderer state.
	var injected_species := {
		"behaviors": [
			{"type": "allowed_surfaces", "surfaces": ["shore"]},
			{"type": "max_step_height", "value": 2},
			{"type": "prefer_tag", "tag": "humid", "weight": 2.0},
		],
	}
	var injected_current := {"logical_height": 10}
	var injected_candidate := {
		"logical_height": 12,
		"logical_surface": "shore",
		"logical_tags": ["humid"],
	}
	var injected_context := {
		"current": injected_current,
		"surface_at": func(cell_data: Dictionary) -> StringName:
			return StringName(cell_data.get("logical_surface", "shore")),
		"height_at": func(cell_data: Dictionary) -> float:
			return float(cell_data.get("logical_height", 10)),
		"has_tag": func(cell_data: Dictionary, tag: StringName) -> bool:
			return String(tag) in cell_data.get("logical_tags", []),
	}
	var injected_decision: Dictionary = registry.evaluate_species(
		injected_species,
		injected_candidate,
		injected_context
	)
	_expect(bool(injected_decision["allowed"]), "Callable 注入的地表/高度没有生效")
	_expect(
		is_equal_approx(float(injected_decision["score"]), 2.0),
		"Callable 注入的 tag 没有生效"
	)

	# Tag affinity and pack cohesion must rank candidates, not mutate the world.
	var snow_candidate := candidate.duplicate(true)
	snow_candidate["tags"] = ["snow"]
	var snow_decision: Dictionary = registry.evaluate_species(species, snow_candidate, context)
	_expect(
		float(snow_decision["score"]) < float(decision["score"]),
		"avoid_tag 没有降低雪地候选分数"
	)
	var far_from_water := candidate.duplicate(true)
	far_from_water["water_distance"] = 6.0
	var far_from_water_decision: Dictionary = registry.evaluate_species(
		species,
		far_from_water,
		context
	)
	_expect(
		float(far_from_water_decision["score"]) < float(decision["score"]),
		"near_tag 没有偏好更接近目标 tag 的候选"
	)
	var far_from_pack := candidate.duplicate(true)
	far_from_pack["cell"] = Vector2i(7, 0)
	far_from_pack["water_distance"] = 1.0
	var far_from_pack_context := context.duplicate(true)
	far_from_pack_context["player_cell"] = Vector2i(-20, 0)
	var near_pack_context := far_from_pack_context.duplicate(true)
	var no_flee_near_pack: Dictionary = registry.evaluate_species(
		species,
		candidate,
		near_pack_context
	)
	var no_flee_far_pack: Dictionary = registry.evaluate_species(
		species,
		far_from_pack,
		far_from_pack_context
	)
	_expect(
		float(no_flee_far_pack["score"]) < float(no_flee_near_pack["score"]),
		"pack_cohesion 没有惩罚脱离群体的候选"
	)

	# Compatibility: old strings become the equivalent composable stack.
	var legacy_near_water: Array[Dictionary] = registry.behaviors_for_species({
		"behavior": "near_water",
	})
	_expect(legacy_near_water.size() == 1, "near_water 旧行为没有转换")
	_expect(
		String(legacy_near_water[0].get("type", "")) == "near_tag"
		and String(legacy_near_water[0].get("tag", "")) == "water",
		"near_water 旧行为转换语义错误"
	)
	var legacy_avoid_snow: Array[Dictionary] = registry.behaviors_for_species({
		"behavior": "avoid_snow",
	})
	_expect(
		String(legacy_avoid_snow[0].get("type", "")) == "avoid_tag",
		"avoid_snow 旧行为转换语义错误"
	)
	var legacy_prefer_snow: Array[Dictionary] = registry.behaviors_for_species({
		"behaviors": ["prefer_snow"],
	})
	_expect(
		String(legacy_prefer_snow[0].get("type", "")) == "prefer_tag",
		"behaviors 数组中的旧字符串没有转换"
	)
	_expect(
		registry.behaviors_for_species({"behavior": "wander"}).is_empty(),
		"wander 兼容转换不应添加无意义 scorer"
	)

	# Existing constraint fields are promoted during incremental migration.
	var promoted_stack: Array[Dictionary] = registry.behaviors_for_species({
		"behavior": "wander",
		"movement": {
			"allowed_surfaces": ["land"],
			"max_step_height": 1,
		},
	})
	_expect(promoted_stack.size() == 2, "旧 movement 约束没有提升到新行为栈")
	var compact_constraint_stack: Array[Dictionary] = registry.behaviors_for_species({
		"behaviors": [{
			"allowed_surfaces": ["land"],
			"max_step_height": 2,
		}],
	})
	_expect(
		compact_constraint_stack.size() == 2,
		"同一约束字典没有展开 allowed_surfaces 与 max_step_height"
	)
	var direct_center_context := context.duplicate(true)
	direct_center_context.erase("pack_members")
	direct_center_context["pack_center"] = Vector2.ZERO
	var direct_center_decision: Dictionary = registry.evaluate_species(
		species,
		candidate,
		direct_center_context
	)
	_expect(bool(direct_center_decision["allowed"]), "直接注入 pack_center 导致行为求值失败")

	# A completely new scorer is a separate script registered at runtime. The
	# registry source has no knowledge of `season_affinity`.
	_expect(not registry.has_scorer(&"season_affinity"), "自定义类型意外成为内置行为")
	_expect(
		registry.register_scorer(&"season_affinity", CustomAnimalBehaviorScorer),
		"自定义 scorer Script 注册失败"
	)
	_expect(
		not registry.register_scorer(&"season_affinity", CustomAnimalBehaviorScorer),
		"重复注册在未 replace 时覆盖了 scorer"
	)
	var custom_decision: Dictionary = registry.evaluate_species(
		{
			"behaviors": [{
				"type": "season_affinity",
				"season": "spring",
				"tag": "meadow",
				"weight": 7.0,
			}],
		},
		candidate,
		{"season": "spring"}
	)
	_expect(bool(custom_decision["allowed"]), "注册后的自定义行为被当成未知类型")
	_expect(
		is_equal_approx(float(custom_decision["score"]), 7.0),
		"自定义 scorer 没有贡献分数"
	)
	_expect(
		bool(custom_decision["state"].get("custom_scorer_ran", false)),
		"自定义 scorer state 没有合并"
	)

	var unknown_decision: Dictionary = AnimalBehaviorRegistry.new(false).evaluate_stack(
		[{"type": "unregistered_behavior"}],
		candidate,
		{}
	)
	_expect(not bool(unknown_decision["allowed"]), "未知行为被静默忽略")
	_expect(
		"unknown_behavior:unregistered_behavior" in unknown_decision["errors"],
		"未知行为缺少配置错误"
	)

	if failures.is_empty():
		print("ANIMAL_BEHAVIOR_REGISTRY_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
