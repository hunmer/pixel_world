class_name EcologyLegacyCodec
extends RefCounted

## ecology_legacy_codec.gd — 职责：迁移期 legacy 生态配置（单文件 ecosystems.json）的
## 解码回写与 legacy 规则域校验。legacy placement_seed / selection_seed_key 等字段是
## 存档/世界确定性契约，这里只做结构校验与位置搬移，绝不改写语义。
## 静态纯函数集：读取/合并/报错全部通过 EcologyRegistry 宿主完成，自身零状态。

const LEGACY_ROOT_FIELDS := [
	"version",
	"default_ecosystem",
	"generation",
	"species",
	"pool_selection",
	"ecosystems",
]
const LEGACY_ECOSYSTEM_FIELDS := ["id", "match", "flora", "fauna", "ambient"]
const FLORA_RULE_FIELDS := [
	"layer",
	"pool_id",
	"selection_seed_key",
	"species",
	"chance",
	"placement_seed",
	"max_water_depth",
	"placement",
	"render_priority",
	"noise_above",
	"conflict_weight",
]
const FAUNA_RULE_FIELDS := [
	"pool_id",
	"selection_seed_key",
	"species",
	"chance",
	"placement_seed",
	"only_if_flora_missed",
	"distribution",
]
const AMBIENT_RULE_FIELDS := [
	"pool_id",
	"selection_seed_key",
	"species",
	"chance",
	"placement_seed",
	"requires_ground_flora",
]
const FAUNA_SUBSTITUTION_FIELDS := ["species", "chance", "max_count"]


## Compatibility entry point for the current monolithic ecosystems.json.
## It adapts every legacy ecosystem to a biome plus a `legacy_bundle` community
## by writing through the host registry（语义与拆分前完全一致，仅位置搬移）。
static func load_into(host: EcologyRegistry, config_path: String) -> bool:
	host._reset()
	var legacy: Dictionary = host._read_json_object(config_path, "legacy ecosystem config")
	if legacy.is_empty() and not host._errors.is_empty():
		return false
	if not host._validate_version(legacy, config_path):
		return false
	if not host._reject_unknown_fields(legacy, LEGACY_ROOT_FIELDS, config_path, "legacy root"):
		return false

	_store_world(host, legacy, config_path)
	_store_species(host, legacy, config_path)
	_store_ecosystems(host, legacy, config_path)
	host._loaded_kinds["communities"] = true
	host._loaded_kinds["biomes"] = true

	if not host._errors.is_empty():
		return false
	host._validate_catalog(config_path)
	host._loaded = host._errors.is_empty()
	if host._loaded:
		host._legacy_original = host._deep_copy(legacy)
	return host._loaded


static func _store_world(host: EcologyRegistry, legacy: Dictionary, config_path: String) -> void:
	var default_biome_id := String(legacy.get("default_ecosystem", ""))
	host._catalog["world"] = {
		"default_biome_id": default_biome_id,
		"generation": host._deep_copy(legacy.get("generation", {})),
		"pool_selection": host._deep_copy(legacy.get("pool_selection", {})),
	}
	host._catalog["default_biome_id"] = default_biome_id
	host._catalog["source_paths"]["manifest"] = config_path
	host._catalog["source_paths"]["world"] = config_path
	host._loaded_kinds["world"] = true


static func _store_species(host: EcologyRegistry, legacy: Dictionary, config_path: String) -> void:
	var species_value: Variant = legacy.get("species", null)
	if not species_value is Dictionary:
		host._add_error(config_path, "legacy species must be a Dictionary")
	else:
		host._merge_species_payload(species_value, config_path)
	host._loaded_kinds["species"] = true


static func _store_ecosystems(host: EcologyRegistry, legacy: Dictionary, config_path: String) -> void:
	var ecosystems_value: Variant = legacy.get("ecosystems", null)
	if not ecosystems_value is Array:
		host._add_error(config_path, "legacy ecosystems must be an Array")
		return
	for index in (ecosystems_value as Array).size():
		_store_ecosystem(host, (ecosystems_value as Array)[index], index, config_path)


static func _store_ecosystem(
	host: EcologyRegistry,
	ecosystem_value: Variant,
	index: int,
	config_path: String
) -> void:
	if not ecosystem_value is Dictionary:
		host._add_error(config_path, "legacy ecosystems[%d] must be a Dictionary" % index)
		return
	var ecosystem: Dictionary = ecosystem_value
	if not host._reject_unknown_fields(
		ecosystem,
		LEGACY_ECOSYSTEM_FIELDS,
		config_path,
		"legacy ecosystems[%d]" % index
	):
		return
	var ecosystem_id := String(ecosystem.get("id", ""))
	if ecosystem_id.is_empty():
		host._add_error(config_path, "legacy ecosystems[%d].id is empty" % index)
		return
	var community := {
		"id": ecosystem_id,
		"kind": "legacy_bundle",
		"flora": host._deep_copy(ecosystem.get("flora", [])),
		"fauna": host._deep_copy(ecosystem.get("fauna", [])),
		"ambient": host._deep_copy(ecosystem.get("ambient", [])),
	}
	host._merge_community(community, config_path)
	var biome := {
		"id": ecosystem_id,
		"match": host._deep_copy(ecosystem.get("match", {})),
		"community_refs": [ecosystem_id],
		"attachments": [],
	}
	host._merge_biome(biome, config_path)


## 校验 community 内嵌的 legacy 形状 flora/fauna/ambient 规则数组（manifest 与 legacy
## 路径共用；按规则域拆 helper，嵌套 ≤3，报错文案与顺序逐字保留）。
static func validate_community_rules(
	host: EcologyRegistry,
	community: Dictionary,
	source_path: String,
	community_id: String
) -> void:
	var rule_specs := {
		"flora": {"fields": FLORA_RULE_FIELDS, "category": "plants"},
		"fauna": {"fields": FAUNA_RULE_FIELDS, "category": "animals"},
		"ambient": {"fields": AMBIENT_RULE_FIELDS, "category": "ambient"},
	}
	for rule_kind in rule_specs:
		var spec: Dictionary = rule_specs[rule_kind]
		_validate_rule_list(host, community, String(rule_kind), spec, source_path, community_id)


static func _validate_rule_list(
	host: EcologyRegistry,
	community: Dictionary,
	rule_kind: String,
	spec: Dictionary,
	source_path: String,
	community_id: String
) -> void:
	var rules_value: Variant = community.get(rule_kind, [])
	if not rules_value is Array:
		return
	for index in (rules_value as Array).size():
		var rule_value: Variant = (rules_value as Array)[index]
		if not rule_value is Dictionary:
			host._add_error(
				source_path,
				"community %s.%s[%d] must be a Dictionary" % [community_id, rule_kind, index]
			)
			continue
		_validate_rule(host, rule_value, rule_kind, spec, source_path, community_id, index)


static func _validate_rule(
	host: EcologyRegistry,
	rule: Dictionary,
	rule_kind: String,
	spec: Dictionary,
	source_path: String,
	community_id: String,
	index: int
) -> void:
	var context := "community %s.%s[%d]" % [community_id, rule_kind, index]
	if not host._reject_unknown_fields(rule, spec["fields"], source_path, context):
		return
	var species_pool: Variant = rule.get("species", null)
	if not species_pool is Array or (species_pool as Array).is_empty():
		host._add_error(source_path, "%s.species must be a non-empty Array" % context)
		return
	for species_id_value in species_pool:
		host._validate_species_reference(
			String(species_id_value),
			String(spec["category"]),
			source_path,
			context
		)
	if rule_kind == "fauna":
		_validate_fauna_substitution(host, rule, source_path, community_id, context)


static func _validate_fauna_substitution(
	host: EcologyRegistry,
	rule: Dictionary,
	source_path: String,
	community_id: String,
	context: String
) -> void:
	var distribution_value: Variant = rule.get("distribution", {})
	if not distribution_value is Dictionary:
		return
	var substitution_value: Variant = (distribution_value as Dictionary).get("substitution", {})
	if not substitution_value is Dictionary or (substitution_value as Dictionary).is_empty():
		return
	var substitution: Dictionary = substitution_value
	if host._reject_unknown_fields(
		substitution,
		FAUNA_SUBSTITUTION_FIELDS,
		source_path,
		"%s.distribution.substitution" % context
	):
		host._validate_species_reference(
			String(substitution.get("species", "")),
			"animals",
			source_path,
			"community %s fauna substitution" % community_id
		)
