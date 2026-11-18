## battle_ui_components_contract.gd — 真实战斗组件的数据、交互和窗口布局契约。
extends SceneTree

var BattleUIScript: GDScript
const UnitScript = preload("res://scripts/core/unit.gd")
const CardScript = preload("res://ui/components/pixel_panel.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _buttons(node: Node) -> Array[Button]:
	var found: Array[Button] = []
	if node is Button:
		found.append(node)
	for child in node.get_children():
		found.append_array(_buttons(child))
	return found

func _text(node: Node) -> String:
	var value := ""
	if node is Label or node is Button:
		value += node.text + "\n"
	for child in node.get_children():
		value += _text(child)
	return value

func _settle() -> void:
	for i in range(5):
		await process_frame

func _run() -> void:
	BattleUIScript = load("res://scripts/battle/battle_ui.gd")
	var player := UnitScript.create_random_unit(&"ui_player", "组件测试我方", &"player", 3, Vector2i(1, 1))
	var enemy := UnitScript.create_random_unit(&"ui_enemy", "组件测试敌方", &"enemy", 3, Vector2i(2, 1))
	player.skills = [&"fireball", &"smite"]
	player.skillCooldowns = {&"smite": 2}
	player.mp = 0
	player.items = [{id = &"hpPotion", uses = 2}, {id = &"hpPotion", uses = 0}]
	var grid := GridSystem.new(4, 4, [[&"plain", &"plain", &"plain", &"plain"], [&"plain", &"plain", &"plain", &"plain"], [&"plain", &"plain", &"plain", &"plain"], [&"plain", &"plain", &"plain", &"plain"]])
	grid.units = {player.id: player, enemy.id: enemy}
	var turn := TurnManager.new([player, enemy])
	root.add_child(turn)
	var ui: Node = BattleUIScript.new()
	ui.setup(null, grid, {}, turn)
	ui.chapter = {victory = {type = &"defend_turns", turns = 5}}
	ui.on_set_mode = func(_mode): pass
	ui.on_clear_pending_move_undo = func(): pass
	root.add_child(ui)
	var clicked := [0]
	ui.build(func(): clicked[0] += 1, func(): pass, func(): pass)
	await _settle()
	ui.end_turn_btn.pressed.emit()
	_expect(clicked[0] == 1, "结束回合按钮必须连接真实回调")
	_expect(ui.immersive_toggle is CheckButton, "设置保持真实沉浸演出开关")
	_expect(_text(ui).contains("坚守 5 回合"), "HUD读取真实战场目标")
	var force_hp: ProgressBar = ui.find_child("ForceHp_player", true, false)
	_expect(force_hp != null and force_hp.value == player.hp, "阵营生命读取当前单位HP")
	player.hp -= 1
	await _settle()
	_expect(force_hp != null and force_hp.value == player.hp, "受伤后HUD自动刷新")
	ui.open_unit_menu(player, player.position, player.position)
	await _settle()
	var menu: Node = ui.menu_container.find_child("BattleMenuCard", true, false)
	_expect(menu != null and menu.get_script() == CardScript, "行动菜单使用组件卡片")
	_expect(_text(ui.menu_container).contains(player.name), "行动菜单显示真实单位")
	ui.close_menu()
	ui._menu._open_skill_picker(player)
	await _settle()
	var skill_buttons := _buttons(ui.menu_container)
	_expect(skill_buttons.size() == 2, "技能列表必须保留所有已学技能")
	for index in skill_buttons.size():
		var button: Button = skill_buttons[index]
		_expect(button.disabled, "MP 不足或冷却技能必须禁用")
		_expect(button.icon != null and button.icon == SkillData.skill_icon(player.skills[index]), "技能按钮必须显示对应技能图标")
		_expect(button.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "技能图标保持最近邻采样")
	_expect(_text(ui.menu_container).contains("冷却 2 回合"), "冷却原因必须来自单位状态")
	ui.close_menu()
	ui._menu._open_item_picker(player)
	await _settle()
	var item_buttons := _buttons(ui.menu_container)
	_expect(item_buttons.size() == 2, "背包保留可用和耗尽物品")
	if item_buttons.size() == 2:
		_expect(not item_buttons[0].disabled and item_buttons[1].disabled, "背包根据实际剩余次数禁用")
		for button in item_buttons:
			_expect(button.icon != null and button.icon == ItemData.item_icon(&"hpPotion"), "物品按钮必须显示对应物品图标")
			_expect(button.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "物品图标保持最近邻采样")
	ui.close_menu()
	var before := [player.hp, enemy.hp, player.mp]
	var prediction := CombatSystem.preview(player, enemy, 0, 0)
	ui._show_preview_panel(player, enemy, prediction)
	await _settle()
	var hp := ui.preview_container.find_child("BattlePreviewAttackerHp", true, false) as ProgressBar
	_expect(hp != null and hp.value == player.hp, "预测血条读取真实HP")
	_expect(_text(ui.preview_container).contains("命中 %d%%" % prediction.atkHit), "预测命中率与结算内核一致")
	ui._show_skill_preview(player, enemy, &"fireball")
	await _settle()
	_expect(ui.preview_container.get_child_count() == 1, "同帧替换预测不能残留旧卡片")
	_expect(_text(ui.preview_container).contains("MP 6"), "技能预测读取真实MP消耗")
	var skill_preview: PanelContainer = ui.preview_container.find_child("BattleSkillPreviewCard", true, false)
	_expect(skill_preview != null and skill_preview.get("icon") == SkillData.skill_icon(&"fireball"), "技能预测显示当前技能图标")
	_expect(before == [player.hp, enemy.hp, player.mp], "预测不得改动战斗数值")
	ui.close_preview()
	var long_loot: Array = []
	for index in range(30):
		long_loot.append({name = "战利品 %d · 用于检验长奖励列表的完整展示" % index, count = index + 1})
	for viewport in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1640, 800)]:
		root.content_scale_size = viewport
		root.size = viewport
		ui.open_unit_menu(player, player.position, player.position)
		await _settle()
		menu = ui.menu_container.find_child("BattleMenuCard", true, false)
		if menu != null:
			var rect: Rect2 = menu.get_global_rect()
			_expect(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= viewport.x + 1 and rect.end.y <= viewport.y + 1, "行动菜单越出视口 %s：%s" % [viewport, rect])
		ui.close_menu()
		ui._show_preview_panel(player, enemy, prediction)
		await _settle()
		var preview_card: Control = ui.preview_container.find_child("BattlePreviewCard", true, false)
		if preview_card != null:
			var rect: Rect2 = preview_card.get_global_rect()
			_expect(rect.position.x >= 0 and rect.end.x <= viewport.x - ui.SIDEBAR_WIDTH + 1 and rect.end.y <= viewport.y + 1, "预测卡片越界或遮住侧栏 %s：%s" % [viewport, rect])
		ui.close_preview()
		ui.open_unit_detail(player)
		await _settle()
		var detail: Control = ui.preview_container.find_child("UnitDetailCard", true, false)
		if detail != null:
			var rect: Rect2 = detail.get_global_rect()
			_expect(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= viewport.x + 1 and rect.end.y <= viewport.y + 1, "单位详情越界 %s：%s" % [viewport, rect])
		var detail_hp: ProgressBar = ui.preview_container.find_child("UnitDetailHp", true, false)
		_expect(detail_hp != null and detail_hp.value == player.hp, "详情读取真实HP")
		for sid: StringName in player.skills:
			var skill_card: PanelContainer = ui.preview_container.find_child("Skill_" + String(sid), true, false)
			_expect(skill_card != null and skill_card.get("icon") == SkillData.skill_icon(sid), "单位详情显示技能图标 %s" % sid)
		_expect(_text(ui.preview_container).contains("剩余 0/"), "详情显示耗尽物品")
		ui.close_unit_detail()
		await _settle()
		ui.result_presentation.play_result(&"win", {loot = long_loot, exp = 90, gold = 30})
		ui.result_presentation.skip()
		await _settle()
		var result_card: Control = ui.result_presentation.find_child("ResultPanel", true, false)
		if result_card != null:
			var rect: Rect2 = result_card.get_global_rect()
			_expect(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= viewport.x + 1 and rect.end.y <= viewport.y + 1, "长奖励结算卡越界 %s：%s" % [viewport, rect])
		var result_scroll: ScrollContainer = ui.result_presentation.find_child("ResultScroll", true, false)
		_expect(result_scroll != null and result_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "长奖励列表必须只纵向滚动")
	ui.queue_free()
	turn.queue_free()
	await process_frame
	if failures == 0:
		print("BATTLE_UI_COMPONENTS_CONTRACT_OK")
	quit(0 if failures == 0 else 1)
