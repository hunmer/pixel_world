## pixel_grid.gd — 组件库网格布局容器：统一横向/纵向间距 token 的薄 GridContainer
##
## 列数 columns 保持 GridContainer 原生属性（脚本不声明同名 var，避免遮蔽失灵）；
## h_gap / v_gap 分别默认 ComponentTheme.SPACE_MD = 16，setter 非负夹紧且幂等；
## 不添加隐式子节点，不改主题与变体。
@tool
class_name PixelGrid
extends GridContainer

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")

## 默认横向间距：分组节奏 token 16。
const DEFAULT_H_GAP: int = ComponentThemeScript.SPACE_MD

## 默认纵向间距：分组节奏 token 16。
const DEFAULT_V_GAP: int = ComponentThemeScript.SPACE_MD

## 子项横向间距（像素）；负值夹紧为 0。
@export var h_gap: int = DEFAULT_H_GAP:
	set(value):
		h_gap = maxi(value, 0)
		_refresh_gaps()

## 子项纵向间距（像素）；负值夹紧为 0。
@export var v_gap: int = DEFAULT_V_GAP:
	set(value):
		v_gap = maxi(value, 0)
		_refresh_gaps()


func _init() -> void:
	_refresh_gaps()


func _ready() -> void:
	_refresh_gaps()


## 幂等写主题常量 override；不增删子节点、不连接信号。
func _refresh_gaps() -> void:
	add_theme_constant_override("h_separation", h_gap)
	add_theme_constant_override("v_separation", v_gap)
