## core/reinforcement_spawner.gd — 按回合增援的共享刷入逻辑（FE 式波次援军）
##
## 职责：消费 chapter["reinforcements"] 波次（由 battlefield_loader 解析产出），
## 在敌方回合开始时把到点波次（wave.turn <= 当前回合号）的单位刷入
## grid / turn / chapter.enemyUnits。battle.gd（带演出）与 battle_runner.gd
## （无头自动化）共用同一实现，保证两条链路行为一致。
##
## 落点策略：优先用声明坐标；被占/不可站立时在半径 SEARCH_RADIUS 内找最近
## 可站立空格；找不到则丢弃该单位并打日志（安全兜底，不阻塞回合）。
##
## 与胜利判定的链路：刷入的单位追加进 chapter.enemyUnits，check_victory 的
## 敌存活集合自然纳入；未到点的波次经 pending_units() 并入敌集合，避免
## 「初始敌全灭即胜」漏掉还在路上的增援。

class_name ReinforcementSpawner
extends RefCounted

const FacingRules = preload("res://scripts/systems/facing_rules.gd")

## 落点被占时的邻近搜索半径（曼哈顿环）
const SEARCH_RADIUS := 3


## 到点波次刷入。返回本回合实际刷入的单位列表（battle.gd 用它补 sprite）。
## 已消费（含整波丢弃）的波次从 chapter["reinforcements"] 移除，保证只触发一次
## （存档快照复制 chapter，恢复局不重复刷）。
static func spawn_due(chapter: Dictionary, grid: GridSystem, turn: TurnManager, turn_number: int) -> Array:
	var waves: Array = chapter.get("reinforcements", [])
	if waves.is_empty():
		return []
	var remaining: Array = []
	var spawned: Array = []
	for w in waves:
		var wave_turn := int((w as Dictionary).get(&"turn", 0))
		if wave_turn > turn_number:
			remaining.append(w)
			continue
		for u in ((w as Dictionary).get(&"units", []) as Array):
			var unit: Dictionary = u
			var pos: Vector2i = unit[&"position"]
			var spot := _find_spot(grid, pos)
			if spot.x < 0:
				push_warning("[reinforcement] 单位 %s 刷入失败：(%d,%d) 附近 %d 格内无空可站立格，已丢弃"
					% [String(unit.get(&"name", unit.get(&"id", &""))), pos.x, pos.y, SEARCH_RADIUS])
				continue
			if spot != pos:
				unit[&"position"] = spot
			grid.place_unit(unit, spot.x, spot.y)
			# 入场朝向：面向最近敌方（place_unit 的 face_move 对「出生即落位」零位移不设朝向）。
			FacingRules.orient_toward_nearest_enemy(unit, grid.units.values())
			(chapter["enemyUnits"] as Array).append(unit)
			(turn.units as Array).append(unit)
			spawned.append(unit)
	chapter["reinforcements"] = remaining
	return spawned


## 未到点波次的全部单位（并入 check_victory 的敌存活集合，防提前判胜）。
## dead 标志恒为 false（尚未入场），与 check_victory 只读 isDead 兼容。
static func pending_units(chapter: Dictionary) -> Array:
	var out: Array = []
	for w in (chapter.get("reinforcements", []) as Array):
		for u in ((w as Dictionary).get(&"units", []) as Array):
			out.append(u)
	return out


## 找刷入落点：origin 可用直接用；否则按曼哈顿环由近到远找可站立空格。
## 返回 Vector2i(-1,-1) 表示放弃。
static func _find_spot(grid: GridSystem, origin: Vector2i) -> Vector2i:
	if _cell_free(grid, origin):
		return origin
	for r in range(1, SEARCH_RADIUS + 1):
		for dx in range(-r, r + 1):
			var dy := r - absi(dx)
			for cand: Vector2i in [Vector2i(origin.x + dx, origin.y + dy), Vector2i(origin.x + dx, origin.y - dy)]:
				if _cell_free(grid, cand):
					return cand
	return Vector2i(-1, -1)


static func _cell_free(grid: GridSystem, cell: Vector2i) -> bool:
	if not grid.in_bounds(cell.x, cell.y):
		return false
	# 建筑占用格不可刷入（与单位放置/传送共用 is_building_cell 阻挡语义）
	if grid.is_building_cell(cell.x, cell.y):
		return false
	if not grid.unit_at(cell.x, cell.y).is_empty():
		return false
	var tile: Dictionary = grid.tile_at(cell.x, cell.y)
	if not bool(tile.get(&"walkable", false)):
		return false
	return int(tile[&"move_cost"].get(&"foot", 99)) < 99
