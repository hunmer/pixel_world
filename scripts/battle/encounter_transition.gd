## battle/encounter_transition.gd — B1/B2 共用的遭遇转场屏幕层
## 负责径向扭曲、两次闪烁、暗化/覆盖与程序化音效；不读写战斗逻辑状态。
extends CanvasLayer

signal covered
signal finished

const EncounterWarpShader = preload("res://shaders/encounter_warp.gdshader")
const B1_DURATION := 0.64
const B2_REVEAL_DURATION := 0.58
const SCENE_COVER_DURATION := 0.30

var audio_hook: Callable = Callable()
var _overlay: ColorRect = null
var _material: ShaderMaterial = null
var _audio: AudioStreamPlayer = null
var _playing := false


func _ready() -> void:
	layer = 120
	_overlay = ColorRect.new()
	_overlay.name = "EncounterWarpOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = EncounterWarpShader
	_overlay.material = _material
	add_child(_overlay)
	_overlay.visible = false
	_audio = AudioStreamPlayer.new()
	_audio.name = "EncounterSting"
	_audio.volume_db = -13.0
	_audio.stream = _make_sting()
	add_child(_audio)


## B1 在原棋盘上暗化；B2 新场景从不透明覆盖层揭开。
func play(mode: StringName = &"b1", p_audio_hook: Callable = Callable()) -> void:
	if _playing or _overlay == null:
		return
	_playing = true
	if p_audio_hook.is_valid():
		audio_hook = p_audio_hook
	var b2_reveal := mode == &"b2_reveal"
	_reset_shader()
	_overlay.visible = true
	if b2_reveal:
		_material.set_shader_parameter("cover_alpha", 1.0)
		_material.set_shader_parameter("dim_amount", 0.55)
		_material.set_shader_parameter("warp_amount", 0.85)
	else:
		_play_sting()
	print("[EncounterTransition] start mode=%s" % String(mode))

	var tween := create_tween().set_parallel(true)
	if b2_reveal:
		tween.tween_property(
			_material, "shader_parameter/warp_amount", 0.0, B2_REVEAL_DURATION
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(
			_material, "shader_parameter/cover_alpha", 0.0, 0.46
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(
			_material, "shader_parameter/dim_amount", 0.0, B2_REVEAL_DURATION
		)
		tween.tween_property(
			_material, "shader_parameter/flash_phase", 1.0, B2_REVEAL_DURATION
		)
	else:
		tween.tween_property(
			_material, "shader_parameter/warp_amount", 1.0, 0.24
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(
			_material, "shader_parameter/dim_amount", 0.58, 0.24
		)
		tween.tween_property(
			_material, "shader_parameter/cover_alpha", 0.42, 0.24
		)
		tween.tween_property(
			_material, "shader_parameter/flash_phase", 1.0, B1_DURATION
		)
		tween.tween_property(
			_material, "shader_parameter/warp_amount", 0.0, 0.40
		).set_delay(0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(
			_material, "shader_parameter/dim_amount", 0.0, 0.38
		).set_delay(0.26)
		tween.tween_property(
			_material, "shader_parameter/cover_alpha", 0.0, 0.38
		).set_delay(0.26)
	await tween.finished
	_reset_shader()
	_overlay.visible = false
	_playing = false
	print("[EncounterTransition] finish mode=%s" % String(mode))
	finished.emit()


## B2 切场景前遮住旧世界；新 Battle 场景再用 play("b2_reveal") 揭开。
func cover_for_scene_change(p_audio_hook: Callable = Callable()) -> void:
	if _playing or _overlay == null:
		return
	_playing = true
	if p_audio_hook.is_valid():
		audio_hook = p_audio_hook
	_reset_shader()
	_overlay.visible = true
	_play_sting()
	print("[EncounterTransition] scene cover")
	var tween := create_tween().set_parallel(true)
	tween.tween_property(
		_material, "shader_parameter/warp_amount", 1.0, SCENE_COVER_DURATION
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(
		_material, "shader_parameter/dim_amount", 0.60, SCENE_COVER_DURATION
	)
	tween.tween_property(
		_material, "shader_parameter/cover_alpha", 1.0, SCENE_COVER_DURATION
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(
		_material, "shader_parameter/flash_phase", 1.0, SCENE_COVER_DURATION
	)
	await tween.finished
	_playing = false
	covered.emit()


func is_playing() -> bool:
	return _playing


func _reset_shader() -> void:
	_material.set_shader_parameter("warp_amount", 0.0)
	_material.set_shader_parameter("dim_amount", 0.0)
	_material.set_shader_parameter("cover_alpha", 0.0)
	_material.set_shader_parameter("flash_phase", 0.0)


func _play_sting() -> void:
	if audio_hook.is_valid():
		audio_hook.call(&"encounter")
	elif _audio != null:
		_audio.play()


## 固定波形生成短促遭遇提示音；不消耗 RNG，也不依赖外部音频文件。
func _make_sting() -> AudioStreamWAV:
	const MIX_RATE := 22050
	const SAMPLE_COUNT := 8372
	var bytes := PackedByteArray()
	bytes.resize(SAMPLE_COUNT * 2)
	for index in SAMPLE_COUNT:
		var t := float(index) / float(MIX_RATE)
		var envelope := sin(clampf(t / 0.38, 0.0, 1.0) * PI)
		envelope *= envelope
		var frequency := lerpf(180.0, 420.0, clampf(t / 0.38, 0.0, 1.0))
		var sample := (
			sin(t * frequency * TAU) * 0.62
			+ sin(t * frequency * 1.5 * TAU) * 0.24
		) * envelope * 0.55
		bytes.encode_s16(index * 2, clampi(roundi(sample * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
