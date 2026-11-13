## tests/encounter_transition_contract.gd — 遭遇转场与开战对峙表现层契约
extends SceneTree

const EncounterTransitionScript = preload("res://scripts/battle/encounter_transition.gd")
const BattlePresentationScript = preload("res://scripts/battle/battle_presentation.gd")
const UnitSpriteScript = preload("res://scripts/iso/unit_sprite.gd")
const IsometricCameraScript = preload("res://scripts/iso/isometric_camera_3d.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _unit(id: StringName, faction: StringName, cell: Vector2i) -> Dictionary:
	return {
		&"id": id,
		&"name": String(id),
		&"faction": faction,
		&"position": cell,
		&"hasActed": false,
		&"isDead": false,
	}


func _sprite(unit: Dictionary, at: Vector3) -> UnitSprite3D:
	var sprite := UnitSpriteScript.new() as UnitSprite3D
	sprite.unit = unit
	var portrait := Sprite3D.new()
	sprite.add_child(portrait)
	root.add_child(sprite)
	sprite.global_position = at
	return sprite


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_transition()
	await _test_standoff()
	print("ENCOUNTER_TRANSITION_CONTRACT_%s" % ("OK" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_transition() -> void:
	var transition := EncounterTransitionScript.new() as CanvasLayer
	root.add_child(transition)
	await process_frame
	_expect(transition.get("_audio") != null, "转场创建程序化音效播放器")
	var material := transition.get("_material") as ShaderMaterial
	_expect(material != null and material.shader != null, "径向扭曲 shader 可实例化")
	var finishes := [0]
	transition.finished.connect(func(): finishes[0] += 1)
	transition.play(&"b1")
	await transition.finished
	_expect(finishes == [1], "B1 转场完成信号一次")
	_expect(not transition.get("_overlay").visible, "B1 转场结束释放屏幕覆盖")
	_expect(is_zero_approx(float(material.get_shader_parameter("warp_amount"))), "B1 扭曲参数归零")
	_expect(is_zero_approx(float(material.get_shader_parameter("cover_alpha"))), "B1 覆盖透明度归零")

	transition.play(&"b2_reveal")
	await transition.finished
	_expect(finishes == [2], "B2 揭开完成信号一次")
	var covered := [0]
	transition.covered.connect(func(): covered[0] += 1)
	transition.cover_for_scene_change()
	await transition.covered
	_expect(covered == [1], "B2 切场景覆盖信号一次")
	_expect(transition.get("_overlay").visible, "切场景前覆盖保持不透明")
	_expect(is_equal_approx(float(material.get_shader_parameter("cover_alpha")), 1.0), "切场景覆盖 alpha=1")
	transition.queue_free()
	await process_frame


func _test_standoff() -> void:
	var camera := IsometricCameraScript.new() as Camera3D
	root.add_child(camera)
	camera.set("focus_position", Vector3(1.0, 0.0, 2.0))
	camera.set("elevation_radians", 0.52)
	camera.set("target_elevation_radians", 0.52)
	var original_focus: Vector3 = camera.get("focus_position")
	var original_zoom: float = camera.get("zoom")
	var original_yaw: float = camera.get("yaw_radians")
	var original_elevation: float = camera.get("elevation_radians")
	for quarter in range(4):
		camera.call("snap_to_angle", rad_to_deg(original_yaw) + float(quarter) * 90.0)
		var presentation := BattlePresentationScript.new() as Node
		presentation.set("duration_scale", 0.02)
		root.add_child(presentation)
		var player_unit := _unit(&"player", &"player", Vector2i(1, 1))
		var enemy_unit := _unit(&"enemy", &"enemy", Vector2i(3, 3))
		var player_position := Vector3(-1.0, 0.4, 0.0)
		var enemy_position := Vector3(1.0, 0.4, 0.0)
		var player := _sprite(player_unit, player_position)
		var enemy := _sprite(enemy_unit, enemy_position)
		var sprites := {&"player": player, &"enemy": enemy}
		var starts := [0]
		var finishes := [0]
		presentation.standoff_started.connect(func(): starts[0] += 1)
		presentation.standoff_finished.connect(func(): finishes[0] += 1)
		# quarter=0 验证 B2 取景；其余角度关闭取景，等价 B1 只借屏幕方向。
		presentation.play_standoff(sprites, camera, quarter == 0)
		_expect(starts == [1], "角度 %d 对峙开始信号一次" % (quarter * 90))
		var right := camera.global_basis.x.normalized()
		var up := camera.global_basis.y.normalized()
		var player_expected := (-right * 4.8 - up * 2.4).normalized()
		var enemy_expected := (right * 4.8 + up * 2.4).normalized()
		var player_offset := (player.global_position - player_position).normalized()
		var enemy_offset := (enemy.global_position - enemy_position).normalized()
		_expect(player_offset.dot(player_expected) > 0.999, "角度 %d 我方未沿屏幕左下入场" % (quarter * 90))
		_expect(enemy_offset.dot(enemy_expected) > 0.999, "角度 %d 敌方未沿屏幕右上入场" % (quarter * 90))
		await presentation.standoff_finished
		_expect(finishes == [1], "角度 %d 对峙完成信号一次" % (quarter * 90))
		_expect(player.global_position.is_equal_approx(player_position), "我方显示位置精确恢复")
		_expect(enemy.global_position.is_equal_approx(enemy_position), "敌方显示位置精确恢复")
		_expect(player_unit[&"position"] == Vector2i(1, 1), "对峙不写我方逻辑格")
		_expect(enemy_unit[&"position"] == Vector2i(3, 3), "对峙不写敌方逻辑格")
		_expect(is_equal_approx(float(camera.get("zoom")), original_zoom), "对峙不改变像素缩放")
		_expect(is_equal_approx(float(camera.get("yaw_radians")), original_yaw + quarter * PI * 0.5), "对峙不改变正交 yaw")
		_expect(is_equal_approx(float(camera.get("elevation_radians")), original_elevation), "对峙恢复 elevation")
		_expect((camera.get("focus_position") as Vector3).is_equal_approx(original_focus), "对峙恢复相机焦点")
		presentation.queue_free()
		player.queue_free()
		enemy.queue_free()
		await process_frame
	camera.queue_free()
	await process_frame
