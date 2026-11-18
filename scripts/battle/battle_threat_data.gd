## battle_threat_data.gd — 只读范围与敌方威胁预测，复用实际移动、射程、战斗公式。
class_name BattleThreatData
extends RefCounted

const FacingRules = preload("res://scripts/systems/facing_rules.gd")
const DEFAULT_CRIT_THRESHOLD: int = 20


## moveRange 保留可穿越的友军格；攻击/辅助只从实际可停留格外扩。
## allow_move=false 用于已移动单位/原地行动。结果不应替代实际行动合法性判定。
static func unit_ranges(grid: GridSystem, unit: Dictionary, allow_move: bool = true) -> Dictionary:
	var result: Dictionary = {moveRange = {}, attackTiles = {}, supportTiles = {}}
	if unit.is_empty() or bool(unit.get(&"isDead", false)):
		return result
	var pos: Vector2i = unit[&"position"]
	if not grid.in_bounds(pos.x, pos.y):
		return result
	var moves: Dictionary = {_key(pos): 0}
	if allow_move:
		moves = grid.compute_move_range(pos.x, pos.y, unit[&"moveType"], int(unit[&"stats"][&"mov"]), unit[&"faction"])
	result[&"moveRange"] = moves
	var tiles: Dictionary = {}
	var weapon_range: Array = ProfessionData.unit_attack_range(unit)
	for raw_key: Variant in moves:
		var stop: Vector2i = _cell(String(raw_key))
		var occupant: Dictionary = grid.unit_at(stop.x, stop.y)
		if not occupant.is_empty() and occupant.get(&"id") != unit.get(&"id"):
			continue
		tiles.merge(tiles_in_range(grid, stop, weapon_range))
	if unit[&"weapon"][&"type"] == &"staff":
		result[&"supportTiles"] = tiles
	else:
		result[&"attackTiles"] = tiles
	return result


## 与实际武器判距一致：曼哈顿距离，不额外引入视线/地形阻挡。
## 也可供 lead 以实际技能/道具的 [min,max] 射程显示绿色辅助格。
static func tiles_in_range(grid: GridSystem, origin: Vector2i, reach: Array) -> Dictionary:
	var tiles: Dictionary = {}
	var min_range: int = int(reach[0])
	var max_range: int = int(reach[1])
	if max_range <= 0:
		return tiles
	for y: int in range(maxi(0, origin.y - max_range), mini(grid.height, origin.y + max_range + 1)):
		for x: int in range(maxi(0, origin.x - max_range), mini(grid.width, origin.x + max_range + 1)):
			var cell: Vector2i = Vector2i(x, y)
			var distance: int = GridSystem.distance(origin, cell)
			if distance >= min_range and distance <= max_range:
				tiles[_key(cell)] = true
	return tiles


## enemies 由调用者提供敌对单位集合；死亡与治疗杖不产生普通攻击危险区。
## 不看 hasMoved/hasActed：显示敌方下一回合完整移动后的潜在威胁。
static func danger_tiles(grid: GridSystem, enemies: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_enemy: Variant in enemies:
		var enemy: Dictionary = raw_enemy
		var ranges: Dictionary = unit_ranges(grid, enemy)
		result.merge(ranges[&"attackTiles"])
	return result


## 每个敌人最多一条线；默认原位射程，allow_enemy_move=true 可选下一回合移动预测。
## 从其实际位置指向 target，attack_from 是预测攻击站位。
## 黄色 = atkCrit >= crit_threshold 或真实武器三角占优；preview 原样提供真实预测。
## 玩家移至 target 的占位/朝向仅作用于快照，原单位、grid、随机流均不改变。
static func threats_to(grid: GridSystem, enemies: Array, player: Dictionary, target: Vector2i, crit_threshold: int = DEFAULT_CRIT_THRESHOLD, allow_enemy_move: bool = false) -> Array:
	var result: Array = []
	if player.is_empty() or bool(player.get(&"isDead", false)) or not grid.in_bounds(target.x, target.y):
		return result
	var occupant: Dictionary = grid.unit_at(target.x, target.y)
	if not occupant.is_empty() and occupant.get(&"id") != player.get(&"id"):
		return result
	var snapshot: GridSystem = _with_player_at(grid, player, target)
	var defender: Dictionary = snapshot.units[player[&"id"]]
	var tile: Dictionary = snapshot.tile_at(target.x, target.y)
	for raw_enemy: Variant in enemies:
		var enemy: Dictionary = raw_enemy
		if enemy.is_empty() or bool(enemy.get(&"isDead", false)) or enemy.get(&"faction") == player.get(&"faction"):
			continue
		if enemy[&"weapon"][&"type"] == &"staff":
			continue
		var ranges: Dictionary = unit_ranges(snapshot, enemy, allow_enemy_move)
		if not (ranges[&"attackTiles"] as Dictionary).has(_key(target)):
			continue
		var reach: Array = ProfessionData.unit_attack_range(enemy)
		var best_preview: Dictionary = {}
		var best_stop: Vector2i = enemy[&"position"]
		var best_score: float = -1.0
		var moves: Dictionary = ranges[&"moveRange"]
		for raw_key: Variant in moves:
			var stop: Vector2i = _cell(String(raw_key))
			var blocker: Dictionary = snapshot.unit_at(stop.x, stop.y)
			if not blocker.is_empty() and blocker.get(&"id") != enemy.get(&"id"):
				continue
			var distance: int = GridSystem.distance(stop, target)
			if distance < int(reach[0]) or distance > int(reach[1]):
				continue
			var attacker: Dictionary = enemy.duplicate()
			attacker[&"position"] = stop
			var prediction: Dictionary = CombatSystem.preview(attacker, defender, int(tile.get(&"avoid_bonus", 0)), int(tile.get(&"def_bonus", 0)))
			var score: float = float(prediction[&"atkDmg"]) * float(prediction[&"atkHit"]) * (2.0 if bool(prediction[&"doubleAttack"]) else 1.0)
			if score > best_score:
				best_score = score
				best_stop = stop
				best_preview = prediction
		if best_preview.is_empty():
			continue
		var triangle: Dictionary = WeaponData.triangle_modifier(enemy[&"weapon"][&"type"], defender[&"weapon"][&"type"])
		var advantage: bool = int(triangle[&"damage"]) > 0
		result.append({
			source = enemy[&"position"], target = target, enemy_id = enemy[&"id"],
			attack_from = best_stop, preview = best_preview, advantage = advantage,
			high_risk = advantage or int(best_preview[&"atkCrit"]) >= crit_threshold,
		})
	return result


static func _with_player_at(grid: GridSystem, player: Dictionary, target: Vector2i) -> GridSystem:
	var snapshot: GridSystem = GridSystem.new(0, 0, [])
	snapshot.width = grid.width
	snapshot.height = grid.height
	snapshot.tiles = grid.tiles
	snapshot.building_cells = grid.building_cells
	snapshot.units = grid.units.duplicate()
	snapshot.cell_to_unit = grid.cell_to_unit.duplicate(true)
	var defender: Dictionary = player.duplicate()
	var old_pos: Vector2i = player[&"position"]
	if grid.in_bounds(old_pos.x, old_pos.y):
		snapshot.cell_to_unit[old_pos.y][old_pos.x] = null
	FacingRules.face_move(defender, old_pos, target)
	defender[&"position"] = target
	snapshot.units[player[&"id"]] = defender
	snapshot.cell_to_unit[target.y][target.x] = player[&"id"]
	return snapshot


static func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func _cell(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
