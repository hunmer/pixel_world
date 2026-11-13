extends PanelContainer
## side_panel.gd — 右侧常驻多 Tab 面板
## 当前只有一个【输出】tab：接管 Panku native_logger 的日志流
## （logger_view.content_updated，格式与原左上角屏幕日志完全一致），
## 并把原生屏幕覆盖层切成 NeverShow——左上角不再显示日志。
## 后续新 tab 在 _build_tabs() 里向 _tabs 追加子容器即可。

const PANEL_WIDTH := 360.0

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")

## 配色常量统一取自 ui_theme.gd（本文件别名保持既有引用不变）。
const HELP_BG := UIThemeScript.HELP_BG
const BORDER := UIThemeScript.BORDER
const TEXT_SECONDARY := UIThemeScript.TEXT_SECONDARY
const ACCENT := UIThemeScript.ACCENT

var _tabs: TabContainer
var _log_label: RichTextLabel
var _pending_log_bbcode := ""
var _log_update_pending := false

## PankuModuleNativeLogger 实例（duck-typed；Panku 不在时保持 null）
var _logger_module = null


func _ready() -> void:
	name = "SidePanel"
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -PANEL_WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UIThemeScript.dock_panel_style())
	_build_tabs()
	_attach_panku()


func _build_tabs() -> void:
	# Tab 样式统一走 ui_theme（页签三态与面板底）
	_tabs = TabContainer.new()
	_tabs.name = "SideTabs"
	_tabs.custom_minimum_size = Vector2(PANEL_WIDTH - 16.0, 0.0)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 13)
	_tabs.add_theme_stylebox_override("panel", UIThemeScript.tab_panel_style())
	UIThemeScript.apply_tab_styles(_tabs)
	add_child(_tabs)

	var output_tab := VBoxContainer.new()
	output_tab.name = "OutputTab"
	output_tab.add_theme_constant_override("separation", 4)
	_tabs.add_child(output_tab)
	_tabs.set_tab_title(0, "输出")

	# 工具行：清空按钮
	var toolbar := HBoxContainer.new()
	toolbar.name = "OutputToolbar"
	toolbar.add_theme_constant_override("separation", 8)
	output_tab.add_child(toolbar)
	var clear_btn := UIFactoryScript.button("清空", _clear_log)
	clear_btn.name = "ClearLogBtn"
	clear_btn.tooltip_text = "清空日志（同步清空 Panku native_logger 缓冲）"
	toolbar.add_child(clear_btn)
	var source_label := UIFactoryScript.label("引擎日志 · info/warning/error", 10, TEXT_SECONDARY)
	source_label.name = "LogSource"
	source_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	toolbar.add_child(source_label)

	# 日志正文：与原左上角覆盖层同一份 bbcode（统一走 ui_factory.log_label）
	_log_label = UIFactoryScript.log_label()
	_log_label.scroll_active = true
	_log_label.context_menu_enabled = true
	_log_label.shortcut_keys_enabled = true
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output_tab.add_child(_log_label)


## 接管 Panku native_logger：关掉原左上角覆盖层，镜像它的日志内容
func _attach_panku() -> void:
	var panku := get_node_or_null("/root/Panku")
	if panku == null:
		_log_label.text = "（Panku 未加载，无日志源）"
		return
	var module_manager = panku.get("module_manager")
	if module_manager == null or not module_manager.has_method("get_module"):
		return
	if not module_manager.has_module("native_logger"):
		return
	_logger_module = module_manager.get_module("native_logger")

	# 1) 左上角屏幕日志关闭（仅本会话；不写回 panku 持久化配置）
	_logger_module.set_overlay_display_mode(
		PankuModuleNativeLogger.ScreenOverlayDisplayMode.NeverShow
	)
	# 2) 镜像 logger_view 的完整 bbcode（自带去重 / 条数上限 / 时间戳着色）
	var logger_ui: Node = _logger_module.logger_ui
	logger_ui.content_updated.connect(_on_log_content_updated)
	if _logger_module.native_logs_monitor == null \
			or _logger_module.native_logs_monitor.get("godot_log") == null:
		_log_label.text = "（引擎文件日志未开启：debug/file_logging，无日志流入）"
	# L1 埋点：接管成功与否写一条日志（会立刻流回本面板）
	print("[side_panel] 已接管 native_logger 屏幕日志（左上角覆盖关闭）")


func _process(_delta: float) -> void:
	# 拖选时保留最新全量日志，选区清除后再刷新，避免重写文本打断选择。
	if _log_update_pending and not _log_selection_active():
		_log_label.text = _pending_log_bbcode
		_log_update_pending = false


func _log_selection_active() -> bool:
	return not _log_label.get_selected_text().is_empty() \
		or (_log_label.has_focus() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))


func _on_log_content_updated(bbcode: String) -> void:
	if _log_selection_active():
		_pending_log_bbcode = bbcode
		_log_update_pending = true
		return
	_log_label.text = bbcode


func _clear_log() -> void:
	_log_label.deselect()
	if _logger_module != null and is_instance_valid(_logger_module):
		# content_updated 会回传空文本并同步本面板
		_logger_module.logger_ui.clear_all()
	else:
		_log_label.text = ""
