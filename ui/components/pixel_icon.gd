## pixel_icon.gd — 图标：固定尺寸 + 着色的 TextureRect
##
## 继承 TextureRect，纹理走原生 texture 属性（编辑器里可直接拖入项目图标）。
## icon_size 统一最小尺寸并保持等比缩放；icon_color 通过 modulate 着色，
## 不改纹理本身。@tool 下幂等刷新。
@tool
class_name PixelIcon
extends TextureRect

## 图标尺寸（像素），同时作为最小尺寸与等比缩放基准。
@export_range(8, 128, 1) var icon_size: int = 24:
	set(value):
		icon_size = clampi(value, 8, 128)
		_refresh()

## 图标着色；默认白色不改变纹理。
@export var icon_color: Color = Color.WHITE:
	set(value):
		icon_color = value
		_refresh()


func _init() -> void:
	_refresh()


func _ready() -> void:
	_refresh()


## 尺寸与着色刷新；幂等，不创建子节点。
func _refresh() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	custom_minimum_size = Vector2(icon_size, icon_size)
	modulate = icon_color
