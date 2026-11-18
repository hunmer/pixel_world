## scripts/scenes/ui_component_gallery.gd — UI 组件库演示画廊（装配层）
##
## 只展示真实组件、短名称、必要操作标签与真实值；API、继承、资源路径与用法
## 说明全部放 ui/README.md，界面不写教学文字、帮助页、描述段落或说明 tooltip。
##
## 页签：按钮 / 卡片 / 输入 / 数值 / 媒体 / 菜单 / 布局 / 鼠标 / 边框 / 名牌 / 头像 / 战棋。
## 本文件只负责装配与公共设施：标题行、页签容器、右侧反馈卡片、状态/日志公开面、
## GameCursor 运行时解析、PixelButton 音效全局开关与重置协调；各页签内容拆分到
## scripts/ui_gallery/ 能力模块（RefCounted，setup() 注入本画廊作 duck-typed 宿主）：
##   - UiGalleryBasicPages：基础六页（按钮/卡片/输入/数值/媒体/菜单）+ 演示回调；
##   - UiGalleryLayoutPage：六个 Pixel 布局容器真实摆位；
##   - UiGalleryCursorPage：GameCursor 指针库 + 箭头三色风格；
##   - UiGalleryFramePages：边框/名牌/头像三页（框体系组件）；
##   - UiGalleryBattlePage：战棋界面（story/10_ui_ux.md 还原）。
## 共享卡片/按钮工具在 UiGalleryWidgets。F6 独立运行，不依赖战斗参数，不修改默认启动；ESC 退出。
extends Control

const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const PixelButtonScript = preload("res://ui/components/pixel_button.gd")
const PixelTabsScript = preload("res://ui/components/pixel_tabs.gd")

## 反馈面板最多保留的历史条数（超出丢弃最早一条，避免长时间点击后无限增长）。
const FEEDBACK_MAX_LINES := 60
## 右侧反馈卡片的窄窗口最小宽度。
const SIDE_MIN_WIDTH := 360

var _tabs: TabContainer
var _feedback_log: RichTextLabel
var _status_label: Label
var _feedback_lines: PackedStringArray = PackedStringArray()
var _reset_button: Button

## GameCursor autoload 的运行时引用：契约用 --script(SceneTree) 模式运行时注册单例，
## 但编译期不注册单例标识符，直接写 GameCursor.xxx 会让画廊在该模式下无法编译。
## 一律经 gc() 运行时解析，并用 call/get 做动态访问（静态类型 Node 上无这些成员）。
var _game_cursor: Node = null

## 各页签能力模块（UiGalleryWidgets 为纯静态工具，无需实例）。
var _basic_pages := UiGalleryBasicPages.new()
var _layout_page := UiGalleryLayoutPage.new()
var _cursor_page := UiGalleryCursorPage.new()
var _frame_pages := UiGalleryFramePages.new()
var _battle_page := UiGalleryBattlePage.new()


func _ready() -> void:
	_build_ui()
	_tabs.tab_changed.connect(_on_tab_changed)
	_status_label.text = "就绪"
	_basic_pages.primary_button.grab_focus()


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

	_basic_pages.setup(self)
	_layout_page.setup(self)
	_cursor_page.setup(self)
	_frame_pages.setup(self)
	_battle_page.setup(self)
	_basic_pages.build()
	_layout_page.build()
	_cursor_page.build()
	_frame_pages.build()
	_battle_page.build()

	var feedback_card := UiGalleryWidgets.make_card("反馈", "")
	feedback_card.custom_minimum_size = Vector2(SIDE_MIN_WIDTH, 0)
	feedback_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feedback_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(feedback_card)
	_build_feedback_body(UiGalleryWidgets.card_slot(feedback_card))


## 标题行：短标题 + 重置按钮。
func _build_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var title := UIFactoryScript.outline_label("UI 组件库", ComponentThemeScript.FONT_DISPLAY, Color.WHITE, 6)
	row.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_reset_button = UIFactoryScript.button("重置", _reset_demo)
	_reset_button.name = "ResetButton"
	_reset_button.custom_minimum_size = Vector2(96, 36)
	row.add_child(_reset_button)
	return row


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
	_feedback_log.add_theme_font_size_override("normal_font_size", ComponentThemeScript.FONT_CAPTION)
	_feedback_log.add_theme_color_override("default_color", Color(0.85, 0.9, 0.9))
	slot.add_child(_feedback_log)


# ---------------------------------------------------------------------------
# 宿主公开面：能力模块经 setup() 拿到本画廊，全部经这些入口操作公共设施。
# ---------------------------------------------------------------------------

## 新增一个画廊页签（PixelTabs.add_pixel_tab 外壳），返回页内容容器。
func add_gallery_tab(title_text: String) -> VBoxContainer:
	return _tabs.call("add_pixel_tab", title_text) as VBoxContainer


## 更新右侧状态行文本。
func set_status(text: String) -> void:
	_status_label.text = text


## 追加一条反馈历史（带时间戳与着色，超上限丢弃最早一条）。
func log_feedback(message: String) -> void:
	var stamp := Time.get_time_string_from_system()
	_feedback_lines.append(
		"[color=#%s]%s[/color] %s" % [UIThemeScript.ACCENT.to_html(false), stamp, message]
	)
	if _feedback_lines.size() > FEEDBACK_MAX_LINES:
		_feedback_lines.remove_at(0)
	_feedback_log.text = "\n".join(_feedback_lines)
	_feedback_log.scroll_to_line(_feedback_log.get_line_count() - 1)


## GameCursor 单例运行时解析（可能缺席，调用方需判空）。
func gc() -> Node:
	if _game_cursor == null:
		_game_cursor = get_tree().root.get_node_or_null("GameCursor")
	return _game_cursor


## 统一开关所有演示用 PixelButton 的悬停/点击音效（按脚本识别，不动其他按钮）。
func apply_sfx_enabled(enabled: bool) -> void:
	for btn: Button in find_children("*", "Button", true, false):
		if btn.get_script() != PixelButtonScript:
			continue
		btn.set("hover_sfx_enabled", enabled)
		btn.set("click_sfx_enabled", enabled)


# ---------------------------------------------------------------------------
# 演示协调
# ---------------------------------------------------------------------------

func _on_tab_changed(tab: int) -> void:
	var tab_title := _tabs.get_tab_title(tab)
	_status_label.text = "页签：%s" % tab_title
	log_feedback("页签 → %s" % tab_title)


## 重置所有演示状态：清空反馈、按原顺序复位各模块，并把焦点还给第一个按钮。
func _reset_demo() -> void:
	_feedback_lines.clear()
	_feedback_log.text = ""
	_basic_pages.reset()
	apply_sfx_enabled(true)
	_cursor_page.reset()
	_frame_pages.reset()
	_battle_page.reset()
	_tabs.current_tab = 0
	_status_label.text = "已重置"
	log_feedback("重置")
	_basic_pages.primary_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
