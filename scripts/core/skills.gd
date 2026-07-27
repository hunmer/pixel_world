## core/skills.gd — 技能系统（仿 professions.gd 的 JSON + 懒加载模式）
## 从 res://data/skills.json 加载。SkillData 用 Dictionary 表达（全 StringName key）。
##
## 技能字段：
##   id, name, desc, type(damage/heal/aoe/buff/debuff), element,
##   range:[min,max], targetType(self/ally/enemy/aoe_ally/aoe_enemy),
##   mpCost, cooldown, power, hitBonus,
##   stat(str/mag/def/...), buffValue, buffTurns（buff/debuff 用）

class_name SkillData
extends RefCounted

static var _config: Dictionary = {}
static var _skills: Dictionary = {}      # { id -> skill dict }
static var _list: Array = []              # [skill dict, ...]（保持 json 顺序）
static var _default_id: StringName = &"fireball"
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var path := "res://data/skills.json"
	var text := ""
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			text = f.get_as_text()
	if text.is_empty():
		push_error("SkillData: 无法加载 %s" % path)
		return
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("SkillData: skills.json 解析失败: %s" % json.get_error_message())
		return
	_config = json.data
	_default_id = StringName(_config.get("defaultSkill", "fireball"))
	_list = _config.get("skills", [])
	_skills.clear()
	for s in _list:
		var d := _normalize(s)
		_skills[d[&"id"]] = d
	_list = _list.map(_normalize)


## 把 json 的一条技能 dict 重建为全 StringName key 结构。
static func _normalize(s: Dictionary) -> Dictionary:
	var g := func(k: String): return s.get(k)
	var r: Array = g.call("range") if g.call("range") != null else [1, 1]
	var d := {
		id = StringName(g.call("id")),
		name = String(g.call("name")),
		desc = String(g.call("desc")),
		type = StringName(g.call("type")),
		element = StringName(g.call("element")),
		range = [int(r[0]), int(r[1])],
		targetType = StringName(g.call("targetType")),
		mpCost = int(g.call("mpCost")),
		cooldown = int(g.call("cooldown")),
		power = int(g.call("power")),
		hitBonus = int(g.call("hitBonus")) if g.call("hitBonus") != null else 100,
		stat = StringName(g.call("stat")) if g.call("stat") != null else &"",
		buffValue = int(g.call("buffValue")) if g.call("buffValue") != null else 0,
		buffTurns = int(g.call("buffTurns")) if g.call("buffTurns") != null else 0,
	}
	return d


static func get_skill(skill_id: StringName) -> Dictionary:
	_ensure_loaded()
	if _skills.has(skill_id):
		return _skills[skill_id]
	return _skills.get(_default_id, {})


static var SKILL_LIST: Array:
	get:
		_ensure_loaded()
		return _list


static func skill_name(skill_id: StringName) -> String:
	_ensure_loaded()
	if _skills.has(skill_id):
		return _skills[skill_id][&"name"]
	return String(skill_id)


## 该单位已学技能中「当前可用」的（MP 足、冷却为 0）。
## 供战斗菜单/AI 使用。返回 [skill dict, ...]。
static func usable_skills(unit: Dictionary) -> Array:
	_ensure_loaded()
	var out: Array = []
	var cd: Dictionary = unit.get(&"skillCooldowns", {})
	var mp: int = int(unit.get(&"mp", 0))
	for sid in unit.get(&"skills", []):
		if not _skills.has(sid):
			continue
		var sk: Dictionary = _skills[sid]
		if int(cd.get(sid, 0)) > 0:
			continue
		if int(sk[&"mpCost"]) > mp:
			continue
		out.append(sk)
	return out


## 该单位已学的全部技能（不考虑 MP/冷却），编辑器/信息面板用。
static func owned_skills(unit: Dictionary) -> Array:
	_ensure_loaded()
	var out: Array = []
	for sid in unit.get(&"skills", []):
		if _skills.has(sid):
			out.append(_skills[sid])
	return out


## 给职业配默认技能（professions.json 的 defaultSkills 字段引用）。
## 这里提供一份「按职业 weaponType 推荐的默认技能」映射，供 create_random_unit 兜底。
const DEFAULT_SKILLS_BY_WEAPON_TYPE := {
	&"anima": [&"fireball", &"blizzard", &"heal"],
	&"dark": [&"weaken"],
	&"staff": [&"heal", &"haste"],
	&"sword": [&"smite", &"powerSurge"],
	&"lance": [&"smite", &"guard"],
	&"axe": [&"smite"],
	&"bow": [&"powerSurge"],
}
