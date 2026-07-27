## systems/turn_manager.gd — 回合调度（对应 src/systems/TurnManager.ts）
## TS 版继承 Phaser.Events.EventEmitter；这里用 Godot signal 替代。
## 用法：作为子节点 add_child；发 phase_player / phase_enemy 信号。

class_name TurnManager
extends Node

signal phase_player(turn_number: int)
signal phase_enemy(turn_number: int)

var phase: StringName = &"player"
var turn_number: int = 1
var units: Array = [] # [UnitData dict, ...]


func _init(p_units: Array = []) -> void:
	units = p_units


func start_player_phase() -> void:
	phase = &"player"
	for u in units:
		if u[&"faction"] == &"player":
			u[&"hasMoved"] = false
			u[&"hasActed"] = false
			_tick_cooldowns(u)
	SkillSystem.tick_buffs(units)
	phase_player.emit(turn_number)


func start_enemy_phase() -> void:
	phase = &"enemy"
	for u in units:
		if u[&"faction"] == &"enemy":
			u[&"hasMoved"] = false
			u[&"hasActed"] = false
			_tick_cooldowns(u)
	SkillSystem.tick_buffs(units)
	phase_enemy.emit(turn_number)


## 技能冷却 -1（≥0），在该单位所属阵营回合开始时调用。
func _tick_cooldowns(u: Dictionary) -> void:
	var cd: Dictionary = u.get(&"skillCooldowns", {})
	if cd.is_empty():
		return
	for sid in cd.keys():
		cd[sid] = maxi(0, int(cd[sid]) - 1)
	u[&"skillCooldowns"] = cd


func end_turn() -> void:
	if phase == &"player":
		start_enemy_phase()
	elif phase == &"enemy":
		turn_number += 1
		start_player_phase()


## 玩家方是否所有单位都行动完毕
func all_player_acted() -> bool:
	for u in units:
		if u[&"faction"] == &"player" and not u[&"isDead"] and not u[&"hasActed"]:
			return false
	return true


## 敌方方是否所有单位都行动完毕
func all_enemy_acted() -> bool:
	for u in units:
		if u[&"faction"] == &"enemy" and not u[&"isDead"] and not u[&"hasActed"]:
			return false
	return true


## 胜负判定：win / lose / 空(null)
func check_victory(enemies: Array) -> StringName:
	var alive_enemies := false
	for e in enemies:
		if not e[&"isDead"]:
			alive_enemies = true
			break
	if not alive_enemies:
		return &"win"
	var alive_players := false
	for u in units:
		if u[&"faction"] == &"player" and not u[&"isDead"]:
			alive_players = true
			break
	if not alive_players:
		return &"lose"
	return &"" # null 语义
