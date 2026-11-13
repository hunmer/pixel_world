## battle/battle_ui.gd — 战场屏幕空间 UI（从 scenes/battle.gd 抽出）
##
## 职责：
##   - HUD 构建：右侧固定宽多 Tab 侧边栏（map_editor 风格，Tab=回合/情报/托管/日志）
##     —— 回合标签 / 阵营状态 / 结束回合按钮 / 悬停信息 / 托管与偏好 / 退出战斗
##     / 引擎日志（接管 Panku native_logger，浮层不再挂页面左侧）
##   - 单位信息悬浮显示（show_info_at → 侧栏【情报】Tab）
##   - 单位行动菜单（攻击/技能/物品/等待）+ 各级目标选择 picker
##   - 战斗预览面板 / 技能预览面板（贴侧栏左侧，避开右侧栏）
##   - 开战名牌/Boss 横幅与胜利/失败/章节末结算演出（ResultPresentation）
##   - 结果横幅（旧 show_result_banner 兼容入口）
##   - 侧栏/tab 深色样式辅助 + 通用面板样式 _make_panel_style
##
## 设计：从 battle.gd 抽出的 CanvasLayer（屏幕空间 UI 根）。不持有父场景引用；
## board / grid / unit_sprites / turn 由 battle.gd 在 setup() 注入；
## 战斗演出 / 状态机修改（mode / selected_unit / _pending_move_undo / hasActed）/
## 胜负判定 / 取消移动 / 选中单位 / 结束行动收尾 全部通过 Callable 回交 battle.gd，
## 保持状态机核心不外移。
##
## 公开 API（battle.gd 调用）：
##   setup(board, grid, unit_sprites, turn)
##   build(end_turn_cb, toggle_hosting_cb, open_pref_cb)
##   show_info_at(x, y)
##   open_unit_menu(u, at_pos, from_pos)
##   is_over_ui(screen_pos) -> bool
##   set_phase_text(text, color)
##   disable_end_turn(disabled)
##   show_result_banner(text, color)  # 旧入口；新演出用 play_result
##   play_opening(units, boss = {})
##   play_result(result, data = {}, survivors = [], defeated = [])
##   play_chapter_result(data = {}, survivors = [])
##   skip_presentation()
##   is_presentation_active() -> bool
##   update_unit_sprite(u)            # 菜单里改了单位状态后刷新对应 sprite
##   has_open_menu() -> bool          # 输入路径判断菜单是否打开
##
## Callable 注入面（battle.gd setup 后赋值）：
##   on_resolve_combat(attacker, defender, on_done_cb)
##   on_resolve_skill(caster, targets, skill_id)
##   on_resolve_item(user, targets, entry)
##   on_finish_player_action(u)
##   on_clear_selection()
##   on_clear_pending_move_undo()
##   on_cancel_move()
##   on_select_unit(u)
##   on_set_mode(m: int)
##   on_check_battle_end()
##   on_should_end_turn_after_action()  # turn.phase==player && all_player_acted() 时 end_turn
class_name BattleUI
extends CanvasLayer

const ResultPresentationScript = preload("res://scripts/battle/result_presentation.gd")
# 用预加载脚本作类型，避免干净 headless 尚未生成 global class cache 时无法解析。

## 开战/结算演出事件；场景集成者连接这些信号驱动音效与单位视觉钩子。
signal nameplate_shown(unit: Dictionary, index: int)
signal boss_banner_shown(unit: Dictionary)
signal loot_shown(entry: Dictionary, index: int)
signal cheer_requested(unit: Dictionary)
signal collapse_requested(unit: Dictionary)
signal presentation_sound_requested(cue: StringName)
signal opening_finished(skipped: bool)
signal result_finished(result: StringName, skipped: bool)
signal presentation_finished(kind: StringName, skipped: bool)

# ---- 注入的只读引用 ----
var board: IsoBoard
## 可选：柱顶高度函数（BattlefieldRenderer.visual_top_level，B2 等距方块模式注入）
var level_fn: Callable = Callable()
## B1/B2 统一注入 cell → 屏幕坐标，避免 B1 没有 IsoBoard 时菜单定位中断。
var cell_screen_fn: Callable = Callable()
var grid: GridSystem
var unit_sprites: Dictionary
var turn: TurnManager

# ---- Callable 注入面 ----
var on_resolve_combat: Callable
var on_resolve_skill: Callable
var on_resolve_item: Callable
var on_finish_player_action: Callable
var on_clear_selection: Callable
var on_clear_pending_move_undo: Callable
var on_cancel_move: Callable
var on_select_unit: Callable
var on_set_mode: Callable
var on_check_battle_end: Callable
var on_should_end_turn_after_action: Callable

# ---- 控件 ----
var phase_label: Label
var end_turn_btn: Button
var info_label: Label
var menu_container: Control
var preview_container: Control
var _turn_status_labels: Dictionary = {}
var _turn_status_signature := ""
var result_presentation: ResultPresentationScript
# 单位详情面板（右键查看任意单位完整信息；与行动菜单 menu_container 独立）
var _unit_detail_panel: Control = null
# 右侧多 Tab 侧栏（map_editor 风格）
var _sidebar: PanelContainer = null
# 【托管】Tab 内容盒（退出战斗按钮按需追加到这里）
var _host_tab: VBoxContainer = null
# 【日志】Tab：接管 Panku native_logger（B2 从 Game.tscn 进来时没有世界 side_panel，
# 不接管的话 Panku 屏幕日志浮层会挂在页面左侧；逻辑照搬 side_panel.gd）
var _log_label: RichTextLabel = null
var _pending_log_bbcode := ""
var _log_update_pending := false
## PankuModuleNativeLogger 实例（duck-typed；Panku 不在时保持 null）
var _logger_module = null

# ---- 侧边栏样式（照搬 map_editor.gd 配色，与世界 side_panel.gd 同系） ----
## 侧栏宽度：与世界 side_panel.PANEL_WIDTH 对齐 —— B1 就地模式下世界相机已按
## 该宽度预留右侧取景（main.gd: _cam.reserved_right_px = GameHud.SIDE_PANEL_WIDTH），
## 战斗侧栏同宽覆盖世界侧栏，取景刚好对齐；B2 由 battle.gd 设置 reserved_right_px。
const SIDEBAR_WIDTH := 360.0
const ICON_DIR := "res://addons/at-icons/control/"
const BG := Color(0.05, 0.07, 0.10, 0.97)
const PANEL_BORDER := Color(0.25, 0.37, 0.43, 0.9)
const TEXT_MAIN := Color(0.88, 0.93, 0.95)
const TEXT_DIM := Color(0.56, 0.68, 0.71)
const ACCENT := Color(0.40, 0.86, 0.76)
# 统一样式系统：按钮三态底色，pressed 描边统一走 ACCENT
const BTN_BG := Color(0.08, 0.11, 0.14, 0.95)
const BTN_BG_HOVER := Color(0.13, 0.18, 0.22, 0.98)
const BTN_BG_PRESSED := Color(0.10, 0.26, 0.23, 1.0)

# battle.gd 的 Mode 枚举镜像（on_set_mode 传 int；与 battle.gd enum Mode 保持一致）
const MODE_IDLE := 0
const MODE_MENU := 3
# 阵营 → 显示名 / 颜色（与 unit_sprite.gd 保持一致，详情面板标题用）
const FACTION_NAME := {
	player = "我方",
	enemy = "敌方",
	ally = "友军",
	other = "中立",
}
const FACTION_COLOR := {
	player = Color(0.376, 0.647, 0.980),
	enemy = Color(0.973, 0.443, 0.443),
	ally = Color(0.290, 0.867, 0.502),
	other = Color(0.984, 0.749, 0.141),
}


func setup(p_board: IsoBoard, p_grid: GridSystem, p_unit_sprites: Dictionary, p_turn: TurnManager) -> void:
	board = p_board
	grid = p_grid
	unit_sprites = p_unit_sprites
	turn = p_turn


func _process(_delta: float) -> void:
	# 战斗、技能、物品和AI都可能改HP/行动状态；以签名检测统一刷新，避免遗漏调用链。
	refresh_turn_status()
	# 日志镜像：拖选期间挂起，选区清除后再落盘（同 side_panel.gd）。
	if _log_update_pending and not _log_selection_active():
		if is_instance_valid(_log_label):
			_log_label.text = _pending_log_bbcode
		_log_update_pending = false


## 阵营状态行（挂侧栏【回合】Tab）：按阵营存在性建「我方/敌方」两行 Label。
## turn 未注入（headless 契约测试直接 build）时不建行，refresh_turn_status 自然跳过。
func _add_turn_status_rows(parent: VBoxContainer) -> void:
	if turn == null:
		return
	for faction: StringName in [&"player", &"enemy"]:
		var has_faction := false
		for u: Dictionary in turn.units:
			if StringName(u.get(&"faction", &"")) == faction:
				has_faction = true
				break
		if not has_faction:
			continue
		var label := Label.new()
		label.name = "PlayerStatus" if faction == &"player" else "EnemyStatus"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", FACTION_COLOR[faction])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(label)
		_turn_status_labels[faction] = label
	refresh_turn_status()


## 顶部精简状态：阵营、存活角色、行动状态与实时HP；死亡角色不再占行。
func refresh_turn_status() -> void:
	if turn == null or _turn_status_labels.is_empty():
		return
	var signature := "%d:%s" % [turn.turn_number, String(turn.phase)]
	for u: Dictionary in turn.units:
		signature += "|%s:%s:%s:%d:%d:%s:%s" % [
			String(u.get(&"id", &"")), String(u.get(&"name", "")),
			String(u.get(&"faction", &"")), int(u.get(&"hp", 0)),
			int((u.get(&"stats", {}) as Dictionary).get(&"hp", 0)),
			str(bool(u.get(&"hasActed", false))), str(bool(u.get(&"isDead", false)))
		]
	if signature == _turn_status_signature:
		return
	_turn_status_signature = signature
	for faction: StringName in _turn_status_labels:
		var parts := PackedStringArray()
		for u: Dictionary in turn.units:
			if StringName(u.get(&"faction", &"")) != faction or bool(u.get(&"isDead", false)):
				continue
			var stats: Dictionary = u.get(&"stats", {})
			parts.append("%s %s HP%d/%d" % [
				String(u.get(&"name", "")), "已行动" if bool(u.get(&"hasActed", false)) else "未行动",
				int(u.get(&"hp", 0)), int(stats.get(&"hp", 0))
			])
		var label: Label = _turn_status_labels[faction]
		label.text = "%s｜%s" % [FACTION_NAME[faction], "；".join(parts)]
		label.visible = not parts.is_empty()


# ============================================================
# HUD 构建
# ============================================================
func build(end_turn_cb: Callable, toggle_hosting_cb: Callable, open_pref_cb: Callable) -> void:
	name = "UI"
	# B1 就地模式：世界 HUD（GameHud，layer=100，含右侧 side_panel）仍在树上，
	# 战斗侧栏与之同宽对齐并压在其上；B2 独立场景无世界 HUD，直接独占右侧。
	layer = 101
	_build_sidebar(end_turn_cb, toggle_hosting_cb, open_pref_cb)
	# 菜单/预览容器（屏幕空间，用于动态添加）
	menu_container = Control.new()
	menu_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_container)
	preview_container = Control.new()
	preview_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview_container)
	_ensure_result_presentation()


## 右侧固定宽多 Tab 侧边栏（map_editor 布局范式：标题行 + TabContainer + 底部提示行）。
## 三个 Tab：回合（阶段/阵营状态/结束回合）· 情报（悬停信息）· 托管（托管/偏好/退出）。
func _build_sidebar(end_turn_cb: Callable, toggle_hosting_cb: Callable, open_pref_cb: Callable) -> void:
	_sidebar = PanelContainer.new()
	_sidebar.name = "BattleSidePanel"
	_sidebar.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_sidebar.offset_left = -SIDEBAR_WIDTH
	_sidebar.mouse_filter = Control.MOUSE_FILTER_STOP
	_sidebar.add_theme_stylebox_override("panel", _sidebar_panel_style())
	add_child(_sidebar)

	var sv := VBoxContainer.new()
	sv.name = "SideVBox"
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", 6)
	_sidebar.add_child(sv)

	# 标题行：双剑图标 + 文字（图标缺失只显示文字）
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	var swords: Texture2D = _icon("swords")
	if swords != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = swords
		icon_rect.custom_minimum_size = Vector2(18, 18)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_row.add_child(icon_rect)
	title_row.add_child(_label("战场情报", 16, ACCENT))
	sv.add_child(title_row)

	var tabs := TabContainer.new()
	tabs.name = "InfoTabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 13)
	tabs.add_theme_stylebox_override("panel", _tab_panel_style())
	_tab_styles(tabs)
	sv.add_child(tabs)

	# ---- Tab【回合】：阶段 / 阵营状态 / 结束回合 ----
	var turn_tab := _new_tab(tabs, "回合", "swords")
	phase_label = _label("第 1 轮 · 我方行动", 18, TEXT_MAIN)
	turn_tab.add_child(phase_label)
	_add_turn_status_rows(turn_tab)
	end_turn_btn = Button.new()
	end_turn_btn.text = "结束回合 (E)"
	end_turn_btn.pressed.connect(end_turn_cb)
	_btn_styles(end_turn_btn)
	turn_tab.add_child(end_turn_btn)
	turn_tab.add_child(_label("存活单位实时 HP 与行动状态；全部行动后自动结束回合。", 10, TEXT_DIM))

	# ---- Tab【情报】：悬停单位 / 地形详情（show_info_at 更新） ----
	var info_tab := _new_tab(tabs, "情报", "info")
	info_label = _label("（鼠标悬停单位或地形查看详情）", 13, TEXT_DIM)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_tab.add_child(info_label)
	info_tab.add_child(_label("右键单位打开完整详情；方向键移动光标同样刷新。", 10, TEXT_DIM))

	# ---- Tab【托管】：托管 / 偏好 /（按需）退出战斗 ----
	_host_tab = _new_tab(tabs, "托管", "gears")
	var host_btn := Button.new()
	host_btn.pressed.connect(toggle_hosting_cb)
	_btn_styles(host_btn)
	_host_tab.add_child(host_btn)
	# 把 host_btn 引用交给 turn_director（它负责更新按钮文字）—— 通过注入回调
	if _on_set_host_btn.is_valid():
		_on_set_host_btn.call(host_btn)
	var pref_btn := Button.new()
	pref_btn.text = "托管偏好"
	pref_btn.pressed.connect(open_pref_cb)
	_btn_styles(pref_btn)
	_host_tab.add_child(pref_btn)
	_host_tab.add_child(_label("托管 = 本场战斗自动代打（敌方回合本就自动）；偏好按单位配置目标与策略。", 10, TEXT_DIM))

	# ---- Tab【日志】：引擎/战斗日志（接管 Panku native_logger，浮层不再挂左侧） ----
	var log_tab := _new_tab(tabs, "日志", "file_terminal")
	var log_toolbar := HBoxContainer.new()
	log_toolbar.add_theme_constant_override("separation", 8)
	log_tab.add_child(log_toolbar)
	var clear_btn := Button.new()
	clear_btn.text = "清空"
	clear_btn.tooltip_text = "清空日志（同步清空 Panku native_logger 缓冲）"
	clear_btn.add_theme_font_size_override("font_size", 12)
	clear_btn.pressed.connect(_clear_log)
	_btn_styles(clear_btn)
	log_toolbar.add_child(clear_btn)
	var log_source := _label("引擎日志 · info/warning/error", 10, TEXT_DIM)
	log_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_source.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	log_toolbar.add_child(log_source)
	_log_label = RichTextLabel.new()
	_log_label.name = "LogLabel"
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.scroll_active = true
	_log_label.selection_enabled = true
	_log_label.context_menu_enabled = true
	_log_label.shortcut_keys_enabled = true
	_log_label.focus_mode = Control.FOCUS_CLICK
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.add_theme_font_size_override("normal_font_size", 12)
	_log_label.add_theme_color_override("default_color", Color(0.85, 0.9, 0.9))
	_log_label.text = "（等待日志…）"
	log_tab.add_child(_log_label)
	_attach_panku_logger()

	# 底部提示行（贴面板底部，自动换行）
	var hint := _label("Q/Z·E/X 旋转视角 · R 复位 · 中键拖拽平移 · ESC 取消", 10, TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(hint)


## 新建一个侧栏 Tab：ScrollContainer(只纵向滚) + VBox；设标题与可选图标，返回内容 VBox
func _new_tab(tabs: TabContainer, title: String, icon_name := "") -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "%sScroll" % title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)
	var v := VBoxContainer.new()
	v.name = "%sTab" % title
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	var idx := tabs.get_tab_count() - 1
	tabs.set_tab_title(idx, title)
	if icon_name != "":
		var icon: Texture2D = _icon(icon_name)
		if icon != null:
			tabs.set_tab_icon(idx, icon)
	return v


## 接管 Panku native_logger（照搬 side_panel.gd._attach_panku）：
## 把原生屏幕浮层切成 NeverShow（B2 从 Game.tscn 进来没人关它，会挂在页面左侧），
## 并镜像 logger_view 的完整 bbcode 到【日志】Tab。B1 下世界 side_panel 可能已接管过，
## 再切一次幂等；content_updated 多消费者并存，各自维护自己的文本。
func _attach_panku_logger() -> void:
	var panku := get_node_or_null("/root/Panku")
	if panku == null:
		if is_instance_valid(_log_label):
			_log_label.text = "（Panku 未加载，无日志源）"
		return
	var module_manager = panku.get("module_manager")
	if module_manager == null or not module_manager.has_method("get_module"):
		return
	if not module_manager.has_module("native_logger"):
		return
	_logger_module = module_manager.get_module("native_logger")
	# 1) 屏幕浮层关闭（仅本会话；不写回 panku 持久化配置）
	_logger_module.set_overlay_display_mode(
		PankuModuleNativeLogger.ScreenOverlayDisplayMode.NeverShow
	)
	# 2) 镜像 logger_view 的完整 bbcode（自带去重 / 条数上限 / 时间戳着色）
	var logger_ui: Node = _logger_module.logger_ui
	logger_ui.content_updated.connect(_on_log_content_updated)


func _log_selection_active() -> bool:
	if not is_instance_valid(_log_label):
		return false
	return not _log_label.get_selected_text().is_empty() \
		or (_log_label.has_focus() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))


func _on_log_content_updated(bbcode: String) -> void:
	if _log_selection_active():
		_pending_log_bbcode = bbcode
		_log_update_pending = true
		return
	if is_instance_valid(_log_label):
		_log_label.text = bbcode


func _clear_log() -> void:
	if not is_instance_valid(_log_label):
		return
	_log_label.deselect()
	if _logger_module != null and is_instance_valid(_logger_module):
		# content_updated 会回传空文本并同步本面板
		_logger_module.logger_ui.clear_all()
	else:
		_log_label.text = ""


## battle.gd 注入：把 host_btn 交给 turn_director（battle.gd 持有 director 引用）。
var _on_set_host_btn: Callable
func set_host_btn_callback(cb: Callable) -> void:
	_on_set_host_btn = cb


# ---- 战旗持久化辅助 UI ----
var _exit_btn: Button = null
var _toast: Label = null

## battle.gd 注入「退出战斗」回调：有存档身份的 B2 战斗显示（返回 return_to 场景）。
## 按钮追加到侧栏【托管】Tab；侧栏未建好时兜底直接挂层。
func set_exit_callback(cb: Callable) -> void:
	if not cb.is_valid():
		return
	_exit_btn = Button.new()
	_exit_btn.text = "⏏ 退出战斗"
	_exit_btn.pressed.connect(cb)
	_btn_styles(_exit_btn)
	if _host_tab != null:
		_host_tab.add_child(_exit_btn)
	else:
		add_child(_exit_btn)


## 顶部居中提示条（保存失败 / 续玩通知等），3 秒后自动淡出。
func show_toast(text: String) -> void:
	if _toast != null and is_instance_valid(_toast):
		_toast.queue_free()
	_toast = Label.new()
	_toast.text = text
	_toast.add_theme_font_size_override("font_size", 13)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 4)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -280.0
	_toast.offset_right = 280.0
	_toast.offset_top = 12.0
	_toast.offset_bottom = 52.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_toast)
	var tw := _toast.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(_toast, "modulate:a", 0.0, 1.0)
	tw.tween_callback(_toast.queue_free)


## 偏好面板容器（由 battle.gd _open_pref_panel 使用，因为偏好数据在 turn_director）。
## battle.gd 在 build 后通过 get_pref_panel_container() 拿到这个 Control 再 add_child。
func get_pref_panel_container() -> Control:
	var pref_panel := Control.new()
	pref_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	pref_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pref_panel.visible = false
	add_child(pref_panel)
	return pref_panel


# ============================================================
# 鼠标命中 UI 检测（_input 用）
# ============================================================
func is_over_ui(screen_pos: Vector2) -> bool:
	for child in get_children():
		if _hit_ui(child, screen_pos):
			return true
	return false


func _hit_ui(node: Node, screen_pos: Vector2) -> bool:
	var interactive := node is Button or node is OptionButton or node is ItemList \
		or node is ScrollContainer or node is Slider or node is SpinBox \
		or node is LineEdit or node is TextEdit or node is Panel \
		or node is PanelContainer  # 侧栏本体（mouse_filter=STOP）要拦截战场点击
	if interactive and (node as Control).is_visible_in_tree():
		if (node as Control).get_global_rect().has_point(screen_pos):
			return true
	for child in node.get_children():
		if _hit_ui(child, screen_pos):
			return true
	return false


func has_open_menu() -> bool:
	return menu_container.get_child_count() > 0


## 飘字容器（战斗演出 _spawn_float_text 用 —— 飘字叠加在预览面板同层）。
func get_float_text_container() -> Control:
	return preview_container


# ============================================================
# 回合标签 / 结束回合按钮
# ============================================================
func set_phase_text(text: String, color: Color) -> void:
	phase_label.text = text
	phase_label.add_theme_color_override("font_color", color)


func disable_end_turn(disabled: bool) -> void:
	end_turn_btn.disabled = disabled


# ============================================================
# 单位信息悬浮
# ============================================================
func show_info_at(x: int, y: int) -> void:
	var u := grid.unit_at(x, y)
	if u.is_empty():
		var t := grid.tile_at(x, y)
		if not t.is_empty():
			info_label.text = "(%d,%d) %s\n防御+%d 回避+%d" % [x, y, String(t.type), t.def_bonus, t.avoid_bonus]
		else:
			info_label.text = "(%d,%d)" % [x, y]
	else:
		var s: Dictionary = u.stats
		var lines := PackedStringArray()
		lines.append("%s [%s] Lv%d" % [u.name, ProfessionData.profession_name(u.classId), u.level])
		lines.append("HP %d/%d  MP %d/%d" % [u.hp, s.hp, int(u.get(&"mp", 0)), int(s.get(&"mp", 0))])
		lines.append("力%d 速%d 防%d 魔防%d 射程%s" % [
			s.get(&"str", 0) + s.get(&"mag", 0), s.spd, s.def, s.res,
			str(ProfessionData.unit_attack_range(u)),
		])
		# 技能列表（含冷却）
		var skill_parts: Array = []
		var cd: Dictionary = u.get(&"skillCooldowns", {})
		for sid in u.get(&"skills", []):
			var sn := SkillData.skill_name(sid)
			var c: int = int(cd.get(sid, 0))
			if c > 0:
				skill_parts.append("%s(冷却%d)" % [sn, c])
			else:
				skill_parts.append(sn)
		if not skill_parts.is_empty():
			lines.append("技能: " + ", ".join(skill_parts))
		# 背包（含 uses）
		var item_parts: Array = []
		for ie in u.get(&"items", []):
			var iname := ItemData.item_name(ie.get(&"id", &""))
			item_parts.append("%s×%d" % [iname, int(ie.get(&"uses", 0))])
		if not item_parts.is_empty():
			lines.append("背包: " + ", ".join(item_parts))
		# buff 状态
		var buff_parts: Array = []
		for b in u.get(&"buffs", []):
			buff_parts.append("%s%+d(%d回合)" % [String(b.get(&"stat", &"")), int(b.get(&"value", 0)), int(b.get(&"turns", 0))])
		if not buff_parts.is_empty():
			lines.append("状态: " + ", ".join(buff_parts))
		info_label.text = "\n".join(lines)


# ============================================================
# 单位详情面板（右键查看任意单位完整信息）
# ============================================================
## 打开单位详情面板：居中弹出，展示阵营/等级/HP/MP/全部属性/技能/背包/buff/武器。
## 与行动菜单（menu_container）独立，不改变 mode；ESC 或关闭按钮关。
func open_unit_detail(u: Dictionary) -> void:
	close_unit_detail()
	var s: Dictionary = u.stats
	var viewport_size := get_viewport().get_visible_rect().size
	# 详情面板挂在 preview_container（屏幕空间，FULL_RECT）
	var panel := PanelContainer.new()
	panel.name = "UnitDetailPanel"
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	panel.position = (viewport_size - Vector2(360, 420)) * 0.5
	panel.custom_minimum_size = Vector2(360, 0)
	panel.size = Vector2(360, 420)
	preview_container.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(340, 380)
	panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	var faction_text: String = FACTION_NAME.get(u.faction, "")
	# 标题：阵营色 + 名字 + 职业 + 等级
	var title := _detail_label(
		"%s · %s [%s] Lv.%d" % [faction_text, String(u.name),
			ProfessionData.profession_name(u.classId), int(u.level)],
		18, FACTION_COLOR.get(u.faction, Color.WHITE))
	vbox.add_child(title)

	# 状态行：HP/MP/经验
	vbox.add_child(_detail_label(
		"HP %d / %d    MP %d / %d    EXP %d" % [
			int(u.hp), int(s.hp), int(u.get(&"mp", 0)), int(s.get(&"mp", 0)),
			int(u.get(&"exp", 0))], 14, Color(0.92, 0.95, 0.98)))

	# 全部基础属性
	vbox.add_child(_detail_label(
		("力 %d   魔 %d   技 %d   速 %d\n" +
		 "防 %d   魔防 %d   运 %d   移动 %d") % [
			int(s.get(&"str", 0)), int(s.get(&"mag", 0)), int(s.get(&"skl", 0)), int(s.spd),
			int(s.def), int(s.res), int(s.get(&"luk", 0)), int(s.get(&"mov", 0))],
		14, Color(0.88, 0.93, 0.96)))

	# 攻击范围
	vbox.add_child(_detail_label(
		"攻击射程 %s" % str(ProfessionData.unit_attack_range(u)),
		14, Color(0.88, 0.93, 0.96)))

	# 武器
	var weapon = u.get(&"weapon", null)
	if weapon is Dictionary and not (weapon as Dictionary).is_empty():
		var wd: Dictionary = weapon
		vbox.add_child(_detail_label(
			"武器：%s" % String(wd.get(&"name", String(wd.get(&"id", &"")))),
			14, Color(0.96, 0.84, 0.40)))

	# 技能列表（含冷却 + 描述）
	var skills: Array = u.get(&"skills", [])
	if not skills.is_empty():
		var cd: Dictionary = u.get(&"skillCooldowns", {})
		var skill_lines: Array = []
		for sid in skills:
			var sn := SkillData.skill_name(sid)
			var c: int = int(cd.get(sid, 0))
			if c > 0:
				skill_lines.append("  • %s（冷却 %d）" % [sn, c])
			else:
				skill_lines.append("  • %s" % sn)
		vbox.add_child(_detail_label("技能：", 14, Color(0.75, 0.92, 0.78)))
		vbox.add_child(_detail_label("\n".join(skill_lines), 13, Color(0.82, 0.90, 0.84)))

	# 背包（含 uses）
	var items: Array = u.get(&"items", [])
	if not items.is_empty():
		var item_lines: Array = []
		for ie in items:
			var iname := ItemData.item_name(ie.get(&"id", &""))
			item_lines.append("  • %s ×%d" % [iname, int(ie.get(&"uses", 0))])
		vbox.add_child(_detail_label("背包：", 14, Color(0.74, 0.84, 0.96)))
		vbox.add_child(_detail_label("\n".join(item_lines), 13, Color(0.80, 0.88, 0.95)))

	# buff 状态
	var buffs: Array = u.get(&"buffs", [])
	if not buffs.is_empty():
		var buff_lines: Array = []
		for b in buffs:
			buff_lines.append("  • %s %+d（%d 回合）" % [
				String(b.get(&"stat", &"")), int(b.get(&"value", 0)), int(b.get(&"turns", 0))])
		vbox.add_child(_detail_label("状态：", 14, Color(0.98, 0.84, 0.30)))
		vbox.add_child(_detail_label("\n".join(buff_lines), 13, Color(0.95, 0.86, 0.50)))

	# 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "关闭 (ESC)"
	close_btn.pressed.connect(close_unit_detail)
	vbox.add_child(close_btn)

	_unit_detail_panel = panel


func close_unit_detail() -> void:
	if _unit_detail_panel != null and is_instance_valid(_unit_detail_panel):
		_unit_detail_panel.queue_free()
	_unit_detail_panel = null


func is_unit_detail_open() -> bool:
	return _unit_detail_panel != null and is_instance_valid(_unit_detail_panel)


## 详情面板用的小 Label 工厂（带描边，可指定颜色/字号）。
func _detail_label(text_value: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text_value
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 3)
	return lbl



func open_unit_menu(u: Dictionary, at_pos: Vector2i, _from_pos: Vector2i) -> void:
	on_set_mode.call(MODE_MENU)
	# 记录可撤销移动：菜单期间按 ESC 取消时，把单位送回 from_pos。
	# _pending_move_undo 由 battle.gd 在调用本方法前/后维护；这里通过回调让 battle.gd 设置。
	# （battle.gd._perform_move 调本方法时已持有 from_pos，由它设置 _pending_move_undo）
	# 收集可攻击目标
	var targets: Array = []
	var ar := ProfessionData.unit_attack_range(u)
	for other in grid.units.values():
		if other.faction == u.faction or other.isDead:
			continue
		var dist := absi(other.position.x - at_pos.x) + absi(other.position.y - at_pos.y)
		if dist >= ar[0] and dist <= ar[1]:
			targets.append(other)
	# 可用技能 / 可用物品（uses>0 非装备）
	var usable_skills := SkillData.usable_skills(u)
	var usable_items := ItemData.usable_items(u)
	# 面板高度按按钮数动态算
	var btn_count := 1   # 等待
	if not targets.is_empty():
		btn_count += 1
	if not usable_skills.is_empty():
		btn_count += 1
	if not usable_items.is_empty():
		btn_count += 1
	var panel := Panel.new()
	panel.size = Vector2(120, 40 + btn_count * 28)
	# Camera3D 直接给出 viewport 屏幕坐标；菜单位于 CanvasLayer。
	var menu_level := 0
	if level_fn.is_valid():
		menu_level = int(level_fn.call(at_pos.x, at_pos.y))
	var screen := Vector2.ZERO
	if cell_screen_fn.is_valid():
		screen = cell_screen_fn.call(at_pos.x, at_pos.y, float(menu_level))
	elif board != null:
		screen = board.cell_to_screen(at_pos.x, at_pos.y, float(menu_level))
	panel.position = screen - panel.size / 2.0 + Vector2(40, -40)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	menu_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6; vbox.offset_top = 6; vbox.offset_right = -6; vbox.offset_bottom = -6
	panel.add_child(vbox)
	if not targets.is_empty():
		var b := Button.new()
		b.text = "攻击"
		b.pressed.connect(func():
			close_menu()
			# 确认行动：移动生效，不再可撤销。
			on_clear_pending_move_undo.call()
			_open_attack_target_picker(u, targets)
		)
		vbox.add_child(b)
	if not usable_skills.is_empty():
		var bs := Button.new()
		bs.text = "技能"
		bs.pressed.connect(func():
			close_menu()
			on_clear_pending_move_undo.call()
			_open_skill_picker(u)
		)
		vbox.add_child(bs)
	if not usable_items.is_empty():
		var bi := Button.new()
		bi.text = "物品"
		bi.pressed.connect(func():
			close_menu()
			on_clear_pending_move_undo.call()
			_open_item_picker(u)
		)
		vbox.add_child(bi)
	var bwait := Button.new()
	bwait.text = "等待"
	bwait.pressed.connect(func():
		close_menu()
		# 确认行动：移动生效，不再可撤销。
		on_clear_pending_move_undo.call()
		u.hasActed = true
		update_unit_sprite(u)
		on_clear_selection.call()
		on_set_mode.call(MODE_IDLE)
		on_check_battle_end.call()
		if turn.all_player_acted():
			await get_tree().create_timer(0.3).timeout
			turn.end_turn()
	)
	vbox.add_child(bwait)


## 菜单里改了单位状态后刷新对应 sprite。
func update_unit_sprite(u: Dictionary) -> void:
	if unit_sprites.has(u.id):
		(unit_sprites[u.id] as UnitSprite3D).update_state()


## 技能选择菜单：列出单位可用技能（含 MP/冷却/描述），选中后按 targetType 分发。
func _open_skill_picker(u: Dictionary) -> void:
	var usable := SkillData.usable_skills(u)
	if usable.is_empty():
		return
	var panel := Panel.new()
	panel.size = Vector2(280, 40 + usable.size() * 44)
	var vp := get_viewport().get_visible_rect().size
	panel.position = Vector2(vp.x / 2 - 140, vp.y / 2 - panel.size.y / 2)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	menu_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6; vbox.offset_top = 6; vbox.offset_right = -6; vbox.offset_bottom = -6
	panel.add_child(vbox)
	for sk in usable:
		var info := "%s (MP%d" % [String(sk[&"name"]), int(sk[&"mpCost"])]
		if int(sk[&"cooldown"]) > 0:
			info += " 冷却%d" % int(sk[&"cooldown"])
		info += ")"
		var b := Button.new()
		b.text = info
		b.custom_minimum_size = Vector2(0, 40)
		b.tooltip_text = String(sk[&"desc"])
		b.pressed.connect(func():
			close_menu()
			_on_skill_selected(u, sk[&"id"])
		)
		vbox.add_child(b)


## 技能选中后：self 类型直接执行；其它类型列目标。
func _on_skill_selected(u: Dictionary, skill_id: StringName) -> void:
	var sk := SkillData.get_skill(skill_id)
	if sk[&"targetType"] == &"self":
		await on_resolve_skill.call(u, [u], skill_id)
		on_finish_player_action.call(u)
		return
	var targets := SkillSystem.targets_for(u, skill_id, grid)
	if targets.is_empty():
		# 没有合法目标，回退到等待
		u.hasActed = true
		on_clear_selection.call()
		on_set_mode.call(MODE_IDLE)
		return
	if targets.size() == 1:
		_preview_and_use_skill(u, targets, skill_id)
	else:
		_open_skill_target_picker(u, targets, skill_id)


## 技能目标选择菜单（多目标时）。仿 _open_attack_target_picker。
func _open_skill_target_picker(u: Dictionary, targets: Array, skill_id: StringName) -> void:
	var panel := Panel.new()
	panel.size = Vector2(150, 30 + targets.size() * 28)
	panel.position = Vector2(get_viewport().get_visible_rect().size.x / 2 - 75, get_viewport().get_visible_rect().size.y / 2 - panel.size.y / 2)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	menu_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6; vbox.offset_top = 6; vbox.offset_right = -6; vbox.offset_bottom = -6
	panel.add_child(vbox)
	for t in targets:
		var b := Button.new()
		b.text = "▸ " + String(t.name)
		b.pressed.connect(func():
			close_menu()
			_preview_and_use_skill(u, [t], skill_id)
		)
		vbox.add_child(b)


## 技能预览面板 + 执行。仿 _preview_and_attack。
func _preview_and_use_skill(caster: Dictionary, targets: Array, skill_id: StringName) -> void:
	# 显示技能预览面板（针对第一个目标）
	if not targets.is_empty():
		_show_skill_preview(caster, targets[0], skill_id)
	await get_tree().create_timer(1.0).timeout
	close_preview()
	await on_resolve_skill.call(caster, targets, skill_id)
	on_finish_player_action.call(caster)


## 技能效果预览面板。仿 _show_preview_panel。
func _show_skill_preview(caster: Dictionary, target: Dictionary, skill_id: StringName) -> void:
	close_preview()
	var sk := SkillData.get_skill(skill_id)
	var prev := SkillSystem.preview(caster, target, skill_id)
	var panel := Panel.new()
	panel.size = Vector2(230, 110)
	# 贴侧栏左侧（避开右侧 360 宽侧栏）
	panel.position = Vector2(get_viewport().get_visible_rect().size.x - 250.0 - SIDEBAR_WIDTH, 60)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	preview_container.add_child(panel)
	var lines: Array = [
		"%s · %s" % [String(sk[&"name"]), String(sk[&"type"])],
		"→ %s" % String(target.name),
	]
	if prev.has(&"desc"):
		lines.append(String(prev[&"desc"]))
	if prev.has(&"hit"):
		lines.append("命中 %d%%" % int(prev[&"hit"]))
	var lbl := Label.new()
	lbl.text = "\n".join(lines)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.position = Vector2(10, 10)
	panel.add_child(lbl)


## 物品选择菜单。
func _open_item_picker(u: Dictionary) -> void:
	var usable := ItemData.usable_items(u)
	if usable.is_empty():
		return
	var panel := Panel.new()
	panel.size = Vector2(280, 40 + usable.size() * 40)
	var vp := get_viewport().get_visible_rect().size
	panel.position = Vector2(vp.x / 2 - 140, vp.y / 2 - panel.size.y / 2)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	menu_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6; vbox.offset_top = 6; vbox.offset_right = -6; vbox.offset_bottom = -6
	panel.add_child(vbox)
	for ie in usable:
		var entry: Dictionary = ie[&"entry"]
		var idef: Dictionary = ie[&"def"]
		var b := Button.new()
		b.text = "%s ×%d" % [String(idef[&"name"]), int(entry.get(&"uses", 0))]
		b.custom_minimum_size = Vector2(0, 36)
		b.tooltip_text = String(idef[&"desc"])
		b.pressed.connect(func():
			close_menu()
			_on_item_selected(u, idef[&"id"], entry)
		)
		vbox.add_child(b)


## 物品选中后：self/单目标直接执行，多目标走 picker。
func _on_item_selected(u: Dictionary, item_id: StringName, entry: Dictionary) -> void:
	var idef := ItemData.get_item(item_id)
	if idef[&"target"] == &"self":
		await on_resolve_item.call(u, [u], entry)
		on_finish_player_action.call(u)
		return
	var targets := ItemSystem.targets_for(u, item_id, grid)
	if targets.is_empty():
		u.hasActed = true
		on_clear_selection.call()
		on_set_mode.call(MODE_IDLE)
		return
	if targets.size() == 1:
		await on_resolve_item.call(u, targets, entry)
		on_finish_player_action.call(u)
	else:
		_open_item_target_picker(u, targets, item_id, entry)


## 物品多目标选择。
func _open_item_target_picker(u: Dictionary, targets: Array, _item_id: StringName, entry: Dictionary) -> void:
	var panel := Panel.new()
	panel.size = Vector2(150, 30 + targets.size() * 28)
	panel.position = Vector2(get_viewport().get_visible_rect().size.x / 2 - 75, get_viewport().get_visible_rect().size.y / 2 - panel.size.y / 2)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	menu_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6; vbox.offset_top = 6; vbox.offset_right = -6; vbox.offset_bottom = -6
	panel.add_child(vbox)
	for t in targets:
		var b := Button.new()
		b.text = "▸ " + String(t.name)
		b.pressed.connect(func():
			close_menu()
			await on_resolve_item.call(u, [t], entry)
			on_finish_player_action.call(u)
		)
		vbox.add_child(b)


func _open_attack_target_picker(u: Dictionary, targets: Array) -> void:
	if targets.size() == 1:
		_preview_and_attack(u, targets[0])
		return
	var panel := Panel.new()
	panel.size = Vector2(150, 30 + targets.size() * 28)
	panel.position = Vector2(get_viewport().get_visible_rect().size.x / 2 - 75, get_viewport().get_visible_rect().size.y / 2 - panel.size.y / 2)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	menu_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6; vbox.offset_top = 6; vbox.offset_right = -6; vbox.offset_bottom = -6
	panel.add_child(vbox)
	for t in targets:
		var b := Button.new()
		b.text = "▸ " + String(t.name)
		b.pressed.connect(func():
			close_menu()
			_preview_and_attack(u, t)
		)
		vbox.add_child(b)


func _preview_and_attack(attacker: Dictionary, defender: Dictionary) -> void:
	var def_tile := grid.tile_at(defender.position.x, defender.position.y)
	var prev := CombatSystem.preview(attacker, defender, def_tile.avoid_bonus, def_tile.def_bonus)
	_show_preview_panel(attacker, defender, prev)
	await get_tree().create_timer(1.2).timeout
	close_preview()
	on_resolve_combat.call(attacker, defender, func():
		on_clear_selection.call()
		on_set_mode.call(MODE_IDLE)
		on_check_battle_end.call()
		if turn.phase == &"player" and turn.all_player_acted():
			await get_tree().create_timer(0.3).timeout
			turn.end_turn()
	)


func _show_preview_panel(attacker: Dictionary, defender: Dictionary, prev: Dictionary) -> void:
	close_preview()
	var panel := Panel.new()
	panel.size = Vector2(210, 150)
	# 贴侧栏左侧（避开右侧 360 宽侧栏）
	panel.position = Vector2(get_viewport().get_visible_rect().size.x - 230.0 - SIDEBAR_WIDTH, 60)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	preview_container.add_child(panel)
	var lines := [
		"%s → %s" % [String(attacker.name), String(defender.name)],
		"命中 %d%%  必杀 %d%%" % [prev.atkHit, prev.atkCrit],
		"伤害 %d%s" % [prev.atkDmg, " ×2" if prev.doubleAttack else ""],
		"%s 反击" % String(defender.name),
		"命中 %d%%" % prev.defHit,
		"伤害 %d%s" % [prev.defDmg, " ×2" if prev.defenderDouble else ""],
	]
	var lbl := Label.new()
	lbl.text = "\n".join(lines)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.position = Vector2(10, 10)
	panel.add_child(lbl)


# ============================================================
# 通用：关闭菜单 / 关闭预览 / 面板样式
# ============================================================
func close_preview() -> void:
	for c in preview_container.get_children():
		c.queue_free()


## 关菜单：free 掉控件 + 若当前是 MENU 态则回到 IDLE（mode 由 battle.gd 改）。
func close_menu() -> void:
	for c in menu_container.get_children():
		c.queue_free()
	# mode 复位交给 battle.gd：通过 on_menu_closed 回调。
	# 但原代码只在 mode==MENU 时复位；这里统一通知 battle.gd。
	if _on_menu_closed.is_valid():
		_on_menu_closed.call()


var _on_menu_closed: Callable
func set_menu_closed_callback(cb: Callable) -> void:
	_on_menu_closed = cb


func _make_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.88)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(4)
	return sb


# ============================================================
# 侧栏 / Tab 样式辅助（照搬 map_editor.gd 的配色与做法）
# ============================================================
## 通用扁平样式盒（侧栏系样式的基础）
func _flat_style(bg: Color, border: Color, border_width := 1, corner_radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(corner_radius)
	sb.set_content_margin_all(6)
	return sb


## 侧栏本体：不透明深底 + 细边
func _sidebar_panel_style() -> StyleBoxFlat:
	var sb := _flat_style(BG, PANEL_BORDER, 1, 0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## TabContainer 内容区底色（半透明深色，与 map_editor tab panel 一致）
func _tab_panel_style() -> StyleBoxFlat:
	return _flat_style(Color(0.02, 0.03, 0.045, 0.55), PANEL_BORDER, 1, 4)


## TabContainer 页签三态：常态暗、hover 提亮、选中 ACCENT 底边线
func _tab_styles(tabs: TabContainer) -> void:
	var normal := _flat_style(Color(0.05, 0.07, 0.09, 0.7), PANEL_BORDER, 1, 4)
	var hover := _flat_style(Color(0.09, 0.13, 0.16, 0.9), PANEL_BORDER, 1, 4)
	var selected := _flat_style(Color(0.02, 0.03, 0.045, 0.95), ACCENT, 1, 4)
	# 选中态底边线（map_editor 同款：border_width_bottom=2 + ACCENT）
	selected.border_color = ACCENT
	selected.border_width_bottom = 2
	tabs.add_theme_stylebox_override("tab_selected", selected)
	tabs.add_theme_stylebox_override("tab_unselected", normal)
	tabs.add_theme_stylebox_override("tab_hovered", hover)


## 侧栏系按钮三态（pressed 描边 ACCENT）
func _btn_styles(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _flat_style(BTN_BG, PANEL_BORDER))
	b.add_theme_stylebox_override("hover", _flat_style(BTN_BG_HOVER, PANEL_BORDER))
	b.add_theme_stylebox_override("pressed", _flat_style(BTN_BG_PRESSED, ACCENT))
	b.add_theme_stylebox_override("focus", _flat_style(Color.TRANSPARENT, ACCENT, 1, 6))
	b.add_theme_stylebox_override("disabled", _flat_style(Color(0.06, 0.07, 0.08, 0.7), Color(0.2, 0.24, 0.26, 0.6)))
	b.add_theme_color_override("font_color", TEXT_MAIN)
	b.add_theme_color_override("font_hover_color", TEXT_MAIN)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)
	b.add_theme_color_override("font_focus_color", ACCENT)


## 侧栏系 Label 工厂（默认字号 12，TEXT_DIM）
func _label(text_value: String, font_size := 12, color := TEXT_DIM) -> Label:
	var l := Label.new()
	l.text = text_value
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 加载 at-icons 图标；失败返回 null（调用方回退纯文字）
func _icon(icon_name: String) -> Texture2D:
	var path := ICON_DIR + icon_name + ".svg"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


# ============================================================
# 开战 / 胜负 / 章节末演出（公开给 battle.gd 集成）
# ============================================================
func _ensure_result_presentation() -> ResultPresentationScript:
	if is_instance_valid(result_presentation):
		return result_presentation
	result_presentation = ResultPresentationScript.new()
	result_presentation.name = "ResultPresentation"
	add_child(result_presentation)
	result_presentation.nameplate_shown.connect(func(unit: Dictionary, index: int): nameplate_shown.emit(unit, index))
	result_presentation.boss_banner_shown.connect(func(unit: Dictionary): boss_banner_shown.emit(unit))
	result_presentation.loot_shown.connect(func(entry: Dictionary, index: int): loot_shown.emit(entry, index))
	result_presentation.cheer_requested.connect(func(unit: Dictionary): cheer_requested.emit(unit))
	result_presentation.collapse_requested.connect(func(unit: Dictionary): collapse_requested.emit(unit))
	result_presentation.sound_requested.connect(_on_presentation_sound_requested)
	result_presentation.opening_finished.connect(_on_opening_finished)
	result_presentation.result_finished.connect(_on_result_finished)
	return result_presentation


## units 的 Array 顺序就是名牌亮出顺序；boss 传 {} 表示无 Boss。
func play_opening(units: Array, boss: Dictionary = {}) -> void:
	await _ensure_result_presentation().play_opening(units, boss)


## data 复用逻辑层现有结果：{ loot, exp, gold, chapter_end, chapter_title, title, return_hint }。
## survivors/defeated 仅用于发出视觉钩子，演出不改 UnitData 或 UnitSprite3D。
func play_result(result: StringName, data: Dictionary = {}, survivors: Array = [], defeated: Array = []) -> void:
	if is_instance_valid(phase_label):
		set_phase_text("胜利 · 结算" if result in [&"win", &"victory"] else "战斗结束 · 等待返回", Color(0.55, 0.95, 0.66) if result in [&"win", &"victory"] else Color(0.95, 0.48, 0.48))
	if is_instance_valid(end_turn_btn):
		disable_end_turn(true)
	await _ensure_result_presentation().play_result(result, data, survivors, defeated)


func play_chapter_result(data: Dictionary = {}, survivors: Array = []) -> void:
	if is_instance_valid(phase_label):
		set_phase_text("章节完成 · 结算", Color(1.0, 0.86, 0.48))
	if is_instance_valid(end_turn_btn):
		disable_end_turn(true)
	await _ensure_result_presentation().play_chapter_result(data, survivors)


func skip_presentation() -> void:
	_ensure_result_presentation().skip()


func is_presentation_active() -> bool:
	return is_instance_valid(result_presentation) and result_presentation.is_playing()


func _on_presentation_sound_requested(cue: StringName) -> void:
	presentation_sound_requested.emit(cue)


func _on_opening_finished(skipped: bool) -> void:
	opening_finished.emit(skipped)
	presentation_finished.emit(&"opening", skipped)


func _on_result_finished(result: StringName, skipped: bool) -> void:
	result_finished.emit(result, skipped)
	presentation_finished.emit(result, skipped)


# ============================================================
# 结果横幅（旧 API 保留；新集成请改用 play_result）
# ============================================================
## 显示结果横幅 + 禁用结束回合按钮。5 秒后切场景由根节点 battle.gd 负责
## （子 CanvasLayer 可能在 timer 触发时已 free，直接 get_tree() 会拿到 null）。
func show_result_banner(text: String, color: Color) -> void:
	var banner := Label.new()
	banner.text = text
	banner.add_theme_font_size_override("font_size", 64)
	banner.add_theme_color_override("font_color", color)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 8)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.position -= Vector2(100, 40)
	add_child(banner)
	end_turn_btn.disabled = true
