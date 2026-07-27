## core/items.gd — 物品系统（仿 skills.gd 的 JSON + 懒加载模式）
## 从 res://data/items.json 加载。ItemData 用 Dictionary 表达（全 StringName key）。
##
## 物品字段：
##   id, name, desc, type(consumable/throwable/equip/buff),
##   target(self/ally/enemy/aoe_enemy), effect(heal_hp/heal_mp/damage/buff/cleanse/equip),
##   power, range:[min,max], uses, stat, buffValue, buffTurns, equipStat, equipValue

class_name ItemData
extends RefCounted

static var _config: Dictionary = {}
static var _items: Dictionary = {}        # { id -> item dict }
static var _list: Array = []              # [item dict, ...]（保持 json 顺序）
static var _default_id: StringName = &"hpPotion"
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var path := "res://data/items.json"
	var text := ""
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			text = f.get_as_text()
	if text.is_empty():
		push_error("ItemData: 无法加载 %s" % path)
		return
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("ItemData: items.json 解析失败: %s" % json.get_error_message())
		return
	_config = json.data
	_default_id = StringName(_config.get("defaultItem", "hpPotion"))
	_list = _config.get("items", [])
	_items.clear()
	for it in _list:
		var d := _normalize(it)
		_items[d[&"id"]] = d
	_list = _list.map(_normalize)


static func _normalize(s: Dictionary) -> Dictionary:
	var g := func(k: String): return s.get(k)
	var r: Array = g.call("range") if g.call("range") != null else [0, 0]
	var d := {
		id = StringName(g.call("id")),
		name = String(g.call("name")),
		desc = String(g.call("desc")),
		type = StringName(g.call("type")),
		target = StringName(g.call("target")),
		effect = StringName(g.call("effect")),
		power = int(g.call("power")) if g.call("power") != null else 0,
		range = [int(r[0]), int(r[1])],
		uses = int(g.call("uses")) if g.call("uses") != null else 1,
		stat = StringName(g.call("stat")) if g.call("stat") != null else &"",
		buffValue = int(g.call("buffValue")) if g.call("buffValue") != null else 0,
		buffTurns = int(g.call("buffTurns")) if g.call("buffTurns") != null else 0,
		equipStat = StringName(g.call("equipStat")) if g.call("equipStat") != null else &"",
		equipValue = int(g.call("equipValue")) if g.call("equipValue") != null else 0,
	}
	return d


static func get_item(item_id: StringName) -> Dictionary:
	_ensure_loaded()
	if _items.has(item_id):
		return _items[item_id]
	return _items.get(_default_id, {})


static var ITEM_LIST: Array:
	get:
		_ensure_loaded()
		return _list


static func item_name(item_id: StringName) -> String:
	_ensure_loaded()
	if _items.has(item_id):
		return _items[item_id][&"name"]
	return String(item_id)


## 背包里「当前可用」的物品条目（uses > 0，且非装备类）。
## 返回 [{entry: {id,uses}, def: item dict}, ...]，供战斗菜单/AI 使用。
static func usable_items(unit: Dictionary) -> Array:
	_ensure_loaded()
	var out: Array = []
	for entry in unit.get(&"items", []):
		var eid = entry.get(&"id", &"")
		var uses: int = int(entry.get(&"uses", 0))
		if uses <= 0 or not _items.has(eid):
			continue
		var idef: Dictionary = _items[eid]
		# 装备类不在战斗中「使用」，单独走 equip 流程
		if idef[&"type"] == &"equip":
			continue
		out.append({ &"entry": entry, &"def": idef })
	return out


## 装备类物品条目（供装备菜单）。
static func equipable_items(unit: Dictionary) -> Array:
	_ensure_loaded()
	var out: Array = []
	for entry in unit.get(&"items", []):
		var eid = entry.get(&"id", &"")
		var uses: int = int(entry.get(&"uses", 0))
		if uses <= 0 or not _items.has(eid):
			continue
		var idef: Dictionary = _items[eid]
		if idef[&"type"] == &"equip":
			out.append({ &"entry": entry, &"def": idef })
	return out


## 给新建单位一份默认初始背包（每职业通用，消耗品为主）。
const DEFAULT_ITEMS := [
	{ id = &"hpPotion", uses = 2 },
	{ id = &"mpPotion", uses = 1 },
]
