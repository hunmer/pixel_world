## map_editor_units.gd — 角色选中、资料回显与可撤销编辑。
extends RefCounted

const ProfessionDataScript = preload("res://scripts/core/professions.gd")


static func unit_at(ed, cell: Vector2i) -> Dictionary:
	for unit: Dictionary in ed.model.get("units", []):
		if int(unit.x) == cell.x and int(unit.y) == cell.y:
			return unit
	return {}


## 选择只更新编辑器状态，不写文档或历史。
static func select_unit(ed, cell: Vector2i) -> bool:
	if unit_at(ed, cell).is_empty():
		return false
	ed._seal_pending()
	ed._selected_unit_cell = cell
	ed._select_cell(cell, false)
	sync_panel(ed)
	for index in range(ed._tabs.get_tab_count()):
		if ed._tabs.get_tab_title(index) == "角色":
			ed._tabs.current_tab = index
			break
	ed._status("已选中角色 @(%d,%d)，修改资料后点击应用修改" % [cell.x, cell.y])
	return true


static func clear_selection(ed) -> void:
	ed._selected_unit_cell = Vector2i(-1, -1)
	sync_panel(ed)


## 历史恢复或模型变更后重新查找，避免使用失效的数组下标/字典引用。
static func sync_panel(ed) -> void:
	if ed._unit_info_label == null:
		return
	var unit := unit_at(ed, ed._selected_unit_cell)
	var selected := not unit.is_empty()
	ed._unit_apply_btn.disabled = not selected
	ed._unit_remove_btn.disabled = not selected
	if not selected:
		ed._selected_unit_cell = Vector2i(-1, -1)
		ed._unit_info_label.text = "新建角色：选择资料后点击空格放置；点击已有角色可编辑。"
		return
	ed.selected_class = String(unit.get("class", "swordsman"))
	ed.selected_faction = String(unit.get("faction", "enemy"))
	for cid in ed._class_buttons:
		(ed._class_buttons[cid] as Button).set_pressed_no_signal(cid == ed.selected_class)
	for faction in ed._faction_buttons:
		(ed._faction_buttons[faction] as Button).set_pressed_no_signal(faction == ed.selected_faction)
	ed._level_box.value = int(unit.get("level", 1))
	ed._unit_name_edit.text = String(unit.get("name", ""))
	ed._unit_info_label.text = "编辑角色：%s @(%d,%d)" % [
		String(unit.get("name", "")), ed._selected_unit_cell.x, ed._selected_unit_cell.y]


static func apply_changes(ed) -> void:
	var unit := unit_at(ed, ed._selected_unit_cell)
	if unit.is_empty():
		sync_panel(ed)
		return
	# SpinBox 内尚未失焦的键盘输入也必须提交。
	ed._level_box.apply()
	var cn := ProfessionDataScript.profession_name(StringName(ed.selected_class))
	var uname: String = ed._unit_name_edit.text.strip_edges()
	var changes := {
		"class": ed.selected_class, "faction": ed.selected_faction,
		"level": clampi(int(ed._level_box.value), 1, 9),
		"name": uname if not uname.is_empty() else cn,
		"tag": cn.substr(0, 1),
	}
	var changed := false
	for key in changes:
		if unit.get(key) != changes[key]:
			changed = true
	if not changed:
		return
	ed._push_undo("修改角色")
	unit.merge(changes, true)
	ed._canvas._refresh_cell(ed._selected_unit_cell)
	sync_panel(ed)
	ed._seal_pending()
	ed._status("已修改角色：%s" % String(unit.name))
	print("[editor] 修改角色 cell=%s class=%s faction=%s level=%d" % [
		str(ed._selected_unit_cell), String(unit["class"]), String(unit.faction), int(unit.level)])


static func remove_selected(ed) -> void:
	if unit_at(ed, ed._selected_unit_cell).is_empty():
		sync_panel(ed)
		return
	ed._push_undo("移除角色")
	ed._remove_unit_at(ed._selected_unit_cell)
	clear_selection(ed)
	ed._seal_pending()
