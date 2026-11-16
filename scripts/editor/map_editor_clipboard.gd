## map_editor_clipboard.gd — 地图编辑器区域剪贴板与区域移动
##
## 区域复制/剪切/粘贴（粘贴模式 + 幽灵预览 + 提交/取消）、区域内拖动与
## 移动工具的抓取-预览-提交链、方向键逐格平移、状态查询 info。
## 内核全部走 region_clipboard.gd 纯函数；本模块只做门禁、历史与状态栏。
## 全部 static，ed=map_editor 实例；逻辑与原 map_editor.gd 内联实现逐行一致。

class_name MapEditorClipboard
extends RefCounted

const RegionClipboardScript = preload("res://scripts/editor/region_clipboard.gd")


## 提交区域移动（越界仅报错：不改模型不入历史；成功恰好一步历史）；
## translate=移动工具提交：选区随内容平移到目标（区域内拖动不平移）
static func commit_region_move(ed, bounds: Array, delta: Vector2i, translate_selection: bool) -> void:
	var lo: Vector2i = bounds[0]
	var hi: Vector2i = bounds[1]
	var err := RegionClipboardScript.bounds_error(ed.model, lo + delta, hi + delta)
	if not err.is_empty():
		ed._status("移动失败：%s" % err, true)
		return
	ed._push_undo("移动区域")
	var result: Dictionary = RegionClipboardScript.move(ed.model, lo, hi, delta)
	if translate_selection and ed._selection_range.is_active():
		ed._selection_range.anchor += Vector3i(delta.x, delta.y, 0)
		ed._selection_range.focus += Vector3i(delta.x, delta.y, 0)
	ed._refresh_canvas()
	ed._sync_region_marker()
	var dropped := int(result.get("dropped_units", 0))
	var suffix := "（%d 个单位因地形不可站立被丢弃）" % dropped if dropped > 0 else ""
	ed._status("已移动区域 → (%d,%d)%s" % [lo.x + delta.x, lo.y + delta.y, suffix])
	print("[editor] 移动区域 min=%s delta=%s dropped_units=%d" % [str(lo), str(delta), dropped])  # L1 埋点


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
	ed._clipboard = payload
	ed._status("已复制 %s（CTRL+V 粘贴）" % RegionClipboardScript.describe(payload))
	print("[editor] 复制区域 %s" % RegionClipboardScript.describe(payload))  # L1 埋点


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
	RegionClipboardScript.clear_rect(ed.model, bounds[0], bounds[1])
	ed._clipboard = payload
	ed._refresh_canvas()
	ed._sync_region_marker()
	ed._status("已剪切 %s（CTRL+V 粘贴）" % RegionClipboardScript.describe(payload))
	print("[editor] 剪切区域 %s" % RegionClipboardScript.describe(payload))  # L1 埋点


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
	var ghost := RegionClipboardScript.ghost_at(ed.model, ed._clipboard, hover)
	ed._canvas.set_placement_preview(ghost.cells, ghost.valid)


## 提交粘贴：越界/非法仅 _status 报错（不改模型不入历史）；成功一步历史
static func commit_paste(ed, origin: Vector2i) -> void:
	var size := RegionClipboardScript.payload_size(ed._clipboard)
	var lo := origin
	var hi := origin + size - Vector2i(1, 1)
	var err := RegionClipboardScript.bounds_error(ed.model, lo, hi)
	if not err.is_empty():
		ed._status("粘贴失败：%s" % err, true)
		return
	ed._push_undo("粘贴区域")
	var result: Dictionary = RegionClipboardScript.paste(ed.model, ed._clipboard, lo)
	cancel_paste(ed)
	ed._refresh_canvas()
	ed._sync_region_marker()
	var dropped := int(result.get("dropped_units", 0))
	var suffix := "（%d 个单位因地形不可站立被丢弃）" % dropped if dropped > 0 else ""
	ed._status("已粘贴 %s%s" % [RegionClipboardScript.describe(ed._clipboard), suffix])
	print("[editor] 粘贴区域 origin=%s dropped_units=%d" % [str(lo), dropped])  # L1 埋点


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
		"w": 0, "h": 0, "units": 0, "props": 0, "overrides": 0,
	}
	if not ed._clipboard.is_empty():
		var size := RegionClipboardScript.payload_size(ed._clipboard)
		info["w"] = size.x
		info["h"] = size.y
		info["units"] = (ed._clipboard.get("units", []) as Array).size()
		info["props"] = (ed._clipboard.get("props", []) as Array).size()
		info["overrides"] = (ed._clipboard.get("tile_overrides", {}) as Dictionary).size()
	return info
