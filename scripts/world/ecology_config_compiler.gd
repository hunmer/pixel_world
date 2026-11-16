class_name EcologyConfigCompiler
extends RefCounted

## ecology_config_compiler.gd — 职责：把 legacy 形状的生态运行时配置按配置域
## （version/height/noise/flora/regions/climate/species/ecosystems/pool_selection）
## 编译并校验为 main.gd 消费的扁平字段集。纯静态函数集：只读输入字典、
## 不触碰节点状态；noise_fields/species 等容器保持原引用（不拷贝、不改顺序），
## 编译结果与 main.gd 历史内联实现逐字段一致（terrain_generation SHA-256 护栏）。

const EcologyConfigValidatorScript = preload("res://scripts/world/ecology_config_validator.gd")


## 编译 generation 域 + species 引用（原 _compile_ecosystem_config 前半）。
## defaults 为调用方当前字段值，作为配置缺省回退（保持历史回退语义）。
## 返回 {"ok": bool, "error": String, "values": {...}}；失败时 error 为单条报错文案。
static func compile_generation(
	config: Dictionary,
	defaults: Dictionary,
	flora_layer_ids: Array,
	landform_id_to_type: Dictionary
) -> Dictionary:
	var result := {"ok": false, "error": "", "values": {}}
	if not _check_version(config, result):
		return result
	var generation: Dictionary = config.get("generation", {})
	if not _compile_height(generation, defaults, result):
		return result
	if not _compile_noise(generation, defaults, result):
		return result
	if not _compile_flora_layers(generation, defaults, flora_layer_ids, result):
		return result
	if not _compile_regions(generation, defaults, landform_id_to_type, result):
		return result
	if not _compile_climate(generation, defaults, result):
		return result
	if not _compile_species(config, result):
		return result
	result["ok"] = true
	return result


## 编译 ecosystems / default_ecosystem / pool_selection 域（原函数后半）。
## 返回 {"ok": bool, "error": String, "values": {...}}。
static func compile_ecosystems(config: Dictionary) -> Dictionary:
	var result := {"ok": false, "error": "", "values": {}}
	var values: Dictionary = result["values"]
	var ecosystems_by_id := {}
	var ecosystem_order: Array[Dictionary] = []
	for ecosystem_value in config.get("ecosystems", []):
		var ecosystem: Dictionary = ecosystem_value
		var ecosystem_id := String(ecosystem.get("id", ""))
		if ecosystem_id.is_empty() or ecosystems_by_id.has(ecosystem_id):
			result["error"] = "生态 id 为空或重复: " + ecosystem_id
			return result
		ecosystems_by_id[ecosystem_id] = ecosystem
		ecosystem_order.append(ecosystem)
	if ecosystem_order.is_empty():
		result["error"] = "生态配置至少需要一个 ecosystem"
		return result
	var default_ecosystem_id := String(config.get("default_ecosystem", ""))
	if default_ecosystem_id.is_empty() or not ecosystems_by_id.has(default_ecosystem_id):
		result["error"] = "default_ecosystem 必须引用已定义的生态: " + default_ecosystem_id
		return result
	var dominant_species_chance := float(
		(config.get("pool_selection", {}) as Dictionary).get("dominant_chance", 0.8)
	)
	if dominant_species_chance < 0.0 or dominant_species_chance > 1.0:
		result["error"] = "pool_selection.dominant_chance 必须在 0..1"
		return result
	values["ecosystems_by_id"] = ecosystems_by_id
	values["ecosystem_order"] = ecosystem_order
	values["default_ecosystem_id"] = default_ecosystem_id
	values["dominant_species_chance"] = dominant_species_chance
	result["ok"] = true
	return result


static func _check_version(config: Dictionary, result: Dictionary) -> bool:
	if int(config.get("version", 0)) != 1:
		result["error"] = "不支持的生态配置版本: %s" % config.get("version", null)
		return false
	return true


static func _compile_height(generation: Dictionary, defaults: Dictionary, result: Dictionary) -> bool:
	var values: Dictionary = result["values"]
	var height: Dictionary = generation.get("height", {})
	values["rock_level"] = int(height.get("rock_level", defaults["rock_level"]))
	values["peak_max"] = int(height.get("peak_extra_levels", defaults["peak_max"]))
	values["sea_threshold"] = float(height.get("sea_threshold", defaults["sea_threshold"]))
	values["mountain_threshold"] = float(
		height.get("mountain_threshold", defaults["mountain_threshold"])
	)
	values["terrace_period"] = float(height.get("terrace_period", defaults["terrace_period"]))
	if (
		values["rock_level"] < 0
		or values["peak_max"] < 0
		or values["sea_threshold"] <= 0.0
		or values["sea_threshold"] >= 1.0
		or values["mountain_threshold"] <= values["sea_threshold"]
		or values["mountain_threshold"] >= 1.0
		or values["terrace_period"] <= 0.0
	):
		result["error"] = "generation.height 的范围无效"
		return false
	return true


static func _compile_noise(generation: Dictionary, defaults: Dictionary, result: Dictionary) -> bool:
	var values: Dictionary = result["values"]
	var noise: Dictionary = generation.get("noise", {})
	var noise_type_name := String(noise.get("type", "perlin")).to_lower()
	if noise_type_name not in ["perlin", "simplex", "simplex_smooth", "value", "value_cubic"]:
		result["error"] = "未知 noise type: " + noise_type_name
		return false
	var fractal_type_name := String(noise.get("fractal", "fbm")).to_lower()
	if fractal_type_name not in ["fbm", "ridged", "ping_pong"]:
		result["error"] = "未知 fractal type: " + fractal_type_name
		return false
	values["noise_type"] = EcologyConfigValidatorScript.noise_type_from_name(noise_type_name)
	values["fractal_type"] = EcologyConfigValidatorScript.fractal_type_from_name(fractal_type_name)
	values["noise_octaves"] = int(noise.get("octaves", defaults["noise_octaves"]))
	if values["noise_octaves"] <= 0:
		result["error"] = "noise.octaves 必须大于 0"
		return false
	var noise_fields: Dictionary = noise.get("fields", {})
	for field_id in noise_fields:
		var field: Dictionary = noise_fields[field_id]
		if float(field.get("frequency", 0.0)) <= 0.0:
			result["error"] = "noise field frequency 必须大于 0: " + field_id
			return false
		if int(field.get("octaves", values["noise_octaves"])) <= 0:
			result["error"] = "noise field octaves 必须大于 0: " + field_id
			return false
	values["noise_fields"] = noise_fields
	return true


static func _compile_flora_layers(
	generation: Dictionary,
	defaults: Dictionary,
	flora_layer_ids: Array,
	result: Dictionary
) -> bool:
	var values: Dictionary = result["values"]
	var flora_generation_value: Variant = generation.get("flora", {})
	if not flora_generation_value is Dictionary:
		result["error"] = "generation.flora 必须是 Dictionary"
		return false
	var flora_generation: Dictionary = flora_generation_value
	values["flora_conflict_seed"] = int(
		flora_generation.get("conflict_seed", defaults["flora_conflict_seed"])
	)
	var flora_layers_value: Variant = flora_generation.get("layers", {})
	if not flora_layers_value is Dictionary:
		result["error"] = "generation.flora.layers 必须是 Dictionary"
		return false
	var flora_layer_configs: Dictionary = flora_layers_value
	for configured_layer_id in flora_layer_configs:
		if String(configured_layer_id) not in flora_layer_ids:
			result["error"] = "generation.flora.layers 包含未知层: " + String(configured_layer_id)
			return false
	var noise_fields: Dictionary = result["values"]["noise_fields"]
	for layer_id in flora_layer_ids:
		if not _check_flora_layer(flora_layer_configs, String(layer_id), noise_fields, result):
			return false
	values["flora_layer_configs"] = flora_layer_configs
	return true


static func _check_flora_layer(
	flora_layer_configs: Dictionary,
	layer_id: String,
	noise_fields: Dictionary,
	result: Dictionary
) -> bool:
	if not flora_layer_configs.has(layer_id):
		result["error"] = "generation.flora.layers 缺少层: " + layer_id
		return false
	var layer_value: Variant = flora_layer_configs[layer_id]
	if not layer_value is Dictionary:
		result["error"] = "flora layer 必须是 Dictionary: " + layer_id
		return false
	var layer: Dictionary = layer_value
	var noise_field_id := String(layer.get("noise_field", ""))
	if (
		noise_field_id.is_empty()
		or not noise_fields.has(noise_field_id)
	):
		result["error"] = "flora layer 引用了未知 noise field [%s]: %s" % [layer_id, noise_field_id]
		return false
	var default_noise_above := float(layer.get("default_noise_above", 0.0))
	if default_noise_above < -1.0 or default_noise_above > 1.0:
		result["error"] = "flora layer default_noise_above 必须在 -1..1: " + layer_id
		return false
	var layer_dominant_chance := float(layer.get("dominant_chance", 0.8))
	if layer_dominant_chance < 0.0 or layer_dominant_chance > 1.0:
		result["error"] = "flora layer dominant_chance 必须在 0..1: " + layer_id
		return false
	return true


static func _compile_regions(
	generation: Dictionary,
	defaults: Dictionary,
	landform_id_to_type: Dictionary,
	result: Dictionary
) -> bool:
	var values: Dictionary = result["values"]
	var regions: Dictionary = generation.get("regions", {})
	values["region_cell_size"] = float(regions.get("cell_size", defaults["region_cell_size"]))
	values["region_jitter"] = float(regions.get("jitter", defaults["region_jitter"]))
	values["region_blend_width"] = float(
		regions.get("blend_width", defaults["region_blend_width"])
	)
	if (
		values["region_cell_size"] <= 0.0
		or values["region_blend_width"] <= 0.0
		or values["region_jitter"] < 0.0
	):
		result["error"] = "generation.regions 的范围无效"
		return false
	if not _compile_landforms(regions, landform_id_to_type, result):
		return false
	return true


static func _compile_landforms(
	regions: Dictionary,
	landform_id_to_type: Dictionary,
	result: Dictionary
) -> bool:
	var values: Dictionary = result["values"]
	var landform_count := landform_id_to_type.size()
	var landform_configs: Array[Dictionary] = []
	var landform_ids: Array[String] = []
	var landform_names: Array[String] = []
	landform_configs.resize(landform_count)
	landform_ids.resize(landform_count)
	landform_names.resize(landform_count)
	for i in landform_count:
		landform_configs[i] = {}
		landform_ids[i] = ""
		landform_names[i] = ""
	var landform_order: Array[int] = []
	var landform_total_weight := 0.0
	var seen_landforms := {}
	var landforms: Array = regions.get("landforms", [])
	for profile_value in landforms:
		var profile: Dictionary = profile_value
		var profile_id := String(profile.get("id", ""))
		if profile_id.is_empty():
			result["error"] = "landform id 不能为空"
			return false
		if seen_landforms.has(profile_id):
			result["error"] = "重复的 landform id: " + profile_id
			return false
		seen_landforms[profile_id] = true
		var terrain: Dictionary = profile.get("terrain", {})
		var profile_weight := float(profile.get("weight", 0.0))
		if profile_weight <= 0.0:
			result["error"] = "landform weight 必须大于 0: " + profile_id
			return false
		var compiled := {
			"offset": float(terrain.get("offset", 0.0)),
			"amp": float(terrain.get("amplitude", 1.0)),
			"ridge": float(terrain.get("ridge", 0.0)),
			"steep": float(terrain.get("underwater_steepness", 1.0)),
			"peak": float(terrain.get("peak", 0.0)),
			"terrace": float(terrain.get("terrace", 0.0)),
			"weight": profile_weight,
		}
		landform_total_weight += float(compiled["weight"])
		# 旧 enum 只作为现有规则/测试的适配边界；新 ID 完整保留在 TerrainSampler。
		if landform_id_to_type.has(profile_id):
			var landform_type: int = landform_id_to_type[profile_id]
			landform_configs[landform_type] = compiled
			landform_ids[landform_type] = profile_id
			landform_names[landform_type] = String(profile.get("name_zh", profile_id))
			landform_order.append(landform_type)
	for required_landform_id in landform_id_to_type:
		if not seen_landforms.has(required_landform_id):
			result["error"] = "生态配置缺少 legacy landform: " + String(required_landform_id)
			return false
	if landform_total_weight <= 0.0:
		result["error"] = "landform 总权重必须大于 0"
		return false
	values["landform_configs"] = landform_configs
	values["landform_ids"] = landform_ids
	values["landform_names"] = landform_names
	values["landform_order"] = landform_order
	values["landform_total_weight"] = landform_total_weight
	return true


static func _compile_climate(generation: Dictionary, defaults: Dictionary, result: Dictionary) -> bool:
	var values: Dictionary = result["values"]
	var climate: Dictionary = generation.get("climate", {})
	var snow: Dictionary = climate.get("snow", {})
	values["snow_base_level"] = int(snow.get("base_level", defaults["snow_base_level"]))
	values["snow_temperature_level_scale"] = float(
		snow.get("temperature_level_scale", defaults["snow_temperature_level_scale"])
	)
	return true


static func _compile_species(config: Dictionary, result: Dictionary) -> bool:
	var values: Dictionary = result["values"]
	var species: Dictionary = config.get("species", {})
	values["plant_species"] = species.get("plants", {})
	values["animal_species"] = species.get("animals", {})
	values["ambient_species"] = species.get("ambient", {})
	return true
