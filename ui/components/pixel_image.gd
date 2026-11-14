## pixel_image.gd — 图片容器：卡片面 + 等比适配/裁切纹理
##
## 继承 PanelContainer，内部固定一个 TextureRect（节点名 Image）。主题走
## ComponentTheme.IMAGE_VARIATION（卡片面、内容边距 0），纹理适配由 stretch_mode
## 控制：KEEP_ASPECT_CENTERED（等比完整显示）或 KEEP_ASPECT_COVERED（等比铺满并裁切）。
## @tool 下只刷新属性，不加载网络或外部资源；重复进树不重复建节点。
@tool
class_name PixelImage
extends PanelContainer

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")

## 内部纹理节点名（契约按此路径断言）。
const IMAGE_NODE_NAME: StringName = &"Image"

## 显示的纹理；为空时只占位不报错。
@export var texture: Texture2D = null:
	set(value):
		texture = value
		_refresh_content()

## 纹理适配方式；默认等比完整显示。
@export var stretch_mode: TextureRect.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
	set(value):
		stretch_mode = value
		_refresh_content()

## 图片区域最小尺寸（像素）。
@export var image_size: Vector2i = Vector2i(320, 180):
	set(value):
		image_size = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		_refresh_content()

var _image: TextureRect


func _init() -> void:
	_refresh()
	_refresh_content()


func _ready() -> void:
	_refresh()
	_refresh_content()


## 主题与结构刷新；幂等，可在 @tool 下反复调用。
func _refresh() -> void:
	if theme == null:
		theme = ComponentThemeScript.create()
	theme_type_variation = ComponentThemeScript.IMAGE_VARIATION
	_ensure_image()


## 复用已有 Image 节点；只在缺失时新建，重复进树不增子节点。
func _ensure_image() -> void:
	if is_instance_valid(_image):
		return
	_image = get_node_or_null(NodePath(IMAGE_NODE_NAME)) as TextureRect
	if _image != null:
		return
	_image = TextureRect.new()
	_image.name = IMAGE_NODE_NAME
	add_child(_image)


## 把导出属性写入内部 TextureRect；不触发资源加载。
func _refresh_content() -> void:
	_ensure_image()
	if _image == null:
		return
	_image.texture = texture
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = stretch_mode
	_image.custom_minimum_size = Vector2(image_size)
