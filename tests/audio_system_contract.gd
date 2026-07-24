extends SceneTree

const WanderingAnimalScript = preload("res://scripts/wandering_animal.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _nearby_land_cell(world, center: Vector2i, radius: int) -> Vector2i:
	for distance in range(1, radius + 1):
		for offset_y in range(-distance, distance + 1):
			var offset_x := distance - absi(offset_y)
			for signed_x in [offset_x, -offset_x]:
				var cell := center + Vector2i(signed_x, offset_y)
				if world._quantize(cell.x, cell.y) > world.WATER_MAX:
					return cell
	return Vector2i(1000000, 1000000)


func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	world.seed = 42
	root.add_child(world)
	await process_frame
	world.set_process(false)
	var audio = world._audio
	_expect(audio != null and audio.is_config_valid(), "世界音频没有成功初始化")
	if audio == null or not audio.is_config_valid():
		quit(1)
		return

	var animal_species: Array[String] = []
	var audible_species: Array[String] = []
	for species_id_value in world._animal_species:
		var species_id := String(species_id_value)
		animal_species.append(species_id)
		var species: Dictionary = world._animal_species[species_id_value]
		var metadata: Dictionary = species.get("metadata", {})
		if not bool(metadata.get("silent", false)):
			audible_species.append(species_id)
	animal_species.sort()
	audible_species.sort()
	for species_id in animal_species:
		var species: Dictionary = world._animal_species[species_id]
		var metadata: Dictionary = species.get("metadata", {})
		if bool(metadata.get("silent", false)):
			_expect(not audio.has_animal_sound(species_id), "静音动物错误绑定了叫声: " + species_id)
		else:
			_expect(audio.has_animal_sound(species_id), "动物缺少叫声: " + species_id)
	_expect(
		audio._animal_configs.size() == audible_species.size(),
		"动物叫声配置与非静音生态动物数量不一致"
	)
	var expected_stream_paths := {
		"dog": "res://sound_effect/狗叫声.mp3",
		"fox": "res://sound_effect/狐狸叫声.mp3",
		"frog": "res://sound_effect/蛙鸣声.mp3",
		"husky": "res://sound_effect/狗叫声.mp3",
		"pig": "res://sound_effect/猪哼声.mp3",
		"wolf": "res://sound_effect/狼嚎声.mp3",
	}
	for species_id in expected_stream_paths:
		var stream := audio._animal_streams.get(species_id) as AudioStream
		_expect(stream != null, "动物叫声资源没有加载: " + species_id)
		if stream != null:
			_expect(
				stream.resource_path == expected_stream_paths[species_id],
				"动物叫声资源映射错误: " + species_id
			)
			_expect(stream is AudioStreamMP3, "动物叫声不是 MP3 stream: " + species_id)
			if stream is AudioStreamMP3:
				_expect(
					not (stream as AudioStreamMP3).loop,
					"动物叫声不应循环播放: " + species_id
				)
	_expect(
		audio._animal_streams["husky"].resource_path
		== audio._animal_streams["dog"].resource_path,
		"哈士奇没有复用狗叫声"
	)
	var sound_probe_index := 0
	for species_id in audible_species:
		var sound_probe = WanderingAnimalScript.new()
		world.add_child(sound_probe)
		sound_probe.species_id = species_id
		sound_probe.origin_cell = Vector2i(sound_probe_index, 0)
		sound_probe.grid_cell = sound_probe.origin_cell
		sound_probe.target_cell = sound_probe.origin_cell
		sound_probe.visible = true
		audio.reset_world(42)
		audio.update_animal_sounds([sound_probe], sound_probe.grid_cell, 0.0)
		_expect(
			audio.get_animal_play_event_count() == 1,
			"动物靠近玩家时没有触发叫声: " + species_id
		)
		if audio.get_playing_animal_sound_count() == 1:
			_expect(
				audio._animal_players[0].stream == audio._animal_streams[species_id],
				"动物播放了错误的叫声: " + species_id
			)
		world.remove_child(sound_probe)
		sound_probe.free()
		sound_probe_index += 1
	_expect(audio._animal_players.size() == 5, "动物音效池没有为狼群预留并发声道")
	_expect(
		is_equal_approx(float(audio._animal_configs["wolf"]["volume_db"]), -20.0),
		"狼嚎音量没有提高到配置值"
	)
	var wolves: Array = []
	for wolf_index in 5:
		var wolf = WanderingAnimalScript.new()
		world.add_child(wolf)
		wolf.species_id = "wolf"
		wolf.origin_cell = Vector2i(wolf_index, 0)
		wolf.grid_cell = wolf.origin_cell
		wolf.target_cell = wolf.origin_cell
		wolf.visible = true
		wolves.append(wolf)
	audio.reset_world(42)
	audio.update_animal_sounds(wolves, Vector2i.ZERO, 0.0)
	_expect(
		audio.get_playing_animal_sound_count() == 4,
		"狼群没有以最多 4 路独立声源叠加嚎叫"
	)
	_expect(
		audio.get_animal_play_event_count() == 4,
		"狼群并发上限没有阻止第 5 只狼同时嚎叫"
	)
	for wolf in wolves:
		world.remove_child(wolf)
		wolf.free()
	audio.reset_world(42)
	_expect(audio._day_music.stream is AudioStreamMP3, "白天音乐不是 MP3 stream")
	_expect(audio._night_music.stream is AudioStreamMP3, "夜晚音乐不是 MP3 stream")
	_expect((audio._day_music.stream as AudioStreamMP3).loop, "白天音乐没有开启运行时循环")
	_expect((audio._night_music.stream as AudioStreamMP3).loop, "夜晚音乐没有开启运行时循环")
	_expect(audio._rain_ambience != null, "雨声播放器没有创建")
	if audio._rain_ambience != null:
		_expect(audio._rain_ambience.stream is AudioStreamMP3, "雨声不是 MP3 stream")
		_expect(
			audio._rain_stream_path == "res://sound_effect/持续雨声环境音.mp3",
			"雨声资源映射错误"
		)
		if audio._rain_ambience.stream is AudioStreamMP3:
			_expect(
				(audio._rain_ambience.stream as AudioStreamMP3).loop,
				"雨声没有开启运行时循环"
			)
		_expect(not audio._rain_ambience.playing, "晴天仍在解码静音雨声")

	audio.set_night_amount(0.0, true)
	_expect(audio.get_day_music_volume_db() > audio.get_night_music_volume_db(), "白天没有以 normal 音乐为主")
	_expect(audio.get_day_music_volume_db() <= -20.0, "白天音乐音量过大")
	audio.set_night_amount(1.0, true)
	_expect(audio.get_night_music_volume_db() > audio.get_day_music_volume_db(), "夜晚没有以 night 音乐为主")
	_expect(audio.get_night_music_volume_db() <= -20.0, "夜晚音乐音量过大")

	audio.set_night_amount(0.0, true)
	audio.set_rain_amount(1.0, true)
	_expect(audio._rain_ambience.playing, "雨天没有启动循环雨声")
	_expect(is_equal_approx(audio.get_rain_amount(), 1.0), "雨声没有立即淡入到目标强度")
	_expect(
		audio.get_rain_ambience_volume_db() < audio.get_day_music_volume_db(),
		"雨声没有保持在 BGM 以下"
	)
	_expect(
		is_equal_approx(audio.get_rain_ambience_volume_db(), -26.0),
		"雨声音量没有提高到配置值"
	)
	audio.set_rain_amount(0.0, true)
	_expect(not audio._rain_ambience.playing, "晴天没有停止雨声解码")
	_expect(
		audio.get_rain_ambience_volume_db() <= -79.0,
		"晴天时雨声没有静音"
	)

	world._weather.set_manual_weather(&"rain")
	_expect(
		is_equal_approx(audio.get_target_rain_amount(), 1.0),
		"天气进入雨天后没有通知音频系统"
	)
	audio._process(audio._rain_fade_seconds * 0.5)
	_expect(
		audio.get_rain_amount() > 0.0 and audio.get_rain_amount() < 1.0,
		"雨声没有平滑淡入"
	)
	world._weather.set_manual_weather(&"clear")
	_expect(
		is_equal_approx(audio.get_target_rain_amount(), 0.0),
		"天气转晴后没有停止雨声目标"
	)
	audio._process(audio._rain_fade_seconds)
	_expect(is_equal_approx(audio.get_rain_amount(), 0.0), "雨声没有平滑淡出")

	var dog = WanderingAnimalScript.new()
	world.add_child(dog)
	dog.species_id = "dog"
	dog.origin_cell = Vector2i(4, 5)
	dog.grid_cell = dog.origin_cell
	dog.target_cell = dog.origin_cell
	dog.visible = true
	dog.fleeing = true
	audio.reset_world(42)
	audio.update_animal_sounds([dog], Vector2i(100, 100), 100.0)
	_expect(audio.get_animal_play_event_count() == 0, "玩家远离时仍触发了动物叫声")
	audio.update_animal_sounds([dog], dog.grid_cell, 0.0)
	_expect(audio.get_animal_play_event_count() == 1, "玩家首次靠近时没有立即触发叫声")
	audio.update_animal_sounds([dog], dog.grid_cell, 0.99)
	_expect(audio.get_animal_play_event_count() == 1, "追逐叫声未满 1 秒就重复触发")
	audio.update_animal_sounds([dog], dog.grid_cell, 0.02)
	_expect(audio.get_animal_play_event_count() == 2, "持续追逐时没有按约 1 秒重触发叫声")
	_expect(audio.get_playing_animal_sound_count() == 1, "触发后的动物叫声没有播放")
	dog._visual_position = Vector2(96.0, 144.0)
	audio.update_animal_sounds([dog], dog.grid_cell, 0.0)
	_expect(
		audio._animal_players[0].position.is_equal_approx(dog.current_visual_position()),
		"播放中的空间音效没有跟随动物"
	)
	audio.update_animal_sounds([dog], Vector2i(100, 100), 0.0)
	_expect(
		audio.get_playing_animal_sound_count() == 0,
		"玩家离开动物附近后叫声仍在播放"
	)
	audio.update_animal_sounds([dog], dog.grid_cell, 0.0)
	_expect(audio.get_animal_play_event_count() == 3, "玩家重新靠近时没有再次立即叫声")
	dog.fleeing = false
	audio.update_animal_sounds([dog], dog.grid_cell, 1.1)
	_expect(
		audio.get_animal_play_event_count() == 3,
		"停止追逐后仍按 1 秒间隔重复叫声"
	)

	# 后靠近的动物拥有首次叫声优先级，第一只不能用 1 秒追逐重播永久占住播放器。
	var fox = WanderingAnimalScript.new()
	world.add_child(fox)
	fox.species_id = "fox"
	fox.origin_cell = dog.origin_cell + Vector2i.RIGHT
	fox.grid_cell = fox.origin_cell
	fox.target_cell = fox.origin_cell
	fox.visible = true
	fox.fleeing = true
	dog.fleeing = true
	audio.reset_world(42)
	audio.update_animal_sounds([dog], dog.grid_cell, 0.0)
	audio.update_animal_sounds([dog], dog.grid_cell, 1.01)
	_expect(audio.get_animal_play_event_count() == 2, "并发测试没有建立持续狗叫声")
	audio.update_animal_sounds([dog, fox], dog.grid_cell, 0.0)
	audio.update_animal_sounds([dog, fox], dog.grid_cell, 1.01)
	_expect(
		audio.get_animal_play_event_count() == 2,
		"存在待兑现首次叫声时，旧动物仍抢先重播"
	)
	audio._animal_players[0].stop()
	audio.update_animal_sounds([dog, fox], dog.grid_cell, 0.0)
	_expect(
		audio.get_animal_play_event_count() == 3,
		"播放器空闲后没有优先兑现后来动物的首次叫声"
	)

	# 已隐藏或离开触发范围的欠叫动物不能永久压住仍在被追逐的动物。
	audio.reset_world(42)
	fox.visible = false
	audio.update_animal_sounds([dog], dog.grid_cell, 0.0)
	fox.visible = true
	audio.update_animal_sounds([dog, fox], dog.grid_cell, 0.0)
	fox.visible = false
	audio.update_animal_sounds([dog, fox], dog.grid_cell, 1.01)
	_expect(
		audio.get_animal_play_event_count() == 2,
		"隐藏动物遗留的首次叫声阻塞了持续追逐叫声"
	)
	world.remove_child(fox)
	fox.free()

	# 动物被流式卸载时，也必须立即收掉已经开始的叫声。
	audio.reset_world(42)
	dog.fleeing = true
	audio.update_animal_sounds([dog], dog.grid_cell, 0.0)
	_expect(audio.get_playing_animal_sound_count() == 1, "卸载测试没有先触发叫声")

	dog.queue_free()
	await process_frame
	audio.update_animal_sounds([], Vector2i.ZERO, 0.0)
	_expect(
		audio.get_playing_animal_sound_count() == 0,
		"动物卸载后叫声仍在播放"
	)

	# 真实主循环中，同一帧先把附近动物切入 fleeing，再由音频系统触发靠近叫声。
	world._clear_animals()
	var actual_cell := _nearby_land_cell(world, world._player_cell, world.ANIMAL_FLEE_RADIUS)
	_expect(actual_cell.x < 1000000, "真实地图找不到玩家附近的陆地动物测试格")
	if actual_cell.x < 1000000:
		var actual = world._spawn_animal(
			"dog", actual_cell, world._quantize(actual_cell.x, actual_cell.y)
		)
		_expect(actual != null, "真实主循环测试无法生成狗")
		if actual != null:
			actual.wait_remaining = 10.0
			world._update_animals(0.0)
			_expect(actual.fleeing, "玩家靠近后动物没有立即进入逃跑状态")
			audio.reset_world(42)
			audio.update_animal_sounds([actual], world._player_cell, 0.0)
			_expect(
				audio.get_animal_play_event_count() == 1,
				"真实主循环中动物逃跑前没有立即叫声"
			)
	world.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("AUDIO_SYSTEM_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
