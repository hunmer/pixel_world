## tests/ui_contract.gd — 统一 UI 主题（ui_theme.gd）与工厂（ui_factory.gd）契约
##
## 跑法：godot --headless --path . --script res://tests/ui_contract.gd
## 覆盖：
##   1. UITheme：配色常量关键值、flat_style/各面板样式构建器返回 StyleBoxFlat
##      且结构参数正确；style_button 三态 + focus 覆盖齐全。
##   2. UIFactory：button/label/shadow_label/outline_label/line_edit/
##      option_button/check_button/tab_container/add_tab/log_label/center_row
##      的类型、名称、默认配置与信号接线（add_tab 产 "<标题>Scroll/<标题>Tab"
##      结构，与 map_editor/battle_ui 既有契约一致）。
##   3. 迁移接线（静态源检查）：8 个迁移文件引用工厂/主题且不再保留被
##      删除的本地样式 helper 定义。
## 注：game_hud_contract.gd 在 HEAD 上本就无法以 --script 模式编译
## （Settings autoload 限制，见 hint_bar_contract.gd 头部注释），
## HUD 运行态断言由 Godot MCP runtime_assert_* 覆盖，不在本测试重复。

extends SceneTree

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _check_source(path: String, must_have: Array, must_not_have: Array) -> void:
	var src := FileAccess.open(path, FileAccess.READ)
	if src == null:
		_expect(false, "%s 可读" % path)
		return
	var text := src.get_as_text()
	src.close()
	for needle in must_have:
		_expect(text.contains(needle), "%s 应包含 %s" % [path, needle])
	for needle in must_not_have:
		_expect(not text.contains(needle), "%s 不应再包含 %s" % [path, needle])


func _run() -> void:
	# ---- 1. UITheme ----
	_expect(UIThemeScript.BG is Color and UIThemeScript.BG.a < 1.0,
		"BG 为半透明色")
	_expect(UIThemeScript.ACCENT is Color and UIThemeScript.ACCENT.g > 0.5,
		"ACCENT 为亮青色系")
	_expect(UIThemeScript.ICON_DIR.begins_with("res://addons/at-icons/"),
		"ICON_DIR 指向 at-icons 库")
	var flat := UIThemeScript.flat_style(UIThemeScript.BG, UIThemeScript.PANEL_BORDER)
	_expect(flat is StyleBoxFlat, "flat_style 返回 StyleBoxFlat")
	_expect(flat.bg_color == UIThemeScript.BG and flat.border_color == UIThemeScript.PANEL_BORDER,
		"flat_style 底色/边色按参数")
	_expect(flat.corner_radius_top_left == 6, "flat_style 默认圆角 6")
	_expect(flat.content_margin_left < 0.0, "flat_style 默认不设 content margin")
	var flat_m := UIThemeScript.flat_style(UIThemeScript.BG, UIThemeScript.PANEL_BORDER, 2, 4, 8.0)
	_expect(flat_m.border_width_top == 2 and flat_m.corner_radius_top_left == 4
		and flat_m.content_margin_left == 8.0,
		"flat_style 参数化边宽/圆角/边距")
	for builder: Callable in [
			UIThemeScript.overlay_panel_style, UIThemeScript.dock_panel_style,
			UIThemeScript.rail_style, UIThemeScript.float_panel_style,
			UIThemeScript.tab_panel_style, UIThemeScript.menu_panel_style]:
		var sb: StyleBoxFlat = builder.call()
		_expect(sb is StyleBoxFlat, "%s 返回 StyleBoxFlat" % builder.get_method())
	var menu_sb := UIThemeScript.menu_panel_style()
	_expect(menu_sb.bg_color.a < 0.95 and menu_sb.border_color == Color.WHITE,
		"menu_panel_style 半透明黑底白边（演出面板）")
	var dock_sb := UIThemeScript.dock_panel_style()
	_expect(dock_sb.bg_color == UIThemeScript.BG, "dock_panel_style 用主题 BG")

	# ---- 2. UIFactory.button ----
	var cb_called := [false]
	var btn := UIFactoryScript.button("确定", func(): cb_called[0] = true)
	_expect(btn is Button, "button 返回 Button")
	_expect(btn.text == "确定", "button 文本")
	btn.pressed.emit()
	_expect(cb_called[0], "button 信号接线")
	UIThemeScript.style_button(btn)
	_expect(btn.get_theme_stylebox("normal") is StyleBoxFlat, "button normal 样式")
	_expect(btn.get_theme_stylebox("hover") is StyleBoxFlat, "button hover 样式")
	_expect(btn.get_theme_stylebox("pressed") is StyleBoxFlat, "button pressed 样式")
	_expect(btn.get_theme_stylebox("disabled") is StyleBoxFlat, "button disabled 样式")
	_expect(btn.get_theme_stylebox("focus") is StyleBoxFlat, "button focus 样式")
	_expect(btn.get_theme_font_size("font_size") == 12, "button 字号 12")
	_expect(btn.get_theme_color("font_color") == UIThemeScript.TEXT_MAIN, "button 字色")
	_expect(btn.get_theme_color("font_focus_color") == UIThemeScript.ACCENT,
		"button focus 字色高亮")
	btn.queue_free()

	# ---- 3. UIFactory 其余控件 ----
	var lbl := UIFactoryScript.label("文本", 14, UIThemeScript.ACCENT)
	_expect(lbl is Label and lbl.text == "文本", "label 文本")
	_expect(lbl.get_theme_font_size("font_size") == 14, "label 字号")
	_expect(lbl.get_theme_color("font_color") == UIThemeScript.ACCENT, "label 字色")
	lbl.queue_free()

	var shadow := UIFactoryScript.shadow_label("阴影", 13, UIThemeScript.TEXT_MAIN)
	_expect(shadow is Label, "shadow_label 返回 Label")
	_expect(shadow.get_theme_constant("shadow_offset_x") == 1, "shadow_label 阴影偏移")
	shadow.queue_free()

	var outline := UIFactoryScript.outline_label("描边", 13, UIThemeScript.TOAST_COLOR, 4)
	_expect(outline is Label, "outline_label 返回 Label")
	_expect(outline.get_theme_constant("outline_size") == 4, "outline_label 描边宽度")
	_expect(outline.get_theme_color("font_color") == UIThemeScript.TOAST_COLOR,
		"outline_label 字色")
	outline.queue_free()

	var edit := UIFactoryScript.line_edit("占位")
	_expect(edit is LineEdit and edit.placeholder_text == "占位", "line_edit 占位文本")
	_expect(edit.clear_button_enabled, "line_edit 清除按钮")
	edit.queue_free()

	var opt := UIFactoryScript.option_button()
	_expect(opt is OptionButton, "option_button 返回 OptionButton")
	opt.queue_free()

	var check := UIFactoryScript.check_button("开关", "提示")
	_expect(check is CheckButton and check.text == "开关", "check_button 文本")
	_expect(check.tooltip_text == "提示", "check_button 提示")
	check.queue_free()

	# ---- 4. tab_container / add_tab / log_label / center_row ----
	var tabs := UIFactoryScript.tab_container("ToolTabs")
	_expect(tabs is TabContainer and tabs.name == "ToolTabs", "tab_container 名称")
	UIThemeScript.apply_tab_styles(tabs)
	_expect(tabs.get_theme_stylebox("panel") is StyleBoxFlat, "tab 面板底样式")
	var body := UIFactoryScript.add_tab(tabs, "地形", "terrain")
	_expect(tabs.get_tab_count() == 1, "add_tab 加入一页")
	_expect(tabs.get_tab_title(0) == "地形", "add_tab 页标题")
	_expect(tabs.has_node("地形Scroll"), "add_tab 产 <标题>Scroll")
	_expect(tabs.has_node("地形Scroll/地形Tab"), "add_tab 产 <标题>Tab")
	_expect(body is VBoxContainer
		and body.get_theme_constant("separation") == 6, "add_tab VBox separation 6")
	# 缺失图标名容错：不崩溃，返回 null Texture2D
	var missing_tex := UIThemeScript.icon("definitely-missing-icon")
	_expect(missing_tex == null or missing_tex is Texture2D,
		"icon 缺失名容错（Texture2D 或 null）")

	var log := UIFactoryScript.log_label()
	_expect(log is RichTextLabel and log.name == "LogLabel", "log_label 名称 LogLabel")
	_expect(log.bbcode_enabled and log.scroll_following, "log_label bbcode/滚动跟随")
	_expect(log.text == "（等待日志…）", "log_label 默认文本")
	_expect(log.get_theme_color("default_color") == Color(0.85, 0.9, 0.9),
		"log_label 默认字色")
	log.queue_free()

	var row := HBoxContainer.new()
	UIFactoryScript.center_row(row)
	_expect(row.get_child_count() == 0, "center_row 只调标志位、不改结构")
	var flag_child := Label.new()
	row.add_child(flag_child)
	UIFactoryScript.center_row(row)
	_expect(flag_child.size_flags_vertical == Control.SIZE_SHRINK_CENTER,
		"center_row 子控件垂直居中标志")
	row.queue_free()
	tabs.queue_free()

	# ---- 5. 迁移接线（静态源检查） ----
	_check_source("res://scripts/scenes/map_editor.gd",
		["UIFactoryScript.add_tab(", "UIThemeScript.overlay_panel_style("],
		["func _new_tab(", "func _btn_styles(", "func _panel_style("])
	_check_source("res://scripts/battle/battle_ui.gd",
		["UIFactoryScript.button(", "UIThemeScript.menu_panel_style("],
		["func _btn_styles(", "func _make_panel_style(", "func _sidebar_panel_style(",
			"func _detail_label(", "func _tab_styles("])
	_check_source("res://scripts/game_hud.gd",
		["UIThemeScript.rail_style()", "UIFactoryScript.option_button("],
		["func _label(", "func _panel_style(", "func _rail_style("])
	_check_source("res://scripts/side_panel.gd",
		["UIThemeScript.dock_panel_style(", "UIFactoryScript.log_label("],
		["func _panel_style("])
	_check_source("res://scripts/scenes/battle.gd",
		["UIFactoryScript.option_button(", "UIThemeScript.menu_panel_style("],
		["func _make_panel_style("])
	_check_source("res://scripts/battle/result_presentation.gd",
		["UIFactoryScript.button("],
		[])
	_check_source("res://scripts/scenes/title.gd",
		["UIFactoryScript.button("], [])
	_check_source("res://scripts/scenes/game_entry.gd",
		["UIFactoryScript.button("], [])
	_check_source("res://scripts/scenes/pixelfx_gallery.gd",
		["UIFactoryScript.option_button(", "UIFactoryScript.check_button("], [])

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("UI_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
