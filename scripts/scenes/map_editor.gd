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
## 状态栏），左侧画布伸展填充最大化；Tab 共 7 页 —— 文件/生成/地形/方块/角色/
## 历史/素材，内容超高走 ScrollContainer 纵向滚动；1280×800 与 1024×640 自适应。
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
## 按钮一律由 ui/components 像素组件创建（UIFactory / PixelButton 预加载），
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

const Tool = {
	PAINT = 0, FILL = 1, ERASE = 2, UNIT = 3, PLANT = 4, SELECT = 5,
	HEIGHT_UP = 6, HEIGHT_DOWN = 7, ASSET = 8, REPLACE = 9, PICK = 10,
}
const TAB_BLOCK := 3
## 操作提示只常驻键盘图标；完整 13 条键帽说明在点击后的弹窗内展示。
const HINT_ITEMS := [
	{"key": "左键", "action": "使用工具"},
	{"key": "SPACE+左键 / 右键拖", "action": "平移"},
	{"key": "滚轮 / 双指捏合", "action": "缩放"},
	{"key": "Q E / Z X", "action": "转向 90°"},
	{"key": "R", "action": "视角复位"},
	{"key": "CTRL+Z / Y", "action": "撤销 / 重做"},
	{"key": "CTRL+C / X / V", "action": "复制 / 剪切 / 粘贴区域"},
	{"key": "SHIFT+X", "action": "交换前景 / 背景方块"},
	{"key": "ALT（按住）", "action": "临时吸管；SHIFT+左键取背景"},
	{"key": "最近吸取", "action": "点击取前景；SHIFT+点击取背景"},
	{"key": "区域内拖动", "action": "移动区域"},
	{"key": "移动工具", "action": "左栏第 8 钮，拖拽/方向键移动选区"},
	{"key": "ESC", "action": "返回世界"},
]

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
## 统一按钮组件（ui/components）：tile/工具条等领域 toggle 按钮直接创建用。
const PixelButtonScript = preload("res://ui/components/pixel_button.gd")

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
## 高度画笔单笔内已处理的格子：避免原地 motion 重复升降，也防止 A→B→A 重复。
var _height_stroke_cells: Dictionary = {}
var current_terrain: StringName = &"mountain"
## PS 风格前景/背景方块：{kind:"terrain"|"asset", id:String, z:int}；只存编辑器状态。
var _block_fg: Dictionary = {"kind": "terrain", "id": "plain", "z": 0}
var _block_bg: Dictionary = {"kind": "terrain", "id": "plain", "z": 0}
var _fg_swatch: Button = null
var _bg_swatch: Button = null
## 最近吸取：会话内按 (kind,id) 去重，最新在首，最多 8 条；不随生成/读档/改尺寸清空。
var _recent_picks: Array[Dictionary] = []
var _recent_picks_bar: PanelContainer = null
var _recent_pick_list: VBoxContainer = null
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
## 方块页「素材方块」选中（asset_id）；与素材 Tab 选中互斥，非空时方块页画笔=ASSET 放置
var _selected_block_asset := ""
var _block_asset_buttons: Dictionary = {}  # asset_id -> Button
## 下载完成待刷缩略图的素材集合 + 0.3s 合批定时器（见 _on_block_asset_ready）
var _pending_asset_thumbs: Dictionary = {}
var _asset_thumb_timer: Timer = null
var _block_asset_grid: EditorBlockListScript = null
var _block_asset_empty: Label = null
var _block_asset_group: ButtonGroup = null
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


func _text_input_has_focus() -> bool:
	if get_viewport() == null:
		return false
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _begin_alt_pick() -> void:
	if _alt_pick_active or current_tool == Tool.PICK or not _tool_buttons.has(Tool.PICK):
		return
	_alt_pick_return_tool = current_tool
	_alt_pick_active = true
	_tool_buttons[Tool.PICK].button_pressed = true
	print("MapEditor: Alt 临时吸管 -> 松开恢复工具 %d" % _alt_pick_return_tool)


func _end_alt_pick() -> void:
	if not _alt_pick_active:
		return
	var return_tool := _alt_pick_return_tool
	_alt_pick_active = false
	_alt_pick_return_tool = -1
	if return_tool >= 0 and _tool_buttons.has(return_tool):
		_tool_buttons[return_tool].button_pressed = true
		print("MapEditor: Alt 松开 -> 恢复工具 %d" % return_tool)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		var alt_key := event as InputEventKey
		if alt_key.keycode == KEY_ALT or alt_key.physical_keycode == KEY_ALT:
			if alt_key.pressed:
				if alt_key.ctrl_pressed or alt_key.meta_pressed or _text_input_has_focus():
					return
				_alt_key_down = true
				_begin_alt_pick()
			else:
				_alt_key_down = false
				_end_alt_pick()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			return
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
		elif ctrl and (key.keycode == KEY_C or key.physical_keycode == KEY_C):
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			_on_region_copy_pressed()
		elif ctrl and (key.keycode == KEY_X or key.physical_keycode == KEY_X):
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			_on_region_cut_pressed()
		elif ctrl and (key.keycode == KEY_V or key.physical_keycode == KEY_V):
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			_on_region_paste_pressed()
		elif not ctrl and key.shift_pressed and (key.keycode == KEY_X or key.physical_keycode == KEY_X):
			# Shift+X 交换前景/背景；必须先于下方 X 右转分支拦截。
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			_swap_block_slots()
		elif _move_tool_active and (key.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
				or key.physical_keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]):
			# 移动工具开启：方向键逐格平移选区（上/下/左/右 = y-/y+/x-/x+），
			# 每键恰好一步历史、选区跟随；无完整选区仅中文提示
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			var kc: Key = key.keycode
			if not (kc in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]):
				kc = key.physical_keycode
			match kc:
				KEY_UP: _nudge_region(Vector2i(0, -1))
				KEY_DOWN: _nudge_region(Vector2i(0, 1))
				KEY_LEFT: _nudge_region(Vector2i(-1, 0))
				KEY_RIGHT: _nudge_region(Vector2i(1, 0))
		elif key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE:
			# 操作提示最优先：只关弹窗，不取消地图模式、更不返回世界。
			if _shortcut_hints_dialog != null and _shortcut_hints_dialog.visible:
				_shortcut_hints_dialog.close()
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
			# 方块选择器优先于 ReplacePopup/地图模式：取消只关选择器且不回填。
			if _replace_picker_dialog != null and _replace_picker_dialog.visible:
				_replace_picker_dialog.cancel()
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
			# 放置模式激活时：Esc 先退出放置（清预览），不碰菜单也不返回世界
			if _place_mode:
				_cancel_place_mode()
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
			# 粘贴/移动预览激活时：Esc 先取消预览，不关菜单也不返回世界
			if _paste_mode or _move_armed:
				_cancel_paste()
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
			# 移动工具开启时：Esc 先关掉移动工具（同步工具栏开关），不关菜单也不返回世界
			if _move_tool_active:
				_set_move_tool(false)
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
			# 条件替换弹窗打开时：Esc 只收起弹窗，不返回世界。
			if _replace_popup != null and _replace_popup.visible:
				_replace_popup.hide()
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
			# 选择模式菜单打开时：Esc 先关菜单，不碰素材弹窗也不返回世界
			if _selection_popup != null and _selection_popup.visible:
				_close_selection_popup()
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
			# 素材面板弹窗（导入文件选择/隐藏确认）打开时：Esc 先关弹窗，不返回世界
			if _asset_panel != null and _asset_panel.is_dialog_open():
				_asset_panel.close_dialogs()
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
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
	# ---- 画布右侧最近吸取栏（限制在 CanvasHolder 内，不占 SidePanel 宽度） ----
	_build_recent_picks_bar(holder)

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

	# ---- 8 个 Tab：文件 / 生成 / 地形 / 方块 / 角色 / 历史 / 素材 / 预设 ----
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
	if _replace_source_opt == null:
		return "terrain:."
	return String(_replace_source_opt.get_meta("code", "terrain:."))


func _replace_dest_code() -> String:
	if _replace_dest_opt == null:
		return _replace_code_for_block(_block_fg)
	return String(_replace_dest_opt.get_meta("code", _replace_code_for_block(_block_fg)))


func _replace_code_for_block(block: Dictionary) -> String:
	if String(block.get("kind", "terrain")) == "asset" and not String(block.get("id", "")).is_empty():
		return "asset:%s" % String(block.get("id", ""))
	var terrain := StringName(String(block.get("id", "plain")))
	return "terrain:%s" % String(BattlefieldDocScript.TERRAIN_GLYPH.get(terrain, "."))


## 选中编码项；地图里吸到但不在已保存素材库的 id 也允许作为源/目标。
func _select_replace_option(opt: Button, code: String) -> bool:
	if opt == null or code.is_empty():
		return false
	var item: Dictionary = {}
	for candidate in _replace_items:
		if "%s:%s" % [String(candidate.get("kind", "")), String(candidate.get("id", ""))] == code:
			item = candidate
			break
	if item.is_empty() and code.begins_with("asset:") and code.length() > 6:
		item = MapEditorOverlaysScript.replace_item_for_code(self, code)
		_replace_items.append(item)
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


func _open_replace_picker(target: String) -> void:
	if _replace_picker_dialog == null:
		return
	MapEditorOverlaysScript.replace_populate_options(self)
	_replace_picker_target = target
	var selected := _replace_dest_code() if target == "dest" else _replace_source_code()
	_replace_picker_dialog.open(_replace_items, selected)


func _on_replace_picker_chosen(kind: String, id: String) -> void:
	var code := "%s:%s" % [kind, id]
	if _replace_picker_target == "dest":
		_select_replace_option(_replace_dest_opt, code)
	else:
		_select_replace_option(_replace_source_opt, code)
		_refresh_replace_scope()


func _reset_replace_popup() -> void:
	MapEditorOverlaysScript.replace_populate_options(self)
	var source_code := "terrain:."
	if _canvas != null:
		var hover_code := MapEditorPaintOpsScript.code_at(model, _canvas.hover_cell)
		if not hover_code.is_empty():
			source_code = hover_code
	_select_replace_option(_replace_source_opt, source_code)
	_select_replace_option(_replace_dest_opt, _replace_code_for_block(_block_fg))
	_refresh_replace_scope()


func _set_replace_source_from_cell(cell: Vector2i) -> void:
	var code := MapEditorPaintOpsScript.code_at(model, cell)
	if code.is_empty():
		_status("替换失败：坐标越界", true)
		return
	_select_replace_option(_replace_source_opt, code)
	_refresh_replace_scope()
	_status("被替换方块：%s" % _replace_source_opt.text)
	print("[editor] 替换源 cell=%s code=%s" % [str(cell), code])  # L1 埋点


func _refresh_replace_scope() -> void:
	if _replace_scope_label == null:
		return
	var is_region := _selection_mode == &"region" and _region_pos2_set and _selection_range.is_active()
	var count := _selection_range.cells_2d().size() if is_region else int(model.width) * int(model.height)
	_replace_scope_label.text = "当前范围：%s %d 格" % ["选区内" if is_region else "全图", count]


func _build_cell_info() -> Control:
	return MapEditorOverlaysScript.build_cell_info(self)


## 右下角 34×30 键盘图标；节点名保留 EditorHintBar，点击打开完整键帽弹窗。
func _build_hint_bar() -> Control:
	var button := Button.new()
	button.name = "EditorHintBar"
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.tooltip_text = "操作提示"
	button.custom_minimum_size = Vector2(34, 30)
	button.icon = UIThemeScript.icon("keyboard")
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 20)
	button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	button.offset_left = -46.0
	button.offset_top = -42.0
	button.offset_right = -12.0
	button.offset_bottom = -12.0
	button.pressed.connect(func():
		if _shortcut_hints_dialog != null:
			_shortcut_hints_dialog.open(HINT_ITEMS))
	return button


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


func _swap_block_slots() -> void:
	var old_fg := _block_fg.duplicate(true)
	_set_block_slot("fg", _block_bg)
	_set_block_slot("bg", old_fg)
	_status("已交换前景/背景：%s" % _block_label(_block_fg))


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


## 画笔统一消费前景槽：素材写覆盖层，内置地形写 rows 并清覆盖。
func _apply_paint_block(cell: Vector2i) -> void:
	if String(_block_fg.get("kind", "terrain")) == "asset":
		var asset_id := String(_block_fg.get("id", ""))
		if not asset_id.is_empty():
			_set_tile_override(cell, asset_id)
		return
	var terrain := StringName(_block_fg.get("id", "plain"))
	_set_glyph(cell, BattlefieldDocScript.TERRAIN_GLYPH.get(terrain, "."))
	_set_tile_override(cell, "")


## 吸管只读取模型：素材覆盖优先，否则取 rows 图例；Alt/背景参数决定写入哪个槽。
func _pick_block(cell: Vector2i, to_background: bool = false) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(model.width) or cell.y >= int(model.height):
		_status("吸取失败：坐标越界", true)
		return
	var asset_id := BattlefieldDocScript.tile_override_at(model, cell)
	var block: Dictionary
	if not asset_id.is_empty():
		block = {"kind": "asset", "id": asset_id, "z": BattlefieldDocScript.cell_z(model, cell)}
	else:
		var row: String = model.rows[cell.y]
		var terrain := BattlefieldDocScript.glyph_to_terrain(row.substr(cell.x, 1))
		block = {"kind": "terrain", "id": String(terrain), "z": BattlefieldDocScript.cell_z(model, cell)}
	_set_block_slot("bg" if to_background else "fg", block)
	_remember_recent_pick(block)
	_status("已吸取：%s（%s）" % [_block_label(block), "背景" if to_background else "前景"])
	print("[editor] 吸取方块 cell=%s slot=%s kind=%s id=%s z=%d"
		% [str(cell), "bg" if to_background else "fg", String(block.kind), String(block.id), int(block.z)])  # L1 埋点


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


## Tab【预设】：区域预设库（保存当前选区为命名预设；填入选区=选区左上角一步
## 历史回写，放置模式=点击画布以该格为左上角连续放置；均走 region_clipboard
## 五层 payload，预设本体持久化在 region_preset_store）。
func _build_preset_tab(tabs: TabContainer) -> void:
	var tab := UIFactoryScript.add_tab(tabs, "预设", "bookmark")
	var preview_toggle := CheckButton.new()  # 直建控件：随预设簇留在门面（P0-3 统一整改）
	MapEditorPanelTabsScript.build_preset_tab(self, tab, preview_toggle)


## 素材面板选中变化：写入选中态并同步画布预览格
func _on_asset_selected(descriptor: Dictionary) -> void:
	_selected_asset = descriptor
	if String(descriptor.get("kind", "")) == UserAssetCatalogScript.KIND_TERRAIN:
		_set_block_slot("fg", {"kind": "asset", "id": String(descriptor.get("id", "")), "z": int(_block_fg.z)})
	_clear_block_asset_selection()  # 与方块页选中互斥
	_update_asset_preview()


## 重建方块页「素材方块」网格：全部地形素材（未缓存的顺手触发自动加载），按 id 稳定排序；
## 缩略图走 adapter.resolve_many 一次库加载批量出图（逐 id resolve 会重复整库 JSON 解析，
## 1455 素材 × 每 asset_ready 全网格重建曾直接把编辑器卡死）；asset_ready 只换单按钮缩略图。
## 选中项仍存在则恢复按下态，已消失（被隐藏）则清空选中。
func _rebuild_block_asset_grid() -> void:
	if _block_asset_grid == null or _asset_service == null or _asset_adapter == null:
		return
	_block_asset_buttons.clear()
	var assets: Array = _asset_service.list_assets()
	assets.sort_custom(func(a, b): return String((a as Dictionary).get("id", "")) < String((b as Dictionary).get("id", "")))
	var ids: Array = []
	var items: Array[Dictionary] = []
	for raw in assets:
		var d := raw as Dictionary
		if String(d.get("kind", "")) != UserAssetCatalogScript.KIND_TERRAIN:
			continue
		var aid := String(d.get("id", ""))
		# 只列用户保存（✓）的方块：浏览在线列表会自动下载缓存，按缓存过滤等于全量进来；
		# 未下载的已保存方块保持占位，下面顺手触发下载，完成后经 asset_ready 合批重建换真图
		if not bool(d.get("saved", false)):
			continue
		ids.append(aid)
		if String(_asset_service.get_asset_state(aid).get("status", "")) != "ready":
			_asset_service.request_asset_image(aid)
	# p_cache=false：不灌 LRU（防挤穿热缓存）；列表规模=已下载数，resolve_many 单次库加载可承受
	var visuals: Dictionary = _asset_adapter.resolve_many(ids, false)
	for aid in ids:
		var d: Dictionary = _asset_service.find_by_id(aid)
		var visual: Dictionary = visuals.get(aid, {})
		items.append({"kind": "asset", "id": aid,
			"label": String(d.get("name", aid)), "texture": visual.get("texture")})
	var selected := "" if _selected_block_asset.is_empty() else "asset:%s" % _selected_block_asset
	_block_asset_grid.configure(items, selected, true)
	for i in range(ids.size()):
		var tb := _block_asset_grid.get_button(i)
		UIThemeScript.style_button(tb)
		_block_asset_buttons[ids[i]] = tb
	if _block_asset_empty != null:
		_block_asset_empty.visible = ids.is_empty()
	if not _selected_block_asset.is_empty() and not _block_asset_buttons.has(_selected_block_asset):
		_selected_block_asset = ""
		_update_asset_preview()


func _on_block_asset_btn_pressed(asset_id: String) -> void:
	if _selected_block_asset == asset_id:
		_selected_block_asset = ""
	else:
		_selected_block_asset = asset_id
		_set_block_slot("fg", {"kind": "asset", "id": asset_id, "z": int(_block_fg.z)})
		_clear_asset_selection()  # 与素材 Tab 选中互斥
	_update_asset_preview()
	if _selected_block_asset.is_empty():
		_status("已取消方块素材选择")
	else:
		_status("方块素材 %s（画笔放置）" % asset_id)


## 清空方块页素材选中（素材 Tab 选中 / 地形调色板选中时调用，互斥）
func _clear_block_asset_selection() -> void:
	if _selected_block_asset.is_empty():
		return
	_selected_block_asset = ""
	if _block_asset_grid != null:
		_block_asset_grid.set_selected("")


## 当前生效的素材描述符：素材 Tab 选中优先，其次方块页选中
func _active_asset() -> Dictionary:
	if not _selected_asset.is_empty():
		return _selected_asset
	if _selected_block_asset.is_empty() or _asset_service == null:
		return {}
	var d: Variant = _asset_service.find_by_id(_selected_block_asset)
	return d if d is Dictionary else {}


## 素材图片下载完成：不立即逐张刷新——下载洪流期间每个事件都 clear_cache+resolve
## 会反复整库解析刷屏（每事件一次 654KB JSON parse）。记入待刷集合，0.3s 合批一次
## resolve_many 单库解析，只换受影响按钮的缩略图（全网格重建曾是进编辑器卡死的根因）。
func _on_block_asset_ready(asset_id: String) -> void:
	_pending_asset_thumbs[asset_id] = true
	if _asset_thumb_timer == null or not is_instance_valid(_asset_thumb_timer):
		_asset_thumb_timer = Timer.new()
		_asset_thumb_timer.name = "AssetThumbBatchTimer"
		_asset_thumb_timer.one_shot = true
		_asset_thumb_timer.wait_time = 0.3
		_asset_thumb_timer.timeout.connect(_flush_asset_thumbs)
		add_child(_asset_thumb_timer)
	_asset_thumb_timer.start()
	# 选中素材刚下载完时预览立即升级真图（单个 resolve，量小；先清陈旧占位缓存）
	if asset_id == String(_selected_asset.get("id", "")) or asset_id == _selected_block_asset:
		if _asset_adapter != null:
			_asset_adapter.clear_cache(asset_id)
		_update_asset_preview()


## 合批刷新待刷缩略图：整批一次 clear_cache + 一次 resolve_many（单库解析）。
func _flush_asset_thumbs() -> void:
	# 0.3s 合批：新下载的素材整体重建网格加入（列表=已下载集，重建即增量；不做逐按钮补丁）
	_pending_asset_thumbs.clear()
	_rebuild_block_asset_grid()


## 选地形/植物调色板时清空素材选中（两组互斥，避免误放置）
func _clear_asset_selection() -> void:
	if _selected_asset.is_empty():
		return
	_selected_asset = {}
	if _asset_panel != null:
		_asset_panel.deselect()
	_update_asset_preview()


## 库内容变化（导入/隐藏/编辑/清单同步）：校正方块页素材网格；
## 选中素材已不存在则清空选中；画布烘焙缓存已随库失效，整图刷新
func _on_asset_library_changed() -> void:
	_rebuild_block_asset_grid()
	MapEditorOverlaysScript.replace_populate_options(self)
	if _selected_asset.is_empty():
		_refresh_canvas()
		return
	var aid := String(_selected_asset.get("id", ""))
	if not (_asset_service.find_by_id(aid) is Dictionary):
		_selected_asset = {}
		if _asset_panel != null:
			_asset_panel.deselect()
	_update_asset_preview()
	_refresh_canvas()


## 画布预览格跟随素材选中（地块/植物素材统一走 adapter.resolve 烘焙视觉）
func _update_asset_preview() -> void:
	if _canvas == null:
		return
	var d := _active_asset()
	if d.is_empty():
		_canvas.asset_preview_visual = {}
		return
	_canvas.asset_preview_visual = _asset_adapter.resolve(String(d.get("id", "")))


## 切 Tab 时封存上一动作（画笔拖动在换页瞬间定格为一步）
func _on_tab_changed(_idx: int) -> void:
	_seal_pending()
# ============================================================
# UI 构建辅助（统一样式系统 + 控件工厂）
# ============================================================
## 统一按钮组件入口：PixelButton + 禁用自带音效。
## 编辑器内按钮音效由全局 Sfx autoload（game_sfx.gd）对 BaseButton 统一挂接，
## 组件自带 HoverSfx/ClickSfx 会叠加双声，故一律关闭、只留全局钩子。
func _pixel_btn() -> Button:
	var b := PixelButtonScript.new()
	b.hover_sfx_enabled = false
	b.click_sfx_enabled = false
	return b


# ============================================================
# 编辑操作（canvas 信号 + 可测方法；生效工具由激活 Tab 决定）
# ============================================================

## 当前生效工具：高度升降/替换始终遵循工具条；地形 Tab = 画笔/植物；角色 Tab = 放置单位。
## 避免在角色页选好职业点画布，却沿用工具条遗留的填充/橡皮。
func _active_tool() -> int:
	if current_tool == Tool.HEIGHT_UP or current_tool == Tool.HEIGHT_DOWN \
			or current_tool == Tool.REPLACE or current_tool == Tool.PICK:
		return current_tool
	if _tabs == null:
		return current_tool
	var title := _tabs.get_tab_title(_tabs.current_tab)
	if title == "地形":
		if current_tool == Tool.PAINT:
			return Tool.PLANT if not current_prop.is_empty() else Tool.PAINT
		if not _selected_asset.is_empty():
			return Tool.ASSET
		return Tool.PLANT if not current_prop.is_empty() else Tool.PAINT
	if title == "方块":
		if current_tool == Tool.PAINT:
			return Tool.PAINT
		return Tool.ASSET if not _selected_block_asset.is_empty() else Tool.SELECT
	if title == "角色":
		return Tool.UNIT
	return current_tool


func _on_cell_pressed(cell: Vector2i, alt_pressed: bool = false, shift_pressed: bool = false) -> void:
	# 临时吸管优先于放置/粘贴/移动：按住 Alt 时始终只吸取，绝不改模型。
	if _alt_pick_active:
		_pick_block(cell, shift_pressed or Input.is_key_pressed(KEY_SHIFT))
		return
	if _place_mode:
		_commit_place_preset(cell)  # 放置模式：点击=以该格为左上角放置
		return
	if _paste_mode:
		_commit_paste(cell)  # 粘贴模式：点击=提交落点
		return
	# 移动工具开启（独立开关，与 current_tool/_selection_mode 解耦）：任意格按下
	# =抓取选区（不落点、不设端点、不进任何工具动作，绝不触发 _apply_region_click）
	if _move_tool_active:
		var mt_bounds := _move_tool_bounds()
		if mt_bounds.is_empty():
			_status("移动工具：请先框选一个区域", true)
			return
		_move_armed = true
		_move_grab = cell - mt_bounds[0]  # 记录抓取偏移（按下格-选区 min）
		_move_preview = cell
		return
	var tool := _active_tool()
	if tool == Tool.PICK:
		_pick_block(cell, alt_pressed or _alt_key_down)
		return  # 吸管只改前景/背景槽，不进入文档历史。
	if tool == Tool.REPLACE:
		_set_replace_source_from_cell(cell)
		return  # 条件替换：点格只选源；写模型统一走 ReplaceApplyBtn。
	# 区域内按下（完整区域+SELECT+区域模式）→ 待移动：不落点、不设端点；
	# 原地松开=纯点击，由 _on_cell_released 补走原 _apply_region_click 逻辑
	if tool == Tool.SELECT and _selection_mode == &"region" and _region_pos2_set \
			and _selection_range.is_active() and _selection_range.contains_2i(cell):
		_move_armed = true
		_move_grab = cell
		_move_preview = cell
		return
	if tool == Tool.HEIGHT_UP or tool == Tool.HEIGHT_DOWN:
		_height_stroke_cells.clear()
	_apply_tool(cell)


func _on_cell_dragged(cell: Vector2i) -> void:
	# 区域内按下后拖动 → 移动预览（绿=合法落点/红=越界）；仍不设区域端点（既有契约）
	if _move_armed and _move_tool_active:
		if cell != _move_preview:  # 移动工具：跨格才预览（跟随抓取偏移）
			_move_preview = cell
			_update_move_preview(cell)
		return
	if _move_armed and cell != _move_grab:
		_move_preview = cell
		_update_move_preview(cell)
		return
	# 拖动仅对画笔/植物/橡皮/高度升降有意义（填充/角色不响应拖动）
	var tool := _active_tool()
	if tool == Tool.SELECT:
		if _selection_mode != &"region":
			_select_cell(cell)  # 区域模式：拖动不设端点，须两次独立点击
	elif tool == Tool.PAINT:
		_apply_paint_block(cell)
	elif tool == Tool.PLANT:
		_set_prop(cell, current_prop)
	elif tool == Tool.ASSET:
		_apply_asset_tool(cell)
	elif tool == Tool.ERASE:
		_set_glyph(cell, ".")
		_set_prop(cell, "")
		_set_tile_override(cell, "")
		_set_prop_asset(cell, "")
	elif tool == Tool.HEIGHT_UP or tool == Tool.HEIGHT_DOWN:
		_apply_height_brush(cell, tool)


## 画布左键释放（本次笔画以 cell press 开始）：移动工具/区域内拖动 → 跨格=移动
## 区域（一步历史）；原地松开：移动工具=纯点击不改任何状态，区域内拖动=按原
## 逻辑补 _apply_region_click（第三次点击仍重置 pos1）
func _on_cell_released(cell: Vector2i) -> void:
	if not _move_armed:
		return
	var grab := _move_grab
	var via_tool := _move_tool_active
	_move_armed = false
	_move_grab = Vector2i(-1, -1)
	_move_preview = Vector2i(-1, -1)
	if _canvas != null:
		_canvas.clear_paste_preview()
	if via_tool:
		var mt_bounds := _move_tool_bounds()
		if mt_bounds.is_empty():
			return
		var delta: Vector2i = cell - grab - (mt_bounds[0] as Vector2i)  # grab=抓取偏移（按下格-选区 min）
		if delta == Vector2i.ZERO:
			return  # 原地松开：不改模型、不入历史、不改选区、不触发区域选择
		_commit_region_move(mt_bounds, delta, true)
		return
	var bounds := _region_2d_bounds()
	if cell == grab:
		_apply_region_click(cell)
		return
	if bounds.is_empty():
		return
	_commit_region_move(bounds, cell - grab, false)


## 提交区域移动（越界仅报错：不改模型不入历史；成功恰好一步历史）；
## translate=移动工具提交：选区随内容平移到目标（区域内拖动不平移）
func _commit_region_move(bounds: Array, delta: Vector2i, translate_selection: bool) -> void:
	var lo: Vector2i = bounds[0]
	var hi: Vector2i = bounds[1]
	var err := RegionClipboardScript.bounds_error(model, lo + delta, hi + delta)
	if not err.is_empty():
		_status("移动失败：%s" % err, true)
		return
	_push_undo("移动区域")
	var result: Dictionary = RegionClipboardScript.move(model, lo, hi, delta)
	if translate_selection and _selection_range.is_active():
		_selection_range.anchor += Vector3i(delta.x, delta.y, 0)
		_selection_range.focus += Vector3i(delta.x, delta.y, 0)
	_refresh_canvas()
	_sync_region_marker()
	var dropped := int(result.get("dropped_units", 0))
	var suffix := "（%d 个单位因地形不可站立被丢弃）" % dropped if dropped > 0 else ""
	_status("已移动区域 → (%d,%d)%s" % [lo.x + delta.x, lo.y + delta.y, suffix])
	print("[editor] 移动区域 min=%s delta=%s dropped_units=%d" % [str(lo), str(delta), dropped])  # L1 埋点


## 方向键逐格平移：复用移动提交（一步历史+选区跟随）；无完整选区仅中文提示
func _nudge_region(delta: Vector2i) -> void:
	var bounds := _move_tool_bounds()
	if bounds.is_empty():
		_status("移动工具：请先框选一个区域", true)
		return
	_commit_region_move(bounds, delta, true)


## 移动工具模式 _move_grab=抓取偏移（delta=悬停格-偏移-选区 min）；
## 区域内拖动 _move_grab=按下格（delta=悬停格-按下格）
func _move_delta_for(cell: Vector2i) -> Vector2i:
	if _move_tool_active:
		var bounds := _move_tool_bounds()
		if bounds.is_empty():
			return Vector2i.ZERO
		return cell - _move_grab - (bounds[0] as Vector2i)
	return cell - _move_grab


## 移动预览：原区域矩形平移 delta（=悬停格-按下格），合法=绿框/越界=红框
func _update_move_preview(hover: Vector2i) -> void:
	if _canvas == null or not _move_armed:
		return
	var bounds := _move_tool_bounds() if _move_tool_active else _region_2d_bounds()
	if bounds.is_empty():
		return
	var delta := _move_delta_for(hover)
	var lo: Vector2i = bounds[0] + delta
	var hi: Vector2i = bounds[1] + delta
	_canvas.set_paste_preview(lo, hi, RegionClipboardScript.bounds_error(model, lo, hi).is_empty())


func _apply_tool(cell: Vector2i) -> void:
	var tool := _active_tool()
	if tool == Tool.SELECT:
		if _selection_mode == &"region":
			_apply_region_click(cell)
		else:
			_select_cell(cell)
		return  # 选择不是文档编辑，不进入历史。
	if tool == Tool.PICK:
		_pick_block(cell)
		return  # 吸管不是文档编辑，不进入历史。
	if tool == Tool.REPLACE:
		_set_replace_source_from_cell(cell)
		return  # 防御直接调用：替换工具点击同样只选源。
	var names := {
		Tool.PAINT: "画笔", Tool.FILL: "填充", Tool.ERASE: "橡皮", Tool.UNIT: "角色",
		Tool.PLANT: "植物", Tool.HEIGHT_UP: "地形上升", Tool.HEIGHT_DOWN: "地形下降",
		Tool.ASSET: "素材", Tool.REPLACE: "替换方块", Tool.PICK: "吸管",
	}
	var undo_label: String = names[tool]
	_push_undo(undo_label)  # 按下一次=一步；后续拖动不再入栈（整笔一笔撤销）
	match tool:
		Tool.PAINT:
			_apply_paint_block(cell)
		Tool.FILL:
			_apply_fill(cell)
		Tool.ERASE:
			if _remove_unit_at(cell):
				pass  # 单位优先删除
			else:
				_set_glyph(cell, ".")
				_set_prop(cell, "")
				_set_tile_override(cell, "")
				_set_prop_asset(cell, "")
		Tool.UNIT:
			if not _remove_unit_at(cell):
				place_unit(cell, selected_faction, selected_class, int(_level_box.value), _unit_name_edit.text)
		Tool.PLANT:
			_set_prop(cell, current_prop)
		Tool.ASSET:
			_apply_asset_tool(cell)
		Tool.HEIGHT_UP, Tool.HEIGHT_DOWN:
			_apply_height_brush(cell, tool)


## 高度画笔只改 block_layout.z；单笔每格至多执行一次，边界由文档 schema 限制。
func _apply_height_brush(cell: Vector2i, tool: int) -> void:
	if _height_stroke_cells.has(cell):
		return
	_height_stroke_cells[cell] = true
	var delta := 1 if tool == Tool.HEIGHT_UP else -1
	var next_z := clampi(
		BattlefieldDocScript.cell_z(model, cell) + delta,
		BattlefieldDocScript.BLOCK_MIN_Z,
		BattlefieldDocScript.BLOCK_MAX_Z
	)
	if not BattlefieldDocScript.set_cell_z(model, cell, next_z):
		return
	_canvas._refresh_cell(cell)
	if _canvas.selected_cell == cell:
		_sync_block_panel()
	_update_cell_info(cell)
	var action := "地形上升" if tool == Tool.HEIGHT_UP else "地形下降"
	_status("%s (%d,%d) → z=%d" % [action, cell.x, cell.y, next_z])
	print("[editor] 高度画笔 cell=%s z=%d" % [str(cell), next_z])  # L1 埋点


func _select_cell(cell: Vector2i, activate_block: bool = true) -> void:
	_canvas.selected_cell = cell
	_sync_block_panel()
	_update_cell_info(cell)
	if activate_block and _tabs != null:
		_tabs.current_tab = TAB_BLOCK


func _on_hover_changed(cell: Vector2i) -> void:
	if _paste_mode:
		_update_paste_preview(cell)  # 粘贴预览跟随悬停格
	if _place_mode:
		_update_place_preview(cell)  # 放置预览跟随悬停格
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
	_set_block_slot("fg", {"kind": String(_block_fg.kind), "id": String(_block_fg.id), "z": int(value)})
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


## 放置/清除某格的素材覆盖（asset_id 为空=清除）：
## kind=terrain → tile_overrides 层（整格替换为素材块，与地形字符解耦）；
## kind=plant   → props 层 asset 通道（与 texture 通道植物同层共存，同格至多一株）
func _set_tile_override(cell: Vector2i, asset_id: String) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(model.width) or cell.y >= int(model.height):
		return
	if not BattlefieldDocScript.set_tile_override(model, cell, asset_id):
		return
	_canvas._refresh_cell(cell)
	if not asset_id.is_empty():
		_status("地块素材 %s @(%d,%d)" % [asset_id, cell.x, cell.y])


func _set_prop_asset(cell: Vector2i, asset_id: String) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(model.width) or cell.y >= int(model.height):
		return
	if not BattlefieldDocScript.set_prop_asset(model, cell, asset_id):
		return
	_canvas._refresh_cell(cell)
	if not asset_id.is_empty():
		_status("植物素材 %s @(%d,%d)" % [asset_id, cell.x, cell.y])


## 素材放置 / 同格再点取消覆盖（拖动路径只放置不取消）
func _apply_asset_tool(cell: Vector2i) -> void:
	var d := _active_asset()
	var asset_id := String(d.get("id", ""))
	if asset_id.is_empty():
		return
	if String(d.get("kind", "")) == UserAssetCatalogScript.KIND_PLANT:
		if BattlefieldDocScript.prop_asset_at(model, cell) == asset_id:
			_set_prop_asset(cell, "")
		else:
			_set_prop_asset(cell, asset_id)
	else:
		if BattlefieldDocScript.tile_override_at(model, cell) == asset_id:
			_set_tile_override(cell, "")
		else:
			_set_tile_override(cell, asset_id)


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


## 洪水填充：同图例连通区域 -> 目标地形（内核在 MapEditorPaintOpsScript.flood_fill_terrain）
func fill_cell(cell: Vector2i, terrain: StringName) -> void:
	var filled := MapEditorPaintOpsScript.flood_fill_terrain(model, cell, terrain)
	if filled <= 0:
		return
	_refresh_canvas()
	_status("填充 %s ×%d 格" % [BattlefieldDocScript.TERRAIN_CN[terrain], filled])


# ============================================================
# 选择模式菜单与区域填充（GLM：EditorSelectionRange / BlockSelector / 画布虚线框）
# ============================================================

## 选择模式弹窗（点「选择」/「填充」图标打开，Esc 关闭）：模式切换 + pos1/pos2
## 坐标编辑 + 通用方块选择器 + 区域填充/清除按钮。默认隐藏。
func _build_selection_popup() -> void:
	_mode_option = OptionButton.new()  # 直建控件：随选择簇留在门面（P0-3 统一整改）
	MapEditorOverlaysScript.build_selection_popup(self, _mode_option)


func _open_selection_popup() -> void:
	if _selection_popup == null:
		return
	_selection_popup.visible = true
	if _fill_selector != null:
		_fill_selector.refresh_assets()
	_sync_region_boxes()


func _close_selection_popup() -> void:
	if _selection_popup != null:
		_selection_popup.visible = false


func _on_selection_mode_item(idx: int) -> void:
	_selection_mode = &"region" if idx == 1 else &"single"
	if _selection_mode == &"single":
		# 回单格：清区域端点与虚线框（单格选择行为与既有契约完全一致）
		_selection_range.clear()
		_region_pos2_set = false
		_sync_region_marker()
	_status("选择模式：%s" % ("区域（两次点击设 pos1/pos2，拖动无效）" if idx == 1 else "单格"))


## 区域模式点击：第一次=pos1（取所在格 z），第二次=pos2，第三次重新从 pos1 开始
func _apply_region_click(cell: Vector2i) -> void:
	var p := Vector3i(cell.x, cell.y, BattlefieldDocScript.cell_z(model, cell))
	if not _selection_range.is_active() or _region_pos2_set:
		_selection_range.begin(p)
		_region_pos2_set = false
	else:
		_selection_range.update_focus(p)
		_region_pos2_set = true
	_sync_region_marker()
	var mn := _selection_range.min_corner()
	var mx := _selection_range.max_corner()
	_status("区域 pos1=(%d,%d,%d) pos2=(%d,%d,%d) · %d 格" % [
		mn.x, mn.y, mn.z, mx.x, mx.y, mx.z, _selection_range.cell_count(),
	])
	print("[editor] 区域端点 pos1=%s pos2=%s" % [str(mn), str(mx)])  # L1 埋点


## range.changed（端点变化 / clamp_to 缩框）→ 画布虚线框 + 坐标 SpinBox 回显
func _on_selection_range_changed() -> void:
	_sync_region_marker()
	_refresh_replace_scope()


func _sync_region_marker() -> void:
	if _canvas == null:
		return
	if _selection_range.is_active():
		var mn := _selection_range.min_corner()
		var mx := _selection_range.max_corner()
		# 两端点同高度 → 固定高度平面四边形（旧行为）；异高度 → 立体选择体
		# （z_min 底面 + z_max 顶面 + 四角立边），不再退化为单平面/跟随地形
		if mn.z == mx.z:
			_canvas.set_selection_region(Vector2i(mn.x, mn.y), Vector2i(mx.x, mx.y), mn.z)
		else:
			_canvas.set_selection_region(Vector2i(mn.x, mn.y), Vector2i(mx.x, mx.y),
				mini(mn.z, mx.z), maxi(mn.z, mx.z))
	else:
		_canvas.clear_selection_region()
	_sync_region_boxes()


## 坐标 SpinBox 回显原始端点（anchor=pos1 / focus=pos2，与手改一一对应）：
## 未激活时禁用编辑，max 跟随模型尺寸
func _sync_region_boxes() -> void:
	if _pos1_boxes.is_empty() or _pos2_boxes.is_empty():
		return
	_syncing_region_boxes = true
	var active := _selection_range.is_active()
	for pair in [[_pos1_boxes, _selection_range.anchor], [_pos2_boxes, _selection_range.focus]]:
		var boxes: Dictionary = pair[0]
		var p: Vector3i = pair[1]
		boxes.x.max_value = float(maxi(0, int(model.width) - 1))
		boxes.y.max_value = float(maxi(0, int(model.height) - 1))
		boxes.x.editable = active
		boxes.y.editable = active
		boxes.z.editable = active
		if active:
			boxes.x.value = p.x
			boxes.y.value = p.y
			boxes.z.value = p.z
	_syncing_region_boxes = false


## SpinBox 手改坐标：直接改原始端点（anchor=pos1 / focus=pos2，回显与输入
## 一一对应；归一化只影响虚线框与填充遍历）；夹进模型边界
func _on_region_box_changed(value: float, which: String, axis: StringName) -> void:
	if _syncing_region_boxes or not _selection_range.is_active():
		return
	var v := int(value)
	if axis == &"x":
		v = clampi(v, 0, int(model.width) - 1)
	elif axis == &"y":
		v = clampi(v, 0, int(model.height) - 1)
	else:
		v = clampi(v, BattlefieldDocScript.BLOCK_MIN_Z, BattlefieldDocScript.BLOCK_MAX_Z)
	if which == "pos1":
		var p := _selection_range.anchor
		p[String(axis)] = v
		var f := _selection_range.focus
		_selection_range.begin(p)
		_selection_range.update_focus(f)
	else:
		var p := _selection_range.focus
		p[String(axis)] = v
		_selection_range.update_focus(p)
	_sync_region_marker()


## 填充路由：完整区域 → 区域填充；否则按前景槽做素材/地形洪水填充。
func _apply_fill(cell: Vector2i) -> void:
	if _selection_mode == &"region" and _region_pos2_set and _selection_range.is_active():
		_fill_region()
		return
	match StringName(_block_fg.get("kind", "terrain")):
		&"asset":
			var asset_id := String(_block_fg.get("id", ""))
			var filled := MapEditorPaintOpsScript.flood_fill_asset(model, cell, asset_id)
			if filled > 0:
				_refresh_canvas()
				_status("素材填充 %s ×%d 格" % [asset_id, filled])
				print("[editor] 素材洪水填充 asset=%s cells=%d" % [asset_id, filled])  # L1 埋点
		_:
			fill_cell(cell, StringName(_block_fg.get("id", "plain")))


## 条件替换：完整选区优先，否则全图；仅命中源类型的格子写目标，高度一律不动
##（匹配/写入内核在 MapEditorPaintOpsScript；匹配与写入之间夹入历史入栈）。
## terrain 源只匹配无 tile_override 且 rows 图例相同的格；asset 源只匹配覆盖 id。
func _apply_replace() -> void:
	if _replace_source_opt == null or _replace_dest_opt == null:
		_status("替换失败：请选择源方块与目标方块", true)
		return
	var source_code := _replace_source_code()
	var dest_code := _replace_dest_code()
	if source_code.is_empty() or dest_code.is_empty():
		_status("替换失败：源方块或目标方块无效", true)
		return
	if source_code == dest_code:
		_status("替换失败：源方块与目标方块相同", true)
		return
	var is_region := _selection_mode == &"region" and _region_pos2_set and _selection_range.is_active()
	var cells: Array = []
	if is_region:
		var mn := _selection_range.min_corner()
		var mx := _selection_range.max_corner()
		var err := RegionClipboardScript.bounds_error(model,
			Vector2i(mn.x, mn.y), Vector2i(mx.x, mx.y))
		if not err.is_empty():
			_status("替换失败：%s" % err, true)
			return
		cells = _selection_range.cells_2d()
	else:
		for y in range(int(model.height)):
			for x in range(int(model.width)):
				cells.append(Vector2i(x, y))
	if cells.is_empty():
		_status("替换失败：选区为空", true)
		return
	var source_kind := "asset" if source_code.begins_with("asset:") else "terrain"
	var source_value := source_code.substr(6) if source_kind == "asset" else source_code.substr(8)
	var matched: Array = MapEditorPaintOpsScript.match_cells(model, cells, source_kind, source_value)
	if matched.is_empty():
		_status("匹配 0 格：未替换", true)
		return
	var action := "替换区域" if is_region else "替换全图"
	_push_undo(action)
	var dest_kind := "asset" if dest_code.begins_with("asset:") else "terrain"
	var dest_value := dest_code.substr(6) if dest_kind == "asset" else dest_code.substr(8)
	var replaced: int = MapEditorPaintOpsScript.write_cells(model, matched, dest_kind, dest_value)
	_seal_pending()  # 按钮动作立即落一条历史，不等下一次画布交互
	_refresh_canvas()
	_status("%s：%d 格（高度不变）" % [action, replaced])
	print("[editor] %s source=%s dest=%s cells=%d" % [action, source_code, dest_code, replaced])  # L1 埋点


## 区域填充：区域内每格应用选择器内容——内置地形写 rows 并清素材覆盖；
## 已保存素材方块写 tile_overrides 不动 rows（两层正确区分）。
## 立体选择（pos1/pos2 异高）= 体积填充语义：矩形内每列都填充，且每列顶面统一
## 找平至带顶 z_hi（单块列模型每列只有一块立方体——选择 0..4 填充即整片抬成 z4
## 平台，「填充整个选择范围」而不是只刷表层）；同高选择保持平面行为（全 footprint
## 写材质、不动块高）。调用方负责 _push_undo：填充与高度变化同一步历史（原子）。
##（填充内核在 MapEditorPaintOpsScript.fill_region）
func _fill_region() -> void:
	var mn := _selection_range.min_corner()
	var mx := _selection_range.max_corner()
	var result: Dictionary = MapEditorPaintOpsScript.fill_region(model, mn, mx,
		StringName(_block_fg.get("kind", "terrain")), String(_block_fg.get("id", "plain")),
		_selection_range.cells_2d())
	var kind := StringName(result.get("kind", &"terrain"))
	var id := String(result.get("id", "plain"))
	var count := int(result.get("count", 0))
	var leveled := int(result.get("leveled", 0))
	var volume := mn.z != mx.z
	var z_hi := maxi(mn.z, mx.z)
	_refresh_canvas()
	var label := id if kind == &"asset" else String(BattlefieldDocScript.TERRAIN_CN.get(StringName(id), id))
	if volume:
		_status("区域填充 %s ×%d 格（体积填充至 z%d，调整高度 %d 列）" % [label, count, z_hi, leveled])
	else:
		_status("区域填充 %s ×%d 格" % [label, count])
	print("[editor] 区域填充 kind=%s id=%s cells=%d volume=%s z_hi=%d leveled=%d"
		% [String(kind), id, count, str(volume), z_hi, leveled])  # L1 埋点


func _on_region_fill_pressed() -> void:
	if _selection_mode != &"region" or not _region_pos2_set or not _selection_range.is_active():
		_status("区域未完整（需两次点击画布设置 pos1/pos2）", true)
		return
	_push_undo("区域填充")  # 按钮路径自行入栈；画布 FILL 路径由 _apply_tool 统一入栈
	_fill_region()


func _on_region_clear_pressed() -> void:
	_selection_range.clear()
	_region_pos2_set = false
	_sync_region_marker()
	_status("已清除区域选择")


# ============================================================
# 区域剪贴板：复制 / 剪切 / 粘贴 / 区域内拖动移动
# （内核全部走 region_clipboard.gd 纯函数；本文件只做门禁、历史与状态栏）
# ============================================================

## 当前完整区域的 2D 角点 [min, max]；区域不完整（未两次点击/未激活）返回 []
func _region_2d_bounds() -> Array:
	if _selection_mode != &"region" or not _region_pos2_set or not _selection_range.is_active():
		return []
	var mn := _selection_range.min_corner()
	var mx := _selection_range.max_corner()
	return [Vector2i(mini(mn.x, mx.x), mini(mn.y, mx.y)),
		Vector2i(maxi(mn.x, mx.x), maxi(mn.y, mx.y))]


## 移动工具专用角点 [min, max]（与 current_tool/_selection_mode 解耦）：
## 只要求区域完整（两击设好 pos1/pos2 且选区激活）
func _move_tool_bounds() -> Array:
	if not _region_pos2_set or not _selection_range.is_active():
		return []
	var mn := _selection_range.min_corner()
	var mx := _selection_range.max_corner()
	return [Vector2i(mini(mn.x, mx.x), mini(mn.y, mx.y)),
		Vector2i(maxi(mn.x, mx.x), maxi(mn.y, mx.y))]


## 复制区域：extract 入剪贴板，不入历史（模型不变）
func _on_region_copy_pressed() -> void:
	var bounds := _region_2d_bounds()
	if bounds.is_empty():
		_status("区域未完整（需两次点击画布设置 pos1/pos2）", true)
		return
	var payload := RegionClipboardScript.extract(model, bounds[0], bounds[1])
	if payload.is_empty():
		_status("复制失败：区域越界", true)
		return
	_clipboard = payload
	_status("已复制 %s（CTRL+V 粘贴）" % RegionClipboardScript.describe(payload))
	print("[editor] 复制区域 %s" % RegionClipboardScript.describe(payload))  # L1 埋点


## 剪切区域：extract + clear_rect，一步历史（成功才入栈）
func _on_region_cut_pressed() -> void:
	var bounds := _region_2d_bounds()
	if bounds.is_empty():
		_status("区域未完整（需两次点击画布设置 pos1/pos2）", true)
		return
	var payload := RegionClipboardScript.extract(model, bounds[0], bounds[1])
	if payload.is_empty():
		_status("剪切失败：区域越界", true)
		return
	var err := RegionClipboardScript.bounds_error(model, bounds[0], bounds[1])
	if not err.is_empty():
		_status("剪切失败：%s" % err, true)
		return
	_push_undo("剪切区域")
	RegionClipboardScript.clear_rect(model, bounds[0], bounds[1])
	_clipboard = payload
	_refresh_canvas()
	_sync_region_marker()
	_status("已剪切 %s（CTRL+V 粘贴）" % RegionClipboardScript.describe(payload))
	print("[editor] 剪切区域 %s" % RegionClipboardScript.describe(payload))  # L1 埋点


## 粘贴区域：空剪贴板报错；否则进入粘贴模式，预览框跟随悬停格
func _on_region_paste_pressed() -> void:
	if _clipboard.is_empty():
		_status("剪贴板为空（先复制或剪切一个区域）", true)
		return
	_cancel_place_mode()  # 与放置模式互斥
	_paste_mode = true
	_paste_origin = Vector2i(-1, -1)
	_update_paste_preview(_canvas.hover_cell if _canvas != null else Vector2i(-1, -1))
	_status("粘贴模式：移动鼠标选择落点，点击画布提交，ESC 取消")
	print("[editor] 进入粘贴模式 %s" % RegionClipboardScript.describe(_clipboard))  # L1 埋点


## 粘贴预览随悬停格刷新：展开真实方块幽灵；只画地图内格，整体越界标红。
func _update_paste_preview(hover: Vector2i) -> void:
	if _canvas == null or not _paste_mode or _clipboard.is_empty():
		return
	_paste_origin = hover
	if hover.x < 0:
		_canvas.clear_paste_preview()
		return
	var ghost := RegionClipboardScript.ghost_at(model, _clipboard, hover)
	_canvas.set_placement_preview(ghost.cells, ghost.valid)


## 提交粘贴：越界/非法仅 _status 报错（不改模型不入历史）；成功一步历史
func _commit_paste(origin: Vector2i) -> void:
	var size := RegionClipboardScript.payload_size(_clipboard)
	var lo := origin
	var hi := origin + size - Vector2i(1, 1)
	var err := RegionClipboardScript.bounds_error(model, lo, hi)
	if not err.is_empty():
		_status("粘贴失败：%s" % err, true)
		return
	_push_undo("粘贴区域")
	var result: Dictionary = RegionClipboardScript.paste(model, _clipboard, lo)
	_cancel_paste()
	_refresh_canvas()
	_sync_region_marker()
	var dropped := int(result.get("dropped_units", 0))
	var suffix := "（%d 个单位因地形不可站立被丢弃）" % dropped if dropped > 0 else ""
	_status("已粘贴 %s%s" % [RegionClipboardScript.describe(_clipboard), suffix])
	print("[editor] 粘贴区域 origin=%s dropped_units=%d" % [str(lo), dropped])  # L1 埋点


## 取消粘贴/移动预览（ESC 或提交后调用；剪贴板内容保留，可再次粘贴）
func _cancel_paste() -> void:
	_paste_mode = false
	_paste_origin = Vector2i(-1, -1)
	_move_armed = false
	_move_grab = Vector2i(-1, -1)
	_move_preview = Vector2i(-1, -1)
	if _canvas != null:
		_canvas.clear_paste_preview()


## 移动工具开关（左侧工具栏 MoveToolToggle toggled）：写回状态并提示
func _on_move_tool_toggled(pressed: bool) -> void:
	_set_move_tool(pressed)
	_status("移动工具：%s" % ("开" if pressed else "关"))


## 同步移动工具状态（含开关无信号回写）；关闭时清待移动/预览
func _set_move_tool(active: bool) -> void:
	_move_tool_active = active
	if _move_tool_toggle != null and _move_tool_toggle.button_pressed != active:
		_move_tool_toggle.set_pressed_no_signal(active)
	if not active:
		_move_armed = false
		_move_grab = Vector2i(-1, -1)
		_move_preview = Vector2i(-1, -1)
		if _canvas != null:
			_canvas.clear_paste_preview()


# ============================================================
# 区域预设（预设 Tab）：保存=选区→payload→store（不动模型不入历史）；
# 填入选区=以选区左上角为原点按预设尺寸一步历史回写；放置模式=点击画布
# 以该格为左上角连续放置，每次一步历史；与粘贴模式互斥，ESC/切工具/
# 生成/读取/调尺寸均退出并清预览。
# ============================================================

## 刷新预设列表；select_id 非空则选中该项（保存后选中新项）
func _refresh_preset_list(select_id := "") -> void:
	if _preset_list == null or _preset_store == null:
		return
	_preset_list.clear()
	var selected_idx := -1
	for meta in _preset_store.list():
		var idx := _preset_list.add_item("%s — %d×%d — %d单位/%d植物" % [
			meta.name, int(meta.w), int(meta.h), int(meta.units), int(meta.props),
		])
		_preset_list.set_item_metadata(idx, String(meta.id))
		if String(meta.id) == select_id:
			selected_idx = idx
	if selected_idx >= 0:
		_preset_list.select(selected_idx)


## 当前列表选中项的预设 id（未选中返回空串）
func _selected_preset_id() -> String:
	if _preset_list == null:
		return ""
	var selected := _preset_list.get_selected_items()
	if selected.is_empty():
		return ""
	return String(_preset_list.get_item_metadata(selected[0]))


## 保存当前完整选区为预设：无完整选区仅中文提示（不写盘）；成功列表刷新并选中新项
func _on_save_preset_pressed() -> void:
	var bounds := _move_tool_bounds()
	if bounds.is_empty():
		_status("预设保存：请先框选一个完整区域（两次点击画布）", true)
		return
	var payload := RegionClipboardScript.extract(model, bounds[0], bounds[1])
	if payload.is_empty():
		_status("预设保存：区域数据提取失败", true)
		return
	var preset_name := _preset_name_edit.text if _preset_name_edit != null else ""
	var result: Dictionary = _preset_store.save(preset_name, payload)
	if not bool(result.ok):
		_status("预设保存失败：%s" % result.error, true)
		return
	_refresh_preset_list(String(result.id))
	if _preset_name_edit != null:
		_preset_name_edit.text = "预设 %d" % (_preset_store.count() + 1)
	_status("已保存预设「%s」（%d×%d）" % [preset_name.strip_edges(), int(payload.w), int(payload.h)])
	print("[editor] 保存预设 id=%s name=%s %d×%d" % [String(result.id), preset_name.strip_edges(), int(payload.w), int(payload.h)])  # L1 埋点


## 填入选区：以选区 2D 左上角为原点按预设尺寸回写五层；越界仅报错，成功一步历史
func _on_fill_preset_pressed() -> void:
	var id := _selected_preset_id()
	if id.is_empty():
		_status("填入预设：请先在列表选中一个预设", true)
		return
	var bounds := _move_tool_bounds()
	if bounds.is_empty():
		_status("填入预设：请先框选一个完整区域", true)
		return
	var payload: Dictionary = _preset_store.load(id)
	if payload.is_empty():
		_status("填入预设：预设不存在或已损坏", true)
		return
	var origin: Vector2i = bounds[0]
	var size := Vector2i(int(payload.w), int(payload.h))
	var hi := origin + size - Vector2i(1, 1)
	var err := RegionClipboardScript.bounds_error(model, origin, hi)
	if not err.is_empty():
		_status("填入失败：%s" % err, true)
		return
	_push_undo("填入预设")
	var result: Dictionary = RegionClipboardScript.write(model, payload, origin)
	_refresh_canvas()
	_sync_region_marker()
	var dropped := int(result.get("dropped_units", 0))
	var suffix := "（%d 个单位因地形不可站立被丢弃）" % dropped if dropped > 0 else ""
	_status("已填入预设 → (%d,%d)%s" % [origin.x, origin.y, suffix])
	print("[editor] 填入预设 id=%s origin=%s dropped_units=%d" % [id, str(origin), dropped])  # L1 埋点


## 放置模式开关：开启需已选预设（否则回弹）；与粘贴模式互斥
func _on_place_preset_toggled(on: bool) -> void:
	if on:
		var id := _selected_preset_id()
		if id.is_empty():
			_status("放置模式：请先在列表选中一个预设", true)
			if _place_preset_btn != null:
				_place_preset_btn.set_pressed_no_signal(false)
			return
		_cancel_paste()  # 与粘贴模式互斥
		_place_mode = true
		_place_preset_id = id
		_update_place_preview(_canvas.hover_cell if _canvas != null else Vector2i(-1, -1))
		_status("放置模式：点击画布放置「%s」，ESC 退出" % _preset_name_for_id(id))
		print("[editor] 进入放置模式 id=%s" % id)  # L1 埋点
	else:
		_cancel_place_mode()


## 实时预览总开关：关闭立即清除当前放置预览；不影响粘贴模式或放置提交
func _on_place_preview_toggled(on: bool) -> void:
	_place_preview_enabled = on
	if _canvas == null or not _place_mode:
		return
	if on:
		_update_place_preview(_canvas.hover_cell)
	else:
		_canvas.clear_paste_preview()


## 预设显示名（状态栏提示用；找不到返回 id）
func _preset_name_for_id(id: String) -> String:
	if _preset_store == null:
		return id
	for meta in _preset_store.list():
		if String(meta.id) == id:
			return String(meta.name)
	return id


## 放置预览随悬停格刷新：总开关关闭时保持无预览；正常显示真实应用效果，越界红色提示。
func _update_place_preview(hover: Vector2i) -> void:
	if _canvas == null or not _place_mode:
		return
	if not _place_preview_enabled or hover.x < 0:
		_canvas.clear_paste_preview()
		return
	var payload: Dictionary = _preset_store.load(_place_preset_id)
	if payload.is_empty():
		return
	var ghost := RegionClipboardScript.ghost_at(model, payload, hover)
	_canvas.set_placement_preview(ghost.cells, ghost.valid)


## 放置提交：以点击格为左上角写五层，一步历史；越界仅报错保持模式可重试；
## 成功后模式保持（可连续放置）
func _commit_place_preset(cell: Vector2i) -> void:
	var payload: Dictionary = _preset_store.load(_place_preset_id)
	if payload.is_empty():
		_status("预设不存在或已损坏，已退出放置模式", true)
		_cancel_place_mode()
		return
	var size := Vector2i(int(payload.w), int(payload.h))
	var hi := cell + size - Vector2i(1, 1)
	var err := RegionClipboardScript.bounds_error(model, cell, hi)
	if not err.is_empty():
		_status("放置失败：%s" % err, true)
		_update_place_preview(_canvas.hover_cell if _canvas != null else Vector2i(-1, -1))
		return
	_push_undo("放置预设")
	var result: Dictionary = RegionClipboardScript.write(model, payload, cell)
	_refresh_canvas()
	_sync_region_marker()
	var dropped := int(result.get("dropped_units", 0))
	var suffix := "（%d 个单位因地形不可站立被丢弃）" % dropped if dropped > 0 else ""
	_status("已放置预设 → (%d,%d)%s" % [cell.x, cell.y, suffix])
	print("[editor] 放置预设 id=%s at=%s dropped_units=%d" % [_place_preset_id, str(cell), dropped])  # L1 埋点


## 退出放置模式并清预览（ESC/关开关/生成/读取/调尺寸/切工具/进粘贴模式）
func _cancel_place_mode() -> void:
	_place_mode = false
	_place_preset_id = ""
	if _place_preset_btn != null and _place_preset_btn.button_pressed:
		_place_preset_btn.set_pressed_no_signal(false)
	if _canvas != null:
		_canvas.clear_paste_preview()


## 重命名选中预设：新名取名称输入框，失败中文提示
func _on_rename_preset_pressed() -> void:
	var id := _selected_preset_id()
	if id.is_empty():
		_status("重命名：请先在列表选中一个预设", true)
		return
	var new_name := _preset_name_edit.text if _preset_name_edit != null else ""
	if not _preset_store.rename(id, new_name):
		_status("重命名失败：名称不能为空或预设已不存在", true)
		return
	_refresh_preset_list(id)
	_status("已重命名为「%s」" % new_name.strip_edges())


## 删除选中预设：列表与存储同步；正在放置该预设则先退出
func _on_delete_preset_pressed() -> void:
	var id := _selected_preset_id()
	if id.is_empty():
		_status("删除：请先在列表选中一个预设", true)
		return
	if _place_mode and _place_preset_id == id:
		_cancel_place_mode()
	if not _preset_store.delete(id):
		_status("删除失败：预设已不存在", true)
		return
	_refresh_preset_list()
	_status("已删除预设")


## 刷新按钮：重读存储（外部改动/多实例并发时手动同步）
func _on_refresh_preset_pressed() -> void:
	_refresh_preset_list()
	_status("预设列表已刷新（共 %d 个）" % _preset_store.count())


func region_clipboard_info() -> Dictionary:
	var info := {
		"has_clipboard": not _clipboard.is_empty(),
		"paste_mode": _paste_mode,
		"place_preview": _place_preview_enabled,
		"move_armed": _move_armed,
		"move_tool": _move_tool_active,
		"history_len": _history.size(),
		"w": 0, "h": 0, "units": 0, "props": 0, "overrides": 0,
	}
	if not _clipboard.is_empty():
		var size := RegionClipboardScript.payload_size(_clipboard)
		info["w"] = size.x
		info["h"] = size.y
		info["units"] = (_clipboard.get("units", []) as Array).size()
		info["props"] = (_clipboard.get("props", []) as Array).size()
		info["overrides"] = (_clipboard.get("tile_overrides", {}) as Dictionary).size()
	return info


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
	_clipboard.clear()  # 跨模型粘贴语义不成立：生成即清剪贴板/取消预览
	_cancel_paste()
	_cancel_place_mode()  # 旧预设引用同样作废：退出放置
	if _move_tool_active:
		_set_move_tool(false)  # 新模型旧选区不成立：收起移动工具
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
	_clipboard.clear()  # 尺寸变化后旧区域可能越界：清剪贴板/取消预览
	_cancel_paste()
	_cancel_place_mode()  # 尺寸变化后放置同样作废：退出
	if _move_tool_active:
		_set_move_tool(false)  # 尺寸变化后旧选区可能越界：收起移动工具


func _refresh_canvas() -> void:
	if _canvas == null:
		return
	_selection_range.clamp_to(model)  # resize/生成后区域端点夹进新边界（无交集=清空）
	_canvas.model = model
	_canvas.queue_redraw()
	_sync_selection_after_model_change()
	_refresh_replace_scope()


func _on_tool_changed() -> void:
	if _place_mode:
		_cancel_place_mode()  # 切工具退出放置模式
	if current_tool != Tool.REPLACE and _replace_picker_dialog != null:
		_replace_picker_dialog.cancel()
	if _replace_popup != null:
		_replace_popup.visible = current_tool == Tool.REPLACE
		if _replace_popup.visible:
			_reset_replace_popup()
	var names := {
		Tool.SELECT: "选择", Tool.PAINT: "画笔", Tool.FILL: "填充", Tool.ERASE: "橡皮",
		Tool.UNIT: "角色", Tool.HEIGHT_UP: "地形上升", Tool.HEIGHT_DOWN: "地形下降",
		Tool.REPLACE: "替换方块", Tool.PICK: "吸管",
	}
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
	var res: Dictionary = MapEditorFileIoScript.load_candidate(path)
	if not bool(res.get("ok", false)):
		var err: String = String(res.get("error", ""))
		if err == "无法打开文件":
			_status("无法打开 %s" % path, true)
		elif err == "JSON 解析失败":
			_status("JSON 解析失败：%s" % path, true)
		else:
			_status("读取失败：%s" % err, true)
		return { "ok": false, "error": err }
	var candidate: Dictionary = res.get("model", {})
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
	_clipboard.clear()  # 跨模型粘贴语义不成立：读取即清剪贴板/取消预览
	_cancel_paste()
	_cancel_place_mode()  # 跨模型粘贴语义不成立：读取退出放置
	if _move_tool_active:
		_set_move_tool(false)  # 新模型旧选区不成立：收起移动工具
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
	MapEditorFileIoScript.sync_user_assets(model, _asset_service)  # 被引用素材描述符快照入档（B2 渲染离线自包含）
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
