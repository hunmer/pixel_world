## map_editor_cell_tools.gd — 地图编辑器画布交互路由与格子面板同步
##
## 生效工具解析（Tab 决定语义）、cell 按下/拖动/释放三态（临时吸管、
## 放置/粘贴/移动模式优先）、工具分发、高度画笔、选中格信息条与
## 方块 z 面板回显、Tab 切换封存。全部 static，ed=map_editor 实例；
## 逻辑与原 map_editor.gd 内联实现逐行一致。

class_name MapEditorCellTools
extends RefCounted

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")


## 切 Tab 时封存上一动作（画笔拖动在换页瞬间定格为一步）
static func on_tab_changed(ed, _idx: int) -> void:
	ed._seal_pending()


## 当前生效工具：高度升降/替换始终遵循工具条；地形 Tab = 画笔/植物；角色 Tab = 放置单位。
## 避免在角色页选好职业点画布，却沿用工具条遗留的填充/橡皮。
static func active_tool(ed) -> int:
	if ed.current_tool == ed.Tool.HEIGHT_UP or ed.current_tool == ed.Tool.HEIGHT_DOWN \
			or ed.current_tool == ed.Tool.REPLACE or ed.current_tool == ed.Tool.PICK:
		return ed.current_tool
	if ed._tabs == null:
		return ed.current_tool
	var title: String = ed._tabs.get_tab_title(ed._tabs.current_tab)
	if title == "地形":
		if ed.current_tool == ed.Tool.PAINT:
			return ed.Tool.PLANT if not ed.current_prop.is_empty() else ed.Tool.PAINT
		if not ed._selected_asset.is_empty():
			return ed.Tool.ASSET
		return ed.Tool.PLANT if not ed.current_prop.is_empty() else ed.Tool.PAINT
	if title == "方块":
		if ed.current_tool == ed.Tool.PAINT:
			return ed.Tool.PAINT
		return ed.Tool.ASSET if not ed._selected_block_asset.is_empty() else ed.Tool.SELECT
	if title == "角色":
		return ed.Tool.UNIT
	return ed.current_tool


static func on_cell_pressed(ed, cell: Vector2i, alt_pressed: bool = false, shift_pressed: bool = false) -> void:
	# 临时吸管优先于放置/粘贴/移动：按住 Alt 时始终只吸取，绝不改模型。
	if ed._alt_pick_active:
		ed._pick_block(cell, shift_pressed or Input.is_key_pressed(KEY_SHIFT))
		return
	if ed._place_mode:
		ed._commit_place_preset(cell)  # 放置模式：点击=以该格为左上角放置
		return
	if ed._paste_mode:
		ed._commit_paste(cell)  # 粘贴模式：点击=提交落点
		return
	# 移动工具开启（独立开关，与 current_tool/_selection_mode 解耦）：任意格按下
	# =抓取选区（不落点、不设端点、不进任何工具动作，绝不触发 _apply_region_click）
	if ed._move_tool_active:
		var mt_bounds: Array = ed._move_tool_bounds()
		if mt_bounds.is_empty():
			ed._status("移动工具：请先框选一个区域", true)
			return
		ed._move_armed = true
		ed._move_grab = cell - mt_bounds[0]  # 记录抓取偏移（按下格-选区 min）
		ed._move_preview = cell
		return
	var tool := active_tool(ed)
	if tool == ed.Tool.PICK:
		ed._pick_block(cell, alt_pressed or ed._alt_key_down)
		return  # 吸管只改前景/背景槽，不进入文档历史。
	if tool == ed.Tool.REPLACE:
		ed._set_replace_source_from_cell(cell)
		return  # 条件替换：点格只选源；写模型统一走 ReplaceApplyBtn。
	# 区域内按下（完整区域+SELECT+区域模式）→ 待移动：不落点、不设端点；
	# 原地松开=纯点击，由 _on_cell_released 补走原 _apply_region_click 逻辑
	if tool == ed.Tool.SELECT and ed._selection_mode == &"region" and ed._region_pos2_set \
			and ed._selection_range.is_active() and ed._selection_range.contains_2i(cell):
		ed._move_armed = true
		ed._move_grab = cell
		ed._move_preview = cell
		return
	if tool == ed.Tool.HEIGHT_UP or tool == ed.Tool.HEIGHT_DOWN:
		ed._height_stroke_cells.clear()
	ed._apply_tool(cell)


static func on_cell_dragged(ed, cell: Vector2i) -> void:
	# 区域内按下后拖动 → 移动预览（绿=合法落点/红=越界）；仍不设区域端点（既有契约）
	if ed._move_armed and ed._move_tool_active:
		if cell != ed._move_preview:  # 移动工具：跨格才预览（跟随抓取偏移）
			ed._move_preview = cell
			ed._update_move_preview(cell)
		return
	if ed._move_armed and cell != ed._move_grab:
		ed._move_preview = cell
		ed._update_move_preview(cell)
		return
	# 拖动仅对画笔/植物/橡皮/高度升降有意义（填充/角色不响应拖动）
	var tool := active_tool(ed)
	if tool == ed.Tool.SELECT:
		if ed._selection_mode != &"region":
			select_cell(ed, cell)  # 区域模式：拖动不设端点，须两次独立点击
	elif tool == ed.Tool.PAINT:
		ed._apply_paint_block(cell)
	elif tool == ed.Tool.PLANT:
		ed._set_prop(cell, ed.current_prop)
	elif tool == ed.Tool.ASSET:
		ed._apply_asset_tool(cell)
	elif tool == ed.Tool.ERASE:
		ed._set_glyph(cell, ".")
		ed._set_prop(cell, "")
		ed._set_tile_override(cell, "")
		ed._set_prop_asset(cell, "")
	elif tool == ed.Tool.HEIGHT_UP or tool == ed.Tool.HEIGHT_DOWN:
		apply_height_brush(ed, cell, tool)


## 画布左键释放（本次笔画以 cell press 开始）：移动工具/区域内拖动 → 跨格=移动
## 区域（一步历史）；原地松开：移动工具=纯点击不改任何状态，区域内拖动=按原
## 逻辑补 _apply_region_click（第三次点击仍重置 pos1）
static func on_cell_released(ed, cell: Vector2i) -> void:
	if not ed._move_armed:
		return
	var grab: Vector2i = ed._move_grab
	var via_tool: bool = ed._move_tool_active
	ed._move_armed = false
	ed._move_grab = Vector2i(-1, -1)
	ed._move_preview = Vector2i(-1, -1)
	if ed._canvas != null:
		ed._canvas.clear_paste_preview()
	if via_tool:
		var mt_bounds: Array = ed._move_tool_bounds()
		if mt_bounds.is_empty():
			return
		var delta: Vector2i = cell - grab - (mt_bounds[0] as Vector2i)  # grab=抓取偏移（按下格-选区 min）
		if delta == Vector2i.ZERO:
			return  # 原地松开：不改模型、不入历史、不改选区、不触发区域选择
		ed._commit_region_move(mt_bounds, delta, true)
		return
	var bounds: Array = ed._region_2d_bounds()
	if cell == grab:
		ed._apply_region_click(cell)
		return
	if bounds.is_empty():
		return
	ed._commit_region_move(bounds, cell - grab, false)


static func apply_tool(ed, cell: Vector2i) -> void:
	var tool := active_tool(ed)
	if tool == ed.Tool.SELECT:
		if ed._selection_mode == &"region":
			ed._apply_region_click(cell)
		else:
			select_cell(ed, cell)
		return  # 选择不是文档编辑，不进入历史。
	if tool == ed.Tool.PICK:
		ed._pick_block(cell)
		return  # 吸管不是文档编辑，不进入历史。
	if tool == ed.Tool.REPLACE:
		ed._set_replace_source_from_cell(cell)
		return  # 防御直接调用：替换工具点击同样只选源。
	var names := {
		ed.Tool.PAINT: "画笔", ed.Tool.FILL: "填充", ed.Tool.ERASE: "橡皮", ed.Tool.UNIT: "角色",
		ed.Tool.PLANT: "植物", ed.Tool.HEIGHT_UP: "地形上升", ed.Tool.HEIGHT_DOWN: "地形下降",
		ed.Tool.ASSET: "素材", ed.Tool.REPLACE: "替换方块", ed.Tool.PICK: "吸管",
	}
	var undo_label: String = names[tool]
	ed._push_undo(undo_label)  # 按下一次=一步；后续拖动不再入栈（整笔一笔撤销）
	match tool:
		ed.Tool.PAINT:
			ed._apply_paint_block(cell)
		ed.Tool.FILL:
			ed._apply_fill(cell)
		ed.Tool.ERASE:
			if ed._remove_unit_at(cell):
				pass  # 单位优先删除
			else:
				ed._set_glyph(cell, ".")
				ed._set_prop(cell, "")
				ed._set_tile_override(cell, "")
				ed._set_prop_asset(cell, "")
		ed.Tool.UNIT:
			if not ed._remove_unit_at(cell):
				ed.place_unit(cell, ed.selected_faction, ed.selected_class, int(ed._level_box.value), ed._unit_name_edit.text)
		ed.Tool.PLANT:
			ed._set_prop(cell, ed.current_prop)
		ed.Tool.ASSET:
			ed._apply_asset_tool(cell)
		ed.Tool.HEIGHT_UP, ed.Tool.HEIGHT_DOWN:
			apply_height_brush(ed, cell, tool)


## 高度画笔只改 block_layout.z；单笔每格至多执行一次，边界由文档 schema 限制。
static func apply_height_brush(ed, cell: Vector2i, tool: int) -> void:
	if ed._height_stroke_cells.has(cell):
		return
	ed._height_stroke_cells[cell] = true
	var delta := 1 if tool == ed.Tool.HEIGHT_UP else -1
	var next_z := clampi(
		BattlefieldDocScript.cell_z(ed.model, cell) + delta,
		BattlefieldDocScript.BLOCK_MIN_Z,
		BattlefieldDocScript.BLOCK_MAX_Z
	)
	if not BattlefieldDocScript.set_cell_z(ed.model, cell, next_z):
		return
	ed._canvas._refresh_cell(cell)
	if ed._canvas.selected_cell == cell:
		sync_block_panel(ed)
	update_cell_info(ed, cell)
	var action := "地形上升" if tool == ed.Tool.HEIGHT_UP else "地形下降"
	ed._status("%s (%d,%d) → z=%d" % [action, cell.x, cell.y, next_z])
	print("[editor] 高度画笔 cell=%s z=%d" % [str(cell), next_z])  # L1 埋点


static func select_cell(ed, cell: Vector2i, activate_block: bool = true) -> void:
	ed._canvas.selected_cell = cell
	sync_block_panel(ed)
	update_cell_info(ed, cell)
	if activate_block and ed._tabs != null:
		ed._tabs.current_tab = ed.TAB_BLOCK


static func on_hover_changed(ed, cell: Vector2i) -> void:
	if ed._paste_mode:
		ed._update_paste_preview(cell)  # 粘贴预览跟随悬停格
	if ed._place_mode:
		ed._update_place_preview(cell)  # 放置预览跟随悬停格
	if cell.x >= 0:
		update_cell_info(ed, cell)
	elif ed._canvas.selected_cell.x >= 0:
		update_cell_info(ed, ed._canvas.selected_cell)
	else:
		update_cell_info(ed, Vector2i(-1, -1))


static func update_cell_info(ed, cell: Vector2i) -> void:
	if ed._cell_info_label == null:
		return
	if cell.x < 0 or cell.y < 0 or cell.x >= int(ed.model.width) or cell.y >= int(ed.model.height):
		ed._cell_info_label.text = "未选中格子"
		return
	var terrain := BattlefieldDocScript.glyph_to_terrain((ed.model.rows[cell.y] as String).substr(cell.x, 1))
	ed._cell_info_label.text = "(%d,%d) · %s · z=%d" % [
		cell.x, cell.y, BattlefieldDocScript.TERRAIN_CN[terrain], BattlefieldDocScript.cell_z(ed.model, cell)
	]


static func sync_block_panel(ed) -> void:
	if ed._block_z_box == null:
		return
	var cell: Vector2i = ed._canvas.selected_cell
	var valid := cell.x >= 0 and cell.y >= 0 and cell.x < int(ed.model.width) and cell.y < int(ed.model.height)
	ed._syncing_block_z = true
	ed._block_z_box.editable = valid
	ed._block_z_box.value = BattlefieldDocScript.cell_z(ed.model, cell) if valid else 0
	ed._syncing_block_z = false


static func on_block_z_changed(ed, value: float) -> void:
	if ed._syncing_block_z or ed._canvas.selected_cell.x < 0:
		return
	var cell: Vector2i = ed._canvas.selected_cell
	ed._push_undo("方块高度")
	if not BattlefieldDocScript.set_cell_z(ed.model, cell, int(value)):
		return
	ed._set_block_slot("fg", {"kind": String(ed._block_fg.kind), "id": String(ed._block_fg.id), "z": int(value)})
	ed._canvas._refresh_cell(cell)
	sync_block_panel(ed)
	update_cell_info(ed, cell)
	ed._status("方块高度 (%d,%d) → z=%d" % [cell.x, cell.y, int(value)])
	print("[editor] 单格高度 cell=%s z=%d" % [str(cell), int(value)])  # L1 埋点


static func sync_selection_after_model_change(ed, clear_selection: bool = false) -> void:
	var cell: Vector2i = ed._canvas.selected_cell
	if clear_selection or cell.x < 0 or cell.y < 0 or cell.x >= int(ed.model.width) or cell.y >= int(ed.model.height):
		ed._canvas.selected_cell = Vector2i(-1, -1)
	else:
		ed._canvas.selected_cell = cell
	sync_block_panel(ed)
	update_cell_info(ed, ed._canvas.selected_cell)
