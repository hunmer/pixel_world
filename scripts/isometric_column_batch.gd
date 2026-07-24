extends Node2D

## 一个地图格只对应一个 CanvasItem。父节点负责按格子脚点排序，
## 这里按已经排好的顺序一次画完整根地块柱，避免不同格的层互相穿插。

var _blocks: Array[Dictionary] = []
var _screen_y_offset := 0.0
var _level_height := 8.0
var _water_ripples: Array[Dictionary] = []
var _ripple_redraw_elapsed := 0.0
var _has_shoreline := false
var _occlusion_alpha := 1.0
var _occlusion_target_alpha := 1.0
var _block_occlusion_alphas := {}  ## block index -> current alpha
var _block_occlusion_targets := {}  ## block index -> target alpha
var _block_cutaway_shades := {}  ## block index -> current deep-gray overlay amount
var _block_cutaway_shade_targets := {}  ## block index -> target overlay amount
var _occluder_visual_bounds := Rect2()
var _has_occluder_visual_bounds := false
static var _texture_image_cache: Dictionary = {}
static var _texture_alpha_mask_cache: Dictionary = {}

const WATER_SURFACE_VISUAL_OFFSET := Vector2(0.0, -2.0)
const MAX_WATER_RIPPLES := 4
const RIPPLE_SEGMENTS := 18
const RIPPLE_REDRAW_INTERVAL := 1.0 / 30.0
const SHORELINE_FRAME_COUNT := 4
const SHORELINE_FRAME_SECONDS := 0.34
const SHORELINE_COLOR := Color(0.94, 0.98, 1.0, 0.96)
const SHORELINE_LINE_WIDTH := 0.50
const SHORELINE_EDGE_COVERAGE := 0.50
const SHORELINE_HALF_LENGTH_MIN := 3.4
const SHORELINE_HALF_LENGTH_MAX := 5.3
const SHORELINE_TIDE_PHASES := [0.08, 0.54, 1.0, 0.38]
const SHORELINE_TIDE_ALPHA_PHASES := [0.96, 1.0, 1.0, 0.98]
const SHORELINE_EVEN_ALPHA_PHASES := [1.0, 0.68, 0.05, 0.68]
const SHORELINE_ODD_ALPHA_PHASES := [0.05, 0.68, 1.0, 0.68]
const SHORELINE_SEGMENT_COUNT_MIN := 5
const SHORELINE_SEGMENT_COUNT_MAX := 6
const PLAYER_OCCLUDED_ALPHA := 0.20
const PLAYER_CUTAWAY_SHADE_AMOUNT := 0.76
const PLAYER_CUTAWAY_SHADE_COLOR := Color(0.298, 0.325, 0.357, 1.0)
const PLAYER_OCCLUSION_FADE_OUT_RATE := 14.0
const PLAYER_OCCLUSION_FADE_IN_RATE := 7.0
const OCCLUSION_LEVEL_EPSILON := 0.01
const OCCLUDER_TERRAIN := &"terrain"
const OCCLUDER_PROP := &"prop"


func configure(
	cell: Vector2i,
	blocks: Array[Dictionary],
	screen_position: Vector2,
	sort_y: float,
	level_height: float
) -> void:
	name = "Column_%d_%d" % [cell.x, cell.y]
	_blocks = blocks
	_level_height = level_height
	_occlusion_alpha = 1.0
	_occlusion_target_alpha = 1.0
	_block_occlusion_alphas.clear()
	_block_occlusion_targets.clear()
	_block_cutaway_shades.clear()
	_block_cutaway_shade_targets.clear()
	_ripple_redraw_elapsed = 0.0
	_has_shoreline = false
	for block_value in _blocks:
		var configured_block: Dictionary = block_value
		if int(configured_block.get("shore_edges", 0)) != 0:
			_has_shoreline = true
			break
	var tint := self_modulate
	tint.a = 1.0
	self_modulate = tint
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 岸线循环由 RenderingServer 的 animation slice 驱动，不让每个岸线格
	# 都进入 _process()。这里只有短生命周期的雨雪水波需要 CPU 更新。
	set_process(not _water_ripples.is_empty())
	update_sort_position(screen_position, sort_y)


func update_sort_position(screen_position: Vector2, sort_y: float) -> void:
	# 节点原点承载合成的 Y-sort 深度；局部绘制偏移把像素补偿回真实投影位置。
	position = Vector2(screen_position.x, sort_y)
	_screen_y_offset = screen_position.y - sort_y
	_rebuild_occluder_visual_bounds()
	queue_redraw()


func _block_visual_rect(block: Dictionary) -> Rect2:
	var texture: Texture2D = block["texture"]
	var center := position + Vector2(
		0.0,
		_screen_y_offset - float(block["level"]) * _level_height
	) + Vector2(block["render_offset"])
	return Rect2(center - texture.get_size() * 0.5, texture.get_size())


func _texture_image(texture: Texture2D) -> Image:
	var texture_id := texture.get_instance_id()
	if not _texture_image_cache.has(texture_id):
		_texture_image_cache[texture_id] = texture.get_image()
	return _texture_image_cache[texture_id]


func _texture_alpha_mask(texture: Texture2D) -> Texture2D:
	var texture_id := texture.get_instance_id()
	if _texture_alpha_mask_cache.has(texture_id):
		return _texture_alpha_mask_cache[texture_id]
	var source := _texture_image(texture)
	var mask := Image.create(
		source.get_width(),
		source.get_height(),
		false,
		Image.FORMAT_RGBA8
	)
	for y in source.get_height():
		for x in source.get_width():
			mask.set_pixel(x, y, Color(1.0, 1.0, 1.0, source.get_pixel(x, y).a))
	var mask_texture := ImageTexture.create_from_image(mask)
	_texture_alpha_mask_cache[texture_id] = mask_texture
	return mask_texture


func _block_has_opaque_overlap(block: Dictionary, query_rect: Rect2) -> bool:
	var block_rect := _block_visual_rect(block)
	var overlap := block_rect.intersection(query_rect)
	if not overlap.has_area():
		return false
	var texture: Texture2D = block["texture"]
	var image := _texture_image(texture)
	if image == null or image.is_empty():
		return true
	var minimum_x := clampi(
		floori(overlap.position.x - block_rect.position.x),
		0,
		image.get_width() - 1
	)
	var maximum_x := clampi(
		ceili(overlap.end.x - block_rect.position.x) - 1,
		0,
		image.get_width() - 1
	)
	var minimum_y := clampi(
		floori(overlap.position.y - block_rect.position.y),
		0,
		image.get_height() - 1
	)
	var maximum_y := clampi(
		ceili(overlap.end.y - block_rect.position.y) - 1,
		0,
		image.get_height() - 1
	)
	for y in range(minimum_y, maximum_y + 1):
		for x in range(minimum_x, maximum_x + 1):
			if image.get_pixel(x, y).a > 0.01:
				return true
	return false


func _block_can_occlude_player(block: Dictionary, player_stand_level: float) -> bool:
	var occluder_class: StringName = block.get("occluder_class", &"")
	if occluder_class == OCCLUDER_PROP:
		return true
	return (
		occluder_class == OCCLUDER_TERRAIN
		and float(block["level"]) > player_stand_level + OCCLUSION_LEVEL_EPSILON
	)


func _rebuild_occluder_visual_bounds() -> void:
	_has_occluder_visual_bounds = false
	_occluder_visual_bounds = Rect2()
	for block in _blocks:
		var occluder_class: StringName = block.get("occluder_class", &"")
		if occluder_class != OCCLUDER_TERRAIN and occluder_class != OCCLUDER_PROP:
			continue
		var block_rect := _block_visual_rect(block)
		if _has_occluder_visual_bounds:
			_occluder_visual_bounds = _occluder_visual_bounds.merge(block_rect)
		else:
			_occluder_visual_bounds = block_rect
			_has_occluder_visual_bounds = true


## 返回最终投影后覆盖指定屏幕窗口的具体方块，而不是用逻辑地图距离猜测。
## 判定始终读取原始贴图范围，不受正在变化的透明度影响，避免淡出/淡入振荡。
func player_occluding_block_indices(
	player_rect: Rect2,
	player_stand_level: float
) -> Array[int]:
	var result: Array[int] = []
	if (
		not _has_occluder_visual_bounds
		or not _occluder_visual_bounds.intersects(player_rect)
	):
		return result
	for index in _blocks.size():
		var block: Dictionary = _blocks[index]
		if not _block_can_occlude_player(block, player_stand_level):
			continue
		if _block_has_opaque_overlap(block, player_rect):
			result.append(index)
	return result


func has_player_occluding_block(player_rect: Rect2, player_stand_level: float) -> bool:
	return not player_occluding_block_indices(player_rect, player_stand_level).is_empty()


## 兼容调试/回归接口；正式路径使用 player_occluding_block_indices 精确选 block。
func has_player_occlusion_content(player_stand_level: float) -> bool:
	for block in _blocks:
		if _block_can_occlude_player(block, player_stand_level):
			return true
	return false


func _cutaway_underlay_indices(occluded_indices: Dictionary) -> Dictionary:
	var lowest_occluded_terrain_level := 0
	var has_occluded_terrain := false
	for index_value in occluded_indices.keys():
		var index := int(index_value)
		var block: Dictionary = _blocks[index]
		if block.get("occluder_class", &"") != OCCLUDER_TERRAIN:
			continue
		var level := int(block["level"])
		if not has_occluded_terrain or level < lowest_occluded_terrain_level:
			lowest_occluded_terrain_level = level
			has_occluded_terrain = true
	var result := {}
	if not has_occluded_terrain:
		return result
	var base_index := -1
	var base_level := 0
	for index in _blocks.size():
		var block: Dictionary = _blocks[index]
		if (
			block.get("occluder_class", &"") == OCCLUDER_TERRAIN
			and int(block["level"]) < lowest_occluded_terrain_level
		):
			var level := int(block["level"])
			if base_index < 0 or level > base_level:
				base_index = index
				base_level = level
	if base_index >= 0:
		result[base_index] = true
	return result


func set_player_occlusion_blocks(block_indices: Array, target_alpha: float) -> void:
	var next_indices := {}
	var changed := false
	var clamped_target := clampf(target_alpha, 0.0, 1.0)
	for index_value in block_indices:
		var index := int(index_value)
		if index < 0 or index >= _blocks.size():
			continue
		next_indices[index] = true
		if not _block_occlusion_alphas.has(index):
			_block_occlusion_alphas[index] = 1.0
		if (
			not _block_occlusion_targets.has(index)
			or not is_equal_approx(float(_block_occlusion_targets[index]), clamped_target)
		):
			changed = true
		_block_occlusion_targets[index] = clamped_target
	for index_value in _block_occlusion_targets.keys():
		var index := int(index_value)
		if not next_indices.has(index):
			if not is_equal_approx(float(_block_occlusion_targets[index]), 1.0):
				changed = true
			_block_occlusion_targets[index] = 1.0

	# 透明地形下方仍是实体柱。只给同柱紧邻的 terrain 基底加深灰剖面，
	# prop、植物和水都不会触发或继承这层不可通行提示。
	var next_cutaway_indices := _cutaway_underlay_indices(next_indices)
	for index_value in next_cutaway_indices.keys():
		var index := int(index_value)
		if not _block_cutaway_shades.has(index):
			_block_cutaway_shades[index] = 0.0
		if (
			not _block_cutaway_shade_targets.has(index)
			or not is_equal_approx(
				float(_block_cutaway_shade_targets[index]),
				PLAYER_CUTAWAY_SHADE_AMOUNT
			)
		):
			changed = true
		_block_cutaway_shade_targets[index] = PLAYER_CUTAWAY_SHADE_AMOUNT
	for index_value in _block_cutaway_shade_targets.keys():
		var index := int(index_value)
		if next_cutaway_indices.has(index):
			continue
		if not is_equal_approx(float(_block_cutaway_shade_targets[index]), 0.0):
			changed = true
		_block_cutaway_shade_targets[index] = 0.0
	_refresh_occlusion_summary()
	if changed:
		queue_redraw()


func _refresh_occlusion_summary() -> void:
	_occlusion_alpha = 1.0
	_occlusion_target_alpha = 1.0
	for index_value in _block_occlusion_targets.keys():
		var index := int(index_value)
		_occlusion_alpha = minf(
			_occlusion_alpha,
			float(_block_occlusion_alphas.get(index, 1.0))
		)
		_occlusion_target_alpha = minf(
			_occlusion_target_alpha,
			float(_block_occlusion_targets[index])
		)


func set_player_occluded(occluded: bool) -> void:
	if not occluded:
		set_player_occlusion_blocks([], 1.0)
		return
	var all_occluding_blocks: Array[int] = []
	for index in _blocks.size():
		var occluder_class: StringName = _blocks[index].get("occluder_class", &"")
		if occluder_class == OCCLUDER_TERRAIN or occluder_class == OCCLUDER_PROP:
			all_occluding_blocks.append(index)
	set_player_occlusion_blocks(all_occluding_blocks, PLAYER_OCCLUDED_ALPHA)


## 返回是否已经到达目标；仅含活跃 block 的少量列会由 Main 调用。
func advance_player_occlusion(delta: float) -> bool:
	var settled := true
	var changed := false
	for index_value in _block_occlusion_targets.keys():
		var index := int(index_value)
		var current := float(_block_occlusion_alphas.get(index, 1.0))
		var target := float(_block_occlusion_targets[index])
		var rate := (
			PLAYER_OCCLUSION_FADE_OUT_RATE
			if target < current
			else PLAYER_OCCLUSION_FADE_IN_RATE
		)
		var blend := 1.0 - exp(-rate * maxf(delta, 0.0))
		var previous := current
		current = lerpf(current, target, blend)
		if absf(current - target) < 0.001:
			current = target
		else:
			settled = false
		if not is_equal_approx(previous, current):
			changed = true
		_block_occlusion_alphas[index] = current
		if is_equal_approx(current, 1.0) and is_equal_approx(target, 1.0):
			_block_occlusion_alphas.erase(index)
			_block_occlusion_targets.erase(index)
	for index_value in _block_cutaway_shade_targets.keys():
		var index := int(index_value)
		var current := float(_block_cutaway_shades.get(index, 0.0))
		var target := float(_block_cutaway_shade_targets[index])
		var rate := (
			PLAYER_OCCLUSION_FADE_OUT_RATE
			if target > current
			else PLAYER_OCCLUSION_FADE_IN_RATE
		)
		var blend := 1.0 - exp(-rate * maxf(delta, 0.0))
		var previous := current
		current = lerpf(current, target, blend)
		if absf(current - target) < 0.001:
			current = target
		else:
			settled = false
		if not is_equal_approx(previous, current):
			changed = true
		_block_cutaway_shades[index] = current
		if is_zero_approx(current) and is_zero_approx(target):
			_block_cutaway_shades.erase(index)
			_block_cutaway_shade_targets.erase(index)
	_refresh_occlusion_summary()
	if changed:
		queue_redraw()
	return settled


func get_occlusion_alpha() -> float:
	return _occlusion_alpha


func get_occlusion_target_alpha() -> float:
	return _occlusion_target_alpha


func get_occluded_block_count() -> int:
	var count := 0
	for target in _block_occlusion_targets.values():
		if float(target) < 1.0:
			count += 1
	return count


func get_cutaway_shaded_block_count() -> int:
	var count := 0
	for target in _block_cutaway_shade_targets.values():
		if float(target) > 0.0:
			count += 1
	return count


func get_block_cutaway_shade(index: int) -> float:
	return float(_block_cutaway_shades.get(index, 0.0))


func get_block_cutaway_target_shade(index: int) -> float:
	return float(_block_cutaway_shade_targets.get(index, 0.0))


## 涟漪属于当前水柱，并在水面贴图之后、同格水面植物之前绘制。
## 这样无需额外节点，也不会破坏外层地块/动物的 Y-sort 遮挡关系。
func spawn_water_ripple(
	local_offset: Vector2,
	kind: StringName,
	strength: float,
	maximum_radius: float
) -> void:
	if _water_ripples.is_empty():
		_ripple_redraw_elapsed = 0.0
	if _water_ripples.size() >= MAX_WATER_RIPPLES:
		_water_ripples.pop_front()
	_water_ripples.append({
		"age": 0.0,
		"lifetime": 0.72 if kind == &"rain" else 1.05,
		"kind": kind,
		"offset": local_offset,
		"strength": clampf(strength, 0.0, 1.0),
		"maximum_radius": maximum_radius,
	})
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var needs_redraw := false
	if not _water_ripples.is_empty():
		_ripple_redraw_elapsed += delta
		for index in range(_water_ripples.size() - 1, -1, -1):
			var ripple: Dictionary = _water_ripples[index]
			ripple["age"] = float(ripple["age"]) + delta
			if float(ripple["age"]) >= float(ripple["lifetime"]):
				_water_ripples.remove_at(index)
				needs_redraw = true
			else:
				_water_ripples[index] = ripple
		if _ripple_redraw_elapsed >= RIPPLE_REDRAW_INTERVAL:
			_ripple_redraw_elapsed = fmod(
				_ripple_redraw_elapsed,
				RIPPLE_REDRAW_INTERVAL
			)
			needs_redraw = true
	else:
		_ripple_redraw_elapsed = 0.0
	set_process(not _water_ripples.is_empty())
	if needs_redraw:
		queue_redraw()


func _draw() -> void:
	for index in _blocks.size():
		var block: Dictionary = _blocks[index]
		var level: int = block["level"]
		var texture: Texture2D = block["texture"]
		var center := Vector2(
			0.0,
			_screen_y_offset - level * _level_height
		) + Vector2(block["render_offset"])
		var draw_modulate: Color = block["modulate"]
		draw_modulate.a *= float(_block_occlusion_alphas.get(index, 1.0))
		var draw_position := center - texture.get_size() * 0.5
		draw_texture(
			texture,
			draw_position,
			draw_modulate
		)
		var cutaway_shade := float(_block_cutaway_shades.get(index, 0.0))
		if cutaway_shade > 0.0:
			# 白色 alpha mask 让深灰以真实颜色覆盖，而不是简单乘暗后仍偏绿/偏棕。
			# 保留一部分原贴图，形成可辨认材质的深灰不可通行剖面。
			var shade_color := PLAYER_CUTAWAY_SHADE_COLOR
			shade_color.a = cutaway_shade * draw_modulate.a
			draw_texture(
				_texture_alpha_mask(texture),
				draw_position,
				shade_color
			)
		if block.get("water_part", &"") == &"surface":
			_draw_shoreline_foam(
				center,
				int(block.get("shore_edges", 0)),
				int(block.get("shore_seed", 0))
			)
			_draw_water_ripples(center + WATER_SURFACE_VISUAL_OFFSET)


func _draw_shoreline_foam(
	surface_center: Vector2,
	edge_mask: int,
	seed: int
) -> void:
	if edge_mask == 0:
		return
	var cycle_seconds := SHORELINE_FRAME_COUNT * SHORELINE_FRAME_SECONDS
	# 相邻格仅分成两个交错相位，再叠加极小时间偏移。比每格完全随机闪烁
	# 更像沿岸传播的潮汐，同时不会让整条岸线同步亮灭。
	var phase_step := 0 if _shoreline_rand(seed, 211) < 0.5 else 2
	var phase_offset := (
		float(phase_step) * SHORELINE_FRAME_SECONDS
		+ _shoreline_rand(seed, 213) * SHORELINE_FRAME_SECONDS * 0.08
	)
	for frame in SHORELINE_FRAME_COUNT:
		draw_animation_slice(
			cycle_seconds,
			float(frame) * SHORELINE_FRAME_SECONDS,
			float(frame + 1) * SHORELINE_FRAME_SECONDS,
			phase_offset
		)
		_draw_shoreline_frame(surface_center, edge_mask, seed, frame)
	# 后续雨滴水波必须恢复普通绘制，否则也会被最后一个动画切片过滤。
	draw_end_animation()


func _draw_shoreline_frame(
	surface_center: Vector2,
	edge_mask: int,
	seed: int,
	animation_step: int
) -> void:
	var vertices := [
		Vector2(-16.0, -2.0),
		Vector2(0.0, -10.0),
		Vector2(16.0, -2.0),
		Vector2(0.0, 6.0),
	]
	var edges := [
		[vertices[0], vertices[1]],
		[vertices[1], vertices[2]],
		[vertices[2], vertices[3]],
		[vertices[3], vertices[0]],
	]
	var active_edges: Array[int] = []
	for edge_index in 4:
		if (edge_mask & (1 << edge_index)) == 0:
			continue
		# 仅约半数接岸边生成浪花，静态缺口会打破连续描边感。
		if _shoreline_rand(seed, edge_index * 41 + 3) > SHORELINE_EDGE_COVERAGE:
			continue
		active_edges.append(edge_index)
	# 拐角通常只出现一小段浪花，避免两条边叠成醒目的白色 V；少量拐角
	# 保留第二段，让长岸线仍有自然的局部变化。
	if active_edges.size() > 1:
		var first_index := mini(
			int(_shoreline_rand(seed, 223) * float(active_edges.size())),
			active_edges.size() - 1
		)
		var selected_edges: Array[int] = [active_edges[first_index]]
		if _shoreline_rand(seed, 227) > 0.82:
			selected_edges.append(active_edges[(first_index + 1) % active_edges.size()])
		active_edges = selected_edges
	for edge_index in active_edges:
		var edge: Array = edges[edge_index]
		var start: Vector2 = surface_center + Vector2(edge[0])
		var finish: Vector2 = surface_center + Vector2(edge[1])
		var tangent: Vector2 = (finish - start).normalized()
		var inward: Vector2 = (surface_center - (start + finish) * 0.5).normalized()
		var salt: int = edge_index * 97
		# 波纹中心保持稳定，只沿岸线伸展、向水内涨起后退回；这样更像一次
		# 小潮汐呼吸，而不是短线沿菱形边机械滑动。
		var center_t: float = (
			0.28
			+ _shoreline_rand(seed, salt + 13) * 0.44
		)
		var center: Vector2 = start.lerp(finish, center_t)
		var phase: int = posmod(animation_step, SHORELINE_FRAME_COUNT)
		var tide: float = float(SHORELINE_TIDE_PHASES[phase])
		var fade: float = float(SHORELINE_TIDE_ALPHA_PHASES[phase])
		var half_length: float = lerpf(
			SHORELINE_HALF_LENGTH_MIN,
			SHORELINE_HALF_LENGTH_MAX,
			_shoreline_rand(seed, salt + 17)
		) * lerpf(0.68, 1.0, tide)
		var inset: float = 0.34 + tide * 1.72
		var bend: float = lerpf(
			0.42,
			0.88,
			_shoreline_rand(seed, salt + 23)
		) * lerpf(0.42, 1.0, tide)
		var shape_variant := mini(
			int(_shoreline_rand(seed, salt + 29) * 3.0),
			2
		)
		var shape_mirrored := _shoreline_rand(seed, salt + 31) < 0.5
		var segment_count := mini(
			SHORELINE_SEGMENT_COUNT_MIN
			+ int(
				_shoreline_rand(seed, salt + 37)
				* float(SHORELINE_SEGMENT_COUNT_MAX - SHORELINE_SEGMENT_COUNT_MIN + 1)
			),
			SHORELINE_SEGMENT_COUNT_MAX
		)
		var even_segments := PackedVector2Array()
		var odd_segments := PackedVector2Array()
		var slot_width := 2.0 / float(segment_count)
		for segment_index in segment_count:
			var segment_salt := salt + 101 + segment_index * 17
			var center_u := (
				-1.0
				+ (float(segment_index) + 0.5) * slot_width
				+ lerpf(
					-slot_width * 0.055,
					slot_width * 0.055,
					_shoreline_rand(seed, segment_salt)
				)
			)
			var half_segment_u := slot_width * lerpf(
				0.34,
				0.43,
				_shoreline_rand(seed, segment_salt + 3)
			)
			var group_inset := (
				0.0
				if segment_index % 2 == 0
				else lerpf(0.22, 0.68, tide)
			)
			var point_a := _shoreline_curve_point(
				center,
				tangent,
				inward,
				half_length,
				clampf(center_u - half_segment_u, -1.0, 1.0),
				inset + group_inset,
				bend,
				shape_variant,
				shape_mirrored
			)
			var point_b := _shoreline_curve_point(
				center,
				tangent,
				inward,
				half_length,
				clampf(center_u + half_segment_u, -1.0, 1.0),
				inset + group_inset,
				bend,
				shape_variant,
				shape_mirrored
			)
			if segment_index % 2 == 0:
				even_segments.append(point_a)
				even_segments.append(point_b)
			else:
				odd_segments.append(point_a)
				odd_segments.append(point_b)
		var even_color := SHORELINE_COLOR
		even_color.a *= fade * float(SHORELINE_EVEN_ALPHA_PHASES[phase])
		var odd_color := SHORELINE_COLOR
		odd_color.a *= fade * float(SHORELINE_ODD_ALPHA_PHASES[phase])
		# A/B 两组分别批绘。它们沿曲线天然错开一个槽位：A 退暗时 B
		# 变亮，位置会移动；绘制调用仍固定为每帧最多两次。
		if not even_segments.is_empty():
			draw_multiline(
				even_segments,
				even_color,
				SHORELINE_LINE_WIDTH,
				true
			)
		if not odd_segments.is_empty():
			draw_multiline(
				odd_segments,
				odd_color,
				SHORELINE_LINE_WIDTH,
				true
			)


func _shoreline_curve_point(
	center: Vector2,
	tangent: Vector2,
	inward: Vector2,
	half_length: float,
	normalized_position: float,
	inset: float,
	bend: float,
	shape_variant: int,
	mirrored: bool
) -> Vector2:
	var u := clampf(normalized_position, -1.0, 1.0)
	var base_curve := maxf(0.0, 1.0 - u * u)
	var curve_amount: float
	match shape_variant:
		1:
			var direction := -u if mirrored else u
			curve_amount = base_curve * (0.72 + direction * 0.28)
		2:
			# 宽而平缓的弧，与普通抛物线形成明显轮廓差异。
			curve_amount = pow(base_curve, 0.56) * 0.88
		_:
			curve_amount = base_curve
	return (
		center
		+ tangent * (half_length * u)
		+ inward * (inset + bend * curve_amount)
	)


func _shoreline_rand(seed: int, salt: int) -> float:
	var mixed := int(hash(Vector3i(seed, salt, seed ^ (salt * 31))))
	return float(mixed & 0xFFFF) / 65535.0


func _draw_water_ripples(surface_center: Vector2) -> void:
	for ripple in _water_ripples:
		var lifetime: float = ripple["lifetime"]
		var progress := clampf(float(ripple["age"]) / lifetime, 0.0, 1.0)
		var expansion := 1.0 - pow(1.0 - progress, 2.0)
		var fade := pow(1.0 - progress, 1.7) * float(ripple["strength"])
		var maximum_radius: float = ripple["maximum_radius"]
		var radius_x := lerpf(1.2, maximum_radius, expansion)
		var radius_y := radius_x * 0.46
		var center := surface_center + Vector2(ripple["offset"])
		var color := Color(0.72, 0.91, 1.0, fade * 0.68)
		if ripple["kind"] == &"snow":
			color = Color(0.91, 0.97, 1.0, fade * 0.36)
		_draw_ellipse(center, radius_x, radius_y, color, 0.72)

		# 第二道较淡的尾环让雨点命中不只是一个机械扩张圆。
		if progress > 0.18:
			var tail_progress := (progress - 0.18) / 0.82
			var tail_expansion := 1.0 - pow(1.0 - tail_progress, 2.0)
			var tail_radius_x := lerpf(0.8, maximum_radius * 0.72, tail_expansion)
			var tail_color := color
			tail_color.a *= (1.0 - tail_progress) * 0.52
			_draw_ellipse(
				center,
				tail_radius_x,
				tail_radius_x * 0.46,
				tail_color,
				0.58
			)

		if ripple["kind"] == &"rain" and progress < 0.12:
			var splash_height := (1.0 - progress / 0.12) * 3.5
			draw_line(
				center - Vector2(0.0, splash_height),
				center + Vector2(0.0, 0.4),
				Color(0.78, 0.94, 1.0, fade * 0.72),
				0.72,
				true
			)


func _draw_ellipse(
	center: Vector2,
	radius_x: float,
	radius_y: float,
	color: Color,
	width: float
) -> void:
	if radius_x <= 0.0 or radius_y <= 0.0:
		return
	# 使用 Canvas 变换把单个 draw_arc 压成椭圆，避免每圈、每帧分配
	# PackedVector2Array 并在 GDScript 中重复计算 sin/cos。
	draw_set_transform(center, 0.0, Vector2(1.0, radius_y / radius_x))
	draw_arc(Vector2.ZERO, radius_x, 0.0, TAU, RIPPLE_SEGMENTS, color, width, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
