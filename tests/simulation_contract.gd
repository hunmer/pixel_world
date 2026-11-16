## simulation_contract.gd — 批量模拟入口契约：fixtures schema、指标形态、不变量、RNG 隔离证据
extends SceneTree


const SimBatch := preload("res://tools/simulation_batch.gd")

const BATCH_FIXED := "res://tests/fixtures/simulations/battle_determinism_fixed.json"
const BATCH_SEQ := "res://tests/fixtures/simulations/battle_smoke_sequential.json"

var _failures: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_fixtures_schema()
	_check_fixed_batch_execution()
	_check_sequential_batch_execution()
	_check_in_process_rng_isolation()
	if _failures.is_empty():
		print("[OK] simulation_contract: 全部检查通过")
		quit(0)
	else:
		for f in _failures:
			print("[FAIL] simulation_contract: %s" % String(f))
		quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


## 1) fixtures 能解析、字段合法（schema 层）。
func _check_fixtures_schema() -> void:
	for path in [BATCH_FIXED, BATCH_SEQ]:
		var loaded := SimBatch.load_batch(path)
		if not bool(loaded.get("ok", false)):
			_fail("batch 解析失败 %s: %s" % [path, String(loaded.get("error", ""))])
			continue
		var batch: Dictionary = loaded["batch"]
		if int(batch["runs"]) < 5 or int(batch["runs"]) > 20:
			_fail("batch 默认 runs 必须在 5-20: %s (runs=%d)" % [path, int(batch["runs"])])
		print("SIMBATCH|fixture=%s|runs=%d|strategy=%s|invariants=%d" % [
			String(batch["id"]), int(batch["runs"]), String(batch["seed_strategy"]),
			(batch["invariants"] as Array).size(),
		])
	# 非法 batch 必须被拒（runs 越界 / 未知不变量）
	var bad_runs := SimBatch.validate_batch({
		"version": 1, "id": "x", "mode": "battle", "scenario": "s.json",
		"runs": 1000, "seed": {"strategy": "fixed", "base": 1}, "invariants": [],
	}, "inline")
	if bool(bad_runs["ok"]):
		_fail("runs=1000 的 batch 必须被拒（大容量只允许 CLI --runs 显式覆盖）")
	var bad_inv := SimBatch.validate_batch({
		"version": 1, "id": "x", "mode": "battle", "scenario": "s.json",
		"runs": 5, "seed": {"strategy": "fixed", "base": 1},
		"invariants": [{"type": "no_such_invariant"}],
	}, "inline")
	if bool(bad_inv["ok"]):
		_fail("未知不变量 type 必须被拒")


## 2) fixed 批：6 次全过、指标形态齐全、全部不变量通过、同 seed 摘要一致。
func _check_fixed_batch_execution() -> void:
	var loaded := SimBatch.load_batch(BATCH_FIXED)
	if not bool(loaded.get("ok", false)):
		_fail("fixed batch 加载失败: %s" % String(loaded.get("error", "")))
		return
	var executed := SimBatch.execute_batch(loaded["batch"])
	if not bool(executed.get("ok", false)):
		_fail("fixed batch 执行失败: %s" % String(executed.get("error", "")))
		return
	var metrics: Array = executed["metrics"]
	if metrics.size() != 6:
		_fail("fixed batch 应执行 6 次，实际 %d" % metrics.size())
		return
	for m in metrics:
		var md: Dictionary = m as Dictionary
		for key in ["index", "seed", "exit_code", "stop_reason", "turns", "steps",
				"assertions_total", "assertions_failed", "events_count", "events_digest"]:
			if not md.has(key):
				_fail("指标缺少字段 %s" % key)
				return
		if int(md["exit_code"]) != 0:
			_fail("run[%d] 退出码非 0: %d" % [int(md["index"]), int(md["exit_code"])])
		if int(md["assertions_failed"]) > 0:
			_fail("run[%d] 场景断言失败 %d 条" % [int(md["index"]), int(md["assertions_failed"])])
		if int(md["steps"]) <= 0 or int(md["events_count"]) < 1:
			_fail("run[%d] 指标异常: steps=%d events=%d" % [int(md["index"]), int(md["steps"]), int(md["events_count"])])
	var digests := {}
	for m in metrics:
		digests[(m as Dictionary)["events_digest"]] = true
	if digests.size() != 1:
		_fail("fixed seed 6 次复跑事件摘要应唯一，实际 %d 种" % digests.size())
	_check_all_invariants_pass(executed["invariants"], "fixed")
	print("SIMBATCH|fixed|digest=%s|steps=%d" % [
		String((metrics[0] as Dictionary)["events_digest"]).substr(0, 12),
		int((metrics[0] as Dictionary)["steps"]),
	])


## 3) sequential 批：5 次不同 seed、runs_override 生效、断言全过。
func _check_sequential_batch_execution() -> void:
	var loaded := SimBatch.load_batch(BATCH_SEQ)
	if not bool(loaded.get("ok", false)):
		_fail("sequential batch 加载失败: %s" % String(loaded.get("error", "")))
		return
	var executed := SimBatch.execute_batch(loaded["batch"], 3)  # 覆盖为 3 次，契约内提速
	if not bool(executed.get("ok", false)):
		_fail("sequential batch 执行失败: %s" % String(executed.get("error", "")))
		return
	if int(executed["runs"]) != 3:
		_fail("runs_override=3 未生效，实际 %d" % int(executed["runs"]))
	var seeds: Array = []
	for m in (executed["metrics"] as Array):
		seeds.append(int((m as Dictionary)["seed"]))
	if seeds != [42, 43, 44]:
		_fail("sequential seed 序列应为 42,43,44，实际 %s" % str(seeds))
	_check_all_invariants_pass(executed["invariants"], "sequential")


## 4) S5.2 同进程 RNG 隔离证据：A→B→A 三段，两次 A 的事件摘要必须一致。
##    BattleRunner 每次执行开头 seed(scenario.seed)（全局重播种），
##    因此顺序多 run 相互独立；并发才会共享全局流（故并发隔离走进程级）。
func _check_in_process_rng_isolation() -> void:
	var batch_a := {"id": "isoA", "mode": "battle", "scenario": "res://tests/fixtures/battle_scenarios/deterministic_replay.json",
		"runs": 1, "seed_strategy": "fixed", "seed_base": 42, "invariants": []}
	var batch_b := {"id": "isoB", "mode": "battle", "scenario": "res://tests/fixtures/battle_scenarios/quick_duel.json",
		"runs": 1, "seed_strategy": "fixed", "seed_base": 7, "invariants": []}
	var a1 := SimBatch.run_once(batch_a, 0)
	var b := SimBatch.run_once(batch_b, 0)
	var a2 := SimBatch.run_once(batch_a, 0)
	if not (bool(a1["ok"]) and bool(b["ok"]) and bool(a2["ok"])):
		_fail("隔离性验证三段运行有失败: %s / %s / %s" % [str(a1.get("ok")), str(b.get("ok")), str(a2.get("ok"))])
		return
	var d1 := String((a1["metrics"] as Dictionary)["events_digest"])
	var db := String((b["metrics"] as Dictionary)["events_digest"])
	var d2 := String((a2["metrics"] as Dictionary)["events_digest"])
	if d1 != d2:
		_fail("同进程 A→B→A 隔离破坏：A 首跑 %s vs A 复跑 %s" % [d1.substr(0, 12), d2.substr(0, 12)])
	if d1 == db:
		_fail("不同场景/seed 的事件摘要不应相同")
	print("SIMBATCH|isolation|A=%s|B=%s|A2==A=%s" % [d1.substr(0, 12), db.substr(0, 12), str(d1 == d2)])


func _check_all_invariants_pass(invariants: Array, label: String) -> void:
	for inv in invariants:
		var d: Dictionary = inv as Dictionary
		if not bool(d["passed"]):
			_fail("%s 批不变量 %s 失败: %s" % [label, String(d["type"]), String(d["detail"])])
