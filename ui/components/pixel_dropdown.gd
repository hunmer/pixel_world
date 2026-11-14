## pixel_dropdown.gd — 动作菜单：MenuButton 外观 + 原生 PopupMenu 信号
##
## 与 PixelOptionButton 的区别：OptionButton 是“选择一个当前值”的表单控件，
## 本组件是“触发一条动作”的菜单按钮，选中项通过 get_popup().id_pressed 通知。
## items 导出项只用于演示/静态配置；运行时可继续用 get_popup() 或 add_choice()。
@tool
class_name PixelDropdown
extends MenuButton

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")

## 菜单项文本；设置时重建弹层条目（清空后按顺序添加）。
@export var items: PackedStringArray = PackedStringArray():
	set(value):
		items = value
		_rebuild_items()


func _init() -> void:
	_refresh()
	_rebuild_items()


func _ready() -> void:
	_refresh()
	_rebuild_items()


## 主题刷新；幂等。
func _refresh() -> void:
	if theme == null:
		theme = ComponentThemeScript.create()
	theme_type_variation = ComponentThemeScript.DROPDOWN_VARIATION


## 按 items 重建条目；弹层未就绪时安全跳过。
func _rebuild_items() -> void:
	var popup: PopupMenu = get_popup()
	if popup == null:
		return
	popup.clear()
	for item_text: String in items:
		popup.add_item(item_text)


## 追加一个动作项；返回其索引。
func add_choice(item_text: String) -> int:
	var popup: PopupMenu = get_popup()
	if popup == null:
		return -1
	popup.add_item(item_text)
	return popup.item_count - 1


## 当前条目数。
func get_choice_count() -> int:
	var popup: PopupMenu = get_popup()
	return popup.item_count if popup != null else 0
