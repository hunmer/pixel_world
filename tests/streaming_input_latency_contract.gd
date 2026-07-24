extends SceneTree

const MEDIAN_LIMIT_MS := 120.0
const MAXIMUM_LIMIT_MS := 250.0

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	# A water-heavy seed exercises fish habitat clearance and community streaming,
	# which is the expensive path most likely to regress movement responsiveness.
	world.seed = 1
	root.add_child(world)
	await process_frame
	world.set_process(false)

	var timings: Array[float] = []
	for direction in [
		Vector2i.RIGHT,
		Vector2i.RIGHT,
		Vector2i.DOWN,
		Vector2i.LEFT,
		Vector2i.UP,
	]:
		var started := Time.get_ticks_usec()
		world._try_move(direction)
		timings.append((Time.get_ticks_usec() - started) / 1000.0)
	var sorted_timings := timings.duplicate()
	sorted_timings.sort()
	var median_ms: float = sorted_timings[sorted_timings.size() / 2]
	var maximum_ms: float = sorted_timings.back()
	_expect(
		median_ms < MEDIAN_LIMIT_MS,
		"流式移动中位延迟过高: %.2f ms" % median_ms
	)
	_expect(
		maximum_ms < MAXIMUM_LIMIT_MS,
		"流式移动峰值延迟过高: %.2f ms" % maximum_ms
	)

	world.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print(
			"STREAMING_INPUT_LATENCY_CONTRACT_OK median_ms=%.2f max_ms=%.2f samples=%s"
			% [median_ms, maximum_ms, timings]
		)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
