## battle_drop_contract.gd — W4 击杀掉落契约（loader/resolver/runner/campaign 全链）
##
## 覆盖：
##   1. plains 示范数据：drop_table 白名单保留 + 归一化形状
##   2. loader 严格校验：player 侧声明/非数组/空表/未知物品/重复 id/非法 count/weight
##   3. resolver 普攻致死掷落 + 同 seed 重放一致 + 空 ctx 旧行为
##   4. 同敌重复致死不重掷（rolled 幂等）
##   5. 同 id 合并（两名敌人同表）
##   6. 独立 RNG 不扰全局流（有表/无表敌人，全局 randf 探针前后一致）
##   7. 致死类别：普攻 / 反击 / 技能 / 投掷物
##   8. runner 真实入口：inline 场景脚本攻击致死 → chapter.pending_loot 落物
##   9. campaign 集成：prepare → resolver 击杀（battle.gd 同款种子）→ settle win
##      → receipt.loot 精确合并（关卡表掷出 + 击杀掉落）+ 落盘 + level_ups 保留
extends SceneTree


const Loader := preload("res://scripts/core/battlefield_loader.gd")
const Resolver := preload("res://scripts/battle/battle_action_resolver.gd")
const ScenarioLoader := preload("res://scripts/battle/automation/battle_scenario_loader.gd")
const Runner := preload("res://scripts/battle/automation/battle_runner.gd")
const SessionScript := preload("res://scripts/campaign/campaign_session.gd")
const CampaignConfig := preload("res://scripts/campaign/campaign_config.gd")

const PLAINS := "res://data/battlefields/plains_skirmish.json"
const ROOT := "user://battle_drop_contract_tmp"

var failures: Array = []
var _cur_dir := ""
var _sessions: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	_test_plains_data()
	_test_loader_validation()
	_test_resolver_attack_drop()
	_test_repeat_death_no_redrop()
	_test_same_id_merge()
	_test_independent_rng()
	_test_death_categories()
	_test_runner_inline_drop()
	_test_campaign_win_drops()
	if failures.is_empty():
		print("BATTLE_DROP_CONTRACT_OK")
		quit(0)
	else:
		for f in failures:
			print("FAIL: %s" % f)
		quit(1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


## 战场加载 + 返回第一个带 drop_table 的敌人与不带表的敌人（供 resolver 测试用）。
func _plains_units() -> Dictionary:
	var res := Loader.load_battlefield(PLAINS)
	if not bool(res.get("ok", false)):
		return {}
	var chapter: Dictionary = res["chapter"]
	var with_table: Dictionary = {}
	var without_table: Dictionary = {}
	for u in chapter["enemyUnits"]:
		if (u as Dictionary).has(&"drop_table"):
			if with_table.is_empty():
				with_table = u
		elif without_table.is_empty():
			without_table = u
	return {
		"chapter": chapter, "with_table": with_table, "without_table": without_table,
	}


func _mk_ctx(seed_value: int, loot: Array = []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return { "rng": rng, "loot": loot, "rolled": {} }


func _mk_grid(chapter: Dictionary) -> GridSystem:
	return GridSystem.new(int(chapter["width"]), int(chapter["height"]), chapter["map"])


# ------------------------------------------------------------------
# 1. plains 示范数据
# ------------------------------------------------------------------
func _test_plains_data() -> void:
	var pu := _plains_units()
	if pu.is_empty():
		failures.append("plains 加载失败")
		return
	var chapter: Dictionary = pu["chapter"]
	var tabled := 0
	var plain_count := 0
	var berserker_table: Array = []
	var assassin_table: Array = []
	for u in chapter["enemyUnits"]:
		var ud: Dictionary = u
		if ud.has(&"drop_table"):
			tabled += 1
			if String(ud.get(&"name", "")) == "血斧":
				berserker_table = ud[&"drop_table"]
			elif String(ud.get(&"name", "")) == "影刃":
				assassin_table = ud[&"drop_table"]
		else:
			plain_count += 1
	_expect(tabled == 2 and plain_count == 2, "plains 恰 2 敌带表、2 敌无表（got %d/%d）" % [tabled, plain_count])
	_expect(berserker_table.size() == 2, "血斧表 2 条")
	if berserker_table.size() == 2:
		var e0: Dictionary = berserker_table[0]
		_expect(e0.get("id", &"") == &"hpPotion" and int(e0.get("count", 0)) == 1 and float(e0.get("weight", 0.0)) == 60.0,
			"血斧表[0] hpPotion count1 w60（got %s）" % str(e0))
		_expect((berserker_table[1] as Dictionary).get("id", &"") == &"shuriken",
			"血斧表[1] shuriken")
	_expect(assassin_table.size() == 1 and (assassin_table[0] as Dictionary).get("id", &"") == &"bomb",
		"影刃表单条 bomb w100")
	# 归一化类型：id StringName / count int / weight float
	if berserker_table.size() == 2:
		var e0: Dictionary = berserker_table[0]
		_expect(typeof(e0["id"]) == TYPE_STRING_NAME and typeof(e0["count"]) == TYPE_INT and typeof(e0["weight"]) == TYPE_FLOAT,
			"表条目归一化类型 id/count/weight")


# ------------------------------------------------------------------
# 2. loader 严格校验
# ------------------------------------------------------------------
func _inline_bf(enemy_extra: Dictionary = {}) -> Dictionary:
	var enemy: Dictionary = { "class": "berserker", "x": 2, "y": 0 }
	for k in enemy_extra.keys():
		enemy[k] = enemy_extra[k]
	return {
		"rows": ["...", "...", "..."],
		"playerUnits": [{ "class": "swordsman", "x": 0, "y": 0 }],
		"enemyUnits": [enemy],
	}


func _load_inline(d: Dictionary) -> Dictionary:
	return Loader.load_battlefield_inline(d, "drop_val")


func _test_loader_validation() -> void:
	# 合法表通过并挂到单位
	var ok_res := _load_inline(_inline_bf({
		"drop_table": [{ "id": "hpPotion", "count": 2, "weight": 60 }],
	}))
	_expect(bool(ok_res.get("ok", false)), "合法 drop_table 通过: %s" % str(ok_res.get("error", "")))
	if bool(ok_res.get("ok", false)):
		var eu: Dictionary = ok_res["chapter"]["enemyUnits"][0]
		_expect(eu.has(&"drop_table") and (eu[&"drop_table"] as Array).size() == 1,
			"合法表挂在敌方单位上")
	var cases: Array = [
		[{ "drop_table": [{ "id": "hpPotion", "count": 1, "weight": 60 }] }, "player 侧声明", "仅支持敌方"],
		[{ "drop_table": "hpPotion" }, "非数组", "必须是数组"],
		[{ "drop_table": [] }, "空表", "不能为空"],
		[{ "drop_table": [{ "id": "notExist", "count": 1, "weight": 60 }] }, "未知物品", "未知物品"],
		[{ "drop_table": [{ "id": "hpPotion", "count": 1, "weight": 60 }, { "id": "hpPotion", "count": 1, "weight": 40 }] }, "重复 id", "重复"],
		[{ "drop_table": [{ "id": "hpPotion", "count": 0, "weight": 60 }] }, "count 0", "count 必须"],
		[{ "drop_table": [{ "id": "hpPotion", "count": 1.5, "weight": 60 }] }, "count 1.5", "count 必须"],
		[{ "drop_table": [{ "id": "hpPotion", "count": 1, "weight": 0 }] }, "weight 0", "weight 必须"],
		[{ "drop_table": [{ "id": "hpPotion", "count": 1, "weight": -5 }] }, "weight -5", "weight 必须"],
		[{ "drop_table": [{ "id": "hpPotion", "count": 1, "weight": "60" }] }, "weight 字符串", "weight 必须"],
	]
	for case in cases:
		var player_side: bool = String(case[1]) == "player 侧声明"
		var d := _inline_bf(case[0])
		if player_side:
			(d["playerUnits"][0] as Dictionary)["drop_table"] = case[0]["drop_table"]
			((d["enemyUnits"][0] as Dictionary)).erase("drop_table")
		var res := _load_inline(d)
		_expect(not bool(res.get("ok", false)) and String(res.get("error", "")).contains(case[2]),
			"loader 拒绝 %s（got %s）" % [case[1], str(res.get("error", "无错误"))])


# ------------------------------------------------------------------
# 3. resolver 普攻致死掷落 + 重放一致
# ------------------------------------------------------------------
func _kill_by_attack(chapter: Dictionary, attacker: Dictionary, victim: Dictionary, ctx: Dictionary) -> Dictionary:
	# 挑一个能保证命中的做法：把 victim hp 压到 1，attacker 保持满状态；
	# 命中带随机性 → 调用方先 seed。
	return Resolver.resolve_attack(attacker, victim, _mk_grid(chapter), ctx)


func _test_resolver_attack_drop() -> void:
	var pu := _plains_units()
	if pu.is_empty():
		failures.append("plains 加载失败（attack_drop）")
		return
	var chapter: Dictionary = pu["chapter"]
	var victim: Dictionary = pu["with_table"]
	# 独立副本：两轮重放互不干扰
	var run := func() -> String:
		var v: Dictionary = victim.duplicate(true)
		v[&"hp"] = 1
		var a: Dictionary = (chapter["playerUnits"][0] as Dictionary).duplicate(true)
		seed(4242)
		var loot: Array = []
		var outcome := _kill_by_attack(chapter, a, v, _mk_ctx(77, loot))
		if (outcome[&"deaths"] as Array).is_empty():
			failures.append("seed 4242 未致死（重放前提破坏）")
		return JSON.stringify(_str_loot(loot))
	var first: String = run.call()
	var second: String = run.call()
	_expect(not first.is_empty() and first == second, "同 seed 击杀掉落重放一致：%s vs %s" % [first, second])
	# 空 ctx：旧行为（不掷落）且不报错
	var v2: Dictionary = victim.duplicate(true)
	v2[&"hp"] = 1
	var a2: Dictionary = (chapter["playerUnits"][0] as Dictionary).duplicate(true)
	seed(4242)
	var outcome2 := Resolver.resolve_attack(a2, v2, _mk_grid(chapter))
	_expect(not (outcome2[&"deaths"] as Array).is_empty(), "空 ctx 仍正常致死")
	# loot 形状：单表敌一次掷一件 → 恰 1 条 {id,count}
	var loot3: Array = []
	var v3: Dictionary = victim.duplicate(true)
	v3[&"hp"] = 1
	var a3: Dictionary = (chapter["playerUnits"][0] as Dictionary).duplicate(true)
	seed(4242)
	_kill_by_attack(chapter, a3, v3, _mk_ctx(77, loot3))
	_expect(loot3.size() == 1 and int((loot3[0] as Dictionary).get("count", 0)) >= 1
		and typeof((loot3[0] as Dictionary).get("id", &"")) == TYPE_STRING_NAME,
		"单敌击杀恰掷 1 件（got %s）" % str(loot3))


func _str_loot(loot: Array) -> Array:
	var out: Array = []
	for e in loot:
		var ed: Dictionary = e
		out.append({ "id": String(ed.get("id", &"")), "count": int(ed.get("count", 0)) })
	return out


# ------------------------------------------------------------------
# 4. 同敌重复致死不重掷
# ------------------------------------------------------------------
func _test_repeat_death_no_redrop() -> void:
	var pu := _plains_units()
	if pu.is_empty():
		failures.append("plains 加载失败（repeat_death）")
		return
	var chapter: Dictionary = pu["chapter"]
	var v: Dictionary = pu["with_table"].duplicate(true)
	v[&"hp"] = 1
	var a: Dictionary = (chapter["playerUnits"][0] as Dictionary).duplicate(true)
	var loot: Array = []
	var ctx := _mk_ctx(9, loot)
	seed(11)
	var o1 := _kill_by_attack(chapter, a, v, ctx)
	if (o1[&"deaths"] as Array).is_empty():
		failures.append("seed 11 首击未致死（前提破坏）")
		return
	var count1 := int((loot[0] as Dictionary).get("count", 0)) if loot.size() > 0 else 0
	# 第二次攻击同一具尸体：CombatSystem 仍会给出 defenderDied（hp=0），
	# rolled 幂等表必须保证不重掷。
	seed(12)
	var o2 := _kill_by_attack(chapter, a, v, ctx)
	_expect(not (o2[&"deaths"] as Array).is_empty(), "重复攻击仍计死亡")
	var count2 := int((loot[0] as Dictionary).get("count", 0)) if loot.size() > 0 else 0
	_expect(count1 == count2, "重复致死不重掷（%d → %d）" % [count1, count2])


# ------------------------------------------------------------------
# 5. 同 id 合并
# ------------------------------------------------------------------
func _test_same_id_merge() -> void:
	var pu := _plains_units()
	if pu.is_empty():
		failures.append("plains 加载失败（same_id）")
		return
	var chapter: Dictionary = pu["chapter"]
	# 两名同表敌人：表内只有 hpPotion → 合并成单条 count=2
	var table := [{ "id": &"hpPotion", "count": 1, "weight": 100.0 }]
	var loot: Array = []
	var ctx := _mk_ctx(5, loot)
	var a: Dictionary = (chapter["playerUnits"][0] as Dictionary).duplicate(true)
	for i in range(2):
		var v: Dictionary = pu["with_table"].duplicate(true)
		v[&"hp"] = 1
		v[&"drop_table"] = table
		v[&"id"] = StringName("dup_%d" % i)
		seed(30 + i)
		var o := _kill_by_attack(chapter, a, v, ctx)
		if (o[&"deaths"] as Array).is_empty():
			failures.append("seed %d 未致死（same_id 前提）" % (30 + i))
			return
	_expect(loot.size() == 1, "同 id 合并成单条（got %s）" % str(loot))
	if loot.size() == 1:
		_expect(int((loot[0] as Dictionary).get("count", 0)) == 2,
			"合并 count=2（got %s）" % str(loot[0]))


# ------------------------------------------------------------------
# 6. 独立 RNG：全局 randf 探针不受掉落掷骰影响
# ------------------------------------------------------------------
func _probe_run(chapter: Dictionary, victim: Dictionary, use_ctx: bool) -> float:
	var v: Dictionary = victim.duplicate(true)
	v[&"hp"] = 1
	var a: Dictionary = (chapter["playerUnits"][0] as Dictionary).duplicate(true)
	seed(777)
	var ctx := _mk_ctx(31337) if use_ctx else {}
	_kill_by_attack(chapter, a, v, ctx)
	return randf()


func _test_independent_rng() -> void:
	var pu := _plains_units()
	if pu.is_empty():
		failures.append("plains 加载失败（independent_rng）")
		return
	var chapter: Dictionary = pu["chapter"]
	# 无表敌人：ctx 开关不影响全局流
	var p1 := _probe_run(chapter, pu["without_table"], false)
	var p2 := _probe_run(chapter, pu["without_table"], true)
	_expect(p1 == p2, "无表敌人掉落路径零全局消耗（%f vs %f）" % [p1, p2])
	# 有表敌人：掷落一次，同样不动全局流
	var q1 := _probe_run(chapter, pu["with_table"], false)
	var q2 := _probe_run(chapter, pu["with_table"], true)
	_expect(q1 == q2, "有表敌人掉落掷骰独立于全局流（%f vs %f）" % [q1, q2])


# ------------------------------------------------------------------
# 7. 致死类别：普攻（已覆盖）/ 反击 / 技能 / 投掷物
# ------------------------------------------------------------------
func _test_death_categories() -> void:
	var pu := _plains_units()
	if pu.is_empty():
		failures.append("plains 加载失败（categories）")
		return
	var chapter: Dictionary = pu["chapter"]
	var drop_entry := { "id": &"bomb", "count": 1, "weight": 100.0 }

	# --- 反击致死：弱敌攻强玩家，被反击打死 ---
	var v: Dictionary = pu["with_table"].duplicate(true)
	v[&"hp"] = 1
	v[&"drop_table"] = [drop_entry]
	var strong: Dictionary = (chapter["playerUnits"][0] as Dictionary).duplicate(true)
	strong[&"hp"] = 99
	(strong[&"stats"] as Dictionary)[&"hp"] = 99
	var c_loot: Array = []
	seed(101)
	Resolver.resolve_attack(v, strong, _mk_grid(chapter), _mk_ctx(1, c_loot))
	# 无论本 seed 下反击是否命中致死，断言只有命中致死才掉落：
	# （seed 固定 → 行为确定；先验证当前 seed 反击致死确实发生）
	if bool(strong.get(&"isDead", false)) or not bool(v.get(&"isDead", false)):
		# 敌未死于反击 → 换断言方向会造成 flaky；直接报告 seed 行为并要求掉落为空一致性
		_expect(c_loot.size() == (1 if bool(v.get(&"isDead", false)) else 0),
			"反击路径掷落与死亡一致（isDead=%s loot=%s）" % [str(v.get(&"isDead", false)), str(c_loot)])
	else:
		_expect(c_loot.size() == 1, "反击致死掷落 1 件（got %s）" % str(c_loot))

	# --- 技能致死：fireball ---
	var sv: Dictionary = pu["with_table"].duplicate(true)
	sv[&"hp"] = 1
	sv[&"drop_table"] = [drop_entry]
	var caster: Dictionary = (chapter["playerUnits"][0] as Dictionary).duplicate(true)
	caster[&"mp"] = 99
	(caster[&"stats"] as Dictionary)[&"mag"] = 30
	var s_loot: Array = []
	seed(202)
	var so := Resolver.resolve_skill(caster, [sv], &"fireball", _mk_ctx(2, s_loot))
	if (so[&"deaths"] as Array).is_empty():
		failures.append("seed 202 fireball 未致死（前提破坏，需换 seed 或加 mag）")
	else:
		_expect(s_loot.size() == 1 and (s_loot[0] as Dictionary).get("id", &"") == &"bomb",
			"技能致死掷落（got %s）" % str(s_loot))

	# --- 投掷物致死：bomb ---
	var iv: Dictionary = pu["with_table"].duplicate(true)
	iv[&"hp"] = 1
	iv[&"drop_table"] = [drop_entry]
	var user: Dictionary = (chapter["playerUnits"][0] as Dictionary).duplicate(true)
	user[&"items"] = [{ "id": &"bomb", "uses": 1 }]
	var i_loot: Array = []
	seed(303)
	var io := Resolver.resolve_item(user, [iv], { "id": &"bomb", "uses": 1 }, _mk_ctx(3, i_loot))
	if (io[&"deaths"] as Array).is_empty():
		failures.append("seed 303 bomb 未致死（前提破坏）")
	else:
		_expect(i_loot.size() == 1, "投掷物致死掷落（got %s）" % str(i_loot))


# ------------------------------------------------------------------
# 8. runner 真实入口：inline 场景 + 脚本攻击
# ------------------------------------------------------------------
func _test_runner_inline_drop() -> void:
	var mk := func() -> Dictionary:
		return {
			"version": 1, "id": "drop_smoke", "seed": 17,
			"inline": {
				"rows": ["....", "....", "....", "...."],
				"playerUnits": [{ "class": "swordsman", "name": "甲", "x": 1, "y": 1 }],
				"enemyUnits": [{
					"class": "berserker", "name": "乙", "x": 2, "y": 1,
					"drop_table": [{ "id": "hpPotion", "count": 1, "weight": 100 }],
				}],
			},
			"overrides": { "u_e_0": { "hp": 1 } },
			"factions": {
				"player": { "mode": "script", "script": [{ "unit": "u_p_0", "attack": "u_e_0" }] },
				"enemy": { "mode": "ai" },
			},
		}
	var res1 := ScenarioLoader.load_from_dict(mk.call())
	if not bool(res1.get("ok", false)):
		failures.append("runner 场景装载失败：%s" % str(res1.get("error", "")))
		return
	var r1 := Runner.run(res1["scenario"])
	var pending1: Array = res1["scenario"]["chapter"].get("pending_loot", [])
	var outcome1: Dictionary = r1.get("result", {}).get("outcome", {})
	if not bool(r1.get("ok", false)) or outcome1.get("winner", &"") != &"player":
		failures.append("runner 对局未正常结束/玩家未胜：%s" % str(outcome1))
		return
	_expect(pending1.size() == 1 and (pending1[0] as Dictionary).get("id", &"") == &"hpPotion",
		"runner 击杀掉落入 chapter.pending_loot（got %s）" % str(pending1))
	# 同 seed 重放一致 + chapter 复用重置（pending 不跨 run 污染）
	var res2 := ScenarioLoader.load_from_dict(mk.call())
	Runner.run(res2["scenario"])
	var pending2: Array = res2["scenario"]["chapter"].get("pending_loot", [])
	_expect(JSON.stringify(_str_loot(pending1)) == JSON.stringify(_str_loot(pending2)),
		"runner 同 seed 重放掉落一致")
	# 实例复用：同一 scenario 字典再跑 → 开局 pending 被重置（敌方单位带着上局
	# isDead，不会产生新掉落），断言无跨局残留污染
	Runner.run(res1["scenario"])
	var pending1b: Array = res1["scenario"]["chapter"].get("pending_loot", [])
	_expect(pending1b.is_empty(), "runner 复用重置 pending，无跨局残留（got %s）" % str(pending1b))


# ------------------------------------------------------------------
# 9. campaign 集成：击杀掉落随胜利入账
# ------------------------------------------------------------------
func _mk_session() -> SessionScript:
	var session := SessionScript.new()
	session.base_dir = _cur_dir
	_sessions.append(session)
	return session


func _test_campaign_win_drops() -> void:
	_begin("campaign_win")
	var session := _mk_session()
	var created := session.create_profile("drop_tester")
	if not bool(created.get("ok", false)):
		failures.append("建档失败：%s" % str(created.get("error", "")))
		return
	var prepared := session.prepare_battle(&"plains_skirmish")
	if not bool(prepared.get("ok", false)):
		failures.append("出征失败：%s" % str(prepared.get("error", "")))
		return
	var token: String = prepared["token"]
	var chapter: Dictionary = prepared["chapter"]
	# 锁定关卡表掷出（W2 通道）与击杀流（battle.gd 同款种子公式）
	session._attempt["loot_seed"] = 42
	var drop_loot: Array = []
	chapter["pending_loot"] = drop_loot
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("plains_skirmish|%s" % token)
	var ctx := { "rng": rng, "loot": drop_loot, "rolled": {} }
	# 击杀血斧（表 hpPotion60/shuriken40）
	var victim: Dictionary = {}
	for u in chapter["enemyUnits"]:
		if String((u as Dictionary).get(&"name", "")) == "血斧":
			victim = u
			break
	if victim.is_empty():
		failures.append("campaign 章节缺少血斧（drop_table 未随 loader 透传）")
		return
	victim[&"hp"] = 1
	var attacker: Dictionary = chapter["playerUnits"][0]
	# 基线：出征（deploy 会 FIFO 领用库存）之后、击杀结算之前的 hpPotion 实例数
	var hp_after_prepare := 0
	for inst in session.get_profile().get("inventory", []):
		if String((inst as Dictionary).get("id", "")) == "hpPotion":
			hp_after_prepare += 1
	seed(606)
	var outcome := Resolver.resolve_attack(attacker, victim, _mk_grid(chapter), ctx)
	if (outcome[&"deaths"] as Array).is_empty():
		failures.append("seed 606 campaign 击杀未致死（前提破坏）")
		return
	var receipt := session.settle_battle(token, &"win", chapter)
	if not bool(receipt.get("ok", false)):
		failures.append("结算失败：%s" % str(receipt.get("error", "")))
		return
	# 期望 = 关卡表掷出（roll_loot 同 seed 对拍）+ 击杀掉落，按 W2 合并语义（同 id 累加、首现序）
	var expect_rng := RandomNumberGenerator.new()
	expect_rng.seed = 42
	var rewards := CampaignConfig.rewards_for(&"plains_skirmish", true)
	var rolled: Array = []
	for e in CampaignConfig.roll_loot(rewards.get("loot_table", []), int(rewards.get("loot_rolls", 0)), expect_rng):
		(e as Dictionary).erase("name")
		(e as Dictionary).erase("uses")
		rolled.append(e)
	var merged: Array = []
	for src in [rolled, _str_loot(drop_loot)]:
		for e in src:
			var ed: Dictionary = e
			var hit := false
			for m in merged:
				if String((m as Dictionary)["id"]) == String(ed["id"]):
					(m as Dictionary)["count"] = int((m as Dictionary)["count"]) + int(ed["count"])
					hit = true
					break
			if not hit:
				merged.append({ "id": String(ed["id"]), "count": int(ed["count"]) })
	var got_loot: Array = []
	for e in receipt.get("loot", []):
		var ed: Dictionary = e
		got_loot.append({ "id": String(ed.get("id", &"")), "count": int(ed.get("count", 0)) })
	_expect(JSON.stringify(got_loot) == JSON.stringify(merged),
		"campaign receipt.loot = 关卡表+击杀掉落精确合并（got %s want %s）" % [str(got_loot), str(merged)])
	_expect(receipt.has("level_ups"), "receipt 保留 level_ups 键")
	_expect(receipt.has("items") and receipt.has("items_awarded"), "receipt 保留 items/items_awarded")
	# 掉落入库且满 uses 落盘（inventory 为 [{id,uses}] 实例数组）
	var inv_mem: Array = session.get_profile().get("inventory", [])
	var reload := SessionScript.new()
	reload.base_dir = _cur_dir
	var pid := String(session.get_profile().get("id", ""))
	var loaded := reload.load_profile(pid)
	if not bool(loaded.get("ok", false)):
		failures.append("重载失败：%s" % str(loaded.get("error", "")))
		return
	var inv_reload: Array = reload.get_profile().get("inventory", [])
	var want_hp := 0
	for e in merged:
		if String(e["id"]) == "hpPotion":
			want_hp = int(e["count"])
	# 首胜固定奖也含 1 件 hpPotion → 期望 = 固定奖 + 掉落里的 hpPotion 数
	var fixed_hp := 0
	var rew := CampaignConfig.rewards_for(&"plains_skirmish", true)
	for it in rew.get("items", []):
		if String((it as Dictionary).get("id", &"")) == "hpPotion":
			fixed_hp = int((it as Dictionary).get("count", 0))
	var expect_hp := fixed_hp + want_hp
	var hp_reload := 0
	var hp_mem := 0
	for inst in inv_reload:
		if String((inst as Dictionary).get("id", "")) == "hpPotion":
			hp_reload += 1
	for inst in inv_mem:
		if String((inst as Dictionary).get("id", "")) == "hpPotion":
			hp_mem += 1
	_expect(hp_reload >= hp_after_prepare + expect_hp,
		"重载后 hpPotion ≥ 基线+固定奖+掉落（%d，基线 %d + 期望 %d；deploy/回收可再增）" % [hp_reload, hp_after_prepare, expect_hp])
	_expect(hp_mem == hp_reload, "内存与磁盘库存一致（%d vs %d）" % [hp_mem, hp_reload])
	if hp_reload > 0:
		var full_uses := true
		for inst in inv_reload:
			var inst_d: Dictionary = inst
			if String(inst_d.get("id", "")) == "hpPotion" and int(inst_d.get("uses", 0)) <= 0:
				full_uses = false
		_expect(full_uses, "掉落实例满 uses 入库")


func _begin(tag: String) -> SessionScript:
	var dir := ROOT.path_join(tag)
	_remove_recursive(dir)
	_cur_dir = dir
	return _mk_session()


func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return
	if dir.dir_exists(path.get_file()):
		var target := DirAccess.open(path)
		if target != null:
			for f in target.get_files():
				target.remove(f)
			for d in target.get_directories():
				_remove_recursive(path.path_join(d))
		dir.remove(path.get_file())
