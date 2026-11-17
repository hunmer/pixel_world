## scripts/scenes/campaign_shop.gd — 营地商店屏（金币购买补给）
##
## 经 CampaignSession.list_shop()/buy_item(id, count) 交易：接口未落地时
## call_dict 兜底成可读错误明示（W2 后自动接通）。每次购买 1 件，先经
## 单层确认弹窗（防重：确认/结算期间入口禁用）再请求结算；成功依赖
## changed 信号自动刷新金币/库存（本屏 refresh 兜底）；失败在页面明示。
## remaining=-1 / max_buyable<0 视为不限购；余额不足/售罄按钮禁用。
## 布局只用六薄容器，按钮一律 UIFactory PixelButton（禁裸 Button）。
extends Control

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const PixelMarginScript = preload("res://ui/components/pixel_margin.gd")
const PixelVBoxScript = preload("res://ui/components/pixel_v_box.gd")
const PixelHBoxScript = preload("res://ui/components/pixel_h_box.gd")
const PixelScrollScript = preload("res://ui/components/pixel_scroll.gd")
const CampaignFormatScript = preload("res://scripts/scenes/campaign_format.gd")

var _main: Control
var _notice: Label
var _gold_label: Label
var _list: VBoxContainer
var _back_btn: Button
var _first_buy_btn: Button
## id → 购买按钮（每次重建列表刷新）：购买成功后焦点恢复用。
var _buy_btn_by_id: Dictionary = {}
var _stock: Array = []
var _gold: int = 0
## 正在确认/结算中的商品 id（""=空闲）：防确认弹窗叠加与重复提交。
var _purchasing: String = ""


func setup(main_ref: Control) -> void:
	_main = main_ref


func _ready() -> void:
	_build()
	visible = false


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var page := PixelMarginScript.new()
	page.name = "PageMargin"
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)

	var box := PixelVBoxScript.new()
	box.name = "PageBox"
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(box)

	var header := PixelHBoxScript.new()
	header.name = "HeaderRow"
	box.add_child(header)

	_back_btn = _make_action_button("← 返回基地", 1, _on_back)
	_back_btn.name = "BackBtn"
	header.add_child(_back_btn)

	var title: Label = UIFactoryScript.label(
		"营地商店", ComponentThemeScript.FONT_TITLE, UIThemeScript.TEXT_MAIN
	)
	title.name = "PageTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)

	_gold_label = UIFactoryScript.label(
		"", ComponentThemeScript.FONT_BODY, UIThemeScript.TOAST_COLOR
	)
	_gold_label.name = "GoldLabel"
	_gold_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_gold_label)

	var caption: Label = UIFactoryScript.label(
		"用金币购买补给。限购额度按通关周期刷新：每新通关一关额度重置。",
		ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM
	)
	caption.name = "PageCaption"
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(caption)

	_notice = UIFactoryScript.label("", ComponentThemeScript.FONT_BODY, UIThemeScript.ERROR)
	_notice.name = "ShopNotice"
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.visible = false
	box.add_child(_notice)

	var scroll := PixelScrollScript.new()
	scroll.name = "ShopScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)

	_list = PixelVBoxScript.new()
	_list.name = "ShopList"
	scroll.add_child(_list)


func _make_action_button(text: String, semantic: int, handler: Callable) -> Button:
	var button: Button = UIFactoryScript.button(text, Callable(), "", false)
	button.set("semantic", clampi(semantic, 0, 2))
	button.pressed.connect(handler)
	return button


func on_shown() -> void:
	refresh()
	if not bool(_main.call("modal_open")):
		if CampaignFormatScript.can_grab_focus(_first_buy_btn):
			_first_buy_btn.grab_focus()
		elif CampaignFormatScript.can_grab_focus(_back_btn):
			_back_btn.grab_focus()


func on_data_changed() -> void:
	if visible:
		refresh()


func refresh() -> void:
	var session: Node = _main.call("session")
	var result: Dictionary = CampaignFormatScript.call_dict(session, "list_shop")
	if not bool(result.get("ok", false)):
		_stock = []
		_gold = 0
		_gold_label.text = ""
		_notice.text = CampaignFormatScript.as_text(result.get("error", ""), "商店服务不可用。")
		_notice.visible = true
		_rebuild_list()
		return
	_notice.visible = false
	_gold = CampaignFormatScript.as_int(result.get("gold", 0), 0)
	_gold_label.text = "金币 %d" % _gold
	var stock: Variant = result.get("stock", [])
	_stock = stock if stock is Array else []
	_rebuild_list()


func _rebuild_list() -> void:
	_first_buy_btn = null
	_buy_btn_by_id = {}
	CampaignFormatScript.detach_children(_list)
	var index := 0
	for entry: Variant in _stock:
		var item: Dictionary = entry if entry is Dictionary else {}
		_list.add_child(_make_item_row(item, index))
		index += 1
	if _stock.is_empty() and not _notice.visible:
		var empty := UIFactoryScript.label(
			"货架为空。", ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_DIM
		)
		empty.name = "ShopEmpty"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)


func _make_item_row(item: Dictionary, index: int) -> Container:
	var id := CampaignFormatScript.as_text(item.get("id", ""), "item_%d" % index)
	var display_name := CampaignFormatScript.as_text(item.get("name", ""), id)
	var price := CampaignFormatScript.as_int(item.get("price", 0), 0)
	var remaining := CampaignFormatScript.as_int(item.get("remaining", -1), -1)
	var max_buyable := CampaignFormatScript.as_int(item.get("max_buyable", 0), 0)

	var row := PixelHBoxScript.new()
	row.name = "ItemRow_%d" % index

	var info := PixelVBoxScript.new()
	info.name = "ItemInfo_%d" % index
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var name_label: Label = UIFactoryScript.label(
		display_name, ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN
	)
	name_label.name = "ItemName_%d" % index
	info.add_child(name_label)

	var limit_text := "不限购" if remaining < 0 else "本周期剩 %d" % remaining
	var meta: Label = UIFactoryScript.label(
		"%d 金币 · %s" % [price, limit_text],
		ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM
	)
	meta.name = "ItemMeta_%d" % index
	info.add_child(meta)

	var buy_btn := _make_action_button("购买", 0, _on_buy.bind(id, display_name, price))
	buy_btn.name = "BuyBtn_%d" % index
	var unlimited := remaining < 0 or max_buyable < 0
	buy_btn.disabled = _purchasing != "" or price > _gold or (not unlimited and max_buyable <= 0)
	if _first_buy_btn == null and not buy_btn.disabled:
		_first_buy_btn = buy_btn
	_buy_btn_by_id[id] = buy_btn
	row.add_child(buy_btn)
	return row


## 购买入口：防重（弹窗/结算期间忽略），单层确认弹窗复用 campaign_modal。
func _on_buy(id: String, display_name: String, price: int) -> void:
	if _purchasing != "":
		return
	_purchasing = id
	var modal: Control = _main.call(
		"open_modal",
		"购买确认",
		"购买 %s ×1，花费 %d 金币？\n当前金币 %d，购买后剩 %d。" % [
			display_name, price, _gold, _gold - price
		],
		[
			{"text": "购买", "semantic": 0, "id": "confirm", "focus": true},
			{"text": "取消", "semantic": 1, "id": "cancel"},
		]
	)
	modal.connect("chosen", Callable(self, "_on_buy_chosen").bind(id))


func _on_buy_chosen(action_id: String, id: String) -> void:
	if action_id != "confirm":
		_purchasing = ""
		return
	var session: Node = _main.call("session")
	var result: Dictionary = CampaignFormatScript.call_dict(session, "buy_item", [id, 1])
	_purchasing = ""
	if bool(result.get("ok", false)):
		refresh()
		_restore_focus_after_purchase(id)
	else:
		# 失败不动列表（金币/库存未变），错误原地明示；changed 若已触发会自动刷新。
		_notice.text = CampaignFormatScript.as_text(result.get("error", ""), "购买失败，请重试。")
		_notice.visible = true


## 确认弹窗 close 先把焦点还给发起按钮，随后 changed→refresh 重建列表会把
## 该按钮 detach（焦点悬空）。购买成功后在重建列表上重新抓焦：优先刚购买
## 的商品行（仍可买时），其次首个可购买行，最后返回按钮。
func _restore_focus_after_purchase(id: String) -> void:
	var target: Button = _buy_btn_by_id.get(id, null)
	if target == null or target.disabled:
		target = _first_buy_btn
	if target == null or target.disabled:
		target = _back_btn
	if CampaignFormatScript.can_grab_focus(target):
		target.grab_focus()


func _on_back() -> void:
	_main.call("go_hub")
