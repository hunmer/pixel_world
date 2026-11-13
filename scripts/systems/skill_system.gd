## systems/skill_system.gd — 技能结算（全静态）
##
## 与 CombatSystem（普攻，含反击/双击）解耦：技能走独立结算，不被反击。
## 伤害公式复用 CombatSystem 的物理/魔法判定思路，但用 skill.power 取代 weapon.might。
## buff/debuff 通过挂 unit.buffs + effective_stat() 生效，影响普攻和技能。
##
## 技能 type：
##   damage  — 单体伤害（含命中判定，不被反击）
##   heal    — 单体治疗（不超 stats.hp 上限，必中）
##   aoe     — 范围伤害（对范围内所有合法目标各结算一次）
##   buff    — 增益（自身/友方，挂正面 buff）
##   debuff  — 减益（敌方，挂负面 buff，value 为负）

class_name SkillSystem
extends RefCounted

const AttackEventBuilder = preload("res://scripts/systems/attack_event.gd")


# ============================================================
# buff 系统（转发到 BuffSystem，保持向后兼容的 API）
# buff 逻辑实现在 BuffSystem（零依赖），避免 CombatSystem↔SkillSystem 循环。
# ============================================================

## 取单位某项属性的「实际值」= 基础 stats + 所有 buff 累计。
## CombatSystem/SkillSystem/AI 取属性时统一用此函数，保证 buff 真实生效。
static func effective_stat(unit: Dictionary, stat: StringName) -> int:
	return BuffSystem.effective_stat(unit, stat)


## 给单位挂一个 buff/debuff。
static func apply_buff(unit: Dictionary, stat: StringName, value: int, turns: int, label: String = "") -> void:
	BuffSystem.apply_buff(unit, stat, value, turns, label)


## 每回合开始对所有单位的 buff 倒计时，turns<=0 的移除。
static func tick_buffs(units: Array) -> void:
	BuffSystem.tick_buffs(units)


## 清除单位所有 debuff（value<0 的 buff），解毒药用。
static func cleanse_debuffs(unit: Dictionary) -> int:
	return BuffSystem.cleanse_debuffs(unit)


# ============================================================
# 可用性 & 目标
# ============================================================

## 单位当前能否使用某技能（MP 足 + 冷却 0）。不检查目标可达性。
static func can_use(caster: Dictionary, skill_id: StringName) -> bool:
	var sk: Dictionary = SkillData.get_skill(skill_id)
	if sk.is_empty():
		return false
	var cd: Dictionary = caster.get(&"skillCooldowns", {})
	if int(cd.get(skill_id, 0)) > 0:
		return false
	if int(sk[&"mpCost"]) > int(caster.get(&"mp", 0)):
		return false
	return true


## 列出技能的合法目标（按 targetType + range + 阵营过滤）。
## grid 可为 null（self/无目标场景），需要距离判断时必须传。
static func targets_for(caster: Dictionary, skill_id: StringName, grid: GridSystem) -> Array:
	var sk: Dictionary = SkillData.get_skill(skill_id)
	if sk.is_empty():
		return []
	var tt: StringName = sk[&"targetType"]
	# self：目标就是自己
	if tt == &"self":
		return [caster]
	if grid == null:
		return []
	var r: Array = sk[&"range"]
	var cp: Vector2i = caster[&"position"]
	var caster_faction: StringName = caster[&"faction"]
	var out: Array = []
	for other in grid.units.values():
		if other.get(&"isDead", false):
			continue
		var dist := absi(other.position.x - cp.x) + absi(other.position.y - cp.y)
		if dist < int(r[0]) or dist > int(r[1]):
			continue
		var same_side: bool = other.faction == caster_faction
		match tt:
			&"ally":
				if same_side and other.id != caster.id:
					out.append(other)
			&"enemy":
				if not same_side:
					out.append(other)
			&"aoe_ally":
				if same_side:
					out.append(other)
			&"aoe_enemy":
				if not same_side:
					out.append(other)
	return out


# ============================================================
# 预览（UI 用，不落地）
# ============================================================

## 预期效果。返回 { type, hp_delta, mp_delta, buff_desc, hit }
static func preview(caster: Dictionary, target: Dictionary, skill_id: StringName) -> Dictionary:
	var sk: Dictionary = SkillData.get_skill(skill_id)
	if sk.is_empty():
		return {}
	var res: Dictionary = { id = skill_id, name = sk[&"name"], type = sk[&"type"] }
	match sk[&"type"]:
		&"damage", &"aoe":
			res[&"hit"] = _skill_hit(caster, target, sk)
			res[&"hp_delta"] = -_skill_damage(caster, target, sk)
			res[&"desc"] = "伤害 ~%d" % int(res[&"hp_delta"] * -1)
		&"heal":
			var max_hp: int = int(target[&"stats"][&"hp"])
			var heal_amt: int = int(sk[&"power"]) + _heal_bonus(caster)
			res[&"hp_delta"] = mini(heal_amt, max_hp - int(target[&"hp"]))
			res[&"desc"] = "治疗 ~%d" % heal_amt
		&"buff", &"debuff":
			res[&"buff_desc"] = "%s%+d (%d回合)" % [String(sk[&"stat"]), int(sk[&"buffValue"]), int(sk[&"buffTurns"])]
			res[&"desc"] = res[&"buff_desc"]
	return res


# ============================================================
# 执行（落地，mutate hp/mp/buffs）
# ============================================================

## 执行技能。targets 为 targets_for 的结果（self 时是 [caster]）。
## 返回 { hits:[{unit,hp_delta,died}], healed:[{unit,hp_delta}], buffed:[{unit,desc,status}], missed:[unit], mp_cost, skill_id, attack_event }
## HP/MP/冷却/状态在本函数内先落地；attack_event 仅供随后演出回放。
static func execute(caster: Dictionary, targets: Array, skill_id: StringName) -> Dictionary:
	var sk: Dictionary = SkillData.get_skill(skill_id)
	if sk.is_empty():
		return {}
	var result: Dictionary = {
		hits = [], healed = [], buffed = [], missed = [],
		mp_cost = int(sk[&"mpCost"]), skill_id = skill_id,
	}
	# 扣 MP + 置冷却
	caster[&"mp"] = maxi(0, int(caster.get(&"mp", 0)) - int(sk[&"mpCost"]))
	var cd: Dictionary = caster.get(&"skillCooldowns", {})
	cd[skill_id] = int(sk[&"cooldown"])
	caster[&"skillCooldowns"] = cd

	match sk[&"type"]:
		&"damage":
			_apply_damage_to_targets(caster, targets, sk, result)
		&"aoe":
			_apply_damage_to_targets(caster, targets, sk, result)
		&"heal":
			for t in targets:
				var max_hp: int = int(t[&"stats"][&"hp"])
				var amt: int = int(sk[&"power"]) + _heal_bonus(caster)
				var before: int = int(t[&"hp"])
				t[&"hp"] = mini(max_hp, before + amt)
				result[&"healed"].append({ unit = t, hp_delta = int(t[&"hp"]) - before })
		&"buff", &"debuff":
			for t in targets:
				apply_buff(t, sk[&"stat"], int(sk[&"buffValue"]), int(sk[&"buffTurns"]), String(sk[&"name"]))
				var status := {
					&"stat": sk[&"stat"], &"value": int(sk[&"buffValue"]),
					&"turns": int(sk[&"buffTurns"]), &"label": String(sk[&"name"]),
				}
				result[&"buffed"].append({
					unit = t, desc = "%s%+d" % [String(sk[&"stat"]), int(sk[&"buffValue"])], status = status,
				})
	result[&"attack_event"] = AttackEventBuilder.from_skill(caster, sk, result)
	return result


# ============================================================
# 子公式
# ============================================================

## 技能伤害/治疗的基础施法属性：魔法元素走 mag，物理元素走 str。
static func _skill_atk(caster: Dictionary, sk: Dictionary) -> int:
	var is_magic: bool = _is_magic_element(sk[&"element"])
	return effective_stat(caster, &"mag") if is_magic else effective_stat(caster, &"str")


static func _skill_damage(caster: Dictionary, target: Dictionary, sk: Dictionary) -> int:
	var is_magic: bool = _is_magic_element(sk[&"element"])
	var atk: int = _skill_atk(caster, sk)
	var def: int = effective_stat(target, &"res") if is_magic else effective_stat(target, &"def")
	return maxi(0, atk + int(sk[&"power"]) - def)


static func _skill_hit(caster: Dictionary, target: Dictionary, sk: Dictionary) -> int:
	var base: int = int(sk.get(&"hitBonus", 100))
	var skl: int = effective_stat(caster, &"skl")
	var avoid: int = effective_stat(target, &"spd") + int(floorf(effective_stat(target, &"luk") / 2.0))
	return clampi(base + skl - avoid, 5, 100)


static func _heal_bonus(caster: Dictionary) -> int:
	# 治疗量受 mag 加成（魔法系奶得更猛）
	return int(floorf(effective_stat(caster, &"mag") / 2.0))


static func _is_magic_element(el: StringName) -> bool:
	return not el in [&"physical"]   # 除 physical 外（fire/ice/holy/dark/wind...）都按魔法


## 对 targets 逐个做命中判定 + 伤害落地。
static func _apply_damage_to_targets(caster: Dictionary, targets: Array, sk: Dictionary, result: Dictionary) -> void:
	for t in targets:
		if t.get(&"isDead", false):
			continue
		var hit_roll: int = _skill_hit(caster, t, sk)
		if randf() * 100.0 < hit_roll:
			var dmg: int = _skill_damage(caster, t, sk)
			var before: int = int(t[&"hp"])
			t[&"hp"] = maxi(0, before - dmg)
			var delta: int = int(t[&"hp"]) - before   # 负数
			var died: bool = int(t[&"hp"]) <= 0
			result[&"hits"].append({ unit = t, hp_delta = delta, dmg = dmg, died = died })
		else:
			result[&"missed"].append({ unit = t })
