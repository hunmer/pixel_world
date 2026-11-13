## systems/combat_system.gd — 战斗结算（对应 src/systems/CombatSystem.ts）
## FE 经典简化版：
##   命中率 = 武器命中 + 技*1.5 + 运/2 - 对方回避(速*1.5+运/2+地形回避) ± 三角
##   伤害   = 力/魔 + 武器威力 - 对方 防/魔防 - 地形防御 + 三角
##   双击   = 攻击速度差 ≥ 4（重量补正后）
##   必杀   = (技/2 + 武器必杀 - 对方运/2)%
## 纯静态函数；UnitData 用 Dictionary。

class_name CombatSystem
extends RefCounted

const AttackEventBuilder = preload("res://scripts/systems/attack_event.gd")

## 预览：不造成伤害，返回 { atkHit,defHit,atkDmg,defDmg,doubleAttack,defenderDouble,atkCrit }
static func preview(
	attacker: Dictionary, defender: Dictionary,
	defender_tile_avoid: int, defender_tile_def: int
) -> Dictionary:
	var tri := _triangle_modifier(attacker, defender)
	var tri_hit: int = tri[&"hit"]
	var tri_dmg: int = tri[&"damage"]
	var atk_hit: int = _hit_chance(attacker, defender, defender_tile_avoid) + tri_hit
	var def_hit := 0
	if defender[&"weapon"][&"type"] != &"staff":
		def_hit = _hit_chance(defender, attacker, 0) - tri_hit
	var atk_dmg: int = _damage(attacker, defender, defender_tile_def) + tri_dmg
	var def_dmg := 0
	if defender[&"weapon"][&"type"] != &"staff":
		def_dmg = _damage(defender, attacker, 0) - tri_dmg
	var double_attack := _attack_speed(attacker) - _attack_speed(defender) >= 4
	var defender_double := _attack_speed(defender) - _attack_speed(attacker) >= 4
	return {
		&"atkHit": clampi(atk_hit, 0, 100),
		&"defHit": clampi(def_hit, 0, 100),
		&"atkDmg": maxi(atk_dmg, 0),
		&"defDmg": maxi(def_dmg, 0),
		&"doubleAttack": double_attack,
		&"defenderDouble": defender_double,
		&"atkCrit": _crit_chance(attacker, defender),
	}


## 实际执行一次战斗（含双击判定）。
## 返回 CombatResult = {
##   attackerHits, defenderHits, attackerDamage, defenderDamage,
##   attackerDied, defenderDied, isDoubleAttack, isCrit, attack_event }
## 会直接 mutate 双方 hp；attack_event 是结算完成后的只读演出快照。
static func execute(
	attacker: Dictionary, defender: Dictionary,
	defender_tile_avoid: int, defender_tile_def: int
) -> Dictionary:
	var p := preview(attacker, defender, defender_tile_avoid, defender_tile_def)
	var result := {
		&"attackerHits": false, &"defenderHits": false,
		&"attackerDamage": 0, &"defenderDamage": 0,
		&"attackerDied": false, &"defenderDied": false,
		&"isDoubleAttack": false, &"isCrit": false,
	}
	var impacts: Array = []
	var tri := _triangle_modifier(attacker, defender)
	var atk_effective := int(tri[&"damage"]) > 0
	var def_effective := int(tri[&"damage"]) < 0
	var atk_element := _weapon_element(attacker)
	var def_element := _weapon_element(defender)

	# 攻击者第一次攻击。随机判定顺序与原结算保持一致。
	if randf() * 100.0 < int(p[&"atkHit"]):
		var is_crit: bool = randf() * 100.0 < int(p[&"atkCrit"])
		var base_dmg: int = int(p[&"atkDmg"])
		var dmg: int = base_dmg * 3 if is_crit else base_dmg
		var hp_before := int(defender[&"hp"])
		defender[&"hp"] = maxi(0, hp_before - dmg)
		result[&"attackerHits"] = true
		result[&"attackerDamage"] = dmg
		result[&"isCrit"] = is_crit
		impacts.append(AttackEventBuilder.make_impact(
			attacker, defender, true, dmg, hp_before, int(defender[&"hp"]),
			is_crit, atk_effective, atk_element))
		if int(defender[&"hp"]) <= 0:
			result[&"defenderDied"] = true
			return _finish_combat(attacker, defender, result, impacts)
	else:
		impacts.append(AttackEventBuilder.make_impact(
			attacker, defender, false, 0, int(defender[&"hp"]), int(defender[&"hp"]),
			false, atk_effective, atk_element))

	# 是否能反击（射程内 + 远程武器）
	var can_counter := _in_range(attacker, defender)
	if can_counter:
		if randf() * 100.0 < int(p[&"defHit"]):
			var dmg: int = int(p[&"defDmg"])
			var hp_before := int(attacker[&"hp"])
			attacker[&"hp"] = maxi(0, hp_before - dmg)
			result[&"defenderHits"] = true
			result[&"defenderDamage"] = dmg
			impacts.append(AttackEventBuilder.make_impact(
				defender, attacker, true, dmg, hp_before, int(attacker[&"hp"]),
				false, def_effective, def_element))
			if int(attacker[&"hp"]) <= 0:
				result[&"attackerDied"] = true
				return _finish_combat(attacker, defender, result, impacts)
		else:
			# staff 原本就不能反击（defHit=0）；保留原 randf 消耗，但不伪造反击 MISS 演出。
			if defender[&"weapon"][&"type"] != &"staff":
				impacts.append(AttackEventBuilder.make_impact(
					defender, attacker, false, 0, int(attacker[&"hp"]), int(attacker[&"hp"]),
					false, def_effective, def_element))

	# 攻击者追击（双击）
	if p[&"doubleAttack"]:
		result[&"isDoubleAttack"] = true
		if randf() * 100.0 < int(p[&"atkHit"]):
			var dmg: int = int(p[&"atkDmg"])
			var hp_before := int(defender[&"hp"])
			defender[&"hp"] = maxi(0, hp_before - dmg)
			result[&"attackerDamage"] = int(result[&"attackerDamage"]) + dmg
			impacts.append(AttackEventBuilder.make_impact(
				attacker, defender, true, dmg, hp_before, int(defender[&"hp"]),
				false, atk_effective, atk_element))
			if int(defender[&"hp"]) <= 0:
				result[&"defenderDied"] = true
				return _finish_combat(attacker, defender, result, impacts)
		else:
			impacts.append(AttackEventBuilder.make_impact(
				attacker, defender, false, 0, int(defender[&"hp"]), int(defender[&"hp"]),
				false, atk_effective, atk_element))
	return _finish_combat(attacker, defender, result, impacts)


static func _finish_combat(
	attacker: Dictionary, defender: Dictionary, result: Dictionary, impacts: Array
) -> Dictionary:
	result[&"attack_event"] = AttackEventBuilder.from_combat(attacker, defender, result, impacts)
	return result


static func _weapon_element(unit: Dictionary) -> StringName:
	var weapon_type: StringName = unit.get(&"weapon", {}).get(&"type", &"sword")
	return weapon_type if weapon_type in [&"anima", &"dark", &"staff"] else &"physical"


# ----------- 子公式 -----------

static func _triangle_modifier(attacker: Dictionary, defender: Dictionary) -> Dictionary:
	return WeaponData.triangle_modifier(attacker[&"weapon"][&"type"], defender[&"weapon"][&"type"])


static func _hit_chance(attacker: Dictionary, defender: Dictionary, defender_tile_avoid: int) -> int:
	var weapon_hit: int = attacker[&"weapon"][&"hit"]
	var skl: int = BuffSystem.effective_stat(attacker, &"skl")
	var luk: int = BuffSystem.effective_stat(attacker, &"luk")
	var d_spd: int = BuffSystem.effective_stat(defender, &"spd")
	var d_luk: int = BuffSystem.effective_stat(defender, &"luk")
	var avoid: float = d_spd * 1.5 + d_luk / 2.0 + defender_tile_avoid
	return roundi(weapon_hit + skl * 1.5 + luk / 2.0 - avoid)


static func _damage(attacker: Dictionary, defender: Dictionary, defender_tile_def: int) -> int:
	var is_magic := ([&"anima", &"dark", &"staff"] as Array).has(attacker[&"weapon"][&"type"])
	var atk: int = BuffSystem.effective_stat(attacker, &"mag") if is_magic else BuffSystem.effective_stat(attacker, &"str")
	var def: int = BuffSystem.effective_stat(defender, &"res") if is_magic else BuffSystem.effective_stat(defender, &"def")
	return maxi(0, atk + attacker[&"weapon"][&"might"] - def - defender_tile_def)


static func _attack_speed(u: Dictionary) -> int:
	var burden := maxi(0, u[&"weapon"][&"weight"] - floori(BuffSystem.effective_stat(u, &"str") / 2.0))
	return BuffSystem.effective_stat(u, &"spd") - burden


static func _crit_chance(attacker: Dictionary, defender: Dictionary) -> int:
	return maxi(0, floori(BuffSystem.effective_stat(attacker, &"skl") / 2.0) + attacker[&"weapon"][&"crit"] - floori(BuffSystem.effective_stat(defender, &"luk") / 2.0))


static func _in_range(attacker: Dictionary, defender: Dictionary) -> bool:
	var ap: Vector2i = attacker[&"position"]
	var dp: Vector2i = defender[&"position"]
	var dist := absi(ap.x - dp.x) + absi(ap.y - dp.y)
	var r: Array = ProfessionData.unit_attack_range(attacker)
	return dist >= r[0] and dist <= r[1]
