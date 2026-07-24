extends SceneTree

const ColumnBatchScript = preload("res://scripts/isometric_column_batch.gd")

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

	var weather = world._weather
	_expect(weather != null, "天气系统没有初始化")
	if weather != null:
		_expect(weather._rain_particles.amount == 420, "优化不应降低雨线数量")
		_expect(weather._rain_particles.fixed_fps == 30, "雨粒子没有使用 30 Hz 模拟")
		_expect(weather._snow_particles.fixed_fps == 30, "雪粒子没有使用 30 Hz 模拟")
		_expect(weather._rain_particles.interpolate, "雨粒子低频模拟没有启用插值")
		_expect(weather._snow_particles.interpolate, "雪粒子低频模拟没有启用插值")
		_expect(
			is_equal_approx(weather._rain_impact_attempts_per_second, 24.0),
			"雨水落点预算不是每秒 24 次"
		)
		var shader_code := String(weather._material.shader.code)
		_expect("sin(" not in shader_code, "天气全屏 Shader 仍在逐像素调用 sin")
		_expect("TIME" in shader_code, "天气氛围动画没有改用 GPU 内置时间")

		var impact_counter := {"count": 0}
		weather.water_impact_requested.connect(func(
			_viewport_position: Vector2,
			_kind: StringName,
			_strength: float
		) -> void:
			impact_counter["count"] = int(impact_counter["count"]) + 1
		)
		weather._rain_amount = 1.0
		weather._snow_amount = 0.0
		weather._rain_impact_budget = 0.0
		weather._emit_water_impacts(1.0)
		var impact_count := int(impact_counter["count"])
		_expect(
			impact_count == 3,
			"长帧雨水落点没有限制为最多 3 个: %d" % impact_count
		)
		_expect(weather._rain_impact_budget < 1.0, "雨水落点仍会积压到后续帧")
		impact_counter["count"] = 0
		weather._rain_impact_budget = 0.0
		for _frame in 60:
			weather._emit_water_impacts(1.0 / 60.0)
		_expect(
			int(impact_counter["count"]) == 24,
			"稳态一秒没有生成 24 个雨水落点: %s" % impact_counter["count"]
		)

	var column = ColumnBatchScript.new()
	root.add_child(column)
	column.configure(Vector2i.ZERO, [], Vector2.ZERO, 0.0, 8.0)
	_expect(column.RIPPLE_SEGMENTS == 18, "水波折线段数不是预算值 18")
	_expect(
		is_equal_approx(column.RIPPLE_REDRAW_INTERVAL, 1.0 / 30.0),
		"水波重绘预算不是 30 Hz"
	)
	column.spawn_water_ripple(Vector2.ZERO, &"rain", 1.0, 10.0)
	column._process(1.0 / 60.0)
	_expect(
		column._ripple_redraw_elapsed > 0.0,
		"水波首个 60 Hz 帧没有进入重绘节流"
	)
	column._process(1.0 / 60.0)
	_expect(
		column._ripple_redraw_elapsed < column.RIPPLE_REDRAW_INTERVAL,
		"水波 30 Hz 重绘计时没有回绕"
	)

	var shoreline_image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	shoreline_image.fill(Color.WHITE)
	var shoreline_texture := ImageTexture.create_from_image(shoreline_image)
	var shoreline_column = ColumnBatchScript.new()
	root.add_child(shoreline_column)
	shoreline_column.configure(
		Vector2i.ONE,
		[{
			"texture": shoreline_texture,
			"level": 6,
			"render_offset": Vector2.ZERO,
			"modulate": Color.WHITE,
			"water_part": &"surface",
			"shore_edges": 5,
			"shore_seed": 17,
			"occluder_class": &"none",
		}],
		Vector2.ZERO,
		0.0,
		8.0
	)
	_expect(shoreline_column._has_shoreline, "岸线水格没有识别白浪边")
	_expect(
		shoreline_column.SHORELINE_COLOR.a <= 0.98,
		"岸线白浪仍然过厚或不透明"
	)
	_expect(
		shoreline_column.SHORELINE_LINE_WIDTH <= 0.50,
		"岸线白浪仍使用完整逻辑像素宽度"
	)
	_expect(
		shoreline_column.SHORELINE_HALF_LENGTH_MIN >= 3.0,
		"岸线波纹仍然过短，难以形成舒展弧线"
	)
	_expect(
		shoreline_column.SHORELINE_TIDE_PHASES.size()
		== shoreline_column.SHORELINE_FRAME_COUNT
		and shoreline_column.SHORELINE_TIDE_ALPHA_PHASES.size()
		== shoreline_column.SHORELINE_FRAME_COUNT
		and shoreline_column.SHORELINE_EVEN_ALPHA_PHASES.size()
		== shoreline_column.SHORELINE_FRAME_COUNT
		and shoreline_column.SHORELINE_ODD_ALPHA_PHASES.size()
		== shoreline_column.SHORELINE_FRAME_COUNT,
		"岸线潮汐关键帧与渲染帧数量不一致"
	)
	_expect(
		float(shoreline_column.SHORELINE_TIDE_PHASES[0])
		< float(shoreline_column.SHORELINE_TIDE_PHASES[2])
		and float(shoreline_column.SHORELINE_TIDE_PHASES[3])
		< float(shoreline_column.SHORELINE_TIDE_PHASES[2]),
		"岸线波纹没有先涨起再收回的潮汐曲线"
	)
	_expect(
		float(shoreline_column.SHORELINE_EVEN_ALPHA_PHASES[0])
		> float(shoreline_column.SHORELINE_ODD_ALPHA_PHASES[0])
		and float(shoreline_column.SHORELINE_EVEN_ALPHA_PHASES[2])
		< float(shoreline_column.SHORELINE_ODD_ALPHA_PHASES[2]),
		"岸线奇偶线段没有交替淡入淡出"
	)
	_expect(
		shoreline_column.SHORELINE_SEGMENT_COUNT_MIN >= 5
		and shoreline_column.SHORELINE_SEGMENT_COUNT_MAX <= 6,
		"岸线分段数量超出稀疏波纹设计范围"
	)
	var symmetric_curve: Vector2 = shoreline_column._shoreline_curve_point(
		Vector2.ZERO,
		Vector2.RIGHT,
		Vector2.DOWN,
		5.0,
		0.45,
		0.4,
		0.8,
		0,
		false
	)
	var broad_curve: Vector2 = shoreline_column._shoreline_curve_point(
		Vector2.ZERO,
		Vector2.RIGHT,
		Vector2.DOWN,
		5.0,
		0.45,
		0.4,
		0.8,
		2,
		false
	)
	var skewed_curve: Vector2 = shoreline_column._shoreline_curve_point(
		Vector2.ZERO,
		Vector2.RIGHT,
		Vector2.DOWN,
		5.0,
		0.45,
		0.4,
		0.8,
		1,
		false
	)
	var mirrored_curve: Vector2 = shoreline_column._shoreline_curve_point(
		Vector2.ZERO,
		Vector2.RIGHT,
		Vector2.DOWN,
		5.0,
		0.45,
		0.4,
		0.8,
		1,
		true
	)
	_expect(
		not symmetric_curve.is_equal_approx(broad_curve)
		and not skewed_curve.is_equal_approx(mirrored_curve),
		"岸线仍然只生成一种重复曲线"
	)
	_expect(
		shoreline_column.SHORELINE_EDGE_COVERAGE <= 0.56,
		"岸线白浪覆盖过密，仍会形成连续描边"
	)
	_expect(
		is_equal_approx(
			shoreline_column._shoreline_rand(17, 9),
			shoreline_column._shoreline_rand(17, 9)
		),
		"岸线波纹位置不具备确定性"
	)
	_expect(
		not shoreline_column.is_processing(),
		"只有岸线白浪的地块仍在逐帧执行 _process"
	)
	_expect(
		shoreline_column.get_child_count() == 0,
		"岸线白浪为每个水格创建了额外节点"
	)

	column.queue_free()
	shoreline_column.queue_free()
	world.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("WEATHER_PERFORMANCE_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
