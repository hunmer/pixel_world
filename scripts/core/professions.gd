## core/professions.gd — 职业系统（对应 src/data/professions.ts）
## 从 res://data/professions.json 加载。ProfessionData 用 Dictionary 表达。
##
## 约定（与 TS 版一致）：
##   power 统一表示主攻击属性，apply_profession 按武器类型写入 str（物理）或 mag（魔法）。
##   agility → spd。attack_range 是职业固有属性，优先于武器射程。

class_name ProfessionData
extends RefCounted

static var _config: Dictionary = {}        # 解析后的整份 json
static var _professions: Dictionary = {}    # { id -> ProfessionData dict }
static var _list: Array = []                # [ProfessionData dict, ...]（保持 json 顺序）
static var _default_id: StringName = &"swordsman"
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var path := "res://data/professions.json"
	var text := ""
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			text = f.get_as_text()
	if text.is_empty():
		push_error("ProfessionData: 无法加载 %s" % path)
		return
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("ProfessionData: professions.json 解析失败: %s" % json.get_error_message())
		return
	_config = json.data
	_default_id = StringName(_config.get("defaultProfession", "swordsman"))
	_list = _config.get("professions", [])
	_professions.clear()
	for p in _list:
		# 把 json 的字符串 key 归一化：attackRange/weaponType/moveType 等转 StringName
		var d := _normalize(p)
		_professions[d[&"id"]] = d
	_list = _list.map(_normalize)


## 把 json 里的一条职业 dict 重建为「全部 StringName key」的结构。
## json 解析出的 key 是 String，全文用 &"x" 访问，必须统一。
static func _normalize(p: Dictionary) -> Dictionary:
	var g := func(s: String): return p.get(s)           # 取原始 String key 的值
	var ar: Array = g.call("attackRange") if g.call("attackRange") != null else [1, 1]
	# animations 数组归一化（name 转 StringName，其余 frame 参数保留）
	var anims_out: Array = []
	var anims_in: Array = g.call("animations") if g.call("animations") != null else []
	for a in anims_in:
		var ad: Dictionary = a
		var an := {}
		for k in ad.keys():
			if k == "name":
				an[&"name"] = StringName(ad[k])
			else:
				an[StringName(k)] = ad[k]
		anims_out.append(an)
	return {
		id = StringName(g.call("id")),
		name = String(g.call("name")),
		title = String(g.call("title")),
		hp = int(g.call("hp")),
		power = int(g.call("power")),
		agility = int(g.call("agility")),
		attackRange = [int(ar[0]), int(ar[1])],
		weaponType = StringName(g.call("weaponType")),
		moveType = StringName(g.call("moveType")),
		skl = int(g.call("skl")),
		luk = int(g.call("luk")),
		def = int(g.call("def")),
		res = int(g.call("res")),
		mov = int(g.call("mov")),
		image = String(g.call("image")),
		defaultAnimation = StringName(g.call("defaultAnimation")) if g.call("defaultAnimation") != null else &"",
		animations = anims_out,
	}


## 获取职业（缺失回退默认职业）
static func get_profession(class_id: StringName) -> Dictionary:
	_ensure_loaded()
	if _professions.has(class_id):
		return _professions[class_id]
	return _professions.get(_default_id, {})


static var DEFAULT_PROFESSION: Dictionary:
	get:
		_ensure_loaded()
		return _professions.get(_default_id, {})


static var PROFESSION_LIST: Array:
	get:
		_ensure_loaded()
		return _list


## 职业池（玩家/敌人当前相同）
static func player_pool() -> Array:
	_ensure_loaded()
	return _list

static func enemy_pool() -> Array:
	_ensure_loaded()
	return _list


static func random_profession(pool: Array = []) -> Dictionary:
	_ensure_loaded()
	var p := pool if not pool.is_empty() else _list
	if p.is_empty():
		return DEFAULT_PROFESSION
	return p[randi() % p.size()]


## 把职业属性写入 UnitData（mutates unit dict）。
## 对应 professions.ts 的 applyProfession。
static func apply_profession(unit: Dictionary, prof: Dictionary) -> Dictionary:
	var physical := WeaponData.is_physical(prof[&"weaponType"])
	unit[&"classId"] = prof[&"id"]
	unit[&"moveType"] = prof[&"moveType"]
	var ar: Array = prof[&"attackRange"]
	unit[&"attackRange"] = [ar[0], ar[1]]
	var stats: Dictionary = unit[&"stats"]
	stats[&"hp"] = prof[&"hp"]
	stats[&"spd"] = prof[&"agility"]
	stats[&"str"] = prof[&"power"] if physical else 0
	stats[&"mag"] = 0 if physical else prof[&"power"]
	stats[&"skl"] = prof[&"skl"]
	stats[&"luk"] = prof[&"luk"]
	stats[&"def"] = prof[&"def"]
	stats[&"res"] = prof[&"res"]
	stats[&"mov"] = prof[&"mov"]
	unit[&"hp"] = prof[&"hp"]
	return unit


## 返回 [min, max] 攻击范围（职业固有优先，回退武器射程）
static func unit_attack_range(unit: Dictionary) -> Array:
	if unit.has(&"attackRange") and unit[&"attackRange"] != null:
		var r: Array = unit[&"attackRange"]
		return [r[0], r[1]]
	var w: Dictionary = unit[&"weapon"]
	var wr: Array = w[&"range"]
	return [wr[0], wr[1]]


static func profession_name(class_id: StringName) -> String:
	_ensure_loaded()
	if _professions.has(class_id):
		return _professions[class_id][&"name"]
	return String(class_id)


## 职业 → 默认武器 id（chapter1 / UnitFactory 共用）
static func default_weapon_for_class(class_id: StringName) -> StringName:
	var prof := get_profession(class_id)
	if prof.is_empty():
		return &"ironSword"
	return WeaponData.default_weapon_for_type(prof[&"weaponType"])
