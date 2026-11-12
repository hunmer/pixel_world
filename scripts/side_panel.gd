extends PanelContainer
## side_panel.gd — 右侧常驻多 Tab 面板
## 当前只有一个【输出】tab：接管 Panku native_logger 的日志流
## （logger_view.content_updated，格式与原左上角屏幕日志完全一致），
## 并把原生屏幕覆盖层切成 NeverShow——左上角不再显示日志。
## 后续新 tab 在 _build_tabs() 里向 _tabs 追加子容器即可。

const PANEL_WIDTH := 360.0

const HELP_BG := Color(0.035, 0.055, 0.075, 0.90)
const BORDER := Color(0.25, 0.37, 0.43, 0.88)
const TEXT_SECONDARY := Color(0.56, 0.68, 0.71)
const ACCENT := Color(0.40, 0.86, 0.76)

var _tabs: TabContainer
var _log_label: RichTextLabel

## PankuModuleNativeLogger 实例（duck-typed；Panku 不在时保持 null）
var _logger_module = null


func _ready() -> void:
	name = "SidePanel"
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -PANEL_WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _panel_style())
	_build_tabs()
	_attach_panku()


func _build_tabs() -> void:
	_tabs = TabContainer.new()
	_tabs.name = "SideTabs"
	_tabs.custom_minimum_size = Vector2(PANEL_WIDTH - 16.0, 0.0)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 13)
	var tab_panel := StyleBoxFlat.new()
	tab_panel.bg_color = Color(0.02, 0.03, 0.045, 0.55)
	tab_panel.border_color = BORDER
	tab_panel.border_width_left = 1
	tab_panel.border_width_right = 1
	tab_panel.border_width_bottom = 1
	_tabs.add_theme_stylebox_override("panel", tab_panel)
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
	var clear_btn := Button.new()
	clear_btn.name = "ClearLogBtn"
	clear_btn.text = "清空"
	clear_btn.tooltip_text = "清空日志（同步清空 Panku native_logger 缓冲）"
	clear_btn.add_theme_font_size_override("font_size", 12)
	clear_btn.pressed.connect(_clear_log)
	toolbar.add_child(clear_btn)
	var source_label := Label.new()
	source_label.name = "LogSource"
	source_label.text = "引擎日志 · info/warning/error"
	source_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	source_label.add_theme_font_size_override("font_size", 10)
	source_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	toolbar.add_child(source_label)

	# 日志正文：与原左上角覆盖层同一份 bbcode
	_log_label = RichTextLabel.new()
	_log_label.name = "LogLabel"
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.scroll_active = true
	_log_label.selection_enabled = true
	_log_label.shortcut_keys_enabled = false
	_log_label.focus_mode = Control.FOCUS_NONE
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.add_theme_font_size_override("normal_font_size", 12)
	_log_label.add_theme_color_override("default_color", Color(0.85, 0.9, 0.9))
	_log_label.text = "（等待日志…）"
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


func _on_log_content_updated(bbcode: String) -> void:
	_log_label.text = bbcode


func _clear_log() -> void:
	if _logger_module != null and is_instance_valid(_logger_module):
		# content_updated 会回传空文本并同步本面板
		_logger_module.logger_ui.clear_all()
	else:
		_log_label.text = ""


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
