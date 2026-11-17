## map_editor_panel_tabs.gd — 地图编辑器右侧面板 8 个 Tab 的内容构建器与按钮工厂
##
## 文件/生成/地形/方块/角色/历史/素材/预设 Tab 页内容 + 地形/植物/阵营/职业按钮工厂 +
## 植物素材目录扫描。Tab 页注册（UIFactory.add_tab）与文件页工厂控件创建留在门面。
## 全部 static，ed=map_editor 实例（动态访问其成员与信号方法）；节点属性与加树顺序
## 与原 map_editor.gd 内联实现逐行一致。

class_name MapEditorPanelTabs
extends RefCounted

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const TilePreviewScript = preload("res://scripts/editor/tile_preview.gd")
const ProfessionDataScript = preload("res://scripts/core/professions.gd")
const ProfessionVisualScript = preload("res://scripts/iso/profession_visual.gd")
const AssetLibraryPanelScript = preload("res://scripts/editor/asset_library_panel.gd")
const EditorBlockListScript = preload("res://scripts/editor/editor_block_list.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const MapEditorUnitsScript = preload("res://scripts/editor/map_editor_units.gd")
const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const PixelHBoxScript = preload("res://ui/components/pixel_h_box.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")

const TEXT_MAIN := UIThemeScript.TEXT_MAIN
const TEXT_DIM := UIThemeScript.TEXT_DIM


## Tab【文件】：id / 名称 / 托管 / 读取 / 保存 / 返回
static func build_file_tab(ed, tab: VBoxContainer) -> void:
	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 4)
	id_row.add_child(UIFactoryScript.label("id:", 11, TEXT_DIM))
	ed._id_edit = UIFactoryScript.line_edit()
	ed._id_edit.text = "custom_map"
	ed._id_edit.placeholder_text = "snake_case"
	ed._id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_row.add_child(ed._id_edit)
	tab.add_child(id_row)
	UIFactoryScript.center_row(id_row)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	name_row.add_child(UIFactoryScript.label("名称:", 11, TEXT_DIM))
	ed._name_edit = UIFactoryScript.line_edit()
	ed._name_edit.text = "自定义战场"
	ed._name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(ed._name_edit)
	tab.add_child(name_row)
	UIFactoryScript.center_row(name_row)

	tab.add_child(ed._hosting_check)

	ed._load_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ed._refresh_load_box()
	tab.add_child(ed._load_box)

	var io_row := HBoxContainer.new()
	io_row.add_theme_constant_override("separation", 4)
	var load_btn := UIFactoryScript.button("读取", ed._load_selected, "folder_open")
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	io_row.add_child(load_btn)
	var save_btn := UIFactoryScript.button("保存", ed._save, "floppy_disk")
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	io_row.add_child(save_btn)
	tab.add_child(io_row)

	var back_btn := UIFactoryScript.button("返回(Esc)", ed._back_to_world, "doorway_exit")
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(back_btn)


## Tab【生成】：种子 / 随机种子 / 宽高 / 生成 / 清空地形
static func build_generate_tab(ed, tab: VBoxContainer) -> void:
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 4)
	seed_row.add_child(UIFactoryScript.label("种子:", 11, TEXT_DIM))
	ed._seed_edit = UIFactoryScript.line_edit()
	ed._seed_edit.text = "demo"
	ed._seed_edit.placeholder_text = "任意文本，同种子同地图"
	ed._seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(ed._seed_edit)
	tab.add_child(seed_row)
	UIFactoryScript.center_row(seed_row)

	var dice_btn := UIFactoryScript.button("随机种子", func():
		ed._seed_edit.text = str(Time.get_unix_time_from_system()).sha1_text().substr(0, 8)
		ed._generate(), "dice")
	dice_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(dice_btn)

	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 4)
	size_row.add_child(UIFactoryScript.label("宽:", 11, TEXT_DIM))
	ed._width_box = SpinBox.new()
	ed._width_box.min_value = BattlefieldDocScript.MIN_SIZE
	ed._width_box.max_value = BattlefieldDocScript.MAX_SIZE
	ed._width_box.value = ed.model.width
	ed._width_box.value_changed.connect(func(_v: float): ed._on_resize())
	ed._width_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(ed._width_box)
	size_row.add_child(UIFactoryScript.label("高:", 11, TEXT_DIM))
	ed._height_box = SpinBox.new()
	ed._height_box.min_value = BattlefieldDocScript.MIN_SIZE
	ed._height_box.max_value = BattlefieldDocScript.MAX_SIZE
	ed._height_box.value = ed.model.height
	ed._height_box.value_changed.connect(func(_v: float): ed._on_resize())
	ed._height_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(ed._height_box)
	tab.add_child(size_row)
	UIFactoryScript.center_row(size_row)

	var gen_row := HBoxContainer.new()
	gen_row.add_theme_constant_override("separation", 4)
	var gen_btn := UIFactoryScript.button("生成", ed._generate, "sprout")
	gen_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen_row.add_child(gen_btn)
	var clear_btn := UIFactoryScript.button("清空地形", func():
		ed._push_undo("清空地形")
		ed.model.rows = BattlefieldDocScript.create_empty(ed.model.width, ed.model.height).rows
		ed.model.props = []  # 植物层一并清空
		ed._refresh_canvas()
		ed._status("地形已清空（单位保留）"), "trash_can")
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen_row.add_child(clear_btn)
	tab.add_child(gen_row)


## 地形组：11 种地形各一个**单块** tile（不叠高塔、不插树）。
## 植物组：枚举 trees/plants/decorations 全部素材（树木/植物/装饰三小节），
## 每张贴图一个独立 tile，选中后画笔在格子上放置该具体植物（模型 props 层）。
## 素材方块组：已保存（✓）的用户地形素材（原方块 Tab 列表融合至此），点选后
## 画笔放置（tile_overrides 层），再点取消。
## 地形/植物按钮共用一个 ButtonGroup（选地形清空 current_prop，选植物反之），
## 与素材方块选中双向互斥。
static func build_terrain_tab(ed, tab: VBoxContainer) -> void:
	ed._terrain_group = ButtonGroup.new()
	var terrain_group: ButtonGroup = ed._terrain_group
	terrain_group.pressed.connect(func(btn: Button):
		if btn.has_meta("terrain"):
			ed.current_terrain = btn.get_meta("terrain")
			ed._set_block_slot("fg", {"kind": "terrain", "id": String(ed.current_terrain), "z": int(ed._block_fg.z)})
			ed.current_prop = ""
			ed._clear_asset_selection()
			ed._clear_block_asset_selection()
		elif btn.has_meta("prop"):
			ed.current_prop = btn.get_meta("prop")
			ed._clear_asset_selection()
			ed._clear_block_asset_selection())
	# ---- 地形组（单块 tile，不叠装饰物/高塔）----
	tab.add_child(UIFactoryScript.label("地形", 12, TEXT_DIM))
	var tgrid := GridContainer.new()
	tgrid.name = "TerrainGrid"
	tgrid.columns = 4
	tgrid.add_theme_constant_override("h_separation", 2)
	tgrid.add_theme_constant_override("v_separation", 2)
	tab.add_child(tgrid)
	for t: StringName in BattlefieldDocScript.TERRAIN_GLYPH:
		var tb := terrain_btn(ed, t, terrain_group)
		tgrid.add_child(tb)
		ed._terrain_buttons[t] = tb
	# ---- 植物组：全部素材按目录分三小节（树木/植物/装饰）----
	for group_title: String in BattlefieldDocScript.PLANT_DIRS:
		tab.add_child(UIFactoryScript.label("%s（%d）" % [group_title, ed._prop_paths[group_title].size()], 12, TEXT_DIM))
		var pgrid := GridContainer.new()
		pgrid.name = "%sGrid" % group_title
		pgrid.columns = 4
		pgrid.add_theme_constant_override("h_separation", 2)
		pgrid.add_theme_constant_override("v_separation", 2)
		tab.add_child(pgrid)
		for path: String in ed._prop_paths[group_title]:
			var pb := plant_btn(ed, path, terrain_group)
			pgrid.add_child(pb)
	# ---- 素材方块组：已保存（✓）的用户地形素材，点选后画笔放置；再点取消 ----
	tab.add_child(UIFactoryScript.label("素材方块（已保存 ✓，点选后用画笔放置；再点取消选中）", 11, TEXT_DIM))
	ed._block_asset_grid = EditorBlockListScript.new()
	ed._block_asset_grid.name = "BlockAssetGrid"
	ed._block_asset_grid.columns = 4
	ed._block_asset_grid.add_theme_constant_override("h_separation", 2)
	ed._block_asset_grid.add_theme_constant_override("v_separation", 2)
	ed._block_asset_grid.block_activated.connect(func(kind: String, id: String):
		if kind == "asset":
			ed._on_block_asset_btn_pressed(id))
	tab.add_child(ed._block_asset_grid)
	ed._block_asset_empty = UIFactoryScript.label(
		"暂无已保存的素材方块\n在「素材」Tab 选中方块后点「保存标记」，保存后会出现在这里", 11, UIThemeScript.TEXT_DIM)
	ed._block_asset_empty.name = "BlockAssetEmptyHint"
	ed._block_asset_empty.visible = false
	tab.add_child(ed._block_asset_empty)
	ed._terrain_buttons[ed.current_terrain].button_pressed = true
	# 初始地形按钮只负责既有默认选中态；前景/背景仍按新契约从 plain z0 起步。
	ed._block_fg = {"kind": "terrain", "id": "plain", "z": 0}
	ed._refresh_block_slot_ui()
	ed._rebuild_block_asset_grid()


## Tab【方块】：编辑当前选格的独立高度（不修改同列/其他格）与前景/背景槽回显；
## 「素材方块」列表已融合进【地形】Tab。
static func build_block_tab(ed, tab: VBoxContainer) -> void:
	tab.add_child(UIFactoryScript.label("用「选择」工具点选格子；拖动其他工具不会改变选择。", 11, TEXT_DIM))
	var row := HBoxContainer.new()
	row.name = "BlockZRow"
	row.add_theme_constant_override("separation", 6)
	row.add_child(UIFactoryScript.label("所在 z:", 12, TEXT_MAIN))
	ed._block_z_box = SpinBox.new()
	ed._block_z_box.name = "BlockZSpin"
	ed._block_z_box.min_value = BattlefieldDocScript.BLOCK_MIN_Z
	ed._block_z_box.max_value = BattlefieldDocScript.BLOCK_MAX_Z
	ed._block_z_box.step = 1
	ed._block_z_box.rounded = true
	ed._block_z_box.editable = false
	ed._block_z_box.tooltip_text = "未选择格子时禁用；范围 0..16"
	ed._block_z_box.value_changed.connect(ed._on_block_z_changed)
	ed._block_z_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ed._block_z_box)
	tab.add_child(row)
	UIFactoryScript.center_row(row)
	var slot_row := HBoxContainer.new()
	slot_row.name = "BlockSlotRow"
	slot_row.add_theme_constant_override("separation", 4)
	ed._fg_swatch = ed._pixel_btn()
	ed._fg_swatch.name = "FgSwatch"
	ed._fg_swatch.disabled = true  # 色块只读展示，不响应点击
	ed._fg_swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_row.add_child(ed._fg_swatch)
	ed._bg_swatch = ed._pixel_btn()
	ed._bg_swatch.name = "BgSwatch"
	ed._bg_swatch.disabled = true
	ed._bg_swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_row.add_child(ed._bg_swatch)
	tab.add_child(slot_row)
	UIFactoryScript.center_row(slot_row)
	ed._refresh_block_slot_ui()
	tab.add_child(UIFactoryScript.label("每格只有一个独立方块；z=0 为统一平面。", 10, TEXT_DIM))


## Tab【角色】：阵营 + 8 职业头像网格 + 等级/姓名
static func build_units_tab(ed, tab: VBoxContainer) -> void:
	ed._unit_info_label = UIFactoryScript.label("", ComponentThemeScript.FONT_CAPTION, TEXT_DIM)
	ed._unit_info_label.name = "UnitInfoLabel"
	ed._unit_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var faction_row := HBoxContainer.new()
	faction_row.add_theme_constant_override("separation", 4)
	var faction_group := ButtonGroup.new()
	faction_group.pressed.connect(func(btn: Button):
		ed.selected_faction = btn.get_meta("faction"))
	for faction: String in ["player", "enemy"]:
		var button := faction_btn(ed, faction, "我方" if faction == "player" else "敌方",
			"shield" if faction == "player" else "skull", faction_group)
		faction_row.add_child(button)
		ed._faction_buttons[faction] = button
	tab.add_child(faction_row)
	tab.add_child(ed._unit_info_label)

	var class_group := ButtonGroup.new()
	class_group.pressed.connect(func(btn: Button):
		ed.selected_class = btn.get_meta("class"))
	var pgrid := GridContainer.new()
	pgrid.name = "PortraitGrid"
	pgrid.columns = 4
	pgrid.add_theme_constant_override("h_separation", 4)
	pgrid.add_theme_constant_override("v_separation", 4)
	tab.add_child(pgrid)
	# 头像网格：8 职业 4×2、48×48（ProfessionVisual.portrait_path，缺图回退职业首字）
	for cid: String in ed.CLASS_IDS:
		var pb := class_btn(ed, cid, class_group)
		pgrid.add_child(pb)
		ed._class_buttons[cid] = pb
	ed._class_buttons[ed.selected_class].button_pressed = true

	var lv_row := HBoxContainer.new()
	lv_row.add_theme_constant_override("separation", 4)
	lv_row.add_child(UIFactoryScript.label("等级:", 11, TEXT_DIM))
	ed._level_box = SpinBox.new()
	ed._level_box.min_value = 1
	ed._level_box.max_value = 9
	ed._level_box.value = 3
	ed._level_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv_row.add_child(ed._level_box)
	lv_row.add_child(UIFactoryScript.label("姓名:", 11, TEXT_DIM))
	ed._unit_name_edit = UIFactoryScript.line_edit()
	ed._unit_name_edit.placeholder_text = "自动"
	ed._unit_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv_row.add_child(ed._unit_name_edit)
	tab.add_child(lv_row)
	UIFactoryScript.center_row(lv_row)
	var actions := PixelHBoxScript.new()
	ed._unit_apply_btn = UIFactoryScript.button("应用修改", func(): MapEditorUnitsScript.apply_changes(ed))
	ed._unit_apply_btn.name = "ApplyUnitBtn"
	ed._unit_apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(ed._unit_apply_btn)
	ed._unit_remove_btn = UIFactoryScript.button("移除角色", func(): MapEditorUnitsScript.remove_selected(ed))
	ed._unit_remove_btn.name = "RemoveUnitBtn"
	ed._unit_remove_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(ed._unit_remove_btn)
	tab.add_child(actions)
	var new_btn := UIFactoryScript.button("新建角色", func(): MapEditorUnitsScript.clear_selection(ed))
	new_btn.name = "NewUnitBtn"
	tab.add_child(new_btn)
	MapEditorUnitsScript.sync_panel(ed)


## Tab【历史】：动作时间线（点击任意记录跳转到该状态）
static func build_history_tab(ed, tab: VBoxContainer) -> void:
	ed._history_list = ItemList.new()
	ed._history_list.name = "HistoryList"
	ed._history_list.custom_minimum_size = Vector2(0, 240)
	ed._history_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ed._history_list.allow_reselect = true
	ed._history_list.item_selected.connect(func(idx: int):
		if not ed._syncing_history:
			ed._jump_history(idx))
	tab.add_child(ed._history_list)
	tab.add_child(UIFactoryScript.label("点击记录跳转到该状态；Ctrl+Z / Ctrl+Y 撤销重做", 10, TEXT_DIM))


## Tab【素材】：用户素材库管理（本地导入/远程清单/编辑 render/隐藏），
## 选中素材后回「地形」页用画笔放置（地块→tile_overrides 层，植物→props 层）。
static func build_asset_tab(ed, tab: VBoxContainer) -> void:
	ed._asset_panel = AssetLibraryPanelScript.new()
	ed._asset_panel.name = "AssetLibraryPanel"
	ed._asset_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ed._asset_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ed._asset_panel.asset_selected.connect(ed._on_asset_selected)
	ed._asset_panel.library_changed.connect(ed._on_asset_library_changed)
	tab.add_child(ed._asset_panel)
	# 素材页禁外层垂直滚动：面板撑满侧栏可用高度，AssetList 拿到全部剩余
	# 高度（列表自身滚动）；其余 Tab 是表单，保留 add_tab 默认滚动行为。
	var scroll := tab.get_parent() as ScrollContainer
	if scroll != null:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ed._asset_panel.setup(ed._asset_service, ed._asset_adapter)


## Tab【预设】：区域预设库（保存当前选区为命名预设；填入选区=选区左上角一步
## 历史回写，放置模式=点击画布以该格为左上角连续放置；均走 region_clipboard
## 五层 payload，预设本体持久化在 region_preset_store）。
## preview_toggle 由编辑器门面先裸构造（CheckButton.new() 留在 map_editor.gd），
## 此处从原逻辑位置继续命名/接线/加树。
static func build_preset_tab(ed, tab: VBoxContainer, preview_toggle: CheckButton) -> void:
	ed._preset_name_edit = UIFactoryScript.line_edit("预设名称")
	ed._preset_name_edit.name = "PresetNameEdit"
	ed._preset_name_edit.text = "预设 %d" % (ed._preset_store.count() + 1)
	tab.add_child(ed._preset_name_edit)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 4)
	var save_btn := UIFactoryScript.button("保存当前选区", ed._on_save_preset_pressed)
	save_btn.name = "SavePresetBtn"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(save_btn)
	tab.add_child(save_row)
	UIFactoryScript.center_row(save_row)

	ed._preset_list = ItemList.new()
	ed._preset_list.name = "PresetList"
	ed._preset_list.custom_minimum_size = Vector2(0, 140)
	ed._preset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(ed._preset_list)

	var op_row := HBoxContainer.new()
	op_row.add_theme_constant_override("separation", 4)
	var fill_btn := UIFactoryScript.button("填入选区", ed._on_fill_preset_pressed)
	fill_btn.name = "FillPresetBtn"
	fill_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	op_row.add_child(fill_btn)
	var place_btn := UIFactoryScript.button("放置模式")
	place_btn.name = "PlacePresetBtn"
	place_btn.toggle_mode = true
	place_btn.toggled.connect(ed._on_place_preset_toggled)
	place_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	op_row.add_child(place_btn)
	ed._place_preset_btn = place_btn
	var rename_btn := UIFactoryScript.button("重命名", ed._on_rename_preset_pressed)
	rename_btn.name = "RenamePresetBtn"
	rename_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	op_row.add_child(rename_btn)
	var delete_btn := UIFactoryScript.button("删除", ed._on_delete_preset_pressed)
	delete_btn.name = "DeletePresetBtn"
	delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	op_row.add_child(delete_btn)
	var refresh_btn := UIFactoryScript.button("刷新", ed._on_refresh_preset_pressed)
	refresh_btn.name = "RefreshPresetBtn"
	refresh_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	op_row.add_child(refresh_btn)
	tab.add_child(op_row)
	UIFactoryScript.center_row(op_row)

	ed._place_preview_toggle = preview_toggle
	ed._place_preview_toggle.name = "PlacePreviewToggle"
	ed._place_preview_toggle.text = "实时放置预览"
	ed._place_preview_toggle.button_pressed = ed._place_preview_enabled
	ed._place_preview_toggle.toggled.connect(ed._on_place_preview_toggled)
	tab.add_child(ed._place_preview_toggle)

	tab.add_child(UIFactoryScript.label("选中区域后可保存为预设；填入选区与放置模式均一步撤销", 10, TEXT_DIM))
	ed._refresh_preset_list()


## 扫描植物素材目录（BattlefieldDoc.PLANT_DIRS）→ { 组名: [res://路径] }（排序）
static func scan_prop_paths() -> Dictionary:
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
static func plant_btn(ed, path: String, group: ButtonGroup) -> Button:
	var tb: Button = ed._pixel_btn()
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


## 阵营切换按钮（盾=我方 / 骷髅=敌方，ButtonGroup 单选；缺图回退纯文字）
static func faction_btn(ed, faction: String, label: String, icon_name: String, group: ButtonGroup) -> Button:
	var b: Button = ed._pixel_btn()
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
	b.button_pressed = faction == ed.selected_faction
	return b


## 调色板按钮：每项一个 tile 缩略图（无文字，悬停提示地形名）。
## plant=true 用独立植物贴图（树单独成块，不叠在方块柱上）。
static func terrain_btn(ed, t: StringName, group: ButtonGroup, plant := false) -> Button:
	var tb: Button = ed._pixel_btn()
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
static func class_btn(ed, cid: String, group: ButtonGroup) -> Button:
	var b: Button = ed._pixel_btn()
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = ed.PORTRAIT_BTN_SIZE
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
		tr.size = ed.PORTRAIT_BTN_SIZE - Vector2(6, 6)
		tr.position = Vector2(3, 3)
	else:
		b.text = cn.substr(0, 1)
		b.add_theme_font_size_override("font_size", 14)
	return b
