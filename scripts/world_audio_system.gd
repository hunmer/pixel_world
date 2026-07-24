extends Node2D

## 世界音频与地图生成解耦：音乐按昼夜交叉淡化，雨声随天气淡入淡出，
## 动物叫声只在玩家附近低频触发。

const CONFIG_PATH := "res://config/audio.json"
const SILENT_DB := -80.0
const ANIMAL_OWNER_META := &"animal_owner_instance_id"
const ANIMAL_GROUP_META := &"animal_polyphony_group"

var _config_valid := false
var _music_volume_db := -22.0
var _music_crossfade_seconds := 4.0
var _music_mix := 0.0
var _target_music_mix := 0.0
var _rain_volume_db := -26.0
var _rain_fade_seconds := 2.5
var _rain_mix := 0.0
var _target_rain_mix := 0.0
var _rain_stream_path := ""

var _day_music: AudioStreamPlayer
var _night_music: AudioStreamPlayer
var _rain_ambience: AudioStreamPlayer
var _animal_players: Array[AudioStreamPlayer2D] = []
var _animal_streams := {}
var _animal_configs := {}
var _animal_states := {}
var _required_animal_species := {}
var _global_interval := Vector2(6.0, 12.0)
var _global_sound_wait := 0.0
var _world_seed := 1
var _animal_play_event_count := 0


func _ready() -> void:
	_config_valid = _load_config()
	if not _config_valid:
		set_process(false)
		return
	_build_music_players()
	_build_weather_ambience_player()
	_build_animal_players()
	_apply_music_mix()
	_apply_rain_mix()
	set_process(true)


func configure_animal_species(species_ids: Array) -> void:
	_required_animal_species.clear()
	for species_id_value in species_ids:
		var species_id := String(species_id_value)
		if not species_id.is_empty():
			_required_animal_species[species_id] = true


func _exit_tree() -> void:
	if _day_music != null:
		_day_music.stop()
		_day_music.stream = null
	if _night_music != null:
		_night_music.stop()
		_night_music.stream = null
	if _rain_ambience != null:
		_rain_ambience.stop()
		_rain_ambience.stream = null
	for player in _animal_players:
		player.stop()
		player.stream = null
		if player.has_meta(ANIMAL_OWNER_META):
			player.remove_meta(ANIMAL_OWNER_META)
		if player.has_meta(ANIMAL_GROUP_META):
			player.remove_meta(ANIMAL_GROUP_META)
	_animal_streams.clear()


func _load_config() -> bool:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("音频配置不存在: " + CONFIG_PATH)
		return false
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取音频配置: " + CONFIG_PATH)
		return false
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK or not json.data is Dictionary:
		push_error("音频配置 JSON 无效: " + CONFIG_PATH)
		return false
	var config: Dictionary = json.data
	if int(config.get("version", 0)) != 1:
		push_error("音频配置版本无效")
		return false

	var music: Dictionary = config.get("music", {})
	var day_path := String(music.get("day_stream", ""))
	var night_path := String(music.get("night_stream", ""))
	if not _resource_path_is_valid(day_path) or not _resource_path_is_valid(night_path):
		push_error("昼夜音乐资源不存在")
		return false
	_music_volume_db = clampf(float(music.get("volume_db", -22.0)), -40.0, -6.0)
	_music_crossfade_seconds = maxf(0.05, float(music.get("crossfade_seconds", 4.0)))
	_day_music = _make_music_player("DayMusic", day_path)
	_night_music = _make_music_player("NightMusic", night_path)

	var weather_ambience_value: Variant = config.get("weather_ambience", {})
	if not weather_ambience_value is Dictionary:
		push_error("天气环境音配置必须是 Dictionary")
		return false
	var weather_ambience: Dictionary = weather_ambience_value
	var rain_value: Variant = weather_ambience.get("rain", {})
	if not rain_value is Dictionary:
		push_error("雨声配置必须是 Dictionary")
		return false
	var rain: Dictionary = rain_value
	var rain_path := String(rain.get("stream", ""))
	if not _resource_path_is_valid(rain_path):
		push_error("雨声资源不存在: " + rain_path)
		return false
	_rain_stream_path = rain_path
	_rain_volume_db = clampf(float(rain.get("volume_db", -26.0)), -50.0, -6.0)
	if _rain_volume_db >= _music_volume_db:
		push_error("雨声基础音量必须低于 BGM")
		return false
	_rain_fade_seconds = maxf(0.05, float(rain.get("fade_seconds", 2.5)))
	_rain_ambience = _make_music_player("RainAmbience", rain_path)

	var animal_sounds: Dictionary = config.get("animal_sounds", {})
	_global_interval = _read_float_range(
		animal_sounds.get("global_interval_seconds", [6.0, 12.0]),
		Vector2(6.0, 12.0),
		0.0
	)
	var defaults: Dictionary = animal_sounds.get("defaults", {})
	var species_configs: Dictionary = animal_sounds.get("species", {})
	for required_species_id_value in _required_animal_species:
		var required_species_id := String(required_species_id_value)
		if not species_configs.has(required_species_id):
			push_error("动物缺少音效配置: " + required_species_id)
			return false
	for species_id_value in species_configs:
		var species_id := String(species_id_value)
		var configured: Dictionary = defaults.duplicate(true)
		var overrides: Dictionary = species_configs[species_id]
		for key in overrides:
			configured[key] = overrides[key]
		var stream_path := String(configured.get("stream", ""))
		if not _resource_path_is_valid(stream_path):
			push_error("动物音效资源不存在 [%s]: %s" % [species_id, stream_path])
			return false
		configured["trigger_radius"] = maxi(1, int(configured.get("trigger_radius", 10)))
		configured["approach_call"] = bool(configured.get("approach_call", true))
		configured["chase_interval_seconds"] = _read_float_range(
			configured.get("chase_interval_seconds", [1.0, 1.0]),
			Vector2(1.0, 1.0),
			0.1
		)
		configured["interval_seconds"] = _read_float_range(
			configured.get("interval_seconds", [20.0, 45.0]),
			Vector2(20.0, 45.0),
			0.1
		)
		configured["pitch_scale"] = _read_float_range(
			configured.get("pitch_scale", [0.96, 1.04]),
			Vector2(0.96, 1.04),
			0.1
		)
		configured["volume_db"] = clampf(
			float(configured.get("volume_db", -18.0)),
			-40.0,
			-6.0
		)
		configured["max_distance_pixels"] = maxf(
			64.0,
			float(configured.get("max_distance_pixels", 320.0))
		)
		configured["attenuation"] = maxf(0.1, float(configured.get("attenuation", 1.35)))
		configured["polyphony_group"] = String(
			configured.get("polyphony_group", "general")
		)
		if String(configured["polyphony_group"]).is_empty():
			push_error("动物音效并发组不能为空: " + species_id)
			return false
		configured["polyphony_limit"] = clampi(
			int(configured.get("polyphony_limit", 1)),
			1,
			8
		)
		_animal_configs[species_id] = configured
		_animal_streams[species_id] = load(stream_path)

	var max_simultaneous := clampi(
		int(animal_sounds.get("max_simultaneous", 1)),
		1,
		8
	)
	for index in max_simultaneous:
		var player := AudioStreamPlayer2D.new()
		player.name = "AnimalSound%d" % index
		player.panning_strength = 0.65
		_animal_players.append(player)
	return true


func _resource_path_is_valid(path: String) -> bool:
	return not path.is_empty() and ResourceLoader.exists(path)


func _read_float_range(value: Variant, fallback: Vector2, minimum: float) -> Vector2:
	if not value is Array or value.size() != 2:
		return fallback
	var first := maxf(minimum, float(value[0]))
	var second := maxf(first, float(value[1]))
	return Vector2(first, second)


func _make_music_player(player_name: String, stream_path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	var source: AudioStream = load(stream_path)
	var looped := source.duplicate(true) as AudioStream
	if looped is AudioStreamMP3:
		(looped as AudioStreamMP3).loop = true
	player.stream = looped
	return player


func _build_music_players() -> void:
	add_child(_day_music)
	add_child(_night_music)
	_day_music.play()
	_night_music.play()


func _build_weather_ambience_player() -> void:
	add_child(_rain_ambience)
	_rain_ambience.volume_db = SILENT_DB


func _build_animal_players() -> void:
	for player in _animal_players:
		add_child(player)


func _process(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	_music_mix = move_toward(
		_music_mix,
		_target_music_mix,
		safe_delta / _music_crossfade_seconds
	)
	_rain_mix = move_toward(
		_rain_mix,
		_target_rain_mix,
		safe_delta / _rain_fade_seconds
	)
	_apply_music_mix()
	_apply_rain_mix()


func set_night_amount(value: float, snap := false) -> void:
	_target_music_mix = clampf(value, 0.0, 1.0)
	if snap:
		_music_mix = _target_music_mix
		_apply_music_mix()


func set_rain_amount(value: float, snap := false) -> void:
	_target_rain_mix = clampf(value, 0.0, 1.0)
	if _target_rain_mix > 0.0001 and not _rain_ambience.playing:
		_rain_ambience.volume_db = SILENT_DB
		_rain_ambience.play()
	if snap:
		_rain_mix = _target_rain_mix
		_apply_rain_mix()


func _apply_music_mix() -> void:
	if _day_music == null or _night_music == null:
		return
	var angle := clampf(_music_mix, 0.0, 1.0) * PI * 0.5
	_day_music.volume_db = _music_gain_db(cos(angle))
	_night_music.volume_db = _music_gain_db(sin(angle))


func _apply_rain_mix() -> void:
	if _rain_ambience == null:
		return
	_rain_ambience.volume_db = _rain_gain_db(_rain_mix)
	# 淡出完成后停止解码；只有实际雨天才维持循环播放。
	if (
		_rain_mix <= 0.0001
		and _target_rain_mix <= 0.0001
		and _rain_ambience.playing
	):
		_rain_ambience.stop()


func _music_gain_db(gain: float) -> float:
	if gain <= 0.0001:
		return SILENT_DB
	return _music_volume_db + linear_to_db(gain)


func _rain_gain_db(gain: float) -> float:
	if gain <= 0.0001:
		return SILENT_DB
	return _rain_volume_db + linear_to_db(gain)


func reset_world(world_seed: int) -> void:
	_world_seed = world_seed
	_animal_states.clear()
	_global_sound_wait = 0.0
	_animal_play_event_count = 0
	for player in _animal_players:
		player.stop()
		if player.has_meta(ANIMAL_OWNER_META):
			player.remove_meta(ANIMAL_OWNER_META)
		if player.has_meta(ANIMAL_GROUP_META):
			player.remove_meta(ANIMAL_GROUP_META)


func update_animal_sounds(animals: Array, player_cell: Vector2i, delta: float) -> void:
	if not _config_valid:
		return
	_global_sound_wait = maxf(0.0, _global_sound_wait - maxf(delta, 0.0))
	var alive_animals := {}
	for animal_value in animals:
		if not is_instance_valid(animal_value):
			continue
		var animal = animal_value
		var instance_id: int = int(animal.get_instance_id())
		alive_animals[instance_id] = animal
	_refresh_playing_animal_sounds(alive_animals, player_cell)
	for instance_id in alive_animals:
		var animal = alive_animals[instance_id]
		var species_id := String(animal.species_id)
		if not _animal_configs.has(species_id):
			continue
		if not animal.visible:
			if _animal_states.has(instance_id):
				var hidden_state: Dictionary = _animal_states[instance_id]
				hidden_state["near_player"] = false
				hidden_state["approach_pending"] = false
				hidden_state["was_fleeing"] = false
				hidden_state["chase_wait_remaining"] = 0.0
				_animal_states[instance_id] = hidden_state
			continue
		var config: Dictionary = _animal_configs[species_id]
		var radius := int(config["trigger_radius"])
		var near_player := _animal_is_near_player(animal, player_cell, radius)
		var state: Dictionary = _animal_states.get(instance_id, {
			"near_player": false,
			"approach_pending": false,
			"was_fleeing": false,
			"chase_wait_remaining": 0.0,
			"wait_remaining": 0.0,
			"event_index": 0,
		})
		if not near_player:
			state["near_player"] = false
			state["approach_pending"] = false
			state["was_fleeing"] = false
			state["chase_wait_remaining"] = 0.0
			_animal_states[instance_id] = state
			continue
		var just_approached := not bool(state["near_player"])
		var fleeing := bool(animal.fleeing)
		if just_approached:
			state["near_player"] = true
			state["approach_pending"] = bool(config["approach_call"])
			state["was_fleeing"] = fleeing
			state["chase_wait_remaining"] = 0.0

		# 首次靠近是有保证的事件，不受全局偶发叫声冷却影响；播放器忙时保留 pending。
		if bool(state["approach_pending"]):
			if _play_animal_sound(
				animal, species_id, config, int(state["event_index"]), false
			):
				state["approach_pending"] = false
				state["event_index"] = int(state["event_index"]) + 1
				state["wait_remaining"] = _animal_wait(
					animal,
					int(state["event_index"]),
					config["interval_seconds"],
					1201
				)
				state["chase_wait_remaining"] = _animal_wait(
					animal,
					int(state["event_index"]),
					config["chase_interval_seconds"],
					1251
				)
				_global_sound_wait = _animal_wait(
					animal,
					int(state["event_index"]),
					_global_interval,
					1301
				)
			_animal_states[instance_id] = state
			continue

		# 玩家持续追逐时，每约一秒重触发同一只动物的叫声；该紧急事件绕过普通冷却。
		if fleeing:
			if not bool(state["was_fleeing"]):
				state["chase_wait_remaining"] = 0.0
			state["was_fleeing"] = true
			state["chase_wait_remaining"] = maxf(
				0.0,
				float(state["chase_wait_remaining"]) - maxf(delta, 0.0)
			)
			# 单播放器优先兑现其他动物欠下的首次靠近叫声，防止首只动物每秒
			# 重启音效而让后来者永久饥饿；其追逐计时保持为 0，之后会继续尝试。
			if _has_pending_approach(
				instance_id,
				alive_animals,
				player_cell,
				String(config["polyphony_group"])
			):
				_animal_states[instance_id] = state
				continue
			if float(state["chase_wait_remaining"]) <= 0.0:
				if _play_animal_sound(
					animal, species_id, config, int(state["event_index"]), true
				):
					state["event_index"] = int(state["event_index"]) + 1
					state["chase_wait_remaining"] = _animal_wait(
						animal,
						int(state["event_index"]),
						config["chase_interval_seconds"],
						1251
					)
					_global_sound_wait = _animal_wait(
						animal,
						int(state["event_index"]),
						_global_interval,
						1301
					)
			_animal_states[instance_id] = state
			continue

		state["was_fleeing"] = false
		state["chase_wait_remaining"] = 0.0
		state["wait_remaining"] = maxf(
			0.0,
			float(state["wait_remaining"]) - maxf(delta, 0.0)
		)
		if float(state["wait_remaining"]) > 0.0 or _global_sound_wait > 0.0:
			_animal_states[instance_id] = state
			continue
		if _play_animal_sound(
			animal, species_id, config, int(state["event_index"]), false
		):
			state["event_index"] = int(state["event_index"]) + 1
			state["wait_remaining"] = _animal_wait(
				animal,
				int(state["event_index"]),
				config["interval_seconds"],
				1201
			)
			_global_sound_wait = _animal_wait(
				animal,
				int(state["event_index"]),
				_global_interval,
				1301
			)
		else:
			state["wait_remaining"] = 1.0
		_animal_states[instance_id] = state
	for instance_id in _animal_states.keys():
		if not alive_animals.has(instance_id):
			_animal_states.erase(instance_id)


func _has_pending_approach(
	except_instance_id: int,
	alive_animals: Dictionary,
	player_cell: Vector2i,
	polyphony_group: String
) -> bool:
	for instance_id in _animal_states:
		if int(instance_id) == except_instance_id:
			continue
		var state: Dictionary = _animal_states[instance_id]
		if not bool(state.get("approach_pending", false)):
			continue
		if not alive_animals.has(instance_id):
			continue
		var animal = alive_animals[instance_id]
		if not animal.visible:
			continue
		var species_id := String(animal.species_id)
		if not _animal_configs.has(species_id):
			continue
		var config: Dictionary = _animal_configs[species_id]
		if String(config["polyphony_group"]) != polyphony_group:
			continue
		if _animal_is_near_player(animal, player_cell, int(config["trigger_radius"])):
			return true
	return false


func _refresh_playing_animal_sounds(
	alive_animals: Dictionary,
	player_cell: Vector2i
) -> void:
	for player in _animal_players:
		if not player.playing:
			if player.has_meta(ANIMAL_OWNER_META):
				player.remove_meta(ANIMAL_OWNER_META)
			if player.has_meta(ANIMAL_GROUP_META):
				player.remove_meta(ANIMAL_GROUP_META)
			continue
		var owner_id := int(player.get_meta(ANIMAL_OWNER_META, 0))
		if owner_id == 0 or not alive_animals.has(owner_id):
			_stop_animal_player(player)
			continue
		var animal = alive_animals[owner_id]
		var species_id := String(animal.species_id)
		if not _animal_configs.has(species_id) or not animal.visible:
			_stop_animal_player(player)
			continue
		var config: Dictionary = _animal_configs[species_id]
		if not _animal_is_near_player(
			animal,
			player_cell,
			int(config["trigger_radius"])
		):
			_stop_animal_player(player)
			continue
		# 叫声持续期间跟随动物，避免空间声像停留在触发时的旧位置。
		player.position = animal.current_visual_position()


func _animal_is_near_player(animal, player_cell: Vector2i, radius: int) -> bool:
	var distance_squared: float = animal.grid_cell.distance_squared_to(player_cell)
	if animal.moving:
		distance_squared = minf(
			distance_squared,
			animal.target_cell.distance_squared_to(player_cell)
		)
	return distance_squared <= radius * radius


func _stop_animal_player(player: AudioStreamPlayer2D) -> void:
	player.stop()
	if player.has_meta(ANIMAL_OWNER_META):
		player.remove_meta(ANIMAL_OWNER_META)
	if player.has_meta(ANIMAL_GROUP_META):
		player.remove_meta(ANIMAL_GROUP_META)


func _play_animal_sound(
	animal,
	species_id: String,
	config: Dictionary,
	event_index: int,
	restart_same_owner: bool
) -> bool:
	var available: AudioStreamPlayer2D = null
	var owner_id := int(animal.get_instance_id())
	var polyphony_group := String(config["polyphony_group"])
	if restart_same_owner:
		for player in _animal_players:
			if (
				player.playing
				and int(player.get_meta(ANIMAL_OWNER_META, 0)) == owner_id
			):
				available = player
				player.stop()
				break
	if available == null:
		var group_playing := 0
		for player in _animal_players:
			if (
				player.playing
				and String(player.get_meta(ANIMAL_GROUP_META, "")) == polyphony_group
			):
				group_playing += 1
		if group_playing >= int(config["polyphony_limit"]):
			return false
	for player in _animal_players:
		if available != null:
			break
		if not player.playing:
			available = player
			break
	if available == null:
		return false
	available.stream = _animal_streams[species_id]
	available.position = animal.current_visual_position()
	available.volume_db = float(config["volume_db"])
	available.max_distance = float(config["max_distance_pixels"])
	available.attenuation = float(config["attenuation"])
	available.set_meta(ANIMAL_OWNER_META, owner_id)
	available.set_meta(ANIMAL_GROUP_META, polyphony_group)
	var pitch_range: Vector2 = config["pitch_scale"]
	available.pitch_scale = lerpf(
		pitch_range.x,
		pitch_range.y,
		_animal_rand(animal, event_index, 1401)
	)
	available.play()
	_animal_play_event_count += 1
	return true


func _animal_wait(animal, event_index: int, interval: Vector2, salt: int) -> float:
	return lerpf(
		interval.x,
		interval.y,
		_animal_rand(animal, event_index, salt)
	)


func _animal_rand(animal, event_index: int, salt: int) -> float:
	var origin: Vector2i = animal.origin_cell
	var value := (
		origin.x * 0x8da6b343
		^ origin.y * 0xd8163841
		^ (_world_seed + salt + event_index * 0x9e3779b9)
	)
	return _hash_u32(value) / 4294967295.0


func _hash_u32(value: int) -> int:
	value = (value ^ (value >> 16)) & 0xFFFFFFFF
	value = (value * 0x7feb352d) & 0xFFFFFFFF
	value = (value ^ (value >> 15)) & 0xFFFFFFFF
	value = (value * 0x846ca68b) & 0xFFFFFFFF
	value = (value ^ (value >> 16)) & 0xFFFFFFFF
	return value


func is_config_valid() -> bool:
	return _config_valid


func has_animal_sound(species_id: String) -> bool:
	return _animal_configs.has(species_id)


func get_day_music_volume_db() -> float:
	return _day_music.volume_db if _day_music != null else SILENT_DB


func get_night_music_volume_db() -> float:
	return _night_music.volume_db if _night_music != null else SILENT_DB


func get_rain_ambience_volume_db() -> float:
	return _rain_ambience.volume_db if _rain_ambience != null else SILENT_DB


func get_rain_amount() -> float:
	return _rain_mix


func get_target_rain_amount() -> float:
	return _target_rain_mix


func get_playing_animal_sound_count() -> int:
	var count := 0
	for player in _animal_players:
		if player.playing:
			count += 1
	return count


func get_animal_play_event_count() -> int:
	return _animal_play_event_count
