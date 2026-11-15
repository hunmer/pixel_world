## animal_runtime.gd — 动物个体的生成 / 外观 / 逐帧行为（簇9：从 main.gd 原样迁出）
## 确定性盐（9000+step*97、8200+step*53、8300+bout*67、8400+step*71）逐字保留。
## 宿主状态经 configure 注入（字典按引用同步）；stream_center/stream_extent/player_cell
## 随每次入口调用刷新（与原 main 字段语义一致）。
class_name AnimalRuntime
extends RefCounted

const WanderingAnimalScript = preload("res://scripts/wandering_animal.gd")
const UnderwaterAnimalShader = preload("res://shaders/underwater_animal.gdshader")

const ANIMAL_WAIT_MIN := 0.6
const ANIMAL_WAIT_SPAN := 2.0
const ANIMAL_FLEE_WAIT := 0.08
const ANIMAL_BLOCKED_RETRY := 0.25
const ANIMAL_LEAVE_WATER_BONUS := 10000.0
const ANIMAL_GROUP_COHESION_WEIGHT := 6.0

var _host: Node2D
var _animals: Dictionary
var _cell_states: Dictionary
var _animal_species: Dictionary
var _animal_behavior_stacks: Dictionary
var _animal_behavior_registry
var _animal_groups
var _water_max: int
var _water_surface_level: int
var _water_color: Color
var _animal_sort_bias: float
var _animal_directions: Array

var _cell_rand: Callable
var _quantize: Callable
var _cell_context_for_query: Callable
var _water_clearance: Callable
var _column_sort_y: Callable
var _cell_feet_pos: Callable
var _grid_to_screen: Callable

var _stream_center := Vector2i.ZERO
var _stream_extent := 32
var _player_cell := Vector2i.ZERO
var _animal_behavior_tag_scan_radius := 1

var _animal_frames_cache := {}  ## animal species id -> SpriteFrames
var _underwater_animal_material_cache := {}  ## water depth -> shared foreground-water material
var _animal_behavior_distance_cache := {}


func configure(
	host: Node2D,
	animals: Dictionary,
	cell_states: Dictionary,
	animal_species: Dictionary,
	animal_behavior_stacks: Dictionary,
	animal_behavior_registry,
	animal_groups,
	water_max: int,
	water_surface_level: int,
	water_color: Color,
	animal_sort_bias: float,
	animal_directions: Array,
	cell_rand: Callable,
	quantize: Callable,
	cell_context_for_query: Callable,
	water_clearance: Callable,
	column_sort_y: Callable,
	cell_feet_pos: Callable,
	grid_to_screen: Callable
) -> void:
	_host = host
	_animals = animals
	_cell_states = cell_states
	_animal_species = animal_species
	_animal_behavior_stacks = animal_behavior_stacks
	_animal_behavior_registry = animal_behavior_registry
	_animal_groups = animal_groups
	_water_max = water_max
	_water_surface_level = water_surface_level
	_water_color = water_color
	_animal_sort_bias = animal_sort_bias
	_animal_directions = animal_directions
	_cell_rand = cell_rand
	_quantize = quantize
	_cell_context_for_query = cell_context_for_query
	_water_clearance = water_clearance
	_column_sort_y = column_sort_y
	_cell_feet_pos = cell_feet_pos
	_grid_to_screen = grid_to_screen


## 由宿主薄委托在入口刷新当前流式帧与编译期扫描半径。
func sync_frame(
	stream_center: Vector2i, stream_extent_value: int, player_cell: Vector2i,
	tag_scan_radius: int
) -> void:
	_stream_center = stream_center
	_stream_extent = stream_extent_value
	_player_cell = player_cell
	_animal_behavior_tag_scan_radius = tag_scan_radius


func spawn_animal(
	species_id: String, cell: Vector2i, _level: int
) -> AnimatedSprite3D:
	if _animals.has(cell) or animal_cell_reserved(cell):
		return null
	if not _animal_species.has(species_id):
		push_error("生态配置引用了未知动物: " + species_id)
		return null
	var species: Dictionary = _animal_species[species_id]
	var terrain_level: int = _quantize.call(cell.x, cell.y)
	var surface_id := &"water" if terrain_level <= _water_max else &"land"
	if not animal_species_allows_surface(species, surface_id):
		return null
	var spawn_stack_value: Variant = _animal_behavior_stacks.get(species_id, [])
	var spawn_stack: Array[Dictionary] = []
	if spawn_stack_value is Array:
		for behavior_value in spawn_stack_value:
			if behavior_value is Dictionary:
				spawn_stack.append((behavior_value as Dictionary).duplicate(true))
	var spawn_cell_data := animal_behavior_cell_data(cell)
	var spawn_decision: Dictionary = _animal_behavior_registry.evaluate_stack(
		spawn_stack,
		spawn_cell_data,
		{
			"current": spawn_cell_data,
			"player_cell": _player_cell,
			"distance_to_tag": Callable(self, "animal_behavior_distance_to_tag"),
		}
	)
	if not bool(spawn_decision.get("allowed", false)):
		return null
	var animal: AnimatedSprite3D = WanderingAnimalScript.new()
	_animals[cell] = animal
	_host.add_child(animal)
	animal.configure(
		species_id,
		cell,
		animal_frames_for(species_id),
		_cell_feet_pos.call(cell),
		_column_sort_y.call(cell) + _animal_sort_bias,
		animal_wait(cell, 0),
		StringName(species.get("behavior", &"wander")),
		species.get("movement", {}),
		float(species.get("foot_offset_y", 0.0)),
		_stand_level(terrain_level)
	)
	var metadata: Dictionary = species.get("metadata", {})
	if bool(metadata.get("aquatic", false)):
		# 地块批绘制器会把湖底和水面合为一个 CanvasItem，移动鱼无法真正插入
		# 两次 draw call 之间；水下材质在鱼身上重建前景水层，形成被透明水体
		# 遮住的感觉，同时不额外创建成千上万个水面节点。
		animal.material = underwater_animal_material_for_depth(
			_water_surface_level - terrain_level
		)
	return animal


func underwater_animal_material_for_depth(water_depth: int) -> ShaderMaterial:
	var depth_key := clampi(water_depth, 1, _water_surface_level)
	if _underwater_animal_material_cache.has(depth_key):
		return _underwater_animal_material_cache[depth_key]
	var material := ShaderMaterial.new()
	material.shader = UnderwaterAnimalShader
	material.set_shader_parameter("water_colour", _water_color)
	material.set_shader_parameter("fin_coverage", 0.08)
	material.set_shader_parameter(
		"body_coverage",
		clampf(0.58 + float(depth_key - 1) * 0.05, 0.58, 0.74)
	)
	material.set_shader_parameter("waterline", 0.29)
	material.set_shader_parameter(
		"submerged_visibility",
		clampf(0.80 - float(depth_key - 1) * 0.05, 0.62, 0.80)
	)
	_underwater_animal_material_cache[depth_key] = material
	return material


func animal_species_allows_surface(
	species: Dictionary,
	surface_id: StringName
) -> bool:
	var movement_value: Variant = species.get("movement", {})
	var movement: Dictionary = movement_value if movement_value is Dictionary else {}
	var surfaces_value: Variant = species.get(
		"allowed_surfaces",
		movement.get("allowed_surfaces", ["land"])
	)
	if not surfaces_value is Array:
		return false
	for allowed_surface in surfaces_value:
		if StringName(allowed_surface) == surface_id:
			return true
	return false


func animal_frames_for(species_id: String) -> SpriteFrames:
	if _animal_frames_cache.has(species_id):
		return _animal_frames_cache[species_id]
	var species: Dictionary = _animal_species[species_id]
	var directory := String(species.get("directory", ""))
	var actions: Dictionary = species.get("actions", {})
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	for action_id in actions:
		var action: Dictionary = actions[action_id]
		var animation_name := StringName(action_id)
		var texture: Texture2D = load(directory.path_join(String(action.get("file", ""))))
		if action.has("frame_size"):
			var frame_size_value: Array = action["frame_size"]
			add_sheet_animation(
				frames,
				animation_name,
				texture,
				Vector2i(int(frame_size_value[0]), int(frame_size_value[1])),
				int(action.get("columns", 1)),
				int(action.get("frames", 1)),
				float(action.get("fps", 1.0)),
				bool(action.get("loop", true))
			)
		else:
			frames.add_animation(animation_name)
			frames.set_animation_speed(animation_name, float(action.get("fps", 1.0)))
			frames.set_animation_loop(animation_name, bool(action.get("loop", true)))
			frames.add_frame(animation_name, texture)
	_animal_frames_cache[species_id] = frames
	return frames


func add_sheet_animation(
	frames: SpriteFrames,
	animation_name: StringName,
	sheet: Texture2D,
	frame_size: Vector2i,
	columns: int,
	frame_count: int,
	fps: float,
	loop: bool
) -> void:
	frames.add_animation(animation_name)
	frames.set_animation_speed(animation_name, fps)
	frames.set_animation_loop(animation_name, loop)
	for i in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(
			(i % columns) * frame_size.x,
			(i / columns) * frame_size.y,
			frame_size.x,
			frame_size.y
		)
		frames.add_frame(animation_name, atlas)


func clear_animals() -> void:
	for animal_value in _animals.values():
		var animal: Node = animal_value
		if is_instance_valid(animal):
			_host.remove_child(animal)
			animal.queue_free()
	_animals.clear()
	_animal_groups.clear()


func cleanup_streamed_animals() -> void:
	for origin_value in _animals.keys():
		var origin: Vector2i = origin_value
		var animal: AnimatedSprite3D = _animals[origin]
		if not is_instance_valid(animal):
			_animals.erase(origin)
			continue
		var active := animal_in_active_stream(animal)
		animal.visible = active
		var retained := (
			_in_stream(origin)
			or active
		)
		if retained:
			continue
		release_animal_group_member(animal)
		_animals.erase(origin)
		_host.remove_child(animal)
		animal.queue_free()


func update_animals(delta: float) -> void:
	for animal_value in _animals.values():
		var animal: AnimatedSprite3D = animal_value
		if not is_instance_valid(animal):
			continue
		var active := animal_in_active_stream(animal)
		animal.visible = active
		if not active:
			continue
		# 玩家进入警戒范围时打断静止等待；已经起步的动作完成后再重新选逃跑方向。
		var should_flee := animal_should_flee(animal)
		if not animal.moving and should_flee and not animal.fleeing:
			animal.wait_remaining = 0.0
		animal.fleeing = should_flee
		if animal.tick(delta):
			animal.consume_move_bout_step()
			animal.fleeing = animal_should_flee(animal)
			var continue_bout: bool = (
				animal.move_action_loops()
				and (animal.fleeing or animal.move_steps_remaining > 0)
			)
			if continue_bout:
				animal.wait_remaining = (
					ANIMAL_FLEE_WAIT
					if animal.fleeing
					else animal_step_pause(animal)
				)
			else:
				animal.finish_move_bout()
				animal.wait_remaining = (
					ANIMAL_FLEE_WAIT
					if animal.fleeing
					else animal_wait(animal.origin_cell, animal.step_index)
				)
		elif animal.ready_to_move():
			begin_animal_move(animal)


func animal_in_active_stream(animal: AnimatedSprite3D) -> bool:
	return (
		_in_stream(animal.grid_cell)
		or (animal.moving and _in_stream(animal.target_cell))
	)


func release_animal_group_member(animal: AnimatedSprite3D) -> void:
	var group_id := String(animal.community_group_id)
	if group_id.is_empty() or not _animal_groups.has(group_id):
		return
	_animal_groups.decrement_active_members(group_id)


func begin_animal_move(animal: AnimatedSprite3D) -> void:
	var current_cell: Vector2i = animal.grid_cell
	var fleeing := animal_should_flee(animal)
	_animal_behavior_distance_cache.clear()
	if not animal.move_bout_active:
		animal.start_move_bout(animal_bout_steps(animal))
	var direction_offset := int(_cell_rand.call(
		animal.origin_cell,
		9000 + animal.step_index * 97
	) * _animal_directions.size()) % _animal_directions.size()
	animal.step_index += 1
	var best_target := current_cell
	var best_score := animal_move_score(animal, current_cell, current_cell)
	for i in _animal_directions.size():
		var target: Vector2i = current_cell + _animal_directions[(direction_offset + i) % _animal_directions.size()]
		if not can_animal_enter(animal, target):
			continue
		var score := animal_move_score(animal, target, current_cell)
		# 平分时保留由 deterministic direction_offset 决定的第一个方向。
		if score > best_score:
			best_score = score
			best_target = target
	if best_target == current_cell:
		animal.finish_move_bout()
		animal.wait_remaining = (
			ANIMAL_BLOCKED_RETRY
			if fleeing
			else animal_wait(animal.origin_cell, animal.step_index)
		)
		return
	var movement_decision := animal_behavior_decision(animal, best_target, current_cell)
	var movement_speed := maxf(0.01, float(movement_decision.get("speed_multiplier", 1.0)))
	var from_stand_level := _stand_level(_quantize.call(current_cell.x, current_cell.y))
	var to_stand_level := _stand_level(_quantize.call(best_target.x, best_target.y))
	# 网格方向不等于屏幕方向；同一相机状态下投影起终点，供动物素材定向。
	var screen_horizontal_delta: float = (
		_grid_to_screen.call(best_target, to_stand_level).x
		- _grid_to_screen.call(current_cell, from_stand_level).x
	)
	animal.begin_move(
		best_target,
		_cell_feet_pos.call(current_cell),
		_cell_feet_pos.call(best_target),
		_column_sort_y.call(current_cell) + _animal_sort_bias,
		_column_sort_y.call(best_target) + _animal_sort_bias,
		animal.move_duration / movement_speed,
		movement_speed,
		from_stand_level,
		to_stand_level,
		screen_horizontal_delta
	)


func can_animal_enter(animal: AnimatedSprite3D, target: Vector2i) -> bool:
	if not _in_stream(target):
		return false
	var current_cell: Vector2i = animal.grid_cell
	var decision := animal_behavior_decision(animal, target, current_cell)
	if not bool(decision.get("allowed", false)):
		return false
	if target == _player_cell:
		return false
	if _cell_states.has(target) and _cell_states[target].blocks_movement():
		return false
	if animal_cell_reserved(target, animal):
		return false
	return true


func animal_cell_reserved(cell: Vector2i, except_animal: AnimatedSprite3D = null) -> bool:
	for other_value in _animals.values():
		var other: AnimatedSprite3D = other_value
		if other == except_animal or not is_instance_valid(other):
			continue
		if other.grid_cell == cell or (other.moving and other.target_cell == cell):
			return true
	return false


func animal_should_flee(animal: AnimatedSprite3D) -> bool:
	var current_decision := animal_behavior_decision(
		animal,
		animal.grid_cell,
		animal.grid_cell
	)
	if bool((current_decision.get("state", {}) as Dictionary).get("fleeing", false)):
		return true
	if animal.moving:
		var target_decision := animal_behavior_decision(
			animal,
			animal.target_cell,
			animal.grid_cell
		)
		return bool((target_decision.get("state", {}) as Dictionary).get("fleeing", false))
	return false


func animal_move_score(
	animal: AnimatedSprite3D,
	candidate: Vector2i,
	current_cell: Vector2i
) -> float:
	var score := 1.0 if candidate != current_cell else 0.0
	# 兼容热更新前已经误入水中的单位：水格仍不可作为新目标，但相邻陆格
	# 获得最高优先级，使遗留单位能够自行回到岸上而不是困在原地。
	if (
		_quantize.call(current_cell.x, current_cell.y) <= _water_max
		and _quantize.call(candidate.x, candidate.y) > _water_max
	):
		score += ANIMAL_LEAVE_WATER_BONUS
	var decision := animal_behavior_decision(animal, candidate, current_cell)
	if not bool(decision.get("allowed", false)):
		return -INF
	return (
		score
		+ float(decision.get("score", 0.0))
		+ animal.direction_persistence_score(candidate, current_cell)
	)


func animal_behavior_decision(
	animal: AnimatedSprite3D,
	candidate: Vector2i,
	current_cell: Vector2i
) -> Dictionary:
	var stack_value: Variant = _animal_behavior_stacks.get(animal.species_id, [])
	var stack: Array[Dictionary] = []
	if stack_value is Array:
		for behavior_value in stack_value:
			if behavior_value is Dictionary:
				stack.append((behavior_value as Dictionary).duplicate(true))
	if not String(animal.social_group_id).is_empty():
		stack.append({
			"type": "pack_cohesion",
			"radius": float(animal.social_radius),
			"weight": ANIMAL_GROUP_COHESION_WEIGHT,
		})
	var current := animal_behavior_cell_data(current_cell)
	var candidate_data := animal_behavior_cell_data(candidate)
	return _animal_behavior_registry.evaluate_stack(stack, candidate_data, {
		"current": current,
		"player_cell": _player_cell,
		"pack_center": (
			animal_social_center(animal)
			if not String(animal.social_group_id).is_empty()
			else null
		),
		"distance_to_tag": Callable(self, "animal_behavior_distance_to_tag"),
	})


func animal_behavior_cell_data(cell: Vector2i) -> Dictionary:
	var context = _cell_context_for_query.call(cell)
	return {
		"cell": cell,
		"height": _stand_level(context.height),
		"water_depth": context.water_depth,
		"water_clearance": _water_clearance.call(cell, 1),
		# 通行约束使用 surface class；材质与 biome 细节都保留在 tags 中。
		"surface_id": &"water" if context.is_water else &"land",
		"surface_kind": context.surface_id,
		"tags": context.tag_list(),
	}


func animal_behavior_distance_to_tag(
	candidate: Dictionary,
	tag: StringName
) -> float:
	var center: Vector2i = candidate.get("cell", Vector2i.ZERO)
	var cache_key := "%d/%d/%s" % [center.x, center.y, tag]
	if _animal_behavior_distance_cache.has(cache_key):
		return float(_animal_behavior_distance_cache[cache_key])
	var nearest := INF
	var scan_radius := _animal_behavior_tag_scan_radius
	for offset_y in range(-scan_radius, scan_radius + 1):
		var row_radius := scan_radius - absi(offset_y)
		for offset_x in range(-row_radius, row_radius + 1):
			var distance := absi(offset_x) + absi(offset_y)
			if float(distance) >= nearest:
				continue
			var context = _cell_context_for_query.call(
				center + Vector2i(offset_x, offset_y)
			)
			if context.has_tag(tag):
				nearest = float(distance)
	_animal_behavior_distance_cache[cache_key] = nearest
	return nearest


func animal_social_center(animal: AnimatedSprite3D) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for other_value in _animals.values():
		var other: AnimatedSprite3D = other_value
		if (
			not is_instance_valid(other)
			or not other.visible
			or other.social_group_id != animal.social_group_id
		):
			continue
		total += Vector2(other.grid_cell)
		count += 1
	return total / count if count > 0 else Vector2(animal.grid_cell)


func animal_wait(origin: Vector2i, step_index: int) -> float:
	return ANIMAL_WAIT_MIN + _cell_rand.call(origin, 8200 + step_index * 53) * ANIMAL_WAIT_SPAN


func animal_bout_steps(animal: AnimatedSprite3D) -> int:
	var step_count: int = int(animal.move_steps_max) - int(animal.move_steps_min) + 1
	if step_count <= 1:
		return int(animal.move_steps_min)
	return int(animal.move_steps_min) + int(
		_cell_rand.call(animal.origin_cell, 8300 + animal.bout_index * 67) * step_count
	) % step_count


func animal_step_pause(animal: AnimatedSprite3D) -> float:
	return lerpf(
		animal.step_pause_min,
		animal.step_pause_max,
		_cell_rand.call(animal.origin_cell, 8400 + animal.step_index * 71)
	)


func _stand_level(q: int) -> int:
	return maxi(q, _water_surface_level)


func _in_stream(cell: Vector2i) -> bool:
	return (
		absi(cell.x - _stream_center.x) <= _stream_extent
		and absi(cell.y - _stream_center.y) <= _stream_extent
	)
