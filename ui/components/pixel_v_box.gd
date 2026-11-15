## pixel_v_box.gd — 组件库纵向布局容器：集中间距 token 的薄 VBoxContainer
##
## 只把子项纵向间距收敛为可导出的 gap（默认 ComponentTheme.SPACE_MD = 16），
## setter 非负夹紧且幂等（重复设置同值/重复进树结果一致）；不添加隐式子节点，
## 不改主题与变体（容器无视觉承载），锚点/Expand Fill 等全部保留原生行为。
@tool
class_name PixelVBox
extends VBoxContainer

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")

## 默认纵向间距：分组节奏 token 16。
const DEFAULT_GAP: int = ComponentThemeScript.SPACE_MD

## 子项纵向间距（像素）；负值夹紧为 0。
@export var gap: int = DEFAULT_GAP:
	set(value):
		gap = maxi(value, 0)
		_refresh_gap()


func _init() -> void:
	_refresh_gap()


func _ready() -> void:
	_refresh_gap()


## 幂等写主题常量 override；不增删子节点、不连接信号。
func _refresh_gap() -> void:
	add_theme_constant_override("separation", gap)
