extends SceneTree

const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	world.seed = 42
	root.add_child(world)
	await process_frame
	world.set_process(false)

	var depth = world._depth_of_field
	_expect(depth != null, "景深系统没有初始化")
	if depth != null:
		_expect(not depth.is_enabled(), "实验景深默认必须关闭")
		_expect(depth._effect_layer.layer == 2, "景深没有位于世界和天气之间")
		_expect(not depth._effect_layer.visible, "默认关闭时景深层仍在绘制")
		_expect(
			depth._back_buffer.copy_mode == BackBufferCopy.COPY_MODE_VIEWPORT,
			"景深没有复制完整视口"
		)
		depth.set_enabled(true)
		_expect(depth._effect_layer.visible, "开启景深后后处理层仍不可见")
		depth.set_enabled(false)
		_expect(not depth._effect_layer.visible, "关闭景深后后处理层仍在绘制")
		depth.set_enabled(true)

		# 玩家真实视觉位置相对平滑相机偏移时，焦平面必须跟随玩家屏幕 Y，
		# 不能固定在屏幕中心或读取仅用于遮挡排序的 Sprite.position。
		var viewport_size: Vector2 = world.get_viewport_rect().size
		var player_level: float = world._player_current_stand_level()
		var player_world: Variant = IsoProjection.screen_to_world(
			world._cam, Vector2(viewport_size.x * 0.5, viewport_size.y * 0.7), player_level
		)
		_expect(player_world != null, "景深测试无法构造玩家屏幕位置")
		if player_world != null:
			world._player.global_position = player_world
		world._sync_depth_of_field_focus()
		_expect(
			is_equal_approx(depth._target_focus_y, 0.7),
			"景深焦平面没有跟随玩家真实屏幕位置"
		)
		depth._process(1.0)
		_expect(
			is_equal_approx(
				float(depth._material.get_shader_parameter("focus_y")),
				depth._focus_y
			),
			"景深焦平面没有同步到 Shader"
		)

	var weather = world._weather
	_expect(weather != null, "天气系统没有初始化")
	if weather != null:
		_expect(weather._precipitation_layer.layer == 4, "雨雪层级错误")
		_expect(
			weather._precipitation_layer.follow_viewport_enabled,
			"雨雪层没有跟随世界视口"
		)
		_expect(
			weather._rain_particles.get_parent() == weather._precipitation_layer
			and weather._snow_particles.get_parent() == weather._precipitation_layer,
			"雨雪仍会被世界景深后处理捕获"
		)
		_expect(weather._atmosphere_layer.layer == 10, "天气氛围层级发生回归")
	_expect(
		world._day_night != null and world._day_night._atmosphere_layer.layer == 5,
		"昼夜氛围层级发生回归"
	)

	world.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("DEPTH_OF_FIELD_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
