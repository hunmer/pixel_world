## scenes/map_editor.gd — 战场地图编辑器（JSON 战场调试工具）
##
## 三大能力（用户需求）：
##   1. 更换地图种子：seed 输入 + 生成（骰子随机种子） -> BattlefieldDoc.generate 确定性地形
##   2. 添加地图实体：地形调色板分「地形/植物」两组（数据驱动遍历
##      TERRAIN_GLYPH，W1 扩链后自动含沙地/雪地/草原/碎石地共 11 种；
##      每项单独一个 tile——地形=纯方块柱，植物=独立树贴图，不组合）+
##      画笔/填充/橡皮
##   3. 添加阵营角色：阵营（我方/敌方）+ 8 职业头像网格（48×48，缺图回退职业
##      首字）+ 等级 + 姓名放置，左键放置/再点删除
## 布局（右侧 Tabs 面板版）：全部 UI 收进右侧固定宽面板（标题 + Tab 页 +
## 状态栏），左侧画布伸展填充最大化；Tab 共 6 页 —— 文件/生成/地形/方块/角色/
## 历史，内容超高走 ScrollContainer 纵向滚动；1280×800 与 1024×640 自适应。
## 画布生效工具跟随激活 Tab：地形页=画笔刷选中地形（选植物则放植物）、
## 角色页=放置单位，其余 Tab 沿用左上角悬浮工具条的手动单选（_active_tool）。
## 撤销/重做：Ctrl+Z / Ctrl+Y（或 Ctrl+Shift+Z），快照式历史时间线覆盖全部
## 编辑动作；历史 Tab 列出动作时间线，点击任意记录可一步跳转到该状态。
## 图标：at-icons 矢量 SVG（res://addons/at-icons/control/，16×16），加载失败
## 自动回退文字标签。保存为 res://data/battlefields/<id>.json（loader schema，
## 保存即回读校验），战场列表（O 键）立即可见可开战。
## UI 样式/控件统一走 scripts/ui（ui_theme.gd 主题 + ui_factory.gd 工厂），
## 本文件不再自带样式 helper；领域按钮工厂（_add_tool_btn 等）保留。
##
## 入口：世界内 E 键 / 战场面板「打开编辑器」按钮；返回 -> res://main.tscn。

extends Control

const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const EditorCanvasScript = preload("res://scripts/editor/editor_canvas.gd")
const TilePreviewScript = preload("res://scripts/editor/tile_preview.gd")
const ProfessionDataScript = preload("res://scripts/core/professions.gd")
const ProfessionVisualScript = preload("res://scripts/iso/profession_visual.gd")
const HintBarScript = preload("res://scripts/hint_bar.gd")

const Tool = { PAINT = 0, FILL = 1, ERASE = 2, UNIT = 3, PLANT = 4, SELECT = 5 }
const TAB_BLOCK := 3

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")

## 配色常量统一取自 ui_theme.gd（本文件别名保持既有引用不变）。
const BG := UIThemeScript.BG
const PANEL_BORDER := UIThemeScript.PANEL_BORDER
const TEXT_MAIN := UIThemeScript.TEXT_MAIN
const TEXT_DIM := UIThemeScript.TEXT_DIM
const ACCENT := UIThemeScript.ACCENT
const ERR := UIThemeScript.ERROR
const BTN_BG := UIThemeScript.BTN_BG
const BTN_BG_HOVER := UIThemeScript.BTN_BG_HOVER
const BTN_BG_PRESSED := UIThemeScript.BTN_BG_PRESSED

const CLASS_IDS: Array[String] = [
	"swordsman", "knight", "archer", "mage", "berserker", "assassin", "lancer", "priest",
]
const PORTRAIT_BTN_SIZE := Vector2(48, 48)
## 右侧面板固定宽度（不随窗口伸展，多出空间全给画布）
const SIDEBAR_WIDTH := 320
## 撤销栈上限（快照式：rows+units 深拷贝，画笔整笔拖动合并为一步）
const UNDO_LIMIT := 100
var model: Dictionary = {}
var current_tool: int = Tool.PAINT
var current_terrain: StringName = &"mountain"
## 当前选中的具体植物贴图（非空=地形 Tab 画笔改为放置植物，写模型 props 层）
var current_prop := ""
## 植物素材枚举 { 组名: [res://路径] }（_ready 里扫描，_build_terrain_tab 用）
var _prop_paths: Dictionary = {}
var selected_class: String = "swordsman"
var selected_faction: String = "player"

var _canvas: EditorCanvasScript
var _tabs: TabContainer
## 历史时间线：_history[k] = 第 k 步动作完成后的快照（含 label）；
## _history[0] = 「初始地图」；_history_cursor 指向当前状态
var _history: Array[Dictionary] = []
var _history_cursor := 0
## 按下时登记、下一次交互时封存的「未完成动作」标签（画笔拖动整笔合并）
var _pending_label := ""
var _syncing_history := false
var _history_list: ItemList
var _status_label: Label
var _id_edit: LineEdit
var _name_edit: LineEdit
var _seed_edit: LineEdit
var _width_box: SpinBox
var _height_box: SpinBox
var _hosting_check: CheckButton
var _level_box: SpinBox
var _unit_name_edit: LineEdit
var _load_box: OptionButton
var _block_z_box: SpinBox
var _cell_info_label: Label
var _syncing_block_z := false
var _tool_buttons: Dictionary = {}   # Tool -> Button
var _terrain_buttons: Dictionary = {}  # StringName(terrain) -> Button
var _class_buttons: Dictionary = {}  # String(class_id) -> Button
## 程序化同步 SpinBox 时挂起 _on_resize（避免读到另一半的旧值触发错误 resize）
var _syncing_boxes := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	model = BattlefieldDocScript.create_empty()
	_prop_paths = _scan_prop_paths()  # 植物素材枚举（_build_terrain_tab 用）
	_build_ui()
	_init_history()  # 初始空板定格为历史第 0 条「初始地图」


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		var ctrl := key.ctrl_pressed or key.meta_pressed
		if ctrl and (key.keycode == KEY_Z or key.physical_keycode == KEY_Z):
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			# Ctrl+Z 撤销；Ctrl+Shift+Z / Ctrl+Y 重做（通用习惯）
			if key.shift_pressed:
				_redo()
			else:
				_undo()
		elif ctrl and (key.keycode == KEY_Y or key.physical_keycode == KEY_Y):
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			_redo()
		elif key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE:
			# 先标记已处理再切场景：change_scene 后本节点被释放，get_viewport() 会变 null
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			_back_to_world()
		elif not ctrl and (key.keycode == KEY_Q or key.keycode == KEY_Z):
			# 视角旋转 ±90°（Q/Z 左转；E/X 右转；R 复位）——与世界/战棋肌肉记忆一致
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			_canvas.rotate_view(-1)
		elif not ctrl and (key.keycode == KEY_E or key.keycode == KEY_X):
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			_canvas.rotate_view(1)
		elif not ctrl and key.keycode == KEY_R:
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			_canvas.reset_view()


# ============================================================
# UI 构建（容器化：VBox/HBox/ScrollContainer 锚点全矩形自适应，
# 纯代码建 UI，项目风格与 game_hud.gd / title.gd 一致）
# ============================================================

func _build_ui() -> void:
	# ---- 根：画布（左，伸展填充） + 右侧 Tabs 面板（固定宽） ----
	var root := HBoxContainer.new()
	root.name = "EditorRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_top = 6
	root.offset_right = -8
	root.offset_bottom = -6
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# ---- 画布（等距方块渲染，内部自带平移/缩放；先加=最左，吃满剩余宽度） ----
	# ---- 画布容器（画布吃满 + 左上角悬浮工具条覆盖在画布上） ----
	var holder := Control.new()
	holder.name = "CanvasHolder"
	holder.custom_minimum_size = Vector2(320, 240)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(holder)

	_canvas = EditorCanvasScript.new()
	_canvas.name = "EditorCanvas"
	_canvas.cell_pressed.connect(_on_cell_pressed)
	_canvas.cell_dragged.connect(_on_cell_dragged)
	_canvas.hover_changed.connect(_on_hover_changed)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 3D 取景让出右侧栏宽度（同世界 reserved_right_px），画布内容对齐舞台中心
	_canvas.sidebar_reserved_px = SIDEBAR_WIDTH
	holder.add_child(_canvas)

	# ---- 左上角垂直工具条（悬浮在画布上，取代旧「工具」Tab） ----
	holder.add_child(_build_tool_bar())
	holder.add_child(_build_cell_info())
	# ---- 底部操作提示条（复用 hint_bar.gd 组件，与世界 HUD 同一套 keycap 提示） ----
	holder.add_child(_build_hint_bar())

	# ---- 右侧面板：标题 / 5 个 Tab / 状态栏（固定宽，不吃画布空间） ----
	var side := PanelContainer.new()
	side.name = "SidePanel"
	side.custom_minimum_size = Vector2(SIDEBAR_WIDTH, 0)
	side.size_flags_horizontal = Control.SIZE_FILL
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_stylebox_override("panel", UIThemeScript.overlay_panel_style())
	root.add_child(side)

	var sv := VBoxContainer.new()
	sv.name = "SideVBox"
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", 6)
	side.add_child(sv)

	# 标题行：at-icons 扳手图标 + 文字（图标缺失只显示文字）
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	var wrench: Texture2D = UIThemeScript.icon("wrench")
	if wrench != null:
		var tw := TextureRect.new()
		tw.texture = wrench
		tw.custom_minimum_size = Vector2(18, 18)
		tw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tw.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_row.add_child(tw)
	title_row.add_child(UIFactoryScript.label("战场编辑器", 16, ACCENT))
	sv.add_child(title_row)

	# ---- 6 个 Tab：文件 / 生成 / 地形 / 方块 / 角色 / 历史 ----
	# Tab 样式统一走 ui_factory.tab_container（含页签三态与面板底）
	var tabs := UIFactoryScript.tab_container("ToolTabs")
	_tabs = tabs
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.tab_changed.connect(_on_tab_changed)
	sv.add_child(tabs)
	_build_file_tab(tabs)
	_build_generate_tab(tabs)
	_build_terrain_tab(tabs)
	_build_block_tab(tabs)
	_build_units_tab(tabs)
	_build_history_tab(tabs)

	# ---- 状态栏（贴面板底部，自动换行） ----
	_status_label = UIFactoryScript.label("就绪 — 左键操作画布；同种子+同尺寸生成结果确定", 11, TEXT_DIM)
	_status_label.name = "StatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(_status_label)

	_refresh_canvas()

# ============================================================
# Tab 构建（每页 ScrollContainer 只纵向滚 + VBox，与旧侧栏滚动策略一致）
# ============================================================
## Tab【文件】：id / 名称 / 托管 / 读取 / 保存 / 返回
func _build_file_tab(tabs: TabContainer) -> void:
	var tab := UIFactoryScript.add_tab(tabs, "文件", "floppy_disk")
	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 4)
	id_row.add_child(UIFactoryScript.label("id:", 11, TEXT_DIM))
	_id_edit = UIFactoryScript.line_edit()
	_id_edit.text = "custom_map"
	_id_edit.placeholder_text = "snake_case"
	_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_row.add_child(_id_edit)
	tab.add_child(id_row)
	UIFactoryScript.center_row(id_row)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	name_row.add_child(UIFactoryScript.label("名称:", 11, TEXT_DIM))
	_name_edit = UIFactoryScript.line_edit()
	_name_edit.text = "自定义战场"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)
	tab.add_child(name_row)
	UIFactoryScript.center_row(name_row)

	_hosting_check = CheckButton.new()
	_hosting_check.text = "托管"
	_hosting_check.tooltip_text = "开启后战斗自动托管运行（AI 对 AI），调试观察用"
	tab.add_child(_hosting_check)

	_load_box = OptionButton.new()
	_load_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refresh_load_box()
	tab.add_child(_load_box)

	var io_row := HBoxContainer.new()
	io_row.add_theme_constant_override("separation", 4)
	var load_btn := _action_btn("读取", _load_selected, "folder_open")
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	io_row.add_child(load_btn)
	var save_btn := _action_btn("保存", _save, "floppy_disk")
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	io_row.add_child(save_btn)
	tab.add_child(io_row)

	var back_btn := _action_btn("返回(Esc)", _back_to_world, "doorway_exit")
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(back_btn)


## Tab【生成】：种子 / 随机种子 / 宽高 / 生成 / 清空地形
func _build_generate_tab(tabs: TabContainer) -> void:
	var tab := UIFactoryScript.add_tab(tabs, "生成", "dice")
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 4)
	seed_row.add_child(UIFactoryScript.label("种子:", 11, TEXT_DIM))
	_seed_edit = UIFactoryScript.line_edit()
	_seed_edit.text = "demo"
	_seed_edit.placeholder_text = "任意文本，同种子同地图"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_edit)
	tab.add_child(seed_row)
	UIFactoryScript.center_row(seed_row)

	var dice_btn := _action_btn("随机种子", func():
		_seed_edit.text = str(Time.get_unix_time_from_system()).sha1_text().substr(0, 8)
		_generate(), "dice")
	dice_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(dice_btn)

	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 4)
	size_row.add_child(UIFactoryScript.label("宽:", 11, TEXT_DIM))
	_width_box = SpinBox.new()
	_width_box.min_value = BattlefieldDocScript.MIN_SIZE
	_width_box.max_value = BattlefieldDocScript.MAX_SIZE
	_width_box.value = model.width
	_width_box.value_changed.connect(func(_v: float): _on_resize())
	_width_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(_width_box)
	size_row.add_child(UIFactoryScript.label("高:", 11, TEXT_DIM))
	_height_box = SpinBox.new()
	_height_box.min_value = BattlefieldDocScript.MIN_SIZE
	_height_box.max_value = BattlefieldDocScript.MAX_SIZE
	_height_box.value = model.height
	_height_box.value_changed.connect(func(_v: float): _on_resize())
	_height_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(_height_box)
	tab.add_child(size_row)
	UIFactoryScript.center_row(size_row)

	var gen_row := HBoxContainer.new()
	gen_row.add_theme_constant_override("separation", 4)
	var gen_btn := _action_btn("生成", _generate, "sprout")
	gen_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen_row.add_child(gen_btn)
	var clear_btn := _action_btn("清空地形", func():
		_push_undo("清空地形")
		model.rows = BattlefieldDocScript.create_empty(model.width, model.height).rows
		model.props = []  # 植物层一并清空
		_refresh_canvas()
		_status("地形已清空（单位保留）"), "trash_can")
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen_row.add_child(clear_btn)
	tab.add_child(gen_row)


## 左上角悬浮工具条：选择 / 画笔 / 填充 / 橡皮 / 角色 垂直图标按钮（覆盖在画布上）
func _build_tool_bar() -> Control:
	var bar := PanelContainer.new()
	bar.name = "ToolBar"
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	bar.offset_left = 8
	bar.offset_top = 8
	bar.add_theme_stylebox_override("panel", UIThemeScript.overlay_panel_style())
	var box := VBoxContainer.new()
	box.name = "ToolBox"
	box.add_theme_constant_override("separation", 4)
	bar.add_child(box)
	var tool_group := ButtonGroup.new()
	tool_group.pressed.connect(func(btn: Button):
		current_tool = btn.get_meta("tool")
		_on_tool_changed())
	_add_tool_btn(box, tool_group, Tool.SELECT, "选择", "mouse_pointer")
	_add_tool_btn(box, tool_group, Tool.PAINT, "画笔", "paintbrush")
	_add_tool_btn(box, tool_group, Tool.FILL, "填充", "bucket_fill")
	_add_tool_btn(box, tool_group, Tool.ERASE, "橡皮", "eraser")
	_add_tool_btn(box, tool_group, Tool.UNIT, "角色", "person")
	_tool_buttons[Tool.PAINT].button_pressed = true
	return bar


func _build_cell_info() -> Control:
	var panel := PanelContainer.new()
	panel.name = "CellInfoPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 8
	panel.offset_top = -38
	panel.offset_right = 250
	panel.offset_bottom = -8
	panel.add_theme_stylebox_override("panel", UIThemeScript.overlay_panel_style())
	_cell_info_label = UIFactoryScript.label("未选中格子", 11, TEXT_MAIN)
	_cell_info_label.name = "CellInfoLabel"
	_cell_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_cell_info_label)
	return panel


## 底部右侧操作提示条：快捷键/鼠标操作 keycap（复用 hint_bar.gd，同 game_hud）。
## 锚定右下角、向左/向上生长（HFlow 过窄自动换行）；横向避开左下 CellInfoPanel
## （其右缘固定 250px，最窄 1024 视口下画布宽约 680，提示条左缘 ≥268 不重叠）。
func _build_hint_bar() -> Control:
	var bar := HintBarScript.new()
	bar.name = "EditorHintBar"
	bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.custom_minimum_size = Vector2(360.0, 30.0)
	bar.offset_left = -412.0
	bar.offset_top = -86.0
	bar.offset_right = -12.0
	bar.offset_bottom = -10.0
	bar.set_title("操作")
	bar.add_hint("左键", "使用工具")
	bar.add_hint("SPACE+左键 / 右键拖", "平移")
	bar.add_hint("滚轮 / 双指捏合", "缩放")
	bar.add_hint("Q E / Z X", "转向 90°")
	bar.add_hint("R", "视角复位")
	bar.add_hint("CTRL+Z / Y", "撤销 / 重做")
	bar.add_hint("ESC", "返回世界")
	return bar


## Tab【地形】：地形 / 植物 分组调色板。
## 地形组：11 种地形各一个**单块** tile（不叠高塔、不插树）。
## 植物组：枚举 trees/plants/decorations 全部素材（树木/植物/装饰三小节），
## 每张贴图一个独立 tile，选中后画笔在格子上放置该具体植物（模型 props 层）。
## 全部按钮共用一个 ButtonGroup（选地形清空 current_prop，选植物反之）。
func _build_terrain_tab(tabs: TabContainer) -> void:
	var tab := UIFactoryScript.add_tab(tabs, "地形", "sprout")
	var terrain_group := ButtonGroup.new()
	terrain_group.pressed.connect(func(btn: Button):
		if btn.has_meta("terrain"):
			current_terrain = btn.get_meta("terrain")
			current_prop = ""
		elif btn.has_meta("prop"):
			current_prop = btn.get_meta("prop"))
	# ---- 地形组（单块 tile，不叠装饰物/高塔）----
	tab.add_child(UIFactoryScript.label("地形", 12, TEXT_DIM))
	var tgrid := GridContainer.new()
	tgrid.name = "TerrainGrid"
	tgrid.columns = 4
	tgrid.add_theme_constant_override("h_separation", 2)
	tgrid.add_theme_constant_override("v_separation", 2)
	tab.add_child(tgrid)
	for t: StringName in BattlefieldDocScript.TERRAIN_GLYPH:
		var tb := _terrain_btn(t, terrain_group)
		tgrid.add_child(tb)
		_terrain_buttons[t] = tb
	# ---- 植物组：全部素材按目录分三小节（树木/植物/装饰）----
	for group_title: String in BattlefieldDocScript.PLANT_DIRS:
		tab.add_child(UIFactoryScript.label("%s（%d）" % [group_title, _prop_paths[group_title].size()], 12, TEXT_DIM))
		var pgrid := GridContainer.new()
		pgrid.name = "%sGrid" % group_title
		pgrid.columns = 4
		pgrid.add_theme_constant_override("h_separation", 2)
		pgrid.add_theme_constant_override("v_separation", 2)
		tab.add_child(pgrid)
		for path: String in _prop_paths[group_title]:
			var pb := _plant_btn(path, terrain_group)
			pgrid.add_child(pb)
	_terrain_buttons[current_terrain].button_pressed = true


## Tab【方块】：只编辑当前选格的独立高度，不修改同列/其他格。
func _build_block_tab(tabs: TabContainer) -> void:
	var tab := UIFactoryScript.add_tab(tabs, "方块", "cube")
	tab.add_child(UIFactoryScript.label("用「选择」工具点选格子；拖动其他工具不会改变选择。", 11, TEXT_DIM))
	var row := HBoxContainer.new()
	row.name = "BlockZRow"
	row.add_theme_constant_override("separation", 6)
	row.add_child(UIFactoryScript.label("所在 z:", 12, TEXT_MAIN))
	_block_z_box = SpinBox.new()
	_block_z_box.name = "BlockZSpin"
	_block_z_box.min_value = BattlefieldDocScript.BLOCK_MIN_Z
	_block_z_box.max_value = BattlefieldDocScript.BLOCK_MAX_Z
	_block_z_box.step = 1
	_block_z_box.rounded = true
	_block_z_box.editable = false
	_block_z_box.tooltip_text = "未选择格子时禁用；范围 0..16"
	_block_z_box.value_changed.connect(_on_block_z_changed)
	_block_z_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_block_z_box)
	tab.add_child(row)
	UIFactoryScript.center_row(row)
	tab.add_child(UIFactoryScript.label("每格只有一个独立方块；z=0 为统一平面。", 10, TEXT_DIM))


## 扫描植物素材目录（BattlefieldDoc.PLANT_DIRS）→ { 组名: [res://路径] }（排序）
func _scan_prop_paths() -> Dictionary:
	var out: Dictionary = {}
	for group_title: String in BattlefieldDocScript.PLANT_DIRS:
		var paths: Array[String] = []
		var dir := DirAccess.open(BattlefieldDocScript.PLANT_DIRS[group_title])
		if dir != null:
			dir.list_dir_begin()
			var fn := dir.get_next()
			while not fn.is_empty():
				if fn.get_extension() == "png" and not dir.current_is_dir():
					paths.append(BattlefieldDocScript.PLANT_DIRS[group_title] + "/" + fn)
				fn = dir.get_next()
			dir.list_dir_end()
			paths.sort()
		out[group_title] = paths
	return out


## 植物按钮：独立贴图 tile（无文字，悬停提示素材名），选中写 current_prop
func _plant_btn(path: String, group: ButtonGroup) -> Button:
	var tb := Button.new()
	tb.toggle_mode = true
	tb.button_group = group
	tb.custom_minimum_size = Vector2(46, 96)
	tb.tooltip_text = path.get_file().get_basename()
	tb.set_meta("prop", path)
	UIThemeScript.style_button(tb)
	var prev := TilePreviewScript.new(&"plain", false, path)
	tb.add_child(prev)
	prev.position = (tb.custom_minimum_size - prev.size) * 0.5
	return tb


## Tab【角色】：阵营 + 8 职业头像网格 + 等级/姓名
func _build_units_tab(tabs: TabContainer) -> void:
	var tab := UIFactoryScript.add_tab(tabs, "角色", "person")
	var faction_row := HBoxContainer.new()
	faction_row.add_theme_constant_override("separation", 4)
	var faction_group := ButtonGroup.new()
	faction_group.pressed.connect(func(btn: Button):
		selected_faction = btn.get_meta("faction"))
	faction_row.add_child(_faction_btn("player", "我方", "shield", faction_group))
	faction_row.add_child(_faction_btn("enemy", "敌方", "skull", faction_group))
	tab.add_child(faction_row)

	var class_group := ButtonGroup.new()
	class_group.pressed.connect(func(btn: Button):
		selected_class = btn.get_meta("class"))
	var pgrid := GridContainer.new()
	pgrid.name = "PortraitGrid"
	pgrid.columns = 4
	pgrid.add_theme_constant_override("h_separation", 4)
	pgrid.add_theme_constant_override("v_separation", 4)
	tab.add_child(pgrid)
	# 头像网格：8 职业 4×2、48×48（ProfessionVisual.portrait_path，缺图回退职业首字）
	for cid: String in CLASS_IDS:
		var pb := _class_btn(cid, class_group)
		pgrid.add_child(pb)
		_class_buttons[cid] = pb
	_class_buttons[selected_class].button_pressed = true

	var lv_row := HBoxContainer.new()
	lv_row.add_theme_constant_override("separation", 4)
	lv_row.add_child(UIFactoryScript.label("等级:", 11, TEXT_DIM))
	_level_box = SpinBox.new()
	_level_box.min_value = 1
	_level_box.max_value = 9
	_level_box.value = 3
	_level_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv_row.add_child(_level_box)
	lv_row.add_child(UIFactoryScript.label("姓名:", 11, TEXT_DIM))
	_unit_name_edit = UIFactoryScript.line_edit()
	_unit_name_edit.placeholder_text = "自动"
	_unit_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv_row.add_child(_unit_name_edit)
	tab.add_child(lv_row)
	UIFactoryScript.center_row(lv_row)


## Tab【历史】：动作时间线（点击任意记录跳转到该状态）
func _build_history_tab(tabs: TabContainer) -> void:
	var tab := UIFactoryScript.add_tab(tabs, "历史", "clock")
	_history_list = ItemList.new()
	_history_list.name = "HistoryList"
	_history_list.custom_minimum_size = Vector2(0, 240)
	_history_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_list.allow_reselect = true
	_history_list.item_selected.connect(func(idx: int):
		if not _syncing_history:
			_jump_history(idx))
	tab.add_child(_history_list)
	tab.add_child(UIFactoryScript.label("点击记录跳转到该状态；Ctrl+Z / Ctrl+Y 撤销重做", 10, TEXT_DIM))


## 切 Tab 时封存上一动作（画笔拖动在换页瞬间定格为一步）
func _on_tab_changed(_idx: int) -> void:
	_seal_pending()
# ============================================================
# UI 构建辅助（统一样式系统 + 控件工厂）
# ============================================================
func _add_tool_btn(parent: Node, group: ButtonGroup, tool: int, text: String, icon_name := "") -> void:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	var icon: Texture2D = null
	if icon_name != "":
		icon = UIThemeScript.icon(icon_name)
	if icon != null:
		# 垂直工具条：只显示图标（tooltip 提示名称），固定方形按钮
		b.icon = icon
		b.text = ""
		b.tooltip_text = "%s工具" % text
		b.custom_minimum_size = Vector2(34, 34)
		b.expand_icon = true
	else:
		b.text = text
		b.tooltip_text = text
	b.set_meta("tool", tool)
	UIThemeScript.style_button(b)
	parent.add_child(b)
	_tool_buttons[tool] = b


## 动作按钮：图标 + 文字并排（图标缺失只显示文字）
func _action_btn(text: String, cb: Callable, icon_name := "") -> Button:
	var b := Button.new()
	b.text = text
	var icon: Texture2D = null
	if icon_name != "":
		icon = UIThemeScript.icon(icon_name)
	if icon != null:
		b.icon = icon
	UIThemeScript.style_button(b)
	b.pressed.connect(cb)
	return b

## 阵营切换按钮（盾=我方 / 骷髅=敌方，ButtonGroup 单选；缺图回退纯文字）
func _faction_btn(faction: String, label: String, icon_name: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.set_meta("faction", faction)
	b.tooltip_text = "%s %s" % [label, faction]
	b.custom_minimum_size = Vector2(104, 30)
	var icon: Texture2D = null
	if icon_name != "":
		icon = UIThemeScript.icon(icon_name)
	if icon != null:
		b.icon = icon
	b.text = label
	UIThemeScript.style_button(b)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.button_pressed = faction == selected_faction
	return b


## 调色板按钮：每项一个 tile 缩略图（无文字，悬停提示地形名）。
## plant=true 用独立植物贴图（树单独成块，不叠在方块柱上）。
func _terrain_btn(t: StringName, group: ButtonGroup, plant := false) -> Button:
	var tb := Button.new()
	tb.toggle_mode = true
	tb.button_group = group
	tb.custom_minimum_size = Vector2(46, 96)
	tb.tooltip_text = "%s（%s）" % [
		String(BattlefieldDocScript.TERRAIN_CN.get(t, String(t))),
		String(BattlefieldDocScript.TERRAIN_GLYPH[t]),
	]
	tb.set_meta("terrain", t)
	UIThemeScript.style_button(tb)
	var prev := TilePreviewScript.new(t, plant)
	tb.add_child(prev)
	# Button 不是 Container：手动按按钮最小尺寸居中（anchors 在无父时会烤错）。
	prev.position = (tb.custom_minimum_size - prev.size) * 0.5
	return tb


## 职业头像按钮：48×48；有立绘显示 TextureRect，缺图回退职业首字（按钮文本自动居中）
func _class_btn(cid: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = PORTRAIT_BTN_SIZE
	var cn := ProfessionDataScript.profession_name(StringName(cid))
	b.tooltip_text = "%s %s" % [cn, cid]
	b.set_meta("class", cid)
	UIThemeScript.style_button(b)
	if ProfessionVisualScript.portrait_exists(StringName(cid)):
		var tex: Texture2D = load(ProfessionVisualScript.portrait_path(StringName(cid)))
		var tr := TextureRect.new()
		tr.texture = tex
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		b.add_child(tr)
		# Button 不是 Container：显式给尺寸并贴边内缩 3px 居中（TilePreview 同款处理）
		tr.size = PORTRAIT_BTN_SIZE - Vector2(6, 6)
		tr.position = Vector2(3, 3)
	else:
		b.text = cn.substr(0, 1)
		b.add_theme_font_size_override("font_size", 14)
	return b
# ============================================================
# 编辑操作（canvas 信号 + 可测方法；生效工具由激活 Tab 决定）
# ============================================================

## 当前生效工具：地形 Tab = 画笔刷选中地形（选了具体植物则改为放置植物）；
## 角色 Tab = 放置单位；其余 Tab = 左上角工具条的手动单选 current_tool。
## 避免在角色页选好职业点画布，却沿用工具条遗留的填充/橡皮。
func _active_tool() -> int:
	if _tabs == null:
		return current_tool
	var title := _tabs.get_tab_title(_tabs.current_tab)
	if title == "地形":
		return Tool.PLANT if not current_prop.is_empty() else Tool.PAINT
	if title == "方块":
		return Tool.SELECT
	if title == "角色":
		return Tool.UNIT
	return current_tool


func _on_cell_pressed(cell: Vector2i) -> void:
	_apply_tool(cell)


func _on_cell_dragged(cell: Vector2i) -> void:
	# 拖动仅对画笔/植物/橡皮有意义（填充/角色不响应拖动）
	var tool := _active_tool()
	if tool == Tool.SELECT:
		_select_cell(cell)
	elif tool == Tool.PAINT:
		_set_glyph(cell, BattlefieldDocScript.TERRAIN_GLYPH[current_terrain])
	elif tool == Tool.PLANT:
		_set_prop(cell, current_prop)
	elif tool == Tool.ERASE:
		_set_glyph(cell, ".")
		_set_prop(cell, "")


func _apply_tool(cell: Vector2i) -> void:
	var tool := _active_tool()
	if tool == Tool.SELECT:
		_select_cell(cell)
		return  # 选择不是文档编辑，不进入历史。
	var names := { Tool.PAINT: "画笔", Tool.FILL: "填充", Tool.ERASE: "橡皮", Tool.UNIT: "角色", Tool.PLANT: "植物" }
	_push_undo(names[tool])  # 按下一次=一步；后续拖动不再入栈（整笔一笔撤销）
	match tool:
		Tool.PAINT:
			_set_glyph(cell, BattlefieldDocScript.TERRAIN_GLYPH[current_terrain])
		Tool.FILL:
			fill_cell(cell, current_terrain)
		Tool.ERASE:
			if _remove_unit_at(cell):
				pass  # 单位优先删除
			else:
				_set_glyph(cell, ".")
				_set_prop(cell, "")
		Tool.UNIT:
			if not _remove_unit_at(cell):
				place_unit(cell, selected_faction, selected_class, int(_level_box.value), _unit_name_edit.text)
		Tool.PLANT:
			_set_prop(cell, current_prop)


func _select_cell(cell: Vector2i, activate_block: bool = true) -> void:
	_canvas.selected_cell = cell
	_sync_block_panel()
	_update_cell_info(cell)
	if activate_block and _tabs != null:
		_tabs.current_tab = TAB_BLOCK


func _on_hover_changed(cell: Vector2i) -> void:
	if cell.x >= 0:
		_update_cell_info(cell)
	elif _canvas.selected_cell.x >= 0:
		_update_cell_info(_canvas.selected_cell)
	else:
		_update_cell_info(Vector2i(-1, -1))


func _update_cell_info(cell: Vector2i) -> void:
	if _cell_info_label == null:
		return
	if cell.x < 0 or cell.y < 0 or cell.x >= int(model.width) or cell.y >= int(model.height):
		_cell_info_label.text = "未选中格子"
		return
	var terrain := BattlefieldDocScript.glyph_to_terrain((model.rows[cell.y] as String).substr(cell.x, 1))
	_cell_info_label.text = "(%d,%d) · %s · z=%d" % [
		cell.x, cell.y, BattlefieldDocScript.TERRAIN_CN[terrain], BattlefieldDocScript.cell_z(model, cell)
	]


func _sync_block_panel() -> void:
	if _block_z_box == null:
		return
	var cell: Vector2i = _canvas.selected_cell
	var valid := cell.x >= 0 and cell.y >= 0 and cell.x < int(model.width) and cell.y < int(model.height)
	_syncing_block_z = true
	_block_z_box.editable = valid
	_block_z_box.value = BattlefieldDocScript.cell_z(model, cell) if valid else 0
	_syncing_block_z = false


func _on_block_z_changed(value: float) -> void:
	if _syncing_block_z or _canvas.selected_cell.x < 0:
		return
	var cell: Vector2i = _canvas.selected_cell
	_push_undo("方块高度")
	if not BattlefieldDocScript.set_cell_z(model, cell, int(value)):
		return
	_canvas._refresh_cell(cell)
	_sync_block_panel()
	_update_cell_info(cell)
	_status("方块高度 (%d,%d) → z=%d" % [cell.x, cell.y, int(value)])
	print("[editor] 单格高度 cell=%s z=%d" % [str(cell), int(value)])  # L1 埋点


func _sync_selection_after_model_change(clear_selection: bool = false) -> void:
	var cell: Vector2i = _canvas.selected_cell
	if clear_selection or cell.x < 0 or cell.y < 0 or cell.x >= int(model.width) or cell.y >= int(model.height):
		_canvas.selected_cell = Vector2i(-1, -1)
	else:
		_canvas.selected_cell = cell
	_sync_block_panel()
	_update_cell_info(_canvas.selected_cell)


## 放置/清除（path 为空）某格的具体植物；与地形解耦，同格至多一株
func _set_prop(cell: Vector2i, path: String) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(model.width) or cell.y >= int(model.height):
		return
	if path.is_empty():
		if BattlefieldDocScript.remove_prop(model, cell):
			_canvas._refresh_cell(cell)
		return
	if not BattlefieldDocScript.set_prop(model, cell, path):
		return
	_canvas._refresh_cell(cell)
	_status("放置植物 %s @(%d,%d)" % [path.get_file().get_basename(), cell.x, cell.y])


## 设置地形图例字符（含画笔/橡皮/拖动路径）
func _set_glyph(cell: Vector2i, glyph: String) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= model.width or cell.y >= model.height:
		return
	var rows: Array = model.rows
	var row: String = rows[cell.y]
	if row.substr(cell.x, 1) == glyph:
		return
	rows[cell.y] = row.substr(0, cell.x) + glyph + row.substr(cell.x + 1)
	_canvas._refresh_cell(cell)


## 洪水填充：同图例连通区域 -> 目标地形
func fill_cell(cell: Vector2i, terrain: StringName) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= model.width or cell.y >= model.height:
		return
	var rows: Array = model.rows
	var from: String = (rows[cell.y] as String).substr(cell.x, 1)
	var to: String = String(BattlefieldDocScript.TERRAIN_GLYPH.get(terrain, "."))
	if from == to:
		return
	var stack: Array[Vector2i] = [cell]
	var seen := { cell: true }
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		rows[c.y] = (rows[c.y] as String).substr(0, c.x) + to + (rows[c.y] as String).substr(c.x + 1)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= model.width or n.y >= model.height or seen.has(n):
				continue
			if (rows[n.y] as String).substr(n.x, 1) == from:
				seen[n] = true
				stack.append(n)
	_refresh_canvas()
	_status("填充 %s ×%d 格" % [BattlefieldDocScript.TERRAIN_CN[terrain], seen.size()])


## 放置阵营角色：站不住的地形拒绝；同格已有单位则先移除
func place_unit(cell: Vector2i, faction: String, class_id: String, level: int, uname: String = "") -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= model.width or cell.y >= model.height:
		_status("越界：(%d,%d)" % [cell.x, cell.y], true)
		return false
	var terrain := BattlefieldDocScript.glyph_to_terrain((model.rows[cell.y] as String).substr(cell.x, 1))
	if not BattlefieldLoaderScript._is_standable(terrain):
		_status("%s 不可站人（%s）" % [BattlefieldDocScript.TERRAIN_CN[terrain], str(cell)], true)
		return false
	_remove_unit_at(cell)
	var cn := ProfessionDataScript.profession_name(StringName(class_id))
	var seq := 1
	for u in model.units:
		if String(u.get("class", "")) == class_id and String(u.get("faction", "")) == faction:
			seq += 1
	var unit := {
		"class": class_id,
		"name": uname.strip_edges() if not uname.strip_edges().is_empty() else "%s%d" % [cn, seq],
		"level": clampi(level, 1, 9),
		"x": cell.x,
		"y": cell.y,
		"faction": faction,
		"tag": cn.substr(0, 1),
	}
	(model.units as Array).append(unit)
	_canvas._refresh_cell(cell)
	_status("放置 %s·%s Lv%d @(%d,%d)" % [cn, unit.name, unit.level, cell.x, cell.y])
	return true


## 删除 (cell) 处单位；返回是否删到
func _remove_unit_at(cell: Vector2i) -> bool:
	for i in range((model.units as Array).size()):
		var u: Dictionary = model.units[i]
		if int(u.x) == cell.x and int(u.y) == cell.y:
			model.units.remove_at(i)
			_canvas._refresh_cell(cell)
			_status("移除 %s @(%d,%d)" % [u.name, cell.x, cell.y])
			return true
	return false


## 种子生成（保留 id/name/hosting，替换地形并清空单位）
func apply_generate(seed: String, w: int, h: int) -> void:
	_push_undo("生成")
	var meta := {
		"id": _id_edit.text if _id_edit != null else String(model.id),
		"name": _name_edit.text if _name_edit != null else String(model.name),
		"hosting": _hosting_check.button_pressed if _hosting_check != null else false,
	}
	model = BattlefieldDocScript.generate(seed, w, h)
	model.merge(meta, true)  # overwrite=true：generate 的空 id/name 需被当前输入覆盖
	_canvas.selected_cell = Vector2i(-1, -1)
	_syncing_boxes = true
	_width_box.value = w
	_height_box.value = h
	_syncing_boxes = false
	_refresh_canvas()
	_status("已生成 %d×%d · 种子「%s」（单位已清空）" % [w, h, seed])
	print("[editor] 生成地形 seed=%s size=%dx%d" % [seed, w, h])  # L1 埋点


func _generate() -> void:
	apply_generate(_seed_edit.text, int(_width_box.value), int(_height_box.value))


func _on_resize() -> void:
	if _canvas == null or _syncing_boxes:
		return
	var w := int(_width_box.value)
	var h := int(_height_box.value)
	if w == model.width and h == model.height:
		return
	_push_undo("调整尺寸")
	model = BattlefieldDocScript.resize(model, w, h)
	_refresh_canvas()


func _refresh_canvas() -> void:
	if _canvas == null:
		return
	_canvas.model = model
	_canvas.queue_redraw()
	_sync_selection_after_model_change()


func _on_tool_changed() -> void:
	var names := { Tool.SELECT: "选择", Tool.PAINT: "画笔", Tool.FILL: "填充", Tool.ERASE: "橡皮", Tool.UNIT: "角色" }
	_status("工具：%s" % names[current_tool])


# ============================================================
# 历史时间线 / 撤销 / 重做（快照式：rows + units + props + block_layout + 尺寸深拷贝）
# _history[0] = 初始地图；按下时登记标签、下一次交互（按键/换页/新
# 动作）时封存完成状态 → 画笔整笔拖动合并为一步。生成/清空/调尺寸/
# 读取各算一步。Ctrl+Z / Ctrl+Y / 历史 Tab 点击跳转共用同一时间线。
# ============================================================

## _ready 末尾调用：把初始空板定格为第 0 条历史
func _init_history() -> void:
	if not _history.is_empty():
		return
	_history.append(_snapshot("初始地图"))
	_history_cursor = 0
	_pending_label = ""
	_refresh_history()


## 动作发生前调用：封存上一动作，登记新动作标签
func _push_undo(label: String = "") -> void:
	_seal_pending()
	_pending_label = label


## 封存 pending 动作的完成状态（快照与当前游标状态相同则丢弃）
func _seal_pending() -> void:
	if _pending_label.is_empty() or _history.is_empty():
		return
	var label := _pending_label
	_pending_label = ""
	var snap := _snapshot(label)
	if _state_equal(snap, _history[_history_cursor]):
		return  # 无效操作不入史（越界 / 不可站人被拒）
	_history.resize(_history_cursor + 1)  # 新编辑截断重做分支
	_history.append(snap)
	_history_cursor += 1
	if _history.size() > UNDO_LIMIT + 1:
		_history.pop_front()
		_history_cursor -= 1
	_refresh_history()


func _undo() -> void:
	_seal_pending()
	if _history.is_empty() or _history_cursor == 0:
		_status("没有可撤销的操作")
		return
	var undone: String = _history[_history_cursor]["label"]
	_history_cursor -= 1
	_restore(_history[_history_cursor])
	_status("撤销：%s（还可撤 %d 步）" % [undone, _history_cursor])
	_refresh_history()


func _redo() -> void:
	_seal_pending()
	if _history.is_empty() or _history_cursor >= _history.size() - 1:
		_status("没有可重做的操作")
		return
	_history_cursor += 1
	_restore(_history[_history_cursor])
	_status("重做：%s（还可重做 %d 步）" % [_history[_history_cursor]["label"],
		_history.size() - 1 - _history_cursor])
	_refresh_history()


## 历史 Tab 点击跳转：一次多步撤销/重做；越界或点击当前条仅刷新列表
func _jump_history(idx: int) -> void:
	_seal_pending()
	if idx < 0 or idx >= _history.size() or idx == _history_cursor:
		_refresh_history()
		return
	var forward := idx > _history_cursor
	_history_cursor = idx
	_restore(_history[idx])
	_status("%s：%s（第 %d/%d 步）" % ["重做" if forward else "撤销",
		_history[idx]["label"], idx, _history.size() - 1])
	_refresh_history()


## 重建历史列表（▶ 当前条 ACCENT；游标之后=可重做，置灰）
func _refresh_history() -> void:
	if _history_list == null:
		return
	_syncing_history = true
	_history_list.clear()
	for k in range(_history.size()):
		_history_list.add_item("▶ %d. %s" % [k, _history[k]["label"]] if k == _history_cursor
			else "%d. %s" % [k, _history[k]["label"]])
		if k == _history_cursor:
			_history_list.set_item_custom_fg_color(k, ACCENT)
		elif k > _history_cursor:
			_history_list.set_item_custom_fg_color(k, TEXT_DIM)
	_history_list.select(_history_cursor)
	_syncing_history = false


func _snapshot(label: String = "") -> Dictionary:
	var units := []
	for u in model.units:
		units.append((u as Dictionary).duplicate())
	var props := []
	for p in model.get("props", []):
		props.append((p as Dictionary).duplicate())
	return {
		"rows": (model.rows as Array).duplicate(),
		"units": units,
		"props": props,
		"block_layout": (model.get("block_layout", {}) as Dictionary).duplicate(true),
		"width": int(model.width),
		"height": int(model.height),
		"label": label,
	}


func _state_equal(snap: Dictionary, other: Dictionary) -> bool:
	return snap.rows == other.rows and snap.units == other.units \
		and snap.get("props", []) == other.get("props", []) \
		and snap.get("block_layout", {}) == other.get("block_layout", {})


## 恢复快照（rows/units/props/尺寸从快照再深拷贝，栈内条目保持原样可重复恢复）
func _restore(snap: Dictionary) -> void:
	model.rows = (snap.rows as Array).duplicate()
	var units := []
	for u in snap.units:
		units.append((u as Dictionary).duplicate())
	model.units = units
	var props := []
	for p in snap.get("props", []):
		props.append((p as Dictionary).duplicate())
	model.props = props
	model["block_layout"] = (snap.get("block_layout", {}) as Dictionary).duplicate(true)
	model.width = int(snap.width)
	model.height = int(snap.height)
	_syncing_boxes = true
	if _width_box != null:
		_width_box.value = int(model.width)
	if _height_box != null:
		_height_box.value = int(model.height)
	_syncing_boxes = false
	_refresh_canvas()


# ============================================================
# 读取 / 保存 / 返回
# ============================================================

func _refresh_load_box() -> void:
	if _load_box == null:
		return
	_load_box.clear()
	for entry in BattlefieldLoaderScript.list_battlefields():
		if String(entry.get("error", "")) != "":
			continue
		_load_box.add_item("%s · %s" % [entry.get("name", ""), entry.get("file", "")])
		_load_box.set_item_metadata(_load_box.item_count - 1, entry.get("path", ""))


func _load_selected() -> void:
	if _load_box.selected < 0:
		_status("先在下拉框选择要读取的战场", true)
		return
	load_path(String(_load_box.get_item_metadata(_load_box.selected)))


## 从战场 JSON 读入编辑器（rows / map 两种写法都支持）
func load_path(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_status("无法打开 %s" % path, true)
		return { "ok": false, "error": "无法打开文件" }
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		_status("JSON 解析失败：%s" % path, true)
		return { "ok": false, "error": "JSON 解析失败" }
	var candidate := BattlefieldDocScript.from_json_dict(json.data)
	var layout_error := BattlefieldDocScript.validate_block_layout(candidate)
	if not layout_error.is_empty():
		_status("读取失败：%s" % layout_error, true)
		return {"ok": false, "error": layout_error}
	_push_undo("读取")
	model = candidate
	_canvas.selected_cell = Vector2i(-1, -1)
	# 补 tag（画布职业缩写）
	for u in model.units:
		if String(u.get("tag", "")).is_empty():
			u["tag"] = ProfessionDataScript.profession_name(StringName(String(u.get("class", "swordsman")))).substr(0, 1)
	_id_edit.text = String(model.id)
	_name_edit.text = String(model.name)
	_hosting_check.button_pressed = bool(model.hosting)
	_syncing_boxes = true
	_width_box.value = model.width
	_height_box.value = model.height
	_syncing_boxes = false
	_refresh_canvas()
	_status("已读取 %s（%d×%d · 我方%d/敌方%d）" % [
		path.get_file(), model.width, model.height,
		(model.units as Array).filter(func(u): return u.faction != "enemy").size(),
		(model.units as Array).filter(func(u): return u.faction == "enemy").size()])
	print("[editor] 读取战场: %s" % path)  # L1 埋点
	return { "ok": true }


## 保存当前模型（UI 入口；返回 save_model 结果）
func _save() -> void:
	var result := save_current()
	if bool(result.get("ok", false)):
		_status("已保存 -> %s（战场列表立即可用）" % result.get("path", ""))
		_refresh_load_box()
	else:
		_status("保存失败：%s" % result.get("error", ""), true)


func save_current() -> Dictionary:
	model.id = _id_edit.text
	model.name = _name_edit.text if not _name_edit.text.strip_edges().is_empty() else "自定义战场"
	model.hosting = _hosting_check.button_pressed
	var result: Dictionary = BattlefieldDocScript.save_model(model)
	if bool(result.get("ok", false)):
		print("[editor] 保存战场: %s" % result.get("path", ""))  # L1 埋点
	else:
		print("[editor] 保存失败: %s" % result.get("error", ""))  # L1 埋点
	return result


func _back_to_world() -> void:
	# 返回来源场景：Game 入口启动时回到 Game（战场列表）；世界 E 键启动时回到世界
	get_tree().change_scene_to_file(SceneArgs.map_editor_return_to)


func _status(text: String, is_error: bool = false) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", ERR if is_error else TEXT_DIM)
