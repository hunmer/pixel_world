## systems/enemy_ai.gd — 敌方 AI 决策（对应 src/systems/EnemyAI.ts）
##
## 决策流程（从「只普攻」扩展为「普攻/技能/物品」三选一）：
##   1. 收集可停留格子 stops（移动范围内、未被占）。
##   2. 对每个 stop 枚举三类候选：
##      - 普攻：(stop, enemy_unit) → 伤害评分
##      - 技能：(stop, skill, skill_targets) → 技能效果评分
##      - 物品：(stop, item, item_targets) → 物品效果评分
##   3. 选全局最高分，返回 {moveTarget, action:{type, ...}}。
##   4. 无攻击/技能/物品候选时，朝最近敌人移动。
##
## 返回结构：
##   { moveTarget: Vector2i|null,
##     attackTarget: UnitData|{},              # 向后兼容（普攻目标）
##     action: { type: "normal"/"skill"/"item", skillId?, itemId?, targets:[UnitData] } }
## 无技能/物品可用时 action.type="normal"，attackTarget 即旧字段。

class_name EnemyAI
extends RefCounted


## AI 决策。players = 要攻击的目标列表（敌方阵营）。
static func decide(enemy: Dictionary, grid: GridSystem, players: Array) -> Dictionary:
	if players.is_empty():
		return { &"moveTarget": null, &"attackTarget": {}, &"action": { &"type": &"normal" } }

	var ep: Vector2i = enemy[&"position"]
	var res: Dictionary = grid.compute_attack_range(ep.x, ep.y, enemy)
	var move_range: Dictionary = res[&"moveRange"]

	# 收集可停留格子
	var stops: Array = []
	for k in move_range.keys():
		var parts := (k as String).split(",")
		var x: int = parts[0].to_int()
		var y: int = parts[1].to_int()
		var u: Dictionary = grid.unit_at(x, y)
		if u.is_empty() or u[&"id"] == enemy[&"id"]:
			stops.append(Vector2i(x, y))

	var attack_range: Array = ProfessionData.unit_attack_range(enemy)
	var best: Dictionary = {}  # { stop, score, action }

	# 候选 1：普攻（每个 stop × 每个敌方单位）
	for stop in stops:
		for p in players:
			if p.get(&"isDead", false):
				continue
			var dist := absi(stop.x - p[&"position"].x) + absi(stop.y - p[&"position"].y)
			if dist < attack_range[0] or dist > attack_range[1]:
				continue
			var tile: Dictionary = grid.tile_at(p[&"position"].x, p[&"position"].y)
			var prev := CombatSystem.preview(enemy, p, tile.get(&"avoid_bonus", 0), tile.get(&"def_bonus", 0))
			var score: int = prev[&"atkDmg"] * 2 + (prev[&"atkDmg"] if prev[&"doubleAttack"] else 0)
			# 能击杀大幅加分
			if prev[&"atkDmg"] >= int(p[&"hp"]):
				score += 5000
			# 扣掉会被反击的伤害（保守一点）
			score -= int(prev[&"defDmg"])
			_try_best(best, stop, score, { &"type": &"normal", &"targets": [p] })

	# 候选 2：技能（需要 enemy 站在 stop 上能用——简单起见假设移动不影响技能射程判断，
	# 这里以 enemy 当前位置评估技能目标，移动只用来靠近）。
	_evaluate_skill_candidates(enemy, grid, players, best, ep)
	# 候选 3：物品
	_evaluate_item_candidates(enemy, grid, players, best, ep)

	if not best.is_empty():
		var act: Dictionary = best[&"action"]
		var first_target: Dictionary = {}
		var tgts: Array = act.get(&"targets", [])
		if not tgts.is_empty():
			first_target = tgts[0]
		return {
			&"moveTarget": _pick_move_toward(enemy, move_range, best[&"stop"], ep),
			&"attackTarget": first_target,
			&"action": act,
		}

	# 无任何行动候选 → 朝最近敌人移动
	var nearest := _nearest_player(ep, players)
	if nearest.is_empty():
		return { &"moveTarget": null, &"attackTarget": {}, &"action": { &"type": &"normal" } }
	var closest := _closest_stop_to(move_range, nearest[&"position"])
	return {
		&"moveTarget": closest,
		&"attackTarget": {},
		&"action": { &"type": &"normal" },
	}


# ============================================================
# 候选评估
# ============================================================

## 枚举该单位可用技能，评估每个 (skill, targets) 组合的分数。
static func _evaluate_skill_candidates(
	caster: Dictionary, grid: GridSystem, _enemies: Array,
	best: Dictionary, caster_pos: Vector2i
) -> void:
	for sk in SkillData.usable_skills(caster):
		var sid: StringName = sk[&"id"]
		if not SkillSystem.can_use(caster, sid):
			continue
		# 技能目标用施法者当前位置评估（移动决策单独做）
		var targets: Array = SkillSystem.targets_for(caster, sid, grid)
		if targets.is_empty():
			continue
		var score: float = _score_skill(caster, sk, targets)
		# 技能的 moveTarget = 当前位置（不移动，原地施法）；后续 _pick_move_toward 会处理
		_try_best(best, caster_pos, score, {
			&"type": &"skill", &"skillId": sid, &"targets": targets,
		})


## 枚举背包可用物品，评估每个 (item, targets) 组合的分数。
static func _evaluate_item_candidates(
	user: Dictionary, grid: GridSystem, _enemies: Array,
	best: Dictionary, user_pos: Vector2i
) -> void:
	for ie in ItemData.usable_items(user):
		var entry: Dictionary = ie[&"entry"]
		var idef: Dictionary = ie[&"def"]
		var iid: StringName = idef[&"id"]
		var targets: Array = ItemSystem.targets_for(user, iid, grid)
		if targets.is_empty():
			continue
		var score: float = _score_item(user, idef, targets)
		_try_best(best, user_pos, score, {
			&"type": &"item", &"itemId": iid, &"entry": entry, &"targets": targets,
		})


## 技能评分：伤害型按总伤害+击杀；治疗型按恢复量；buff/debuff 按价值。
static func _score_skill(caster: Dictionary, sk: Dictionary, targets: Array) -> float:
	var score: float = 0.0
	match sk[&"type"]:
		&"damage":
			for t in targets:
				var preview_dmg := SkillSystem._skill_damage(caster, t, sk)
				score += preview_dmg * 2.0
				if preview_dmg >= int(t[&"hp"]):
					score += 4000   # 能击杀
		&"aoe":
			for t in targets:
				var preview_dmg := SkillSystem._skill_damage(caster, t, sk)
				score += preview_dmg * 2.5   # AOE 多目标加权
				if preview_dmg >= int(t[&"hp"]):
					score += 4000
		&"heal":
			for t in targets:
				var missing: int = int(t[&"stats"][&"hp"]) - int(t[&"hp"])
				if missing > 5:   # 只在有明显伤口时奶
					score += mini(missing, int(sk[&"power"])) * 1.5
		&"buff", &"debuff":
			# buff/debuff 基础价值较低，但在没有伤害选项时可用
			score += int(sk[&"buffValue"]) * 10.0 * targets.size()
	# 技能有 MP 成本，轻微惩罚（避免无脑用技能不用普攻）
	score -= int(sk[&"mpCost"]) * 0.5
	return score


## 物品评分：投掷物按伤害；消耗品按恢复；buff 按价值。物品不耗 MP，优先级略低于强力技能。
static func _score_item(_user: Dictionary, idef: Dictionary, targets: Array) -> float:
	var score: float = 0.0
	match idef[&"effect"]:
		&"damage":
			for t in targets:
				score += int(idef[&"power"]) * 2.0
				if int(idef[&"power"]) >= int(t[&"hp"]):
					score += 3000
		&"heal_hp":
			for t in targets:
				var missing: int = int(t[&"stats"][&"hp"]) - int(t[&"hp"])
				if missing > 5:
					score += mini(missing, int(idef[&"power"])) * 1.2
		&"heal_mp":
			score += 50.0   # 回 MP 价值较低，缺蓝时才用
		&"buff":
			score += int(idef[&"buffValue"]) * 8.0 * targets.size()
		&"cleanse":
			score += 80.0
	return score


# ============================================================
# 工具
# ============================================================

## 更新 best（取更高分）。
static func _try_best(best: Dictionary, stop: Vector2i, score: float, action: Dictionary) -> void:
	if best.is_empty() or score > float(best[&"score"]):
		best.clear()
		best[&"stop"] = stop
		best[&"score"] = score
		best[&"action"] = action


## 找最近的存活玩家单位。
static func _nearest_player(ep: Vector2i, players: Array) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_dist := INF
	for p in players:
		if p.get(&"isDead", false):
			continue
		var d: int = absi(p[&"position"].x - ep.x) + absi(p[&"position"].y - ep.y)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p
	return nearest


## 在 move_range 内找最接近 goal 的格子。
static func _closest_stop_to(move_range: Dictionary, goal: Vector2i) -> Vector2i:
	var closest := goal
	var closest_dist := INF
	for k in move_range.keys():
		var parts := (k as String).split(",")
		var x: int = parts[0].to_int()
		var y: int = parts[1].to_int()
		var d: int = absi(x - goal.x) + absi(y - goal.y)
		if d < closest_dist:
			closest_dist = d
			closest = Vector2i(x, y)
	return closest


## 决定最终 moveTarget：若 best.stop == 当前位置则不动；否则取 best.stop。
static func _pick_move_toward(_unit: Dictionary, _move_range: Dictionary, best_stop: Vector2i, cur_pos: Vector2i) -> Vector2i:
	if best_stop == cur_pos:
		return cur_pos
	return best_stop
