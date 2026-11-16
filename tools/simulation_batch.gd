## simulation_batch.gd — 批量战斗模拟核心（RefCounted，可被 CLI 与契约共同 preload）
#
# 职责：
#   1) 解析并校验批量模拟 batch JSON（schema 见 tests/fixtures/simulations/*.json 头部注释）；
#   2) 顺序执行 N 次战斗模拟：每次重新加载场景 JSON（无共享可变态）+ 复用 BattleRunner/resolver；
#   3) 逐次收集 JSON 指标（seed/stop_reason/turns/steps/断言/事件数/事件摘要）；
#   4) 按声明评估不变量（不变量位）：deterministic_events / stop_reason_in /
#      steps_bound / assertions_pass / exit_code_zero；
#   5) 不写盘、不打印 —— IO 与退出码映射交给调用方（tools/run_simulations.gd）。
#
# RNG 说明（重要，S5.2 隔离依据）：
#   BattleRunner._run 每次执行开头都调用全局 seed(scenario.seed)（battle_runner.gd L53），
#   因此同一进程内"顺序"多次 run 是逐次重播种的；本类只做顺序执行（不并发），
#   并发隔离交给进程级（runner --jobs 每契约一个 godot 进程）。
extends RefCounted


const Loader := preload("res://scripts/battle/automation/battle_scenario_loader.gd")
const Runner := preload("res://scripts/battle/automation/battle_runner.gd")

const MIN_DEFAULT_RUNS := 5
const MAX_DEFAULT_RUNS := 20
const KNOWN_INVARIANTS := [
	"deterministic_events", "stop_reason_in", "steps_bound",
	"assertions_pass", "exit_code_zero",
]


## 解析 batch JSON 文件并校验；返回 {ok} 或 {ok:false, error}。
static func load_batch(path: String) -> Dictionary:
	if not path.begins_with("res://") and not path.begins_with("user://") and not path.is_absolute_path():
		path = "res://".path_join(path)
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return {"ok": false, "error": "batch 文件不可读或为空: %s" % path}
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return {"ok": false, "error": "batch 不是合法 JSON 对象: %s" % path}
	return validate_batch(parsed as Dictionary, path)


## 校验 batch 结构；返回规范化后的 batch（补默认值）。
## 注意：JSON 数字解析为 float，且 GDScript 无 String(float) 构造器 —— 一律先验类型再取值。
static func validate_batch(d: Dictionary, path: String) -> Dictionary:
	for key in ["version", "id", "mode", "scenario"]:
		if not d.has(key) or d[key] == null:
			return {"ok": false, "error": "batch 缺少必填字段 %s: %s" % [key, path]}
	if not ((d["version"] is int) or (d["version"] is float)):
		return {"ok": false, "error": "batch version 必须是数字: %s" % path}
	if int(d["version"]) != 1:
		return {"ok": false, "error": "batch version 仅支持 1: %s" % path}
	if not (d["id"] is String) or (d["id"] as String) == "":
		return {"ok": false, "error": "batch id 必须是非空字符串: %s" % path}
	if not (d["mode"] is String):
		return {"ok": false, "error": "batch mode 必须是字符串: %s" % path}
	if String(d["mode"]) != "battle":
		return {"ok": false, "error": "batch mode 仅支持 battle（当前: %s）: %s" % [String(d["mode"]), path]}
	if not (d["scenario"] is String) or (d["scenario"] as String) == "":
		return {"ok": false, "error": "batch scenario 必须是非空字符串路径: %s" % path}
	if d.has("description") and d["description"] != null and not (d["description"] is String):
		return {"ok": false, "error": "batch description 必须是字符串: %s" % path}
	# runs：缺省 5，batch 文件声明值必须落在 5-20（CLI --runs 可显式覆盖为任意正数）
	var runs := MIN_DEFAULT_RUNS
	if d.has("runs"):
		if not (d["runs"] is int) and not (d["runs"] is float):
			return {"ok": false, "error": "batch runs 必须是整数: %s" % path}
		runs = int(d["runs"])
		if runs < MIN_DEFAULT_RUNS or runs > MAX_DEFAULT_RUNS:
			return {"ok": false, "error": "batch runs 必须在 %d-%d（大容量请用 CLI --runs 显式指定）: %s" % [MIN_DEFAULT_RUNS, MAX_DEFAULT_RUNS, path]}
	# seed 策略
	var strategy := "fixed"
	var base_seed := 0
	if d.has("seed") and d["seed"] is Dictionary:
		var sd: Dictionary = d["seed"]
		if sd.has("strategy"):
			if not (sd["strategy"] is String):
				return {"ok": false, "error": "seed.strategy 必须是字符串: %s" % path}
			strategy = String(sd["strategy"])
		if strategy != "fixed" and strategy != "sequential":
			return {"ok": false, "error": "seed.strategy 仅支持 fixed/sequential: %s" % path}
		if not sd.has("base") or not ((sd["base"] is int) or (sd["base"] is float)):
			return {"ok": false, "error": "seed.base 必须是整数: %s" % path}
		base_seed = int(sd["base"])
	# 不变量
	var invariants: Array = d.get("invariants", [])
	for inv in invariants:
		if not (inv is Dictionary) or not (inv as Dictionary).has("type"):
			return {"ok": false, "error": "不变量必须是含 type 的对象: %s" % path}
		if not ((inv as Dictionary)["type"] is String):
			return {"ok": false, "error": "不变量 type 必须是字符串: %s" % path}
		var t := String((inv as Dictionary)["type"])
		if not KNOWN_INVARIANTS.has(t):
			return {"ok": false, "error": "未知不变量 type: %s（支持: %s）: %s" % [t, ", ".join(KNOWN_INVARIANTS), path]}
		if t == "stop_reason_in":
			var invd: Dictionary = inv as Dictionary
			if not invd.has("allowed") or not (invd["allowed"] is Array):
				return {"ok": false, "error": "stop_reason_in 需要 allowed 列表: %s" % path}
			for a in (invd["allowed"] as Array):
				if not (a is String):
					return {"ok": false, "error": "stop_reason_in.allowed 元素必须是字符串: %s" % path}
	var batch := {
		"version": 1,
		"id": String(d["id"]),
		"description": String(d.get("description", "")),
		"mode": "battle",
		"scenario": String(d["scenario"]),
		"runs": runs,
		"seed_strategy": strategy,
		"seed_base": base_seed,
		"invariants": invariants,
	}
	return {"ok": true, "batch": batch}


## 第 index 次运行的 seed（fixed=恒定；sequential=base+index）。
static func seed_for(batch: Dictionary, index: int) -> int:
	if String(batch["seed_strategy"]) == "sequential":
		return int(batch["seed_base"]) + index
	return int(batch["seed_base"])


## 执行一个 run：重新加载场景 JSON（深态隔离）→ Runner.run → 单次指标。
## 返回 {ok, metrics} 或 {ok:false, error, exit_code}。
static func run_once(batch: Dictionary, index: int) -> Dictionary:
	var override_seed: int = seed_for(batch, index)
	var loaded := Loader.load_from_file(String(batch["scenario"]), override_seed)
	if not bool(loaded["ok"]):
		return {"ok": false, "error": "run[%d] 场景加载失败: %s" % [index, String(loaded.get("error", ""))], "exit_code": 4}
	var scenario: Dictionary = loaded["scenario"]
	var run := Runner.run(scenario)
	if not bool(run["ok"]):
		return {"ok": false, "error": "run[%d] runner 失败: %s" % [index, String(run.get("error", ""))], "exit_code": 4}
	var result: Dictionary = run["result"]
	var events: Array = run["events"]
	var exit_code := int(run["exit_code"])
	var failed := 0
	for a in (result.get("assertions", []) as Array):
		if not bool((a as Dictionary).get("passed", false)):
			failed += 1
	var outcome: Dictionary = result.get("outcome", {})
	var metrics := {
		"index": index,
		"seed": override_seed,
		"exit_code": exit_code,
		"stop_reason": String(outcome.get("stop_reason", "?")),
		"winner": String(outcome.get("winner", "?")),
		"battle_over": bool(outcome.get("battle_over", false)),
		"turns": int(outcome.get("turns", 0)),
		"steps": int(outcome.get("steps", 0)),
		"assertions_total": int((result.get("assertions", []) as Array).size()),
		"assertions_failed": failed,
		"events_count": events.size(),
		"events_digest": digest_events(events),
	}
	return {"ok": true, "metrics": metrics}


## 事件摘要：SHA-256(JSON(events))，用于同 seed 复跑的逐字节可比对。
static func digest_events(events: Array) -> String:
	return JSON.stringify(events).sha256_text()


## 顺序执行整个 batch（runs_override 非 null 时覆盖次数，用于大容量 --runs）。
## 返回 {ok, batch_id, runs, metrics[], invariants[], summary}。
static func execute_batch(batch: Dictionary, runs_override: Variant = null) -> Dictionary:
	var runs := int(batch["runs"])
	if runs_override != null:
		runs = int(runs_override)
	var metrics: Array = []
	for i in runs:
		var one := run_once(batch, i)
		if not bool(one["ok"]):
			return {"ok": false, "error": String(one["error"]), "exit_code": int(one.get("exit_code", 4))}
		metrics.append(one["metrics"])
	var invariants := evaluate_invariants(batch, metrics)
	var all_pass := true
	for inv in invariants:
		if not bool((inv as Dictionary)["passed"]):
			all_pass = false
	var summary := {
		"batch_id": String(batch["id"]),
		"scenario": String(batch["scenario"]),
		"runs": runs,
		"seed_strategy": String(batch["seed_strategy"]),
		"seed_base": int(batch["seed_base"]),
		"all_invariants_pass": all_pass,
		"stop_reasons": _unique_stop_reasons(metrics),
	}
	return {"ok": true, "batch_id": String(batch["id"]), "runs": runs, "metrics": metrics, "invariants": invariants, "summary": summary}


## 评估全部不变量；返回 [{type, passed, detail}]。
static func evaluate_invariants(batch: Dictionary, metrics: Array) -> Array:
	var out: Array = []
	for inv in (batch["invariants"] as Array):
		var t := String((inv as Dictionary)["type"])
		match t:
			"deterministic_events":
				out.append(_inv_deterministic_events(metrics))
			"stop_reason_in":
				out.append(_inv_stop_reason_in(inv as Dictionary, metrics))
			"steps_bound":
				out.append(_inv_steps_bound(metrics))
			"assertions_pass":
				out.append(_inv_assertions_pass(metrics))
			"exit_code_zero":
				out.append(_inv_exit_code_zero(metrics))
	return out


static func _inv_deterministic_events(metrics: Array) -> Dictionary:
	# 同 seed 的所有 run，events_digest 必须一致
	var by_seed := {}
	for m in metrics:
		var md: Dictionary = m as Dictionary
		var s := int(md["seed"])
		if not by_seed.has(s):
			by_seed[s] = String(md["events_digest"])
		elif String(by_seed[s]) != String(md["events_digest"]):
			var bad := "seed=%d 出现不同事件摘要: %s vs %s" % [s, String(by_seed[s]).substr(0, 12), String(md["events_digest"]).substr(0, 12)]
			return {"type": "deterministic_events", "passed": false, "detail": bad}
	var seeds := by_seed.keys().map(func(s): return int(s))
	return {"type": "deterministic_events", "passed": true, "detail": "同 seed 事件摘要一致（%d 个 run / %d 个不同 seed）" % [metrics.size(), seeds.size()]}


static func _inv_stop_reason_in(inv: Dictionary, metrics: Array) -> Dictionary:
	var allowed: Array = []
	for a in (inv["allowed"] as Array):
		allowed.append(String(a))
	var bad_list: Array = []
	for m in metrics:
		var reason := String((m as Dictionary)["stop_reason"])
		if not allowed.has(reason):
			bad_list.append(reason)
	if not bad_list.is_empty():
		return {"type": "stop_reason_in", "passed": false, "detail": "出现不允许的 stop_reason: %s" % ", ".join(PackedStringArray(bad_list))}
	return {"type": "stop_reason_in", "passed": true, "detail": "stop_reason 全部在 %s 内" % ", ".join(PackedStringArray(allowed))}


static func _inv_steps_bound(metrics: Array) -> Dictionary:
	var max_steps := -1
	for m in metrics:
		max_steps = maxi(max_steps, int((m as Dictionary)["steps"]))
	if max_steps < 0:
		return {"type": "steps_bound", "passed": false, "detail": "无 run 数据"}
	return {"type": "steps_bound", "passed": true, "detail": "最大 steps=%d（有限步，全部 run 均已终止）" % max_steps}


static func _inv_assertions_pass(metrics: Array) -> Dictionary:
	var failed := 0
	for m in metrics:
		failed += int((m as Dictionary)["assertions_failed"])
	if failed > 0:
		return {"type": "assertions_pass", "passed": false, "detail": "共 %d 条场景断言失败" % failed}
	return {"type": "assertions_pass", "passed": true, "detail": "场景断言全部通过"}


static func _inv_exit_code_zero(metrics: Array) -> Dictionary:
	var bad: Array = []
	for m in metrics:
		if int((m as Dictionary)["exit_code"]) != 0:
			bad.append(int((m as Dictionary)["exit_code"]))
	if not bad.is_empty():
		return {"type": "exit_code_zero", "passed": false, "detail": "存在非 0 退出码: %s" % str(bad)}
	return {"type": "exit_code_zero", "passed": true, "detail": "全部 run 退出码为 0"}


static func _unique_stop_reasons(metrics: Array) -> Array:
	var seen := {}
	for m in metrics:
		seen[String((m as Dictionary)["stop_reason"])] = true
	return seen.keys()
