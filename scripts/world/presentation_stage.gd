## presentation_stage.gd — 表现层系统装配 builder：昼夜/阳光、景深、音频、萤火虫、天气。
##
## 从 main.gd 簇15 的五个 _setup_* 迁出（结构性拆分，行为不变）。节点创建、
## 命名、add_child 顺序与信号连线顺序逐行保持；`--time` / `--dof` / `--weather`
## 命令行解析随迁。main 侧字段赋值与调用顺序不变；绑定 main 处理器的信号经
## Callable 显式传入（不反向依赖 main.gd）。
class_name PresentationStage
extends RefCounted

const WeatherSystemScript = preload("res://scripts/weather_system.gd")
const DayNightSystemScript = preload("res://scripts/day_night_system.gd")
const SunlightSystemScript = preload("res://scripts/sunlight_system.gd")
const WorldAudioSystemScript = preload("res://scripts/world_audio_system.gd")
const DepthOfFieldSystemScript = preload("res://scripts/depth_of_field_system.gd")
const AmbientRegistryScript = preload("res://scripts/ecology/ambient_registry.gd")


## 返回 { "day_night": DayNightSystem, "sunlight": SunlightSystem }。
static func build_day_night(host: Node) -> Dictionary:
	var day_night := DayNightSystemScript.new()
	day_night.name = "DayNightSystem"
	host.add_child(day_night)
	var sunlight := SunlightSystemScript.new()
	sunlight.name = "SunlightSystem"
	host.add_child(sunlight)
	sunlight.bind(day_night)
	var args := OS.get_cmdline_user_args()
	var time_arg := args.find("--time")
	if time_arg == -1 or time_arg + 1 >= args.size():
		return {"day_night": day_night, "sunlight": sunlight}
	var requested := String(args[time_arg + 1]).to_lower()
	match requested:
		"day":
			day_night.set_manual_night(false)
		"night":
			day_night.set_manual_night(true)
		"auto":
			day_night.set_auto_mode()
		_:
			push_warning("--time 只接受 day / night / auto")
			return {"day_night": day_night, "sunlight": sunlight}
	day_night.snap_transition()
	return {"day_night": day_night, "sunlight": sunlight}


static func build_depth_of_field(host: Node) -> DepthOfFieldSystemScript:
	var depth_of_field := DepthOfFieldSystemScript.new()
	depth_of_field.name = "DepthOfFieldSystem"
	host.add_child(depth_of_field)
	var args := OS.get_cmdline_user_args()
	var depth_arg := args.find("--dof")
	if depth_arg == -1 or depth_arg + 1 >= args.size():
		return depth_of_field
	var requested := String(args[depth_arg + 1]).to_lower()
	if requested in ["on", "true", "1"]:
		depth_of_field.set_enabled(true)
	elif requested in ["off", "false", "0"]:
		depth_of_field.set_enabled(false)
	else:
		push_warning("--dof 只接受 on / off")
	return depth_of_field


static func build_world_audio(
	host: Node,
	animal_species: Dictionary,
	day_night
) -> WorldAudioSystemScript:
	var audio := WorldAudioSystemScript.new()
	audio.name = "WorldAudioSystem"
	var audible_species: Array = []
	for species_id_value in animal_species:
		var species: Dictionary = animal_species[species_id_value]
		var metadata: Dictionary = species.get("metadata", {})
		if not bool(metadata.get("silent", false)):
			audible_species.append(String(species_id_value))
	audio.configure_animal_species(audible_species)
	host.add_child(audio)
	if not audio.is_config_valid():
		push_warning("世界音频未启用：配置或资源无效")
		return audio
	if day_night != null:
		day_night.night_amount_changed.connect(audio.set_night_amount)
		audio.set_night_amount(day_night.get_night_amount(), true)
	return audio


## 返回 { "registry": AmbientRegistry, "fireflies": 萤火虫渲染器 }。
static func build_ambient_registry(
	host: Node,
	ambient_species: Dictionary,
	day_night
) -> Dictionary:
	var registry := AmbientRegistryScript.new()
	registry.name = "AmbientRegistry"
	host.add_child(registry)
	if not registry.register_species_catalog(ambient_species):
		push_error("Ambient registry 配置无效: %s" % [registry.get_errors()])
	var fireflies = registry.get_renderer(&"firefly")
	if day_night != null:
		day_night.night_amount_changed.connect(
			registry.set_all_environment_amount
		)
		registry.set_all_environment_amount(
			day_night.get_night_amount()
		)
	return {"registry": registry, "fireflies": fireflies}


## water_impact / status_changed 为 main 侧处理器 Callable（屏幕水波 / 音频同步）。
static func build_weather(
	host: Node,
	water_impact: Callable,
	status_changed: Callable
) -> WeatherSystemScript:
	var weather := WeatherSystemScript.new()
	weather.name = "WeatherSystem"
	host.add_child(weather)
	weather.water_impact_requested.connect(water_impact)
	weather.status_changed.connect(status_changed)
	var args := OS.get_cmdline_user_args()
	var weather_arg := args.find("--weather")
	if weather_arg != -1 and weather_arg + 1 < args.size():
		var requested := StringName(args[weather_arg + 1].to_lower())
		if requested == &"auto":
			weather.set_auto_mode()
		elif not weather.set_manual_weather(requested):
			push_warning("--weather 只接受 clear / rain / snow / auto")
		else:
			weather.snap_transition()
	return weather
