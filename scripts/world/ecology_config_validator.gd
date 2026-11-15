## ecology_config_validator.gd — 生态配置的结构校验（纯函数集）
## 从 main.gd 簇2 原样迁移：校验植物/动物/环境生物/ecosystem 规则与匹配遮蔽，
## 以及 noise type/fractal 名称到 FastNoiseLite 枚举的映射。
## 全部为静态纯函数：只读传入的配置字典，不持有状态、不回调 main.gd。

class_name EcologyConfigValidator
extends RefCounted


static func validate_ecosystem_config(
	plant_species: Dictionary,
	animal_species: Dictionary,
	ambient_species: Dictionary,
	ecosystem_order: Array,
	flora_layer_configs: Dictionary,
	flora_layer_ids: Array
) -> bool:
	for plant_id in plant_species:
		var plant: Dictionary = plant_species[plant_id]
		var layer_id := String(plant.get("layer", ""))
		if layer_id not in flora_layer_ids:
			push_error("植物缺少有效 layer [%s]: %s" % [plant_id, layer_id])
			return false
		var texture_path := String(plant.get("texture", ""))
		if texture_path.is_empty() or not ResourceLoader.exists(texture_path):
			push_error("植物资源不存在 [%s]: %s" % [plant_id, texture_path])
			return false
		var habitat_value: Variant = plant.get("habitat", {})
		if not habitat_value is Dictionary:
			push_error("植物 habitat 必须是 Dictionary [%s]" % plant_id)
			return false
		var habitat: Dictionary = habitat_value
		if not habitat.is_empty():
			var near_layer := String(habitat.get("near_flora_layer", ""))
			var radius := int(habitat.get("radius", 0))
			var fallback_species := String(habitat.get("fallback_species", ""))
			if near_layer not in flora_layer_ids or radius < 1 or radius > 8:
				push_error("植物 habitat 邻近层或半径无效 [%s]" % plant_id)
				return false
			if not plant_species.has(fallback_species):
				push_error("植物 habitat fallback 不存在 [%s]: %s" % [
					plant_id, fallback_species
				])
				return false
			var fallback: Dictionary = plant_species[fallback_species]
			if String(fallback.get("layer", "")) != layer_id:
				push_error("植物 habitat fallback 必须与原物种同层 [%s]" % plant_id)
				return false
			if not (fallback.get("habitat", {}) as Dictionary).is_empty():
				push_error("植物 habitat fallback 不能继续声明 habitat [%s]" % plant_id)
				return false
	for animal_id in animal_species:
		var animal: Dictionary = animal_species[animal_id]
		var directory := String(animal.get("directory", ""))
		var actions: Dictionary = animal.get("actions", {})
		if actions.is_empty():
			push_error("动物缺少 actions: " + String(animal_id))
			return false
		for action_id in actions:
			var action: Dictionary = actions[action_id]
			var action_file := String(action.get("file", ""))
			var texture_path := directory.path_join(action_file)
			if directory.is_empty() or action_file.is_empty():
				push_error("动物动作缺少目录或文件 [%s/%s]" % [animal_id, action_id])
				return false
			if not ResourceLoader.exists(texture_path):
				push_error("动物动作资源不存在 [%s/%s]: %s" % [animal_id, action_id, texture_path])
				return false
			if float(action.get("fps", 1.0)) <= 0.0:
				push_error("动物动作 fps 必须大于 0 [%s/%s]" % [animal_id, action_id])
				return false
			if action.has("frame_size"):
				var frame_size_value: Variant = action["frame_size"]
				if (
					not frame_size_value is Array
					or frame_size_value.size() != 2
					or int(frame_size_value[0]) <= 0
					or int(frame_size_value[1]) <= 0
					or int(action.get("columns", 0)) <= 0
					or int(action.get("frames", 0)) <= 0
				):
					push_error("动物图集参数无效 [%s/%s]" % [animal_id, action_id])
					return false
				var frame_width := int(frame_size_value[0])
				var frame_height := int(frame_size_value[1])
				var columns := int(action["columns"])
				var frame_count := int(action["frames"])
				var rows := ceili(frame_count / float(columns))
				var texture: Texture2D = load(texture_path)
				if columns * frame_width > texture.get_width() or rows * frame_height > texture.get_height():
					push_error("动物图集范围超出图片 [%s/%s]" % [animal_id, action_id])
					return false
		var behavior := String(animal.get("behavior", "wander"))
		if (
			not animal.has("behaviors")
			and behavior not in ["wander", "near_water", "avoid_snow", "prefer_snow"]
		):
			push_error("未知动物行为 [%s]: %s" % [animal_id, behavior])
			return false
		var foot_offset_y := float(animal.get("foot_offset_y", 0.0))
		if foot_offset_y < 0.0 or foot_offset_y > 128.0:
			push_error("动物 foot_offset_y 必须在 0..128 [%s]" % animal_id)
			return false
		var movement: Dictionary = animal.get("movement", {})
		var idle_action := String(movement.get("idle_action", "idle"))
		var move_action := String(movement.get("move_action", idle_action))
		if not actions.has(idle_action) or not actions.has(move_action):
			push_error("动物 movement 引用了未知动作 [%s]: %s / %s" % [animal_id, idle_action, move_action])
			return false
		if float(movement.get("duration", 0.0)) <= 0.0:
			push_error("动物 movement.duration 必须大于 0 [%s]" % animal_id)
			return false
		if (
			movement.has("move_steps")
			and not numeric_range_is_valid(movement["move_steps"], 1.0, true)
		):
			push_error("动物 move_steps 必须是递增正整数范围 [%s]" % animal_id)
			return false
		if (
			movement.has("step_pause_seconds")
			and not numeric_range_is_valid(movement["step_pause_seconds"], 0.0, false)
		):
			push_error("动物 step_pause_seconds 必须是非负递增范围 [%s]" % animal_id)
			return false
		if movement.has("sort_switch_progress"):
			var switch_progress := float(movement["sort_switch_progress"])
			if switch_progress < 0.0 or switch_progress > 1.0:
				push_error("动物 sort_switch_progress 必须在 0..1 [%s]" % animal_id)
				return false
	for ambient_id in ambient_species:
		var ambient: Dictionary = ambient_species[ambient_id]
		var cluster_size: Variant = ambient.get("cluster_size", [1, 1])
		if (
			not cluster_size is Array
			or cluster_size.size() != 2
			or int(cluster_size[0]) <= 0
			or int(cluster_size[1]) < int(cluster_size[0])
		):
			push_error("环境生物 cluster_size 无效 [%s]" % ambient_id)
			return false
		if int(ambient.get("max_visible", 1)) <= 0:
			push_error("环境生物 max_visible 必须大于 0 [%s]" % ambient_id)
			return false
		if int(ambient.get("max_lights", 0)) < 0:
			push_error("环境生物 max_lights 不能小于 0 [%s]" % ambient_id)
			return false
	for ecosystem in ecosystem_order:
		var ecosystem_id := String(ecosystem["id"])
		var match_value: Variant = ecosystem.get("match", {})
		if not match_value is Dictionary:
			push_error("生态 match 必须是 Dictionary [%s]" % ecosystem_id)
			return false
		if not validate_ecosystem_match(match_value, ecosystem_id):
			return false
		var seen_flora_pool_ids := {}
		var seen_fauna_pool_ids := {}
		for rule_kind in ["flora", "fauna", "ambient"]:
			var rules_value: Variant = ecosystem.get(rule_kind, [])
			if not rules_value is Array:
				push_error("生态规则必须是数组 [%s/%s]" % [ecosystem_id, rule_kind])
				return false
			var catalog: Dictionary
			match rule_kind:
				"flora":
					catalog = plant_species
				"fauna":
					catalog = animal_species
				_:
					catalog = ambient_species
			for rule_value in rules_value:
				if not rule_value is Dictionary:
					push_error("生态规则必须是 Dictionary [%s/%s]" % [ecosystem_id, rule_kind])
					return false
				var rule: Dictionary = rule_value
				if not chance_value_is_valid(rule.get("chance", 0.0)):
					push_error("生态生成概率必须在 0..1 [%s/%s]" % [ecosystem_id, rule_kind])
					return false
				var pool_value: Variant = rule.get("species", [])
				if not pool_value is Array or pool_value.is_empty():
					push_error("生态物种池不能为空 [%s/%s]" % [ecosystem_id, rule_kind])
					return false
				for species_id_value in pool_value:
					var species_id := String(species_id_value)
					if not catalog.has(species_id):
						push_error("生态引用了未知物种 [%s/%s]: %s" % [ecosystem_id, rule_kind, species_id])
						return false
				if rule_kind == "flora":
					var layer_id := String(rule.get("layer", ""))
					if layer_id not in flora_layer_ids:
						push_error("flora rule 缺少有效 layer [%s]: %s" % [ecosystem_id, layer_id])
						return false
					var pool_id := String(rule.get("pool_id", ""))
					if pool_id.is_empty() or seen_flora_pool_ids.has(pool_id):
						push_error("flora pool_id 为空或重复 [%s]: %s" % [ecosystem_id, pool_id])
						return false
					seen_flora_pool_ids[pool_id] = true
					for species_id_value in pool_value:
						var species_id := String(species_id_value)
						var plant: Dictionary = plant_species[species_id]
						if String(plant.get("layer", "")) != layer_id:
							push_error(
								"flora rule 与物种 layer 不一致 [%s/%s]: %s"
								% [ecosystem_id, layer_id, species_id]
							)
							return false
					var layer: Dictionary = flora_layer_configs[layer_id]
					var noise_above := float(
						rule.get("noise_above", layer.get("default_noise_above", 0.0))
					)
					if noise_above < -1.0 or noise_above > 1.0:
						push_error("flora noise_above 必须在 -1..1 [%s/%s]" % [ecosystem_id, pool_id])
						return false
					if float(rule.get("conflict_weight", 1.0)) <= 0.0:
						push_error("flora conflict_weight 必须大于 0 [%s/%s]" % [ecosystem_id, pool_id])
						return false
					var placement := String(rule.get("placement", "ground"))
					if placement not in ["ground", "lakebed", "water_surface"]:
						push_error("未知植物放置方式 [%s]: %s" % [ecosystem_id, placement])
						return false
				elif rule_kind == "fauna":
					var fauna_pool_id := String(rule.get("pool_id", ""))
					if fauna_pool_id.is_empty() or seen_fauna_pool_ids.has(fauna_pool_id):
						push_error("fauna pool_id 为空或重复 [%s]: %s" % [ecosystem_id, fauna_pool_id])
						return false
					seen_fauna_pool_ids[fauna_pool_id] = true
					if not validate_fauna_distribution(rule, ecosystem_id, fauna_pool_id, animal_species):
						return false
	for later_index in range(1, ecosystem_order.size()):
		var later_ecosystem: Dictionary = ecosystem_order[later_index]
		var later_match: Dictionary = later_ecosystem.get("match", {})
		for earlier_index in later_index:
			var earlier_ecosystem: Dictionary = ecosystem_order[earlier_index]
			var earlier_match: Dictionary = earlier_ecosystem.get("match", {})
			if ecosystem_match_subsumes(earlier_match, later_match):
				push_error(
					"生态 [%s] 被前面的规则 [%s] 完全遮蔽"
					% [String(later_ecosystem["id"]), String(earlier_ecosystem["id"])]
				)
				return false
	return true


static func validate_fauna_distribution(
	rule: Dictionary,
	ecosystem_id: String,
	pool_id: String,
	animal_species: Dictionary
) -> bool:
	var distribution_value: Variant = rule.get("distribution", {})
	if not distribution_value is Dictionary:
		push_error("fauna distribution 必须是 Dictionary [%s/%s]" % [ecosystem_id, pool_id])
		return false
	var distribution: Dictionary = distribution_value
	if rule.has("only_if_flora_missed") and not rule["only_if_flora_missed"] is bool:
		push_error("fauna only_if_flora_missed 必须是 bool [%s/%s]" % [ecosystem_id, pool_id])
		return false
	if int(distribution.get("anchor_spacing", 0)) <= 0:
		push_error("fauna anchor_spacing 必须大于 0 [%s/%s]" % [ecosystem_id, pool_id])
		return false
	var anchor_jitter := float(distribution.get("anchor_jitter", 1.0))
	if anchor_jitter < 0.0 or anchor_jitter > 1.0:
		push_error("fauna anchor_jitter 必须在 0..1 [%s/%s]" % [ecosystem_id, pool_id])
		return false
	if not numeric_range_is_valid(distribution.get("count", []), 1.0, true):
		push_error("fauna count 必须是递增正整数范围 [%s/%s]" % [ecosystem_id, pool_id])
		return false
	if int(distribution.get("radius", -1)) < 0:
		push_error("fauna radius 不能小于 0 [%s/%s]" % [ecosystem_id, pool_id])
		return false
	if float(distribution.get("social_radius", 0.0)) < 0.0:
		push_error("fauna social_radius 不能小于 0 [%s/%s]" % [ecosystem_id, pool_id])
		return false
	if int(distribution.get("requires_water_within", 0)) < 0:
		push_error("fauna requires_water_within 不能小于 0 [%s/%s]" % [ecosystem_id, pool_id])
		return false
	if distribution.has("same_ecosystem") and not distribution["same_ecosystem"] is bool:
		push_error("fauna same_ecosystem 必须是 bool [%s/%s]" % [ecosystem_id, pool_id])
		return false
	var substitution_value: Variant = distribution.get("substitution", {})
	if substitution_value is Dictionary and not substitution_value.is_empty():
		var substitution: Dictionary = substitution_value
		var substitute_species := String(substitution.get("species", ""))
		if not animal_species.has(substitute_species):
			push_error("fauna substitution 引用了未知动物 [%s/%s]: %s" % [
				ecosystem_id, pool_id, substitute_species
			])
			return false
		if not chance_value_is_valid(substitution.get("chance", -1.0)):
			push_error("fauna substitution chance 无效 [%s/%s]" % [ecosystem_id, pool_id])
			return false
		if int(substitution.get("max_count", 0)) <= 0:
			push_error("fauna substitution max_count 必须大于 0 [%s/%s]" % [ecosystem_id, pool_id])
			return false
	elif not substitution_value is Dictionary:
		push_error("fauna substitution 必须是 Dictionary [%s/%s]" % [ecosystem_id, pool_id])
		return false
	return true


static func validate_ecosystem_match(match_rule: Dictionary, ecosystem_id: String) -> bool:
	var allowed_keys := [
		"water",
		"shore",
		"biome",
		"landform",
		"minimum_level",
		"maximum_level",
	]
	for key_value in match_rule:
		var key := String(key_value)
		if key not in allowed_keys:
			push_error("生态 match 包含未知字段 [%s]: %s" % [ecosystem_id, key])
			return false
	for key in ["water", "shore"]:
		if match_rule.has(key) and not match_rule[key] is bool:
			push_error("生态 match.%s 必须是 bool [%s]" % [key, ecosystem_id])
			return false
	if match_rule.has("biome"):
		var biome_value: Variant = match_rule["biome"]
		var biome_ids: Array = biome_value if biome_value is Array else [biome_value]
		if biome_ids.is_empty():
			push_error("生态 match.biome 不能为空 [%s]" % ecosystem_id)
			return false
		for biome_id_value in biome_ids:
			if String(biome_id_value).is_empty():
				push_error("生态 match.biome 包含空 ID [%s]" % ecosystem_id)
				return false
	if match_rule.has("landform"):
		var landform_value: Variant = match_rule["landform"]
		var landform_ids: Array = landform_value if landform_value is Array else [landform_value]
		if landform_ids.is_empty():
			push_error("生态 match.landform 不能为空 [%s]" % ecosystem_id)
			return false
		for landform_id_value in landform_ids:
			if String(landform_id_value).is_empty():
				push_error("生态 match.landform 包含空 ID [%s]" % ecosystem_id)
				return false
	for key in ["minimum_level", "maximum_level"]:
		if match_rule.has(key) and not (match_rule[key] is int or match_rule[key] is float):
			push_error("生态 match.%s 必须是数字 [%s]" % [key, ecosystem_id])
			return false
	if (
		match_rule.has("minimum_level")
		and match_rule.has("maximum_level")
		and int(match_rule["minimum_level"]) > int(match_rule["maximum_level"])
	):
		push_error("生态 minimum_level 不能大于 maximum_level [%s]" % ecosystem_id)
		return false
	return true


## earlier 的匹配集合完全包含 later 时，later 永远不会被 first-match 选中。
static func ecosystem_match_subsumes(earlier: Dictionary, later: Dictionary) -> bool:
	for key in ["water", "shore", "biome"]:
		if earlier.has(key) and (not later.has(key) or earlier[key] != later[key]):
			return false
	if earlier.has("landform"):
		if not later.has("landform"):
			return false
		var earlier_value: Variant = earlier["landform"]
		var later_value: Variant = later["landform"]
		var earlier_ids: Array = earlier_value if earlier_value is Array else [earlier_value]
		var later_ids: Array = later_value if later_value is Array else [later_value]
		for landform_id in later_ids:
			if not earlier_ids.has(landform_id):
				return false
	if earlier.has("minimum_level"):
		if not later.has("minimum_level") or int(earlier["minimum_level"]) > int(later["minimum_level"]):
			return false
	if earlier.has("maximum_level"):
		if not later.has("maximum_level") or int(earlier["maximum_level"]) < int(later["maximum_level"]):
			return false
	return true


static func chance_value_is_valid(value: Variant) -> bool:
	if value is float or value is int:
		var chance := float(value)
		return chance >= 0.0 and chance <= 1.0
	if not value is Dictionary or value.is_empty():
		return false
	for chance_value in value.values():
		if not (chance_value is float or chance_value is int):
			return false
		var chance := float(chance_value)
		if chance < 0.0 or chance > 1.0:
			return false
	return true


static func numeric_range_is_valid(value: Variant, minimum: float, integers_only: bool) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for item in value:
		if not (item is float or item is int):
			return false
		var number := float(item)
		if number < minimum or (integers_only and not is_equal_approx(number, roundf(number))):
			return false
	return float(value[1]) >= float(value[0])


static func noise_type_from_name(value: String) -> int:
	match value.to_lower():
		"simplex":
			return FastNoiseLite.TYPE_SIMPLEX
		"simplex_smooth":
			return FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		"value":
			return FastNoiseLite.TYPE_VALUE
		"value_cubic":
			return FastNoiseLite.TYPE_VALUE_CUBIC
		_:
			return FastNoiseLite.TYPE_PERLIN


static func fractal_type_from_name(value: String) -> int:
	match value.to_lower():
		"ridged":
			return FastNoiseLite.FRACTAL_RIDGED
		"ping_pong":
			return FastNoiseLite.FRACTAL_PING_PONG
		_:
			return FastNoiseLite.FRACTAL_FBM
