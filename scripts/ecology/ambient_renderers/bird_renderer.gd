class_name BirdRenderer
extends Node

## View-lifetime bird renderer used by AmbientRegistry.
##
## Ground birds remain children of their terrain column so they inherit the
## world's existing depth order. Once startled they keep a world-space flight
## position, are projected into the foreground CanvasLayer each frame, play the
## fly loop, and are recycled after leaving the viewport.
## Dismissed cells stay empty until streaming removes and later re-adds them.

const WALK_ACTION := &"walk"
const FLY_ACTION := &"fly"
const DEFAULT_WALK_TEXTURE := "res://meowa_tiles/animals/bird/walk.png"
const DEFAULT_FLY_TEXTURE := "res://meowa_tiles/animals/bird/fly.png"
const FRAME_SIZE := Vector2i(32, 32)
const FRAME_COUNT := 8
const SOURCE_FACES_RIGHT := true
const DEFAULT_FLIGHT_LAYER := 3
const DEFAULT_GROUND_VISUAL_OFFSET := Vector2(0.0, -11.0)
const EPSILON := 0.0001
const MAX_FLIGHT_LIFETIME_SECONDS := 30.0

var _max_grounded := 10
var _walk_fps := 8.0
var _fly_fps := 10.0
var _walk_radius_range := Vector2(3.0, 7.0)
var _walk_speed_range := Vector2(0.8, 1.35)
var _takeoff_radius_cells := 4
var _escape_speed_range := Vector2(110.0, 150.0)
var _flyover_speed_range := Vector2(105.0, 145.0)
var _flyover_interval_range := Vector2(20.0, 45.0)
var _flyover_group_chance := 0.72
var _flyover_group_size := Vector2i(3, 6)
var _flyovers_enabled := true
var _offscreen_margin := 64.0
var _flight_layer_index := DEFAULT_FLIGHT_LAYER
var _ground_visual_offset := DEFAULT_GROUND_VISUAL_OFFSET

var _frames: SpriteFrames
var _flight_layer: CanvasLayer
var _flight_root: Node2D

## Vector2i -> {host_ref, local_surface_position, count, seed}
var _clusters: Dictionary = {}
## Vector3i(cell.x, cell.y, member_index) -> runtime entry
var _grounded: Dictionary = {}
## Cells whose birds already took off. Cleared only by remove_cell/clear.
var _dismissed_cells: Dictionary = {}
## Runtime entries with screen-space sprites plus authoritative world position
## and velocity. The explicit projection keeps camera motion out of integration.
var _flying: Array[Dictionary] = []

var _last_observer_context: Dictionary = {}
var _observer_world_seed := -2147483648
var _flyover_remaining := -1.0
var _rng := RandomNumberGenerator.new()
var _ground_priority_cell := Vector2i.ZERO
var _has_ground_priority := false


func _ready() -> void:
	_ensure_runtime()
	set_process(false)


## Renderer profile keys are optional; defaults are intentionally conservative.
func configure(profile: Dictionary = {}) -> void:
	clear()
	_max_grounded = maxi(0, int(profile.get("max_grounded", _max_grounded)))
	_walk_fps = maxf(0.01, float(profile.get("walk_fps", _walk_fps)))
	_fly_fps = maxf(0.01, float(profile.get("fly_fps", _fly_fps)))
	_walk_radius_range = _float_range(
		profile.get("walk_radius_pixels", [_walk_radius_range.x, _walk_radius_range.y]),
		_walk_radius_range
	)
	_walk_speed_range = _float_range(
		profile.get("walk_speed", [_walk_speed_range.x, _walk_speed_range.y]),
		_walk_speed_range
	)
	_takeoff_radius_cells = maxi(
		0,
		int(profile.get("takeoff_radius_cells", _takeoff_radius_cells))
	)
	_escape_speed_range = _float_range(
		profile.get("escape_speed", [_escape_speed_range.x, _escape_speed_range.y]),
		_escape_speed_range
	)
	_flyover_speed_range = _float_range(
		profile.get("flyover_speed", [_flyover_speed_range.x, _flyover_speed_range.y]),
		_flyover_speed_range
	)
	_flyover_interval_range = _float_range(
		profile.get(
			"flyover_interval_seconds",
			[_flyover_interval_range.x, _flyover_interval_range.y]
		),
		_flyover_interval_range
	)
	_flyover_group_chance = clampf(
		float(profile.get("flyover_group_chance", _flyover_group_chance)),
		0.0,
		1.0
	)
	_flyover_group_size = _integer_range(
		profile.get(
			"flyover_group_size",
			[_flyover_group_size.x, _flyover_group_size.y]
		),
		_flyover_group_size
	)
	_flyovers_enabled = bool(profile.get("flyovers_enabled", _flyovers_enabled))
	_offscreen_margin = maxf(
		1.0,
		float(profile.get("offscreen_margin", _offscreen_margin))
	)
	_flight_layer_index = int(profile.get("flight_layer", _flight_layer_index))
	_ground_visual_offset = _vector2_from_value(
		profile.get(
			"ground_visual_offset",
			[_ground_visual_offset.x, _ground_visual_offset.y]
		),
		_ground_visual_offset
	)
	_ensure_runtime()
	_flight_layer.layer = _flight_layer_index
	_build_frames(
		String(profile.get("walk_texture", DEFAULT_WALK_TEXTURE)),
		String(profile.get("fly_texture", DEFAULT_FLY_TEXTURE))
	)


## AmbientRegistry cluster interface. The position is the projected foot point
## relative to the supplied terrain-column host.
func add_cluster(
	cell: Vector2i,
	host: Node2D,
	local_surface_position: Vector2,
	count: int,
	deterministic_seed: int
) -> void:
	if count <= 0 or not is_instance_valid(host) or host.is_queued_for_deletion():
		remove_cell(cell)
		return
	_clusters[cell] = {
		"host_ref": weakref(host),
		"local_surface_position": local_surface_position,
		"count": count,
		"seed": deterministic_seed,
	}


## Streaming a cell out also releases its dismissed state, allowing birds to
## exist there again if the player returns later. Already-airborne birds finish
## flying out instead of disappearing at the streaming boundary.
func remove_cell(cell: Vector2i) -> void:
	_clusters.erase(cell)
	_dismissed_cells.erase(cell)
	var release_keys: Array[Vector3i] = []
	for key_value in _grounded.keys():
		var key: Vector3i = key_value
		if key.x == cell.x and key.y == cell.y:
			release_keys.append(key)
	for key in release_keys:
		_release_grounded(key)


func clear() -> void:
	_clusters.clear()
	_dismissed_cells.clear()
	for key_value in _grounded.keys().duplicate():
		_release_grounded(key_value)
	for index in range(_flying.size() - 1, -1, -1):
		_release_flying(index)
	_last_observer_context.clear()
	_observer_world_seed = -2147483648
	_flyover_remaining = -1.0
	_has_ground_priority = false


## Selects a deterministic bounded set from all streamed candidate clusters.
func refresh_field() -> void:
	_ensure_runtime()
	_ensure_frames()
	var desired: Dictionary = {}
	if _max_grounded > 0:
		var cells: Array = _clusters.keys()
		cells.sort_custom(_cluster_priority_less)
		for cell_value in cells:
			var cell: Vector2i = cell_value
			if _dismissed_cells.has(cell):
				continue
			var cluster: Dictionary = _clusters[cell]
			if _cluster_host(cluster) == null:
				continue
			# A 32x32 walking animation cannot form a readable pair inside one
			# 32x16 isometric surface. Keep at most one grounded bird per cell;
			# nearby candidate cells still create natural loose groups.
			for member_index in mini(1, maxi(0, int(cluster.get("count", 0)))):
				if desired.size() >= _max_grounded:
					break
				desired[Vector3i(cell.x, cell.y, member_index)] = cluster
			if desired.size() >= _max_grounded:
				break

	for key_value in _grounded.keys().duplicate():
		var key: Vector3i = key_value
		if not desired.has(key):
			_release_grounded(key)

	for key_value in desired.keys():
		var key: Vector3i = key_value
		var cluster: Dictionary = desired[key]
		if _grounded.has(key):
			_update_grounded_cluster(_grounded[key], cluster)
		else:
			_activate_grounded(key, cluster)


## Optional observer interface. Main supplies immutable view/player facts; the
## renderer owns all bird state transitions and never queries the world node.
func update_observer(context: Dictionary, delta: float) -> void:
	_ensure_runtime()
	_ensure_frames()
	if context.has("player_cell"):
		var next_priority_cell: Vector2i = context.get("player_cell", Vector2i.ZERO)
		if not _has_ground_priority or next_priority_cell != _ground_priority_cell:
			_ground_priority_cell = next_priority_cell
			_has_ground_priority = true
			# With more candidates than the visual cap, retain the closest stable
			# clusters instead of spending the entire budget outside the viewport.
			refresh_field()
	_last_observer_context = context.duplicate(true)
	_sync_observer_seed(int(context.get("world_seed", 0)))
	var safe_delta := maxf(0.0, delta)
	_update_grounded_walk(safe_delta)
	_trigger_nearby_takeoffs(context)
	_update_flying(context, safe_delta)
	_update_automatic_flyovers(context, safe_delta)


## Deterministic test/debug hook. direction > 0 flies left-to-right, direction
## < 0 right-to-left, and 0 lets the renderer choose randomly.
func force_flyover(
	count := 1,
	direction := 0,
	context: Dictionary = {}
) -> int:
	if not context.is_empty():
		_last_observer_context = context.duplicate(true)
		_sync_observer_seed(int(context.get("world_seed", 0)))
	return _spawn_flyover(
		maxi(1, int(count)),
		clampi(int(direction), -1, 1),
		_last_observer_context
	)


func get_grounded_count() -> int:
	return _grounded.size()


func get_flying_count() -> int:
	return _flying.size()


func get_dismissed_count() -> int:
	return _dismissed_cells.size()


func is_cell_dismissed(cell: Vector2i) -> bool:
	return _dismissed_cells.has(cell)


func get_grounded_sprites() -> Array[AnimatedSprite2D]:
	var result: Array[AnimatedSprite2D] = []
	for entry_value in _grounded.values():
		var entry: Dictionary = entry_value
		var sprite: AnimatedSprite2D = entry.get("sprite")
		if is_instance_valid(sprite):
			result.append(sprite)
	return result


func get_flying_sprites() -> Array[AnimatedSprite2D]:
	var result: Array[AnimatedSprite2D] = []
	for entry in _flying:
		var sprite: AnimatedSprite2D = entry.get("sprite")
		if is_instance_valid(sprite):
			result.append(sprite)
	return result


func get_sprite_frames() -> SpriteFrames:
	_ensure_frames()
	return _frames


func _ensure_runtime() -> void:
	if not is_instance_valid(_flight_layer):
		_flight_layer = CanvasLayer.new()
		_flight_layer.name = "BirdFlightLayer"
		_flight_layer.layer = _flight_layer_index
		_flight_layer.follow_viewport_enabled = false
		add_child(_flight_layer)
	if not is_instance_valid(_flight_root):
		_flight_root = Node2D.new()
		_flight_root.name = "BirdFlightRoot"
		_flight_layer.add_child(_flight_root)


func _ensure_frames() -> void:
	if _frames == null:
		_build_frames(DEFAULT_WALK_TEXTURE, DEFAULT_FLY_TEXTURE)


func _build_frames(walk_path: String, fly_path: String) -> void:
	_frames = SpriteFrames.new()
	if _frames.has_animation(&"default"):
		_frames.remove_animation(&"default")
	_add_sheet_animation(WALK_ACTION, _load_texture(walk_path), _walk_fps)
	_add_sheet_animation(FLY_ACTION, _load_texture(fly_path), _fly_fps)


## Newly copied art may not have an editor-generated `.import` file yet. The
## direct Image fallback keeps headless tests and first launch functional while
## ResourceLoader remains the normal path after Godot imports the asset.
func _load_texture(resource_path: String) -> Texture2D:
	if ResourceLoader.exists(resource_path):
		var imported: Resource = load(resource_path)
		if imported is Texture2D:
			return imported as Texture2D
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	var image := Image.load_from_file(absolute_path)
	if image == null or image.is_empty():
		push_error("Bird texture cannot be loaded: %s" % resource_path)
		return null
	return ImageTexture.create_from_image(image)


func _add_sheet_animation(
	action: StringName,
	texture: Texture2D,
	fps: float
) -> void:
	_frames.add_animation(action)
	_frames.set_animation_speed(action, fps)
	_frames.set_animation_loop(action, true)
	if texture == null:
		return
	for frame_index in FRAME_COUNT:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(
			Vector2(frame_index * FRAME_SIZE.x, 0),
			Vector2(FRAME_SIZE)
		)
		_frames.add_frame(action, atlas)


func _new_sprite(action: StringName) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = _frames
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.play(action)
	return sprite


func _activate_grounded(key: Vector3i, cluster: Dictionary) -> void:
	var host := _cluster_host(cluster)
	if host == null:
		return
	var sprite := _new_sprite(WALK_ACTION)
	host.add_child(sprite)
	var seed := int(cluster.get("seed", 0)) ^ key.z * 0x45d9f3b
	var member_jitter := Vector2(
		lerpf(-4.0, 4.0, _seeded_rand01(seed + 11)),
		lerpf(-1.0, 1.0, _seeded_rand01(seed + 13))
	)
	var base_position := (
		Vector2(cluster.get("local_surface_position", Vector2.ZERO))
		+ member_jitter
		+ _ground_visual_offset
	)
	var entry := {
		"sprite": sprite,
		"host_ref": weakref(host),
		"cell": Vector2i(key.x, key.y),
		"member_jitter": member_jitter,
		"base_position": base_position,
		"elapsed": 0.0,
		"phase": _seeded_rand01(seed + 17) * TAU,
		"radius": lerpf(
			_walk_radius_range.x,
			_walk_radius_range.y,
			_seeded_rand01(seed + 19)
		),
		"speed": lerpf(
			_walk_speed_range.x,
			_walk_speed_range.y,
			_seeded_rand01(seed + 23)
		),
		"seed": seed,
	}
	_grounded[key] = entry
	_apply_grounded_pose(entry)


func _update_grounded_cluster(entry: Dictionary, cluster: Dictionary) -> void:
	var next_host := _cluster_host(cluster)
	var sprite: AnimatedSprite2D = entry.get("sprite")
	if next_host == null or not is_instance_valid(sprite):
		return
	if sprite.get_parent() != next_host:
		sprite.reparent(next_host, false)
		entry["host_ref"] = weakref(next_host)
	entry["base_position"] = (
		Vector2(cluster.get("local_surface_position", Vector2.ZERO))
		+ Vector2(entry.get("member_jitter", Vector2.ZERO))
		+ _ground_visual_offset
	)
	_apply_grounded_pose(entry)


func _update_grounded_walk(delta: float) -> void:
	var invalid_keys: Array[Vector3i] = []
	for key_value in _grounded.keys():
		var key: Vector3i = key_value
		var entry: Dictionary = _grounded[key]
		var sprite: AnimatedSprite2D = entry.get("sprite")
		if not is_instance_valid(sprite) or _entry_host(entry) == null:
			invalid_keys.append(key)
			continue
		entry["elapsed"] = float(entry.get("elapsed", 0.0)) + delta
		_apply_grounded_pose(entry)
	for key in invalid_keys:
		_release_grounded(key)


func _apply_grounded_pose(entry: Dictionary) -> void:
	var sprite: AnimatedSprite2D = entry.get("sprite")
	if not is_instance_valid(sprite):
		return
	var angle := (
		float(entry.get("phase", 0.0))
		+ float(entry.get("elapsed", 0.0)) * float(entry.get("speed", 1.0))
	)
	var radius := float(entry.get("radius", 0.0))
	var base := Vector2(entry.get("base_position", Vector2.ZERO))
	var host := _entry_host(entry)
	var cell: Vector2i = entry.get("cell", Vector2i.ZERO)
	if host != null and host.has_method("_grid_to_screen") and host.has_method("cell_stand_level"):
		base = host._grid_to_screen(cell, float(host.cell_stand_level(cell))) \
			+ Vector2(entry.get("member_jitter", Vector2.ZERO)) + _ground_visual_offset
	sprite.position = base + Vector2(
		sin(angle) * radius,
		0.0
	)
	var horizontal_velocity := cos(angle) * radius * float(entry.get("speed", 1.0))
	if absf(horizontal_velocity) > EPSILON:
		# Both source sheets face right.
		sprite.flip_h = horizontal_velocity < 0.0 if SOURCE_FACES_RIGHT else horizontal_velocity > 0.0
	if sprite.animation != WALK_ACTION or not sprite.is_playing():
		sprite.play(WALK_ACTION)


func _trigger_nearby_takeoffs(context: Dictionary) -> void:
	if not context.has("player_cell"):
		return
	var player_cell: Vector2i = context.get("player_cell", Vector2i.ZERO)
	var takeoff_keys: Array[Vector3i] = []
	for key_value in _grounded.keys():
		var key: Vector3i = key_value
		var entry: Dictionary = _grounded[key]
		var cell: Vector2i = entry.get("cell", Vector2i(key.x, key.y))
		if (
			absi(cell.x - player_cell.x) + absi(cell.y - player_cell.y)
			<= _takeoff_radius_cells
		):
			takeoff_keys.append(key)
	for key in takeoff_keys:
		_takeoff(key, context)


func _takeoff(key: Vector3i, context: Dictionary) -> void:
	if not _grounded.has(key):
		return
	var entry: Dictionary = _grounded[key]
	var sprite: AnimatedSprite2D = entry.get("sprite")
	if not is_instance_valid(sprite):
		_grounded.erase(key)
		return
	var world_position := sprite.global_position
	var screen_position := _world_to_screen(world_position, context)
	var viewport_size: Vector2 = context.get("viewport_size", Vector2.ZERO)
	var player_screen: Vector2 = context.get(
		"player_screen_position",
		viewport_size * 0.5
	)
	var away := screen_position - player_screen
	if away.length_squared() <= EPSILON:
		away = Vector2(-1.0 if _seeded_rand01(int(entry.get("seed", 0)) + 31) < 0.5 else 1.0, -0.25)
	else:
		away = away.normalized()
	# A mostly vertical trajectory can remain visible for too long. Preserve the
	# away direction while guaranteeing a useful horizontal exit component.
	if absf(away.x) < 0.45:
		away.x = -0.45 if screen_position.x < player_screen.x else 0.45
		away = away.normalized()
	var speed := lerpf(
		_escape_speed_range.x,
		_escape_speed_range.y,
		_seeded_rand01(int(entry.get("seed", 0)) + 37)
	)
	var screen_velocity := away * speed
	var world_velocity := _screen_velocity_to_world(screen_velocity, context)
	var scale_value := _observer_scale(context)
	_grounded.erase(key)
	var old_parent := sprite.get_parent()
	if old_parent != null:
		old_parent.remove_child(sprite)
	_flight_root.add_child(sprite)
	sprite.position = screen_position
	sprite.scale = scale_value
	sprite.play(FLY_ACTION)
	sprite.flip_h = away.x < 0.0 if SOURCE_FACES_RIGHT else away.x > 0.0
	_flying.append({
		"sprite": sprite,
		"world_position": world_position,
		"world_velocity": world_velocity,
		"age": 0.0,
		"entered_viewport": true,
		"kind": &"escape",
		"origin_cell": Vector2i(key.x, key.y),
	})
	_dismissed_cells[Vector2i(key.x, key.y)] = true


func _update_flying(context: Dictionary, delta: float) -> void:
	var viewport_size: Vector2 = context.get("viewport_size", Vector2.ZERO)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	var visible_rect := Rect2(Vector2.ZERO, viewport_size).grow(_offscreen_margin)
	var observer_scale := _observer_scale(context)
	for index in range(_flying.size() - 1, -1, -1):
		var entry: Dictionary = _flying[index]
		var sprite: AnimatedSprite2D = entry.get("sprite")
		if not is_instance_valid(sprite):
			_flying.remove_at(index)
			continue
		var previous_screen_position := sprite.position
		entry["age"] = float(entry.get("age", 0.0)) + delta
		# Integrate only authoritative world coordinates. Camera smoothing changes
		# the projection below, never the bird's velocity or accumulated position.
		var world_position: Vector2 = entry.get(
			"world_position",
			_screen_to_world(sprite.position, context)
		)
		var world_velocity: Vector2 = entry.get(
			"world_velocity",
			_screen_velocity_to_world(
				Vector2(entry.get("velocity", Vector2.ZERO)),
				context
			)
		)
		world_position += world_velocity * delta
		entry["world_position"] = world_position
		entry["world_velocity"] = world_velocity
		sprite.position = _world_to_screen(world_position, context)
		sprite.scale = observer_scale
		var entered_viewport := bool(entry.get("entered_viewport", false))
		var travel_min := previous_screen_position.min(sprite.position)
		var travel_max := previous_screen_position.max(sprite.position)
		var crossed_viewport := (
			travel_min.x <= viewport_size.x
			and travel_max.x >= 0.0
			and travel_min.y <= viewport_size.y
			and travel_max.y >= 0.0
		)
		if (
			viewport_rect.has_point(sprite.position)
			or crossed_viewport
		):
			entered_viewport = true
		entry["entered_viewport"] = entered_viewport
		_flying[index] = entry
		# Flyover formations deliberately start beyond one another outside the
		# viewport. Do not recycle their trailing members before they have had a
		# chance to enter; once seen, the normal expanded-viewport culling applies.
		if (
			(entered_viewport and not visible_rect.has_point(sprite.position))
			or float(entry["age"]) >= MAX_FLIGHT_LIFETIME_SECONDS
		):
			_release_flying(index)


func _update_automatic_flyovers(context: Dictionary, delta: float) -> void:
	if not _flyovers_enabled or not bool(context.get("allow_flyovers", true)):
		return
	var viewport_size: Vector2 = context.get("viewport_size", Vector2.ZERO)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	if _flyover_remaining < 0.0:
		_schedule_next_flyover()
	_flyover_remaining -= delta
	if _flyover_remaining > 0.0:
		return
	var count := 1
	if _rng.randf() < _flyover_group_chance:
		count = _rng.randi_range(_flyover_group_size.x, _flyover_group_size.y)
	_spawn_flyover(count, 0, context)
	_schedule_next_flyover()


func _spawn_flyover(
	count: int,
	direction: int,
	context: Dictionary
) -> int:
	_ensure_runtime()
	_ensure_frames()
	var viewport_size: Vector2 = context.get("viewport_size", Vector2.ZERO)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return 0
	var horizontal_direction := direction
	if horizontal_direction == 0:
		horizontal_direction = 1 if _rng.randf() < 0.5 else -1
	var base_x := (
		-_offscreen_margin * 0.75
		if horizontal_direction > 0
		else viewport_size.x + _offscreen_margin * 0.75
	)
	var base_y := lerpf(viewport_size.y * 0.18, viewport_size.y * 0.55, _rng.randf())
	var base_speed := lerpf(
		_flyover_speed_range.x,
		_flyover_speed_range.y,
		_rng.randf()
	)
	var observer_scale := _observer_scale(context)
	var base_vertical_speed := lerpf(-4.0, 4.0, _rng.randf())
	var trail_distance := 0.0
	var spawned := 0
	for member_index in maxi(1, count):
		var sprite := _new_sprite(FLY_ACTION)
		_flight_root.add_child(sprite)
		if member_index > 0:
			trail_distance += lerpf(22.0, 28.0, _rng.randf()) * observer_scale.x
		var formation_rank := float((member_index + 1) / 2)
		var formation_y := (
			0.0
			if member_index == 0
			else (-1.0 if member_index % 2 == 0 else 1.0)
			* (8.0 + formation_rank * 4.0)
			* observer_scale.y
		)
		var screen_position := Vector2(
			base_x - float(horizontal_direction) * trail_distance,
			base_y + formation_y
		)
		sprite.position = screen_position
		sprite.scale = observer_scale
		sprite.flip_h = horizontal_direction < 0 if SOURCE_FACES_RIGHT else horizontal_direction > 0
		sprite.frame = _rng.randi_range(0, FRAME_COUNT - 1)
		# Members share the flock's vertical drift and only receive a small
		# variation, so the V formation does not immediately tear apart.
		var vertical_speed := base_vertical_speed + lerpf(-1.5, 1.5, _rng.randf())
		var screen_velocity := Vector2(
			float(horizontal_direction) * base_speed,
			vertical_speed
		)
		_flying.append({
			"sprite": sprite,
			"world_position": _screen_to_world(screen_position, context),
			"world_velocity": _screen_velocity_to_world(screen_velocity, context),
			"age": 0.0,
			"entered_viewport": false,
			"kind": &"flyover",
			"origin_cell": Vector2i.ZERO,
		})
		spawned += 1
	return spawned


func _release_grounded(key: Vector3i) -> void:
	if not _grounded.has(key):
		return
	var entry: Dictionary = _grounded[key]
	var sprite: AnimatedSprite2D = entry.get("sprite")
	_grounded.erase(key)
	if is_instance_valid(sprite):
		sprite.queue_free()


func _release_flying(index: int) -> void:
	if index < 0 or index >= _flying.size():
		return
	var entry: Dictionary = _flying[index]
	var sprite: AnimatedSprite2D = entry.get("sprite")
	_flying.remove_at(index)
	if is_instance_valid(sprite):
		sprite.queue_free()


func _cluster_host(cluster: Dictionary) -> Node2D:
	var host_ref: Variant = cluster.get("host_ref", null)
	if not host_ref is WeakRef:
		return null
	var host: Variant = (host_ref as WeakRef).get_ref()
	if (
		not host is Node2D
		or not is_instance_valid(host)
		or (host as Node2D).is_queued_for_deletion()
	):
		return null
	return host as Node2D


func _entry_host(entry: Dictionary) -> Node2D:
	var host_ref: Variant = entry.get("host_ref", null)
	if not host_ref is WeakRef:
		return null
	var host: Variant = (host_ref as WeakRef).get_ref()
	return host as Node2D if host is Node2D and is_instance_valid(host) else null


func _cluster_priority_less(a: Vector2i, b: Vector2i) -> bool:
	if _has_ground_priority:
		var a_distance := (
			absi(a.x - _ground_priority_cell.x)
			+ absi(a.y - _ground_priority_cell.y)
		)
		var b_distance := (
			absi(b.x - _ground_priority_cell.x)
			+ absi(b.y - _ground_priority_cell.y)
		)
		if a_distance != b_distance:
			return a_distance < b_distance
	var a_cluster: Dictionary = _clusters.get(a, {})
	var b_cluster: Dictionary = _clusters.get(b, {})
	var a_priority := _mixed_priority(a, int(a_cluster.get("seed", 0)))
	var b_priority := _mixed_priority(b, int(b_cluster.get("seed", 0)))
	if a_priority != b_priority:
		return a_priority < b_priority
	return a.y < b.y or (a.y == b.y and a.x < b.x)


func _mixed_priority(cell: Vector2i, seed: int) -> int:
	return hash(Vector3i(cell.x ^ seed, cell.y, seed * 31))


func _sync_observer_seed(world_seed: int) -> void:
	if world_seed == _observer_world_seed:
		return
	_observer_world_seed = world_seed
	_rng.seed = world_seed ^ 0x42b1a55
	_flyover_remaining = -1.0


func _schedule_next_flyover() -> void:
	_flyover_remaining = lerpf(
		_flyover_interval_range.x,
		_flyover_interval_range.y,
		_rng.randf()
	)


func _observer_scale(context: Dictionary) -> Vector2:
	if context.has("camera_3d"):
		return Vector2.ONE
	var zoom_value: Variant = context.get("zoom", Vector2.ONE)
	if zoom_value is Vector2:
		var zoom: Vector2 = zoom_value
		return Vector2(maxf(EPSILON, absf(zoom.x)), maxf(EPSILON, absf(zoom.y)))
	var uniform := maxf(EPSILON, absf(float(zoom_value)))
	return Vector2.ONE * uniform


## The foreground flight layer stays in screen space for a stable draw layer,
## while every bird keeps authoritative world coordinates. Project from the
## current Camera2D values supplied by main; Viewport.canvas_transform can still
## describe the previous camera frame while camera smoothing is being updated.
func _world_to_screen(world_position: Vector2, context: Dictionary) -> Vector2:
	if context.has("camera_3d"):
		return world_position
	var viewport_size: Vector2 = context.get("viewport_size", Vector2.ZERO)
	var camera_world_position: Vector2 = context.get(
		"camera_world_position",
		Vector2.ZERO
	)
	var zoom := _observer_scale(context)
	return viewport_size * 0.5 + (world_position - camera_world_position) * zoom


func _screen_to_world(screen_position: Vector2, context: Dictionary) -> Vector2:
	if context.has("camera_3d"):
		return screen_position
	var viewport_size: Vector2 = context.get("viewport_size", Vector2.ZERO)
	var camera_world_position: Vector2 = context.get(
		"camera_world_position",
		Vector2.ZERO
	)
	var zoom := _observer_scale(context)
	return camera_world_position + Vector2(
		(screen_position.x - viewport_size.x * 0.5) / zoom.x,
		(screen_position.y - viewport_size.y * 0.5) / zoom.y
	)


func _screen_velocity_to_world(
	screen_velocity: Vector2,
	context: Dictionary
) -> Vector2:
	var zoom := Vector2.ONE if context.has("camera_3d") else _observer_scale(context)
	return Vector2(screen_velocity.x / zoom.x, screen_velocity.y / zoom.y)


func _seeded_rand01(seed_value: int) -> float:
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = seed_value
	return local_rng.randf()


func _float_range(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() == 2:
		var minimum := maxf(0.0, float(value[0]))
		return Vector2(minimum, maxf(minimum, float(value[1])))
	return fallback


func _integer_range(value: Variant, fallback: Vector2i) -> Vector2i:
	if value is Array and value.size() == 2:
		var minimum := maxi(1, int(value[0]))
		return Vector2i(minimum, maxi(minimum, int(value[1])))
	return fallback


func _vector2_from_value(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Vector2:
		return value
	return fallback
