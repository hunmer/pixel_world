## tests/battle_action_chain_contract.gd — B1/B2 普攻、技能、敌方与托管统一 ActionAnim 集成契约
extends SceneTree

const WorldToChapter = preload("res://scripts/core/world_to_chapter.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
		assert(condition, message)


## 与 ActionAnim._present_float_text 的可见分支一致：无内容 impact 不应生成空飘字。
func _visible_impact_count(event: Dictionary) -> int:
	var count := 0
	for impact_value in event.get(&"impacts", []):
		var impact: Dictionary = impact_value
		if (
			not bool(impact.get(&"hit", true))
			or int(impact.get(&"healing", 0)) > 0
			or int(impact.get(&"damage", 0)) > 0
			or not (impact.get(&"statuses", []) as Array).is_empty()
		):
			count += 1
	return count


func _first_unit(battle: Node, faction: StringName) -> Dictionary:
	for unit_value in battle.grid.units.values():
		var unit: Dictionary = unit_value
		if unit.get(&"faction", &"") == faction and not bool(unit.get(&"isDead", false)):
			return unit
	return {}


func _exercise_actions(battle: Node, label: String) -> void:
	_expect(battle.action_anim != null, "%s 未创建 ActionAnim" % label)
	_expect(
		battle.turn_director.on_resolve_combat_async.is_valid(),
		"%s 未注入敌方/托管 async 普攻入口" % label
	)
	_expect(
		not battle.turn_director.on_resolve_combat_sync.is_valid(),
		"%s 仍注入旧同步普攻，可能绕过事件演出" % label
	)
	var attacker := _first_unit(battle, &"player")
	var defender := _first_unit(battle, &"enemy")
	_expect(not attacker.is_empty() and not defender.is_empty(), "%s 缺少普攻测试单位" % label)
	if attacker.is_empty() or defender.is_empty():
		return
	# 防止反击/技能偶发致死影响后续链路；只改契约夹具，不改生产结算。
	for unit in [attacker, defender]:
		unit[&"hp"] = 999
		unit[&"maxHp"] = 999
		unit[&"hasActed"] = false
		unit[&"hasMoved"] = false
	battle.turn_director.set_pref(attacker.id, &"anim_speed", 4.0)
	battle.turn_director.set_pref(attacker.id, &"skip_anim", false)
	battle.turn_director.set_enemy_animation(4.0, false)

	var events: Array[Dictionary] = []
	var on_finished := func(event: Dictionary, skipped: bool) -> void:
		events.append({"event": event, "skipped": skipped})
	battle.action_anim.finished.connect(on_finished)
	var float_count := [0]
	var on_float := func(_node: Node) -> void:
		float_count[0] += 1
	var container: Node = battle.battle_ui.get_float_text_container()
	container.child_entered_tree.connect(on_float)

	var manual_done := [false]
	await battle._resolve_combat(attacker, defender, func() -> void:
		manual_done[0] = true
	)
	_expect(manual_done[0], "%s 手动普攻 callback 未在 ActionAnim 后返回" % label)
	_expect(events.size() == 1, "%s 普攻未恰好发出一次 ActionAnim.finished" % label)
	if events.size() == 1:
		var event: Dictionary = events[0]["event"]
		_expect(not (event.get(&"impacts", []) as Array).is_empty(), "%s 普攻 attack_event 无 impact" % label)
		_expect(
			float_count[0] == _visible_impact_count(event),
			"%s 普攻 impact/飘字数量不一致，可能重复或漏播: floats=%d impacts=%d" % [
				label, float_count[0], _visible_impact_count(event)]
		)
	_expect(bool(attacker.get(&"hasActed", false)), "%s 普攻演出后未恢复 hasActed 结算" % label)

	# 技能也复用同一个事件播放器，不再由 battle.gd 手工补一份冲撞/飘字。
	if not (attacker.get(&"skills", []) as Array).has(&"fireball"):
		(attacker[&"skills"] as Array).append(&"fireball")
	attacker[&"mp"] = 99
	attacker[&"skillCooldowns"][&"fireball"] = 0
	attacker[&"hasActed"] = false
	float_count[0] = 0
	var handled: bool = await battle._resolve_skill(attacker, [defender], &"fireball")
	_expect(handled, "%s 技能未告知 TurnDirector 已自行 await" % label)
	_expect(events.size() == 2, "%s 技能未恰好发出一次 ActionAnim.finished" % label)
	if events.size() == 2:
		var event: Dictionary = events[1]["event"]
		_expect(StringName(event.get(&"skill_id", &"")) == &"fireball", "%s 技能事件 id 错误" % label)
		_expect(
			float_count[0] == _visible_impact_count(event),
			"%s 技能 impact/飘字数量不一致，可能重复或漏播" % label
		)

	# 敌方通过 TurnDirector 注入的同一 async 入口，仍走 execute→event→play。
	float_count[0] = 0
	await battle.turn_director.on_resolve_combat_async.call(defender, attacker)
	_expect(events.size() == 3, "%s 敌方未进入统一 ActionAnim 链" % label)
	_expect(battle.mode == battle.Mode.ANIMATING, "%s 敌方演出尚未交回回合状态机" % label)

	# 托管跳过只压缩表现，不绕过 CombatSystem 或 finished 信号。
	battle.turn_director.set_hosting(true)
	battle.turn_director.set_hosting_animation(8.0, true)
	await battle.turn_director.on_resolve_combat_async.call(attacker, defender)
	_expect(events.size() == 4, "%s 托管普攻未发出 finished" % label)
	if events.size() == 4:
		_expect(bool(events[3]["skipped"]), "%s 托管 skip 选项未传入 ActionAnim" % label)
	battle.turn_director.set_hosting(false)
	container.child_entered_tree.disconnect(on_float)
	battle.action_anim.finished.disconnect(on_finished)


func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	if world.get_script() == null:
		_expect(false, "main.gd 编译失败，测试不能作为通过依据")
		quit(1)
		return
	world.seed = 42
	root.add_child(world)
	await process_frame
	var chapter: Dictionary = WorldToChapter.world_to_chapter(
		world._terrain_sampler, world._player_cell, 4, 42
	)
	world._enter_battle_inline(chapter)
	var battle = world._battle_system
	if battle == null:
		_expect(false, "B1 战斗创建失败")
		quit(1)
		return
	await battle.battle_ready
	await _exercise_actions(battle, "B1")
	world._exit_battle(&"contract")
	world.queue_free()
	await process_frame
	await process_frame

	root.get_node("SceneArgs").set("battle_args", {"chapter": chapter, "hosting": false})
	var b2 = load("res://scenes/Battle.tscn").instantiate()
	if b2.get_script() == null:
		_expect(false, "battle.gd 编译失败，测试不能作为通过依据")
		quit(1)
		return
	root.add_child(b2)
	await b2.battle_ready
	await _exercise_actions(b2, "B2")
	b2.queue_free()
	await process_frame
	if failures == 0:
		print("BATTLE_ACTION_CHAIN_CONTRACT_OK")
	quit(0 if failures == 0 else 1)
