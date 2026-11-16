## pixel_tabs_vertical.gd — 组件库垂直页签：左侧竖排页签条 + 右侧内容区
##
## 引擎 TabContainer 只有 Top/Bottom 横排页签（tabs_position 枚举实测无垂直值），
## 垂直模式由本组件组合实现：内部 PixelTabs（tabs_visible=false，页面占满整个
## 内容区，add_tab 语义与 "<标题>Scroll/<标题>Tab" 节点契约不变）+ 左侧 TabStrip
## （VBox 内 PixelButton toggle × ButtonGroup，选中态右缘 ACCENT 2px，样式走
## UITheme.apply_vertical_tab_button_styles）。
##
## 对外：tabs 属性暴露内部 TabContainer —— 调用方可继续 UIFactory.add_tab /
## current_tab / get_tab_title / tab_changed 等 TabContainer 全部契约；页签条按钮
## 通过 tabs.child_entered_tree/exiting_tree 自动重建（延迟到帧末，等 add_tab
## 的 set_tab_title/set_tab_icon 完成），无需手动同步。
@tool
class_name PixelTabsVertical
extends HBoxContainer

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const PixelButtonScript = preload("res://ui/components/pixel_button.gd")
const PixelTabsScript = preload("res://ui/components/pixel_tabs.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")

## 页签条最小宽度：图标 18 + 两字页签名 + 内容边距；更长标题 clip_text 截断。
const STRIP_MIN_WIDTH := 72
## 页签条按钮最小高度（与横排页签头 31px 观感一致的点击舒适区）。
const STRIP_BUTTON_MIN_HEIGHT := 34

## 内部 TabContainer（tabs_visible=false）；调用方经它加页/接 tab_changed。
var tabs: TabContainer
## 左侧竖排页签条容器；调用方可改 custom_minimum_size 调宽度。
var strip: VBoxContainer

var _group := ButtonGroup.new()


func _init() -> void:
	add_theme_constant_override("separation", 0)
	strip = VBoxContainer.new()
	strip.name = "TabStrip"
	strip.custom_minimum_size = Vector2(STRIP_MIN_WIDTH, 0)
	strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	strip.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	add_child(strip)

	tabs = PixelTabsScript.new()
	tabs.name = "Tabs"
	tabs.tabs_visible = false
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)

	tabs.tab_changed.connect(_on_tab_changed)
	# add_tab 在 add_child 之后才 set_tab_title/set_tab_icon，立即重建会拿到
	# 默认页签名（节点名）；延迟到帧末重建保证标题/图标就绪。
	tabs.child_entered_tree.connect(func(_node: Node) -> void: _rebuild_strip.call_deferred())
	tabs.child_exiting_tree.connect(func(_node: Node) -> void: _rebuild_strip.call_deferred())


## 与 PixelTabs.add_pixel_tab 同构的便利入口（页节点仍是 "<标题>Scroll/<标题>Tab"）。
func add_pixel_tab(tab_title: String, icon_name: String = "") -> VBoxContainer:
	var page := UIFactoryScript.add_tab(tabs, tab_title, icon_name) as VBoxContainer
	_rebuild_strip.call_deferred()
	return page


## 按内部 tabs 当前页签重建竖排按钮（标题/图标/三态样式/单选组）。
func _rebuild_strip() -> void:
	for child in strip.get_children():
		strip.remove_child(child)
		child.queue_free()
	for i in range(tabs.get_tab_count()):
		var btn: Button = PixelButtonScript.new()
		btn.name = "TabBtn%d" % i
		btn.toggle_mode = true
		btn.button_group = _group
		btn.text = tabs.get_tab_title(i)
		btn.icon = tabs.get_tab_icon(i)
		btn.clip_text = true
		btn.custom_minimum_size = Vector2(0, STRIP_BUTTON_MIN_HEIGHT)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 与 UIFactory.button 同因：游戏内 Sfx autoload 已全局接管按钮音效，
		# 组件自带音效关闭，防止双声。
		btn.hover_sfx_enabled = false
		btn.click_sfx_enabled = false
		UIThemeScript.apply_vertical_tab_button_styles(btn)
		var idx := i
		btn.pressed.connect(func() -> void: tabs.current_tab = idx)
		# 点击已选中的 toggle 按钮会先把它弹起（引擎不会为相同 current_tab
		# 重发 tab_changed），此处把选中态按回去，避免页签条视觉漂移。
		btn.toggled.connect(func(on: bool) -> void:
			if not on and tabs.current_tab == idx:
				btn.set_pressed_no_signal(true))
		strip.add_child(btn)
	_sync_strip(tabs.current_tab)


## tab_changed → 页签条单选同步（不回环：set_pressed_no_signal 不发信号）。
func _on_tab_changed(index: int) -> void:
	_sync_strip(index)


func _sync_strip(index: int) -> void:
	var buttons := strip.get_children()
	for i in range(buttons.size()):
		var btn := buttons[i] as BaseButton
		if btn != null:
			btn.set_pressed_no_signal(i == index)
