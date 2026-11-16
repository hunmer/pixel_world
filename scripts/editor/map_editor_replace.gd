## map_editor_replace.gd — 地图编辑器条件替换（替换方块工具）
##
## 源/目标编码（terrain:<glyph> / asset:<id>）、候选枚举选中和回填、
## 方块选择器开合、替换范围回显与替换执行（匹配/写入内核在
## map_editor_paint_ops.gd；候选枚举在 map_editor_overlays.gd）。
## 全部 static，ed=map_editor 实例；逻辑与原 map_editor.gd 内联实现逐行一致。

class_name MapEditorReplace
extends RefCounted

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const MapEditorPaintOpsScript = preload("res://scripts/editor/map_editor_paint_ops.gd")
const MapEditorOverlaysScript = preload("res://scripts/editor/map_editor_overlays.gd")
const RegionClipboardScript = preload("res://scripts/editor/region_clipboard.gd")


static func replace_source_code(ed) -> String:
	if ed._replace_source_opt == null:
		return "terrain:."
	return String(ed._replace_source_opt.get_meta("code", "terrain:."))


static func replace_dest_code(ed) -> String:
	if ed._replace_dest_opt == null:
		return replace_code_for_block(ed, ed._block_fg)
	return String(ed._replace_dest_opt.get_meta("code", replace_code_for_block(ed, ed._block_fg)))


static func replace_code_for_block(ed, block: Dictionary) -> String:
	if String(block.get("kind", "terrain")) == "asset" and not String(block.get("id", "")).is_empty():
		return "asset:%s" % String(block.get("id", ""))
	var terrain := StringName(String(block.get("id", "plain")))
	return "terrain:%s" % String(BattlefieldDocScript.TERRAIN_GLYPH.get(terrain, "."))


## 选中编码项；地图里吸到但不在已保存素材库的 id 也允许作为源/目标。
static func select_replace_option(ed, opt: Button, code: String) -> bool:
	if opt == null or code.is_empty():
		return false
	var item: Dictionary = {}
	for candidate in ed._replace_items:
		if "%s:%s" % [String(candidate.get("kind", "")), String(candidate.get("id", ""))] == code:
			item = candidate
			break
	if item.is_empty() and code.begins_with("asset:") and code.length() > 6:
		item = MapEditorOverlaysScript.replace_item_for_code(ed, code)
		ed._replace_items.append(item)
	if item.is_empty():
		return false
	opt.set_meta("code", code)
	opt.text = String(item.get("label", code))
	opt.tooltip_text = opt.text
	var texture: Variant = item.get("texture")
	opt.icon = texture if texture is Texture2D else null
	opt.expand_icon = true
	opt.add_theme_constant_override("icon_max_width", 32)
	return true


static func open_replace_picker(ed, target: String) -> void:
	if ed._replace_picker_dialog == null:
		return
	MapEditorOverlaysScript.replace_populate_options(ed)
	ed._replace_picker_target = target
	var selected := replace_dest_code(ed) if target == "dest" else replace_source_code(ed)
	ed._replace_picker_dialog.open(ed._replace_items, selected)


static func on_replace_picker_chosen(ed, kind: String, id: String) -> void:
	var code := "%s:%s" % [kind, id]
	if ed._replace_picker_target == "dest":
		select_replace_option(ed, ed._replace_dest_opt, code)
	else:
		select_replace_option(ed, ed._replace_source_opt, code)
		ed._refresh_replace_scope()


static func reset_replace_popup(ed) -> void:
	MapEditorOverlaysScript.replace_populate_options(ed)
	var source_code := "terrain:."
	if ed._canvas != null:
		var hover_code := MapEditorPaintOpsScript.code_at(ed.model, ed._canvas.hover_cell)
		if not hover_code.is_empty():
			source_code = hover_code
	select_replace_option(ed, ed._replace_source_opt, source_code)
	select_replace_option(ed, ed._replace_dest_opt, replace_code_for_block(ed, ed._block_fg))
	ed._refresh_replace_scope()


static func set_replace_source_from_cell(ed, cell: Vector2i) -> void:
	var code := MapEditorPaintOpsScript.code_at(ed.model, cell)
	if code.is_empty():
		ed._status("替换失败：坐标越界", true)
		return
	select_replace_option(ed, ed._replace_source_opt, code)
	ed._refresh_replace_scope()
	ed._status("被替换方块：%s" % ed._replace_source_opt.text)
	print("[editor] 替换源 cell=%s code=%s" % [str(cell), code])  # L1 埋点


static func refresh_replace_scope(ed) -> void:
	if ed._replace_scope_label == null:
		return
	var is_region: bool = ed._selection_mode == &"region" and ed._region_pos2_set and ed._selection_range.is_active()
	var count: int = ed._selection_range.cells_2d().size() if is_region else int(ed.model.width) * int(ed.model.height)
	ed._replace_scope_label.text = "当前范围：%s %d 格" % ["选区内" if is_region else "全图", count]


## 条件替换：完整选区优先，否则全图；仅命中源类型的格子写目标，高度一律不动
##（匹配/写入内核在 MapEditorPaintOpsScript；匹配与写入之间夹入历史入栈）。
## terrain 源只匹配无 tile_override 且 rows 图例相同的格；asset 源只匹配覆盖 id。
static func apply_replace(ed) -> void:
	if ed._replace_source_opt == null or ed._replace_dest_opt == null:
		ed._status("替换失败：请选择源方块与目标方块", true)
		return
	var source_code := replace_source_code(ed)
	var dest_code := replace_dest_code(ed)
	if source_code.is_empty() or dest_code.is_empty():
		ed._status("替换失败：源方块或目标方块无效", true)
		return
	if source_code == dest_code:
		ed._status("替换失败：源方块与目标方块相同", true)
		return
	var is_region: bool = ed._selection_mode == &"region" and ed._region_pos2_set and ed._selection_range.is_active()
	var cells: Array = []
	if is_region:
		var mn: Vector3i = ed._selection_range.min_corner()
		var mx: Vector3i = ed._selection_range.max_corner()
		var err := RegionClipboardScript.bounds_error(ed.model,
			Vector2i(mn.x, mn.y), Vector2i(mx.x, mx.y))
		if not err.is_empty():
			ed._status("替换失败：%s" % err, true)
			return
		cells = ed._selection_range.cells_2d()
	else:
		for y in range(int(ed.model.height)):
			for x in range(int(ed.model.width)):
				cells.append(Vector2i(x, y))
	if cells.is_empty():
		ed._status("替换失败：选区为空", true)
		return
	var source_kind := "asset" if source_code.begins_with("asset:") else "terrain"
	var source_value := source_code.substr(6) if source_kind == "asset" else source_code.substr(8)
	var matched: Array = MapEditorPaintOpsScript.match_cells(ed.model, cells, source_kind, source_value)
	if matched.is_empty():
		ed._status("匹配 0 格：未替换", true)
		return
	var action := "替换区域" if is_region else "替换全图"
	ed._push_undo(action)
	var dest_kind := "asset" if dest_code.begins_with("asset:") else "terrain"
	var dest_value := dest_code.substr(6) if dest_kind == "asset" else dest_code.substr(8)
	var replaced: int = MapEditorPaintOpsScript.write_cells(ed.model, matched, dest_kind, dest_value)
	ed._seal_pending()  # 按钮动作立即落一条历史，不等下一次画布交互
	ed._refresh_canvas()
	ed._status("%s：%d 格（高度不变）" % [action, replaced])
	print("[editor] %s source=%s dest=%s cells=%d" % [action, source_code, dest_code, replaced])  # L1 埋点
