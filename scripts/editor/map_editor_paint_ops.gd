## map_editor_paint_ops.gd — 地图编辑器笔刷/填充/替换的纯模型内核
##
## 地形洪水填充、素材洪水填充、区域（体积）填充、条件替换、取格编码。
## 只操作 Dictionary 模型，不触碰 UI；画布刷新/状态栏/L1 埋点留在 map_editor.gd 门面。

class_name MapEditorPaintOps
extends RefCounted

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")


## 取格编码：素材覆盖优先 "asset:<id>"，否则 "terrain:<glyph>"；越界返回 ""。
static func code_at(model: Dictionary, cell: Vector2i) -> String:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(model.width) or cell.y >= int(model.height):
		return ""
	var aid := BattlefieldDocScript.tile_override_at(model, cell)
	if not aid.is_empty():
		return "asset:%s" % aid
	return "terrain:%s" % String((model.rows[cell.y] as String).substr(cell.x, 1))


## 地形洪水填充：同图例连通区域 -> 目标地形，并清掉覆盖格的素材地块覆盖。
## 返回填充格数；0 = 无可做（越界，或地形未变且无覆盖），调用方不应刷新/报状态。
static func flood_fill_terrain(model: Dictionary, cell: Vector2i, terrain: StringName) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= model.width or cell.y >= model.height:
		return 0
	var rows: Array = model.rows
	var from: String = (rows[cell.y] as String).substr(cell.x, 1)
	var to: String = String(BattlefieldDocScript.TERRAIN_GLYPH.get(terrain, "."))
	if from == to and (model.get("tile_overrides", {}) as Dictionary).is_empty():
		return 0  # 地形未变且无素材覆盖：无可做；有覆盖时要继续走完以便清 override
	var stack: Array[Vector2i] = [cell]
	var seen := { cell: true }
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		rows[c.y] = (rows[c.y] as String).substr(0, c.x) + to + (rows[c.y] as String).substr(c.x + 1)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= model.width or n.y >= model.height or seen.has(n):
				continue
			if (rows[n.y] as String).substr(n.x, 1) == from:
				seen[n] = true
				stack.append(n)
	# 填充经过的格子一并清素材地块覆盖，否则 override 优先整图替换、内置填充看不见
	if not (model.get("tile_overrides", {}) as Dictionary).is_empty():
		for c in seen:
			BattlefieldDocScript.set_tile_override(model, c, "")
	return seen.size()


## 素材洪水填充：同「地形字符 + 现有覆盖」连通区域整体替换为素材方块，
## 只写 tile_overrides、不动 rows。返回填充格数；0 = 无可做（空 id/越界/起点已是目标）。
static func flood_fill_asset(model: Dictionary, cell: Vector2i, asset_id: String) -> int:
	if asset_id.is_empty():
		return 0
	if cell.x < 0 or cell.y < 0 or cell.x >= int(model.width) or cell.y >= int(model.height):
		return 0
	if BattlefieldDocScript.tile_override_at(model, cell) == asset_id:
		return 0  # 起点已是目标素材：无可做
	var rows: Array = model.rows
	var from_glyph: String = rows[cell.y].substr(cell.x, 1)
	var from_override := BattlefieldDocScript.tile_override_at(model, cell)
	var stack: Array[Vector2i] = [cell]
	var seen := { cell: true }
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		BattlefieldDocScript.set_tile_override(model, c, asset_id)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= int(model.width) or n.y >= int(model.height) or seen.has(n):
				continue
			if (rows[n.y] as String).substr(n.x, 1) != from_glyph:
				continue
			if BattlefieldDocScript.tile_override_at(model, n) != from_override:
				continue
			seen[n] = true
			stack.append(n)
	return seen.size()


## 区域填充：矩形内每格应用 kind/id——内置地形写 rows 并清素材覆盖；素材写
## tile_overrides 不动 rows。立体选择（mn.z != mx.z）= 体积填充语义：全 footprint
## 填充且每列顶面统一找平至 z_hi。cells 传入选区 2D 足迹（x/y 矩形）。
## 返回 {"kind": 归一后类型, "id": 归一后 id, "count": 填充格数, "leveled": 找平列数}；
## id 为空时按内置地形 plain 处理。
static func fill_region(model: Dictionary, mn: Vector3i, mx: Vector3i, kind: StringName, id: String, cells: Array) -> Dictionary:
	if id.is_empty():
		kind = &"terrain"
		id = "plain"
	var z_hi := maxi(mn.z, mx.z)
	var volume := mn.z != mx.z  # 异高 → 全 footprint 填充 + 顶面找平均 z_hi
	var rows: Array = model.rows
	var glyph := String(BattlefieldDocScript.TERRAIN_GLYPH.get(StringName(id), "."))
	var count := 0
	var leveled := 0
	for c in cells:
		if c.x < 0 or c.y < 0 or c.x >= int(model.width) or c.y >= int(model.height):
			continue
		if volume:
			var cz := BattlefieldDocScript.cell_z(model, c)
			if cz != z_hi:
				BattlefieldDocScript.set_cell_z(model, c, z_hi)
				leveled += 1
		if kind == &"asset":
			BattlefieldDocScript.set_tile_override(model, c, id)
		else:
			var row: String = rows[c.y]
			if row.substr(c.x, 1) != glyph:
				rows[c.y] = row.substr(0, c.x) + glyph + row.substr(c.x + 1)
			BattlefieldDocScript.set_tile_override(model, c, "")
		count += 1
	return {"kind": kind, "id": id, "count": count, "leveled": leveled}


## 条件替换·匹配（只读不写）：terrain 源只匹配无 tile_override 且 rows 图例相同
## 的格；asset 源只匹配覆盖 id。返回命中格数组。
static func match_cells(model: Dictionary, cells: Array, source_kind: String, source_value: String) -> Array:
	var rows: Array = model.rows
	var matched: Array = []
	for c: Vector2i in cells:
		var override_id := BattlefieldDocScript.tile_override_at(model, c)
		if source_kind == "asset":
			if override_id == source_value:
				matched.append(c)
		elif override_id.is_empty() and String((rows[c.y] as String).substr(c.x, 1)) == source_value:
			matched.append(c)
	return matched


## 条件替换·写入：对命中格写目标（高度一律不动）。返回写入格数。
## terrain 目标写 rows 并清素材覆盖；asset 目标写 tile_overrides 不动 rows。
static func write_cells(model: Dictionary, matched: Array, dest_kind: String, dest_value: String) -> int:
	var rows: Array = model.rows
	for c: Vector2i in matched:
		if dest_kind == "asset":
			BattlefieldDocScript.set_tile_override(model, c, dest_value)
		else:
			var row: String = rows[c.y]
			rows[c.y] = row.substr(0, c.x) + dest_value + row.substr(c.x + 1)
			BattlefieldDocScript.set_tile_override(model, c, "")
	return matched.size()
