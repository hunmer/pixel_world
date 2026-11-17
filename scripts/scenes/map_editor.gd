## scenes/map_editor.gd — 战场地图编辑器（JSON 战场调试工具）
##
## 三大能力（用户需求）：
##   1. 更换地图种子：seed 输入 + 生成（骰子随机种子） -> BattlefieldDoc.generate 确定性地形
##   2. 添加地图实体：地形调色板分「地形/植物」两组（数据驱动遍历
##      TERRAIN_GLYPH，W1 扩链后自动含沙地/雪地/草原/碎石地共 11 种；
##      每项单独一个 tile——地形=纯方块柱，植物=独立树贴图，不组合）+
##      画笔/填充/橡皮
##   3. 添加阵营角色：阵营（我方/敌方）+ 8 职业头像网格（48×48，缺图回退职业
##      首字）+ 等级 + 姓名放置，点击已有角色回显编辑，按钮移除
## 布局（右侧垂直页签面板版）：全部 UI 收进右侧固定宽面板（标题 + 垂直页签 +
## 状态栏），左侧画布伸展填充最大化；页签走 PixelTabsVertical（左竖排页签条 +
## 右内容区，引擎 TabContainer 无原生垂直模式），共 8 页 —— 文件/生成/地形/
## 方块/角色/历史/素材/预设，内容超高走 ScrollContainer 纵向滚动；1280×800 与
## 1024×640 自适应。最近吸取为画布底部水平横条（最近在左，最多 8 个方块）。
## 画布生效工具跟随激活 Tab：地形页=画笔刷选中地形（选植物放植物、选素材放素材）、
## 角色页=放置单位，其余 Tab 沿用左上角悬浮工具条的手动单选（_active_tool）。
## 撤销/重做：Ctrl+Z / Ctrl+Y（或 Ctrl+Shift+Z），快照式历史时间线覆盖全部
## 编辑动作；历史 Tab 列出动作时间线，点击任意记录可一步跳转到该状态。
## 图标：at-icons 矢量 SVG（res://addons/at-icons/control/，16×16），加载失败
## 自动回退文字标签。保存为 res://data/battlefields/<id>.json（loader schema，
## 保存即回读校验），战场列表（O 键）立即可见可开战。
## 选择模式（点「选择」/「填充」图标弹出菜单）：单格选择沿用原行为；区域选择=
## 两次独立点击设 pos1/pos2（z 取所在格高度，可在菜单内 SpinBox 精修），画布
## 同步 GLM 虚线边框（同高度=固定平面，异高度=立体选择体：z_min 底面 + z_max
## 顶面 + 四角立边）；区域填充与无区域
## 洪水填充均支持内置地形与已保存素材方块——地形写 rows 并清 override，素材写
## tile_overrides 不动 rows，整个区域一步历史（原子）。
## 区域剪贴板（Ctrl+C/X/V 或弹窗按钮）：复制/剪切当前完整区域，粘贴模式预览
## 跟随悬停格（绿=合法/红=越界），点击提交；区域内按下拖动=移动区域。
## 内核全部走 scripts/editor/region_clipboard.gd 纯函数；每次提交恰好一步历史，
## 越界拒绝且不改模型；生成/读取/调尺寸清空剪贴板并取消预览。
## 移动工具（左侧工具栏 MoveToolToggle，ToolBox 第 8 钮，独立开关）：
## 与 current_tool/_selection_mode 解耦，
## 任意工具下开启后画布拖拽=平移当前选区（选区跟随、全程不重置端点），
## 方向键（上/下/左/右=y-/y+/x-/x+）逐格平移，每键一步历史，越界仅报错；
## 原地松开=纯点击；关闭后回到区域内拖动/两次点击语义。
## UI 样式/控件统一走 scripts/ui（ui_theme.gd 主题 + ui_factory.gd 工厂），
## 按钮一律经 UIFactory 工厂创建（ui/components 像素组件，组件预加载只在工厂内），
## 本文件不再自带样式 helper；领域按钮工厂与悬浮层/弹窗构建在
## scripts/editor/map_editor_overlays.gd 等模块，本门面只保留总装与接线。
##
## 入口：世界内 E 键 / 战场面板「打开编辑器」按钮；返回 -> res://main.tscn。

extends Control

const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const EditorCanvasScript = preload("res://scripts/editor/editor_canvas.gd")
const BattlefieldRendererScript = preload("res://scripts/iso/battlefield_renderer.gd")
const ProfessionDataScript = preload("res://scripts/core/professions.gd")
const ShortcutHintsDialogScript = preload("res://scripts/editor/shortcut_hints_dialog.gd")
const UserAssetServiceScript = preload("res://scripts/assets/user_asset_service.gd")
const UserAssetVisualAdapterScript = preload("res://scripts/assets/user_asset_visual_adapter.gd")
const UserAssetCatalogScript = preload("res://scripts/assets/user_asset_catalog.gd")
const SelectionRangeScript = preload("res://scripts/editor/selection_range.gd")
const BlockSelectorScript = preload("res://scripts/editor/block_selector.gd")
const EditorBlockListScript = preload("res://scripts/editor/editor_block_list.gd")
const EditorBlockPickerDialogScript = preload("res://scripts/editor/editor_block_picker_dialog.gd")
const RegionClipboardScript = preload("res://scripts/editor/region_clipboard.gd")
const RegionPresetStoreScript = preload("res://scripts/editor/region_preset_store.gd")
const MapEditorHistoryScript = preload("res://scripts/editor/map_editor_history.gd")
const MapEditorPaintOpsScript = preload("res://scripts/editor/map_editor_paint_ops.gd")
const MapEditorPanelTabsScript = preload("res://scripts/editor/map_editor_panel_tabs.gd")
const MapEditorBlockPaletteScript = preload("res://scripts/editor/map_editor_block_palette.gd")
const MapEditorOverlaysScript = preload("res://scripts/editor/map_editor_overlays.gd")
const MapEditorFileIoScript = preload("res://scripts/editor/map_editor_file_io.gd")
const MapEditorShortcutsScript = preload("res://scripts/editor/map_editor_shortcuts.gd")
const MapEditorReplaceScript = preload("res://scripts/editor/map_editor_replace.gd")
const MapEditorAssetsScript = preload("res://scripts/editor/map_editor_assets.gd")
const MapEditorCellToolsScript = preload("res://scripts/editor/map_editor_cell_tools.gd")
const MapEditorModelOpsScript = preload("res://scripts/editor/map_editor_model_ops.gd")
const MapEditorUnitsScript = preload("res://scripts/editor/map_editor_units.gd")
const MapEditorRegionSelectScript = preload("res://scripts/editor/map_editor_region_select.gd")
const MapEditorClipboardScript = preload("res://scripts/editor/map_editor_clipboard.gd")
const MapEditorPresetsScript = preload("res://scripts/editor/map_editor_presets.gd")
const MapEditorGenerateScript = preload("res://scripts/editor/map_editor_generate.gd")

const Tool = {
	PAINT = 0, FILL = 1, ERASE = 2, UNIT = 3, PLANT = 4, SELECT = 5,
	HEIGHT_UP = 6, HEIGHT_DOWN = 7, ASSET = 8, REPLACE = 9, PICK = 10,
}
const TAB_BLOCK := 3
## 操作提示只常驻键盘图标；完整 12 条键帽说明在点击后的弹窗内展示。
const HINT_ITEMS := [
	{"key": "左键", "action": "使用工具"},
	{"key": "SPACE+左键 / 右键拖", "action": "平移"},
	{"key": "滚轮 / 双指捏合", "action": "缩放"},
	{"key": "Q E / Z X", "action": "转向 90°"},
	{"key": "R", "action": "视角复位"},
	{"key": "CTRL+Z / Y", "action": "撤销 / 重做"},
	{"key": "CTRL+C / X / V", "action": "复制 / 剪切 / 粘贴区域"},
	{"key": "ALT（按住）", "action": "临时吸管；SHIFT+左键取背景"},
	{"key": "最近吸取", "action": "点击取前景；SHIFT+点击取背景"},
	{"key": "区域内拖动", "action": "移动区域"},
	{"key": "移动工具", "action": "左栏第 8 钮，拖拽/方向键移动选区"},
	{"key": "ESC", "action": "返回世界"},
]

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
## 垂直页签宿主组件（同 ui_component_gallery 直接实例化 PixelTabs 的先例）。
const PixelTabsVerticalScript = preload("res://ui/components/pixel_tabs_vertical.gd")

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
## 右侧面板固定宽度（不随窗口伸展，多出空间全给画布；含垂直页签条 72px）
const SIDEBAR_WIDTH := 360
## 撤销栈上限（快照式：rows+units 深拷贝，画笔整笔拖动合并为一步）
const UNDO_LIMIT := 100
var model: Dictionary = {}
var current_tool: int = Tool.PAINT
## 高度画笔单笔内已处理的格子：避免原地 motion 重复升降，也防止 A→B→A 重复。
var _height_stroke_cells: Dictionary = {}
var current_terrain: StringName = &"mountain"
## PS 风格前景/背景方块：{kind:"terrain"|"asset", id:String, z:int}；只存编辑器状态。
var _block_fg: Dictionary = {"kind": "terrain", "id": "plain", "z": 0}
var _block_bg: Dictionary = {"kind": "terrain", "id": "plain", "z": 0}
var _fg_swatch: Button = null
var _bg_swatch: Button = null
## 最近吸取（画布底部水平横条）：会话内按 (kind,id) 去重，最新在首（横条左侧），
## 最多 8 条；不随生成/读档/改尺寸清空。
var _recent_picks: Array[Dictionary] = []
var _recent_picks_bar: PanelContainer = null
var _recent_pick_list: HBoxContainer = null
## Alt 按住时的临时吸管：仅由 InputEventKey 的 KEY_ALT 按下/松开驱动，不轮询。
var _alt_key_down := false
var _alt_pick_active := false
var _alt_pick_return_tool := -1
## 当前选中的具体植物贴图（非空=地形 Tab 画笔改为放置植物，写模型 props 层）
var current_prop := ""
## 植物素材枚举 { 组名: [res://路径] }（_ready 里扫描，_build_terrain_tab 用）
var _prop_paths: Dictionary = {}
var selected_class: String = "swordsman"
var selected_faction: String = "player"

var _canvas: EditorCanvasScript
var _shortcut_hints_dialog = null
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
var _selected_unit_cell := Vector2i(-1, -1)
var _unit_info_label: Label
var _unit_apply_btn: Button
var _unit_remove_btn: Button
var _faction_buttons: Dictionary = {}
var _load_box: OptionButton
var _block_z_box: SpinBox
var _cell_info_label: Label
var _syncing_block_z := false
## 用户素材库：服务（场景持有非 autoload）+ 共享视觉适配器（画布/预览/面板同库同缓存）
var _asset_service: UserAssetService
var _asset_adapter: UserAssetVisualAdapter
var _asset_panel: AssetLibraryPanel
## 素材页当前选中的素材描述符（asset_selected 写入；选地形/植物调色板时清空，互斥）
var _selected_asset: Dictionary = {}
## 素材方块选中（asset_id，列表在【地形】Tab）；与素材 Tab / 地形调色板选中互斥，非空时画笔=ASSET 放置
var _selected_block_asset := ""
## 建筑预放置朝向（T 键循环 0..3；放置与预览共用，不影响已放置建筑）
var _building_rotation := 0
var _block_asset_buttons: Dictionary = {}  # asset_id -> Button
## 下载完成待刷缩略图的素材集合 + 0.3s 合批定时器（见 _on_block_asset_ready）
var _pending_asset_thumbs: Dictionary = {}
var _asset_thumb_timer: Timer = null
var _block_asset_grid: EditorBlockListScript = null
var _block_asset_empty: Label = null
## 地形 Tab 地形/植物调色板单选组（选方块素材时清按下态互斥用）
var _terrain_group: ButtonGroup = null
var _tool_buttons: Dictionary = {}   # Tool -> Button
var _terrain_buttons: Dictionary = {}  # StringName(terrain) -> Button
var _class_buttons: Dictionary = {}  # String(class_id) -> Button
## 程序化同步 SpinBox 时挂起 _on_resize（避免读到另一半的旧值触发错误 resize）
var _syncing_boxes := false
## 选择模式菜单（点「选择」/「填充」图标弹出）：&"single" 单格 / &"region" 区域
var _selection_mode := &"single"
## GLM 区域选择组件：双端点（x/y 格 + z 高度层）；changed → 画布虚线框 + 坐标回显
var _selection_range := SelectionRangeScript.new()
## 区域模式第二次点击已置 pos2（第三次点击重新从 pos1 开始）
var _region_pos2_set := false
var _selection_popup: PanelContainer = null
var _mode_option: OptionButton = null
## 条件替换弹窗：源/目标均为 terrain:<glyph> / asset:<id>；点格只选源，不改模型。
var _replace_popup: PanelContainer = null
var _replace_source_opt: Button = null
var _replace_dest_opt: Button = null
var _replace_scope_label: Label = null
var _replace_apply_btn: Button = null
var _replace_hint: Label = null
var _replace_items: Array[Dictionary] = []
var _replace_picker_dialog: EditorBlockPickerDialogScript = null
var _replace_picker_target := "source"
## pos1/pos2 坐标编辑：{ &"x"/&"y"/&"z": SpinBox }（名称 Pos1X 等，UI 契约用）
var _pos1_boxes: Dictionary = {}
var _pos2_boxes: Dictionary = {}
## 通用方块选择器（弹窗内）：区域填充/洪水填充用内置地形还是已保存素材方块
var _fill_selector: BlockSelectorScript = null
## 程序化回写 SpinBox 时挂起 _on_region_box_changed（防回环）
var _syncing_region_boxes := false
## 区域剪贴板（region_clipboard.gd payload）：复制/剪切写入，粘贴/移动消费；
## 生成/读取/调尺寸清空（跨模型粘贴语义不成立）
var _clipboard: Dictionary = {}
## 粘贴模式：预览框跟随悬停格，下一次画布点击=提交粘贴
var _paste_mode := false
## 粘贴落点（payload 左上角 = 悬停格；提交时转正）
var _paste_origin := Vector2i(-1, -1)
## 区域内按下待移动（SELECT+区域模式+完整区域，按下格在区域内；
## 或移动工具开启，任意格按下）
var _move_armed := false
var _move_grab := Vector2i(-1, -1)
var _move_preview := Vector2i(-1, -1)
## 移动工具（左侧工具栏开关）：开启后画布拖拽=平移当前选区（选区跟随平移）
var _move_tool_active := false
var _move_tool_toggle: BaseButton = null
## 区域预设（预设 Tab）：命名保存选区 payload，可填入选区/放置模式连续落子
var _preset_store: RefCounted = null  # RegionPresetStoreScript（preload，避免 class_name 缓存依赖）
var _preset_name_edit: LineEdit = null
var _preset_list: ItemList = null
var _place_preset_btn: BaseButton = null
var _place_preview_toggle: CheckButton = null
## 实时放置预览总开关：只影响预览标记，不影响点击提交与撤销
var _place_preview_enabled := true
var _place_mode := false
var _place_preset_id := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	model = BattlefieldDocScript.create_empty()
	_selection_range.changed.connect(_on_selection_range_changed)
	_prop_paths = MapEditorPanelTabsScript.scan_prop_paths()  # 植物素材枚举（_build_terrain_tab 用）
	_init_asset_service()  # 素材服务必须先于 UI（画布/面板注入共享 adapter）
	_preset_store = RegionPresetStoreScript.new()  # 预设存储先于 UI（列表初始刷新）
	_build_ui()
	_init_history()  # 初始空板定格为历史第 0 条「初始地图」


## 素材服务（场景持有，非 autoload）：管理 user://custom_assets 素材库
func _init_asset_service() -> void:
	_asset_service = UserAssetServiceScript.new()
	_asset_service.name = "UserAssetService"
	add_child(_asset_service)
	_asset_adapter = UserAssetVisualAdapterScript.new()
	# 下载完成 → 方块页「素材方块」网格补入新下载的方块（只重建该网格，不动画布）
	_asset_service.asset_ready.connect(_on_block_asset_ready)


func _unhandled_input(event: InputEvent) -> void:
	MapEditorShortcutsScript.unhandled_input(self, event)


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
	_canvas.cell_released.connect(_on_cell_released)
	_canvas.hover_changed.connect(_on_hover_changed)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 3D 取景让出右侧栏宽度（同世界 reserved_right_px），画布内容对齐舞台中心
	_canvas.sidebar_reserved_px = SIDEBAR_WIDTH
	_canvas.asset_adapter = _asset_adapter  # 画布与素材面板共享同一库缓存
	holder.add_child(_canvas)

	# ---- 左上角垂直工具条（悬浮在画布上，取代旧「工具」Tab） ----
	holder.add_child(_build_tool_bar())
	holder.add_child(_build_cell_info())
	# ---- 右下角只留键盘图标；完整提示由 CanvasHolder 内遮罩弹窗展示 ----
	holder.add_child(_build_hint_bar())
	_shortcut_hints_dialog = ShortcutHintsDialogScript.new()
	holder.add_child(_shortcut_hints_dialog)
	# ---- 画布底部最近吸取横条（限制在 CanvasHolder 内，不占 SidePanel 宽度） ----
	_build_recent_picks_bar(holder)

	# ---- 右侧面板：标题 / 垂直页签 / 状态栏（固定宽，不吃画布空间） ----
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

	# ---- 8 个 Tab：文件 / 生成 / 地形 / 方块 / 角色 / 历史 / 素材 / 预设 ----
	# 垂直页签：PixelTabsVertical = 左侧竖排页签条 + 右侧内容区；内部 TabContainer
	# 改名 ToolTabs（tabs_visible=false），add_tab 页结构与 tab_changed/current_tab
	# 等契约不变（map_editor_cell_tools 等按 TabContainer API 使用 _tabs）。
	var tabs_host := PixelTabsVerticalScript.new()
	tabs_host.name = "ToolTabsHost"
	tabs_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(tabs_host)
	var tabs: TabContainer = tabs_host.tabs
	tabs.name = "ToolTabs"
	_tabs = tabs
	tabs.tab_changed.connect(_on_tab_changed)
	_build_file_tab(tabs)
	_build_generate_tab(tabs)
	_build_terrain_tab(tabs)
	_build_block_tab(tabs)
	_build_units_tab(tabs)
	_build_history_tab(tabs)
	_build_asset_tab(tabs)
	_build_preset_tab(tabs)  # 预设页追加在最后：TAB_BLOCK=3 等既有索引不变

	# ---- 选择模式菜单（点「选择」/「填充」图标弹出的悬浮窗，默认隐藏） ----
	_build_selection_popup()
	# ---- 条件替换菜单（替换工具激活时显示，位于工具条右侧，不进入侧栏） ----
	_build_replace_popup()

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
	_hosting_check = UIFactoryScript.check_button(
		"托管", "开启后战斗自动托管运行（AI 对 AI），调试观察用"
	)
	_load_box = UIFactoryScript.option_button()
	MapEditorPanelTabsScript.build_file_tab(self, tab)


## Tab【生成】：种子 / 随机种子 / 宽高 / 生成 / 清空地形
func _build_generate_tab(tabs: TabContainer) -> void:
	var tab := UIFactoryScript.add_tab(tabs, "生成", "dice")
	MapEditorPanelTabsScript.build_generate_tab(self, tab)


## 左上角悬浮工具条：选择 / 画笔 / 填充 / 橡皮 / 高度升降 / 角色（覆盖在画布上）
func _build_tool_bar() -> Control:
	return MapEditorOverlaysScript.build_tool_bar(self)


## 条件替换弹窗：双下拉编码 terrain:<glyph> / asset:<id>；只有执行按钮写模型。
func _build_replace_popup() -> void:
	_replace_source_opt = UIFactoryScript.button("选择被替换方块", _open_replace_picker.bind("source"))
	_replace_dest_opt = UIFactoryScript.button("选择替换目标", _open_replace_picker.bind("dest"))
	_replace_apply_btn = UIFactoryScript.button("执行替换", _apply_replace, "replace")
	MapEditorOverlaysScript.build_replace_popup(self)


## 画布右侧最近吸取栏：独立于右侧 SidePanel，最多 8 个 34px 窄条按钮，超出后滚动。
func _build_recent_picks_bar(holder: Control) -> void:
	MapEditorOverlaysScript.build_recent_picks_bar(self, holder)


func _replace_source_code() -> String:
	return MapEditorReplaceScript.replace_source_code(self)


func _replace_dest_code() -> String:
	return MapEditorReplaceScript.replace_dest_code(self)


func _replace_code_for_block(block: Dictionary) -> String:
	return MapEditorReplaceScript.replace_code_for_block(self, block)


func _select_replace_option(opt: Button, code: String) -> bool:
	return MapEditorReplaceScript.select_replace_option(self, opt, code)


func _open_replace_picker(target: String) -> void:
	MapEditorReplaceScript.open_replace_picker(self, target)


func _on_replace_picker_chosen(kind: String, id: String) -> void:
	MapEditorReplaceScript.on_replace_picker_chosen(self, kind, id)


func _reset_replace_popup() -> void:
	MapEditorReplaceScript.reset_replace_popup(self)


func _set_replace_source_from_cell(cell: Vector2i) -> void:
	MapEditorReplaceScript.set_replace_source_from_cell(self, cell)


func _refresh_replace_scope() -> void:
	MapEditorReplaceScript.refresh_replace_scope(self)


func _build_cell_info() -> Control:
	return MapEditorOverlaysScript.build_cell_info(self)


func _build_hint_bar() -> Control:
	return MapEditorOverlaysScript.build_hint_bar(self)


## Tab【地形】：地形 / 植物 分组调色板。
## 地形组：11 种地形各一个**单块** tile（不叠高塔、不插树）。
## 植物组：枚举 trees/plants/decorations 全部素材（树木/植物/装饰三小节），
## 每张贴图一个独立 tile，选中后画笔在格子上放置该具体植物（模型 props 层）。
## 全部按钮共用一个 ButtonGroup（选地形清空 current_prop，选植物反之）。
func _build_terrain_tab(tabs: TabContainer) -> void:
	var tab := UIFactoryScript.add_tab(tabs, "地形", "sprout")
	MapEditorPanelTabsScript.build_terrain_tab(self, tab)


## Tab【方块】：编辑当前选格的独立高度（不修改同列/其他格）；
## 下方「素材方块」列表展示已下载的素材方块，点选后画笔放置（tile_overrides 层），再点取消。
func _build_block_tab(tabs: TabContainer) -> void:
	var tab := UIFactoryScript.add_tab(tabs, "方块", "cube")
	MapEditorPanelTabsScript.build_block_tab(self, tab)


## 写入前景/背景槽；地形前景同步旧 current_terrain，保持既有调色板与测试入口兼容。
func _set_block_slot(which: String, block: Dictionary) -> void:
	var normalized := {
		"kind": String(block.get("kind", "terrain")),
		"id": String(block.get("id", "plain")),
		"z": int(block.get("z", 0)),
	}
	if which == "bg":
		_block_bg = normalized
	else:
		_block_fg = normalized
		if String(normalized.kind) == "terrain":
			current_terrain = StringName(normalized.id)
	_refresh_block_slot_ui()


func _block_label(block: Dictionary) -> String:
	return MapEditorBlockPaletteScript.label(block)


func _refresh_block_slot_ui() -> void:
	MapEditorBlockPaletteScript.refresh_slot_ui(self)


## 只读快照供契约/调试使用；外部修改返回值不会污染会话内最近吸取列表。
func _recent_picks_info() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for block in _recent_picks:
		out.append(block.duplicate(true))
	return out


## 仅吸管成功时调用：按 (kind,id) 去重并置顶，z 取最近一次，最多保留 8 条。
func _remember_recent_pick(block: Dictionary) -> void:
	MapEditorBlockPaletteScript.remember_pick(self, block)


## 最近吸取使用与真实地图一致的地形顶面/素材视觉贴图；加载失败才回退短标签。
func _recent_pick_texture(block: Dictionary) -> Texture2D:
	return MapEditorBlockPaletteScript.texture(self, block)


func _refresh_recent_picks() -> void:
	MapEditorBlockPaletteScript.refresh_recent_picks(self)


## 点击取为前景，Shift+点击取为背景；取用本身不改变最近列表顺序。
func _on_recent_pick_pressed(index: int, shift_pressed: bool = false) -> void:
	if index < 0 or index >= _recent_picks.size():
		return
	var block := _recent_picks[index].duplicate(true)
	var to_background := shift_pressed or Input.is_key_pressed(KEY_SHIFT)
	_set_block_slot("bg" if to_background else "fg", block)
	_status("已取用最近吸取：%s（%s）" % [_block_label(block), "背景" if to_background else "前景"])
	print("[editor] 最近吸取取用 index=%d slot=%s kind=%s id=%s z=%d"
		% [index, "bg" if to_background else "fg", String(block.kind), String(block.id), int(block.z)])  # L1 埋点


func _apply_paint_block(cell: Vector2i) -> void:
	MapEditorModelOpsScript.apply_paint_block(self, cell)


func _pick_block(cell: Vector2i, to_background: bool = false) -> void:
	MapEditorModelOpsScript.pick_block(self, cell, to_background)


## Tab【角色】：阵营 + 8 职业头像网格 + 等级/姓名
func _build_units_tab(tabs: TabContainer) -> void:
	var tab := UIFactoryScript.add_tab(tabs, "角色", "person")
	MapEditorPanelTabsScript.build_units_tab(self, tab)


## Tab【历史】：动作时间线（点击任意记录跳转到该状态）
func _build_history_tab(tabs: TabContainer) -> void:
	var tab := UIFactoryScript.add_tab(tabs, "历史", "clock")
	MapEditorPanelTabsScript.build_history_tab(self, tab)


## Tab【素材】：用户素材库管理（本地导入/远程清单/编辑 render/隐藏），
## 选中素材后回「地形」页用画笔放置（地块→tile_overrides 层，植物→props 层）。
func _build_asset_tab(tabs: TabContainer) -> void:
	var tab := UIFactoryScript.add_tab(tabs, "素材", "library")
	MapEditorPanelTabsScript.build_asset_tab(self, tab)


func _build_preset_tab(tabs: TabContainer) -> void:
	var tab := UIFactoryScript.add_tab(tabs, "预设", "bookmark")
	var preview_toggle := UIFactoryScript.check_button()  # 直建控件整改：改走组件工厂
	MapEditorPanelTabsScript.build_preset_tab(self, tab, preview_toggle)


func _on_asset_selected(descriptor: Dictionary) -> void:
	MapEditorAssetsScript.on_asset_selected(self, descriptor)


func _rebuild_block_asset_grid() -> void:
	MapEditorAssetsScript.rebuild_block_asset_grid(self)


func _on_block_asset_btn_pressed(asset_id: String) -> void:
	MapEditorAssetsScript.on_block_asset_btn_pressed(self, asset_id)


func _clear_block_asset_selection() -> void:
	MapEditorAssetsScript.clear_block_asset_selection(self)


func _active_asset() -> Dictionary:
	return MapEditorAssetsScript.active_asset(self)


func _on_block_asset_ready(asset_id: String) -> void:
	MapEditorAssetsScript.on_block_asset_ready(self, asset_id)


func _clear_asset_selection() -> void:
	MapEditorAssetsScript.clear_asset_selection(self)


func _on_asset_library_changed() -> void:
	MapEditorAssetsScript.on_asset_library_changed(self)


## 建筑门面：朝向循环（T）/ 整栋删除（橡皮与删除路径共用）/ 预览驱动（悬停、选中变化）
func _rotate_building_intent() -> void:
	MapEditorModelOpsScript.rotate_building_intent(self)


func _remove_building_at(cell: Vector2i) -> bool:
	return MapEditorModelOpsScript.remove_building_at(self, cell)


func _update_building_preview(cell: Vector2i) -> void:
	MapEditorCellToolsScript.update_building_preview(self, cell)


func _clear_building_preview() -> void:
	MapEditorCellToolsScript.clear_building_preview(self)


func _on_tab_changed(_idx: int) -> void:
	MapEditorCellToolsScript.on_tab_changed(self, _idx)
# ============================================================
# UI 构建辅助（统一样式系统 + 控件工厂）
# ============================================================
## 统一按钮组件入口：原 PixelButtonScript.new() 直建已收敛至 UIFactory.button
## （styled=false：不叠加 style_button 逐控件 override，保持组件自身主题与
## 编辑器 tile/工具条原观感）。
## 编辑器内按钮音效由全局 Sfx autoload（game_sfx.gd）对 BaseButton 统一挂接，
## 组件自带 HoverSfx/ClickSfx 会叠加双声，故一律关闭、只留全局钩子（工厂已禁）。
func _pixel_btn() -> Button:
	return UIFactoryScript.button("", Callable(), "", false)


# ============================================================
# 编辑操作（canvas 信号 + 可测方法；生效工具由激活 Tab 决定）
# ============================================================

func _active_tool() -> int:
	return MapEditorCellToolsScript.active_tool(self)


func _on_cell_pressed(cell: Vector2i, alt_pressed: bool = false, shift_pressed: bool = false) -> void:
	MapEditorCellToolsScript.on_cell_pressed(self, cell, alt_pressed, shift_pressed)


func _on_cell_dragged(cell: Vector2i) -> void:
	MapEditorCellToolsScript.on_cell_dragged(self, cell)


func _on_cell_released(cell: Vector2i) -> void:
	MapEditorCellToolsScript.on_cell_released(self, cell)


func _commit_region_move(bounds: Array, delta: Vector2i, translate_selection: bool) -> void:
	MapEditorClipboardScript.commit_region_move(self, bounds, delta, translate_selection)


func _nudge_region(delta: Vector2i) -> void:
	MapEditorClipboardScript.nudge_region(self, delta)


func _update_move_preview(hover: Vector2i) -> void:
	MapEditorClipboardScript.update_move_preview(self, hover)


func _apply_tool(cell: Vector2i) -> void:
	MapEditorCellToolsScript.apply_tool(self, cell)




func _select_cell(cell: Vector2i, activate_block: bool = true) -> void:
	MapEditorCellToolsScript.select_cell(self, cell, activate_block)


func _on_hover_changed(cell: Vector2i) -> void:
	MapEditorCellToolsScript.on_hover_changed(self, cell)


func _on_block_z_changed(value: float) -> void:
	MapEditorCellToolsScript.on_block_z_changed(self, value)


func _sync_selection_after_model_change(clear_selection: bool = false) -> void:
	MapEditorCellToolsScript.sync_selection_after_model_change(self, clear_selection)


func _set_prop(cell: Vector2i, path: String) -> void:
	MapEditorModelOpsScript.set_prop(self, cell, path)


func _set_tile_override(cell: Vector2i, asset_id: String) -> void:
	MapEditorModelOpsScript.set_tile_override(self, cell, asset_id)


func _set_prop_asset(cell: Vector2i, asset_id: String) -> void:
	MapEditorModelOpsScript.set_prop_asset(self, cell, asset_id)


func _apply_asset_tool(cell: Vector2i) -> void:
	MapEditorModelOpsScript.apply_asset_tool(self, cell)


func _set_glyph(cell: Vector2i, glyph: String) -> void:
	MapEditorModelOpsScript.set_glyph(self, cell, glyph)


## 洪水填充：同图例连通区域 -> 目标地形（内核在 MapEditorModelOpsScript.fill_cell）
func fill_cell(cell: Vector2i, terrain: StringName) -> void:
	MapEditorModelOpsScript.fill_cell(self, cell, terrain)


# ============================================================
# 选择模式菜单与区域填充（GLM：EditorSelectionRange / BlockSelector / 画布虚线框）
# ============================================================

## 选择模式弹窗（点「选择」/「填充」图标打开，Esc 关闭）：模式切换 + pos1/pos2
## 坐标编辑 + 通用方块选择器 + 区域填充/清除按钮。默认隐藏。
func _build_selection_popup() -> void:
	_mode_option = UIFactoryScript.option_button()  # 直建控件整改：改走组件工厂
	MapEditorOverlaysScript.build_selection_popup(self, _mode_option)


func _open_selection_popup() -> void:
	MapEditorRegionSelectScript.open_selection_popup(self)


func _close_selection_popup() -> void:
	MapEditorRegionSelectScript.close_selection_popup(self)


## 弹窗右上角关闭按钮统一入口：按下画笔工具，借 _on_tool_changed 的
## 收起逻辑统一关闭选择/替换弹窗。弹窗开启时 current_tool 必为
## SELECT/FILL/REPLACE，与 PAINT 不重合，button_pressed 赋值必有信号。
func _dismiss_tool_popups() -> void:
	_tool_buttons[Tool.PAINT].button_pressed = true


func _on_selection_mode_item(idx: int) -> void:
	MapEditorRegionSelectScript.on_selection_mode_item(self, idx)


func _apply_region_click(cell: Vector2i) -> void:
	MapEditorRegionSelectScript.apply_region_click(self, cell)


func _on_selection_range_changed() -> void:
	MapEditorRegionSelectScript.on_selection_range_changed(self)


func _sync_region_marker() -> void:
	MapEditorRegionSelectScript.sync_region_marker(self)


func _on_region_box_changed(value: float, which: String, axis: StringName) -> void:
	MapEditorRegionSelectScript.on_region_box_changed(self, value, which, axis)


func _apply_fill(cell: Vector2i) -> void:
	MapEditorModelOpsScript.apply_fill(self, cell)


func _apply_replace() -> void:
	MapEditorReplaceScript.apply_replace(self)


func _fill_region() -> void:
	MapEditorModelOpsScript.fill_region(self)


func _on_region_fill_pressed() -> void:
	MapEditorRegionSelectScript.on_region_fill_pressed(self)


func _on_region_clear_pressed() -> void:
	MapEditorRegionSelectScript.on_region_clear_pressed(self)


# ============================================================
# 区域剪贴板：复制 / 剪切 / 粘贴 / 区域内拖动移动
# （内核全部走 region_clipboard.gd 纯函数；本文件只做门禁、历史与状态栏）
# ============================================================

func _region_2d_bounds() -> Array:
	return MapEditorRegionSelectScript.region_2d_bounds(self)


func _move_tool_bounds() -> Array:
	return MapEditorRegionSelectScript.move_tool_bounds(self)


func _on_region_copy_pressed() -> void:
	MapEditorClipboardScript.on_region_copy_pressed(self)


func _on_region_cut_pressed() -> void:
	MapEditorClipboardScript.on_region_cut_pressed(self)


func _on_region_paste_pressed() -> void:
	MapEditorClipboardScript.on_region_paste_pressed(self)


func _update_paste_preview(hover: Vector2i) -> void:
	MapEditorClipboardScript.update_paste_preview(self, hover)


func _commit_paste(origin: Vector2i) -> void:
	MapEditorClipboardScript.commit_paste(self, origin)


func _cancel_paste() -> void:
	MapEditorClipboardScript.cancel_paste(self)


func _on_move_tool_toggled(pressed: bool) -> void:
	MapEditorClipboardScript.on_move_tool_toggled(self, pressed)


func _set_move_tool(active: bool) -> void:
	MapEditorClipboardScript.set_move_tool(self, active)


# ============================================================
# 区域预设（预设 Tab）：保存=选区→payload→store（不动模型不入历史）；
# 填入选区=以选区左上角为原点按预设尺寸一步历史回写；放置模式=点击画布
# 以该格为左上角连续放置，每次一步历史；与粘贴模式互斥，ESC/切工具/
# 生成/读取/调尺寸均退出并清预览。
# ============================================================

func _refresh_preset_list(select_id := "") -> void:
	MapEditorPresetsScript.refresh_preset_list(self, select_id)


func _on_save_preset_pressed() -> void:
	MapEditorPresetsScript.on_save_preset_pressed(self)


func _on_fill_preset_pressed() -> void:
	MapEditorPresetsScript.on_fill_preset_pressed(self)


func _on_place_preset_toggled(on: bool) -> void:
	MapEditorPresetsScript.on_place_preset_toggled(self, on)


func _on_place_preview_toggled(on: bool) -> void:
	MapEditorPresetsScript.on_place_preview_toggled(self, on)


func _update_place_preview(hover: Vector2i) -> void:
	MapEditorPresetsScript.update_place_preview(self, hover)


func _commit_place_preset(cell: Vector2i) -> void:
	MapEditorPresetsScript.commit_place_preset(self, cell)


func _cancel_place_mode() -> void:
	MapEditorPresetsScript.cancel_place_mode(self)


func _on_rename_preset_pressed() -> void:
	MapEditorPresetsScript.on_rename_preset_pressed(self)


func _on_delete_preset_pressed() -> void:
	MapEditorPresetsScript.on_delete_preset_pressed(self)


func _on_refresh_preset_pressed() -> void:
	MapEditorPresetsScript.on_refresh_preset_pressed(self)


func region_clipboard_info() -> Dictionary:
	return MapEditorClipboardScript.region_clipboard_info(self)


func place_unit(cell: Vector2i, faction: String, class_id: String, level: int, uname: String = "") -> bool:
	return MapEditorModelOpsScript.place_unit(self, cell, faction, class_id, level, uname)


func _remove_unit_at(cell: Vector2i) -> bool:
	return MapEditorModelOpsScript.remove_unit_at(self, cell)


func apply_generate(seed: String, w: int, h: int) -> void:
	MapEditorGenerateScript.apply_generate(self, seed, w, h)


func _generate() -> void:
	MapEditorGenerateScript.generate(self)


func _on_resize() -> void:
	MapEditorGenerateScript.on_resize(self)


func _refresh_canvas() -> void:
	MapEditorGenerateScript.refresh_canvas(self)


func _on_tool_changed() -> void:
	MapEditorGenerateScript.on_tool_changed(self)


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
	if MapEditorHistoryScript.seal(self):
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
	return MapEditorHistoryScript.snapshot(model, label)


## 恢复快照（深拷贝内核在 MapEditorHistoryScript.restore_into；此处补尺寸框回显与画布刷新）
func _restore(snap: Dictionary) -> void:
	var size := MapEditorHistoryScript.restore_into(model, snap)
	_syncing_boxes = true
	if _width_box != null:
		_width_box.value = size.x
	if _height_box != null:
		_height_box.value = size.y
	_syncing_boxes = false
	_refresh_canvas()


# ============================================================
# 读取 / 保存 / 返回
# ============================================================

func _refresh_load_box() -> void:
	MapEditorFileIoScript.refresh_load_box(self)


func _load_selected() -> void:
	if _load_box.selected < 0:
		_status("先在下拉框选择要读取的战场", true)
		return
	load_path(String(_load_box.get_item_metadata(_load_box.selected)))


## 从战场 JSON 读入编辑器（rows / map 两种写法都支持）
func load_path(path: String) -> Dictionary:
	return MapEditorFileIoScript.apply_load(self, path)


## 保存当前模型（UI 入口；返回 save_model 结果）
func _save() -> void:
	var result := save_current()
	if bool(result.get("ok", false)):
		_status("已保存 -> %s（战场列表立即可用）" % result.get("path", ""))
		_refresh_load_box()
	else:
		_status("保存失败：%s" % result.get("error", ""), true)


func save_current() -> Dictionary:
	return MapEditorFileIoScript.apply_save(self)


func _back_to_world() -> void:
	# 返回来源场景：Game 入口启动时回到 Game（战场列表）；世界 E 键启动时回到世界
	get_tree().change_scene_to_file(SceneArgs.map_editor_return_to)


func _status(text: String, is_error: bool = false) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", ERR if is_error else TEXT_DIM)
