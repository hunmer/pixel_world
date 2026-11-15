## tests/map_editor_region_ops_contract.gd — 地图编辑器区域剪贴板（复制/剪切/粘贴/拖动移动）契约
##
## 跑法：godot --headless --path . --script res://tests/map_editor_region_ops_contract.gd
## 覆盖：选择模式菜单新增 RegionOpRow（复制/剪切/粘贴三按钮 + 快捷键提示）；
##       区域未完整 / 剪贴板为空 → 中文拒绝（不改模型、不入历史）；
##       复制 → 粘贴模式（预览跟随悬停、绿/红框）→ 点击提交：五层内容
##       （rows 地形 / block_z 高度 / tile_overrides 覆盖 / props 植物 / units 单位）
##       整体落位、恰好一步历史、_undo 原子回滚；
##       区域内按下拖动 = 移动区域（预览随拖动刷新，同样一步历史 + 回滚）；
##       拖动不设区域端点（既有契约）；原地松开仍走第三次点击重置 pos1（既有契约）；
##       越界粘贴拒绝（模型 / 历史不动）；ESC 取消粘贴预览；
##       Ctrl+C/X/V 快捷键派发；剪切一步历史；生成清空剪贴板；
##       region_clipboard_info() 只读快照；工具条 8 钮（7 工具+移动开关）、ModeOption 仍 2 项。
##       左侧工具栏移动工具（MoveToolToggle，ToolBox 第 8 钮）：无完整选区中文拒绝；开启后拖拽平移选区
##       （选区跟随、恰好一步历史、可回滚）；原地松开=纯点击不触发区域选择；
##       关闭后回到区域内拖动/两次点击语义（第三次点击重置 pos1 不回退）。
##       方向键（上/下/左/右 = y-/y+/x-/x+）逐格平移选区：仅移动工具开启时生效，
##       每键恰好一步历史、选区跟随；顶边越界仅报错零变化；工具关闭时零动作。

extends SceneTree

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var editor = load("res://scenes/MapEditor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor.apply_generate("region_ops", 10, 8)
	await process_frame
	editor.current_tool = editor.Tool.SELECT

	# ---- A. 既有契约不回退 + 区域操作按钮存在 ----
	var toolbar: Node = editor.get_node_or_null("EditorRoot/CanvasHolder/ToolBar/ToolBox")
	_expect(toolbar != null and toolbar.get_child_count() == 8,
		"A 工具条为 8 个按钮（7 工具 + 移动开关，用户已取消 7 钮契约）")
	var popup: Control = editor.get_node_or_null("SelectionPopup")
	_expect(popup != null and not popup.visible, "A 选择菜单存在且默认隐藏")
	if popup == null:
		_finish(editor)
		return
	var sel_box: VBoxContainer = popup.get_node_or_null("SelectionPopupBox")
	var mode_opt := sel_box.get_node_or_null("ModeOption") if sel_box != null else null
	_expect(mode_opt is OptionButton and (mode_opt as OptionButton).item_count == 2,
		"A 模式菜单仍为 单格/区域 两项")
	_expect(sel_box != null and sel_box.get_node_or_null("RegionOpRow/CopyRegionBtn") is Button
		and sel_box.get_node_or_null("RegionOpRow/CutRegionBtn") is Button
		and sel_box.get_node_or_null("RegionOpRow/PasteRegionBtn") is Button,
		"A 复制/剪切/粘贴三按钮齐全（RegionOpRow）")
	_expect(sel_box != null and sel_box.get_node_or_null("RegionOpHint") is Label,
		"A 区域操作快捷键提示存在")

	# ---- B. 区域未完整 / 剪贴板为空 → 中文拒绝，不改模型不入历史 ----
	editor._on_selection_mode_item(1)
	editor._apply_region_click(Vector2i(1, 1))
	_expect(editor._selection_range.is_active() and not editor._region_pos2_set,
		"B 第一次点击置 pos1（区域未完备）")
	editor._seal_pending()
	var h0: int = editor._history.size()
	var m0: Dictionary = editor.model.duplicate(true)
	editor._on_region_copy_pressed()
	_expect(String(editor._status_label.text).contains("区域未完整"),
		"B 未完备复制 → 状态栏中文拒绝")
	editor._on_region_cut_pressed()
	_expect(String(editor._status_label.text).contains("区域未完整"),
		"B 未完备剪切 → 状态栏中文拒绝")
	editor._on_region_paste_pressed()
	_expect(String(editor._status_label.text).contains("剪贴板为空"),
		"B 空剪贴板粘贴 → 状态栏中文拒绝")
	var info0: Dictionary = editor.region_clipboard_info()
	_expect(not bool(info0["has_clipboard"]) and int(info0["history_len"]) == h0
		and editor.model == m0 and editor._history.size() == h0,
		"B 三类拒绝均不改模型、不入历史（info.has_clipboard=false）")

	# ---- C. 复制 → 粘贴 → 提交：五层落位、一步历史、撤销回滚 ----
	editor._apply_region_click(Vector2i(4, 3))
	_expect(editor._region_pos2_set, "C 第二次点击完备区域 (1,1)-(4,3)")
	# 源区域铺五层内容：地形 g / 高度 z=3 / 覆盖素材 / 植物 / 单位
	editor._set_glyph(Vector2i(1, 1), "g")
	BattlefieldDocScript.set_cell_z(editor.model, Vector2i(2, 2), 3)
	BattlefieldDocScript.set_tile_override(editor.model, Vector2i(3, 2), "asset_grass_block")
	BattlefieldDocScript.set_prop(editor.model, Vector2i(2, 1), "tree")
	(editor.model.units as Array).append({
		"class": "warrior", "name": "契约探员", "level": 3,
		"x": 1, "y": 1, "faction": "player",
	})
	editor._seal_pending()
	# 布景入史：五层直改模型后手动封存为历史条目，撤销「粘贴」才有可比对的回滚点
	editor._push_undo("布景五层")
	editor._seal_pending()
	var h1: int = editor._history.size()
	var before_paste: Dictionary = editor.model.duplicate(true)
	editor._on_region_copy_pressed()
	var info1: Dictionary = editor.region_clipboard_info()
	_expect(bool(info1["has_clipboard"]) and int(info1["w"]) == 4 and int(info1["h"]) == 3
		and int(info1["units"]) == 1 and int(info1["props"]) == 1
		and int(info1["overrides"]) == 1 and int(info1["history_len"]) == h1,
		"C 复制入剪贴板 4×3·单位1·植物1·覆盖1，且不入历史")
	editor._on_region_paste_pressed()
	_expect(bool(editor.region_clipboard_info()["paste_mode"]),
		"C 粘贴模式开启")
	editor._on_hover_changed(Vector2i(6, 1))
	_expect(editor._canvas.has_paste_preview(),
		"C 粘贴预览跟随悬停格出现")
	editor._on_cell_pressed(Vector2i(6, 1))
	var info2: Dictionary = editor.region_clipboard_info()
	_expect(not bool(info2["paste_mode"]) and not editor._canvas.has_paste_preview(),
		"C 点击提交后粘贴模式与预览均关闭")
	editor._seal_pending()
	_expect(editor._history.size() == h1 + 1
		and String(editor._history[editor._history_cursor]["label"]) == "粘贴区域",
		"C 粘贴恰好一步历史（标签「粘贴区域」）")
	_expect((editor.model.rows[1] as String).substr(6, 1) == "g"
		and BattlefieldDocScript.cell_z(editor.model, Vector2i(7, 2)) == 3
		and BattlefieldDocScript.tile_override_at(editor.model, Vector2i(8, 2)) == "asset_grass_block"
		and BattlefieldDocScript.prop_at(editor.model, Vector2i(7, 1)) == "tree",
		"C 目标区 (6,1)-(9,3)：地形/高度/覆盖/植物 四层整体落位")
	var moved_unit: Dictionary = {}
	for u in editor.model.units:
		if int(u.x) == 6 and int(u.y) == 1:
			moved_unit = u
	_expect(not moved_unit.is_empty() and String(moved_unit.get("name", "")) == "契约探员"
		and int(moved_unit.get("level", 0)) == 3
		and String(moved_unit.get("faction", "")) == "player"
		and String(editor._status_label.text).contains("已粘贴"),
		"C 单位层随区域落到 (6,1)，状态栏报告粘贴结果")
	editor._undo()
	_expect(editor.model == before_paste,
		"C 撤销粘贴 → 五层整体回滚（与粘贴前逐层相等）")

	# ---- D. 区域内按下拖动 = 移动区域：一步历史 + 回滚；拖动不设端点 ----
	editor._seal_pending()
	var before_move: Dictionary = editor.model.duplicate(true)
	var corner_before_min: Vector3i = editor._selection_range.min_corner()
	var corner_before_max: Vector3i = editor._selection_range.max_corner()
	var d_cursor0: int = editor._history_cursor
	editor._on_cell_pressed(Vector2i(2, 2))
	_expect(bool(editor.region_clipboard_info()["move_armed"])
		and editor._region_pos2_set
		and editor._selection_range.min_corner() == corner_before_min,
		"D 区域内按下进入待移动，不触发端点变化")
	editor._on_cell_dragged(Vector2i(7, 4))
	_expect(editor._canvas.has_paste_preview()
		and editor._selection_range.min_corner() == corner_before_min
		and editor._selection_range.max_corner() == corner_before_max,
		"D 拖动出现移动预览，且区域端点保持（拖动仍不设端点）")
	editor._on_cell_released(Vector2i(7, 4))
	_expect(not bool(editor.region_clipboard_info()["move_armed"]),
		"D 释放后移动 armed 复位")
	editor._seal_pending()
	_expect(editor._history_cursor == d_cursor0 + 1
		and editor._history.size() == editor._history_cursor + 1
		and String(editor._history[editor._history_cursor]["label"]) == "移动区域",
		"D 移动区域恰好一步历史（游标+1、标签「移动区域」、截断重做分支后无冗余条目）")
	_expect((editor.model.rows[3] as String).substr(6, 1) == "g"
		and BattlefieldDocScript.cell_z(editor.model, Vector2i(7, 4)) == 3
		and BattlefieldDocScript.tile_override_at(editor.model, Vector2i(8, 4)) == "asset_grass_block"
		and BattlefieldDocScript.prop_at(editor.model, Vector2i(7, 3)) == "tree",
		"D 区域平移 (+5,+2)：四层内容落位到 (6,3)-(9,5)")
	var moved_unit2: Dictionary = {}
	for u in editor.model.units:
		if int(u.x) == 6 and int(u.y) == 3:
			moved_unit2 = u
	_expect(not moved_unit2.is_empty() and String(moved_unit2.get("name", "")) == "契约探员",
		"D 单位层随区域平移到 (6,3)")
	_expect(BattlefieldDocScript.prop_at(editor.model, Vector2i(2, 1)) == ""
		and BattlefieldDocScript.tile_override_at(editor.model, Vector2i(3, 2)) == ""
		and (editor.model.rows[1] as String).substr(1, 1) == ".",
		"D 源区域被清空（植物/覆盖/地形还原）")
	editor._undo()
	_expect(editor.model == before_move,
		"D 撤销移动 → 区域五层整体回滚")

	# ---- E. 原地松开 = 纯点击：第三次点击重置 pos1（既有契约不回退） ----
	editor._on_cell_pressed(Vector2i(2, 2))
	editor._on_cell_released(Vector2i(2, 2))
	_expect(not editor._region_pos2_set and editor._selection_range.is_active()
		and editor._selection_range.min_corner() == editor._selection_range.max_corner(),
		"E 区域内原地点击松开仍走区域点击：完备区域被重置为新 pos1 单点")

	# ---- F. 越界粘贴拒绝（模型/历史不动）+ ESC 取消 ----
	editor._apply_region_click(Vector2i(9, 6))
	_expect(editor._region_pos2_set, "F 重新完备区域 (2,2)-(9,6)")
	editor._on_region_copy_pressed()
	_expect(bool(editor.region_clipboard_info()["has_clipboard"]), "F 复制 8×5 入剪贴板")
	editor._seal_pending()
	var h3: int = editor._history.size()
	var m3: Dictionary = editor.model.duplicate(true)
	editor._on_region_paste_pressed()
	editor._on_hover_changed(Vector2i(8, 1))
	editor._on_cell_pressed(Vector2i(8, 1))
	_expect(String(editor._status_label.text).contains("粘贴失败")
		and editor.model == m3 and editor._history.size() == h3,
		"F 越界粘贴拒绝：中文报错、模型与历史均不动")
	_expect(bool(editor.region_clipboard_info()["paste_mode"])
		and editor._canvas.has_paste_preview(),
		"F 拒绝后仍处粘贴模式（可挪落点重试）")
	_send_key(editor, KEY_ESCAPE)
	_expect(not bool(editor.region_clipboard_info()["paste_mode"])
		and not editor._canvas.has_paste_preview(),
		"F ESC 取消粘贴模式与预览")

	# ---- G. Ctrl+C/X 快捷键派发 + 剪切一步历史 ----
	editor._clipboard.clear()
	var g_cursor0: int = editor._history_cursor
	_send_key(editor, KEY_C, true)
	_expect(bool(editor.region_clipboard_info()["has_clipboard"]),
		"G Ctrl+C 复制当前区域入剪贴板")
	_send_key(editor, KEY_X, true)
	editor._seal_pending()
	_expect(editor._history_cursor == g_cursor0 + 1
		and editor._history.size() == editor._history_cursor + 1
		and String(editor._history[editor._history_cursor]["label"]) == "剪切区域"
		and BattlefieldDocScript.tile_override_at(editor.model, Vector2i(3, 2)) == ""
		and BattlefieldDocScript.cell_z(editor.model, Vector2i(2, 2)) != 3,
		"G Ctrl+X 剪切：一步历史「剪切区域」，源区域内 (2,2)-(9,6) 被清空")
	editor._undo()
	_send_key(editor, KEY_V, true)
	_expect(bool(editor.region_clipboard_info()["paste_mode"]),
		"G Ctrl+V 进入粘贴模式（剪贴板在剪切后保留）")
	_send_key(editor, KEY_ESCAPE)

	# ---- H. 生成清空剪贴板与预览 ----
	editor.apply_generate("region_ops_clear", 6, 6)
	await process_frame
	var info3: Dictionary = editor.region_clipboard_info()
	_expect(not bool(info3["has_clipboard"]) and not bool(info3["paste_mode"])
		and not bool(info3["move_armed"]) and not editor._canvas.has_paste_preview(),
		"H 生成新地形 → 剪贴板/粘贴模式/移动预览全部清空")

	# ---- I. 左侧工具栏移动工具：开关 + 拖拽平移选区 + 原地松开不触发区域选择 ----
	var mt_toggle := editor.find_child("MoveToolToggle", true, false) as BaseButton
	_expect(mt_toggle != null and mt_toggle.icon != null,
		"移动工具开关是带图标的按钮（control/move 图标）")
	var mt_box: Node = mt_toggle.get_parent() if mt_toggle != null else null
	_expect(mt_box != null and mt_box.name == "ToolBox"
		and not mt_toggle.button_pressed,
		"I 移动工具开关位于左侧 ToolBox（第 8 钮），默认关闭")
	if mt_toggle == null:
		_finish(editor)
		return
	mt_toggle.button_pressed = true  # 触发 toggled → 开启移动工具
	_expect(bool(editor.region_clipboard_info()["move_tool"]),
		"I 开启后 region_clipboard_info().move_tool=true")
	# I-② 无完整选区：按下只给中文提示，不改选区/历史/不 armed
	editor._on_region_clear_pressed()
	editor._seal_pending()
	var i_h0: int = editor._history.size()
	editor._on_cell_pressed(Vector2i(2, 2))
	_expect(String(editor._status_label.text).contains("请先框选")
		and not editor._selection_range.is_active()
		and not bool(editor.region_clipboard_info()["move_armed"])
		and editor._history.size() == i_h0,
		"I 无完整选区时按下 → 中文提示，选区/历史/armed 均不变")
	# I-③ 建区域 + 五层布景 → 拖拽平移（选区跟随）→ 一步历史 + 回滚
	editor._apply_region_click(Vector2i(1, 1))
	editor._apply_region_click(Vector2i(4, 3))
	editor._set_glyph(Vector2i(1, 1), "g")
	BattlefieldDocScript.set_cell_z(editor.model, Vector2i(2, 2), 3)
	BattlefieldDocScript.set_tile_override(editor.model, Vector2i(3, 2), "asset_grass_block")
	BattlefieldDocScript.set_prop(editor.model, Vector2i(2, 1), "tree")
	(editor.model.units as Array).append({
		"class": "warrior", "name": "契约探员", "level": 3,
		"x": 1, "y": 1, "faction": "player",
	})
	editor._seal_pending()
	editor._push_undo("布景五层I")
	editor._seal_pending()
	var i_cursor0: int = editor._history_cursor
	var i_before: Dictionary = editor.model.duplicate(true)
	var i_min0: Vector3i = editor._selection_range.min_corner()
	var i_max0: Vector3i = editor._selection_range.max_corner()
	editor._on_cell_pressed(Vector2i(2, 2))
	_expect(bool(editor.region_clipboard_info()["move_armed"])
		and editor._selection_range.min_corner() == i_min0
		and editor._selection_range.max_corner() == i_max0
		and editor._region_pos2_set,
		"I 工具开启：按下进入待移动，端点不变（未触发区域点击/未重置 pos1）")
	editor._on_cell_dragged(Vector2i(3, 3))
	_expect(editor._canvas.has_paste_preview(),
		"I 拖到 (3,3) 出现移动预览（相对按下格 +1,+1，落点合法=绿框）")
	editor._on_cell_released(Vector2i(3, 3))
	editor._seal_pending()
	_expect(editor._history_cursor == i_cursor0 + 1
		and editor._history.size() == editor._history_cursor + 1
		and String(editor._history[editor._history_cursor]["label"]) == "移动区域",
		"I 松开提交移动：恰好一步历史「移动区域」（截断重做分支后无冗余条目）")
	_expect((editor.model.rows[2] as String).substr(2, 1) == "g"
		and BattlefieldDocScript.cell_z(editor.model, Vector2i(3, 3)) == 3
		and BattlefieldDocScript.tile_override_at(editor.model, Vector2i(4, 3)) == "asset_grass_block"
		and BattlefieldDocScript.prop_at(editor.model, Vector2i(3, 2)) == "tree",
		"I 五层内容平移 (+1,+1) 到 (2,2)-(5,4)")
	var i_unit: Dictionary = {}
	for u in editor.model.units:
		if int(u.x) == 2 and int(u.y) == 2:
			i_unit = u
	_expect(not i_unit.is_empty() and String(i_unit.get("name", "")) == "契约探员",
		"I 单位层平移到 (2,2)")
	var i_min_after: Vector3i = editor._selection_range.min_corner()
	var i_max_after: Vector3i = editor._selection_range.max_corner()
	_expect(Vector2i(i_min_after.x, i_min_after.y) == Vector2i(2, 2)
		and Vector2i(i_max_after.x, i_max_after.y) == Vector2i(5, 4),
		"I 选区随内容平移到目标 (2,2)-(5,4)")
	editor._undo()
	_expect(editor.model == i_before,
		"I 撤销移动 → 五层整体回滚")
	# I-④ 原地按下松开：不产生历史、不改模型、不触发区域选择
	editor._seal_pending()
	var i_h4: int = editor._history.size()
	var i_m4: Dictionary = editor.model.duplicate(true)
	var i_min4: Vector3i = editor._selection_range.min_corner()
	editor._on_cell_pressed(Vector2i(3, 3))
	editor._on_cell_released(Vector2i(3, 3))
	_expect(editor._history.size() == i_h4 and editor.model == i_m4
		and editor._selection_range.min_corner() == i_min4
		and not bool(editor.region_clipboard_info()["move_armed"]),
		"I 原地按下松开 → 无历史/模型/选区变化（纯点击不触发区域选择）")
	# I-⑤ 关闭工具 → 旧行为：区域内按下 armed、原地松开重置 pos1
	mt_toggle.button_pressed = false
	_expect(not bool(editor.region_clipboard_info()["move_tool"]),
		"I 关闭后 move_tool=false")
	editor._on_cell_pressed(Vector2i(3, 3))
	_expect(bool(editor.region_clipboard_info()["move_armed"]),
		"I 关闭后区域内按下仍进入待移动（旧语义）")
	editor._on_cell_released(Vector2i(3, 3))
	_expect(not editor._region_pos2_set
		and editor._selection_range.min_corner() == editor._selection_range.max_corner(),
		"I 关闭后原地松开仍走第三次点击重置 pos1（旧契约）")

	# ---- J. 移动工具独立化：任意工具（画笔）下可拖、全程绝不重置选区 ----
	editor.apply_generate("region_ops_t5", 8, 8)
	await process_frame
	editor.current_tool = editor.Tool.PAINT
	editor._on_tool_changed()  # 与工具条按下同一入口（不弹选择面板）
	_expect(editor.current_tool == editor.Tool.PAINT,
		"J 切到画笔工具（_on_tool_changed 同步）")
	var j_toggle := editor.find_child("MoveToolToggle", true, false) as BaseButton
	j_toggle.button_pressed = true
	_expect(bool(editor.region_clipboard_info()["move_tool"]),
		"J 画笔下仍可开启移动工具（不因工具切换被收起）")
	# 直接构造完整选区 (1,1)-(4,3)：与入口状态无关（点击语义已由 C/E/I 段覆盖）
	editor._selection_range.begin(Vector3i(1, 1, 0))
	editor._selection_range.update_focus(Vector3i(4, 3, 0))
	editor._region_pos2_set = true
	editor._set_glyph(Vector2i(1, 1), "g")
	BattlefieldDocScript.set_cell_z(editor.model, Vector2i(2, 2), 3)
	BattlefieldDocScript.set_tile_override(editor.model, Vector2i(3, 2), "asset_grass_block")
	BattlefieldDocScript.set_prop(editor.model, Vector2i(2, 1), "tree")
	(editor.model.units as Array).append({
		"class": "warrior", "name": "契约探员", "level": 3,
		"x": 1, "y": 1, "faction": "player",
	})
	editor._seal_pending()
	editor._push_undo("布景五层J")
	editor._seal_pending()
	var j_cursor0: int = editor._history_cursor
	var j_before: Dictionary = editor.model.duplicate(true)
	var j_min0: Vector3i = editor._selection_range.min_corner()
	var j_max0: Vector3i = editor._selection_range.max_corner()
	# J-② 画笔下按下：移动优先于画笔，不画一笔、端点/模型不变
	editor._on_cell_pressed(Vector2i(2, 2))
	_expect(bool(editor.region_clipboard_info()["move_armed"])
		and editor._selection_range.min_corner() == j_min0
		and editor._selection_range.max_corner() == j_max0
		and editor._region_pos2_set
		and editor.model == j_before,
		"J 画笔+移动工具按下：进入待移动，不画一笔、端点/pos2/模型全不变")
	editor._on_cell_dragged(Vector2i(3, 3))
	_expect(editor._canvas.has_paste_preview()
		and editor._selection_range.min_corner() == j_min0
		and editor._selection_range.max_corner() == j_max0
		and editor._region_pos2_set,
		"J 拖动出预览，端点仍原值（提交前 min/max 逐次比对）")
	editor._on_cell_released(Vector2i(3, 3))
	_expect(editor._selection_range.is_active() and editor._region_pos2_set,
		"J 提交后选区保持完整（is_active 与 pos2_set 均仍真，可继续拖拽）")
	editor._seal_pending()
	_expect(editor._history_cursor == j_cursor0 + 1
		and editor._history.size() == editor._history_cursor + 1
		and String(editor._history[editor._history_cursor]["label"]) == "移动区域",
		"J 第一次拖拽提交：恰好一步历史「移动区域」")
	_expect((editor.model.rows[2] as String).substr(2, 1) == "g"
		and BattlefieldDocScript.cell_z(editor.model, Vector2i(3, 3)) == 3
		and BattlefieldDocScript.tile_override_at(editor.model, Vector2i(4, 3)) == "asset_grass_block"
		and BattlefieldDocScript.prop_at(editor.model, Vector2i(3, 2)) == "tree",
		"J 五层内容 (+1,+1) 平移到位（画笔未画任何一笔）")
	var j_unit: Dictionary = {}
	for u in editor.model.units:
		if int(u.x) == 2 and int(u.y) == 2:
			j_unit = u
	_expect(not j_unit.is_empty() and String(j_unit.get("name", "")) == "契约探员",
		"J 单位层平移到 (2,2)")
	var j_min1: Vector3i = editor._selection_range.min_corner()
	var j_max1: Vector3i = editor._selection_range.max_corner()
	_expect(Vector2i(j_min1.x, j_min1.y) == Vector2i(2, 2)
		and Vector2i(j_max1.x, j_max1.y) == Vector2i(5, 4),
		"J 选区随内容平移到 (2,2)-(5,4)")
	# J-③ 连续再拖一次（仍画笔下）：再 +1 历史、选区再平移
	editor._on_cell_pressed(Vector2i(3, 3))
	editor._on_cell_dragged(Vector2i(4, 4))
	editor._on_cell_released(Vector2i(4, 4))
	editor._seal_pending()
	_expect(editor._history_cursor == j_cursor0 + 2
		and editor._selection_range.is_active() and editor._region_pos2_set,
		"J 连续第二次拖拽：再 +1 历史，选区仍完整")
	var j_min2: Vector3i = editor._selection_range.min_corner()
	var j_max2: Vector3i = editor._selection_range.max_corner()
	_expect(Vector2i(j_min2.x, j_min2.y) == Vector2i(3, 3)
		and Vector2i(j_max2.x, j_max2.y) == Vector2i(6, 5)
		and (editor.model.rows[3] as String).substr(3, 1) == "g",
		"J 选区再平移到 (3,3)-(6,5)，地形层累计 (+2,+2)")
	# J-④ 原地按下松开：端点/历史/模型零变化
	editor._seal_pending()
	var j_h4: int = editor._history.size()
	var j_m4: Dictionary = editor.model.duplicate(true)
	var j_min4: Vector3i = editor._selection_range.min_corner()
	editor._on_cell_pressed(Vector2i(5, 5))
	editor._on_cell_released(Vector2i(5, 5))
	_expect(editor._history.size() == j_h4 and editor.model == j_m4
		and editor._selection_range.min_corner() == j_min4
		and editor._region_pos2_set
		and not bool(editor.region_clipboard_info()["move_armed"]),
		"J 原地按下松开：端点/pos2/历史/模型全不变（不补区域点击）")
	# J-⑤ 关闭开关 → 旧逻辑回归（切回选择工具后纯点击重置 pos1）
	j_toggle.button_pressed = false
	_expect(not bool(editor.region_clipboard_info()["move_tool"]),
		"J 关闭后 move_tool=false")
	editor.current_tool = editor.Tool.SELECT
	editor._on_tool_changed()
	_expect(editor.current_tool == editor.Tool.SELECT, "J 切回选择工具")
	editor._on_cell_pressed(Vector2i(4, 4))
	_expect(bool(editor.region_clipboard_info()["move_armed"]),
		"J 关闭后区域内按下回到旧待移动语义")
	editor._on_cell_released(Vector2i(4, 4))
	_expect(not editor._region_pos2_set
		and editor._selection_range.min_corner() == editor._selection_range.max_corner(),
		"J 关闭后原地松开仍走第三次点击重置 pos1（旧契约）")

	# ---- K. 方向键逐格移动区域（仅移动工具开启时生效） ----
	editor.apply_generate("region_ops_k", 8, 8)
	await process_frame
	# 直接构造完整选区 (2,2)-(4,4) + 一格地形锚点
	editor._selection_range.begin(Vector3i(2, 2, 0))
	editor._selection_range.update_focus(Vector3i(4, 4, 0))
	editor._region_pos2_set = true
	editor._set_glyph(Vector2i(2, 2), "g")
	editor._seal_pending()
	editor._push_undo("布景K")
	editor._seal_pending()
	var k_cursor0: int = editor._history_cursor
	var k_model0: Dictionary = editor.model.duplicate(true)
	# K-① 工具关闭（生成后自动收起）：方向键零动作
	_expect(not bool(editor.region_clipboard_info()["move_tool"]),
		"K 生成后移动工具默认关闭")
	_send_key(editor, KEY_UP)
	_expect(editor._history_cursor == k_cursor0 and editor.model == k_model0
		and editor._selection_range.min_corner() == Vector3i(2, 2, 0),
		"K 工具关闭时方向键零动作（历史/模型/选区全不变）")
	# K-② 开启后 KEY_UP：上= y-1，内容+选区同移，恰好一步历史
	var k_toggle := editor.find_child("MoveToolToggle", true, false) as BaseButton
	k_toggle.button_pressed = true
	_send_key(editor, KEY_UP)
	editor._seal_pending()
	_expect(editor._history_cursor == k_cursor0 + 1
		and editor._history.size() == editor._history_cursor + 1
		and String(editor._history[editor._history_cursor]["label"]) == "移动区域"
		and (editor.model.rows[1] as String).substr(2, 1) == "g"
		and editor._selection_range.min_corner() == Vector3i(2, 1, 0),
		"K KEY_UP=上移一格（y-1）：地形+选区同移、恰好一步「移动区域」")
	# K-③ 左/下/右往返：净位移 0，每键各一步历史
	_send_key(editor, KEY_LEFT)
	_send_key(editor, KEY_DOWN)
	_send_key(editor, KEY_RIGHT)
	editor._seal_pending()
	_expect(editor._history_cursor == k_cursor0 + 4
		and (editor.model.rows[2] as String).substr(2, 1) == "g"
		and editor._selection_range.min_corner() == Vector3i(2, 2, 0),
		"K 左/下/右往返后地形+选区复位，累计 4 步历史")
	# K-④ 顶边越界：再按两次 UP 到 y=0，第三次 UP 仅报错、零变化
	_send_key(editor, KEY_UP)
	_send_key(editor, KEY_UP)
	editor._seal_pending()
	_expect(editor._selection_range.min_corner() == Vector3i(2, 0, 0),
		"K 连按两次 UP 选区到顶 y=0")
	var k_h4: int = editor._history.size()
	var k_model4: Dictionary = editor.model.duplicate(true)
	_send_key(editor, KEY_UP)
	_expect(editor._history.size() == k_h4 and editor.model == k_model4
		and editor._selection_range.min_corner() == Vector3i(2, 0, 0),
		"K 顶边越界：方向键仅报错（历史/模型/选区零变化）")
	k_toggle.button_pressed = false

	_finish(editor)


## 直接向 editor._unhandled_input 发合成按键（ctrl=true 模拟 Ctrl+<key>）
func _send_key(editor: Node, key: Key, ctrl := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	editor._unhandled_input(ev)


func _finish(editor: Node) -> void:
	editor.queue_free()
	if failures.is_empty():
		print("MAP_EDITOR_REGION_OPS_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
