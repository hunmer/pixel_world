## battle/battle_ui.gd — 战场屏幕空间 UI 装配层（从 scenes/battle.gd 抽出，2026-11 再拆分）
##
## 职责（装配层 + 共用面板面）：
##   - 信号面 / Callable 注入面 / 控件别名的持有者（契约兼容）
##   - build()：按序装配 HUD 侧栏 → 菜单/预览容器 → 演出层
##   - 共用屏幕空间容器与面板：menu_container / preview_container /
##     战斗预览面板 / 技能预览面板（贴侧栏左侧，避开右侧栏）
##   - toast / 退出战斗按钮 / 偏好面板容器 / 鼠标命中 UI 检测
##   - 开战名牌/Boss 横幅与胜利/失败/章节末结算演出（ResultPresentation）包装
##   - 旧 show_result_banner 兼容入口（新演出用 play_result）
##
## 已按职责拆出的子模块（scripts/battle/，RefCounted + setup(ui) 注入宿主，
## 经 _ui duck-typed 访问注入面 —— 与拆分前本文件访问 self 等价）：
##   - BattleUiHud (RefCounted)        HUD 侧栏（回合/情报/托管/战场设置/日志 Tab +
##                                     阵营状态行 + 悬停情报文本 + Panku 日志接管）
##   - BattleUiUnitMenu (RefCounted)   单位行动菜单（攻击/技能/物品/交换/等待）+ 各级 picker
##   - BattleUiUnitDetail (RefCounted) 单位详情面板（右键查看任意单位完整信息）
##   - BattleUiBanner (RefCounted)     结果横幅
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
const BattleUiHudScript = preload("res://scripts/battle/battle_ui_hud.gd")
const BattleUiUnitMenuScript = preload("res://scripts/battle/battle_ui_unit_menu.gd")
const BattleUiUnitDetailScript = preload("res://scripts/battle/battle_ui_unit_detail.gd")
const BattleUiBannerScript = preload("res://scripts/battle/battle_ui_banner.gd")
const BattleUiPreviewScript = preload("res://scripts/battle/battle_ui_preview.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")

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
signal immersive_presentation_changed(enabled: bool)

# ---- 注入的只读引用 ----
var board: IsoBoard
## 可选：柱顶高度函数（BattlefieldRenderer.visual_top_level，B2 等距方块模式注入）
var level_fn: Callable = Callable()
## B1/B2 统一注入 cell → 屏幕坐标，避免 B1 没有 IsoBoard 时菜单定位中断。
var cell_screen_fn: Callable = Callable()
var grid: GridSystem
var unit_sprites: Dictionary
var turn: TurnManager
## 真实战场目标，由场景装配时注入；不从画廊复制示例目标。
var chapter: Dictionary = {}

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
var on_show_support_range: Callable
var on_clear_support_range: Callable
## 每次取消预览递增，阻止已经取消的协程落地行动。
var action_preview_revision: int = 0
## 行动记录（battle.gd 注入）：on_record_action(label) 记一条已结算行动；
## on_rewind_action(index) 点击记录条目回退（0-based，恢复到该行动之前）。
var on_record_action: Callable
var on_rewind_action: Callable

# ---- 子模块（build 时创建并注入宿主） ----
var _hud: BattleUiHudScript = null
var _menu: BattleUiUnitMenuScript = null
var _detail: BattleUiUnitDetailScript = null
var _banner: BattleUiBannerScript = null
var _preview: BattleUiPreviewScript = null

# ---- 控件（HUD 别名：build 后指向 hud 模块持有的同一实例；契约测试直戳） ----
var phase_label: Label
var end_turn_btn: Button
var info_label: Label
var menu_container: Control
var preview_container: Control
var immersive_toggle: CheckButton = null
var _turn_status_labels: Dictionary = {}
var result_presentation: ResultPresentationScript
## 【托管】Tab 内容盒（hud 模块别名；退出战斗按钮按需追加到这里）
var _host_tab: VBoxContainer = null

# ---- 侧边栏几何 ----
## 侧栏宽度：与世界 side_panel.PANEL_WIDTH 对齐 —— B1 就地模式下世界相机已按
## 该宽度预留右侧取景（main.gd: _cam.reserved_right_px = GameHud.SIDE_PANEL_WIDTH），
## 战斗侧栏同宽覆盖世界侧栏，取景刚好对齐；B2 由 battle.gd 设置 reserved_right_px。
const SIDEBAR_WIDTH := 360.0


func setup(p_board: IsoBoard, p_grid: GridSystem, p_unit_sprites: Dictionary, p_turn: TurnManager) -> void:
	board = p_board
	grid = p_grid
	unit_sprites = p_unit_sprites
	turn = p_turn


func _process(_delta: float) -> void:
	# HUD 每帧刷新（阵营状态签名检测 + 挂起日志落盘），见 battle_ui_hud.gd。
	if _hud != null:
		_hud.process_tick()


func _on_immersive_presentation_toggled(enabled: bool) -> void:
	Settings.set_battle_immersive_presentation(enabled)
	immersive_presentation_changed.emit(enabled)
	print("[BattleUI] 沉浸式演出 → %s" % ("开启" if enabled else "关闭"))


# ============================================================
# 装配（子节点顺序必须保持：侧栏 → 菜单容器 → 预览容器 → 演出层）
# ============================================================
func build(end_turn_cb: Callable, toggle_hosting_cb: Callable, open_pref_cb: Callable) -> void:
	name = "UI"
	# B1 就地模式：世界 HUD（GameHud，layer=100，含右侧 side_panel）仍在树上，
	# 战斗侧栏与之同宽对齐并压在其上；B2 独立场景无世界 HUD，直接独占右侧。
	layer = 101
	# HUD 侧栏（回合/情报/托管/战场设置/日志）—— battle_ui_hud.gd
	_hud = BattleUiHudScript.new()
	_hud.setup(self)
	_hud.build(end_turn_cb, toggle_hosting_cb, open_pref_cb,
		_on_set_host_btn, _on_immersive_presentation_toggled)
	# 控件别名：与 hud 模块持有同一实例（battle.gd / 契约测试经本层访问）
	phase_label = _hud.phase_label
	end_turn_btn = _hud.end_turn_btn
	info_label = _hud.info_label
	immersive_toggle = _hud.immersive_toggle
	_turn_status_labels = _hud.turn_status_labels
	_host_tab = _hud.host_tab
	# 菜单/预览容器（屏幕空间，用于动态添加）
	menu_container = Control.new()
	menu_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_container)
	preview_container = Control.new()
	preview_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview_container)
	# 单位行动菜单 / 单位详情 / 结果横幅 —— 对应拆分模块（均只持宿主引用）
	_menu = BattleUiUnitMenuScript.new()
	_menu.setup(self)
	_detail = BattleUiUnitDetailScript.new()
	_detail.setup(self)
	_banner = BattleUiBannerScript.new()
	_banner.setup(self)
	_preview = BattleUiPreviewScript.new()
	_preview.setup(self)
	_ensure_result_presentation()


## 顶部精简状态刷新（阵营/存活/行动/HP）—— 薄委托到 hud 模块（见 battle_ui_hud.gd）。
func refresh_turn_status() -> void:
	if _hud != null:
		_hud.refresh_turn_status()


## 【记录】Tab 重渲染 —— 薄委托到 hud 模块；labels 由 battle.gd 推送。
func refresh_action_history(labels: Array) -> void:
	if _hud != null:
		_hud.refresh_action_history(labels)


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
	_exit_btn = UIFactoryScript.button()
	_exit_btn.text = "⏏ 退出战斗"
	_exit_btn.pressed.connect(cb)
	if _host_tab != null:
		_host_tab.add_child(_exit_btn)
	else:
		add_child(_exit_btn)


## 顶部居中提示条（保存失败 / 续玩通知等），3 秒后自动淡出。
func show_toast(text: String) -> void:
	if _toast != null and is_instance_valid(_toast):
		_toast.queue_free()
	_toast = UIFactoryScript.outline_label(text, 13, UIThemeScript.TOAST_COLOR, 4)
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


func show_support_range(unit: Dictionary, skill_id: StringName) -> void:
	if on_show_support_range.is_valid():
		on_show_support_range.call(unit, skill_id)


func clear_support_range() -> void:
	if on_clear_support_range.is_valid():
		on_clear_support_range.call()


func cancel_action_preview() -> void:
	action_preview_revision += 1
	close_preview()
	clear_support_range()


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
# 单位信息悬浮（面板内容在 hud 模块）
# ============================================================
func show_info_at(x: int, y: int) -> void:
	_hud.show_info_at(x, y)


# ============================================================
# 单位详情面板（面板在 battle_ui_unit_detail 模块）
# ============================================================
func open_unit_detail(u: Dictionary) -> void:
	_detail.open_unit_detail(u)


func close_unit_detail() -> void:
	_detail.close_unit_detail()


func is_unit_detail_open() -> bool:
	return _detail.is_unit_detail_open()


# ============================================================
# 单位行动菜单（菜单/picker 在 battle_ui_unit_menu 模块）
# ============================================================
func open_unit_menu(u: Dictionary, at_pos: Vector2i, _from_pos: Vector2i) -> void:
	_menu.open_unit_menu(u, at_pos, _from_pos)


## 菜单里改了单位状态后刷新对应 sprite。
func update_unit_sprite(u: Dictionary) -> void:
	if unit_sprites.has(u.id):
		(unit_sprites[u.id] as UnitSprite3D).update_state()


## 技能效果预览面板。仿 _show_preview_panel（贴侧栏左侧，避开右侧 360 宽侧栏）。
func _show_skill_preview(caster: Dictionary, target: Dictionary, skill_id: StringName) -> void:
	_preview.show_skill(caster, target, skill_id)


# ============================================================
# 通用：关闭菜单 / 关闭预览 / 预览面板
# ============================================================
func close_preview() -> void:
	for c in preview_container.get_children():
		preview_container.remove_child(c)
		c.queue_free()


## 关菜单：free 掉控件 + 若当前是 MENU 态则回到 IDLE（mode 由 battle.gd 改）。
func close_menu() -> void:
	for c in menu_container.get_children():
		menu_container.remove_child(c)
		c.queue_free()
	# mode 复位交给 battle.gd：通过 on_menu_closed 回调。
	# 但原代码只在 mode==MENU 时复位；这里统一通知 battle.gd。
	if _on_menu_closed.is_valid():
		_on_menu_closed.call()


var _on_menu_closed: Callable
func set_menu_closed_callback(cb: Callable) -> void:
	_on_menu_closed = cb


func _show_preview_panel(attacker: Dictionary, defender: Dictionary, prev: Dictionary) -> void:
	_preview.show_combat(attacker, defender, prev)


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
# 结果横幅（旧 API 保留；面板在 battle_ui_banner 模块）
# ============================================================
func show_result_banner(text: String, color: Color) -> void:
	_banner.show_result_banner(text, color)
