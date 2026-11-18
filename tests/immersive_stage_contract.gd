## tests/immersive_stage_contract.gd — 独立沉浸舞台契约（布局纯逻辑 + B1/B2 序列/密闭性）
##
## 覆盖：
##   A. 纯布局：参战者收集（含真实夹击友军/反击方）、阵营对角站位（我方左下/敌方右上，
##      敌方先手不换侧）、代理 HP 重建（首个作为目标的 impact.hp_before；从未被目标者沿用真实 HP）、
##      逐 impact 出手模板（按实际 source 武器）与反击/连击标签。
##   B. B2 实战序列（arena_1v1）：开关开启整场进舞台；每非 skip impact 恰一次
##      strike_scheduled/impact_presented 且顺序/出手者与 impacts 严格一致；真实
##      ActionAnim 不被驱动；真实相机零写入；代理 HP 逐 impact 推进（impact_presented
##      命中帧时代理 HP == 该 impact.hp_after）；真实单位零写回；敌方先手不换侧（序列级）；
##      倍速可感知（慢速耗时 > 快速）；演出中 request_skip 立即收尾；死亡路径（含收尾
##      姿态重放）；整体 skip（托管）保持传统链路；关闭开关恢复传统链路；舞台层随演出
##      显示/隐藏；右侧战斗侧栏进入独演即隐藏、结束/跳过精确恢复原可见性（原本隐藏
##      不强行打开；整体 skip 与关闭开关不动侧栏）。
##   C. B2 技能/多目标/完整链（plains_skirmish）：治疗（HP 回升、无敌方参战）、
##      自身 buff（statuses impact）、aoe 多目标伤害、反击/连击/夹击合成链的出手顺序/
##      标签/出手模板/逐次 HP、演出中销毁 battle 的退出清理。
##   D. B1（世界内联战斗）：同样的舞台路径，世界相机零写入；独演期间隐藏战斗侧栏 +
##      世界 HUD 左栏/右侧栏，结束恢复；演出中退出战斗经 _exit_tree 精确恢复世界侧栏。
##   E. 取景自适应：宽/窄/小窗口 × 2/6/10 人，以舞台相机实际投影断言全员（脚/头采样）
##      不越出视口、阵营对角分立（敌方右上/我方左下）、人数越多取景越广（zoom 单调）。
## 契约跑法：python3 tools/run_contracts.py --test immersive_stage --out <dir>
## 注意：SceneTree 契约下 autoload 标识符不可用，一律 root.get_node("Settings"/"SceneArgs")。
extends SceneTree

const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const Layout = preload("res://scripts/battle/immersive_stage_layout.gd")
const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
const WorldToChapter = preload("res://scripts/core/world_to_chapter.gd")

const ARENA := "res://data/battlefields/arena_1v1.json"
const PLAINS := "res://data/battlefields/plains_skirmish.json"

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("IMMERSIVE_STAGE_FAIL: " + message)
		assert(condition, message)


func _impact(
		source_id: String, target_id: String,
		hit: bool, damage: int,
		hp_before: int, hp_after: int,
		extra: Dictionary = {}
) -> Dictionary:
	var data := {
		&"source_id": StringName(source_id),
		&"target_id": StringName(target_id),
		&"hit": hit,
		&"damage": damage,
		&"healing": maxi(0, hp_after - hp_before),
		&"hp_before": hp_before,
		&"hp_after": hp_after,
		&"died": hp_after <= 0,
	}
	for key in extra.keys():
		data[key] = extra[key]
	return data


func _fixture_units() -> Dictionary:
	return {
		&"p1": {&"id": &"p1", &"faction": &"player", &"hp": 30, &"weapon": {&"type": &"sword"}},
		&"a1": {&"id": &"a1", &"faction": &"ally", &"hp": 18, &"weapon": {&"type": &"lance"}},
		&"e1": {&"id": &"e1", &"faction": &"enemy", &"hp": 20, &"weapon": {&"type": &"bow"}},
	}


func _fixture_event() -> Dictionary:
	return {
		&"kind": &"normal",
		&"attacker_id": &"p1",
		&"primary_target_id": &"e1",
		&"anim": &"slash",
		&"double_attack": true,
		&"hitstop": 0.0,
		&"impacts": [
			_impact("p1", "e1", true, 10, 20, 10),
			_impact("e1", "p1", true, 5, 30, 25),
			_impact("a1", "e1", true, 7, 10, 3, {&"pincer": true}),
		],
	}


## ————— A. 纯布局逻辑 —————


func _test_layout() -> void:
	var units := _fixture_units()
	var event := _fixture_event()
	# 参战者顺序：出手者、主目标、impact source/target 去重（追击友军在内）。
	var participants: Array = Layout.participants_for(event, units)
	_expect(participants.map(func(u): return u[&"id"]) == [&"p1", &"e1", &"a1"],
		"参战者收集/顺序错误: %s" % str(participants.map(func(u): return u[&"id"])))
	# 对角站位：我方(player/ally) y>0，敌方 y<0；出手者前排中央、追击友军同排左侧。
	var slots := Layout.build_slots(event, participants)
	var p1_slot: Dictionary = slots[&"p1"]
	var a1_slot: Dictionary = slots[&"a1"]
	var e1_slot: Dictionary = slots[&"e1"]
	_expect(p1_slot[&"side"] == Layout.SIDE_ALLY and a1_slot[&"side"] == Layout.SIDE_ALLY,
		"我方/友军应同侧(ally)")
	_expect(e1_slot[&"side"] == Layout.SIDE_ENEMY, "敌方应站 enemy 侧")
	_expect((p1_slot[&"cell"] as Vector2i).y > 0 and (a1_slot[&"cell"] as Vector2i).y > 0,
		"我方侧应在 +y（屏幕左下对角）")
	_expect((e1_slot[&"cell"] as Vector2i).y < 0, "敌方侧应在 -y（屏幕右上对角）")
	_expect(p1_slot[&"cell"] == Vector2i(0, Layout.ANCHOR_STEPS), "出手者应站我方前排中央")
	_expect(a1_slot[&"cell"] == Vector2i(-1, Layout.ANCHOR_STEPS + 1), "追击友军应站我方前排左侧")
	_expect(e1_slot[&"cell"] == Vector2i(0, -Layout.ANCHOR_STEPS), "主目标应站敌方前排中央")
	# 屏幕对角：我方格世界 z > 0（投影屏幕左下）、敌方 z < 0（右上）。
	var p1_world := IsoProjection.grid_to_world(p1_slot[&"cell"], 0.0)
	var e1_world := IsoProjection.grid_to_world(e1_slot[&"cell"], 0.0)
	_expect(p1_world.z > 0.0 and e1_world.z < 0.0, "阵营对角方向(世界 z 轴)错误")
	# 朝向：我方面向 -z（敌方侧），敌方面向 +z（我方侧）。
	_expect((p1_slot[&"facing"] as Vector3).z < 0.0, "我方朝向应指向敌方")
	_expect((e1_slot[&"facing"] as Vector3).z > 0.0, "敌方朝向应指向我方")
	# 敌方先手不换侧：attacker=enemy 时敌方仍在 -y。
	var enemy_first := event.duplicate(true)
	enemy_first[&"attacker_id"] = &"e1"
	enemy_first[&"primary_target_id"] = &"p1"
	var ef_slots := Layout.build_slots(enemy_first, Layout.participants_for(enemy_first, units))
	_expect((ef_slots[&"e1"][&"cell"] as Vector2i).y < 0, "敌方先手不应换侧")
	# HP 重建：目标以首个 hp_before 为初态；从未被目标者(a1)沿用真实 HP；dies 聚合。
	var participants_units := {}
	for unit in participants:
		participants_units[unit[&"id"]] = unit
	var hp_map := Layout.initial_hp_map(event, participants_units)
	_expect(int(hp_map[&"e1"][&"hp"]) == 20, "敌方初态应为首个 hp_before")
	_expect(int(hp_map[&"p1"][&"hp"]) == 30, "我方初态应为反击 impact hp_before")
	_expect(int(hp_map[&"a1"][&"hp"]) == 18, "未被目标者应沿用真实 HP")
	_expect(not bool(hp_map[&"e1"][&"dies"]), "存活链不应标 dies")
	var death_event := event.duplicate(true)
	(death_event[&"impacts"] as Array)[2] = _impact("a1", "e1", true, 10, 10, 0, {&"pincer": true})
	var death_map := Layout.initial_hp_map(death_event, participants_units)
	_expect(bool(death_map[&"e1"][&"dies"]), "致死 impact 应标 dies")
	# 出手模板：普攻按 source 武器，技能沿用事件 anim。
	_expect(Layout.strike_anim_for(event, units[&"e1"]) == &"projectile:arrow", "bow 出手模板错误")
	_expect(Layout.strike_anim_for(event, units[&"p1"]) == &"slash", "sword 出手模板错误")
	var skill_event := event.duplicate(true)
	skill_event[&"kind"] = &"skill"
	skill_event[&"anim"] = &"burst:holy"
	_expect(Layout.strike_anim_for(skill_event, units[&"p1"]) == &"burst:holy", "技能应沿用事件 anim")
	# 标签：反击/连击可辨识，追击交给高亮+前缀。
	_expect(Layout.strike_label(event, 1, event[&"impacts"][1]) == "反击", "反击标签缺失")
	_expect(Layout.strike_label(event, 2, event[&"impacts"][0]) == "连击", "连击标签缺失")
	_expect(Layout.strike_label(event, 2, event[&"impacts"][2]) == "", "追击不应重复标签")
	# 同阵营治疗不造敌方：全友方事件敌方侧空位。
	var heal_event := {
		&"kind": &"skill", &"attacker_id": &"p1", &"anim": &"burst:holy",
		&"impacts": [_impact("p1", "a1", true, 0, 10, 16)],
	}
	var heal_slots := Layout.build_slots(heal_event, Layout.participants_for(heal_event, units))
	_expect(not heal_slots.has(&"e1"), "治疗事件不应造敌方站位")
	_expect((heal_slots[&"a1"][&"cell"] as Vector2i).y > 0, "受疗友军应在我方侧")
	# 稳定排序：相同 rank（普通参战者）保持原始参加顺序——sort_custom 不稳定，
	# 传入乱序数组，前排左/右槽位应按参加顺序分配而非被重排。
	var stable_units := _fixture_units().duplicate(true)
	stable_units[&"x1"] = {&"id": &"x1", &"faction": &"player", &"hp": 12, &"weapon": {&"type": &"sword"}}
	stable_units[&"x2"] = {&"id": &"x2", &"faction": &"player", &"hp": 13, &"weapon": {&"type": &"sword"}}
	# 参加顺序：x2 在 x1 前、出手者 p1 与主目标 e1 夹在中间（rank 决胜）。
	var stable_order: Array = [stable_units[&"x2"], stable_units[&"p1"], stable_units[&"x1"], stable_units[&"e1"]]
	var stable_event := event.duplicate(true)
	var stable_slots := Layout.build_slots(stable_event, stable_order)
	_expect(stable_slots[&"p1"][&"cell"] == Vector2i(0, Layout.ANCHOR_STEPS), "稳定排序：出手者仍前排中央")
	_expect(stable_slots[&"x2"][&"cell"] == Vector2i(-1, Layout.ANCHOR_STEPS + 1),
		"稳定排序：先参加的 x2 应占前排左侧（实际 %s）" % str(stable_slots[&"x2"][&"cell"]))
	_expect(stable_slots[&"x1"][&"cell"] == Vector2i(1, Layout.ANCHOR_STEPS - 1),
		"稳定排序：后参加的 x1 应占前排右侧（实际 %s）" % str(stable_slots[&"x1"][&"cell"]))
	_expect(stable_slots[&"e1"][&"cell"] == Vector2i(0, -Layout.ANCHOR_STEPS), "稳定排序：主目标仍敌方前排中央")


## ————— 战场搭建/工具 —————


func _setup_battle(path: String) -> Node:
	var loaded: Dictionary = BattlefieldLoaderScript.load_battlefield(path)
	_expect(bool(loaded.get("ok", false)), "真实 JSON 战场加载失败: %s" % path)
	var chapter: Dictionary = loaded.get("chapter", {})
	root.get_node("SceneArgs").set("battle_args", {
		"chapter": chapter,
		"return_to": "res://main.tscn",
		"hosting": false,
		"save_identity": "",
	})
	var battle = load("res://scenes/Battle.tscn").instantiate()
	if battle.get_script() == null:
		_expect(false, "battle.gd 编译失败，测试不能作为通过依据")
		return null
	root.add_child(battle)
	await battle.battle_ready
	return battle


func _pick(battle: Node, faction: StringName) -> Dictionary:
	for unit_value in battle.grid.units.values():
		var unit: Dictionary = unit_value
		if unit.get(&"faction", &"") == faction and not bool(unit.get(&"isDead", false)):
			return unit
	return {}


func _pick_all(battle: Node, faction: StringName) -> Array:
	var result: Array = []
	for unit_value in battle.grid.units.values():
		var unit: Dictionary = unit_value
		if unit.get(&"faction", &"") == faction and not bool(unit.get(&"isDead", false)):
			result.append(unit)
	return result


func _reset_unit(unit: Dictionary, hp: int) -> void:
	unit[&"hp"] = hp
	unit[&"hasActed"] = false
	unit[&"hasMoved"] = false
	unit[&"isDead"] = false


## 舞台监听器：捕获信号 + 在信号时刻读取舞台内部代理/站位状态。
class StageWatcher:
	var started: Array = []
	var finished: Array = []
	var strikes: Array = []
	var impacts: Array = []
	var hp_at_impact: Array = []   # [{target_id, stage_hp, hp_after}] — 命中帧即已推进
	var proxies_at_finish: Dictionary = {}
	var slots_at_finish: Dictionary = {}
	var sprites_at_finish: Dictionary = {}  # {id: {visible, pose}} — 死亡终态视觉
	var fade_alpha_at_finish := -1.0
	var real_finished: Array = []

	func attach(stage: Node, real_anim: Node) -> void:
		stage.presentation_started.connect(func(event): started.append(event))
		stage.presentation_finished.connect(func(event, skipped):
			finished.append({"event": event, "skipped": skipped})
			proxies_at_finish = stage._stage_units.duplicate(false)
			slots_at_finish = stage._slots.duplicate(false)
			var sprite_states := {}
			for unit_id in stage._sprites.keys():
				var sprite: Node = stage._sprites[unit_id]
				if sprite != null and is_instance_valid(sprite):
					sprite_states[unit_id] = {
						"visible": sprite.visible,
						"pose": String(sprite.get_pose()),
					}
			sprites_at_finish = sprite_states
			fade_alpha_at_finish = float(stage._fade_rect.color.a))
		stage.strike_scheduled.connect(func(pseudo): strikes.append(pseudo))
		stage.impact_presented.connect(func(impact):
			impacts.append(impact)
			var target_id: StringName = impact.get(&"target_id", &"")
			var proxy: Dictionary = stage._stage_units.get(target_id, {})
			hp_at_impact.append({
				"target": target_id,
				"stage_hp": int(proxy.get(&"hp", -1)),
				"hp_after": int(impact.get(&"hp_after", -2)),
			}))
		if real_anim != null:
			real_anim.finished.connect(func(event, skipped): real_finished.append(event))


func _assert_sequenced(watcher: StageWatcher, label: String) -> Dictionary:
	## 通用序列断言：started/finished 恰一次；每 impact 恰一次出手/受击且顺序与事件一致；
	## 逐次 HP：impact_presented（命中帧）时代理 HP == 该 impact.hp_after（推进后）；
	## 退出转场在 finished 前完成（fade 全黑）。
	_expect(watcher.started.size() == 1, "%s: presentation_started 应恰一次" % label)
	if watcher.finished.size() != 1:
		_expect(false, "%s: presentation_finished 应恰一次（实际 %d）" % [label, watcher.finished.size()])
		return {}
	_expect(watcher.real_finished.is_empty(), "%s: 舞台路径不应驱动真实 ActionAnim.finished" % label)
	_expect(watcher.fade_alpha_at_finish >= 0.999,
		"%s: finished 前退出转场应已完成（fade a=%.3f）" % [label, watcher.fade_alpha_at_finish])
	var event: Dictionary = watcher.started[0]
	var impacts: Array = event.get(&"impacts", [])
	_expect(watcher.strikes.size() == impacts.size(),
		"%s: 每非 skip impact 应恰一次出手: %d/%d" % [label, watcher.strikes.size(), impacts.size()])
	_expect(watcher.impacts.size() == impacts.size(),
		"%s: 每非 skip impact 应恰一次受击呈现: %d/%d" % [label, watcher.impacts.size(), impacts.size()])
	for i in range(mini(watcher.strikes.size(), impacts.size())):
		var impact: Dictionary = impacts[i]
		var pseudo: Dictionary = watcher.strikes[i]
		_expect(StringName(pseudo.get(&"attacker_id", &"")) == StringName(impact.get(&"source_id", &"")),
			"%s: 第 %d 次出手者应等于 impact.source_id" % [label, i])
		_expect(StringName(pseudo.get(&"primary_target_id", &"")) == StringName(impact.get(&"target_id", &"")),
			"%s: 第 %d 次出手目标应等于 impact.target_id" % [label, i])
	for i in range(watcher.hp_at_impact.size()):
		var sample: Dictionary = watcher.hp_at_impact[i]
		if sample["target"] == watcher.impacts[i].get(&"target_id", &""):
			_expect(int(sample["stage_hp"]) == int(sample["hp_after"]),
				"%s: 第 %d 次受击（命中帧）代理 HP(%d) 应已推进到 hp_after(%d)" % [label, i, sample["stage_hp"], sample["hp_after"]])
	return event


## ————— 主流程 —————


func _run() -> void:
	_test_layout()
	await _run_framing()
	var settings: Node = root.get_node("Settings")
	var immersive_saved := bool(settings.get("battle_immersive_presentation"))
	settings.set("battle_immersive_presentation", true)

	await _run_b2_arena(settings)
	await _run_b2_plains()
	await _run_b1_world()

	settings.set("battle_immersive_presentation", immersive_saved)
	if failures == 0:
		print("IMMERSIVE_STAGE_CONTRACT_OK")
	quit(0 if failures == 0 else 1)


## B. B2 实战序列（arena_1v1）。
func _run_b2_arena(settings: Node) -> void:
	var battle := await _setup_battle(ARENA)
	if battle == null:
		quit(1)
		return
	_expect(battle._immersive_stage != null, "沉浸舞台未创建")
	_expect(battle._immersive_stage.is_enabled(), "开关开启时舞台应启用")

	var watcher := StageWatcher.new()
	watcher.attach(battle._immersive_stage, battle.action_anim)

	# 独演侧栏：进入舞台隐藏右侧战斗侧栏，结束/跳过后精确恢复原可见性。
	var sidebar: Control = battle.battle_ui.get_sidebar()
	_expect(sidebar != null, "battle_ui 应提供右侧战斗侧栏（get_sidebar）")
	var sidebar_during := {}
	battle._immersive_stage.presentation_started.connect(func(_event):
		sidebar_during["visible"] = sidebar.visible)

	var attacker := _pick(battle, &"player")
	var defender := _pick(battle, &"enemy")
	_expect(not attacker.is_empty() and not defender.is_empty(), "arena 缺少测试单位")

	# ① 开关开启 + 倍速 8：整场进舞台，真实链路/相机零写入，序列与 HP 链一致。
	battle.turn_director.set_pref(attacker.id, &"anim_speed", 8.0)
	battle.turn_director.set_pref(attacker.id, &"skip_anim", false)
	_reset_unit(attacker, 999)
	_reset_unit(defender, 999)
	var camera: Camera3D = battle.board.camera
	var cam_before := _camera_state(camera)
	var fast_start := Time.get_ticks_msec()
	await battle._resolve_combat(attacker, defender, func() -> void: pass)
	var fast_ms := Time.get_ticks_msec() - fast_start
	var event := _assert_sequenced(watcher, "①开启整场")
	_expect(not battle._immersive_stage.is_presenting(), "演出结束舞台应复位")
	if not event.is_empty():
		var last_def_hp := 999
		var last_atk_hp := 999
		for impact_value in event.get(&"impacts", []):
			var impact: Dictionary = impact_value
			if StringName(impact[&"target_id"]) == defender.id:
				last_def_hp = int(impact[&"hp_after"])
			if StringName(impact[&"target_id"]) == attacker.id:
				last_atk_hp = int(impact[&"hp_after"])
		_expect(int(defender[&"hp"]) == last_def_hp, "舞台演出不得改写真实单位 HP（防御方）")
		_expect(int(attacker[&"hp"]) == last_atk_hp, "舞台演出不得改写真实单位 HP（出手方，含反击）")
		# 零写回：格位不变（代理站位只存在于舞台内）。
		_expect((attacker[&"position"] as Vector2i) != (defender[&"position"] as Vector2i),
			"真实单位格位不应被舞台改动")
	var cam_after := _camera_state(camera)
	_expect(cam_before == cam_after, "舞台演出不得写入真实相机")
	_expect(not battle._stage_layer.visible, "演出结束后舞台层应隐藏（不遮真实战场）")
	_expect(not bool(sidebar_during.get("visible", true)), "①演出中右侧战斗侧栏应隐藏")
	_expect(sidebar.visible, "①演出结束右侧战斗侧栏应恢复可见")
	_expect(battle._stage_hidden_columns.is_empty(), "①恢复后侧栏隐藏记录应清空")

	# ② 敌方先手（序列级）：敌方出手者仍在 -y 侧、玩家仍在 +y 侧。
	var enemy_watcher := StageWatcher.new()
	enemy_watcher.attach(battle._immersive_stage, battle.action_anim)
	var atk_pos_before := attacker[&"position"] as Vector2i
	_reset_unit(attacker, 999)
	_reset_unit(defender, 999)
	await battle._resolve_combat(defender, attacker, func() -> void: pass)
	var enemy_event := _assert_sequenced(enemy_watcher, "②敌方先手")
	if not enemy_event.is_empty() and not enemy_watcher.slots_at_finish.is_empty():
		var enemy_cell: Vector2i = enemy_watcher.slots_at_finish.get(defender.id, {}).get(&"cell", Vector2i.ZERO)
		var player_cell: Vector2i = enemy_watcher.slots_at_finish.get(attacker.id, {}).get(&"cell", Vector2i.ZERO)
		_expect(enemy_cell.y < 0, "敌方先手序列：敌方仍应站 -y 侧（实际 %s）" % str(enemy_cell))
		_expect(player_cell.y > 0, "敌方先手序列：玩家仍应站 +y 侧（实际 %s）" % str(player_cell))
	_expect((attacker[&"position"] as Vector2i) == atk_pos_before, "B2 真实格位零写回")

	# ③ 倍速可感知：speed 1 耗时 > speed 8。
	var slow_watcher := StageWatcher.new()
	slow_watcher.attach(battle._immersive_stage, battle.action_anim)
	battle.turn_director.set_pref(defender.id, &"anim_speed", 1.0)
	battle.turn_director.set_pref(defender.id, &"skip_anim", false)
	_reset_unit(attacker, 999)
	_reset_unit(defender, 999)
	var slow_start := Time.get_ticks_msec()
	await battle._resolve_combat(defender, attacker, func() -> void: pass)
	var slow_ms := Time.get_ticks_msec() - slow_start
	_assert_sequenced(slow_watcher, "③慢速")
	_expect(slow_ms > fast_ms, "倍速应可感知: 慢速 %dms <= 快速 %dms" % [slow_ms, fast_ms])

	# ④ 演出中跳过：首个受击后 request_skip → 立即收尾，不再有新出手/受击。
	var midskip_finished: Array = []
	var midskip_impacts: Array = []
	battle._immersive_stage.presentation_finished.connect(
		func(_event, skipped): midskip_finished.append(skipped), CONNECT_ONE_SHOT)
	battle._immersive_stage.impact_presented.connect(func(_impact):
		midskip_impacts.append(true)
		if midskip_impacts.size() == 1:
			battle._immersive_stage.request_skip())
	battle.turn_director.set_pref(defender.id, &"anim_speed", 1.0)
	_reset_unit(attacker, 999)
	_reset_unit(defender, 999)
	await battle._resolve_combat(defender, attacker, func() -> void: pass)
	_expect(midskip_finished.size() == 1 and bool(midskip_finished[0]), "演出中跳过 finished.skipped 应为 true")
	var midskip_impact_total := midskip_impacts.size()
	await process_frame
	await process_frame
	_expect(midskip_impacts.size() == midskip_impact_total, "跳过后不应再有新受击呈现")
	# 跳过路径 HP 仍按权威值推进（真实单位由结算层写，舞台无残留）。
	_expect(not battle._immersive_stage.is_presenting(), "演出中跳过后舞台应复位")
	_expect(sidebar.visible, "④跳过收尾后侧栏应恢复可见")

	# ⑤ 整体 skip 选项（托管）：舞台被绕过，保持传统链路。
	battle.turn_director.set_pref(attacker.id, &"skip_anim", true)
	var legacy_watcher := StageWatcher.new()
	legacy_watcher.attach(battle._immersive_stage, battle.action_anim)
	_reset_unit(attacker, 999)
	_reset_unit(defender, 999)
	await battle._resolve_combat(attacker, defender, func() -> void: pass)
	_expect(legacy_watcher.started.is_empty(), "整体 skip 不应进舞台")
	_expect(legacy_watcher.real_finished.size() == 1, "整体 skip 应走真实 ActionAnim 同步完成恰一次")
	_expect(sidebar.visible, "⑤整体 skip（传统链路）不得隐藏侧栏")

	# ⑥ 关闭开关：下一场恢复传统链路。
	battle._immersive_stage.set_enabled(false)
	battle.turn_director.set_pref(attacker.id, &"skip_anim", false)
	var off_watcher := StageWatcher.new()
	off_watcher.attach(battle._immersive_stage, battle.action_anim)
	_reset_unit(attacker, 999)
	_reset_unit(defender, 999)
	await battle._resolve_combat(attacker, defender, func() -> void: pass)
	_expect(off_watcher.real_finished.size() == 1, "关闭舞台后应恢复真实 ActionAnim 链")
	_expect(off_watcher.started.is_empty(), "关闭舞台后不应再进舞台")
	_expect(sidebar.visible, "⑥关闭开关传统链路侧栏应保持可见")

	# ⑦ 死亡路径（最后执行，避免击杀后从 grid 移除影响后续场次）。
	#   前置：侧栏设为「原本隐藏」，演出不得强行打开它。
	battle._immersive_stage.set_enabled(true)
	sidebar.visible = false
	var hidden_during := {}
	battle._immersive_stage.presentation_started.connect(func(_event):
		hidden_during["visible"] = sidebar.visible)
	var death_watcher := StageWatcher.new()
	death_watcher.attach(battle._immersive_stage, battle.action_anim)
	_reset_unit(attacker, 999)
	_reset_unit(defender, 1)
	await battle._resolve_combat(attacker, defender, func() -> void: pass)
	_expect(death_watcher.finished.size() == 1, "击杀演出 finished 应恰一次")
	_expect(bool(defender.get(&"isDead", false)) or not battle.grid.units.has(defender.id),
		"击杀后真实单位应死亡/移除")
	_expect(not bool(hidden_during.get("visible", true)), "⑦演出中侧栏应保持隐藏（原本隐藏）")
	_expect(not sidebar.visible, "⑦原本隐藏的侧栏恢复后不得强行打开")

	battle.queue_free()
	await process_frame
	await process_frame


func _camera_state(camera: Camera3D) -> Dictionary:
	return {
		"origin": camera.global_transform.origin,
		"size": camera.size,
		"focus": camera.focus_position,
		"offset": camera.presentation_offset,
	}


## C. B2 技能/多目标/完整链/退出清理（plains_skirmish：4 玩家 vs 4 敌方）。
func _run_b2_plains() -> void:
	var battle := await _setup_battle(PLAINS)
	if battle == null:
		quit(1)
		return
	var players := _pick_all(battle, &"player")
	var enemies := _pick_all(battle, &"enemy")
	_expect(players.size() >= 2 and enemies.size() >= 2, "plains 缺少测试单位")
	var caster: Dictionary = players[0]
	var ally: Dictionary = players[1]

	# ⑧ 治疗：HP 回升呈现、无敌方参战、出手模板=事件 anim。
	_reset_unit(caster, 999)
	caster[&"mp"] = 999
	(caster.get(&"skills", []) as Array).append(&"heal")
	var heal_target_hp := 10
	_reset_unit(ally, heal_target_hp)
	ally[&"position"] = (caster[&"position"] as Vector2i) + Vector2i(1, 0)
	var heal_watcher := StageWatcher.new()
	heal_watcher.attach(battle._immersive_stage, battle.action_anim)
	var heal_handled: bool = await battle._resolve_skill(caster, [ally], &"heal")
	_expect(heal_handled, "heal 技能应可施放")
	var heal_event := _assert_sequenced(heal_watcher, "⑧治疗")
	if not heal_event.is_empty():
		var heal_impacts: Array = heal_event.get(&"impacts", [])
		_expect(heal_impacts.size() == 1, "单目标治疗应恰 1 个 impact")
		if heal_impacts.size() == 1:
			_expect(int(heal_impacts[0].get(&"healing", 0)) > 0, "治疗 impact 应有治疗量")
			_expect(int(ally[&"hp"]) == int(heal_impacts[0].get(&"hp_after", -1)), "治疗后真实 HP 应等于结算值")
		for strike_value in heal_watcher.strikes:
			var strike: Dictionary = strike_value
			_expect(StringName(strike.get(&"anim", &"")) == StringName(heal_event.get(&"anim", &"")),
				"治疗出手模板应沿用事件 anim")
		for unit_id in heal_watcher.slots_at_finish.keys():
			_expect(heal_watcher.slots_at_finish[unit_id][&"side"] == Layout.SIDE_ALLY,
				"治疗事件全部参战者应在盟军侧: %s" % String(unit_id))
		if heal_watcher.proxies_at_finish.has(ally.id):
			_expect(int(heal_watcher.proxies_at_finish[ally.id].get(&"hp", -1)) == int(heal_impacts[0].get(&"hp_after", -2)),
				"治疗结束时代理 HP 应为最终值")

	# ⑨ 自身 buff：statuses impact 可辨识。
	_reset_unit(caster, 999)
	caster[&"mp"] = 999
	(caster.get(&"skills", []) as Array).append(&"powerSurge")
	var buff_watcher := StageWatcher.new()
	buff_watcher.attach(battle._immersive_stage, battle.action_anim)
	var buff_handled: bool = await battle._resolve_skill(caster, [caster], &"powerSurge")
	_expect(buff_handled, "powerSurge 应可施放")
	var buff_event := _assert_sequenced(buff_watcher, "⑨buff")
	if not buff_event.is_empty():
		var buff_impacts: Array = buff_event.get(&"impacts", [])
		_expect(buff_impacts.size() == 1 and (buff_impacts[0].get(&"statuses", []) as Array).size() > 0,
			"buff 事件应有带 statuses 的 impact")

	# ⑩ aoe 多目标：出手次数 == impact 数，逐目标 HP 链。
	_reset_unit(caster, 999)
	caster[&"mp"] = 999
	(caster.get(&"skills", []) as Array).append(&"blizzard")
	var aoe_targets: Array = [enemies[0], enemies[1]]
	_reset_unit(aoe_targets[0], 999)
	_reset_unit(aoe_targets[1], 999)
	var aoe_watcher := StageWatcher.new()
	aoe_watcher.attach(battle._immersive_stage, battle.action_anim)
	var aoe_handled: bool = await battle._resolve_skill(caster, aoe_targets, &"blizzard")
	_expect(aoe_handled, "blizzard 应可施放")
	var aoe_event := _assert_sequenced(aoe_watcher, "⑩aoe")
	if not aoe_event.is_empty():
		var aoe_impacts: Array = aoe_event.get(&"impacts", [])
		_expect(aoe_impacts.size() >= 2, "aoe 应有多目标 impacts: %d" % aoe_impacts.size())
		var seen_targets := {}
		for impact_value in aoe_impacts:
			seen_targets[StringName(impact_value.get(&"target_id", &""))] = true
		_expect(seen_targets.size() >= 2, "aoe 应覆盖至少 2 个目标")

	# ⑪ 反击/连击/夹击合成链：出手顺序/模板按 source/标签/逐次 HP/死亡。
	var bow_ally: Dictionary = players[players.size() - 1]
	bow_ally[&"weapon"] = {&"id": &"w_bow", &"type": &"bow", &"might": 6, &"hit": 90, &"weight": 3}
	_reset_unit(caster, 40)
	_reset_unit(bow_ally, 30)
	var main_target: Dictionary = aoe_targets[0]
	_reset_unit(main_target, 40)
	var chain_event := {
		&"kind": &"normal",
		&"attacker_id": caster.id,
		&"primary_target_id": main_target.id,
		&"anim": &"slash",
		&"double_attack": true,
		&"hitstop": 0.0,
		&"impacts": [
			_impact(String(caster.id), String(main_target.id), true, 12, 40, 28),
			_impact(String(main_target.id), String(caster.id), true, 5, 40, 35),
			_impact(String(caster.id), String(main_target.id), true, 8, 28, 20),
			_impact(String(bow_ally.id), String(main_target.id), true, 20, 20, 0, {&"pincer": true}),
		],
	}
	var chain_watcher := StageWatcher.new()
	chain_watcher.attach(battle._immersive_stage, battle.action_anim)
	await battle._immersive_stage.present(chain_event, battle._unit_sprites, 1.0, false)
	_assert_sequenced(chain_watcher, "⑪合成链")
	if chain_watcher.strikes.size() == 4:
		_expect(StringName(chain_watcher.strikes[1].get(&"attacker_id", &"")) == StringName(main_target.id),
			"反击出手者应为原防御方")
		_expect(String(chain_watcher.strikes[1].get(&"_stage_label", "")) == "反击", "反击标签应在出手事件上")
		_expect(StringName(chain_watcher.strikes[2].get(&"attacker_id", &"")) == StringName(caster.id),
			"连击出手者应为原出手方")
		_expect(String(chain_watcher.strikes[2].get(&"_stage_label", "")) == "连击", "连击标签应在出手事件上")
		_expect(StringName(chain_watcher.strikes[3].get(&"attacker_id", &"")) == StringName(bow_ally.id),
			"夹击出手者应为对侧友军")
		_expect(StringName(chain_watcher.strikes[3].get(&"anim", &"")) == &"projectile:arrow",
			"夹击友军(bow)出手模板应为 arrow")
		_expect(not chain_watcher.strikes[3].has(&"_stage_label"), "夹击不应重复标签")
	if chain_watcher.proxies_at_finish.has(main_target.id):
		_expect(int(chain_watcher.proxies_at_finish[main_target.id].get(&"hp", -1)) == 0,
			"合成链结束时代理 HP 应为最终值 0")
		_expect(bool(chain_watcher.proxies_at_finish[main_target.id].get(&"isDead", false)),
			"致死链结束时代理应标 isDead")
	if chain_watcher.sprites_at_finish.has(main_target.id):
		var dead_sprite: Dictionary = chain_watcher.sprites_at_finish[main_target.id]
		_expect(not bool(dead_sprite["visible"]), "死亡代理收尾后应不可见（实际 %s）" % str(dead_sprite))
		_expect(String(dead_sprite["pose"]) == String(&"downed"),
			"死亡代理收尾姿态应保持倒地（finish_event 恢复后重放，实际 %s）" % str(dead_sprite["pose"]))
	# 真实单位零写回：合成链只存在于舞台。
	_expect(int(main_target[&"hp"]) == 40, "合成链不得写回真实单位 HP")
	_expect(not bool(main_target.get(&"isDead", false)), "合成链不得写回真实死亡态")

	# ⑫ 退出清理：慢速演出中途销毁 battle（_exit_tree → stage.cancel → teardown）。
	var plains_sidebar: Control = battle.battle_ui.get_sidebar()
	var exit_watcher := StageWatcher.new()
	exit_watcher.attach(battle._immersive_stage, battle.action_anim)
	battle._immersive_stage.present(chain_event.duplicate(true), battle._unit_sprites, 0.25, false)
	var exit_deadline := Time.get_ticks_msec() + 8000
	while exit_watcher.impacts.is_empty() and Time.get_ticks_msec() < exit_deadline:
		await process_frame
	_expect(not exit_watcher.impacts.is_empty(), "退出清理场景应至少呈现一次受击")
	_expect(battle._stage_layer != null and battle._stage_layer.visible,
		"演出进行中舞台层应显示")
	_expect(plains_sidebar != null and not plains_sidebar.visible,
		"⑫演出进行中侧栏应隐藏")
	battle.queue_free()
	await process_frame
	await process_frame
	await process_frame
	_expect(not is_instance_valid(battle), "演出中销毁 battle 应完成释放")

	# battle 已释放：不再触碰它；本节结束。


## D. B1（世界内联战斗）舞台路径。
func _run_b1_world() -> void:
	var world = load("res://main.tscn").instantiate()
	if world.get_script() == null:
		_expect(false, "main.gd 编译失败，测试不能作为通过依据")
		return
	world.seed = 42
	root.add_child(world)
	await process_frame
	var chapter: Dictionary = WorldToChapter.world_to_chapter(
		world._terrain_sampler, world._player_cell, 4, 42
	)
	world._enter_battle_inline(chapter)
	var battle = world._battle_system
	if battle == null or not is_instance_valid(battle):
		_expect(false, "B1 战斗创建失败")
		world.queue_free()
		return
	await battle.battle_ready
	_expect(battle._immersive_stage != null and battle._immersive_stage.is_enabled(),
		"B1 也应创建并启用沉浸舞台")
	# B1 世界 HUD 侧栏（左停靠栏 + 世界右侧栏）与战斗侧栏：独演中全隐藏，结束恢复。
	var left_rail: CanvasItem = world.get_node_or_null("GameHUD/HUDRoot/LeftRail")
	var world_side: CanvasItem = world.get_node_or_null("GameHUD/HUDRoot/SidePanel")
	_expect(left_rail != null and world_side != null, "B1 世界 HUD 侧栏应存在")
	var b1_sidebar: Control = battle.battle_ui.get_sidebar()
	var b1_columns_during := {}
	battle._immersive_stage.presentation_started.connect(func(_event):
		b1_columns_during["battle"] = b1_sidebar.visible if b1_sidebar != null else null
		b1_columns_during["rail"] = left_rail.visible
		b1_columns_during["side"] = world_side.visible)
	var b1_attacker := _pick(battle, &"player")
	var b1_defender := _pick(battle, &"enemy")
	_expect(not b1_attacker.is_empty() and not b1_defender.is_empty(), "B1 缺少测试单位")
	battle.turn_director.set_pref(b1_attacker.id, &"anim_speed", 8.0)
	_reset_unit(b1_attacker, 999)
	_reset_unit(b1_defender, 999)
	var b1_watcher := StageWatcher.new()
	b1_watcher.attach(battle._immersive_stage, battle.action_anim)
	var world_cam: Camera3D = world._cam
	var b1_cam_before := _camera_state(world_cam)
	await battle._resolve_combat(b1_attacker, b1_defender, func() -> void: pass)
	_assert_sequenced(b1_watcher, "⑬B1")
	var b1_cam_after := _camera_state(world_cam)
	_expect(b1_cam_before == b1_cam_after, "B1 舞台演出不得写入世界相机")
	_expect(bool(b1_columns_during.get("battle", true)) == false
		and bool(b1_columns_during.get("rail", true)) == false
		and bool(b1_columns_during.get("side", true)) == false,
		"⑬B1 演出中战斗侧栏+世界左栏/右侧栏都应隐藏")
	_expect(left_rail.visible and world_side.visible and b1_sidebar.visible,
		"⑬B1 演出结束三处侧栏都应恢复可见")
	_expect(battle._stage_hidden_columns.is_empty(), "⑬B1 恢复后隐藏记录应清空")

	# ⑭ B1 演出中退出战斗：cancel 不补发 finished，世界侧栏必须经 _exit_tree 恢复
	#    （世界 HUD 属于 main，不随战斗释放——漏恢复 = 永久隐藏）。
	var midexit_started := {}
	battle._immersive_stage.presentation_started.connect(func(_event):
		midexit_started["ok"] = true, CONNECT_ONE_SHOT)
	var midexit_event := {
		&"kind": &"normal",
		&"attacker_id": b1_attacker.id,
		&"primary_target_id": b1_defender.id,
		&"anim": &"slash",
		&"hitstop": 0.0,
		&"impacts": [
			_impact(String(b1_attacker.id), String(b1_defender.id), true, 5, 999, 994),
		],
	}
	battle._immersive_stage.present(midexit_event, battle._unit_sprites, 0.25, false)
	var midexit_deadline := Time.get_ticks_msec() + 8000
	while not midexit_started.has("ok") and Time.get_ticks_msec() < midexit_deadline:
		await process_frame
	_expect(bool(midexit_started.get("ok", false)), "⑭退出场景演出应已开始")
	_expect(not left_rail.visible and not world_side.visible and not b1_sidebar.visible,
		"⑭演出进行中世界侧栏应处于隐藏态")
	world._exit_battle(&"contract")
	await process_frame
	await process_frame
	await process_frame
	_expect(not is_instance_valid(battle), "⑭退出战斗后 battle 应已释放")
	_expect(left_rail.visible and world_side.visible,
		"⑭演出中退出战斗：世界左栏/右侧栏必须经 _exit_tree 精确恢复")
	world.queue_free()
	await process_frame
	await process_frame


## ————— E. 取景自适应（纯舞台：宽/窄/小窗口 × 2/6/10 人） —————

## 采样常量与舞台实现保持一致（脚/头身位）。
const FRAME_HALF := 0.35
const FRAME_HEAD := 1.45

func _run_framing() -> void:
	var windows: Array = [
		{"label": "宽1280x800", "size": Vector2(1280, 800)},
		{"label": "窄480x800", "size": Vector2(480, 800)},
		{"label": "小640x480", "size": Vector2(640, 480)},
	]
	var counts: Array = [2, 6, 10]
	for window in windows:
		# 裸舞台：不经 battle，直接驱动 _build_stage，用舞台相机实际投影断言。
		var stage = load("res://scenes/ImmersiveStage.tscn").instantiate()
		root.add_child(stage)
		stage.size = window["size"]
		await process_frame
		var zooms := {}
		for count in counts:
			var fixture := _framing_fixture(count)
			stage._real_units = fixture["units"]
			stage._build_stage(fixture["event"])
			await process_frame
			zooms[count] = _framing_assert(stage, "%s/%d人" % [window["label"], count])
		# 人数越多取景越广（zoom 不增）：同一窗口下的单调性。
		_expect(float(zooms[10]) <= float(zooms[2]) + 0.0001,
			"%s: 10 人取景不应比 2 人更近（zoom %s vs %s）" % [window["label"], str(zooms[10]), str(zooms[2])])
		stage.queue_free()
		await process_frame
		await process_frame


func _framing_fixture(count: int) -> Dictionary:
	var units := {}
	var impacts: Array = []
	var ally_count := maxi(1, count / 2)
	var enemy_count := maxi(1, count - ally_count)
	for i in range(ally_count):
		units[StringName("fp%d" % i)] = {
			&"id": StringName("fp%d" % i), &"faction": &"player", &"classId": &"knight",
			&"hp": 30, &"stats": {&"hp": 30}, &"weapon": {&"type": &"sword"},
		}
	for j in range(enemy_count):
		units[StringName("fe%d" % j)] = {
			&"id": StringName("fe%d" % j), &"faction": &"enemy", &"classId": &"knight",
			&"hp": 30, &"stats": {&"hp": 30}, &"weapon": {&"type": &"sword"},
		}
	impacts.append(_impact("fp0", "fe0", true, 5, 30, 25))
	for i in range(1, ally_count):
		impacts.append(_impact("fp%d" % i, "fe0", false, 0, 30, 30))
	for j in range(1, enemy_count):
		impacts.append(_impact("fp0", "fe%d" % j, false, 0, 30, 30))
	var event := {
		&"kind": &"normal",
		&"attacker_id": &"fp0",
		&"primary_target_id": &"fe0",
		&"anim": &"slash",
		&"impacts": impacts,
	}
	return {"units": units, "event": event}


## 返回当前舞台 zoom（供单调性断言）。
func _framing_assert(stage, label: String) -> float:
	var rect: Rect2 = stage.get_visible_rect()
	var camera = stage._camera
	var zoom := float(camera.get("zoom"))
	var tol := 2.0
	var ally_sum := Vector2.ZERO
	var enemy_sum := Vector2.ZERO
	var ally_n := 0
	var enemy_n := 0
	for unit_id in stage._slots.keys():
		var slot: Dictionary = stage._slots[unit_id]
		var ground: Vector3 = IsoProjection.grid_to_world(slot[&"cell"], 0.0)
		var samples: Array = [
			ground + Vector3(FRAME_HALF, 0.05, 0.0),
			ground + Vector3(-FRAME_HALF, 0.05, 0.0),
			ground + Vector3(0.0, 0.05, FRAME_HALF),
			ground + Vector3(0.0, 0.05, -FRAME_HALF),
			ground + Vector3(0.0, FRAME_HEAD, 0.0),
		]
		for sample in samples:
			var screen: Vector2 = camera.unproject_position(sample)
			_expect(
				screen.x >= -tol and screen.x <= rect.size.x + tol
					and screen.y >= -tol and screen.y <= rect.size.y + tol,
				"%s: 参战者 %s 采样点越出视口（%s → %s）" % [label, String(unit_id), str(sample), str(screen)])
		var feet: Vector2 = camera.unproject_position(ground + Vector3(0.0, 0.6, 0.0))
		if slot[&"side"] == Layout.SIDE_ALLY:
			ally_sum += feet
			ally_n += 1
		else:
			enemy_sum += feet
			enemy_n += 1
	if ally_n > 0 and enemy_n > 0:
		var ally_mean := ally_sum / float(ally_n)
		var enemy_mean := enemy_sum / float(enemy_n)
		_expect(enemy_mean.x > ally_mean.x and enemy_mean.y < ally_mean.y,
			"%s: 阵营对角分立错误：ally=%s enemy=%s" % [label, str(ally_mean), str(enemy_mean)])
	return zoom
