## tests/battle_action_chain_contract.gd — B1/B2 普攻、技能、敌方与托管统一 ActionAnim 集成契约
extends SceneTree

const WorldToChapter = preload("res://scripts/core/world_to_chapter.gd")

var failures := 0
var _immersive_saved := false


## 本契约测传统演出链（关闭沉浸走真实 ActionAnim）；沉浸舞台路径由
## immersive_stage 契约另行覆盖。密闭性：固定关闭 immersive_presentation，
## 本地 user://settings.cfg 开关不再泄入（与 battle_presentation_hooks 同做法）。
func _pin_immersive_presentation() -> void:
	var settings: Node = root.get_node("Settings")
	_immersive_saved = bool(settings.get("battle_immersive_presentation"))
	settings.set("battle_immersive_presentation", false)


func _restore_immersive_presentation() -> void:
	root.get_node("Settings").set("battle_immersive_presentation", _immersive_saved)


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
		assert(condition, message)


## 每个 impact 的飘字容器期望子节点数（与现行呈现链一致，作为断言口径）：
##   ActionAnim._present_float_text → BattleFx.spawn_float_text：未命中 "MISS" / 治疗 "+N" / 纯 buff 各 1 个
##     outline 标签；伤害 "-N" 文本标签被 spawn_float_text 跳过（伤害数字已由 pixelfx damage-number 接管）。
##   battle.gd _on_impact_presented → BattleFx.spawn_damage_from_impact：实际伤害（hit 且 damage>0）再生成
##     damage-number + health-bar-hit 两个 PixelFx2D 节点（均挂入同一飘字容器，见 battle_fx.gd spawn_damage_fx）。
func _expected_float_node_count(event: Dictionary) -> int:
	var count := 0
	for impact_value in event.get(&"impacts", []):
		var impact: Dictionary = impact_value
		if not bool(impact.get(&"hit", true)):
			count += 1  # "MISS" 标签
			continue
		if int(impact.get(&"healing", 0)) > 0:
			count += 1  # "+N" 治疗标签
		elif int(impact.get(&"damage", 0)) > 0:
			pass  # "-N" 标签跳过，伤害呈现走下方特效两节点
		elif not (impact.get(&"statuses", []) as Array).is_empty():
			count += 1  # 纯 buff 标签
		if int(impact.get(&"damage", 0)) > 0:
			count += 2  # pixelfx damage-number + health-bar-hit
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
			float_count[0] == _expected_float_node_count(event),
			"%s 普攻飘字节点数与 impact 呈现不一致，可能重复或漏播: floats=%d expect=%d" % [
				label, float_count[0], _expected_float_node_count(event)]
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
			float_count[0] == _expected_float_node_count(event),
			"%s 技能飘字节点数与 impact 呈现不一致，可能重复或漏播: floats=%d expect=%d" % [
				label, float_count[0], _expected_float_node_count(event)]
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
	_pin_immersive_presentation()
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
	_restore_immersive_presentation()
	if failures == 0:
		print("BATTLE_ACTION_CHAIN_CONTRACT_OK")
	quit(0 if failures == 0 else 1)
