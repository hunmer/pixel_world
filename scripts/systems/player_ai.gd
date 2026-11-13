## systems/player_ai.gd — 玩家方托管决策器
##
## 与 EnemyAI.decide 阵营中立、签名一致，仅多一个 pref 参数。
## pref = { priorityTargetId: StringName|"", strategy: StringName, difficulty: StringName }
## - strategy=auto 或 pref 为空 → 直接退化为 EnemyAI.decide（零侵入复用，透传难度）。
## - 其它策略在 EnemyAI 的「枚举可停留格 × 可达敌人」基础上，对 CombatSystem.preview 的伤害
##   按 strategy 加权打分，priorityTargetId 命中加绝对权重；难度档的残血集火加分同样生效，
##   候选选择按难度档 best/worst（novice 选最差）。
## 无可攻击目标时，朝优先目标（若存活）或最近敌人移动（复用 EnemyAI fallback）。

class_name PlayerAI
extends RefCounted

const AIDifficulty := preload("res://scripts/systems/ai_difficulty.gd")
const AIDifficultyScoring := preload("res://scripts/systems/ai_difficulty_scoring.gd")

const STRATEGY_AUTO       := &"auto"        # 复用 EnemyAI 行为（伤害最大化）
const STRATEGY_AGGRESSIVE := &"aggressive"  # 优先击杀
const STRATEGY_DEFENSIVE  := &"defensive"   # 规避反击
const STRATEGY_NEAREST    := &"nearest"     # 打最近的
const STRATEGY_WEAKEST    := &"weakest"     # 打残血

## 策略下拉显示项（key=StringName，value=中文标签）
const STRATEGY_OPTIONS: Array = [
	{ &"id": STRATEGY_AUTO,       &"label": "自动(伤害最大)" },
	{ &"id": STRATEGY_AGGRESSIVE, &"label": "激进(优先击杀)" },
	{ &"id": STRATEGY_DEFENSIVE,  &"label": "保守(规避反击)" },
	{ &"id": STRATEGY_NEAREST,    &"label": "最近(贴脸)" },
	{ &"id": STRATEGY_WEAKEST,    &"label": "残血(收割)" },
]


## 默认偏好（未配置单位退化为 auto，等价 EnemyAI）
static func default_pref() -> Dictionary:
	return { &"priorityTargetId": "", &"strategy": STRATEGY_AUTO }


## 决策。返回 { moveTarget: Vector2i|null, attackTarget: UnitData|{} }
static func decide(unit: Dictionary, grid: GridSystem, enemies: Array, pref: Dictionary = {}) -> Dictionary:
	if enemies.is_empty():
		return { &"moveTarget": null, &"attackTarget": {}, &"action": { &"type": &"normal" } }

	# 难度档：normalize 非法/缺失回 normal（与 EnemyAI 缺省一致）
	var difficulty: StringName = AIDifficulty.normalize(pref.get(&"difficulty", AIDifficulty.DEFAULT))
	var priority_id = pref.get(&"priorityTargetId", "")
	var strategy: StringName = pref.get(&"strategy", STRATEGY_AUTO)

	# 显式优先目标：存活则限定目标列表（任何难度/策略下用户意图优先；
	# 优先目标不可达时 EnemyAI 的 fallback 恰好会朝它移动，语义一致）。
	# limit_targets 让技能/物品候选同样只打优先目标（EnemyAI 内部从 grid 重取目标，
	# 仅缩小 enemies 列表拦不住技能/投掷物）。
	if strategy == STRATEGY_AUTO or pref.is_empty():
		var prio_auto := _find_alive(enemies, priority_id)
		if not prio_auto.is_empty():
			return EnemyAI.decide(unit, grid, [prio_auto], difficulty, [prio_auto])
		return EnemyAI.decide(unit, grid, enemies, difficulty)

	var prof: Dictionary = AIDifficulty.profile(difficulty)

	var ep: Vector2i = unit[&"position"]
	var res: Dictionary = grid.compute_attack_range(ep.x, ep.y, unit)
	var move_range: Dictionary = res[&"moveRange"]

	# 收集可停留的格子（EnemyAI 同款过滤）
	var stops: Array = []
	for k in move_range.keys():
		var parts := (k as String).split(",")
		var x: int = parts[0].to_int()
		var y: int = parts[1].to_int()
		var u: Dictionary = grid.unit_at(x, y)
		if u.is_empty() or u[&"id"] == unit[&"id"]:
			stops.append(Vector2i(x, y))

	var attack_range: Array = ProfessionData.unit_attack_range(unit)

	# 枚举 (stop, target) 按 strategy 打分
	var best: Dictionary = {} # { stop, target, score }
	for stop in stops:
		for p in enemies:
			if p[&"isDead"]:
				continue
			var dist := absi(stop.x - p[&"position"].x) + absi(stop.y - p[&"position"].y)
			if dist < attack_range[0] or dist > attack_range[1]:
				continue
			var tile: Dictionary = grid.tile_at(p[&"position"].x, p[&"position"].y)
			var prev := CombatSystem.preview(unit, p, tile.get(&"avoid_bonus", 0), tile.get(&"def_bonus", 0))
			var score := _score_target(unit, p, prev, dist, strategy)
			# 难度档：残血集火加分
			score += AIDifficultyScoring.focus_bonus(p, prof)
			# 优先目标绝对加权（novice 的 worst 档反转：推高「非优先」目标分使其被排除，
			# 保证显式优先目标在任何难度下都胜出）
			if priority_id != "":
				if priority_id == p[&"id"]:
					if prof[&"selection"] != &"worst":
						score += 100000
				elif prof[&"selection"] == &"worst":
					score += 100000
			if best.is_empty() or AIDifficultyScoring.better(score, best[&"score"], prof):
				best = { &"stop": stop, &"target": p, &"score": score }

	if not best.is_empty():
		return {
			&"moveTarget": best[&"stop"],
			&"attackTarget": best[&"target"],
			&"action": { &"type": &"normal", &"targets": [best[&"target"]] },
		}

	# novice 档不追击：无攻击目标时原地待命（与 EnemyAI fallback 的 pursue 语义一致）
	if not AIDifficultyScoring.should_pursue(prof):
		return { &"moveTarget": null, &"attackTarget": {}, &"action": { &"type": &"normal" } }

	# 无可攻击目标 → 朝优先目标（若存活）或最近敌人移动
	var move_target: Dictionary = {}
	if priority_id != "":
		for p in enemies:
			if not p[&"isDead"] and p[&"id"] == priority_id:
				move_target = p
				break
	if move_target.is_empty():
		var nearest_dist := INF
		for p in enemies:
			if p[&"isDead"]:
				continue
			var d: int = absi(p[&"position"].x - ep.x) + absi(p[&"position"].y - ep.y)
			if d < nearest_dist:
				nearest_dist = d
				move_target = p
	if move_target.is_empty():
		return { &"moveTarget": null, &"attackTarget": {}, &"action": { &"type": &"normal" } }

	# 在移动范围内找最接近 move_target 的格子
	var closest_stop = null
	var closest_dist := INF
	for k in move_range.keys():
		var parts := (k as String).split(",")
		var x: int = parts[0].to_int()
		var y: int = parts[1].to_int()
		var d: int = absi(x - move_target[&"position"].x) + absi(y - move_target[&"position"].y)
		if d < closest_dist:
			closest_dist = d
			closest_stop = Vector2i(x, y)
	return { &"moveTarget": closest_stop, &"attackTarget": {}, &"action": { &"type": &"normal" } }


## 在候选列表里找存活的优先目标（找不到返回空 dict）。
static func _find_alive(enemies: Array, id) -> Dictionary:
	if String(id) == "":
		return {}
	for e in enemies:
		if not bool(e.get(&"isDead", false)) and e.get(&"id", "") == id:
			return e
	return {}


## 按 strategy 对单个 (stop, target, preview) 组合打分。
## unit 预留给未来扩展（如根据施法者属性调整），当前未使用故前缀下划线。
static func _score_target(_unit: Dictionary, target: Dictionary, prev: Dictionary, dist: int, strategy: StringName) -> float:
	var atk_dmg: int = prev[&"atkDmg"]
	var def_dmg: int = prev[&"defDmg"]
	var double_atk: bool = prev[&"doubleAttack"]
	# EnemyAI 同款基础分
	var base: float = float(atk_dmg * 2 + (atk_dmg if double_atk else 0))

	match strategy:
		STRATEGY_AGGRESSIVE:
			# 能击杀的招式最优先；否则用基础分
			if atk_dmg >= int(target[&"hp"]):
				return base + 50000
			return base
		STRATEGY_DEFENSIVE:
			# 规避反击：反击伤害越低越好；不会被反击额外加权
			var s: float = base - def_dmg * 3.0
			if def_dmg == 0:
				s += 500
			return s
		STRATEGY_NEAREST:
			# 距离主导，伤害仅作同距离时的 tiebreak
			return -float(dist) * 10.0 + base * 0.1
		STRATEGY_WEAKEST:
			# 收割残血：缺失血量越多越优先；能击杀再加分
			var missing: int = int(target[&"stats"][&"hp"]) - int(target[&"hp"])
			var s: float = base + float(missing) * 5.0
			if atk_dmg >= int(target[&"hp"]):
				s += 5000
			return s
		_:
			return base
