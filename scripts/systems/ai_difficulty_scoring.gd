## systems/ai_difficulty_scoring.gd — 难度参数化的候选评分（纯函数，无状态）
##
## 从 EnemyAI 的历史评分公式参数化而来：normal 档下各函数与原公式逐值相等。
## 消费方：EnemyAI（普攻/技能/物品候选）、PlayerAI（策略叠加残血集火）。

class_name AIDifficultyScoring
extends RefCounted


## 普攻候选评分。prev = CombatSystem.preview 结果。
## 历史公式（normal 等价）：atkDmg*2 + double 追击伤害 + 可击杀 5000 - defDmg*1.0
static func attack_score(prev: Dictionary, target: Dictionary, prof: Dictionary) -> float:
	var dmg: int = int(prev[&"atkDmg"])
	var s: float = float(dmg * 2 + (dmg if bool(prev[&"doubleAttack"]) else 0))
	if dmg >= int(target[&"hp"]):
		s += float(prof[&"kill_bonus"])
	s -= float(prev[&"defDmg"]) * float(prof[&"counter_weight"])
	s += focus_bonus(target, prof)
	return s


## 残血集火加分 = 目标已损血量 × focus_wounded（权重 ≤0 时恒 0）。
static func focus_bonus(target: Dictionary, prof: Dictionary) -> float:
	var w := float(prof[&"focus_wounded"])
	if w <= 0.0 or bool(target.get(&"isDead", false)):
		return 0.0
	var missing := int(target[&"stats"][&"hp"]) - int(target[&"hp"])
	if missing <= 0:
		return 0.0
	return float(missing) * w


## 候选替换判定：best 档取更高分；worst 档（新手）取更低分。
static func better(candidate: float, current: float, prof: Dictionary) -> bool:
	if prof[&"selection"] == &"worst":
		return candidate < current
	return candidate > current


## 无行动候选时是否追击（novice 原地待命）。
static func should_pursue(prof: Dictionary) -> bool:
	return bool(prof[&"pursue"])
