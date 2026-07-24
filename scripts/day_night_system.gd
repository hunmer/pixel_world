extends Node

## 独立于地图生成和天气状态机的昼夜时钟。
## 世界上方使用一层屏幕空间靛蓝氛围，天气层继续绘制在其上，HUD 不受影响。

signal night_amount_changed(value: float)
signal status_changed

const CONFIG_PATH := "res://config/day_night.json"
const NIGHT_SHADER := preload("res://shaders/day_night_overlay.gdshader")

var _cycle_seconds := 480.0
var _cycle_progress := 0.5  ## 0=午夜，0.5=正午
var _manual_transition_seconds := 0.8
var _sunrise_start := 0.18
var _sunrise_end := 0.28
var _sunset_start := 0.70
var _sunset_end := 0.82
var _night_overlay_opacity := 0.63

var _atmosphere_layer: CanvasLayer
var _overlay: ColorRect
var _material: ShaderMaterial
var _manual_mode := false
var _manual_night := false
var _auto_resume_blend := false
var _night_amount := 0.0
var _target_night_amount := 0.0
var _elapsed_time := 0.0
var _last_emitted_amount := -1.0
var _last_status_text := ""


func _ready() -> void:
	_load_config()
	_build_atmosphere()
	_target_night_amount = _automatic_night_amount(_cycle_progress)
	_night_amount = _target_night_amount
	_apply_visual_state(true)
	_sync_status()
	set_process(true)


func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("昼夜配置不存在，使用默认值: " + CONFIG_PATH)
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("无法读取昼夜配置，使用默认值: " + CONFIG_PATH)
		return
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK or not json.data is Dictionary:
		push_warning("昼夜配置 JSON 无效，使用默认值: " + CONFIG_PATH)
		return
	var config: Dictionary = json.data
	if int(config.get("version", 0)) != 1:
		push_warning("昼夜配置版本无效，使用默认值")
		return

	var sunrise_start := float(config.get("sunrise_start", _sunrise_start))
	var sunrise_end := float(config.get("sunrise_end", _sunrise_end))
	var sunset_start := float(config.get("sunset_start", _sunset_start))
	var sunset_end := float(config.get("sunset_end", _sunset_end))
	if not (
		0.0 <= sunrise_start
		and sunrise_start < sunrise_end
		and sunrise_end < sunset_start
		and sunset_start < sunset_end
		and sunset_end <= 1.0
	):
		push_warning("昼夜配置的日出/日落区间无效，使用默认区间")
	else:
		_sunrise_start = sunrise_start
		_sunrise_end = sunrise_end
		_sunset_start = sunset_start
		_sunset_end = sunset_end

	_cycle_seconds = maxf(10.0, float(config.get(
		"cycle_seconds", _cycle_seconds
	)))
	_cycle_progress = fposmod(float(config.get(
		"start_progress", _cycle_progress
	)), 1.0)
	_manual_transition_seconds = maxf(0.01, float(config.get(
		"manual_transition_seconds", _manual_transition_seconds
	)))
	_night_overlay_opacity = clampf(float(config.get(
		"night_overlay_opacity", _night_overlay_opacity
	)), 0.0, 0.9)


func _build_atmosphere() -> void:
	_atmosphere_layer = CanvasLayer.new()
	_atmosphere_layer.name = "DayNightAtmosphereLayer"
	_atmosphere_layer.layer = 5
	_atmosphere_layer.follow_viewport_enabled = false
	add_child(_atmosphere_layer)

	_overlay = ColorRect.new()
	_overlay.name = "NightOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Color.WHITE
	_material = ShaderMaterial.new()
	_material.shader = NIGHT_SHADER
	_overlay.material = _material
	_atmosphere_layer.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false


func _process(delta: float) -> void:
	_elapsed_time += maxf(delta, 0.0)
	if _manual_mode:
		_target_night_amount = 1.0 if _manual_night else 0.0
		_night_amount = move_toward(
			_night_amount,
			_target_night_amount,
			maxf(delta, 0.0) / _manual_transition_seconds
		)
	else:
		_cycle_progress = fposmod(
			_cycle_progress + maxf(delta, 0.0) / _cycle_seconds,
			1.0
		)
		_target_night_amount = _automatic_night_amount(_cycle_progress)
		if _auto_resume_blend:
			_night_amount = move_toward(
				_night_amount,
				_target_night_amount,
				maxf(delta, 0.0) / _manual_transition_seconds
			)
			if is_equal_approx(_night_amount, _target_night_amount):
				_auto_resume_blend = false
		else:
			# 自动曲线本身已在日出/日落区间做平滑插值，不再叠加迟滞。
			_night_amount = _target_night_amount

	_apply_visual_state(false)
	_sync_status()


func _automatic_night_amount(progress: float) -> float:
	var value := fposmod(progress, 1.0)
	if value < _sunrise_start or value >= _sunset_end:
		return 1.0
	if value < _sunrise_end:
		return 1.0 - smoothstep(_sunrise_start, _sunrise_end, value)
	if value < _sunset_start:
		return 0.0
	return smoothstep(_sunset_start, _sunset_end, value)


func _apply_visual_state(force_signal: bool) -> void:
	if _overlay == null:
		return
	_overlay.visible = _night_amount > 0.001
	_material.set_shader_parameter("night_amount", _night_amount)
	_material.set_shader_parameter("night_opacity", _night_overlay_opacity)
	_material.set_shader_parameter("cycle_time", _elapsed_time)
	if force_signal or absf(_night_amount - _last_emitted_amount) > 0.0001:
		_last_emitted_amount = _night_amount
		night_amount_changed.emit(_night_amount)


func toggle_manual_night() -> void:
	if _manual_mode:
		set_manual_night(not _manual_night)
	else:
		# 自动白天时第一次按 N 必定直达夜晚；自动夜晚时则切到白天便于对比。
		set_manual_night(_night_amount < 0.5)


func set_manual_night(enabled: bool) -> void:
	_manual_mode = true
	_manual_night = enabled
	_auto_resume_blend = false
	_target_night_amount = 1.0 if enabled else 0.0
	_sync_status(true)


func set_auto_mode() -> void:
	if not _manual_mode:
		return
	_manual_mode = false
	_auto_resume_blend = true
	_target_night_amount = _automatic_night_amount(_cycle_progress)
	_sync_status(true)


func snap_transition() -> void:
	_target_night_amount = (
		1.0 if _manual_night
		else 0.0
	) if _manual_mode else _automatic_night_amount(_cycle_progress)
	_night_amount = _target_night_amount
	_auto_resume_blend = false
	_apply_visual_state(true)
	_sync_status(true)


func set_cycle_progress(value: float, snap := false) -> void:
	_cycle_progress = fposmod(value, 1.0)
	if not _manual_mode:
		_target_night_amount = _automatic_night_amount(_cycle_progress)
		if snap:
			_night_amount = _target_night_amount
			_auto_resume_blend = false
			_apply_visual_state(true)
	_sync_status(true)


func _phase_name() -> String:
	if _manual_mode:
		return "夜晚" if _manual_night else "白天"
	if _cycle_progress < _sunrise_start or _cycle_progress >= _sunset_end:
		return "夜晚"
	if _cycle_progress < _sunrise_end:
		return "黎明"
	if _cycle_progress < _sunset_start:
		return "白天"
	return "黄昏"


func _sync_status(force := false) -> void:
	var next_status := get_status_text()
	if force or next_status != _last_status_text:
		_last_status_text = next_status
		status_changed.emit()


func get_status_text() -> String:
	return "%s（%s）" % [_phase_name(), "手动" if _manual_mode else "自动"]


func get_night_amount() -> float:
	return _night_amount


func get_cycle_progress() -> float:
	return _cycle_progress


func is_manual_mode() -> bool:
	return _manual_mode


func is_manual_night() -> bool:
	return _manual_mode and _manual_night
