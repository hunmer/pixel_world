## pixel_video_player.gd — 视频容器：VideoStreamPlayer + 播放/暂停/停止 + 进度
##
## 组合控件（PanelContainer + VBox）：
##   - 节点 Video（VideoStreamPlayer，等比拉伸填满区域）、Progress（HSlider，只读）、
##     PositionLabel（Label）与三个 PixelButton（PlayButton/PauseButton/StopButton）。
## stream 导出（VideoStream，如 .ogv）；空 stream 安全。编辑器 @tool 下不自动播放；
## 运行态 _ready 只在 autoplay 时播。空流不会以“空播放器”冒充可播内容。
@tool
class_name PixelVideoPlayer
extends PanelContainer

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const PixelButtonScript = preload("res://ui/components/pixel_button.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")

const LAYOUT_NAME: StringName = &"Layout"
const CONTROLS_NAME: StringName = &"Controls"
const VIDEO_NAME: StringName = &"Video"
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

## 要播放的视频流（VideoStream，项目自带 .ogv 样例）。
@export var stream: VideoStream = null:
	set(value):
		stream = value
		_apply_stream()

## 进入场景树后是否自动播放（编辑器内始终不播）。
@export var autoplay: bool = false

## 视频显示区最小尺寸。
@export var video_size: Vector2i = Vector2i(320, 180):
	set(value):
		video_size = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		_refresh_video_size()

var _video: VideoStreamPlayer
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
	_refresh_video_size()
	if autoplay and _can_play():
		play_video()


## 主题与结构刷新；幂等，不重复建节点。
func _refresh() -> void:
	if theme == null:
		theme = ComponentThemeScript.create()
	theme_type_variation = ComponentThemeScript.PANEL_VARIATION
	_ensure_ui()


## 首次调用时搭出视频、进度、位置标签与三个按钮；之后直接返回。
func _ensure_ui() -> void:
	if has_node(NodePath(LAYOUT_NAME)):
		_video = get_node_or_null(NodePath(VIDEO_NAME)) as VideoStreamPlayer
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

	_video = VideoStreamPlayer.new()
	_video.name = VIDEO_NAME
	_video.expand = true
	_video.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_video)

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

	_play_button.pressed.connect(play_video)
	_pause_button.pressed.connect(pause_video)
	_stop_button.pressed.connect(stop_video)


## 建一个带稳定 name 的 PixelButton，复用语义按钮外观。
func _make_control_button(button_text: String, node_name: StringName) -> Button:
	var button: Button = PixelButtonScript.new()
	button.name = node_name
	button.text = button_text
	button.set("semantic", 1)
	button.custom_minimum_size = Vector2(0, 36)
	return button


func _apply_stream() -> void:
	if _video != null:
		_video.stream = stream


func _refresh_video_size() -> void:
	if _video != null:
		_video.custom_minimum_size = Vector2(video_size)


## 播放：空流 / 未入树 / 编辑器内都安全忽略。
func play_video() -> void:
	if not _can_play():
		return
	_video.paused = false
	if not _video.is_playing():
		_video.play()
	_sync_progress()
	playback_started.emit()


## 暂停/恢复；未在播放时忽略。
func pause_video() -> void:
	if not _can_play() or not _video.is_playing():
		return
	_video.paused = not _video.paused
	if _video.paused:
		playback_paused.emit()
	else:
		playback_started.emit()


## 停止并复位进度显示。
func stop_video() -> void:
	if _video == null:
		return
	_video.stop()
	_sync_progress()
	playback_stopped.emit()


## 空流、未入树或编辑器内不允许播放。
func _can_play() -> bool:
	return (
		stream != null
		and _video != null
		and is_inside_tree()
		and not Engine.is_editor_hint()
	)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _video == null:
		return
	_sync_progress()


## 进度条与位置标签显示当前播放位置；不反向 seek。
func _sync_progress() -> void:
	if _progress == null or _position_label == null:
		return
	var length: float = 0.0
	if _video != null:
		length = _video.get_stream_length()
	var current: float = 0.0
	if _video != null and _video.is_playing():
		current = _video.stream_position
	_progress.max_value = maxf(length, 0.001)
	_progress.value = minf(current, _progress.max_value)
	_position_label.text = "%0.1f / %0.1f" % [current, length]


## 原生视频播放器（供调用方接 finished 等信号）。
func get_video_player() -> VideoStreamPlayer:
	return _video


## 进度条（只读显示）。
func get_progress_slider() -> HSlider:
	return _progress
