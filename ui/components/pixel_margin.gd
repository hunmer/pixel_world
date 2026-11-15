## pixel_margin.gd — 组件库边距容器：统一内容边距 token 的薄 MarginContainer
##
## 四向 margin 独立可导出（默认 ComponentTheme.SPACE_LG = 24），另提供
## set_margin_all() 一次写四向；setter 非负夹紧且幂等；不添加隐式子节点，
## 不改主题与变体。
@tool
class_name PixelMargin
extends MarginContainer

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")

## 默认单边边距：页面节奏 token 24。
const DEFAULT_MARGIN: int = ComponentThemeScript.SPACE_LG

## 左边距（像素）；负值夹紧为 0。
@export var margin_left_v: int = DEFAULT_MARGIN:
	set(value):
		margin_left_v = maxi(value, 0)
		_refresh_margins()

## 上边距（像素）；负值夹紧为 0。
@export var margin_top_v: int = DEFAULT_MARGIN:
	set(value):
		margin_top_v = maxi(value, 0)
		_refresh_margins()

## 右边距（像素）；负值夹紧为 0。
@export var margin_right_v: int = DEFAULT_MARGIN:
	set(value):
		margin_right_v = maxi(value, 0)
		_refresh_margins()

## 下边距（像素）；负值夹紧为 0。
@export var margin_bottom_v: int = DEFAULT_MARGIN:
	set(value):
		margin_bottom_v = maxi(value, 0)
		_refresh_margins()


func _init() -> void:
	_refresh_margins()


func _ready() -> void:
	_refresh_margins()


## 一次写四向相同边距；等价于逐个赋值，保持幂等夹紧语义。
func set_margin_all(value: int) -> void:
	var clamped := maxi(value, 0)
	margin_left_v = clamped
	margin_top_v = clamped
	margin_right_v = clamped
	margin_bottom_v = clamped


## 幂等写主题常量 override；不增删子节点、不连接信号。
func _refresh_margins() -> void:
	add_theme_constant_override("margin_left", margin_left_v)
	add_theme_constant_override("margin_top", margin_top_v)
	add_theme_constant_override("margin_right", margin_right_v)
	add_theme_constant_override("margin_bottom", margin_bottom_v)
