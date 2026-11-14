## pixel_tabs.gd — 组件库标签页：PixelTabs 变体 + 内部 TabBar 主题
##
## 继承 TabContainer，页面仍是原生 add_child 方式；只幂等应用 Theme 变体，
## 不拦截 UIFactory.add_tab 等既有页构造逻辑（子类实例可直接传入）。
@tool
class_name PixelTabs
extends TabContainer

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")


func _init() -> void:
	# new() 后即带主题，不依赖入树；_ready 再刷新一次保证 @tool 预览一致。
	_refresh()


func _ready() -> void:
	_refresh()


## 幂等应用 PixelTabs 变体；不增删页面，保持 TabContainer 原生页面行为。
func _refresh() -> void:
	if theme == null:
		theme = ComponentThemeScript.create()
	theme_type_variation = ComponentThemeScript.TABS_VARIATION


## 与 UIFactory.add_tab 同构的便利入口（页节点仍是 "<标题>Scroll / <标题>Tab"）。
func add_pixel_tab(tab_title: String, icon_name: String = "") -> VBoxContainer:
	return UIFactoryScript.add_tab(self, tab_title, icon_name) as VBoxContainer
