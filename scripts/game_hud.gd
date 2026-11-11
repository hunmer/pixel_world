extends CanvasLayer
## 战场选择面板（调试）：列出 data/battlefields/*.json，点选后由 main.gd 以 B2 独立场景加载。
## 左侧竖排图标按钮（战场列表/设置）；操作提示移到右下角；面板不拦截输入。

const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")

## 用户点选了一个战场 JSON（main.gd 接收后 _enter_battlefield）
signal battlefield_picked(path: String)

## 用户请求打开地图编辑器（main.gd 接收后切 MapEditor.tscn）
signal editor_requested()

const HELP_BG := Color(0.035, 0.055, 0.075, 0.90)
const BORDER := Color(0.25, 0.37, 0.43, 0.88)
const TEXT_SECONDARY := Color(0.56, 0.68, 0.71)
const ACCENT := Color(0.40, 0.86, 0.76)
const KEY_COLOR := Color(1.0, 0.78, 0.34)
const ERROR_COLOR := Color(1.0, 0.45, 0.42)

var _bottom_area: VBoxContainer
var _help_flow: HFlowContainer
## 战场选择面板（懒创建；null = 关闭）
var _battlefield_panel: Control = null
var _battlefield_error_label: Label = null


func _ready() -> void:
	layer = 100
	_build_ui()


func _build_ui() -> void:
	var root := Control.new()
	root.name = "HUDRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_bottom_area = VBoxContainer.new()
	_bottom_area.name = "BottomArea"
	_bottom_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_area.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom_area.offset_left = 12.0
	_bottom_area.offset_top = -56.0
	_bottom_area.offset_right = -12.0
	_bottom_area.offset_bottom = -10.0
	root.add_child(_bottom_area)

	var help_panel := PanelContainer.new()
	help_panel.name = "HelpPanel"
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_panel.custom_minimum_size = Vector2(800.0, 32.0)
	help_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	help_panel.add_theme_stylebox_override("panel", _panel_style())
	_bottom_area.add_child(help_panel)

	_help_flow = HFlowContainer.new()
	_help_flow.name = "HelpFlow"
	_help_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_flow.add_theme_constant_override("h_separation", 12)
	_help_flow.add_theme_constant_override("v_separation", 4)
	help_panel.add_child(_help_flow)

	var help_title := _label("操作", 11, ACCENT)
	help_title.name = "HelpTitle"
	_help_flow.add_child(help_title)
	_add_hint("WASD / ↑ ↓", "移动")
	_add_hint("SHIFT", "加速")
	_add_hint("滚轮 / + −", "缩放")
	_add_hint("Q E / ← →", "按住旋转")
	_add_hint("Z / X", "步进 45°")
	_add_hint("中键拖拽", "旋转视角")
	_add_hint("R", "视角复位")
	_add_hint("SPACE+拖拽", "平移地图")
	_add_hint("M", "地图")
	_add_hint("T", "天气")
	_add_hint("N", "昼夜")
	_add_hint("B", "景深")
	_add_hint("SHIFT + T / N", "恢复自动")
	_add_hint("F", "缩放复位")
	_add_hint("CTRL + R", "新世界")
	_add_hint("P", "进入战棋")
	_add_hint("O", "战场列表")
	_add_hint("CTRL + E", "地图编辑器")

	# 左侧竖排图标按钮栏：战场列表 + 设置（无文字，悬停显示提示）
	var left_bar := VBoxContainer.new()
	left_bar.name = "LeftBar"
	left_bar.position = Vector2(10.0, 10.0)
	left_bar.add_theme_constant_override("separation", 8)
	root.add_child(left_bar)

	# 「战场」按钮（JSON 战场加载列表，调试入口）
	var battlefield_btn := Button.new()
	battlefield_btn.name = "BattlefieldBtn"
	battlefield_btn.text = "⚔"
	battlefield_btn.tooltip_text = "战场列表（O）"
	battlefield_btn.custom_minimum_size = Vector2(42.0, 42.0)
	battlefield_btn.add_theme_font_size_override("font_size", 18)
	battlefield_btn.pressed.connect(toggle_battlefield_panel)
	left_bar.add_child(battlefield_btn)

	# 「设置」按钮
	var settings_btn := Button.new()
	settings_btn.name = "SettingsBtn"
	settings_btn.text = "⚙"
	settings_btn.tooltip_text = "设置"
	settings_btn.custom_minimum_size = Vector2(42.0, 42.0)
	settings_btn.add_theme_font_size_override("font_size", 18)
	settings_btn.pressed.connect(_open_settings)
	left_bar.add_child(settings_btn)


## 设置面板：战斗模式切换（就地/独立场景）
func _open_settings() -> void:
	# 如果已打开，先移除
	var old := get_node_or_null("HUDRoot/SettingsPanel")
	if old != null:
		old.queue_free()
		return
	var vp := get_viewport().get_visible_rect().size
	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.custom_minimum_size = Vector2(280, 120)
	panel.position = (vp - panel.custom_minimum_size) / 2.0
	panel.add_theme_stylebox_override("panel", _panel_style())
	$"HUDRoot".add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.offset_left = 12; vbox.offset_top = 8
	vbox.offset_right = -12; vbox.offset_bottom = -8
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	# 标题
	var title := _label("设置", 14, ACCENT)
	vbox.add_child(title)
	# 战斗模式选项
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	var lbl := _label("战斗模式", 12, TEXT_SECONDARY)
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.add_item("就地（B1）", 0)
	opt.add_item("独立场景（B2）", 1)
	opt.select(0 if Settings.battle_inline_mode else 1)
	opt.custom_minimum_size = Vector2(140, 0)
	opt.item_selected.connect(func(idx: int):
		Settings.set_battle_inline_mode(idx == 0)
	)
	row.add_child(opt)
	# 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(func():
		var p := get_node_or_null("HUDRoot/SettingsPanel")
		if p != null: p.queue_free()
	)
	vbox.add_child(close_btn)


## ---- 战场选择面板（JSON 战场加载列表，调试入口） --------------------------

## 打开/关闭战场面板（O 键 / ⚔ 按钮共用）
func toggle_battlefield_panel() -> void:
	if _battlefield_panel != null and is_instance_valid(_battlefield_panel):
		close_battlefield_panel()
	else:
		_open_battlefield_panel()


func close_battlefield_panel() -> void:
	if _battlefield_panel != null and is_instance_valid(_battlefield_panel):
		_battlefield_panel.queue_free()
	_battlefield_panel = null
	_battlefield_error_label = null


## 面板打开时 ESC 关闭（O 键由 main.gd 分发，避免与主输入链抢事件）
func _unhandled_input(event: InputEvent) -> void:
	if _battlefield_panel == null or not is_instance_valid(_battlefield_panel):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
			close_battlefield_panel()
			get_viewport().set_input_as_handled()


func _open_battlefield_panel() -> void:
	close_battlefield_panel()
	var vp := get_viewport().get_visible_rect().size
	var panel := PanelContainer.new()
	panel.name = "BattlefieldPanel"
	panel.custom_minimum_size = Vector2(500.0, 0.0)
	panel.position = Vector2((vp.x - 500.0) / 2.0, 90.0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	$"HUDRoot".add_child(panel)
	_battlefield_panel = panel

	var vbox := VBoxContainer.new()
	vbox.name = "BattlefieldVBox"
	vbox.offset_left = 14.0
	vbox.offset_top = 10.0
	vbox.offset_right = -14.0
	vbox.offset_bottom = -10.0
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# 标题行：标题 + 关闭按钮
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vbox.add_child(head)
	var title := _label("加载战场（JSON）", 14, ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕ 关闭"
	close_btn.pressed.connect(close_battlefield_panel)
	head.add_child(close_btn)

	var subtitle := _label("data/battlefields/*.json · 独立场景模式 · O/ESC 关闭", 10, TEXT_SECONDARY)
	vbox.add_child(subtitle)

	# 可滚动列表
	var scroll := ScrollContainer.new()
	scroll.name = "BattlefieldScroll"
	scroll.custom_minimum_size = Vector2(0.0, 300.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "BattlefieldList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	# 错误提示行（加载失败时由 main.gd 回填）
	_battlefield_error_label = _label("", 11, ERROR_COLOR)
	_battlefield_error_label.visible = false
	vbox.add_child(_battlefield_error_label)

	# 编辑器入口：打开战场地图编辑器（种子生成地形 / 涂地形 / 放阵营角色，保存即出现在本列表）
	var editor_btn := Button.new()
	editor_btn.name = "OpenEditorBtn"
	editor_btn.text = "🛠 打开地图编辑器"
	editor_btn.add_theme_font_size_override("font_size", 12)
	editor_btn.pressed.connect(func(): editor_requested.emit())
	vbox.add_child(editor_btn)

	# 填充列表（L1 埋点：面板打开时打印条目数，方便确认扫描正常）
	var battlefields: Array = BattlefieldLoaderScript.list_battlefields()
	print("[hud] 战场列表打开：data/battlefields/ 共 %d 个" % battlefields.size())
	if battlefields.is_empty():
		list.add_child(_label("（data/battlefields/ 下没有 *.json）", 11, TEXT_SECONDARY))
		return
	for entry in battlefields:
		list.add_child(_make_battlefield_entry(entry))


## 单个战场条目：按钮（名称 + 规模）+ 描述行；解析失败的条目置灰
func _make_battlefield_entry(entry: Dictionary) -> Control:
	var item := VBoxContainer.new()
	item.add_theme_constant_override("separation", 1)

	var btn := Button.new()
	btn.text = "%s   （%d×%d · 我方%d/敌方%d）" % [
		entry.get("name", ""), entry.get("width", 0), entry.get("height", 0),
		entry.get("players", 0), entry.get("enemies", 0),
	]
	btn.add_theme_font_size_override("font_size", 13)
	var err := String(entry.get("error", ""))
	var path := String(entry.get("path", ""))
	if not err.is_empty():
		btn.disabled = true
	else:
		btn.pressed.connect(func():
			# 不主动关面板：成功时切场景整个 HUD 会被释放，失败时留面板显示错误
			battlefield_picked.emit(path)
		)
	item.add_child(btn)

	var desc := String(entry.get("description", ""))
	if not err.is_empty():
		desc = "⚠ " + err
	if not desc.is_empty():
		item.add_child(_label("    " + desc, 10, ERROR_COLOR if not err.is_empty() else TEXT_SECONDARY))
	return item


## 加载失败时在面板上回显错误（main.gd 调用）
func show_battlefield_error(message: String) -> void:
	if _battlefield_error_label == null or not is_instance_valid(_battlefield_error_label):
		return
	_battlefield_error_label.text = "加载失败：" + message
	_battlefield_error_label.visible = true


func _add_hint(key_text: String, action_text: String) -> void:
	var group := HBoxContainer.new()
	group.name = "Hint%d" % _help_flow.get_child_count()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override("separation", 5)
	_help_flow.add_child(group)

	var key_panel := PanelContainer.new()
	key_panel.name = "Keycap"
	key_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_panel.add_theme_stylebox_override("panel", _keycap_style())
	group.add_child(key_panel)
	var key_label := _label(key_text, 10, KEY_COLOR)
	key_label.name = "Key"
	key_panel.add_child(key_label)

	var action_label := _label(action_text, 11, TEXT_SECONDARY)
	action_label.name = "Action"
	group.add_child(action_label)


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text_value
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	result.add_theme_constant_override("shadow_offset_x", 1)
	result.add_theme_constant_override("shadow_offset_y", 1)
	return result


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = HELP_BG
	style.border_color = BORDER
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 7.0
	style.content_margin_top = 3.0
	style.content_margin_right = 7.0
	style.content_margin_bottom = 3.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0.0, 2.0)
	return style


func _keycap_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.095, 0.075, 0.96)
	style.border_color = KEY_COLOR
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 4.0
	style.content_margin_top = 2.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 2.0
	return style
