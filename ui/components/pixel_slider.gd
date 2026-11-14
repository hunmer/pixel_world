## pixel_slider.gd — 统一主题的 HSlider 薄包装
##
## 只接管 theme 与 Theme Type Variation；min/max/step/page、拖拽、滚轮、
## 键盘步进与原生 value_changed 信号全部保持 Godot 行为。
@tool
class_name PixelSlider
extends HSlider

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")


func _init() -> void:
	_refresh()


func _ready() -> void:
	_refresh()


## 幂等刷新：主题为空才创建，重复进树/重复 set 不会新增节点或信号。
func _refresh() -> void:
	if theme == null:
		theme = ComponentThemeScript.create()
	theme_type_variation = ComponentThemeScript.SLIDER_VARIATION
