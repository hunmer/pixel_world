## systems/buff_system.gd — buff/属性修正工具（全静态，零依赖）
##
## 从 SkillSystem 抽出来的低层模块，打破 CombatSystem ↔ SkillSystem 的循环依赖：
##   CombatSystem 取属性时要算 buff → 依赖 SkillSystem；
##   SkillSystem 又是上层 → 形成 class_name 编译期循环。
## 解法：把 effective_stat / apply_buff / tick_buffs / cleanse 放到这里（不依赖任何战斗类），
##   CombatSystem 和 SkillSystem 都只单向依赖 BuffSystem。
##
## buff 数据结构（挂在 unit.buffs）：{ stat:StringName, value:int, turns:int, label:String }

class_name BuffSystem
extends RefCounted


## 取单位某项属性的「实际值」= 基础 stats + 所有 buff 累计。
static func effective_stat(unit: Dictionary, stat: StringName) -> int:
	var base: int = int(unit[&"stats"].get(stat, 0))
	var total: int = base
	for b in unit.get(&"buffs", []):
		if b.get(&"stat", &"") == stat:
			total += int(b.get(&"value", 0))
	return total


## 给单位挂一个 buff/debuff（同属性同 label 刷新时长并覆盖值）。
static func apply_buff(unit: Dictionary, stat: StringName, value: int, turns: int, label: String = "") -> void:
	var buffs: Array = unit.get(&"buffs", [])
	for b in buffs:
		if b.get(&"stat", &"") == stat and b.get(&"label", &"") == label:
			b[&"value"] = value
			b[&"turns"] = turns
			return
	buffs.append({ stat = stat, value = value, turns = turns, label = label })
	unit[&"buffs"] = buffs


## 每回合开始对所有单位的 buff 倒计时，turns<=0 的移除。
static func tick_buffs(units: Array) -> void:
	for u in units:
		if u.get(&"isDead", false):
			continue
		var buffs: Array = u.get(&"buffs", [])
		var remain: Array = []
		for b in buffs:
			b[&"turns"] = int(b.get(&"turns", 0)) - 1
			if int(b[&"turns"]) > 0:
				remain.append(b)
		u[&"buffs"] = remain


## 清除单位所有 debuff（value<0），返回移除数。
static func cleanse_debuffs(unit: Dictionary) -> int:
	var buffs: Array = unit.get(&"buffs", [])
	var remain: Array = []
	var removed := 0
	for b in buffs:
		if int(b.get(&"value", 0)) < 0:
			removed += 1
		else:
			remain.append(b)
	unit[&"buffs"] = remain
	return removed
