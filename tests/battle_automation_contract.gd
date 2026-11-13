## battle_automation_contract.gd — 声明式战场自动化契约（loader / runner / report 进程内验证）
extends SceneTree


const ScenarioLoader := preload("res://scripts/battle/automation/battle_scenario_loader.gd")
const Runner := preload("res://scripts/battle/automation/battle_runner.gd")
const Report := preload("res://scripts/battle/automation/battle_report.gd")

const FIXTURE_QUICK_DUEL := "res://tests/fixtures/battle_scenarios/quick_duel.json"
const FIXTURE_REPLAY := "res://tests/fixtures/battle_scenarios/deterministic_replay.json"

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[battle_automation_contract] start")
	_test_loader_valid()
	_test_loader_invalid()
	_test_runner_quick_duel()
	_test_runner_determinism()
	_test_runner_illegal_action()
	_test_runner_assertion_failure()
	_test_runner_stop_after_steps()
	_test_runner_script_exhausted_fail()
	_test_report_write()
	if _failures > 0:
		push_error("[battle_automation_contract] FAILED: %d 处断言未过" % _failures)
		quit(1)
		return
	print("BATTLE_AUTOMATION_CONTRACT_OK")
	quit(0)


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  [ok] %s" % label)
	else:
		_failures += 1
		push_error("  [FAIL] %s" % label)


## ---- loader -------------------------------------------------------------


func _test_loader_valid() -> void:
	print("[loader valid]")
	var res := ScenarioLoader.load_from_file(FIXTURE_QUICK_DUEL)
	_expect(bool(res["ok"]), "quick_duel fixture 加载成功")
	if not bool(res["ok"]):
		return
	var sc: Dictionary = res["scenario"]
	_expect(int(sc["version"]) == 1, "version==1")
	_expect(int(sc["seed"]) == 7, "seed 透传==7")
	_expect(String(sc["id"]) == "quick_duel", "id 从文件名取")
	_expect(sc["chapter"]["playerUnits"].size() == 1 and sc["chapter"]["enemyUnits"].size() == 1, "chapter 双方各 1 单位（引用预制战场）")
	_expect(String(sc["factions"][&"player"][&"mode"]) == "script", "player 阵营 mode=script")
	_expect(sc["factions"][&"player"][&"script"].size() == 4, "player 脚本 4 条")
	# seed override
	var res2 := ScenarioLoader.load_from_file(FIXTURE_QUICK_DUEL, 99)
	_expect(bool(res2["ok"]) and int(res2["scenario"]["seed"]) == 99, "seed_override 覆盖为 99")
	# inline 战场
	var res3 := ScenarioLoader.load_from_dict({
		"version": 1, "id": "inline_test", "seed": 3,
		"inline": {
			"rows": ["...", "...", "..."],
			"playerUnits": [{"class": "swordsman", "x": 0, "y": 1}],
			"enemyUnits": [{"class": "berserker", "x": 2, "y": 1}],
		},
		"factions": {"player": {"mode": "ai"}, "enemy": {"mode": "ai"}},
	})
	_expect(bool(res3["ok"]), "inline 战场加载成功")
	if bool(res3["ok"]):
		var sc3: Dictionary = res3["scenario"]
		_expect(int(sc3["chapter"]["width"]) == 3 and int(sc3["chapter"]["height"]) == 3, "inline 尺寸 3x3")
		_expect(String(sc3["chapter"]["playerUnits"][0][&"id"]) == "u_p_0", "inline 单位 ID 缺省 u_p_0/u_e_0")


func _test_loader_invalid() -> void:
	print("[loader invalid]")
	# 版本不支持
	var r1 := ScenarioLoader.load_from_dict({"version": 2, "seed": 1})
	_expect(not bool(r1["ok"]) and String(r1["error"]).contains("version"), "version 2 被拒绝")
	# battlefield 与 inline 冲突
	var r2 := ScenarioLoader.load_from_dict({
		"version": 1, "seed": 1,
		"battlefield": "res://data/battlefields/arena_1v1.json",
		"inline": {"rows": ["."], "playerUnits": [{"class": "swordsman", "x": 0, "y": 0}], "enemyUnits": [{"class": "berserker", "x": 0, "y": 0}]},
	})
	_expect(not bool(r2["ok"]), "battlefield+inline 同时给被拒绝")
	# seed 非整数
	var r3 := ScenarioLoader.load_from_dict({"version": 1, "seed": "abc", "battlefield": "res://data/battlefields/arena_1v1.json"})
	_expect(not bool(r3["ok"]) and String(r3["error"]).contains("seed"), "seed 非整数被拒绝")
	# 非法断言 op
	var r4 := ScenarioLoader.load_from_dict({
		"version": 1, "seed": 1, "battlefield": "res://data/battlefields/arena_1v1.json",
		"factions": {"player": {"mode": "ai"}, "enemy": {"mode": "ai"}},
		"assertions": [{"type": "winner", "op": "~=", "value": "player"}],
	})
	_expect(not bool(r4["ok"]) and String(r4["error"]).contains("op"), "非法断言 op 被拒绝")
	# 非法 mode
	var r5 := ScenarioLoader.load_from_dict({
		"version": 1, "seed": 1, "battlefield": "res://data/battlefields/arena_1v1.json",
		"factions": {"player": {"mode": "quantum"}, "enemy": {"mode": "ai"}},
	})
	_expect(not bool(r5["ok"]) and String(r5["error"]).contains("mode"), "非法阵营 mode 被拒绝")
	# overrides 引用不存在单位
	var r6 := ScenarioLoader.load_from_dict({
		"version": 1, "seed": 1, "battlefield": "res://data/battlefields/arena_1v1.json",
		"factions": {"player": {"mode": "ai"}, "enemy": {"mode": "ai"}},
		"overrides": {"u_p_9": {"hp": 99}},
	})
	_expect(not bool(r6["ok"]) and String(r6["error"]).contains("u_p_9"), "overrides 引用不存在单位被拒绝")
	# script 条目缺任何动作（裸 unit）
	var r7 := ScenarioLoader.load_from_dict({
		"version": 1, "seed": 1, "battlefield": "res://data/battlefields/arena_1v1.json",
		"factions": {"player": {"mode": "script", "script": [{"unit": "u_p_0"}]}, "enemy": {"mode": "ai"}},
	})
	_expect(not bool(r7["ok"]) and String(r7["error"]).contains("缺少动作"), "空动作脚本条目被拒绝")
	# 文件不存在
	var r8 := ScenarioLoader.load_from_file("res://tests/fixtures/battle_scenarios/nope.json")
	_expect(not bool(r8["ok"]) and String(r8["error"]).contains("不存在"), "不存在的场景文件被拒绝")


## ---- runner -------------------------------------------------------------


func _test_runner_quick_duel() -> void:
	print("[runner quick_duel]")
	var res := ScenarioLoader.load_from_file(FIXTURE_QUICK_DUEL)
	var run := Runner.run(res["scenario"])
	_expect(bool(run["ok"]), "run 返回 ok")
	var result: Dictionary = run["result"]
	_expect(int(run["exit_code"]) == 0, "exit_code==0（victory 且断言全过）")
	_expect(String(result["outcome"]["stop_reason"]) == "victory", "stop_reason==victory")
	_expect(String(result["outcome"]["winner"]) == "player", "winner==player")
	# 覆盖生效：罗兰初始 hp=999
	var ev0: Dictionary = run["events"][0]
	_expect(int(ev0["units"][0]["hp"]) == 999, "overrides hp=999 进初始快照")
	# 最终快照包含死亡单位
	var ids: Array = []
	for u in (result["final_units"] as Array):
		ids.append(String(u["id"]))
	_expect(ids.has("u_e_0"), "final_units 包含死亡单位 u_e_0")
	# move 后同轮攻击（事件序列）
	var has_move_then_attack := false
	var last_type := ""
	for e in (run["events"] as Array):
		var t := String(e["type"])
		if last_type == "move" and t == "attack":
			has_move_then_attack = true
		last_type = t
	_expect(has_move_then_attack, "move 后同轮攻击出现在事件流")
	# 事件 seq 连续递增
	var seq_ok := true
	for i in (run["events"] as Array).size():
		if int(run["events"][i]["seq"]) != i + 1:
			seq_ok = false
	_expect(seq_ok, "事件 seq 从 1 连续递增")


func _test_runner_determinism() -> void:
	print("[runner determinism]")
	var res := ScenarioLoader.load_from_file(FIXTURE_REPLAY)
	var run1 := Runner.run(res["scenario"])
	var run2 := Runner.run(ScenarioLoader.load_from_file(FIXTURE_REPLAY)["scenario"])
	var j1 := JSON.stringify(run1["events"])
	var j2 := JSON.stringify(run2["events"])
	_expect(j1 == j2, "同 seed 双跑 events 完全一致（确定性契约）")
	_expect(int(run1["exit_code"]) == 0, "deterministic_replay 断言全过 exit 0")
	_expect(String(run1["result"]["outcome"]["stop_reason"]) == "victory" or String(run1["result"]["outcome"]["stop_reason"]) == "defeat", "AI 对局分出胜负")
	# 异 seed 应产生不同事件流（伤害/命中至少一处不同；统计所有 attack 事件的 damage 序列）
	var res43 := ScenarioLoader.load_from_file(FIXTURE_REPLAY, 43)
	var run3 := Runner.run(res43["scenario"])
	var j3 := JSON.stringify(run3["events"])
	_expect(j1 != j3, "异 seed(43) 事件流与 seed(42) 不同")


func _test_runner_illegal_action() -> void:
	print("[runner illegal]")
	# 距离 2 攻击（swordsman rng [1,1]）：初始站位 (1,2) vs (3,2) 曼哈顿距离 2
	var res := ScenarioLoader.load_from_dict({
		"version": 1, "id": "illegal_case", "seed": 5,
		"battlefield": "res://data/battlefields/arena_1v1.json",
		"factions": {
			"player": {"mode": "script", "script": [{"unit": "u_p_0", "attack": "u_e_0"}]},
			"enemy": {"mode": "ai"},
		},
	})
	var run := Runner.run(res["scenario"])
	_expect(int(run["exit_code"]) == 2, "超距离攻击 → exit 2")
	var result: Dictionary = run["result"]
	_expect(String(result["outcome"]["stop_reason"]) == "illegal_action", "stop_reason==illegal_action")
	_expect(String(result["error"]).contains("step=1"), "错误信息带 step 定位")
	# 未知技能
	var res2 := ScenarioLoader.load_from_dict({
		"version": 1, "id": "illegal_skill", "seed": 5,
		"battlefield": "res://data/battlefields/arena_1v1.json",
		"factions": {
			"player": {"mode": "script", "script": [{"unit": "u_p_0", "skill": "megaFlare", "targets": ["u_e_0"]}]},
			"enemy": {"mode": "ai"},
		},
	})
	var run2 := Runner.run(res2["scenario"])
	_expect(int(run2["exit_code"]) == 2, "未拥有技能 → exit 2")


func _test_runner_assertion_failure() -> void:
	print("[runner assertion]")
	var res := ScenarioLoader.load_from_dict({
		"version": 1, "id": "assert_fail_case", "seed": 5,
		"battlefield": "res://data/battlefields/arena_1v1.json",
		"factions": {"player": {"mode": "ai"}, "enemy": {"mode": "ai"}},
		"assertions": [
			{"type": "winner", "op": "==", "value": "enemy"},
			{"type": "turn_number", "op": "<=", "value": 3},
		],
	})
	var run := Runner.run(res["scenario"])
	# AI 对局 winner 由 seed 决定；构造上 enemy 断言大概率失败，但为稳定断言 turn_number<=3：
	# 只要 winner 断言失败或 turn_number 失败其一 → exit 1
	var any_fail := false
	for a in (run["result"]["assertions"] as Array):
		if not bool(a["passed"]):
			any_fail = true
	_expect(any_fail, "存在失败断言（enemy 胜或轮数>3）")
	if any_fail:
		_expect(int(run["exit_code"]) == 1, "断言失败 → exit 1")
	else:
		_expect(int(run["exit_code"]) == 0, "（小概率全过）exit 0")


func _test_runner_stop_after_steps() -> void:
	print("[runner stop_after_steps]")
	var res := ScenarioLoader.load_from_dict({
		"version": 1, "id": "stop_case", "seed": 5,
		"battlefield": "res://data/battlefields/arena_1v1.json",
		"stop_after_steps": 1,
		"factions": {
			"player": {"mode": "script", "script": [
				{"unit": "u_p_0", "move": {"x": 2, "y": 2}, "attack": "u_e_0"},
			]},
			"enemy": {"mode": "ai"},
		},
	})
	var run := Runner.run(res["scenario"])
	_expect(int(run["exit_code"]) == 0, "stop_after_steps 到达 → 正常停 exit 0")
	_expect(String(run["result"]["outcome"]["stop_reason"]) == "stop_after_steps", "stop_reason==stop_after_steps")
	_expect(int(run["result"]["outcome"]["steps"]) == 1, "steps==1")


func _test_runner_script_exhausted_fail() -> void:
	print("[runner script_exhausted=fail]")
	var res := ScenarioLoader.load_from_dict({
		"version": 1, "id": "exhaust_fail", "seed": 5,
		"battlefield": "res://data/battlefields/arena_1v1.json",
		"factions": {
			"player": {"mode": "script", "script_exhausted": "fail", "script": [
				{"unit": "u_p_0", "wait": true},
			]},
			"enemy": {"mode": "ai"},
		},
	})
	var run := Runner.run(res["scenario"])
	_expect(int(run["exit_code"]) == 2, "脚本耗尽 exhausted=fail → exit 2")
	_expect(String(run["result"]["error"]).contains("耗尽"), "错误信息含「耗尽」")


## ---- report -------------------------------------------------------------


func _test_report_write() -> void:
	print("[report]")
	var res := ScenarioLoader.load_from_file(FIXTURE_QUICK_DUEL)
	var run := Runner.run(res["scenario"])
	var out_dir := "user://battle_reports/test_automation_contract"
	var dir := DirAccess.open("user://")
	if dir.dir_exists("battle_reports/test_automation_contract"):
		dir.remove("battle_reports/test_automation_contract/events.jsonl")
		dir.remove("battle_reports/test_automation_contract/result.json")
		dir.remove("battle_reports/test_automation_contract/summary.txt")
	var written := Report.write_all(out_dir, run["events"], run["result"])
	_expect(bool(written["ok"]), "write_all 成功")
	if not bool(written["ok"]):
		return
	var ev_text := FileAccess.open(String(written["dir"]) + "/events.jsonl", FileAccess.READ).get_as_text()
	_expect(ev_text.contains("battle_start") and ev_text.contains("battle_end"), "events.jsonl 含开场/终局事件")
	_expect(ev_text.split("\n").size() >= (run["events"] as Array).size(), "events.jsonl 行数 ≥ 事件数")
	var res_text := FileAccess.open(String(written["dir"]) + "/result.json", FileAccess.READ).get_as_text()
	var parsed = JSON.parse_string(res_text)
	_expect(parsed is Dictionary and (parsed as Dictionary).has("outcome"), "result.json 可解析且含 outcome")
	var sum_text := FileAccess.open(String(written["dir"]) + "/summary.txt", FileAccess.READ).get_as_text()
	_expect(sum_text.contains("战报") and sum_text.contains("断言"), "summary.txt 含战报/断言段")
