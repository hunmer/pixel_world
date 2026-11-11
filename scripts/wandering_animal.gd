extends AnimatedSprite2D

## 独立于地块批绘制的移动动物。节点 Y 坐标只承担合成排序，offset 把动画画面补偿回真实脚点。

const IsometricDepthSort = preload("res://scripts/isometric_depth_sort.gd")
const SORT_BIAS := 0.75

var species_id := ""
var origin_cell := Vector2i.ZERO
var grid_cell := Vector2i.ZERO
var from_cell := Vector2i.ZERO
var target_cell := Vector2i.ZERO
var step_index := 0
var wait_remaining := 0.0
var moving := false
var fleeing := false
var behavior_mode: StringName = &"wander"
var idle_action: StringName = &"idle"
var move_action: StringName = &"idle"
var move_duration := 0.65
var sort_switch_progress := -1.0
var foot_offset_y := 0.0
var move_steps_min := 2
var move_steps_max := 4
var step_pause_min := 0.08
var step_pause_max := 0.16
var source_faces_right := false
var direction_persistence_weight := 0.0
var travel_direction := Vector2i.ZERO
var move_bout_active := false
var move_steps_remaining := 0
var bout_index := 0
var community_group_id := ""
var social_group_id := ""
var social_radius := 0.0

var _move_t := 1.0
var _move_duration := 0.8
var _from_visual := Vector2.ZERO
var _target_visual := Vector2.ZERO
var _visual_position := Vector2.ZERO
var _from_sort_y := 0.0
var _target_sort_y := 0.0
var _sort_y := 0.0
var _from_stand_level := 0.0
var _target_stand_level := 0.0


func configure(
	configured_species_id: String,
	spawn_cell: Vector2i,
	frames: SpriteFrames,
	visual_position: Vector2,
	sort_y: float,
	initial_wait: float,
	behavior: StringName,
	movement: Dictionary,
	configured_foot_offset_y := 0.0
) -> void:
	species_id = configured_species_id
	origin_cell = spawn_cell
	grid_cell = spawn_cell
	from_cell = spawn_cell
	target_cell = spawn_cell
	sprite_frames = frames
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = true
	wait_remaining = initial_wait
	behavior_mode = behavior
	idle_action = StringName(movement.get("idle_action", "idle"))
	move_action = StringName(movement.get("move_action", idle_action))
	move_duration = float(movement.get("duration", 0.65))
	sort_switch_progress = float(movement.get("sort_switch_progress", -1.0))
	var move_steps_value: Variant = movement.get("move_steps", [2, 4])
	if move_steps_value is Array and move_steps_value.size() == 2:
		move_steps_min = maxi(1, int(move_steps_value[0]))
		move_steps_max = maxi(move_steps_min, int(move_steps_value[1]))
	var step_pause_value: Variant = movement.get("step_pause_seconds", [0.08, 0.16])
	if step_pause_value is Array and step_pause_value.size() == 2:
		step_pause_min = maxf(0.0, float(step_pause_value[0]))
		step_pause_max = maxf(step_pause_min, float(step_pause_value[1]))
	source_faces_right = bool(movement.get("source_faces_right", false))
	direction_persistence_weight = maxf(
		0.0,
		float(movement.get("direction_persistence", 0.0))
	)
	foot_offset_y = configured_foot_offset_y
	_from_visual = visual_position
	_target_visual = visual_position
	_visual_position = visual_position
	_from_sort_y = sort_y
	_target_sort_y = sort_y
	_sort_y = sort_y
	if sprite_frames.has_animation(idle_action):
		play(idle_action)
	_apply_render_proxy()


func begin_move(
	next_cell: Vector2i,
	from_visual: Vector2,
	to_visual: Vector2,
	from_sort_y: float,
	to_sort_y: float,
	duration: float,
	playback_speed: float,
	from_stand_level: float,
	to_stand_level: float
) -> void:
	from_cell = grid_cell
	target_cell = next_cell
	_from_visual = from_visual
	_target_visual = to_visual
	_visual_position = from_visual
	_from_sort_y = from_sort_y
	_target_sort_y = to_sort_y
	_from_stand_level = from_stand_level
	_target_stand_level = to_stand_level
	_move_duration = maxf(duration, 0.001)
	_move_t = 0.0
	_sort_y = _movement_sort_y()
	moving = true
	speed_scale = maxf(playback_speed, 0.001)
	travel_direction = next_cell - from_cell
	if not is_equal_approx(to_visual.x, from_visual.x):
		var moving_screen_right := to_visual.x > from_visual.x
		# 物种明确声明原图朝右时，向左移动才镜像；未声明的旧素材继续
		# 沿用“原图朝左、向右镜像”的兼容行为。
		flip_h = moving_screen_right != source_faces_right
	if (
		sprite_frames.has_animation(move_action)
		and (animation != move_action or not is_playing())
	):
		play(move_action)
	_apply_render_proxy()


## 返回 true 表示本帧刚完成一次移动。
func tick(delta: float) -> bool:
	if not moving:
		wait_remaining = maxf(0.0, wait_remaining - delta)
		_apply_render_proxy()
		return false
	_move_t = minf(1.0, _move_t + delta / _move_duration)
	_visual_position = _from_visual.lerp(_target_visual, _move_t)
	# 动作切换点仍提供首选遮挡锚点，但支撑面高度约束优先，地板不会盖住动物。
	_sort_y = _movement_sort_y()
	_apply_render_proxy()
	if _move_t < 1.0:
		return false
	grid_cell = target_cell
	moving = false
	_apply_render_proxy()
	return true


func ready_to_move() -> bool:
	return not moving and wait_remaining <= 0.0


func start_move_bout(step_count: int) -> void:
	move_bout_active = true
	move_steps_remaining = maxi(1, step_count)
	travel_direction = Vector2i.ZERO
	bout_index += 1


func consume_move_bout_step() -> void:
	move_steps_remaining = maxi(0, move_steps_remaining - 1)


func finish_move_bout() -> void:
	move_bout_active = false
	move_steps_remaining = 0
	travel_direction = Vector2i.ZERO
	speed_scale = 1.0
	if (
		sprite_frames != null
		and sprite_frames.has_animation(idle_action)
		and (animation != idle_action or not is_playing())
	):
		play(idle_action)
	_apply_render_proxy()


func direction_persistence_score(
	next_cell: Vector2i,
	current_cell: Vector2i
) -> float:
	if travel_direction == Vector2i.ZERO:
		return 0.0
	return (
		direction_persistence_weight
		if next_cell - current_cell == travel_direction
		else 0.0
	)


func move_action_loops() -> bool:
	return (
		sprite_frames != null
		and sprite_frames.has_animation(move_action)
		and sprite_frames.get_animation_loop(move_action)
	)


## 地图视角变化时按原移动进度重投影，不重置行为、计时或确定性状态。
func reproject(
	new_from_visual: Vector2,
	new_target_visual: Vector2,
	new_from_sort_y: float,
	new_target_sort_y: float
) -> void:
	_from_visual = new_from_visual
	_target_visual = new_target_visual
	_visual_position = _from_visual.lerp(_target_visual, clampf(_move_t, 0.0, 1.0))
	rebase_sort(new_from_sort_y, new_target_sort_y)


func rebase_sort(new_from_sort_y: float, new_target_sort_y: float) -> void:
	_from_sort_y = new_from_sort_y
	_target_sort_y = new_target_sort_y
	_sort_y = _movement_sort_y()
	_apply_render_proxy()


func current_visual_position() -> Vector2:
	return _visual_position


func _movement_sort_y() -> float:
	return IsometricDepthSort.moving_support_sort_y(
		_from_sort_y,
		_target_sort_y,
		_from_stand_level,
		_target_stand_level,
		_move_t,
		SORT_BIAS,
		sort_switch_progress
	)


func _apply_render_proxy() -> void:
	position = Vector2(_visual_position.x, _sort_y)
	var frame_texture: Texture2D = null
	if sprite_frames != null and sprite_frames.has_animation(animation):
		var frame_count := sprite_frames.get_frame_count(animation)
		if frame_count > 0:
			frame_texture = sprite_frames.get_frame_texture(animation, mini(frame, frame_count - 1))
	var frame_height: float = float(frame_texture.get_height()) if frame_texture != null else 0.0
	# 动画图集允许在单帧底部留透明边距；把实体脚底重新落回地表脚点。
	offset = Vector2(
		0.0,
		_visual_position.y - _sort_y - frame_height * 0.5 + foot_offset_y
	)
