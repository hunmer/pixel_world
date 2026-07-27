## systems/item_system.gd — 物品结算（全静态）
##
## 物品 effect：
##   heal_hp  — 恢复 HP（消耗品）
##   heal_mp  — 恢复 MP（消耗品）
##   damage   — 造成固定伤害（投掷物，不被反击，通常必中）
##   buff     — 挂临时 buff（buff 道具）
##   cleanse  — 清除减益（解毒）
##   equip    — 永久改 stats（装备类，不消耗 uses，单独走 equip 流程）
##
## 消耗品/投掷物/buff 道具：使用后 uses-=1，归零从背包移除。
## 装备类：走 equip()，永久改 stats 并标记已装备（uses 保持，不入消耗）。

class_name ItemSystem
extends RefCounted


## 背包条目是否可用（uses>0 且非装备）。
static func can_use(_user: Dictionary, item_entry: Dictionary) -> bool:
	if int(item_entry.get(&"uses", 0)) <= 0:
		return false
	var idef: Dictionary = ItemData.get_item(item_entry.get(&"id", &""))
	if idef.is_empty() or idef[&"type"] == &"equip":
		return false
	return true


## 列出物品的合法目标（按 target + range + 阵营过滤）。仿 SkillSystem.targets_for。
static func targets_for(user: Dictionary, item_id: StringName, grid: GridSystem) -> Array:
	var idef: Dictionary = ItemData.get_item(item_id)
	if idef.is_empty():
		return []
	var tt: StringName = idef[&"target"]
	if tt == &"self":
		return [user]
	if grid == null:
		return []
	var r: Array = idef[&"range"]
	var up: Vector2i = user[&"position"]
	var user_faction: StringName = user[&"faction"]
	var out: Array = []
	for other in grid.units.values():
		if other.get(&"isDead", false):
			continue
		var dist := absi(other.position.x - up.x) + absi(other.position.y - up.y)
		if dist < int(r[0]) or dist > int(r[1]):
			continue
		var same_side: bool = other.faction == user_faction
		match tt:
			&"ally":
				if same_side:   # ally 含自己（可以奶自己/给自己吃药）
					out.append(other)
			&"enemy":
				if not same_side:
					out.append(other)
			&"aoe_enemy":
				if not same_side:
					out.append(other)
	return out


# ============================================================
# 预览
# ============================================================
static func preview(_user: Dictionary, target: Dictionary, item_id: StringName) -> Dictionary:
	var idef: Dictionary = ItemData.get_item(item_id)
	if idef.is_empty():
		return {}
	var res: Dictionary = { id = item_id, name = idef[&"name"], type = idef[&"type"], effect = idef[&"effect"] }
	match idef[&"effect"]:
		&"heal_hp":
			var max_hp: int = int(target[&"stats"][&"hp"])
			res[&"hp_delta"] = mini(int(idef[&"power"]), max_hp - int(target[&"hp"]))
			res[&"desc"] = "回 HP ~%d" % int(idef[&"power"])
		&"heal_mp":
			var max_mp: int = int(target[&"stats"].get(&"mp", 0))
			res[&"mp_delta"] = mini(int(idef[&"power"]), max_mp - int(target.get(&"mp", 0)))
			res[&"desc"] = "回 MP ~%d" % int(idef[&"power"])
		&"damage":
			res[&"hp_delta"] = -int(idef[&"power"])
			res[&"desc"] = "伤害 %d" % int(idef[&"power"])
		&"buff":
			res[&"buff_desc"] = "%s%+d (%d回合)" % [String(idef[&"stat"]), int(idef[&"buffValue"]), int(idef[&"buffTurns"])]
			res[&"desc"] = res[&"buff_desc"]
		&"cleanse":
			res[&"desc"] = "清除减益"
		&"equip":
			res[&"desc"] = "%s%+d（装备）" % [String(idef[&"equipStat"]), int(idef[&"equipValue"])]
	return res


# ============================================================
# 执行（落地）
# ============================================================

## 执行非装备物品。消耗 uses，落地效果。
## 返回 { effect, hp_deltas:[{unit,delta}], mp_deltas:[{unit,delta}], buffed:[{unit,desc}], cleansed:[{unit,count}], entry_consumed }
static func execute(user: Dictionary, targets: Array, item_entry: Dictionary) -> Dictionary:
	var idef: Dictionary = ItemData.get_item(item_entry.get(&"id", &""))
	if idef.is_empty():
		return {}
	var result: Dictionary = {
		effect = idef[&"effect"], id = idef[&"id"], name = idef[&"name"],
		hp_deltas = [], mp_deltas = [], buffed = [], cleansed = [],
	}
	for t in targets:
		if t.get(&"isDead", false):
			continue
		match idef[&"effect"]:
			&"heal_hp":
				var max_hp: int = int(t[&"stats"][&"hp"])
				var before: int = int(t[&"hp"])
				t[&"hp"] = mini(max_hp, before + int(idef[&"power"]))
				result[&"hp_deltas"].append({ unit = t, delta = int(t[&"hp"]) - before })
			&"heal_mp":
				var max_mp: int = int(t[&"stats"].get(&"mp", 0))
				var before_m: int = int(t.get(&"mp", 0))
				t[&"mp"] = mini(max_mp, before_m + int(idef[&"power"]))
				result[&"mp_deltas"].append({ unit = t, delta = int(t[&"mp"]) - before_m })
			&"damage":
				# 投掷物固定伤害，通常必中（不做命中判定）
				var dmg: int = int(idef[&"power"])
				var before_d: int = int(t[&"hp"])
				t[&"hp"] = maxi(0, before_d - dmg)
				result[&"hp_deltas"].append({ unit = t, delta = int(t[&"hp"]) - before_d, died = int(t[&"hp"]) <= 0 })
			&"buff":
				SkillSystem.apply_buff(t, idef[&"stat"], int(idef[&"buffValue"]), int(idef[&"buffTurns"]), String(idef[&"name"]))
				result[&"buffed"].append({ unit = t, desc = "%s%+d" % [String(idef[&"stat"]), int(idef[&"buffValue"])] })
			&"cleanse":
				var removed: int = SkillSystem.cleanse_debuffs(t)
				result[&"cleansed"].append({ unit = t, count = removed })
	# 消耗 uses：减 1，归零从背包移除
	item_entry[&"uses"] = int(item_entry.get(&"uses", 0)) - 1
	result[&"entry_consumed"] = int(item_entry[&"uses"]) <= 0
	if int(item_entry[&"uses"]) <= 0:
		(user[&"items"] as Array).erase(item_entry)
	return result


## 装备类：永久改 stats，标记已装备（加到 unit.equipped 列表防重复装备）。
static func equip(user: Dictionary, item_entry: Dictionary) -> Dictionary:
	var idef: Dictionary = ItemData.get_item(item_entry.get(&"id", &""))
	if idef.is_empty() or idef[&"type"] != &"equip":
		return {}
	# 防重复装备
	var equipped: Array = user.get(&"equipped", [])
	if equipped.has(idef[&"id"]):
		return { equipped = false, reason = "already" }
	var stat: StringName = idef[&"equipStat"]
	user[&"stats"][stat] = int(user[&"stats"].get(stat, 0)) + int(idef[&"equipValue"])
	equipped.append(idef[&"id"])
	user[&"equipped"] = equipped
	# 装备后从背包移除该条目（占用装备槽）
	(user[&"items"] as Array).erase(item_entry)
	return { equipped = true, stat = stat, value = int(idef[&"equipValue"]) }
