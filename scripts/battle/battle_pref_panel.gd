## battle/battle_pref_panel.gd — 托管偏好面板（每单位配：优先目标 + 策略）
##
## 职责：
##   - 打开面板：动态拉取当前存活敌方单位填充优先目标下拉，列出所有 player 单位
##   - 选择写回 turn_director 偏好（仅本场战斗有效，key=unitId → {priorityTargetId, strategy}）
##   - 关闭并清空面板内容
##
## 设计：从 scenes/battle.gd 抽出的 Node。面板容器由 battle_ui.get_pref_panel_container()
## 提供（battle.gd 在 setup() 注入）；数据面（读当前偏好/写偏好）全部经 turn_director。
## UI 走 UIThemeScript/UIFactoryScript 组件工厂（禁裸数字样式/裸建按钮）。
##
## 公开 API（battle.gd 调用）：
##   setup(grid, turn_director, container)
##   open()    # battle.gd _open_pref_panel 委托（async：清旧内容后等一帧）
##   close()

class_name BattlePrefPanel
extends Node

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")

var grid: GridSystem
var turn_director: TurnDirector
var container: Control


func setup(p_grid: GridSystem, p_turn_director: TurnDirector, p_container: Control) -> void:
	grid = p_grid
	turn_director = p_turn_director
	container = p_container


## 打开偏好面板：动态拉取当前存活敌方单位填充优先目标下拉，列出所有 player 单位。
func open() -> void:
	# 清旧内容
	for c in container.get_children():
		c.queue_free()
	await get_tree().process_frame

	# 收集 player 单位（含 name/class）和存活敌方单位（优先目标候选）
	var player_units: Array = []
	var enemy_units: Array = []
	for u in grid.units.values():
		if u.isDead:
			continue
		if u.faction == &"player":
			player_units.append(u)
		else:
			enemy_units.append(u)

	# 居中面板
	var viewport_size := get_viewport().get_visible_rect().size
	var panel := Panel.new()
	panel.size = Vector2(440, 60 + player_units.size() * 34)
	panel.position = (viewport_size - panel.size) / 2.0
	panel.add_theme_stylebox_override("panel", UIThemeScript.menu_panel_style())
	container.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 10; vbox.offset_top = 8; vbox.offset_right = -10; vbox.offset_bottom = -8
	panel.add_child(vbox)

	var title := UIFactoryScript.label("托管偏好（仅本场战斗有效）", 14, UIThemeScript.TEXT_MAIN)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 0)
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	# 策略下拉选项
	var strat_ids: Array = []
	var strat_labels: Array = []
	for opt in PlayerAI.STRATEGY_OPTIONS:
		strat_ids.append(opt[&"id"])
		strat_labels.append(String(opt[&"label"]))

	for u in player_units:
		var row := HBoxContainer.new()
		list.add_child(row)

		var name_lbl := UIFactoryScript.label(
			"%s [%s]" % [String(u.name), String(ProfessionData.profession_name(u.classId))],
			16, UIThemeScript.TEXT_MAIN)
		name_lbl.custom_minimum_size = Vector2(150, 0)
		row.add_child(name_lbl)

		# 优先目标下拉
		var target_opt := UIFactoryScript.option_button()
		target_opt.add_item("（无，按策略）", 0)
		var cur_pref: Dictionary = turn_director.get_pref(u.id)
		var cur_priority = cur_pref.get(&"priorityTargetId", "")
		var sel_idx := 0
		for i in range(enemy_units.size()):
			var e: Dictionary = enemy_units[i]
			target_opt.add_item("%s [%s]" % [String(e.name), String(ProfessionData.profession_name(e.classId))], i + 1)
			if cur_priority != "" and cur_priority == e.id:
				sel_idx = i + 1
		target_opt.select(sel_idx)
		target_opt.custom_minimum_size = Vector2(150, 0)
		target_opt.item_selected.connect(_on_target_changed.bind(u.id, target_opt, enemy_units))
		row.add_child(target_opt)

		# 策略下拉
		var strat_opt := UIFactoryScript.option_button()
		for i in range(strat_ids.size()):
			strat_opt.add_item(strat_labels[i], i)
		var cur_strat = cur_pref.get(&"strategy", PlayerAI.STRATEGY_AUTO)
		var strat_sel := 0
		for i in range(strat_ids.size()):
			if strat_ids[i] == cur_strat:
				strat_sel = i
				break
		strat_opt.select(strat_sel)
		strat_opt.custom_minimum_size = Vector2(120, 0)
		strat_opt.item_selected.connect(_on_strategy_changed.bind(u.id, strat_opt, strat_ids))
		row.add_child(strat_opt)

	var close_btn := UIFactoryScript.button("关闭", close)
	vbox.add_child(close_btn)

	container.visible = true


func _on_target_changed(unit_id, opt: OptionButton, enemy_units: Array) -> void:
	var idx := opt.get_selected_id()
	var priority_id = ""
	if idx >= 1 and idx <= enemy_units.size():
		priority_id = enemy_units[idx - 1].id
	turn_director.set_pref(unit_id, &"priorityTargetId", priority_id)


func _on_strategy_changed(unit_id, opt: OptionButton, strat_ids: Array) -> void:
	var idx := opt.get_selected_id()
	turn_director.set_pref(unit_id, &"strategy", strat_ids[idx])


func close() -> void:
	container.visible = false
	for c in container.get_children():
		c.queue_free()
