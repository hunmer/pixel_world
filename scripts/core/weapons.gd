## core/weapons.gd — 武器定义 + 武器三角 + 经验公式
## 对应 src/data/staticData.ts 的 WEAPONS / WEAPON_TRIANGLE / TRIANGLE_MODIFIER / 经验公式

class_name WeaponData
extends RefCounted

# WEAPONS: { weaponId -> Weapon Dictionary }
# Weapon = { id, name, type, might, hit, crit, range:[min,max] or int, weight, uses }
static var WEAPONS: Dictionary = {}

# WEAPON_TRIANGLE: { weaponType -> { strong_vs:[], weak_vs:[] } }
static var WEAPON_TRIANGLE: Dictionary = {}

# TRIANGLE_MODIFIER
static var TRIANGLE_MODIFIER: Dictionary = {}

# 武器类型是否物理（决定 power 写 str 还是 mag）
static var PHYSICAL_TYPES: Array[StringName] = [&"sword", &"lance", &"axe", &"bow"]


static func _static_init() -> void:
	WEAPONS = {
		&"ironSword":  _mk(&"ironSword",  &"铁剑",   &"sword", 5, 90, 0, 1,    5, 46),
		&"steelSword": _mk(&"steelSword", &"钢剑",   &"sword", 8, 80, 0, 1,    8, 30),
		&"ironLance":  _mk(&"ironLance",  &"铁枪",   &"lance", 7, 80, 0, 1,    6, 45),
		&"ironAxe":    _mk(&"ironAxe",    &"铁斧",   &"axe",   8, 70, 0, 1,    10, 45),
		&"ironBow":    _mk(&"ironBow",    &"铁弓",   &"bow",   6, 85, 0, [2,2],5, 45),
		&"fire":       _mk(&"fire",       &"火焰",   &"anima", 5, 90, 0, [1,2],4, 40),
		&"heal":       _mk(&"heal",       &"治疗杖", &"staff", 5, 100,0, [1,2],2, 30),
	}

	# 剑 → 斧 → 枪 → 剑；弓/魔法独立
	WEAPON_TRIANGLE = {
		&"sword": { &"strong_vs": [&"axe"],   &"weak_vs": [&"lance"] },
		&"lance": { &"strong_vs": [&"sword"], &"weak_vs": [&"axe"]   },
		&"axe":   { &"strong_vs": [&"lance"], &"weak_vs": [&"sword"] },
		&"bow":   { &"strong_vs": [],         &"weak_vs": [] },
		&"anima": { &"strong_vs": [],         &"weak_vs": [] },
		&"dark":  { &"strong_vs": [],         &"weak_vs": [] },
		&"staff": { &"strong_vs": [],         &"weak_vs": [] },
	}

	TRIANGLE_MODIFIER = {
		&"advantage":    { &"damage": 1,  &"hit": 15 },   # 相克：+1 伤害 +15 命中
		&"disadvantage": { &"damage": -1, &"hit": -15 },
	}


static func _mk(id: StringName, wname: String, type_: StringName, might: int, hit: int, crit: int, p_range, weight: int, uses: int) -> Dictionary:
	var r: Array[int] = []
	if p_range is Array:
		r = [int(p_range[0]), int(p_range[1])]
	else:
		r = [int(p_range), int(p_range)]
	# 用裸标识符 key：dict 字面量里裸 key 自动成为 StringName 字面量（&"id"）
	return {
		id = id,
		name = wname,
		type = type_,
		might = might,
		hit = hit,
		crit = crit,
		range = r, # [min, max]
		weight = weight,
		uses = uses,
	}


## 武器类型是否物理
static func is_physical(type_: StringName) -> bool:
	return PHYSICAL_TYPES.has(type_)


## 适配某职业武器类型的所有武器（编辑器武器下拉用）。
## 对应 Phaser UnitFactory.weaponsForClass，返回 [{ id, name }]。
static func weapons_for_class(class_id: StringName) -> Array:
	var prof := ProfessionData.get_profession(class_id)
	if prof.is_empty():
		return []
	var wtype: StringName = prof[&"weaponType"]
	var out: Array = []
	for wid in WEAPONS.keys():
		var w: Dictionary = WEAPONS[wid]
		if w[&"type"] == wtype:
			out.append({ id = w[&"id"], name = String(w[&"name"]) })
	return out


## 武器三角修正：返回 { damage, hit }
static func triangle_modifier(attacker_type: StringName, defender_type: StringName) -> Dictionary:
	var a: Dictionary = WEAPON_TRIANGLE.get(attacker_type, {})
	if a.is_empty():
		return { &"damage": 0, &"hit": 0 }
	if (a[&"strong_vs"] as Array).has(defender_type):
		return (TRIANGLE_MODIFIER[&"advantage"] as Dictionary).duplicate()
	if (a[&"weak_vs"] as Array).has(defender_type):
		return (TRIANGLE_MODIFIER[&"disadvantage"] as Dictionary).duplicate()
	return { &"damage": 0, &"hit": 0 }


# ---------- 经验公式 ----------
static func exp_for_kill(enemy_level: int) -> int:
	return 30 + enemy_level * 3

static func exp_for_hit(enemy_level: int, attacker_level: int) -> int:
	return max(1, 10 + (enemy_level - attacker_level))

static func exp_to_next(level: int) -> int:
	return 50 + level * 30


## 按职业 weaponType 选默认武器 id（chapter1/UnitFactory 共用）
static var DEFAULT_WEAPON_BY_TYPE: Dictionary = {
	&"sword": &"ironSword",
	&"lance": &"ironLance",
	&"axe":   &"ironAxe",
	&"bow":   &"ironBow",
	&"anima": &"fire",
	&"dark":  &"fire",
	&"staff": &"heal",
}

static func default_weapon_for_type(type_: StringName) -> StringName:
	return WeaponData.DEFAULT_WEAPON_BY_TYPE.get(type_, &"ironSword")
