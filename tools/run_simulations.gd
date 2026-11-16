## run_simulations.gd — 批量战斗模拟命令行入口（SceneTree --script 模式）
#
# 用法: godot --headless --path <project> --script res://tools/run_simulations.gd -- \
#         --batch res://tests/fixtures/simulations/<batch>.json [--runs N] [--out <dir>]
#
# 退出码: 0=全部不变量通过  1=不变量失败  2=输入错误  4=运行/输出失败
# 默认次数由 batch 文件声明（5-20）；--runs 可显式覆盖（大容量模式，如 1000）。
extends SceneTree


const SimBatch := preload("res://tools/simulation_batch.gd")

const EXIT_OK := 0
const EXIT_INVARIANT := 1
const EXIT_INPUT := 2
const EXIT_RUN := 4


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var argv := OS.get_cmdline_user_args()
	var parsed := _parse_args(argv)
	if not bool(parsed["ok"]):
		if String(parsed.get("error", "")) == "--help":
			quit(EXIT_OK)
			return
		push_error("run_simulations: %s" % String(parsed["error"]))
		_usage()
		quit(EXIT_INPUT)
		return
	var opts: Dictionary = parsed["opts"]
	var loaded := SimBatch.load_batch(String(opts["batch"]))
	if not bool(loaded.get("ok", false)):
		push_error("run_simulations: %s" % String(loaded["error"]))
		_usage()
		quit(EXIT_INPUT)
		return
	var batch: Dictionary = loaded["batch"]
	var runs_override: Variant = null
	if String(opts["runs"]) != "":
		runs_override = int(opts["runs"])
	var executed := SimBatch.execute_batch(batch, runs_override)
	if not bool(executed.get("ok", false)):
		push_error("run_simulations: %s" % String(executed["error"]))
		quit(int(executed.get("exit_code", EXIT_RUN)))
		return
	# 控制台输出：每 run 一行 + 不变量结论 + 汇总
	for m in (executed["metrics"] as Array):
		var md: Dictionary = m as Dictionary
		print("SIM|run=%d|seed=%d|stop=%s|turns=%d|steps=%d|events=%d|digest=%s" % [
			int(md["index"]), int(md["seed"]), String(md["stop_reason"]),
			int(md["turns"]), int(md["steps"]), int(md["events_count"]),
			String(md["events_digest"]).substr(0, 12),
		])
	var all_pass := true
	for inv in (executed["invariants"] as Array):
		var d: Dictionary = inv as Dictionary
		var mark := "[inv-ok]" if bool(d["passed"]) else "[inv-FAIL]"
		if not bool(d["passed"]):
			all_pass = false
		print("%s %s — %s" % [mark, String(d["type"]), String(d["detail"])])
	var s: Dictionary = executed["summary"]
	print("SIMSUMMARY|batch=%s|runs=%d|strategy=%s|stop_reasons=%s|all_pass=%s" % [
		String(s["batch_id"]), int(s["runs"]), String(s["seed_strategy"]),
		", ".join(PackedStringArray(s["stop_reasons"])), str(bool(s["all_invariants_pass"])),
	])
	# 可选指标落盘（--out）
	if String(opts["out"]) != "":
		var out_dir := String(opts["out"])
		DirAccess.make_dir_recursive_absolute(out_dir)
		var payload := JSON.stringify({
			"summary": s,
			"metrics": executed["metrics"],
			"invariants": executed["invariants"],
		}, "  ")
		var path := out_dir.path_join("simulation_metrics.json")
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			push_error("run_simulations: 指标写盘失败: %s" % path)
			quit(EXIT_RUN)
			return
		f.store_string(payload + "\n")
		f.close()
		print("SIMSUMMARY|metrics=%s" % path)
	quit(EXIT_OK if all_pass else EXIT_INVARIANT)


## 解析命令行用户参数（-- 之后）。
func _parse_args(argv: Array) -> Dictionary:
	var opts := {"batch": "", "runs": "", "out": ""}
	var i := 0
	while i < argv.size():
		var a := String(argv[i])
		match a:
			"--batch":
				i += 1
				if i >= argv.size():
					return {"ok": false, "error": "--batch 需要一个路径参数"}
				opts["batch"] = String(argv[i])
			"--runs":
				i += 1
				if i >= argv.size():
					return {"ok": false, "error": "--runs 需要一个整数参数"}
				if not String(argv[i]).is_valid_int() or int(String(argv[i])) <= 0:
					return {"ok": false, "error": "--runs 必须是正整数: %s" % String(argv[i])}
				opts["runs"] = String(argv[i])
			"--out":
				i += 1
				if i >= argv.size():
					return {"ok": false, "error": "--out 需要一个目录参数"}
				opts["out"] = String(argv[i])
			"--help", "-h":
				_usage()
				return {"ok": false, "error": "--help"}
			_:
				return {"ok": false, "error": "未知参数: %s" % a}
		i += 1
	if String(opts["batch"]) == "":
		return {"ok": false, "error": "必须提供 --batch <path>"}
	return {"ok": true, "opts": opts}


func _usage() -> void:
	print("""用法: godot --headless --path <project> --script res://tools/run_simulations.gd -- <选项>
选项:
  --batch <path>   batch JSON（schema 见 tests/fixtures/simulations/；res:// 相对或绝对）
  --runs <int>     覆盖 batch 声明的次数（大容量模式显式指定，如 1000）
  --out <dir>      把逐次指标+不变量结论写为 <dir>/simulation_metrics.json
  --help           显示本帮助
退出码: 0=不变量全过  1=不变量失败  2=输入错误  4=运行/输出失败""")
