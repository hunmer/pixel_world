## pixel_option_button.gd — 统一主题的 OptionButton 薄包装
##
## 只接管 theme 与 Theme Type Variation；选项管理、弹出菜单、键盘选择与
## 原生 item_selected / item_focused 信号全部保持 Godot 行为。
@tool
class_name PixelOptionButton
extends OptionButton

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")


func _init() -> void:
	_refresh()


func _ready() -> void:
	_refresh()


## 幂等刷新：主题为空才创建，重复进树/重复 set 不会新增节点或信号。
func _refresh() -> void:
	if theme == null:
		theme = ComponentThemeScript.create()
	theme_type_variation = ComponentThemeScript.OPTION_BUTTON_VARIATION
