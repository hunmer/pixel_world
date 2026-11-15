## world_query_service.gd — 与流式生成顺序无关的世界空间查询。
##
## 从 main.gd 簇9 前段迁出的查询四件套（结构性拆分，行为不变）：
## cell_context_for_query（已生成格优先）、water_clearance、
## community_water_clearance_valid、ecology_near_tag（带缓存）。
## 只读取 CellContext，不依赖已生成节点，因而结果与生成先后无关。
class_name WorldQueryService
extends RefCounted

var _cell_states: Dictionary = {}
var _sample_cell_context: Callable
var _near_tag_cache := {}


## cell_states 为主场景的 _cell_states 字典引用（增删实时同步）；
## sample_cell_context 为未生成格的采样回调（main._sample_cell_context）。
func configure(cell_states: Dictionary, sample_cell_context: Callable) -> void:
	_cell_states = cell_states
	_sample_cell_context = sample_cell_context


func clear_caches() -> void:
	_near_tag_cache.clear()


func cell_context_for_query(cell: Vector2i):
	if _cell_states.has(cell):
		return _cell_states[cell].context
	return _sample_cell_context.call(cell)


## 水中格到最近陆地的曼哈顿安全层数。clearance=1 表示四个正交邻格
## 也全部是水，因此鱼的 32px 动画不会贴着岸线或半个身体压到泥地上。
func water_clearance(cell: Vector2i, maximum_radius: int) -> int:
	var center_context = cell_context_for_query(cell)
	if center_context == null or not center_context.is_water:
		return 0
	var scan_radius := maxi(0, maximum_radius)
	for distance in range(1, scan_radius + 1):
		for offset_y in range(-distance, distance + 1):
			var offset_x_abs := distance - absi(offset_y)
			var x_offsets := (
				[0]
				if offset_x_abs == 0
				else [-offset_x_abs, offset_x_abs]
			)
			for offset_x in x_offsets:
				var nearby = cell_context_for_query(
					cell + Vector2i(offset_x, offset_y)
				)
				if nearby == null or not nearby.is_water:
					return distance - 1
	return scan_radius


func community_water_clearance_valid(
	definition: Dictionary,
	context
) -> bool:
	var habitat_value: Variant = definition.get("habitat", {})
	if not habitat_value is Dictionary:
		return true
	var habitat: Dictionary = habitat_value
	var required_clearance := maxi(
		0,
		int(habitat.get("minimum_water_clearance", 0))
	)
	return (
		required_clearance <= 0
		or water_clearance(context.cell, required_clearance) >= required_clearance
	)


## Community habitat 的统一空间查询。它只读取 CellContext，不依赖已生成节点，
## 因而结果与流式生成顺序无关，火山/冰原等新模块也能直接查询自己的 tag。
func ecology_near_tag(context, tag: StringName, radius: float) -> bool:
	if context == null:
		return false
	var center: Vector2i = context.cell
	var scan_radius := maxi(0, ceili(radius))
	var cache_key := "%d/%d/%s/%d" % [
		center.x,
		center.y,
		tag,
		scan_radius,
	]
	if _near_tag_cache.has(cache_key):
		return bool(_near_tag_cache[cache_key])
	for offset_y in range(-scan_radius, scan_radius + 1):
		var row_radius := scan_radius - absi(offset_y)
		for offset_x in range(-row_radius, row_radius + 1):
			var nearby = cell_context_for_query(
				center + Vector2i(offset_x, offset_y)
			)
			if nearby.has_tag(tag):
				_near_tag_cache[cache_key] = true
				return true
	_near_tag_cache[cache_key] = false
	return false
