extends Node

## 天气状态与地图生成完全解耦。
## 氛围遮罩固定在屏幕；雨雪粒子位于跟随世界视口的独立 CanvasLayer 4，
## 保持相对地面的下落速度，同时绘制在景深之后、昼夜氛围之前。

signal water_impact_requested(viewport_position: Vector2, kind: StringName, strength: float)
signal status_changed

const CONFIG_PATH := "res://config/weather.json"
const WEATHER_SHADER := preload("res://shaders/weather_overlay.gdshader")

const WEATHER_CLEAR := &"clear"
const WEATHER_RAIN := &"rain"
const WEATHER_SNOW := &"snow"
const MANUAL_SEQUENCE: Array[StringName] = [WEATHER_CLEAR, WEATHER_RAIN, WEATHER_SNOW]

const RAIN_AMOUNT := 420
const RAIN_LIFETIME := 1.35
const RAIN_SPEED_MIN := 720.0
const RAIN_SPEED_MAX := 1040.0
const RAIN_GRAVITY := Vector3(45.0, 220.0, 0.0)
const RAIN_SCALE_MIN := 0.72
const RAIN_SCALE_MAX := 1.28

const SNOW_AMOUNT := 320
const SNOW_LIFETIME := 9.0
const SNOW_SPEED_MIN := 46.0
const SNOW_SPEED_MAX := 92.0
const SNOW_GRAVITY := Vector3(8.0, 12.0, 0.0)
const SNOW_SCALE_MIN := 0.18
const SNOW_SCALE_MAX := 0.56

var _auto_interval_seconds := 60.0
var _transition_seconds := 6.0
var _manual_transition_seconds := 0.8
var _rain_start_chance := 0.33
var _rain_continue_chance := 0.20
var _snow_exit_hysteresis_levels := 2
var _rain_impact_attempts_per_second := 24.0
var _snow_impact_attempts_per_second := 12.0

var _atmosphere_layer: CanvasLayer
var _precipitation_layer: CanvasLayer
var _overlay: ColorRect
var _material: ShaderMaterial
var _rain_particles: GPUParticles2D
var _snow_particles: GPUParticles2D
var _rain_process_material: ParticleProcessMaterial
var _snow_process_material: ParticleProcessMaterial
var _last_world_per_pixel := -1.0
var _last_viewport_size := Vector2.ZERO
var _last_canvas_transform := Transform2D.IDENTITY
var _has_last_canvas_transform := false
var _last_applied_rain := -1.0
var _last_applied_snow := -1.0

var _rng := RandomNumberGenerator.new()
var _base_auto_weather: StringName = WEATHER_CLEAR
var _effective_weather: StringName = WEATHER_CLEAR
var _manual_weather: StringName = WEATHER_CLEAR
var _manual_mode := false
var _high_altitude := false
var _snow_line := 14
var _auto_elapsed := 0.0
var _rain_amount := 0.0
var _snow_amount := 0.0
var _target_rain := 0.0
var _target_snow := 0.0
var _rain_impact_budget := 0.0
var _snow_impact_budget := 0.0


func _ready() -> void:
	_load_config()
	_rng.randomize()
	_build_atmosphere()
	_build_precipitation()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_sync_particle_emitters_to_viewport(true)
	_apply_visual_state(false)
	set_process(true)


func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("天气配置不存在，使用默认值: " + CONFIG_PATH)
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("无法读取天气配置，使用默认值: " + CONFIG_PATH)
		return
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK or not json.data is Dictionary:
		push_warning("天气配置 JSON 无效，使用默认值: " + CONFIG_PATH)
		return
	var config: Dictionary = json.data
	if int(config.get("version", 0)) != 1:
		push_warning("天气配置版本无效，使用默认值")
		return
	_auto_interval_seconds = maxf(1.0, float(config.get(
		"auto_interval_seconds", _auto_interval_seconds
	)))
	_transition_seconds = maxf(0.01, float(config.get(
		"transition_seconds", _transition_seconds
	)))
	_manual_transition_seconds = maxf(0.01, float(config.get(
		"manual_transition_seconds", _manual_transition_seconds
	)))
	_rain_start_chance = clampf(float(config.get(
		"rain_start_chance", _rain_start_chance
	)), 0.0, 1.0)
	_rain_continue_chance = clampf(float(config.get(
		"rain_continue_chance", _rain_continue_chance
	)), 0.0, 1.0)
	_snow_exit_hysteresis_levels = maxi(0, int(config.get(
		"snow_exit_hysteresis_levels", _snow_exit_hysteresis_levels
	)))
	_rain_impact_attempts_per_second = maxf(0.0, float(config.get(
		"rain_impact_attempts_per_second", _rain_impact_attempts_per_second
	)))
	_snow_impact_attempts_per_second = maxf(0.0, float(config.get(
		"snow_impact_attempts_per_second", _snow_impact_attempts_per_second
	)))


func _build_atmosphere() -> void:
	_atmosphere_layer = CanvasLayer.new()
	_atmosphere_layer.name = "WeatherAtmosphereLayer"
	_atmosphere_layer.layer = 10
	_atmosphere_layer.follow_viewport_enabled = false
	add_child(_atmosphere_layer)

	_overlay = ColorRect.new()
	_overlay.name = "WeatherOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Color.WHITE
	_material = ShaderMaterial.new()
	_material.shader = WEATHER_SHADER
	_overlay.material = _material
	_atmosphere_layer.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false


func _build_precipitation() -> void:
	_precipitation_layer = CanvasLayer.new()
	_precipitation_layer.name = "PrecipitationLayer"
	_precipitation_layer.layer = 4
	_precipitation_layer.follow_viewport_enabled = true
	add_child(_precipitation_layer)

	_rain_particles = _make_rain_particles()
	_snow_particles = _make_snow_particles()
	_precipitation_layer.add_child(_rain_particles)
	_precipitation_layer.add_child(_snow_particles)


func _make_rain_particles() -> GPUParticles2D:
	var particles := _base_particle_node("RainParticles")
	particles.amount = RAIN_AMOUNT
	particles.lifetime = RAIN_LIFETIME
	particles.preprocess = RAIN_LIFETIME
	particles.randomness = 0.22
	particles.texture = _make_rain_texture()

	_rain_process_material = ParticleProcessMaterial.new()
	_rain_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_process_material.direction = Vector3(0.12, 1.0, 0.0).normalized()
	_rain_process_material.spread = 3.5
	_rain_process_material.color = Color(0.68, 0.84, 0.96, 0.64)
	_rain_process_material.color_ramp = _make_lifetime_ramp(0.62)
	_rain_process_material.set_particle_flag(
		ParticleProcessMaterial.PARTICLE_FLAG_DISABLE_Z,
		true
	)
	_rain_process_material.set_particle_flag(
		ParticleProcessMaterial.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY,
		true
	)
	particles.process_material = _rain_process_material
	return particles


func _make_snow_particles() -> GPUParticles2D:
	var particles := _base_particle_node("SnowParticles")
	particles.amount = SNOW_AMOUNT
	particles.lifetime = SNOW_LIFETIME
	particles.preprocess = SNOW_LIFETIME
	particles.randomness = 0.65
	particles.texture = _make_snow_texture()

	_snow_process_material = ParticleProcessMaterial.new()
	_snow_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_snow_process_material.direction = Vector3(0.08, 1.0, 0.0).normalized()
	_snow_process_material.spread = 18.0
	_snow_process_material.angular_velocity_min = -42.0
	_snow_process_material.angular_velocity_max = 42.0
	_snow_process_material.color = Color(0.92, 0.97, 1.0, 0.80)
	_snow_process_material.color_ramp = _make_lifetime_ramp(0.84)
	_snow_process_material.set_particle_flag(
		ParticleProcessMaterial.PARTICLE_FLAG_DISABLE_Z,
		true
	)
	particles.process_material = _snow_process_material
	return particles


func _base_particle_node(node_name: String) -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.name = node_name
	particles.emitting = false
	particles.amount_ratio = 0.0
	particles.local_coords = false
	# 30 Hz GPU simulation + interpolation keeps the streaks smooth while halving
	# particle simulation updates compared with the previous 60 Hz setting.
	particles.fixed_fps = 30
	particles.fract_delta = true
	particles.interpolate = true
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	particles.z_as_relative = false
	particles.z_index = 4095
	return particles


func _make_rain_texture() -> Texture2D:
	var width := 10
	var height := 64
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			var center := Vector2(width * 0.5, height * 0.5)
			var half_segment := height * 0.42
			var relative := point - center
			var closest_y := clampf(relative.y, -half_segment, half_segment)
			var distance := (relative - Vector2(0.0, closest_y)).length()
			var alpha := 1.0 - smoothstep(0.75, 2.35, distance)
			var tip_fade := 1.0 - smoothstep(
				half_segment - 5.0,
				half_segment + 1.0,
				absf(relative.y)
			)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha * tip_fade))
	return ImageTexture.create_from_image(image)


func _make_snow_texture() -> Texture2D:
	var size := 20
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			var distance := point.distance_to(center)
			var alpha := 1.0 - smoothstep(size * 0.16, size * 0.43, distance)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _make_lifetime_ramp(max_alpha: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.08, 0.82, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, max_alpha),
		Color(1.0, 1.0, 1.0, max_alpha),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 128
	return texture


func _on_viewport_size_changed() -> void:
	_sync_particle_emitters_to_viewport(true)


## 用 Canvas Transform 反投影视口，避免假设 Camera2D 的位置或缩放方式。
## 发射器始终补充当前视野上方；local_coords=false 使旧粒子不跟发射器平移。
func _sync_particle_emitters_to_viewport(force_restart: bool = false) -> void:
	if _rain_particles == null or _snow_particles == null:
		return
	var viewport := get_viewport()
	var viewport_size := Vector2(viewport.get_visible_rect().size)
	var canvas_transform := viewport.get_canvas_transform()
	if (
		not force_restart
		and _has_last_canvas_transform
		and viewport_size == _last_viewport_size
		and canvas_transform.is_equal_approx(_last_canvas_transform)
	):
		return
	var canvas_inverse := canvas_transform.affine_inverse()
	var world_per_pixel := canvas_inverse.basis_xform(Vector2.RIGHT).length()
	if world_per_pixel <= 0.0:
		return
	var scale_changed := not is_equal_approx(world_per_pixel, _last_world_per_pixel)
	var size_changed := viewport_size != _last_viewport_size

	_rain_particles.position = canvas_inverse * Vector2(viewport_size.x * 0.5, -72.0)
	_snow_particles.position = canvas_inverse * Vector2(viewport_size.x * 0.5, -54.0)

	if scale_changed or size_changed:
		_rain_process_material.emission_box_extents = Vector3(
			viewport_size.x * 0.58 * world_per_pixel,
			40.0 * world_per_pixel,
			0.0
		)
		_rain_process_material.initial_velocity_min = RAIN_SPEED_MIN * world_per_pixel
		_rain_process_material.initial_velocity_max = RAIN_SPEED_MAX * world_per_pixel
		_rain_process_material.gravity = RAIN_GRAVITY * world_per_pixel
		_rain_process_material.scale_min = RAIN_SCALE_MIN * world_per_pixel
		_rain_process_material.scale_max = RAIN_SCALE_MAX * world_per_pixel

		_snow_process_material.emission_box_extents = Vector3(
			viewport_size.x * 0.58 * world_per_pixel,
			90.0 * world_per_pixel,
			0.0
		)
		_snow_process_material.initial_velocity_min = SNOW_SPEED_MIN * world_per_pixel
		_snow_process_material.initial_velocity_max = SNOW_SPEED_MAX * world_per_pixel
		_snow_process_material.gravity = SNOW_GRAVITY * world_per_pixel
		_snow_process_material.scale_min = SNOW_SCALE_MIN * world_per_pixel
		_snow_process_material.scale_max = SNOW_SCALE_MAX * world_per_pixel

		var visibility_size := Vector2(
			viewport_size.x * 1.35,
			viewport_size.y + 440.0
		) * world_per_pixel
		var visibility_position := Vector2(
			-visibility_size.x * 0.5,
			-180.0 * world_per_pixel
		)
		_rain_particles.visibility_rect = Rect2(visibility_position, visibility_size)
		_snow_particles.visibility_rect = Rect2(visibility_position, visibility_size)
		_last_world_per_pixel = world_per_pixel
		_last_viewport_size = viewport_size
	_last_canvas_transform = canvas_transform
	_has_last_canvas_transform = true

	if force_restart or scale_changed:
		_restart_active_particles()


func _process(delta: float) -> void:
	if not _manual_mode:
		_auto_elapsed += delta
		while _auto_elapsed >= _auto_interval_seconds:
			_auto_elapsed -= _auto_interval_seconds
			_roll_auto_weather()

	var transition_duration := (
		_manual_transition_seconds if _manual_mode else _transition_seconds
	)
	var blend_step := delta / transition_duration
	_rain_amount = move_toward(_rain_amount, _target_rain, blend_step)
	_snow_amount = move_toward(_snow_amount, _target_snow, blend_step)
	_sync_particle_emitters_to_viewport()
	_apply_visual_state(false)
	_emit_water_impacts(delta)


func _apply_visual_state(restart_particles: bool) -> void:
	var has_visible_weather := _rain_amount > 0.001 or _snow_amount > 0.001
	if _overlay.visible != has_visible_weather:
		_overlay.visible = has_visible_weather
	if restart_particles or not is_equal_approx(_last_applied_rain, _rain_amount):
		_material.set_shader_parameter("rain_amount", _rain_amount)
		_apply_particle_strength(_rain_particles, _rain_amount, restart_particles)
		_last_applied_rain = _rain_amount
	if restart_particles or not is_equal_approx(_last_applied_snow, _snow_amount):
		_material.set_shader_parameter("snow_amount", _snow_amount)
		_apply_particle_strength(_snow_particles, _snow_amount, restart_particles)
		_last_applied_snow = _snow_amount


func _apply_particle_strength(
	particles: GPUParticles2D,
	strength: float,
	restart_particles: bool
) -> void:
	var active := strength > 0.001
	particles.amount_ratio = clampf(strength, 0.0, 1.0)
	particles.self_modulate = Color(1.0, 1.0, 1.0, clampf(strength * 1.5, 0.0, 1.0))
	if active:
		var was_emitting := particles.emitting
		particles.emitting = true
		if restart_particles or not was_emitting:
			particles.restart()
	else:
		particles.emitting = false


func _restart_active_particles() -> void:
	if _rain_amount > 0.001:
		_rain_particles.restart()
	if _snow_amount > 0.001:
		_snow_particles.restart()


func _roll_auto_weather() -> void:
	if _base_auto_weather == WEATHER_RAIN:
		_base_auto_weather = (
			WEATHER_RAIN if _rng.randf() < _rain_continue_chance else WEATHER_CLEAR
		)
	else:
		_base_auto_weather = (
			WEATHER_RAIN if _rng.randf() < _rain_start_chance else WEATHER_CLEAR
		)
	_refresh_effective_weather()


func set_environment(level: int, snow_biome: bool, snow_line: int) -> void:
	_snow_line = snow_line
	var previous_high_altitude := _high_altitude
	if snow_biome or level >= _snow_line:
		_high_altitude = true
	elif level <= _snow_line - _snow_exit_hysteresis_levels:
		_high_altitude = false
	if previous_high_altitude != _high_altitude and not _manual_mode:
		_refresh_effective_weather()


func cycle_manual_weather() -> void:
	var current := _manual_weather if _manual_mode else _effective_weather
	var current_index := MANUAL_SEQUENCE.find(current)
	_manual_weather = MANUAL_SEQUENCE[(current_index + 1) % MANUAL_SEQUENCE.size()]
	_manual_mode = true
	_set_effective_weather(_manual_weather)
	status_changed.emit()


func set_manual_weather(weather: StringName) -> bool:
	if weather not in MANUAL_SEQUENCE:
		return false
	_manual_mode = true
	_manual_weather = weather
	_set_effective_weather(weather)
	status_changed.emit()
	return true


func set_auto_mode() -> void:
	if not _manual_mode:
		return
	_manual_mode = false
	_auto_elapsed = 0.0
	_refresh_effective_weather()
	status_changed.emit()


func snap_transition() -> void:
	_rain_amount = _target_rain
	_snow_amount = _target_snow
	_sync_particle_emitters_to_viewport()
	_apply_visual_state(true)


func refresh_particle_field() -> void:
	_sync_particle_emitters_to_viewport(true)
	_apply_visual_state(true)


func _refresh_effective_weather() -> void:
	if _manual_mode:
		_set_effective_weather(_manual_weather)
	elif _high_altitude:
		_set_effective_weather(WEATHER_SNOW)
	else:
		_set_effective_weather(_base_auto_weather)


func _set_effective_weather(weather: StringName) -> void:
	var changed := weather != _effective_weather
	_effective_weather = weather
	_target_rain = 1.0 if weather == WEATHER_RAIN else 0.0
	_target_snow = 1.0 if weather == WEATHER_SNOW else 0.0
	if changed:
		status_changed.emit()


func _emit_water_impacts(delta: float) -> void:
	if _rain_amount <= 0.001 and _snow_amount <= 0.001:
		return
	# 丢弃长帧积压，避免卡顿后连续数帧追赶几十个涟漪并进一步放大抖动。
	_rain_impact_budget = minf(
		_rain_impact_budget + delta * _rain_impact_attempts_per_second * _rain_amount,
		3.0
	)
	_snow_impact_budget = minf(
		_snow_impact_budget + delta * _snow_impact_attempts_per_second * _snow_amount,
		2.0
	)
	var viewport_size := Vector2(get_viewport().get_visible_rect().size)
	var attempts := 0
	while _rain_impact_budget >= 1.0 and attempts < 3:
		_rain_impact_budget -= 1.0
		attempts += 1
		water_impact_requested.emit(_random_viewport_point(viewport_size), &"rain", _rain_amount)
	attempts = 0
	while _snow_impact_budget >= 1.0 and attempts < 2:
		_snow_impact_budget -= 1.0
		attempts += 1
		water_impact_requested.emit(_random_viewport_point(viewport_size), &"snow", _snow_amount)


func _random_viewport_point(viewport_size: Vector2) -> Vector2:
	return Vector2(
		_rng.randf_range(viewport_size.x * 0.035, viewport_size.x * 0.965),
		_rng.randf_range(viewport_size.y * 0.04, viewport_size.y * 0.97)
	)


func get_status_text() -> String:
	var weather_name: String = {
		WEATHER_CLEAR: "晴",
		WEATHER_RAIN: "雨",
		WEATHER_SNOW: "雪",
	}.get(_effective_weather, "未知")
	if _manual_mode:
		return "%s（手动）" % weather_name
	if _high_altitude:
		return "%s（自动·高海拔）" % weather_name
	return "%s（自动）" % weather_name


func get_effective_weather() -> StringName:
	return _effective_weather


func get_rain_amount() -> float:
	return _rain_amount


func get_snow_amount() -> float:
	return _snow_amount


func is_manual_mode() -> bool:
	return _manual_mode
