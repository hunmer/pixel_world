## tests/game_sfx_contract.gd — Sfx autoload 契约：素材完整性、cue 播放、
## 地形脚步映射、UI 按钮自动挂接。headless 运行：
##   godot --headless --path . --script res://tests/game_sfx_contract.gd
extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok: %s" % message)
	else:
		failures += 1
		printerr("  FAIL: %s" % message)


func _run() -> void:
	var sfx: Node = root.get_node_or_null("/root/Sfx")
	_expect(sfx != null, "Sfx autoload 已注册")
	if sfx == null:
		_finish()
		return

	# 1) 素材完整性：每个 cue 的资源都存在且可加载。
	print("game_sfx_contract: 素材完整性")
	var cues: Dictionary = sfx.CUES
	_expect(cues.size() >= 40, "cue 表共 %d 条（期望 ≥40）" % cues.size())
	for cue in cues:
		var entry: Array = cues[cue]
		var path := "res://assets/audio/sfx/" + String(entry[0])
		_expect(ResourceLoader.exists(path), "素材存在: %s -> %s" % [String(cue), path])
		var stream: AudioStream = load(path)
		_expect(stream != null, "可加载: %s" % String(cue))

	# 2) play()：所有 cue 均能成功播放（headless dummy 音频驱动下仍返回 true）。
	print("game_sfx_contract: 播放")
	var all_played := true
	for cue in cues:
		if not sfx.play(cue):
			all_played = false
			printerr("  FAIL: play(%s) 返回 false" % String(cue))
	_expect(all_played, "全部 cue play() 成功")

	# 3) 地形脚步映射（先清节流表，避免与第 2 节播放冲突）。
	print("game_sfx_contract: 脚步映射")
	sfx._last_play_at.clear()
	_expect(sfx.play_step(&"plain") == true, "step plain")
	_expect(sfx.play_step(&"forest") == true, "step forest")
	_expect(sfx.play_step(&"snow") == true, "step snow")
	_expect(sfx.play_step(&"mountain") == true, "step mountain")
	_expect(sfx.play_step(&"water") == true, "step water")
	sfx._last_play_at.clear()
	_expect(sfx.play_step(&"unknown_terrain") == true, "未知地形回退 plain")

	# 4) 世界脚步（Dictionary 形式 CellContext；先清节流表）。
	sfx._last_play_at.clear()
	_expect(sfx.play_world_step({"is_water": true, "biome_id": &"temperate", "landform_id": &""}) == true,
		"world step water")
	_expect(sfx.play_world_step({"is_water": false, "biome_id": &"snow_field", "landform_id": &""}) == true,
		"world step snow")
	sfx._last_play_at.clear()
	_expect(sfx.play_world_step(null) == true, "world step null 回退 plain")

	# 5) UI 按钮自动挂接：node_added 后 pressed/mouse_entered 已连接。
	print("game_sfx_contract: UI 自动挂接")
	var button := Button.new()
	button.name = "ContractTestButton"
	root.add_child(button)
	await process_frame
	await process_frame
	_expect(button.has_meta(sfx.UI_ATTACH_META), "按钮已挂接音效 meta")
	var connected_pressed := false
	var connected_hover := false
	for signal_item in button.pressed.get_connections():
		connected_pressed = true
	for signal_item in button.mouse_entered.get_connections():
		connected_hover = true
	_expect(connected_pressed, "pressed 已连接")
	_expect(connected_hover, "mouse_entered 已连接")
	button.queue_free()

	_finish()


func _finish() -> void:
	if failures == 0:
		print("game_sfx_contract: ALL PASS")
	else:
		printerr("game_sfx_contract: %d FAILURES" % failures)
	quit(1 if failures > 0 else 0)
