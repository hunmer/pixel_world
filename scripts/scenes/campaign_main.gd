## scripts/scenes/campaign_main.gd — 冒险入口装配层
##
## Campaign.tscn 的根脚本：装配四屏（存档选择 / 基地 Hub / 关卡列表 /
## 营地商店）与模态层，路由屏间切换，向 CampaignSession 转发 changed 事件
## （事件驱动，不轮询）。出征经 battle_requested 信号 +
## campaign_battle_bridge（直接 preload）跳转 Battle.tscn。
extends Control

signal battle_requested(level_id: String)

const SaveSelectScript = preload("res://scripts/scenes/campaign_save_select.gd")
const HubScript = preload("res://scripts/scenes/campaign_hub.gd")
const LevelsScript = preload("res://scripts/scenes/campaign_levels.gd")
const ShopScript = preload("res://scripts/scenes/campaign_shop.gd")
const ModalScript = preload("res://scripts/scenes/campaign_modal.gd")
const CampaignFormatScript = preload("res://scripts/scenes/campaign_format.gd")
## 战斗桥接已落盘：直接 preload（缺失会在加载期暴露，而非运行期兜底）。
const BattleBridgeScript = preload("res://scripts/battle/campaign_battle_bridge.gd")

var _screens: Control
var _modal_layer: Control
var _save_select: Control
var _hub: Control
var _levels: Control
var _shop: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screens = Control.new()
	_screens.name = "Screens"
	_screens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screens)

	_save_select = SaveSelectScript.new()
	_save_select.name = "SaveSelect"
	_save_select.call("setup", self)
	_screens.add_child(_save_select)

	_hub = HubScript.new()
	_hub.name = "Hub"
	_hub.call("setup", self)
	_screens.add_child(_hub)

	_levels = LevelsScript.new()
	_levels.name = "Levels"
	_levels.call("setup", self)
	_screens.add_child(_levels)

	_shop = ShopScript.new()
	_shop.name = "Shop"
	_shop.call("setup", self)
	_screens.add_child(_shop)

	_modal_layer = Control.new()
	_modal_layer.name = "ModalLayer"
	_modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_layer)

	var sess := session()
	if sess != null and sess.has_signal("changed"):
		sess.connect("changed", Callable(self, "_on_session_changed"))
	# 战斗返回时场景整体重载：会话里仍有已加载档则直接回基地，否则进档列表。
	if not CampaignFormatScript.call_raw_dict(sess, "get_profile").is_empty():
		go_hub()
	else:
		go_save_select()


func session() -> Node:
	return get_tree().root.get_node_or_null("CampaignSession")


func go_save_select() -> void:
	_switch_screen(_save_select)


func go_hub() -> void:
	_switch_screen(_hub)


func go_levels() -> void:
	_switch_screen(_levels)


func go_shop() -> void:
	_switch_screen(_shop)


func _switch_screen(screen: Control) -> void:
	for child: Node in _screens.get_children():
		child.visible = false
	screen.visible = true
	if screen.has_method("on_shown"):
		screen.call("on_shown")


## 模态层是否有弹窗打开（屏 on_shown 抓焦前检查，避免对已被陷阱禁用
## 焦点的背景控件重复抓焦）。
func modal_open() -> bool:
	return _modal_layer.get_child_count() > 0


func _on_session_changed(_reason: String = "") -> void:
	for child: Node in _screens.get_children():
		if child.visible and child.has_method("on_data_changed"):
			child.call("on_data_changed")
			return


## 通用模态入口；返回弹层控件（可继续 connect("chosen")）。scope 为 Screens，
## 打开期间背景层焦点全部禁用（焦点陷阱），关闭自动恢复。
func open_modal(
	title: String,
	message: String,
	actions: Array,
	want_input: bool = false,
	input_placeholder: String = "",
	input_default: String = "",
	cancelable: bool = true
) -> Control:
	var modal: Control = ModalScript.new()
	modal.call(
		"build", title, message, actions, _screens, want_input, input_placeholder, input_default, cancelable
	)
	_modal_layer.add_child(modal)
	modal.call("open")
	return modal


func open_error(title: String, message: String) -> Control:
	return open_modal(
		title,
		message,
		[{"text": "关闭", "semantic": 0, "id": "close", "focus": true}]
	)


## 出征：发信号（测试/外部可监听），再走战斗桥接（static）进入 Battle.tscn。
func request_battle(level_id: String) -> void:
	battle_requested.emit(level_id)
	var result: Variant = BattleBridgeScript.enter_battle(get_tree(), level_id)
	if not (result is Dictionary) or not bool((result as Dictionary).get("ok", false)):
		var detail := CampaignFormatScript.as_text(
			(result as Dictionary).get("error", "") if result is Dictionary else "",
			"未知错误"
		)
		open_error(
			"进入战斗失败",
			"%s\n本次未消耗出征状态，可重试或返回基地。" % detail
		)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _modal_layer.get_child_count() > 0:
		return  # 弹层自行处理 ESC（关闭弹层而非切屏）。
	if _shop.visible:
		get_viewport().set_input_as_handled()
		go_hub()
	elif _levels.visible:
		get_viewport().set_input_as_handled()
		go_hub()
	elif _hub.visible:
		get_viewport().set_input_as_handled()
		CampaignFormatScript.call_void(session(), "leave_profile")
		go_save_select()
