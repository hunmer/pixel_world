## tests/action_anim_contract.gd — 四模板时间轴、打击镜头、状态恢复与托管跳过契约。
extends SceneTree

const AttackEventScript = preload("res://scripts/systems/attack_event.gd")
const ActionAnimScript = preload("res://scripts/battle/action_anim.gd")
const UnitSpriteScript = preload("res://scripts/iso/unit_sprite.gd")
const Director = preload("res://scripts/battle/turn_director.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok: %s" % message)
	else:
		failures += 1
		printerr("  FAIL: %s" % message)


func _unit(id: StringName, faction: StringName, cell: Vector2i) -> Dictionary:
	return {
		&"id": id, &"name": String(id), &"classId": &"swordsman", &"faction": faction,
		&"position": cell, &"hp": 14, &"isDead": false,
	}


func _sprite(unit: Dictionary, at: Vector3) -> UnitSprite3D:
	var sprite: UnitSprite3D = UnitSpriteScript.new()
	sprite.unit = unit
	var portrait := Sprite3D.new()
	portrait.name = "Portrait"
	sprite.portrait = portrait
	sprite.add_child(portrait)
	root.add_child(sprite)
	sprite.global_position = at
	return sprite


func _event(anim_spec: StringName, kind: StringName = &"normal") -> Dictionary:
	var attacker := _unit(&"attacker", &"player", Vector2i(0, 0))
	var target := _unit(&"target", &"enemy", Vector2i(1, 0))
	var impact := AttackEventScript.make_impact(attacker, target, true, 6, 20, 14, false, true, &"fire")
	return {
		&"version": 1, &"kind": kind, &"attacker_id": &"attacker", &"attacker_cell": Vector2i(0, 0),
		&"primary_target_id": &"target", &"skill_id": &"", &"anim": anim_spec, &"element": &"fire",
		&"impacts": [impact], &"effective": true, &"weakness": true,
		&"hitstop": AttackEventScript.WEAKNESS_HITSTOP_SECONDS, &"statuses": [],
	}


func _run() -> void:
	print("== action_anim_contract ==")
	var attacker_unit := _unit(&"attacker", &"player", Vector2i(0, 0))
	var target_unit := _unit(&"target", &"enemy", Vector2i(1, 0))
	var attacker := _sprite(attacker_unit, Vector3(-0.7, 0.0, 0.0))
	var target := _sprite(target_unit, Vector3(0.7, 0.0, 0.0))
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	camera.global_position = Vector3(4.0, 5.0, 4.0)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var camera_position := camera.global_position
	var camera_size := camera.size
	var camera_basis := camera.global_basis
	var attacker_position := attacker.global_position
	var target_position := target.global_position
	var attacker_scale := attacker.scale
	var target_modulate := target.portrait.modulate

	var anim = ActionAnimScript.new()
	root.add_child(anim)
	var phases: Array = []
	var hit_camera_sizes: Array = []
	var hit_camera_positions: Array = []
	var impacts: Array = []
	var floats: Array = []
	var finishes: Array = []
	anim.phase_started.connect(func(phase: StringName, _event: Dictionary):
		phases.append(phase)
		if phase == &"hit":
			hit_camera_sizes.append(camera.size)
			hit_camera_positions.append(camera.global_position)
	)
	anim.impact_presented.connect(func(impact: Dictionary): impacts.append(impact))
	anim.float_text_requested.connect(func(unit_id: StringName, text: String, color: Color, font_size: int):
		floats.append({&"unit_id": unit_id, &"text": text, &"color": color, &"font_size": font_size})
	)
	anim.finished.connect(func(event: Dictionary, skipped: bool): finishes.append({&"event": event, &"skipped": skipped}))
	anim.setup({&"attacker": attacker, &"target": target}, camera, Callable())

	var normal := _event(&"slash")
	_expect(anim.duration_seconds(normal) <= 1.2, "普攻完整时间轴不超过 1.2s")
	await anim.play(normal)
	_expect(phases == [&"windup", &"step", &"strike", &"hit", &"hitstop", &"return"], "蓄力→踏步→斩击→受击→顿帧→返回顺序")
	_expect(hit_camera_sizes.size() == 1 and is_equal_approx(float(hit_camera_sizes[0]), camera_size / ActionAnimScript.CAMERA_EFFECTIVE_ZOOM_SCALE), "克制命中时镜头推近更强")
	_expect(
		hit_camera_positions.size() == 1 and (hit_camera_positions[0] as Vector3).is_equal_approx(camera_position),
		"ActionAnim 只推近 size，不直接写普通 Camera3D 位置"
	)
	_expect(impacts.size() == 1 and impacts[0][&"hp_after"] == 14, "impact 信号只读结算快照")
	_expect(floats.size() == 1 and String(floats[0][&"text"]).contains("克制"), "克制元素伤害飘字")
	_expect(not anim.is_playing(), "完整演出结束释放播放状态")
	_expect(attacker.global_position.is_equal_approx(attacker_position) and target.global_position.is_equal_approx(target_position), "显示位置恢复且击退不污染格位")
	_expect(attacker.scale.is_equal_approx(attacker_scale) and target.portrait.modulate.is_equal_approx(target_modulate), "蓄力缩放与白闪 modulate 恢复")
	_expect(camera.size == camera_size and camera.global_position.is_equal_approx(camera_position), "推近镜头 size/位置恢复")
	_expect(camera.global_basis.is_equal_approx(camera_basis), "打击镜头不改变4正交 yaw/elevation")
	_expect(attacker_unit[&"position"] == Vector2i(0, 0) and target_unit[&"position"] == Vector2i(1, 0), "演出不写 unit.position")
	await process_frame
	_expect(anim._effect_root.get_child_count() == 0, "临时斩击/高亮/盾裂节点清理")

	for spec in [&"slash", &"projectile:fire", &"burst:ice", &"beam:dark"]:
		var event := _event(spec, &"skill")
		_expect(ActionAnimScript.template_for(event) == String(spec).split(":")[0], "%s 模板选择" % spec)
		_expect(anim.duration_seconds(event) <= 2.0, "%s 技能时间轴不超过2s" % spec)
		await anim.play(event, 8.0, false)
		_expect(camera.size == camera_size and attacker.global_position.is_equal_approx(attacker_position), "%s 倍速播放后状态恢复" % spec)

	var finish_count := finishes.size()
	anim.play(normal, 1.0, true)
	_expect(not anim.is_playing() and finishes.size() == finish_count + 1, "skipped=true 同步完成并发出 finished")
	_expect(finishes.back()[&"skipped"], "finished 标记立即跳过")
	_expect(attacker.global_position.is_equal_approx(attacker_position) and camera.size == camera_size, "立即跳过不留下显示/镜头偏移")

	finish_count = finishes.size()
	anim.play(normal, 1.0, false)
	await create_timer(0.04).timeout
	anim.skip()
	await process_frame
	_expect(not anim.is_playing() and finishes.size() == finish_count + 1, "播放中 skip 强制推进 tween 且 await 链路返回")
	_expect(finishes.back()[&"skipped"], "播放中跳过标记")
	_expect(attacker.global_position.is_equal_approx(attacker_position) and target.global_position.is_equal_approx(target_position), "播放中跳过恢复所有单位位置")

	# 无 IsoCamera、且视口没有任何当前相机时，只跳过镜头效果，不留伪信号或空引用。
	camera.current = false
	var null_anim = ActionAnimScript.new()
	root.add_child(null_anim)
	null_anim.setup({&"attacker": attacker, &"target": target}, null, Callable())
	await null_anim.play(normal, 8.0, false)
	_expect(not null_anim.is_playing(), "null 相机边界仍完成完整时间轴")
	_expect(
		camera.global_position.is_equal_approx(camera_position) and is_equal_approx(camera.size, camera_size),
		"null/普通 Camera3D 边界不产生额外位置或 size 写入"
	)
	null_anim.queue_free()

	var grid := GridSystem.new(1, 1, [[&"plain"]])
	grid.units[&"player"] = {&"faction": &"player"}
	grid.units[&"enemy"] = {&"faction": &"enemy"}
	var director: TurnDirector = Director.new()
	director.grid = grid
	director.set_enemy_animation(2.5, false)
	director.set_hosting_animation(3.0, true)
	_expect(director.get_action_anim_options(&"enemy") == {&"anim_speed": 2.5, &"skip": false}, "敌方独立倍速选项")
	_expect(director.get_action_anim_options(&"player") == {&"anim_speed": 1.0, &"skip": false}, "非托管玩家不被敌方选项影响")
	director.hosting_active = true
	_expect(director.get_action_anim_options(&"player") == {&"anim_speed": 3.0, &"skip": true}, "托管倍速/跳过选项")
	director.set_pref(&"player", &"anim_speed", 4.0)
	_expect(director.get_action_anim_options(&"player")[&"anim_speed"] == 4.0, "单位 pref 可覆盖托管倍速")
	director.free()
	anim.queue_free()
	camera.queue_free()
	attacker.queue_free()
	target.queue_free()
	print("== action_anim_contract: %s ==" % ("PASS" if failures == 0 else "FAIL(%d)" % failures))
	quit(failures)
