## campaign_battle_bridge.gd — 冒险出征与战场场景路由；不读写旧逐战场存档。
extends RefCounted

const HUB_SCENE := "res://scenes/Campaign.tscn"
const BATTLE_SCENE := "res://scenes/Battle.tscn"


static func enter_battle(tree: SceneTree, level_id: String) -> Dictionary:
	var session: Node = tree.root.get_node_or_null("CampaignSession")
	var args: Node = tree.root.get_node_or_null("SceneArgs")
	if session == null or args == null:
		return {"ok": false, "error": "冒险服务尚未就绪。"}
	var prepared: Dictionary = session.prepare_battle(level_id)
	if not bool(prepared.get("ok", false)):
		return prepared
	args.battle_args = {
		"chapter": prepared["chapter"],
		"return_to": HUB_SCENE,
		"campaign_token": String(prepared["token"]),
		"campaign_level_id": level_id,
		"save_identity": "",
		# 档案难度档：battle 侧优先于全局设置注入敌方 AI
		"difficulty": String(prepared.get("difficulty", "normal")),
	}
	var err: Error = tree.change_scene_to_file(BATTLE_SCENE)
	if err != OK:
		session.settle_battle(String(prepared["token"]), &"abandon", prepared["chapter"])
		args.battle_args = {}
		return {"ok": false, "error": "无法打开战场（%d）。" % err}
	print("[campaign] enter level=%s token=%s" % [level_id, String(prepared["token"])])
	return {"ok": true}


static func settle(tree: SceneTree, token: String, result: StringName, chapter: Dictionary) -> Dictionary:
	var session: Node = tree.root.get_node_or_null("CampaignSession")
	if session == null:
		return {"ok": false, "error": "冒险服务不可用，请重试保存。"}
	return session.settle_battle(token, result, chapter)
