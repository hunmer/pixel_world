extends SceneTree

const BirdRendererScript = preload(
	"res://scripts/ecology/ambient_renderers/bird_renderer.gd"
)
const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
const IsometricCamera3D = preload("res://scripts/iso/isometric_camera_3d.gd")


class TerrainHost3D:
	extends Node2D

	const Iso = preload("res://scripts/iso/iso_projection_3d.gd")

	var camera: Camera3D
	var stand_level := 3.0

	func _grid_to_screen(cell: Vector2i, level: float) -> Vector2:
		return Iso.grid_to_screen(camera, cell, level)

	func cell_stand_level(_cell: Vector2i) -> float:
		return stand_level


var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _observer(
	player_cell: Vector2i,
	player_screen_position: Vector2 = Vector2(160.0, 90.0),
	camera_world_position: Vector2 = Vector2(110.0, 95.0)
) -> Dictionary:
	return {
		"player_cell": player_cell,
		"player_screen_position": player_screen_position,
		"viewport_size": Vector2(320.0, 180.0),
		"canvas_transform": Transform2D.IDENTITY,
		"camera_world_position": camera_world_position,
		"zoom": Vector2(2.0, 2.0),
		"world_seed": 4242,
		"allow_flyovers": false,
	}


func _observer_3d(camera, zoom: float, player_cell: Vector2i = Vector2i.ZERO) -> Dictionary:
	var context := _observer(player_cell)
	context["camera_3d"] = camera
	context["viewport_size"] = camera.get_viewport().get_visible_rect().size
	context["zoom"] = Vector2.ONE * zoom
	context["camera_world_position"] = IsoProjection.world_to_grid_position(
		camera.focus_position
	)
	context["player_world_3d"] = camera.focus_position
	context["player_screen_position"] = camera.unproject_position(camera.focus_position)
	return context


func _expect_vector2_near(
	actual: Vector2,
	expected: Vector2,
	message: String,
	tolerance: float = 0.01
) -> void:
	_expect(
		actual.distance_to(expected) <= tolerance,
		"%s (actual=%s expected=%s)" % [message, actual, expected]
	)


func _run() -> void:
	var renderer = BirdRendererScript.new()
	renderer.name = "BirdRendererContract"
	root.add_child(renderer)
	renderer.configure({
		"max_grounded": 4,
		"walk_radius_pixels": [4.0, 4.0],
		"walk_speed": [1.0, 1.0],
		"takeoff_radius_cells": 3,
		"escape_speed": [100.0, 100.0],
		"flyover_speed": [100.0, 100.0],
		"flyovers_enabled": false,
		"offscreen_margin": 16.0,
	})

	var frames: SpriteFrames = renderer.get_sprite_frames()
	_expect(frames.has_animation(&"walk"), "鸟模块缺少 walk 动画")
	_expect(frames.has_animation(&"fly"), "鸟模块缺少 fly 动画")
	_expect(frames.get_frame_count(&"walk") == 8, "walk 没有按 32x32 切为 8 帧")
	_expect(frames.get_frame_count(&"fly") == 8, "fly 没有按 32x32 切为 8 帧")
	_expect(frames.get_animation_loop(&"walk"), "walk 没有循环")
	_expect(frames.get_animation_loop(&"fly"), "fly 没有循环")
	var walk_texture: Texture2D = frames.get_frame_texture(&"walk", 0)
	var fly_texture: Texture2D = frames.get_frame_texture(&"fly", 0)
	_expect(
		walk_texture != null and walk_texture.get_size() == Vector2(32.0, 32.0),
		"walk 单帧尺寸不是 32x32"
	)
	_expect(
		fly_texture != null and fly_texture.get_size() == Vector2(32.0, 32.0),
		"fly 单帧尺寸不是 32x32"
	)

	var host := Node2D.new()
	host.name = "TerrainColumnHost"
	host.position = Vector2(100.0, 80.0)
	root.add_child(host)
	var bird_cell := Vector2i(10, 10)
	# Even if ecological input requests two members for one source cell, the
	# renderer must keep only one 32x32 walking bird on that isometric surface.
	renderer.add_cluster(bird_cell, host, Vector2(20.0, 30.0), 2, 12345)
	renderer.refresh_field()
	_expect(renderer.get_grounded_count() == 1, "同一地块生成了重叠的地面鸟")
	var grounded: Array[AnimatedSprite2D] = renderer.get_grounded_sprites()
	_expect(grounded.size() == 1, "无法读取激活的地面鸟")
	if grounded.size() == 1:
		_expect(grounded[0].animation == &"walk", "地面鸟没有播放 walk")
		_expect(grounded[0].is_playing(), "地面鸟 walk 没有播放")
		var position_before := grounded[0].position
		renderer.update_observer(_observer(Vector2i.ZERO), 0.37)
		_expect(
			not grounded[0].position.is_equal_approx(position_before),
			"地面鸟没有在出生格内踱步"
		)

	# The bird is to the left of the player in screen space, so takeoff must use
	# the left-facing mirror of the source-right fly sheet.
	var near_context := _observer(Vector2i(11, 10), Vector2(200.0, 99.0))
	renderer.update_observer(near_context, 0.0)
	_expect(renderer.get_grounded_count() == 0, "玩家靠近后地面鸟没有起飞")
	_expect(renderer.get_flying_count() == 1, "惊飞鸟没有进入世界坐标飞行集合")
	_expect(renderer.is_cell_dismissed(bird_cell), "起飞后的出生格没有 dismissed")
	var escaped: Array[AnimatedSprite2D] = renderer.get_flying_sprites()
	if escaped.size() == 1:
		_expect(escaped[0].animation == &"fly", "惊飞鸟没有切换 fly")
		_expect(escaped[0].is_playing(), "惊飞鸟 fly 没有播放")
		_expect(escaped[0].flip_h, "默认朝右素材向左飞时没有水平反转")
		_expect(
			escaped[0].scale.is_equal_approx(Vector2(2.0, 2.0)),
			"起飞切到屏幕空间时没有保留相机缩放"
		)

	# Refreshing the still-streamed cluster must not recreate a startled bird.
	renderer.refresh_field()
	_expect(renderer.get_grounded_count() == 0, "dismissed 出生格立即重新生成了鸟")
	renderer.update_observer(near_context, 4.0)
	_expect(renderer.get_flying_count() == 0, "飞出可见区域的惊飞鸟没有回收")

	# Streaming the cell out resets its dismissed lifetime; returning can produce
	# a new ground bird from the same deterministic candidate.
	renderer.remove_cell(bird_cell)
	_expect(not renderer.is_cell_dismissed(bird_cell), "移除出生格后 dismissed 没有释放")
	renderer.add_cluster(bird_cell, host, Vector2(20.0, 30.0), 2, 12345)
	renderer.refresh_field()
	_expect(renderer.get_grounded_count() == 1, "出生格重新流入后没有恢复地面鸟")

	# Explicit flyovers provide deterministic coverage for both one bird and a
	# small group without shortening the production timer.
	var flyover_context := _observer(Vector2i.ZERO)
	_expect(
		renderer.force_flyover(1, 1, flyover_context) == 1,
		"无法强制生成单只飞越鸟"
	)
	var after_single: Array[AnimatedSprite2D] = renderer.get_flying_sprites()
	_expect(after_single.size() == 1, "单只 flyover 数量错误")
	if after_single.size() == 1:
		_expect(not after_single[0].flip_h, "向右 flyover 错误反转了默认朝右素材")
		var world_position_before: Vector2 = renderer._flying[0].get(
			"world_position",
			Vector2.INF
		)
		var screen_position_before := after_single[0].position
		var shifted_camera := Vector2(102.0, 90.0)
		var shifted_context := _observer(
			Vector2i.ZERO,
			Vector2(160.0, 90.0),
			shifted_camera
		)
		renderer.update_observer(
			shifted_context,
			0.0
		)
		var world_position_after: Vector2 = renderer._flying[0].get(
			"world_position",
			Vector2.INF
		)
		_expect(
			world_position_after.is_equal_approx(world_position_before),
			"镜头移动错误地写入了鸟的世界坐标"
		)
		_expect(
			after_single[0].position.is_equal_approx(
				Vector2(160.0, 90.0)
				+ (world_position_before - shifted_camera) * Vector2(2.0, 2.0)
			),
			"飞行鸟没有随镜头变换重新投影"
		)
		_expect(
			not after_single[0].position.is_equal_approx(screen_position_before),
			"飞行鸟仍被固定在屏幕参考系"
		)
		var first_step_start: Vector2 = renderer._flying[0]["world_position"]
		renderer.update_observer(shifted_context, 0.1)
		var first_step_end: Vector2 = renderer._flying[0]["world_position"]
		renderer.update_observer(flyover_context, 0.1)
		var second_step_end: Vector2 = renderer._flying[0]["world_position"]
		_expect(
			(first_step_end - first_step_start).is_equal_approx(
				second_step_end - first_step_end
			),
			"相同时间步的鸟世界位移受镜头移动影响"
		)
	_expect(
		renderer.force_flyover(3, -1, flyover_context) == 3,
		"无法强制生成小群飞越鸟"
	)
	var after_group: Array[AnimatedSprite2D] = renderer.get_flying_sprites()
	_expect(after_group.size() == 4, "单只与三只小群没有同时存在")
	if after_group.size() == 4:
		for index in range(1, 4):
			_expect(after_group[index].flip_h, "向左小群成员没有水平反转")
		for index in range(2, 4):
			_expect(
				absf(after_group[index].position.x - after_group[index - 1].position.x)
				>= 40.0,
				"飞越鸟群成员间距太小，仍会互相重叠"
			)
	renderer.update_observer(flyover_context, 0.1)
	_expect(
		renderer.get_flying_count() == 4,
		"鸟群队尾在进入视口前被首帧回收"
	)
	renderer.update_observer(flyover_context, 10.0)
	_expect(renderer.get_flying_count() == 0, "飞越屏幕后的鸟群没有回收")

	renderer.clear()
	_expect(renderer.get_grounded_count() == 0, "clear 后仍有地面鸟")
	_expect(renderer.get_flying_count() == 0, "clear 后仍有飞行鸟")
	_expect(renderer.get_dismissed_count() == 0, "clear 后仍保留 dismissed 状态")

	await _exercise_camera_3d(renderer)

	renderer.queue_free()
	host.queue_free()
	await process_frame
	await process_frame

	# Real world integration: the modular ecology catalog must instantiate this
	# renderer and produce sparse ground birds without a main.gd species branch.
	var world = load("res://main.tscn").instantiate()
	world.seed = 42
	root.add_child(world)
	await process_frame
	await process_frame
	world.set_process(false)
	var world_renderer = world._ambient_registry.get_renderer(&"bird")
	_expect(world_renderer != null, "真实世界没有通过 AmbientRegistry 实例化 bird 模块")
	if world_renderer != null:
		_expect(
			world_renderer._flyover_group_chance >= 0.70
			and world_renderer._flyover_group_size.x >= 3
			and world_renderer._flyover_group_size.y >= 6,
			"正式生态配置仍很少生成成群飞鸟"
		)
		_expect(
			world_renderer.get_grounded_count() > 0,
			"温带流式区域没有自然生成任何稀疏地面鸟"
		)
		for sprite in world_renderer.get_grounded_sprites():
			_expect(sprite.animation == &"walk", "真实地面鸟没有循环 walk")
	world.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("BIRD_RENDERER_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _exercise_camera_3d(renderer) -> void:
	var camera = IsometricCamera3D.new()
	root.add_child(camera)
	var bird_cell := Vector2i(10, 10)
	var stand_level := 3.0
	var base_focus := IsoProjection.grid_to_world(bird_cell, stand_level)
	camera.focus_position = base_focus
	camera.zoom = 2.0
	var host := TerrainHost3D.new()
	host.camera = camera
	host.stand_level = stand_level
	root.add_child(host)
	await process_frame

	# The production camera limits are 0.5 / 2 / 4. Projection, inverse
	# projection, pixel scale, and velocity conversion must agree at every stop.
	var zoom_stops: Array[float] = [
		IsometricCamera3D.MIN_ZOOM,
		float(camera.zoom),
		IsometricCamera3D.MAX_ZOOM,
	]
	var world_point := Vector2(13.25, 8.5)
	var world_level := 2.5
	for zoom in zoom_stops:
		camera.zoom = zoom
		var context := _observer_3d(camera, zoom)
		_expect_vector2_near(
			renderer._observer_scale(context),
			Vector2.ONE * zoom,
			"3D observer 没有采用相机 zoom"
		)
		var screen_point: Vector2 = renderer._world_to_screen(
			world_point,
			context,
			world_level
		)
		_expect_vector2_near(
			screen_point,
			camera.unproject_position(
				IsoProjection.visual_to_world(world_point, world_level)
			),
			"3D world_to_screen 与真实 Camera3D 投影不一致"
		)
		_expect_vector2_near(
			renderer._screen_to_world(screen_point, context, world_level),
			world_point,
			"3D screen_to_world 不能还原连续 grid 坐标"
		)
		var screen_velocity := Vector2(73.0, -29.0)
		var world_velocity: Vector2 = renderer._screen_velocity_to_world(
			screen_velocity,
			context,
			world_level
		)
		var projected_velocity: Vector2 = renderer._world_to_screen(
			world_point + world_velocity,
			context,
			world_level
		) - screen_point
		_expect_vector2_near(
			projected_velocity,
			screen_velocity,
			"3D 屏幕速度与权威 grid 速度转换不一致",
			0.02
		)

	# Moving and zooming the camera only reprojects an existing bird. It cannot
	# rewrite position, velocity, level, or age; simulation steps stay identical.
	renderer.clear()
	camera.focus_position = base_focus
	camera.zoom = 2.0
	_expect(
		renderer.force_flyover(1, 1, _observer_3d(camera, 2.0)) == 1,
		"无法生成 3D flyover"
	)
	var flying: Array[AnimatedSprite2D] = renderer.get_flying_sprites()
	if flying.size() == 1:
		var position_before: Vector2 = renderer._flying[0]["world_position"]
		var velocity_before: Vector2 = renderer._flying[0]["world_velocity"]
		var level_before := float(renderer._flying[0]["world_level"])
		var age_before := float(renderer._flying[0]["age"])
		camera.focus_position = base_focus + IsoProjection.visual_to_world(
			Vector2(0.75, -0.5)
		)
		camera.zoom = 0.5
		var changed_context := _observer_3d(camera, 0.5)
		renderer.update_observer(changed_context, 0.0)
		_expect(renderer.get_flying_count() == 1, "3D 镜头变化错误回收了飞鸟")
		if renderer.get_flying_count() == 1:
			_expect_vector2_near(
				renderer._flying[0]["world_position"],
				position_before,
				"3D 镜头移动/zoom 写回了权威位置"
			)
			_expect_vector2_near(
				renderer._flying[0]["world_velocity"],
				velocity_before,
				"3D 镜头移动/zoom 写回了权威速度"
			)
			_expect(
				is_equal_approx(float(renderer._flying[0]["world_level"]), level_before)
				and is_equal_approx(float(renderer._flying[0]["age"]), age_before),
				"3D 镜头变化改写了飞行高度或年龄"
			)
			_expect_vector2_near(
				flying[0].scale,
				Vector2.ONE * 0.5,
				"3D 飞鸟没有随最小 zoom 缩放"
			)
			_expect_vector2_near(
				flying[0].position,
				renderer._world_to_screen(position_before, changed_context, level_before),
				"3D 镜头变化后没有按权威位置重投影"
			)
		camera.zoom = 4.0
		renderer.update_observer(_observer_3d(camera, 4.0), 0.25)
		if renderer.get_flying_count() == 1:
			_expect_vector2_near(
				renderer._flying[0]["world_position"],
				position_before + velocity_before * 0.25,
				"3D 世界积分受 zoom 污染"
			)
			_expect_vector2_near(
				renderer._flying[0]["world_velocity"],
				velocity_before,
				"3D 积分后世界速度发生变化"
			)
			_expect(
				is_equal_approx(float(renderer._flying[0]["age"]), age_before + 0.25),
				"3D zoom 改写了年龄增量"
			)

	# Spawn RNG consumption is independent of the observer zoom.
	var spawn_frames: Array[int] = []
	camera.focus_position = base_focus
	camera.zoom = 0.5
	renderer.clear()
	renderer.force_flyover(4, 1, _observer_3d(camera, 0.5))
	var minimum_zoom_rng_state: int = renderer._rng.state
	for sprite in renderer.get_flying_sprites():
		spawn_frames.append(sprite.frame)
	renderer.clear()
	camera.zoom = 4.0
	renderer.force_flyover(4, 1, _observer_3d(camera, 4.0))
	_expect(renderer.get_flying_count() == 4, "最大 zoom 改变了 flyover 生成数量")
	_expect(
		renderer._rng.state == minimum_zoom_rng_state,
		"zoom 改变了 flyover 的确定性 RNG 序列"
	)
	var maximum_zoom_sprites: Array[AnimatedSprite2D] = renderer.get_flying_sprites()
	if maximum_zoom_sprites.size() == spawn_frames.size():
		for index in spawn_frames.size():
			_expect(
				maximum_zoom_sprites[index].frame == spawn_frames[index],
				"zoom 改变了 flyover 的确定性初始帧"
			)

	# Ground sprites use the same pixel scale and offsets as their flight
	# representation. Takeoff preserves the exact foot point at every zoom stop.
	for zoom in zoom_stops:
		renderer.clear()
		camera.focus_position = base_focus
		camera.zoom = zoom
		renderer.add_cluster(bird_cell, host, Vector2(bird_cell), 1, 12345)
		renderer.update_observer(_observer_3d(camera, zoom), 0.19)
		var grounded: Array[AnimatedSprite2D] = renderer.get_grounded_sprites()
		_expect(grounded.size() == 1, "3D 地面鸟没有激活")
		if grounded.size() != 1:
			continue
		var ground_screen := grounded[0].global_position
		_expect_vector2_near(
			grounded[0].scale,
			Vector2.ONE * zoom,
			"3D 地面鸟没有采用当前 zoom"
		)
		renderer.update_observer(_observer_3d(camera, zoom, bird_cell), 0.0)
		flying = renderer.get_flying_sprites()
		_expect(
			renderer.get_grounded_count() == 0 and flying.size() == 1,
			"3D 地面鸟没有切换到飞行状态"
		)
		if flying.size() != 1:
			continue
		_expect_vector2_near(
			flying[0].global_position,
			ground_screen,
			"3D ground-to-flight 发生位置跳变",
			0.02
		)
		_expect_vector2_near(
			flying[0].scale,
			Vector2.ONE * zoom,
			"3D ground-to-flight 发生尺度跳变"
		)
		_expect(
			is_equal_approx(float(renderer._flying[0]["world_level"]), stand_level),
			"3D 起飞没有保留地面站立高度"
		)
		var takeoff_position: Vector2 = renderer._flying[0]["world_position"]
		var takeoff_velocity: Vector2 = renderer._flying[0]["world_velocity"]
		var next_zoom := 4.0 if zoom < 4.0 else 0.5
		camera.zoom = next_zoom
		renderer.update_observer(_observer_3d(camera, next_zoom), 0.0)
		if renderer.get_flying_count() == 1:
			_expect_vector2_near(
				renderer._flying[0]["world_position"],
				takeoff_position,
				"3D 起飞后 zoom 改写了位置"
			)
			_expect_vector2_near(
				renderer._flying[0]["world_velocity"],
				takeoff_velocity,
				"3D 起飞后 zoom 改写了速度"
			)
			_expect_vector2_near(
				flying[0].scale,
				Vector2.ONE * next_zoom,
				"3D 起飞后没有连续切换到新 zoom"
			)

	renderer.clear()
	host.queue_free()
	camera.queue_free()
	await process_frame
	await process_frame
