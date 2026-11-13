## tests/battle_result_presentation_contract.gd — 开战/胜负/章节末演出 UI 契约
## 运行：godot --headless --path . --script res://tests/battle_result_presentation_contract.gd
## 覆盖：0.15s 名牌/Boss、自然完成、立即跳过、奖励只读与最终值、失败褪色/倒地钩子、
##       键盘跳过、BattleUI 公开包装、完成信号幂等。
extends SceneTree

const PresentationScript = preload("res://scripts/battle/result_presentation.gd")
# 预加载脚本同时作为类型，保证干净 headless 不依赖 global class cache。
const BattleUIScript = preload("res://scripts/battle/battle_ui.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _noop() -> void:
	pass


func _label(presentation: Node, node_name: String) -> Label:
	return presentation.find_child(node_name, true, false) as Label


func _flush_frames() -> void:
	await process_frame
	await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var presentation := PresentationScript.new()
	_expect(presentation != null, "ResultPresentation 可实例化")
	if presentation == null:
		_finish(presentation)
		return
	root.add_child(presentation)
	await _flush_frames()
	_expect(is_equal_approx(PresentationScript.NAMEPLATE_INTERVAL, 0.15), "名牌节奏必须为 0.15s")
	_expect(not presentation.is_playing(), "初始无活动演出")

	await _test_opening_natural(presentation)
	await _test_opening_skip(presentation)
	await _test_victory_natural(presentation)
	await _test_chapter_skip(presentation)
	await _test_defeat_key_skip(presentation)
	await _test_battle_ui_wrapper()

	_finish(presentation)


func _test_opening_natural(presentation: PresentationScript) -> void:
	var names: Array[String] = []
	var bosses: Array[String] = []
	var sounds: Array[StringName] = []
	var finished: Array[bool] = []
	presentation.nameplate_shown.connect(func(unit: Dictionary, _index: int): names.append(String(unit.id)))
	presentation.boss_banner_shown.connect(func(unit: Dictionary): bosses.append(String(unit.name)))
	presentation.sound_requested.connect(func(cue: StringName): sounds.append(cue))
	presentation.opening_finished.connect(func(skipped: bool): finished.append(skipped))
	var units := [
		{&"id": &"p1", &"name": "艾琳", &"faction": &"player", &"level": 3, &"classId": &"swordsman"},
		{&"id": &"e1", &"name": "荒原狼", &"faction": &"enemy", &"level": 2},
	]
	var boss := {&"id": &"boss", &"name": "熔核君王", &"title": "灰烬之主"}
	presentation.play_opening(units, boss)
	_expect(presentation.is_playing(), "开战后演出进入活动态")
	_expect(presentation._nameplate_rows.size() == 2, "按输入创建两张名牌")
	_expect(presentation._nameplate_rows[0].visible and not presentation._nameplate_rows[1].visible, "名牌逐个而非同时亮出")
	_expect(not presentation._boss_panel.visible, "Boss 横幅等待名牌后播放")
	await create_timer(1.25).timeout
	_expect(names == ["p1", "e1"], "自然完成按输入顺序亮名牌（实际 %s）" % str(names))
	_expect(bosses == ["熔核君王"], "Boss 横幅只触发一次")
	_expect(sounds.count(&"nameplate") == 2 and sounds.count(&"boss") == 1, "名牌/Boss 提供音效钩子")
	_expect(finished == [false], "开战自然完成信号一次且 skipped=false")
	_expect(not presentation.is_playing(), "开战自然完成后解除活动态")
	_expect(not presentation._opening_root.visible, "开战完成后隐藏开场层")
	_expect(presentation.mouse_filter == Control.MOUSE_FILTER_IGNORE, "开战结束恢复棋盘输入")
	for connection in presentation.nameplate_shown.get_connections():
		presentation.nameplate_shown.disconnect(connection.callable)
	for connection in presentation.boss_banner_shown.get_connections():
		presentation.boss_banner_shown.disconnect(connection.callable)
	for connection in presentation.sound_requested.get_connections():
		presentation.sound_requested.disconnect(connection.callable)
	for connection in presentation.opening_finished.get_connections():
		presentation.opening_finished.disconnect(connection.callable)
	await _flush_frames()


func _test_opening_skip(presentation: PresentationScript) -> void:
	var name_count := [0]
	var boss_count := [0]
	var finished: Array[bool] = []
	presentation.nameplate_shown.connect(func(_unit: Dictionary, _index: int): name_count[0] += 1)
	presentation.boss_banner_shown.connect(func(_unit: Dictionary): boss_count[0] += 1)
	presentation.opening_finished.connect(func(skipped: bool): finished.append(skipped))
	presentation.play_opening([
		{&"id": &"p1", &"name": "甲"},
		{&"id": &"p2", &"name": "乙"},
		{&"id": &"e1", &"name": "丙"},
	], {&"name": "Boss", &"title": "称号"})
	presentation.skip()
	_expect(name_count[0] == 3 and boss_count[0] == 1, "立即跳过补齐全部名牌与 Boss 事件")
	_expect(finished == [true], "开战跳过完成信号一次")
	_expect(not presentation.is_playing(), "开战跳过后无活动演出")
	for row in presentation._nameplate_rows:
		_expect(row.visible and is_equal_approx(row.modulate.a, 1.0), "跳过名牌落最终可见状态")
	_expect(presentation._boss_panel.visible and is_equal_approx(presentation._boss_panel.modulate.a, 1.0), "跳过 Boss 落最终可见状态")
	presentation.skip()
	await create_timer(0.60).timeout
	_expect(finished.size() == 1 and name_count[0] == 3 and boss_count[0] == 1, "重复 skip/旧协程不重复完成或补发事件")
	for connection in presentation.nameplate_shown.get_connections():
		presentation.nameplate_shown.disconnect(connection.callable)
	for connection in presentation.boss_banner_shown.get_connections():
		presentation.boss_banner_shown.disconnect(connection.callable)
	for connection in presentation.opening_finished.get_connections():
		presentation.opening_finished.disconnect(connection.callable)
	await _flush_frames()


func _test_victory_natural(presentation: PresentationScript) -> void:
	var loot: Array[String] = []
	var cheers: Array[String] = []
	var finished: Array = []
	presentation.loot_shown.connect(func(entry: Dictionary, _index: int): loot.append(String(entry.name)))
	presentation.cheer_requested.connect(func(unit: Dictionary): cheers.append(String(unit.id)))
	presentation.result_finished.connect(func(result: StringName, skipped: bool): finished.append([result, skipped]))
	var data := {
		&"loot": [{&"name": "铁剑", &"count": 1}, {&"name": "回复药", &"count": 2}],
		&"exp": 90,
		&"gold": 30,
	}
	presentation.play_result(&"win", data, [{&"id": &"p1"}, {&"id": &"p2"}])
	_expect(cheers == ["p1", "p2"], "胜利为每个存活单位发欢呼钩子")
	_expect(presentation._loot_rows.size() == 2, "按已有战利品创建两行")
	_expect(presentation._loot_rows[0].visible and not presentation._loot_rows[1].visible, "战利品逐条弹出")
	await create_timer(1.35).timeout
	_expect(loot == ["铁剑", "回复药"], "自然结算按顺序展示全部战利品")
	_expect(finished == [[&"win", false]], "胜利自然完成信号一次")
	_expect(_label(presentation, "ExpValue") != null and _label(presentation, "ExpValue").text == "90", "EXP 滚动结束落最终值")
	_expect(_label(presentation, "GoldValue") != null and _label(presentation, "GoldValue").text == "30", "金币滚动结束落最终值")
	_expect(not presentation.is_playing(), "胜利自然完成后无活动协程")
	_expect(presentation._result_root.visible and presentation.mouse_filter == Control.MOUSE_FILTER_STOP, "结果保留并屏蔽棋盘点击")
	for connection in presentation.loot_shown.get_connections():
		presentation.loot_shown.disconnect(connection.callable)
	for connection in presentation.cheer_requested.get_connections():
		presentation.cheer_requested.disconnect(connection.callable)
	for connection in presentation.result_finished.get_connections():
		presentation.result_finished.disconnect(connection.callable)
	await _flush_frames()


func _test_chapter_skip(presentation: PresentationScript) -> void:
	var loot_count := [0]
	var finished: Array = []
	presentation.loot_shown.connect(func(_entry: Dictionary, _index: int): loot_count[0] += 1)
	presentation.result_finished.connect(func(result: StringName, skipped: bool): finished.append([result, skipped]))
	var data := {
		&"loot": [{&"item_id": &"iron_sword", &"quantity": 2}, {&"item_name": "水晶", &"amount": 1}],
		&"exp": 120,
		&"gold": 45,
		&"chapter_title": "第二章 · 风止之谷",
	}
	var before := data.duplicate(true)
	presentation.play_chapter_result(data, [{&"id": &"p1"}])
	presentation.skip()
	_expect(data == before, "演出不修改调用方奖励数据")
	_expect(loot_count[0] == 2, "章节跳过补齐逐条战利品事件")
	_expect(finished == [[&"win", true]], "章节结果复用 win 且 skipped=true")
	_expect(_label(presentation, "ExpValue").text == "120" and _label(presentation, "GoldValue").text == "45", "跳过滚动直接落 EXP/金币最终值")
	for row in presentation._loot_rows:
		_expect(row.visible and is_equal_approx(row.modulate.a, 1.0), "跳过战利品落最终可见状态")
	_expect(presentation._chapter_card.visible, "章节末标题卡跳过也显示")
	_expect(_label(presentation, "ChapterName").text == "第二章 · 风止之谷", "章节标题卡使用传入章节名")
	_expect(not presentation.get_node("SkipButton").visible, "完成后隐藏跳过按钮")
	presentation.skip()
	await create_timer(0.90).timeout
	_expect(finished.size() == 1 and loot_count[0] == 2, "章节旧协程不会二次完成或发奖事件")
	for connection in presentation.loot_shown.get_connections():
		presentation.loot_shown.disconnect(connection.callable)
	for connection in presentation.result_finished.get_connections():
		presentation.result_finished.disconnect(connection.callable)
	await _flush_frames()


func _test_defeat_key_skip(presentation: PresentationScript) -> void:
	var collapsed: Array[String] = []
	var finished: Array = []
	presentation.collapse_requested.connect(func(unit: Dictionary): collapsed.append(String(unit.id)))
	presentation.result_finished.connect(func(result: StringName, skipped: bool): finished.append([result, skipped]))
	presentation.play_result(&"lose", {&"return_hint": "返回世界地图"}, [], [{&"id": &"p1"}, {&"id": &"p2"}])
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = true
	presentation._input(event)
	_expect(collapsed == ["p1", "p2"], "失败为每个指定单位发倒地钩子")
	_expect(finished == [[&"lose", true]], "Space 可跳过失败且只完成一次")
	_expect(is_equal_approx(float(presentation._fade_material.get_shader_parameter("fade_amount")), 1.0), "失败跳过直接落完全褪色")
	_expect(_label(presentation, "ReturnHint").text == "返回世界地图", "失败显示传入返回提示")
	await create_timer(0.70).timeout
	_expect(finished.size() == 1, "失败褪色旧协程不重复完成")
	for connection in presentation.collapse_requested.get_connections():
		presentation.collapse_requested.disconnect(connection.callable)
	for connection in presentation.result_finished.get_connections():
		presentation.result_finished.disconnect(connection.callable)
	await _flush_frames()


func _test_battle_ui_wrapper() -> void:
	var ui := BattleUIScript.new()
	root.add_child(ui)
	ui.build(Callable(self, "_noop"), Callable(self, "_noop"), Callable(self, "_noop"))
	await _flush_frames()
	_expect(ui.result_presentation != null, "BattleUI.build 初始化 ResultPresentation")
	var finished: Array = []
	ui.presentation_finished.connect(func(kind: StringName, skipped: bool): finished.append([kind, skipped]))
	ui.play_chapter_result({&"chapter_title": "终章", &"exp": 7, &"gold": 3})
	ui.skip_presentation()
	_expect(finished == [[&"win", true]], "BattleUI 转发通用完成信号")
	_expect(not ui.is_presentation_active(), "BattleUI 活动态查询与跳过一致")
	_expect(ui.phase_label.text == "章节完成 · 结算", "BattleUI 章节末更新回合标题")
	_expect(ui.end_turn_btn.disabled, "结算禁用结束回合")
	await _flush_frames()
	ui.queue_free()
	await _flush_frames()


func _finish(presentation: Node) -> void:
	if is_instance_valid(presentation):
		presentation.queue_free()
		await process_frame
	if failures.is_empty():
		print("BATTLE_RESULT_PRESENTATION_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
