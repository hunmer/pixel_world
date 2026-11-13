## tests/battle_3d_contract.gd — B1/B2 真实 Camera3D 战场集成契约
extends SceneTree

const WorldToChapter = preload("res://scripts/core/world_to_chapter.gd")
const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
		assert(condition, message)


## x=DirectionalLight3D 数量，y=WorldEnvironment 数量；递归覆盖场景内真实节点。
func _lighting_counts(node: Node) -> Vector2i:
	var counts := Vector2i.ZERO
	if node is DirectionalLight3D:
		counts.x += 1
	if node is WorldEnvironment:
		counts.y += 1
	for child in node.get_children():
		counts += _lighting_counts(child)
	return counts


func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	if world.get_script() == null:
		_expect(false, "main.gd 编译失败，测试不能作为通过依据")
		world.queue_free()
		quit(1)
		return
	world.seed = 42
	root.add_child(world)
	await process_frame
	var chapter: Dictionary = WorldToChapter.world_to_chapter(
		world._terrain_sampler, world._player_cell, 4, 42
	)
	world._enter_battle_inline(chapter)
	var battle = world._battle_system
	await process_frame
	_expect(battle.mode == battle.Mode.ANIMATING, "B1 遭遇演出期间未锁定战斗输入")
	await battle.battle_ready
	_expect(battle.battle_ui != null, "BattleUI 初始化失败，开场链无效")
	if battle.battle_ui == null:
		world._exit_battle(&"contract")
		quit(1)
		return
	_expect(world._battle_active and world._battle_system != null, "B1 未能进入")
	_expect(world._cam is Camera3D and world._cam.current, "B1 未复用主世界 Camera3D")
	_expect(battle._b1_mode and battle.renderer == null, "B1 错误创建了 B2 地形")
	_expect(battle._sunlight == null, "B1 不应重复创建战斗太阳")
	_expect(_lighting_counts(world) == Vector2i(1, 1), "B1 主世界应有且只有一组太阳与环境节点")
	_expect(_lighting_counts(battle) == Vector2i.ZERO, "B1 战斗节点不应持有额外灯光或环境")
	_expect(not battle._unit_sprites.is_empty(), "B1 没有战棋单位")
	for sprite in battle._unit_sprites.values():
		_expect(sprite is Node3D, "B1 单位不是 Node3D")
		_expect(sprite.get("portrait") is Sprite3D, "B1 单位立绘不是 Sprite3D")
	var unit: Dictionary = battle.grid.units["u_enemy_0"]
	var unit_sprite: Node3D = battle._unit_sprites[unit.id]
	var unit_world_before: Vector3 = unit_sprite.global_position
	var unit_screen_before: Vector2 = world._cam.unproject_position(unit_world_before)
	world._cam.snap_to_angle(rad_to_deg(world._cam.yaw_radians) + 90.0)
	world._cam.advance(1.0)
	await process_frame
	_expect(unit_sprite.global_position.is_equal_approx(unit_world_before), "B1 旋转改变了单位逻辑世界位置")
	_expect(world._cam.unproject_position(unit_world_before).distance_to(unit_screen_before) > 1.0,
		"B1 旋转没有改变单位屏幕投影")
	var drag_start := InputEventMouseButton.new()
	drag_start.button_index = MOUSE_BUTTON_MIDDLE
	drag_start.pressed = true
	drag_start.ctrl_pressed = true
	drag_start.position = Vector2(100, 100)
	world._handle_battle_camera_input(drag_start)
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.ctrl_pressed = true
	drag_motion.position = Vector2(150, 100)
	var drag_yaw_before: float = world._cam.target_yaw_radians
	world._handle_battle_camera_input(drag_motion)
	_expect(absf(world._cam.target_yaw_radians - drag_yaw_before + 50.0 * 0.008) < 0.001,
		"B1 Ctrl+中键拖转未驱动 Camera3D")
	var drag_end := InputEventMouseButton.new()
	drag_end.button_index = MOUSE_BUTTON_MIDDLE
	drag_end.pressed = false
	drag_end.position = Vector2(150, 100)
	world._handle_battle_camera_input(drag_end)
	var world_cell: Vector2i = battle._world_origin + unit.position
	var picked: Vector2i = world.screen_to_cell(world._grid_to_screen(
		world_cell, float(world.cell_stand_level(world_cell))
	))
	_expect(picked == world_cell, "B1 Camera3D 单位格拾取失败")
	# 结算信号链：ResultPresentation.result_finished 之后才允许 main._exit_battle。
	for battle_unit in battle.grid.units.values():
		if battle_unit.faction == &"enemy":
			battle_unit.isDead = true
	battle._check_battle_end()
	await process_frame
	battle.battle_ui.skip_presentation()
	await process_frame
	await process_frame
	_expect(not world._battle_active and world._battle_system == null, "B1 结算后退出状态未恢复")
	_expect(world._player.visible == world._player_visible_backup, "B1 退出未恢复玩家可见性")

	world.queue_free()
	await process_frame
	await process_frame
	root.get_node("SceneArgs").set("battle_args", {"chapter": chapter, "hosting": false})
	var b2 = load("res://scenes/Battle.tscn").instantiate()
	if b2.get_script() == null:
		_expect(false, "battle.gd 编译失败，测试不能作为通过依据")
		b2.queue_free()
		quit(1)
		return
	root.add_child(b2)
	await process_frame
	_expect(b2.mode == b2.Mode.ANIMATING, "B2 遭遇演出期间未锁定战斗输入")
	await b2.battle_ready
	_expect(not b2._b1_mode, "B2 被误判为 B1")
	_expect(b2.board.camera is Camera3D and b2.board.camera.current, "B2 未启用 Camera3D")
	_expect(b2.renderer._terrain_3d != null, "B2 未创建共享真实 3D 地形")
	_expect(b2._sunlight != null, "B2 未创建静态白昼 SunlightSystem")
	_expect(_lighting_counts(b2) == Vector2i(1, 1), "B2 应有且只有一个方向光和一个环境节点")
	var b2_sun: DirectionalLight3D = b2._sunlight.sun
	_expect(b2_sun != null and b2_sun.light_energy > 0.0, "B2 静态白昼没有有效直射光")
	_expect(b2_sun.global_basis.z.y > 0.0, "B2 太阳位于地平线以下")
	_expect(b2_sun.shadow_enabled, "B2 地形太阳未启用真实阴影")
	var b2_environment: Environment = b2._sunlight.world_environment.environment
	_expect(b2_environment != null and b2_environment.ambient_light_energy > 0.0, "B2 缺少有效环境光")
	_expect(b2._sunlight._clock == null, "B2 静态白昼不应绑定主世界时钟")
	_expect(not b2._unit_sprites.is_empty(), "B2 没有战棋单位")
	var first_unit: Dictionary = b2.grid.units.values()[0]
	var first_sprite: Node3D = b2._unit_sprites[first_unit.id]
	var expected_world := IsoProjection.grid_to_world(
		first_unit.position, float(b2.renderer.visual_top_level(first_unit.position.x, first_unit.position.y))
	)
	_expect(first_sprite.global_position.distance_to(expected_world) < 0.001, "B2 单位未落在可视柱顶")
	var cell_screen: Vector2 = b2.renderer.top_center_for(first_unit.position.x, first_unit.position.y)
	_expect(b2.renderer.pick_cell(cell_screen, root.get_visible_rect().size) == first_unit.position,
		"B2 Camera3D 柱顶拾取失败")
	b2.range_overlay.highlight_range({"0,0": 1}, {}, {})
	await process_frame
	_expect(not b2.range_overlay._range_markers.is_empty(), "B2 范围标记未创建")
	var marker = b2.range_overlay._range_markers[0]
	var corners_before: Array = marker.corners.duplicate()
	var mesh_ids_before: Array = []
	for chunk in b2.renderer._terrain_3d._chunks.values():
		for child in chunk.get_children():
			mesh_ids_before.append(child.get_instance_id())
	var b2_target_before: float = b2.board.camera.target_yaw_radians
	var rotate_key := InputEventKey.new()
	rotate_key.keycode = KEY_X
	rotate_key.pressed = true
	b2._unhandled_input(rotate_key)
	_expect(absf(angle_difference(b2.board.camera.target_yaw_radians,
		wrapf(b2_target_before + PI * 0.5, 0.0, TAU))) < 0.001,
		"B2 X 键没有旋转共享 Camera3D: before=%s target=%s" % [rad_to_deg(b2_target_before), rad_to_deg(b2.board.camera.target_yaw_radians)])
	b2.board.camera.advance(1.0)
	await process_frame
	await process_frame
	_expect(first_sprite.global_position.is_equal_approx(expected_world), "B2 旋转改变了单位世界位置")
	_expect(marker.corners != corners_before, "B2 范围标记未随 Camera3D 重投影")
	var mesh_ids_after: Array = []
	for chunk in b2.renderer._terrain_3d._chunks.values():
		for child in chunk.get_children():
			mesh_ids_after.append(child.get_instance_id())
	_expect(mesh_ids_after == mesh_ids_before, "B2 旋转重建了地形 mesh")
	b2.queue_free()
	await process_frame
	if failures == 0:
		print("BATTLE_3D_CONTRACT_OK")
	quit(0 if failures == 0 else 1)
