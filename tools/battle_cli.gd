## battle_cli.gd — 声明式战场命令行入口（SceneTree --script 模式）
extends SceneTree


const ScenarioLoader := preload("res://scripts/battle/automation/battle_scenario_loader.gd")
const Runner := preload("res://scripts/battle/automation/battle_runner.gd")
const Report := preload("res://scripts/battle/automation/battle_report.gd")

const EXIT_OK := 0            # 正常结束且断言通过
const EXIT_ASSERTION := 1     # 断言失败
const EXIT_INPUT := 2         # 输入参数/非法操作
const EXIT_STALEMATE := 3     # 非预期轮数/步数上限（僵持保护）
const EXIT_RUN := 4           # 输出/运行失败


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var argv := OS.get_cmdline_user_args()
	var parsed := _parse_args(argv)
	if not parsed["ok"]:
		if String(parsed.get("error", "")) == "--help":
			quit(EXIT_OK)
			return
		push_error("battle_cli: %s" % parsed["error"])
		_usage()
		quit(EXIT_INPUT)
		return
	var opts: Dictionary = parsed["opts"]
	# 场景加载
	var scenario_res := _load_scenario(opts)
	if not scenario_res["ok"]:
		push_error("battle_cli: %s" % scenario_res["error"])
		_usage()
		quit(EXIT_INPUT)
		return
	var scenario: Dictionary = scenario_res["scenario"]
	# 执行
	var run := Runner.run(scenario)
	if not bool(run["ok"]):
		push_error("battle_cli: runner 失败: %s" % String(run.get("error", "")))
		quit(EXIT_RUN)
		return
	var result: Dictionary = run["result"]
	var events: Array = run["events"]
	var exit_code := int(run["exit_code"])
	# 战报写盘
	var out_dir := _resolve_out_dir(opts, scenario)
	var written := Report.write_all(out_dir, events, result)
	if not bool(written["ok"]):
		push_error("battle_cli: 战报写盘失败: %s" % String(written["error"]))
		quit(EXIT_RUN)
		return
	# 控制台摘要（stdout）
	print("battle_cli: 场景=%s seed=%d → %s (turns=%d steps=%d) 退出码=%d" % [
		String(result.get("scenario_id", "?")),
		int(result.get("seed", 0)),
		String(result.get("outcome", {}).get("stop_reason", "?")),
		int(result.get("outcome", {}).get("turns", 0)),
		int(result.get("outcome", {}).get("steps", 0)),
		exit_code,
	])
	for a in (result.get("assertions", []) as Array):
		if not bool((a as Dictionary).get("passed", false)):
			print("  [断言失败] %s" % String((a as Dictionary).get("summary", "")))
	print("battle_cli: 战报已写入 %s" % String(written["dir"]))
	quit(exit_code)


## 解析命令行用户参数（-- 分隔后的部分）。
func _parse_args(argv: Array) -> Dictionary:
	var opts := {
		"scenario": "", "scenario-json": "", "seed": null, "out": "",
	}
	var i := 0
	while i < argv.size():
		var a := String(argv[i])
		match a:
			"--scenario":
				i += 1
				if i >= argv.size():
					return {"ok": false, "error": "--scenario 需要一个路径参数"}
				opts["scenario"] = String(argv[i])
			"--scenario-json":
				i += 1
				if i >= argv.size():
					return {"ok": false, "error": "--scenario-json 需要一个 JSON 字符串参数"}
				opts["scenario-json"] = String(argv[i])
			"--seed":
				i += 1
				if i >= argv.size():
					return {"ok": false, "error": "--seed 需要一个整数参数"}
				if not String(argv[i]).is_valid_int():
					return {"ok": false, "error": "--seed 必须是整数: %s" % String(argv[i])}
				opts["seed"] = String(argv[i]).to_int()
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
	if opts["scenario"] == "" and opts["scenario-json"] == "":
		return {"ok": false, "error": "必须提供 --scenario <path> 或 --scenario-json <json> 之一"}
	if opts["scenario"] != "" and opts["scenario-json"] != "":
		return {"ok": false, "error": "--scenario 与 --scenario-json 只能二选一"}
	return {"ok": true, "opts": opts}


## 加载场景（文件路径或内联 JSON）。
func _load_scenario(opts: Dictionary) -> Dictionary:
	var seed_override: Variant = opts["seed"]
	if opts["scenario-json"] != "":
		var text := String(opts["scenario-json"])
		var parsed = JSON.parse_string(text)
		if parsed == null or not (parsed is Dictionary):
			return {"ok": false, "error": "--scenario-json 不是合法 JSON 对象"}
		return ScenarioLoader.load_from_dict(parsed as Dictionary, "inline", seed_override)
	var path := String(opts["scenario"])
	if not path.begins_with("res://") and not path.is_absolute_path():
		path = "res://".path_join(path)
	return ScenarioLoader.load_from_file(path, seed_override)


## 解析输出目录：--out 优先，否则 user://battle_reports/<scenario_id>/run_<seed>。
func _resolve_out_dir(opts: Dictionary, scenario: Dictionary) -> String:
	if String(opts["out"]) != "":
		return String(opts["out"])
	return "user://battle_reports/%s/run_%d" % [String(scenario["id"]), int(scenario["seed"])]


func _usage() -> void:
	print("""用法: godot --headless --path <project> --script res://tools/battle_cli.gd -- <选项>
选项:
  --scenario <path>        场景 JSON 文件路径（res:// 相对或绝对）
  --scenario-json <json>   内联场景 JSON（与 --scenario 二选一）
  --seed <int>             覆盖场景 seed
  --out <dir>              战报输出目录（缺省 user://battle_reports/<id>/run_<seed>）
  --help                   显示本帮助
退出码: 0=正常+断言过  1=断言失败  2=输入/非法操作  3=轮数步数上限  4=输出/运行失败""")
