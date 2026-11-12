extends Node

## 夜间萤火虫场。候选簇由 Main 按生态与流式地块注册，本节点只负责
## 确定性实例选择、池化和视觉动画，不参与地图或生态生成。
##
## Sprite2D 始终挂在对应地块列 host 下，因此使用世界空间并继承该列的
## 绘制顺序；上下漂浮只改变列内局部位置，不会改变遮挡锚点。

const DEFAULT_MAX_VISIBLE := 72
const DEFAULT_MAX_LIGHTS := 12
const NIGHT_START := 0.30
const NIGHT_FULL := 0.72
const ACTIVE_EPSILON := 0.001
const GLOW_TEXTURE_SIZE := 32
const CORE_TEXTURE_SIZE := 4
const LIGHT_TEXTURE_SIZE := Vector2i(128, 64)
const TAU_F := TAU

var _max_visible := DEFAULT_MAX_VISIBLE
var _max_lights := DEFAULT_MAX_LIGHTS
var _night_amount := 0.0
var _visible_night_amount := 0.0
var _elapsed := 0.0
var _field_dirty := false

## Vector2i -> {host_ref, local_surface_position, count, seed}
var _clusters: Dictionary = {}
## Vector3i(cell.x, cell.y, instance_index) -> runtime entry
var _active: Dictionary = {}
var _sprite_pool: Array[Sprite2D] = []
## Vector2i -> {light, host_ref, phase, energy_scale}
var _cluster_lights: Dictionary = {}
var _light_pool: Array[PointLight2D] = []

var _glow_texture: ImageTexture
var _core_texture: ImageTexture
var _light_texture: ImageTexture
var _glow_material: CanvasItemMaterial


func _ready() -> void:
	_ensure_visual_resources()
	set_process(false)


func configure(
	max_visible: int = DEFAULT_MAX_VISIBLE,
	max_lights: int = DEFAULT_MAX_LIGHTS
) -> void:
	_max_visible = maxi(0, max_visible)
	_max_lights = maxi(0, max_lights)
	_ensure_visual_resources()
	_field_dirty = true
	refresh_field()


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
	_field_dirty = true


func remove_cell(cell: Vector2i) -> void:
	_clusters.erase(cell)
	var keys_to_release: Array[Vector3i] = []
	for key_value in _active.keys():
		var key: Vector3i = key_value
		if key.x == cell.x and key.y == cell.y:
			keys_to_release.append(key)
	for key in keys_to_release:
		_release_active(key)
	_release_cluster_light(cell)
	_field_dirty = true
	_update_processing_state()


func clear() -> void:
	_clusters.clear()
	for key_value in _active.keys().duplicate():
		_release_active(key_value)
	for cell_value in _cluster_lights.keys().duplicate():
		_release_cluster_light(cell_value)
	_field_dirty = false
	_elapsed = 0.0
	_update_processing_state()


func set_night_amount(amount: float) -> void:
	_night_amount = clampf(amount, 0.0, 1.0)
	_visible_night_amount = smoothstep(NIGHT_START, NIGHT_FULL, _night_amount)
	if _visible_night_amount > ACTIVE_EPSILON and (_field_dirty or _active.is_empty()):
		refresh_field()
	_apply_visual_state()
	_update_processing_state()


## 将注册簇稳定地映射到最多 max_visible 个实例。保留仍在目标集合内的
## Sprite，避免流式窗口平移时整片萤火虫重新闪烁。
func refresh_field() -> void:
	_ensure_visual_resources()
	var desired: Dictionary = {}
	if _max_visible > 0:
		var cells: Array = _clusters.keys()
		cells.sort_custom(_cluster_priority_less)
		for cell_value in cells:
			var cell: Vector2i = cell_value
			var cluster: Dictionary = _clusters[cell]
			var host := _cluster_host(cluster)
			if host == null:
				continue
			var instance_count := maxi(0, int(cluster.get("count", 0)))
			for instance_index in instance_count:
				if desired.size() >= _max_visible:
					break
				var key := Vector3i(cell.x, cell.y, instance_index)
				desired[key] = cluster
			if desired.size() >= _max_visible:
				break

	var release_keys: Array[Vector3i] = []
	for key_value in _active.keys():
		var key: Vector3i = key_value
		if not desired.has(key) or not _entry_matches_cluster(_active[key], desired[key]):
			release_keys.append(key)
	for key in release_keys:
		_release_active(key)

	for key_value in desired.keys():
		var key: Vector3i = key_value
		var cluster: Dictionary = desired[key]
		if _active.has(key):
			var retained: Dictionary = _active[key]
			retained["base_position"] = Vector2(cluster["local_surface_position"])
			continue
		_activate(key, cluster)

	_field_dirty = false
	_refresh_cluster_lights()
	_apply_visual_state()
	_update_processing_state()


func get_active_count() -> int:
	if _visible_night_amount <= ACTIVE_EPSILON:
		return 0
	return _active.size()


func get_registered_count() -> int:
	return _clusters.size()


func get_active_light_count() -> int:
	if _visible_night_amount <= ACTIVE_EPSILON:
		return 0
	var count := 0
	for light_entry_value in _cluster_lights.values():
		var light_entry: Dictionary = light_entry_value
		var light: PointLight2D = light_entry["light"]
		if is_instance_valid(light) and light.enabled and light.energy > 0.0:
			count += 1
	return count


func get_active_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if _visible_night_amount <= ACTIVE_EPSILON:
		return result
	var seen: Dictionary = {}
	for key_value in _active.keys():
		var key: Vector3i = key_value
		var cell := Vector2i(key.x, key.y)
		if not seen.has(cell):
			seen[cell] = true
			result.append(cell)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return result


func _process(delta: float) -> void:
	_elapsed += delta
	var invalid_keys: Array[Vector3i] = []
	for key_value in _active.keys():
		var key: Vector3i = key_value
		var entry: Dictionary = _active[key]
		var sprite: Sprite2D = entry["sprite"]
		var host := _entry_host(entry)
		if host == null or not is_instance_valid(sprite):
			invalid_keys.append(key)
			continue
		_animate_entry(entry, sprite)
	for key in invalid_keys:
		_release_active(key)
	if not invalid_keys.is_empty():
		_field_dirty = true
		_refresh_cluster_lights()
	_animate_cluster_lights()
	_update_processing_state()


func _activate(key: Vector3i, cluster: Dictionary) -> void:
	var host := _cluster_host(cluster)
	if host == null:
		return
	var sprite := _acquire_sprite()
	_reparent_sprite(sprite, host)
	sprite.name = "Firefly_%d_%d_%d" % [key.x, key.y, key.z]
	sprite.set_meta("firefly_cell", Vector2i(key.x, key.y))
	sprite.set_meta("firefly_index", key.z)
	sprite.set_meta("firefly_visual_role", &"halo")
	var core := _core_sprite(sprite)
	if core != null:
		core.set_meta("firefly_cell", Vector2i(key.x, key.y))
		core.set_meta("firefly_index", key.z)
		core.set_meta("firefly_visual_role", &"core")

	var seed := int(cluster.get("seed", 0))
	var cell := Vector2i(key.x, key.y)
	var base_seed := _instance_seed(cell, key.z, seed, 0)
	var cluster_angle := _rand01(_instance_seed(cell, key.z, seed, 1)) * TAU_F
	var cluster_distance := 2.0 + _rand01(_instance_seed(cell, key.z, seed, 2)) * 8.0
	var entry := {
		"sprite": sprite,
		"host_ref": weakref(host),
		"base_position": Vector2(cluster["local_surface_position"]),
		"cell": cell,
		"seed": seed,
		"phase": _rand01(base_seed) * TAU_F,
		"phase_secondary": _rand01(_instance_seed(cell, key.z, seed, 3)) * TAU_F,
		"cluster_offset": Vector2.from_angle(cluster_angle) * cluster_distance,
		"hover_height": 8.0 + _rand01(_instance_seed(cell, key.z, seed, 4)) * 12.0,
		"radius_x": 2.5 + _rand01(_instance_seed(cell, key.z, seed, 5)) * 5.5,
		"radius_y": 1.5 + _rand01(_instance_seed(cell, key.z, seed, 6)) * 4.0,
		"speed_x": 0.38 + _rand01(_instance_seed(cell, key.z, seed, 7)) * 0.42,
		"speed_y": 0.27 + _rand01(_instance_seed(cell, key.z, seed, 8)) * 0.36,
		"pulse_period": 2.4 + _rand01(_instance_seed(cell, key.z, seed, 9)) * 2.8,
		"pulse_offset": _rand01(_instance_seed(cell, key.z, seed, 11)),
		"double_flash": (
			0.62
			if _rand01(_instance_seed(cell, key.z, seed, 12)) < 0.22
			else 0.0
		),
		"scale_base": 0.50 + _rand01(_instance_seed(cell, key.z, seed, 10)) * 0.22,
		"current_flicker": 0.0,
	}
	_active[key] = entry
	_animate_entry(entry, sprite)


func _animate_entry(entry: Dictionary, sprite: Sprite2D) -> void:
	var phase := float(entry["phase"])
	var phase_secondary := float(entry["phase_secondary"])
	var slow_drift := Vector2(
		sin(_elapsed * float(entry["speed_x"]) + phase) * float(entry["radius_x"]),
		cos(_elapsed * float(entry["speed_y"]) + phase_secondary) * float(entry["radius_y"])
	)
	var flutter := Vector2(
		sin(_elapsed * 1.73 + phase_secondary) * 0.9,
		sin(_elapsed * 1.31 + phase) * 0.65
	)
	var base_position: Vector2 = entry["base_position"]
	var host := _entry_host(entry)
	var cell: Vector2i = entry.get("cell", Vector2i.ZERO)
	if host != null and host.has_method("_grid_to_screen") and host.has_method("cell_stand_level"):
		base_position = host._grid_to_screen(cell, float(host.cell_stand_level(cell)))
	var cluster_offset: Vector2 = entry["cluster_offset"]
	sprite.position = (
		base_position
		+ cluster_offset
		+ Vector2(0.0, -float(entry["hover_height"]))
		+ slow_drift
		+ flutter
	)

	var wave := 0.5 + 0.5 * sin(_elapsed * 0.74 + phase_secondary)
	var pulse_cycle := fposmod(
		_elapsed / float(entry["pulse_period"]) + float(entry["pulse_offset"]),
		1.0
	)
	var primary_flash := (
		smoothstep(0.0, 0.035, pulse_cycle)
		* (1.0 - smoothstep(0.11, 0.22, pulse_cycle))
	)
	var secondary_flash := (
		smoothstep(0.24, 0.275, pulse_cycle)
		* (1.0 - smoothstep(0.32, 0.40, pulse_cycle))
		* float(entry["double_flash"])
	)
	# 短亮长暗，少量个体带双闪；各自周期与相位不同，不会整片同步呼吸。
	var flicker := maxf(primary_flash, secondary_flash) * (0.88 + wave * 0.12)
	entry["current_flicker"] = flicker
	var halo_alpha := _visible_night_amount * (0.08 + flicker * 0.84)
	sprite.self_modulate = Color(1.0, 1.0, 1.0, halo_alpha)
	var visual_scale := float(entry["scale_base"]) * (0.92 + flicker * 0.16)
	sprite.scale = Vector2.ONE * visual_scale
	sprite.visible = halo_alpha > ACTIVE_EPSILON
	var core := _core_sprite(sprite)
	if core != null:
		var core_alpha := _visible_night_amount * (0.20 + flicker * 0.80)
		core.self_modulate = Color(1.0, 0.96, 0.60, core_alpha)
		core.scale = Vector2.ONE * (0.84 + wave * 0.04 + flicker * 0.20)
		core.visible = core_alpha > ACTIVE_EPSILON


func _apply_visual_state() -> void:
	var visible_at_night := _visible_night_amount > ACTIVE_EPSILON
	for entry_value in _active.values():
		var entry: Dictionary = entry_value
		var sprite: Sprite2D = entry["sprite"]
		if not is_instance_valid(sprite):
			continue
		if visible_at_night:
			_animate_entry(entry, sprite)
		else:
			sprite.visible = false
			sprite.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
			var core := _core_sprite(sprite)
			if core != null:
				core.visible = false
				core.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
	_animate_cluster_lights()


func _update_processing_state() -> void:
	set_process(_visible_night_amount > ACTIVE_EPSILON and not _active.is_empty())


func _acquire_sprite() -> Sprite2D:
	var sprite: Sprite2D
	if _sprite_pool.is_empty():
		sprite = Sprite2D.new()
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.texture = _glow_texture
		sprite.material = _glow_material
		sprite.z_index = 0
		sprite.z_as_relative = true
		sprite.show_behind_parent = false
		var core := Sprite2D.new()
		core.name = "Core"
		core.centered = true
		core.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		core.texture = _core_texture
		core.material = _glow_material
		core.z_index = 1
		core.z_as_relative = true
		sprite.add_child(core)
		add_child(sprite)
	else:
		sprite = _sprite_pool.pop_back()
		sprite.texture = _glow_texture
		sprite.material = _glow_material
		var core := _core_sprite(sprite)
		if core != null:
			core.texture = _core_texture
			core.material = _glow_material
	return sprite


func _core_sprite(sprite: Sprite2D) -> Sprite2D:
	return sprite.get_node_or_null("Core") as Sprite2D


func _release_active(key: Vector3i) -> void:
	if not _active.has(key):
		return
	var entry: Dictionary = _active[key]
	var sprite: Sprite2D = entry["sprite"]
	_active.erase(key)
	if not is_instance_valid(sprite):
		return
	sprite.visible = false
	sprite.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2.ONE
	sprite.remove_meta("firefly_cell")
	sprite.remove_meta("firefly_index")
	sprite.remove_meta("firefly_visual_role")
	var core := _core_sprite(sprite)
	if core != null:
		core.visible = false
		core.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
		core.scale = Vector2.ONE
		core.remove_meta("firefly_cell")
		core.remove_meta("firefly_index")
		core.remove_meta("firefly_visual_role")
	_reparent_sprite(sprite, self)
	_sprite_pool.append(sprite)


## 每个生态簇最多使用一个真实 2D 光源。光源数量独立受限，避免 72 个
## 萤火虫各自照明；视觉粒子仍可全部显示。
func _refresh_cluster_lights() -> void:
	var active_cells: Dictionary = {}
	for key_value in _active.keys():
		var key: Vector3i = key_value
		active_cells[Vector2i(key.x, key.y)] = true
	var desired_cells: Array = active_cells.keys()
	# 屏幕内簇优先获得有限灯位；同一视野内按距中心排序，最后才用稳定 hash。
	desired_cells.sort_custom(_light_priority_less)
	if desired_cells.size() > _max_lights:
		desired_cells.resize(_max_lights)
	var desired: Dictionary = {}
	for cell_value in desired_cells:
		desired[cell_value] = true

	for cell_value in _cluster_lights.keys().duplicate():
		var cell: Vector2i = cell_value
		if not desired.has(cell):
			_release_cluster_light(cell)

	for cell_value in desired_cells:
		var cell: Vector2i = cell_value
		if not _clusters.has(cell):
			continue
		var cluster: Dictionary = _clusters[cell]
		var host := _cluster_host(cluster)
		if host == null:
			continue
		if _cluster_lights.has(cell):
			var retained: Dictionary = _cluster_lights[cell]
			if _light_entry_host(retained) == host:
				retained["base_position"] = Vector2(cluster["local_surface_position"])
				continue
			_release_cluster_light(cell)

		var light := _acquire_light()
		_reparent_light(light, host)
		light.name = "FireflyLight_%d_%d" % [cell.x, cell.y]
		light.set_meta("firefly_cell", cell)
		var seed := int(cluster.get("seed", 0))
		_cluster_lights[cell] = {
			"light": light,
			"host_ref": weakref(host),
			"base_position": Vector2(cluster["local_surface_position"]),
			"energy_scale": 0.88 + _rand01(
				_instance_seed(cell, 0, seed, 42)
			) * 0.24,
		}
	_animate_cluster_lights()


func _animate_cluster_lights() -> void:
	var accumulators: Dictionary = {}
	for key_value in _active.keys():
		var key: Vector3i = key_value
		var cell := Vector2i(key.x, key.y)
		if not _cluster_lights.has(cell):
			continue
		var entry: Dictionary = _active[key]
		var sprite: Sprite2D = entry["sprite"]
		if not is_instance_valid(sprite):
			continue
		if not accumulators.has(cell):
			accumulators[cell] = {
				"position_sum": Vector2.ZERO,
				"flicker_sum": 0.0,
				"flicker_peak": 0.0,
				"count": 0,
			}
		var accumulator: Dictionary = accumulators[cell]
		accumulator["position_sum"] = Vector2(accumulator["position_sum"]) + sprite.position
		var current_flicker := float(entry.get("current_flicker", 0.0))
		accumulator["flicker_sum"] = float(accumulator["flicker_sum"]) + current_flicker
		accumulator["flicker_peak"] = maxf(
			float(accumulator["flicker_peak"]),
			current_flicker
		)
		accumulator["count"] = int(accumulator["count"]) + 1

	for cell_value in _cluster_lights.keys():
		var cell: Vector2i = cell_value
		var light_entry: Dictionary = _cluster_lights[cell]
		var light: PointLight2D = light_entry["light"]
		if not is_instance_valid(light):
			continue
		if _visible_night_amount <= ACTIVE_EPSILON or not accumulators.has(cell):
			light.enabled = false
			light.energy = 0.0
			continue
		var accumulator: Dictionary = accumulators[cell]
		var count := maxi(1, int(accumulator["count"]))
		var average_position := Vector2(accumulator["position_sum"]) / float(count)
		var average_flicker := float(accumulator["flicker_sum"]) / float(count)
		var peak_flicker := float(accumulator["flicker_peak"])
		var surface_position := _cluster_screen_position(cell)
		light_entry["base_position"] = surface_position
		# 光团略向地表下沉，让邻近地块被照亮，而不是只围绕空中的亮点。
		light.position = average_position.lerp(surface_position, 0.68)
		# 簇光跟随最亮个体，同时混入平均亮度，避免多个异步个体把光照摊薄成常亮。
		var light_envelope := pow(
			clampf(peak_flicker * 0.78 + average_flicker * 0.22, 0.0, 1.0),
			1.45
		)
		light.energy = (
			_visible_night_amount
			* (0.045 + light_envelope * 0.60)
			* float(light_entry["energy_scale"])
		)
		light.enabled = light.energy > ACTIVE_EPSILON


func _acquire_light() -> PointLight2D:
	var light: PointLight2D
	if _light_pool.is_empty():
		light = PointLight2D.new()
		light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		light.blend_mode = Light2D.BLEND_MODE_ADD
		light.shadow_enabled = false
		light.range_z_min = -4096
		light.range_z_max = 4096
		add_child(light)
	else:
		light = _light_pool.pop_back()
	light.texture = _light_texture
	light.texture_scale = 0.54
	light.color = Color(1.0, 0.92, 0.50)
	light.energy = 0.0
	light.enabled = false
	return light


func _release_cluster_light(cell: Vector2i) -> void:
	if not _cluster_lights.has(cell):
		return
	var light_entry: Dictionary = _cluster_lights[cell]
	var light: PointLight2D = light_entry["light"]
	_cluster_lights.erase(cell)
	if not is_instance_valid(light):
		return
	light.enabled = false
	light.energy = 0.0
	light.position = Vector2.ZERO
	light.remove_meta("firefly_cell")
	_reparent_light(light, self)
	_light_pool.append(light)


func _reparent_light(light: PointLight2D, new_parent: Node) -> void:
	if light.get_parent() == new_parent:
		return
	var old_parent := light.get_parent()
	if old_parent != null:
		old_parent.remove_child(light)
	new_parent.add_child(light)


func _light_entry_host(entry: Dictionary) -> Node2D:
	var host_ref: WeakRef = entry.get("host_ref")
	if host_ref == null:
		return null
	var host := host_ref.get_ref() as Node2D
	if host == null or not is_instance_valid(host) or host.is_queued_for_deletion():
		return null
	return host


func _reparent_sprite(sprite: Sprite2D, new_parent: Node) -> void:
	if sprite.get_parent() == new_parent:
		return
	var old_parent := sprite.get_parent()
	if old_parent != null:
		old_parent.remove_child(sprite)
	new_parent.add_child(sprite)


func _entry_matches_cluster(entry: Dictionary, cluster: Dictionary) -> bool:
	var entry_host := _entry_host(entry)
	var cluster_host := _cluster_host(cluster)
	return (
		entry_host != null
		and entry_host == cluster_host
		and int(entry.get("seed", 0)) == int(cluster.get("seed", 0))
	)


func _cluster_host(cluster: Dictionary) -> Node2D:
	var host_ref: WeakRef = cluster.get("host_ref")
	if host_ref == null:
		return null
	var host: Node2D = host_ref.get_ref() as Node2D
	if (
		host == null
		or not is_instance_valid(host)
		or host.is_queued_for_deletion()
	):
		return null
	return host


func _entry_host(entry: Dictionary) -> Node2D:
	var host_ref: WeakRef = entry.get("host_ref")
	if host_ref == null:
		return null
	var host: Node2D = host_ref.get_ref() as Node2D
	if (
		host == null
		or not is_instance_valid(host)
		or host.is_queued_for_deletion()
	):
		return null
	return host


func _cluster_priority_less(a_value: Variant, b_value: Variant) -> bool:
	var a: Vector2i = a_value
	var b: Vector2i = b_value
	var a_cluster: Dictionary = _clusters[a]
	var b_cluster: Dictionary = _clusters[b]
	var a_priority := _instance_seed(a, 0, int(a_cluster.get("seed", 0)), 97)
	var b_priority := _instance_seed(b, 0, int(b_cluster.get("seed", 0)), 97)
	if a_priority != b_priority:
		return a_priority < b_priority
	return a.y < b.y or (a.y == b.y and a.x < b.x)


func _light_priority_less(a_value: Variant, b_value: Variant) -> bool:
	var a: Vector2i = a_value
	var b: Vector2i = b_value
	var viewport := get_viewport()
	if viewport == null:
		return _cluster_priority_less(a, b)
	var viewport_size := Vector2(viewport.get_visible_rect().size)
	var viewport_center := viewport_size * 0.5
	var margin := Vector2(64.0, 64.0)
	var expanded_view := Rect2(-margin, viewport_size + margin * 2.0)
	var a_screen := _cluster_screen_position(a)
	var b_screen := _cluster_screen_position(b)
	var a_visible := expanded_view.has_point(a_screen)
	var b_visible := expanded_view.has_point(b_screen)
	if a_visible != b_visible:
		return a_visible
	var a_distance := a_screen.distance_squared_to(viewport_center)
	var b_distance := b_screen.distance_squared_to(viewport_center)
	if not is_equal_approx(a_distance, b_distance):
		return a_distance < b_distance
	return _cluster_priority_less(a, b)


func _cluster_screen_position(cell: Vector2i) -> Vector2:
	if not _clusters.has(cell):
		return Vector2(1.0e20, 1.0e20)
	var cluster: Dictionary = _clusters[cell]
	var host := _cluster_host(cluster)
	if host == null:
		return Vector2(1.0e20, 1.0e20)
	var viewport := get_viewport()
	if viewport == null:
		return Vector2(1.0e20, 1.0e20)
	if host.has_method("_grid_to_screen") and host.has_method("cell_stand_level"):
		return host._grid_to_screen(cell, float(host.cell_stand_level(cell)))
	var world_position := host.to_global(Vector2(cluster["local_surface_position"]))
	return viewport.get_canvas_transform() * world_position


func _instance_seed(cell: Vector2i, instance_index: int, seed: int, salt: int) -> int:
	return _hash_u32(
		seed
		^ cell.x * 0x8DA6B343
		^ cell.y * 0xD8163841
		^ instance_index * 0xCB1AB31F
		^ salt * 0x165667B1
	)


func _rand01(value: int) -> float:
	return float(_hash_u32(value)) / 4294967295.0


func _hash_u32(value: int) -> int:
	var hashed := value
	hashed = (hashed ^ (hashed >> 16)) & 0xFFFFFFFF
	hashed = (hashed * 0x7FEB352D) & 0xFFFFFFFF
	hashed = (hashed ^ (hashed >> 15)) & 0xFFFFFFFF
	hashed = (hashed * 0x846CA68B) & 0xFFFFFFFF
	hashed = (hashed ^ (hashed >> 16)) & 0xFFFFFFFF
	return hashed


func _ensure_visual_resources() -> void:
	if _glow_texture == null:
		_glow_texture = _make_glow_texture()
	if _core_texture == null:
		_core_texture = _make_core_texture()
	if _light_texture == null:
		_light_texture = _make_light_texture()
	if _glow_material == null:
		_glow_material = CanvasItemMaterial.new()
		_glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_glow_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED


func _make_glow_texture() -> ImageTexture:
	var image := Image.create(
		GLOW_TEXTURE_SIZE,
		GLOW_TEXTURE_SIZE,
		false,
		Image.FORMAT_RGBA8
	)
	var center := Vector2(GLOW_TEXTURE_SIZE, GLOW_TEXTURE_SIZE) * 0.5
	var outer_color := Color(0.70, 0.94, 0.30)
	var inner_color := Color(1.0, 0.82, 0.22)
	for y in GLOW_TEXTURE_SIZE:
		for x in GLOW_TEXTURE_SIZE:
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			var distance := point.distance_to(center) / (GLOW_TEXTURE_SIZE * 0.5)
			var halo := 1.0 - smoothstep(0.08, 1.0, distance)
			var inner := 1.0 - smoothstep(0.02, 0.34, distance)
			var color := outer_color.lerp(inner_color, inner)
			var alpha := maxf(pow(halo, 2.0) * 0.16, inner * 0.58)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
	return ImageTexture.create_from_image(image)


func _make_core_texture() -> ImageTexture:
	var image := Image.create(
		CORE_TEXTURE_SIZE,
		CORE_TEXTURE_SIZE,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color.TRANSPARENT)
	var core_color := Color(1.0, 0.94, 0.52, 1.0)
	for y in range(1, 3):
		for x in range(1, 3):
			image.set_pixel(x, y, core_color)
	return ImageTexture.create_from_image(image)


func _make_light_texture() -> ImageTexture:
	# 椭圆光池顺着等距地表展开，比圆形光斑更像悬浮光源投向地面的漫反射。
	var image := Image.create(
		LIGHT_TEXTURE_SIZE.x,
		LIGHT_TEXTURE_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	var center := Vector2(LIGHT_TEXTURE_SIZE) * 0.5
	var half_size := Vector2(LIGHT_TEXTURE_SIZE) * 0.5
	for y in LIGHT_TEXTURE_SIZE.y:
		for x in LIGHT_TEXTURE_SIZE.x:
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			var normalized := (point - center) / half_size
			var distance := normalized.length()
			var falloff := 1.0 - smoothstep(0.04, 1.0, distance)
			var intensity := pow(maxf(falloff, 0.0), 2.2)
			# Add 模式读取 RGB 强度；alpha 同步写入以兼容其他渲染后端。
			image.set_pixel(x, y, Color(intensity, intensity, intensity, intensity))
	return ImageTexture.create_from_image(image)
