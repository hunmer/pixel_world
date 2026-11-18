## battle_action_history.gd — 玩家行动记录与回退（整场战斗粒度）
## 记录玩家每次已结算行动的快照；点【记录】Tab 条目回退到该行动之前。
## 历史 = [baseline(战斗首个玩家回合开始), 每次已结算行动后的快照...]，
## 整场战斗累积，跨回合可回退；回合数与增援波次一并快照/恢复。

class_name BattleActionHistory
extends RefCounted

## 战斗开始（首个玩家回合开始）快照；{} = 尚未开始记录
var baseline: Dictionary = {}
## 每条：{label: String, turn: int, snapshot: Dictionary}
var entries: Array = []


## 深拷贝单位与掉落（+回合数+未刷的增援波次）。
## duplicate(true) 防快照被后续战斗修改污染（同一 baseline 可能被多次回退应用）。
static func take_snapshot(units: Array, loot: Array, reinforcements: Array, turn_number: int) -> Dictionary:
	var snap_units: Dictionary = {}
	for u in units:
		var unit: Dictionary = u
		snap_units[unit[&"id"]] = unit.duplicate(true)
	return {
		&"units": snap_units,
		&"loot": (loot as Array).duplicate(true),
		&"reinforcements": (reinforcements as Array).duplicate(true),
		&"turn": turn_number,
	}


## 战斗首个玩家回合开始记一次 baseline；后续回合不再重置（整场累积）。
func ensure_baseline(units: Array, loot: Array, reinforcements: Array, turn_number: int = 1) -> void:
	if not baseline.is_empty():
		return
	baseline = take_snapshot(units, loot, reinforcements, turn_number)
	entries.clear()


func clear_all() -> void:
	baseline = {}
	entries.clear()


## 记一条已结算行动（在结算完成后调用）。
func record(label: String, units: Array, loot: Array, reinforcements: Array, turn_number: int) -> void:
	entries.append({
		"label": label,
		"turn": turn_number,
		"snapshot": take_snapshot(units, loot, reinforcements, turn_number),
	})


## 点第 index 条（0-based）→ 恢复到该行动开始之前：
## index==0 → baseline（战斗开始）；否则 → entries[index-1].snapshot。
func rewind_target(index: int) -> Dictionary:
	if index < 0 or index > entries.size():
		return {}
	if index == 0:
		return baseline
	return entries[index - 1].snapshot


## 回退到第 index 条之前后，截掉该条及其后所有记录。
func truncate_after_rewind(index: int) -> void:
	if index < 0 or index > entries.size():
		return
	entries.resize(index)


## 展示标签（带回合前缀），顺序即记录顺序。
func labels() -> Array:
	var out: Array = []
	for e in entries:
		out.append("T%d · %s" % [int(e.turn), String(e.label)])
	return out
