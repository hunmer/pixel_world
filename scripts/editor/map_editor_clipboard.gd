## map_editor_clipboard.gd — 地图编辑器区域剪贴板与区域移动
##
## 区域复制/剪切/粘贴（粘贴模式 + 幽灵预览 + 提交/取消）、区域内拖动与
## 移动工具的抓取-预览-提交链、方向键逐格平移、状态查询 info。
## 内核全部走 region_clipboard.gd 纯函数；本模块只做门禁、历史与状态栏。
## 全部 static，ed=map_editor 实例；逻辑与原 map_editor.gd 内联实现逐行一致。

class_name MapEditorClipboard
extends RefCounted

const RegionClipboardScript = preload("res://scripts/editor/region_clipboard.gd")
const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const MapEditorModelOpsScript = preload("res://scripts/editor/map_editor_model_ops.gd")
const BuildingLayoutScript = preload("res://scripts/core/building_layout.gd")


## 区域内整栋建筑相对坐标条目（extract 附加；region 内核 validate 容忍额外键）
static func _extract_buildings_payload(model: Dictionary, lo: Vector2i, hi: Vector2i) -> Array:
	var out: Array = []
	for e in BattlefieldDocScript.buildings_fully_within(model, lo, hi):
		out.append({
			"asset_id": String(e.get("asset_id", "")),
			"rotation": int(e.get("rotation", 0)),
			"rx": int(e.get("x", 0)) - lo.x,
			"ry": int(e.get("y", 0)) - lo.y,
		})
	return out


## 已捕获的建筑条目列表 → 相对坐标 payload（cut 场景：模型中已删除，从快照转）
static func _extract_buildings_payload_from(entries: Array, lo: Vector2i) -> Array:
	var out: Array = []
	for e in entries:
		out.append({
			"asset_id": String((e as Dictionary).get("asset_id", "")),
			"rotation": int((e as Dictionary).get("rotation", 0)),
			"rx": int((e as Dictionary).get("x", 0)) - lo.x,
			"ry": int((e as Dictionary).get("y", 0)) - lo.y,
		})
	return out


## 粘贴恢复区域建筑：逐个 can_place 校验（等高按粘贴后高度、不与目标区
## 既有建筑重叠），失败跳过并计数（不静默切碎）；素材快照缺时从素材库补。
## 返回 {placed, skipped}。
static func _restore_buildings(ed, payload: Dictionary, origin: Vector2i) -> Dictionary:
	var placed := 0
	var skipped := 0
	for b in payload.get("buildings", []) as Array:
		if not (b is Dictionary):
			continue
		var asset_id := String((b as Dictionary).get("asset_id", ""))
		if asset_id.is_empty():
			continue
		var target := origin + Vector2i(int((b as Dictionary).get("rx", 0)), int((b as Dictionary).get("ry", 0)))
		var snapshot: Dictionary = MapEditorModelOpsScript.building_assets_snapshot(ed, asset_id)
		var result: Dictionary = BattlefieldDocScript.add_building(
			ed.model, asset_id, target, int((b as Dictionary).get("rotation", 0)), snapshot)
		if bool(result.get("ok", false)):
			placed += 1
		else:
			skipped += 1
	return { "placed": placed, "skipped": skipped }


## 提交区域移动（越界仅报错：不改模型不入历史；成功恰好一步历史）；
## translate=移动工具提交：选区随内容平移到目标（区域内拖动不平移）。
## 区域内整栋建筑随区域平移（保留 instance_id）：先在副本上完整仿真
## （地形移动+删原位建筑+平移重放）逐栋 can_place，任一失败整体拒绝（原子）；
## 跨界建筑留原地不动。
static func commit_region_move(ed, bounds: Array, delta: Vector2i, translate_selection: bool) -> void:
	var lo: Vector2i = bounds[0]
	var hi: Vector2i = bounds[1]
	var err := RegionClipboardScript.bounds_error(ed.model, lo + delta, hi + delta)
	if not err.is_empty():
		ed._status("移动失败：%s" % err, true)
		return
	var moved_buildings := BattlefieldDocScript.buildings_fully_within(ed.model, lo, hi)
	# —— sim 统一预校验：地形移动可行 + 随移建筑落位合法 + 平移后单位不进建筑 ——
	var sim: Dictionary = ed.model.duplicate(true)
	var sim_move: Dictionary = RegionClipboardScript.move(sim, lo, hi, delta)
	if not bool(sim_move.get("ok", false)):
		ed._status("移动失败：%s" % String(sim_move.get("error", "")), true)
		return
	for b in moved_buildings:
		BattlefieldDocScript.remove_building(sim, String((b as Dictionary).get("instance_id", "")))
	# 计划占用 = sim 剩余建筑（跨界留在原地）+ 随移建筑平移后的占用
	var planned_occ := BattlefieldDocScript.building_occupancy(sim)
	for b in moved_buildings:
		var mb: Dictionary = b as Dictionary
		var nb := mb.duplicate(true)
		nb["x"] = int(nb.get("x", 0)) + delta.x
		nb["y"] = int(nb.get("y", 0)) + delta.y
		var berr := BattlefieldDocScript.can_place_building(
			sim, String(mb.get("asset_id", "")),
			Vector2i(int(nb.get("x", 0)), int(nb.get("y", 0))),
			int(mb.get("rotation", 0)))
		if not berr.is_empty():
			ed._status("移动失败：建筑 %s %s" % [String(mb.get("instance_id", "")), berr], true)
			return
		for cell in BuildingLayoutScript.occupied_cells(nb, sim.get("user_assets", {}) as Dictionary):
			planned_occ[BuildingLayoutScript.cell_key(cell.x, cell.y)] = String(mb.get("instance_id", ""))
	# sim.units 已被 move 平移到目标位：逐个对照计划占用
	for unit_value in sim.get("units", []) as Array:
		var unit: Dictionary = unit_value
		var k := BuildingLayoutScript.cell_key(int(unit.get("x", -1)), int(unit.get("y", -1)))
		if planned_occ.has(k):
			ed._status("移动失败：单位 %s 目标格被建筑 %s 占用，请换位置" % [
				String(unit.get("name", "?")), String(planned_occ[k])], true)
			return
	ed._push_undo("移动区域")
	var result: Dictionary = RegionClipboardScript.move(ed.model, lo, hi, delta)
	# 建筑平移重放：删原位（含 user_assets 快照原样保留），原 instance_id 追加平移条目
	for b in moved_buildings:
		BattlefieldDocScript.remove_building(ed.model, String((b as Dictionary).get("instance_id", "")))
	for b in moved_buildings:
		var nb := (b as Dictionary).duplicate(true)
		nb["x"] = int(nb.get("x", 0)) + delta.x
		nb["y"] = int(nb.get("y", 0)) + delta.y
		(BattlefieldDocScript.building_entries(ed.model) as Array).append(nb)
	if translate_selection and ed._selection_range.is_active():
		ed._selection_range.anchor += Vector3i(delta.x, delta.y, 0)
		ed._selection_range.focus += Vector3i(delta.x, delta.y, 0)
	ed._refresh_canvas()
	ed._sync_region_marker()
	var dropped := int(result.get("dropped_units", 0))
	var suffix := "（%d 个单位因地形不可站立被丢弃）" % dropped if dropped > 0 else ""
	if not moved_buildings.is_empty():
		suffix += "（建筑 %d 栋随移）" % moved_buildings.size()
	ed._status("已移动区域 → (%d,%d)%s" % [lo.x + delta.x, lo.y + delta.y, suffix])
	print("[editor] 移动区域 min=%s delta=%s dropped_units=%d buildings=%d" % [
		str(lo), str(delta), dropped, moved_buildings.size()])  # L1 埋点


## 方向键逐格平移：复用移动提交（一步历史+选区跟随）；无完整选区仅中文提示
static func nudge_region(ed, delta: Vector2i) -> void:
	var bounds: Array = ed._move_tool_bounds()
	if bounds.is_empty():
		ed._status("移动工具：请先框选一个区域", true)
		return
	commit_region_move(ed, bounds, delta, true)


## 移动工具模式 _move_grab=抓取偏移（delta=悬停格-偏移-选区 min）；
## 区域内拖动 _move_grab=按下格（delta=悬停格-按下格）
static func move_delta_for(ed, cell: Vector2i) -> Vector2i:
	if ed._move_tool_active:
		var bounds: Array = ed._move_tool_bounds()
		if bounds.is_empty():
			return Vector2i.ZERO
		return cell - ed._move_grab - (bounds[0] as Vector2i)
	return cell - ed._move_grab


## 移动预览：原区域矩形平移 delta（=悬停格-按下格），合法=绿框/越界=红框
static func update_move_preview(ed, hover: Vector2i) -> void:
	if ed._canvas == null or not ed._move_armed:
		return
	var bounds: Array = ed._move_tool_bounds() if ed._move_tool_active else ed._region_2d_bounds()
	if bounds.is_empty():
		return
	var delta := move_delta_for(ed, hover)
	var lo: Vector2i = bounds[0] + delta
	var hi: Vector2i = bounds[1] + delta
	ed._canvas.set_paste_preview(lo, hi, RegionClipboardScript.bounds_error(ed.model, lo, hi).is_empty())


## 复制区域：extract 入剪贴板，不入历史（模型不变）
static func on_region_copy_pressed(ed) -> void:
	var bounds: Array = ed._region_2d_bounds()
	if bounds.is_empty():
		ed._status("区域未完整（需两次点击画布设置 pos1/pos2）", true)
		return
	var payload := RegionClipboardScript.extract(ed.model, bounds[0], bounds[1])
	if payload.is_empty():
		ed._status("复制失败：区域越界", true)
		return
	# 完全在内的建筑整栋随区域走（相对坐标）；跨界建筑不收（留原地不切碎）
	var buildings_payload := _extract_buildings_payload(ed.model, bounds[0], bounds[1])
	if not buildings_payload.is_empty():
		payload["buildings"] = buildings_payload
	ed._clipboard = payload
	var b_suffix := " · 建筑 %d" % buildings_payload.size() if not buildings_payload.is_empty() else ""
	ed._status("已复制 %s%s（CTRL+V 粘贴）" % [RegionClipboardScript.describe(payload), b_suffix])
	print("[editor] 复制区域 %s%s" % [RegionClipboardScript.describe(payload), b_suffix])  # L1 埋点


## 剪切区域：extract + clear_rect，一步历史（成功才入栈）
static func on_region_cut_pressed(ed) -> void:
	var bounds: Array = ed._region_2d_bounds()
	if bounds.is_empty():
		ed._status("区域未完整（需两次点击画布设置 pos1/pos2）", true)
		return
	var payload := RegionClipboardScript.extract(ed.model, bounds[0], bounds[1])
	if payload.is_empty():
		ed._status("剪切失败：区域越界", true)
		return
	var err := RegionClipboardScript.bounds_error(ed.model, bounds[0], bounds[1])
	if not err.is_empty():
		ed._status("剪切失败：%s" % err, true)
		return
	ed._push_undo("剪切区域")
	# 建筑整栋随剪切走：完全在内的删除（随剪贴板可粘贴回来）；
	# 跨界建筑留原地（内核 clear_rect/_remove_entities 均不动建筑层）
	var moved_buildings := BattlefieldDocScript.buildings_fully_within(ed.model, bounds[0], bounds[1])
	var kept_count := BattlefieldDocScript.building_entries(ed.model).size() - moved_buildings.size()
	var dropped_buildings := 0
	for b in moved_buildings:
		if BattlefieldDocScript.remove_building(ed.model, String(b.get("instance_id", ""))):
			dropped_buildings += 1
	if dropped_buildings > 0:
		payload["buildings"] = _extract_buildings_payload_from(moved_buildings, bounds[0])
	RegionClipboardScript.clear_rect(ed.model, bounds[0], bounds[1])
	ed._clipboard = payload
	ed._refresh_canvas()
	ed._sync_region_marker()
	var b_note := ""
	if dropped_buildings > 0:
		b_note = " · 建筑 %d" % dropped_buildings
		if kept_count > 0:
			b_note += "（跨界的 %d 栋保留原地）" % kept_count
	ed._status("已剪切 %s%s（CTRL+V 粘贴）" % [RegionClipboardScript.describe(payload), b_note])
	print("[editor] 剪切区域 %s%s" % [RegionClipboardScript.describe(payload), b_note])  # L1 埋点


## 粘贴区域：空剪贴板报错；否则进入粘贴模式，预览框跟随悬停格
static func on_region_paste_pressed(ed) -> void:
	if ed._clipboard.is_empty():
		ed._status("剪贴板为空（先复制或剪切一个区域）", true)
		return
	ed._cancel_place_mode()  # 与放置模式互斥
	ed._paste_mode = true
	ed._paste_origin = Vector2i(-1, -1)
	update_paste_preview(ed, ed._canvas.hover_cell if ed._canvas != null else Vector2i(-1, -1))
	ed._status("粘贴模式：移动鼠标选择落点，点击画布提交，ESC 取消")
	print("[editor] 进入粘贴模式 %s" % RegionClipboardScript.describe(ed._clipboard))  # L1 埋点


## 粘贴预览随悬停格刷新：展开真实方块幽灵；只画地图内格，整体越界标红。
static func update_paste_preview(ed, hover: Vector2i) -> void:
	if ed._canvas == null or not ed._paste_mode or ed._clipboard.is_empty():
		return
	ed._paste_origin = hover
	if hover.x < 0:
		ed._canvas.clear_paste_preview()
		return
	ed._canvas.set_placement_preview(ed._clipboard, hover)


## 粘贴 payload.units 平移目标格 vs 模型既有建筑占用；返回冲突格描述（"" = 无冲突）
static func _units_conflict_buildings(model: Dictionary, payload: Dictionary, origin: Vector2i) -> String:
	var occ := BattlefieldDocScript.building_occupancy(model)
	var hits: Array = []
	for unit_value in payload.get("units", []) as Array:
		var unit: Dictionary = unit_value
		var target := origin + Vector2i(int(unit.get("dx", 0)), int(unit.get("dy", 0)))
		var k := BuildingLayoutScript.cell_key(target.x, target.y)
		if occ.has(k):
			hits.append("%s（建筑 %s）" % [str(target), String(occ[k])])
	if hits.is_empty():
		return ""
	return "、".join(hits)


## 提交粘贴：越界/非法仅 _status 报错（不改模型不入历史）；成功一步历史
static func commit_paste(ed, origin: Vector2i) -> void:
	var size := RegionClipboardScript.payload_size(ed._clipboard)
	var lo := origin
	var hi := origin + size - Vector2i(1, 1)
	var err := RegionClipboardScript.bounds_error(ed.model, lo, hi)
	if not err.is_empty():
		ed._status("粘贴失败：%s" % err, true)
		return
	# 单位目标格不得落在既有建筑上（原子拒绝：不写模型不入历史）
	var units_block := _units_conflict_buildings(ed.model, ed._clipboard, lo)
	if not units_block.is_empty():
		ed._status("粘贴失败：单位目标格被建筑占用 %s，请换位置" % units_block, true)
		return
	ed._push_undo("粘贴区域")
	var result: Dictionary = RegionClipboardScript.paste(ed.model, ed._clipboard, lo)
	# 区域建筑恢复：粘贴后的地形/高度已就位，can_place 按最终状态校验
	var restored := _restore_buildings(ed, ed._clipboard, lo)
	cancel_paste(ed)
	ed._refresh_canvas()
	ed._sync_region_marker()
	var dropped := int(result.get("dropped_units", 0))
	var suffix := "（%d 个单位因地形不可站立被丢弃）" % dropped if dropped > 0 else ""
	if restored.skipped > 0:
		suffix += "（%d 栋建筑无法落下被跳过）" % int(restored.skipped)
	ed._status("已粘贴 %s%s" % [RegionClipboardScript.describe(ed._clipboard), suffix])
	print("[editor] 粘贴区域 origin=%s dropped_units=%d buildings=%d/%d" % [
		str(lo), dropped, int(restored.placed), int(restored.placed) + int(restored.skipped)])  # L1 埋点


## 取消粘贴/移动预览（ESC 或提交后调用；剪贴板内容保留，可再次粘贴）
static func cancel_paste(ed) -> void:
	ed._paste_mode = false
	ed._paste_origin = Vector2i(-1, -1)
	ed._move_armed = false
	ed._move_grab = Vector2i(-1, -1)
	ed._move_preview = Vector2i(-1, -1)
	if ed._canvas != null:
		ed._canvas.clear_paste_preview()


## 移动工具开关（左侧工具栏 MoveToolToggle toggled）：写回状态并提示
static func on_move_tool_toggled(ed, pressed: bool) -> void:
	set_move_tool(ed, pressed)
	ed._status("移动工具：%s" % ("开" if pressed else "关"))


## 同步移动工具状态（含开关无信号回写）；关闭时清待移动/预览
static func set_move_tool(ed, active: bool) -> void:
	if active and ed.get("_building_place_mode") == true:
		ed._cancel_place_mode()
	ed._move_tool_active = active
	if ed._move_tool_toggle != null and ed._move_tool_toggle.button_pressed != active:
		ed._move_tool_toggle.set_pressed_no_signal(active)
	if not active:
		ed._move_armed = false
		ed._move_grab = Vector2i(-1, -1)
		ed._move_preview = Vector2i(-1, -1)
		if ed._canvas != null:
			ed._canvas.clear_paste_preview()


static func region_clipboard_info(ed) -> Dictionary:
	var info := {
		"has_clipboard": not ed._clipboard.is_empty(),
		"paste_mode": ed._paste_mode,
		"place_preview": ed._place_preview_enabled,
		"move_armed": ed._move_armed,
		"move_tool": ed._move_tool_active,
		"history_len": ed._history.size(),
		"w": 0, "h": 0, "units": 0, "props": 0, "overrides": 0, "buildings": 0,
	}
	if not ed._clipboard.is_empty():
		var size := RegionClipboardScript.payload_size(ed._clipboard)
		info["w"] = size.x
		info["h"] = size.y
		info["units"] = (ed._clipboard.get("units", []) as Array).size()
		info["props"] = (ed._clipboard.get("props", []) as Array).size()
		info["overrides"] = (ed._clipboard.get("tile_overrides", {}) as Dictionary).size()
		info["buildings"] = (ed._clipboard.get("buildings", []) as Array).size()
	return info
