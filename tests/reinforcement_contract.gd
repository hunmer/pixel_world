## reinforcement_contract.gd — 按回合增援框架契约（A3）
##
## 覆盖：battlefield_loader 对 "reinforcements" 波次的解析/校验（合法/非法/
## 旧战场兼容）；ReinforcementSpawner 的刷入时点/落点兜底/幂等；
## BattleRunner 端到端（回合 N 前后单位集合、到点波次阻断提前判胜、
## 全波清空后 rout 胜）。
extends SceneTree

const Loader := preload("res://scripts/core/battlefield_loader.gd")
const Spawner := preload("res://scripts/core/reinforcement_spawner.gd")
const ScenarioLoader := preload("res://scripts/battle/automation/battle_scenario_loader.gd")
const Runner := preload("res://scripts/battle/automation/battle_runner.gd")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[reinforcement_contract] start")
	_test_loader_parse()
	_test_loader_reject()
	_test_loader_compat()
	_test_spawner_timing()
	_test_spawner_displaced()
	_test_runner_e2e()
	if _failures > 0:
		push_error("[reinforcement_contract] FAILED: %d 处断言未过" % _failures)
		quit(1)
		return
	print("REINFORCEMENT_CONTRACT_OK")
	quit(0)


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  [ok] %s" % label)
	else:
		_failures += 1
		push_error("  [FAIL] %s" % label)


func _base() -> Dictionary:
	return {
		"rows": [".......", ".......", ".......", "......."],
		"playerUnits": [{ "class": "swordsman", "level": 3, "x": 1, "y": 1 }],
		"enemyUnits": [{ "class": "berserker", "level": 1, "x": 6, "y": 0 }],
	}


## ---- battlefield_loader：合法解析 ------------------------------------------

func _test_loader_parse() -> void:
	print("[loader parse]")
	var d := _base()
	d["reinforcements"] = [
		{
			"turn": 2,
			"units": [{ "class": "archer", "level": 2 }, { "class": "lancer" }],
			"positions": [{ "x": 0, "y": 3 }, { "x": 6, "y": 3 }],
		},
		{ "turn": 4, "units": [{ "class": "assassin", "level": 3 }], "positions": [{ "x": 0, "y": 0 }] },
	]
	var r := Loader.load_battlefield_inline(d)
	_expect(bool(r["ok"]), "带 reinforcements 加载 ok")
	if not bool(r["ok"]):
		push_error("  error=%s" % String(r.get("error", "")))
		return
	var waves: Array = r["chapter"]["reinforcements"]
	_expect(waves.size() == 2, "两个波次解析")
	_expect(int((waves[0] as Dictionary)[&"turn"]) == 2 and ((waves[0] as Dictionary)[&"units"] as Array).size() == 2,
		"波次 0：turn=2 units=2")
	var u0: Dictionary = ((waves[0] as Dictionary)[&"units"] as Array)[0]
	_expect(String(u0[&"id"]) == "u_r0_0" and (u0[&"position"] as Vector2i) == Vector2i(0, 3),
		"增援单位 id=u_r0_0 落点 (0,3)")
	_expect(String(u0[&"faction"]) == "enemy" and int(u0[&"level"]) == 2, "增援单位 faction=enemy level=2")
	# 增援不进入初始 enemyUnits
	_expect((r["chapter"]["enemyUnits"] as Array).size() == 1, "初始 enemyUnits 仍为 1（增援未提前入场）")


## ---- battlefield_loader：非法拒绝 ------------------------------------------

func _test_loader_reject() -> void:
	print("[loader reject]")
	var d1 := _base(); d1["reinforcements"] = [{"units": [{"class": "archer"}], "positions": [{"x": 0, "y": 0}]}]
	_expect(not bool(Loader.load_battlefield_inline(d1)["ok"]), "缺 turn 拒绝")
	var d2 := _base(); d2["reinforcements"] = [{"turn": 0, "units": [{"class": "archer"}], "positions": [{"x": 0, "y": 0}]}]
	_expect(not bool(Loader.load_battlefield_inline(d2)["ok"]), "turn<1 拒绝")
	var d3 := _base(); d3["reinforcements"] = [{"turn": 2, "units": [], "positions": []}]
	_expect(not bool(Loader.load_battlefield_inline(d3)["ok"]), "空 units 拒绝")
	var d4 := _base(); d4["reinforcements"] = [{"turn": 2, "units": [{"class": "archer"}], "positions": []}]
	_expect(not bool(Loader.load_battlefield_inline(d4)["ok"]), "positions 与 units 不等长拒绝")
	var d5 := _base(); d5["reinforcements"] = [{"turn": 2, "units": [{"class": "ninja"}], "positions": [{"x": 0, "y": 0}]}]
	_expect(not bool(Loader.load_battlefield_inline(d5)["ok"]), "未知职业拒绝")
	var d6 := _base(); d6["reinforcements"] = [{"turn": 2, "units": [{"class": "archer"}], "positions": [{"x": 9, "y": 0}]}]
	_expect(not bool(Loader.load_battlefield_inline(d6)["ok"]), "坐标越界拒绝")
	var d7 := _base(); d7["reinforcements"] = "nope"
	_expect(not bool(Loader.load_battlefield_inline(d7)["ok"]), "reinforcements 非数组拒绝")
	# 与初始单位静态重叠也拒绝（同一 occupied 管线）
	var d8 := _base(); d8["reinforcements"] = [{"turn": 2, "units": [{"class": "archer"}], "positions": [{"x": 1, "y": 1}]}]
	_expect(not bool(Loader.load_battlefield_inline(d8)["ok"]), "与初始单位重叠拒绝")


## ---- battlefield_loader：旧战场兼容 + 演示战场 ------------------------------

func _test_loader_compat() -> void:
	print("[loader compat]")
	var r := Loader.load_battlefield_inline(_base())
	_expect(bool(r["ok"]) and not (r["chapter"] as Dictionary).has("reinforcements"),
		"无 reinforcements 字段 = 不写入 chapter（旧战场兼容）")
	var demo := Loader.load_battlefield("res://data/battlefields/ambush_reinforce.json")
	_expect(bool(demo["ok"]), "演示战场 ambush_reinforce.json 加载 ok")
	if bool(demo["ok"]):
		var waves: Array = demo["chapter"]["reinforcements"]
		_expect(waves.size() == 2 and int((waves[1] as Dictionary)[&"turn"]) == 3,
			"演示战场两波增援（第 2/3 轮）")


## ---- ReinforcementSpawner：时点与幂等 ---------------------------------------

func _test_spawner_timing() -> void:
	print("[spawner timing]")
	var d := _base()
	d["reinforcements"] = [
		{"turn": 2, "units": [{"class": "archer"}], "positions": [{"x": 0, "y": 2}]},
		{"turn": 3, "units": [{"class": "lancer"}], "positions": [{"x": 6, "y": 2}]},
	]
	var r := Loader.load_battlefield_inline(d)
	var ch: Dictionary = r["chapter"]
	var grid := GridSystem.new(int(ch["width"]), int(ch["height"]), ch["map"])
	for u in (ch["playerUnits"] as Array):
		grid.place_unit(u, (u[&"position"] as Vector2i).x, (u[&"position"] as Vector2i).y)
	for u in (ch["enemyUnits"] as Array):
		grid.place_unit(u, (u[&"position"] as Vector2i).x, (u[&"position"] as Vector2i).y)
	var tm := TurnManager.new((ch["playerUnits"] as Array) + (ch["enemyUnits"] as Array))
	# 第 1 轮：无到点波次
	var s1: Array = Spawner.spawn_due(ch, grid, tm, 1)
	_expect(s1.is_empty() and (ch["reinforcements"] as Array).size() == 2, "第 1 轮无刷入（两波仍在）")
	# 第 2 轮：波次 0 刷入
	var s2: Array = Spawner.spawn_due(ch, grid, tm, 2)
	_expect(s2.size() == 1 and String((s2[0] as Dictionary)[&"id"]) == "u_r0_0", "第 2 轮刷入 u_r0_0")
	_expect((ch["enemyUnits"] as Array).size() == 2, "刷入后 enemyUnits=2")
	_expect((tm.units as Array).size() == 3, "刷入后 turn.units=3")
	_expect((grid.unit_at(0, 2) as Dictionary).get(&"id", &"") == &"u_r0_0", "增援已放上 grid (0,2)")
	_expect((ch["reinforcements"] as Array).size() == 1, "波次 0 已消费")
	# 跳到第 5 轮（错过第 3 轮）：迟到也补刷，且幂等
	var s5: Array = Spawner.spawn_due(ch, grid, tm, 5)
	_expect(s5.size() == 1 and String((s5[0] as Dictionary)[&"id"]) == "u_r1_0", "迟到波次（turn<=N）补刷")
	_expect((ch["reinforcements"] as Array).is_empty(), "波次全部消费")
	var s6: Array = Spawner.spawn_due(ch, grid, tm, 6)
	_expect(s6.is_empty(), "重复调用不重复刷（幂等）")


## ---- ReinforcementSpawner：落点被占时邻近兜底 -------------------------------

func _test_spawner_displaced() -> void:
	print("[spawner displaced]")
	var d := _base()
	d["reinforcements"] = [{"turn": 1, "units": [{"class": "archer"}], "positions": [{"x": 0, "y": 0}]}]
	var r := Loader.load_battlefield_inline(d)
	var ch: Dictionary = r["chapter"]
	var grid := GridSystem.new(int(ch["width"]), int(ch["height"]), ch["map"])
	for u in (ch["playerUnits"] as Array):
		grid.place_unit(u, (u[&"position"] as Vector2i).x, (u[&"position"] as Vector2i).y)
	for u in (ch["enemyUnits"] as Array):
		grid.place_unit(u, (u[&"position"] as Vector2i).x, (u[&"position"] as Vector2i).y)
	var tm := TurnManager.new([])
	# 占住声明落点 (0,0)：一个玩家单位先站上去
	grid.place_unit(ch["playerUnits"][0], 0, 0)
	(ch["playerUnits"][0] as Dictionary)[&"position"] = Vector2i(0, 0)
	var spawned: Array = Spawner.spawn_due(ch, grid, tm, 1)
	_expect(spawned.size() == 1, "落点被占仍刷入（挪格兜底）")
	var pos: Vector2i = (spawned[0] as Dictionary)[&"position"]
	_expect(pos != Vector2i(0, 0) and grid.unit_at(pos.x, pos.y).get(&"id", &"") == (spawned[0] as Dictionary)[&"id"],
		"增援挪到最近空格且已入 grid")


## ---- BattleRunner：端到端 ---------------------------------------------------

func _run_reinforce_scenario() -> Dictionary:
	# 初始敌 1 人（hp 覆盖为 1，一刀即死）；第 2 轮敌方回合刷 1 个增援。
	# 胜利条件 defend_turns=3：T1 歼灭初始敌后若漏判 pending 会提前判胜；
	# 第 3 轮结束正常防守胜。增援全程存活 → 结果快照应包含它（链路④）。
	var bf := {
		"rows": [".......", ".......", ".......", "......."],
		"playerUnits": [{ "class": "swordsman", "level": 3, "x": 1, "y": 1 }],
		"enemyUnits": [{ "class": "berserker", "level": 1, "x": 6, "y": 0 }],
		"victory": { "type": "defend_turns", "turns": 3 },
		"reinforcements": [
			{"turn": 2, "units": [{ "class": "archer", "level": 1 }], "positions": [{"x": 0, "y": 3}]},
		],
	}
	var scenario := {
		"version": 1,
		"id": "rf_inline",
		"inline": bf,
		"seed": 23,
		"limits": { "max_turns": 6, "max_steps": 200 },
		"overrides": { "u_p_0": { "hp": 999 }, "u_e_0": { "hp": 1 } },
		"factions": {
			"player": {
				"mode": "script",
				"script": [
					{ "unit": "u_p_0", "move": { "x": 5, "y": 0 }, "attack": "u_e_0" },
				],
				"script_exhausted": "wait",
			},
			"enemy": { "mode": "script", "script": [], "script_exhausted": "wait" },
		},
		"assertions": [],
	}
	var res := ScenarioLoader.load_from_dict(scenario, "rf_inline")
	if not bool(res["ok"]):
		return { "ok": false, "error": res.get("error", "") }
	return Runner.run(res["scenario"])


func _test_runner_e2e() -> void:
	print("[runner e2e]")
	var run := _run_reinforce_scenario()
	if not bool(run["ok"]):
		_expect(false, "增援场景运行 ok（error=%s）" % String(run.get("error", "")))
		return
	_expect(true, "增援场景运行 ok")
	var events: Array = run["events"]
	# 事件流：T2 敌方相位前有 reinforce 事件；初始快照不含未入场增援
	var reinforce_turn := 0
	var in_initial_snapshot := false
	var in_final_units := false
	for e in events:
		var ev: Dictionary = e
		if String(ev.get("type", "")) == "reinforce":
			reinforce_turn = int(ev["turn"])
		if String(ev.get("type", "")) == "battle_start":
			for u in (ev.get("units", []) as Array):
				if String((u as Dictionary).get("id", "")) == "u_r0_0":
					in_initial_snapshot = true
	_expect(reinforce_turn == 2, "第 2 轮敌方相位发出 reinforce 事件")
	_expect(not in_initial_snapshot, "battle_start 快照不含未入场增援")
	var out: Dictionary = run["result"]["outcome"]
	_expect(String(out["winner"]) == "player" and String(out["stop_reason"]) == "victory",
		"T1 歼灭初始敌不提前判胜，第 3 轮防守胜")
	_expect(int(out["turns"]) == 3, "第 3 轮结束时结算（turns=3）")
	# 链路④：刷入单位自然进入结果单位集合（增援存活到最后）
	for u in (run["result"].get("final_units", []) as Array):
		if String((u as Dictionary).get("id", "")) == "u_r0_0":
			in_final_units = true
	_expect(in_final_units, "增援 u_r0_0 出现在最终单位集合")
