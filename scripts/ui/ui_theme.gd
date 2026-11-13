## ui_theme.gd — 统一 UI 主题：配色常量 + StyleBox / 按钮 / Tab 样式工厂
##
## 从 map_editor.gd / battle_ui.gd / game_hud.gd / side_panel.gd 里重复的
## _flat_style / _btn_styles / _tab_styles / _panel_style 抽出的唯一权威版本。
## 全静态方法，直接 UITheme.xxx(...) 调用；不持有任何状态。
##
## 原有各文件的样式语义（迁移后保持不变或收敛为统一观感）：
##   - style_button      三态按钮 + 禁用 + 聚焦描边（合并 map_editor 与 battle_ui 两版）
##   - apply_tab_styles  TabContainer 三态选中/悬停/未选（两版合并，选中下缘 ACCENT 2px）
##   - overlay_panel_style  画布上悬浮小面板（地图编辑器工具条/格子信息）
##   - dock_panel_style     不透明停靠面板（战斗侧栏 / 编辑器右栏）
##   - rail_style           左侧竖栏（右单边框，game_hud LeftRail）
##   - float_panel_style    半透明悬浮卡片（HUD 设置/战场面板、战斗单位详情）
##   - tab_panel_style      TabContainer 内容区底
##   - menu_panel_style     战斗黑底白边弹窗（battle.gd / battle_ui.gd 共用）
class_name UITheme
extends RefCounted

const ICON_DIR := "res://addons/at-icons/control/"

# ---- 配色（统一定义；原 map_editor.gd / battle_ui.gd 两版微差常量收敛于此）----
const BG := Color(0.05, 0.07, 0.10, 0.97)
const PANEL_BORDER := Color(0.25, 0.37, 0.43, 0.9)
const TEXT_MAIN := Color(0.88, 0.93, 0.95)
const TEXT_DIM := Color(0.56, 0.68, 0.71)
const ACCENT := Color(0.40, 0.86, 0.76)
const ERROR := Color(1.0, 0.45, 0.42)
const BTN_BG := Color(0.08, 0.11, 0.14, 0.95)
const BTN_BG_HOVER := Color(0.13, 0.18, 0.22, 0.98)
const BTN_BG_PRESSED := Color(0.10, 0.26, 0.23, 1.0)
## HUD 系（game_hud.gd / side_panel.gd / hint_bar.gd 同族）
const HELP_BG := Color(0.035, 0.055, 0.075, 0.90)
const BORDER := Color(0.24, 0.32, 0.38, 0.8)
const TEXT_SECONDARY := Color(0.56, 0.68, 0.71)
const TOAST_COLOR := Color(1.0, 0.72, 0.4)


## 通用扁平 StyleBox；content_margin < 0 时不设内容边距。
static func flat_style(
	bg: Color, border: Color, border_width := 1, corner_radius := 6,
	content_margin := -1.0
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(corner_radius)
	if content_margin >= 0.0:
		sb.content_margin_left = content_margin
		sb.content_margin_right = content_margin
		sb.content_margin_top = content_margin
		sb.content_margin_bottom = content_margin
	return sb


## 画布上悬浮小面板（地图编辑器工具条 / 格子信息）。
static func overlay_panel_style() -> StyleBoxFlat:
	var sb := flat_style(Color(0.05, 0.07, 0.10, 0.97), PANEL_BORDER)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


## 不透明停靠面板（战斗侧栏 / 编辑器右栏）。
static func dock_panel_style() -> StyleBoxFlat:
	var sb := flat_style(BG, PANEL_BORDER)
	sb.content_margin_left = 10
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## 左侧竖栏（右单边框，不透明）。
static func rail_style() -> StyleBoxFlat:
	var sb := flat_style(
		Color(0.035, 0.055, 0.075, 1.0), Color(0.24, 0.32, 0.38, 0.8),
		1, 0, -1.0
	)
	sb.content_margin_left = 7
	sb.content_margin_right = 3
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


## 半透明悬浮卡片（HUD 设置/战场面板、战斗单位详情、Toast 面板）。
static func float_panel_style() -> StyleBoxFlat:
	var sb := flat_style(HELP_BG, BORDER, 1, 6, -1.0)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	return sb


## TabContainer 内容区底。
static func tab_panel_style() -> StyleBoxFlat:
	return flat_style(Color(0.02, 0.03, 0.045, 0.55), PANEL_BORDER, 1, 4, -1.0)


## 战斗黑底白边弹窗（菜单 / 预览 / 托管面板，battle.gd 与 battle_ui.gd 共用）。
static func menu_panel_style() -> StyleBoxFlat:
	return flat_style(
		Color(0, 0, 0, 0.88), Color.WHITE, 2, 4, 4.0
	)


## 统一三态按钮样式：normal/hover/pressed/hover_pressed + disabled + 聚焦 ACCENT 描边。
## 合并原 map_editor.gd 与 battle_ui.gd 两版（后者多 disabled 与 font_color overrides）。
static func style_button(b: Button) -> Button:
	b.add_theme_stylebox_override("normal",
		flat_style(BTN_BG, PANEL_BORDER, 1, 6, 6.0))
	b.add_theme_stylebox_override("hover",
		flat_style(BTN_BG_HOVER, PANEL_BORDER, 1, 6, 6.0))
	b.add_theme_stylebox_override("pressed",
		flat_style(BTN_BG_PRESSED, ACCENT, 1, 6, 6.0))
	b.add_theme_stylebox_override("hover_pressed",
		flat_style(BTN_BG_PRESSED, ACCENT, 1, 6, 6.0))
	var focus_style := flat_style(Color(0, 0, 0, 0), ACCENT, 1, 6, 6.0)
	b.add_theme_stylebox_override("focus", focus_style)
	b.add_theme_stylebox_override("disabled",
		flat_style(Color(0.07, 0.09, 0.11, 0.8), Color(0.2, 0.25, 0.28, 0.5), 1, 6, 6.0))
	b.add_theme_color_override("font_color", TEXT_MAIN)
	b.add_theme_color_override("font_hover_color", TEXT_MAIN)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_color_override("font_hover_pressed_color", ACCENT)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.55, 0.58, 0.5))
	b.add_theme_color_override("font_focus_color", ACCENT)
	b.add_theme_font_size_override("font_size", 12)
	return b


## 统一 TabContainer 三态样式（选中下缘 ACCENT 2px，未选中透明底）。
static func apply_tab_styles(tabs: TabContainer) -> void:
	var sb_selected := StyleBoxFlat.new()
	sb_selected.bg_color = Color(0.08, 0.12, 0.15)
	sb_selected.border_color = PANEL_BORDER
	sb_selected.set_border_width_all(1)
	sb_selected.set_border_width(SIDE_BOTTOM, 2)
	sb_selected.border_color = ACCENT
	sb_selected.set_corner_radius_all(4)
	sb_selected.content_margin_left = 10
	sb_selected.content_margin_right = 10
	sb_selected.content_margin_top = 4
	sb_selected.content_margin_bottom = 4
	tabs.add_theme_stylebox_override("tab_selected", sb_selected)

	var sb_hovered := StyleBoxFlat.new()
	sb_hovered.bg_color = Color(0.06, 0.08, 0.10)
	sb_hovered.border_color = PANEL_BORDER
	sb_hovered.set_border_width_all(1)
	sb_hovered.set_corner_radius_all(4)
	sb_hovered.content_margin_left = 10
	sb_hovered.content_margin_right = 10
	sb_hovered.content_margin_top = 4
	sb_hovered.content_margin_bottom = 4
	tabs.add_theme_stylebox_override("tab_hovered", sb_hovered)

	var sb_unselected := StyleBoxFlat.new()
	sb_unselected.bg_color = Color(0, 0, 0, 0)
	sb_unselected.border_color = Color(0, 0, 0, 0)
	sb_unselected.set_border_width_all(1)
	sb_unselected.set_corner_radius_all(4)
	sb_unselected.content_margin_left = 10
	sb_unselected.content_margin_right = 10
	sb_unselected.content_margin_top = 4
	sb_unselected.content_margin_bottom = 4
	tabs.add_theme_stylebox_override("tab_unselected", sb_unselected)
	tabs.add_theme_color_override("font_selected_color", TEXT_MAIN)
	tabs.add_theme_color_override("font_unselected_color", TEXT_DIM)
	tabs.add_theme_color_override("font_hovered_color", TEXT_MAIN)


## at-icons 图标（缺失时返回 null，调用方自行回退）。
static func icon(icon_name: String) -> Texture2D:
	if icon_name.is_empty():
		return null
	var path := ICON_DIR + icon_name + ".svg"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
