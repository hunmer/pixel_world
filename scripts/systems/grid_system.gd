## systems/grid_system.gd — 网格世界模型（对应 src/systems/GridSystem.ts）
##
## 持有地形矩阵 + 单位占位；提供：
##   - compute_move_range  Dijkstra（考虑地形消耗、非己方单位阻挡）
##   - compute_attack_range 移动范围与攻击范围【解耦】（攻击范围仅反映"原地能打到哪里"）
##   - find_path           A*（曼哈顿启发，显示移动轨迹）
##
## 地形用 StringName(TerrainType) 矩阵传入；单位用 UnitData dict。

class_name GridSystem
extends RefCounted

var width: int
var height: int
# tiles[y][x] = TileData dict（拷贝自 TerrainData.TERRAIN）
var tiles: Array = []
# units: unitId(StringName) -> UnitData dict
var units: Dictionary = {}
# cell_to_unit[y][x] = unitId or null
var cell_to_unit: Array = []


func _init(w: int, h: int, terrain: Array) -> void:
	width = w
	height = h
	tiles = []
	for y in range(h):
		var row: Array = []
		for x in range(w):
			row.append(TerrainData.get_tile(terrain[y][x]))
		tiles.append(row)
	cell_to_unit = []
	for y in range(h):
		cell_to_unit.append([])
		for x in range(w):
			cell_to_unit[y].append(null)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func tile_at(x: int, y: int) -> Dictionary:
	if not in_bounds(x, y):
		return {}
	return tiles[y][x]


func unit_at(x: int, y: int) -> Dictionary:
	if not in_bounds(x, y):
		return {}
	var id = cell_to_unit[y][x]
	if id == null:
		return {}
	return units.get(id, {})


## 注册/移动单位到指定位置
func place_unit(unit: Dictionary, x: int, y: int) -> void:
	var pos: Vector2i = unit[&"position"]
	if in_bounds(pos.x, pos.y):
		cell_to_unit[pos.y][pos.x] = null
	unit[&"position"] = Vector2i(x, y)
	units[unit[&"id"]] = unit
	cell_to_unit[y][x] = unit[&"id"]


func remove_unit(unit: Dictionary) -> void:
	var pos: Vector2i = unit[&"position"]
	if in_bounds(pos.x, pos.y):
		cell_to_unit[pos.y][pos.x] = null
	unit[&"isDead"] = true
	units.erase(unit[&"id"])


# 单元格 key 用 "x,y" 字符串（与 TS 版 Map<string,number> 一致）
static func _key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]

const DIRS := [[1,0],[-1,0],[0,1],[0,-1]]

## Dijkstra：从 (sx,sy) 出发，移动类型 move_type、移动力 mov 的所有可达格子。
## 非己方单位阻挡。返回 { "x,y" -> cost }。
func compute_move_range(
	sx: int, sy: int, move_type: StringName, mov: int, ally_faction: StringName
) -> Dictionary:
	var result: Dictionary = {}
	var visited: Dictionary = {}
	# 优先队列用数组 + 每次 sort（MVP 够用，与 TS 版一致）
	var queue: Array = [{ &"x": sx, &"y": sy, &"cost": 0 }]
	result[_key(sx, sy)] = 0
	while not queue.is_empty():
		queue.sort_custom(func(a, b): return a[&"cost"] < b[&"cost"])
		var cur: Dictionary = queue.pop_front()
		var k := _key(cur[&"x"], cur[&"y"])
		if visited.has(k):
			continue
		visited[k] = true
		for d in DIRS:
			var nx: int = cur[&"x"] + d[0]
			var ny: int = cur[&"y"] + d[1]
			if not in_bounds(nx, ny):
				continue
			var tile: Dictionary = tiles[ny][nx]
			if not tile[&"walkable"]:
				continue
			var cost: int = tile[&"move_cost"].get(move_type, 99)
			if cost >= 99:
				continue
			var new_cost: int = cur[&"cost"] + cost
			if new_cost > mov:
				continue
			var blocker: Dictionary = unit_at(nx, ny)
			if not blocker.is_empty() and blocker[&"faction"] != ally_faction:
				continue
			var nk := _key(nx, ny)
			if not result.has(nk) or new_cost < result[nk]:
				result[nk] = new_cost
				queue.append({ &"x": nx, &"y": ny, &"cost": new_cost })
	return result


## 计算单位的【移动范围】与【攻击范围】——两个相互独立的概念。
## attack_tiles 仅反映"原地能打到哪里"，与移动范围解耦（保留原设计意图）。
## 返回 { moveRange:{}, attackTiles:{}(用 set 语义的 Dictionary) }
func compute_attack_range(
	sx: int, sy: int, unit: Dictionary
) -> Dictionary:
	var move_range := compute_move_range(sx, sy, unit[&"moveType"], unit[&"stats"][&"mov"], unit[&"faction"])
	var r: Array = ProfessionData.unit_attack_range(unit)
	var min_r: int = r[0]
	var max_r: int = r[1]
	var attack_tiles: Dictionary = {}
	if max_r > 0:
		var visited: Dictionary = { _key(sx, sy): true }
		var q: Array = [{ &"x": sx, &"y": sy, &"d": 0 }]
		while not q.is_empty():
			var cur: Dictionary = q.pop_front()
			var d: int = cur[&"d"]
			if d >= max_r:
				continue
			for delta in DIRS:
				var nx: int = cur[&"x"] + delta[0]
				var ny: int = cur[&"y"] + delta[1]
				var k := _key(nx, ny)
				if visited.has(k) or not in_bounds(nx, ny):
					continue
				visited[k] = true
				var next_d: int = d + 1
				if next_d >= min_r and next_d <= max_r:
					attack_tiles[k] = true
				q.append({ &"x": nx, &"y": ny, &"d": next_d })
	return { &"moveRange": move_range, &"attackTiles": attack_tiles }


## A* 寻路（显示移动轨迹）。返回 [Vector2i, ...] 或空数组（无路）。
func find_path(start: Vector2i, goal: Vector2i, move_type: StringName, max_cost: int) -> Array:
	if start.x == goal.x and start.y == goal.y:
		return [start]
	var h := func(a: Vector2i, b: Vector2i) -> int: return abs(a.x - b.x) + abs(a.y - b.y)
	# Node = { pos, g, f, parent(Node|null) }
	var start_node := { &"pos": start, &"g": 0, &"f": h.call(start, goal), &"parent": null }
	var open: Array = [start_node]
	var closed: Dictionary = {}
	while not open.is_empty():
		open.sort_custom(func(a, b): return a[&"f"] < b[&"f"])
		var cur: Dictionary = open.pop_front()
		var ck := _key(cur[&"pos"].x, cur[&"pos"].y)
		if closed.has(ck):
			continue
		closed[ck] = true
		var cp: Vector2i = cur[&"pos"]
		if cp.x == goal.x and cp.y == goal.y:
			var path: Array = []
			var n: Variant = cur
			while n != null:
				path.push_front((n as Dictionary)[&"pos"])
				n = (n as Dictionary)[&"parent"]
			return path
		for delta in DIRS:
			var nx: int = cp.x + delta[0]
			var ny: int = cp.y + delta[1]
			if not in_bounds(nx, ny):
				continue
			var tile: Dictionary = tiles[ny][nx]
			if not tile[&"walkable"]:
				continue
			var cost: int = tile[&"move_cost"].get(move_type, 99)
			if cost >= 99:
				continue
			var g: int = cur[&"g"] + cost
			if g > max_cost:
				continue
			var k := _key(nx, ny)
			if closed.has(k):
				continue
			open.append({
				&"pos": Vector2i(nx, ny), &"g": g,
				&"f": g + h.call(Vector2i(nx, ny), goal), &"parent": cur,
			})
	return []


## 曼哈顿距离
static func distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
