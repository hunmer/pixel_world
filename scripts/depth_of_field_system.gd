extends Node

## 纯 2D 世界的移轴景深近似。只处理 layer 0 的世界画面；雨雪、昼夜、
## 天气氛围和 HUD 位于更高 CanvasLayer，因而继续保持清晰。

signal status_changed

const CONFIG_PATH := "res://config/depth_of_field.json"
const DEPTH_SHADER := preload("res://shaders/tilt_shift_dof.gdshader")
const EFFECT_LAYER := 2

var _enabled := false
var _focus_y := 0.5
var _target_focus_y := 0.5
var _focus_follow_speed := 12.0

var _effect_layer: CanvasLayer
var _back_buffer: BackBufferCopy
var _overlay: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	var parameters := _load_config()
	_enabled = bool(parameters["enabled_by_default"])
	_build_effect(parameters)
	_apply_enabled_state()
	set_process(true)


func _load_config() -> Dictionary:
	var values := {
		"enabled_by_default": false,
		"focus_half_height": 0.13,
		"focus_feather": 0.27,
		"max_blur_lod": 2.6,
		"far_strength": 0.78,
		"near_strength": 1.08,
		"vignette_strength": 0.05,
	}
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("景深配置不存在，使用默认值: " + CONFIG_PATH)
		return values
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("无法读取景深配置，使用默认值: " + CONFIG_PATH)
		return values
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK or not json.data is Dictionary:
		push_warning("景深配置 JSON 无效，使用默认值: " + CONFIG_PATH)
		return values
	var config: Dictionary = json.data
	if int(config.get("version", 0)) != 1:
		push_warning("景深配置版本无效，使用默认值")
		return values
	values["focus_half_height"] = clampf(float(config.get(
		"focus_half_height", values["focus_half_height"]
	)), 0.02, 0.4)
	values["focus_feather"] = clampf(float(config.get(
		"focus_feather", values["focus_feather"]
	)), 0.02, 0.5)
	values["max_blur_lod"] = clampf(float(config.get(
		"max_blur_lod", values["max_blur_lod"]
	)), 0.0, 5.0)
	values["far_strength"] = clampf(float(config.get(
		"far_strength", values["far_strength"]
	)), 0.0, 1.5)
	values["near_strength"] = clampf(float(config.get(
		"near_strength", values["near_strength"]
	)), 0.0, 1.5)
	values["vignette_strength"] = clampf(float(config.get(
		"vignette_strength", values["vignette_strength"]
	)), 0.0, 0.25)
	values["enabled_by_default"] = bool(config.get(
		"enabled_by_default", values["enabled_by_default"]
	))
	return values


func _build_effect(parameters: Dictionary) -> void:
	_effect_layer = CanvasLayer.new()
	_effect_layer.name = "DepthOfFieldLayer"
	_effect_layer.layer = EFFECT_LAYER
	_effect_layer.follow_viewport_enabled = false
	add_child(_effect_layer)

	_back_buffer = BackBufferCopy.new()
	_back_buffer.name = "WorldBackBuffer"
	_back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_effect_layer.add_child(_back_buffer)

	_overlay = ColorRect.new()
	_overlay.name = "TiltShiftOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Color.WHITE
	_material = ShaderMaterial.new()
	_material.shader = DEPTH_SHADER
	_material.set_shader_parameter("focus_half_height", parameters["focus_half_height"])
	_material.set_shader_parameter("focus_feather", parameters["focus_feather"])
	_material.set_shader_parameter("max_blur_lod", parameters["max_blur_lod"])
	_material.set_shader_parameter("far_strength", parameters["far_strength"])
	_material.set_shader_parameter("near_strength", parameters["near_strength"])
	_material.set_shader_parameter("vignette_strength", parameters["vignette_strength"])
	_overlay.material = _material
	_effect_layer.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-_focus_follow_speed * maxf(delta, 0.0))
	_focus_y = lerpf(_focus_y, _target_focus_y, blend)
	if _material != null:
		_material.set_shader_parameter("focus_y", _focus_y)


func set_focus_screen_position(screen_position: Vector2, viewport_size: Vector2) -> void:
	if viewport_size.y <= 0.0:
		return
	_target_focus_y = clampf(screen_position.y / viewport_size.y, 0.1, 0.9)


func set_enabled(enabled: bool) -> void:
	if enabled == _enabled:
		return
	_enabled = enabled
	_apply_enabled_state()
	status_changed.emit()


func toggle() -> void:
	set_enabled(not _enabled)


func _apply_enabled_state() -> void:
	if _effect_layer != null:
		_effect_layer.visible = _enabled


func is_enabled() -> bool:
	return _enabled


func get_status_text() -> String:
	return "开启" if _enabled else "关闭"
