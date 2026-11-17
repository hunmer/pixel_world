## map_editor_unit_edit_contract.gd — 角色点击回显、资料修改与移除的交互契约。
extends SceneTree

const DocScript = preload("res://scripts/editor/battlefield_doc.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	# 本契约验证角色操作；不挂接按钮音效，避免无头退出时 MP3 播放残留。
	var audio_hook := Callable(root.get_node("Sfx"), "_on_node_added")
	node_added.disconnect(audio_hook)
	var editor = load("res://scenes/MapEditor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor.model = DocScript.create_empty(8, 4)
	editor._canvas.selected_cell = Vector2i(-1, -1)
	editor._refresh_canvas()
	editor._history.clear()
	editor._init_history()
	editor.current_tool = editor.Tool.UNIT
	editor._tabs.current_tab = 4
	_expect(editor._unit_remove_btn.disabled and editor._unit_apply_btn.disabled, "无选择时禁用编辑与移除")
	var cell := Vector2i(1, 1)
	editor._unit_name_edit.text = "初始角色"
	editor._on_cell_pressed(cell)
	_expect(editor.model.units.size() == 1, "空格点击放置角色")
	var original: Dictionary = editor.model.units[0].duplicate(true)
	var history_size: int = editor._history.size()
	editor._on_cell_pressed(cell)
	editor._on_cell_pressed(cell)
	_expect(editor.model.units.size() == 1 and editor.model.units[0] == original, "重复点击只选择、不移除或改写角色")
	_expect(editor._history.size() == history_size, "重复选择不增加历史记录")
	_expect(editor._selected_unit_cell == cell and editor._unit_name_edit.text == "初始角色", "角色姓名和位置回显")
	_expect(not editor._unit_remove_btn.disabled and not editor._unit_apply_btn.disabled, "选中后启用按钮")
	(editor._faction_buttons["enemy"] as Button).button_pressed = true
	(editor._class_buttons["mage"] as Button).button_pressed = true
	editor._level_box.get_line_edit().text = "7"
	editor._unit_name_edit.text = "  新法师  "
	editor._unit_apply_btn.pressed.emit()
	var changed: Dictionary = editor.model.units[0].duplicate(true)
	_expect(changed["class"] == "mage" and changed.faction == "enemy" and changed.level == 7
		and changed.name == "新法师", "应用按钮提交职业、阵营、未失焦等级和姓名")
	_expect(changed.x == cell.x and changed.y == cell.y and editor.model.units.size() == 1, "修改原角色并保留位置")
	_expect(editor._canvas._unit_markers[0].unit.classId == &"mage", "编辑后画布刷新战场精灵")
	editor._undo()
	_expect(editor.model.units[0] == original and editor._unit_name_edit.text == "初始角色", "一步撤销资料修改并同步面板")
	editor._redo()
	_expect(editor.model.units[0] == changed and editor._unit_name_edit.text == "新法师", "重做资料修改")
	history_size = editor._history.size()
	editor._unit_apply_btn.pressed.emit()
	_expect(editor._history.size() == history_size, "资料未变时应用不增加历史")
	editor._unit_remove_btn.pressed.emit()
	_expect(editor.model.units.is_empty() and editor._canvas._unit_markers.is_empty(), "移除按钮清理模型与精灵")
	_expect(editor._unit_remove_btn.disabled and editor._selected_unit_cell == Vector2i(-1, -1), "移除后清除选择")
	editor._undo()
	_expect(editor.model.units.size() == 1 and editor.model.units[0] == changed, "一步撤销移除恢复角色")
	editor._redo()
	_expect(editor.model.units.is_empty(), "重做移除")
	editor._undo()
	# 单格选择也能进入角色页，区域选择仍保留原有语义。
	editor._tabs.current_tab = 0
	editor.current_tool = editor.Tool.SELECT
	editor._selection_mode = &"single"
	editor._on_cell_pressed(cell)
	_expect(editor._tabs.current_tab == 4 and editor._selected_unit_cell == cell, "单格选择角色自动切换角色页")
	_expect(editor._class_buttons["mage"].button_pressed and editor._faction_buttons["enemy"].button_pressed,
		"选中后职业及阵营按钮同步")
	var new_btn: Button = editor.find_child("NewUnitBtn", true, false)
	new_btn.pressed.emit()
	_expect(editor._selected_unit_cell == Vector2i(-1, -1) and editor.model.units.size() == 1, "新建按钮退出编辑且保留原角色")
	editor._on_cell_pressed(Vector2i(2, 1))
	_expect(editor.model.units.size() == 2, "继续点击空格新增角色")
	editor.apply_generate("unit_edit_reset", 8, 4)
	_expect(editor._unit_apply_btn.disabled and editor._unit_remove_btn.disabled, "生成新地图清除角色选择与按钮状态")
	editor.queue_free()
	await process_frame
	node_added.connect(audio_hook)
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("MAP_EDITOR_UNIT_EDIT_CONTRACT_OK")
	quit(0 if failures.is_empty() else 1)
