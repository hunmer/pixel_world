extends Node2D

## 一个地图格只对应一个 CanvasItem。父节点负责按格子脚点排序，
## 这里按已经排好的顺序一次画完整根地块柱，避免不同格的层互相穿插。

var _blocks: Array[Dictionary] = []
var _cell := Vector2i.ZERO
var _screen_y_offset := 0.0
var _level_height := 8.0
var _basis_x := Vector2(16.0, 8.0)
var _basis_y := Vector2(-16.0, 8.0)
var _neighbor_stand_level_fn: Callable = Callable()
var _terrain_top_level := -1
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
var _occluder_bounds_dirty := true
var _has_occluder_content := false
var _occluder_broadphase_radius := 0.0
static var _texture_image_cache: Dictionary = {}
static var _texture_alpha_mask_cache: Dictionary = {}
static var _projected_terrain_material: ShaderMaterial
static var _projected_shader_angle := 0.0
var _projected_mesh_cache: Dictionary = {}
var _projected_draw_plan_cache: Dictionary = {}
var _projected_sector := -1
var _draw_cull_rect := Rect2()
var _rotation_cull_active := false
var _rotation_draw_visible := true

const PROJECTED_TERRAIN_SHADER = preload("res://shaders/isometric_terrain_rotate.gdshader")

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
const DEFAULT_BASIS_X := Vector2(16.0, 8.0)
const DEFAULT_BASIS_Y := Vector2(-16.0, 8.0)
const TOP_CENTER_OFFSET := Vector2(0.0, -2.0)
const TOP_UV := [
	Vector2(16.0, 6.0),
	Vector2(32.0, 14.0),
	Vector2(16.0, 22.0),
	Vector2(0.0, 14.0),
]
const RIGHT_SIDE_UV := [
	Vector2(32.0, 14.0),
	Vector2(16.0, 22.0),
	Vector2(16.0, 32.0),
	Vector2(32.0, 24.0),
]
const LEFT_SIDE_UV := [
	Vector2(0.0, 14.0),
	Vector2(16.0, 22.0),
	Vector2(16.0, 32.0),
	Vector2(0.0, 24.0),
]


func configure(
	cell: Vector2i,
	blocks: Array[Dictionary],
	screen_position: Vector2,
	sort_y: float,
	level_height: float,
	basis_x := DEFAULT_BASIS_X,
	basis_y := DEFAULT_BASIS_Y,
	neighbor_stand_level_fn: Callable = Callable()
) -> void:
	name = "Column_%d_%d" % [cell.x, cell.y]
	_cell = cell
	_blocks = blocks
	_neighbor_stand_level_fn = neighbor_stand_level_fn
	_terrain_top_level = -1
	for block in _blocks:
		if (
			block.get("occluder_class", &"") == OCCLUDER_TERRAIN
			and block.get("water_part", &"") == &""
		):
			_terrain_top_level = maxi(_terrain_top_level, int(block["level"]))
	_projected_mesh_cache.clear()
	_projected_draw_plan_cache.clear()
	_projected_sector = -1
	_has_occluder_content = false
	_occluder_broadphase_radius = 0.0
	_occluder_bounds_dirty = true
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
	for block_value in _blocks:
		var configured_block: Dictionary = block_value
		var occluder_class: StringName = configured_block.get("occluder_class", &"")
		if occluder_class != OCCLUDER_TERRAIN and occluder_class != OCCLUDER_PROP:
			continue
		_has_occluder_content = true
		var texture: Texture2D = configured_block["texture"]
		_occluder_broadphase_radius = maxf(
			_occluder_broadphase_radius,
			float(configured_block["level"]) * _level_height + texture.get_size().length()
		)
	var tint := self_modulate
	tint.a = 1.0
	self_modulate = tint
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 岸线循环由 RenderingServer 的 animation slice 驱动，不让每个岸线格
	# 都进入 _process()。这里只有短生命周期的雨雪水波需要 CPU 更新。
	set_process(not _water_ripples.is_empty())
	update_sort_position(screen_position, sort_y, basis_x, basis_y)


func update_sort_position(
	screen_position: Vector2,
	sort_y: float,
	basis_x := DEFAULT_BASIS_X,
	basis_y := DEFAULT_BASIS_Y
) -> void:
	# 节点原点承载合成的 Y-sort 深度；局部绘制偏移把像素补偿回真实投影位置。
	position = Vector2(screen_position.x, sort_y)
	_screen_y_offset = screen_position.y - sort_y
	_basis_x = basis_x
	_basis_y = basis_y
	_projected_sector = (1 if _basis_x.y < 0.0 else 0) | (2 if _basis_y.y < 0.0 else 0)
	_occluder_bounds_dirty = true
	_update_draw_cull_rect()
	if _rotation_cull_active and not _rotation_draw_visible:
		return
	var terrain_material := _get_projected_terrain_material()
	material = terrain_material
	var view_angle := _basis_x.angle() - DEFAULT_BASIS_X.angle()
	if not is_equal_approx(_projected_shader_angle, view_angle):
		terrain_material.set_shader_parameter("view_angle", view_angle)
		_projected_shader_angle = view_angle
	queue_redraw()


## draw_mesh 的显式偏移不参与自动视口剔除；节点原点又是合成后的 sort_y，
## 因此必须显式提供覆盖真实本地绘制内容的矩形。
func _update_draw_cull_rect() -> void:
	_draw_cull_rect = Rect2()
	for index in _blocks.size():
		var block_rect := _block_visual_rect(_blocks[index])
		block_rect.position -= position
		_draw_cull_rect = block_rect if index == 0 else _draw_cull_rect.merge(block_rect)
	RenderingServer.canvas_item_set_custom_rect(
		get_canvas_item(),
		not _blocks.is_empty(),
		_draw_cull_rect
	)


static func _get_projected_terrain_material() -> ShaderMaterial:
	if _projected_terrain_material == null:
		_projected_terrain_material = ShaderMaterial.new()
		_projected_terrain_material.shader = PROJECTED_TERRAIN_SHADER
	return _projected_terrain_material


func _is_projected_terrain(block: Dictionary) -> bool:
	return (
		block.get("occluder_class", &"") == OCCLUDER_TERRAIN
		or block.get("water_part", &"") != &""
	)


## 地块 level L 的侧面若已有同层或更高邻格，就是柱体内部面，不能绘制。
## 只在当前朝向的两个侧面调用；边界与真正的高差仍保留完整侧壁。
func _is_side_exposed(axis: int, positive: bool, level: int) -> bool:
	if not _neighbor_stand_level_fn.is_valid():
		return true
	var direction := Vector2i.ZERO
	if axis == 0:
		direction = Vector2i(1 if positive else -1, 0)
	else:
		direction = Vector2i(0, 1 if positive else -1)
	var neighbor_level := int(_neighbor_stand_level_fn.call(_cell + direction))
	return neighbor_level < level


func _is_default_projection() -> bool:
	return _basis_x.is_equal_approx(DEFAULT_BASIS_X) and _basis_y.is_equal_approx(DEFAULT_BASIS_Y)


## 柱内较低方块的顶面被同柱上层占据，不属于可见表面。
## 水面是独立透明表层；湖床顶面仍保留以透过水体显示。
func _is_visible_top(water_part: StringName, level: int) -> bool:
	if water_part == &"surface":
		return true
	return water_part == &"" and level == _terrain_top_level


## 顶面四角顺序固定为上、右、下、左；旋转只改变地面基向量，高度不旋转。
func _terrain_top_corners(center: Vector2) -> PackedVector2Array:
	var top_center := center + TOP_CENTER_OFFSET
	var half_x := _basis_x * 0.5
	var half_y := _basis_y * 0.5
	return PackedVector2Array([
		top_center - half_x - half_y,
		top_center + half_x - half_y,
		top_center + half_x + half_y,
		top_center - half_x + half_y,
	])


func _block_visual_rect(block: Dictionary) -> Rect2:
	var texture: Texture2D = block["texture"]
	var center := position + Vector2(
		0.0,
		_screen_y_offset - float(block["level"]) * _level_height
	) + Vector2(block["render_offset"])
	if _is_projected_terrain(block) and not _is_default_projection():
		var extents := (_basis_x.abs() + _basis_y.abs()) * 0.5
		var top_center := center + TOP_CENTER_OFFSET
		return Rect2(
			top_center - extents,
			extents * 2.0 + Vector2(0.0, _level_height)
		)
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
	_occluder_bounds_dirty = false
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
	if not _has_occluder_content:
		return result
	if _occluder_bounds_dirty:
		var column_center := position + Vector2(0.0, _screen_y_offset)
		if not player_rect.grow(_occluder_broadphase_radius).has_point(column_center):
			return result
		_rebuild_occluder_visual_bounds()
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


## 将连续、同贴图且同色调的投影面合并为三角形网格，避免逐面 draw_polygon
## 在完整地图旋转时产生数万次 CanvasItem 绘制调用。
class ProjectedTerrainBatch:
	var texture: Texture2D
	var water_part: StringName = &""
	var tint := Color.WHITE
	var start_index := -1
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var customs := PackedColorArray()
	var colors := PackedColorArray()

	func matches(next_texture: Texture2D, next_part: StringName, next_tint: Color) -> bool:
		return (
			start_index >= 0
			and texture == next_texture
			and water_part == next_part
			and tint.is_equal_approx(next_tint)
		)

	func begin(
		next_texture: Texture2D,
		next_part: StringName,
		next_tint: Color,
		block_index: int
	) -> void:
		texture = next_texture
		water_part = next_part
		tint = next_tint
		start_index = block_index

	func append_quad(points: PackedVector2Array, quad_uvs: Array, center: Vector2) -> void:
		for vertex_index in [0, 1, 2, 0, 2, 3]:
			vertices.append(points[vertex_index])
			uvs.append(quad_uvs[vertex_index])
			var vertical := maxf(float(quad_uvs[vertex_index].y) - 22.0, 0.0)
			customs.append(Color(center.x, center.y, 1.0, vertical))
			colors.append(tint)

	func append_side(
		corners: PackedVector2Array,
		axis: int,
		positive: bool,
		level_height: float,
		center: Vector2
	) -> void:
		var first := 0
		var second := 0
		var quad_uvs: Array = []
		if axis == 0:
			first = 1 if positive else 0
			second = 2 if positive else 3
			quad_uvs = RIGHT_SIDE_UV
		else:
			first = 3 if positive else 0
			second = 2 if positive else 1
			quad_uvs = LEFT_SIDE_UV
		var down := Vector2(0.0, level_height)
		append_quad(
			PackedVector2Array([
				corners[first],
				corners[second],
				corners[second] + down,
				corners[first] + down,
			]),
			quad_uvs,
			center
		)

	func commit(mesh_cache: Dictionary, sector: int, end_index: int) -> ArrayMesh:
		if start_index < 0 or vertices.is_empty():
			start_index = -1
			return null
		var cache_key := "%d:%d:%d:%d:%s" % [
			start_index,
			end_index,
			sector,
			texture.get_instance_id(),
			str(tint),
		]
		var mesh: ArrayMesh = mesh_cache.get(cache_key)
		if mesh == null:
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surface.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
			var texture_size := texture.get_size()
			for vertex_index in vertices.size():
				# draw_polygon 接受像素 UV，但 draw_mesh/ArrayMesh 必须使用归一化 UV。
				surface.set_uv(uvs[vertex_index] / texture_size)
				surface.set_color(colors[vertex_index])
				surface.set_custom(0, customs[vertex_index])
				var point := vertices[vertex_index]
				surface.add_vertex(Vector3(point.x, point.y, 0.0))
			mesh = surface.commit()
			mesh_cache[cache_key] = mesh
		start_index = -1
		vertices = PackedVector2Array()
		uvs = PackedVector2Array()
		customs = PackedColorArray()
		colors = PackedColorArray()
		return mesh

	func flush(
		canvas: CanvasItem,
		mesh_cache: Dictionary,
		sector: int,
		end_index: int,
		screen_y_offset: float
	) -> void:
		var mesh := commit(mesh_cache, sector, end_index)
		if mesh == null:
			return
		# draw_mesh 必须在 identity Canvas transform 下记录，否则 custom rect
		# 仍无法纠正 Y-sort 原点造成的视口剔除；Y 偏移只走显式 transform。
		canvas.draw_set_transform(Vector2.ZERO)
		canvas.draw_mesh(
			mesh,
			texture,
			Transform2D(0.0, Vector2(0.0, screen_y_offset))
		)
		canvas.draw_set_transform(Vector2(0.0, screen_y_offset))


func _draw_textured_quad(
	points: PackedVector2Array,
	uvs: Array,
	texture: Texture2D,
	tint: Color
) -> void:
	draw_polygon(
		points,
		PackedColorArray([tint, tint, tint, tint]),
		PackedVector2Array(uvs),
		texture
	)


func _draw_terrain_side(
	texture: Texture2D,
	corners: PackedVector2Array,
	axis: int,
	positive: bool,
	tint: Color
) -> void:
	var first := 0
	var second := 0
	var uvs: Array = []
	if axis == 0:
		first = 1 if positive else 0
		second = 2 if positive else 3
		uvs = RIGHT_SIDE_UV
	else:
		first = 3 if positive else 0
		second = 2 if positive else 1
		uvs = LEFT_SIDE_UV
	var down := Vector2(0.0, _level_height)
	_draw_textured_quad(
		PackedVector2Array([
			corners[first],
			corners[second],
			corners[second] + down,
			corners[first] + down,
		]),
		uvs,
		texture,
		tint
	)


## 实心地形的源贴图只带默认视角的两侧；转到背面时复用对应材质，
## 但按当前视角只画朝向镜头的两侧。平地内部侧面由前排顶面覆盖。
func _draw_projected_terrain(
	texture: Texture2D,
	center: Vector2,
	tint: Color,
	water_part: StringName,
	level: int
) -> void:
	var corners := _terrain_top_corners(center)
	if water_part != &"surface":
		if water_part == &"":
			_draw_terrain_side(texture, corners, 0, _basis_x.y >= 0.0, tint)
			_draw_terrain_side(texture, corners, 1, _basis_y.y >= 0.0, tint)
		elif water_part == &"right_side" and _basis_x.y >= 0.0:
			_draw_terrain_side(texture, corners, 0, true, tint)
		elif water_part == &"right_side_opposite" and _basis_x.y < 0.0:
			_draw_terrain_side(texture, corners, 0, false, tint)
		elif water_part == &"left_side" and _basis_y.y >= 0.0:
			_draw_terrain_side(texture, corners, 1, true, tint)
		elif water_part == &"left_side_opposite" and _basis_y.y < 0.0:
			_draw_terrain_side(texture, corners, 1, false, tint)
	if _is_visible_top(water_part, level):
		_draw_textured_quad(corners, TOP_UV, texture, tint)


func _append_batch_terrain(
	batch: ProjectedTerrainBatch,
	corners: PackedVector2Array,
	water_part: StringName,
	center: Vector2,
	level: int
) -> void:
	if water_part != &"surface":
		if water_part == &"":
			var x_positive := _basis_x.y >= 0.0
			var y_positive := _basis_y.y >= 0.0
			if _is_side_exposed(0, x_positive, level):
				batch.append_side(corners, 0, x_positive, _level_height, center)
			if _is_side_exposed(1, y_positive, level):
				batch.append_side(corners, 1, y_positive, _level_height, center)
		elif (
			water_part == &"right_side" and _basis_x.y >= 0.0
			and _is_side_exposed(0, true, level)
		):
			batch.append_side(corners, 0, true, _level_height, center)
		elif (
			water_part == &"right_side_opposite" and _basis_x.y < 0.0
			and _is_side_exposed(0, false, level)
		):
			batch.append_side(corners, 0, false, _level_height, center)
		elif (
			water_part == &"left_side" and _basis_y.y >= 0.0
			and _is_side_exposed(1, true, level)
		):
			batch.append_side(corners, 1, true, _level_height, center)
		elif (
			water_part == &"left_side_opposite" and _basis_y.y < 0.0
			and _is_side_exposed(1, false, level)
		):
			batch.append_side(corners, 1, false, _level_height, center)
	if _is_visible_top(water_part, level):
		batch.append_quad(corners, TOP_UV, center)


func _commit_draw_plan_batch(
	batch: ProjectedTerrainBatch,
	plan: Array,
	sector: int,
	end_index: int
) -> void:
	var mesh := batch.commit(_projected_mesh_cache, sector, end_index)
	if mesh != null:
		plan.append({"kind": &"mesh", "mesh": mesh, "texture": batch.texture})


## 普通柱没有动态遮挡时，把每帧绘制退化为遍历已缓存命令。网格顶点、UV、
## CUSTOM0 与色调只在首次遇到某个朝向扇区时生成，连续旋转不再逐顶点重建。
func _build_projected_draw_plan(sector: int) -> Array:
	var plan: Array = []
	var batch := ProjectedTerrainBatch.new()
	for index in _blocks.size():
		var block: Dictionary = _blocks[index]
		var level := int(block["level"])
		var texture: Texture2D = block["texture"]
		var water_part: StringName = block.get("water_part", &"")
		var draw_modulate: Color = block["modulate"]
		var projected := _is_projected_terrain(block) and (
			not _is_default_projection() or (water_part != &"" and water_part != &"surface")
		)
		if projected:
			if not batch.matches(texture, water_part, draw_modulate):
				_commit_draw_plan_batch(batch, plan, sector, index - 1)
				batch.begin(texture, water_part, draw_modulate, index)
			var center := (
				Vector2(0.0, -level * _level_height)
				+ Vector2(block["render_offset"])
				+ TOP_CENTER_OFFSET
			)
			var half_x := DEFAULT_BASIS_X * 0.5
			var half_y := DEFAULT_BASIS_Y * 0.5
			var corners := PackedVector2Array([
				center - half_x - half_y,
				center + half_x - half_y,
				center + half_x + half_y,
				center - half_x + half_y,
			])
			_append_batch_terrain(batch, corners, water_part, center, level)
		else:
			_commit_draw_plan_batch(batch, plan, sector, index - 1)
			plan.append({"kind": &"texture", "index": index})
		if water_part == &"surface":
			_commit_draw_plan_batch(batch, plan, sector, index)
			plan.append({"kind": &"water_effects", "index": index})
	_commit_draw_plan_batch(batch, plan, sector, _blocks.size() - 1)
	return plan


func _draw_cached_plan(plan: Array) -> void:
	draw_set_transform(Vector2(0, _screen_y_offset))
	for item_value in plan:
		var item: Dictionary = item_value
		var kind: StringName = item["kind"]
		if kind == &"mesh":
			# 与动态遮挡路径一致：mesh 记录时保持 identity，避免绕过 custom rect。
			draw_set_transform(Vector2.ZERO)
			draw_mesh(
				item["mesh"],
				item["texture"],
				Transform2D(0.0, Vector2(0.0, _screen_y_offset))
			)
			draw_set_transform(Vector2(0, _screen_y_offset))
			continue
		var block: Dictionary = _blocks[int(item["index"])]
		var center := Vector2(
			0.0,
			-int(block["level"]) * _level_height
		) + Vector2(block["render_offset"])
		if kind == &"texture":
			var texture: Texture2D = block["texture"]
			draw_texture(texture, center - texture.get_size() * 0.5, block["modulate"])
		else:
			_draw_shoreline_foam(
				center,
				int(block.get("shore_edges", 0)),
				int(block.get("shore_seed", 0))
			)
			_draw_water_ripples(center + WATER_SURFACE_VISUAL_OFFSET)
	draw_set_transform(Vector2.ZERO)


func set_rotation_draw_culling(active: bool, draw_visible: bool) -> void:
	if _rotation_cull_active == active and _rotation_draw_visible == draw_visible:
		return
	_rotation_cull_active = active
	_rotation_draw_visible = draw_visible
	queue_redraw()


func _draw() -> void:
	if _rotation_cull_active and not _rotation_draw_visible:
		return
	var sector := (1 if _basis_x.y < 0.0 else 0) | (2 if _basis_y.y < 0.0 else 0)
	if (
		_block_occlusion_alphas.is_empty()
		and _block_occlusion_targets.is_empty()
		and _block_cutaway_shades.is_empty()
		and _block_cutaway_shade_targets.is_empty()
	):
		if not _projected_draw_plan_cache.has(sector):
			_projected_draw_plan_cache[sector] = _build_projected_draw_plan(sector)
		_draw_cached_plan(_projected_draw_plan_cache[sector])
		return
	draw_set_transform(Vector2(0, _screen_y_offset))
	var projected_batch := ProjectedTerrainBatch.new()
	for index in _blocks.size():
		var block: Dictionary = _blocks[index]
		var level: int = block["level"]
		var texture: Texture2D = block["texture"]
		var center := Vector2(
			0.0,
			-level * _level_height
		) + Vector2(block["render_offset"])
		var draw_modulate: Color = block["modulate"]
		draw_modulate.a *= float(_block_occlusion_alphas.get(index, 1.0))
		var draw_position := center - texture.get_size() * 0.5
		var water_part: StringName = block.get("water_part", &"")
		var cutaway_shade := float(_block_cutaway_shades.get(index, 0.0))
		var projected_terrain := _is_projected_terrain(block) and (
			not _is_default_projection() or (water_part != &"" and water_part != &"surface")
		)
		var can_batch := projected_terrain and cutaway_shade <= 0.0 and draw_modulate.a >= 0.999
		if can_batch:
			if not projected_batch.matches(texture, water_part, draw_modulate):
				projected_batch.flush(self, _projected_mesh_cache, sector, index - 1, _screen_y_offset)
				projected_batch.begin(texture, water_part, draw_modulate, index)
			var batch_center := (
				Vector2(0.0, -level * _level_height)
				+ Vector2(block["render_offset"])
				+ TOP_CENTER_OFFSET
			)
			var half_x := DEFAULT_BASIS_X * 0.5
			var half_y := DEFAULT_BASIS_Y * 0.5
			var corners := PackedVector2Array([
				batch_center - half_x - half_y,
				batch_center + half_x - half_y,
				batch_center + half_x + half_y,
				batch_center - half_x + half_y,
			])
			_append_batch_terrain(projected_batch, corners, water_part, batch_center, level)
		else:
			projected_batch.flush(self, _projected_mesh_cache, sector, index - 1, _screen_y_offset)
			if projected_terrain:
				_draw_projected_terrain(texture, center, draw_modulate, water_part, level)
			else:
				draw_texture(
					texture,
					draw_position,
					draw_modulate
				)
		if cutaway_shade > 0.0:
			# 白色 alpha mask 让深灰以真实颜色覆盖，而不是简单乘暗后仍偏绿/偏棕。
			# 保留一部分原贴图，形成可辨认材质的深灰不可通行剖面。
			var shade_color := PLAYER_CUTAWAY_SHADE_COLOR
			shade_color.a = cutaway_shade * draw_modulate.a
			if projected_terrain:
				_draw_projected_terrain(
					_texture_alpha_mask(texture),
					center,
					shade_color,
					water_part,
					level
				)
			else:
				draw_texture(
					_texture_alpha_mask(texture),
					draw_position,
					shade_color
				)
		if water_part == &"surface":
			projected_batch.flush(self, _projected_mesh_cache, sector, index, _screen_y_offset)
			_draw_shoreline_foam(
				center,
				int(block.get("shore_edges", 0)),
				int(block.get("shore_seed", 0))
			)
			_draw_water_ripples(center + WATER_SURFACE_VISUAL_OFFSET)
	projected_batch.flush(self, _projected_mesh_cache, sector, _blocks.size() - 1, _screen_y_offset)
	draw_set_transform(Vector2.ZERO)


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
	var corners := _terrain_top_corners(surface_center)
	var vertices := [
		corners[3],
		corners[0],
		corners[1],
		corners[2],
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
	var y_offset := Vector2.ZERO
	draw_set_transform(center, 0.0, Vector2(1.0, radius_y / radius_x))
	draw_arc(Vector2.ZERO, radius_x, 0.0, TAU, RIPPLE_SEGMENTS, color, width, true)
	draw_set_transform(y_offset, 0.0, Vector2.ONE)
