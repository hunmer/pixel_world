## battle/battle_action_resolver.gd — 战斗行动共享结算器（单一事实源）
##
## 从 battle.gd 提取的「纯结算 + 状态后处理」：普攻/技能/物品的 CombatSystem/
## SkillSystem/ItemSystem.execute 调用、死亡标志、hasActed/hasMoved、玩家方经验与升级。
## battle.gd（演出场景）与 battle automation runner（headless 无表现执行）共用本模块，
## 保证两套入口的战斗规则永远一致；任何规则修改只改这里。
##
## 职责边界：
##   - 本模块只 mutate 单位数据与标志位（含把死亡单位 isDead 置 true），不动 GridSystem
##     的占位表 —— grid.remove_unit 由调用方在演出完成后（或 runner 立即）执行。
##   - 随机流说明：execute 与 gain_exp 内部的 randf 按固定顺序消耗全局 RNG，
##     本模块保证「结算 randf → 经验 randf」与 battle.gd 原实现逐次对齐，
##     因此同 seed + 同动作序列在游戏内与 CLI 中产生完全相同的结果。
##
## 返回结构（三个 resolve_* 一致的骨架）：
##   { combat|skill|item = <系统原始 result>,
##     deaths: [UnitData, ...],          # 本次行动致死（isDead 已置 true，待 grid 移除）
##     exp: { amount: int, gained: bool, levels: [{level, gains:{stat:from->to}}] } }
##
## 注意：不负责战斗结束判定（check_victory 由调用方做）、不负责经验/伤害演出。

class_name BattleActionResolver
extends RefCounted


## 普攻结算。attacker/defender 为 UnitData；grid 用于取防守方地形加成。
## 与 battle.gd._resolve_combat_async 的结算部分逐行等价：
##   CombatSystem.execute → 死亡标志 → hasActed（敌方加 hasMoved）→ 玩家方经验。
static func resolve_attack(attacker: Dictionary, defender: Dictionary, grid: GridSystem) -> Dictionary:
	var def_tile: Dictionary = grid.tile_at(defender.position.x, defender.position.y)
	var result: Dictionary = CombatSystem.execute(
		attacker, defender, int(def_tile.avoid_bonus), int(def_tile.def_bonus)
	)
	var deaths: Array = []
	if bool(result.defenderDied):
		defender[&"isDead"] = true
		deaths.append(defender)
	if bool(result.attackerDied):
		attacker[&"isDead"] = true
		deaths.append(attacker)
	attacker[&"hasActed"] = true
	if attacker.faction == &"enemy":
		attacker[&"hasMoved"] = true
	var exp: Dictionary = { amount = 0, gained = false, levels = [] }
	if attacker.faction == &"player":
		if bool(result.defenderDied):
			exp = gain_exp(attacker, WeaponData.exp_for_kill(int(defender.level)))
		elif bool(result.attackerHits):
			exp = gain_exp(attacker, WeaponData.exp_for_hit(int(defender.level), int(attacker.level)))
	return { combat = result, deaths = deaths, exp = exp }


## 技能结算。与 battle.gd._resolve_skill 的结算部分逐行等价。
## 空目标时仅置 hasActed（与演出版早退分支一致，不消耗系统调用）。
static func resolve_skill(caster: Dictionary, targets: Array, skill_id: StringName) -> Dictionary:
	if targets.is_empty():
		caster[&"hasActed"] = true
		return { skill = {}, deaths = [], exp = { amount = 0, gained = false, levels = [] } }
	var result: Dictionary = SkillSystem.execute(caster, targets, skill_id)
	var deaths: Array = []
	for h in result[&"hits"]:
		if bool(h.get(&"died", false)):
			var victim: Dictionary = h[&"unit"]
			victim[&"isDead"] = true
			deaths.append(victim)
	caster[&"hasActed"] = true
	if caster.faction == &"enemy":
		caster[&"hasMoved"] = true
	var exp: Dictionary = { amount = 0, gained = false, levels = [] }
	var killed: int = deaths.size()
	if caster.faction == &"player" and killed > 0:
		exp = gain_exp(caster, WeaponData.exp_for_kill(int(targets[0][&"level"])) * killed)
	elif caster.faction == &"player" and not (result[&"hits"] as Array).is_empty():
		exp = gain_exp(caster, WeaponData.exp_for_hit(int(targets[0][&"level"]), int(caster[&"level"])))
	return { skill = result, deaths = deaths, exp = exp }


## 物品结算。与 battle.gd._resolve_item 的结算部分逐行等价（ItemSystem 无 RNG）。
## 空目标/空条目时仅置 hasActed（与演出版早退分支一致）。
static func resolve_item(user: Dictionary, targets: Array, item_entry: Dictionary) -> Dictionary:
	if targets.is_empty() or item_entry.is_empty():
		user[&"hasActed"] = true
		return { item = {}, deaths = [] }
	var result: Dictionary = ItemSystem.execute(user, targets, item_entry)
	var deaths: Array = []
	for h in result.get(&"hp_deltas", []):
		if bool(h.get(&"died", false)):
			var victim: Dictionary = h[&"unit"]
			victim[&"isDead"] = true
			deaths.append(victim)
	user[&"hasActed"] = true
	if user.faction == &"enemy":
		user[&"hasMoved"] = true
	return { item = result, deaths = deaths }


## 经验/升级结算（battle.gd._gain_exp 逐行等价，去掉演出）。
## 返回 { amount, gained, levels: [{ level:int, gains: { statKey: {from,to} } }] }。
static func gain_exp(u: Dictionary, amount: int) -> Dictionary:
	if bool(u.get(&"isDead", false)):
		return { amount = 0, gained = false, levels = [] }
	u[&"exp"] = int(u[&"exp"]) + amount
	var levels: Array = []
	while int(u[&"exp"]) >= WeaponData.exp_to_next(int(u[&"level"])) and int(u[&"level"]) < 20:
		u[&"exp"] = int(u[&"exp"]) - WeaponData.exp_to_next(int(u[&"level"]))
		u[&"level"] = int(u[&"level"]) + 1
		var g: Dictionary = u[&"growths"]
		var s: Dictionary = u[&"stats"]
		var gains: Dictionary = {}
		for k in g.keys():
			# 升级随机成长：每属性按 growths% 概率 +1（全局 randf，消耗顺序与 battle.gd 一致）
			if randf() * 100.0 < int(g[k]):
				gains[k] = { from = int(s[k]), to = int(s[k]) + 1 }
				s[k] = int(s[k]) + 1
		u[&"hp"] = int(u[&"stats"][&"hp"])  # 升 hp 上限后回满
		levels.append({ level = int(u[&"level"]), gains = gains })
	return { amount = amount, gained = true, levels = levels }
