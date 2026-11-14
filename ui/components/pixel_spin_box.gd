## pixel_spin_box.gd — 统一主题的 SpinBox 薄包装
##
## 自身只接管 theme 与 Theme Type Variation；内部输入框复用 PixelLineEdit
## 变体，使数值编辑与文本输入外观一致。范围、步进、上下按钮、键盘输入和
## 原生 value_changed 信号全部保持 Godot 行为。
@tool
class_name PixelSpinBox
extends SpinBox

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")


func _init() -> void:
	_refresh()


func _ready() -> void:
	_refresh()


## 幂等刷新：主题为空才创建；内部 LineEdit 与自身共享同一 Theme 实例。
func _refresh() -> void:
	if theme == null:
		theme = ComponentThemeScript.create()
	theme_type_variation = ComponentThemeScript.SPIN_BOX_VARIATION
	var line_edit: LineEdit = get_line_edit()
	if line_edit != null:
		line_edit.theme = theme
		line_edit.theme_type_variation = ComponentThemeScript.LINE_EDIT_VARIATION
