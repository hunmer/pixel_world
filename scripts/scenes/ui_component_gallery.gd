## scripts/scenes/ui_component_gallery.gd — UI 组件库演示画廊（精简版）
##
## 只展示真实组件、短名称、必要操作标签与真实值；API、继承、资源路径与用法
## 说明全部放 ui/README.md，界面不写教学文字、帮助页、描述段落或说明 tooltip。
##
## 页签：按钮 / 卡片 / 输入 / 数值。PixelButton、PixelTabs、PixelPanel 与六类
## 新组件（输入框 / 下拉 / 开关 / 滑块 / 数值框 / 进度条）在同一画廊真实交互。
## F6 独立运行，不依赖战斗参数，不修改默认启动；ESC 退出。
extends Control

const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const PixelButtonScript = preload("res://ui/components/pixel_button.gd")
const PixelTabsScript = preload("res://ui/components/pixel_tabs.gd")
const PixelPanelScene = preload("res://ui/components/pixel_panel.tscn")
const PixelLineEditScript = preload("res://ui/components/pixel_line_edit.gd")
const PixelOptionButtonScript = preload("res://ui/components/pixel_option_button.gd")
const PixelCheckButtonScript = preload("res://ui/components/pixel_check_button.gd")
const PixelSliderScript = preload("res://ui/components/pixel_slider.gd")
const PixelSpinBoxScript = preload("res://ui/components/pixel_spin_box.gd")
const PixelProgressBarScript = preload("res://ui/components/pixel_progress_bar.gd")

## 反馈面板最多保留的历史条数（超出丢弃最早一条，避免长时间点击后无限增长）。
const FEEDBACK_MAX_LINES := 60
## 右侧反馈卡片的窄窗口最小宽度。
const SIDE_MIN_WIDTH := 360
## 页签标题：只保留短组件类别。
const DEMO_TAB_TITLES: Array[String] = ["按钮", "卡片", "输入", "数值"]
## 数值页滑块 / 数值框 / 进度条的共用范围。
const DEMO_VALUE_MAX: float = 100.0

var _tabs: TabContainer
var _feedback_log: RichTextLabel
var _status_label: Label
var _feedback_lines: PackedStringArray = PackedStringArray()

var _primary_button: Button
var _secondary_button: Button
var _danger_button: Button
var _icon_button: Button
var _disabled_button: Button
var _toggle_button: Button
var _reset_button: Button
var _demo_sfx_switch: CheckButton

var _demo_edit: LineEdit
var _demo_option: OptionButton
var _demo_switch: CheckButton
var _preview_label: Label

var _demo_slider: HSlider
var _demo_spin: SpinBox
var _demo_progress: ProgressBar


func _ready() -> void:
	_build_ui()
	_connect_signals()
	_status_label.text = "就绪"
	_primary_button.grab_focus()


## 全屏锚点 + MarginContainer + VBox + HSplitContainer：标题行固定，主体两列可拖拽。
func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = UIThemeScript.BG
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sides: Array[String] = ["left", "right", "top", "bottom"]
	for side: String in sides:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 12)
	margin.add_child(root_box)

	root_box.add_child(_build_header())

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 680
	root_box.add_child(split)

	_tabs = PixelTabsScript.new() as TabContainer
	_tabs.name = "ComponentTabs"
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(_tabs)

	_build_button_page()
	_build_panel_page()
	_build_input_page()
	_build_value_page()

	var feedback_card := _make_card("反馈", "")
	feedback_card.custom_minimum_size = Vector2(SIDE_MIN_WIDTH, 0)
	feedback_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feedback_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(feedback_card)
	_build_feedback_body(_card_slot(feedback_card))


## 标题行：短标题 + 重置按钮。
func _build_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var title := UIFactoryScript.outline_label("UI 组件库", 26, Color.WHITE, 6)
	row.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_reset_button = UIFactoryScript.button("重置", _reset_demo)
	_reset_button.name = "ResetButton"
	_reset_button.custom_minimum_size = Vector2(96, 36)
	row.add_child(_reset_button)
	return row


## 第 1 页：三种按钮语义、图标/禁用/切换原生状态、按钮音效开关。
func _build_button_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[0]) as VBoxContainer
	page.add_theme_constant_override("separation", 12)

	var card := _make_card("按钮", "")
	_card_slot(card).add_child(_build_semantic_row())
	page.add_child(card)

	var state_card := _make_card("状态", "")
	_card_slot(state_card).add_child(_build_native_row())
	page.add_child(state_card)

	var sfx_card := _make_card("音效", "")
	_demo_sfx_switch = UIFactoryScript.check_button("音效", "")
	_demo_sfx_switch.name = "DemoSfxSwitch"
	_demo_sfx_switch.button_pressed = true
	_card_slot(sfx_card).add_child(_demo_sfx_switch)
	page.add_child(sfx_card)


func _build_semantic_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_primary_button = _make_pixel_button("主操作", 0, "play")
	_primary_button.name = "PrimaryButton"
	_secondary_button = _make_pixel_button("次操作", 1, "cog")
	_secondary_button.name = "SecondaryButton"
	_danger_button = _make_pixel_button("危险", 2, "skull")
	_danger_button.name = "DangerButton"
	var buttons: Array[Button] = [_primary_button, _secondary_button, _danger_button]
	for btn: Button in buttons:
		btn.custom_minimum_size = Vector2(0, 40)
		row.add_child(btn)
	return row


func _build_native_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_icon_button = _make_pixel_button("图标 32", 0, "star", 32)
	_icon_button.name = "IconButton"
	_icon_button.custom_minimum_size = Vector2(0, 44)
	row.add_child(_icon_button)

	_disabled_button = _make_pixel_button("禁用", 1, "info")
	_disabled_button.name = "DisabledButton"
	_disabled_button.disabled = true
	_disabled_button.custom_minimum_size = Vector2(0, 40)
	row.add_child(_disabled_button)

	_toggle_button = _make_pixel_button("切换", 1, "target")
	_toggle_button.name = "ToggleButton"
	_toggle_button.toggle_mode = true
	_toggle_button.custom_minimum_size = Vector2(0, 40)
	row.add_child(_toggle_button)
	return row


## 第 2 页：PixelPanel 卡片（有头部 / 空头部）。
func _build_panel_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[1]) as VBoxContainer
	page.add_theme_constant_override("separation", 12)

	var card := _make_card("卡片", "")
	var action := _make_pixel_button("卡片操作", 1, "target")
	action.custom_minimum_size = Vector2(0, 36)
	action.pressed.connect(_on_card_action_pressed)
	_card_slot(card).add_child(action)
	page.add_child(card)

	var bare_card := _make_card("", "")
	var bare_action := _make_pixel_button("空头部", 1, "info")
	bare_action.custom_minimum_size = Vector2(0, 36)
	_card_slot(bare_card).add_child(bare_action)
	page.add_child(bare_card)


## 第 3 页：PixelLineEdit / PixelOptionButton / PixelCheckButton + 当前值。
func _build_input_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[2]) as VBoxContainer
	page.add_theme_constant_override("separation", 12)

	var card := _make_card("输入", "")
	var slot := _card_slot(card)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)

	grid.add_child(UIFactoryScript.label("文本", 12, UIThemeScript.TEXT_MAIN))
	_demo_edit = PixelLineEditScript.new() as LineEdit
	_demo_edit.name = "DemoLineEdit"
	_demo_edit.placeholder_text = "输入"
	_demo_edit.custom_minimum_size = Vector2(260, 0)
	_demo_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_demo_edit)

	grid.add_child(UIFactoryScript.label("选项", 12, UIThemeScript.TEXT_MAIN))
	_demo_option = PixelOptionButtonScript.new() as OptionButton
	_demo_option.name = "DemoOption"
	_demo_option.add_item("A")
	_demo_option.add_item("B")
	_demo_option.add_item("C")
	_demo_option.select(0)
	grid.add_child(_demo_option)

	grid.add_child(UIFactoryScript.label("开关", 12, UIThemeScript.TEXT_MAIN))
	_demo_switch = PixelCheckButtonScript.new() as CheckButton
	_demo_switch.name = "DemoSwitch"
	_demo_switch.text = "禁用危险按钮"
	grid.add_child(_demo_switch)

	slot.add_child(grid)

	_preview_label = UIFactoryScript.label("值：—", 13, UIThemeScript.TEXT_MAIN)
	_preview_label.name = "PreviewLabel"
	slot.add_child(_preview_label)
	page.add_child(card)


## 第 4 页：PixelSlider / PixelProgressBar / PixelSpinBox，滑块与数值框联动进度。
func _build_value_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[3]) as VBoxContainer
	page.add_theme_constant_override("separation", 12)

	var card := _make_card("数值", "")
	var slot := _card_slot(card)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)

	grid.add_child(UIFactoryScript.label("滑块", 12, UIThemeScript.TEXT_MAIN))
	_demo_slider = PixelSliderScript.new() as HSlider
	_demo_slider.name = "DemoSlider"
	_demo_slider.min_value = 0.0
	_demo_slider.max_value = DEMO_VALUE_MAX
	_demo_slider.step = 1.0
	_demo_slider.value = 0.0
	_demo_slider.custom_minimum_size = Vector2(260, 0)
	_demo_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_demo_slider)

	grid.add_child(UIFactoryScript.label("进度", 12, UIThemeScript.TEXT_MAIN))
	_demo_progress = PixelProgressBarScript.new() as ProgressBar
	_demo_progress.name = "DemoProgress"
	_demo_progress.min_value = 0.0
	_demo_progress.max_value = DEMO_VALUE_MAX
	_demo_progress.value = 0.0
	_demo_progress.custom_minimum_size = Vector2(260, 0)
	_demo_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_demo_progress)

	grid.add_child(UIFactoryScript.label("数值", 12, UIThemeScript.TEXT_MAIN))
	_demo_spin = PixelSpinBoxScript.new() as SpinBox
	_demo_spin.name = "DemoSpinBox"
	_demo_spin.min_value = 0.0
	_demo_spin.max_value = DEMO_VALUE_MAX
	_demo_spin.step = 1.0
	_demo_spin.value = 0.0
	grid.add_child(_demo_spin)

	slot.add_child(grid)
	page.add_child(card)


## 右侧反馈卡片内容：状态行 + 富文本历史。
func _build_feedback_body(slot: Container) -> void:
	_status_label = UIFactoryScript.label("就绪", 13, UIThemeScript.TEXT_MAIN)
	_status_label.name = "StatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot.add_child(_status_label)

	_feedback_log = RichTextLabel.new()
	_feedback_log.name = "FeedbackLog"
	_feedback_log.bbcode_enabled = true
	_feedback_log.scroll_following = true
	_feedback_log.selection_enabled = true
	_feedback_log.focus_mode = Control.FOCUS_CLICK
	_feedback_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback_log.custom_minimum_size = Vector2(0, 220)
	_feedback_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_feedback_log.add_theme_font_size_override("normal_font_size", 12)
	_feedback_log.add_theme_color_override("default_color", Color(0.85, 0.9, 0.9))
	slot.add_child(_feedback_log)


## 统一接线：演示控件只在这里挂信号，回调只更新反馈/状态与联动，不改业务状态。
func _connect_signals() -> void:
	_primary_button.pressed.connect(_on_semantic_pressed.bind("主操作"))
	_secondary_button.pressed.connect(_on_semantic_pressed.bind("次操作"))
	_danger_button.pressed.connect(_on_semantic_pressed.bind("危险"))
	_icon_button.pressed.connect(_on_semantic_pressed.bind("图标"))
	_toggle_button.toggled.connect(_on_toggle_toggled)
	# _reset_button 的回调已由 UIFactory.button() 构造时绑定，这里不重复 connect。
	_demo_edit.text_changed.connect(_on_text_changed)
	_demo_edit.text_submitted.connect(_on_text_submitted)
	_demo_option.item_selected.connect(_on_option_selected)
	_demo_switch.toggled.connect(_on_switch_toggled)
	_demo_sfx_switch.toggled.connect(_on_sfx_toggled)
	_demo_slider.value_changed.connect(_on_slider_changed)
	_demo_spin.value_changed.connect(_on_spin_changed)
	_tabs.tab_changed.connect(_on_tab_changed)


## 生成一个 PixelButton（不依赖全局类名，统一走 preload 脚本 + 动态属性）。
func _make_pixel_button(
	label_text: String, semantic: int, icon_name: String = "", icon_size: int = 0
) -> Button:
	var btn: Button = PixelButtonScript.new()
	btn.text = label_text
	btn.set("semantic", semantic)
	if not icon_name.is_empty():
		btn.icon = UIThemeScript.icon(icon_name)
	if icon_size > 0:
		btn.set("icon_size", icon_size)
	return btn


## 实例化卡片 PackedScene 并写入短标题；内容由调用方通过 _card_slot 注入。
func _make_card(title_text: String, description_text: String) -> PanelContainer:
	var panel: PanelContainer = PixelPanelScene.instantiate() as PanelContainer
	panel.set("title", title_text)
	panel.set("description", description_text)
	return panel


func _card_slot(card: PanelContainer) -> Container:
	return card.call("get_content_slot") as Container


func _log_feedback(message: String) -> void:
	var stamp := Time.get_time_string_from_system()
	_feedback_lines.append(
		"[color=#%s]%s[/color] %s" % [UIThemeScript.ACCENT.to_html(false), stamp, message]
	)
	if _feedback_lines.size() > FEEDBACK_MAX_LINES:
		_feedback_lines.remove_at(0)
	_feedback_log.text = "\n".join(_feedback_lines)
	_feedback_log.scroll_to_line(_feedback_log.get_line_count() - 1)


func _on_semantic_pressed(which: String) -> void:
	_status_label.text = "按下「%s」" % which
	_log_feedback("按钮「%s」" % which)


func _on_toggle_toggled(toggled_on: bool) -> void:
	_status_label.text = "切换：%s" % ("开" if toggled_on else "关")
	_log_feedback("切换 → %s" % ("开" if toggled_on else "关"))


func _on_card_action_pressed() -> void:
	_status_label.text = "卡片操作"
	_log_feedback("卡片操作")


func _on_text_changed(new_text: String) -> void:
	var preview := new_text
	if preview.length() > 40:
		preview = preview.substr(0, 40) + "…"
	_preview_label.text = "值：%s" % (preview if not preview.is_empty() else "—")
	_status_label.text = "文本长度：%d" % new_text.length()


func _on_text_submitted(new_text: String) -> void:
	_status_label.text = "文本已提交"
	_log_feedback("文本提交「%s」" % new_text)


func _on_option_selected(index: int) -> void:
	var item_text := _demo_option.get_item_text(index)
	_status_label.text = "选项：%s" % item_text
	_log_feedback("选项 → %s" % item_text)


func _on_switch_toggled(toggled_on: bool) -> void:
	_danger_button.disabled = toggled_on
	_status_label.text = "危险按钮%s" % ("禁用" if toggled_on else "启用")
	_log_feedback("开关 → %s" % ("开" if toggled_on else "关"))


func _on_slider_changed(value: float) -> void:
	_demo_progress.value = value
	_demo_spin.set_value_no_signal(value)
	_status_label.text = "滑块：%d" % int(value)
	_log_feedback("滑块 → %d" % int(value))


func _on_spin_changed(value: float) -> void:
	_demo_slider.set_value_no_signal(value)
	_demo_progress.value = value
	_status_label.text = "数值：%d" % int(value)
	_log_feedback("数值 → %d" % int(value))


func _on_tab_changed(tab: int) -> void:
	var tab_title := _tabs.get_tab_title(tab)
	_status_label.text = "页签：%s" % tab_title
	_log_feedback("页签 → %s" % tab_title)


## 统一开关所有演示用 PixelButton 的悬停/点击音效（按脚本识别，不动其他按钮）。
func _apply_sfx_enabled(enabled: bool) -> void:
	for btn: Button in find_children("*", "Button", true, false):
		if btn.get_script() != PixelButtonScript:
			continue
		btn.set("hover_sfx_enabled", enabled)
		btn.set("click_sfx_enabled", enabled)


func _on_sfx_toggled(enabled: bool) -> void:
	_apply_sfx_enabled(enabled)
	_status_label.text = "音效：%s" % ("开" if enabled else "关")
	_log_feedback("音效 → %s" % ("开" if enabled else "关"))


## 重置所有演示状态：清空反馈、复位控件与联动值，并把焦点还给第一个按钮。
func _reset_demo() -> void:
	_feedback_lines.clear()
	_feedback_log.text = ""
	_demo_edit.text = ""
	_demo_option.select(0)
	_demo_switch.set_pressed_no_signal(false)
	_demo_sfx_switch.set_pressed_no_signal(true)
	_apply_sfx_enabled(true)
	_danger_button.disabled = false
	_toggle_button.set_pressed_no_signal(false)
	_demo_slider.set_value_no_signal(0.0)
	_demo_spin.set_value_no_signal(0.0)
	_demo_progress.value = 0.0
	_preview_label.text = "值：—"
	_tabs.current_tab = 0
	_status_label.text = "已重置"
	_log_feedback("重置")
	_primary_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
