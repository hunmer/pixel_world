extends SceneTree

## tests/game_session_contract.gd — 战棋会话路由契约测试
## 运行：godot --headless --path . --script res://tests/game_session_contract.gd
## 覆盖：稳定身份 / 启动决策（默认→最近→恢复）/ open+commit+resume 往返 /
##       分战场隔离（不同战场互不影响）/ 一次性重置 / 无活动战斗提交拒绝。

const SessionScript := preload("res://scripts/scenes/game_session.gd")
const StoreScript := preload("res://scripts/core/battle_save_store.gd")
const Loader := preload("res://scripts/core/battlefield_loader.gd")

const TMP_DIR := "user://game_session_contract_tmp"
const PLAINS := "plains_skirmish"

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session: Node = SessionScript.new()
	var store: RefCounted = StoreScript.new()
	store.base_dir = TMP_DIR
	session.store = store

	_test_identities(session)
	_test_default_then_commit_then_resume(session, store)
	_test_isolation_between_battlefields(session, store)
	_test_reset(session, store)
	_test_world_latest_resume(session, store)
	_test_commit_without_battle(session)

	# 清理临时目录
	var dir := DirAccess.open(TMP_DIR)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
		dir.change_dir("..")
		dir.remove(TMP_DIR.get_file())
	if failures.is_empty():
		print("GAME_SESSION_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error("[game_session_contract] %s" % failure)
		quit(1)


# ------------------------------------------------------------------
# 稳定身份
# ------------------------------------------------------------------
func _test_identities(session: Node) -> void:
	var res_info := {"id": "plains_skirmish", "path": "res://data/battlefields/plains_skirmish.json",
		"file": "plains_skirmish.json"}
	_expect(session.identity_for_battlefield(res_info) == "bf:res/plains_skirmish",
		"res 战场身份应为 bf:res/plains_skirmish，实际 %s" % session.identity_for_battlefield(res_info))
	var user_info := {"id": "my_map", "path": "user://battlefields/my_map.json",
		"file": "my_map.json"}
	_expect(session.identity_for_battlefield(user_info) == "bf:user/my_map",
		"user 战场身份应为 bf:user/my_map，实际 %s" % session.identity_for_battlefield(user_info))
	var no_id := {"id": "", "path": "user://battlefields/legacy.json", "file": "legacy.json"}
	_expect(session.identity_for_battlefield(no_id) == "bf:user/<file>legacy.json",
		"无 id 旧文件应回退文件名身份，实际 %s" % session.identity_for_battlefield(no_id))
	_expect(session.identity_for_world_chapter(1234, Vector2i(-5, 7)) == "world:1234/-5/7",
		"世界战旗身份应为 world:1234/-5/7，实际 %s" % session.identity_for_world_chapter(1234, Vector2i(-5, 7)))


# ------------------------------------------------------------------
# 默认启动 → 提交 → 恢复（核心主流程）
# ------------------------------------------------------------------
func _test_default_then_commit_then_resume(session: Node, store: RefCounted) -> void:
	# 空存档冷启动：默认 plains_skirmish，fresh 模式
	var first: Dictionary = session.prepare_entry()
	_expect(String(first.get("mode", "")) == "fresh",
		"空存档应 fresh 启动，实际 %s（notice=%s）" % [str(first.get("mode")), str(first.get("notice"))])
	_expect(String(first.get("identity", "")) == "bf:res/" + PLAINS,
		"默认身份应为 bf:res/%s，实际 %s" % [PLAINS, str(first.get("identity"))])
	var chapter: Dictionary = first.get("chapter", {})
	_expect(not chapter.is_empty() and (chapter["playerUnits"] as Array).size() > 0,
		"默认 chapter 应有玩家单位")

	# open → 推进进度 → commit
	session.open_battle(String(first["identity"]), "battlefield", String(first["source"]), chapter)
	var p0: Dictionary = (chapter["playerUnits"] as Array)[0]
	p0["hp"] = int(p0["hp"]) - 5
	p0["hasActed"] = true
	var state := {"turn_number": 7, "phase": &"player", "hosting": false,
		"prefs": {}, "result": &""}
	var commit_res: Dictionary = session.commit(chapter, state)
	_expect(bool(commit_res.get("ok", false)),
		"commit 应成功: %s" % str(commit_res))
	_expect(store.load_latest() == String(first["identity"]),
		"最近索引应指向 plains_skirmish，实际 %s" % store.load_latest())

	# 二次启动：恢复模式，进度一致
	var second: Dictionary = session.prepare_entry()
	_expect(String(second.get("mode", "")) == "resume",
		"有存档应 resume，实际 %s（notice=%s）" % [str(second.get("mode")), str(second.get("notice"))])
	var r_state: Dictionary = second.get("state", {})
	_expect(int(r_state.get("turn_number", -1)) == 7,
		"恢复 turn_number 应为 7，实际 %s" % str(r_state.get("turn_number")))
	var r_p0: Dictionary = ((second.get("chapter", {}).get("playerUnits", []) as Array)[0] if (second.get("chapter", {}).get("playerUnits", []) as Array).size() > 0 else {})
	_expect(int(r_p0.get("hp", -1)) == int(p0["hp"]),
		"恢复 hp 应为 %d，实际 %s" % [int(p0["hp"]), str(r_p0.get("hp"))])
	_expect(bool(r_p0.get("hasActed", false)) == true, "恢复 hasActed 应保留")


# ------------------------------------------------------------------
# 分战场隔离：另一个战场的记录互不覆盖
# ------------------------------------------------------------------
func _test_isolation_between_battlefields(session: Node, store: RefCounted) -> void:
	var entries: Array = session.list_battlefields_checked()
	var other: Dictionary = {}
	for e in entries:
		if String(e.get("identity", "")) != "bf:res/" + PLAINS and bool((e.get("save") as Dictionary).get("exists", false)) == false:
			other = e
			break
	if other.is_empty():
		push_warning("[game_session_contract] 仓库只有 1 个战场，跳过隔离用例")
		return
	var loaded: Dictionary = Loader.load_battlefield(String(other["info"]["path"]))
	_expect(bool(loaded.get("ok", false)), "第二战场加载失败: %s" % str(loaded.get("error", "")))
	session.open_battle(String(other["identity"]), "battlefield", String(other["info"]["path"]), loaded["chapter"])
	var commit2: Dictionary = session.commit(loaded["chapter"],
		{"turn_number": 1, "phase": &"player", "hosting": false, "prefs": {}, "result": &""})
	_expect(bool(commit2.get("ok", false)), "第二战场 commit 应成功: %s" % str(commit2))
	_expect(store.load_latest() == String(other["identity"]),
		"最近索引应切到第二战场，实际 %s" % store.load_latest())
	# plains 的记录仍在且内容未被覆盖
	var plains_load: Dictionary = store.load_record("bf:res/" + PLAINS)
	_expect(bool(plains_load.get("ok", false)), "plains 记录不应被第二战场覆盖")
	if bool(plains_load.get("ok", false)):
		var rr: Dictionary = (plains_load["record"] as Dictionary)
		_expect(int(rr["state"]["turn_number"]) == 7,
			"plains 进度应保持 7，实际 %s" % str(rr["state"]["turn_number"]))


# ------------------------------------------------------------------
# 世界就地战旗：latest 指向 world: 身份时，冷启动直接从档案快照恢复；
# 世界内按 P（prepare_world_entry）同身份恢复、内容变更给提示。
# ------------------------------------------------------------------
func _test_world_latest_resume(session: Node, store: RefCounted) -> void:
	var loaded: Dictionary = Loader.load_battlefield("res://data/battlefields/" + PLAINS + ".json")
	_expect(bool(loaded.get("ok", false)), "世界用例加载 plains 失败: %s" % str(loaded.get("error", "")))
	if not bool(loaded.get("ok", false)):
		return
	var wid := "world:777/-3/4"
	var chapter: Dictionary = loaded["chapter"]
	session.open_battle(wid, "world", "world", chapter)
	var c: Dictionary = session.commit(chapter,
		{"turn_number": 4, "phase": &"enemy", "hosting": false, "prefs": {}, "result": &""})
	_expect(bool(c.get("ok", false)), "世界战旗 commit 应成功: %s" % str(c))
	# 冷启动：latest 是 world: → 直接恢复（不是回退默认战旗）
	var cold: Dictionary = session.prepare_entry()
	_expect(String(cold.get("mode", "")) == "resume",
		"latest=world 应 resume，实际 %s（notice=%s）" % [str(cold.get("mode")), str(cold.get("notice"))])
	_expect(String(cold.get("identity", "")) == wid,
		"恢复身份应为 %s，实际 %s" % [wid, str(cold.get("identity"))])
	_expect(int((cold.get("state", {}) as Dictionary).get("turn_number", -1)) == 4,
		"世界恢复 turn_number 应为 4")
	# 世界内按 P（同身份）：同样恢复；传入内容不同的 chapter → 恢复档案 + 变更提示
	var again: Dictionary = session.prepare_world_entry(wid, chapter)
	_expect(String(again.get("mode", "")) == "resume", "世界内再进应 resume，实际 %s" % str(again.get("mode")))
	var mutated: Dictionary = chapter.duplicate(true)
	(mutated["playerUnits"] as Array)[0]["hp"] = int((mutated["playerUnits"] as Array)[0]["hp"]) - 1
	var changed: Dictionary = session.prepare_world_entry(wid, mutated)
	_expect(String(changed.get("mode", "")) == "resume", "内容变更仍应 resume 档案")
	_expect(String(changed.get("notice", "")).contains("变更"),
		"内容变更应有提示，实际 %s" % str(changed.get("notice")))
	# 新位置（无档案身份）：fresh
	var fresh: Dictionary = session.prepare_world_entry("world:777/9/9", chapter)
	_expect(String(fresh.get("mode", "")) == "fresh", "无档案世界身份应 fresh")
	store.delete_record(wid)


# ------------------------------------------------------------------
# 一次性重置（prepare_entry_for reset）
# ------------------------------------------------------------------
func _test_reset(session: Node, store: RefCounted) -> void:
	var identity := "bf:res/" + PLAINS
	_expect(bool(store.load_record(identity).get("ok", false)), "重置前应存在记录")
	var after: Dictionary = session.prepare_entry_for(identity, true)
	_expect(String(after.get("mode", "")) == "fresh",
		"重置后应 fresh，实际 %s（notice=%s）" % [str(after.get("mode")), str(after.get("notice"))])
	_expect(String(after.get("notice", "")).contains("重置"),
		"重置应产生提示，实际 %s" % str(after.get("notice")))
	_expect(bool(store.load_record(identity).get("missing", false)) == true,
		"重置后档案应被删除")


# ------------------------------------------------------------------
# 未 open_battle 直接 commit → 拒绝
# ------------------------------------------------------------------
func _test_commit_without_battle(session: Node) -> void:
	var fresh_session: Node = SessionScript.new()
	var s2: RefCounted = StoreScript.new()
	s2.base_dir = TMP_DIR + "_2"
	fresh_session.store = s2
	var res: Dictionary = fresh_session.commit({}, {})
	_expect(not bool(res.get("ok", true)) and String(res.get("error", "")) == "no_active_battle",
		"无活动战斗 commit 应拒绝，实际 %s" % str(res))
	var dir2 := DirAccess.open(TMP_DIR + "_2")
	if dir2 != null:
		for f in dir2.get_files():
			dir2.remove(f)
		dir2.change_dir("..")
		dir2.remove((TMP_DIR + "_2").get_file())
