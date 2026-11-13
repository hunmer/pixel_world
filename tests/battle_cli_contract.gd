## battle_cli_contract.gd — 声明式战场 CLI 契约（子进程退出码 + 战报文件）
extends SceneTree


const FIXTURE_QUICK_DUEL := "res://tests/fixtures/battle_scenarios/quick_duel.json"

var _failures: int = 0
var _godot := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[battle_cli_contract] start")
	_godot = OS.get_executable_path()
	print("  godot = %s" % _godot)
	var project := ProjectSettings.globalize_path("res://")
	_test_cli_ok(project)
	_test_cli_seed_override(project)
	_test_cli_bad_args(project)
	_test_cli_assertion_fail(project)
	_test_cli_illegal_action(project)
	if _failures > 0:
		push_error("[battle_cli_contract] FAILED: %d 处断言未过" % _failures)
		quit(1)
		return
	print("BATTLE_CLI_CONTRACT_OK")
	quit(0)


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  [ok] %s" % label)
	else:
		_failures += 1
		push_error("  [FAIL] %s" % label)


## 跑一次 CLI，返回 {code, stdout}。
func _run_cli(project: String, args: Array) -> Dictionary:
	var out: Array = []
	var code := OS.execute(_godot, ["--headless", "--path", project, "--script", "res://tools/battle_cli.gd", "--"] + args, out, true)
	return {"code": code, "stdout": "\n".join(out)}


func _clean_dir(rel: String) -> void:
	var base := ProjectSettings.globalize_path("user://")
	var abs := base + rel
	var dir := DirAccess.open(abs.get_base_dir())
	if dir == null:
		return
	if dir.dir_exists(rel):
		for f in ["events.jsonl", "result.json", "summary.txt"]:
			dir.remove(rel + "/" + f)
		dir.remove(rel)


func _test_cli_ok(project: String) -> void:
	print("[cli quick_duel exit 0]")
	_clean_dir("battle_reports/test_cli_contract/qd")
	var out_dir := ProjectSettings.globalize_path("user://") + "battle_reports/test_cli_contract/qd"
	var r := _run_cli(project, ["--scenario", FIXTURE_QUICK_DUEL, "--out", out_dir])
	_expect(int(r["code"]) == 0, "退出码 0（%s）" % r["stdout"].substr(-200).replace("\n", " "))
	var res_path := out_dir + "/result.json"
	_expect(FileAccess.file_exists(res_path), "result.json 已生成")
	_expect(FileAccess.file_exists(out_dir + "/events.jsonl"), "events.jsonl 已生成")
	_expect(FileAccess.file_exists(out_dir + "/summary.txt"), "summary.txt 已生成")
	if FileAccess.file_exists(res_path):
		var parsed = JSON.parse_string(FileAccess.open(res_path, FileAccess.READ).get_as_text())
		if parsed is Dictionary:
			var outcome: Dictionary = (parsed as Dictionary).get("outcome", {})
			_expect(String(outcome.get("stop_reason", "")) == "victory", "stop_reason==victory")
			_expect(String(outcome.get("winner", "")) == "player", "winner==player")
			var all_pass := true
			for a in ((parsed as Dictionary).get("assertions", []) as Array):
				if not bool((a as Dictionary).get("passed", false)):
					all_pass = false
			_expect(all_pass, "断言全部 passed")
		else:
			_expect(false, "result.json 可解析")


func _test_cli_seed_override(project: String) -> void:
	print("[cli --seed 覆盖]")
	_clean_dir("battle_reports/test_cli_contract/seed777")
	var out_dir := ProjectSettings.globalize_path("user://") + "battle_reports/test_cli_contract/seed777"
	var r := _run_cli(project, ["--scenario", FIXTURE_QUICK_DUEL, "--seed", "777", "--out", out_dir])
	_expect(int(r["code"]) == 0, "退出码 0")
	var res_path := out_dir + "/result.json"
	if FileAccess.file_exists(res_path):
		var parsed = JSON.parse_string(FileAccess.open(res_path, FileAccess.READ).get_as_text())
		_expect(parsed is Dictionary and int((parsed as Dictionary).get("seed", 0)) == 777, "result.seed==777（覆盖生效）")
	else:
		_expect(false, "result.json 已生成")


func _test_cli_bad_args(project: String) -> void:
	print("[cli 非法参数 exit 2]")
	var r1 := _run_cli(project, [])
	_expect(int(r1["code"]) == 2, "缺 --scenario → exit 2")
	var r2 := _run_cli(project, ["--scenario", "res://tests/fixtures/battle_scenarios/nope.json"])
	_expect(int(r2["code"]) == 2, "场景文件不存在 → exit 2")
	var r3 := _run_cli(project, ["--scenario", FIXTURE_QUICK_DUEL, "--seed", "abc"])
	_expect(int(r3["code"]) == 2, "--seed 非整数 → exit 2")
	var r4 := _run_cli(project, ["--frobnicate", "1"])
	_expect(int(r4["code"]) == 2, "未知参数 → exit 2")


func _test_cli_assertion_fail(project: String) -> void:
	print("[cli 断言失败 exit 1]")
	_clean_dir("battle_reports/test_cli_contract/assertfail")
	var out_dir := ProjectSettings.globalize_path("user://") + "battle_reports/test_cli_contract/assertfail"
	# 注：OS.execute 的 Windows 引号转义会破坏内联 JSON，这里走临时文件（内联 dict 链路已由
	# battle_automation_contract 的 load_from_dict 覆盖）。
	var tmp := ProjectSettings.globalize_path("user://") + "cli_assert_fail_scenario.json"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"version": 1, "id": "cli_assert_fail", "seed": 5,
		"battlefield": "res://data/battlefields/arena_1v1.json",
		"factions": {"player": {"mode": "ai"}, "enemy": {"mode": "ai"}},
		"assertions": [{"type": "battle_over", "op": "==", "value": false}],
	}))
	f.close()
	var r := _run_cli(project, ["--scenario", tmp, "--out", out_dir])
	_expect(int(r["code"]) == 1, "battle_over==false 必败断言 → exit 1")
	var res_path := out_dir + "/result.json"
	if FileAccess.file_exists(res_path):
		var parsed = JSON.parse_string(FileAccess.open(res_path, FileAccess.READ).get_as_text())
		var has_fail := false
		if parsed is Dictionary:
			for a in ((parsed as Dictionary).get("assertions", []) as Array):
				if not bool((a as Dictionary).get("passed", false)):
					has_fail = true
		_expect(has_fail, "result.assertions 含失败记录")
	else:
		_expect(false, "result.json 已生成（失败也写盘）")


func _test_cli_illegal_action(project: String) -> void:
	print("[cli 非法操作 exit 2]")
	_clean_dir("battle_reports/test_cli_contract/illegal")
	var out_dir := ProjectSettings.globalize_path("user://") + "battle_reports/test_cli_contract/illegal"
	var tmp := ProjectSettings.globalize_path("user://") + "cli_illegal_scenario.json"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"version": 1, "id": "cli_illegal", "seed": 5,
		"battlefield": "res://data/battlefields/arena_1v1.json",
		"factions": {
			"player": {"mode": "script", "script": [{"unit": "u_p_0", "attack": "u_e_0"}]},
			"enemy": {"mode": "ai"},
		},
	}))
	f.close()
	var r := _run_cli(project, ["--scenario", tmp, "--out", out_dir])
	_expect(int(r["code"]) == 2, "超距离攻击 → exit 2")
	var res_path := out_dir + "/result.json"
	if FileAccess.file_exists(res_path):
		var parsed = JSON.parse_string(FileAccess.open(res_path, FileAccess.READ).get_as_text())
		if parsed is Dictionary:
			_expect(String((parsed as Dictionary).get("error", "")).contains("step=1"), "result.error 带 step=1 定位")
		else:
			_expect(false, "result.json 可解析")
	else:
		_expect(false, "result.json 已生成（非法操作也写盘）")
