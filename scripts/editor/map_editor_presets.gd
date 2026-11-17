## map_editor_presets.gd — 地图编辑器区域预设库（预设 Tab）
##
## 保存=选区→payload→store（不动模型不入历史）；填入选区=以选区左上角为原点
## 按预设尺寸一步历史回写；放置模式=点击画布以该格为左上角连续放置，每次一步
## 历史；与粘贴模式互斥，ESC/切工具/生成/读取/调尺寸均退出并清预览。
## payload 内核在 region_clipboard.gd，持久化在 region_preset_store.gd。
## 全部 static，ed=map_editor 实例；逻辑与原 map_editor.gd 内联实现逐行一致。

class_name MapEditorPresets
extends RefCounted

const RegionClipboardScript = preload("res://scripts/editor/region_clipboard.gd")
const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")


## 刷新预设列表；select_id 非空则选中该项（保存后选中新项）
static func refresh_preset_list(ed, select_id := "") -> void:
	if ed._preset_list == null or ed._preset_store == null:
		return
	ed._preset_list.clear()
	var selected_idx := -1
	for meta in ed._preset_store.list():
		var idx: int = ed._preset_list.add_item("%s — %d×%d — %d单位/%d植物" % [
			meta.name, int(meta.w), int(meta.h), int(meta.units), int(meta.props),
		])
		ed._preset_list.set_item_metadata(idx, String(meta.id))
		if String(meta.id) == select_id:
			selected_idx = idx
	if selected_idx >= 0:
		ed._preset_list.select(selected_idx)


## 当前列表选中项的预设 id（未选中返回空串）
static func selected_preset_id(ed) -> String:
	if ed._preset_list == null:
		return ""
	var selected: PackedInt32Array = ed._preset_list.get_selected_items()
	if selected.is_empty():
		return ""
	return String(ed._preset_list.get_item_metadata(selected[0]))


## 保存当前完整选区为预设：无完整选区仅中文提示（不写盘）；成功列表刷新并选中新项
static func on_save_preset_pressed(ed) -> void:
	var bounds: Array = ed._move_tool_bounds()
	if bounds.is_empty():
		ed._status("预设保存：请先框选一个完整区域（两次点击画布）", true)
		return
	var payload := RegionClipboardScript.extract(ed.model, bounds[0], bounds[1])
	if payload.is_empty():
		ed._status("预设保存：区域数据提取失败", true)
		return
	var preset_name: String = ed._preset_name_edit.text if ed._preset_name_edit != null else ""
	var result: Dictionary = ed._preset_store.save(preset_name, payload)
	if not bool(result.ok):
		ed._status("预设保存失败：%s" % result.error, true)
		return
	refresh_preset_list(ed, String(result.id))
	if ed._preset_name_edit != null:
		ed._preset_name_edit.text = "预设 %d" % (ed._preset_store.count() + 1)
	var b_note := ""
	if not BattlefieldDocScript.buildings_fully_within(ed.model, bounds[0], bounds[1]).is_empty():
		b_note = "（区域内建筑不随预设保存，请用区域复制/剪切带走）"
	ed._status("已保存预设「%s」（%d×%d）%s" % [preset_name.strip_edges(), int(payload.w), int(payload.h), b_note])
	print("[editor] 保存预设 id=%s name=%s %d×%d%s" % [String(result.id), preset_name.strip_edges(), int(payload.w), int(payload.h), b_note])  # L1 埋点


## 填入选区：以选区 2D 左上角为原点按预设尺寸回写五层；越界仅报错，成功一步历史
static func on_fill_preset_pressed(ed) -> void:
	var id := selected_preset_id(ed)
	if id.is_empty():
		ed._status("填入预设：请先在列表选中一个预设", true)
		return
	var bounds: Array = ed._move_tool_bounds()
	if bounds.is_empty():
		ed._status("填入预设：请先框选一个完整区域", true)
		return
	var payload: Dictionary = ed._preset_store.load(id)
	if payload.is_empty():
		ed._status("填入预设：预设不存在或已损坏", true)
		return
	var origin: Vector2i = bounds[0]
	var size := Vector2i(int(payload.w), int(payload.h))
	var hi := origin + size - Vector2i(1, 1)
	var err := RegionClipboardScript.bounds_error(ed.model, origin, hi)
	if not err.is_empty():
		ed._status("填入失败：%s" % err, true)
		return
	ed._push_undo("填入预设")
	var result: Dictionary = RegionClipboardScript.write(ed.model, payload, origin)
	ed._refresh_canvas()
	ed._sync_region_marker()
	var dropped := int(result.get("dropped_units", 0))
	var suffix := "（%d 个单位因地形不可站立被丢弃）" % dropped if dropped > 0 else ""
	ed._status("已填入预设 → (%d,%d)%s" % [origin.x, origin.y, suffix])
	print("[editor] 填入预设 id=%s origin=%s dropped_units=%d" % [id, str(origin), dropped])  # L1 埋点


## 放置模式开关：开启需已选预设（否则回弹）；与粘贴模式互斥
static func on_place_preset_toggled(ed, on: bool) -> void:
	if on:
		var id := selected_preset_id(ed)
		if id.is_empty():
			ed._status("放置模式：请先在列表选中一个预设", true)
			if ed._place_preset_btn != null:
				ed._place_preset_btn.set_pressed_no_signal(false)
			return
		ed._cancel_paste()  # 与粘贴模式互斥
		ed._place_mode = true
		ed._place_preset_id = id
		update_place_preview(ed, ed._canvas.hover_cell if ed._canvas != null else Vector2i(-1, -1))
		ed._status("放置模式：点击画布放置「%s」，ESC 退出" % preset_name_for_id(ed, id))
		print("[editor] 进入放置模式 id=%s" % id)  # L1 埋点
	else:
		cancel_place_mode(ed)


## 实时预览总开关：关闭立即清除当前放置预览；不影响粘贴模式或放置提交
static func on_place_preview_toggled(ed, on: bool) -> void:
	ed._place_preview_enabled = on
	if ed._canvas == null or not ed._place_mode:
		return
	if on:
		update_place_preview(ed, ed._canvas.hover_cell)
	else:
		ed._canvas.clear_paste_preview()


## 预设显示名（状态栏提示用；找不到返回 id）
static func preset_name_for_id(ed, id: String) -> String:
	if ed._preset_store == null:
		return id
	for meta in ed._preset_store.list():
		if String(meta.id) == id:
			return String(meta.name)
	return id


## 放置预览随悬停格刷新：总开关关闭时保持无预览；正常显示真实应用效果，越界红色提示。
static func update_place_preview(ed, hover: Vector2i) -> void:
	if ed._canvas == null or not ed._place_mode:
		return
	if not ed._place_preview_enabled or hover.x < 0:
		ed._canvas.clear_paste_preview()
		return
	var payload: Dictionary = ed._preset_store.load(ed._place_preset_id)
	if payload.is_empty():
		return
	ed._canvas.set_placement_preview(payload, hover)


## 放置提交：以点击格为左上角写五层，一步历史；越界仅报错保持模式可重试；
## 成功后模式保持（可连续放置）
static func commit_place_preset(ed, cell: Vector2i) -> void:
	var payload: Dictionary = ed._preset_store.load(ed._place_preset_id)
	if payload.is_empty():
		ed._status("预设不存在或已损坏，已退出放置模式", true)
		cancel_place_mode(ed)
		return
	var size := Vector2i(int(payload.w), int(payload.h))
	var hi := cell + size - Vector2i(1, 1)
	var err := RegionClipboardScript.bounds_error(ed.model, cell, hi)
	if not err.is_empty():
		ed._status("放置失败：%s" % err, true)
		update_place_preview(ed, ed._canvas.hover_cell if ed._canvas != null else Vector2i(-1, -1))
		return
	ed._push_undo("放置预设")
	var result: Dictionary = RegionClipboardScript.write(ed.model, payload, cell)
	ed._refresh_canvas()
	ed._sync_region_marker()
	var dropped := int(result.get("dropped_units", 0))
	var suffix := "（%d 个单位因地形不可站立被丢弃）" % dropped if dropped > 0 else ""
	ed._status("已放置预设 → (%d,%d)%s" % [cell.x, cell.y, suffix])
	print("[editor] 放置预设 id=%s at=%s dropped_units=%d" % [ed._place_preset_id, str(cell), dropped])  # L1 埋点


## 退出放置模式并清预览（ESC/关开关/生成/读取/调尺寸/切工具/进粘贴模式）
static func cancel_place_mode(ed) -> void:
	ed._place_mode = false
	ed._place_preset_id = ""
	if ed._place_preset_btn != null and ed._place_preset_btn.button_pressed:
		ed._place_preset_btn.set_pressed_no_signal(false)
	if ed._canvas != null:
		ed._canvas.clear_paste_preview()


## 重命名选中预设：新名取名称输入框，失败中文提示
static func on_rename_preset_pressed(ed) -> void:
	var id := selected_preset_id(ed)
	if id.is_empty():
		ed._status("重命名：请先在列表选中一个预设", true)
		return
	var new_name: String = ed._preset_name_edit.text if ed._preset_name_edit != null else ""
	if not ed._preset_store.rename(id, new_name):
		ed._status("重命名失败：名称不能为空或预设已不存在", true)
		return
	refresh_preset_list(ed, id)
	ed._status("已重命名为「%s」" % new_name.strip_edges())


## 删除选中预设：列表与存储同步；正在放置该预设则先退出
static func on_delete_preset_pressed(ed) -> void:
	var id := selected_preset_id(ed)
	if id.is_empty():
		ed._status("删除：请先在列表选中一个预设", true)
		return
	if ed._place_mode and ed._place_preset_id == id:
		cancel_place_mode(ed)
	if not ed._preset_store.delete(id):
		ed._status("删除失败：预设已不存在", true)
		return
	refresh_preset_list(ed)
	ed._status("已删除预设")


## 刷新按钮：重读存储（外部改动/多实例并发时手动同步）
static func on_refresh_preset_pressed(ed) -> void:
	refresh_preset_list(ed)
	ed._status("预设列表已刷新（共 %d 个）" % ed._preset_store.count())
