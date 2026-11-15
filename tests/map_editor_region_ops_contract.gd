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
##       region_clipboard_info() 只读快照；工具条 10 钮（9 工具+移动开关）、ModeOption 仍 2 项。
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
	_expect(toolbar != null and toolbar.get_child_count() == 10,
		"A 工具条为 10 个按钮（9 工具 + 移动开关）")
	var a_replace_popup := editor.get_node_or_null("ReplacePopup") as PanelContainer
	_expect(a_replace_popup != null and not a_replace_popup.visible,
		"A ReplacePopup 初始存在且默认隐藏")
	_expect(editor._block_fg == {"kind": "terrain", "id": "plain", "z": 0}
		and editor._block_bg == {"kind": "terrain", "id": "plain", "z": 0},
		"A 前景/背景方块槽默认均为 plain z0")
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

	# ---- L. 预设 Tab：保存/列表/填入/放置模式/删除（隔离 user://test_editor_presets_ui） ----
	editor._preset_store = load("res://scripts/editor/region_preset_store.gd").new(
		"user://test_editor_presets_ui")
	editor._refresh_preset_list()
	# L-① 预设页 UI：第 8 个 Tab + 关键控件
	var l_tabs := editor.find_child("ToolTabs", true, false) as TabContainer
	_expect(l_tabs != null and l_tabs.get_tab_count() == 8
		and String(l_tabs.get_tab_title(7)) == "预设",
		"L 预设页是第 8 个 Tab（文件/生成/地形/方块/角色/历史/素材/预设）")
	var l_preview_toggle := editor.find_child("PlacePreviewToggle", true, false) as CheckButton
	_expect(editor.find_child("PresetList", true, false) != null
		and editor.find_child("SavePresetBtn", true, false) != null
		and editor.find_child("PlacePresetBtn", true, false) != null
		and l_preview_toggle != null and l_preview_toggle.button_pressed
		and l_preview_toggle.text == "实时放置预览",
		"L 预设页含列表/保存/放置控件，实时放置预览 CheckButton 默认开启")
	_expect(bool(editor.region_clipboard_info().get("place_preview", false)),
		"L region_clipboard_info().place_preview 暴露默认开启状态")
	# L-② 无完整区域保存：仅中文提示，不写盘、不动模型与历史
	editor._region_pos2_set = false
	var l_h0: int = editor._history.size()
	var l_m0: Dictionary = editor.model.duplicate(true)
	editor._on_save_preset_pressed()
	_expect(String(editor._status_label.text).contains("预设保存")
		and editor._preset_store.count() == 0
		and editor.model == l_m0 and editor._history.size() == l_h0,
		"L 无完整选区保存：中文提示且零写入（存储/模型/历史不变）")
	# L-③ 完整选区 (1,1)-(3,3) 铺五层 → 保存 → 列表 1 项，元数据 3×3
	editor._selection_range.begin(Vector3i(1, 1, 0))
	editor._selection_range.update_focus(Vector3i(3, 3, 0))
	editor._region_pos2_set = true
	editor._set_glyph(Vector2i(1, 1), "g")
	BattlefieldDocScript.set_cell_z(editor.model, Vector2i(2, 2), 3)
	BattlefieldDocScript.set_tile_override(editor.model, Vector2i(3, 2), "asset_grass_block")
	BattlefieldDocScript.set_prop(editor.model, Vector2i(2, 1), "tree")
	(editor.model.units as Array).append({
		"class": "warrior", "name": "预设探员", "level": 2,
		"x": 1, "y": 1, "faction": "player",
	})
	editor._seal_pending()
	editor._push_undo("布景L")
	editor._seal_pending()
	editor._preset_name_edit.text = "契约预设"
	var l_save_h0: int = editor._history.size()
	var l_save_m0: Dictionary = editor.model.duplicate(true)
	editor._on_save_preset_pressed()
	var l_metas: Array = editor._preset_store.list()
	_expect(editor._preset_store.count() == 1 and editor._preset_list.item_count == 1
		and l_metas.size() == 1 and int(l_metas[0].w) == 3 and int(l_metas[0].h) == 3
		and String(l_metas[0].name) == "契约预设"
		and editor._history.size() == l_save_h0 and editor.model == l_save_m0,
		"L 保存当前选区为预设：列表 1 项且保存本身零历史/模型增量，元数据 3×3 名「契约预设」")
	# L-④ 清空画布后填入选区：五层按预设回写到选区左上角，恰好一步历史，一步撤销回滚
	for y in range(8):
		editor.model.rows[y] = "........"
	BattlefieldDocScript.set_cell_z(editor.model, Vector2i(2, 2), 0)
	(editor.model.units as Array).clear()
	(editor.model.get("props", []) as Array).clear()
	(editor.model.get("tile_overrides", {}) as Dictionary).clear()
	editor._push_undo("清空画布L")  # 清空入史：撤销「填入预设」才有可比对的清空回滚点
	editor._seal_pending()
	var l_wiped: Dictionary = editor.model.duplicate(true)
	var l_fill_h0: int = editor._history.size()
	editor._on_fill_preset_pressed()
	editor._seal_pending()
	_expect(editor._history.size() == l_fill_h0 + 1
		and editor._history_cursor >= 0
		and String(editor._history[editor._history_cursor]["label"]) == "填入预设"
		and (editor.model.rows[1] as String).substr(1, 1) == "g"
		and BattlefieldDocScript.cell_z(editor.model, Vector2i(2, 2)) == 3
		and BattlefieldDocScript.tile_override_at(editor.model, Vector2i(3, 2)) == "asset_grass_block"
		and BattlefieldDocScript.prop_at(editor.model, Vector2i(2, 1)) == "tree",
		"L 填入选区：地形/高度/覆盖/植物四层回写到 (1,1)-(3,3)，标签「填入预设」")
	var l_unit: Dictionary = {}
	for u in editor.model.units:
		if int(u.x) == 1 and int(u.y) == 1:
			l_unit = u
	_expect(not l_unit.is_empty() and String(l_unit.get("name", "")) == "预设探员",
		"L 填入选区：单位层回写到 (1,1)")
	editor._undo()
	_expect(editor.model == l_wiped,
		"L 一步撤销填入 → 画布回到清空态")
	# L-⑤ 放置模式：预览跟随悬停；点击连续放置各一步历史；ESC 退出清预览
	var l_place_btn := editor.find_child("PlacePresetBtn", true, false) as BaseButton
	l_place_btn.button_pressed = true
	_expect(bool(editor._place_mode), "L 放置模式开启（列表已有选中预设）")
	editor._on_hover_changed(Vector2i(2, 2))
	_expect(editor._canvas.has_paste_preview(), "L 放置预览跟随悬停格出现")
	var l_place_h0: int = editor._history.size()
	var l_place_c0: int = editor._history_cursor
	var l_place_before0: Dictionary = editor.model.duplicate(true)
	editor._on_cell_pressed(Vector2i(0, 0))
	editor._seal_pending()
	# 上一次断言撤销了「填入预设」；首次放置会截断这条 redo 再追加，故 size 不变、cursor +1。
	_expect(editor._history.size() == l_place_h0
		and editor._history_cursor == l_place_c0 + 1
		and String(editor._history[editor._history_cursor]["label"]) == "放置预设"
		and (editor.model.rows[0] as String).substr(0, 1) == "g",
		"L 放置预设 at (0,0)：历史恰好 +1，标签「放置预设」且地形落位")
	var l_place_h1: int = editor._history.size()
	var l_place_c1: int = editor._history_cursor
	var l_place_before1: Dictionary = editor.model.duplicate(true)
	editor._on_cell_pressed(Vector2i(4, 4))
	editor._seal_pending()
	_expect(editor._history.size() == l_place_h1 + 1
		and editor._history_cursor == l_place_c1 + 1 and editor._place_mode
		and (editor.model.rows[4] as String).substr(4, 1) == "g",
		"L 连续放置 at (4,4)：模式保持，历史再次恰好 +1")
	editor._undo()
	_expect(editor.model == l_place_before1,
		"L 一步撤销连续放置 → 仅回滚 at (4,4)，保留首次放置")
	editor._undo()
	_expect(editor.model == l_place_before0,
		"L 再一步撤销首次放置 → 画布回到放置前")
	# L-⑤b 关闭实时预览：悬停无标记，但点击仍放置且恰好一步历史/撤销；再开启恢复预览
	var l_preview_h0: int = editor._history.size()
	var l_preview_c0: int = editor._history_cursor
	var l_preview_before: Dictionary = editor.model.duplicate(true)
	l_preview_toggle.button_pressed = false
	_expect(not bool(editor.region_clipboard_info()["place_preview"])
		and not editor._canvas.has_paste_preview()
		and editor._history.size() == l_preview_h0 and editor.model == l_preview_before,
		"L 关闭实时放置预览：状态快照=false、旧预览立即清除，模型/历史不变")
	editor._on_hover_changed(Vector2i(5, 1))
	_expect(not editor._canvas.has_paste_preview(),
		"L 预览关闭后放置模式悬停不再显示标记")
	editor._on_cell_pressed(Vector2i(5, 1))
	editor._seal_pending()
	_expect(editor._history_cursor == l_preview_c0 + 1
		and editor._history.size() == editor._history_cursor + 1
		and String(editor._history[editor._history_cursor]["label"]) == "放置预设"
		and (editor.model.rows[1] as String).substr(5, 1) == "g"
		and not editor._canvas.has_paste_preview(),
		"L 无预览点击仍放置 at (5,1)：恰好一步「放置预设」，预览保持关闭")
	editor._undo()
	_expect(editor.model == l_preview_before,
		"L 无预览放置仍可一步撤销回滚")
	l_preview_toggle.button_pressed = true
	_expect(bool(editor.region_clipboard_info()["place_preview"]),
		"L 重新开启实时放置预览：状态快照恢复 true")
	editor._on_hover_changed(Vector2i(2, 2))
	_expect(editor._canvas.has_paste_preview(),
		"L 重新开启后悬停预览恢复")
	_send_key(editor, KEY_ESCAPE)
	_expect(not editor._place_mode and not editor._canvas.has_paste_preview(),
		"L ESC 退出放置模式并清预览")
	# L-⑥ 删除预设：存储与列表同步清零
	editor._on_delete_preset_pressed()
	_expect(editor._preset_store.count() == 0 and editor._preset_list.item_count == 0,
		"L 删除后存储与列表均空")
	var l_dir := DirAccess.open("user://")
	if l_dir != null and l_dir.dir_exists("test_editor_presets_ui"):
		l_dir.remove("test_editor_presets_ui/presets.json")
		l_dir.remove("test_editor_presets_ui")


	# ---- N. 替换工具：点击只选择源方块，不再直接改模型或写历史 ----
	editor.apply_generate("replace_ops", 6, 5)
	await process_frame
	var n_replace_btn := editor._tool_buttons.get(editor.Tool.REPLACE) as BaseButton
	_expect(editor.Tool.REPLACE == 9 and n_replace_btn != null
		and n_replace_btn.name == "ReplaceToolBtn" and n_replace_btn.get_index() == 8
		and int(n_replace_btn.get_meta("tool", -1)) == editor.Tool.REPLACE,
		"N Tool.REPLACE=9，ReplaceToolBtn 是 ToolBox 第 9 钮")
	n_replace_btn.button_pressed = true
	_expect(editor.current_tool == editor.Tool.REPLACE and editor._active_tool() == editor.Tool.REPLACE,
		"N 替换工具可激活且不被当前 Tab 覆盖")
	editor._on_selection_mode_item(0)
	editor._selection_range.clear()
	editor._region_pos2_set = false
	BattlefieldDocScript.set_tile_override(editor.model, Vector2i(1, 1), "old_asset")
	editor._push_undo("布景N")
	editor._seal_pending()
	var n_before: Dictionary = editor.model.duplicate(true)
	var n_h0: int = editor._history.size()
	var n_c0: int = editor._history_cursor
	editor._on_cell_pressed(Vector2i(1, 1))
	editor._seal_pending()
	_expect(String(editor._replace_source_opt.get_selected_metadata()) == "asset:old_asset"
		and editor.model == n_before and editor._history.size() == n_h0
		and editor._history_cursor == n_c0,
		"N 替换工具点格只设置 ReplaceSourceOpt，模型与历史零变化")
	editor._on_cell_pressed(Vector2i(-1, 0))
	_expect(editor.model == n_before and editor._history.size() == n_h0
		and editor._history_cursor == n_c0 and String(editor._status_label.text).contains("越界"),
		"N 越界点格中文拒绝，仍不写模型或历史")

	# ---- O. 吸管 + 前景/背景交换：只读模型、不写历史，画笔消费交换后的前景 ----
	editor.apply_generate("pick_ops", 6, 5)
	await process_frame
	editor._on_selection_mode_item(0)
	editor._selection_range.clear()
	editor._region_pos2_set = false
	var o_asset_cell := Vector2i(2, 2)
	var o_terrain_cell := Vector2i(3, 2)
	BattlefieldDocScript.set_tile_override(editor.model, o_asset_cell, "pick_asset")
	BattlefieldDocScript.set_cell_z(editor.model, o_asset_cell, 3)
	editor._set_glyph(o_terrain_cell, "w")
	BattlefieldDocScript.set_cell_z(editor.model, o_terrain_cell, 1)
	editor._push_undo("布景O")
	editor._seal_pending()
	var o_pick_btn := editor._tool_buttons.get(editor.Tool.PICK) as BaseButton
	_expect(editor.Tool.PICK == 10 and o_pick_btn != null
		and o_pick_btn.name == "PickToolBtn" and o_pick_btn.get_index() == 9
		and int(o_pick_btn.get_meta("tool", -1)) == editor.Tool.PICK,
		"O Tool.PICK=10，PickToolBtn 是 ToolBox 第 10 钮")
	o_pick_btn.button_pressed = true
	_expect(editor.current_tool == editor.Tool.PICK and editor._active_tool() == editor.Tool.PICK,
		"O 吸管工具可激活且不被当前 Tab 覆盖")
	var o_before: Dictionary = editor.model.duplicate(true)
	var o_h0: int = editor._history.size()
	var o_c0: int = editor._history_cursor
	editor._on_cell_pressed(o_asset_cell)
	_expect(editor._block_fg == {"kind": "asset", "id": "pick_asset", "z": 3}
		and editor.model == o_before and editor._history.size() == o_h0
		and editor._history_cursor == o_c0 and String(editor._status_label.text).contains("已吸取"),
		"O 吸取素材格写前景 kind/asset/id/z，模型与历史不变")
	editor._on_cell_pressed(o_terrain_cell, true)  # Alt+点击的确定性测试入口
	_expect(editor._block_bg == {"kind": "terrain", "id": "water", "z": 1}
		and editor.model == o_before and editor._history.size() == o_h0
		and editor._history_cursor == o_c0,
		"O Alt+点击地形格写背景 kind/terrain/id/z，模型与历史不变")
	_send_key(editor, KEY_X, false, true)
	_expect(editor._block_fg == {"kind": "terrain", "id": "water", "z": 1}
		and editor._block_bg == {"kind": "asset", "id": "pick_asset", "z": 3}
		and editor.model == o_before and editor._history.size() == o_h0,
		"O Shift+X 交换前景/背景且不触发文档编辑")
	var o_swap_btn := editor.find_child("SwapBlocksBtn", true, false) as Button
	_expect(o_swap_btn != null and o_swap_btn.text == "⇄ 交换", "O 方块 Tab 存在 SwapBlocksBtn")
	if o_swap_btn != null:
		o_swap_btn.pressed.emit()
	_expect(editor._block_fg == {"kind": "asset", "id": "pick_asset", "z": 3}
		and editor._block_bg == {"kind": "terrain", "id": "water", "z": 1},
		"O SwapBlocksBtn 再次交换，前景恢复所吸素材")
	var o_paint_target := Vector2i(0, 0)
	var o_paint_before: Dictionary = editor.model.duplicate(true)
	var o_paint_c0: int = editor._history_cursor
	editor._tool_buttons[editor.Tool.PAINT].button_pressed = true
	editor._on_cell_pressed(o_paint_target)
	editor._seal_pending()
	_expect(BattlefieldDocScript.tile_override_at(editor.model, o_paint_target) == "pick_asset"
		and editor._history_cursor == o_paint_c0 + 1
		and editor._history.size() == editor._history_cursor + 1
		and String(editor._history[editor._history_cursor]["label"]) == "画笔",
		"O 交换后画笔写入新前景素材，恰好一步历史")
	editor._undo()
	_expect(editor.model == o_paint_before, "O 前景素材画笔一次 undo 回滚")

	# ---- P. 真实方块幽灵：五层展开、平移/越界、预览开关与放置撤销 ----
	editor.apply_generate("ghost_ops", 6, 5)
	await process_frame
	editor._preset_store = load("res://scripts/editor/region_preset_store.gd").new(
		"user://test_editor_presets_ghost")
	editor._on_selection_mode_item(1)
	editor._selection_range.begin(Vector3i(1, 1, 0))
	editor._selection_range.update_focus(Vector3i(2, 2, 0))
	editor._region_pos2_set = true
	BattlefieldDocScript.set_tile_override(editor.model, Vector2i(1, 1), "ghost_asset")
	BattlefieldDocScript.set_cell_z(editor.model, Vector2i(1, 1), 3)
	editor._set_glyph(Vector2i(2, 2), "w")
	BattlefieldDocScript.set_cell_z(editor.model, Vector2i(2, 2), 1)
	editor._push_undo("布景P")
	editor._seal_pending()
	editor._preset_name_edit.text = "幽灵契约"
	editor._on_save_preset_pressed()
	_expect(editor._preset_store.count() == 1 and editor._preset_list.item_count == 1,
		"P 准备 2×2 预设成功")
	var p_before: Dictionary = editor.model.duplicate(true)
	editor._place_preset_btn.button_pressed = true
	_expect(editor._place_mode and editor._place_preview_enabled,
		"P 放置模式开启且实时预览默认开启")
	editor._on_hover_changed(Vector2i(0, 0))
	var p_cells: Array = editor._canvas._block_ghost_cells
	_expect(editor._canvas.ghost_cell_count() == 4 and editor._canvas.has_paste_preview()
		and editor._canvas._block_ghost_valid and editor.model == p_before,
		"P 合法悬停生成 w×h=4 个真实幽灵块，模型不变")
	_expect(editor._canvas._block_ghost_marks.size() == 4
		and is_equal_approx(editor._canvas._block_ghost_marks[0].self_modulate.a, 0.45)
		and editor._canvas._block_ghost_marks[0].self_modulate == editor._canvas.GHOST_OK_COLOR,
		"P 幽灵层实际创建 4 个 ColumnBatch，合法态绿色半透明 alpha=0.45")
	_expect(p_cells.size() == 4 and p_cells[0] == {
		"x": 0, "y": 0, "terrain": "f", "asset_id": "ghost_asset", "z": 3,
	} and p_cells[3] == {"x": 1, "y": 1, "terrain": "w", "asset_id": "", "z": 1},
		"P rows/block_z/tile_overrides 按相对坐标正确展开；实际=%s" % str(p_cells))
	editor._on_hover_changed(Vector2i(1, 0))
	p_cells = editor._canvas._block_ghost_cells
	_expect(editor._canvas.ghost_cell_count() == 4 and p_cells[0].x == 1 and p_cells[0].y == 0
		and p_cells[3].x == 2 and p_cells[3].y == 1 and editor.model == p_before,
		"P 幽灵格坐标随悬停整体平移且仍不改模型")
	editor._on_hover_changed(Vector2i(5, 4))
	_expect(not editor._canvas._block_ghost_valid and editor._canvas.ghost_cell_count() == 1
		and editor._canvas._block_ghost_cells[0].x == 5
		and editor._canvas._block_ghost_cells[0].y == 4 and editor.model == p_before,
		"P 越界落点 valid=false，只画地图内的一格")
	_expect(editor._canvas._block_ghost_marks.size() == 1
		and editor._canvas._block_ghost_marks[0].self_modulate == editor._canvas.GHOST_BAD_COLOR,
		"P 越界幽灵块切换为红色半透明")
	editor._place_preview_toggle.button_pressed = false
	_expect(editor._canvas.ghost_cell_count() == 0 and not editor._canvas.has_paste_preview()
		and editor.model == p_before, "P 关闭实时预览立即清空幽灵层")
	var p_place_c0: int = editor._history_cursor
	editor._on_cell_pressed(Vector2i(0, 3))
	editor._seal_pending()
	_expect(editor._history_cursor == p_place_c0 + 1
		and editor._history.size() == editor._history_cursor + 1
		and String(editor._history[editor._history_cursor]["label"]) == "放置预设",
		"P 无预览点击仍放置且恰好一步「放置预设」历史")
	editor._undo()
	_expect(editor.model == p_before, "P 无预览放置一次 undo 原子回滚")
	editor._place_preview_toggle.button_pressed = true
	editor._on_hover_changed(Vector2i(0, 0))
	_expect(editor._canvas.ghost_cell_count() == 4 and editor._canvas._block_ghost_valid
		and editor.model == p_before, "P 重新开启预览后悬停恢复 4 个幽灵块")
	editor._on_region_copy_pressed()
	editor._on_region_paste_pressed()
	editor._on_hover_changed(Vector2i(0, 0))
	_expect(editor._paste_mode and not editor._place_mode
		and editor._canvas.ghost_cell_count() == 4 and editor._canvas.has_paste_preview()
		and editor._canvas._block_ghost_valid and editor.model == p_before,
		"P 粘贴模式同样展开 4 个幽灵块并与放置模式互斥")
	editor._cancel_paste()
	_expect(editor._canvas.ghost_cell_count() == 0 and not editor._canvas.has_paste_preview(),
		"P 取消粘贴清空幽灵层但保留剪贴板")
	editor._on_delete_preset_pressed()
	var p_dir := DirAccess.open("user://")
	if p_dir != null and p_dir.dir_exists("test_editor_presets_ghost"):
		p_dir.remove("test_editor_presets_ghost/presets.json")
		p_dir.remove("test_editor_presets_ghost")

	# ---- Q. 条件替换弹窗：双下拉、全图/选区命中、零写入与原子撤销 ----
	editor.apply_generate("replace_popup", 6, 5)
	await process_frame
	editor._tool_buttons[editor.Tool.PAINT].button_pressed = true
	editor._on_selection_mode_item(0)
	editor._selection_range.clear()
	editor._region_pos2_set = false
	var q_popup := editor.get_node_or_null("ReplacePopup") as PanelContainer
	var q_source := editor.get_node_or_null("ReplacePopup/ReplacePopupBox/ReplaceSourceOpt") as OptionButton
	var q_dest := editor.get_node_or_null("ReplacePopup/ReplacePopupBox/ReplaceDestOpt") as OptionButton
	var q_scope := editor.get_node_or_null("ReplacePopup/ReplacePopupBox/ReplaceScopeLabel") as Label
	var q_apply := editor.get_node_or_null("ReplacePopup/ReplacePopupBox/ReplaceApplyBtn") as Button
	var q_hint := editor.get_node_or_null("ReplacePopup/ReplacePopupBox/ReplaceHint") as Label
	_expect(q_popup != null and not q_popup.visible and q_source != null and q_dest != null
		and q_scope != null and q_apply != null and q_hint != null
		and q_apply.text == "执行替换" and q_hint.text == "点地图格子可快速设为被替换方块",
		"Q ReplacePopup 默认隐藏，双下拉/范围/执行/提示节点齐全")
	editor._set_glyph(Vector2i(1, 1), "g")
	editor._set_glyph(Vector2i(2, 1), "g")
	editor._set_glyph(Vector2i(3, 1), "w")
	editor._set_glyph(Vector2i(4, 1), "g")
	BattlefieldDocScript.set_cell_z(editor.model, Vector2i(1, 1), 3)
	BattlefieldDocScript.set_cell_z(editor.model, Vector2i(2, 1), 4)
	BattlefieldDocScript.set_cell_z(editor.model, Vector2i(3, 1), 2)
	BattlefieldDocScript.set_cell_z(editor.model, Vector2i(4, 1), 5)
	BattlefieldDocScript.set_tile_override(editor.model, Vector2i(1, 1), "old_asset")
	BattlefieldDocScript.set_tile_override(editor.model, Vector2i(2, 1), "old_asset")
	BattlefieldDocScript.set_tile_override(editor.model, Vector2i(3, 1), "")
	BattlefieldDocScript.set_tile_override(editor.model, Vector2i(4, 1), "cover_asset")
	editor._push_undo("布景Q")
	editor._seal_pending()
	editor._canvas.hover_cell = Vector2i(3, 1)
	editor._set_block_slot("fg", {"kind": &"asset", "id": "target_asset", "z": 0})
	editor._tool_buttons[editor.Tool.REPLACE].button_pressed = true
	_expect(q_popup.visible and String(q_source.get_selected_metadata()) == "terrain:w"
		and String(q_dest.get_selected_metadata()) == "asset:target_asset"
		and q_scope.text == "当前范围：全图 30 格",
		"Q 选替换工具显示弹窗：源取悬停格、目标取前景、无选区计全图")
	editor._on_cell_pressed(Vector2i(1, 1))
	var q_has_asset := false
	for i in range(q_source.item_count):
		if String(q_source.get_item_metadata(i)) == "asset:old_asset":
			q_has_asset = true
	_expect(q_has_asset and String(q_source.get_selected_metadata()) == "asset:old_asset",
		"Q 下拉编码含 terrain:/asset:，点格可把素材设为源")
	editor._select_replace_option(q_dest, "terrain:w")
	var q_full_before: Dictionary = editor.model.duplicate(true)
	var q_full_c0: int = editor._history_cursor
	q_apply.emit_signal("pressed")
	_expect((editor.model.rows[1] as String).substr(1, 1) == "w"
		and (editor.model.rows[1] as String).substr(2, 1) == "w"
		and BattlefieldDocScript.tile_override_at(editor.model, Vector2i(1, 1)) == ""
		and BattlefieldDocScript.tile_override_at(editor.model, Vector2i(2, 1)) == ""
		and BattlefieldDocScript.cell_z(editor.model, Vector2i(1, 1)) == 3
		and BattlefieldDocScript.cell_z(editor.model, Vector2i(2, 1)) == 4
		and BattlefieldDocScript.cell_z(editor.model, Vector2i(3, 1)) == 2
		and BattlefieldDocScript.tile_override_at(editor.model, Vector2i(4, 1)) == "cover_asset"
		and BattlefieldDocScript.cell_z(editor.model, Vector2i(4, 1)) == 5
		and editor._history_cursor == q_full_c0 + 1
		and editor._history.size() == editor._history_cursor + 1
		and String(editor._history[editor._history_cursor]["label"]) == "替换全图"
		and String(editor._status_label.text).contains("2 格"),
		"Q 全图按类型只替换 2 个命中格，高度/不命中格不变，恰好一步「替换全图」")
	editor._undo()
	_expect(editor.model == q_full_before, "Q 全图条件替换一次 undo 完整回滚")
	editor._select_replace_option(q_source, "asset:old_asset")
	editor._select_replace_option(q_dest, "asset:old_asset")
	var q_same_before: Dictionary = editor.model.duplicate(true)
	var q_same_h0: int = editor._history.size()
	var q_same_c0: int = editor._history_cursor
	q_apply.emit_signal("pressed")
	_expect(editor.model == q_same_before and editor._history.size() == q_same_h0
		and editor._history_cursor == q_same_c0
		and String(editor._status_label.text).contains("相同"),
		"Q 源==目标拒绝：模型/历史游标/条数零变化")
	editor._on_selection_mode_item(1)
	editor._selection_range.begin(Vector3i(4, 1, 5))
	editor._selection_range.update_focus(Vector3i(4, 1, 5))
	editor._region_pos2_set = true
	editor._select_replace_option(q_source, "terrain:g")
	editor._select_replace_option(q_dest, "terrain:w")
	q_apply.emit_signal("pressed")
	_expect(editor.model == q_same_before and editor._history.size() == q_same_h0
		and editor._history_cursor == q_same_c0
		and String(editor._status_label.text).contains("0 格"),
		"Q terrain 源不命中带覆盖格：0 匹配提示且零历史")
	editor._selection_range.begin(Vector3i(1, 1, 0))
	editor._selection_range.update_focus(Vector3i(2, 2, 4))
	editor._region_pos2_set = true
	editor._select_replace_option(q_source, "asset:old_asset")
	editor._select_replace_option(q_dest, "terrain:g")
	var q_region_before: Dictionary = editor.model.duplicate(true)
	var q_region_c0: int = editor._history_cursor
	_expect(q_scope.text == "当前范围：选区内 4 格", "Q 完整选区范围计数为 2×2=4 格")
	q_apply.emit_signal("pressed")
	_expect(BattlefieldDocScript.tile_override_at(editor.model, Vector2i(1, 1)) == ""
		and BattlefieldDocScript.tile_override_at(editor.model, Vector2i(2, 1)) == ""
		and (editor.model.rows[1] as String).substr(1, 1) == "g"
		and (editor.model.rows[1] as String).substr(2, 1) == "g"
		and BattlefieldDocScript.cell_z(editor.model, Vector2i(1, 1)) == 3
		and BattlefieldDocScript.cell_z(editor.model, Vector2i(2, 1)) == 4
		and BattlefieldDocScript.tile_override_at(editor.model, Vector2i(4, 1)) == "cover_asset"
		and editor._history_cursor == q_region_c0 + 1
		and editor._history.size() == editor._history_cursor + 1
		and String(editor._history[editor._history_cursor]["label"]) == "替换区域",
		"Q 选区优先只命中 2 格，高度不动，恰好一步「替换区域」")
	editor._undo()
	_expect(editor.model == q_region_before, "Q 选区条件替换一次 undo 原子回滚")
	editor._tool_buttons[editor.Tool.PAINT].button_pressed = true
	_expect(not q_popup.visible, "Q 切到其他工具隐藏弹窗")
	editor._tool_buttons[editor.Tool.REPLACE].button_pressed = true
	var q_esc_before: Dictionary = editor.model.duplicate(true)
	var q_esc_h0: int = editor._history.size()
	_send_key(editor, KEY_ESCAPE)
	_expect(not q_popup.visible and editor.model == q_esc_before
		and editor._history.size() == q_esc_h0,
		"Q Esc 只收起替换弹窗，不改模型或历史")

	_finish(editor)


## 直接向 editor._unhandled_input 发合成按键（ctrl/shift 模拟组合键）
func _send_key(editor: Node, key: Key, ctrl := false, shift := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
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
