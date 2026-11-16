## map_editor_overlays.gd — 地图编辑器画布悬浮层与替换/选择弹窗构建器
##
## 左上工具条 / 条件替换弹窗 / 画布底部最近吸取横条 / 左下格子信息条 /
## 选择模式弹窗 /
## 区域端点行 + 替换候选项枚举与编码解析。全部 static，ed=map_editor 实例；
## 节点属性与加树顺序与原 map_editor.gd 内联实现逐行一致。
## 按钮一律经 UIFactory.button 创建（PixelButton 组件、音效已关；
## 工具条/键帽条等走 styled=false 保持组件主题原观感）；
## OptionButton 等其余控件按 §2.2 决策留在门面，经参数传入。

class_name MapEditorOverlays
extends RefCounted

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const BlockSelectorScript = preload("res://scripts/editor/block_selector.gd")
const EditorBlockPickerDialogScript = preload("res://scripts/editor/editor_block_picker_dialog.gd")
const UserAssetCatalogScript = preload("res://scripts/assets/user_asset_catalog.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")

const TEXT_MAIN := UIThemeScript.TEXT_MAIN
const TEXT_DIM := UIThemeScript.TEXT_DIM
const ACCENT := UIThemeScript.ACCENT


## 左上角悬浮工具条：选择 / 画笔 / 填充 / 橡皮 / 高度升降 / 角色（覆盖在画布上）
static func build_tool_bar(ed) -> Control:
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
		ed.current_tool = btn.get_meta("tool")
		ed._on_tool_changed()
		if ed.current_tool == ed.Tool.SELECT or ed.current_tool == ed.Tool.FILL:
			ed._open_selection_popup())
	add_tool_btn(ed, box, tool_group, ed.Tool.SELECT, "选择", "mouse_pointer")
	add_tool_btn(ed, box, tool_group, ed.Tool.PAINT, "画笔", "paintbrush")
	add_tool_btn(ed, box, tool_group, ed.Tool.FILL, "填充", "bucket_fill")
	add_tool_btn(ed, box, tool_group, ed.Tool.ERASE, "橡皮", "eraser")
	add_tool_btn(ed, box, tool_group, ed.Tool.HEIGHT_UP, "地形上升", "arrow_up_from_line")
	add_tool_btn(ed, box, tool_group, ed.Tool.HEIGHT_DOWN, "地形下降", "arrow_down_from_line")
	add_tool_btn(ed, box, tool_group, ed.Tool.UNIT, "角色", "person")
	ed._tool_buttons[ed.Tool.PAINT].button_pressed = true
	# 移动工具开关：ToolBox 第 8 钮（用户已取消 7 钮契约）。独立开关，
	# 不入 tool_group（不与 7 个画布工具互斥，可任意工具下叠加开启）
	var move_toggle: Button = UIFactoryScript.button("", Callable(), "", false)
	move_toggle.name = "MoveToolToggle"
	move_toggle.toggle_mode = true
	var move_icon: Texture2D = UIThemeScript.icon("move")
	if move_icon != null:
		# 与上方 7 钮同观感：方形图标按钮（tooltip 提示用途）
		move_toggle.icon = move_icon
		move_toggle.set("icon_size", 22)
		move_toggle.text = ""
		move_toggle.custom_minimum_size = Vector2(34, 34)
		move_toggle.expand_icon = true
	else:
		move_toggle.text = "移动"
	move_toggle.tooltip_text = "移动工具：拖拽移动选中区域"
	move_toggle.focus_mode = Control.FOCUS_NONE
	move_toggle.toggled.connect(ed._on_move_tool_toggled)
	box.add_child(move_toggle)
	ed._move_tool_toggle = move_toggle
	# 替换方块：ToolBox 第 9 钮，保持在移动开关之后以稳定既有按钮索引。
	add_tool_btn(ed, box, tool_group, ed.Tool.REPLACE, "替换方块", "replace")
	var replace_btn := ed._tool_buttons[ed.Tool.REPLACE] as Button
	replace_btn.name = "ReplaceToolBtn"
	replace_btn.custom_minimum_size = Vector2(34, 34)
	if replace_btn.icon == null:
		replace_btn.text = "替"
		replace_btn.tooltip_text = "替换方块工具"
	# 吸管：ToolBox 第 10 钮；点击写前景，Alt+点击写背景，不产生文档历史。
	add_tool_btn(ed, box, tool_group, ed.Tool.PICK, "吸管", "pipette")
	var pick_btn := ed._tool_buttons[ed.Tool.PICK] as Button
	pick_btn.name = "PickToolBtn"
	pick_btn.custom_minimum_size = Vector2(34, 34)
	pick_btn.tooltip_text = "吸管：点击吸取前景，Alt+点击吸取背景；其它工具按住 Alt 临时吸取，Shift+点击取背景"
	if pick_btn.icon == null:
		pick_btn.text = "吸"
	return bar


## 条件替换弹窗：双下拉编码 terrain:<glyph> / asset:<id>；只有执行按钮写模型。
## 三个 UIFactoryScript.button 由门面预建（ed._replace_source_opt 等），此处只接线加树。
static func build_replace_popup(ed) -> void:
	var popup := PanelContainer.new()
	popup.name = "ReplacePopup"
	popup.visible = false
	popup.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	popup.offset_left = 52
	popup.offset_top = 8
	popup.offset_right = 352
	popup.offset_bottom = 310
	popup.add_theme_stylebox_override("panel", UIThemeScript.overlay_panel_style())
	ed._replace_popup = popup
	ed.add_child(popup)
	var box := VBoxContainer.new()
	box.name = "ReplacePopupBox"
	box.add_theme_constant_override("separation", 6)
	popup.add_child(box)
	box.add_child(UIFactoryScript.label("替换方块", 13, ACCENT))
	box.add_child(UIFactoryScript.label("被替换方块", 10, TEXT_DIM))
	ed._replace_source_opt.name = "ReplaceSourceOpt"
	ed._replace_source_opt.custom_minimum_size = Vector2(0, 40)
	ed._replace_source_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(ed._replace_source_opt)
	box.add_child(UIFactoryScript.label("替换为", 10, TEXT_DIM))
	ed._replace_dest_opt.name = "ReplaceDestOpt"
	ed._replace_dest_opt.custom_minimum_size = Vector2(0, 40)
	ed._replace_dest_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(ed._replace_dest_opt)
	ed._replace_scope_label = UIFactoryScript.label("当前范围：全图 0 格", 11, TEXT_MAIN)
	ed._replace_scope_label.name = "ReplaceScopeLabel"
	box.add_child(ed._replace_scope_label)
	ed._replace_apply_btn.name = "ReplaceApplyBtn"
	ed._replace_apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(ed._replace_apply_btn)
	ed._replace_hint = UIFactoryScript.label("点地图格子可快速设为被替换方块", 10, TEXT_DIM)
	ed._replace_hint.name = "ReplaceHint"
	ed._replace_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(ed._replace_hint)
	ed._replace_picker_dialog = EditorBlockPickerDialogScript.new()
	ed._replace_picker_dialog.name = "ReplaceBlockPicker"
	ed._replace_picker_dialog.visible = false
	ed.add_child(ed._replace_picker_dialog)
	ed._replace_picker_dialog.block_chosen.connect(ed._on_replace_picker_chosen)
	replace_populate_options(ed)
	ed._select_replace_option(ed._replace_source_opt, "terrain:.")
	ed._select_replace_option(ed._replace_dest_opt, ed._replace_code_for_block(ed._block_fg))
	ed._refresh_replace_scope()


## 画布底部最近吸取横条：独立于右侧 SidePanel，最多 8 个 40px 方块按钮（最新在左）；
## 标题常驻左端。右端让出 EditorHintBar（右下角图标），上方让出 CellInfoPanel。
## 8×40 + 标题 ≈ 460px，在最小画布（648px）内完整容纳，不需要滚动
## （DESIGN.md 禁横向滚动，两个滚动轴均禁用）。
static func build_recent_picks_bar(ed, holder: Control) -> void:
	var bar := PanelContainer.new()
	bar.name = "RecentPicksBar"
	bar.anchor_left = 0.0
	bar.anchor_top = 1.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 8
	bar.offset_top = -96
	bar.offset_right = -52
	bar.offset_bottom = -44
	bar.add_theme_stylebox_override("panel", UIThemeScript.overlay_panel_style())
	holder.add_child(bar)
	ed._recent_picks_bar = bar
	var row := HBoxContainer.new()
	row.name = "RecentPicksHBox"
	row.add_theme_constant_override("separation", 4)
	bar.add_child(row)
	var title := UIFactoryScript.label("最近吸取", 12, ACCENT)
	title.name = "RecentPicksTitle"
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "RecentPickScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(scroll)
	ed._recent_pick_list = HBoxContainer.new()
	ed._recent_pick_list.name = "RecentPickList"
	ed._recent_pick_list.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ed._recent_pick_list.add_theme_constant_override("separation", 2)
	scroll.add_child(ed._recent_pick_list)
	ed._refresh_recent_picks()


## 候选与方块选择器一致：全部内置地形 + 素材库中 kind=terrain 且 saved=true 的素材。
static func replace_populate_options(ed) -> void:
	if ed._replace_source_opt == null or ed._replace_dest_opt == null:
		return
	var source_code: String = ed._replace_source_code()
	var dest_code: String = ed._replace_dest_code()
	ed._replace_items.clear()
	for terrain: StringName in BattlefieldDocScript.TERRAIN_GLYPH:
		var label := "地形 · %s" % String(BattlefieldDocScript.TERRAIN_CN.get(terrain, String(terrain)))
		var code := "terrain:%s" % String(BattlefieldDocScript.TERRAIN_GLYPH[terrain])
		ed._replace_items.append(replace_item_for_code(ed, code, label))
	if ed._asset_service != null:
		var assets: Array = ed._asset_service.list_assets()
		assets.sort_custom(func(a, b):
			return String((a as Dictionary).get("id", "")) < String((b as Dictionary).get("id", "")))
		for raw in assets:
			var d := raw as Dictionary
			if String(d.get("kind", "")) != UserAssetCatalogScript.KIND_TERRAIN \
					or not bool(d.get("saved", false)):
				continue
			var aid := String(d.get("id", ""))
			ed._replace_items.append(replace_item_for_code(ed, "asset:%s" % aid,
				"素材 · %s" % String(d.get("name", aid))))
	ed._select_replace_option(ed._replace_source_opt, source_code)
	ed._select_replace_option(ed._replace_dest_opt, dest_code)


static func replace_item_for_code(ed, code: String, label: String = "") -> Dictionary:
	var kind := "asset" if code.begins_with("asset:") else "terrain"
	var id := code.substr(6) if kind == "asset" else code.substr(8)
	if label.is_empty():
		label = ("素材 · %s" % id) if kind == "asset" else "地形 · %s" % id
	var texture: Texture2D = null
	if kind == "asset":
		texture = ed._recent_pick_texture({"kind": "asset", "id": id, "z": 0})
	else:
		var terrain := BattlefieldDocScript.glyph_to_terrain(id)
		texture = ed._recent_pick_texture({"kind": "terrain", "id": String(terrain), "z": 0})
	return {"kind": kind, "id": id, "label": label, "texture": texture}


## 左下角格子信息条（只读，鼠标穿透）
static func build_cell_info(ed) -> Control:
	var panel := PanelContainer.new()
	panel.name = "CellInfoPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 8
	panel.offset_top = -38
	panel.offset_right = 250
	panel.offset_bottom = -8
	panel.add_theme_stylebox_override("panel", UIThemeScript.overlay_panel_style())
	ed._cell_info_label = UIFactoryScript.label("未选中格子", 11, TEXT_MAIN)
	ed._cell_info_label.name = "CellInfoLabel"
	ed._cell_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(ed._cell_info_label)
	return panel


## 工具条按钮（toggle + ButtonGroup；有图标只显图标，无图标回退文字；
## 工厂默认叠 style_button，等价原先建后手动 UIThemeScript.style_button）
static func add_tool_btn(ed, parent: Node, group: ButtonGroup, tool: int, text: String, icon_name := "") -> void:
	var b: Button = UIFactoryScript.button()
	b.toggle_mode = true
	b.button_group = group
	var icon: Texture2D = null
	if icon_name != "":
		icon = UIThemeScript.icon(icon_name)
	if icon != null:
		# 垂直工具条：只显示图标（tooltip 提示名称），固定方形按钮。
		# icon_size=22 对齐 34×34 按钮内容区（34-2×6），保住 expand_icon 原观感
		# （组件默认 icon_max_width=18 会把放大后的图标截小）；b 静态类型是
		# Button，组件属性经 set() 走 PixelButton setter（触发 _refresh 生效）。
		b.icon = icon
		b.set("icon_size", 22)
		b.text = ""
		b.tooltip_text = "%s工具" % text
		b.custom_minimum_size = Vector2(34, 34)
		b.expand_icon = true
	else:
		b.text = text
		b.tooltip_text = text
	b.set_meta("tool", tool)
	parent.add_child(b)
	ed._tool_buttons[tool] = b


## 选择模式弹窗（点「选择」/「填充」图标打开，Esc 关闭）：模式切换 + pos1/pos2
## 坐标编辑 + 通用方块选择器 + 区域填充/清除按钮。默认隐藏。
## OptionButton 由门面裸构造（SITE 决策），经 mode_option 参数传入。
static func build_selection_popup(ed, mode_option: OptionButton) -> void:
	var popup := PanelContainer.new()
	popup.name = "SelectionPopup"
	popup.visible = false
	popup.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	popup.offset_left = 52
	popup.offset_top = 8
	popup.offset_right = 332
	popup.offset_bottom = 460
	popup.add_theme_stylebox_override("panel", UIThemeScript.overlay_panel_style())
	ed._selection_popup = popup
	ed.add_child(popup)

	var box := VBoxContainer.new()
	box.name = "SelectionPopupBox"
	box.add_theme_constant_override("separation", 6)
	popup.add_child(box)

	box.add_child(UIFactoryScript.label("选择模式", 13, ACCENT))
	ed._mode_option = mode_option
	ed._mode_option.name = "ModeOption"
	ed._mode_option.add_item("单格选择", 0)
	ed._mode_option.add_item("区域选择", 1)
	ed._mode_option.item_selected.connect(ed._on_selection_mode_item)
	box.add_child(ed._mode_option)

	box.add_child(UIFactoryScript.label("区域端点（点击画布设置，可再精修）", 10, TEXT_DIM))
	box.add_child(build_region_endpoint_row(ed, "pos1", ed._pos1_boxes))
	box.add_child(build_region_endpoint_row(ed, "pos2", ed._pos2_boxes))

	box.add_child(UIFactoryScript.label("填充内容（内置地形 / 已保存素材方块）", 10, TEXT_DIM))
	ed._fill_selector = BlockSelectorScript.new()
	ed._fill_selector.name = "FillBlockSelector"
	ed._fill_selector.custom_minimum_size = Vector2(0, 140)
	ed._fill_selector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ed._fill_selector.setup(ed._asset_service, ed._asset_adapter)
	ed._fill_selector.selection_changed.connect(func(kind: StringName, id: String):
		if id.is_empty():
			return
		ed._set_block_slot("fg", {"kind": String(kind), "id": id, "z": int(ed._block_fg.z)}))
	box.add_child(ed._fill_selector)

	var btns := HBoxContainer.new()
	btns.name = "RegionBtnRow"
	btns.add_theme_constant_override("separation", 4)
	var fill_btn: Button = UIFactoryScript.button("填充区域", ed._on_region_fill_pressed)
	fill_btn.name = "RegionFillBtn"
	btns.add_child(fill_btn)
	var clear_btn: Button = UIFactoryScript.button("清除区域", ed._on_region_clear_pressed)
	clear_btn.name = "RegionClearBtn"
	btns.add_child(clear_btn)
	var close_btn: Button = UIFactoryScript.button("关闭", ed._close_selection_popup)
	close_btn.name = "CloseBtn"
	btns.add_child(close_btn)
	box.add_child(btns)

	# ---- 区域操作：复制/剪切/粘贴（Ctrl+C/X/V 同款；区域内按下拖动=移动）----
	var ops := HBoxContainer.new()
	ops.name = "RegionOpRow"
	ops.add_theme_constant_override("separation", 4)
	var copy_btn: Button = UIFactoryScript.button("复制区域", ed._on_region_copy_pressed)
	copy_btn.name = "CopyRegionBtn"
	ops.add_child(copy_btn)
	var cut_btn: Button = UIFactoryScript.button("剪切区域", ed._on_region_cut_pressed)
	cut_btn.name = "CutRegionBtn"
	ops.add_child(cut_btn)
	var paste_btn: Button = UIFactoryScript.button("粘贴区域", ed._on_region_paste_pressed)
	paste_btn.name = "PasteRegionBtn"
	ops.add_child(paste_btn)
	box.add_child(ops)
	var op_hint := UIFactoryScript.label("CTRL+C/X/V 复制/剪切/粘贴 · 区域内拖动=移动 · ESC 取消", 9, TEXT_DIM)
	op_hint.name = "RegionOpHint"
	op_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(op_hint)


## pos1/pos2 行：标签 + x/y/z 三个 SpinBox（名称 Pos1X 等，坐标 UI 契约用）
static func build_region_endpoint_row(ed, which: String, store: Dictionary) -> HBoxContainer:
	var tag: String = which.replace("pos", "Pos")
	var row := HBoxContainer.new()
	row.name = "%sRow" % tag
	row.add_theme_constant_override("separation", 4)
	row.add_child(UIFactoryScript.label(which, 10, TEXT_DIM))
	for axis in [&"x", &"y", &"z"]:
		var sp := SpinBox.new()
		sp.name = "%s%s" % [tag, String(axis).to_upper()]
		sp.min_value = BattlefieldDocScript.BLOCK_MIN_Z if axis == &"z" else 0
		sp.max_value = BattlefieldDocScript.BLOCK_MAX_Z if axis == &"z" else 999
		sp.step = 1
		sp.rounded = true
		sp.value_changed.connect(ed._on_region_box_changed.bind(which, axis))
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		store[axis] = sp
		row.add_child(sp)
	return row


## 右下角 34×30 键盘图标；节点名保留 EditorHintBar，点击打开完整键帽弹窗。
## 原直建控件已收敛至 UIFactory.button(styled=false)（PixelButton 组件、
## 音效已关、不叠 style_button override 保持组件主题）——属性与加树顺序
## 与原实现逐行一致。
static func build_hint_bar(ed) -> Button:
	var button: Button = UIFactoryScript.button("", Callable(), "", false)
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
		if ed._shortcut_hints_dialog != null:
			ed._shortcut_hints_dialog.open(ed.HINT_ITEMS))
	return button
