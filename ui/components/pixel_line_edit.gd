## pixel_line_edit.gd — 统一主题的 LineEdit 薄包装
##
## 只接管 theme 与 Theme Type Variation；文本编辑、占位符、选中、快捷键、
## 原生 text_changed / text_submitted 信号全部保持 Godot 行为，不复制业务状态。
@tool
class_name PixelLineEdit
extends LineEdit

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")


func _init() -> void:
	_refresh()


func _ready() -> void:
	_refresh()


## 幂等刷新：主题为空才创建，重复进树/重复 set 不会新增节点或信号。
func _refresh() -> void:
	if theme == null:
		theme = ComponentThemeScript.create()
	theme_type_variation = ComponentThemeScript.LINE_EDIT_VARIATION
