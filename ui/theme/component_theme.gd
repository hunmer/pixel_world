## component_theme.gd — 组件库集中 Theme 工厂：按钮语义变体 / TabContainer / 卡片面
##
## 复用 scripts/ui/ui_theme.gd 的配色常量与 flat_style 口径，不修改旧主题与旧工厂：
##   - PixelButtonPrimary / PixelButtonSecondary / PixelButtonDanger：Button 三种语义变体
##   - PixelTabs：TabContainer 变体，并给内部 TabBar 提供同口径主题项
##   - PixelPanel：PanelContainer 卡片面（深底 + 细边 + 圆角 + 阴影）
## create() 每次返回全新 Theme 实例，调用方之间主题实例隔离。
class_name ComponentTheme
extends RefCounted

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")

## 按钮语义枚举；语义 -> Theme Type Variation 由 variation_for_semantic() 决定。
enum ButtonSemantic {
	PRIMARY,
	SECONDARY,
	DANGER,
}

const BUTTON_PRIMARY: StringName = &"PixelButtonPrimary"
const BUTTON_SECONDARY: StringName = &"PixelButtonSecondary"
const BUTTON_DANGER: StringName = &"PixelButtonDanger"
const TABS_VARIATION: StringName = &"PixelTabs"
const PANEL_VARIATION: StringName = &"PixelPanel"
const LINE_EDIT_VARIATION: StringName = &"PixelLineEdit"
const OPTION_BUTTON_VARIATION: StringName = &"PixelOptionButton"
const CHECK_BUTTON_VARIATION: StringName = &"PixelCheckButton"
const SLIDER_VARIATION: StringName = &"PixelSlider"
const SPIN_BOX_VARIATION: StringName = &"PixelSpinBox"
const PROGRESS_BAR_VARIATION: StringName = &"PixelProgressBar"
const IMAGE_VARIATION: StringName = &"PixelImage"
const TEXT_AREA_VARIATION: StringName = &"PixelTextArea"
const DROPDOWN_VARIATION: StringName = &"PixelDropdown"
const POPUP_VARIATION: StringName = &"PixelPopup"

## 按钮图标默认最大宽度（像素）；PixelButton 可用 icon_size 覆盖。
const DEFAULT_ICON_SIZE: int = 18
const DEFAULT_FONT_SIZE: int = 12
const TAB_FONT_SIZE: int = 13


## 每次调用返回独立 Theme 实例（主题实例隔离；组装逻辑只读不共享可变状态）。
static func create() -> Theme:
	var theme := Theme.new()
	_define_button_variations(theme)
	_define_tabs(theme)
	_define_panel(theme)
	_define_controls(theme)
	_define_media_controls(theme)
	return theme


## 语义 -> Theme Type Variation 名；未知值回退主操作。
static func variation_for_semantic(semantic: int) -> StringName:
	match semantic:
		ButtonSemantic.SECONDARY:
			return BUTTON_SECONDARY
		ButtonSemantic.DANGER:
			return BUTTON_DANGER
		_:
			return BUTTON_PRIMARY


## 三种按钮语义：主操作对齐 UITheme.style_button 观感，次操作更低调，危险操作红系。
static func _define_button_variations(theme: Theme) -> void:
	_define_button(
		theme,
		BUTTON_PRIMARY,
		UIThemeScript.BTN_BG,
		UIThemeScript.BTN_BG_HOVER,
		UIThemeScript.BTN_BG_PRESSED,
		UIThemeScript.PANEL_BORDER,
		UIThemeScript.ACCENT,
		UIThemeScript.TEXT_MAIN,
		UIThemeScript.ACCENT,
		UIThemeScript.TEXT_MAIN
	)
	_define_button(
		theme,
		BUTTON_SECONDARY,
		Color(0.05, 0.07, 0.09, 0.62),
		UIThemeScript.BTN_BG_HOVER,
		Color(0.10, 0.16, 0.15, 1.0),
		UIThemeScript.BORDER,
		UIThemeScript.ACCENT,
		UIThemeScript.TEXT_DIM,
		UIThemeScript.TEXT_MAIN,
		UIThemeScript.TEXT_DIM
	)
	_define_button(
		theme,
		BUTTON_DANGER,
		Color(0.16, 0.06, 0.06, 0.95),
		Color(0.24, 0.09, 0.09, 0.98),
		Color(0.30, 0.06, 0.06, 1.0),
		Color(1.0, 0.45, 0.42, 0.55),
		UIThemeScript.ERROR,
		Color(1.0, 0.78, 0.75),
		Color.WHITE,
		Color(1.0, 0.62, 0.58)
	)


## 单个按钮变体：normal/hover/pressed/hover_pressed/focus/disabled 与图标尺寸。
static func _define_button(
	theme: Theme,
	variation: StringName,
	normal_bg: Color,
	hover_bg: Color,
	pressed_bg: Color,
	border: Color,
	pressed_border: Color,
	font_color: Color,
	pressed_font_color: Color,
	icon_color: Color
) -> void:
	theme.set_type_variation(variation, &"Button")
	theme.set_stylebox(
		"normal", variation, UIThemeScript.flat_style(normal_bg, border, 1, 6, 6.0)
	)
	theme.set_stylebox(
		"hover", variation, UIThemeScript.flat_style(hover_bg, border, 1, 6, 6.0)
	)
	theme.set_stylebox(
		"pressed", variation, UIThemeScript.flat_style(pressed_bg, pressed_border, 1, 6, 6.0)
	)
	theme.set_stylebox(
		"hover_pressed", variation,
		UIThemeScript.flat_style(pressed_bg, pressed_border, 1, 6, 6.0)
	)
	theme.set_stylebox(
		"focus", variation,
		UIThemeScript.flat_style(Color(0, 0, 0, 0), UIThemeScript.ACCENT, 1, 6, 6.0)
	)
	theme.set_stylebox(
		"disabled", variation,
		UIThemeScript.flat_style(
			Color(0.07, 0.09, 0.11, 0.8), Color(0.2, 0.25, 0.28, 0.5), 1, 6, 6.0
		)
	)
	theme.set_color("font_color", variation, font_color)
	theme.set_color("font_hover_color", variation, font_color)
	theme.set_color("font_pressed_color", variation, pressed_font_color)
	theme.set_color("font_hover_pressed_color", variation, pressed_font_color)
	theme.set_color("font_focus_color", variation, UIThemeScript.ACCENT)
	theme.set_color("font_disabled_color", variation, Color(0.5, 0.55, 0.58, 0.5))
	theme.set_color("font_outline_color", variation, Color.BLACK)
	theme.set_color("icon_normal_color", variation, icon_color)
	theme.set_color("icon_hover_color", variation, icon_color)
	theme.set_color("icon_pressed_color", variation, pressed_font_color)
	theme.set_color("icon_hover_pressed_color", variation, pressed_font_color)
	theme.set_color("icon_focus_color", variation, UIThemeScript.ACCENT)
	theme.set_color("icon_disabled_color", variation, Color(0.5, 0.55, 0.58, 0.5))
	theme.set_constant("icon_max_width", variation, DEFAULT_ICON_SIZE)
	theme.set_constant("h_separation", variation, 6)
	theme.set_font_size("font_size", variation, DEFAULT_FONT_SIZE)


## TabContainer 变体 + 内部 TabBar：原生页面结构不动，只补主题项。
static func _define_tabs(theme: Theme) -> void:
	var selected := _tab_stylebox(Color(0.08, 0.12, 0.15), UIThemeScript.ACCENT, 2)
	var hovered := _tab_stylebox(
		Color(0.06, 0.08, 0.10), UIThemeScript.PANEL_BORDER, 1
	)
	var unselected := _tab_stylebox(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 1)
	var disabled := _tab_stylebox(
		Color(0.06, 0.08, 0.10, 0.5), Color(0.2, 0.25, 0.28, 0.4), 1
	)
	var focus := _tab_stylebox(Color(0, 0, 0, 0), UIThemeScript.ACCENT, 1)
	var tabbar_bg := UIThemeScript.flat_style(
		Color(0.02, 0.03, 0.045, 0.55), Color(0, 0, 0, 0), 0, 4, -1.0
	)

	theme.set_type_variation(TABS_VARIATION, &"TabContainer")
	for type_name: StringName in [&"TabContainer", &"TabBar", TABS_VARIATION]:
		_apply_tabs_type(
			theme, type_name, selected, hovered, unselected, disabled, focus, tabbar_bg
		)


## 同一套 Tab 主题项写入指定类型（TabContainer 与内部 TabBar 共用口径）。
static func _apply_tabs_type(
	theme: Theme,
	type_name: StringName,
	selected: StyleBox,
	hovered: StyleBox,
	unselected: StyleBox,
	disabled: StyleBox,
	focus: StyleBox,
	tabbar_bg: StyleBox
) -> void:
	theme.set_stylebox("panel", type_name, UIThemeScript.tab_panel_style())
	theme.set_stylebox("tabbar_background", type_name, tabbar_bg)
	theme.set_stylebox("tab_selected", type_name, selected)
	theme.set_stylebox("tab_hovered", type_name, hovered)
	theme.set_stylebox("tab_unselected", type_name, unselected)
	theme.set_stylebox("tab_disabled", type_name, disabled)
	theme.set_stylebox("tab_focus", type_name, focus)
	theme.set_color("font_selected_color", type_name, UIThemeScript.TEXT_MAIN)
	theme.set_color("font_unselected_color", type_name, UIThemeScript.TEXT_DIM)
	theme.set_color("font_hovered_color", type_name, UIThemeScript.TEXT_MAIN)
	theme.set_color("font_disabled_color", type_name, Color(0.5, 0.55, 0.58, 0.5))
	theme.set_color("font_outline_color", type_name, Color.BLACK)
	theme.set_color("icon_selected_color", type_name, UIThemeScript.TEXT_MAIN)
	theme.set_color("icon_unselected_color", type_name, UIThemeScript.TEXT_DIM)
	theme.set_color("icon_hovered_color", type_name, UIThemeScript.TEXT_MAIN)
	theme.set_color("icon_disabled_color", type_name, Color(0.5, 0.55, 0.58, 0.5))
	theme.set_constant("side_margin", type_name, 8)
	theme.set_constant("tab_separation", type_name, 4)
	theme.set_constant("icon_separation", type_name, 6)
	theme.set_constant("icon_max_width", type_name, DEFAULT_ICON_SIZE)
	theme.set_constant("outline_size", type_name, 0)
	theme.set_font_size("font_size", type_name, TAB_FONT_SIZE)


## Tab 三态 StyleBox：选中下缘加宽，未选中透明但保留 1px 占位避免跳变。
static func _tab_stylebox(bg: Color, border: Color, bottom_width: int) -> StyleBoxFlat:
	var sb := UIThemeScript.flat_style(bg, border, 1, 4, -1.0)
	sb.set_border_width(SIDE_BOTTOM, bottom_width)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


## 卡片面：深底细边 + 圆角 + 阴影；内容边距由 StyleBox 统一给。
static func _define_panel(theme: Theme) -> void:
	theme.set_type_variation(PANEL_VARIATION, &"PanelContainer")
	var sb := UIThemeScript.flat_style(
		UIThemeScript.HELP_BG, UIThemeScript.BORDER, 1, 8, 12.0
	)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	theme.set_stylebox("panel", PANEL_VARIATION, sb)


## 六个薄控件变体：输入框 / 下拉 / 开关 / 滑块 / 数值 / 进度条。
## 只覆盖与观感直接相关的键，原生输入、信号、范围与禁用行为全部保留。
static func _define_controls(theme: Theme) -> void:
	_define_line_edit(theme)
	_define_option_button(theme)
	_define_check_button(theme)
	_define_slider(theme)
	_define_spin_box(theme)
	_define_progress_bar(theme)


## 输入框：深底细边，焦点用 ACCENT 描边；占位符弱化。
static func _define_line_edit(theme: Theme) -> void:
	theme.set_type_variation(LINE_EDIT_VARIATION, &"LineEdit")
	theme.set_stylebox(
		"normal", LINE_EDIT_VARIATION,
		UIThemeScript.flat_style(UIThemeScript.BTN_BG, UIThemeScript.BORDER, 1, 6, 8.0)
	)
	theme.set_stylebox(
		"focus", LINE_EDIT_VARIATION,
		UIThemeScript.flat_style(Color(0.07, 0.10, 0.12, 1.0), UIThemeScript.ACCENT, 1, 6, 8.0)
	)
	theme.set_stylebox(
		"read_only", LINE_EDIT_VARIATION,
		UIThemeScript.flat_style(
			Color(0.06, 0.08, 0.10, 0.9), Color(0.2, 0.25, 0.28, 0.5), 1, 6, 8.0
		)
	)
	theme.set_color("font_color", LINE_EDIT_VARIATION, UIThemeScript.TEXT_MAIN)
	theme.set_color("font_placeholder_color", LINE_EDIT_VARIATION, UIThemeScript.TEXT_DIM)
	theme.set_color("font_selected_color", LINE_EDIT_VARIATION, UIThemeScript.TEXT_MAIN)
	theme.set_color("caret_color", LINE_EDIT_VARIATION, UIThemeScript.ACCENT)
	theme.set_color("selection_color", LINE_EDIT_VARIATION, Color(0.4, 0.86, 0.76, 0.28))
	theme.set_font_size("font_size", LINE_EDIT_VARIATION, DEFAULT_FONT_SIZE)


## 下拉：复用按钮三态结构，比主按钮更扁平。
static func _define_option_button(theme: Theme) -> void:
	theme.set_type_variation(OPTION_BUTTON_VARIATION, &"OptionButton")
	theme.set_stylebox(
		"normal", OPTION_BUTTON_VARIATION,
		UIThemeScript.flat_style(UIThemeScript.BTN_BG, UIThemeScript.BORDER, 1, 6, 6.0)
	)
	theme.set_stylebox(
		"hover", OPTION_BUTTON_VARIATION,
		UIThemeScript.flat_style(UIThemeScript.BTN_BG_HOVER, UIThemeScript.PANEL_BORDER, 1, 6, 6.0)
	)
	theme.set_stylebox(
		"pressed", OPTION_BUTTON_VARIATION,
		UIThemeScript.flat_style(UIThemeScript.BTN_BG_PRESSED, UIThemeScript.ACCENT, 1, 6, 6.0)
	)
	theme.set_stylebox(
		"hover_pressed", OPTION_BUTTON_VARIATION,
		UIThemeScript.flat_style(UIThemeScript.BTN_BG_PRESSED, UIThemeScript.ACCENT, 1, 6, 6.0)
	)
	theme.set_stylebox(
		"focus", OPTION_BUTTON_VARIATION,
		UIThemeScript.flat_style(Color(0, 0, 0, 0), UIThemeScript.ACCENT, 1, 6, 6.0)
	)
	theme.set_stylebox(
		"disabled", OPTION_BUTTON_VARIATION,
		UIThemeScript.flat_style(
			Color(0.07, 0.09, 0.11, 0.8), Color(0.2, 0.25, 0.28, 0.5), 1, 6, 6.0
		)
	)
	theme.set_color("font_color", OPTION_BUTTON_VARIATION, UIThemeScript.TEXT_MAIN)
	theme.set_color("font_hover_color", OPTION_BUTTON_VARIATION, UIThemeScript.TEXT_MAIN)
	theme.set_color("font_pressed_color", OPTION_BUTTON_VARIATION, UIThemeScript.ACCENT)
	theme.set_color("font_focus_color", OPTION_BUTTON_VARIATION, UIThemeScript.ACCENT)
	theme.set_color("font_disabled_color", OPTION_BUTTON_VARIATION, Color(0.5, 0.55, 0.58, 0.5))
	theme.set_constant("h_separation", OPTION_BUTTON_VARIATION, 6)
	theme.set_font_size("font_size", OPTION_BUTTON_VARIATION, DEFAULT_FONT_SIZE)


## 开关：透明底 + 悬停微亮；勾选图标沿用原生 CheckButton 图标。
static func _define_check_button(theme: Theme) -> void:
	theme.set_type_variation(CHECK_BUTTON_VARIATION, &"CheckButton")
	theme.set_stylebox(
		"normal", CHECK_BUTTON_VARIATION,
		UIThemeScript.flat_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4, 2.0)
	)
	theme.set_stylebox(
		"hover", CHECK_BUTTON_VARIATION,
		UIThemeScript.flat_style(Color(0.10, 0.16, 0.15, 0.5), Color(0, 0, 0, 0), 0, 4, 2.0)
	)
	theme.set_stylebox(
		"pressed", CHECK_BUTTON_VARIATION,
		UIThemeScript.flat_style(Color(0.10, 0.16, 0.15, 0.7), Color(0, 0, 0, 0), 0, 4, 2.0)
	)
	theme.set_stylebox(
		"focus", CHECK_BUTTON_VARIATION,
		UIThemeScript.flat_style(Color(0, 0, 0, 0), UIThemeScript.ACCENT, 1, 4, 2.0)
	)
	theme.set_stylebox(
		"disabled", CHECK_BUTTON_VARIATION,
		UIThemeScript.flat_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4, 2.0)
	)
	theme.set_color("font_color", CHECK_BUTTON_VARIATION, UIThemeScript.TEXT_MAIN)
	theme.set_color("font_hover_color", CHECK_BUTTON_VARIATION, UIThemeScript.TEXT_MAIN)
	theme.set_color("font_pressed_color", CHECK_BUTTON_VARIATION, UIThemeScript.ACCENT)
	theme.set_color("font_disabled_color", CHECK_BUTTON_VARIATION, Color(0.5, 0.55, 0.58, 0.5))
	theme.set_constant("h_separation", CHECK_BUTTON_VARIATION, 6)
	theme.set_font_size("font_size", CHECK_BUTTON_VARIATION, DEFAULT_FONT_SIZE)


## 滑块：深色槽 + ACCENT 已填充区；抓取图标沿用原生。
static func _define_slider(theme: Theme) -> void:
	theme.set_type_variation(SLIDER_VARIATION, &"HSlider")
	theme.set_stylebox(
		"slider", SLIDER_VARIATION,
		UIThemeScript.flat_style(Color(0.06, 0.08, 0.10, 1.0), UIThemeScript.BORDER, 1, 3, 3.0)
	)
	theme.set_stylebox(
		"grabber_area", SLIDER_VARIATION,
		UIThemeScript.flat_style(Color(0.40, 0.86, 0.76, 0.55), Color(0, 0, 0, 0), 0, 3, 3.0)
	)
	theme.set_stylebox(
		"grabber_area_highlight", SLIDER_VARIATION,
		UIThemeScript.flat_style(Color(0.40, 0.86, 0.76, 0.75), Color(0, 0, 0, 0), 0, 3, 3.0)
	)


## 数值框：自身只注册变体；输入区外观由 PixelSpinBox 指向 LineEdit 变体。
static func _define_spin_box(theme: Theme) -> void:
	theme.set_type_variation(SPIN_BOX_VARIATION, &"SpinBox")


## 进度条：深底槽 + ACCENT 填充。
static func _define_progress_bar(theme: Theme) -> void:
	theme.set_type_variation(PROGRESS_BAR_VARIATION, &"ProgressBar")
	theme.set_stylebox(
		"background", PROGRESS_BAR_VARIATION,
		UIThemeScript.flat_style(UIThemeScript.BTN_BG, UIThemeScript.BORDER, 1, 6, 4.0)
	)
	theme.set_stylebox(
		"fill", PROGRESS_BAR_VARIATION,
		UIThemeScript.flat_style(Color(0.40, 0.86, 0.76, 0.85), Color(0, 0, 0, 0), 0, 6, 4.0)
	)
	theme.set_font_size("font_size", PROGRESS_BAR_VARIATION, DEFAULT_FONT_SIZE)
	theme.set_color("font_color", PROGRESS_BAR_VARIATION, UIThemeScript.TEXT_MAIN)


## 媒体与菜单类变体：图片容器 / 多行文本 / 动作菜单 / 弹层。
## 播放器容器直接复用 PANEL_VARIATION，不额外造变体。
static func _define_media_controls(theme: Theme) -> void:
	_define_image(theme)
	_define_text_area(theme)
	_define_dropdown(theme)
	_define_popup(theme)


## 图片容器：卡片面但内容边距为 0，让纹理贴边；圆角由 StyleBox 裁出观感。
static func _define_image(theme: Theme) -> void:
	theme.set_type_variation(IMAGE_VARIATION, &"PanelContainer")
	theme.set_stylebox(
		"panel", IMAGE_VARIATION,
		UIThemeScript.flat_style(UIThemeScript.HELP_BG, UIThemeScript.BORDER, 1, 8, 0.0)
	)


## 多行文本：与输入框同口径，补只读态与选区色。
static func _define_text_area(theme: Theme) -> void:
	theme.set_type_variation(TEXT_AREA_VARIATION, &"TextEdit")
	theme.set_stylebox(
		"normal", TEXT_AREA_VARIATION,
		UIThemeScript.flat_style(UIThemeScript.BTN_BG, UIThemeScript.BORDER, 1, 6, 8.0)
	)
	theme.set_stylebox(
		"focus", TEXT_AREA_VARIATION,
		UIThemeScript.flat_style(Color(0.07, 0.10, 0.12, 1.0), UIThemeScript.ACCENT, 1, 6, 8.0)
	)
	theme.set_stylebox(
		"read_only", TEXT_AREA_VARIATION,
		UIThemeScript.flat_style(
			Color(0.06, 0.08, 0.10, 0.9), Color(0.2, 0.25, 0.28, 0.5), 1, 6, 8.0
		)
	)
	theme.set_color("font_color", TEXT_AREA_VARIATION, UIThemeScript.TEXT_MAIN)
	theme.set_color("font_readonly_color", TEXT_AREA_VARIATION, UIThemeScript.TEXT_DIM)
	theme.set_color("font_selected_color", TEXT_AREA_VARIATION, UIThemeScript.TEXT_MAIN)
	theme.set_color("caret_color", TEXT_AREA_VARIATION, UIThemeScript.ACCENT)
	theme.set_color("selection_color", TEXT_AREA_VARIATION, Color(0.4, 0.86, 0.76, 0.28))
	theme.set_font_size("font_size", TEXT_AREA_VARIATION, DEFAULT_FONT_SIZE)


## 动作菜单：沿用按钮六态观感，与 OptionButton 的下拉外观区分（MenuButton 基类）。
static func _define_dropdown(theme: Theme) -> void:
	theme.set_type_variation(DROPDOWN_VARIATION, &"MenuButton")
	theme.set_stylebox(
		"normal", DROPDOWN_VARIATION,
		UIThemeScript.flat_style(UIThemeScript.BTN_BG, UIThemeScript.BORDER, 1, 6, 6.0)
	)
	theme.set_stylebox(
		"hover", DROPDOWN_VARIATION,
		UIThemeScript.flat_style(UIThemeScript.BTN_BG_HOVER, UIThemeScript.PANEL_BORDER, 1, 6, 6.0)
	)
	theme.set_stylebox(
		"pressed", DROPDOWN_VARIATION,
		UIThemeScript.flat_style(UIThemeScript.BTN_BG_PRESSED, UIThemeScript.ACCENT, 1, 6, 6.0)
	)
	theme.set_stylebox(
		"hover_pressed", DROPDOWN_VARIATION,
		UIThemeScript.flat_style(UIThemeScript.BTN_BG_PRESSED, UIThemeScript.ACCENT, 1, 6, 6.0)
	)
	theme.set_stylebox(
		"focus", DROPDOWN_VARIATION,
		UIThemeScript.flat_style(Color(0, 0, 0, 0), UIThemeScript.ACCENT, 1, 6, 6.0)
	)
	theme.set_stylebox(
		"disabled", DROPDOWN_VARIATION,
		UIThemeScript.flat_style(
			Color(0.07, 0.09, 0.11, 0.8), Color(0.2, 0.25, 0.28, 0.5), 1, 6, 6.0
		)
	)
	theme.set_color("font_color", DROPDOWN_VARIATION, UIThemeScript.TEXT_MAIN)
	theme.set_color("font_hover_color", DROPDOWN_VARIATION, UIThemeScript.TEXT_MAIN)
	theme.set_color("font_pressed_color", DROPDOWN_VARIATION, UIThemeScript.ACCENT)
	theme.set_color("font_focus_color", DROPDOWN_VARIATION, UIThemeScript.ACCENT)
	theme.set_color("font_disabled_color", DROPDOWN_VARIATION, Color(0.5, 0.55, 0.58, 0.5))
	theme.set_constant("h_separation", DROPDOWN_VARIATION, 6)
	theme.set_font_size("font_size", DROPDOWN_VARIATION, DEFAULT_FONT_SIZE)


## 弹层：与卡片同口径的深底面，独立窗口内容直接落在这个面板上。
static func _define_popup(theme: Theme) -> void:
	theme.set_type_variation(POPUP_VARIATION, &"PopupPanel")
	var sb := UIThemeScript.flat_style(
		UIThemeScript.HELP_BG, UIThemeScript.BORDER, 1, 8, 12.0
	)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	theme.set_stylebox("panel", POPUP_VARIATION, sb)
