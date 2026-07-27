## core/enums.gd — 核心枚举（对应 src/types.ts）
## 用 StringName enum，便于和 JSON 字符串互转。
## 作为纯静态常量类使用：Enums.FACTION_PLAYER 等。

class_name Enums
extends RefCounted

# Faction
const FACTION_PLAYER := &"player"
const FACTION_ENEMY := &"enemy"
const FACTION_ALLY := &"ally"
const FACTION_OTHER := &"other"
const FACTIONS: Array[StringName] = [
	&"player", &"enemy", &"ally", &"other",
]

# WeaponType
const WEAPON_SWORD := &"sword"
const WEAPON_LANCE := &"lance"
const WEAPON_AXE := &"axe"
const WEAPON_BOW := &"bow"
const WEAPON_ANIMA := &"anima"
const WEAPON_DARK := &"dark"
const WEAPON_STAFF := &"staff"
const WEAPON_TYPES: Array[StringName] = [
	&"sword", &"lance", &"axe", &"bow", &"anima", &"dark", &"staff",
]

# MoveType
const MOVE_FOOT := &"foot"
const MOVE_ARMOR := &"armor"
const MOVE_CAVALRY := &"cavalry"
const MOVE_FLYING := &"flying"
const MOVE_TYPES: Array[StringName] = [&"foot", &"armor", &"cavalry", &"flying"]

# TerrainType
const TERRAIN_PLAIN := &"plain"
const TERRAIN_FOREST := &"forest"
const TERRAIN_MOUNTAIN := &"mountain"
const TERRAIN_WATER := &"water"
const TERRAIN_FORT := &"fort"
const TERRAIN_VILLAGE := &"village"
const TERRAIN_WALL := &"wall"
const TERRAIN_TYPES: Array[StringName] = [
	&"plain", &"forest", &"mountain", &"water", &"fort", &"village", &"wall",
]

# SkillType（技能效果类型）
const SKILL_DAMAGE := &"damage"   # 单体伤害
const SKILL_HEAL := &"heal"       # 单体治疗
const SKILL_AOE := &"aoe"         # 范围伤害
const SKILL_BUFF := &"buff"       # 增益
const SKILL_DEBUFF := &"debuff"   # 减益
const SKILL_TYPES: Array[StringName] = [
	&"damage", &"heal", &"aoe", &"buff", &"debuff",
]

# ItemType（物品类型）
const ITEM_CONSUMABLE := &"consumable"   # 消耗品
const ITEM_THROWABLE := &"throwable"     # 投掷物
const ITEM_EQUIP := &"equip"             # 装备类
const ITEM_BUFF := &"buff"               # buff 道具
const ITEM_TYPES: Array[StringName] = [
	&"consumable", &"throwable", &"equip", &"buff",
]

# TargetType（技能/物品的目标类型）
const TARGET_SELF := &"self"
const TARGET_ALLY := &"ally"
const TARGET_ENEMY := &"enemy"
const TARGET_AOE_ALLY := &"aoe_ally"
const TARGET_AOE_ENEMY := &"aoe_enemy"
const TARGET_TYPES: Array[StringName] = [
	&"self", &"ally", &"enemy", &"aoe_ally", &"aoe_enemy",
]
