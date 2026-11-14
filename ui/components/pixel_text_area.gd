## pixel_text_area.gd — 多行文本：保留 TextEdit 原生编辑/换行/只读行为
##
## 只做主题与占位符转发：原生 text、editable、read_only、换行、选区、
## text_changed 等信号全部沿用。@tool 下幂等刷新，不自动聚焦。
@tool
class_name PixelTextArea
extends TextEdit

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")

## 占位提示；为空时不显示。仅在没有文本时由原生 TextEdit 绘制。
@export var placeholder: String = "":
	set(value):
		placeholder = value
		placeholder_text = value


func _init() -> void:
	_refresh()


func _ready() -> void:
	_refresh()


## 主题刷新；幂等，不改变原生可编辑状态。
func _refresh() -> void:
	if theme == null:
		theme = ComponentThemeScript.create()
	theme_type_variation = ComponentThemeScript.TEXT_AREA_VARIATION
