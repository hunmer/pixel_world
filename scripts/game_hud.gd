extends CanvasLayer
## game_hud.gd — 世界 HUD 装配层：窗口分栏（左侧停靠竖栏 + 中间舞台 + 右侧
## side_panel 多 Tab 面板）、操作提示条、栏内按钮与信号接线。
## 战场选择面板与设置面板已拆至 scripts/hud/game_hud_battlefield_panel.gd /
## scripts/hud/game_hud_settings_panel.gd（hud 注入式静态装配，本文件只委托）。
## 面板不拦截输入（LeftRail/SidePanel 除外，它们要承接点击/滚动）。

const SidePanelScript = preload("res://scripts/side_panel.gd")
const HintBarScript = preload("res://scripts/hint_bar.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const HudBattlefieldPanelScript = preload("res://scripts/hud/game_hud_battlefield_panel.gd")
const HudSettingsPanelScript = preload("res://scripts/hud/game_hud_settings_panel.gd")
## 侧栏占用的窗口右侧列宽；main.gd 用它让 3D 视锥让出该列。
const SIDE_PANEL_WIDTH := SidePanelScript.PANEL_WIDTH
## 左侧停靠竖栏宽度（不透明，装战场/设置按钮）；窗口分栏 = 左栏 + 中间舞台 + 右侧栏。
const LEFT_RAIL_WIDTH := 56.0

## 用户点选了一个战场 JSON（main.gd 接收后 _enter_battlefield）
signal battlefield_picked(path: String)

## 用户请求打开地图编辑器（main.gd 接收后切 MapEditor.tscn）
signal editor_requested()

## 操作提示条目（键帽, 说明），hint_bar 组件渲染；契约断言 ≥12 条且含「M 地图」。
const HINT_ITEMS: Array = [
	["WASD / ↑ ↓", "移动"],
	["SHIFT", "加速"],
	["滚轮 / + −", "缩放"],
	["Q E / ← → / Z X", "切换 90°"],
	["中键拖拽", "步进旋转"],
	["R", "视角复位"],
	["SPACE+拖拽", "平移地图"],
	["M", "地图"],
	["T", "天气"],
	["N", "昼夜"],
	["B", "景深"],
	["SHIFT + T / N", "恢复自动"],
	["F", "缩放复位"],
	["CTRL + R", "新世界"],
	["P", "进入战棋"],
	["O", "战场列表"],
	["CTRL + E", "地图编辑器"],
]

var _bottom_area: VBoxContainer
## 战场选择面板（懒创建；null = 关闭；状态由 hud/ 面板模块维护）
var _battlefield_panel: Control = null
var _battlefield_error_label: Label = null


func _ready() -> void:
	layer = 100
	_apply_window_override_size()
	_build_ui()


## 编辑器调试运行不会重读 project.godot 的 window_*_override；
## 侧栏需要窗口多出一列，这里按配置补齐窗口尺寸（直接 godot --path . / 导出包时为幂等 no-op）。
func _apply_window_override_size() -> void:
	var width := int(ProjectSettings.get_setting_with_override(
		"display/window/size/window_width_override"))
	var height := int(ProjectSettings.get_setting_with_override(
		"display/window/size/window_height_override"))
	if width <= 0 or height <= 0:
		print("[side_panel] window_*_override 未配置，窗口尺寸保持引擎默认")
		return
	_resize_window_to(Vector2i(width, height))
	# 引擎/调试器可能在主场景 _ready 之后才施加启动尺寸；deferred 再补一次。
	_resize_window_to.call_deferred(Vector2i(width, height))


func _resize_window_to(target: Vector2i) -> void:
	var window := get_window()
	if window.size == target:
		return
	window.size = target
	print("[side_panel] 窗口尺寸 → %s（实际 %s，屏幕 %s）" % [
		target,
		window.size,
		DisplayServer.screen_get_usable_rect(),
	])


func _build_ui() -> void:
	var root := Control.new()
	root.name = "HUDRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_bottom_area = VBoxContainer.new()
	_bottom_area.name = "BottomArea"
	_bottom_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_area.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom_area.offset_left = LEFT_RAIL_WIDTH + 12.0
	_bottom_area.offset_top = -56.0
	# 右侧给常驻 SidePanel 让位，操作提示条不被覆盖
	_bottom_area.offset_right = -12.0 - SidePanelScript.PANEL_WIDTH
	_bottom_area.offset_bottom = -10.0
	root.add_child(_bottom_area)

	# 操作提示条（抽离为可复用组件 hint_bar.gd；地图编辑器 map_editor.gd 复用同一组件）
	var help_panel := HintBarScript.new()
	help_panel.name = "HelpPanel"
	help_panel.custom_minimum_size = Vector2(800.0, 32.0)
	help_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_bottom_area.add_child(help_panel)
	help_panel.set_title("操作")
	for hint: Array in HINT_ITEMS:
		help_panel.add_hint(hint[0], hint[1])

	# 左侧停靠竖栏（不透明窗格）：战场列表 + 设置按钮装进栏内，游戏画面不再从栏下透出
	var left_rail := PanelContainer.new()
	left_rail.name = "LeftRail"
	left_rail.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left_rail.offset_right = LEFT_RAIL_WIDTH
	left_rail.mouse_filter = Control.MOUSE_FILTER_STOP
	left_rail.add_theme_stylebox_override("panel", UIThemeScript.rail_style())
	root.add_child(left_rail)

	var left_bar := VBoxContainer.new()
	left_bar.name = "LeftBar"
	left_bar.add_theme_constant_override("separation", 8)
	left_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left_rail.add_child(left_bar)

	# 「战场」按钮（JSON 战场加载列表，调试入口）
	var battlefield_btn := UIFactoryScript.button("⚔", toggle_battlefield_panel)
	battlefield_btn.name = "BattlefieldBtn"
	battlefield_btn.tooltip_text = "战场列表（O）"
	battlefield_btn.custom_minimum_size = Vector2(42.0, 42.0)
	battlefield_btn.add_theme_font_size_override("font_size", 18)
	left_bar.add_child(battlefield_btn)

	# 「设置」按钮
	var settings_btn := UIFactoryScript.button("⚙", _open_settings)
	settings_btn.name = "SettingsBtn"
	settings_btn.tooltip_text = "设置"
	settings_btn.custom_minimum_size = Vector2(42.0, 42.0)
	settings_btn.add_theme_font_size_override("font_size", 18)
	left_bar.add_child(settings_btn)

	# 右侧常驻多 Tab 面板：【输出】tab 承接原左上角屏幕日志（见 side_panel.gd）
	var side_panel := SidePanelScript.new()
	side_panel.name = "SidePanel"
	root.add_child(side_panel)


## ---- 面板委托（装配在 scripts/hud/ 模块，对外方法/信号名不变） -------------

## 设置面板：战斗模式切换（就地/独立场景）
func _open_settings() -> void:
	HudSettingsPanelScript.open(self)


## 打开/关闭战场面板（O 键 / ⚔ 按钮共用）
func toggle_battlefield_panel() -> void:
	HudBattlefieldPanelScript.toggle(self)


func close_battlefield_panel() -> void:
	HudBattlefieldPanelScript.close(self)


## 面板打开时 ESC 关闭（O 键由 main.gd 分发，避免与主输入链抢事件）
func _unhandled_input(event: InputEvent) -> void:
	if _battlefield_panel == null or not is_instance_valid(_battlefield_panel):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
			close_battlefield_panel()
			get_viewport().set_input_as_handled()


## 加载失败时在面板上回显错误（main.gd 调用）
func show_battlefield_error(message: String) -> void:
	HudBattlefieldPanelScript.show_error(self, message)
