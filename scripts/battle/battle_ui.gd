## battle/battle_ui.gd — 战场屏幕空间 UI（从 scenes/battle.gd 抽出）
##
## 职责：
##   - HUD 构建（回合标签 / 结束回合按钮 / 信息面板 / 托管按钮 / 偏好按钮 / 菜单&预览容器）
##   - 单位信息悬浮显示（show_info_at）
##   - 单位行动菜单（攻击/技能/物品/等待）+ 各级目标选择 picker
##   - 战斗预览面板 / 技能预览面板
##   - 开战名牌/Boss 横幅与胜利/失败/章节末结算演出（ResultPresentation）
##   - 结果横幅（旧 show_result_banner 兼容入口）
##   - 通用面板样式 _make_panel_style
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
## 可选：柱顶高度函数（BattlefieldRenderer.stand_level，B2 等距方块模式注入）
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
var turn_status_panel: PanelContainer
var _turn_status_labels: Dictionary = {}
var _turn_status_signature := ""
var result_presentation: ResultPresentationScript
# 单位详情面板（右键查看任意单位完整信息；与行动菜单 menu_container 独立）
var _unit_detail_panel: Control = null

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


func _build_turn_status_panel() -> void:
	turn_status_panel = PanelContainer.new()
	turn_status_panel.name = "TurnStatus"
	turn_status_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	turn_status_panel.offset_left = 230.0
	turn_status_panel.offset_top = 10.0
	turn_status_panel.offset_right = -230.0
	turn_status_panel.offset_bottom = 78.0
	turn_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_status_panel.add_theme_stylebox_override("panel", _make_panel_style())
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 2)
	turn_status_panel.add_child(rows)
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
		rows.add_child(label)
		_turn_status_labels[faction] = label
	add_child(turn_status_panel)
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
	# 回合标签
	phase_label = Label.new()
	phase_label.text = "第 1 轮 · 我方行动"
	phase_label.add_theme_font_size_override("font_size", 22)
	phase_label.position = Vector2(16, 12)
	add_child(phase_label)
	_build_turn_status_panel()
	# 结束回合按钮
	end_turn_btn = Button.new()
	end_turn_btn.text = "结束回合 (E)"
	end_turn_btn.position = Vector2(16, 50)
	end_turn_btn.pressed.connect(end_turn_cb)
	add_child(end_turn_btn)
	# 信息面板（加大高度以容纳 MP/技能/物品/状态）
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 13)
	info_label.position = Vector2(16, 92)
	info_label.size = Vector2(360, 240)
	add_child(info_label)
	# 托管按钮 + 偏好按钮（top-left 簇，info_label 下方）
	var host_btn := Button.new()
	host_btn.position = Vector2(16, 340)
	host_btn.pressed.connect(toggle_hosting_cb)
	add_child(host_btn)
	# 把 host_btn 引用交给 turn_director（它负责更新按钮文字）—— 通过注入回调
	if _on_set_host_btn.is_valid():
		_on_set_host_btn.call(host_btn)
	var pref_btn := Button.new()
	pref_btn.text = "托管偏好"
	pref_btn.position = Vector2(120, 340)
	pref_btn.pressed.connect(open_pref_cb)
	add_child(pref_btn)
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


## battle.gd 注入：把 host_btn 交给 turn_director（battle.gd 持有 director 引用）。
var _on_set_host_btn: Callable
func set_host_btn_callback(cb: Callable) -> void:
	_on_set_host_btn = cb


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
		or node is LineEdit or node is TextEdit or node is Panel
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
	panel.position = Vector2(get_viewport().get_visible_rect().size.x - 250, 60)
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
	panel.position = Vector2(get_viewport().get_visible_rect().size.x - 230, 60)
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
