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
