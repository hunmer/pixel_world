## campaign_battle_integration_contract.gd — 真实战场结算接回冒险的运行态探针。
## MCP 启动同名 tscn，断言 finished/passed，再检查 error 日志。
extends Node2D

const BattleScene = preload("res://scenes/Battle.tscn")
const Bridge = preload("res://scripts/battle/campaign_battle_bridge.gd")

var finished := false
var passed := false
var checks: Array[Dictionary] = []
var _session: Node
var _profile_id := ""
var _old_presentation := false


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	checks.append({"label": label, "passed": condition})
	if not condition:
		push_error("[campaign_integration] " + label)


func _run() -> void:
	_old_presentation = Settings.battle_immersive_presentation
	_session = get_node("/root/CampaignSession")
	_session.configure_store_dir("user://campaign_integration_%d" % Time.get_ticks_usec())
	var created: Dictionary = _session.create_profile("战斗集成测试")
	_check(bool(created.get("ok", false)), "创建隔离测试冒险")
	if not bool(created.get("ok", false)):
		_finish()
		return
	var profile: Dictionary = _session.get_profile()
	_profile_id = String(profile["id"])
	var levels: Array = _session.list_levels()
	var prepared: Dictionary = _session.prepare_battle(String(levels[0]["id"]))
	_check(bool(prepared.get("ok", false)), "首关出征成功")
	if not bool(prepared.get("ok", false)):
		_finish()
		return
	Settings.set_battle_immersive_presentation(false)
	SceneArgs.battle_args = {
		"chapter": prepared["chapter"],
		"campaign_token": prepared["token"],
		"save_identity": "intentionally-stale-legacy-identity",
		"save_state": {"result": &"win"},
	}
	var battle = BattleScene.instantiate()
	add_child(battle)
	await battle.battle_ready
	_check(battle._save.identity.is_empty(), "冒险战斗隔离旧存档身份")
	_check(battle._save.pending_state.is_empty(), "不恢复旧回合记录")
	var actor: Dictionary = battle.chapter.playerUnits[0]
	var expected_exp := int(actor["exp"]) + 7
	actor["exp"] = expected_exp
	actor["hp"] = 1
	for enemy in battle.chapter.enemyUnits:
		enemy["hp"] = 0
		enemy["isDead"] = true
		battle.grid.remove_unit(enemy)
	battle._check_battle_end()
	# 探针保留当前场景检查持久化；正常玩家流程仍由原回调返回营地。
	var finish_callback := Callable(battle, "_on_result_presentation_finished")
	if battle.battle_ui.result_finished.is_connected(finish_callback):
		battle.battle_ui.result_finished.disconnect(finish_callback)
	_check(battle._battle_ended, "真实胜负判定进入终局")
	_check(bool(battle._campaign_receipt.get("ok", false)), "真实终局提交冒险成功")
	var after: Dictionary = _session.get_profile()
	_check(int(after["gold"]) == 200, "首胜奖励200金币")
	_check((after["completed_levels"] as Array).size() == 1, "记录首关通关")
	_check(int(after["roster"][0]["exp"]) == expected_exp, "保留战斗实际经验")
	_check(int(actor["hp"]) == 1, "存档结算不原地修改演出中的角色")
	_check(int(after["roster"][0]["hp"]) > 1, "营地恢复角色生命")
	_check(battle._settle_campaign(&"win"), "重复结束回调成功返回")
	_check(int((_session.get_profile() as Dictionary)["gold"]) == 200, "重复回调不重复发奖")
	var reloaded: Dictionary = _session.load_profile(_profile_id)
	_check(bool(reloaded.get("ok", false)), "胜利档可以重新加载")
	_check(int((_session.get_profile() as Dictionary)["gold"]) == 200, "重新加载仍有首胜金币")
	battle.queue_free()
	await get_tree().process_frame
	var retry: Dictionary = _session.prepare_battle(String(levels[0]["id"]))
	_check(bool(retry.get("ok", false)), "已过关可以再次出征")
	if bool(retry.get("ok", false)):
		var retry_chapter: Dictionary = retry["chapter"]
		retry_chapter["playerUnits"][0]["exp"] = expected_exp + 20
		var lost: Dictionary = Bridge.settle(get_tree(), String(retry["token"]), &"lose", retry_chapter)
		_check(bool(lost.get("ok", false)), "失败结算回退成功")
		var rolled_back: Dictionary = _session.get_profile()
		_check(int(rolled_back["gold"]) == 200, "失败不发奖")
		_check(int(rolled_back["roster"][0]["exp"]) == expected_exp, "失败不保留本次经验")
	await _check_ui_roundtrip()
	_finish()


func _check_ui_roundtrip() -> void:
	# 探针留在 root，允许真实 Campaign → Battle → Campaign 切换整个 current_scene。
	_session.clear_last_result()
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/Campaign.tscn")
	var campaign: Node = await _await_scene("res://scenes/Campaign.tscn")
	if campaign == null:
		return
	_check(_press(campaign, "MapBtn"), "营地按钮打开世界地图")
	await get_tree().process_frame
	_check(_press(campaign, "ChallengeBtn_0"), "地图按钮打开出征确认")
	await get_tree().process_frame
	_check(_press(campaign, "Action_go"), "确认出征调用真实战斗桥接")
	var battle: Node = await _await_scene("res://scenes/Battle.tscn")
	if battle == null:
		return
	_check(not String(battle.get("_campaign_token")).is_empty(), "跨场景出征携带冒险令牌")
	for enemy: Dictionary in battle.get("chapter")["enemyUnits"]:
		enemy["hp"] = 0
		enemy["isDead"] = true
		battle.get("grid").remove_unit(enemy)
	battle.call("_check_battle_end")
	campaign = await _await_scene("res://scenes/Campaign.tscn")
	if campaign == null:
		return
	_check((campaign.find_child("Hub", true, false) as Control).visible, "真实结算自动返回营地")
	_check(int((_session.get_profile() as Dictionary)["gold"]) == 250, "真实重复挑战仅奖励50金币")
	_check((campaign.find_child("GoldValue", true, false) as Label).text.contains("250"), "营地显示最新金币")
	var modal: Node = campaign.find_child("CampaignModal", true, false)
	_check(modal != null, "返回营地显示本次结算")


func _press(scope: Node, node_name: String) -> bool:
	var button := scope.find_child(node_name, true, false) as Button
	if button == null or button.disabled:
		return false
	button.pressed.emit()
	return true


func _await_scene(path: String) -> Node:
	for frame in range(600):
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path == path:
			# 等待 _ready 的布局与异步战场初始化完毕。
			for settle_frame in range(5):
				await get_tree().process_frame
			_check(true, "切换场景 " + path.get_file())
			return scene
	_check(false, "切换场景超时 " + path)
	return null


func _finish() -> void:
	SceneArgs.battle_args = {}
	Settings.set_battle_immersive_presentation(_old_presentation)
	if not _profile_id.is_empty():
		_session.delete_profile(_profile_id)
		_session.leave_profile()
	passed = not checks.is_empty()
	for check in checks:
		passed = passed and bool(check["passed"])
	finished = true
	print("CAMPAIGN_BATTLE_INTEGRATION ", "PASS" if passed else "FAIL", " checks=", checks.size())
