## tests/map_editor_ui_contract.gd — 战场地图编辑器 UI 契约（右侧 Tabs 面板版）
##
## 跑法：godot --headless --path . --script res://tests/map_editor_ui_contract.gd
## 覆盖：右侧 Tabs 面板布局（画布左满幅 + 面板右停靠）、5 Tab 结构
##       （文件/生成/工具/地形/角色）、每 Tab 关键控件齐全、
##       ButtonGroup 交互（工具/地形/阵营/职业单选）联动 editor 状态。

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

	# ---- 1. 根布局：EditorRoot(HBox) 内 画布在左、SidePanel 在右 ----
	var root_box: HBoxContainer = editor.get_node_or_null("EditorRoot")
	_expect(root_box != null, "EditorRoot 存在且为 HBoxContainer")
	if root_box == null:
		_finish(editor)
		return
	_expect(root_box.get_child_count() == 2, "EditorRoot 只有画布+面板两个子节点（无顶栏残留）")
	var canvas: Control = root_box.get_node_or_null("EditorCanvas")
	var side: Control = root_box.get_node_or_null("SidePanel")
	_expect(canvas != null, "EditorCanvas 存在")
	_expect(side is PanelContainer, "SidePanel 存在且为 PanelContainer")
	if canvas != null and side != null:
		_expect(canvas.get_index() < side.get_index(), "画布在面板左侧")
		_expect(canvas.size_flags_horizontal == Control.SIZE_EXPAND_FILL,
			"画布水平伸展填充（吃满剩余宽度）")

	# ---- 2. 面板结构：SideVBox -> ToolTabs(5 Tab) + StatusLabel ----
	var sv: VBoxContainer = side.get_node_or_null("SideVBox") if side != null else null
	_expect(sv != null, "SideVBox 存在")
	var tabs: TabContainer = sv.get_node_or_null("ToolTabs") if sv != null else null
	_expect(tabs != null, "ToolTabs 存在且为 TabContainer")
	if tabs == null:
		_finish(editor)
		return
	var titles := []
	for i in range(tabs.get_tab_count()):
		titles.append(tabs.get_tab_title(i))
	_expect(titles == ["文件", "生成", "工具", "地形", "角色"],
		"5 个 Tab 且顺序为 文件/生成/工具/地形/角色（实际 %s）" % str(titles))
	var status: Label = sv.get_node_or_null("StatusLabel")
	_expect(status != null and status is Label, "状态栏贴面板底部（SideVBox 内）")
	if status != null:
		_expect(status.get_index() > tabs.get_index(), "状态栏在 Tabs 下方")

	# ---- 3. 各 Tab 关键控件齐全（经 Scroll > VBox 容器，子行可嵌套 HBox） ----
	var file_tab: VBoxContainer = tabs.get_node_or_null("文件Scroll/文件Tab")
	var gen_tab: VBoxContainer = tabs.get_node_or_null("生成Scroll/生成Tab")
	var tools_tab: VBoxContainer = tabs.get_node_or_null("工具Scroll/工具Tab")
	var terrain_tab: VBoxContainer = tabs.get_node_or_null("地形Scroll/地形Tab")
	var units_tab: VBoxContainer = tabs.get_node_or_null("角色Scroll/角色Tab")
	_expect(file_tab != null and gen_tab != null and tools_tab != null
		and terrain_tab != null and units_tab != null, "5 个 Tab 均有内容容器")
	if file_tab != null:
		_expect(_count_type(file_tab, LineEdit) == 2, "文件 Tab：id+名称 两个输入框")
		_expect(_count_type(file_tab, OptionButton) == 1, "文件 Tab：读取下拉框")
		_expect(_count_type(file_tab, CheckButton) == 1, "文件 Tab：托管开关")
		_expect(_count_type(file_tab, Button) >= 4, "文件 Tab：读取/保存/返回按钮齐全")
	if gen_tab != null:
		_expect(_count_type(gen_tab, SpinBox) == 2, "生成 Tab：宽+高 SpinBox")
		_expect(_count_type(gen_tab, LineEdit, SpinBox) == 1,
			"生成 Tab：种子输入框（排除 SpinBox 内部 LineEdit）")
	if tools_tab != null:
		_expect(tools_tab.get_child_count() == 4, "工具 Tab：4 个工具按钮")

	var terrain_grid: GridContainer = terrain_tab.get_node_or_null("TerrainGrid") if terrain_tab != null else null
	var expected_terrains: int = BattlefieldDocScript.TERRAIN_GLYPH.size()
	var actual_terrains: int = _count_type(terrain_grid, Button) if terrain_grid != null else -1
	_expect(terrain_grid != null and actual_terrains == expected_terrains,
		"地形 Tab：调色板含全部 %d 种地形（实际 %d）" % [expected_terrains, actual_terrains])

	var portrait_grid: GridContainer = units_tab.get_node_or_null("PortraitGrid") if units_tab != null else null
	_expect(portrait_grid != null and portrait_grid.get_child_count() == editor.CLASS_IDS.size(),
		"角色 Tab：8 职业头像网格")

	# ---- 4. 交互契约：ButtonGroup 单选联动 editor 状态 ----
	editor._tool_buttons[editor.Tool.FILL].button_pressed = true
	_expect(editor.current_tool == editor.Tool.FILL, "点填充按钮 → current_tool=FILL")
	editor._tool_buttons[editor.Tool.UNIT].button_pressed = true
	_expect(editor.current_tool == editor.Tool.UNIT, "点角色按钮 → current_tool=UNIT（组内单选切换）")

	var pick: StringName = editor.current_terrain
	for t: StringName in editor._terrain_buttons:
		if t != pick:
			editor._terrain_buttons[t].button_pressed = true
			_expect(editor.current_terrain == t, "点地形按钮 → current_terrain=%s" % t)
			break
	editor._terrain_buttons[pick].button_pressed = true
	_expect(editor.current_terrain == pick, "地形单选可切回")

	var enemy_btn: Button = null
	if units_tab != null and units_tab.get_child_count() > 0:
		for c in units_tab.get_child(0).get_children():
			if c is Button and c.get_meta("faction", "") == "enemy":
				enemy_btn = c
				break
	_expect(enemy_btn != null, "角色 Tab：敌方阵营按钮存在")
	if enemy_btn != null:
		enemy_btn.button_pressed = true
		_expect(editor.selected_faction == "enemy", "点敌方按钮 → selected_faction=enemy")
	editor._class_buttons["mage"].button_pressed = true
	_expect(editor.selected_class == "mage", "点头像按钮 → selected_class=mage")

	# ---- 5. Tab 切换可见性 + 读取下拉框数据源 ----
	tabs.current_tab = 4
	await process_frame
	if units_tab != null and file_tab != null:
		_expect(units_tab.is_visible_in_tree(), "切到 Tab4 → 角色 Tab 可见")
		_expect(not file_tab.is_visible_in_tree(), "切走后 → 文件 Tab 隐藏")
	_expect(editor._load_box.item_count >= 4,
		"读取下拉框列出内置战场（≥4，实际 %d）" % editor._load_box.item_count)

	_finish(editor)


## 递归统计子树内某类型控件数（type 为原生类常量或 Script）；
## prune 指定时跳过该类型子树（SpinBox 内部含 LineEdit，需剪枝避免误计）
func _count_type(node: Node, type: Variant, prune: Variant = null) -> int:
	if node == null:
		return 0
	if prune != null and is_instance_of(node, prune):
		return 0
	var n := 0
	if is_instance_of(node, type):
		n += 1
	for c in node.get_children():
		n += _count_type(c, type, prune)
	return n


func _finish(editor: Node) -> void:
	editor.queue_free()
	if failures.is_empty():
		print("MAP_EDITOR_UI_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
