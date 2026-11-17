## tests/battle_levelup_flow_contract.gd — 升级演出×真实 Battle 装配探针（契约）
## 运行：godot --headless --path . --script res://tests/battle_levelup_flow_contract.gd
##
## 覆盖（真实 Battle.tscn 装配 + 真实 resolver 主路径，非 mock）：
##   Phase A 普攻末击双级连升：弹窗文本与 exp.levels[].gains 逐行一致、真实
##          Sfx.play(&"ui_levelup") 与 battle meta 双观测、弹窗期 on_done 未返还
##          （控制未回）、终局判定与结算演出均在弹窗之后（末击弹窗先于终局）、
##          skip 后 on_done 恰一次（phase 返还）、finished 恰一次。
##   Phase C 技能（smite）末击单级升级：_resolve_skill 协程完成（控制返还）+
##          终局置位 + 终局演出接续（终局时 mode 被 _check_battle_end 合法覆盖
##          为 ANIMATING，不在此断言 IDLE）。
##   Phase C2 技能非终局升级（守方存活）：skip 后 _resolve_skill 返还控制
##          （mode 回 IDLE 且保持）、无终局、无结算演出。
##   Phase D 无升级普攻（守方存活）：不弹窗、不发 finished、不触发 ui_levelup
##          音效（双观测零增量）。
## 场景边界：终局 result_finished 的 ONE_SHOT 连接在 _check_battle_end 才建立，
##   探针在其出现后立即断开（_neuter_result_finished），阻断
##   _on_result_presentation_finished 的 change_scene_to_file —— 探针自管
##   Battle 生命周期（每 phase queue_free），不得误切产品场景。
## 退出清理：每 phase 后多帧排空 Battle（queue_free 落地）+ 退出前清理本测试触发的
##   音频活动（_release_audio：停回放/清流引用/等混音帧，锚点日志
##   "[levelup-flow] sfx playback stopped & stream refs cleared before exit"）。
## 已知局限（2026-11-18 定论，不再扩大清理）：headless 退出仍报约 7 ObjectDB
##   + 3 resources 真实音频对象退出残留（AudioStreamPlayback*/被播流）。全库 grep
##   证明文件流的 GDScript 持有面只有 Sfx._streams 与池播放器 .stream，
##   _release_audio 均已清（运行态属性复核 custom_minimum/maximum sane）；
##   机制推断为 AudioServer 混音侧移除在退出检查前不提交（headless 无音频驱动的
##   环境限制，未在引擎源码层确证）。行为断言全绿（3/3 exit 0），泄漏计数随实际
##   播放次数浮动、与本契约清理逻辑无关（加清理前后不变即为佐证）。
## 控制法：world_to_chapter(null sampler) 生成确定性 5x5 平地 chapter，变异攻方
## （growths 全 100=每属性必 +1、weapon hit100 might30 weight0）与守方
## （weapon type=staff=不反击、stats 归零、hp=1 必杀 / hp=999 必活），
## 使结算结果完全确定；不影响任何公式与 RNG 本身。
extends SceneTree

const WorldToChapterScript = preload("res://scripts/core/world_to_chapter.gd")

## Phase A 期望成长文本：基础 stats {hp50 mp40 str30 mag20 skl99 spd10 luk99 def5 res5}
## 连升两级（exp 157 + 击杀 33 = 190 = 80(L1→2) + 110(L2→3)，WeaponData.exp_to_next
## = 50+level*30），growths 全 100 → 每属性每级 +1，余 0。
const EXPECT_GAINS_A := "▶ Lv.2\nHP 50 → 51\nMP 40 → 41\n力 30 → 31\n魔 20 → 21\n技 99 → 100\n速 10 → 11\n运 99 → 100\n防 5 → 6\n魔防 5 → 6\n▶ Lv.3\nHP 51 → 52\nMP 41 → 42\n力 31 → 32\n魔 21 → 22\n技 100 → 101\n速 11 → 12\n运 100 → 101\n防 6 → 7\n魔防 6 → 7"
## Phase C（exp 47 + 33 = 80 → 恰好一级）单段成长文本。
const EXPECT_GAINS_C := "HP 50 → 51\nMP 40 → 41\n力 30 → 31\n魔 20 → 21\n技 99 → 100\n速 10 → 11\n运 99 → 100\n防 5 → 6\n魔防 5 → 6"

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _phase_a_attack_kill()
	await _phase_c_skill_kill()
	await _phase_c2_skill_survive()
	await _phase_d_no_level()
	# 退出前停掉本测试触发的音频回放并清流引用（verbose 定位的泄漏源），排空混音帧。
	await _release_audio()
	if failures.is_empty():
		print("BATTLE_LEVELUP_FLOW_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


# ---------- helpers ----------

## 有界轮询等待：process_frame 驱动，超时返回最后一次条件值（不挂死）。
func _wait_until(condition: Callable, timeout_msec: int = 12000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return condition.call()


func _flush_frames() -> void:
	await process_frame
	await process_frame


## 真实 Sfx autoload 的 ui_levelup 最近播放时间戳（未播过 = -1）：Sfx.play 真实调用 spy。
func _sfx_last_play(cue: StringName) -> float:
	var sfx := root.get_node_or_null("Sfx")
	if sfx == null:
		return -1.0
	return float((sfx.get("_last_play_at") as Dictionary).get(cue, -1.0))


## battle.gd _on_presentation_sound 的 meta 观测：ui_levelup 累计次数。
func _meta_levelup_count(battle: Node) -> int:
	return int((battle.get_meta(&"presentation_sfx_counts", {}) as Dictionary).get(&"ui_levelup", 0))


## B2 装配：SceneArgs 注入 chapter 后真实实例化 Battle.tscn，等 battle_ready。
## battle 保持无类型注解：需要动态访问 battle.battle_ready / _level_up 等脚本成员。
func _make_battle(chapter: Dictionary):
	var args := root.get_node("SceneArgs")
	args.set("battle_args", {"chapter": chapter, "hosting": false})
	var battle = load("res://scenes/Battle.tscn").instantiate()
	var ready_done := {"ok": false}
	battle.battle_ready.connect(func() -> void: ready_done.ok = true)
	root.add_child(battle)
	await _wait_until(func() -> bool: return ready_done.ok, 15000)
	_expect(battle.get_script() != null, "Battle 脚本编译通过")
	return battle


## 终局 result_finished 的 ONE_SHOT 连接在 _check_battle_end 时才建立（_make_battle
## 时还不存在）；终局置位后轮询其出现并断开，阻断 B2 change_scene_to_file 副作用。
func _neuter_result_finished(battle) -> bool:
	var ui = battle.battle_ui
	if ui == null:
		return false
	var found := await _wait_until(func() -> bool:
		return not ui.get_signal_connection_list(&"result_finished").is_empty(), 4000)
	if not found:
		return false
	for conn in ui.get_signal_connection_list(&"result_finished"):
		ui.result_finished.disconnect(conn["callable"])
	return true


## fire-and-forget 跑 _resolve_skill 并记录协程完成（控制返还的可观测证据）。
func _run_skill(battle, attacker: Dictionary, defender: Dictionary, done: Dictionary) -> void:
	await battle._resolve_skill(attacker, [defender], &"smite")
	done.n += 1


func _free_battle(battle: Node) -> void:
	if is_instance_valid(battle):
		battle.queue_free()
		# 多帧排空：让 queue_free 落地、deferred 调用与 Tween/协程尾帧全部完成，
		# 避免退出时 pending 引用计入 ObjectDB 泄漏。
		for i in 8:
			await process_frame


## 退出前清理本测试触发的音频活动 —— Lead --verbose 复跑定位的泄漏源全部是音频：
## AudioStreamPlaybackMP3/WAV（活跃回放）+ AudioStreamMP3/WAV（Sfx._streams 流缓存
## 与池 player.stream 播完残留的引用）。此处只做测试侧收尾：停回放、清 player.stream、
## 清 Sfx._streams、等混音帧；不动 _last_play_at（真实 Sfx spy 断言全部在此之前完成）。
func _release_audio() -> void:
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null:
		for child in sfx.get_children():
			if child is AudioStreamPlayer:
				child.stop()
				child.stream = null
		sfx.set("_streams", {})
	for i in 6:
		await process_frame
	print("[levelup-flow] sfx playback stopped & stream refs cleared before exit")


## 攻方变异：growths 全 100（每属性必 +1）、stats 定值、必中武器、mp 充足、带 smite。
func _mutate_attacker(unit: Dictionary, exp: int) -> void:
	unit[&"level"] = 1
	unit[&"exp"] = exp
	unit[&"growths"] = {
		&"hp": 100, &"mp": 100, &"str": 100, &"mag": 100, &"skl": 100,
		&"spd": 100, &"luk": 100, &"def": 100, &"res": 100,
	}
	unit[&"stats"] = {
		&"hp": 50, &"mp": 40, &"str": 30, &"mag": 20, &"skl": 99,
		&"spd": 10, &"luk": 99, &"def": 5, &"res": 5, &"mov": 5,
	}
	unit[&"hp"] = 50
	unit[&"mp"] = 99
	unit[&"weapon"] = {
		&"id": &"probe_sword", &"name": "探针剑", &"type": &"sword",
		&"might": 30, &"hit": 100, &"crit": 0, &"weight": 0, &"range": [1, 1],
	}
	var skills: Array = unit[&"skills"]
	if not skills.has(&"smite"):
		skills.append(&"smite")
	unit[&"skillCooldowns"] = {}
	unit[&"hasMoved"] = false
	unit[&"hasActed"] = false
	unit[&"isDead"] = false


## 守方变异：staff 武器（不反击）、属性归零；hp=1 必被击杀 / hp=999 必存活。
func _mutate_defender(unit: Dictionary, hp: int) -> void:
	unit[&"level"] = 1
	unit[&"exp"] = 0
	unit[&"stats"] = {
		&"hp": hp, &"mp": 0, &"str": 0, &"mag": 0, &"skl": 0,
		&"spd": 0, &"luk": 0, &"def": 0, &"res": 0, &"mov": 0,
	}
	unit[&"hp"] = hp
	unit[&"mp"] = 0
	unit[&"weapon"] = {
		&"id": &"probe_staff", &"name": "探针杖", &"type": &"staff",
		&"might": 0, &"hit": 0, &"crit": 0, &"weight": 0, &"range": [1, 2],
	}
	unit[&"isDead"] = false


func _popup_label(battle, node_name: String) -> Label:
	return battle._level_up.find_child(node_name, true, false) as Label


# ---------- phases ----------

func _phase_a_attack_kill() -> void:
	var chapter: Dictionary = WorldToChapterScript.world_to_chapter(
		null, Vector2i.ZERO, 2, 42, 1)
	var attacker: Dictionary = chapter.playerUnits[0]
	var defender: Dictionary = chapter.enemyUnits[0]
	_mutate_attacker(attacker, 157)  # 157 + 击杀33 = 190 = 80(L1→2)+110(L2→3) 恰两级余 0
	_mutate_defender(defender, 1)
	var battle = await _make_battle(chapter)
	if battle == null or battle.get_script() == null:
		return
	_expect(battle._level_up != null, "A 升级弹窗节点已装配（battle._level_up）")
	if battle._level_up == null:
		await _free_battle(battle)
		return
	var finished := {"n": 0}
	battle._level_up.finished.connect(func(_skipped: bool) -> void: finished.n += 1)
	var cb_count := {"n": 0}
	var ts0 := _sfx_last_play(&"ui_levelup")
	var counts0 := _meta_levelup_count(battle)
	# 真实普攻主路径（fire-and-forget，便于弹窗期间断言"控制未返还"）。
	battle._resolve_combat(attacker, defender, func() -> void:
		cb_count.n += 1
		battle.mode = battle.Mode.IDLE
		battle._check_battle_end())
	var shown := await _wait_until(func() -> bool:
		return battle._level_up != null and battle._level_up.is_playing())
	_expect(shown, "A 普攻末击双级升级：弹窗出现")
	if shown:
		_expect(cb_count.n == 0, "A 弹窗期 on_done 未返还（实际 %d）" % cb_count.n)
		_expect(battle.mode == battle.Mode.ANIMATING, "A 弹窗期 mode=ANIMATING（实际 %d）" % battle.mode)
		_expect(not battle._battle_ended, "A 弹窗先于终局判定")
		_expect(not battle.battle_ui.is_presentation_active(), "A 弹窗期结算演出未开始")
		var gains_text := _popup_label(battle, "GainsText").text
		_expect(gains_text == EXPECT_GAINS_A, "A gains 文本与 levels[].gains 逐行一致（实际 %s）" % gains_text)
		var range_text := _popup_label(battle, "LevelRange").text
		_expect(range_text == "Lv.1 → Lv.3", "A 双级跨度 Lv.1 → Lv.3（实际 %s）" % range_text)
		_expect(_popup_label(battle, "LevelTitle").text == "%s 升级！" % String(attacker[&"name"]),
			"A 标题使用单位名")
		var ts1 := _sfx_last_play(&"ui_levelup")
		var counts1 := _meta_levelup_count(battle)
		_expect(ts1 >= 0.0 and ts1 != ts0, "A 真实 Sfx.play(ui_levelup) 被调用（%f → %f）" % [ts0, ts1])
		_expect(counts1 == counts0 + 1, "A battle meta ui_levelup 计数 +1（%d → %d）" % [counts0, counts1])
		_expect(battle.get_meta(&"presentation_sfx_last", &"") == &"ui_levelup",
			"A 最近演出音效 cue = ui_levelup")
		battle._level_up.skip()
		var done := await _wait_until(func() -> bool: return cb_count.n == 1, 4000)
		_expect(done, "A skip 后 on_done 恰一次（phase 返还，实际 %d）" % cb_count.n)
		_expect(not battle._level_up.is_playing(), "A skip 后弹窗关闭")
		_expect(finished.n == 1, "A finished 恰一次（实际 %d）" % finished.n)
		var ended := await _wait_until(func() -> bool: return battle._battle_ended, 4000)
		_expect(ended, "A 末击终局在弹窗收尾后置位")
		var result_live := await _wait_until(func() -> bool:
			return battle.battle_ui.is_presentation_active(), 4000)
		_expect(result_live, "A 终局演出在弹窗之后接续")
		# 终局连接出现即断开（防 change_scene_to_file 误切产品场景），再快进结算演出。
		var neutered := await _neuter_result_finished(battle)
		_expect(neutered, "A 终局 result_finished 连接已断开（场景边界）")
		battle.battle_ui.skip_presentation()
		var result_done := await _wait_until(func() -> bool:
			return not battle.battle_ui.is_presentation_active(), 4000)
		_expect(result_done, "A 结算演出收尾")
		_expect(battle.is_inside_tree(), "A 无场景切换（battle 仍在树内）")
		await _free_battle(battle)


func _phase_c_skill_kill() -> void:
	var chapter: Dictionary = WorldToChapterScript.world_to_chapter(
		null, Vector2i.ZERO, 2, 43, 1)
	var attacker: Dictionary = chapter.playerUnits[0]
	var defender: Dictionary = chapter.enemyUnits[0]
	_mutate_attacker(attacker, 47)  # 47 + 击杀33 = 80 → 恰好一级
	_mutate_defender(defender, 1)
	var battle = await _make_battle(chapter)
	if battle == null or battle.get_script() == null:
		return
	_expect(battle._level_up != null, "C 升级弹窗节点已装配（battle._level_up）")
	if battle._level_up == null:
		await _free_battle(battle)
		return
	var finished := {"n": 0}
	battle._level_up.finished.connect(func(_skipped: bool) -> void: finished.n += 1)
	var ts0 := _sfx_last_play(&"ui_levelup")
	var counts0 := _meta_levelup_count(battle)
	var skill_done := {"n": 0}
	# 真实技能主路径（fire-and-forget + 完成计数 = 协程返还控制的可观测证据）。
	_run_skill(battle, attacker, defender, skill_done)
	var shown := await _wait_until(func() -> bool:
		return battle._level_up != null and battle._level_up.is_playing())
	_expect(shown, "C 技能末击升级：弹窗出现")
	if shown:
		_expect(battle.mode == battle.Mode.ANIMATING, "C 弹窗期 mode=ANIMATING（实际 %d）" % battle.mode)
		_expect(not battle._battle_ended, "C 弹窗先于终局判定")
		var gains_text := _popup_label(battle, "GainsText").text
		_expect(gains_text == EXPECT_GAINS_C, "C gains 文本与 levels[].gains 一致（实际 %s）" % gains_text)
		var range_text := _popup_label(battle, "LevelRange").text
		_expect(range_text == "Lv.1 → Lv.2", "C 单级跨度 Lv.1 → Lv.2（实际 %s）" % range_text)
		var ts1 := _sfx_last_play(&"ui_levelup")
		var counts1 := _meta_levelup_count(battle)
		_expect(ts1 >= 0.0 and ts1 != ts0, "C 真实 Sfx.play(ui_levelup) 被调用（%f → %f）" % [ts0, ts1])
		_expect(counts1 == counts0 + 1, "C battle meta ui_levelup 计数 +1（%d → %d）" % [counts0, counts1])
		battle._level_up.skip()
		# 终局路径：mode 被 _check_battle_end 合法覆盖为 ANIMATING，控制返还以
		# 协程完成为准（skill_done），终局以置位+结算演出接续为准。
		var returned := await _wait_until(func() -> bool: return skill_done.n == 1, 4000)
		_expect(returned, "C skip 后 _resolve_skill 协程完成（控制返还）")
		_expect(not battle._level_up.is_playing(), "C skip 后弹窗关闭")
		_expect(finished.n == 1, "C finished 恰一次（实际 %d）" % finished.n)
		var ended := await _wait_until(func() -> bool: return battle._battle_ended, 4000)
		_expect(ended, "C 技能末击终局置位")
		var result_live := await _wait_until(func() -> bool:
			return battle.battle_ui.is_presentation_active(), 4000)
		_expect(result_live, "C 终局演出在弹窗之后接续")
		var neutered := await _neuter_result_finished(battle)
		_expect(neutered, "C 终局 result_finished 连接已断开（场景边界）")
		battle.battle_ui.skip_presentation()
		var result_done := await _wait_until(func() -> bool:
			return not battle.battle_ui.is_presentation_active(), 4000)
		_expect(result_done, "C 结算演出收尾")
		_expect(battle.is_inside_tree(), "C 无场景切换（battle 仍在树内）")
	await _free_battle(battle)


## 技能非终局升级：守方存活（hp 999，smite 伤害 38 不足击杀）、exp 70 + 命中10
## = 80 恰一级 —— 验证 skip 后 _resolve_skill 返还控制（mode 回 IDLE 且保持）、
## 无终局无结算演出（终局覆盖 IDLE 的场景由 Phase C 单独覆盖）。
func _phase_c2_skill_survive() -> void:
	var chapter: Dictionary = WorldToChapterScript.world_to_chapter(
		null, Vector2i.ZERO, 2, 45, 1)
	var attacker: Dictionary = chapter.playerUnits[0]
	var defender: Dictionary = chapter.enemyUnits[0]
	_mutate_attacker(attacker, 70)  # 70 + 命中10 = 80 → 恰好一级（守方存活）
	_mutate_defender(defender, 999)
	var battle = await _make_battle(chapter)
	if battle == null or battle.get_script() == null:
		return
	_expect(battle._level_up != null, "C2 升级弹窗节点已装配（battle._level_up）")
	if battle._level_up == null:
		await _free_battle(battle)
		return
	var finished := {"n": 0}
	battle._level_up.finished.connect(func(_skipped: bool) -> void: finished.n += 1)
	var ts0 := _sfx_last_play(&"ui_levelup")
	var counts0 := _meta_levelup_count(battle)
	var skill_done := {"n": 0}
	_run_skill(battle, attacker, defender, skill_done)
	var shown := await _wait_until(func() -> bool:
		return battle._level_up != null and battle._level_up.is_playing())
	_expect(shown, "C2 技能非终局升级：弹窗出现")
	if shown:
		_expect(battle.mode == battle.Mode.ANIMATING, "C2 弹窗期 mode=ANIMATING（实际 %d）" % battle.mode)
		_expect(not battle._battle_ended, "C2 守方存活无终局")
		var gains_text := _popup_label(battle, "GainsText").text
		_expect(gains_text == EXPECT_GAINS_C, "C2 gains 文本与 levels[].gains 一致（实际 %s）" % gains_text)
		var range_text := _popup_label(battle, "LevelRange").text
		_expect(range_text == "Lv.1 → Lv.2", "C2 单级跨度 Lv.1 → Lv.2（实际 %s）" % range_text)
		var ts1 := _sfx_last_play(&"ui_levelup")
		var counts1 := _meta_levelup_count(battle)
		_expect(ts1 >= 0.0 and ts1 != ts0, "C2 真实 Sfx.play(ui_levelup) 被调用（%f → %f）" % [ts0, ts1])
		_expect(counts1 == counts0 + 1, "C2 battle meta ui_levelup 计数 +1（%d → %d）" % [counts0, counts1])
		battle._level_up.skip()
		var idle := await _wait_until(func() -> bool: return battle.mode == battle.Mode.IDLE, 4000)
		_expect(idle, "C2 skip 后 _resolve_skill 返还控制（mode 回 IDLE，实际 %d）" % battle.mode)
		var returned := await _wait_until(func() -> bool: return skill_done.n == 1, 4000)
		_expect(returned, "C2 _resolve_skill 协程完成")
		_expect(not battle._level_up.is_playing(), "C2 skip 后弹窗关闭")
		_expect(finished.n == 1, "C2 finished 恰一次（实际 %d）" % finished.n)
		_expect(not battle._battle_ended, "C2 无终局置位")
		_expect(not battle.battle_ui.is_presentation_active(), "C2 无结算演出")
		await _flush_frames()
		_expect(battle.mode == battle.Mode.IDLE, "C2 mode 保持 IDLE（终局未覆盖）")
	await _free_battle(battle)


func _phase_d_no_level() -> void:
	var chapter: Dictionary = WorldToChapterScript.world_to_chapter(
		null, Vector2i.ZERO, 2, 44, 1)
	var attacker: Dictionary = chapter.playerUnits[0]
	var defender: Dictionary = chapter.enemyUnits[0]
	_mutate_attacker(attacker, 0)  # 命中经验 10 < 阈值 80：不升级
	_mutate_defender(defender, 999)  # 守方存活：无击杀无终局
	var battle = await _make_battle(chapter)
	if battle == null or battle.get_script() == null:
		return
	_expect(battle._level_up != null, "D 升级弹窗节点已装配（battle._level_up）")
	if battle._level_up == null:
		await _free_battle(battle)
		return
	var finished := {"n": 0}
	battle._level_up.finished.connect(func(_skipped: bool) -> void: finished.n += 1)
	var ts0 := _sfx_last_play(&"ui_levelup")
	var counts0 := _meta_levelup_count(battle)
	await battle._resolve_combat(attacker, defender, Callable())
	await _flush_frames()
	_expect(not battle._level_up.is_playing(), "D 无升级不弹窗")
	_expect(finished.n == 0, "D 无升级不发 finished（实际 %d）" % finished.n)
	_expect(_sfx_last_play(&"ui_levelup") == ts0, "D 真实 Sfx(ui_levelup) 零调用")
	_expect(_meta_levelup_count(battle) == counts0, "D battle meta ui_levelup 零增量（%d → %d）" % [counts0, _meta_levelup_count(battle)])
	_expect(not battle._battle_ended, "D 守方存活无终局")
	await _free_battle(battle)
