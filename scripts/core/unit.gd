## core/unit.gd — UnitData 构造与默认成长率（对应 types.ts 的 UnitData + chapter1 的默认值）
##
## UnitData 用 Dictionary 表达：
##   {
##     id, name, classId, faction, level, exp,
##     stats: { hp,mp,str,mag,skl,spd,luk,def,res,mov },  # mp 在 stats 里作 MP 上限
##     growths: { hp,mp,str,mag,skl,spd,luk,def,res },
##     weapon: Weapon dict,
##     moveType, attackRange:[min,max],
##     hp, mp, position:{x,y}, hasMoved, hasActed, isDead,  # mp 是当前 MP（上限=stats.mp）
##     skills:[StringName], skillCooldowns:{skillId->int},  # 技能 + 冷却
##     items:[{id,uses}], buffs:[{stat,value,turns,label}]  # 背包 + 临时状态
##   }
## Stats/Growths 用 Dictionary（key=StringName）。

class_name UnitFactory
extends RefCounted

## 默认成长率（与 TS 版 chapter1.ts / levelToChapter.ts 的 DEFAULT_GROWTHS 一致）
const DEFAULT_GROWTHS := {
	&"hp": 70, &"mp": 20, &"str": 45, &"mag": 15, &"skl": 45, &"spd": 45,
	&"luk": 40, &"def": 30, &"res": 25,
}


static func empty_stats() -> Dictionary:
	return {
		&"hp": 0, &"mp": 0, &"str": 0, &"mag": 0, &"skl": 0,
		&"spd": 0, &"luk": 0, &"def": 0, &"res": 0, &"mov": 0,
	}


static func default_growths() -> Dictionary:
	return DEFAULT_GROWTHS.duplicate()


## 以随机职业创建单位（对应 chapter1.ts 的 createRandomUnit）。
## force_profession 不传则从对应阵营池随机。
## 创建后会塞职业默认技能 + 默认初始背包，并把当前 MP 补满。
static func create_random_unit(
	id: StringName, uname: String, faction: StringName, level: int,
	pos: Vector2i, force_profession: Dictionary = {}
) -> Dictionary:
	var pool := ProfessionData.enemy_pool() if faction == &"enemy" else ProfessionData.player_pool()
	var prof: Dictionary = force_profession if not force_profession.is_empty() else ProfessionData.random_profession(pool)
	var unit := _base_unit(id, uname, faction, level, pos, prof)
	ProfessionData.apply_profession(unit, prof) # 写入 生命/力量/敏捷/攻击范围 + 次要属性
	_apply_default_skills_and_items(unit, prof) # 写入 默认技能 + 初始背包 + 补满 MP
	return unit


## 给单位塞职业默认技能 + 默认初始背包，并把当前 MP 补满到上限。
## 职业 JSON 有 defaultSkills/defaultItems 时优先用；否则回退到 SkillData 按武器类型的推荐。
static func _apply_default_skills_and_items(unit: Dictionary, prof: Dictionary) -> void:
	# MP 上限：由职业 hp 衍生（魔法系更高），存 stats.mp；当前 mp 补满
	var stats: Dictionary = unit[&"stats"]
	if int(stats.get(&"mp", 0)) == 0:
		stats[&"mp"] = default_max_mp_for(prof)
	unit[&"mp"] = stats[&"mp"]
	# 技能：职业 JSON 显式配置优先，否则回退推荐
	var skill_ids: Array = prof.get(&"defaultSkills", [])
	if skill_ids.is_empty():
		skill_ids = SkillData.DEFAULT_SKILLS_BY_WEAPON_TYPE.get(prof.get(&"weaponType", &""), [])
	# 转 StringName 去重
	var owned: Dictionary = {}
	for sid in unit.get(&"skills", []):
		owned[sid] = true
	for sid in skill_ids:
		var sn: StringName = StringName(sid)
		if not owned.has(sn):
			(unit[&"skills"] as Array).append(sn)
			owned[sn] = true
	# 初始背包：职业 JSON 显式配置优先，否则用默认消耗品
	var item_ids: Array = prof.get(&"defaultItems", [])
	if item_ids.is_empty():
		for ie in ItemData.DEFAULT_ITEMS:
			(unit[&"items"] as Array).append({ id = ie.id, uses = ie.uses })
	else:
		for ie in item_ids:
			var e: Dictionary = ie
			(unit[&"items"] as Array).append({ id = StringName(e.get(&"id", &"")), uses = int(e.get(&"uses", 1)) })


## 推导职业的默认 MP 上限：魔法系（anima/dark/staff）给较高上限。
## 公开（default_max_mp_for），供 level_to_chapter 兜底用。
static func default_max_mp_for(prof: Dictionary) -> int:
	var wt: StringName = prof.get(&"weaponType", &"")
	match wt:
		&"anima", &"dark":
			return 30
		&"staff":
			return 24
		_:
			return 12


## 基础骨架（数值未填，apply_profession 前的通用起点）
static func _base_unit(
	id: StringName, uname: String, faction: StringName, level: int,
	pos: Vector2i, prof: Dictionary
) -> Dictionary:
	var w: Dictionary = WeaponData.WEAPONS[ProfessionData.default_weapon_for_class(prof[&"id"])].duplicate(true)
	return {
		id = id,
		name = uname,
		classId = prof[&"id"],
		faction = faction,
		level = level,
		exp = 0,
		stats = empty_stats(),
		growths = default_growths(),
		weapon = w,
		moveType = prof[&"moveType"],
		attackRange = [0, 0],
		hp = prof.get(&"hp", 1),
		mp = 0,                       # 当前 MP（上限由 stats.mp 表达，apply_profession 后补）
		position = pos,
		hasMoved = false,
		hasActed = false,
		isDead = false,
		skills = [],                  # [skillId:StringName, ...]
		skillCooldowns = {},          # {skillId -> 剩余回合}
		items = [],                   # [{id, uses}, ...]
		buffs = [],                   # [{stat, value, turns, label}, ...]
	}


## 从职业创建默认 PlacedUnit（对应 editor/UnitFactory.ts 的 createUnit）。
## PlacedUnit 结构与 UnitData 对齐但精简：只存 weaponId/skillIds/itemIds，stats 含 mov。
static func create_placed_unit(
	class_id: StringName, cell_x: int, cell_y: int,
	opts: Dictionary = {}
) -> Dictionary:
	var prof := ProfessionData.get_profession(class_id)
	var physical := WeaponData.is_physical(prof[&"weaponType"])
	return {
		id = _gen_id(),
		cellX = cell_x,
		cellY = cell_y,
		name = opts.get(&"name", prof[&"name"]),
		classId = prof[&"id"],
		faction = opts.get(&"faction", &"player"),
		level = opts.get(&"level", 1),
		stats = {
			hp = prof[&"hp"], mp = 0,
			str = prof[&"power"] if physical else 0,
			mag = 0 if physical else prof[&"power"],
			skl = prof[&"skl"], spd = prof[&"agility"],
			luk = prof[&"luk"], def = prof[&"def"], res = prof[&"res"],
			mov = prof[&"mov"],
		},
		weaponId = ProfessionData.default_weapon_for_class(class_id),
		currentHp = prof[&"hp"],
		skillIds = opts.get(&"skillIds", []),   # [StringName, ...] 可选，向后兼容
		itemIds = opts.get(&"itemIds", []),     # [StringName, ...] 可选，向后兼容
	}


## 切换职业（保留 id/位置/阵营/等级），对应 reclass
static func reclass(unit: Dictionary, new_class_id: StringName) -> Dictionary:
	var fresh := create_placed_unit(new_class_id, unit[&"cellX"], unit[&"cellY"], {
		&"name": unit[&"name"],
		&"faction": unit[&"faction"],
		&"level": unit[&"level"],
	})
	fresh[&"id"] = unit[&"id"]
	return fresh


static func _gen_id() -> StringName:
	var t := Time.get_ticks_msec()
	return StringName("u_%d_%d" % [t, randi() % 1000000])
