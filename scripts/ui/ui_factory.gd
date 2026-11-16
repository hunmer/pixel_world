## ui_factory.gd — 统一控件工厂：按钮 / 输入框 / 下拉 / Tab / 日志 / 通用行
##
## 从各场景重复「裸 new + 逐行 override」的代码抽出的唯一权威版本。
## 全静态方法，直接 UIFactory.xxx(...) 调用。
## 契约注意（tests 按路径/名字断言）：
##   - add_tab 生成 "<标题>Scroll / <标题>Tab" 两级节点，VBox separation 6
##   - log_label 名字固定 "LogLabel"（side_panel / battle_ui 共用）
##   - 按钮族（button/option_button/check_button）一律由 ui/components 像素组件
##     创建（PixelButton/PixelOptionButton/PixelCheckButton），返回类型仍是
##     Button/OptionButton/CheckButton 基类注解（子类满足，调用方零改动）。
## 样式一律走 ui_theme.gd；工厂只管「怎么造」，主题只管「长什么样」。
## 主题兼容：button() 在组件之上保留 UITheme.style_button 的逐控件 override
## （优先级高于组件主题/variation），像素级维持既有观感；option/check 此前
## 是引擎默认观感，统一为组件 pixel 变体。
## 音效兼容：Sfx autoload（game_sfx.gd）对每个 BaseButton 挂 pressed/hover
## 全局音效，组件自带 HoverSfx/ClickSfx 会与之叠加成双声 → 工厂统一禁用
## 组件自带音效，仅保留全局钩子发声。
class_name UIFactory
extends RefCounted

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const PixelButtonScript = preload("res://ui/components/pixel_button.gd")
const PixelOptionButtonScript = preload("res://ui/components/pixel_option_button.gd")
const PixelCheckButtonScript = preload("res://ui/components/pixel_check_button.gd")


## 主题三态按钮；cb 非空时接 pressed 信号，icon_name 非空时设置图标。
## 由 ui/components PixelButton 创建（统一样式组件）；组件自带音效禁用，
## 交给全局 Sfx autoload 挂接；style_button override 叠加维持既有观感。
## styled=false 时不叠加 style_button 逐控件 override，保持 PixelButton
## 组件自身主题原观感（编辑器 tile/工具条等按组件变体主题直用的调用方）。
static func button(
	text := "", cb := Callable(), icon_name := "", styled := true
) -> Button:
	var b := PixelButtonScript.new()
	b.hover_sfx_enabled = false
	b.click_sfx_enabled = false
	b.text = text
	if styled:
		UIThemeScript.style_button(b)
	if cb.is_valid():
		b.pressed.connect(cb)
	var tex: Texture2D = UIThemeScript.icon(icon_name)
	if tex != null:
		b.icon = tex
	return b


## 普通文字标签（font_size + 颜色）。
static func label(text := "", font_size := 12, color := UIThemeScript.TEXT_DIM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## 带阴影标签（HUD 标题类）。
static func shadow_label(
	text := "", font_size := 12, color := UIThemeScript.TEXT_MAIN
) -> Label:
	var l := label(text, font_size, color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


## 带黑描边标签（战斗详情 / Toast / 飘字；outline 默认 3 同 battle_ui._detail_label）。
static func outline_label(
	text := "", font_size := 12, color := Color.WHITE, outline := 3
) -> Label:
	var l := label(text, font_size, color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	return l


## 输入框（占位符可选）。
static func line_edit(placeholder := "") -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.clear_button_enabled = true
	return e


## 下拉框（由调用方 add_item / 设置最小宽度）。
## 由 ui/components PixelOptionButton 创建（pixel 变体主题）。
static func option_button() -> OptionButton:
	return PixelOptionButtonScript.new()


## 开关勾选按钮。由 ui/components PixelCheckButton 创建（pixel 变体主题）。
static func check_button(text := "", tooltip := "") -> CheckButton:
	var c := PixelCheckButtonScript.new()
	c.text = text
	c.tooltip_text = tooltip
	return c


## 已应用统一样式的 TabContainer。
static func tab_container(name := "Tabs") -> TabContainer:
	var tabs := TabContainer.new()
	tabs.name = name
	tabs.add_theme_stylebox_override("panel", UIThemeScript.tab_panel_style())
	UIThemeScript.apply_tab_styles(tabs)
	tabs.add_theme_font_size_override("font_size", 13)
	return tabs


## 向 TabContainer 追加一页：纵向滚动 + VBox，节点名 "<标题>Scroll / <标题>Tab"。
## 返回 VBox（调用方往里塞内容）；icon_name 非空时给该页设图标。
static func add_tab(
	tabs: TabContainer, title: String, icon_name := ""
) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title + "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)
	var tab := VBoxContainer.new()
	tab.name = title + "Tab"
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("separation", 6)
	scroll.add_child(tab)
	var idx := tabs.get_tab_count() - 1
	tabs.set_tab_title(idx, title)
	if not icon_name.is_empty():
		var tex: Texture2D = UIThemeScript.icon(icon_name)
		if tex != null:
			tabs.set_tab_icon(idx, tex)
	return tab


## Panku 控制台日志镜像标签（side_panel.gd 与 battle_ui.gd 完全相同的配置）。
## 名字固定 "LogLabel"。
static func log_label() -> RichTextLabel:
	var l := RichTextLabel.new()
	l.name = "LogLabel"
	l.bbcode_enabled = true
	l.scroll_following = true
	l.selection_enabled = true
	l.focus_mode = Control.FOCUS_CLICK
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("normal_font_size", 12)
	l.add_theme_color_override("default_color", Color(0.85, 0.9, 0.9))
	l.text = "（等待日志…）"
	return l


## 让 Container 的子控件垂直居中（各表单行共用的小工具）。
static func center_row(row: Control) -> void:
	for child in row.get_children():
		if child is Control:
			(child as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
