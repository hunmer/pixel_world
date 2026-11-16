## editor_block_list.gd — 可复用方块列表：真实图标、kind:id 复合选中与激活信号。
class_name EditorBlockList
extends GridContainer

signal block_activated(kind: String, id: String)

var items: Array[Dictionary] = []
var selected_id: String = ""
var compact: bool = false
## 弹窗画廊：多列、大尺寸纯缩略图；不影响地形 Tab 素材方块区的 compact 外观。
var gallery: bool = false
var _buttons: Array[Button] = []


func _ready() -> void:
	_rebuild()


## 普通模式为 40px 图标文字行；compact 保留地形 Tab 素材方块区的 46×96 纯图标格子；
## gallery 为选择弹窗提供 4 列 88×88 大缩略图，不显示文本列表。
func configure(
	p_items: Array, p_selected_id: String = "", p_compact: bool = false, p_gallery: bool = false
) -> void:
	compact = p_compact
	gallery = p_gallery
	columns = 4 if compact or gallery else 1
	items.clear()
	for raw in p_items:
		if raw is Dictionary:
			items.append((raw as Dictionary).duplicate(true))
	selected_id = p_selected_id
	if is_inside_tree():
		_rebuild()


func set_items(p_items: Array) -> void:
	configure(p_items, selected_id, compact, gallery)


func set_selected(p_selected_id: String) -> void:
	selected_id = p_selected_id
	_sync_selection()


func item_count() -> int:
	return items.size()


func get_button(index: int) -> Button:
	return _buttons[index] if index >= 0 and index < _buttons.size() else null


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	for i in range(items.size()):
		var item := items[i]
		var kind := String(item.get("kind", "terrain"))
		var id := String(item.get("id", ""))
		var label := String(item.get("label", id))
		var btn := Button.new()
		btn.name = "BlockButton%d" % i
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(88, 88) if gallery else (Vector2(46, 96) if compact else Vector2(0, 40))
		btn.text = "" if compact or gallery else label
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.tooltip_text = "%s（%s）" % [label, id]
		btn.set_meta("block_kind", kind)
		btn.set_meta("block_asset", id)
		btn.set_meta("block_id", "%s:%s" % [kind, id])
		var texture: Variant = item.get("texture")
		if texture is Texture2D:
			btn.icon = texture
			btn.expand_icon = true
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.add_theme_constant_override("icon_max_width", 72 if gallery else (40 if compact else 32))
		add_child(btn)
		_buttons.append(btn)
		btn.pressed.connect(_on_item_pressed.bind(i))
	_sync_selection()


func _on_item_pressed(index: int) -> void:
	if index < 0 or index >= items.size():
		return
	var item := items[index]
	var kind := String(item.get("kind", "terrain"))
	var id := String(item.get("id", ""))
	var composite := "%s:%s" % [kind, id]
	selected_id = "" if selected_id == composite else composite
	_sync_selection()
	block_activated.emit(kind, id)


func _sync_selection() -> void:
	for i in range(_buttons.size()):
		var item := items[i]
		var composite := "%s:%s" % [String(item.get("kind", "terrain")), String(item.get("id", ""))]
		_buttons[i].set_pressed_no_signal(composite == selected_id)
