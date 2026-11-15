## shortcut_hints_dialog.gd — 地图编辑器操作提示弹窗：遮罩、居中键帽面板、三种关闭方式。
class_name EditorShortcutHintsDialog
extends Control

signal closed

const HintBarScript = preload("res://scripts/hint_bar.gd")

var _panel: PanelContainer = null
var _flow: HFlowContainer = null
var _shade: ColorRect = null
var _close_btn: Button = null
var _built := false


func _init() -> void:
	name = "ShortcutHintsDialog"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


## 打开并复用 hint_bar.gd 的 Keycap/Key/Action 键帽行；hints 项为 {key, action}。
func open(hints: Array) -> void:
	_build()
	for child in _flow.get_children():
		if child == _close_btn or child.name == "HelpTitle":
			continue
		_flow.remove_child(child)
		child.queue_free()
	for value in hints:
		if not (value is Dictionary):
			continue
		var hint: Dictionary = value
		_panel.add_hint(String(hint.get("key", "")), String(hint.get("action", "")))
	show()
	_close_btn.grab_focus()


## 所有关闭入口统一走这里；重复关闭不重复 emit。
func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _build() -> void:
	if _built:
		return
	_built = true
	_shade = ColorRect.new()
	_shade.name = "ShortcutHintsShade"
	_shade.color = Color(0.025, 0.035, 0.055, 0.90)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			close())

	# HintBar 本体作为居中面板；内部 HelpFlow 改名后仍复用全部键帽渲染逻辑。
	var hint_panel = HintBarScript.new()
	hint_panel.name = "ShortcutHintsPanel"
	hint_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hint_panel.custom_minimum_size = Vector2(660, 440)
	add_child(hint_panel)
	hint_panel.set_anchors_preset(Control.PRESET_CENTER)
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	hint_panel.offset_left = -330
	hint_panel.offset_top = -220
	hint_panel.offset_right = 330
	hint_panel.offset_bottom = 220
	_panel = hint_panel
	_flow = hint_panel.get_node("HelpFlow") as HFlowContainer
	_flow.name = "ShortcutHintFlow"
	_flow.mouse_filter = Control.MOUSE_FILTER_STOP
	_flow.add_theme_constant_override("h_separation", 14)
	_flow.add_theme_constant_override("v_separation", 8)
	_panel.set_title("操作提示")
	_close_btn = Button.new()
	_close_btn.name = "ShortcutHintsCloseBtn"
	_close_btn.text = "关闭"
	_close_btn.custom_minimum_size = Vector2(64, 30)
	_close_btn.tooltip_text = "关闭操作提示（Esc）"
	_close_btn.pressed.connect(close)
	_flow.add_child(_close_btn)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		close()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
