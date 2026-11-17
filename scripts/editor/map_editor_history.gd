## map_editor_history.gd — 地图编辑器历史时间线的纯逻辑内核
##
## 快照/等价比较/恢复/封存（游标数学：截断重做分支、超限淘汰最旧）。
## 只操作 Dictionary 模型，不持有节点；状态栏与列表回显留在 map_editor.gd 门面。

class_name MapEditorHistory
extends RefCounted


## 快照内容六件套（rows/units/props/tile_overrides/block_layout/buildings）+ 尺寸 + 标签。
static func snapshot(model: Dictionary, label: String = "") -> Dictionary:
	var units := []
	for u in model.units:
		units.append((u as Dictionary).duplicate())
	var props := []
	for p in model.get("props", []):
		props.append((p as Dictionary).duplicate())
	var buildings := []
	for b in model.get("buildings", []):
		buildings.append((b as Dictionary).duplicate())
	return {
		"rows": (model.rows as Array).duplicate(),
		"units": units,
		"props": props,
		"tile_overrides": (model.get("tile_overrides", {}) as Dictionary).duplicate(true),
		"block_layout": (model.get("block_layout", {}) as Dictionary).duplicate(true),
		"buildings": buildings,
		"width": int(model.width),
		"height": int(model.height),
		"label": label,
	}


## 等价比较仅看内容六件套（不含尺寸/标签）。
static func state_equal(snap: Dictionary, other: Dictionary) -> bool:
	return snap.rows == other.rows and snap.units == other.units \
		and snap.get("props", []) == other.get("props", []) \
		and snap.get("tile_overrides", {}) == other.get("tile_overrides", {}) \
		and snap.get("block_layout", {}) == other.get("block_layout", {}) \
		and snap.get("buildings", []) == other.get("buildings", [])


## 恢复快照到 model（从快照再深拷贝，栈内条目保持原样可重复恢复）。返回恢复后的尺寸。
static func restore_into(model: Dictionary, snap: Dictionary) -> Vector2i:
	model.rows = (snap.rows as Array).duplicate()
	var units := []
	for u in snap.units:
		units.append((u as Dictionary).duplicate())
	model.units = units
	var props := []
	for p in snap.get("props", []):
		props.append((p as Dictionary).duplicate())
	model.props = props
	var buildings := []
	for b in snap.get("buildings", []):
		buildings.append((b as Dictionary).duplicate())
	model["buildings"] = buildings
	model["tile_overrides"] = (snap.get("tile_overrides", {}) as Dictionary).duplicate(true)
	model["block_layout"] = (snap.get("block_layout", {}) as Dictionary).duplicate(true)
	model.width = int(snap.width)
	model.height = int(snap.height)
	return Vector2i(int(model.width), int(model.height))


## 封存 pending 动作（ed=编辑器实例）：清空 _pending_label；内容与游标条相同则不入史
## （越界/不可站人被拒）；新编辑截断重做分支；超过 UNDO_LIMIT+1 淘汰最旧。
## 返回 true=历史栈有变动（调用方需要 _refresh_history）。
static func seal(ed) -> bool:
	if ed._pending_label.is_empty() or ed._history.is_empty():
		return false
	var label: String = ed._pending_label
	ed._pending_label = ""
	var snap := snapshot(ed.model, label)
	if state_equal(snap, ed._history[ed._history_cursor]):
		return false
	ed._history.resize(ed._history_cursor + 1)
	ed._history.append(snap)
	ed._history_cursor += 1
	if ed._history.size() > ed.UNDO_LIMIT + 1:
		ed._history.pop_front()
		ed._history_cursor -= 1
	return true
