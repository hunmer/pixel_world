extends SceneTree

const GameHudScript = preload("res://scripts/game_hud.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _assert_mouse_passthrough(node: Node) -> void:
	if node is Control:
		_expect(
			(node as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"HUD 控件拦截了游戏输入: " + str(node.get_path())
		)
	for child in node.get_children():
		_assert_mouse_passthrough(child)


func _run() -> void:
	var hud = GameHudScript.new()
	root.add_child(hud)
	await process_frame
	var top_area := hud.get_node("HUDRoot/TopArea") as VBoxContainer
	var help_flow := hud.get_node(
		"HUDRoot/TopArea/HelpPanel/HelpFlow"
	) as HFlowContainer
	_expect(top_area != null, "HUD 缺少顶部安全区")
	_expect(help_flow != null, "HUD 操作提示没有使用响应式 FlowContainer")
	_expect(
		hud.get_node_or_null("HUDRoot/TopArea/StatusPanel") == null,
		"HUD 不应继续显示世界、天气或景深状态栏"
	)
	if top_area != null:
		_expect(top_area.anchor_right == 1.0, "HUD 顶部没有随视口宽度伸展")
		_expect(top_area.offset_right <= -140.0, "HUD 没有为右上角小地图预留空间")
	_expect(help_flow.get_child_count() >= 11, "HUD 快捷键提示不完整")
	var has_map_hint := false
	for child in help_flow.get_children():
		var key_label := child.get_node_or_null("Keycap/Key")
		var action_label := child.get_node_or_null("Action")
		if key_label != null and action_label != null:
			if key_label.text == "M" and action_label.text == "地图":
				has_map_hint = true
	_expect(has_map_hint, "HUD 缺少 M 地图提示")
	_assert_mouse_passthrough(hud)
	hud.queue_free()
	await process_frame
	if failures.is_empty():
		print("GAME_HUD_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
