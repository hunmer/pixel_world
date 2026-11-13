## tests/battle_movement_contract.gd — 跨高度移动、移动后镜头与敌方威胁箭头回归
extends SceneTree

const WorldToChapter = preload("res://scripts/core/world_to_chapter.gd")
const BlockLayout = preload("res://scripts/core/block_layout.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)


## 移动结束后（idle 姿态）立绘呈现必须与最后一步移动朝向一致：
## 新精灵图按 CharacterSheet 等距约定（front/back/side+镜像）解析；
## 旧立绘回退路径保持"按屏幕水平方向翻转"的原有约定。
func _expect_unit_facing_matches_last_step(sprite: UnitSprite3D, label: String) -> void:
	var cam: Camera3D = sprite._active_camera()
	var delta := CharacterSheet.facing_screen_delta(cam, sprite.global_position, sprite._facing_world)
	if sprite._using_sheet:
		var expected := CharacterSheet.resolve_facing(delta)
		var frame: int = expected[&"frame"]
		var atlas := sprite.portrait.texture as AtlasTexture
		_expect(atlas != null and atlas.region.position.x == frame * CharacterSheet.CELL_SIZE,
			"%s 移动后朝向帧与最后一步不一致（应 frame=%d）" % [label, frame])
		_expect(sprite.portrait.flip_h == expected[&"flip"],
			"%s 移动后镜像与等距朝向约定不一致（delta=%s）" % [label, str(delta)])
	elif absf(delta.x) > UnitSprite3D.SCREEN_HORIZONTAL_EPSILON:
		_expect(sprite.portrait.flip_h == ((delta.x > 0.0) != UnitSprite3D.SOURCE_FACES_RIGHT),
			"%s 移动后未按屏幕水平方向翻转立绘" % label)


func _run() -> void:
	await _run_b2()
	await _run_b1()
	if failures == 0:
		print("BATTLE_MOVEMENT_CONTRACT_OK")
	else:
		printerr("BATTLE_MOVEMENT_CONTRACT_FAILED: %d 处失败" % failures)
	quit(0 if failures == 0 else 1)


func _run_b2() -> void:
	var player := UnitFactory.create_random_unit(
		&"move_player", "移动测试", &"player", 1, Vector2i(0, 0),
		ProfessionData.get_profession(&"swordsman")
	)
	var enemy := UnitFactory.create_random_unit(
		&"move_enemy", "弓手", &"enemy", 1, Vector2i(3, 1),
		ProfessionData.get_profession(&"archer")
	)
	var second_enemy := UnitFactory.create_random_unit(
		&"move_enemy_2", "弓手二", &"enemy", 1, Vector2i(2, 2),
		ProfessionData.get_profession(&"archer")
	)
	var rows: Array = []
	for y in range(3):
		var row: Array = []
		for x in range(4):
			row.append(&"mountain" if Vector2i(x, y) == Vector2i(1, 0) else &"plain")
		rows.append(row)
	var chapter := {
		"id": &"movement_contract", "name": "移动契约", "width": 4, "height": 3,
		"map": rows, "playerUnits": [player], "enemyUnits": [enemy, second_enemy],
	}
	root.get_node("SceneArgs").set("battle_args", {"chapter": chapter, "hosting": false})
	var battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	# 开场链（转场/对峙演出）结束后才进入首个玩家回合，固定等待会读到"遭遇战"临时文案。
	await battle.battle_ready
	await process_frame
	await process_frame
	_expect(battle.battle_ui.phase_label.text == "第 1 轮 · 我方行动", "B2 顶部未显示中文当前轮数")
	var player_status: Label = battle.battle_ui._turn_status_labels[&"player"]
	var enemy_status: Label = battle.battle_ui._turn_status_labels[&"enemy"]
	_expect(player_status.text.contains("移动测试 未行动 HP")
		and enemy_status.text.contains("弓手 未行动 HP"), "B2 顶部阵营角色/行动/HP状态不完整")
	var target := Vector2i(1, 0)
	var start_screen: Vector2 = battle._b2_cell_to_screen(0, 0)
	battle._select_unit(player)
	_expect(battle.current_move_range.has("1,0"), "B2 高差目标不在移动指示范围")
	battle._last_path_update_msec = -100
	battle._update_hover_path(target)
	_expect(battle.range_overlay.has_method("threat_arrow_count")
		and battle.range_overlay.threat_arrow_count() == 2,
		"悬停受两名弓手威胁的可达格时应各有一条敌方红色抛物线")
	_expect(battle.range_overlay._path_marker != null
		and battle.range_overlay._path_marker.segments.size() > 0,
		"威胁抛物线不应清掉蓝色移动路径")
	battle._last_path_update_msec = -100
	battle._update_hover_path(Vector2i(3, 1))
	_expect(battle.range_overlay.threat_arrow_count() == 0,
		"从受威胁落点切换到敌方攻击路径时应清除旧威胁抛物线")
	battle._last_path_update_msec = -100
	battle._update_hover_path(target)
	battle._last_path_update_msec = -100
	battle._update_hover_path(Vector2i.ZERO)
	_expect(battle.range_overlay.threat_arrow_count() == 0,
		"悬停不在任何敌方攻击范围内的可达格时不应显示威胁抛物线")
	battle._last_path_update_msec = -100
	battle._update_hover_path(target)
	var target_screen: Vector2 = battle._b2_cell_to_screen(target.x, target.y)
	battle._on_tile_click_at_screen(target_screen)
	await create_timer(0.5).timeout
	_expect(player.position == target and battle.grid.unit_at(target.x, target.y).get("id", &"") == player.id,
		"B2 点击不同 z 的移动格后单位未到目标（position=%s）" % str(player.position))
	_expect(battle.mode == battle.Mode.MENU and battle.battle_ui.has_open_menu(),
		"B2 跨高度移动完成后行动菜单未打开")
	_expect(battle.range_overlay.threat_arrow_count() == 0,
		"进入移动后行动菜单时应清除威胁抛物线")
	var sprite: UnitSprite3D = battle._unit_sprites[player.id]
	_expect_unit_facing_matches_last_step(sprite, "B2")
	player.hasActed = true
	battle.battle_ui.update_unit_sprite(player)
	await process_frame
	await process_frame
	_expect(sprite.visible and is_equal_approx(sprite.portrait.modulate.a, 1.0),
		"B2 行动结束后存活单位被半透明裁剪/隐藏")
	_expect(player_status.text.contains("移动测试 已行动 HP"), "B2 行动结束后顶部状态未实时刷新")
	var focus_before: Vector3 = battle.board.camera.focus_position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.position = Vector2(900, 600)
	battle._unhandled_input(press)
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(950, 630)
	drag.relative = Vector2(50, 30)
	battle._unhandled_input(drag)
	_expect(not battle.board.camera.focus_position.is_equal_approx(focus_before),
		"B2 移动完成后中键拖拽不能平移镜头")
	press.pressed = false
	press.position = drag.position
	battle._unhandled_input(press)
	battle.queue_free()
	await process_frame
	await process_frame


func _run_b1() -> void:
	var world = load("res://main.tscn").instantiate()
	world.seed = 42
	root.add_child(world)
	await process_frame
	var chapter: Dictionary = WorldToChapter.world_to_chapter(
		world._terrain_sampler, world._player_cell, 4, 42
	)
	world._enter_battle_inline(chapter)
	var battle = world._battle_system
	# B1 同样有开场链：等 BattleReady 再断言顶部轮数，固定等待会读到"遭遇战"。
	await battle.battle_ready
	await process_frame
	await process_frame
	var player: Dictionary = chapter.playerUnits[0]
	_expect(battle.battle_ui.phase_label.text == "第 1 轮 · 我方行动", "B1 顶部未显示中文当前轮数")
	var player_status: Label = battle.battle_ui._turn_status_labels[&"player"]
	_expect(player_status.text.contains(String(player[&"name"]))
		and player_status.text.contains("未行动 HP"), "B1 顶部我方角色/行动/HP状态不完整")
	battle._select_unit(player)
	var start: Vector2i = player.position
	var start_screen: Vector2 = battle._b1_cell_to_screen(start.x, start.y)
	var start_level: int = battle._b1_cell_level(start.x, start.y)
	var target := Vector2i(-1, -1)
	for key in battle.current_move_range.keys():
		var parts := (key as String).split(",")
		var candidate := Vector2i(parts[0].to_int(), parts[1].to_int())
		if candidate != start and battle.grid.unit_at(candidate.x, candidate.y).is_empty() \
				and battle._b1_cell_level(candidate.x, candidate.y) != start_level:
			target = candidate
			break
	_expect(target.x >= 0, "B1 契约场景未找到可达异高度格")
	if target.x >= 0:
		var target_screen: Vector2 = battle._b1_cell_to_screen(target.x, target.y)
		battle._on_tile_click_at_screen(target_screen)
		await create_timer(1.5).timeout
		_expect(player.position == target,
			"B1 点击不同 z 的移动格后单位未到目标（target=%s position=%s）" % [str(target), str(player.position)])
		_expect(battle.mode == battle.Mode.MENU and battle.battle_ui.has_open_menu(),
			"B1 跨高度移动完成后行动菜单未打开")
		var sprite: UnitSprite3D = battle._unit_sprites[player.id]
		_expect_unit_facing_matches_last_step(sprite, "B1")
		player.hasActed = true
		battle.battle_ui.update_unit_sprite(player)
		await process_frame
		await process_frame
		_expect(sprite.visible and is_equal_approx(sprite.portrait.modulate.a, 1.0),
			"B1 行动结束后存活单位被半透明裁剪/隐藏")
		_expect(player_status.text.contains("已行动 HP"), "B1 行动结束后顶部状态未实时刷新")
		var focus_before: Vector3 = world._cam.focus_position
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_MIDDLE
		press.pressed = true
		press.position = Vector2(900, 600)
		world._handle_battle_camera_input(press)
		var drag := InputEventMouseMotion.new()
		drag.position = Vector2(950, 630)
		drag.relative = Vector2(50, 30)
		world._handle_battle_camera_input(drag)
		# process_frame 在节点 _process 前发出；第二帧前已至少完成一次相机应用。
		await process_frame
		await process_frame
		_expect(not world._cam.focus_position.is_equal_approx(focus_before),
			"B1 移动完成后中键拖拽不能平移镜头（offset=%s active=%s before=%s after=%s）" % [
				str(world._battle_cam_offset), str(world._battle_pan_active), str(focus_before), str(world._cam.focus_position)
			])
		press.pressed = false
		press.position = drag.position
		world._handle_battle_camera_input(press)
	world._exit_battle(&"contract")
	world.queue_free()
	await process_frame
	await process_frame
