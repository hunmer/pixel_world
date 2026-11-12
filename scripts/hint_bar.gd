## hint_bar.gd — 可复用操作提示条（快捷键 + 鼠标操作 keycap 提示）
##
## 从 game_hud.gd 抽离的底部操作提示条：一行「键帽 + 动作说明」横排，
## 过窄时 HFlowContainer 自动换行。game_hud.gd（世界 HUD，节点名 HelpPanel）
## 与 scenes/map_editor.gd（地图编辑器，节点名 EditorHintBar）共用同一组件。
##
## 用法（纯代码建 UI，项目风格同 side_panel.gd / game_hud.gd）：
##   var bar := HintBarScript.new()      # _init 已建好 HelpFlow，可先配置后入树
##   bar.name = "HelpPanel"              # 命名/锚点/最小尺寸由调用方决定
##   bar.set_title("操作")
##   bar.add_hint("M", "地图")
##   parent.add_child(bar)
## 内部节点名固定（HelpFlow / Hint%d / Keycap / Key / Action / HelpTitle），
## tests/game_hud_contract.gd 按路径 HUDRoot/BottomArea/HelpPanel/HelpFlow 断言；
## 全树 MOUSE_FILTER_IGNORE，不拦截任何游戏输入。

extends PanelContainer

const TEXT_SECONDARY := Color(0.56, 0.68, 0.71)
const ACCENT := Color(0.40, 0.86, 0.76)
const KEY_COLOR := Color(1.0, 0.78, 0.34)
const HELP_BG := Color(0.035, 0.055, 0.075, 0.90)
const BORDER := Color(0.25, 0.37, 0.43, 0.88)

var _flow: HFlowContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", _panel_style())
	_flow = HFlowContainer.new()
	_flow.name = "HelpFlow"
	_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", 12)
	_flow.add_theme_constant_override("v_separation", 4)
	add_child(_flow)


## 提示条开头的分类标题（如「操作」）；条目编号 Hint%d 从标题之后起算
func set_title(text_value: String) -> void:
	var title := _label(text_value, 11, ACCENT)
	title.name = "HelpTitle"
	_flow.add_child(title)


## 追加一条「键帽 + 动作说明」（Keycap/Key/Action 节点名为契约测试依赖，勿改名）
func add_hint(key_text: String, action_text: String) -> void:
	var group := HBoxContainer.new()
	group.name = "Hint%d" % _flow.get_child_count()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override("separation", 5)
	_flow.add_child(group)

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


## 当前条目数（含标题；契约测试用它对齐 hint 数量）
func hint_count() -> int:
	return _flow.get_child_count()


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
