## battle/action_anim.gd — AttackEvent 的只读打击演出回放器。
##
## 集成：add_child 后 setup(unit_sprites, camera, float_text_handler)，再 await play(event, speed, skipped)。
## float_text_handler 签名：(unit_id: StringName, text: String, color: Color, font_size: int)。
## 演出只改 UnitSprite3D 的显示位置/缩放/portrait.modulate，结束时全部恢复；绝不写 unit.position。
class_name ActionAnim
extends Node

signal phase_started(phase: StringName, event: Dictionary)
signal impact_presented(impact: Dictionary)
signal float_text_requested(unit_id: StringName, text: String, color: Color, font_size: int)
signal flash_requested(color: Color, duration: float)
signal finished(event: Dictionary, skipped: bool)

const AttackEventScript = preload("res://scripts/systems/attack_event.gd")
const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")

const PHASE_WINDUP := &"windup"
const PHASE_STEP := &"step"
const PHASE_STRIKE := &"strike"
const PHASE_HIT := &"hit"
const PHASE_HITSTOP := &"hitstop"
const PHASE_RETURN := &"return"
const PHASE_SKIPPED := &"skipped"

const WINDUP_NORMAL := 0.15
const WINDUP_SKILL := 0.20
const STEP_NORMAL := 0.14
const STEP_SKILL := 0.18
const REACTION_NORMAL := 0.20
const REACTION_SKILL := 0.28
const RETURN_NORMAL := 0.16
const RETURN_SKILL := 0.20
const WHITE_FLASH_SECONDS := 0.08
const FLOAT_FONT_SIZE := 18
const CRIT_FONT_SIZE := 24
const CAMERA_ZOOM_SCALE := 1.12
const CAMERA_EFFECTIVE_ZOOM_SCALE := 1.24
const MAX_ANIM_SPEED := 8.0

const STRIKE_SECONDS := {
	&"slash": 0.20,
	&"projectile": 0.32,
	&"burst": 0.36,
	&"beam": 0.30,
}
const ELEMENT_COLORS := {
	&"physical": Color.WHITE,
	&"fire": Color(1.0, 0.38, 0.16),
	&"ice": Color(0.35, 0.82, 1.0),
	&"holy": Color(1.0, 0.91, 0.46),
	&"dark": Color(0.72, 0.38, 1.0),
	&"wind": Color(0.42, 1.0, 0.68),
	&"arrow": Color(0.94, 0.86, 0.64),
}
const ELEMENT_LABELS := {
	&"physical": "",
	&"fire": "火",
	&"ice": "冰",
	&"holy": "圣",
	&"dark": "暗",
	&"wind": "风",
}

var _unit_sprites: Dictionary = {}
var _camera: Camera3D = null
var _float_text_handler: Callable = Callable()
var _layer: CanvasLayer = null
var _effect_root: Control = null
var _border_root: Control = null

var _playing := false
var _skip_requested := false
var _skipped := false
var _speed := 1.0
var _event: Dictionary = {}
var _active_tween: Tween = null
var _effect_tweens: Array = []
var _visual_states: Dictionary = {}
var _camera_state: Dictionary = {}


func _ready() -> void:
	_build_effect_layer()


## unit_sprites 是 battle.gd 持有的 { unitId -> UnitSprite3D } 原 Dictionary（引用共享）。
func setup(
	p_unit_sprites: Dictionary,
	p_camera: Camera3D = null,
	p_float_text_handler: Callable = Callable()
) -> void:
	_unit_sprites = p_unit_sprites
	_camera = p_camera
	_float_text_handler = p_float_text_handler


func set_camera(p_camera: Camera3D) -> void:
	_camera = p_camera


func set_float_text_handler(handler: Callable) -> void:
	_float_text_handler = handler


func is_playing() -> bool:
	return _playing


## 返回不加速、不跳过时的总时间轴长度；用于预算契约与托管排队。
func duration_seconds(event: Dictionary) -> float:
	var skill := StringName(event.get(&"kind", &"normal")) == &"skill"
	var template := template_for(event)
	return (
		(WINDUP_SKILL if skill else WINDUP_NORMAL)
		+ (STEP_SKILL if skill else STEP_NORMAL)
		+ float(STRIKE_SECONDS.get(template, STRIKE_SECONDS[&"slash"]))
		+ (REACTION_SKILL if skill else REACTION_NORMAL)
		+ (RETURN_SKILL if skill else RETURN_NORMAL)
		+ float(event.get(&"hitstop", 0.0))
	)


static func template_for(event: Dictionary) -> StringName:
	var spec := String(event.get(&"anim", &"slash"))
	var parts := spec.split(":", false, 1)
	var template := StringName(parts[0] if not parts.is_empty() else &"slash")
	return template if STRIKE_SECONDS.has(template) else &"slash"


## 结算完成后调用。anim_speed 只压缩显示时间；skipped=true 时同步完成，不等待任何帧。
func play(event: Dictionary, anim_speed: float = 1.0, skipped: bool = false) -> void:
	while _playing:
		await finished
	if not is_inside_tree():
		push_error("ActionAnim.play: 节点尚未加入 SceneTree")
		return
	_event = event
	_speed = clampf(anim_speed, 0.1, MAX_ANIM_SPEED)
	_skip_requested = skipped
	_skipped = skipped
	_playing = true
	_visual_states.clear()
	_camera_state.clear()
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
	_capture_visual_states(event)
	if skipped:
		_finish_play()
		return

	var attacker_id := StringName(event.get(&"attacker_id", &""))
	var target_id := AttackEventScript.primary_target_id(event)
	var attacker := _sprite(attacker_id)
	var target := _sprite(target_id)
	var skill := StringName(event.get(&"kind", &"normal")) == &"skill"
	var strike_seconds := float(STRIKE_SECONDS.get(template_for(event), STRIKE_SECONDS[&"slash"]))

	phase_started.emit(PHASE_WINDUP, event)
	if attacker != null:
		var start_scale: Vector3 = _visual_states[attacker_id][&"scale"]
		var windup_scale := start_scale * Vector3(0.96, 1.08, 0.96)
		await _main_property(attacker, "scale", windup_scale, WINDUP_SKILL if skill else WINDUP_NORMAL)
	else:
		await _wait(WINDUP_SKILL if skill else WINDUP_NORMAL)
	if _skip_requested:
		_finish_play()
		return

	phase_started.emit(PHASE_STEP, event)
	if target != null:
		_spawn_highlight(target_id, strike_seconds + STEP_NORMAL)
	if attacker != null and target != null and attacker != target:
		var start: Vector3 = _visual_states[attacker_id][&"position"]
		var direction := (target.global_position - start)
		direction.y = 0.0
		direction = direction.normalized()
		var step_position := start + direction * (IsoProjection.GRID_STEP * 0.5)
		await _main_property(attacker, "global_position", step_position, STEP_SKILL if skill else STEP_NORMAL)
	else:
		await _wait(STEP_SKILL if skill else STEP_NORMAL)
	if _skip_requested:
		_finish_play()
		return

	phase_started.emit(PHASE_STRIKE, event)
	_spawn_template(event, attacker_id, target_id)
	_camera_push(attacker, target, strike_seconds, bool(event.get(&"weakness", false)))
	await _wait(strike_seconds)
	if _skip_requested:
		_finish_play()
		return

	phase_started.emit(PHASE_HIT, event)
	_present_impacts(event)
	if float(event.get(&"hitstop", 0.0)) > 0.0:
		phase_started.emit(PHASE_HITSTOP, event)
		await _wait(float(event.get(&"hitstop", 0.0)))
	await _wait(REACTION_SKILL if skill else REACTION_NORMAL)
	if _skip_requested:
		_finish_play()
		return

	phase_started.emit(PHASE_RETURN, event)
	_camera_restore(RETURN_SKILL if skill else RETURN_NORMAL)
	if attacker != null:
		var start: Vector3 = _visual_states[attacker_id][&"position"]
		var start_scale: Vector3 = _visual_states[attacker_id][&"scale"]
		var tween := _new_main_tween()
		tween.tween_property(attacker, "global_position", start, RETURN_SKILL if skill else RETURN_NORMAL)
		tween.parallel().tween_property(attacker, "scale", start_scale, RETURN_SKILL if skill else RETURN_NORMAL)
		await tween.finished
		if _active_tween == tween:
			_active_tween = null
	else:
		await _wait(RETURN_SKILL if skill else RETURN_NORMAL)
	_finish_play()


## 立即完成当前演出；强制推进活动 Tween，保证 await play() 一定返回。
func skip() -> void:
	if not _playing:
		return
	_skip_requested = true
	_skipped = true
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.custom_step(10000.0)
		# custom_step 在极端暂停状态下可能不发 finished；下一帧仍由 play 的恢复分支兜底。
		_restore_visuals()
		_restore_camera_immediate()


func _build_effect_layer() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "ActionAnimLayer"
	_layer.layer = 2
	add_child(_layer)
	_effect_root = Control.new()
	_effect_root.name = "Effects"
	_effect_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_effect_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_effect_root)
	_border_root = Control.new()
	_border_root.name = "EffectiveFlash"
	_border_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_border_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_border_root)
	var viewport_size := get_viewport().get_visible_rect().size
	var thickness := 10.0
	var rects := [
		[Vector2.ZERO, Vector2(viewport_size.x, thickness)],
		[Vector2(0.0, viewport_size.y - thickness), Vector2(viewport_size.x, thickness)],
		[Vector2.ZERO, Vector2(thickness, viewport_size.y)],
		[Vector2(viewport_size.x - thickness, 0.0), Vector2(thickness, viewport_size.y)],
	]
	for raw_rect in rects:
		var rect := ColorRect.new()
		rect.position = raw_rect[0]
		rect.size = raw_rect[1]
		rect.color = Color.WHITE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_border_root.add_child(rect)
	_border_root.visible = false


func _capture_visual_states(event: Dictionary) -> void:
	var ids: Array = [StringName(event.get(&"attacker_id", &""))]
	for raw_impact in event.get(&"impacts", []):
		var impact: Dictionary = raw_impact
		ids.append(StringName(impact.get(&"source_id", &"")))
		ids.append(StringName(impact.get(&"target_id", &"")))
	for unit_id in ids:
		if _visual_states.has(unit_id):
			continue
		var sprite := _sprite(unit_id)
		if sprite == null:
			continue
		_visual_states[unit_id] = {
			&"sprite": sprite,
			&"position": sprite.global_position,
			&"scale": sprite.scale,
			&"modulate": sprite.portrait.modulate if sprite.portrait != null else Color.WHITE,
		}


func _sprite(unit_id: StringName) -> UnitSprite3D:
	var sprite: UnitSprite3D = _unit_sprites.get(unit_id)
	return sprite if is_instance_valid(sprite) else null


func _new_main_tween() -> Tween:
	var tween := create_tween()
	tween.set_speed_scale(_speed)
	_active_tween = tween
	return tween


func _main_property(object: Object, property: NodePath, value: Variant, seconds: float) -> void:
	if _skip_requested:
		return
	var tween := _new_main_tween()
	tween.tween_property(object, property, value, seconds)
	await tween.finished
	if _active_tween == tween:
		_active_tween = null


func _wait(seconds: float) -> void:
	if _skip_requested or seconds <= 0.0:
		return
	var tween := _new_main_tween()
	tween.tween_interval(seconds)
	await tween.finished
	if _active_tween == tween:
		_active_tween = null


func _effect_tween() -> Tween:
	var tween := create_tween()
	tween.set_speed_scale(_speed)
	_effect_tweens.append(tween)
	tween.finished.connect(func(): _effect_tweens.erase(tween))
	return tween


func _spawn_template(event: Dictionary, attacker_id: StringName, target_id: StringName) -> void:
	var spec := String(event.get(&"anim", &"slash"))
	var parts := spec.split(":", false, 1)
	var template := StringName(parts[0] if not parts.is_empty() else &"slash")
	var variant := StringName(parts[1] if parts.size() > 1 else event.get(&"element", &"physical"))
	var color: Color = ELEMENT_COLORS.get(variant, ELEMENT_COLORS.get(event.get(&"element", &"physical"), Color.WHITE))
	var from := _screen_position(attacker_id)
	var to := _screen_position(target_id)
	var seconds := float(STRIKE_SECONDS.get(template, STRIKE_SECONDS[&"slash"]))
	match template:
		&"projectile":
			_spawn_projectile(from, to, color, seconds)
		&"burst":
			_spawn_burst(to, color, seconds)
		&"beam":
			_spawn_beam(from, to, color, seconds)
		_:
			_spawn_slash(to, color, seconds)


func _spawn_slash(at: Vector2, color: Color, seconds: float) -> void:
	var line := Line2D.new()
	line.width = 6.0
	line.default_color = color
	line.antialiased = true
	for i in range(9):
		var angle := lerpf(-PI * 0.75, PI * 0.25, float(i) / 8.0)
		line.add_point(at + Vector2(cos(angle), sin(angle)) * 34.0)
	_add_effect(line)
	var tween := _effect_tween()
	tween.tween_property(line, "modulate:a", 0.0, seconds)


func _spawn_projectile(from: Vector2, to: Vector2, color: Color, seconds: float) -> void:
	var projectile := Polygon2D.new()
	projectile.polygon = PackedVector2Array([Vector2(14, 0), Vector2(-8, -5), Vector2(-4, 0), Vector2(-8, 5)])
	projectile.color = color
	projectile.position = from
	projectile.rotation = (to - from).angle()
	_add_effect(projectile)
	var tween := _effect_tween()
	tween.tween_property(projectile, "position", to, seconds * 0.78).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(projectile, "modulate:a", 0.0, seconds * 0.22)


func _spawn_burst(at: Vector2, color: Color, seconds: float) -> void:
	var root := Node2D.new()
	root.position = at
	_add_effect(root)
	for ring_index in range(2):
		var ring := Line2D.new()
		ring.width = 5.0 - ring_index * 2.0
		ring.default_color = color
		ring.antialiased = true
		ring.closed = true
		for i in range(16):
			var angle := TAU * float(i) / 16.0
			ring.add_point(Vector2(cos(angle), sin(angle)) * (24.0 + ring_index * 12.0))
		root.add_child(ring)
	root.scale = Vector2.ONE * 0.35
	var tween := _effect_tween()
	tween.tween_property(root, "scale", Vector2.ONE * 1.35, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(root, "modulate:a", 0.0, seconds)


func _spawn_beam(from: Vector2, to: Vector2, color: Color, seconds: float) -> void:
	var beam := Line2D.new()
	beam.width = 12.0
	beam.default_color = color
	beam.antialiased = true
	beam.add_point(from)
	beam.add_point(to)
	_add_effect(beam)
	var core := Line2D.new()
	core.width = 3.0
	core.default_color = Color.WHITE
	core.add_point(from)
	core.add_point(to)
	_add_effect(core)
	var tween := _effect_tween()
	tween.tween_property(beam, "width", 2.0, seconds)
	tween.parallel().tween_property(beam, "modulate:a", 0.0, seconds)
	tween.parallel().tween_property(core, "modulate:a", 0.0, seconds)


func _spawn_highlight(unit_id: StringName, seconds: float) -> void:
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = Color(1.0, 0.86, 0.30, 0.9)
	ring.antialiased = true
	ring.closed = true
	var at := _screen_position(unit_id)
	for i in range(4):
		var angle := PI * 0.25 + float(i) * PI * 0.5
		ring.add_point(at + Vector2(cos(angle), sin(angle)) * 30.0)
	_add_effect(ring)
	var tween := _effect_tween()
	tween.tween_property(ring, "modulate:a", 0.25, maxf(0.05, seconds * 0.5))
	tween.tween_property(ring, "modulate:a", 0.0, maxf(0.05, seconds * 0.5))


func _present_impacts(event: Dictionary) -> void:
	for raw_impact in event.get(&"impacts", []):
		var impact: Dictionary = raw_impact
		_present_float_text(impact)
		_react_to_impact(impact)
		impact_presented.emit(impact)


func _present_float_text(impact: Dictionary) -> void:
	var unit_id := StringName(impact.get(&"target_id", &""))
	var text := ""
	var color := Color.WHITE
	var font_size := FLOAT_FONT_SIZE
	if not bool(impact.get(&"hit", true)):
		text = "MISS"
		color = Color(0.98, 0.74, 0.14)
	elif int(impact.get(&"healing", 0)) > 0:
		text = "+%d" % int(impact[&"healing"])
		color = Color(0.29, 0.87, 0.50)
	elif int(impact.get(&"damage", 0)) > 0:
		text = "-%d" % int(impact[&"damage"])
		var element := StringName(impact.get(&"element", &"physical"))
		var label := String(ELEMENT_LABELS.get(element, ""))
		if not label.is_empty():
			text += " " + label
		color = ELEMENT_COLORS.get(element, Color.WHITE)
		if bool(impact.get(&"critical", false)):
			font_size = CRIT_FONT_SIZE
			text = "暴击 " + text
		if bool(impact.get(&"effective", false)):
			text += " 克制"
	elif not (impact.get(&"statuses", []) as Array).is_empty():
		var status: Dictionary = (impact[&"statuses"] as Array)[0]
		text = "%s%+d" % [String(status.get(&"stat", &"")), int(status.get(&"value", 0))]
		color = Color(0.98, 0.84, 0.30)
	else:
		return
	float_text_requested.emit(unit_id, text, color, font_size)
	if _float_text_handler.is_valid():
		_float_text_handler.call(unit_id, text, color, font_size)
	else:
		_spawn_float_text(unit_id, text, color, font_size)


## 未接场景飘字 handler 时使用内置弹跳标签；接入 handler 后由场景完全接管。
func _spawn_float_text(unit_id: StringName, text: String, color: Color, font_size: int) -> void:
	if _effect_root == null:
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = _screen_position(unit_id) + Vector2(-24.0, -72.0)
	label.scale = Vector2.ONE * 0.65
	_add_effect(label)
	var tween := _effect_tween()
	tween.tween_property(label, "scale", Vector2.ONE * 1.15, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE, 0.06)
	tween.parallel().tween_property(label, "position:y", label.position.y - 30.0, 0.22)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.22)


func _react_to_impact(impact: Dictionary) -> void:
	if not bool(impact.get(&"hit", false)) or int(impact.get(&"damage", 0)) <= 0:
		return
	var unit_id := StringName(impact.get(&"target_id", &""))
	var sprite := _sprite(unit_id)
	if sprite == null:
		return
	var state: Dictionary = _visual_states.get(unit_id, {})
	var original_modulate: Color = state.get(&"modulate", Color.WHITE)
	if sprite.portrait != null:
		sprite.portrait.modulate = Color(2.0, 2.0, 2.0, original_modulate.a)
	var start := sprite.global_position
	var direction: Vector3 = _impact_world_direction(impact)
	var weakness := bool(impact.get(&"weakness", false))
	var tween := _effect_tween()
	if weakness:
		tween.tween_interval(AttackEventScript.WEAKNESS_HITSTOP_SECONDS)
		_spawn_shield_crack(unit_id)
		_flash_border()
	tween.tween_property(sprite, "global_position", start - direction * 0.10, 0.07)
	tween.tween_property(sprite, "global_position", start + direction * 0.16, 0.11)
	if sprite.portrait != null:
		tween.parallel().tween_property(sprite.portrait, "modulate", original_modulate, WHITE_FLASH_SECONDS)


func _impact_world_direction(impact: Dictionary) -> Vector3:
	var source := _sprite(StringName(impact.get(&"source_id", &"")))
	var target := _sprite(StringName(impact.get(&"target_id", &"")))
	if source != null and target != null:
		var direction := target.global_position - source.global_position
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			return direction.normalized()
	var cell: Vector2i = impact.get(&"knockback", Vector2i.ZERO)
	return Vector3(cell.x, 0.0, cell.y).normalized()


func _spawn_shield_crack(unit_id: StringName) -> void:
	var crack := Line2D.new()
	crack.width = 3.0
	crack.default_color = Color(1.0, 0.94, 0.62)
	crack.antialiased = true
	var at := _screen_position(unit_id)
	var points := PackedVector2Array([
		at + Vector2(-18, -28), at + Vector2(-5, -9), at + Vector2(-13, 4),
		at + Vector2(4, 12), at + Vector2(-2, 30), at + Vector2(18, 8),
	])
	crack.points = points
	_add_effect(crack)
	var tween := _effect_tween()
	tween.tween_interval(AttackEventScript.WEAKNESS_HITSTOP_SECONDS)
	tween.tween_property(crack, "modulate:a", 0.0, 0.20)


func _flash_border() -> void:
	flash_requested.emit(Color.WHITE, 0.16)
	if _border_root == null:
		return
	_border_root.visible = true
	_border_root.modulate.a = 0.85
	var tween := _effect_tween()
	tween.tween_interval(AttackEventScript.WEAKNESS_HITSTOP_SECONDS)
	tween.tween_property(_border_root, "modulate:a", 0.0, 0.16)


## 只负责正交 size 推近；位置由 battle.gd 通过 main/IsoCamera 的 additive 通道统一驱动。
## 普通 Camera3D 与 null 相机同样安全：没有位置写入，也没有伪 camera_kick 信号。
func _camera_push(_attacker: UnitSprite3D, _target: UnitSprite3D, seconds: float, effective: bool) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var zoom_scale := CAMERA_EFFECTIVE_ZOOM_SCALE if effective else CAMERA_ZOOM_SCALE
	if _camera_state.is_empty():
		_camera_state = {
			&"camera": _camera,
			&"size": _camera.size,
		}
	var tween := _effect_tween()
	tween.tween_property(_camera, "size", _camera.size / zoom_scale, seconds)


func _camera_restore(seconds: float) -> void:
	if _camera_state.is_empty():
		return
	var camera: Camera3D = _camera_state[&"camera"]
	if not is_instance_valid(camera):
		return
	var tween := _effect_tween()
	tween.tween_property(camera, "size", float(_camera_state[&"size"]), seconds)


func _screen_position(unit_id: StringName) -> Vector2:
	var sprite := _sprite(unit_id)
	if sprite == null:
		return get_viewport().get_visible_rect().size * 0.5
	var point := sprite.global_position + Vector3(0.0, 0.8, 0.0)
	if _camera != null and is_instance_valid(_camera) and not _camera.is_position_behind(point):
		return _camera.unproject_position(point)
	return get_viewport().get_visible_rect().size * 0.5


func _add_effect(node: Node) -> void:
	if _effect_root != null:
		_effect_root.add_child(node)


func _finish_play() -> void:
	if not _playing:
		return
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null
	_clear_effects()
	_restore_visuals()
	_restore_camera_immediate()
	_playing = false
	finished.emit(_event, _skipped)


func _clear_effects() -> void:
	for raw_tween in _effect_tweens:
		var tween: Tween = raw_tween
		if tween != null and tween.is_valid():
			tween.kill()
	_effect_tweens.clear()
	if _effect_root != null:
		for child in _effect_root.get_children():
			child.queue_free()
	if _border_root != null:
		_border_root.visible = false
		_border_root.modulate.a = 1.0


func _restore_visuals() -> void:
	for raw_state in _visual_states.values():
		var state: Dictionary = raw_state
		var sprite: UnitSprite3D = state.get(&"sprite")
		if not is_instance_valid(sprite):
			continue
		sprite.global_position = state[&"position"]
		sprite.scale = state[&"scale"]
		if sprite.portrait != null:
			sprite.portrait.modulate = state[&"modulate"]


func _restore_camera_immediate() -> void:
	if _camera_state.is_empty():
		return
	var camera: Camera3D = _camera_state.get(&"camera")
	if is_instance_valid(camera):
		camera.size = float(_camera_state[&"size"])
	_camera_state.clear()
