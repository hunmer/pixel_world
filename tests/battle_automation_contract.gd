## battle_automation_contract.gd — 声明式战场自动化契约（loader / runner / report 进程内验证）
extends SceneTree


const ScenarioLoader := preload("res://scripts/battle/automation/battle_scenario_loader.gd")
const Runner := preload("res://scripts/battle/automation/battle_runner.gd")
const Report := preload("res://scripts/battle/automation/battle_report.gd")
const Resolver := preload("res://scripts/battle/battle_action_resolver.gd")

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
	_test_runner_limits_exit3()
	_test_runner_skill_and_cooldown_tick()
	_test_runner_buff_tick_expire()
	_test_runner_kill_exp_levelup()
	_test_runner_item_use_and_illegal()
	_test_runner_illegal_no_side_effects()
	_test_runner_shared_resolver_equivalence()
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


## 轮数/步数上限（僵持保护）→ exit 3。
func _test_runner_limits_exit3() -> void:
	print("[runner limits exit 3]")
	# max_turns：双方 hp 拉满互殴不死，撑满轮数上限
	var res := ScenarioLoader.load_from_dict({
		"version": 1, "id": "stalemate_turns", "seed": 42,
		"battlefield": "res://data/battlefields/arena_1v1.json",
		"limits": {"max_turns": 2},
		"overrides": {"u_p_0": {"hp": 999}, "u_e_0": {"hp": 999}},
		"factions": {"player": {"mode": "ai"}, "enemy": {"mode": "ai"}},
	})
	var run := Runner.run(res["scenario"])
	_expect(int(run["exit_code"]) == 3, "max_turns 到达 → exit 3")
	_expect(String(run["result"]["outcome"]["stop_reason"]) == "max_turns", "stop_reason==max_turns")
	_expect(int(run["result"]["outcome"]["turns"]) == 3, "turns==3（第 3 轮开始时超限判停）")
	_expect(not bool(run["result"]["outcome"]["battle_over"]), "僵持不算分出胜负")
	# max_steps：步数上限先于轮数到达
	var res2 := ScenarioLoader.load_from_dict({
		"version": 1, "id": "stalemate_steps", "seed": 42,
		"battlefield": "res://data/battlefields/arena_1v1.json",
		"limits": {"max_turns": 50, "max_steps": 2},
		"overrides": {"u_p_0": {"hp": 999}, "u_e_0": {"hp": 999}},
		"factions": {"player": {"mode": "ai"}, "enemy": {"mode": "ai"}},
	})
	var run2 := Runner.run(res2["scenario"])
	_expect(int(run2["exit_code"]) == 3, "max_steps 到达 → exit 3")
	_expect(String(run2["result"]["outcome"]["stop_reason"]) == "max_steps", "stop_reason==max_steps")
	_expect(int(run2["result"]["outcome"]["steps"]) == 2, "steps==2")


## 合法技能执行 + 冷却跨回合递减（阶段 tick）：第 2 次同技能必须等下一回合冷却归零。
func _test_runner_skill_and_cooldown_tick() -> void:
	print("[runner skill + cooldown tick]")
	# swordsman 默认技能含 smite(cd1)；敌方空脚本（耗尽=wait，不反击不移动）
	var res := ScenarioLoader.load_from_dict({
		"version": 1, "id": "smite_cd", "seed": 9,
		"inline": {
			"rows": ["...", "...", "..."],
			"playerUnits": [{"class": "swordsman", "x": 0, "y": 1}],
			"enemyUnits": [{"class": "berserker", "x": 1, "y": 1}],
		},
		"stop_after_steps": 2,
		"overrides": {"u_p_0": {"hp": 999}, "u_e_0": {"hp": 999}},
		"factions": {
			"player": {"mode": "script", "script": [
				{"unit": "u_p_0", "skill": "smite", "targets": ["u_e_0"]},
				{"unit": "u_p_0", "skill": "smite", "targets": ["u_e_0"]},
			]},
			"enemy": {"mode": "script", "script": []},
		},
	})
	_expect(bool(res["ok"]), "场景加载成功") 
	if not bool(res["ok"]):
		_expect(false, "场景加载错误: %s" % String(res.get("error", "")))
		return
	var run := Runner.run(res["scenario"])
	_expect(int(run["exit_code"]) == 0, "两次 smite 均合法执行（exit 0，若冷却未跨回合递减第 2 次会 exit 2）")
	var skill_events: Array = []
	for e in (run["events"] as Array):
		if String((e as Dictionary).get("type", "")) == "skill":
			skill_events.append(e)
	_expect(skill_events.size() == 2, "skill 事件恰好 2 条（实际 %d）" % skill_events.size())
	if skill_events.size() == 2:
		var first: Dictionary = skill_events[0]
		_expect(int(first["turn"]) == 1, "第 1 次 smite 发生在第 1 轮")
		_expect(int(first["cooldown"]) == 1, "smite(cd1) 使用后冷却==1")
		_expect(int(first["mp_cost"]) == 4, "mp_cost==4")
		var second: Dictionary = skill_events[1]
		_expect(int(second["turn"]) == 2, "第 2 次 smite 发生在第 2 轮（跨回合）")
		_expect(int(second["mp_after"]) == 4, "mp_after==4（12-4-4，两次都扣 MP）")


## buff 跨阶段 tick 与到期移除（与游戏共享 TurnManager 行为一致）。
## tick 节奏：TurnManager 每次 phase 启动（player 与 enemy 各一次）调
## SkillSystem.tick_buffs（全阵营），因此 3t buff 实际寿命 = 施放后 3 个
## phase：T1 敌相(3→2)、T2 玩家相(2→1)、T2 敌相(1→0 移除)。本契约是该
## 语义的回归锚点——若 tick 时机/到期行为偏离共享 TurnManager 会在此挂掉。
func _test_runner_buff_tick_expire() -> void:
	print("[runner buff tick + expire]")
	# 场景 A：powerSurge(self, str+4, 3t, mp4, cd3) 施放后立即停 → buff 未经历任何 tick
	var base := {
		"version": 1, "id": "buff_tick", "seed": 13,
		"inline": {
			"rows": ["...", "...", "..."],
			"playerUnits": [{"class": "swordsman", "x": 0, "y": 1}],
			"enemyUnits": [{"class": "berserker", "x": 1, "y": 1}],
		},
		"overrides": {"u_p_0": {"hp": 999}, "u_e_0": {"hp": 999}},
		"factions": {
			"player": {"mode": "script", "script": [
				{"unit": "u_p_0", "skill": "powerSurge", "targets": ["u_p_0"]},
			]},
			"enemy": {"mode": "script", "script": []},
		},
	}
	var res_a := ScenarioLoader.load_from_dict(base.duplicate(true))
	_expect(bool(res_a["ok"]), "场景 A 加载成功")
	if not bool(res_a["ok"]):
		_expect(false, "场景 A 错误: %s" % String(res_a.get("error", "")))
		return
	(res_a["scenario"] as Dictionary)["stop_after_steps"] = 1
	var run_a := Runner.run(res_a["scenario"])
	_expect(int(run_a["exit_code"]) == 0, "场景 A：施放后 1 步即停（exit 0）")
	var skill_a: Dictionary = {}
	for e in (run_a["events"] as Array):
		if String((e as Dictionary).get("type", "")) == "skill":
			skill_a = e
			break
	_expect(not skill_a.is_empty(), "场景 A：存在 skill 事件")
	if not skill_a.is_empty():
		_expect(int(skill_a.get("buffed", 0)) == 1, "powerSurge buffed==1")
		_expect(int(skill_a.get("mp_after", -1)) == 8, "mp_after==8（12-4）")
		_expect(int(skill_a.get("cooldown", -1)) == 3, "powerSurge(cd3) 使用后冷却==3")
	var unit_a: Dictionary = _find_unit((run_a["result"] as Dictionary).get("final_units", []), "u_p_0")
	var buffs_a: Array = unit_a.get("buffs", []) if not unit_a.is_empty() else []
	_expect(buffs_a.size() == 1, "场景 A 终局 buffs 恰好 1 条（未 tick）")
	if buffs_a.size() == 1:
		var b: Dictionary = buffs_a[0]
		_expect(String(b.get("stat", "")) == "str" and int(b.get("value", 0)) == 4 and int(b.get("turns", -1)) == 3, "buff 内容 str+4 剩 3 轮（实际 %s）" % JSON.stringify(b))

	# 场景 B：同开局但跑到 max_turns=2 → buff 经 T1敌/T2玩家/T2敌 三次 phase tick 后到期移除
	var cfg_b := base.duplicate(true)
	cfg_b["id"] = "buff_expire"
	cfg_b["limits"] = {"max_turns": 2}
	var res_b := ScenarioLoader.load_from_dict(cfg_b)
	_expect(bool(res_b["ok"]), "场景 B 加载成功")
	var run_b := Runner.run(res_b["scenario"])
	_expect(int(run_b["exit_code"]) == 3, "场景 B：max_turns=2 僵持保护（exit 3）")
	var unit_b: Dictionary = _find_unit((run_b["result"] as Dictionary).get("final_units", []), "u_p_0")
	var buffs_b: Array = unit_b.get("buffs", []) if not unit_b.is_empty() else []
	_expect(buffs_b.is_empty(), "场景 B 终局 buffs 为空（3 次 phase tick 后到期移除；若 tick 失效会残留 str+4）")


## 普攻击杀 → 经验 → 升级事件链。
func _test_runner_kill_exp_levelup() -> void:
	print("[runner kill → exp → level_up]")
	# 相邻普攻：swordsman(剑对斧有三角优势) 一击必杀 hp=7 的 berserker；
	# exp 覆盖 70 + 击杀经验 33 → 103 ≥ 80(升到 2 级需求) → 升级
	var res := ScenarioLoader.load_from_dict({
		"version": 1, "id": "kill_exp", "seed": 4,
		"inline": {
			"rows": [".."],
			"playerUnits": [{"class": "swordsman", "x": 0, "y": 0}],
			"enemyUnits": [{"class": "berserker", "x": 1, "y": 0}],
		},
		"overrides": {"u_p_0": {"exp": 70}, "u_e_0": {"hp": 7}},
		"factions": {
			"player": {"mode": "script", "script": [
				{"unit": "u_p_0", "attack": "u_e_0"},
			]},
			"enemy": {"mode": "script", "script": []},
		},
	})
	var run := Runner.run(res["scenario"])
	_expect(bool(res["ok"]) and int(run["exit_code"]) == 0, "一击必杀脚本 → exit 0")
	var result: Dictionary = run["result"]
	_expect(String(result["outcome"]["stop_reason"]) == "victory", "stop_reason==victory")
	_expect(String(result["outcome"]["winner"]) == "player", "winner==player")
	var types := {}
	for e in (run["events"] as Array):
		var t := String((e as Dictionary).get("type", ""))
		types[t] = true
	_expect(types.has("death"), "death 事件存在")
	_expect(types.has("exp"), "exp 事件存在")
	_expect(types.has("level_up"), "level_up 事件存在")
	var lv := 0
	var exp_amount := 0
	for e in (run["events"] as Array):
		var ed: Dictionary = e
		if String(ed.get("type", "")) == "level_up" and String(ed.get("actor", "")) == "u_p_0":
			lv = int(ed["level"])
		if String(ed.get("type", "")) == "exp" and String(ed.get("actor", "")) == "u_p_0":
			exp_amount = int(ed["amount"])
	_expect(lv == 2, "u_p_0 升到 Lv2（实际 Lv%d）" % lv)
	_expect(exp_amount == 33, "击杀经验==33（exp_for_kill(1)，实际 %d）" % exp_amount)
	var final_p: Dictionary = _find_unit(result["final_units"], "u_p_0")
	_expect(final_p != null and int(final_p["level"]) == 2, "final_units u_p_0 level==2")
	_expect(final_p != null and int(final_p["exp"]) == 23, "final_units u_p_0 exp==23（70+33-80）")


## 合法物品使用（hp 回复 + uses 递减）与非法物品目标。
func _test_runner_item_use_and_illegal() -> void:
	print("[runner item use + illegal]")
	# 合法：hpPotion 对自己（ally 型 rng[0,1]），hp 覆盖 10 → 回满上限 24
	var res := ScenarioLoader.load_from_dict({
		"version": 1, "id": "item_heal", "seed": 6,
		"inline": {
			"rows": [".."],
			"playerUnits": [{"class": "swordsman", "x": 0, "y": 0}],
			"enemyUnits": [{"class": "berserker", "x": 1, "y": 0}],
		},
		"stop_after_steps": 1,
		"overrides": {"u_p_0": {"hp": 10}, "u_e_0": {"hp": 999}},
		"factions": {
			"player": {"mode": "script", "script": [
				{"unit": "u_p_0", "item": "hpPotion", "targets": ["u_p_0"]},
			]},
			"enemy": {"mode": "script", "script": []},
		},
	})
	var run := Runner.run(res["scenario"])
	_expect(int(run["exit_code"]) == 0, "合法物品 → exit 0")
	var item_event: Dictionary = {}
	for e in (run["events"] as Array):
		if String((e as Dictionary).get("type", "")) == "item":
			item_event = e
	_expect(not item_event.is_empty(), "item 事件存在")
	if not item_event.is_empty():
		_expect(int(item_event["uses_left"]) == 1, "uses 2→1")
		var deltas: Array = item_event["hp_deltas"]
		_expect(deltas.size() == 1 and int((deltas[0] as Dictionary)["delta"]) == 14, "hp_delta==14（10+20 回满上限 24）")
	var final_p: Dictionary = _find_unit(run["result"]["final_units"], "u_p_0")
	_expect(final_p != null and int(final_p["hp"]) == 24, "final_units u_p_0 hp==24（回满）")
	# 非法：hpPotion（ally 型）对敌方目标
	var res2 := ScenarioLoader.load_from_dict({
		"version": 1, "id": "item_illegal", "seed": 6,
		"inline": {
			"rows": [".."],
			"playerUnits": [{"class": "swordsman", "x": 0, "y": 0}],
			"enemyUnits": [{"class": "berserker", "x": 1, "y": 0}],
		},
		"factions": {
			"player": {"mode": "script", "script": [
				{"unit": "u_p_0", "item": "hpPotion", "targets": ["u_e_0"]},
			]},
			"enemy": {"mode": "script", "script": []},
		},
	})
	var run2 := Runner.run(res2["scenario"])
	_expect(int(run2["exit_code"]) == 2, "ally 型物品打敌方目标 → exit 2")
	_expect(String(run2["result"]["error"]).contains("合法目标"), "错误信息含「合法目标」定位")


## 非法操作不得产生结算副作用：MP/冷却/hp 全部保持初始值。
func _test_runner_illegal_no_side_effects() -> void:
	print("[runner illegal 无副作用]")
	# 非法技能：MP 未扣、未置冷却、无 skill 事件
	var res := ScenarioLoader.load_from_dict({
		"version": 1, "id": "illegal_side", "seed": 5,
		"battlefield": "res://data/battlefields/arena_1v1.json",
		"factions": {
			"player": {"mode": "script", "script": [{"unit": "u_p_0", "skill": "megaFlare", "targets": ["u_e_0"]}]},
			"enemy": {"mode": "ai"},
		},
	})
	var run := Runner.run(res["scenario"])
	_expect(int(run["exit_code"]) == 2, "未拥有技能 → exit 2")
	var result: Dictionary = run["result"]
	var init_p: Dictionary = _find_unit(result["initial_units"], "u_p_0")
	var final_p: Dictionary = _find_unit(result["final_units"], "u_p_0")
	_expect(final_p != null and int(final_p["mp"]) == int(init_p["mp"]), "非法技能未扣 MP")
	var has_skill_event := false
	for e in (run["events"] as Array):
		if String((e as Dictionary).get("type", "")) == "skill":
			has_skill_event = true
	_expect(not has_skill_event, "无 skill 结算事件")
	# 非法攻击：目标 hp 不变、无 attack 事件
	var res2 := ScenarioLoader.load_from_dict({
		"version": 1, "id": "illegal_side2", "seed": 5,
		"battlefield": "res://data/battlefields/arena_1v1.json",
		"factions": {
			"player": {"mode": "script", "script": [{"unit": "u_p_0", "attack": "u_e_0"}]},
			"enemy": {"mode": "ai"},
		},
	})
	var run2 := Runner.run(res2["scenario"])
	var result2: Dictionary = run2["result"]
	var init_e: Dictionary = _find_unit(result2["initial_units"], "u_e_0")
	var final_e: Dictionary = _find_unit(result2["final_units"], "u_e_0")
	_expect(final_e != null and int(final_e["hp"]) == int(init_e["hp"]), "非法攻击未对目标造成伤害")
	var has_attack_event := false
	for e in (run2["events"] as Array):
		if String((e as Dictionary).get("type", "")) == "attack":
			has_attack_event = true
	_expect(not has_attack_event, "无 attack 结算事件")


## 共享结算一致性：手动镜像 runner 初始化后直调 resolver，与 runner 内同名 attack 的
## 结果逐字段一致（同 seed → 同 randf 消耗序列 → 同结果）。
func _test_runner_shared_resolver_equivalence() -> void:
	print("[runner ↔ resolver 共享结算一致]")
	var res := ScenarioLoader.load_from_file(FIXTURE_QUICK_DUEL)
	_expect(bool(res["ok"]), "quick_duel 加载成功")
	if not bool(res["ok"]):
		return
	var scenario: Dictionary = res["scenario"]
	# 手动镜像 runner 初始化（顺序必须一致：grid → place(player 先) → overrides → seed）
	var chapter: Dictionary = scenario["chapter"]
	var grid := GridSystem.new(int(chapter["width"]), int(chapter["height"]), chapter["map"])
	for u in (chapter["playerUnits"] as Array):
		grid.place_unit(u, (u[&"position"] as Vector2i).x, (u[&"position"] as Vector2i).y)
	for u in (chapter["enemyUnits"] as Array):
		grid.place_unit(u, (u[&"position"] as Vector2i).x, (u[&"position"] as Vector2i).y)
	for uid in (scenario["overrides"] as Dictionary):
		var u2: Dictionary = grid.units[uid]
		for field in (scenario["overrides"][uid] as Dictionary):
			u2[StringName(String(field))] = (scenario["overrides"][uid] as Dictionary)[field]
	var p: Dictionary = grid.units[&"u_p_0"]
	var e_u: Dictionary = grid.units[&"u_e_0"]
	seed(int(scenario["seed"]))
	var outcome := Resolver.resolve_attack(p, e_u, grid)
	var combat: Dictionary = outcome[&"combat"]
	# runner 跑同一场景，取第 1 个 attack 事件（quick_duel 第 1 条脚本 = move+attack，move 不耗 randf）
	var run := Runner.run(scenario)
	var attack_event: Dictionary = {}
	for ev in (run["events"] as Array):
		if String((ev as Dictionary).get("type", "")) == "attack":
			attack_event = ev
			break
	_expect(not attack_event.is_empty(), "runner 产生了 attack 事件")
	if attack_event.is_empty():
		return
	_expect(bool(combat[&"attackerHits"]) == bool(attack_event["hit"]), "hit 一致（%s）" % str(combat[&"attackerHits"]))
	_expect(bool(combat[&"isCrit"]) == bool(attack_event["crit"]), "crit 一致")
	_expect(int(combat[&"attackerDamage"]) == int(attack_event["damage"]), "damage 一致（resolver=%d runner=%d）" % [int(combat[&"attackerDamage"]), int(attack_event["damage"])])
	_expect(bool(combat[&"defenderHits"]) == bool(attack_event["counter"]), "counter 一致")
	_expect(int(combat[&"defenderDamage"]) == int(attack_event["counter_damage"]), "counter_damage 一致")
	_expect(bool(combat[&"isDoubleAttack"]) == bool(attack_event["double"]), "double 一致")


func _find_unit(snapshots: Array, uid: String) -> Variant:
	for s in snapshots:
		if String((s as Dictionary).get("id", "")) == uid:
			return s
	return null


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
