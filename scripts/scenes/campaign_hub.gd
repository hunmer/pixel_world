## scripts/scenes/campaign_hub.gd — 冒险 Hub 屏（只读四数据 + 保存/出征入口）
##
## 四数据：金币、随身物品、角色队伍、关卡进度。胜利/失败/撤退后回到本屏
## 时用 get_last_result 弹一次结算（并 clear_last_result，防重复入账展示）；
## 胜利文案含 level_ups 升级行，角色行 unit_label 带 EXP 当前/阈值。
## 所有按钮走 UIFactory + PixelButton 语义变体；布局只用六薄容器。
extends Control

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const PixelPanelScene = preload("res://ui/components/pixel_panel.tscn")
const PixelProgressBarScript = preload("res://ui/components/pixel_progress_bar.gd")
const PixelMarginScript = preload("res://ui/components/pixel_margin.gd")
const PixelVBoxScript = preload("res://ui/components/pixel_v_box.gd")
const PixelHBoxScript = preload("res://ui/components/pixel_h_box.gd")
const PixelScrollScript = preload("res://ui/components/pixel_scroll.gd")
const CampaignFormatScript = preload("res://scripts/scenes/campaign_format.gd")

var _main: Control
var _profile_title: Label
var _gold_label: Label
var _gold_value: Label
var _progress_label: Label
var _progress_fill: Range
var _roster_list: VBoxContainer
var _inventory_list: VBoxContainer
var _save_btn: Button
var _map_btn: Button
var _switch_btn: Button
var _gold_caption: Label


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

	_profile_title = UIFactoryScript.label(
		"", ComponentThemeScript.FONT_TITLE, UIThemeScript.TEXT_MAIN
	)
	_profile_title.name = "ProfileTitle"
	_profile_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_profile_title)

	_gold_label = UIFactoryScript.label(
		"", ComponentThemeScript.FONT_BODY, UIThemeScript.TOAST_COLOR
	)
	_gold_label.name = "GoldLabel"
	_gold_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_gold_label)

	var columns := PixelHBoxScript.new()
	columns.name = "DataColumns"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(columns)

	# 左列：角色队伍 + 随身物品（可滚动，条目多时不塌陷）。
	var left := PixelVBoxScript.new()
	left.name = "LeftColumn"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)

	left.add_child(_make_section_header("角色队伍", "RosterHeader"))
	var roster_panel: PanelContainer = PixelPanelScene.instantiate() as PanelContainer
	roster_panel.name = "RosterPanel"
	roster_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_panel.set("title", "跨关队伍")
	left.add_child(roster_panel)
	var roster_scroll := PixelScrollScript.new()
	roster_scroll.name = "RosterScroll"
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_panel.call("get_content_slot").add_child(roster_scroll)
	_roster_list = PixelVBoxScript.new()
	_roster_list.name = "RosterList"
	roster_scroll.add_child(_roster_list)

	left.add_child(_make_section_header("随身物品", "InventoryHeader"))
	var inventory_panel: PanelContainer = PixelPanelScene.instantiate() as PanelContainer
	inventory_panel.name = "InventoryPanel"
	inventory_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_panel.set("title", "公共库存 · 自动发放")
	left.add_child(inventory_panel)
	var inventory_scroll := PixelScrollScript.new()
	inventory_scroll.name = "InventoryScroll"
	inventory_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_panel.call("get_content_slot").add_child(inventory_scroll)
	_inventory_list = PixelVBoxScript.new()
	_inventory_list.name = "InventoryList"
	inventory_scroll.add_child(_inventory_list)

	# 右列：金币卡 + 关卡进度卡（PixelProgressBar 直 preload，仅按钮被禁）。
	var right := PixelVBoxScript.new()
	right.name = "RightColumn"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)

	var gold_panel: PanelContainer = PixelPanelScene.instantiate() as PanelContainer
	gold_panel.name = "GoldPanel"
	gold_panel.set("title", "金币")
	right.add_child(gold_panel)
	var gold_slot: Container = gold_panel.call("get_content_slot") as Container
	_gold_value = UIFactoryScript.label(
		"", ComponentThemeScript.FONT_TITLE, UIThemeScript.TOAST_COLOR
	)
	_gold_value.name = "GoldValue"
	gold_slot.add_child(_gold_value)
	_gold_caption = UIFactoryScript.label(
		"", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM
	)
	_gold_caption.name = "GoldCaption"
	gold_slot.add_child(_gold_caption)

	var progress_panel: PanelContainer = PixelPanelScene.instantiate() as PanelContainer
	progress_panel.name = "ProgressPanel"
	progress_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	progress_panel.set("title", "关卡进度")
	right.add_child(progress_panel)
	var progress_slot: Container = progress_panel.call("get_content_slot") as Container
	var progress_body := PixelVBoxScript.new()
	progress_slot.add_child(progress_body)
	_progress_label = UIFactoryScript.label(
		"", ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN
	)
	_progress_label.name = "ProgressLabel"
	progress_body.add_child(_progress_label)
	_progress_fill = PixelProgressBarScript.new() as Range
	_progress_fill.name = "ProgressFill"
	_progress_fill.custom_minimum_size = Vector2(
		ComponentThemeScript.SPACE_LG * 10, ComponentThemeScript.SPACE_SM * 2
	)
	_progress_fill.set("show_percentage", false)
	progress_body.add_child(_progress_fill)

	var footer := PixelHBoxScript.new()
	footer.name = "FooterRow"
	box.add_child(footer)

	_save_btn = _make_action_button("立即保存", 0, _on_save_now)
	_save_btn.name = "SaveNowBtn"
	footer.add_child(_save_btn)

	_map_btn = _make_action_button("世界地图", 0, _on_open_map)
	_map_btn.name = "MapBtn"
	footer.add_child(_map_btn)

	_switch_btn = _make_action_button("切换存档", 1, _on_switch_profile)
	_switch_btn.name = "SwitchProfileBtn"
	footer.add_child(_switch_btn)

	var hint: Label = UIFactoryScript.label(
		"ESC：世界地图中返回基地 / 基地中回到存档选择",
		ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM
	)
	hint.name = "EscHint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)


func _make_section_header(text: String, node_name: String) -> Label:
	var label: Label = UIFactoryScript.label(
		text, ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN
	)
	label.name = node_name
	return label


func _make_action_button(text: String, semantic: int, handler: Callable) -> Button:
	var button: Button = UIFactoryScript.button(text, Callable(), "", false)
	button.set("semantic", clampi(semantic, 0, 2))
	button.pressed.connect(handler)
	return button


func on_shown() -> void:
	refresh()
	if not bool(_main.call("modal_open")) and CampaignFormatScript.can_grab_focus(_save_btn):
		_save_btn.grab_focus()
	_present_last_result()


func on_data_changed() -> void:
	if visible:
		refresh()


func refresh() -> void:
	var session: Node = _main.call("session")
	var profile: Dictionary = CampaignFormatScript.call_raw_dict(session, "get_profile")
	if profile.is_empty():
		_main.call("go_save_select")
		return
	_profile_title.text = CampaignFormatScript.profile_name(profile)
	var gold := CampaignFormatScript.as_int(profile.get("gold", 0), 0)
	_gold_label.text = "金币 %d" % gold
	_gold_value.text = "%d" % gold
	var levels: Array = CampaignFormatScript.call_array(session, "list_levels")
	_fill_roster(profile.get("roster", []))
	_fill_inventory(profile.get("inventory", []))
	_fill_progress(profile, levels)
	_update_gold_caption(levels)


func _fill_roster(roster: Variant) -> void:
	CampaignFormatScript.detach_children(_roster_list)
	var units: Array = roster if roster is Array else []
	var index := 0
	for entry: Variant in units:
		var unit: Dictionary = entry if entry is Dictionary else {}
		var row := _make_detail_button(CampaignFormatScript.unit_label(unit), unit)
		row.name = "UnitRow_%d" % index
		_roster_list.add_child(row)
		index += 1
	if units.is_empty():
		_roster_list.add_child(_make_empty_label("（暂无角色：首次出征后队伍将固定）", "RosterEmpty"))


func _fill_inventory(inventory: Variant) -> void:
	CampaignFormatScript.detach_children(_inventory_list)
	var items: Array = inventory if inventory is Array else []
	var index := 0
	for entry: Variant in items:
		var item: Dictionary = entry if entry is Dictionary else {}
		var row := _make_detail_button(CampaignFormatScript.item_label(item), item)
		row.name = "ItemRow_%d" % index
		_inventory_list.add_child(row)
		index += 1
	if items.is_empty():
		_inventory_list.add_child(_make_empty_label("（暂无物品：首胜奖励将自动发放）", "InventoryEmpty"))


func _make_empty_label(text: String, node_name: String) -> Label:
	var label: Label = UIFactoryScript.label(
		text, ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_DIM
	)
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _make_detail_button(text: String, data: Dictionary) -> Button:
	var button: Button = UIFactoryScript.button(text, Callable(), "", false)
	button.set("semantic", 1)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_show_detail.bind(text, data))
	return button


func _fill_progress(profile: Dictionary, levels: Array) -> void:
	var total := levels.size()
	var completed_ids: Array = profile.get("completed_levels", []) if profile.get("completed_levels", []) is Array else []
	_progress_label.text = "已通关 %d / %d" % [completed_ids.size(), total]
	_progress_fill.max_value = maxf(1.0, float(total))
	_progress_fill.value = float(completed_ids.size())


## 金币说明从关卡数据算（不硬编码数值）；无数据时退化为引导文案。
func _update_gold_caption(levels: Array) -> void:
	if levels.is_empty():
		_gold_caption.text = "首胜/重复奖励见世界地图"
		return
	var first: Dictionary = levels[0] if levels[0] is Dictionary else {}
	var first_gold := CampaignFormatScript.as_int(first.get("reward_gold", 0), 0)
	var repeat_gold := CampaignFormatScript.as_int(first.get("reward_gold_repeat", 0), 0)
	_gold_caption.text = "首胜 %d · 重复通关 %d" % [first_gold, repeat_gold]


## 回基地时展示一次上次战斗结算（win/lose/abandon），随后清空防重复。
func _present_last_result() -> void:
	var session: Node = _main.call("session")
	var result: Dictionary = CampaignFormatScript.call_raw_dict(session, "get_last_result")
	if result.is_empty():
		return
	var outcome := CampaignFormatScript.as_text(result.get("result", ""), "")
	var level_name := CampaignFormatScript.as_text(result.get("level_name", ""), "上一场战斗")
	var title := ""
	var lines: Array[String] = ["关卡：%s" % level_name]
	match outcome:
		"win":
			title = "胜利！"
			var gold := CampaignFormatScript.as_int(result.get("gold", 0), 0)
			lines.append("获得金币：%d" % gold)
			var items_line := CampaignFormatScript.items_line(result.get("items", []))
			lines.append("获得物品：%s" % items_line)
			if bool(result.get("first_clear", false)):
				lines.append("首次通关！")
			for line: String in CampaignFormatScript.level_up_lines(result.get("level_ups", [])):
				lines.append(line)
		"lose":
			title = "战败"
			lines.append("未发放奖励，队伍恢复出征前状态。")
		"abandon":
			title = "已撤退"
			lines.append("未发放奖励，队伍恢复出征前状态。")
		_:
			title = "战斗结束"
			lines.append("结果未识别（%s），奖励以存档数据为准。" % outcome)
	var modal: Control = _main.call(
		"open_modal",
		title,
		"\n".join(lines),
		[{"text": "继续", "semantic": 0, "id": "continue", "focus": true}]
	)
	modal.connect("chosen", Callable(self, "_on_result_closed"))
	CampaignFormatScript.call_void(session, "clear_last_result")


func _on_result_closed(_action_id: String) -> void:
	refresh()


func _on_save_now() -> void:
	var session: Node = _main.call("session")
	var result: Dictionary = CampaignFormatScript.call_dict(session, "save_current")
	if bool(result.get("ok", false)):
		_main.call(
			"open_modal",
			"已保存",
			"当前冒险进度已写入磁盘。",
			[{"text": "关闭", "semantic": 0, "id": "close", "focus": true}]
		)
	else:
		_main.call(
			"open_error",
			"保存失败",
			"%s\n进度仍保留在内存中，可重试「立即保存」。" % CampaignFormatScript.as_text(result.get("error", ""), "未知错误")
		)


func _on_open_map() -> void:
	_main.call("go_levels")


func _on_switch_profile() -> void:
	var session: Node = _main.call("session")
	CampaignFormatScript.call_void(session, "leave_profile")
	_main.call("go_save_select")


func _on_show_detail(title: String, data: Dictionary) -> void:
	var body: String = CampaignFormatScript.detail_lines(data)
	if body == "":
		body = "（无更多信息）"
	_main.call(
		"open_modal",
		title,
		body,
		[{"text": "关闭", "semantic": 0, "id": "close", "focus": true}]
	)
