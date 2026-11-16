## battle/battle_camera_kick.gd — 行动演出镜头踢击（ActionAnim 相位驱动的附加位移）
##
## 职责：
##   - ActionAnim strike/return 相位：按攻击焦点（攻守中点）计算短促推近偏移并 tween 过渡
##   - strike 相位同步触发出手音（经注入的 strike_sound_fn，保持在沉浸门控之后）
##   - 每帧把当前偏移写到取景通道：B1 → main.gd 的 set_battle_camera_kick（附加位移），
##     B2 → board.camera.presentation_offset（演出专用通道）
##   - 与沉浸演出互斥：沉浸镜头 engaged 时主动写零（B1）并停更（B2 由沉浸模块独占）
##   - 演出结束/场景退出：清零偏移并恢复
##
## 设计：从 scenes/battle.gd 抽出的 Node（_process/create_tween 需要）。订阅
## action_anim.phase_started / finished 由 battle.gd 接线；strike 出手音经
## strike_sound_fn 回交（BattleSfx.play_strike）。B1/B2 通道差异：b1_world 非空走
## set_battle_camera_kick，否则经 camera_fn 取 B2 演出相机写 presentation_offset。
##
## 公开 API（battle.gd 接线）：
##   setup(unit_sprites, immersive_camera, b1_world, camera_fn, strike_sound_fn)
##   on_phase_started(phase, event)  # 连 action_anim.phase_started
##   on_anim_finished()              # 连 action_anim.finished（与 battle.gd 的血条恢复并列）

class_name BattleCameraKick
extends Node

var unit_sprites: Dictionary
var immersive_camera: Node = null
## B1 模式：main.gd 引用（kick 经 set_battle_camera_kick 附加）；B2 传 null。
var b1_world: Node2D = null
## B2 模式：()->Camera3D，取 board.camera（battle.gd 的 _b2_camera）。
var camera_fn: Callable
## strike 相位出手音（battle.gd 注入 BattleSfx.play_strike；在沉浸门控之后调用）。
var strike_sound_fn: Callable

var _tween: Tween = null
var _offset := Vector3.ZERO
var _active := false


func setup(
	p_unit_sprites: Dictionary,
	p_immersive_camera: Node,
	p_b1_world: Node2D,
	p_camera_fn: Callable,
	p_strike_sound_fn: Callable
) -> void:
	unit_sprites = p_unit_sprites
	immersive_camera = p_immersive_camera
	b1_world = p_b1_world
	camera_fn = p_camera_fn
	strike_sound_fn = p_strike_sound_fn


## ActionAnim 仍负责缩放；位置推近走 main/IsoCamera 认可的附加位移，避免被每帧取景覆盖。
func _process(_delta: float) -> void:
	if _active:
		_apply()


func on_phase_started(phase: StringName, event: Dictionary) -> void:
	if is_instance_valid(immersive_camera) and immersive_camera.is_engaged():
		return
	if phase != &"strike" and phase != &"return":
		return
	var target_offset := Vector3.ZERO
	if phase == &"strike":
		strike_sound_fn.call(event)
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return
		var attacker_id := StringName(event.get(&"attacker_id", &""))
		var target_id := StringName(event.get(&"target_id", &""))
		var impacts: Array = event.get(&"impacts", [])
		if target_id == &"" and not impacts.is_empty():
			target_id = StringName((impacts[0] as Dictionary).get(&"target_id", &""))
		var attacker: UnitSprite3D = unit_sprites.get(attacker_id)
		var target: UnitSprite3D = unit_sprites.get(target_id)
		var focus := Vector3.ZERO
		if attacker != null and target != null:
			focus = (attacker.global_position + target.global_position) * 0.5
		elif attacker != null:
			focus = attacker.global_position
		elif target != null:
			focus = target.global_position
		else:
			return
		target_offset = (focus - camera.global_position) * 0.08
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_active = true
	_tween = create_tween()
	_tween.tween_property(
		self, "_offset", target_offset, 0.16 if phase == &"strike" else 0.14
	)


## finished 信号带 (event, skipped) 两参（与 battle.gd 的 _on_action_anim_finished 并列订阅）。
func on_anim_finished(_event: Dictionary, _skipped: bool) -> void:
	_reset()


func _apply() -> void:
	if is_instance_valid(immersive_camera) and immersive_camera.is_engaged():
		# B1 的 additive kick 与沉浸有效焦点互斥；B2 的 presentation_offset 由沉浸模块独占。
		if b1_world != null and is_instance_valid(b1_world):
			b1_world.set_battle_camera_kick(Vector3.ZERO)
		return
	if b1_world != null and is_instance_valid(b1_world):
		b1_world.set_battle_camera_kick(_offset)
	else:
		var camera: Camera3D = camera_fn.call()
		if camera != null:
			camera.presentation_offset = _offset


## 清零偏移并停更（演出结束 / 场景退出）。
func _reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_offset = Vector3.ZERO
	_apply()
	_active = false


func _exit_tree() -> void:
	_reset()
