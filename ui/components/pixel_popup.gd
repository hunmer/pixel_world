## pixel_popup.gd — 弹层：PopupPanel 外观 + 打开前记录焦点、关闭后恢复
##
## 原生 PopupPanel 行为保留：ESC 关闭、点击外部关闭、popup_hide 信号。
## 本组件额外记录打开前的焦点控件，popup_hide 后把焦点还给它，避免键盘
## 用户丢失焦点。用 open_for(opener) 打开可显式指定 opener。
@tool
class_name PixelPopup
extends PopupPanel

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")

## 打开前的焦点控件；关闭后恢复焦点用。
var _opener: Control = null


func _init() -> void:
	_refresh()
	_connect_once()


func _ready() -> void:
	_refresh()
	_connect_once()


## 主题刷新；幂等。
func _refresh() -> void:
	if theme == null:
		theme = ComponentThemeScript.create()
	theme_type_variation = ComponentThemeScript.POPUP_VARIATION


## 信号只连一次；重复进树不重复连接。
func _connect_once() -> void:
	if not about_to_popup.is_connected(_on_about_to_popup):
		about_to_popup.connect(_on_about_to_popup)
	if not popup_hide.is_connected(_on_popup_hide):
		popup_hide.connect(_on_popup_hide)


## 从指定控件打开弹层；关闭后焦点回到该控件。
func open_for(opener: Control) -> void:
	_opener = opener
	popup_centered()


## 打开瞬间记录当前焦点（含用 popup_centered 直接打开的情况）。
func _on_about_to_popup() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	_opener = viewport.gui_get_focus_owner()


## 关闭后恢复焦点；opener 已释放时安全跳过。
func _on_popup_hide() -> void:
	if is_instance_valid(_opener):
		_opener.grab_focus()
	_opener = null
