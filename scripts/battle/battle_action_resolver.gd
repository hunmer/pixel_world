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
## 夹击追击（_apply_pincer，resolve_attack / resolve_skill 共用）：
##   - 触发：攻击方武器为物理口径（非 anima/dark/staff）+ 至少一击命中 +
##     目标整场结算后仍存活 + 目标「对侧相邻格」有与攻击方同阵营的存活友军
##     （判定 PincerRules.pincer_partner，正交攻击线 T+signi(T−A)；斜向/同格无对侧）。
##   - 结算：该友军立即追加一次攻击，伤害 = CombatSystem.pincer_damage（其普攻
##     preview.atkDmg 口径 ×0.5，roundi）。必中、无暴击、零 randf（随机流零消耗）、
##     不被反击、不递归（追击本身不再触发追击）、不消耗友军行动（不动
##     hasActed/hasMoved）；攻击方被反击致死不阻止追击；双击整场只追一次。
##   - 落地：追击 impact（含 pincer=true 标志）追加进 attack_event.impacts，顶层
##     event.pincer/event.pincer_id 由本模块后写（AttackEvent 构建器不感知）；
##     result.pincer = {active,partner_id,damage,died} 写在 combat/skill result 内。
##   - 追击致死：目标 isDead 置 true 并进 deaths（掉落/胜负走统一管线）；普攻路径
##     置 result.defenderDied=true 让攻击方拿击杀经验；技能路径经 deaths.size() 自动计入。
##   - 技能：resolve_skill 尾参 grid 非 null 时，element==physical 且 type∈{damage,aoe}
##     的伤害技能与普攻同规则追击（追击对象 = 首个命中目标）；heal/buff/debuff 与
##     物品投掷（resolve_item）不触发。
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

const AttackEventBuilder = preload("res://scripts/systems/attack_event.gd")
const FacingRules = preload("res://scripts/systems/facing_rules.gd")
const PincerRules = preload("res://scripts/systems/pincer_rules.gd")


## 普攻结算。attacker/defender 为 UnitData；grid 用于取防守方地形加成。
## 与 battle.gd._resolve_combat_async 的结算部分逐行等价：
##   CombatSystem.execute → 死亡标志 → hasActed（敌方加 hasMoved）→ 玩家方经验。
## drop_ctx 可选（见文件头）；默认空 = 不掷落，普攻/反击致死均在此覆盖。
static func resolve_attack(
		attacker: Dictionary, defender: Dictionary, grid: GridSystem,
		drop_ctx: Dictionary = {}
) -> Dictionary:
	# 出手转身：攻击者面向目标（与演出层 sprite 转身一致）。只转攻击者、不动
	# 受击者 —— 背击判定只看防守方朝向，本次背击不被消除；转身后防守方反击
	# 恒打攻击者正面（dot>0），视觉与结算一致。
	FacingRules.face_toward(attacker, defender.position)
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
	# 夹击追击：命中/物理/队形/目标存活由 _apply_pincer 统一判定（详见文件头
	# 契约；无论是否触发都写入 result.pincer，消费方键访问恒安全）。
	var pincer: Dictionary = _apply_pincer(
		attacker, defender, result, result.get(&"attack_event", {}),
		grid.units.values(), int(def_tile.def_bonus),
		bool(result.attackerHits)
	)
	if bool(pincer[&"died"]):
		# 追击致死：普攻路径置 defenderDied，攻击方拿击杀经验（定稿口径）。
		result[&"defenderDied"] = true
		deaths.append(defender)
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
## grid 可选（尾参）：非 null 且技能为物理伤害（element==physical、type∈{damage,aoe}）
## 时启用夹击追击（首个命中目标、结算后仍存活才触发；详见文件头契约）；
## 缺省 null = 完全不判定，旧调用零影响。
static func resolve_skill(
		caster: Dictionary, targets: Array, skill_id: StringName,
		drop_ctx: Dictionary = {}, grid: GridSystem = null
) -> Dictionary:
	if targets.is_empty():
		caster[&"hasActed"] = true
		return { skill = {}, deaths = [], exp = { amount = 0, gained = false, levels = [] } }
	# 出手转身（同 resolve_attack：面向首个目标，只转施放者）。
	FacingRules.face_toward(caster, targets[0][&"position"])
	var result: Dictionary = SkillSystem.execute(caster, targets, skill_id)
	var deaths: Array = []
	for h in result[&"hits"]:
		if bool(h.get(&"died", false)):
			var victim: Dictionary = h[&"unit"]
			victim[&"isDead"] = true
			deaths.append(victim)
	# 夹击追击：首个命中目标；物理技能判定走 main_hit，目标存活由
	# _apply_pincer 统一检查（详见文件头契约）。grid 非空时 pincer 键
	# 恒写入（heal/buff/MISS 等无 hits 路径写 inactive），grid=null 保持旧形状。
	if grid != null:
		if not (result[&"hits"] as Array).is_empty():
			var h0: Dictionary = (result[&"hits"] as Array)[0]
			var pincer_target: Dictionary = h0[&"unit"]
			var sk: Dictionary = SkillData.get_skill(skill_id)
			var is_physical_skill: bool = (
				sk.get(&"element", &"physical") == &"physical"
				and sk.get(&"type", &"") in [&"damage", &"aoe"]
			)
			var tile: Dictionary = grid.tile_at(
				pincer_target[&"position"].x, pincer_target[&"position"].y
			)
			var pincer: Dictionary = _apply_pincer(
				caster, pincer_target, result, result.get(&"attack_event", {}),
				grid.units.values(), int(tile.get(&"def_bonus", 0)),
				is_physical_skill  # hits 非空 = 有命中；物理/存活在此后统一判定
			)
			if bool(pincer[&"died"]):
				deaths.append(pincer_target)  # killed 计数 +1，exp/deaths 统一管线
		else:
			result[&"pincer"] = { &"active": false, &"partner_id": &"", &"damage": 0, &"died": false }
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
	# 出手转身（同 resolve_attack：面向首个目标，只转使用者）。
	FacingRules.face_toward(user, targets[0][&"position"])
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


## 夹击追击结算（resolve_attack / resolve_skill 共用；条件与契约见文件头）。
## source=攻击方；target=受击目标（调用方已保证整场结算后仍存活）；
## main_hit=主攻击是否命中（普攻 = result.attackerHits；技能 = hits 非空）；
## result=系统原始 result（本函数写入 pincer 摘要，未触发也为 active=false）；
## event=attack_event（追击 impact 追加进 impacts、顶层聚合 pincer/pincer_id 后写）；
## allies=攻击方阵营候选池（grid.units.values()）；defender_tile_def=目标地形防御。
## 返回 {active,partner_id,damage,died}（未触发 = active:false 其余零值）；
## 追击致死时 target.isDead 在此置 true，deaths 收集与经验标志由调用方处理。
## 零 randf（必中无暴击），随机流契约不受影响；不递归、不动友军行动标志。
static func _apply_pincer(
		source: Dictionary, target: Dictionary,
		result: Dictionary, event: Dictionary,
		allies: Array, defender_tile_def: int, main_hit: bool
) -> Dictionary:
	var info: Dictionary = { &"active": false, &"partner_id": &"", &"damage": 0, &"died": false }
	result[&"pincer"] = info
	if not main_hit:
		return info
	# 目标在整场结算后仍存活才追击（主攻击杀 / 技能击杀均在此挡下，
	# 保证「击杀不追击」口径且 pincer 键恒存在）。
	if bool(target.get(&"isDead", false)) or int(target.get(&"hp", 0)) <= 0:
		return info
	if not PincerRules.is_physical_weapon(source) or allies.is_empty():
		return info
	var partner: Dictionary = PincerRules.pincer_partner(source, target, allies)
	if partner.is_empty():
		return info
	var dmg: int = CombatSystem.pincer_damage(partner, target, defender_tile_def)
	# 追击友军面向目标（只转身；不移动、不动 hasActed/hasMoved）。
	FacingRules.face_toward(partner, target[&"position"])
	var hp_before := int(target[&"hp"])
	target[&"hp"] = maxi(0, hp_before - dmg)
	var died := int(target[&"hp"]) <= 0
	var impact: Dictionary = AttackEventBuilder.make_impact(
			partner, target, true, dmg, hp_before, int(target[&"hp"]))
	impact[&"pincer"] = true
	if not event.is_empty():
		(event[&"impacts"] as Array).append(impact)
		event[&"pincer"] = true
		event[&"pincer_id"] = StringName(partner.get(&"id", &""))
	info[&"active"] = true
	info[&"partner_id"] = StringName(partner.get(&"id", &""))
	info[&"damage"] = dmg
	info[&"died"] = died
	if died:
		target[&"isDead"] = true
	return info


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
