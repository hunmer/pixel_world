extends Node2D

## isometric_column_batch.gd — 等距地块柱的装配层。
##
## 一个地图格只对应一个 CanvasItem。父节点负责按格子脚点排序，这里按已经
## 排好的顺序一次画完整根地块柱，避免不同格的层互相穿插。
##
## 绘制决策拆至 scripts/iso/ 三个模块（本文件只保留状态与装配）：
##   isometric_column_texture_batch.gd — 网格批绘（ProjectedTerrainBatch）与 UV 常量
##   isometric_column_terrain_draw.gd  — 绘制计划构建/回放与动态遮挡即时绘制
##   isometric_column_shoreline.gd     — 岸线白浪与水面涟漪的绘制命令
## 遮挡透明/剖面状态机与水波节流状态留在本文件（对外 API 与契约依赖）。

const ColumnTextureBatch = preload("res://scripts/iso/isometric_column_texture_batch.gd")
const ColumnTerrainDraw = preload("res://scripts/iso/isometric_column_terrain_draw.gd")
const ColumnShoreline = preload("res://scripts/iso/isometric_column_shoreline.gd")

const PROJECTED_TERRAIN_SHADER = preload("res://shaders/isometric_terrain_rotate.gdshader")

const WATER_SURFACE_VISUAL_OFFSET := Vector2(0.0, -2.0)
const MAX_WATER_RIPPLES := 4
const RIPPLE_REDRAW_INTERVAL := 1.0 / 30.0
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

# 以下常量的规范定义在绘制模块里，这里保留同名别名供既有调用方与契约使用。
const TOP_UV: Array = ColumnTextureBatch.TOP_UV
const RIGHT_SIDE_UV: Array = ColumnTextureBatch.RIGHT_SIDE_UV
const LEFT_SIDE_UV: Array = ColumnTextureBatch.LEFT_SIDE_UV
const SHORELINE_FRAME_COUNT: int = ColumnShoreline.SHORELINE_FRAME_COUNT
const SHORELINE_FRAME_SECONDS: float = ColumnShoreline.SHORELINE_FRAME_SECONDS
const SHORELINE_COLOR: Color = ColumnShoreline.SHORELINE_COLOR
const SHORELINE_LINE_WIDTH: float = ColumnShoreline.SHORELINE_LINE_WIDTH
const SHORELINE_EDGE_COVERAGE: float = ColumnShoreline.SHORELINE_EDGE_COVERAGE
const SHORELINE_HALF_LENGTH_MIN: float = ColumnShoreline.SHORELINE_HALF_LENGTH_MIN
const SHORELINE_HALF_LENGTH_MAX: float = ColumnShoreline.SHORELINE_HALF_LENGTH_MAX
const SHORELINE_TIDE_PHASES: Array = ColumnShoreline.SHORELINE_TIDE_PHASES
const SHORELINE_TIDE_ALPHA_PHASES: Array = ColumnShoreline.SHORELINE_TIDE_ALPHA_PHASES
const SHORELINE_EVEN_ALPHA_PHASES: Array = ColumnShoreline.SHORELINE_EVEN_ALPHA_PHASES
const SHORELINE_ODD_ALPHA_PHASES: Array = ColumnShoreline.SHORELINE_ODD_ALPHA_PHASES
const SHORELINE_SEGMENT_COUNT_MIN: int = ColumnShoreline.SHORELINE_SEGMENT_COUNT_MIN
const SHORELINE_SEGMENT_COUNT_MAX: int = ColumnShoreline.SHORELINE_SEGMENT_COUNT_MAX
const RIPPLE_SEGMENTS: int = ColumnShoreline.RIPPLE_SEGMENTS

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
var _draw_context_cache := {}


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
	_draw_context_cache = {}
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


func set_rotation_draw_culling(active: bool, draw_visible: bool) -> void:
	if _rotation_cull_active == active and _rotation_draw_visible == draw_visible:
		return
	_rotation_cull_active = active
	_rotation_draw_visible = draw_visible
	queue_redraw()


## 绘制上下文：把绘制模块需要的投影/几何状态打包，configure 与视角更新时失效。
func _draw_context() -> Dictionary:
	if not _draw_context_cache.is_empty():
		return _draw_context_cache
	_draw_context_cache = {
		"level_height": _level_height,
		"screen_y_offset": _screen_y_offset,
		"terrain_top_level": _terrain_top_level,
		"x_positive": _basis_x.y >= 0.0,
		"y_positive": _basis_y.y >= 0.0,
		"default_projection": _is_default_projection(),
		"top_center_offset": TOP_CENTER_OFFSET,
		"default_basis_x": DEFAULT_BASIS_X,
		"default_basis_y": DEFAULT_BASIS_Y,
		"side_exposed": Callable(self, "_is_side_exposed"),
		"top_corners": Callable(self, "_terrain_top_corners"),
		"water_effects": Callable(self, "_draw_water_effects"),
		"texture_mask": Callable(self, "_texture_alpha_mask"),
		"cutaway_shade_color": PLAYER_CUTAWAY_SHADE_COLOR,
	}
	return _draw_context_cache


func _occlusion_state_active() -> bool:
	return not (
		_block_occlusion_alphas.is_empty()
		and _block_occlusion_targets.is_empty()
		and _block_cutaway_shades.is_empty()
		and _block_cutaway_shade_targets.is_empty()
	)


func _build_projected_draw_plan(sector: int) -> Array:
	return ColumnTerrainDraw.build_draw_plan(
		_blocks,
		sector,
		_projected_mesh_cache,
		_draw_context()
	)


## 水面特效回调：岸线白浪（含 animation slice 相位）+ 雨雪涟漪。
func _draw_water_effects(center: Vector2, block: Dictionary) -> void:
	ColumnShoreline.draw_foam(
		self,
		center,
		int(block.get("shore_edges", 0)),
		int(block.get("shore_seed", 0)),
		_terrain_top_corners(center)
	)
	ColumnShoreline.draw_water_ripples(
		self,
		_water_ripples,
		center + WATER_SURFACE_VISUAL_OFFSET
	)


func _draw() -> void:
	if _rotation_cull_active and not _rotation_draw_visible:
		return
	var sector := (1 if _basis_x.y < 0.0 else 0) | (2 if _basis_y.y < 0.0 else 0)
	if _occlusion_state_active():
		ColumnTerrainDraw.draw_dynamic_column(
			self,
			_blocks,
			sector,
			_projected_mesh_cache,
			_block_occlusion_alphas,
			_block_cutaway_shades,
			_draw_context()
		)
		return
	if not _projected_draw_plan_cache.has(sector):
		_projected_draw_plan_cache[sector] = _build_projected_draw_plan(sector)
	ColumnTerrainDraw.draw_cached_plan(
		self,
		_projected_draw_plan_cache[sector],
		_blocks,
		_draw_context()
	)


## 以下两个方法保留在节点上供契约与调试直接调用，实现在岸线绘制模块。
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
	return ColumnShoreline.curve_point(
		center,
		tangent,
		inward,
		half_length,
		normalized_position,
		inset,
		bend,
		shape_variant,
		mirrored
	)


func _shoreline_rand(seed: int, salt: int) -> float:
	return ColumnShoreline.rand(seed, salt)
