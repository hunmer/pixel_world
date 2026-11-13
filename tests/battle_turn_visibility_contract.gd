## tests/battle_turn_visibility_contract.gd — 行动结束、敌方阶段、第二轮存活可见性与顶部状态回归
extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)


func _expect_living_visible(battle: Node, stage: String) -> void:
	for id: StringName in battle._unit_sprites:
		var sprite: UnitSprite3D = battle._unit_sprites[id]
		if bool(sprite.unit[&"isDead"]):
			continue
		_expect(sprite.visible, "%s：存活单位 %s 被隐藏" % [stage, String(id)])
		_expect(is_equal_approx(sprite.portrait.modulate.a, 1.0),
			"%s：存活单位 %s 的立绘alpha不是1" % [stage, String(id)])
		_expect(sprite.portrait.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD,
			"%s：测试未覆盖立绘的实际alpha裁剪模式" % stage)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _run() -> void:
	var player := UnitFactory.create_random_unit(
		&"turn_player", "测试勇者", &"player", 1, Vector2i(0, 0),
		ProfessionData.get_profession(&"swordsman")
	)
	var enemy := UnitFactory.create_random_unit(
		&"turn_enemy", "测试守卫", &"enemy", 1, Vector2i(3, 3),
		ProfessionData.get_profession(&"swordsman")
	)
	# 隔离AI攻击：仍走完整TurnDirector阶段，只让敌人在远处原地完成行动。
	enemy.stats[&"mov"] = 0
	var rows: Array = []
	for y in range(4):
		var row: Array = []
		for x in range(4):
			row.append(&"plain")
		rows.append(row)
	var chapter := {
		"id": &"turn_visibility_contract", "name": "回合可见性契约", "width": 4, "height": 4,
		"map": rows, "playerUnits": [player], "enemyUnits": [enemy],
	}
	root.get_node("SceneArgs").set("battle_args", {"chapter": chapter, "hosting": false})
	var battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	# 开场链（转场/对峙演出）结束后才进入首个玩家回合，固定等待会读到"遭遇战"临时文案。
	await battle.battle_ready
	await process_frame
	await process_frame
	_expect_living_visible(battle, "初始")
	_expect(battle.battle_ui.phase_label.text == "第 1 轮 · 我方行动", "初始轮数文案错误")
	var player_status: Label = battle.battle_ui._turn_status_labels[&"player"]
	var enemy_status: Label = battle.battle_ui._turn_status_labels[&"enemy"]
	var initial_hp: int = player.hp
	player.hp = maxi(1, initial_hp - 1)
	await process_frame
	await process_frame
	_expect(player_status.text.contains("测试勇者 未行动 HP%d/%d" % [player.hp, initial_hp]),
		"HP变化后顶部状态没有自动刷新：%s" % player_status.text)

	# 走真实“等待”按钮回调，触发行动结束与唯一我方行动后的自动回合推进。
	battle._select_unit(player)
	battle.battle_ui.open_unit_menu(player, player.position, player.position)
	var wait_button := _find_button(battle.battle_ui.menu_container, "等待")
	_expect(wait_button != null, "找不到等待按钮")
	if wait_button != null:
		wait_button.pressed.emit()
	_expect(player.hasActed, "等待后我方未标记已行动")
	_expect_living_visible(battle, "行动结束")
	await process_frame
	await process_frame
	_expect(player_status.text.contains("测试勇者 已行动 HP"), "行动结束后顶部仍显示未行动")

	var enemy_seen := false
	var second_round_seen := false
	for i in range(140):
		await create_timer(0.05).timeout
		if battle.turn.phase == &"enemy" and not enemy_seen:
			enemy_seen = true
			_expect(battle.battle_ui.phase_label.text == "第 1 轮 · 敌方行动", "敌方阶段顶部轮数/阵营错误")
			_expect_living_visible(battle, "敌方阶段")
		if battle.turn.phase == &"player" and battle.turn.turn_number == 2:
			second_round_seen = true
			break
	_expect(enemy_seen, "未进入敌方阶段")
	_expect(second_round_seen, "未进入第二轮")
	if second_round_seen:
		_expect_living_visible(battle, "第二轮")
		_expect(not player.hasActed and enemy.hasActed, "第二轮行动状态复位错误")
		await process_frame
		await process_frame
		_expect(battle.battle_ui.phase_label.text == "第 2 轮 · 我方行动", "第二轮顶部轮数未刷新")
		_expect(player_status.text.contains("测试勇者 未行动 HP"), "第二轮我方行动状态未刷新")
		_expect(enemy_status.text.contains("测试守卫 已行动 HP"), "第二轮敌方上一阶段行动状态未保留")

	battle.queue_free()
	await process_frame
	await process_frame
	if failures == 0:
		print("BATTLE_TURN_VISIBILITY_CONTRACT_OK")
	else:
		printerr("BATTLE_TURN_VISIBILITY_CONTRACT_FAILED: %d 处失败" % failures)
	quit(0 if failures == 0 else 1)
