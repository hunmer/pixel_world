## character_movement_fauna_streamer.gd — 测试场景的动物群落分帧扫描，保留原遍历顺序与生成规则。
class_name CharacterMovementFaunaStreamer
extends "res://scripts/world/fauna_streamer.gd"

var _incremental_enabled: bool = false
var _scan_active: bool = false
var _rescan_requested: bool = false
var _sources: Array = []
var _source_index: int = 0
var _source_ready: bool = false
var _minimum_bucket: Vector2i = Vector2i.ZERO
var _maximum_bucket: Vector2i = Vector2i.ZERO
var _next_bucket: Vector2i = Vector2i.ZERO


func set_incremental_enabled(enabled: bool) -> void:
	_incremental_enabled = enabled
	if not enabled:
		_scan_active = false
		_rescan_requested = false
		_sources.clear()
		_source_ready = false


func is_scan_active() -> bool:
	return _scan_active


func spawn_fauna_for_stream(
	stream_center: Vector2i,
	stream_extent_value: int,
	player_cell: Vector2i
) -> void:
	if not _incremental_enabled:
		_scan_active = false
		_rescan_requested = false
		super.spawn_fauna_for_stream(stream_center, stream_extent_value, player_cell)
		return
	sync_stream_frame(stream_center, stream_extent_value, player_cell)
	if _scan_active:
		_rescan_requested = true
	else:
		_begin_scan()


## 每帧只处理有限 bucket；新移动到来时完成当前快照后再扫最新窗口，避免饥饿。
func advance(
	stream_center: Vector2i,
	stream_extent_value: int,
	player_cell: Vector2i,
	bucket_budget: int
) -> int:
	if not _incremental_enabled or not _scan_active or bucket_budget <= 0:
		return 0
	sync_stream_frame(stream_center, stream_extent_value, player_cell)
	var processed := 0
	var guard := 0
	while processed < bucket_budget and guard < 4096:
		guard += 1
		if _source_index >= _sources.size():
			_scan_active = false
			if _rescan_requested:
				_begin_scan()
			break
		if not _source_ready and not _prepare_source():
			continue
		if _next_bucket.y > _maximum_bucket.y:
			_source_index += 1
			_source_ready = false
			continue
		var source: Dictionary = _sources[_source_index]
		_process_fauna_bucket(source, _next_bucket)
		processed += 1
		_next_bucket.x += 1
		if _next_bucket.x > _maximum_bucket.x:
			_next_bucket.x = _minimum_bucket.x
			_next_bucket.y += 1
	return processed


func _begin_scan() -> void:
	_sources = _community_runtime.fauna_sources()
	_source_index = 0
	_source_ready = false
	_rescan_requested = false
	_scan_active = true


func _prepare_source() -> bool:
	var source: Dictionary = _sources[_source_index]
	var ecosystem_id := String(source.get("source_biome_id", ""))
	var rule: Dictionary = source.get("rule", {})
	if ecosystem_id.is_empty() or rule.is_empty():
		_source_index += 1
		_source_ready = false
		return false
	var distribution: Dictionary = rule.get("distribution", {})
	var spacing := maxi(1, int(distribution.get("anchor_spacing", 1)))
	var radius := maxi(0, int(distribution.get("radius", 0)))
	_minimum_bucket = Vector2i(
		floori(float(_stream_center.x - _stream_extent - radius) / spacing),
		floori(float(_stream_center.y - _stream_extent - radius) / spacing)
	)
	_maximum_bucket = Vector2i(
		floori(float(_stream_center.x + _stream_extent + radius) / spacing),
		floori(float(_stream_center.y + _stream_extent + radius) / spacing)
	)
	_next_bucket = _minimum_bucket
	_source_ready = true
	return true


## 与 FaunaStreamer.spawn_fauna_for_stream 的单 bucket 分支逐项一致。
func _process_fauna_bucket(source: Dictionary, bucket: Vector2i) -> void:
	var ecosystem_id := String(source.get("source_biome_id", ""))
	var rule: Dictionary = source.get("rule", {})
	var distribution: Dictionary = rule.get("distribution", {})
	var generic_spawner := fauna_source_uses_generic_spawner(source)
	var anchor := (
		community_anchor_for_source(source, bucket)
		if generic_spawner
		else fauna_anchor_for_bucket(rule, bucket)
	)
	var group_id := animal_group_id(ecosystem_id, rule, bucket)
	if _animal_groups.has(group_id):
		restore_animal_group(group_id)
		return
	var radius := maxi(0, int(distribution.get("radius", 0)))
	var anchor_search_radius := int(distribution.get("anchor_search_radius", 0))
	if (
		not fauna_anchor_fully_loaded(anchor, radius + anchor_search_radius)
		or not _cells.has(anchor)
	):
		return
	if generic_spawner:
		create_first_class_animal_group(group_id, source, bucket)
		return
	var anchor_context = _cell_context_for_query.call(anchor)
	var anchor_q: int = anchor_context.height
	var anchor_landform := int(_landform_id_to_type.get(
		String(anchor_context.landform_id),
		EcosystemMatchScript.Landform.PLAINS
	))
	if not _community_runtime.fauna_source_matches_context(
		source,
		anchor_context,
		_ecology_near_tag
	):
		return
	var placement_seed := int(rule.get("placement_seed", 0))
	var chance: float = _ecology_chance.call(
		rule.get("chance", 0.0), anchor_landform, anchor_q
	)
	if _cell_rand.call(bucket, placement_seed + 3) >= chance:
		return
	var water_radius := int(distribution.get("requires_water_within", 0))
	if water_radius > 0 and not has_water_within(anchor, water_radius):
		return
	create_animal_group(
		group_id,
		ecosystem_id,
		rule,
		distribution,
		bucket,
		anchor,
		anchor_q,
		source
	)
