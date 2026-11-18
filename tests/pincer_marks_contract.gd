## tests/pincer_marks_contract.gd — 夹击追击标记/预览/结算 schema/表现接线契约
##
## 覆盖（markers 表现层视角，判定与结算权威在 systems/ 与 resolver）：
##   1. battle.gd._build_engagement_marks 组装：背击+追击双标记、非物理不提示追击、
##      对侧友军死亡不提示、正面攻击无背击标记；
##   2. RangeOverlay engage 视觉层：show_engagement_marks / engagement_mark_count(kind) /
##      clear_engagement_marks 计数与清理；
##   3. battle_ui 预览配对生命周期：_show_preview_panel 记录、close_preview 清空；
##   4. 预览与结算共享口径：CombatSystem.preview(…, allies).pincer 与 resolver
##      result.pincer 同 damage；attack_event.impacts 追击 impact 带 pincer 标志；
##   5. 表现接线：action_anim._present_impacts 全量转发 impacts（含追击高亮路径不崩）；
##      play(skipped=true) 演出关闭路径同步完成。
extends SceneTree

const CombatSystem = preload("res://scripts/systems/combat_system.gd")
const BattleActionResolver = preload("res://scripts/battle/battle_action_resolver.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)


func _run() -> void:
	var attacker := UnitFactory.create_random_unit(
		&"pin_atk", "甲", &"player", 1, Vector2i(0, 0),
		ProfessionData.get_profession(&"swordsman")
	)
	var partner := UnitFactory.create_random_unit(
		&"pin_partner", "乙", &"player", 1, Vector2i(3, 0),
		ProfessionData.get_profession(&"swordsman")
	)
	var defender := UnitFactory.create_random_unit(
		&"pin_def", "敌弓", &"enemy", 1, Vector2i(2, 0),
		ProfessionData.get_profession(&"archer")
	)
	var mage := UnitFactory.create_random_unit(
		&"pin_mage", "法师", &"player", 1, Vector2i(0, 2),
		ProfessionData.get_profession(&"mage")
	)
	# 命中率与存活确定性：攻方 skl 拉满必中；守方 hp 拉满保证结算后存活（追击前提）。
	attacker.stats[&"skl"] = 99
	attacker.stats[&"str"] = 40
	defender.stats[&"hp"] = 999
	defender[&"hp"] = 999
	var rows: Array = []
	for y in range(3):
		var row: Array = []
		for x in range(6):
			row.append(&"plain")
		rows.append(row)
	var chapter := {
		"id": &"pincer_marks_contract", "name": "追击标记契约", "width": 6, "height": 3,
		"map": rows, "playerUnits": [attacker, partner, mage], "enemyUnits": [defender],
	}
	root.get_node("SceneArgs").set("battle_args", {"chapter": chapter, "hosting": false})
	var battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	await battle.battle_ready
	await process_frame
	# 守方面向 +x（背对 -x 来向的攻方）：背击成立；(3,0)=守方身后一格（T+signi(T-A)
	# 口径）上的友军即追击 partner。
	defender[&"facing"] = Vector2i(1, 0)
	var units: Array = battle.turn.units

	# ---- 1. 标记数据组装（battle.gd._build_engagement_marks 纯函数） ----
	var marks: Array = battle._build_engagement_marks(attacker, defender, units)
	_expect(marks.size() == 2, "背对+对侧有友军时应同时组装背击与追击标记（实际 %d）" % marks.size())
	var backstab_marks: Array = marks.filter(func(m): return m.kind == &"backstab")
	var pincer_marks: Array = marks.filter(func(m): return m.kind == &"pincer")
	_expect(backstab_marks.size() == 1
		and backstab_marks[0].cell == defender.position
		and backstab_marks[0].aim == Vector2i(1, 0),
		"背击标记应落在守方格且 aim 指向攻击线（攻→守）")
	_expect(pincer_marks.size() == 1
		and pincer_marks[0].cell == partner.position
		and pincer_marks[0].aim == Vector2i(-1, 0),
		"追击标记应落在对侧友军格且 aim 指向守方")

	# 非物理（anima）攻击者：同攻击线、对侧同友军 → 只提示背击，不提示追击。
	var mage_inline: Dictionary = mage.duplicate()
	mage_inline[&"position"] = Vector2i(0, 0)
	var mage_marks: Array = battle._build_engagement_marks(mage_inline, defender, units)
	_expect(mage_marks.size() == 1 and mage_marks[0].kind == &"backstab",
		"非物理攻击不提示追击（应只剩背击标记，实际 %s）" % str(
			mage_marks.map(func(m): return m.kind)))

	# 对侧友军死亡：追击标记消失，背击不受影响。
	partner[&"isDead"] = true
	var dead_marks: Array = battle._build_engagement_marks(attacker, defender, units)
	_expect(dead_marks.size() == 1 and dead_marks[0].kind == &"backstab",
		"对侧友军死亡后不应再提示追击")
	partner[&"isDead"] = false

	# 守方面向攻击者（正面）：背击标记消失，追击不受影响。
	defender[&"facing"] = Vector2i(-1, 0)
	var front_marks: Array = battle._build_engagement_marks(attacker, defender, units)
	_expect(front_marks.size() == 1 and front_marks[0].kind == &"pincer",
		"正面攻击不应提示背击（应只剩追击标记）")
	defender[&"facing"] = Vector2i(1, 0)

	# ---- 2. RangeOverlay engage 视觉层 ----
	battle.range_overlay.show_engagement_marks(marks)
	_expect(battle.range_overlay.engagement_mark_count() == 2
		and battle.range_overlay.engagement_mark_count(&"backstab") == 1
		and battle.range_overlay.engagement_mark_count(&"pincer") == 1,
		"engage 标记计数应按 kind 正确统计")
	battle.range_overlay.clear_engagement_marks()
	_expect(battle.range_overlay.engagement_mark_count() == 0,
		"clear 后 engage 标记应清空")
	# (0,0) 是合法地图坐标，不应与「无 cell」混淆。
	battle.range_overlay.show_engagement_marks([{
		cell = Vector2i.ZERO, kind = &"backstab", aim = Vector2i.ZERO,
	}])
	_expect(battle.range_overlay.engagement_mark_count(&"backstab") == 1,
		"地图原点 (0,0) 也应能显示标记")
	battle.range_overlay.clear_engagement_marks()
	battle.range_overlay.show_engagement_marks(backstab_marks)
	_expect(battle.range_overlay.engagement_mark_count(&"pincer") == 0
		and battle.range_overlay.engagement_mark_count() == 1,
		"仅背击标记时 pincer 计数应为 0")
	battle.range_overlay.clear_engagement_marks()

	# ---- 3. battle_ui 预览配对生命周期（战场标记在确认期的兜底数据源） ----
	var def_tile: Dictionary = battle.grid.tile_at(defender.position.x, defender.position.y)
	var prev: Dictionary = CombatSystem.preview(
		attacker, defender, def_tile.avoid_bonus, def_tile.def_bonus, units)
	battle.battle_ui._show_preview_panel(attacker, defender, prev)
	var pair: Dictionary = battle.battle_ui.preview_engagement_pair()
	_expect(not pair.is_empty()
		and pair.get(&"attacker", {}).get(&"id", &"") == attacker.id
		and pair.get(&"defender", {}).get(&"id", &"") == defender.id,
		"攻击预览面板打开时 battle_ui 应记录攻击配对")
	battle.battle_ui.close_preview()
	_expect(battle.battle_ui.preview_engagement_pair().is_empty(),
		"close_preview 后配对应清空（取消/技能切换即走此路径）")

	# ---- 4. 预览与结算共享口径 ----
	_expect(prev.pincer.active == true
		and int(prev.pincer.damage) == CombatSystem.pincer_damage(
			partner, defender, int(def_tile.def_bonus))
		and int(prev.pincer.damage) > 0,
		"物理攻击预览 pincer 应激活且 damage 与 pincer_damage 同公式")
	var mage_prev: Dictionary = CombatSystem.preview(
		mage_inline, defender, def_tile.avoid_bonus, def_tile.def_bonus, units)
	_expect(mage_prev.pincer.active == false,
		"非物理攻击预览 pincer 应恒 inactive")

	var outcome: Dictionary = BattleActionResolver.resolve_attack(
		attacker, defender, battle.grid, {})
	var result: Dictionary = outcome[&"combat"]
	var event: Dictionary = result.get(&"attack_event", {})
	var pincer_impacts: Array = (event.get(&"impacts", []) as Array).filter(
		func(i): return bool(i.get(&"pincer", false)))
	_expect(result.has(&"pincer") and result.pincer.active == true,
		"命中且守方存活时 resolver result.pincer 应激活")
	_expect(int(result.pincer.damage) == int(prev.pincer.damage),
		"结算追击伤害应与预览同公式（result=%s prev=%s）" % [
			str(result.pincer.get(&"damage", -1)), str(prev.pincer.get(&"damage", -1))])
	_expect(pincer_impacts.size() == 1
		and StringName(pincer_impacts[0].source_id) == StringName(partner.id),
		"追击 impact 恰一条且 source 为对侧友军")
	_expect(bool(event.get(&"pincer", false))
		and StringName(event.get(&"pincer_id", &"")) == StringName(partner.id),
		"attack_event 顶层应带 pincer/pincer_id")

	# ---- 5. 表现接线：impacts 全量转发 + 演出关闭路径 ----
	var presented: Array = []
	battle.action_anim.impact_presented.connect(func(impact): presented.append(impact))
	battle.action_anim._present_impacts(event)
	_expect(presented.size() == (event.get(&"impacts", []) as Array).size(),
		"_present_impacts 应逐条转发全部 impacts（含追击高亮路径不崩）")
	_expect(presented.any(func(i): return bool(i.get(&"pincer", false))),
		"追击 impact 应进入表现转发序列")
	await battle.action_anim.play(event, 1.0, true)
	_expect(not battle.action_anim._playing,
		"演出关闭（skipped）路径应同步完成不悬挂")

	# ---- 6. battle.gd 标记统一入口（清理分支） ----
	battle._select_unit(attacker)
	battle._update_engagement_marks(defender)
	_expect(battle.range_overlay.engagement_mark_count() == 2,
		"选中攻击方后统一入口应显示双标记")
	battle._update_engagement_marks({})
	_expect(battle.range_overlay.engagement_mark_count() == 0,
		"目标为空时统一入口应清理标记")
	battle.selected_unit = {}
	battle.mode = battle.Mode.IDLE

	if failures == 0:
		print("PINCER_MARKS_CONTRACT_OK")
	else:
		printerr("PINCER_MARKS_CONTRACT_FAILED: %d 处失败" % failures)
	quit(0 if failures == 0 else 1)
