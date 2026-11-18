## tests/battle_action_history_contract.gd — 玩家行动记录与回退（整场战斗粒度）回归
## 覆盖：原地点击弹菜单（需求①）；行动记录条目；跨回合保留；
## 回退恢复单位状态/回合数；增援单位与波次的回滚。
extends SceneTree

const WorldToChapter = preload("res://scripts/core/world_to_chapter.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)


func _run() -> void:
	await _run_b2()
	if failures == 0:
		print("BATTLE_ACTION_HISTORY_CONTRACT_OK")
	else:
		printerr("BATTLE_ACTION_HISTORY_CONTRACT_FAILED: %d 处失败" % failures)
	quit(0 if failures == 0 else 1)


func _run_b2() -> void:
	var p1 := UnitFactory.create_random_unit(
		&"hist_p1", "剑士甲", &"player", 1, Vector2i(0, 0),
		ProfessionData.get_profession(&"swordsman")
	)
	var p2 := UnitFactory.create_random_unit(
		&"hist_p2", "剑士乙", &"player", 1, Vector2i(0, 1),
		ProfessionData.get_profession(&"swordsman")
	)
	var enemy := UnitFactory.create_random_unit(
		&"hist_e1", "强盗", &"enemy", 1, Vector2i(3, 1),
		ProfessionData.get_profession(&"archer")
	)
	var rein := UnitFactory.create_random_unit(
		&"hist_rein", "增援兵", &"enemy", 1, Vector2i(5, 1),
		ProfessionData.get_profession(&"swordsman")
	)
	var rows: Array = []
	for y in range(3):
		var row: Array = []
		for x in range(6):
			row.append(&"plain")
		rows.append(row)
	var chapter := {
		"id": &"history_contract", "name": "记录契约", "width": 6, "height": 3,
		"map": rows, "playerUnits": [p1, p2], "enemyUnits": [enemy],
		"reinforcements": [{ &"turn": 2, &"units": [rein] }],
	}
	root.get_node("SceneArgs").set("battle_args", {"chapter": chapter, "hosting": false})
	var battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	await battle.battle_ready
	await process_frame
	await process_frame

	# ---- 1) 需求①：选中单位后原地再次点击应直接弹出行动菜单 ----
	battle._select_unit(p1)
	var origin_screen: Vector2 = battle._b2_cell_to_screen(0, 0)
	battle._on_tile_click_at_screen(origin_screen)
	await process_frame
	_expect(battle.mode == battle.Mode.MENU and battle.battle_ui.has_open_menu(),
		"原地点击当前角色未弹出行动菜单（mode=%s）" % str(battle.mode))
	battle.battle_ui.close_menu()
	await process_frame

	# ---- 2) 行动记录：两次已结算行动入列 ----
	battle._finish_player_action(p1, "攻击 强盗")
	battle._finish_player_action(p2, "技能 猛击")
	var labels: Array = battle._action_history.labels()
	_expect(labels.size() == 2 and String(labels[0]).contains("T1 · 攻击 强盗")
		and String(labels[1]).contains("T1 · 技能 猛击"),
		"行动记录条目不符合预期：%s" % str(labels))
	# _finish_player_action 不置 hasActed（真实置位在 UI 按钮回调），手动置位模拟完整行动。
	p1[&"hasActed"] = true
	p2[&"hasActed"] = true

	# ---- 3) 回退到第 1 条之前（index 0 → baseline 战斗开始）----
	battle._rewind_player_action(0)
	_expect(not bool(p1[&"hasActed"]) and not bool(p2[&"hasActed"]),
		"回退到战斗开始后 hasActed 应复位")
	_expect(battle._action_history.labels().is_empty(), "回退后历史应截断为空")
	_expect(battle.mode == battle.Mode.IDLE, "回退后应回到 IDLE")
	_expect(battle.turn.phase == &"player" and battle.turn.turn_number == 1,
		"回退后回合状态异常（phase=%s turn=%d）" % [str(battle.turn.phase), battle.turn.turn_number])

	# ---- 4) 跨回合保留：进入第 2 轮后历史不清空 ----
	battle._finish_player_action(p1, "等待 剑士甲")
	battle.turn.restore_state(&"player", 2)
	battle._on_player_phase(2)
	_expect(battle._action_history.labels().size() == 1,
		"新玩家回合开始不应清空整场历史：%s" % str(battle._action_history.labels()))
	_expect(String(battle._action_history.labels()[0]).contains("T1 · 等待 剑士甲"),
		"历史条目应保留早前回合记录")

	# ---- 5) 增援刷入（T2 波次）----
	battle._spawn_due_reinforcements(2)
	_expect(battle.turn.units.any(func(u): return u[&"id"] == &"hist_rein"),
		"T2 增援未入 turn.units")
	_expect((chapter["enemyUnits"] as Array).size() == 2, "增援未并入 enemyUnits")
	_expect((chapter["reinforcements"] as Array).is_empty(), "增援波次未被消费")
	battle._finish_player_action(p2, "攻击 增援兵")
	_expect(battle._action_history.labels().size() == 2, "T2 行动应追加到整场历史")

	# ---- 6) 跨回合回退到战斗开始：增援单位与波次一并回滚 ----
	battle._rewind_player_action(0)
	_expect(not battle.turn.units.any(func(u): return u[&"id"] == &"hist_rein"),
		"跨回合回退后增援单位应从 turn.units 移除")
	_expect((chapter["enemyUnits"] as Array).size() == 1, "增援单位应从 enemyUnits 移除")
	_expect((chapter["reinforcements"] as Array).size() == 1
		and ((chapter["reinforcements"] as Array)[0] as Dictionary).get(&"turn", 0) == 2,
		"增援波次应恢复为未消费")
	_expect(not battle._unit_sprites.has(&"hist_rein"), "增援 sprite 未清理")
	_expect(battle.turn.turn_number == 1 and battle.turn.phase == &"player",
		"跨回合回退后回合数应恢复为 T1（现在是 %d/%s）" % [battle.turn.turn_number, str(battle.turn.phase)])
	_expect(not bool(p1[&"hasActed"]) and not bool(p2[&"hasActed"]),
		"跨回合回退后单位行动标志应复位")
	_expect(battle.grid.unit_at(0, 0).get("id", &"") == &"hist_p1"
		and battle.grid.unit_at(0, 1).get("id", &"") == &"hist_p2",
		"回退后 grid 占位未恢复")
	_expect(battle._action_history.labels().is_empty(), "跨回合回退后历史应截断")

	# ---- 7) 记录 Tab UI：有条目时生成按钮，条数一致 ----
	battle._finish_player_action(p1, "攻击 强盗")
	var hist_vbox: VBoxContainer = battle.battle_ui._hud.history_list
	var button_count := 0
	for c in hist_vbox.get_children():
		if c is Button:
			button_count += 1
	_expect(button_count == 1, "记录 Tab 应渲染 1 个行动按钮，实际 %d" % button_count)

	battle.queue_free()
	await process_frame
