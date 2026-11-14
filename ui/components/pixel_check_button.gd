## pixel_check_button.gd — 统一主题的 CheckButton 薄包装
##
## 只接管 theme 与 Theme Type Variation；开关勾选图标、toggle_mode、
## 原生 toggled 信号与键盘切换全部保持 Godot 行为。
@tool
class_name PixelCheckButton
extends CheckButton

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")


func _init() -> void:
	_refresh()


func _ready() -> void:
	_refresh()


## 幂等刷新：主题为空才创建，重复进树/重复 set 不会新增节点或信号。
func _refresh() -> void:
	if theme == null:
		theme = ComponentThemeScript.create()
	theme_type_variation = ComponentThemeScript.CHECK_BUTTON_VARIATION
