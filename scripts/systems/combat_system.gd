## systems/combat_system.gd — 战斗结算（对应 src/systems/CombatSystem.ts）
## FE 经典简化版：
##   命中率 = 武器命中 + 技*1.5 + 运/2 - 对方回避(速*1.5+运/2+地形回避) ± 三角
##   伤害   = 力/魔 + 武器威力 - 对方 防/魔防 - 地形防御 + 三角
##   双击   = 攻击速度差 ≥ 4（重量补正后）
##   必杀   = (技/2 + 武器必杀 - 对方运/2)%
##   背击   = 攻击来自受击者身后（FacingRules）时本次伤害 ×1.25（preview/execute 共用）
##   夹击追击 = 物理普攻命中且目标未死后，对侧相邻格的同阵营友军自动追加一次
##            半强度攻击（判定 PincerRules.pincer_partner；伤害 pincer_damage；
##            结算由 BattleActionResolver 落地，本类只供预览与公式）
## 纯静态函数；UnitData 用 Dictionary。

class_name CombatSystem
extends RefCounted

const AttackEventBuilder = preload("res://scripts/systems/attack_event.gd")
const FacingRules = preload("res://scripts/systems/facing_rules.gd")
const PincerRules = preload("res://scripts/systems/pincer_rules.gd")

## 预览：不造成伤害，返回 { atkHit,defHit,atkDmg,defDmg,doubleAttack,defenderDouble,atkCrit,atkBackstab,pincer }
## allies（可选）= 攻击方阵营候选单位池（grid.units.values()）时，pincer 字段给出
## 夹击追击预览 {active,partner_id,damage}（判定 PincerRules.pincer_partner、
## 伤害 pincer_damage，与 resolver 真实结算同公式）；缺省恒 inactive，旧调用零影响。
static func preview(
	attacker: Dictionary, defender: Dictionary,
	defender_tile_avoid: int, defender_tile_def: int,
	allies: Array = []
) -> Dictionary:
	var tri := _triangle_modifier(attacker, defender)
	var tri_hit: int = tri[&"hit"]
	var tri_dmg: int = tri[&"damage"]
	var atk_hit: int = _hit_chance(attacker, defender, defender_tile_avoid) + tri_hit
	var def_hit := 0
	if defender[&"weapon"][&"type"] != &"staff":
		def_hit = _hit_chance(defender, attacker, 0) - tri_hit
	# 背击增幅在三角修正合并并钳制后统一施加于「本次总伤害」：
	# (base + tri) × 1.25，攻击与反击同口径；execute 直接消费本结果，天然一致。
	var atk_dmg: int = FacingRules.apply_backstab(
		attacker[&"position"], defender,
		maxi(0, _damage(attacker, defender, defender_tile_def) + tri_dmg))
	var def_dmg := 0
	if defender[&"weapon"][&"type"] != &"staff":
		# 反击背击口径与 resolver 出手转身一致：攻击者出手时已面向防守方，防守方反击
		# 恒打攻击者正面。这里用临时朝向快照（duplicate，不 mutate 原字典）复现该口径，
		# 保证预览（UI/AI）与真实结算同数值 —— 反击永不触发背击增幅。
		var attacker_turned: Dictionary = attacker.duplicate()
		FacingRules.face_toward(attacker_turned, defender[&"position"])
		def_dmg = FacingRules.apply_backstab(
			defender[&"position"], attacker_turned,
			maxi(0, _damage(defender, attacker, 0) - tri_dmg))
	var double_attack := _attack_speed(attacker) - _attack_speed(defender) >= 4
	var defender_double := _attack_speed(defender) - _attack_speed(attacker) >= 4
	var atk_backstab := FacingRules.is_backstab(attacker[&"position"], defender)
	return {
		&"atkHit": clampi(atk_hit, 0, 100),
		&"defHit": clampi(def_hit, 0, 100),
		&"atkDmg": atk_dmg,
		&"defDmg": def_dmg,
		&"doubleAttack": double_attack,
		&"defenderDouble": defender_double,
		&"atkCrit": _crit_chance(attacker, defender),
		&"atkBackstab": atk_backstab,
		&"pincer": _pincer_preview_info(attacker, defender, defender_tile_def, allies),
	}


## 夹击追击伤害唯一公式（预览/结算/无头 runner 共用）：
## 追击友军普攻口径（_damage + 三角修正钳 0 → 背击增幅，与 preview.atkDmg 同式）
## × PincerRules.DAMAGE_RATIO，roundi 四舍五入后 maxi(0, ·)。
## 追击自身无命中/必杀掷（必中无暴击），随机流零消耗。
static func pincer_damage(
	partner: Dictionary, defender: Dictionary, defender_tile_def: int
) -> int:
	var tri := _triangle_modifier(partner, defender)
	var base := maxi(0, _damage(partner, defender, defender_tile_def) + int(tri[&"damage"]))
	var full := FacingRules.apply_backstab(partner[&"position"], defender, base)
	return maxi(0, roundi(full * PincerRules.DAMAGE_RATIO))


## 预览用夹击摘要：非物理武器 / 无 allies / 无对侧友军 → 恒 {active=false}。
static func _pincer_preview_info(
	attacker: Dictionary, defender: Dictionary,
	defender_tile_def: int, allies: Array
) -> Dictionary:
	if not PincerRules.is_physical_weapon(attacker) or allies.is_empty():
		return { &"active": false, &"partner_id": &"", &"damage": 0 }
	var partner := PincerRules.pincer_partner(attacker, defender, allies)
	if partner.is_empty():
		return { &"active": false, &"partner_id": &"", &"damage": 0 }
	return {
		&"active": true,
		&"partner_id": StringName(partner.get(&"id", &"")),
		&"damage": pincer_damage(partner, defender, defender_tile_def),
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
	# 纯基础伤害（不含三角修正与背击增幅）：三角与背击在 preview 合并后统一施加。
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
