## tests/attack_event_contract.gd — 结算先行 AttackEvent 与技能 anim 数据契约。
extends SceneTree

const AttackEventScript = preload("res://scripts/systems/attack_event.gd")
const Combat = preload("res://scripts/systems/combat_system.gd")
const Skills = preload("res://scripts/systems/skill_system.gd")
const SkillConfig = preload("res://scripts/core/skills.gd")
const Anim = preload("res://scripts/battle/action_anim.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok: %s" % message)
	else:
		failures += 1
		printerr("  FAIL: %s" % message)


func _unit(id: StringName, faction: StringName, cell: Vector2i, weapon_type: StringName = &"sword") -> Dictionary:
	return {
		&"id": id, &"name": String(id), &"classId": &"swordsman", &"faction": faction,
		&"position": cell, &"hp": 100, &"mp": 30, &"isDead": false,
		&"stats": { &"hp": 100, &"mp": 30, &"str": 20, &"mag": 20, &"skl": 100,
			&"spd": 10, &"luk": 0, &"def": 0, &"res": 0, &"mov": 5 },
		&"weapon": { &"type": weapon_type, &"hit": 100, &"might": 5, &"weight": 1, &"crit": 0 },
		&"attackRange": [1, 1], &"moveType": &"infantry", &"buffs": [],
		&"skills": [], &"skillCooldowns": {}, &"items": [], &"weaknesses": [],
	}


func _run() -> void:
	print("== attack_event_contract ==")
	seed(731)
	var attacker := _unit(&"attacker", &"player", Vector2i(0, 0))
	var defender := _unit(&"defender", &"enemy", Vector2i(1, 0), &"staff")
	defender[&"stats"][&"spd"] = 0
	var defender_hp := int(defender[&"hp"])
	var result: Dictionary = Combat.execute(attacker, defender, 0, 0)
	_expect(result.has(&"attack_event"), "普攻旧结果附加 attack_event")
	var event: Dictionary = result[&"attack_event"]
	_expect(event.get(&"version") == AttackEventScript.SCHEMA_VERSION, "事件 schema 版本")
	_expect(event.get(&"kind") == &"normal" and event.get(&"anim") == &"slash", "普攻 slash 模板")
	_expect(not event.has(&"attacker") and not event.has(&"defender"), "事件不持有单位 Dictionary")
	var impacts: Array = event[&"impacts"]
	_expect(impacts.size() == 2, "100% 命中且速度差>=4：首击+追击均入事件")
	var damage_total := 0
	var previous_before := defender_hp
	for raw_impact in impacts:
		var impact: Dictionary = raw_impact
		damage_total += int(impact[&"damage"])
		_expect(impact[&"source_id"] == &"attacker" and impact[&"target_id"] == &"defender", "impact 使用稳定单位 ID")
		_expect(int(impact[&"hp_before"]) == previous_before, "逐击 HP 前快照连续")
		_expect(int(impact[&"hp_after"]) == int(impact[&"hp_before"]) + int(impact[&"hp_delta"]), "HP delta 与前后快照一致")
		_expect(not impact.has(&"unit"), "impact 不含结算单位引用")
		previous_before = int(impact[&"hp_after"])
	_expect(damage_total == int(result[&"attackerDamage"]), "事件伤害总额等于结算结果")
	_expect(previous_before == int(defender[&"hp"]), "最终 HP 快照等于已落地 HP")
	_expect(attacker[&"position"] == Vector2i(0, 0) and defender[&"position"] == Vector2i(1, 0), "结算与事件均不改逻辑格位")

	var caster := _unit(&"caster", &"player", Vector2i(0, 0), &"anima")
	var target := _unit(&"target", &"enemy", Vector2i(2, 0))
	target[&"weaknesses"] = [&"fire"]
	var skill_result: Dictionary = Skills.execute(caster, [target], &"fireball")
	var skill_event: Dictionary = skill_result[&"attack_event"]
	_expect(skill_event[&"anim"] == &"projectile:fire", "技能显式 anim 保留")
	_expect(skill_event[&"hitstop"] == AttackEventScript.WEAKNESS_HITSTOP_SECONDS, "元素弱点命中产生 0.08s 顿帧")
	_expect(skill_event[&"impacts"][0][&"weakness"], "impact 记录元素弱点")
	_expect(skill_event[&"impacts"][0][&"hp_after"] == target[&"hp"], "技能事件在 HP 结算后构建")
	_expect(caster[&"mp"] == 24 and skill_event[&"mp_cost"] == 6, "MP 已先行扣除且事件记录成本")

	var buff_result: Dictionary = Skills.execute(caster, [caster], &"powerSurge")
	var buff_event: Dictionary = buff_result[&"attack_event"]
	_expect(buff_event[&"anim"] == &"burst:physical", "缺省 buff anim 按类型回退")
	_expect(buff_event[&"impacts"][0][&"statuses"][0][&"turns"] == 3, "buff impact 带状态持续回合快照")

	var healer := _unit(&"healer", &"player", Vector2i(0, 0), &"staff")
	var patient := _unit(&"patient", &"player", Vector2i(1, 0), &"staff")
	patient[&"hp"] = 20
	var heal_result: Dictionary = Skills.execute(healer, [patient], &"heal")
	var heal_event: Dictionary = heal_result[&"attack_event"]
	_expect(heal_event[&"anim"] == &"burst:holy", "旧治疗技能缺省 anim 回退")
	_expect(heal_event[&"impacts"][0][&"healing"] > 0, "治疗量进入 impact")
	_expect(heal_event[&"impacts"][0][&"hp_before"] == 20, "治疗前 HP 快照")

	_expect(AttackEventScript.resolve_skill_anim(SkillConfig.get_skill(&"smite")) == &"slash", "smite=slash")
	_expect(AttackEventScript.resolve_skill_anim(SkillConfig.get_skill(&"blizzard")) == &"burst:ice", "blizzard=burst:ice")
	_expect(AttackEventScript.resolve_skill_anim(SkillConfig.get_skill(&"weaken")) == &"beam:dark", "weaken=beam:dark")
	for skill_data in SkillConfig.SKILL_LIST:
		_expect(skill_data.has(&"anim"), "%s 归一化保留可选 anim" % skill_data[&"id"])
		_expect(Anim.template_for({&"anim": AttackEventScript.resolve_skill_anim(skill_data)}) in [&"slash", &"projectile", &"burst", &"beam"], "%s anim 映射到四模板" % skill_data[&"id"])
	var anim := Anim.new()
	_expect(anim.duration_seconds(event) <= AttackEventScript.NORMAL_BUDGET_SECONDS, "普攻时间轴<=1.2s")
	_expect(anim.duration_seconds(skill_event) <= AttackEventScript.SKILL_BUDGET_SECONDS, "技能时间轴<=2s")
	anim.free()
	print("== attack_event_contract: %s ==" % ("PASS" if failures == 0 else "FAIL(%d)" % failures))
	quit(failures)
