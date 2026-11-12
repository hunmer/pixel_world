extends Node3D
## sunlight_system.gd — 将 DayNightSystem 的时钟映射为真实 DirectionalLight3D 与环境光。

const CONFIG_PATH := "res://config/sunlight.json"

var sun: DirectionalLight3D
var world_environment: WorldEnvironment

var _clock: Node
var _night_amount := 0.0
var _parameters: Dictionary = {}
var _last_progress := -1.0
var _last_night_amount := -1.0


func _ready() -> void:
	_parameters = _load_config()
	_build_lighting()
	set_process(true)


func bind(clock: Node) -> void:
	if _clock == clock:
		return
	if is_instance_valid(_clock) and _clock.night_amount_changed.is_connected(_on_night_amount_changed):
		_clock.night_amount_changed.disconnect(_on_night_amount_changed)
	_clock = clock
	_night_amount = clampf(float(_clock.get("_night_amount")), 0.0, 1.0)
	_clock.night_amount_changed.connect(_on_night_amount_changed)
	apply_time(float(_clock.get("_cycle_progress")), _night_amount)


func _process(_delta: float) -> void:
	if is_instance_valid(_clock):
		apply_time(float(_clock.get("_cycle_progress")), _night_amount)


func _on_night_amount_changed(value: float) -> void:
	_night_amount = clampf(value, 0.0, 1.0)
	if is_instance_valid(_clock):
		apply_time(float(_clock.get("_cycle_progress")), _night_amount)


## 公开入口同时供聚焦契约使用；游戏运行时只由 bind() 的时钟驱动。
func apply_time(progress: float, night_amount: float) -> void:
	if sun == null or world_environment == null:
		return
	progress = fposmod(progress, 1.0)
	night_amount = clampf(night_amount, 0.0, 1.0)
	var effective_progress := progress
	if (
		is_instance_valid(_clock)
		and bool(_clock.get("_manual_mode"))
		and not bool(_clock.get("_manual_night"))
	):
		# 手动白天覆盖太阳位置；自动时钟仍保留原进度，切回自动后继续使用。
		effective_progress = 0.5
	if is_equal_approx(effective_progress, _last_progress) and is_equal_approx(night_amount, _last_night_amount):
		return
	_last_progress = effective_progress
	_last_night_amount = night_amount

	var ground_to_sun := sun_direction(effective_progress)
	var up := Vector3.UP if absf(ground_to_sun.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
	sun.look_at_from_position(Vector3.ZERO, -ground_to_sun, up)
	var daylight := smoothstep(-0.04, 0.18, ground_to_sun.y) * (1.0 - night_amount)
	var color_blend := smoothstep(0.0, 0.42, maxf(ground_to_sun.y, 0.0))
	sun.light_color = (_parameters["twilight_color"] as Color).lerp(
		_parameters["day_color"], color_blend
	)
	sun.light_energy = lerpf(0.0, float(_parameters["day_energy"]), daylight)

	var environment := world_environment.environment
	environment.ambient_light_color = (_parameters["night_ambient_color"] as Color).lerp(
		_parameters["day_ambient_color"], 1.0 - night_amount
	)
	environment.ambient_light_energy = lerpf(
		float(_parameters["night_ambient_energy"]),
		float(_parameters["day_ambient_energy"]),
		1.0 - night_amount
	)


## 0=午夜、0.25=日出、0.5=正午、0.75=日落；方位固定，高度随时钟连续变化。
func sun_direction(progress: float) -> Vector3:
	var angle := (fposmod(progress, 1.0) - 0.25) * TAU
	var azimuth := deg_to_rad(float(_parameters.get("sun_azimuth_degrees", 32.0)))
	return Vector3(cos(angle) * cos(azimuth), sin(angle), cos(angle) * sin(azimuth)).normalized()


func _build_lighting() -> void:
	world_environment = WorldEnvironment.new()
	world_environment.name = "SunlightEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_sky_contribution = 0.0
	world_environment.environment = environment
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = float(_parameters["shadow_max_distance"])
	sun.shadow_bias = float(_parameters["shadow_bias"])
	sun.shadow_normal_bias = float(_parameters["shadow_normal_bias"])
	sun.shadow_opacity = float(_parameters["shadow_opacity"])
	add_child(sun)
	_apply_immediately()


func _apply_immediately() -> void:
	var progress := 0.5
	if is_instance_valid(_clock):
		progress = float(_clock.get("_cycle_progress"))
	apply_time(progress, _night_amount)


func _load_config() -> Dictionary:
	var values := {
		"sun_azimuth_degrees": 32.0,
		"day_energy": 0.75,
		"day_ambient_energy": 0.55,
		"night_ambient_energy": 0.38,
		"day_color": Color(1.0, 0.94, 0.82),
		"twilight_color": Color(1.0, 0.55, 0.28),
		"day_ambient_color": Color(0.92, 0.96, 1.0),
		"night_ambient_color": Color(0.48, 0.58, 0.78),
		"shadow_max_distance": 72.0,
		"shadow_bias": 0.03,
		"shadow_normal_bias": 0.45,
		"shadow_opacity": 1.0,
	}
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("日照配置不存在，使用默认值: " + CONFIG_PATH)
		return values
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("无法读取日照配置，使用默认值: " + CONFIG_PATH)
		return values
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_warning("日照配置 JSON 无效，使用默认值: " + CONFIG_PATH)
		return values
	var config: Dictionary = json.data
	if int(config.get("version", 0)) != 1:
		push_warning("日照配置版本无效，使用默认值")
		return values
	for key in ["day_color", "twilight_color", "day_ambient_color", "night_ambient_color"]:
		values[key] = Color.from_string(str(config.get(key, values[key])), values[key])
	for key in [
		"sun_azimuth_degrees", "day_energy", "day_ambient_energy", "night_ambient_energy",
		"shadow_max_distance", "shadow_bias", "shadow_normal_bias", "shadow_opacity",
	]:
		values[key] = float(config.get(key, values[key]))
	values["day_energy"] = maxf(0.0, values["day_energy"])
	values["day_ambient_energy"] = maxf(0.0, values["day_ambient_energy"])
	values["night_ambient_energy"] = maxf(0.0, values["night_ambient_energy"])
	values["shadow_max_distance"] = clampf(values["shadow_max_distance"], 8.0, 256.0)
	values["shadow_opacity"] = clampf(values["shadow_opacity"], 0.0, 1.0)
	return values
