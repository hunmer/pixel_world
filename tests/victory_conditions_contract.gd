## victory_conditions_contract.gd — 胜利条件框架契约（rout / defend_turns / seize）
##
## 覆盖：turn_manager.check_victory 三种条件的确定性判定；battlefield_loader
## 对 "victory" 字段的解析/校验（缺省 = rout，旧战场全兼容）；BattleRunner
## 端到端（defend_turns 到回合胜、seize 占领胜、seize 未占领不误胜、rout 兼容）。
extends SceneTree

const Loader := preload("res://scripts/core/battlefield_loader.gd")
const ScenarioLoader := preload("res://scripts/battle/automation/battle_scenario_loader.gd")
const Runner := preload("res://scripts/battle/automation/battle_runner.gd")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[victory_conditions_contract] start")
	_test_rout_default()
	_test_defend_turns_logic()
	_test_seize_logic()
	_test_loader_parse()
	_test_loader_compat()
	_test_runner_defend_turns()
	_test_runner_seize_win()
	_test_runner_seize_not_held()
	_test_runner_rout_compat()
	if _failures > 0:
		push_error("[victory_conditions_contract] FAILED: %d 处断言未过" % _failures)
		quit(1)
		return
	print("VICTORY_CONDITIONS_CONTRACT_OK")
	quit(0)


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  [ok] %s" % label)
	else:
		_failures += 1
		push_error("  [FAIL] %s" % label)


## 最小单位 dict（check_victory 只读 faction/isDead）
func _u(faction: StringName, dead: bool = false) -> Dictionary:
	return { &"faction": faction, &"isDead": dead }


func _mk_tm(players: Array, enemies: Array) -> TurnManager:
	var tm := TurnManager.new(players + enemies)
	tm.turn_number = 1
	return tm


## ---- turn_manager：rout 默认 ------------------------------------------------


func _test_rout_default() -> void:
	print("[rout default]")
	var tm := _mk_tm([_u(&"player")], [_u(&"enemy", true)])
	_expect(String(tm.victory.get(&"type", &"")) == "rout", "缺省 victory = rout")
	_expect(tm.check_victory([_u(&"enemy", true)]) == &"win", "敌全灭 = win（旧签名兼容）")
	var tm2 := _mk_tm([_u(&"player", true)], [_u(&"enemy")])
	_expect(tm2.check_victory([_u(&"enemy")]) == &"lose", "我方全灭 = lose")
	var tm3 := _mk_tm([_u(&"player")], [_u(&"enemy")])
	_expect(tm3.check_victory([_u(&"enemy")]) == &"", "双方存活 = 未分胜负")


## ---- turn_manager：defend_turns --------------------------------------------


func _test_defend_turns_logic() -> void:
	print("[defend_turns logic]")
	var tm := _mk_tm([_u(&"player")], [_u(&"enemy")])
	tm.victory = { &"type": &"defend_turns", &"turns": 3 }
	tm.turn_number = 2
	_expect(tm.check_victory([_u(&"enemy")], { "end_of_round": true, "turns_survived": 2 }) == &"",
		"存活 2/3 回合 = 未胜")
	_expect(tm.check_victory([_u(&"enemy")], { "end_of_round": true, "turns_survived": 3 }) == &"win",
		"存活 3/3 回合 = win")
	_expect(tm.check_victory([_u(&"enemy")], { "end_of_round": true }) == &"",
		"缺省 turns_survived 用 turn_number(2) = 未胜")
	_expect(tm.check_victory([_u(&"enemy")], {}) == &"",
		"回合中（非 end_of_round）不判 defend_turns")
	# 歼灭兜底仍然生效
	_expect(tm.check_victory([_u(&"enemy", true)], {}) == &"win", "敌全灭兜底 = win")


## ---- turn_manager：seize ---------------------------------------------------


func _test_seize_logic() -> void:
	print("[seize logic]")
	var tm := _mk_tm([_u(&"player")], [_u(&"enemy")])
	tm.victory = { &"type": &"seize", &"cell": Vector2i(4, 2) }
	_expect(tm.check_victory([_u(&"enemy")], { "end_of_round": true, "seize_held": true }) == &"win",
		"回合结束占领目标格 = win")
	_expect(tm.check_victory([_u(&"enemy")], { "end_of_round": true, "seize_held": false }) == &"",
		"回合结束未占领 = 未胜")
	_expect(tm.check_victory([_u(&"enemy")], { "seize_held": true }) == &"",
		"回合中（非 end_of_round）不判 seize")
	_expect(tm.check_victory([_u(&"enemy", true)], {}) == &"win", "敌全灭兜底 = win")


## ---- battlefield_loader：victory 解析与校验 ---------------------------------


func _test_loader_parse() -> void:
	print("[loader victory parse]")
	var base := {
		"rows": [".....", "....."],
		"playerUnits": [{ "class": "swordsman", "x": 1, "y": 1 }],
		"enemyUnits": [{ "class": "berserker", "x": 3, "y": 1 }],
	}
	var r := Loader.load_battlefield_inline(base.duplicate())
	_expect(bool(r["ok"]) and not (r["chapter"] as Dictionary).has("victory"),
		"无 victory 字段 = 不写入 chapter（rout 兼容）")

	r = Loader.load_battlefield_inline(_bf(base, { "type": "rout" }))
	_expect(bool(r["ok"]) and (r["chapter"]["victory"] as Dictionary).get(&"type", &"") == &"rout",
		"victory rout 解析")

	r = Loader.load_battlefield_inline(_bf(base, { "type": "defend_turns", "turns": 4 }))
	_expect(bool(r["ok"]) and (r["chapter"]["victory"] as Dictionary).get(&"turns", 0) == 4,
		"victory defend_turns turns=4 解析")

	r = Loader.load_battlefield_inline(_bf(base, { "type": "seize", "cell": [4, 0] }))
	var sv: Dictionary = r["chapter"]["victory"]
	_expect(bool(r["ok"]) and sv.get(&"cell", Vector2i(-1, -1)) == Vector2i(4, 0),
		"victory seize cell 解析（JSON float 坐标归一）")

	r = Loader.load_battlefield_inline(_bf(base, { "type": "escape" }))
	_expect(not bool(r["ok"]), "未知 type 拒绝")

	r = Loader.load_battlefield_inline(_bf(base, { "type": "defend_turns", "turns": 0 }))
	_expect(not bool(r["ok"]), "defend_turns turns<1 拒绝")

	r = Loader.load_battlefield_inline(_bf(base, { "type": "seize", "cell": [9, 9] }))
	_expect(not bool(r["ok"]), "seize cell 越界拒绝")

	r = Loader.load_battlefield_inline(_bf(base, { "type": "seize", "cell": [1] }))
	_expect(not bool(r["ok"]), "seize cell 非二元组拒绝")

	r = Loader.load_battlefield_inline(_bf(base, "nope"))
	_expect(not bool(r["ok"]), "victory 非对象拒绝")


func _bf(base: Dictionary, victory) -> Dictionary:
	var d := base.duplicate()
	d["victory"] = victory
	return d


## 既有 4 个预制战场全部兼容（无 victory 字段也能加载）。


func _test_loader_compat() -> void:
	print("[loader compat]")
	for f in ["arena_1v1.json", "mountain_pass.json", "plains_skirmish.json", "river_crossing.json", "last_stand.json"]:
		var r := Loader.load_battlefield("res://data/battlefields/" + f)
		_expect(bool(r["ok"]), "预制战场 %s 加载 ok" % f)
	var ls := Loader.load_battlefield("res://data/battlefields/last_stand.json")
	_expect(bool(ls["ok"]) and String((ls["chapter"]["victory"] as Dictionary).get(&"type", &"")) == "defend_turns",
		"last_stand.json 携带 defend_turns 条件")


## ---- BattleRunner：端到端 ---------------------------------------------------


func _run_inline(victory, max_turns: int, player_script: Array) -> Dictionary:
	var bf := {
		"rows": [".......", ".......", ".......", "......."],
		"victory": victory,
		"playerUnits": [{ "class": "swordsman", "level": 3, "x": 1, "y": 1 }],
		"enemyUnits": [
			{ "class": "berserker", "level": 1, "x": 6, "y": 0 },
			{ "class": "berserker", "level": 1, "x": 6, "y": 3 },
		],
	}
	# 敌方拉远 + 低等级：脚本里玩家原地等待，避免随机互杀干扰条件验证
	var scenario := {
		"version": 1,
		"id": "vc_inline",
		"inline": bf,
		"seed": 11,
		"limits": { "max_turns": max_turns, "max_steps": 200 },
		"overrides": { "u_p_0": { "hp": 999 } },
		"factions": {
			"player": { "mode": "script", "script": player_script, "script_exhausted": "wait" },
			"enemy": { "mode": "script", "script": [], "script_exhausted": "wait" },
		},
		"assertions": [],
	}
	var res := ScenarioLoader.load_from_dict(scenario, "vc_inline")
	if not bool(res["ok"]):
		return { "ok": false, "error": res.get("error", "") }
	return Runner.run(res["scenario"])


func _test_runner_defend_turns() -> void:
	print("[runner defend_turns]")
	var run := _run_inline({ "type": "defend_turns", "turns": 2 }, 6, [])
	_expect(bool(run["ok"]), "defend_turns 场景运行 ok")
	var out: Dictionary = run["result"]["outcome"]
	_expect(String(out["winner"]) == "player" and String(out["stop_reason"]) == "victory",
		"存活 2 回合 = 玩家胜（stop_reason=victory）")
	_expect(int(out["turns"]) == 2, "第 2 回合结束时结算（turns=2）")


func _test_runner_seize_win() -> void:
	print("[runner seize win]")
	# 玩家第 1 回合移动到目标格 (3,1) 并等待；回合结束 = 占领胜
	var run := _run_inline({ "type": "seize", "cell": [3, 1] }, 6,
		[{ "unit": "u_p_0", "move": { "x": 3, "y": 1 } }])
	_expect(bool(run["ok"]), "seize 场景运行 ok")
	var out: Dictionary = run["result"]["outcome"]
	_expect(String(out["winner"]) == "player" and String(out["stop_reason"]) == "victory",
		"占领目标格回合结束 = 玩家胜")
	_expect(int(out["turns"]) == 1, "第 1 回合结束时结算（turns=1）")


func _test_runner_seize_not_held() -> void:
	print("[runner seize not held]")
	# 玩家原地不动：永不占领 → 走到 max_turns 僵持保护，不误判胜
	var run := _run_inline({ "type": "seize", "cell": [5, 2] }, 3, [])
	_expect(bool(run["ok"]), "seize 未占领场景运行 ok")
	var out: Dictionary = run["result"]["outcome"]
	_expect(String(out["winner"]) != "player" and String(out["stop_reason"]) == "max_turns",
		"未占领目标格 = 不胜（max_turns 僵持保护）")


func _test_runner_rout_compat() -> void:
	print("[runner rout compat]")
	# 无 victory 字段（= rout）：照旧歼灭制 —— 引用 quick_duel fixture 的战场与脚本
	var scenario := {
		"version": 1,
		"id": "vc_rout",
		"battlefield": "res://data/battlefields/arena_1v1.json",
		"seed": 7,
		"limits": { "max_turns": 6, "max_steps": 60 },
		"overrides": { "u_p_0": { "hp": 999 } },
		"factions": {
			"player": {
				"mode": "script",
				"script": [
					{ "unit": "u_p_0", "move": { "x": 2, "y": 2 }, "attack": "u_e_0" },
					{ "unit": "u_p_0", "attack": "u_e_0" },
					{ "unit": "u_p_0", "attack": "u_e_0" },
					{ "unit": "u_p_0", "attack": "u_e_0" },
				],
				"script_exhausted": "wait",
			},
			"enemy": { "mode": "ai" },
		},
		"assertions": [],
	}
	var res := ScenarioLoader.load_from_dict(scenario, "vc_rout")
	_expect(bool(res["ok"]) and not ((res["scenario"]["chapter"] as Dictionary).has("victory")),
		"arena_1v1 chapter 无 victory 键（兼容）")
	var run := Runner.run(res["scenario"])
	_expect(bool(run["ok"]), "rout 场景运行 ok")
	var out: Dictionary = run["result"]["outcome"]
	_expect(String(out["winner"]) == "player" and String(out["stop_reason"]) == "victory",
		"无 victory 字段照旧歼灭制取胜")
