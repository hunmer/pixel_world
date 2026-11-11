## core/terrain.gd — 地形定义（对应 src/data/staticData.ts 的 TERRAIN）
## 纯静态查表类。TileData 结构用 Dictionary 表达：
##   { type, def_bonus, avoid_bonus, move_cost: {foot,armor,cavalry,flying}, walkable }
## move_cost 里 99 = 不可通行（与 TS 版一致）。

class_name TerrainData
extends RefCounted

# { TerrainType -> TileData Dictionary }
static var TERRAIN: Dictionary = {}


static func _static_init() -> void:
	TERRAIN = {
		&"plain":    _mk(&"plain",    0, 0,  {&"foot": 1, &"armor": 1, &"cavalry": 1, &"flying": 1}, true),
		&"forest":   _mk(&"forest",   1, 20, {&"foot": 2, &"armor": 2, &"cavalry": 3, &"flying": 1}, true),
		&"mountain": _mk(&"mountain", 1, 30, {&"foot": 3, &"armor": 99, &"cavalry": 99, &"flying": 1}, true),
		&"water":    _mk(&"water",    0, 10, {&"foot": 99, &"armor": 99, &"cavalry": 99, &"flying": 1}, true),
		&"fort":     _mk(&"fort",     3, 20, {&"foot": 1, &"armor": 1, &"cavalry": 1, &"flying": 1}, true),
		&"village":  _mk(&"village",  0, 0,  {&"foot": 1, &"armor": 1, &"cavalry": 1, &"flying": 1}, true),
		&"wall":     _mk(&"wall",     0, 0,  {&"foot": 99, &"armor": 99, &"cavalry": 99, &"flying": 99}, false),
		&"sand":    _mk(&"sand",    0, 0,  {&"foot": 2, &"armor": 2, &"cavalry": 3, &"flying": 1}, true),
		&"snow":    _mk(&"snow",    0, 10, {&"foot": 2, &"armor": 2, &"cavalry": 3, &"flying": 1}, true),
		&"grass":   _mk(&"grass",   0, 10, {&"foot": 1, &"armor": 1, &"cavalry": 1, &"flying": 1}, true),
		&"rocky":   _mk(&"rocky",   1, 10, {&"foot": 2, &"armor": 2, &"cavalry": 3, &"flying": 1}, true),
	}


static func _mk(type: StringName, def_bonus: int, avoid_bonus: int, move_cost: Dictionary, walkable: bool) -> Dictionary:
	return {
		&"type": type,
		&"def_bonus": def_bonus,
		&"avoid_bonus": avoid_bonus,
		&"move_cost": move_cost, # { MoveType -> int }
		&"walkable": walkable,
	}


## 按类型取 TileData（返回拷贝，调用方可安全改写）
static func get_tile(type_: StringName) -> Dictionary:
	var t: Dictionary = TERRAIN.get(type_, TERRAIN[&"plain"])
	return t.duplicate(true)


## 某 move_type 在该地形的移动消耗（99=阻挡）
static func cost(type_: StringName, move_type: StringName) -> int:
	var t: Dictionary = TERRAIN.get(type_, TERRAIN[&"plain"])
	return t[&"move_cost"].get(move_type, 99)
