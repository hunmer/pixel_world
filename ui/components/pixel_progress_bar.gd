## pixel_progress_bar.gd — 统一主题的 ProgressBar 薄包装
##
## 只接管 theme 与 Theme Type Variation；value/max_value、百分比显示、
## 原生 value_changed 信号全部保持 Godot 行为，不持有任何业务进度状态。
@tool
class_name PixelProgressBar
extends ProgressBar

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")


func _init() -> void:
	_refresh()


func _ready() -> void:
	_refresh()


## 幂等刷新：主题为空才创建，重复进树/重复 set 不会新增节点或信号。
func _refresh() -> void:
	if theme == null:
		theme = ComponentThemeScript.create()
	theme_type_variation = ComponentThemeScript.PROGRESS_BAR_VARIATION
