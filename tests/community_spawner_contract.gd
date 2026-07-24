extends SceneTree

const CommunitySpawner = preload("res://scripts/ecology/community_spawner.gd")
const MemberComposer = preload("res://scripts/ecology/member_composer.gd")

var failures: Array[String] = []
var _random_seed := 41


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _rand01(position: Vector2i, stream_key: String) -> float:
	var digest := "%d/%d/%d/%s" % [
		_random_seed,
		position.x,
		position.y,
		stream_key,
	]
	var prefix := digest.sha256_text().substr(0, 8)
	return float(prefix.hex_to_int() & 0x7fffffff) / float(0x80000000)


func _always_valid(_position: Vector2i) -> bool:
	return true


func _never_valid(_position: Vector2i) -> bool:
	return false


func _run() -> void:
	var patch_definition := {
		"id": "wetland_surface_patch",
		"kind": "flora",
		"distribution": {
			"strategy": "patch",
			"anchor_spacing": 11,
			"anchor_jitter": 0.55,
			"radius": 2,
			"chance": 1.0,
			"count": [5, 5],
		},
		"members": [
			{"species": "surface_leaf", "weight": 4.0},
			{"species": "surface_flower", "weight": 1.0},
		],
	}
	var first_patch := CommunitySpawner.plan_community(
		patch_definition,
		Vector2i(3, -2),
		_rand01,
		_always_valid,
		_always_valid
	)
	var second_patch := CommunitySpawner.plan_community(
		patch_definition,
		Vector2i(3, -2),
		_rand01,
		_always_valid,
		_always_valid
	)
	_expect(bool(first_patch["active"]), "patch 没有生成")
	_expect(first_patch == second_patch, "相同 seed 的群落规划不确定")
	_expect(first_patch["cells"].size() == 5, "patch 没有产生配置数量的多格")
	var unique_patch_cells := {}
	for cell: Vector2i in first_patch["cells"]:
		unique_patch_cells[cell] = true
		_expect(
			cell.distance_squared_to(first_patch["anchor"]) <= 4,
			"patch 成员越过配置半径"
		)
	_expect(unique_patch_cells.size() == 5, "patch 包含重复地块")
	_expect(first_patch["members"].size() == first_patch["cells"].size(), "flora 成员没有逐格组合")
	for member: Dictionary in first_patch["members"]:
		_expect(
			String(member["species"]) in ["surface_leaf", "surface_flower"],
			"weighted flora 选择了未配置物种"
		)

	# Weighted flora is generic and can be sampled independently of placement.
	var sample_positions: Array[Vector2i] = []
	for x in 80:
		sample_positions.append(Vector2i(x, 7))
	var flora_sample := MemberComposer.compose_weighted_flora(
		patch_definition["members"],
		sample_positions,
		_rand01,
		"weighted-contract"
	)
	var sampled_species := {}
	for member: Dictionary in flora_sample:
		sampled_species[String(member["species"])] = true
	_expect(sampled_species.has("surface_leaf"), "weighted flora 未选择高权重成员")
	_expect(sampled_species.has("surface_flower"), "weighted flora 未选择低权重成员")

	var fauna_specs := [
		{
			"species": "variant_companion",
			"count": [1, 1],
			"chance": 1.0,
			"consumes_population": true,
		},
		{
			"species": "ambient_companion",
			"count": [2, 2],
			"chance": 1.0,
			"consumes_population": false,
		},
		{
			"species": "primary_species",
			"fill_remaining": true,
			"weight": 1.0,
			"consumes_population": true,
		},
	]
	var composition := MemberComposer.compose_fauna(
		fauna_specs,
		[8, 8],
		Vector2i(12, 9),
		_rand01,
		"fauna-contract"
	)
	_expect(bool(composition["complete"]), "fauna 组合没有填满人口预算")
	_expect(int(composition["target_population"]) == 8, "fauna 目标数量错误")
	_expect(int(composition["consumed_population"]) == 8, "consumes_population 总数不守恒")
	_expect(int(composition["remaining_population"]) == 0, "fauna 组合仍有未分配人口")
	_expect(composition["members"].size() == 10, "非人口伴生成员被错误计入目标数量")
	var fauna_counts := {}
	for member: Dictionary in composition["members"]:
		var species := String(member["species"])
		fauna_counts[species] = int(fauna_counts.get(species, 0)) + 1
	_expect(int(fauna_counts.get("variant_companion", 0)) == 1, "固定 fauna 成员数量错误")
	_expect(int(fauna_counts.get("ambient_companion", 0)) == 2, "非人口 fauna 成员数量错误")
	_expect(int(fauna_counts.get("primary_species", 0)) == 7, "fill_remaining 没有守恒填充")

	var fish_school_composition := MemberComposer.compose_fauna(
		[
			{"species": "goldfish", "fill_remaining": true, "weight": 4.0},
			{"species": "blue_goldfish", "fill_remaining": true, "weight": 1.0},
			{"species": "calico_goldfish", "fill_remaining": true, "weight": 1.0},
		],
		[5, 5],
		Vector2i(4, 9),
		_rand01,
		"fish-school-contract",
		true
	)
	var school_species := {}
	for member: Dictionary in fish_school_composition["members"]:
		school_species[String(member["species"])] = true
	_expect(bool(fish_school_composition["complete"]), "单鱼种鱼群没有填满数量")
	_expect(school_species.size() == 1, "同一鱼群混入了多种随机鱼类")

	var social_definition := {
		"id": "generic_social_group",
		"kind": "fauna",
		"distribution": {
			"strategy": "social_group",
			"anchor_spacing": 19,
			"anchor_jitter": 0.4,
			"radius": 3,
			"chance": 1.0,
			"count": [8, 8],
		},
		"members": fauna_specs.slice(0, 1) + [fauna_specs[2]],
	}
	var social_group := CommunitySpawner.generate(
		social_definition,
		Vector2i(-1, 4),
		_rand01,
		_always_valid,
		_always_valid
	)
	_expect(bool(social_group["active"]), "social_group 没有生成")
	_expect(social_group["members"].size() == 8, "social_group 组合总数错误")
	_expect(social_group["cells"].size() == 8, "social_group 没有为每个成员分配位置")

	var solitary_definition := {
		"id": "generic_solitary",
		"kind": "fauna",
		"strategy": "solitary",
		"anchor_spacing": 23,
		"anchor_jitter": 0.8,
		"radius": 0,
		"chance": 1.0,
		"members": [{"species": "solitary_species", "fill_remaining": true}],
	}
	var solitary := CommunitySpawner.generate(
		solitary_definition,
		Vector2i(2, 2),
		_rand01,
		_always_valid,
		_always_valid
	)
	_expect(bool(solitary["active"]), "solitary 没有生成")
	_expect(solitary["members"].size() == 1, "solitary 不是单个成员")

	var scatter_definition := patch_definition.duplicate(true)
	scatter_definition["id"] = "generic_scatter"
	scatter_definition["distribution"]["strategy"] = "scatter"
	scatter_definition["distribution"]["count"] = [3, 3]
	var scatter := CommunitySpawner.generate(
		scatter_definition,
		Vector2i(1, 1),
		_rand01,
		_always_valid,
		_always_valid
	)
	_expect(bool(scatter["active"]), "scatter 没有生成")
	_expect(scatter["cells"].size() == 3, "scatter 数量错误")

	var chance_miss := patch_definition.duplicate(true)
	chance_miss["distribution"]["chance"] = 0.0
	var inactive := CommunitySpawner.generate(
		chance_miss,
		Vector2i.ZERO,
		_rand01,
		_always_valid,
		_always_valid
	)
	_expect(not bool(inactive["active"]), "chance=0 的群落仍然生成")
	_expect(String(inactive["reason"]) == "chance_miss", "chance miss 缺少明确原因")
	var invalid_habitat := CommunitySpawner.generate(
		patch_definition,
		Vector2i.ZERO,
		_rand01,
		_never_valid,
		_always_valid
	)
	_expect(not bool(invalid_habitat["active"]), "habitat predicate 未生效")
	var invalid_cells := CommunitySpawner.generate(
		patch_definition,
		Vector2i.ZERO,
		_rand01,
		_always_valid,
		_never_valid
	)
	_expect(not bool(invalid_cells["active"]), "cell validity predicate 未生效")
	_expect(
		String(invalid_cells["reason"]) == "insufficient_valid_cells",
		"cell validity 失败缺少明确原因"
	)

	var river_definition := social_definition.duplicate(true)
	river_definition["id"] = "river_school"
	river_definition["stream_key"] = "river-school"
	river_definition["distribution"]["anchor_search_radius"] = 4
	var original_river_anchor := CommunitySpawner.anchor_for_bucket(
		Vector2i.ZERO,
		19,
		0.4,
		_rand01,
		"river-school/anchor"
	)
	var river_cell := original_river_anchor + Vector2i(2, 0)
	var relocated_school := CommunitySpawner.generate(
		river_definition,
		Vector2i.ZERO,
		_rand01,
		func(cell: Vector2i) -> bool: return cell == river_cell,
		_always_valid
	)
	_expect(bool(relocated_school["active"]), "窄水域没有从领地锚点搜索到合法栖息地")
	_expect(relocated_school["anchor"] == river_cell, "水域群落没有使用最近的合法锚点")

	# Changing only the caller-owned seed must change at least the territory anchor.
	_random_seed = 42
	var changed_seed_patch := CommunitySpawner.generate(
		patch_definition,
		Vector2i(3, -2),
		_rand01,
		_always_valid,
		_always_valid
	)
	_expect(changed_seed_patch != first_patch, "不同 seed 仍得到完全相同的规划")

	if failures.is_empty():
		print("COMMUNITY_SPAWNER_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
