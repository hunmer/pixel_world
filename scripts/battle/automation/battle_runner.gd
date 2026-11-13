## battle/automation/battle_runner.gd — 声明式战场的无表现执行器
##
## 职责：消费 BattleScenarioLoader 产出的标准 scenario，按阵营执行模式
## （脚本队列 / AI）驱动回合，全部结算走 BattleActionResolver（与 battle.gd
## 同一业务规则：命中/技能/物品/死亡/经验/升级），产出过程事件流与结果。
## 不含任何 SceneTree 依赖（纯逻辑，可被 CLI 与契约测试直接调用）。
##
## 公开 API：
##   run(scenario) -> Dictionary { ok, events, result, exit_code }
##     exit_code: 0=正常+断言过；1=断言失败；2=输入/非法操作；3=轮数步数上限；4=内部错误

class_name BattleRunner
extends RefCounted

const Resolver = preload("res://scripts/battle/battle_action_resolver.gd")

# 运行态（单次 run 内有效）
var _grid: GridSystem = null
var _turn: TurnManager = null
var _chapter: Dictionary = {}
var _events: Array = []
var _seq: int = 0
var _steps: int = 0
var _script_cursor := {}   # faction(StringName) -> int 下一条脚本索引
var _stop_reason: StringName = &""
var _winner: StringName = &""
var _battle_over: bool = false
var _illegal: String = ""  # 非空 = exit 2 的定位信息
var _limits: Dictionary = {}


## 执行场景，返回事件流与结果。同一 runner 实例可重复 run（状态全部重置）。
static func run(scenario: Dictionary) -> Dictionary:
	var r := new()
	return r._run(scenario)


func _run(scenario: Dictionary) -> Dictionary:
	# 状态复位（支持实例复用）
	_events = []
	_seq = 0
	_steps = 0
	_script_cursor = {&"player": 0, &"enemy": 0}
	_stop_reason = &""
	_winner = &""
	_battle_over = false
	_illegal = ""
	_chapter = scenario["chapter"]
	_limits = scenario["limits"].duplicate()
	_limits["stop_after_steps"] = int(scenario["stop_after_steps"])
	# 1) RNG：runner 的全部随机判定来源（CombatSystem/SkillSystem/升级成长的 randf）
	seed(int(scenario["seed"]))
	# 2) 战场构建（与 battle.gd _ready 相同：GridSystem + place 全部单位）
	_grid = GridSystem.new(int(_chapter["width"]), int(_chapter["height"]), _chapter["map"])
	for u in (_chapter["playerUnits"] as Array):
		_grid.place_unit(u, (u[&"position"] as Vector2i).x, (u[&"position"] as Vector2i).y)
	for u in (_chapter["enemyUnits"] as Array):
		_grid.place_unit(u, (u[&"position"] as Vector2i).x, (u[&"position"] as Vector2i).y)
	# 3) 初始化覆盖（loader 已校验单位存在与字段白名单）
	for uid in (scenario["overrides"] as Dictionary):
		var u: Dictionary = _grid.units[uid]
		for field in (scenario["overrides"][uid] as Dictionary):
			u[StringName(String(field))] = (scenario["overrides"][uid] as Dictionary)[field]
	# 4) TurnManager（不入树：其相位推进/tick/胜负判定均为纯数据操作）
	var all_units: Array = []
	all_units.append_array(_chapter["playerUnits"])
	all_units.append_array(_chapter["enemyUnits"])
	_turn = TurnManager.new(all_units)
	# 5) 初始快照（overrides 之后、任何行动之前）
	_initial_units = _units_snapshot()
	_emit({
		"type": &"battle_start",
		"seed": int(scenario["seed"]),
		"scenario_id": String(scenario["id"]),
		"source": String(scenario["source"]),
		"map": _map_snapshot(),
		"units": _initial_units.duplicate(true),
	})
	# 6) 主循环（镜像 battle.gd/turn_director 的相位驱动）
	_turn.start_player_phase()
	while true:
		if _battle_over or _illegal != "":
			break
		if int(_turn.turn_number) > int(_limits["max_turns"]):
			_stop_reason = &"max_turns"
			break
		var phase := _turn.phase
		_emit({
			"type": &"phase_start",
			"phase": phase,
			"turn": int(_turn.turn_number),
		})
		if phase == &"player":
			_run_phase(&"player", scenario["factions"][&"player"])
		else:
			_run_phase(&"enemy", scenario["factions"][&"enemy"])
		if _battle_over or _illegal != "":
			break
		if _stop_reason != &"":
			break  # stop_after_steps / max_steps 在 phase 内已置因
		_emit({
			"type": &"turn_end",
			"phase": phase,
			"turn": int(_turn.turn_number),
		})
		_turn.end_turn()
	# 7) 收尾事件
	if _illegal != "":
		_stop_reason = &"illegal_action"
		_emit({"type": &"stop", "reason": _stop_reason, "steps": _steps, "turns": int(_turn.turn_number), "error": _illegal})
	elif _battle_over:
		_emit({"type": &"battle_end", "winner": _winner, "steps": _steps, "turns": int(_turn.turn_number)})
	else:
		_emit({"type": &"stop", "reason": _stop_reason, "steps": _steps, "turns": int(_turn.turn_number)})
	# 8) 结果组装 + 断言评估（在 free TurnManager 之前完成对它的读取）
	var result := _build_result(scenario)
	var exit_code := _exit_code(result)
	_turn.free()
	_turn = null
	return {"ok": true, "events": _events, "result": result, "exit_code": exit_code}


## ---- 相位执行 ----------------------------------------------------------


func _run_phase(faction: StringName, cfg: Dictionary) -> void:
	if cfg["mode"] == &"script":
		_run_script_phase(faction, cfg)
	else:
		_run_ai_phase(faction, cfg)


## 脚本阵营：按队列逐条执行；end_turn 提前结束；队列耗尽按 exhausted 配置。
func _run_script_phase(faction: StringName, cfg: Dictionary) -> void:
	var script: Array = cfg["script"]
	var exhausted: StringName = cfg["exhausted"]
	while not _all_acted(faction):
		if _battle_over or _illegal != "":
			return
		var cursor: int = int(_script_cursor[faction])
		if cursor >= script.size():
			if exhausted == &"fail":
				_illegal = "factions.%s 脚本在 step=%d 耗尽（exhausted=fail）" % [String(faction), _steps]
				return
			# 缺省/明确 wait：剩余单位逐个置 wait（与脚本显式 wait 同事件形态）
			for u in _alive_units(faction):
				if not bool(u[&"hasActed"]):
					u[&"hasActed"] = true
					_emit({"type": &"wait", "actor": u[&"id"], "source": &"script_exhausted"})
			return
		var entry: Dictionary = script[cursor]
		_script_cursor[faction] = cursor + 1
		if entry["kind"] == &"end_turn":
			return  # 提前结束本 phase；未行动单位标志由下一相位开始复位（与游戏一致）
		_exec_script_entry(faction, entry)
		_after_step_checks()
		if _battle_over or _illegal != "":
			return
		if _steps_exceeded():
			return


## AI 阵营：逐个未行动单位 decide → 执行（镜像 turn_director 的驱动方式）。
func _run_ai_phase(faction: StringName, cfg: Dictionary) -> void:
	var foes := _alive_units(&"enemy" if faction == &"player" else &"player")
	if foes.is_empty():
		# 镜像 _player_auto_act：无敌人可打 → 标记全员已行动
		for u in _alive_units(faction):
			u[&"hasMoved"] = true
			u[&"hasActed"] = true
		return
	for u in _alive_units(faction):
		if _battle_over or _illegal != "" or _steps_exceeded():
			return
		if bool(u[&"hasActed"]) or bool(u[&"isDead"]):
			continue
		var decision: Dictionary
		if faction == &"player":
			decision = PlayerAI.decide(u, _grid, foes, cfg["ai_pref"])
		else:
			decision = EnemyAI.decide(u, _grid, foes)
		_exec_ai_decision(faction, u, decision)
		_after_step_checks()


## 单条脚本条目执行：move（可选）→ 终结构动作。全部校验失败 = exit 2 定位信息。
func _exec_script_entry(faction: StringName, entry: Dictionary) -> void:
	var uid: StringName = entry["unit"]
	var u: Dictionary = _grid.units.get(uid, {})
	if u.is_empty():
		_illegal = "step=%d 单位 %s 不存在" % [_steps + 1, String(uid)]
		return
	if bool(u[&"isDead"]):
		_illegal = "step=%d 单位 %s 已死亡，不能行动" % [_steps + 1, String(uid)]
		return
	if bool(u[&"hasActed"]):
		_illegal = "step=%d 单位 %s 本回合已行动（hasActed）" % [_steps + 1, String(uid)]
		return
	if u[&"faction"] != faction:
		_illegal = "step=%d 单位 %s 属于 %s 阵营，不能出现在 factions.%s 脚本里" % [
			_steps + 1, String(uid), String(u[&"faction"]), String(faction)]
		return
	# move（可选）：校验可达 + 目标格空闲
	var move: Dictionary = entry["move"]
	if not move.is_empty():
		var to := Vector2i(int(move["x"]), int(move["y"]))
		if _grid.cell_to_unit[to.y][to.x] != null and _grid.cell_to_unit[to.y][to.x] != u:
			_illegal = "step=%d %s 移动目标 (%d,%d) 已被 %s 占用" % [
				_steps + 1, String(uid), to.x, to.y, String(_grid.cell_to_unit[to.y][to.x].get(&"id", &""))]
			return
		var path: Array = []
		if to != (u[&"position"] as Vector2i):
			path = _grid.find_path(u[&"position"], to, u[&"moveType"], u[&"stats"][&"mov"])
			if path.is_empty():
				_illegal = "step=%d %s 无法从 %s 移动到 (%d,%d)（不可达或超出移动力 %d）" % [
					_steps + 1, String(uid), str(u[&"position"]), to.x, to.y, int(u[&"stats"][&"mov"])]
				return
			_grid.place_unit(u, to.x, to.y)
			u[&"hasMoved"] = true
		_emit({
			"type": &"move",
			"actor": uid,
			"source": &"script",
			"from": _vec_dict(path[0] if not path.is_empty() else u[&"position"]),
			"to": _vec_dict(to),
			"path": _path_snapshot(path if not path.is_empty() else [u[&"position"]]),
		})
	# 终结构动作
	var action: Dictionary = entry["action"]
	var kind: StringName = action["kind"]
	var payload: Dictionary = action["payload"]
	match kind:
		&"attack":
			var target: Dictionary = _grid.units.get(payload["target"], {})
			if target.is_empty() or bool(target[&"isDead"]):
				_illegal = "step=%d %s 的攻击目标 %s 不存在或已死亡" % [
					_steps + 1, String(uid), String(payload["target"])]
				return
			var dist := _manhattan(u[&"position"], target[&"position"])
			var rng := ProfessionData.unit_attack_range(u)
			if dist < int(rng[0]) or dist > int(rng[1]):
				_illegal = "step=%d %s 与 %s 距离 %d 不在攻击范围 [%d,%d] 内" % [
					_steps + 1, String(uid), String(payload["target"]), dist, int(rng[0]), int(rng[1])]
				return
			_resolve_and_emit_attack(u, target, &"script")
		&"skill":
			_exec_skill(u, payload, &"script")
		&"item":
			_exec_item(u, payload, &"script")
		&"wait":
			u[&"hasActed"] = true
			_emit({"type": &"wait", "actor": uid, "source": &"script"})


## 技能执行（脚本）：拥有 + 可用（MP/冷却）+ 目标在合法目标集内。
func _exec_skill(caster: Dictionary, payload: Dictionary, source: StringName) -> void:
	var skill_id: StringName = payload["skill_id"]
	if not (caster[&"skills"] as Array).has(skill_id):
		_illegal = "step=%d %s 不拥有技能 %s" % [_steps + 1, String(caster[&"id"]), String(skill_id)]
		return
	if not SkillSystem.can_use(caster, skill_id):
		_illegal = "step=%d %s 当前不能使用技能 %s（MP 不足或冷却中）" % [
			_steps + 1, String(caster[&"id"]), String(skill_id)]
		return
	var legal := {}
	for t in SkillSystem.targets_for(caster, skill_id, _grid):
		legal[t[&"id"]] = true
	var targets: Array = []
	for tid in (payload["targets"] as Array):
		var t: Dictionary = _grid.units.get(tid, {})
		if t.is_empty() or bool(t[&"isDead"]):
			_illegal = "step=%d 技能 %s 的目标 %s 不存在或已死亡" % [
				_steps + 1, String(skill_id), String(tid)]
			return
		if not legal.has(tid):
			_illegal = "step=%d %s 不是技能 %s 的合法目标（距离/目标类型不符）" % [
				_steps + 1, String(tid), String(skill_id)]
			return
		targets.append(t)
	var outcome := Resolver.resolve_skill(caster, targets, skill_id)
	_emit_skill_event(caster, skill_id, outcome, source)


## 物品执行（脚本）：背包条目 + 可用 + 目标在合法目标集内。
func _exec_item(user: Dictionary, payload: Dictionary, source: StringName) -> void:
	var item_id: StringName = payload["item_id"]
	var entry: Dictionary = {}
	for e in (user[&"items"] as Array):
		if e.get(&"id", &"") == item_id and int(e.get(&"uses", 0)) > 0:
			entry = e
			break
	if entry.is_empty():
		_illegal = "step=%d %s 背包中没有可用的 %s（未携带或已耗尽）" % [
			_steps + 1, String(user[&"id"]), String(item_id)]
		return
	if not ItemSystem.can_use(user, entry):
		_illegal = "step=%d %s 当前不能使用物品 %s" % [_steps + 1, String(user[&"id"]), String(item_id)]
		return
	var legal := {}
	for t in ItemSystem.targets_for(user, item_id, _grid):
		legal[t[&"id"]] = true
	var targets: Array = []
	for tid in (payload["targets"] as Array):
		var t: Dictionary = _grid.units.get(tid, {})
		if t.is_empty() or bool(t[&"isDead"]):
			_illegal = "step=%d 物品 %s 的目标 %s 不存在或已死亡" % [
				_steps + 1, String(item_id), String(tid)]
			return
		if not legal.has(tid):
			_illegal = "step=%d %s 不是物品 %s 的合法目标（距离/目标类型不符）" % [
				_steps + 1, String(tid), String(item_id)]
			return
		targets.append(t)
	var outcome := Resolver.resolve_item(user, targets, entry)
	_emit_item_event(user, item_id, entry, outcome, source)


## AI 决策执行（镜像 turn_director._player_auto_act/_enemy_act 的行为序列）。
func _exec_ai_decision(faction: StringName, u: Dictionary, decision: Dictionary) -> void:
	var source := &"ai"
	# 移动（AI 自算的 moveTarget；信任其与 compute_move_range 一致）
	var move_target = decision.get("moveTarget", null)
	if move_target != null and move_target is Vector2i:
		var to: Vector2i = move_target
		if to != (u[&"position"] as Vector2i):
			var path: Array = _grid.find_path(u[&"position"], to, u[&"moveType"], u[&"stats"][&"mov"])
			if not path.is_empty():
				_grid.place_unit(u, to.x, to.y)
				u[&"hasMoved"] = true
				_emit({
					"type": &"move",
					"actor": u[&"id"],
					"source": source,
					"from": _vec_dict(path[0]),
					"to": _vec_dict(to),
					"path": _path_snapshot(path),
				})
	# 终结构动作（镜像 _player_auto_act：skill/item 优先，普攻看 attackTarget）
	var action: Dictionary = decision.get("action", {})
	var atype: StringName = action.get("type", &"normal")
	if atype == &"skill" and action.has(&"skillId"):
		var outcome := Resolver.resolve_skill(u, action.get(&"targets", []), action[&"skillId"])
		_emit_skill_event(u, action[&"skillId"], outcome, source)
	elif atype == &"item" and action.has(&"itemId"):
		var entry: Dictionary = action.get(&"entry", {})
		var outcome := Resolver.resolve_item(u, action.get(&"targets", []), entry)
		_emit_item_event(u, entry.get(&"id", &""), entry, outcome, source)
	elif decision.get("attackTarget", {}) is Dictionary and not (decision["attackTarget"] as Dictionary).is_empty() and not bool((decision["attackTarget"] as Dictionary).get(&"isDead", true)):
		_resolve_and_emit_attack(u, decision["attackTarget"], source)
	else:
		u[&"hasActed"] = true
		_emit({"type": &"wait", "actor": u[&"id"], "source": source})
	# 敌方 AI 行动后无条件置 hasActed（与 turn_director._enemy_act 一致）
	if faction == &"enemy":
		u[&"hasActed"] = true


## 普攻结算 + 事件（resolver 与 battle.gd 共用同一规则实现）。
func _resolve_and_emit_attack(attacker: Dictionary, defender: Dictionary, source: StringName) -> void:
	var outcome := Resolver.resolve_attack(attacker, defender, _grid)
	var combat: Dictionary = outcome[&"combat"]
	_emit({
		"type": &"attack",
		"actor": attacker[&"id"],
		"source": source,
		"target": defender[&"id"],
		"hit": bool(combat[&"attackerHits"]),
		"crit": bool(combat[&"isCrit"]),
		"counter": bool(combat[&"defenderHits"]),
		"double": bool(combat[&"isDoubleAttack"]),
		"damage": int(combat[&"attackerDamage"]),
		"counter_damage": int(combat[&"defenderDamage"]),
		"attacker_hp_after": int(attacker[&"hp"]),
		"defender_hp_after": int(defender[&"hp"]),
	})
	_emit_deaths_and_exp(attacker, outcome)


func _emit_skill_event(caster: Dictionary, skill_id: StringName, outcome: Dictionary, source: StringName) -> void:
	var skill_res: Dictionary = outcome[&"skill"]
	var hits: Array = []
	for h in (skill_res.get(&"hits", []) as Array):
		var t: Dictionary = h[&"unit"]
		hits.append({
			"unit": t[&"id"],
			"hit": true,
			"damage": int(h.get(&"dmg", 0)),
			"hp_delta": int(h.get(&"hp_delta", 0)),
			"hp_after": int(t[&"hp"]),
			"died": bool(h.get(&"died", false)),
		})
	for m in (skill_res.get(&"missed", []) as Array):
		var t2: Dictionary = m[&"unit"] if (m is Dictionary and m.has(&"unit")) else m
		hits.append({"unit": t2.get(&"id", &""), "hit": false})
	_emit({
		"type": &"skill",
		"actor": caster[&"id"],
		"source": source,
		"skill": skill_id,
		"mp_cost": int(skill_res.get(&"mp_cost", 0)),
		"mp_after": int(caster[&"mp"]),
		"cooldown": int(caster[&"skillCooldowns"].get(skill_id, 0)),
		"hits": hits,
		"healed": int((skill_res.get(&"healed", []) as Array).size()),
		"buffed": int((skill_res.get(&"buffed", []) as Array).size()),
	})
	_emit_deaths_and_exp(caster, outcome)


func _emit_item_event(user: Dictionary, item_id: StringName, entry: Dictionary, outcome: Dictionary, source: StringName) -> void:
	var item_res: Dictionary = outcome[&"item"]
	var hp_deltas: Array = []
	for h in (item_res.get(&"hp_deltas", []) as Array):
		var t: Dictionary = h[&"unit"]
		hp_deltas.append({
			"unit": t[&"id"],
			"delta": int(h.get(&"delta", 0)),
			"hp_after": int(t[&"hp"]),
			"died": bool(h.get(&"died", false)),
		})
	_emit({
		"type": &"item",
		"actor": user[&"id"],
		"source": source,
		"item": item_id,
		"uses_left": int(entry.get(&"uses", 0)),
		"consumed": bool(item_res.get(&"entry_consumed", false)),
		"hp_deltas": hp_deltas,
		"mp_deltas": int((item_res.get(&"mp_deltas", []) as Array).size()),
	})
	_emit_deaths_and_exp(user, outcome)


## 死亡/经验/升级事件（resolver 已完成结算，这里只补 grid 移除与事件流）。
func _emit_deaths_and_exp(actor: Dictionary, outcome: Dictionary) -> void:
	for victim in (outcome[&"deaths"] as Array):
		_grid.remove_unit(victim)
		_emit({"type": &"death", "actor": victim[&"id"], "source": &"resolver"})
	var exp: Dictionary = outcome.get(&"exp", {})
	if bool(exp.get(&"gained", false)):
		_emit({
			"type": &"exp",
			"actor": actor[&"id"],
			"amount": int(exp[&"amount"]),
			"exp_total": int(actor[&"exp"]),
			"levels": int((exp.get(&"levels", []) as Array).size()),
		})
		for lv in (exp.get(&"levels", []) as Array):
			_emit({"type": &"level_up", "actor": actor[&"id"], "level": int(lv), "source": &"resolver"})
	_check_battle_end()


## ---- 每步护栏与胜负 ----------------------------------------------------


## 一个单位终结构行动完成后的公共检查（步数推进 + 上限）。
func _after_step_checks() -> void:
	_steps += 1


## 步数护栏：max_steps 超限 = 僵持保护（exit 3）；stop_after_steps = 短复现正常停（exit 0）。
func _steps_exceeded() -> bool:
	if _battle_over or _illegal != "":
		return true
	if int(_limits["max_steps"]) > 0 and _steps >= int(_limits["max_steps"]):
		_stop_reason = &"max_steps"
		return true
	if int(_limits["stop_after_steps"]) > 0 and _steps >= int(_limits["stop_after_steps"]):
		_stop_reason = &"stop_after_steps"
		return true
	return false


func _check_battle_end() -> void:
	if _battle_over:
		return
	var v := _turn.check_victory(_chapter["enemyUnits"])
	if v == &"win" or v == &"lose":
		_battle_over = true
		_winner = &"player" if v == &"win" else &"enemy"


func _all_acted(faction: StringName) -> bool:
	if faction == &"player":
		return _turn.all_player_acted()
	return _turn.all_enemy_acted()


func _alive_units(faction: StringName) -> Array:
	var out: Array = []
	for u in _grid.units.values():
		if u[&"faction"] == faction and not bool(u[&"isDead"]):
			out.append(u)
	return out


## ---- 结果组装与断言 ----------------------------------------------------


func _build_result(scenario: Dictionary) -> Dictionary:
	var stop_reason := _stop_reason
	if _illegal != "":
		stop_reason = &"illegal_action"
	elif _battle_over:
		stop_reason = &"victory" if _winner == &"player" else &"defeat"
	var result := {
		"version": int(scenario["version"]),
		"scenario_id": String(scenario["id"]),
		"source": String(scenario["source"]),
		"seed": int(scenario["seed"]),
		"outcome": {
			"winner": _winner,
			"battle_over": _battle_over,
			"stop_reason": stop_reason,
			"turns": _turn.turn_number if _turn != null else 0,
			"steps": _steps,
		},
		"limits": {
			"max_turns": int(_limits["max_turns"]),
			"max_steps": int(_limits["max_steps"]),
			"stop_after_steps": int(scenario["stop_after_steps"]),
		},
		"error": _illegal,
		"map": _map_snapshot(),
		"initial_units": _initial_units,
		"final_units": _units_snapshot(),
		"assertions": _evaluate_assertions(scenario["assertions"]),
	}
	return result


var _initial_units: Array = []


func _evaluate_assertions(assertions: Array) -> Array:
	var out: Array = []
	for a in assertions:
		var ok := true
		var detail := ""
		var atype: StringName = a["type"]
		var op: StringName = a["op"]
		var actual: Variant = null
		match atype:
			&"winner":
				actual = _winner
				ok = _compare(op, actual, a["value"])
			&"battle_over":
				actual = _battle_over
				ok = _compare(op, actual, a["value"])
			&"unit_alive":
				actual = _final_unit_alive(a["unit"])
				ok = _compare(op, actual, a["value"])
			&"unit_hp":
				actual = _final_unit_hp(a["unit"])
				ok = _compare(op, actual, a["value"])
			&"unit_position":
				actual = _final_unit_pos(a["unit"])
				var want := {"x": int(a["x"]), "y": int(a["y"])}
				ok = (actual != null and int(actual["x"]) == want["x"] and int(actual["y"]) == want["y"])
			&"turn_number":
				actual = _turn.turn_number if _turn != null else 0
				ok = _compare(op, actual, a["value"])
			&"steps":
				actual = _steps
				ok = _compare(op, actual, a["value"])
			&"event_count":
				actual = _events.size()
				ok = _compare(op, actual, a["value"])
		if actual == null and atype in [&"unit_alive", &"unit_hp", &"unit_position"]:
			ok = false
			detail = "单位 %s 不存在于最终快照" % String(a.get("unit", &""))
		var label := String(atype)
		if String(a.get("unit", "")) != "":
			label += " " + String(a["unit"])
		var summary := "%s %s %s → 实际 %s" % [
			label,
			String(op),
			_value_text(a.get("value", null)),
			_value_text(actual),
		]
		if detail != "":
			summary += "；" + detail
		out.append({
			"index": int(a["index"]),
			"type": atype,
			"op": op,
			"expected": a.get("value", null),
			"actual": actual,
			"passed": ok,
			"detail": detail,
			"summary": summary,
		})
	return out


## 断言值的人读形式。
func _value_text(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL:
			return "null"
		TYPE_STRING_NAME:
			return "(无胜方)" if v == &"" else String(v)
		_:
			return str(v)


func _final_unit_alive(uid: StringName) -> Variant:
	for u in _units_snapshot():
		if u["id"] == String(uid):
			return not bool(u["is_dead"])
	return null


func _final_unit_hp(uid: StringName) -> Variant:
	for u in _units_snapshot():
		if u["id"] == String(uid):
			return int(u["hp"])
	return null


func _final_unit_pos(uid: StringName) -> Variant:
	for u in _units_snapshot():
		if u["id"] == String(uid):
			return {"x": int(u["x"]), "y": int(u["y"])}
	return null


static func _compare(op: StringName, actual: Variant, expected: Variant) -> bool:
	match op:
		&"==":
			return actual == expected
		&"!=":
			return actual != expected
		&"<=":
			return actual <= expected
		&">=":
			return actual >= expected
		&"<":
			return actual < expected
		&">":
			return actual > expected
	return false


func _exit_code(result: Dictionary) -> int:
	var reason: StringName = result["outcome"]["stop_reason"]
	if reason == &"illegal_action":
		return 2
	if reason == &"max_turns" or reason == &"max_steps":
		return 3
	for a in (result["assertions"] as Array):
		if not bool(a["passed"]):
			return 1
	return 0


## ---- 快照与工具 --------------------------------------------------------


func _map_snapshot() -> Array:
	var out: Array = []
	for row in (_chapter["map"] as Array):
		var line: Array = []
		for t in (row as Array):
			line.append(String(t))
		out.append(line)
	return out


func _units_snapshot() -> Array:
	var out: Array = []
	# 遍历 chapter 单位列表而非 grid（死亡单位已从 grid erase，但其 isDead/最终状态仍需入快照）
	var all_units: Array = []
	all_units.append_array(_chapter["playerUnits"])
	all_units.append_array(_chapter["enemyUnits"])
	for u in all_units:
		var pos: Vector2i = u[&"position"]
		var cooldowns := {}
		for k in (u[&"skillCooldowns"] as Dictionary):
			cooldowns[String(k)] = int(u[&"skillCooldowns"][k])
		var items: Array = []
		for e in (u[&"items"] as Array):
			items.append({"id": String(e.get(&"id", &"")), "uses": int(e.get(&"uses", 0))})
		var buffs: Array = []
		for b in (u[&"buffs"] as Array):
			buffs.append({
				"stat": String(b.get(&"stat", &"")),
				"value": int(b.get(&"value", 0)),
				"turns": int(b.get(&"turns", 0)),
			})
		var skills: Array = []
		for s in (u[&"skills"] as Array):
			skills.append(String(s))
		var stats := {}
		for k in (u[&"stats"] as Dictionary):
			stats[String(k)] = u[&"stats"][k]
		out.append({
			"id": String(u[&"id"]),
			"name": String(u[&"name"]),
			"class_id": String(u[&"classId"]),
			"faction": String(u[&"faction"]),
			"level": int(u[&"level"]),
			"exp": int(u[&"exp"]),
			"hp": int(u[&"hp"]),
			"mp": int(u[&"mp"]),
			"x": pos.x,
			"y": pos.y,
			"is_dead": bool(u[&"isDead"]),
			"has_moved": bool(u[&"hasMoved"]),
			"has_acted": bool(u[&"hasActed"]),
			"stats": stats,
			"skills": skills,
			"skill_cooldowns": cooldowns,
			"items": items,
			"buffs": buffs,
		})
	return out


static func _vec_dict(v: Vector2i) -> Dictionary:
	return {"x": v.x, "y": v.y}


static func _path_snapshot(path: Array) -> Array:
	var out: Array = []
	for p in path:
		out.append(_vec_dict(p))
	return out


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _emit(payload: Dictionary) -> void:
	_seq += 1
	var event := {
		"seq": _seq,
		"turn": int(_turn.turn_number) if _turn != null else 0,
		"phase": String(_turn.phase) if _turn != null else "",
	}
	event.merge(payload, true)
	if not event.has("actor"):
		event["actor"] = ""
	if not event.has("source"):
		event["source"] = &"runner"
	_events.append(event)
