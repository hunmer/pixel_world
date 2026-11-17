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
##   - 击杀掉落（可选 drop_ctx）只用调用方注入的 RandomNumberGenerator，绝不触碰
##     全局 randf/randf_range：掉落掷骰与上方契约流完全隔离，无表敌人零随机消费。
##
## 返回结构（三个 resolve_* 一致的骨架）：
##   { combat|skill|item = <系统原始 result>,
##     deaths: [UnitData, ...],          # 本次行动致死（isDead 已置 true，待 grid 移除）
##     exp: { amount: int, gained: bool, levels: [{level, gains:{stat:from->to}}] } }
##
## 击杀掉落上下文（三个 resolve_* 的可选尾参，默认空 = 完全不掷落，旧行为不变）：
##   drop_ctx = { rng: RandomNumberGenerator, loot: Array, rolled: Dictionary }
##   - rng：调用方创建并播种（battle.gd 用战场+token 哈希，runner 用 scenario seed 派生）。
##   - loot：调用方持有的普通数组（battle.gd 挂 chapter.pending_loot），
##     形如 [{ id: StringName, count: int }]，同 id 条目 count 累加合并。
##   - rolled：单位 id → true 的幂等表；同一敌人重复致死只掷一次，重试不重掷。
##   - 仅敌方单位参与：单位带非空 drop_table（由 battlefield_loader 严格校验后挂上）
##     且是新死亡时，按表加权掷 1 件（有放回权重归一，恰消耗 1 次 rng.randf()）。
##
## 注意：不负责战斗结束判定（check_victory 由调用方做）、不负责经验/伤害演出。

class_name BattleActionResolver
extends RefCounted


## 普攻结算。attacker/defender 为 UnitData；grid 用于取防守方地形加成。
## 与 battle.gd._resolve_combat_async 的结算部分逐行等价：
##   CombatSystem.execute → 死亡标志 → hasActed（敌方加 hasMoved）→ 玩家方经验。
## drop_ctx 可选（见文件头）；默认空 = 不掷落，普攻/反击致死均在此覆盖。
static func resolve_attack(
		attacker: Dictionary, defender: Dictionary, grid: GridSystem,
		drop_ctx: Dictionary = {}
) -> Dictionary:
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
	_settle_drop_loot(deaths, drop_ctx)
	return { combat = result, deaths = deaths, exp = exp }


## 技能结算。与 battle.gd._resolve_skill 的结算部分逐行等价。
## 空目标时仅置 hasActed（与演出版早退分支一致，不消耗系统调用）。
## drop_ctx 可选（见文件头）；技能致死在此覆盖。
static func resolve_skill(
		caster: Dictionary, targets: Array, skill_id: StringName,
		drop_ctx: Dictionary = {}
) -> Dictionary:
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
	_settle_drop_loot(deaths, drop_ctx)
	return { skill = result, deaths = deaths, exp = exp }


## 物品结算。与 battle.gd._resolve_item 的结算部分逐行等价（ItemSystem 无 RNG）。
## 空目标/空条目时仅置 hasActed（与演出版早退分支一致）。
## drop_ctx 可选（见文件头）；投掷物致死在此覆盖。
static func resolve_item(
		user: Dictionary, targets: Array, item_entry: Dictionary,
		drop_ctx: Dictionary = {}
) -> Dictionary:
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
	_settle_drop_loot(deaths, drop_ctx)
	return { item = result, deaths = deaths }


## 击杀掉落结算（仅 drop_ctx 非空时生效；详见文件头契约）。
## 每名「新死亡的带表敌人」恰消耗 1 次 ctx.rng.randf()；无表/重复致死零消耗。
static func _settle_drop_loot(deaths: Array, drop_ctx: Dictionary) -> void:
	if drop_ctx.is_empty() or deaths.is_empty():
		return
	var rng: RandomNumberGenerator = drop_ctx.get("rng", null)
	var loot: Array = drop_ctx.get("loot", [])
	var rolled: Dictionary = drop_ctx.get("rolled", {})
	if rng == null or loot == null or rolled == null:
		return
	for victim_value in deaths:
		var victim: Dictionary = victim_value
		if victim.get(&"faction", &"") != &"enemy":
			continue
		var uid: StringName = StringName(victim.get(&"id", &""))
		if rolled.has(uid):
			continue
		rolled[uid] = true
		var table: Array = victim.get(&"drop_table", [])
		if table.is_empty():
			continue
		# 单次加权掷骰：权重和归一后 randf()×total 落点；表已由 loader 严格校验。
		var total := 0.0
		for e in table:
			total += float((e as Dictionary).get("weight", 0.0))
		if total <= 0.0:
			continue
		var r := rng.randf() * total
		var acc := 0.0
		var picked: Dictionary = table[table.size() - 1]
		for e in table:
			acc += float((e as Dictionary).get("weight", 0.0))
			if r <= acc:
				picked = e
				break
		_merge_pending_entry(
			loot,
			StringName(String((picked as Dictionary).get("id", ""))),
			int((picked as Dictionary).get("count", 1))
		)


## 掉落条目并入 pending 数组：同 id count 累加，保持首现顺序（纯数组/字典，可编码）。
static func _merge_pending_entry(loot: Array, item_id: StringName, count: int) -> void:
	if item_id == &"" or count <= 0:
		return
	for entry_value in loot:
		var entry: Dictionary = entry_value
		if StringName(entry.get("id", &"")) == item_id:
			entry["count"] = int(entry.get("count", 0)) + count
			return
	loot.append({ "id": item_id, "count": count })


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
