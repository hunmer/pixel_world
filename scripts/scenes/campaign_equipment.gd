## scripts/scenes/campaign_equipment.gd — 营地单位详情装备装卸弹层
##
## 从 Hub 角色行进入：展示单位概况、四槽（weapon/shield/staff/relic）当前
## 装备与合计加成、该职业可装备清单。装卸一律经 CampaignSession
## equip_item / unequip_item（原子落盘，出征挂起时拒绝）；成功靠 changed
## 事件驱动刷新（延迟一帧重建，避开按钮信号栈），失败原因写入面板内
## 错误行（拒绝信息可见，不再叠一层弹窗）。
## 焦点：打开时对背景层做与 campaign_modal 相同的确定性焦点陷阱，关闭
## 还原背景焦点模式并交还打开前焦点；装卸重建后把焦点交回最相关的
## 下一步按钮（装上→该槽卸下键，卸下→该件装备键，兜底关闭键）。
## 内容区装进 PixelScroll（仅纵滚），窄屏不横向溢出。
## 按钮一律 UIFactory（禁直预加载 pixel_button，全局 Sfx 发声）。
extends Control

signal closed

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const CampaignFormatScript = preload("res://scripts/scenes/campaign_format.gd")
const EquipmentDataScript = preload("res://scripts/core/equipment.gd")
const ProfessionDataScript = preload("res://scripts/core/professions.gd")
const PixelPanelScene = preload("res://ui/components/pixel_panel.tscn")
const PixelCenterScript = preload("res://ui/components/pixel_center.gd")
const PixelVBoxScript = preload("res://ui/components/pixel_v_box.gd")
const PixelHBoxScript = preload("res://ui/components/pixel_h_box.gd")
const PixelScrollScript = preload("res://ui/components/pixel_scroll.gd")

## 槽位显示名：数据槽位 id（EquipmentData.SLOTS）是契约，中文标签只在 UI 层。
const SLOT_LABELS := {
	"weapon": "武器",
	"shield": "盾牌",
	"staff": "法杖",
	"relic": "秘宝",
}

var _main: Control
var _scope: Control
var _roster_id := ""
var _previous_focus: Control
var _focus_disabled: Array = []
var _closing := false
var _summary: Label
var _error_label: Label
var _close_btn: Button
var _content: VBoxContainer
## 重建后希望交回焦点的控件名（装卸动作各自指回最相关的下一步）。
var _pending_focus_name := ""


## 构建弹层视觉树（加入场景树前调用）；scope_focus 同 open_modal（背景层）。
func build(roster_id: String, main_ref: Control, scope_focus: Control) -> void:
	_roster_id = roster_id
	_main = main_ref
	_scope = scope_focus
	name = "CampaignEquipment"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 整层拦截鼠标，屏蔽下方屏幕的点击（子内容在其上正常接收）。
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = UIThemeScript.BG
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var center := PixelCenterScript.new()
	center.name = "EquipCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel: PanelContainer = PixelPanelScene.instantiate() as PanelContainer
	panel.name = "EquipPanel"
	# 最小宽 360 = SPACE_LG(24) * 15（与 campaign_modal 同口径，DESIGN.md §7）。
	panel.custom_minimum_size = Vector2(ComponentThemeScript.SPACE_LG * 15, 0.0)
	var unit := _find_unit()
	panel.set("title", "装备 · %s" % _unit_title(unit))
	center.add_child(panel)

	var body := PixelVBoxScript.new()
	body.name = "EquipBody"
	(panel.call("get_content_slot") as Container).add_child(body)

	_summary = UIFactoryScript.label("", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM)
	_summary.name = "EquipSummary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_summary)

	# 内容区滚动：最小高 288 = SPACE_LG * 12，条目多时纵向滚动，窄屏不溢出。
	var scroll := PixelScrollScript.new()
	scroll.name = "EquipScroll"
	scroll.custom_minimum_size = Vector2(
		ComponentThemeScript.SPACE_LG * 13, ComponentThemeScript.SPACE_LG * 12
	)
	body.add_child(scroll)

	_content = PixelVBoxScript.new()
	_content.name = "EquipContent"
	scroll.add_child(_content)

	_error_label = UIFactoryScript.label("", ComponentThemeScript.FONT_CAPTION, UIThemeScript.ERROR)
	_error_label.name = "EquipError"
	_error_label.visible = false
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_error_label)

	var actions := PixelHBoxScript.new()
	actions.name = "EquipActions"
	actions.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(actions)

	_close_btn = UIFactoryScript.button("关闭", Callable(), "", false)
	_close_btn.set("semantic", 0)
	_close_btn.name = "EquipCloseBtn"
	_close_btn.pressed.connect(close)
	actions.add_child(_close_btn)


## 进入场景树后调用：启用焦点陷阱、抓默认焦点并订阅会话刷新。
func open() -> void:
	_previous_focus = get_viewport().gui_get_focus_owner()
	_focus_disabled.clear()
	if _scope != null:
		for node: Variant in _scope.find_children("*", "Control", true, false):
			var control := node as Control
			if control != null and control.focus_mode != Control.FOCUS_NONE:
				_focus_disabled.append([control, control.focus_mode])
				control.focus_mode = Control.FOCUS_NONE
	if CampaignFormatScript.can_grab_focus(_close_btn):
		_close_btn.grab_focus()
	var session: Node = _main.call("session")
	if session != null and session.has_signal("changed") and not session.is_connected("changed", Callable(self, "_on_session_changed")):
		session.connect("changed", Callable(self, "_on_session_changed"))
	refresh()


## 关闭：先还原背景焦点与原焦点，再脱离父节点发 closed 并延迟释放
## （顺序与 campaign_modal 相同：信号处理器里同步开的新弹层拿到干净状态，
## 信号源按钮不在同步 free 的栈上）。
func close() -> void:
	if _closing:
		return
	_closing = true
	var session: Node = _main.call("session")
	if session != null and session.has_signal("changed") and session.is_connected("changed", Callable(self, "_on_session_changed")):
		session.disconnect("changed", Callable(self, "_on_session_changed"))
	for pair: Variant in _focus_disabled:
		# pair[0] 可能已在弹层存活期间被释放（屏重建等）：先判活再取回。
		if is_instance_valid(pair[0]):
			(pair[0] as Control).focus_mode = pair[1]
	_focus_disabled.clear()
	if CampaignFormatScript.can_grab_focus(_previous_focus):
		_previous_focus.grab_focus()
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## 会话变化（装卸成功 / 商店购买 / 存档切换等）→ 延迟一帧重建内容区，
## 避开 changed 信号发射栈（信号源按钮可能正是本次要释放的控件）。
func _on_session_changed(_reason: String = "") -> void:
	call_deferred("refresh")


## 按 roster_id 从当前档案重读单位并重建内容区；单位不存在时明示。
func refresh() -> void:
	var unit := _find_unit()
	if unit.is_empty():
		_show_error("档内单位不存在或档案已变化")
		return
	_rebuild(unit)


## 在当前档案 roster 里按稳定 id 找单位（找不到返回空字典；只读）。
func _find_unit() -> Dictionary:
	var session: Node = _main.call("session")
	var profile: Dictionary = CampaignFormatScript.call_raw_dict(session, "get_profile")
	if profile.is_empty():
		return {}
	var roster: Variant = profile.get("roster", [])
	if roster is not Array:
		return {}
	for entry: Variant in roster:
		if entry is Dictionary and String((entry as Dictionary).get("id", "")) == _roster_id:
			return entry
	return {}


func _rebuild(unit: Dictionary) -> void:
	CampaignFormatScript.detach_children(_content)
	_summary.text = _summary_text(unit)
	var equipped: Dictionary = EquipmentDataScript.equipment_of(unit)
	for slot: StringName in EquipmentDataScript.SLOTS:
		_content.add_child(_make_slot_row(slot, equipped))
	_content.add_child(_make_bonus_label(unit))
	_append_catalog(unit, equipped)
	_resolve_pending_focus()


func _unit_title(unit: Dictionary) -> String:
	if unit.is_empty():
		return "未知单位"
	return String(unit.get("name", CampaignFormatScript.unit_label(unit)))


func _summary_text(unit: Dictionary) -> String:
	var class_id := _class_id_of(unit)
	var class_text := "未知职业"
	if class_id != &"":
		var pn := ProfessionDataScript.profession_name(class_id)
		class_text = pn if pn != "" else String(class_id)
	return "职业 %s ｜ %s" % [class_text, CampaignFormatScript.unit_label(unit)]


## classId 是职业键（存档/夹具兼容 legacy "class" 键，与 campaign_roster 同口径）。
func _class_id_of(unit: Dictionary) -> StringName:
	return StringName(String(unit.get("classId", unit.get("class", ""))))


func _make_slot_row(slot: StringName, equipped: Dictionary) -> Control:
	var row := PixelHBoxScript.new()
	row.name = "SlotRow_%s" % String(slot)
	var text: String = "%s · " % String(SLOT_LABELS.get(String(slot), String(slot)))
	var entry_id := StringName(String(equipped.get(slot, "")))
	if entry_id == &"":
		text += "（空）"
	else:
		text += EquipmentDataScript.entry_name(entry_id)
		var stats_text := _stat_text(EquipmentDataScript.get_entry(entry_id).get(&"stats", {}))
		if stats_text != "":
			text += "（%s）" % stats_text
	var label: Label = UIFactoryScript.label(text, ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN)
	label.name = "SlotTitle_%s" % String(slot)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if entry_id != &"":
		var button: Button = UIFactoryScript.button("卸下", Callable(), "", false)
		button.set("semantic", 1)
		button.name = "Unequip_%s" % String(slot)
		button.pressed.connect(_on_unequip_pressed.bind(String(slot)))
		row.add_child(button)
	return row


func _make_bonus_label(unit: Dictionary) -> Label:
	var text := _stat_text(EquipmentDataScript.stat_bonuses(unit))
	var label: Label = UIFactoryScript.label(
		"装备加成：%s" % (text if text != "" else "无"),
		ComponentThemeScript.FONT_CAPTION, UIThemeScript.ACCENT
	)
	label.name = "EquipBonus"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## 可装备清单：catalog_for（通用 + 显式授权）按固定槽序分组展示；
## 已装备条目按钮置灰「已装备」，其余可点击安装（同槽即替换）。
func _append_catalog(unit: Dictionary, equipped: Dictionary) -> void:
	var catalog: Array = EquipmentDataScript.catalog_for(_class_id_of(unit))
	var appended := false
	for slot: StringName in EquipmentDataScript.SLOTS:
		var group: Array = []
		for entry: Variant in catalog:
			var item: Dictionary = entry
			if String(item.get("slot", "")) == String(slot):
				group.append(item)
		if group.is_empty():
			continue
		var header: Label = UIFactoryScript.label(
			"可装备 · %s" % String(SLOT_LABELS.get(String(slot), String(slot))),
			ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM
		)
		header.name = "CatalogHeader_%s" % String(slot)
		_content.add_child(header)
		for item: Variant in group:
			_content.add_child(_make_catalog_row(item as Dictionary, equipped))
			appended = true
	if not appended:
		var empty: Label = UIFactoryScript.label(
			"（该职业暂无可装备项）", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM
		)
		empty.name = "CatalogEmpty"
		_content.add_child(empty)


func _make_catalog_row(item: Dictionary, equipped: Dictionary) -> Control:
	var entry_id := String(item.get("id", ""))
	var row := PixelHBoxScript.new()
	row.name = "CatalogRow_%s" % entry_id
	var text := String(item.get("name", entry_id))
	var stats_text := _stat_text(item.get("stats", {}))
	if stats_text != "":
		text += "（%s）" % stats_text
	var label: Label = UIFactoryScript.label(text, ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN)
	label.name = "CatalogLabel_%s" % entry_id
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var button: Button = UIFactoryScript.button("装备", Callable(), "", false)
	button.set("semantic", 0)
	button.name = "Equip_%s" % entry_id
	if equipped.values().has(StringName(entry_id)):
		button.disabled = true
		button.text = "已装备"
	else:
		button.pressed.connect(_on_equip_pressed.bind(entry_id))
	row.add_child(button)
	return row


func _on_equip_pressed(entry_id: String) -> void:
	var session: Node = _main.call("session")
	var result: Dictionary = CampaignFormatScript.call_dict(session, "equip_item", [_roster_id, entry_id])
	if bool(result.get("ok", false)):
		_error_label.visible = false
		var slot := String(result.get("slot", ""))
		# 装上后焦点落在本槽「卸下」键（最自然的下一步：反悔/换装）。
		_pending_focus_name = ("Unequip_%s" % slot) if slot != "" else ""
	else:
		_show_error(String(result.get("error", "装备失败")))


func _on_unequip_pressed(slot: String) -> void:
	var session: Node = _main.call("session")
	var result: Dictionary = CampaignFormatScript.call_dict(session, "unequip_item", [_roster_id, slot])
	if bool(result.get("ok", false)):
		_error_label.visible = false
		# 卸下后焦点落回该件的「装备」键（最自然的下一步：装回/换装）。
		_pending_focus_name = "Equip_%s" % String(result.get("prev", ""))
	else:
		_show_error(String(result.get("error", "卸下失败")))


func _show_error(text: String) -> void:
	_error_label.text = "操作未生效：%s" % text
	_error_label.visible = true


## 重建后交回焦点：指名控件（有效且可抓焦）→ 兜底关闭键。
func _resolve_pending_focus() -> void:
	var target_name := _pending_focus_name
	_pending_focus_name = ""
	if target_name != "":
		var target := find_child(target_name, true, false) as Control
		if target is Button and not (target as Button).disabled and CampaignFormatScript.can_grab_focus(target):
			target.grab_focus()
			return
	if CampaignFormatScript.can_grab_focus(_close_btn):
		_close_btn.grab_focus()


## 九属性固定序格式化「力+1 防+1」；未知键按字典序稳定追加（不依赖插入序）。
func _stat_text(stats: Variant) -> String:
	if stats is not Dictionary:
		return ""
	var dict: Dictionary = stats
	var parts: Array[String] = []
	var handled := {}
	for key: String in CampaignFormatScript.STAT_ORDER:
		var value := int(dict.get(key, 0))
		if value != 0:
			parts.append("%s+%d" % [String(CampaignFormatScript.STAT_LABELS.get(key, key)), value])
		handled[key] = true
	var extra: Array[String] = []
	for key: Variant in dict:
		var ks := String(key)
		if not handled.has(ks) and int(dict[key]) != 0:
			extra.append("%s+%d" % [ks, int(dict[key])])
	extra.sort()
	parts.append_array(extra)
	return " ".join(parts)
