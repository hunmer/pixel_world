## tests/battle_presentation_hooks_contract.gd — 结算视觉/音效消费者与 B1 附加相机 kick 契约
extends SceneTree

const WorldToChapter = preload("res://scripts/core/world_to_chapter.gd")

var failures := 0

## 测试密闭性：相机 kick 断言只对传统取景链成立。用户本地 user://settings.cfg 若开启
## 沉浸式演出（immersive_presentation=true），ImmersiveCamera 会在行动演出期合法接管相机
## （平移+旋转），kick 断言必然观察到位移来源混杂。契约统一固定关闭后测 kick 通道本身。
## 直接改内存变量（不走 set_battle_immersive_presentation 的 save()），退出前恢复原值，
## 不落盘、不污染开发者本地配置。
var _immersive_saved := false


func _pin_immersive_presentation() -> void:
	var settings: Node = root.get_node("Settings")
	_immersive_saved = bool(settings.get("battle_immersive_presentation"))
	settings.set("battle_immersive_presentation", false)


func _restore_immersive_presentation() -> void:
	root.get_node("Settings").set("battle_immersive_presentation", _immersive_saved)


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _first_unit(battle: Node, faction: StringName) -> Dictionary:
	for unit in battle.chapter.playerUnits + battle.chapter.enemyUnits:
		if unit.faction == faction:
			return unit
	return {}


func _sample_b1_kick(world: Node, sample: Dictionary, base_position: Vector3, base_lateral: Vector3) -> void:
	await world.get_tree().create_timer(0.08).timeout
	if not is_instance_valid(world):
		return
	var offset := world.get("_battle_camera_kick_offset") as Vector3
	var actual_delta := (world._cam.global_position as Vector3) - base_position
	# 正交 size 推近会同步改变 HUD 预留侧栏的横向补偿；除此之外只允许 additive。
	var expected_delta := offset + (world._cam._reserved_lateral_world() as Vector3) - base_lateral
	sample["expected_delta"] = expected_delta
	sample["offset"] = offset.length()
	sample["offset_vector"] = offset
	sample["actual_delta"] = actual_delta
	sample["position_delta"] = actual_delta.length()


func _exercise_camera_kick(world: Node, battle: Node) -> void:
	var attacker := _first_unit(battle, &"player")
	var defender := _first_unit(battle, &"enemy")
	attacker[&"hp"] = 999
	defender[&"hp"] = 999
	battle.turn_director.set_pref(attacker.id, &"anim_speed", 1.0)
	battle.turn_director.set_pref(attacker.id, &"skip_anim", false)
	var base_position: Vector3 = world._cam.global_position
	var base_lateral: Vector3 = world._cam._reserved_lateral_world()
	var base_yaw: float = world._cam.yaw_radians
	var base_size: float = world._cam.size
	var sample := {"offset": 0.0, "position_delta": 0.0}
	var on_phase := func(phase: StringName, _event: Dictionary) -> void:
		if phase == &"strike":
			_sample_b1_kick(world, sample, base_position, base_lateral)
	battle.action_anim.phase_started.connect(on_phase)
	await battle._resolve_combat(attacker, defender, Callable())
	battle.action_anim.phase_started.disconnect(on_phase)
	_expect(float(sample["offset"]) > 0.0001, "B1 ActionAnim strike 未产生附加相机位移")
	_expect(float(sample["position_delta"]) > 0.0001, "B1 主相机每帧取景仍覆盖攻击推近")
	_expect(
		(sample.get("actual_delta", Vector3.ZERO) as Vector3).is_equal_approx(
			sample.get("expected_delta", Vector3.ZERO)
		),
		"B1 strike 存在 additive/size 之外的相机位置写入: actual=%s expected=%s" % [
			str(sample.get("actual_delta", Vector3.ZERO)), str(sample.get("expected_delta", Vector3.ZERO))
		]
	)
	_expect((world.get("_battle_camera_kick_offset") as Vector3).is_zero_approx(), "攻击结束附加相机位移未清零")
	_expect((world._cam.global_position as Vector3).distance_to(base_position) < 0.001, "攻击结束世界相机位置未恢复")
	_expect(is_equal_approx(world._cam.yaw_radians, base_yaw), "攻击推近改变世界相机正交角度")
	_expect(is_equal_approx(world._cam.size, base_size), "攻击推近未恢复正交 size")


func _sample_b2_kick(battle: Node, sample: Dictionary, base_position: Vector3, base_rotation: Vector3) -> void:
	await battle.get_tree().create_timer(0.08).timeout
	if not is_instance_valid(battle):
		return
	var camera: Camera3D = battle.board.camera
	var offset := camera.presentation_offset as Vector3
	var actual_delta := camera.global_position - base_position
	sample["offset"] = offset.length()
	sample["offset_vector"] = offset
	sample["actual_delta"] = actual_delta
	sample["position_delta"] = actual_delta.length()
	sample["rotation_preserved"] = camera.global_rotation.is_equal_approx(base_rotation)
	sample["rotation_during"] = camera.global_rotation
	sample["base_rotation"] = base_rotation


func _exercise_b2_camera_kick(battle: Node) -> void:
	# BattleReady 后对峙必须已同时还原角度属性与实际变换。
	var camera: Camera3D = battle.board.camera
	var attacker := _first_unit(battle, &"player")
	var defender := _first_unit(battle, &"enemy")
	attacker[&"hp"] = 999
	defender[&"hp"] = 999
	battle.turn_director.set_pref(attacker.id, &"anim_speed", 1.0)
	battle.turn_director.set_pref(attacker.id, &"skip_anim", false)
	var base_position := camera.global_position
	var base_rotation := camera.global_rotation
	var base_size := camera.size
	var sample := {"offset": 0.0, "position_delta": 0.0, "rotation_preserved": false}
	var on_phase := func(phase: StringName, _event: Dictionary) -> void:
		if phase == &"strike":
			_sample_b2_kick(battle, sample, base_position, base_rotation)
	battle.action_anim.phase_started.connect(on_phase)
	await battle._resolve_combat(attacker, defender, Callable())
	battle.action_anim.phase_started.disconnect(on_phase)
	_expect(float(sample["offset"]) > 0.0001, "B2 ActionAnim strike 未产生 presentation_offset")
	_expect(float(sample["position_delta"]) > 0.0001, "B2 IsoCamera 未应用攻击附加位移")
	_expect(
		(sample.get("actual_delta", Vector3.ZERO) as Vector3).is_equal_approx(
			sample.get("offset_vector", Vector3.ZERO)
		),
		"B2 strike 存在 presentation_offset 之外的相机位置写入"
	)
	_expect(
		bool(sample["rotation_preserved"]),
		"B2 攻击附加位移改变了正交相机姿态: base=%s during=%s" % [
			str(sample.get("base_rotation")), str(sample.get("rotation_during"))
		]
	)
	_expect((camera.presentation_offset as Vector3).is_zero_approx(), "B2 攻击结束 presentation_offset 未清零")
	_expect(
		camera.global_position.distance_to(base_position) < 0.001,
		"B2 攻击结束相机位置未恢复: base=%s actual=%s delta=%f" % [
			str(base_position), str(camera.global_position), camera.global_position.distance_to(base_position)
		]
	)
	_expect(
		camera.global_rotation.is_equal_approx(base_rotation),
		"B2 攻击结束相机姿态未恢复: base=%s actual=%s" % [str(base_rotation), str(camera.global_rotation)]
	)
	_expect(is_equal_approx(camera.size, base_size), "B2 攻击结束相机 size 未恢复")


func _exercise_visual_and_sound_hooks(battle: Node) -> void:
	_expect(battle.battle_ui.cheer_requested.is_connected(battle._on_presentation_cheer), "cheer_requested 无消费者")
	_expect(battle.battle_ui.collapse_requested.is_connected(battle._on_presentation_collapse), "collapse_requested 无消费者")
	_expect(
		battle.battle_ui.presentation_sound_requested.is_connected(battle._on_presentation_sound),
		"presentation_sound_requested 无消费者"
	)
	# 演出 cue 音效按 battle_sfx.gd 设计：先映射为 Sfx 素材名（nameplate→ui_select，victory→victory），
	# 素材存在走真实素材优先路径（不占用程序化回退通道）；映射/素材缺失才回退程序化波形。
	# 两侧都断言，不依赖素材库当下缺哪块。
	var sfx_cues: Dictionary = root.get_node("Sfx").CUES
	battle.battle_ui.presentation_sound_requested.emit(&"nameplate")
	var nameplate_asset: bool = sfx_cues.has(&"ui_select")
	if nameplate_asset:
		_expect(
			not battle._presentation_sound_cache.has(&"nameplate"),
			"名牌 cue 有真实素材（ui_select）时应走 Sfx 优先路径，不应进入程序化波形缓存"
		)
	else:
		_expect(battle._presentation_audio.stream != null, "名牌 cue 缺真实素材时未生成程序化音频")
		_expect(battle._presentation_audio.playing, "名牌 cue 缺真实素材时未实际播放")
	battle.battle_ui.presentation_sound_requested.emit(&"victory")
	if sfx_cues.has(&"victory"):
		_expect(
			not battle._presentation_sound_cache.has(&"victory"),
			"结果 cue 有真实素材（victory）时应走 Sfx 优先路径，不应进入程序化波形缓存"
		)
	else:
		_expect(battle._presentation_sound_cache.has(&"victory"), "结果 cue 缺真实素材时未进入固定波形缓存")
	# 未映射 cue 必然走程序化回退：固定波形生成 + 实际播放 + 入缓存（守护回退通道本身）。
	var cache_before: int = battle._presentation_sound_cache.size()
	battle.battle_ui.presentation_sound_requested.emit(&"contract_probe")
	_expect(battle._presentation_audio.stream != null, "未映射 cue 未回退生成程序化音频")
	_expect(battle._presentation_audio.playing, "未映射 cue 未实际播放")
	_expect(
		battle._presentation_sound_cache.size() == cache_before + 1
			and battle._presentation_sound_cache.has(&"contract_probe"),
		"程序化回退波形未进入固定缓存"
	)

	var player := _first_unit(battle, &"player")
	var sprite: UnitSprite3D = battle._unit_sprites[player.id]
	var hp := int(player.hp)
	var base_position := sprite.global_position
	battle.battle_ui.cheer_requested.emit(player)
	await create_timer(0.07).timeout
	_expect(sprite.global_position.y > base_position.y + 0.01, "胜利 cheer 未驱动存活单位跳跃")
	_expect(int(player.hp) == hp, "胜利跳跃修改了 HP")
	battle._restore_result_visuals()
	_expect(sprite.global_position.is_equal_approx(base_position), "跳跃恢复后显示位置不一致")

	var enemy := _first_unit(battle, &"enemy")
	var collapsed_sprite: UnitSprite3D = battle._unit_sprites[enemy.id]
	enemy[&"isDead"] = true
	collapsed_sprite.update_state()
	var enemy_hp := int(enemy.hp)
	var visual: Node3D = collapsed_sprite.portrait
	var original_rotation := visual.rotation
	battle.battle_ui.collapse_requested.emit(enemy)
	await create_timer(0.30).timeout
	_expect(collapsed_sprite.visible, "失败单位倒地时仍被隐藏")
	_expect(absf(visual.rotation.z + PI * 0.5) < 0.001, "失败单位未旋转到倒地姿态")
	_expect(int(enemy.hp) == enemy_hp, "失败倒地修改了 HP")
	battle._restore_result_visuals()
	_expect(visual.rotation.is_equal_approx(original_rotation), "倒地退出未恢复立绘旋转")
	_expect(not collapsed_sprite.visible, "倒地退出未恢复死亡单位隐藏状态")
	enemy[&"isDead"] = false
	collapsed_sprite.update_state()


func _exercise_result_skip(battle: Node, world: Node) -> void:
	var cheers := [0]
	var on_cheer := func(_unit: Dictionary) -> void:
		cheers[0] += 1
	battle.battle_ui.cheer_requested.connect(on_cheer)
	for enemy in battle.chapter.enemyUnits:
		enemy[&"hp"] = 0
		battle.grid.remove_unit(enemy)
	_expect(battle._units_by_life(&"enemy", false).size() == battle.chapter.enemyUnits.size(), "结果名单丢失已从 grid 移除的死亡单位")
	battle._check_battle_end()
	battle.battle_ui.skip_presentation()
	_expect(cheers[0] > 0, "跳过胜利结果未补发 cheer 钩子")
	_expect(battle._result_visual_states.is_empty(), "结果完成未恢复/清空视觉状态")
	await process_frame
	await process_frame
	_expect((world.get("_battle_camera_kick_offset") as Vector3).is_zero_approx(), "退出战斗后仍残留相机 kick")


func _exercise_defeat_skip(battle: Node) -> void:
	var collapses := [0]
	var on_collapse := func(_unit: Dictionary) -> void:
		collapses[0] += 1
	battle.battle_ui.collapse_requested.connect(on_collapse)
	for player in battle.chapter.playerUnits:
		player[&"hp"] = 0
		battle.grid.remove_unit(player)
	var defeated: Array = battle._units_by_life(&"player", false)
	_expect(defeated.size() == battle.chapter.playerUnits.size(), "败北名单丢失玩家单位")
	battle.battle_ui.result_finished.connect(
		func(_result: StringName, _skipped: bool) -> void:
			battle._restore_result_visuals(),
		CONNECT_ONE_SHOT
	)
	battle.battle_ui.play_result(&"lose", {"chapter_title": "契约"}, [], defeated)
	battle.battle_ui.skip_presentation()
	_expect(collapses[0] == defeated.size(), "跳过败北结果未逐单位补发 collapse 钩子")
	_expect(battle._result_visual_states.is_empty(), "败北跳过未恢复视觉状态")


func _reset_chapter(chapter: Dictionary) -> void:
	for unit in chapter.playerUnits + chapter.enemyUnits:
		unit[&"hp"] = int(unit.stats.hp)
		unit[&"isDead"] = false
		unit[&"hasActed"] = false
		unit[&"hasMoved"] = false


func _run() -> void:
	_pin_immersive_presentation()
	var world = load("res://main.tscn").instantiate()
	if world.get_script() == null:
		_expect(false, "main.gd 编译失败")
		_restore_immersive_presentation()
		quit(1)
		return
	world.seed = 42
	root.add_child(world)
	await process_frame
	var chapter: Dictionary = WorldToChapter.world_to_chapter(world._terrain_sampler, world._player_cell, 4, 42)
	world._enter_battle_inline(chapter)
	var battle = world._battle_system
	await battle.battle_ready
	await _exercise_visual_and_sound_hooks(battle)
	await _exercise_camera_kick(world, battle)
	await _exercise_result_skip(battle, world)
	world.queue_free()
	await process_frame
	await process_frame

	_reset_chapter(chapter)
	root.get_node("SceneArgs").set("battle_args", {"chapter": chapter, "hosting": false})
	var b2 = load("res://scenes/Battle.tscn").instantiate()
	if b2.get_script() == null:
		_expect(false, "battle.gd 编译失败")
		_restore_immersive_presentation()
		quit(1)
		return
	root.add_child(b2)
	await b2.battle_ready
	_expect((b2.board.camera.presentation_offset as Vector3).is_zero_approx(), "连续战斗继承上一场相机附加位移")
	await _exercise_b2_camera_kick(b2)
	_exercise_defeat_skip(b2)
	b2.queue_free()
	await process_frame
	if failures == 0:
		print("BATTLE_PRESENTATION_HOOKS_CONTRACT_OK")
	_restore_immersive_presentation()
	quit(0 if failures == 0 else 1)
