## campaign_battle_integration_contract.gd — 真实战场结算接回冒险的运行态探针。
## MCP 启动同名 tscn，断言 finished/passed，再检查 error 日志。
## 三阶段：①首战真结算（含升级差分）②失败回退 ③真实 Campaign↔Battle 往返。
## 终态：第三局带升级的真实胜仗重进 Campaign，Hub 弹真实 level_ups 收据弹窗。
## 运行态观察：hold_result_view=true 时 _finish 保留档案与弹窗，配合
## result_modal_text()/close_result_modal()/cleanup_now() 供两档分辨率人工断言。
extends Node2D

const BattleScene = preload("res://scenes/Battle.tscn")
const Bridge = preload("res://scripts/battle/campaign_battle_bridge.gd")

var finished := false
var passed := false
var checks: Array[Dictionary] = []
var _session: Node
var _profile_id := ""
var _old_presentation := false
## true = 终态保留结算弹窗与档案（运行态观察用，默认 false 走自动清理）。
var hold_result_view := false


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
	# 模拟战斗内升级：等级 +1、力 +1，验证真实结算回执的升级差分。
	var expected_level := int(actor["level"]) + 1
	actor["level"] = expected_level
	actor["stats"]["str"] = int(actor["stats"].get("str", 0)) + 1
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
	var receipt_ups: Array = battle._campaign_receipt.get("level_ups", [])
	_check(
		receipt_ups.size() == 1
			and String(receipt_ups[0].get("id", "")) == "r_0"
			and int(receipt_ups[0].get("from_level", -1)) == expected_level - 1
			and int(receipt_ups[0].get("to_level", -1)) == expected_level,
		"真实结算回执带升级差分 r_0"
	)
	if receipt_ups.size() == 1:
		_check(int(receipt_ups[0].get("stat_deltas", {}).get("str", 0)) == 1, "升级差分含 str+1")
	var after: Dictionary = _session.get_profile()
	_check(int(after["gold"]) == 200, "首胜奖励200金币")
	_check((after["completed_levels"] as Array).size() == 1, "记录首关通关")
	_check(int(after["roster"][0]["exp"]) == expected_exp, "保留战斗实际经验")
	_check(int(after["roster"][0]["level"]) == expected_level, "档案保留战斗内升级")
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
		_check(not lost.has("level_ups"), "失败回执不带 level_ups")
		var rolled_back: Dictionary = _session.get_profile()
		_check(int(rolled_back["gold"]) == 200, "失败不发奖")
		_check(int(rolled_back["roster"][0]["exp"]) == expected_exp, "失败不保留本次经验")
		_check(int(rolled_back["roster"][0]["level"]) == expected_level, "失败回退后档案等级保持")
	await _check_ui_roundtrip()
	await _check_upgrade_modal_view()
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
	var modal_message: Label = null
	if modal != null:
		modal_message = modal.find_child("ModalMessage", true, false) as Label
	_check(
		modal_message != null and modal_message.text.find("获得金币：50") >= 0,
		"结算弹窗显示重复通关奖励"
	)
	_check(
		modal_message == null or modal_message.text.find("升级：") < 0,
		"未升级的重复通关结算不显示升级行"
	)


## 第三阶段：真实升级收据的营地回显（运行态可观察终态）。再打一场带升级
## 的真实胜仗（Bridge 结算，receipt 带 level_ups），重载 Campaign 让 Hub 弹出
## 真实升级收据弹窗；测试不按「继续」，弹窗留在屏上供运行态断言/截图。
## 此时本探针已不是 current_scene（roundtrip 前已摘除），直接切场景安全。
func _check_upgrade_modal_view() -> void:
	var levels: Array = _session.list_levels()
	var prepared: Dictionary = _session.prepare_battle(String(levels[0]["id"]))
	if not bool(prepared.get("ok", false)):
		_check(false, "升级展示局可以出征")
		return
	var chapter: Dictionary = prepared["chapter"]
	var units: Array = chapter["playerUnits"]
	var from_level := int(units[0]["level"])
	units[0]["level"] = from_level + 1
	units[0]["exp"] = int(units[0]["exp"]) + 15
	units[0]["stats"]["str"] = int(units[0]["stats"].get("str", 0)) + 1
	var receipt: Dictionary = Bridge.settle(get_tree(), String(prepared["token"]), &"win", chapter)
	_check(bool(receipt.get("ok", false)), "升级展示局结算成功")
	_check((receipt.get("level_ups", []) as Array).size() == 1, "升级展示局带升级差分")
	# 先显式释放旧 Campaign 再把 current_scene 置空：_await_scene 按
	# scene_file_path 轮询，若 current 仍是旧 Campaign 会首帧误匹配。
	var old_campaign := get_tree().current_scene
	get_tree().current_scene = null
	if old_campaign != null:
		old_campaign.queue_free()
	get_tree().change_scene_to_file("res://scenes/Campaign.tscn")
	var campaign: Node = await _await_scene("res://scenes/Campaign.tscn")
	if campaign == null:
		return
	var modal: Node = campaign.find_child("CampaignModal", true, false)
	_check(modal != null, "升级展示局营地弹出结算")
	var message: Label = null
	if modal != null:
		message = modal.find_child("ModalMessage", true, false) as Label
	_check(
		message != null and message.text.find("升级：") >= 0
			and message.text.find("%d→%d" % [from_level, from_level + 1]) >= 0,
		"真实升级收据弹窗含升级行（%d→%d）" % [from_level, from_level + 1]
	)
	_check(message != null and message.text.find("力+1") >= 0, "真实升级行含力+1")
	var row: Button = campaign.find_child("UnitRow_0", true, false) as Button
	_check(row != null and row.text.find("EXP ") >= 0, "营地队伍行显示真实 EXP")


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
	if not hold_result_view:
		cleanup_now()
	passed = not checks.is_empty()
	for check in checks:
		passed = passed and bool(check["passed"])
	finished = true
	print("CAMPAIGN_BATTLE_INTEGRATION ", "PASS" if passed else "FAIL", " checks=", checks.size())


# ============================================================
# 运行态观察入口（Lead 用；默认自动流程不调用，仅测试侧，不涉产品代码）
# ============================================================

## 删除隔离测试档案并卸载会话（hold_result_view=true 时 _finish 跳过，
## 观察结束后由本方法显式清理；重复调用安全）。
func cleanup_now() -> void:
	if _profile_id.is_empty() or _session == null:
		return
	_session.delete_profile(_profile_id)
	_session.leave_profile()
	_profile_id = ""


## 当前结算弹窗正文（无 Campaign/无弹窗返回空串）。
func result_modal_text() -> String:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != "res://scenes/Campaign.tscn":
		return ""
	var modal: Node = scene.find_child("CampaignModal", true, false)
	if modal == null:
		return ""
	var message := modal.find_child("ModalMessage", true, false) as Label
	return "" if message == null else message.text


## 按下弹窗「继续」关闭结算弹窗（返回是否成功）；关闭后营地队伍行可见，
## 可断言 UnitRow 的 EXP 文案。
func close_result_modal() -> bool:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != "res://scenes/Campaign.tscn":
		return false
	var modal: Node = scene.find_child("CampaignModal", true, false)
	if modal == null:
		return false
	var button := modal.find_child("Action_continue", true, false) as Button
	if button == null:
		return false
	button.pressed.emit()
	return true
