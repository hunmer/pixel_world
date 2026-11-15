## pixel_scroll.gd — 组件库滚动容器：默认仅纵向滚动的薄 ScrollContainer
##
## 默认形态：横向滚动禁用（SCROLL_MODE_DISABLED）、纵向自动（SCROLL_MODE_AUTO）、
## 双向 size_flags = SIZE_EXPAND_FILL（放进 HBox/VBox/Grid 才能撑满）、
## follow_focus = true（键盘导航跟随焦点）。_init 与 _ready 双写保证幂等；
## 不添加隐式子节点，不改主题与变体。
@tool
class_name PixelScroll
extends ScrollContainer


func _init() -> void:
	_apply_defaults()


func _ready() -> void:
	_apply_defaults()


## 幂等写默认滚动/尺寸/焦点行为；不增删子节点、不连接信号。
func _apply_defaults() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	follow_focus = true
