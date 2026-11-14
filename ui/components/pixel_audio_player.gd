## pixel_audio_player.gd — 音频容器：AudioStreamPlayer + 播放/暂停/停止 + 进度
##
## 组合控件（PanelContainer + VBox）：
##   - 节点 Player（AudioStreamPlayer）、Progress（HSlider，只读显示）、
##     PositionLabel（Label）与三个 PixelButton（PlayButton/PauseButton/StopButton）。
## stream / volume_db / autoplay 导出；空 stream 安全（播放请求直接忽略）。
## 编辑器 @tool 下不自动播放，也不响应按钮播放；运行态 _ready 只在 autoplay 时播。
@tool
class_name PixelAudioPlayer
extends PanelContainer

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const PixelButtonScript = preload("res://ui/components/pixel_button.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")

const LAYOUT_NAME: StringName = &"Layout"
const CONTROLS_NAME: StringName = &"Controls"
const PLAYER_NAME: StringName = &"Player"
const PROGRESS_NAME: StringName = &"Progress"
const POSITION_NAME: StringName = &"PositionLabel"
const PLAY_BUTTON_NAME: StringName = &"PlayButton"
const PAUSE_BUTTON_NAME: StringName = &"PauseButton"
const STOP_BUTTON_NAME: StringName = &"StopButton"

## 开始播放（含从暂停恢复）。
signal playback_started
## 进入暂停。
signal playback_paused
## 停止并回到开头。
signal playback_stopped

## 要播放的音频流；为空时播放/暂停/停止按钮安全无效。
@export var stream: AudioStream = null:
	set(value):
		stream = value
		_apply_stream()

## 音量（dB），直接写入 AudioStreamPlayer.volume_db；不改全局总线策略。
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var volume_db: float = 0.0:
	set(value):
		volume_db = value
		_apply_volume()

## 进入场景树后是否自动播放（编辑器内始终不播）。
@export var autoplay: bool = false

var _player: AudioStreamPlayer
var _progress: HSlider
var _position_label: Label
var _play_button: Button
var _pause_button: Button
var _stop_button: Button


func _init() -> void:
	_refresh()
	_ensure_ui()


func _ready() -> void:
	_refresh()
	_ensure_ui()
	_apply_stream()
	_apply_volume()
	if autoplay and _can_play():
		play_sound()


## 主题与结构刷新；幂等，不重复建节点。
func _refresh() -> void:
	if theme == null:
		theme = ComponentThemeScript.create()
	theme_type_variation = ComponentThemeScript.PANEL_VARIATION
	_ensure_ui()


## 首次调用时搭出播放器、进度、位置标签与三个按钮；之后直接返回。
func _ensure_ui() -> void:
	if has_node(NodePath(LAYOUT_NAME)):
		_player = get_node_or_null(NodePath(PLAYER_NAME)) as AudioStreamPlayer
		_progress = get_node_or_null(
			String(LAYOUT_NAME) + "/" + String(PROGRESS_NAME)
		) as HSlider
		_position_label = get_node_or_null(
			String(LAYOUT_NAME) + "/" + String(POSITION_NAME)
		) as Label
		return

	var layout := VBoxContainer.new()
	layout.name = LAYOUT_NAME
	layout.add_theme_constant_override("separation", 8)
	add_child(layout)

	_player = AudioStreamPlayer.new()
	_player.name = PLAYER_NAME
	_player.max_polyphony = 1
	add_child(_player)

	var controls := HBoxContainer.new()
	controls.name = CONTROLS_NAME
	controls.add_theme_constant_override("separation", 8)
	layout.add_child(controls)

	_play_button = _make_control_button("播放", PLAY_BUTTON_NAME)
	_pause_button = _make_control_button("暂停", PAUSE_BUTTON_NAME)
	_stop_button = _make_control_button("停止", STOP_BUTTON_NAME)
	controls.add_child(_play_button)
	controls.add_child(_pause_button)
	controls.add_child(_stop_button)

	_progress = HSlider.new()
	_progress.name = PROGRESS_NAME
	_progress.editable = false
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.value = 0.0
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(_progress)

	_position_label = Label.new()
	_position_label.name = POSITION_NAME
	_position_label.text = "0.0 / 0.0"
	_position_label.add_theme_font_size_override("font_size", 12)
	_position_label.add_theme_color_override("font_color", UIThemeScript.TEXT_DIM)
	layout.add_child(_position_label)

	_play_button.pressed.connect(play_sound)
	_pause_button.pressed.connect(pause_sound)
	_stop_button.pressed.connect(stop_sound)


## 建一个带稳定 name 的 PixelButton，复用语义按钮外观。
func _make_control_button(button_text: String, node_name: StringName) -> Button:
	var button: Button = PixelButtonScript.new()
	button.name = node_name
	button.text = button_text
	button.set("semantic", 1)
	button.custom_minimum_size = Vector2(0, 36)
	return button


func _apply_stream() -> void:
	if _player != null:
		_player.stream = stream


func _apply_volume() -> void:
	if _player != null:
		_player.volume_db = volume_db


## 播放：空流 / 未入树 / 编辑器内都安全忽略。
func play_sound() -> void:
	if not _can_play():
		return
	_player.stream_paused = false
	if not _player.playing:
		_player.play()
	_sync_progress()
	playback_started.emit()


## 暂停/恢复；未在播放时忽略。
func pause_sound() -> void:
	if not _can_play() or not _player.playing:
		return
	_player.stream_paused = not _player.stream_paused
	if _player.stream_paused:
		playback_paused.emit()
	else:
		playback_started.emit()


## 停止并复位进度显示。
func stop_sound() -> void:
	if _player == null:
		return
	_player.stop()
	_player.stream_paused = false
	_sync_progress()
	playback_stopped.emit()


## 空流、未入树或编辑器内不允许发声。
func _can_play() -> bool:
	return (
		stream != null
		and _player != null
		and is_inside_tree()
		and not Engine.is_editor_hint()
	)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _player == null:
		return
	_sync_progress()


## 进度条与位置标签显示当前播放位置；不反向 seek。
func _sync_progress() -> void:
	if _progress == null or _position_label == null:
		return
	var length: float = 0.0
	if stream != null:
		length = stream.get_length()
	var current: float = 0.0
	if _player != null and _player.playing:
		current = _player.get_playback_position()
	_progress.max_value = maxf(length, 0.001)
	_progress.value = minf(current, _progress.max_value)
	_position_label.text = "%0.1f / %0.1f" % [current, length]


## 原生播放器（供调用方接 finished 等信号）。
func get_player() -> AudioStreamPlayer:
	return _player


## 进度条（只读显示）。
func get_progress_slider() -> HSlider:
	return _progress
