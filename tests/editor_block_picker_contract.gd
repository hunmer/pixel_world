## editor_block_picker_contract.gd — 公共方块列表/选择弹窗：真实图标、复合选中、确认/取消信号。
extends SceneTree

const EditorBlockListScript = preload("res://scripts/editor/editor_block_list.gd")
const EditorBlockPickerDialogScript = preload("res://scripts/editor/editor_block_picker_dialog.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error(label)


func _texture() -> ImageTexture:
	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.8, 0.4, 1.0))
	return ImageTexture.create_from_image(image)


func _run() -> void:
	var items: Array[Dictionary] = [
		{"kind": "terrain", "id": ".", "label": "平原", "texture": _texture()},
		{"kind": "asset", "id": "shared", "label": "素材同名", "texture": _texture()},
		{"kind": "terrain", "id": "shared", "label": "地形同名", "texture": _texture()},
	]
	var list = EditorBlockListScript.new()
	root.add_child(list)
	list.configure(items, "asset:shared", false)
	await process_frame
	_expect(list.item_count() == 3 and list.get_button(0) != null and list.get_button(2) != null,
		"列表构建全部 items")
	_expect(list.get_button(0).icon is Texture2D and list.get_button(1).icon is Texture2D
		and list.get_button(0).custom_minimum_size.y == 40,
		"列表显示真实图标且普通行高 40")
	_expect(list.get_button(1).button_pressed and not list.get_button(2).button_pressed,
		"selected_id 用 kind:id 区分同名素材/地形")
	var activations: Array[Dictionary] = []
	list.block_activated.connect(func(kind: String, id: String): activations.append({"kind": kind, "id": id}))
	list.get_button(2).pressed.emit()
	_expect(list.selected_id == "terrain:shared" and activations == [{"kind": "terrain", "id": "shared"}],
		"点击更新选中并 emit block_activated")
	list.set_selected("asset:shared")
	_expect(activations.size() == 1 and list.get_button(1).button_pressed,
		"程序化 set_selected 不发激活信号")

	var dialog = EditorBlockPickerDialogScript.new()
	root.add_child(dialog)
	var chosen: Array[Dictionary] = []
	dialog.block_chosen.connect(func(kind: String, id: String): chosen.append({"kind": kind, "id": id}))
	dialog.open(items, "asset:shared")
	await process_frame
	_expect(dialog.visible and dialog.block_list.item_count() == 3
		and dialog.block_list.selected_id == "asset:shared",
		"dialog open 弹出并复用列表/回填选中")
	_expect(dialog.exclusive and dialog.size == Vector2i(640, 480)
		and dialog.get_node_or_null("PickerShade/PickerCenter/PickerPanel") != null,
		"dialog 居中独占遮罩结构完整")
	_expect(dialog.block_list.gallery and dialog.block_list.columns == 4
		and dialog.block_list.get_button(0).custom_minimum_size == Vector2(88, 88)
		and dialog.block_list.get_button(0).text.is_empty()
		and dialog.block_list.get_button(0).icon is Texture2D
		and dialog.block_list.get_button(0).get_theme_constant("icon_max_width") == 72,
		"dialog 使用 4 列 88px 纯图片缩略图，不显示文本选择列表")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	dialog._input(esc)
	_expect(not dialog.visible and chosen.is_empty(), "Esc 取消关闭且零 block_chosen")
	dialog.open(items, "asset:shared")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	dialog._shade.gui_input.emit(click)
	_expect(not dialog.visible and chosen.is_empty(), "点遮罩取消关闭且零信号")
	dialog.open(items, "asset:shared")
	dialog.block_list.get_button(2).pressed.emit()
	_expect(not dialog.visible and chosen == [{"kind": "terrain", "id": "shared"}],
		"确认选择关闭 dialog 并正确 emit kind/id")
	dialog.open(items, "asset:shared")
	dialog.close()
	_expect(not dialog.visible and chosen.size() == 1, "close 不额外发选择信号")
	dialog.open(items, "")
	dialog.cancel()
	_expect(not dialog.visible and chosen.size() == 1, "cancel 幂等且零信号")

	list.queue_free()
	dialog.queue_free()
	await process_frame
	if _failures == 0:
		print("EDITOR_BLOCK_PICKER_CONTRACT_OK")
	else:
		print("EDITOR_BLOCK_PICKER_CONTRACT_FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
