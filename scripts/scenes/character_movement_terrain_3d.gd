## character_movement_terrain_3d.gd — 测试场景专用：把流式边缘的 chunk 重建摊到连续帧
extends "res://scripts/iso/isometric_terrain_3d.gd"

const DEFAULT_FLUSH_BUDGET_USEC := 8000
const MAX_CHUNKS_PER_FLUSH := 12

var _incremental_flush_enabled: bool = false
var _flush_budget_usec: int = DEFAULT_FLUSH_BUDGET_USEC
var _last_flush_frame: int = -1


## 初次生成仍同步完成；进入测试场景后才启用分帧，避免出生点缺地形。
func set_incremental_flush(enabled: bool, budget_usec: int = DEFAULT_FLUSH_BUDGET_USEC) -> void:
	_incremental_flush_enabled = enabled
	_flush_budget_usec = maxi(1, budget_usec)
	_last_flush_frame = -1


func pending_chunk_count() -> int:
	return _dirty_chunks.size()


func clear() -> void:
	_incremental_flush_enabled = false
	_last_flush_frame = -1
	super.clear()


## 数据仍由原 set_cell/remove_cell 同步更新；这里只延后视觉 chunk 合批。
## 父世界显式 flush 与 Terrain._process 可能同帧各调一次，本类每帧只提交一个预算。
func flush() -> int:
	if not _incremental_flush_enabled:
		return super.flush()
	if _dirty_chunks.is_empty():
		return 0
	var frame := Engine.get_process_frames()
	if _last_flush_frame == frame:
		return 0
	_last_flush_frame = frame
	var started := Time.get_ticks_usec()
	var rebuilt := 0
	for chunk_value in _dirty_chunks.keys():
		if rebuilt > 0 and (
			rebuilt >= MAX_CHUNKS_PER_FLUSH
			or Time.get_ticks_usec() - started >= _flush_budget_usec
		):
			break
		_dirty_chunks.erase(chunk_value)
		_rebuild_chunk(chunk_value as Vector2i)
		rebuilt += 1
	_last_build_ms = float(Time.get_ticks_usec() - started) / 1000.0
	return rebuilt
