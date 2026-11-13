## systems/ai_difficulty.gd — AI 难度档位：名称常量、校验与评分 profile 参数
##
## 四档：novice（新手）/ normal（普通，与历史行为逐值等价）/ hard（困难）/ nightmare（噩梦）。
## 本文件只负责「档位元数据 + profile 参数」；评分公式在 ai_difficulty_scoring.gd，
## 决策器（EnemyAI/PlayerAI）消费两者。拆分目的：难度配置与评分逻辑职责分离。

class_name AIDifficulty
extends RefCounted


const NOVICE := &"novice"
const NORMAL := &"normal"
const HARD := &"hard"
const NIGHTMARE := &"nightmare"

## 未声明难度时的缺省档（兼容历史行为）。
const DEFAULT := NORMAL

## UI / 配置可选项（key=StringName，value=中文标签）。
const OPTIONS: Array = [
	{ &"id": NOVICE, &"label": "新手" },
	{ &"id": NORMAL, &"label": "普通" },
	{ &"id": HARD, &"label": "困难" },
	{ &"id": NIGHTMARE, &"label": "噩梦" },
]

const VALID: Array = [NOVICE, NORMAL, HARD, NIGHTMARE]


## 校验难度名是否合法（String/StringName 均可）。
static func validate(name) -> bool:
	return VALID.has(StringName(name))


## 归一化：非法 / 缺失回 DEFAULT（运行时宽容；声明式入口由 loader 严格校验报错）。
static func normalize(name) -> StringName:
	if validate(name):
		return StringName(name)
	return DEFAULT


## 难度 profile（评分参数包）。键：
##   kill_bonus        普攻可击杀加分（novice=0 → 无击杀意识）
##   skill_kill_bonus  技能可击杀加分
##   item_kill_bonus   物品可击杀加分
##   counter_weight    反击风险惩罚权重（novice=0 → 无视反击）
##   focus_wounded     残血集火权重（× 目标已损血量；0=不集火）
##   selection         候选选择策略：best（最高分）/ worst（最低分，新手呆滞）
##   pursue            无行动候选时是否朝最近敌人移动（novice=原地待命）
## normal 档参数与 EnemyAI 历史公式逐值相等（kill 5000/4000/3000、反击 ×1.0）。
static func profile(name) -> Dictionary:
	match normalize(name):
		NOVICE:
			return {
				&"kill_bonus": 0, &"skill_kill_bonus": 0, &"item_kill_bonus": 0,
				&"counter_weight": 0.0, &"focus_wounded": 0.0,
				&"selection": &"worst", &"pursue": false,
			}
		HARD:
			return {
				&"kill_bonus": 12000, &"skill_kill_bonus": 10000, &"item_kill_bonus": 8000,
				&"counter_weight": 2.0, &"focus_wounded": 3.0,
				&"selection": &"best", &"pursue": true,
			}
		NIGHTMARE:
			return {
				&"kill_bonus": 20000, &"skill_kill_bonus": 16000, &"item_kill_bonus": 12000,
				&"counter_weight": 3.0, &"focus_wounded": 8.0,
				&"selection": &"best", &"pursue": true,
			}
		_:
			return {
				&"kill_bonus": 5000, &"skill_kill_bonus": 4000, &"item_kill_bonus": 3000,
				&"counter_weight": 1.0, &"focus_wounded": 0.0,
				&"selection": &"best", &"pursue": true,
			}
