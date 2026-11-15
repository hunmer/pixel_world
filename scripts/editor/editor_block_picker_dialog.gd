## editor_block_picker_dialog.gd — 居中遮罩方块选择弹窗，确认回填，取消零信号。
class_name EditorBlockPickerDialog
extends Window

signal block_chosen(kind: String, id: String)

const EditorBlockListScript = preload("res://scripts/editor/editor_block_list.gd")

var block_list: EditorBlockListScript
var _built := false
var _shade: PanelContainer
var _cancel_btn: Button


func _ready() -> void:
	_build()


func open(p_items: Array, selected_id: String = "") -> void:
	_build()
	block_list.configure(p_items, selected_id, false)
	popup_centered()
	size = Vector2i(640, 480)
	move_to_center()
	_cancel_btn.grab_focus()


func close() -> void:
	hide()


func cancel() -> void:
	hide()


func _build() -> void:
	if _built:
		return
	_built = true
	title = "选择方块"
	size = Vector2i(640, 480)
	min_size = Vector2i(360, 280)
	exclusive = true
	transient = true
	close_requested.connect(cancel)

	_shade = PanelContainer.new()
	_shade.name = "PickerShade"
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade_style := StyleBoxFlat.new()
	shade_style.bg_color = Color(0.025, 0.035, 0.055, 0.96)
	_shade.add_theme_stylebox_override("panel", shade_style)
	add_child(_shade)
	_shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			cancel())

	var center := CenterContainer.new()
	center.name = "PickerCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "PickerPanel"
	panel.custom_minimum_size = Vector2(480, 360)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.name = "PickerBox"
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title_label := Label.new()
	title_label.name = "PickerTitle"
	title_label.text = "选择方块"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)
	var scroll := ScrollContainer.new()
	scroll.name = "PickerScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	block_list = EditorBlockListScript.new()
	block_list.name = "BlockPickerList"
	block_list.columns = 1
	block_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(block_list)
	block_list.block_activated.connect(_on_block_activated)
	_cancel_btn = Button.new()
	_cancel_btn.name = "PickerCancelBtn"
	_cancel_btn.text = "取消"
	_cancel_btn.custom_minimum_size = Vector2(0, 36)
	_cancel_btn.pressed.connect(cancel)
	box.add_child(_cancel_btn)


func _on_block_activated(kind: String, id: String) -> void:
	hide()
	block_chosen.emit(kind, id)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel()
		set_input_as_handled()
