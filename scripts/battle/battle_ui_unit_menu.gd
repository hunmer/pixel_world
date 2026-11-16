## battle/battle_ui_unit_menu.gd — 单位行动菜单与目标选择器（从 battle_ui.gd 拆出）
##
## 职责：
##   - 单位行动菜单 open_unit_menu（攻击/技能/物品/交换/等待）+ 等待收尾链
##   - 各级目标选择 picker：技能选择/技能目标、物品选择/物品目标、
##     交换友军/交换物品、攻击目标
##   - 技能/战斗的预览→执行流（预览面板本体在 battle_ui：_show_skill_preview/
##     _show_preview_panel 挂 preview_container，与飘字/详情共用容器）
##   - update_unit_sprite 的本体（battle_ui 对外委托到这里再回委托，见下）
##
## 设计：RefCounted 能力模块（battle_ui 拆分件）。不持有 battle.gd 引用；
## 宿主 BattleUI（CanvasLayer）经 setup() 注入为 _ui：Callable 注入面
## （on_resolve_combat / on_resolve_skill / on_resolve_item / on_finish_player_action /
## on_clear_selection / on_clear_pending_move_undo / on_set_mode / on_check_battle_end）、
## 数据引用（grid / unit_sprites / turn / board / level_fn / cell_screen_fn / menu_container）
## 与共用面板入口（close_menu / close_preview / _show_preview_panel / _show_skill_preview /
## update_unit_sprite）全部经 _ui 在调用时动态读取（duck-typed，与拆分前
## battle_ui 内访问 self 完全等价 —— battle.gd 在 build 前注入的 Callable 永远读到最新值）。
##
## 公开 API（battle_ui 装配层调用）：
##   setup(ui)
##   open_unit_menu(u, at_pos, _from_pos)
class_name BattleUiUnitMenu
extends RefCounted

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
# 用预加载脚本作类型，避免干净 headless 尚未生成 global class cache 时无法解析。
const TradeSystemScript = preload("res://scripts/systems/trade_system.gd")

## 宿主 BattleUI（CanvasLayer；duck-typed 动态访问注入面与共用面板入口）
var _ui = null

# battle.gd 的 Mode 枚举镜像（on_set_mode 传 int；与 battle.gd enum Mode 保持一致）
const MODE_IDLE := 0
const MODE_MENU := 3


func setup(p_ui) -> void:
	_ui = p_ui


func open_unit_menu(u: Dictionary, at_pos: Vector2i, _from_pos: Vector2i) -> void:
	_ui.on_set_mode.call(MODE_MENU)
	# 记录可撤销移动：菜单期间按 ESC 取消时，把单位送回 from_pos。
	# _pending_move_undo 由 battle.gd 在调用本方法前/后维护；这里通过回调让 battle.gd 设置。
	# （battle.gd._perform_move 调本方法时已持有 from_pos，由它设置 _pending_move_undo）
	# 收集可攻击目标
	var targets: Array = []
	var ar := ProfessionData.unit_attack_range(u)
	for other in _ui.grid.units.values():
		if other.faction == u.faction or other.isDead:
			continue
		var dist := absi(other.position.x - at_pos.x) + absi(other.position.y - at_pos.y)
		if dist >= ar[0] and dist <= ar[1]:
			targets.append(other)
	# 可用技能 / 可用物品（uses>0 非装备）
	var usable_skills := SkillData.usable_skills(u)
	var usable_items := ItemData.usable_items(u)
	# 相邻 1 格带物品友军（C1 交换；自由动作）
	var trade_targets: Array = TradeSystemScript.adjacent_trade_targets(u, _ui.grid)
	# 面板高度按按钮数动态算
	var btn_count := 1   # 等待
	if not targets.is_empty():
		btn_count += 1
	if not usable_skills.is_empty():
		btn_count += 1
	if not usable_items.is_empty():
		btn_count += 1
	if not trade_targets.is_empty():
		btn_count += 1
	var panel := Panel.new()
	panel.size = Vector2(120, 40 + btn_count * 28)
	# Camera3D 直接给出 viewport 屏幕坐标；菜单位于 CanvasLayer。
	var menu_level := 0
	if _ui.level_fn.is_valid():
		menu_level = int(_ui.level_fn.call(at_pos.x, at_pos.y))
	var screen := Vector2.ZERO
	if _ui.cell_screen_fn.is_valid():
		screen = _ui.cell_screen_fn.call(at_pos.x, at_pos.y, float(menu_level))
	elif _ui.board != null:
		screen = _ui.board.cell_to_screen(at_pos.x, at_pos.y, float(menu_level))
	panel.position = screen - panel.size / 2.0 + Vector2(40, -40)
	panel.add_theme_stylebox_override("panel", UIThemeScript.menu_panel_style())
	_ui.menu_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6; vbox.offset_top = 6; vbox.offset_right = -6; vbox.offset_bottom = -6
	panel.add_child(vbox)
	if not targets.is_empty():
		var b := UIFactoryScript.button()
		b.text = "攻击"
		b.pressed.connect(func():
			_ui.close_menu()
			# 确认行动：移动生效，不再可撤销。
			_ui.on_clear_pending_move_undo.call()
			_open_attack_target_picker(u, targets)
		)
		vbox.add_child(b)
	if not usable_skills.is_empty():
		var bs := UIFactoryScript.button()
		bs.text = "技能"
		bs.pressed.connect(func():
			_ui.close_menu()
			_ui.on_clear_pending_move_undo.call()
			_open_skill_picker(u)
		)
		vbox.add_child(bs)
	if not usable_items.is_empty():
		var bi := UIFactoryScript.button()
		bi.text = "物品"
		bi.pressed.connect(func():
			_ui.close_menu()
			_ui.on_clear_pending_move_undo.call()
			_open_item_picker(u)
		)
		vbox.add_child(bi)
	if not trade_targets.is_empty():
		var bt := UIFactoryScript.button()
		bt.text = "交换"
		bt.tooltip_text = "与相邻友军转移物品（自由动作，不消耗行动）"
		bt.pressed.connect(func():
			_ui.close_menu()
			_ui.on_clear_pending_move_undo.call()
			_open_trade_picker(u, trade_targets)
		)
		vbox.add_child(bt)
	var bwait := UIFactoryScript.button()
	bwait.text = "等待"
	bwait.pressed.connect(func():
		_ui.close_menu()
		# 确认行动：移动生效，不再可撤销。
		_ui.on_clear_pending_move_undo.call()
		u.hasActed = true
		_ui.update_unit_sprite(u)
		_ui.on_clear_selection.call()
		_ui.on_set_mode.call(MODE_IDLE)
		_ui.on_check_battle_end.call()
		if _ui.turn.all_player_acted():
			await _ui.get_tree().create_timer(0.3).timeout
			_ui.turn.end_turn()
	)
	vbox.add_child(bwait)


## 技能选择菜单：列出单位可用技能（含 MP/冷却/描述），选中后按 targetType 分发。
func _open_skill_picker(u: Dictionary) -> void:
	var usable := SkillData.usable_skills(u)
	if usable.is_empty():
		return
	var panel := Panel.new()
	panel.size = Vector2(280, 40 + usable.size() * 44)
	var vp = _ui.get_viewport().get_visible_rect().size
	panel.position = Vector2(vp.x / 2 - 140, vp.y / 2 - panel.size.y / 2)
	panel.add_theme_stylebox_override("panel", UIThemeScript.menu_panel_style())
	_ui.menu_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6; vbox.offset_top = 6; vbox.offset_right = -6; vbox.offset_bottom = -6
	panel.add_child(vbox)
	for sk in usable:
		var info := "%s (MP%d" % [String(sk[&"name"]), int(sk[&"mpCost"])]
		if int(sk[&"cooldown"]) > 0:
			info += " 冷却%d" % int(sk[&"cooldown"])
		info += ")"
		var b := UIFactoryScript.button()
		b.text = info
		b.custom_minimum_size = Vector2(0, 40)
		b.tooltip_text = String(sk[&"desc"])
		b.pressed.connect(func():
			_ui.close_menu()
			_on_skill_selected(u, sk[&"id"])
		)
		vbox.add_child(b)


## 技能选中后：self 类型直接执行；其它类型列目标。
func _on_skill_selected(u: Dictionary, skill_id: StringName) -> void:
	var sk := SkillData.get_skill(skill_id)
	if sk[&"targetType"] == &"self":
		await _ui.on_resolve_skill.call(u, [u], skill_id)
		_ui.on_finish_player_action.call(u)
		return
	var targets := SkillSystem.targets_for(u, skill_id, _ui.grid)
	if targets.is_empty():
		# 没有合法目标，回退到等待
		u.hasActed = true
		_ui.on_clear_selection.call()
		_ui.on_set_mode.call(MODE_IDLE)
		return
	if targets.size() == 1:
		_preview_and_use_skill(u, targets, skill_id)
	else:
		_open_skill_target_picker(u, targets, skill_id)


## 技能目标选择菜单（多目标时）。仿 _open_attack_target_picker。
func _open_skill_target_picker(u: Dictionary, targets: Array, skill_id: StringName) -> void:
	var panel := Panel.new()
	panel.size = Vector2(150, 30 + targets.size() * 28)
	panel.position = Vector2(_ui.get_viewport().get_visible_rect().size.x / 2 - 75, _ui.get_viewport().get_visible_rect().size.y / 2 - panel.size.y / 2)
	panel.add_theme_stylebox_override("panel", UIThemeScript.menu_panel_style())
	_ui.menu_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6; vbox.offset_top = 6; vbox.offset_right = -6; vbox.offset_bottom = -6
	panel.add_child(vbox)
	for t in targets:
		var b := UIFactoryScript.button()
		b.text = "▸ " + String(t.name)
		b.pressed.connect(func():
			_ui.close_menu()
			_preview_and_use_skill(u, [t], skill_id)
		)
		vbox.add_child(b)


## 技能预览面板 + 执行。仿 _preview_and_attack。
func _preview_and_use_skill(caster: Dictionary, targets: Array, skill_id: StringName) -> void:
	# 显示技能预览面板（针对第一个目标）
	if not targets.is_empty():
		_ui._show_skill_preview(caster, targets[0], skill_id)
	await _ui.get_tree().create_timer(1.0).timeout
	_ui.close_preview()
	await _ui.on_resolve_skill.call(caster, targets, skill_id)
	_ui.on_finish_player_action.call(caster)


## 物品选择菜单。
func _open_item_picker(u: Dictionary) -> void:
	var usable := ItemData.usable_items(u)
	if usable.is_empty():
		return
	var panel := Panel.new()
	panel.size = Vector2(280, 40 + usable.size() * 40)
	var vp = _ui.get_viewport().get_visible_rect().size
	panel.position = Vector2(vp.x / 2 - 140, vp.y / 2 - panel.size.y / 2)
	panel.add_theme_stylebox_override("panel", UIThemeScript.menu_panel_style())
	_ui.menu_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6; vbox.offset_top = 6; vbox.offset_right = -6; vbox.offset_bottom = -6
	panel.add_child(vbox)
	for ie in usable:
		var entry: Dictionary = ie[&"entry"]
		var idef: Dictionary = ie[&"def"]
		var b := UIFactoryScript.button()
		b.text = "%s ×%d" % [String(idef[&"name"]), int(entry.get(&"uses", 0))]
		b.custom_minimum_size = Vector2(0, 36)
		b.tooltip_text = String(idef[&"desc"])
		b.pressed.connect(func():
			_ui.close_menu()
			_on_item_selected(u, idef[&"id"], entry)
		)
		vbox.add_child(b)


## 物品选中后：self/单目标直接执行，多目标走 picker。
func _on_item_selected(u: Dictionary, item_id: StringName, entry: Dictionary) -> void:
	var idef := ItemData.get_item(item_id)
	if idef[&"target"] == &"self":
		await _ui.on_resolve_item.call(u, [u], entry)
		_ui.on_finish_player_action.call(u)
		return
	var targets := ItemSystem.targets_for(u, item_id, _ui.grid)
	if targets.is_empty():
		u.hasActed = true
		_ui.on_clear_selection.call()
		_ui.on_set_mode.call(MODE_IDLE)
		return
	if targets.size() == 1:
		await _ui.on_resolve_item.call(u, targets, entry)
		_ui.on_finish_player_action.call(u)
	else:
		_open_item_target_picker(u, targets, item_id, entry)


## 物品多目标选择。
func _open_item_target_picker(u: Dictionary, targets: Array, _item_id: StringName, entry: Dictionary) -> void:
	var panel := Panel.new()
	panel.size = Vector2(150, 30 + targets.size() * 28)
	panel.position = Vector2(_ui.get_viewport().get_visible_rect().size.x / 2 - 75, _ui.get_viewport().get_visible_rect().size.y / 2 - panel.size.y / 2)
	panel.add_theme_stylebox_override("panel", UIThemeScript.menu_panel_style())
	_ui.menu_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6; vbox.offset_top = 6; vbox.offset_right = -6; vbox.offset_bottom = -6
	panel.add_child(vbox)
	for t in targets:
		var b := UIFactoryScript.button()
		b.text = "▸ " + String(t.name)
		b.pressed.connect(func():
			_ui.close_menu()
			await _ui.on_resolve_item.call(u, [t], entry)
			_ui.on_finish_player_action.call(u)
		)
		vbox.add_child(b)


## 交换友军选择菜单（C1：仅相邻 1 格带物品友军）。选完进入物品选择。
func _open_trade_picker(u: Dictionary, targets: Array) -> void:
	if targets.is_empty():
		return
	if targets.size() == 1:
		_open_trade_item_picker(u, targets[0])
		return
	var panel := Panel.new()
	panel.size = Vector2(170, 30 + targets.size() * 28)
	panel.position = Vector2(_ui.get_viewport().get_visible_rect().size.x / 2 - 85, _ui.get_viewport().get_visible_rect().size.y / 2 - panel.size.y / 2)
	panel.add_theme_stylebox_override("panel", UIThemeScript.menu_panel_style())
	_ui.menu_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6; vbox.offset_top = 6; vbox.offset_right = -6; vbox.offset_bottom = -6
	panel.add_child(vbox)
	for t in targets:
		var b := UIFactoryScript.button()
		b.text = "⇄ " + String(t.name)
		b.pressed.connect(func():
			_ui.close_menu()
			_open_trade_item_picker(u, t)
		)
		vbox.add_child(b)


## 交换物品选择菜单：列出双方背包条目，点选即单向转移（自由动作，不置 hasActed）。
## 转移完成后重开行动菜单，来回点两次即为交换。
func _open_trade_item_picker(u: Dictionary, ally: Dictionary) -> void:
	# 双方背包条目合并列出：owner 标记物品当前归属，转移方向 = 归属方 → 另一方
	var entries: Array = []
	for ie in u.get(&"items", []):
		entries.append({ entry = ie, owner = u })
	for ie in ally.get(&"items", []):
		entries.append({ entry = ie, owner = ally })
	if entries.is_empty():
		_reopen_unit_menu(u)
		return
	var panel := Panel.new()
	panel.size = Vector2(280, 70 + entries.size() * 36)
	var vp = _ui.get_viewport().get_visible_rect().size
	panel.position = Vector2(vp.x / 2 - 140, vp.y / 2 - panel.size.y / 2)
	panel.add_theme_stylebox_override("panel", UIThemeScript.menu_panel_style())
	_ui.menu_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6; vbox.offset_top = 6; vbox.offset_right = -6; vbox.offset_bottom = -6
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "转移给对方（%s ⇄ %s）" % [String(u.name), String(ally.name)]
	title.add_theme_font_size_override("font_size", 12)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)
	for rec in entries:
		var entry: Dictionary = rec[&"entry"]
		var owner: Dictionary = rec[&"owner"]
		var receiver: Dictionary = ally if owner == u else u
		var b := UIFactoryScript.button()
		b.text = "%s：%s ×%d" % [String(owner.name), ItemData.item_name(entry.get(&"id", &"")), int(entry.get(&"uses", 0))]
		b.custom_minimum_size = Vector2(0, 32)
		b.pressed.connect(func():
			_ui.close_menu()
			TradeSystemScript.execute_trade(owner, receiver, entry)
			_ui.update_unit_sprite(u)
			_ui.update_unit_sprite(ally)
			_reopen_unit_menu(u)
		)
		vbox.add_child(b)
	var bclose := UIFactoryScript.button()
	bclose.text = "返回"
	bclose.pressed.connect(func():
		_ui.close_menu()
		_reopen_unit_menu(u)
	)
	vbox.add_child(bclose)


## 自由动作收尾：不置 hasActed，回到行动菜单继续选择（攻击/技能/物品/等待）。
func _reopen_unit_menu(u: Dictionary) -> void:
	open_unit_menu(u, u.position, u.position)


func _open_attack_target_picker(u: Dictionary, targets: Array) -> void:
	if targets.size() == 1:
		_preview_and_attack(u, targets[0])
		return
	var panel := Panel.new()
	panel.size = Vector2(150, 30 + targets.size() * 28)
	panel.position = Vector2(_ui.get_viewport().get_visible_rect().size.x / 2 - 75, _ui.get_viewport().get_visible_rect().size.y / 2 - panel.size.y / 2)
	panel.add_theme_stylebox_override("panel", UIThemeScript.menu_panel_style())
	_ui.menu_container.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6; vbox.offset_top = 6; vbox.offset_right = -6; vbox.offset_bottom = -6
	panel.add_child(vbox)
	for t in targets:
		var b := UIFactoryScript.button()
		b.text = "▸ " + String(t.name)
		b.pressed.connect(func():
			_ui.close_menu()
			_preview_and_attack(u, t)
		)
		vbox.add_child(b)


func _preview_and_attack(attacker: Dictionary, defender: Dictionary) -> void:
	var def_tile = _ui.grid.tile_at(defender.position.x, defender.position.y)
	var prev := CombatSystem.preview(attacker, defender, def_tile.avoid_bonus, def_tile.def_bonus)
	_ui._show_preview_panel(attacker, defender, prev)
	await _ui.get_tree().create_timer(1.2).timeout
	_ui.close_preview()
	_ui.on_resolve_combat.call(attacker, defender, func():
		_ui.on_clear_selection.call()
		_ui.on_set_mode.call(MODE_IDLE)
		_ui.on_check_battle_end.call()
		if _ui.turn.phase == &"player" and _ui.turn.all_player_acted():
			await _ui.get_tree().create_timer(0.3).timeout
			_ui.turn.end_turn()
	)
