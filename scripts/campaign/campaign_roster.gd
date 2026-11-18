## campaign_roster.gd — 冒险队伍纯逻辑（初始构建 / 出征部署 / 胜利导入）
##
## 全部为静态纯函数：输入输出显式传递，不读全局状态；deploy 会消费 inventory
## （就地扣减出征物品），其余函数不修改入参（import_victory 对终局 chapter 只读）。
##
## Hub 归一化约定（_normalize_hub_unit）：满 HP/MP、清除 isDead/hasMoved/hasActed、
## buffs 与技能冷却清空 —— 队伍在 Hub 永远是"满状态待命"。

class_name CampaignRoster
extends RefCounted

const BattlefieldLoaderScript := preload("res://scripts/core/battlefield_loader.gd")
const ItemDataScript := preload("res://scripts/core/items.gd")
const CampaignConfigScript := preload("res://scripts/campaign/campaign_config.gd")
const TerrainDataScript := preload("res://scripts/core/terrain.gd")
const ProfessionDataScript := preload("res://scripts/core/professions.gd")
const EquipmentDataScript := preload("res://scripts/core/equipment.gd")


## 从首关战场确定性重建初始队伍。
## 返回 {ok, roster, templates, inventory} 或 {ok:false, error}。
## - roster：单位 id 重编为 r_0..r_n（稳定跨存档），items 清空（物品汇总进公共库存）。
## - templates：按 roster 序的携带方案 [[{id:StringName, count:int}], ...]。
## - inventory：初始物品实例（uses 沿用战场单位自带值）。
static func build_initial(first_level_id: String) -> Dictionary:
	var level: Dictionary = CampaignConfigScript.get_level(first_level_id)
	if level.is_empty():
		return {"ok": false, "error": "未知关卡：%s" % first_level_id}
	var probe: Dictionary = BattlefieldLoaderScript.load_battlefield(str(level.source))
	if not probe.get("ok", false):
		return {"ok": false, "error": "战场装载失败：%s" % str(probe.get("error", ""))}
	var chapter: Dictionary = probe.get("chapter", {})
	var source_units: Array = chapter.get("playerUnits", [])
	if source_units.is_empty():
		return {"ok": false, "error": "首关没有玩家单位，无法构建队伍"}
	var roster: Array = []
	var templates: Array = []
	var inventory: Array = []
	for i in source_units.size():
		var src: Dictionary = source_units[i]
		var unit: Dictionary = src.duplicate(true)
		unit["id"] = StringName("r_%d" % i)
		var tmpl: Array = []
		for raw_item: Variant in src.get("items", []):
			if raw_item is not Dictionary:
				continue
			var iid := StringName(String(raw_item.get("id", "")))
			if iid == &"" or ItemDataScript.get_item(iid).get("id", &"") != iid:
				continue
			var entry: Dictionary = {}
			for existing in tmpl:
				if StringName(existing.id) == iid:
					entry = existing
					break
			if entry.is_empty():
				entry = {"id": iid, "count": 0}
				tmpl.append(entry)
			entry["count"] = int(entry.count) + 1
			inventory.append({"id": iid, "uses": int(raw_item.get("uses", 0))})
		unit["items"] = []
		# 新档成长分化：只写职业成长表（不重新 apply_profession，避免重置单位已带
		# stats/武器/技能）；职业未知（手搓夹具缺 classId）时保留单位原 growths。
		var prof_id := StringName(String(unit.get("classId", unit.get("class", ""))))
		if prof_id != &"" and ProfessionDataScript.has_profession(prof_id):
			unit["growths"] = ProfessionDataScript.growths_for(ProfessionDataScript.get_profession(prof_id))
		_normalize_hub_unit(unit)
		roster.append(unit)
		templates.append(tmpl)
	return {
		"ok": true,
		"error": "",
		"roster": roster,
		"templates": templates,
		"inventory": inventory,
	}


## 出征部署：**全员出征**——档内队伍按战场声明的玩家槽位序先落位，槽位不够的
## 单位按固定队伍序在「可行走、非敌占、不重复」的空格补位（确定性：按与最近
## 声明槽位的曼哈顿距离、再按 y、x 排序取首个）；空格不足返回明确错误，绝不静默
## 留守。补位完成后按携带方案自动补给（固定队伍序 FIFO，缺货跳过，就地扣
## inventory）。chapter 入参不会被修改（内部先 duplicate(true)）。
## 返回 {ok, chapter, deployed_count, extra_ids, sit_out_ids(恒空)} 或 {ok:false, error}。
static func deploy(chapter: Dictionary, roster: Array, inventory: Array, templates: Array) -> Dictionary:
	var slots: Array = chapter.get("playerUnits", [])
	if slots.is_empty():
		return {"ok": false, "error": "战场没有玩家槽位"}
	if roster.is_empty():
		return {"ok": false, "error": "档内队伍为空"}
	var out_chapter: Dictionary = chapter.duplicate(true)
	var map: Array = chapter.get("map", [])
	var width := int(chapter.get("width", 0))
	var height := int(chapter.get("height", 0))
	if map.is_empty() or width <= 0 or height <= 0:
		return {"ok": false, "error": "战场缺少地图数据，无法全员部署"}
	var deployed: Array = []
	var extra_ids: Array = []
	var occupied := {}  # "x,y" -> true
	for raw_enemy: Variant in chapter.get("enemyUnits", []):
		if raw_enemy is Dictionary and not bool(raw_enemy.get("isDead", false)):
			var pos: Variant = raw_enemy.get("position")
			if pos is Vector2i:
				occupied["%d,%d" % [pos.x, pos.y]] = true
	# 槽位序落位
	for i in roster.size():
		var unit: Dictionary = roster[i].duplicate(true)
		_normalize_hub_unit(unit)
		unit["items"] = []
		if i < slots.size():
			var slot: Dictionary = slots[i]
			unit["position"] = slot.get("position", Vector2i.ZERO)
			occupied["%d,%d" % [unit.position.x, unit.position.y]] = true
		else:
			var cell := _find_free_cell(unit, map, width, height, occupied, slots)
			if cell == Vector2i(-1, -1):
				return {
					"ok": false,
					"error": "战场空格不足，无法全员部署：%s（%s）没有可站立格" % [String(unit.get("name", "?")), String(unit.get("id", "?"))],
				}
			unit["position"] = cell
			occupied["%d,%d" % [cell.x, cell.y]] = true
			extra_ids.append(String(unit.get("id", "")))
		deployed.append(unit)
	# 补给发放
	for i in deployed.size():
		var tmpl: Array = templates[i] if i < templates.size() else []
		for entry: Variant in tmpl:
			if entry is not Dictionary:
				continue
			var iid := StringName(String(entry.get("id", "")))
			var need := int(entry.get("count", 0))
			for c in need:
				var found := _take_inventory_instance(inventory, iid)
				if found.is_empty():
					break
				deployed[i]["items"].append(found)
	out_chapter["playerUnits"] = deployed
	return {
		"ok": true,
		"error": "",
		"chapter": out_chapter,
		"deployed_count": deployed.size(),
		"extra_ids": extra_ids,
		"sit_out_ids": [],
	}


## 为补位单位找空格：可行走（cost < 99）+ 非敌占 + 不与已部署重叠；
## 候选按（与最近声明槽位的曼哈顿距离, y, x）确定性排序取首个。
static func _find_free_cell(unit: Dictionary, map: Array, width: int, height: int, occupied: Dictionary, anchor_slots: Array) -> Vector2i:
	var move_type := StringName(String(unit.get("moveType", "foot")))
	var candidates: Array = []
	for y in height:
		var row: Variant = map[y] if y < map.size() else null
		if row is not Array:
			continue
		for x in width:
			if x >= (row as Array).size():
				continue
			var key := "%d,%d" % [x, y]
			if occupied.has(key):
				continue
			var terrain := StringName(String((row as Array)[x]))
			if TerrainDataScript.cost(terrain, move_type) >= 99:
				continue
			candidates.append({"x": x, "y": y})
	if candidates.is_empty():
		return Vector2i(-1, -1)
	var anchors: Array = anchor_slots
	candidates.sort_custom(func(a, b):
		var da := _min_anchor_dist(a, anchors)
		var db := _min_anchor_dist(b, anchors)
		if da != db:
			return da < db
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	var first: Dictionary = candidates[0]
	return Vector2i(int(first.x), int(first.y))


static func _min_anchor_dist(cell: Dictionary, slots: Array) -> int:
	if slots.is_empty():
		return 0
	var best := 1 << 30
	for raw: Variant in slots:
		if raw is not Dictionary:
			continue
		var pos: Variant = raw.get("position")
		if pos is Vector2i:
			best = mini(best, absi(int(cell.x) - pos.x) + absi(int(cell.y) - pos.y))
	return best


## 胜利导入：按单位 id 匹配，把终局战场的成长（level/exp/stats/growths/weapon/skills）
## 吸收进档内队伍，全员 Hub 归一化（复活/满血蓝/清临时态），并回收剩余物品
## （uses>0 的实例，夹到物品最大充）。
## 终局 chapter 只读，绝不修改（battle 演出层还要用）。
## 返回 {ok, roster_new, recovered, matched} 或 {ok:false, error}。
static func import_victory(final_chapter: Dictionary, roster: Array) -> Dictionary:
	var units: Variant = final_chapter.get("playerUnits", [])
	if units is not Array or units.is_empty():
		return {"ok": false, "error": "终局战场缺少我方单位数据"}
	var by_id := {}
	for raw: Variant in units:
		if raw is Dictionary:
			var uid := String(raw.get("id", ""))
			if uid != "" and not by_id.has(uid):
				by_id[uid] = raw
	var out: Array = []
	var recovered: Array = []
	var matched := 0
	for src: Variant in roster:
		if src is not Dictionary:
			return {"ok": false, "error": "档内队伍单位不是对象"}
		var unit: Dictionary = src.duplicate(true)
		var final_unit: Variant = by_id.get(String(src.get("id", "")), null)
		if final_unit is Dictionary:
			matched += 1
			_absorb_final(unit, final_unit)
			for raw_item: Variant in final_unit.get("items", []):
				if raw_item is not Dictionary:
					continue
				var iid := StringName(String(raw_item.get("id", "")))
				if iid == &"" or ItemDataScript.get_item(iid).get("id", &"") != iid:
					continue
				var uses := int(raw_item.get("uses", 0))
				var max_uses := int(ItemDataScript.get_item(iid).get("uses", 0))
				uses = clampi(uses, 0, maxi(1, max_uses))
				if uses > 0:
					recovered.append({"id": iid, "uses": uses})
		_normalize_hub_unit(unit)
		unit["items"] = []
		out.append(unit)
	if matched == 0:
		return {"ok": false, "error": "终局战场与档内队伍没有匹配单位（id 不一致）"}
	return {
		"ok": true,
		"error": "",
		"roster_new": out,
		"recovered": recovered,
		"matched": matched,
	}


## 把终局单位的成长吸收进档内单位（副本）。只吸收成长性字段；位置/临时态不吸收。
static func _absorb_final(unit: Dictionary, final_unit: Dictionary) -> void:
	unit["level"] = maxi(1, int(final_unit.get("level", unit.get("level", 1))))
	unit["exp"] = maxi(0, int(final_unit.get("exp", unit.get("exp", 0))))
	var src_stats: Dictionary = unit.get("stats", {})
	var final_stats: Variant = final_unit.get("stats")
	if final_stats is Dictionary:
		for key in src_stats:
			var k := String(key)
			if final_stats.has(k):
				src_stats[k] = int(final_stats[k])
		unit["stats"] = src_stats
	var src_growths: Dictionary = unit.get("growths", {})
	var final_growths: Variant = final_unit.get("growths")
	if final_growths is Dictionary:
		for key in src_growths:
			var k := String(key)
			if final_growths.has(k):
				src_growths[k] = int(final_growths[k])
		unit["growths"] = src_growths
	var final_weapon: Variant = final_unit.get("weapon")
	if final_weapon is Dictionary and not (final_weapon as Dictionary).is_empty():
		unit["weapon"] = (final_weapon as Dictionary).duplicate(true)
	var final_skills: Variant = final_unit.get("skills")
	if final_skills is Array:
		var skills_out: Array = []
		for sid: Variant in final_skills:
			skills_out.append(StringName(String(sid)))
		unit["skills"] = skills_out
	# 装备槽随终局吸收（深拷贝，与 weapon 同口径；battle 内装备不被消耗/更换，
	# 这里保底保证战场上发生的装卸能回流档内）。
	var final_equipment: Variant = final_unit.get("equipment")
	if final_equipment is Dictionary and not (final_equipment as Dictionary).is_empty():
		unit["equipment"] = (final_equipment as Dictionary).duplicate(true)


## Hub 归一化（对传入单位原地生效，调用方负责传副本）：
## 满 HP/MP（容量=base+装备）、复活、清行动标记/增益/技能冷却。
static func _normalize_hub_unit(unit: Dictionary) -> void:
	var stats: Dictionary = unit.get("stats", {})
	unit["hp"] = EquipmentDataScript.capacity_hp(unit) if int(stats.get("hp", 0)) > 0 else int(unit.get("hp", 1))
	unit["mp"] = EquipmentDataScript.capacity_mp(unit) if int(stats.get("mp", 0)) > 0 else int(unit.get("mp", 0))
	unit["isDead"] = false
	unit["hasMoved"] = false
	unit["hasActed"] = false
	unit["buffs"] = []
	unit["skillCooldowns"] = {}


## 从库存取走第一个匹配 id 的实例（就地删除）；无货返回 {}。
static func _take_inventory_instance(inventory: Array, iid: StringName) -> Dictionary:
	for i in inventory.size():
		var raw: Variant = inventory[i]
		if raw is Dictionary and StringName(String(raw.get("id", ""))) == iid:
			var inst: Dictionary = raw
			inventory.remove_at(i)
			return {"id": iid, "uses": int(inst.get("uses", 0))}
	return {}
