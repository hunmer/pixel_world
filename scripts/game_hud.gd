extends CanvasLayer

## 屏幕顶部只保留操作提示；面板为右上角小地图预留空间且不拦截输入。

const HELP_BG := Color(0.035, 0.055, 0.075, 0.90)
const BORDER := Color(0.25, 0.37, 0.43, 0.88)
const TEXT_SECONDARY := Color(0.56, 0.68, 0.71)
const ACCENT := Color(0.40, 0.86, 0.76)
const KEY_COLOR := Color(1.0, 0.78, 0.34)
const MINIMAP_RESERVE := 150.0

var _top_area: VBoxContainer
var _help_flow: HFlowContainer


func _ready() -> void:
	layer = 100
	_build_ui()


func _build_ui() -> void:
	var root := Control.new()
	root.name = "HUDRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_top_area = VBoxContainer.new()
	_top_area.name = "TopArea"
	_top_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_area.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_area.offset_left = 12.0
	_top_area.offset_top = 10.0
	_top_area.offset_right = -MINIMAP_RESERVE
	_top_area.offset_bottom = 48.0
	root.add_child(_top_area)

	var help_panel := PanelContainer.new()
	help_panel.name = "HelpPanel"
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_panel.custom_minimum_size = Vector2(800.0, 32.0)
	help_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	help_panel.add_theme_stylebox_override("panel", _panel_style())
	_top_area.add_child(help_panel)

	_help_flow = HFlowContainer.new()
	_help_flow.name = "HelpFlow"
	_help_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_flow.add_theme_constant_override("h_separation", 12)
	_help_flow.add_theme_constant_override("v_separation", 4)
	help_panel.add_child(_help_flow)

	var help_title := _label("操作", 11, ACCENT)
	help_title.name = "HelpTitle"
	_help_flow.add_child(help_title)
	_add_hint("WASD / 方向键", "移动")
	_add_hint("SHIFT", "加速")
	_add_hint("滚轮 / + −", "缩放")
	_add_hint("M", "地图")
	_add_hint("T", "天气")
	_add_hint("N", "昼夜")
	_add_hint("B", "景深")
	_add_hint("SHIFT + T / N", "恢复自动")
	_add_hint("F", "复位")
	_add_hint("R", "新世界")
	_add_hint("P", "进入战棋")

	# 右上角「设置」按钮
	var settings_btn := Button.new()
	settings_btn.name = "SettingsBtn"
	settings_btn.text = "⚙ 设置"
	settings_btn.position = Vector2(get_viewport().get_visible_rect().size.x - MINIMAP_RESERVE - 100, 10)
	settings_btn.size = Vector2(90, 32)
	settings_btn.add_theme_font_size_override("font_size", 12)
	settings_btn.pressed.connect(_open_settings)
	root.add_child(settings_btn)


## 设置面板：战斗模式切换（就地/独立场景）
func _open_settings() -> void:
	# 如果已打开，先移除
	var old := get_node_or_null("HUDRoot/SettingsPanel")
	if old != null:
		old.queue_free()
		return
	var vp := get_viewport().get_visible_rect().size
	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.custom_minimum_size = Vector2(280, 120)
	panel.position = (vp - panel.custom_minimum_size) / 2.0
	panel.add_theme_stylebox_override("panel", _panel_style())
	$"HUDRoot".add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.offset_left = 12; vbox.offset_top = 8
	vbox.offset_right = -12; vbox.offset_bottom = -8
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	# 标题
	var title := _label("设置", 14, ACCENT)
	vbox.add_child(title)
	# 战斗模式选项
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	var lbl := _label("战斗模式", 12, TEXT_SECONDARY)
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.add_item("就地（B1）", 0)
	opt.add_item("独立场景（B2）", 1)
	opt.select(0 if Settings.battle_inline_mode else 1)
	opt.custom_minimum_size = Vector2(140, 0)
	opt.item_selected.connect(func(idx: int):
		Settings.set_battle_inline_mode(idx == 0)
	)
	row.add_child(opt)
	# 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(func():
		var p := get_node_or_null("HUDRoot/SettingsPanel")
		if p != null: p.queue_free()
	)
	vbox.add_child(close_btn)


func _add_hint(key_text: String, action_text: String) -> void:
	var group := HBoxContainer.new()
	group.name = "Hint%d" % _help_flow.get_child_count()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override("separation", 5)
	_help_flow.add_child(group)

	var key_panel := PanelContainer.new()
	key_panel.name = "Keycap"
	key_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_panel.add_theme_stylebox_override("panel", _keycap_style())
	group.add_child(key_panel)
	var key_label := _label(key_text, 10, KEY_COLOR)
	key_label.name = "Key"
	key_panel.add_child(key_label)

	var action_label := _label(action_text, 11, TEXT_SECONDARY)
	action_label.name = "Action"
	group.add_child(action_label)


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text_value
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	result.add_theme_constant_override("shadow_offset_x", 1)
	result.add_theme_constant_override("shadow_offset_y", 1)
	return result


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = HELP_BG
	style.border_color = BORDER
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 7.0
	style.content_margin_top = 3.0
	style.content_margin_right = 7.0
	style.content_margin_bottom = 3.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0.0, 2.0)
	return style


func _keycap_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.095, 0.075, 0.96)
	style.border_color = KEY_COLOR
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 4.0
	style.content_margin_top = 2.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 2.0
	return style
