## tests/map_editor_ui_contract.gd — 战场地图编辑器 UI 契约（右侧 Tabs 面板版）
##
## 跑法：godot --headless --path . --script res://tests/map_editor_ui_contract.gd
## 覆盖：右侧 Tabs 面板布局（画布左满幅 + 面板右停靠固定宽）、6 Tab 结构
##       （文件/生成/地形/方块/角色/历史）+ 画布左上角悬浮工具条（画笔/填充/橡皮/角色/选择 垂直图标）、每 Tab 关键控件齐全、
##       地形调色板分「地形/植物」两组：地形=单块 tile（不叠高塔），
##       植物枚举 meowa_tiles 全部素材（树木/植物/装饰三小节）+ 植物层 props，
##       ButtonGroup 交互（工具/地形/植物/阵营/职业单选）联动 editor 状态、
##       画布生效工具跟随激活 Tab（地形页=画笔、角色页=放置单位）、
##       Ctrl+Z/Ctrl+Y 撤销重做（画笔/单位放置/生成，重做分支截断，边界安全）。
##    8. 历史 Tab：动作时间线列表（初始地图为第 0 条、游标高亮、入史同步），
##       换页封存画笔动作，点击任意记录可一步跳转（前进=重做/后退=撤销）。

extends SceneTree

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const BattlefieldRendererScript = preload("res://scripts/iso/battlefield_renderer.gd")
const BlockLayoutScript = preload("res://scripts/core/block_layout.gd")

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
	await _check_viewport_layout(editor, Vector2i(1024, 640))
	await _check_viewport_layout(editor, Vector2i(1280, 800))

	# ---- 1. 根布局：EditorRoot(HBox) 内 画布在左、SidePanel 在右 ----
	var root_box: HBoxContainer = editor.get_node_or_null("EditorRoot")
	_expect(root_box != null, "EditorRoot 存在且为 HBoxContainer")
	if root_box == null:
		_finish(editor)
		return
	_expect(root_box.get_child_count() == 2, "EditorRoot 只有画布容器+面板两个子节点（无顶栏残留）")
	var holder: Control = root_box.get_node_or_null("CanvasHolder")
	var canvas: Control = root_box.get_node_or_null("CanvasHolder/EditorCanvas")
	var side: Control = root_box.get_node_or_null("SidePanel")
	_expect(holder != null, "CanvasHolder 存在（承载画布+悬浮工具条）")
	_expect(canvas != null, "EditorCanvas 存在")
	_expect(side is PanelContainer, "SidePanel 存在且为 PanelContainer")
	if holder != null and side != null:
		_expect(holder.get_index() < side.get_index(), "画布容器在面板左侧")
		_expect(holder.size_flags_horizontal == Control.SIZE_EXPAND_FILL,
			"画布容器水平伸展填充（吃满剩余宽度）")
		_expect(canvas != null and canvas.anchor_right == 1.0 and canvas.anchor_bottom == 1.0,
			"画布在容器内铺满（悬浮工具条覆盖其上）")
	if side != null:
		_expect(side.custom_minimum_size.x >= 320,
			"侧边栏固定宽度且 ≥320（实际 %d）" % int(side.custom_minimum_size.x))
		_expect(side.size_flags_horizontal == Control.SIZE_FILL,
			"侧边栏不参与水平伸展（多余宽度全给画布）")

	# ---- 2. 面板结构：SideVBox -> ToolTabs(6 Tab) + StatusLabel ----
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
	_expect(titles == ["文件", "生成", "地形", "方块", "角色", "历史"],
		"6 个 Tab 且顺序为 文件/生成/地形/方块/角色/历史（实际 %s）" % str(titles))
	var status: Label = sv.get_node_or_null("StatusLabel")
	_expect(status != null and status is Label, "状态栏贴面板底部（SideVBox 内）")
	if status != null:
		_expect(status.get_index() > tabs.get_index(), "状态栏在 Tabs 下方")

	# ---- 3. 各 Tab 关键控件齐全（经 Scroll > VBox 容器，子行可嵌套 HBox） ----
	var file_tab: VBoxContainer = tabs.get_node_or_null("文件Scroll/文件Tab")
	var gen_tab: VBoxContainer = tabs.get_node_or_null("生成Scroll/生成Tab")
	var terrain_tab: VBoxContainer = tabs.get_node_or_null("地形Scroll/地形Tab")
	var block_tab: VBoxContainer = tabs.get_node_or_null("方块Scroll/方块Tab")
	var units_tab: VBoxContainer = tabs.get_node_or_null("角色Scroll/角色Tab")
	_expect(file_tab != null and gen_tab != null
		and terrain_tab != null and block_tab != null and units_tab != null, "5 个内容 Tab 均有内容容器")
	if file_tab != null:
		_expect(_count_type(file_tab, LineEdit) == 2, "文件 Tab：id+名称 两个输入框")
		_expect(_count_type(file_tab, OptionButton) == 1, "文件 Tab：读取下拉框")
		_expect(_count_type(file_tab, CheckButton) == 1, "文件 Tab：托管开关")
		_expect(_count_type(file_tab, Button) >= 4, "文件 Tab：读取/保存/返回按钮齐全")
	if gen_tab != null:
		_expect(_count_type(gen_tab, SpinBox) == 2, "生成 Tab：宽+高 SpinBox")
		_expect(_count_type(gen_tab, LineEdit, SpinBox) == 1,
			"生成 Tab：种子输入框（排除 SpinBox 内部 LineEdit）")
	# 工具条：左上角悬浮（CanvasHolder/ToolBar/ToolBox），5 个垂直图标按钮
	var toolbar: Node = editor.get_node_or_null("EditorRoot/CanvasHolder/ToolBar/ToolBox")
	_expect(toolbar != null and toolbar.get_child_count() == 5,
		"左上角工具条存在且含 5 个工具按钮")
	if toolbar != null:
		var bar: Control = toolbar.get_parent()
		_expect(bar.get_index() == 1 and editor._canvas.get_index() == 0,
			"工具条悬浮在画布之上（CanvasHolder 内后置）")
		_expect(editor._canvas.get_index() < bar.get_index(), "画布在下、工具条在上")

	# 地形/植物分组：TerrainGrid=纯地形单块 tile；植物组枚举全部素材（树木/植物/装饰）
	var terrain_grid: GridContainer = terrain_tab.get_node_or_null("TerrainGrid") if terrain_tab != null else null
	var actual_terrains: int = _count_type(terrain_grid, Button) if terrain_grid != null else -1
	_expect(terrain_grid != null and actual_terrains == BattlefieldDocScript.TERRAIN_GLYPH.size(),
		"地形 Tab：地形组含全部 %d 种地形单块 tile（实际 %d）" % [BattlefieldDocScript.TERRAIN_GLYPH.size(), actual_terrains])
	# 地形 tile 单块化：mountain(5层) 预览只保留顶块
	var m_blocks: Array = BattlefieldRendererScript.preview_blocks(&"mountain", false, true)
	_expect(m_blocks.size() == 1 and int(m_blocks[0].get("level", -1)) == 0,
		"地形 tile 单块化：mountain 预览 = 1 块 level 0（实际 %d 块）" % m_blocks.size())
	# 植物组：三小节网格（树木Grid/植物Grid/装饰Grid），数量=目录 png 数
	var total_plants := 0
	for group_title: String in BattlefieldDocScript.PLANT_DIRS:
		var g: GridContainer = terrain_tab.get_node_or_null("%sGrid" % group_title) if terrain_tab != null else null
		var dir := DirAccess.open(BattlefieldDocScript.PLANT_DIRS[group_title])
		var expect_n := 0
		if dir != null:
			dir.list_dir_begin()
			var fn := dir.get_next()
			while not fn.is_empty():
				if fn.get_extension() == "png" and not dir.current_is_dir():
					expect_n += 1
				fn = dir.get_next()
			dir.list_dir_end()
		var got_n: int = _count_type(g, Button) if g != null else -1
		total_plants += expect_n
		_expect(g != null and got_n == expect_n and expect_n > 0,
			"地形 Tab：植物组「%s」枚举全部 %d 个素材（实际 %d）" % [group_title, expect_n, got_n])
	_expect(total_plants >= 60,
		"植物组覆盖全部素材目录（共 %d 项，应 ≥60）" % total_plants)
	_expect(editor._terrain_buttons.size() == BattlefieldDocScript.TERRAIN_GLYPH.size(),
		"分组后 11 种地形仍全部可选中（_terrain_buttons 全量注册）")
	var tprev: TilePreview = null
	for c in editor._terrain_buttons[&"mountain"].get_children():
		if c is TilePreview:
			tprev = c
	_expect(tprev != null and not tprev.plant and tprev.prop_path.is_empty(),
		"地形组预览 plant=false 且无 prop_path（单块纯地形）")

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

	# 植物按钮联动：current_prop / _active_tool=PLANT（地形 Tab 下）/ 画布落 prop / 橡皮清除
	tabs.current_tab = 2  # 地形 Tab
	await process_frame
	var trees_grid: GridContainer = terrain_tab.get_node_or_null("树木Grid") if terrain_tab != null else null
	var plant_btn: Button = null
	if trees_grid != null:
		for c in trees_grid.get_children():
			if c is Button and c.has_meta("prop"):
				plant_btn = c
				break
	_expect(plant_btn != null, "树木Grid 存在带 prop 元数据的植物按钮")
	if plant_btn != null:
		plant_btn.button_pressed = true
		var prop_path: String = plant_btn.get_meta("prop")
		_expect(editor.current_prop == prop_path, "点植物按钮 → current_prop=该素材路径")
		_expect(editor._active_tool() == editor.Tool.PLANT,
			"地形 Tab 选中植物后 _active_tool()=PLANT")
		var pcell := _first_standable(editor)
		_expect(pcell.x >= 0, "存在可落植物的格")
		if pcell.x >= 0:
			editor._apply_tool(pcell)
			_expect(BattlefieldDocScript.prop_at(editor.model, pcell) == prop_path,
				"画布点按 → 该格落植物 prop")
			editor._seal_pending()  # 快照在下次交互/按键/换页封存，这里手动封存一步
			_expect(editor._history.size() >= 2, "落植物入历史时间线")
			tabs.current_tab = 0  # 文件 Tab：否则地形 Tab 下 _active_tool 仍是 PLANT
			await process_frame
			editor._tool_buttons[editor.Tool.ERASE].button_pressed = true
			editor._apply_tool(pcell)
			_expect(BattlefieldDocScript.prop_at(editor.model, pcell).is_empty(),
				"橡皮 → 清除该格植物")
			editor._tool_buttons[editor.Tool.PAINT].button_pressed = true
		editor._terrain_buttons[pick].button_pressed = true
		_expect(editor.current_prop.is_empty(), "切回地形按钮 → current_prop 清空（回画笔）")

	# ---- 4b. 独立选择 / 方块属性 / 高度历史 / 缩放平移后的真实顶面命中 ----
	_expect(block_tab != null and editor._block_z_box != null, "方块 Tab：BlockZSpin 存在")
	_expect(not editor._block_z_box.editable and editor._canvas.selected_cell == Vector2i(-1, -1),
		"初始无选择：高度输入禁用")
	editor._seal_pending()
	var select_cell := Vector2i(1, 1)
	var before_select: Dictionary = editor.model.duplicate(true)
	var select_history_size: int = editor._history.size()
	var select_cursor: int = editor._history_cursor
	editor._tool_buttons[editor.Tool.SELECT].button_pressed = true
	tabs.current_tab = 0
	editor._apply_tool(select_cell)
	_expect(editor._canvas.selected_cell == select_cell and tabs.current_tab == 3,
		"选择工具：选格并自动激活方块 Tab")
	_expect(editor.model == before_select and editor._history.size() == select_history_size
		and editor._history_cursor == select_cursor and editor._pending_label.is_empty(),
		"选择不是编辑：不改模型、不进历史")
	_expect(editor._block_z_box.editable and int(editor._block_z_box.value) == 0,
		"选格后高度输入启用并同步 z=0")
	editor._on_hover_changed(Vector2i(-1, -1))
	_expect(editor._cell_info_label.text == "(1,1) · 平原 · z=0",
		"左下格信息显示坐标/中文地形/z（实际 %s）" % editor._cell_info_label.text)
	var selected_polygon: PackedVector2Array = editor._canvas._selection_marker.polygon
	_expect(editor._canvas._selection_marker.visible
		and selected_polygon == editor._canvas._renderer.top_polygon_for(1, 1),
		"选择高亮与真实顶面多边形一致")
	var selected_top: Vector2 = editor._canvas._renderer.top_center_for(1, 1)
	var selected_canvas_point: Vector2 = editor._canvas.get_global_transform().affine_inverse() * (
		editor._canvas._renderer.get_global_transform() * selected_top)
	editor._canvas._refresh_hover(selected_canvas_point)
	_expect(editor._canvas.hover_cell == select_cell, "高度修改前 hover 停在所选格")

	editor._block_z_box.value = 6
	_expect(BattlefieldDocScript.cell_z(editor.model, select_cell) == 6
		and BattlefieldDocScript.cell_z(editor.model, Vector2i(1, 0)) == 0
		and BattlefieldDocScript.cell_z(editor.model, Vector2i(0, 1)) == 0,
		"SpinBox 只改所选格 z=6，不动其他格")
	_expect(editor._canvas._renderer.cell_z(select_cell) == 6,
		"改 z 同步渲染器布局深拷贝，不停留在模型")
	var selected_blocks: Array = (editor._canvas._renderer._columns[select_cell] as Node)._blocks
	_expect(selected_blocks.size() == 1 and int(selected_blocks[0].level) == 6,
		"改 z 后实际重建的单块 level=6")
	_expect(editor._canvas._renderer.top_center_for(1, 1) == selected_top + Vector2(0, -60),
		"改 z 后真实顶面向上移动 6×10px")
	_expect(editor._canvas._selection_marker.polygon == editor._canvas._renderer.top_polygon_for(1, 1),
		"改 z 后选择高亮同步到新顶面")
	_expect(editor._canvas.hover_cell == select_cell
		and editor._canvas._hover_marker.polygon == editor._canvas._renderer.top_polygon_for(1, 1),
		"鼠标不动时 hover 仍随单格 z 重建刷新")
	editor._seal_pending()
	var height_cursor: int = editor._history_cursor
	_expect(String(editor._history[height_cursor].label) == "方块高度", "高度修改进入历史")
	_send_key(editor, KEY_Z, true)
	_expect(BattlefieldDocScript.cell_z(editor.model, select_cell) == 0
		and editor._canvas.selected_cell == select_cell and int(editor._block_z_box.value) == 0,
		"撤销高度：z/SpinBox 同步归零且选择不入史")
	_send_key(editor, KEY_Y, true)
	_expect(BattlefieldDocScript.cell_z(editor.model, select_cell) == 6
		and int(editor._block_z_box.value) == 6, "重做高度：z/SpinBox 同步恢复")
	editor._jump_history(height_cursor - 1)
	_expect(BattlefieldDocScript.cell_z(editor.model, select_cell) == 0
		and int(editor._block_z_box.value) == 0, "历史跳转恢复高度前状态")
	editor._jump_history(height_cursor)
	_expect(BattlefieldDocScript.cell_z(editor.model, select_cell) == 6, "历史跳转恢复高度后状态")

	# 直接以 renderer 顶面中心反变换到 canvas 局部坐标，验证缩放/平移不破坏命中。
	var pick_cell := Vector2i(2, 3)
	var renderer_point: Vector2 = editor._canvas._renderer.top_center_for(pick_cell.x, pick_cell.y)
	var canvas_point: Vector2 = editor._canvas.get_global_transform().affine_inverse() * (
		editor._canvas._renderer.get_global_transform() * renderer_point)
	_expect(editor._canvas._pick(canvas_point) == pick_cell, "默认缩放顶面中心命中")
	editor._canvas._zoom_at(Vector2(120, 100), editor._canvas.ZOOM_STEP)
	canvas_point = editor._canvas.get_global_transform().affine_inverse() * (
		editor._canvas._renderer.get_global_transform() * renderer_point)
	_expect(editor._canvas._pick(canvas_point) == pick_cell, "缩放后顶面中心仍命中同格")
	editor._canvas._world.position += Vector2(37, -19)
	canvas_point = editor._canvas.get_global_transform().affine_inverse() * (
		editor._canvas._renderer.get_global_transform() * renderer_point)
	_expect(editor._canvas._pick(canvas_point) == pick_cell, "平移后顶面中心仍命中同格")
	editor._canvas._refresh_hover(canvas_point)
	_expect(editor._canvas.hover_cell == pick_cell
		and editor._canvas._hover_marker.polygon == editor._canvas._renderer.top_polygon_for(pick_cell.x, pick_cell.y),
		"平移缩放后 hover 与真实顶面高光同步")

	var selected_before_paint: Vector2i = editor._canvas.selected_cell
	tabs.current_tab = 2
	editor._apply_tool(Vector2i(2, 1))
	_expect(tabs.current_tab == 2 and editor._canvas.selected_cell == selected_before_paint,
		"绘制不自动切方块页，也不清除选择高亮")

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
		_expect(units_tab.is_visible_in_tree(), "切到 Tab5 → 角色 Tab 可见")
		_expect(not file_tab.is_visible_in_tree(), "切走后 → 文件 Tab 隐藏")
	_expect(editor._load_box.item_count >= 4,
		"读取下拉框列出内置战场（≥4，实际 %d）" % editor._load_box.item_count)

	# ---- 6. 画布生效工具跟随激活 Tab（_active_tool 契约） ----
	# 场景 A（用户报告的 bug）：current_tool=FILL 遗留时，角色 Tab 点画布 = 放置单位
	editor._tool_buttons[editor.Tool.FILL].button_pressed = true
	var cell_a := _first_standable(editor)
	_expect(cell_a.x >= 0, "地图上存在无单位的可站人格")
	var units_before: int = (editor.model.units as Array).size()
	var rows_a: Array = (editor.model.rows as Array).duplicate()
	tabs.current_tab = 4  # 角色 Tab
	editor._apply_tool(cell_a)
	var placed: Dictionary = {}
	for u in editor.model.units:
		if int(u.x) == cell_a.x and int(u.y) == cell_a.y:
			placed = u
	_expect(cell_a.x >= 0 and (editor.model.units as Array).size() == units_before + 1
		and String(placed.get("class", "")) == editor.selected_class,
		"角色 Tab 点画布 → 放置当前职业单位（而非遗留的填充画笔）")
	_expect(cell_a.x < 0 or editor.model.rows == rows_a, "角色 Tab 点画布 → 不改地形")

	# 场景 B：地形 Tab = 画笔改单格，即使 current_tool 仍为 FILL
	var cell_b := _dominant_standable(editor)
	_pick_diff_terrain(editor, cell_b)
	var rows_b: Array = (editor.model.rows as Array).duplicate()
	tabs.current_tab = 2  # 地形 Tab
	editor._apply_tool(cell_b)
	_expect(_diff_cells(rows_b, editor.model.rows) == 1,
		"地形 Tab 点画布 → 画笔只改单格（不受 FILL 遗留影响）")

	# 场景 C（对照组）：文件 Tab（无 _active_tool 覆盖）下 FILL 照常洪水填充连通区域
	var cell_c := _dominant_standable(editor)
	_pick_diff_terrain(editor, cell_c)
	var rows_c: Array = (editor.model.rows as Array).duplicate()
	tabs.current_tab = 0  # 文件 Tab（current_tool=FILL）
	editor._apply_tool(cell_c)
	_expect(_diff_cells(rows_c, editor.model.rows) >= 2,
		"文件 Tab 下 FILL → 洪水填充连通区域（≥2 格）")

	# ---- 7. Ctrl+Z / Ctrl+Y 撤销重做契约 ----
	var base_rows: Array = (editor.model.rows as Array).duplicate()
	var base_units: int = (editor.model.units as Array).size()
	var base_w: int = int(editor.model.width)
	# 7a 地形页画一笔 → 撤销 → 重做
	tabs.current_tab = 2
	var ucell := _dominant_standable(editor)
	_pick_diff_terrain(editor, ucell)
	editor._apply_tool(ucell)
	_expect(_diff_cells(base_rows, editor.model.rows) == 1, "撤销前置：画笔改了 1 格")
	_send_key(editor, KEY_Z, true)
	_expect(editor.model.rows == base_rows, "Ctrl+Z 撤销画笔 → 地形复原")
	_send_key(editor, KEY_Y, true)
	_expect(_diff_cells(base_rows, editor.model.rows) == 1, "Ctrl+Y 重做画笔 → 改动恢复")
	# 7b 撤销后发生新编辑 → 重做栈清空（Ctrl+Y 不再恢复旧改动）
	_send_key(editor, KEY_Z, true)
	var ucell2 := _first_standable(editor)
	_pick_diff_terrain(editor, ucell2)
	editor._apply_tool(ucell2)
	_send_key(editor, KEY_Y, true)
	_expect(_diff_cells(base_rows, editor.model.rows) == 1,
		"新编辑后重做栈已清空（只剩最新 1 格改动）")
	_send_key(editor, KEY_Z, true)
	_expect(editor.model.rows == base_rows, "撤销最新编辑 → 复原")
	# 7c 角色页放单位 → 撤销删除 → 重做恢复
	# （ucell 可能已被 7a 刷成不可站地形，须重新挑选当前可站格）
	tabs.current_tab = 4
	var ucell3 := _first_standable(editor)
	editor._apply_tool(ucell3)
	_expect(ucell3.x >= 0 and (editor.model.units as Array).size() == base_units + 1, "放单位成功")
	_send_key(editor, KEY_Z, true)
	_expect((editor.model.units as Array).size() == base_units, "Ctrl+Z 撤销放置 → 单位移除")
	_send_key(editor, KEY_Y, true)
	_expect((editor.model.units as Array).size() == base_units + 1, "Ctrl+Y 重做放置")
	# 7d 生成替换整图 → 撤销复原地形/尺寸/单位
	editor.apply_generate("undo_probe", 9, 7)
	_expect(int(editor.model.width) == 9 and int(editor.model.height) == 7, "生成 9×7 新图")
	_expect(editor._canvas.selected_cell == Vector2i(-1, -1) and not editor._block_z_box.editable,
		"生成新图清空选择并禁用高度输入")
	_send_key(editor, KEY_Z, true)
	_expect(editor.model.rows == base_rows and int(editor.model.width) == base_w
		and (editor.model.units as Array).size() == base_units + 1,
		"撤销生成 → 地形/尺寸/单位全部复原（含 7c 放置的单位）")
	# 7e 游标回到初始地图后 Ctrl+Z 无操作、不崩溃
	editor._jump_history(0)
	var snap0: Dictionary = editor._history[0]
	_send_key(editor, KEY_Z, true)
	_expect(editor.model.rows == snap0["rows"] and int(editor.model.width) == int(snap0["width"]),
		"游标在第 0 条时 Ctrl+Z → 无操作无崩溃")

	# ---- 8. 历史 Tab：动作时间线 + 点击跳转 ----
	var hist_tab: VBoxContainer = tabs.get_node_or_null("历史Scroll/历史Tab")
	_expect(hist_tab != null, "历史 Tab 存在（第 6 页）")
	var hlist: ItemList = (hist_tab.get_node_or_null("HistoryList")
		if hist_tab != null else null)
	_expect(hlist != null and hlist is ItemList, "历史 Tab：记录列表为 ItemList")
	_expect(editor._history.size() >= 1 and String(editor._history[0]["label"]) == "初始地图",
		"历史首条 = 初始地图")
	_expect(hlist != null and hlist.item_count == editor._history.size()
		and hlist.get_selected_items().size() == 1
		and hlist.get_selected_items()[0] == editor._history_cursor,
		"列表与时间线同步且选中项 = 当前游标")
	# 画一笔 → 切到历史页（换页封存）→ 画笔入史为末条
	tabs.current_tab = 2  # 地形页 → 画笔
	var hcell := _dominant_standable(editor)
	_pick_diff_terrain(editor, hcell)
	editor._apply_tool(hcell)
	tabs.current_tab = 5
	var hsize: int = editor._history.size()
	_expect(hsize >= 2 and String(editor._history[hsize - 1]["label"]) == "画笔",
		"换页封存：画笔动作入史为末条")
	_expect(hlist.item_count == hsize, "入史后列表同步")
	# 点击首条 → 一步跳回初始地图；点击末条 → 跳回画笔后状态
	editor._jump_history(0)
	_expect(editor.model.rows == snap0["rows"], "点击历史首条 → 地图复原为初始")
	editor._jump_history(hsize - 1)
	_expect(_diff_cells(snap0["rows"], editor.model.rows as Array) == 1,
		"点击历史末条 → 画笔改动恢复（恰好 1 格）")
	_expect(editor._history_cursor == hsize - 1, "游标停在末条")
	_expect(hlist.get_selected_items()[0] == hsize - 1, "列表选中跟随游标")

	# ---- 9. resize 同步选择 / 非法读取拒绝 / 合法读取透传 ----
	tabs.current_tab = 3
	editor._select_cell(Vector2i(0, 0), false)
	editor._block_z_box.value = 5
	editor._seal_pending()
	var old_width: int = int(editor.model.width)
	editor._width_box.value = old_width - 1
	_expect(int(editor.model.width) == old_width - 1
		and BattlefieldDocScript.cell_z(editor.model, Vector2i(0, 0)) == 5
		and editor._canvas.selected_cell == Vector2i(0, 0)
		and int(editor._block_z_box.value) == 5,
		"resize 保留交集高度、选择格与 SpinBox")
	editor._select_cell(Vector2i(int(editor.model.width) - 1, int(editor.model.height) - 1), false)
	editor._height_box.value = int(editor.model.height) - 1
	_expect(editor._canvas.selected_cell == Vector2i(-1, -1) and not editor._block_z_box.editable,
		"resize 裁掉选择格后清空选择并禁用高度输入")
	_send_key(editor, KEY_Z, true)
	_expect(int(editor.model.height) == int(editor._history[editor._history_cursor].height),
		"resize 撤销可回读且尺寸与历史游标一致")

	var json_path := "user://map_editor_ui_block_layout_contract.json"
	var payload: Dictionary = BattlefieldDocScript.to_json_dict(editor.model)
	payload["block_layout"]["version"] = 2
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	_expect(file != null, "UI 非法布局临时文件可写")
	if file != null:
		file.store_string(JSON.stringify(payload))
		file.close()
		var before_invalid: Dictionary = editor.model.duplicate(true)
		var history_before_invalid: int = editor._history.size()
		var cursor_before_invalid: int = editor._history_cursor
		_expect(not bool(editor.load_path(json_path).get("ok", false)), "load_path 拒绝非法 block_layout.version")
		_expect(editor.model == before_invalid and editor._history.size() == history_before_invalid
			and editor._history_cursor == cursor_before_invalid,
			"非法读取不改模型、不入史、不动游标")

	payload = BattlefieldDocScript.to_json_dict(editor.model)
	BlockLayoutScript.set_z(payload["block_layout"], Vector2i(0, 0), 9)
	file = FileAccess.open(json_path, FileAccess.WRITE)
	_expect(file != null, "UI 合法布局临时文件可写")
	if file != null:
		file.store_string(JSON.stringify(payload))
		file.close()
		_expect(bool(editor.load_path(json_path).get("ok", false)), "load_path 接受合法显式布局")
		_expect(BattlefieldDocScript.cell_z(editor.model, Vector2i(0, 0)) == 9
			and editor._canvas.selected_cell == Vector2i(-1, -1)
			and not editor._block_z_box.editable,
			"合法读取透传 z=9，并同步清空旧选择")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(json_path))

	_finish(editor)


func _check_viewport_layout(editor: Node, viewport_size: Vector2i) -> void:
	root.size = viewport_size
	await process_frame
	await process_frame
	var holder: Control = editor.get_node_or_null("EditorRoot/CanvasHolder")
	var side: Control = editor.get_node_or_null("EditorRoot/SidePanel")
	var info: Control = editor.get_node_or_null("EditorRoot/CanvasHolder/CellInfoPanel")
	_expect(root.size == viewport_size, "窗口尺寸 %s 生效（实际 %s）" % [viewport_size, root.size])
	_expect(holder != null and side != null and is_equal_approx(side.size.x, 320.0),
		"%s：侧栏保持 320px" % viewport_size)
	if holder != null and side != null:
		_expect(holder.size.x > 0.0 and holder.position.x + holder.size.x <= side.position.x + 1.0,
			"%s：画布左满幅且不与侧栏重叠" % viewport_size)
		_expect(editor._canvas.size == holder.size, "%s：EditorCanvas 填满画布容器" % viewport_size)
	if holder != null and info != null:
		_expect(info.position.x >= 0.0 and info.position.y >= 0.0
			and info.position.x + info.size.x <= holder.size.x + 1.0
			and info.position.y + info.size.y <= holder.size.y + 1.0,
			"%s：左下格信息完整位于画布内" % viewport_size)


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


## 第一个「可站人且无单位」的格子（找不到返回 (-1,-1)）
func _first_standable(editor: Node) -> Vector2i:
	var occupied := {}
	for u in editor.model.units:
		occupied[Vector2i(int(u.x), int(u.y))] = true
	for y in range(int(editor.model.height)):
		var row: String = editor.model.rows[y]
		for x in range(int(editor.model.width)):
			var t: StringName = BattlefieldDocScript.glyph_to_terrain(row.substr(x, 1))
			if BattlefieldLoaderScript._is_standable(t) and not occupied.has(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## 出现次数最多的图例所在格（保证填充连通区域足够大）
func _dominant_standable(editor: Node) -> Vector2i:
	var counts := {}
	var best_glyph := "."
	var best_n := -1
	for y in range(int(editor.model.height)):
		var row: String = editor.model.rows[y]
		for x in range(int(editor.model.width)):
			var g := row.substr(x, 1)
			counts[g] = int(counts.get(g, 0)) + 1
			if int(counts[g]) > best_n:
				best_n = int(counts[g])
				best_glyph = g
	for y in range(int(editor.model.height)):
		var row: String = editor.model.rows[y]
		for x in range(int(editor.model.width)):
			var t: StringName = BattlefieldDocScript.glyph_to_terrain(row.substr(x, 1))
			if row.substr(x, 1) == best_glyph and BattlefieldLoaderScript._is_standable(t):
				return Vector2i(x, y)
	return Vector2i(0, 0)


## 把 current_terrain 换成与 cell 现有图例不同的地形（避免 fill/paint 空操作）
func _pick_diff_terrain(editor: Node, cell: Vector2i) -> void:
	var src: String = (editor.model.rows[cell.y] as String).substr(cell.x, 1)
	for t: StringName in BattlefieldDocScript.TERRAIN_GLYPH:
		if String(BattlefieldDocScript.TERRAIN_GLYPH[t]) != src:
			editor.current_terrain = t
			return


## 两份 rows 逐格差异计数
func _diff_cells(a: Array, b: Array) -> int:
	var n := 0
	for y in range(min(a.size(), b.size())):
		var ra: String = a[y]
		var rb: String = b[y]
		for x in range(min(ra.length(), rb.length())):
			if ra.substr(x, 1) != rb.substr(x, 1):
				n += 1
	return n


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
		print("MAP_EDITOR_UI_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
