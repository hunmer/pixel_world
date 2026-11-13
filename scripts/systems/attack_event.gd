## systems/attack_event.gd — 战斗结算后的只读演出事件快照。
##
## AttackEvent 只保存单位 ID、格位、HP 与效果快照，不持有 Unit Dictionary 引用。
## CombatSystem/SkillSystem 先完成结算，再把结果交给本类构建事件；ActionAnim 只读事件。
class_name AttackEvent
extends RefCounted

const SCHEMA_VERSION := 1
const NORMAL_BUDGET_SECONDS := 1.2
const SKILL_BUDGET_SECONDS := 2.0
const WEAKNESS_HITSTOP_SECONDS := 0.08


## 一次实际命中/未命中/治疗/状态的效果快照。knockback 仅供显示，不写回逻辑格位。
static func make_impact(
	source: Dictionary,
	target: Dictionary,
	hit: bool,
	damage: int,
	hp_before: int,
	hp_after: int,
	critical: bool = false,
	effective: bool = false,
	element: StringName = &"physical",
	statuses: Array = []
) -> Dictionary:
	var source_cell: Vector2i = source.get(&"position", Vector2i.ZERO)
	var target_cell: Vector2i = target.get(&"position", Vector2i.ZERO)
	var delta := target_cell - source_cell
	var weakness := effective or _has_element_weakness(target, element)
	var knockback := Vector2i.ZERO
	if hit and damage > 0:
		knockback = Vector2i(signi(delta.x), signi(delta.y))
	return {
		&"source_id": StringName(source.get(&"id", &"")),
		&"target_id": StringName(target.get(&"id", &"")),
		&"source_cell": source_cell,
		&"target_cell": target_cell,
		&"hit": hit,
		&"damage": maxi(0, damage),
		&"healing": maxi(0, hp_after - hp_before),
		&"hp_before": hp_before,
		&"hp_after": hp_after,
		&"hp_delta": hp_after - hp_before,
		&"died": hp_after <= 0,
		&"critical": critical,
		&"effective": effective,
		&"weakness": weakness,
		&"knockback": knockback,
		&"element": element,
		&"statuses": statuses.duplicate(true),
	}


## 由 CombatSystem.execute 的逐次 impacts 构建普攻事件。
static func from_combat(
	attacker: Dictionary,
	defender: Dictionary,
	result: Dictionary,
	impacts: Array
) -> Dictionary:
	var weapon_type: StringName = attacker.get(&"weapon", {}).get(&"type", &"sword")
	var element := &"physical"
	if weapon_type in [&"anima", &"dark", &"staff"]:
		element = weapon_type
	var anim := &"slash"
	match weapon_type:
		&"bow":
			anim = &"projectile:arrow"
		&"anima":
			anim = &"projectile:fire"
		&"dark":
			anim = &"projectile:dark"
		&"staff":
			anim = &"burst:holy"
	var event := _base_event(&"normal", attacker, anim, element, impacts)
	event[&"primary_target_id"] = StringName(defender.get(&"id", &""))
	event[&"damage"] = int(result.get(&"attackerDamage", 0))
	event[&"counter_damage"] = int(result.get(&"defenderDamage", 0))
	event[&"critical"] = bool(result.get(&"isCrit", false))
	event[&"double_attack"] = bool(result.get(&"isDoubleAttack", false))
	event[&"countered"] = bool(result.get(&"defenderHits", false))
	return event


## 由 SkillSystem.execute 的 hits/healed/buffed/missed 构建技能事件。
static func from_skill(caster: Dictionary, skill_data: Dictionary, result: Dictionary) -> Dictionary:
	var element: StringName = skill_data.get(&"element", &"physical")
	var impacts: Array = []
	var primary_target_id := &""
	for raw_hit in result.get(&"hits", []):
		var hit: Dictionary = raw_hit
		var target: Dictionary = hit[&"unit"]
		var hp_after := int(target.get(&"hp", 0))
		var hp_before := hp_after - int(hit.get(&"hp_delta", 0))
		if primary_target_id == &"":
			primary_target_id = StringName(target.get(&"id", &""))
		impacts.append(make_impact(
			caster, target, true, int(hit.get(&"dmg", 0)), hp_before, hp_after,
			false, _has_element_weakness(target, element), element))
	for raw_heal in result.get(&"healed", []):
		var heal: Dictionary = raw_heal
		var target: Dictionary = heal[&"unit"]
		var hp_after := int(target.get(&"hp", 0))
		var hp_before := hp_after - int(heal.get(&"hp_delta", 0))
		if primary_target_id == &"":
			primary_target_id = StringName(target.get(&"id", &""))
		impacts.append(make_impact(caster, target, true, 0, hp_before, hp_after, false, false, element))
	for raw_buff in result.get(&"buffed", []):
		var buff: Dictionary = raw_buff
		var target: Dictionary = buff[&"unit"]
		var statuses: Array = []
		if not buff.get(&"status", {}).is_empty():
			statuses.append((buff[&"status"] as Dictionary).duplicate(true))
		if primary_target_id == &"":
			primary_target_id = StringName(target.get(&"id", &""))
		impacts.append(make_impact(
			caster, target, true, 0, int(target.get(&"hp", 0)), int(target.get(&"hp", 0)),
			false, false, element, statuses))
	for raw_miss in result.get(&"missed", []):
		var miss: Dictionary = raw_miss
		var target: Dictionary = miss[&"unit"]
		if primary_target_id == &"":
			primary_target_id = StringName(target.get(&"id", &""))
		impacts.append(make_impact(
			caster, target, false, 0, int(target.get(&"hp", 0)), int(target.get(&"hp", 0)),
			false, false, element))
	var event := _base_event(&"skill", caster, resolve_skill_anim(skill_data), element, impacts)
	event[&"skill_id"] = StringName(skill_data.get(&"id", result.get(&"skill_id", &"")))
	event[&"primary_target_id"] = primary_target_id
	event[&"damage"] = _total_damage(impacts)
	event[&"mp_cost"] = int(result.get(&"mp_cost", 0))
	return event


## data/skills.json 的 anim 是可选项；旧技能按类型与元素回退到四种模板。
static func resolve_skill_anim(skill_data: Dictionary) -> StringName:
	var configured := StringName(skill_data.get(&"anim", &""))
	if configured != &"":
		return configured
	var element: StringName = skill_data.get(&"element", &"physical")
	match StringName(skill_data.get(&"type", &"damage")):
		&"damage":
			return &"slash" if element == &"physical" else StringName("projectile:" + String(element))
		&"aoe":
			return StringName("burst:" + String(element))
		&"debuff":
			return StringName("beam:" + String(element))
		&"heal", &"buff":
			return StringName("burst:" + String(element))
	return &"slash"


static func primary_target_id(event: Dictionary) -> StringName:
	var explicit_id := StringName(event.get(&"primary_target_id", &""))
	if explicit_id != &"":
		return explicit_id
	var impacts: Array = event.get(&"impacts", [])
	if not impacts.is_empty():
		return StringName((impacts[0] as Dictionary).get(&"target_id", &""))
	return &""


static func _base_event(
	kind: StringName,
	attacker: Dictionary,
	anim: StringName,
	element: StringName,
	impacts: Array
) -> Dictionary:
	var effective := false
	var weakness := false
	var statuses: Array = []
	for raw_impact in impacts:
		var impact: Dictionary = raw_impact
		effective = effective or bool(impact.get(&"effective", false))
		weakness = weakness or bool(impact.get(&"weakness", false))
		statuses.append_array(impact.get(&"statuses", []))
	return {
		&"version": SCHEMA_VERSION,
		&"kind": kind,
		&"attacker_id": StringName(attacker.get(&"id", &"")),
		&"attacker_cell": attacker.get(&"position", Vector2i.ZERO),
		&"primary_target_id": &"",
		&"skill_id": &"",
		&"anim": anim,
		&"element": element,
		&"impacts": impacts.duplicate(true),
		&"effective": effective,
		&"weakness": weakness,
		&"hitstop": WEAKNESS_HITSTOP_SECONDS if weakness else 0.0,
		&"statuses": statuses,
	}


static func _total_damage(impacts: Array) -> int:
	var total := 0
	for raw_impact in impacts:
		total += int((raw_impact as Dictionary).get(&"damage", 0))
	return total


static func _has_element_weakness(target: Dictionary, element: StringName) -> bool:
	if element == &"" or element == &"physical":
		return false
	var weaknesses: Array = target.get(&"weaknesses", [])
	return weaknesses.has(element) or weaknesses.has(String(element))
