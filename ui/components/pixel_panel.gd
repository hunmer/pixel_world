## pixel_panel.gd — 组件库卡片：标题 + 说明 + 固定内容槽
##
## 配套场景 pixel_panel.tscn（结构固定，脚本只更新文本/图标与主题变体，不增删节点）。
## 使用方 instantiate() 后把子控件加进 get_content_slot()，布局由场景内 VBox 稳定托管。
@tool
class_name PixelPanel
extends PanelContainer

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")

## 场景内固定节点路径；脚本只做属性同步，不重建结构。
const CONTENT_SLOT_PATH: String = "VBox/ContentSlot"
const HEADER_PATH: String = "VBox/Header"
const ICON_PATH: String = "VBox/Header/Icon"
const TITLE_PATH: String = "VBox/Header/TitleBox/Title"
const DESCRIPTION_PATH: String = "VBox/Header/TitleBox/Description"

## 卡片标题；空字符串时标题行自动隐藏。
@export var title: String = "":
	set(value):
		title = value
		_refresh()

## 卡片说明；空字符串时说明标签自动隐藏。
@export var description: String = "":
	set(value):
		description = value
		_refresh()

## 标题左侧图标；null 时隐藏图标位（标题行仍按文本显隐）。
@export var icon: Texture2D = null:
	set(value):
		icon = value
		_refresh()


func _init() -> void:
	# instantiate() 后即带主题（此时场景子节点尚未创建，_refresh 对空节点安全）；
	# _ready 在子节点就绪后再同步标题/说明/图标。
	_refresh()


func _ready() -> void:
	_refresh()


## 固定内容槽；调用方只往这里 add_child，不直接改场景结构。
func get_content_slot() -> Container:
	return get_node_or_null(CONTENT_SLOT_PATH) as Container


## 幂等同步：重复调用只覆盖同键属性/主题项，不新增节点。
func _refresh() -> void:
	if theme == null:
		theme = ComponentThemeScript.create()
	theme_type_variation = ComponentThemeScript.PANEL_VARIATION

	var header := get_node_or_null(HEADER_PATH) as Control
	var icon_rect := get_node_or_null(ICON_PATH) as TextureRect
	var title_label := get_node_or_null(TITLE_PATH) as Label
	var description_label := get_node_or_null(DESCRIPTION_PATH) as Label
	var has_icon: bool = icon != null
	var has_title: bool = not title.is_empty()
	var has_description: bool = not description.is_empty()

	if icon_rect != null:
		icon_rect.texture = icon
		icon_rect.visible = has_icon
	if title_label != null:
		title_label.text = title
		title_label.visible = has_title
		title_label.add_theme_color_override("font_color", UIThemeScript.TEXT_MAIN)
		title_label.add_theme_font_size_override("font_size", 16)
	if description_label != null:
		description_label.text = description
		description_label.visible = has_description
		description_label.add_theme_color_override("font_color", UIThemeScript.TEXT_DIM)
		description_label.add_theme_font_size_override("font_size", 12)
	if header != null:
		header.visible = has_icon or has_title or has_description
