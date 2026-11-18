## systems/pincer_rules.gd — 夹击追击判定（全静态、零依赖）
##
## 规则：物理攻击命中且目标未死后，若目标「对侧相邻格」有与攻击者同阵营的
## 存活友军（夹击队形 A—T—F），该友军自动追加一次攻击，伤害约其普通攻击一半。
##
## 「对侧格」（opposite_cell）：defender.position + signi(defender.position -
## attacker.position)（逐轴符号）。仅攻击线为正交方向（横/竖）时有效——
## 斜向攻击线（dx、dy 均非 0）无「对侧相邻」概念，不触发；同格也无对侧。
## 近战四方向时与等距镜像点 2*T-A 等价；远程直线（如 bow 距 2）取目标相邻格
## （用户口径「对侧相邻友军」，而非等距镜像的隔一格）。
##
## 伤害公式唯一实现于 CombatSystem.pincer_damage（追击友军普攻 preview.atkDmg
## 口径 × DAMAGE_RATIO，roundi）：预览（CombatSystem.preview 尾参 allies）、
## 真实结算（BattleActionResolver）、无头 runner 全部共用同一公式。
##
## 追击由 BattleActionResolver 统一结算（resolve_attack / resolve_skill 共用）：
## 必中、零 randf 消耗（不破坏 resolver 随机流契约）、不被反击、不递归
## （追击本身不再触发追击）、不消耗追击友军的行动（不动 hasActed/hasMoved）。
## 触发条件：物理武器 + 攻击方至少一击命中 + 目标整场结算后仍存活 +
## 对侧格有同阵营存活友军；攻击者被反击致死不阻止追击。
class_name PincerRules
extends RefCounted

## 追击伤害 = 追击友军普攻伤害（含三角/地形/背击增幅，与 preview.atkDmg 同式）
## × 该倍率（roundi 四舍五入，与 FacingRules.apply_backstab 同取整口径）。
const DAMAGE_RATIO := 0.5

## 「无对侧格」哨兵：斜向攻击线 / 同格时 opposite_cell 返回，永不触发追击。
const NO_CELL := Vector2i(-999999, -999999)


## 攻击是否物理口径（与 CombatSystem._weapon_element 的 physical 判定一致：
## weapon.type ∉ {anima, dark, staff}）。追击仅物理攻击触发；
## 魔法（anima/dark）与治疗杖（staff）普攻不触发。
static func is_physical_weapon(unit: Dictionary) -> bool:
	var weapon_type: StringName = unit.get(&"weapon", {}).get(&"type", &"sword")
	return not (weapon_type in [&"anima", &"dark", &"staff"])


## 对侧格坐标（纯几何，无单位语义）：T + signi(T - A) 逐轴。
## 攻击线斜向（dx、dy 均非 0）或同格（零向量）时返回 NO_CELL。
static func opposite_cell(attacker_pos: Vector2i, defender_pos: Vector2i) -> Vector2i:
	var dir := Vector2i(
		signi(defender_pos.x - attacker_pos.x),
		signi(defender_pos.y - attacker_pos.y)
	)
	if dir == Vector2i.ZERO or (dir.x != 0 and dir.y != 0):
		return NO_CELL
	return defender_pos + dir


## 找对侧追击友军：对侧格上恰有「与攻击者同阵营、与目标敌对、存活」的单位时
## 返回其 UnitData，否则返回 {}。allies 为候选池（调用方给 grid.units.values()
## 或阵营单位数组），内部按位置/阵营/存活过滤；不含任何伤害与落地逻辑。
static func pincer_partner(attacker: Dictionary, defender: Dictionary, allies: Array) -> Dictionary:
	var cell := opposite_cell(
		attacker.get(&"position", Vector2i.ZERO),
		defender.get(&"position", Vector2i.ZERO)
	)
	if cell == NO_CELL:
		return {}
	var attacker_faction = attacker.get(&"faction", &"")
	if attacker_faction == defender.get(&"faction", &""):
		return {}
	for raw in allies:
		var ally: Dictionary = raw
		if bool(ally.get(&"isDead", false)) or int(ally.get(&"hp", 1)) <= 0:
			continue
		if ally.get(&"position", NO_CELL) != cell:
			continue
		if ally.get(&"faction", &"") != attacker_faction:
			continue
		if StringName(ally.get(&"id", &"")) == StringName(attacker.get(&"id", &"")):
			continue
		return ally
	return {}
