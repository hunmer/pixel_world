## campaign_contract.gd — 冒险模式数据层契约测试
##
## 覆盖：配置装载/校验、档案创建/列表/加载、出征部署（全员出征/补位/防重/解锁/
## 补给/落盘失败取消）、胜/败/弃结算（经验导入/复活/回收/奖励/幂等/原子性、
## 胜利升级差分 level_ups 按 id 对位快照：from/to/stat_deltas、失败撤退不产生、
## 落盘失败不发布、幂等重放回带）、
## 快照回滚、存档往返、JSON 损坏与结构损坏回退、新版本拒绝（不回退备份）、
## 损坏档删除、重命名/删除、手动保存、中断标记、断档解锁、落盘故障重试、
## 备份保护自愈（损坏主档+合法备份下落盘失败仍有好档）、最近使用标记、目录隔离。
## 临时目录：user://campaign_contract_tmp/<tag>（每个测试独立子目录，互不污染）。

extends SceneTree

const SessionScript := preload("res://scripts/campaign/campaign_session.gd")
const CampaignConfigScript := preload("res://scripts/campaign/campaign_config.gd")
const CodecScript := preload("res://scripts/campaign/campaign_profile_codec.gd")
const StoreScript := preload("res://scripts/campaign/campaign_profile_store.gd")
const RosterScript := preload("res://scripts/campaign/campaign_roster.gd")
const BattlefieldLoaderScript := preload("res://scripts/core/battlefield_loader.gd")
const ResolverScript := preload("res://scripts/battle/battle_action_resolver.gd")

const ROOT := "user://campaign_contract_tmp"

const L0 := "plains_skirmish"
const L1 := "river_crossing"
const L2 := "ambush_reinforce"
const L3 := "mountain_pass"
const L4 := "last_stand"
const L5 := "arena_1v1"

var failures: Array[String] = []
var _sessions: Array = []
var _cur_dir := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_root()
	_test_config()
	_test_config_validation()
	_test_config_loot()
	_test_create_and_profile()
	_test_list_profiles()
	_test_prepare()
	_test_deploy_full_roster_error()
	_test_settle_win_first()
	_test_settle_win_repeat_and_idempotent()
	_test_settle_win_level_ups()
	_test_lose_and_abandon()
	_test_unlock_progression_and_full_deploy()
	_test_isolation()
	_test_roundtrip()
	_test_corruption_fallback()
	_test_structural_corruption_and_newer_refusal()
	_test_version_validation()
	_test_rename_delete()
	_test_save_current_during_battle()
	_test_interrupted_marker()
	_test_persist_failure()
	_test_bak_heal()
	_test_recent_marker()
	_test_configure_store_dir()
	_test_shop_buy()
	_test_shop_limit_cycle()
	_test_victory_loot()
	_test_victory_loot_pending()
	_test_victory_loot_persist_retry()
	_cleanup_root()
	for raw_session in _sessions:
		var node := raw_session as Node
		if node != null and is_instance_valid(node):
			node.free()
	if failures.is_empty():
		print("CAMPAIGN_CONTRACT_OK")
		quit(0)
	else:
		for f in failures:
			print("FAIL: " + f)
		print("CAMPAIGN_CONTRACT_FAIL (%d)" % failures.size())
		quit(1)


# ============================================================
# 配置
# ============================================================

func _test_config() -> void:
	var loaded: Dictionary = CampaignConfigScript.load_config(true)
	_expect(loaded.ok, "config: load_config 应成功，实际 %s" % str(loaded.error))
	if not loaded.ok:
		return
	var levels: Array = loaded.config.levels
	_expect(levels.size() == 6, "config: 应有 6 关，实际 %d" % levels.size())
	_expect(str(levels[0].id) == L0, "config: 第一关应是 %s" % L0)
	_expect(str(levels[5].id) == L5, "config: 最后一关应是 %s" % L5)
	var ids := {}
	for level in levels:
		ids[str(level.id)] = true
	_expect(ids.size() == 6, "config: 关卡 id 应唯一")
	var first: Dictionary = CampaignConfigScript.rewards_for(L0, true)
	_expect(int(first.gold) == 200, "config: 首胜金币应为 200，实际 %d" % int(first.gold))
	_expect(first.items.size() == 1 and String(first.items[0].id) == "hpPotion" and int(first.items[0].count) == 1,
		"config: 首胜物品应为 1×hpPotion")
	var repeat: Dictionary = CampaignConfigScript.rewards_for(L0, false)
	_expect(int(repeat.gold) == 50 and repeat.items.is_empty(), "config: 重复胜奖励应为 50 金币无物品")
	_expect(CampaignConfigScript.level_index(L2) == 2, "config: ambush_reinforce 序号应为 2")
	var first_loot: Dictionary = CampaignConfigScript.rewards_for(L0, true)
	_expect(first_loot.loot_table.size() == 2 and int(first_loot.loot_rolls) == 1,
		"config: plains 首胜掉落表应 2 条且掷 1 次")
	var no_table: Dictionary = CampaignConfigScript.rewards_for(L3, true)
	_expect(no_table.loot_table.is_empty() and int(no_table.loot_rolls) == 0,
		"config: 无表关（mountain_pass 走全局）掉落应精确为空")


func _test_config_validation() -> void:
	var good := {
		"version": 1,
		"levels": [{"id": "x1", "name": "X", "source": "res://data/battlefields/plains_skirmish.json"}],
		"rewards": {"first_clear": {"gold": 10, "items": []}, "repeat": {"gold": 5, "items": []}},
	}
	_expect(CampaignConfigScript.parse_config(good).ok, "config_validation: 合法配置应通过")
	var cases := [
		{"d": {"version": 2}, "why": "版本不支持"},
		{"d": {"version": 1, "levels": []}, "why": "levels 为空"},
		{"d": {"version": 1, "levels": [
			{"id": "a", "name": "A", "source": "res://data/battlefields/plains_skirmish.json"},
			{"id": "a", "name": "A2", "source": "res://data/battlefields/arena_1v1.json"}],
		"rewards": {"first_clear": {"gold": 1, "items": []}, "repeat": {"gold": 1, "items": []}}}, "why": "id 重复"},
		{"d": {"version": 1, "levels": [{"id": "a", "name": "A", "source": "res://data/battlefields/no_such.json"}],
			"rewards": {"first_clear": {"gold": 1, "items": []}, "repeat": {"gold": 1, "items": []}}}, "why": "source 不存在"},
		{"d": {"version": 1, "levels": [{"id": "a", "name": "A", "source": "res://data/battlefields/plains_skirmish.json"}],
			"rewards": {"first_clear": {"gold": 1, "items": [{"id": "no_such_item", "count": 1}]}, "repeat": {"gold": 1, "items": []}}}, "why": "未知奖励物品"},
		{"d": {"version": 1, "levels": [{"id": "a", "name": "A", "source": "res://data/battlefields/plains_skirmish.json"}],
			"rewards": {"first_clear": {"gold": -1, "items": []}, "repeat": {"gold": 1, "items": []}}}, "why": "负金币"},
	]
	for case in cases:
		var res: Dictionary = CampaignConfigScript.parse_config(case.d)
		_expect(not res.ok, "config_validation: %s 应被拒绝" % case.why)


# ============================================================
# 关卡掉落表（W1）：归一化/透传 + roll_loot 纯函数契约 + 非法配置拒绝
# ============================================================

func _test_config_loot() -> void:
	# —— 归一化与透传 ——
	var loaded: Dictionary = CampaignConfigScript.load_config(true)
	_expect(loaded.ok, "loot: 配置应装载成功")
	var plains: Dictionary = CampaignConfigScript.rewards_for(L0, true)
	_expect(int(plains.gold) == 200 and plains.items.size() == 1,
		"loot: 有表关固定奖励应保持（200 金 + 1×hpPotion）")
	_expect(plains.loot_table.size() == 2 and int(plains.loot_rolls) == 1,
		"loot: plains 首胜应 2 条表 1 次掷骰")
	_expect(String(plains.loot_table[0].id) == "shuriken" and int(plains.loot_table[0].count) == 1,
		"loot: 表条目应归一化保留 id/count")
	var ambush: Dictionary = CampaignConfigScript.rewards_for(L2, true)
	_expect(ambush.loot_table.size() == 3 and int(ambush.loot_rolls) == 1,
		"loot: 有表未设 loot_rolls 应默认 1 次")
	var mountain: Dictionary = CampaignConfigScript.rewards_for(L3, true)
	_expect(int(mountain.gold) == 200 and mountain.loot_table.is_empty() and int(mountain.loot_rolls) == 0,
		"loot: 无表关固定奖励照旧且掉落精确为空")

	# —— roll_loot 纯函数 ——
	var table: Array = [
		{"id": "shuriken", "count": 1, "weight": 60.0},
		{"id": "bomb", "count": 1, "weight": 40.0},
	]
	# 固定 seed 重放一致（掉落版确定性契约）
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 42
	var roll_a: Array = CampaignConfigScript.roll_loot(table, 1, rng_a)
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 42
	var roll_b: Array = CampaignConfigScript.roll_loot(table, 1, rng_b)
	_expect(JSON.stringify(roll_a) == JSON.stringify(roll_b) and not roll_a.is_empty(),
		"loot: 同 seed 同表同次数应重放一致")
	# 单条表：任意 seed 下结果唯一（固定 seed 精确结果）
	var solo: Array = [{"id": "hpPotion", "count": 2, "weight": 100.0}]
	var rng_c := RandomNumberGenerator.new()
	rng_c.seed = 7
	var roll_solo: Array = CampaignConfigScript.roll_loot(solo, 3, rng_c)
	_expect(roll_solo.size() == 1 and String(roll_solo[0].id) == "hpPotion" and int(roll_solo[0].count) == 6,
		"loot: 单条表 3 次应精确合并为 1 条 count=6")
	# 多次抽样总量不变量
	var rng_d := RandomNumberGenerator.new()
	rng_d.seed = 99
	var roll_many: Array = CampaignConfigScript.roll_loot(table, 8, rng_d)
	var total_count := 0
	for e: Dictionary in roll_many:
		total_count += int(e.count)
	_expect(total_count == 8 and roll_many.size() <= 2,
		"loot: 8 次单 count 抽样总量应恰为 8 且按 id 合并")
	# 0 次 / 空表：完全不触碰 rng 状态
	var rng_e := RandomNumberGenerator.new()
	rng_e.seed = 5
	var state_before: int = rng_e.state
	_expect(CampaignConfigScript.roll_loot(table, 0, rng_e).is_empty(), "loot: 0 次应返回空")
	_expect(CampaignConfigScript.roll_loot([], 3, rng_e).is_empty(), "loot: 空表应返回空")
	_expect(rng_e.state == state_before, "loot: 空表/0 次不得消耗 rng 状态")
	# 不改输入
	var table_snapshot := JSON.stringify(table)
	CampaignConfigScript.roll_loot(table, 4, rng_e)
	_expect(JSON.stringify(table) == table_snapshot, "loot: roll_loot 不得修改入参表")

	# —— 非法配置拒绝 ——
	var mk := func(loot_branch: Dictionary) -> Dictionary:
		return {
			"version": 1,
			"levels": [{"id": "a", "name": "A", "source": "res://data/battlefields/plains_skirmish.json"}],
			"rewards": {
				"first_clear": loot_branch,
				"repeat": {"gold": 1, "items": []},
			},
		}
	var bad_cases := [
		{"d": mk.call({"gold": 1, "items": [], "loot_table": [{"id": "no_such_item", "count": 1, "weight": 1}]}), "why": "掉落未知物品"},
		{"d": mk.call({"gold": 1, "items": [], "loot_table": [{"id": "hpPotion", "count": 0, "weight": 1}]}), "why": "掉落 count<1"},
		{"d": mk.call({"gold": 1, "items": [], "loot_table": [{"id": "hpPotion", "count": 1.5, "weight": 1}]}), "why": "掉落 count 非整数"},
		{"d": mk.call({"gold": 1, "items": [], "loot_table": [{"id": "hpPotion", "count": 1, "weight": 0}]}), "why": "掉落 weight=0"},
		{"d": mk.call({"gold": 1, "items": [], "loot_table": [{"id": "hpPotion", "count": 1, "weight": -3.0}]}), "why": "掉落 weight 负数"},
		{"d": mk.call({"gold": 1, "items": [], "loot_table": [{"id": "hpPotion", "count": 1, "weight": "60"}]}), "why": "掉落 weight 字符串"},
		{"d": mk.call({"gold": 1, "items": [], "loot_table": [
			{"id": "hpPotion", "count": 1, "weight": 1}, {"id": "hpPotion", "count": 1, "weight": 1}]}), "why": "掉落 id 重复"},
		{"d": mk.call({"gold": 1, "items": [], "loot_table": [{"id": "hpPotion", "count": 1, "weight": 1}, "x"]}), "why": "掉落条目非对象"},
		{"d": mk.call({"gold": 1, "items": [], "loot_table": "x"}), "why": "loot_table 非数组"},
		{"d": mk.call({"gold": 1, "items": [], "loot_rolls": -1}), "why": "loot_rolls 负数"},
		{"d": mk.call({"gold": 1, "items": [], "loot_rolls": 1.5}), "why": "loot_rolls 非整数"},
	]
	for case in bad_cases:
		_expect(not CampaignConfigScript.parse_config(case.d).ok, "loot: %s 应被拒绝" % case.why)
	# 合法：无表但显式 loot_rolls 0
	var ok_no_table: Dictionary = CampaignConfigScript.parse_config(mk.call({"gold": 1, "items": [], "loot_rolls": 0}))
	_expect(ok_no_table.ok, "loot: 无表显式 rolls 0 应合法")


# ============================================================
# 档案创建与查询
# ============================================================

func _test_create_and_profile() -> void:
	var session := _begin("create")
	_expect(session.get_profile().is_empty(), "create: 未加载时 get_profile 应为空")
	for bad_name in ["", "   ", "a".repeat(33)]:
		var bad: Dictionary = session.create_profile(bad_name)
		_expect(not bad.ok, "create: 非法名 %s 应被拒绝" % str(bad_name).substr(0, 8))
	var created: Dictionary = session.create_profile("  罗兰小队 ")
	_expect(created.ok, "create: 创建应成功，实际 %s" % str(created.error))
	var profile: Dictionary = session.get_profile()
	_expect(not profile.is_empty(), "create: 创建后应有档案")
	_expect(str(profile.name) == "罗兰小队", "create: 名字应去首尾空白")
	_expect(int(profile.gold) == 0, "create: 初始金币应为 0")
	_expect(profile.roster.size() == 4, "create: 队伍应为首关 4 人，实际 %d" % profile.roster.size())
	_expect(profile.completed_levels.is_empty(), "create: 初始不应有通关记录")
	_expect(_count_items(profile.inventory, "hpPotion") == 4 and _count_items(profile.inventory, "mpPotion") == 4,
		"create: 初始库存应汇总首关随身物品 4×hp+4×mp，实际 %s" % _inv_str(profile.inventory))
	for i in profile.roster.size():
		_expect(profile.roster[i].items.is_empty(), "create: 档内单位 %d 不应随身携带" % i)
	_expect(str(profile.roster[0].id) == "r_0", "create: 单位 id 应重编为 r_0")
	_expect(int(profile.roster[0].hp) == int(profile.roster[0].stats.hp), "create: 单位应满血入库")


func _test_list_profiles() -> void:
	var session := _begin("list")
	session.create_profile("甲")
	session.create_profile("乙")
	var summaries: Array = session.list_profiles()
	_expect(summaries.size() == 2, "list: 应列出 2 个档案，实际 %d" % summaries.size())
	var names := {}
	for s in summaries:
		names[str(s.name)] = s
		_expect(bool(s.loadable), "list: %s 应可读" % str(s.name))
		_expect(int(s.gold) == 0 and int(s.completed_count) == 0, "list: 摘要字段应正确")
	_expect(names.size() == 2, "list: 两个名字都应出现")
	_expect(str(summaries[0].name) == "乙", "list: 应按 saved_at 降序")
	_expect(bool(summaries[0].get("is_recent", false)), "list: 最近创建的档案应带 is_recent")


# ============================================================
# 出征
# ============================================================

func _test_prepare() -> void:
	var session := _begin("prepare")
	var no_profile: Dictionary = session.prepare_battle(L0)
	_expect(not no_profile.ok, "prepare: 未加载档案应失败")
	session.create_profile("出征队")
	var locked: Dictionary = session.prepare_battle(L1)
	_expect(not locked.ok and str(locked.error).contains("解锁"), "prepare: 未解锁关卡应失败")
	var unknown: Dictionary = session.prepare_battle("no_such_level")
	_expect(not unknown.ok, "prepare: 未知关卡应失败")
	var probe: Dictionary = BattlefieldLoaderScript.load_battlefield("res://data/battlefields/plains_skirmish.json")
	var declared: Array = probe.chapter.playerUnits
	var prepared: Dictionary = session.prepare_battle(L0)
	_expect(prepared.ok, "prepare: 首关出征应成功，实际 %s" % str(prepared.error))
	if not prepared.ok:
		return
	_expect(str(prepared.level_id) == L0, "prepare: level_id 应回显")
	_expect(str(prepared.token).begins_with("t_"), "prepare: token 应生成")
	_expect(int(prepared.deployed_count) == 4, "prepare: 4 槽战场应全员部署 4 人")
	_expect(prepared.extra_ids.is_empty(), "prepare: 槽位足够时不应有补位单位")
	var chapter: Dictionary = prepared.chapter
	var units: Array = chapter.playerUnits
	_expect(units.size() == 4, "prepare: 应部署 4 人，实际 %d" % units.size())
	for i in units.size():
		_expect(str(units[i].position) == str(declared[i].position), "prepare: 单位 %d 应在声明槽位" % i)
		_expect(units[i].items.size() == 2, "prepare: 单位 %d 应自动补给 2 件" % i)
		_expect(int(units[i].hp) == int(units[i].stats.hp), "prepare: 出征单位应满血")
	var inv: Array = session.get_profile().inventory
	_expect(_count_items(inv, "hpPotion") == 0 and _count_items(inv, "mpPotion") == 0,
		"prepare: 全员补给后初始库存应发完，实际 %s" % _inv_str(inv))
	var again: Dictionary = session.prepare_battle(L0)
	_expect(not again.ok and str(again.error).contains("出征"), "prepare: 挂起时重复出征应失败")
	session.settle_battle(str(prepared.token), &"abandon", {})
	var re: Dictionary = session.prepare_battle(L0)
	_expect(re.ok, "prepare: 结算后应可再次出征，实际 %s" % str(re.error))


## 全员部署的空格不足错误路径（直接调 Roster.deploy，构造无空格小图）。
func _test_deploy_full_roster_error() -> void:
	var session := _begin("deploy_err")
	session.create_profile("满员队")
	var profile: Dictionary = session.get_profile()
	var chapter := {
		"map": [["water", "water"], ["water", "water"]],
		"width": 2,
		"height": 2,
		"playerUnits": [{"position": Vector2i(0, 0)}],
		"enemyUnits": [],
	}
	var inventory: Array = profile.inventory.duplicate(true)
	var res: Dictionary = RosterScript.deploy(chapter, profile.roster, inventory, [])
	_expect(not res.ok, "deploy_error: 无空格应失败")
	_expect(str(res.error).contains("空格"), "deploy_error: 错误应说明空格不足，实际 %s" % str(res.error))
	_expect(_count_items(inventory, "hpPotion") == 4, "deploy_error: 失败时库存不应被扣（未发补给）")


# ============================================================
# 胜利结算
# ============================================================

func _test_settle_win_first() -> void:
	var session := _begin("win_first")
	session.create_profile("胜利队")
	var prepared: Dictionary = session.prepare_battle(L0)
	_expect(prepared.ok, "win: 出征应成功")
	var chapter: Dictionary = prepared.chapter
	var units: Array = chapter.playerUnits
	units[0]["hp"] = maxi(1, int(units[0].hp) - 5)
	units[0]["exp"] = int(units[0].exp) + 30
	units[0]["level"] = int(units[0].level) + 1
	units[0].stats["str"] = int(units[0].stats.get("str", 0)) + 1
	units[1]["isDead"] = true
	units[1]["hasActed"] = true
	var r2_items: Array = units[2].items
	r2_items[0]["uses"] = 1
	r2_items[1]["uses"] = 0
	units[3]["buffs"] = [{"stat": &"str", "value": 2, "turns": 3, "label": "狂暴"}]
	units[3]["skillCooldowns"] = {&"heal": 2}
	var token := str(prepared.token)
	var bad_result: Dictionary = session.settle_battle(token, "draw", chapter)
	_expect(not bad_result.ok, "win: 非法结果应失败")
	var bad_token: Dictionary = session.settle_battle("t_bogus", &"win", chapter)
	_expect(not bad_token.ok and str(bad_token.error).contains("令牌"), "win: 错 token 应失败")
	var empty_ch: Dictionary = session.settle_battle(token, &"win", {})
	_expect(not empty_ch.ok, "win: 空终局战场应失败")
	var still: Dictionary = session.prepare_battle(L0)
	_expect(not still.ok, "win: 校验失败后 attempt 应仍在（不能重复出征）")
	var receipt: Dictionary = session.settle_battle(token, &"win", chapter)
	_expect(receipt.ok, "win: 胜利结算应成功，实际 %s" % str(receipt.error))
	if not receipt.ok:
		return
	_expect(bool(receipt.first_clear), "win: 应为首胜")
	_expect(int(receipt.gold) == 200 and int(receipt.gold_awarded) == 200, "win: 奖励金币应为 200")
	_expect(receipt.items.size() == 1 and String(receipt.items[0].id) == "hpPotion" and int(receipt.items[0].count) == 1,
		"win: 奖励物品应为 1×hpPotion")
	_expect(int(receipt.gold_after) == 200 and int(receipt.gold_before) == 0, "win: 金币入账应正确")
	_expect(int(receipt.items_recovered) == 7, "win: 应回收 7 件（4hp+3mp），实际 %d" % int(receipt.items_recovered))
	var level_ups: Array = receipt.level_ups
	_expect(level_ups.size() == 1 and String(level_ups[0].id) == "r_0"
		and int(level_ups[0].from_level) == int(units[0].level) - 1
		and int(level_ups[0].to_level) == int(units[0].level),
		"win: 升级差分应按 id 记 r_0 from→to")
	var win_deltas: Dictionary = level_ups[0].stat_deltas if level_ups.size() == 1 else {}
	_expect(int(win_deltas.get("str", 0)) == 1 and win_deltas.size() == 1,
		"win: stat_deltas 应恰为 str+1，实际 %s" % str(win_deltas))
	var profile: Dictionary = session.get_profile()
	_expect(int(profile.gold) == 200, "win: 档案金币应为 200")
	_expect(profile.completed_levels.has(L0), "win: 应记录通关")
	var roster: Array = profile.roster
	_expect(int(roster[0].exp) == int(units[0].exp) and int(roster[0].level) == int(units[0].level),
		"win: r_0 经验与等级应保留")
	_expect(int(roster[0].stats.get("str", -99)) == int(units[0].stats.get("str", -98)),
		"win: r_0 属性成长应保留")
	for i in roster.size():
		_expect(int(roster[i].hp) == int(roster[i].stats.hp) and int(roster[i].mp) == int(roster[i].stats.mp),
			"win: 单位 %d 应满血蓝" % i)
		_expect(not bool(roster[i].isDead), "win: 单位 %d 应复活" % i)
		_expect(roster[i].buffs.is_empty() and (roster[i].skillCooldowns as Dictionary).is_empty(),
			"win: 单位 %d 应清临时态" % i)
		_expect(roster[i].items.is_empty(), "win: 档内单位不应随身携带")
	var inv: Array = profile.inventory
	_expect(_count_items(inv, "hpPotion") == 5 and _count_items(inv, "mpPotion") == 3,
		"win: 库存应 5×hp+3mp（回收 4hp+3mp+首胜奖 1hp），实际 %s" % _inv_str(inv))
	var has_reward := false
	for e in inv:
		if String(e.id) == "hpPotion" and int(e.uses) == 3:
			has_reward = true
	_expect(has_reward, "win: 奖励 hpPotion 应为满充 3")
	var last: Dictionary = session.get_last_result()
	_expect(last.get("ok", false) and str(last.result) == "win", "win: get_last_result 应返回胜利结果")
	_expect((last.level_ups as Array).size() == 1, "win: last_result 应带 level_ups")
	var replay: Dictionary = session.settle_battle(token, &"win", chapter)
	_expect(replay.ok and bool(replay.already_settled), "win: 重复结算应幂等回显")
	_expect((replay.level_ups as Array).size() == 1, "win: 幂等重放应回带 level_ups")
	_expect(int(session.get_profile().gold) == 200, "win: 重复结算不应重复发奖")
	session.clear_last_result()
	_expect(session.get_last_result().is_empty(), "win: clear_last_result 应清空")
	var fresh := _mk_session()
	var loaded: Dictionary = fresh.load_profile(str(profile.id))
	_expect(loaded.ok, "win: 重载档案应成功")
	var disk_profile: Dictionary = fresh.get_profile()
	_expect(int(disk_profile.gold) == 200 and disk_profile.completed_levels.has(L0), "win: 磁盘应有通关与金币")
	_expect(int(disk_profile.roster[0].level) == int(units[0].level), "win: 磁盘队伍应保留升级")


func _test_settle_win_repeat_and_idempotent() -> void:
	var session := _begin("repeat")
	session.create_profile("连胜队")
	_win_once(session, L0)
	var prepared: Dictionary = session.prepare_battle(L0)
	_expect(prepared.ok, "repeat: 重打出征应成功")
	var receipt: Dictionary = session.settle_battle(str(prepared.token), "win", prepared.chapter)
	_expect(receipt.ok, "repeat: 重复胜利应成功")
	_expect(not bool(receipt.first_clear), "repeat: 非首胜")
	_expect(int(receipt.gold) == 50, "repeat: 重复奖励应为 50")
	_expect(int(session.get_profile().gold) == 250, "repeat: 金币累计应为 250")
	_expect(receipt.items.is_empty(), "repeat: 重复胜利无物品奖励")
	_expect((receipt.level_ups as Array).is_empty(), "repeat: 无升级时 level_ups 应为空数组")


## 胜利升级差分专项：Lv N→N+1 的 settle，receipt.level_ups 按 id 含
## from/to_level 与 stat_deltas（stats 上限差）；只涨经验未升级不列；
## 队伍等级/经验与磁盘读档一致；同 token 幂等重放回带同一差分。
func _test_settle_win_level_ups() -> void:
	var session := _begin("level_ups")
	session.create_profile("成长队")
	var prepared: Dictionary = session.prepare_battle(L0)
	_expect(prepared.ok, "level_ups: 出征应成功")
	if not prepared.ok:
		return
	var chapter: Dictionary = prepared.chapter
	var units: Array = chapter.playerUnits
	var from_level := int(units[0].level)
	var to_level := from_level + 1
	units[0]["level"] = to_level
	units[0]["exp"] = 40
	units[0].stats["str"] = int(units[0].stats.get("str", 0)) + 1
	units[0].stats["spd"] = int(units[0].stats.get("spd", 0)) + 1
	units[1]["exp"] = int(units[1].exp) + 20
	var token := str(prepared.token)
	var receipt: Dictionary = session.settle_battle(token, &"win", chapter)
	_expect(receipt.ok, "level_ups: 胜利结算应成功，实际 %s" % str(receipt.error))
	if not receipt.ok:
		return
	_expect(receipt.has("level_ups"), "level_ups: 胜利 receipt 应带 level_ups 键")
	var level_ups: Array = receipt.level_ups
	_expect(level_ups.size() == 1, "level_ups: 只涨经验的 r_1 不应列入，实际 %d 条" % level_ups.size())
	if level_ups.size() == 1:
		var entry: Dictionary = level_ups[0]
		_expect(String(entry.id) == "r_0", "level_ups: 应按 id 记 r_0，实际 %s" % String(entry.id))
		_expect(int(entry.from_level) == from_level and int(entry.to_level) == to_level,
			"level_ups: from/to 应为 %d→%d，实际 %s→%s"
			% [from_level, to_level, str(entry.from_level), str(entry.to_level)])
		var deltas: Dictionary = entry.stat_deltas
		_expect(int(deltas.get("str", 0)) == 1 and int(deltas.get("spd", 0)) == 1 and deltas.size() == 2,
			"level_ups: stat_deltas 应恰为 str+1/spd+1，实际 %s" % str(deltas))
	var roster: Array = session.get_profile().roster
	_expect(int(roster[0].level) == to_level and int(roster[0].exp) == 40,
		"level_ups: 档案 r_0 应保留新等级与经验")
	_expect(int(roster[1].exp) == int(units[1].exp), "level_ups: r_1 经验应保留（未升级不丢经验）")
	var last: Dictionary = session.get_last_result()
	_expect((last.level_ups as Array).size() == 1, "level_ups: last_result 应带差分供 Hub 展示")
	var replay: Dictionary = session.settle_battle(token, &"win", chapter)
	_expect(replay.ok and bool(replay.already_settled) and (replay.level_ups as Array).size() == 1,
		"level_ups: 幂等重放应回带同一差分")
	var fresh := _mk_session()
	var loaded: Dictionary = fresh.load_profile(str(session.get_profile().id))
	_expect(loaded.ok, "level_ups: 读档应成功")
	var disk_roster: Array = fresh.get_profile().roster
	_expect(disk_roster.size() == roster.size() and int(disk_roster[0].level) == to_level
		and int(disk_roster[0].exp) == 40 and int(disk_roster[1].exp) == int(units[1].exp),
		"level_ups: 磁盘队伍等级/经验应与内存一致")


func _win_once(session: SessionScript, level_id: String) -> void:
	var prepared: Dictionary = session.prepare_battle(level_id)
	if not prepared.ok:
		failures.append("win_once(%s): 出征失败 %s" % [level_id, str(prepared.error)])
		return
	var receipt: Dictionary = session.settle_battle(str(prepared.token), &"win", prepared.chapter)
	if not receipt.ok:
		failures.append("win_once(%s): 结算失败 %s" % [level_id, str(receipt.error)])


# ============================================================
# 失败/放弃
# ============================================================

func _test_lose_and_abandon() -> void:
	for mode in ["lose", "abandon"]:
		var session := _begin(mode)
		session.create_profile("挫败队" + mode)
		var prepared: Dictionary = session.prepare_battle(L0)
		_expect(prepared.ok, "%s: 出征应成功" % mode)
		var chapter: Dictionary = prepared.chapter
		var units: Array = chapter.playerUnits
		units[0]["exp"] = int(units[0].exp) + 50
		units[0]["hp"] = maxi(1, int(units[0].hp) - 7)
		var receipt: Dictionary = session.settle_battle(str(prepared.token), StringName(mode), {})
		_expect(receipt.ok, "%s: 结算应成功，实际 %s" % [mode, str(receipt.error)])
		_expect(bool(receipt.restored), "%s: 应标记已恢复" % mode)
		_expect(not receipt.has("level_ups"), "%s: 失败/撤退 receipt 不应带 level_ups" % mode)
		_expect(int(session.get_profile().gold) == 0, "%s: 不应发奖" % mode)
		_expect(session.get_profile().completed_levels.is_empty(), "%s: 不应记录通关" % mode)
		var roster: Array = session.get_profile().roster
		_expect(int(roster[0].exp) == 0, "%s: 经验应回退到出征前" % mode)
		_expect(int(roster[0].hp) == int(roster[0].stats.hp), "%s: 应恢复满血" % mode)
		var inv: Array = session.get_profile().inventory
		_expect(_count_items(inv, "hpPotion") == 4 and _count_items(inv, "mpPotion") == 4,
			"%s: 库存应回退出征前，实际 %s" % [mode, _inv_str(inv)])
		_expect(str(session.get_last_result().result) == mode, "%s: last_result 应记录" % mode)
		_expect(not session.get_last_result().has("level_ups"), "%s: last_result 不应带 level_ups" % mode)
		var fresh := _mk_session()
		fresh.load_profile(str(session.get_profile().id))
		var fp: Dictionary = fresh.get_profile()
		_expect(int(fp.gold) == 0 and fp.completed_levels.is_empty(), "%s: 磁盘应同回退" % mode)


# ============================================================
# 解锁推进与全员部署
# ============================================================

func _test_unlock_progression_and_full_deploy() -> void:
	var session := _begin("unlock")
	var dir := session.base_dir
	session.create_profile("推进队")
	var levels: Array = session.list_levels()
	_expect(bool(levels[0].unlocked) and not bool(levels[1].unlocked), "unlock: 初始只有第一关解锁")
	_win_once(session, L0)
	_win_once(session, L1)
	levels = session.list_levels()
	_expect(bool(levels[2].unlocked) and not bool(levels[3].unlocked), "unlock: 通两关后第三关应解锁、第四关锁")
	_expect(bool(levels[0].unlocked) and bool(levels[0].completed), "unlock: 已通关关可重打")
	# 断档：手造 completed=[L0,L2]（L3 解锁当且仅当前关 L2 已通）
	var gap := _mk_session()
	gap.create_profile("断档队")
	var gap_id := str(gap.get_profile().id)
	gap.leave_profile()
	var store := StoreScript.new()
	store.base_dir = dir
	var loaded: Dictionary = store.load_profile_record(gap_id)
	_expect(loaded.ok, "gap: 原档应可读")
	var record: Dictionary = loaded.record
	record["completed_levels"] = [L0, L2]
	var saved: Dictionary = store.save_profile(record)
	_expect(saved.ok, "gap: 改档应成功")
	var reloaded: Dictionary = gap.load_profile(gap_id)
	_expect(reloaded.ok, "gap: 断档档应可载入")
	levels = gap.list_levels()
	_expect(bool(levels[1].unlocked) and bool(levels[2].unlocked) and bool(levels[2].completed),
		"gap: L1/L2 应解锁且 L2 已通")
	_expect(bool(levels[3].unlocked), "gap: L3 前关 L2 已通应解锁")
	# 全员部署：arena_1v1 只有 1 槽，其余 3 人应补位出征
	for level_id in [L2, L3, L4]:
		_win_once(gap, level_id)
	var arena: Dictionary = gap.prepare_battle(L5)
	_expect(arena.ok, "full_deploy: 竞技场应可出征，实际 %s" % str(arena.error))
	if arena.ok:
		_expect(int(arena.deployed_count) == 4, "full_deploy: 应全员出征 4 人，实际 %d" % int(arena.deployed_count))
		_expect(arena.sit_out_ids.is_empty(), "full_deploy: 不应有人留守")
		_expect(arena.extra_ids.size() == 3, "full_deploy: 应有 3 人补位，实际 %s" % str(arena.extra_ids))
		var solo: Array = arena.chapter.playerUnits
		_expect(solo.size() == 4, "full_deploy: 战场应有 4 人")
		_expect(String(solo[0].id) == "r_0", "full_deploy: r_0 应占声明槽位")
		var seen := {}
		for u in solo:
			var key := "%d,%d" % [int(u.position.x), int(u.position.y)]
			_expect(not seen.has(key), "full_deploy: 补位不应重叠 %s" % key)
			seen[key] = true
			_expect(u.items.size() == 2, "full_deploy: %s 应带默认补给" % String(u.id))
		var inv: Array = gap.get_profile().inventory
		_expect(_count_items(inv, "hpPotion") == 2 and _count_items(inv, "mpPotion") == 0,
			"full_deploy: 多轮出征后剩余库存应 2×hp+0×mp，实际 %s" % _inv_str(inv))


# ============================================================
# 档案隔离
# ============================================================

func _test_isolation() -> void:
	var session := _begin("isolation")
	var a: Dictionary = session.create_profile("甲队")
	_win_once(session, L0)
	_expect(int(session.get_profile().gold) == 200, "isolation: 甲队胜后应有 200 金币")
	session.create_profile("乙队")
	_expect(int(session.get_profile().gold) == 0, "isolation: 新档乙队金币应为 0")
	_expect(_count_items(session.get_profile().inventory, "hpPotion") == 4, "isolation: 乙队库存应为初始")
	var back_a: Dictionary = session.load_profile(str(a.profile_id))
	_expect(back_a.ok, "isolation: 甲队应可载回")
	_expect(int(session.get_profile().gold) == 200, "isolation: 载回甲队金币应保持")


# ============================================================
# 往返
# ============================================================

func _test_roundtrip() -> void:
	var session := _begin("roundtrip")
	session.create_profile("往返队")
	var before: Dictionary = session.get_profile()
	var saved: Dictionary = session.save_current()
	_expect(saved.ok, "roundtrip: 手动保存应成功")
	session.leave_profile()
	_expect(session.get_profile().is_empty(), "roundtrip: 退出后应空")
	var loaded: Dictionary = session.load_profile(str(before.id))
	_expect(loaded.ok, "roundtrip: 重载应成功，实际 %s" % str(loaded.error))
	var after: Dictionary = session.get_profile()
	_expect(str(after.name) == str(before.name), "roundtrip: 名字应一致")
	_expect(int(after.gold) == int(before.gold), "roundtrip: 金币应一致")
	_expect(_inv_str(after.inventory) == _inv_str(before.inventory), "roundtrip: 库存应一致")
	_expect(after.completed_levels.size() == before.completed_levels.size(), "roundtrip: 通关数应一致")
	var rb: Array = before.roster
	var ra: Array = after.roster
	_expect(rb.size() == ra.size(), "roundtrip: 队伍人数应一致")
	for i in ra.size():
		_expect(str(ra[i].id) == str(rb[i].id) and str(ra[i].name) == str(rb[i].name), "roundtrip: 单位 %d 身份应一致" % i)
		_expect(int(ra[i].level) == int(rb[i].level) and int(ra[i].exp) == int(rb[i].exp), "roundtrip: 单位 %d 成长应一致" % i)
		_expect(int(ra[i].stats.hp) == int(rb[i].stats.hp), "roundtrip: 单位 %d 属性应一致" % i)


# ============================================================
# JSON 损坏回退
# ============================================================

func _test_corruption_fallback() -> void:
	var session := _begin("corrupt")
	var dir := session.base_dir
	var created: Dictionary = session.create_profile("损坏队")
	var pid := str(created.profile_id)
	session.save_current()  # 第二次保存 → .bak 存在
	var store := StoreScript.new()
	store.base_dir = dir
	var file := ""
	for entry in store.list_records():
		if str(entry.get("record", {}).get("id", "")) == pid:
			file = str(entry.file)
	_expect(file != "", "corrupt: 应找到档案文件")
	# 主档 JSON 损坏 → 备份兜底 + notice
	_write_file(dir.path_join(file), "{{{ not json")
	session.leave_profile()
	var loaded: Dictionary = session.load_profile(pid)
	_expect(loaded.ok, "corrupt: 主档 JSON 损坏应回退备份，实际 %s" % str(loaded.error))
	_expect(str(loaded.notice).contains("备份"), "corrupt: 应提示从备份恢复，实际 %s" % str(loaded.notice))
	for s in session.list_profiles():
		if str(s.id) == pid:
			_expect(str(s.notice).contains("备份"), "corrupt: 列表应保留备份恢复提示")
	# 双损坏 → 失败 + 列表不可读 + 可按文件名 id 删除
	_write_file(dir.path_join(file), "{{{ not json")
	_write_file(dir.path_join(file) + ".bak", "{{{ not json")
	session.leave_profile()
	var broken: Dictionary = session.load_profile(pid)
	_expect(not broken.ok, "corrupt: 双损坏应失败")
	var listed_id := ""
	for s in session.list_profiles():
		if not bool(s.loadable):
			listed_id = str(s.id)
	_expect(listed_id != "", "corrupt: 损坏档案应以文件名 id 出现在列表")
	var del := session.delete_profile(listed_id)
	_expect(del.ok, "corrupt: 损坏档应可按列表 id 删除，实际 %s" % str(del.error))
	_expect(session.list_profiles().is_empty(), "corrupt: 删除后列表应为空")


# ============================================================
# 结构损坏 / 新版本拒绝
# ============================================================

func _test_structural_corruption_and_newer_refusal() -> void:
	# 主档合法 JSON 但结构损坏 → 回退验证后的备份
	var session := _begin("structural")
	var dir := session.base_dir
	var created: Dictionary = session.create_profile("结构队")
	var pid := str(created.profile_id)
	session.save_current()
	var store := StoreScript.new()
	store.base_dir = dir
	var loaded_raw: Dictionary = store.load_profile_record(pid)
	var broken_record: Dictionary = loaded_raw.record
	broken_record["roster"] = "not an array"
	var saved: Dictionary = store.save_profile(broken_record)
	_expect(saved.ok, "structural: 写入结构损坏主档应成功")
	session.leave_profile()
	var healed: Dictionary = session.load_profile(pid)
	_expect(healed.ok, "structural: 结构损坏主档应回退验证后的备份，实际 %s" % str(healed.error))
	_expect(str(healed.notice).contains("备份"), "structural: 应提示从备份恢复")
	# 列表与 load 同口径：结构坏主档+合法备份 → 列表同样 loadable=true + 备份提示
	for s in session.list_profiles():
		if str(s.id) == pid:
			_expect(bool(s.loadable) and str(s.notice).contains("备份"),
				"structural: 列表应与 load 同口径（loadable=true+备份提示），实际 loadable=%s notice=%s"
				% [str(s.loadable), str(s.notice)])
	# 主档新版本 → 直接拒绝，不回退旧备份
	var session2 := _mk_session()
	var created2: Dictionary = session2.create_profile("未来队")
	var pid2 := str(created2.profile_id)
	session2.save_current()
	var store2 := StoreScript.new()
	store2.base_dir = dir
	var raw2: Dictionary = store2.load_profile_record(pid2)
	var newer_record: Dictionary = raw2.record
	newer_record["version"] = 99
	store2.save_profile(newer_record)
	session2.leave_profile()
	var refused: Dictionary = session2.load_profile(pid2)
	_expect(not refused.ok and bool(refused.get("newer", false)), "newer: 新版本主档应被拒绝并标记 newer")
	_expect(session2.get_profile().is_empty(), "newer: 拒绝时不应加载任何档案")
	for s in session2.list_profiles():
		if str(s.id) == pid2:
			_expect(not bool(s.loadable) and str(s.notice).contains("更新版本"), "newer: 列表应提示版本过新")


# ============================================================
# 版本号严格校验
# ============================================================

## 版本必须是整数语义数字：拒绝分数（1.5 不得截断成 1）、字符串、布尔、缺失；
## 未来版本标 newer 拒绝（主档 future 不回退覆写由 load_profile 分层逻辑保证）。
func _test_version_validation() -> void:
	var session := _begin("version")
	session.create_profile("版本队")
	var store := StoreScript.new()
	store.base_dir = session.base_dir
	var loaded: Dictionary = store.load_profile_record(str(session.get_profile().id))
	_expect(loaded.ok, "version: 原档应可读")
	if not loaded.ok:
		return
	var base: Dictionary = loaded.record
	_expect(CodecScript.restore(base).ok, "version: 磁盘原档应通过")
	for case in [
		{"v": 1.5, "why": "分数"},
		{"v": "2", "why": "字符串"},
		{"v": true, "why": "布尔"},
	]:
		var rec: Dictionary = base.duplicate(true)
		rec["version"] = case.v
		var res: Dictionary = CodecScript.restore(rec)
		_expect(not res.ok and not bool(res.get("newer", false)),
			"version: %s版本应被拒绝，实际 ok=%s newer=%s" % [case.why, str(res.ok), str(res.get("newer", false))])
	var fut: Dictionary = base.duplicate(true)
	fut["version"] = 99
	var fut_res: Dictionary = CodecScript.restore(fut)
	_expect(not fut_res.ok and bool(fut_res.get("newer", false)), "version: 未来版本应标记 newer")
	# 主档 future + 合法 v1 备份 → load 拒绝且主档不被回退覆写
	var pid := str(session.get_profile().id)
	session.save_current()  # 第二次保存 → bak 存在
	store.save_profile(fut)  # 轮换：bak←v1，main←v99
	session.leave_profile()
	var refused: Dictionary = session.load_profile(pid)
	_expect(not refused.ok and bool(refused.get("newer", false)), "version: 主档 future 应拒绝且不回退备份")
	var layers: Dictionary = store.read_layers(pid)
	_expect(layers.main.has("record") and int(layers.main.record.get("version", 0)) == 99,
		"version: 拒绝后主档应保持 future 未被覆写")


# ============================================================
# 重命名 / 删除
# ============================================================

func _test_rename_delete() -> void:
	var session := _begin("rename")
	var a: Dictionary = session.create_profile("原名")
	var b: Dictionary = session.create_profile("旁观")
	# create 后当前档是 b（后创建）；显式切回 a，再测「当前档重命名」路径
	var switched: Dictionary = session.load_profile(str(a.profile_id))
	_expect(switched.ok, "rename: 前置：切回 a 应成功")
	var bad: Dictionary = session.rename_profile(str(a.profile_id), "")
	_expect(not bad.ok, "rename: 非法名应失败")
	var renamed: Dictionary = session.rename_profile(str(a.profile_id), "新名")
	_expect(renamed.ok, "rename: 当前档重命名应成功")
	_expect(str(session.get_profile().name) == "新名", "rename: 当前档内存名字应更新")
	# 他档路径：切到 b 后重命名 a
	session.load_profile(str(b.profile_id))
	var renamed_other: Dictionary = session.rename_profile(str(a.profile_id), "远处档")
	_expect(renamed_other.ok, "rename: 非当前档重命名应成功")
	var missing: Dictionary = session.rename_profile("p_no_such", "x")
	_expect(not missing.ok, "rename: 不存在档案应失败")
	session.leave_profile()
	var back: Dictionary = session.load_profile(str(a.profile_id))
	_expect(back.ok and str(session.get_profile().name) == "远处档", "rename: 磁盘名字应为最后一次重命名")
	var del_missing: Dictionary = session.delete_profile("p_no_such")
	_expect(not del_missing.ok, "delete: 不存在档案应失败")
	var del_other: Dictionary = session.delete_profile(str(b.profile_id))
	_expect(del_other.ok, "delete: 删除他档应成功")
	var del_current: Dictionary = session.delete_profile(str(session.get_profile().id))
	_expect(del_current.ok, "delete: 删除当前档应成功")
	_expect(session.get_profile().is_empty(), "delete: 删除当前档后内存应清空")


# ============================================================
# 手动保存边界
# ============================================================

func _test_save_current_during_battle() -> void:
	var session := _begin("save")
	session.create_profile("战中队")
	_expect(session.save_current().ok, "save: 闲暇时应可保存")
	var prepared: Dictionary = session.prepare_battle(L0)
	_expect(prepared.ok, "save: 出征应成功")
	var blocked: Dictionary = session.save_current()
	_expect(not blocked.ok, "save: 战斗挂起时手动保存应失败")


# ============================================================
# 中断标记
# ============================================================

func _test_interrupted_marker() -> void:
	var session := _begin("interrupted")
	var created: Dictionary = session.create_profile("中断队")
	var pid := str(created.profile_id)
	var prepared: Dictionary = session.prepare_battle(L0)
	_expect(prepared.ok, "interrupted: 出征应成功")
	var fresh := _mk_session()
	var loaded: Dictionary = fresh.load_profile(pid)
	_expect(loaded.ok, "interrupted: 带标记档案应可载入")
	_expect(str(loaded.notice).contains("中断"), "interrupted: 应有中断提示")
	_expect(str(loaded.interrupted_level_id) == L0, "interrupted: 应指向中断关卡")
	var inv: Array = fresh.get_profile().inventory
	_expect(_count_items(inv, "hpPotion") == 4 and _count_items(inv, "mpPotion") == 4,
		"interrupted: 应恢复出征前库存，实际 %s" % _inv_str(inv))
	var still_locked: Dictionary = fresh.prepare_battle(L1)
	_expect(not still_locked.ok, "interrupted: 恢复后进度不应跳关")
	for s in fresh.list_profiles():
		if str(s.id) == pid:
			_expect(str(s.notice).contains("中断"), "interrupted: 列表摘要应有中断提示")
	var re: Dictionary = fresh.prepare_battle(L0)
	_expect(re.ok, "interrupted: 恢复后应可再次出征")


# ============================================================
# 落盘故障（出征取消 + 胜利重试）
# ============================================================

func _test_persist_failure() -> void:
	var session := _begin("persist")
	session.create_profile("重试队")
	var pid := str(session.get_profile().id)
	# 1) 出征前落盘失败 → 取消出征、回滚库存
	var faulty := FaultyStore.new()
	faulty.base_dir = session.base_dir
	session._store = faulty
	var blocked: Dictionary = session.prepare_battle(L0)
	_expect(not blocked.ok, "persist: 出征前落盘失败应取消出征")
	_expect(str(blocked.error).contains("出征"), "persist: 错误应说明已取消出征，实际 %s" % str(blocked.error))
	var inv: Array = session.get_profile().inventory
	_expect(_count_items(inv, "hpPotion") == 4 and _count_items(inv, "mpPotion") == 4,
		"persist: 取消出征后库存应回滚，实际 %s" % _inv_str(inv))
	# 2) 修复后出征成功
	faulty.fail_saves = false
	var prepared: Dictionary = session.prepare_battle(L0)
	_expect(prepared.ok, "persist: 修复后出征应成功")
	# 3) 胜利落盘失败 → retryable、内存不动、attempt 仍挂起；level_ups 不发布
	faulty.fail_saves = true
	var chapter: Dictionary = prepared.chapter
	var units: Array = chapter.playerUnits
	units[0]["exp"] = int(units[0].exp) + 10
	units[0]["level"] = int(units[0].level) + 1
	var token := str(prepared.token)
	var failed: Dictionary = session.settle_battle(token, &"win", chapter)
	_expect(not failed.ok and bool(failed.get("retryable", false)), "persist: 胜利落盘失败应可重试")
	_expect(not failed.has("level_ups"), "persist: 落盘失败不发布 level_ups")
	_expect(int(session.get_profile().gold) == 0, "persist: 失败时不应入账")
	_expect(session.get_profile().completed_levels.is_empty(), "persist: 失败时不应记通关")
	var still_pending: Dictionary = session.prepare_battle(L0)
	_expect(not still_pending.ok, "persist: 落盘失败后 attempt 仍挂起（不能重复出征）")
	# 4) 修复 → 同 token 重试成功且只入账一次
	faulty.fail_saves = false
	var receipt: Dictionary = session.settle_battle(token, &"win", chapter)
	_expect(receipt.ok, "persist: 修复后重试应成功，实际 %s" % str(receipt.error))
	if receipt.ok:
		_expect(int(session.get_profile().gold) == 200, "persist: 重试后应恰好入账一次")
		_expect((receipt.level_ups as Array).size() == 1, "persist: 重试成功后才发布 level_ups")
		var replay: Dictionary = session.settle_battle(token, &"win", chapter)
		_expect(replay.ok and bool(replay.already_settled) and int(session.get_profile().gold) == 200,
			"persist: 再次重放不应重复入账")
	# 磁盘健康：新会话可读，升级已落盘
	var fresh := _mk_session()
	var rel: Dictionary = fresh.load_profile(pid)
	_expect(rel.ok and int(fresh.get_profile().gold) == 200, "persist: 最终磁盘态应健康")
	_expect(rel.ok and int(fresh.get_profile().roster[0].level) == int(units[0].level),
		"persist: 磁盘应保留升级后等级")


# ============================================================
# 备份保护：损坏主档 + 合法备份下的落盘自愈
# ============================================================

func _test_bak_heal() -> void:
	var session := _begin("bakheal")
	session.create_profile("护档队")
	var pid := str(session.get_profile().id)
	var pre: Dictionary = session.save_current()
	_expect(pre.ok, "bakheal: 前置保存应成功（产生备份），实际 %s" % str(pre.error))
	var main_path := session.base_dir.path_join(
		StoreScript._safe_stem("campaign:" + pid) + ".json")
	# 1) 损坏主档 + 合法备份 + 落盘失败 → 自愈先行，主档位已是好档（不靠备份续命）
	_write_file(main_path, "{oops")
	var s2 := _mk_session()
	var loaded: Dictionary = s2.load_profile(pid)
	_expect(loaded.ok, "bakheal: 前置：损坏主档应从备份恢复，实际 %s" % str(loaded.error))
	var faulty := HealFaultyStore.new()
	faulty.base_dir = session.base_dir
	s2._store = faulty
	var failed_save: Dictionary = s2.save_current()
	_expect(not failed_save.ok, "bakheal: 注入的 save_record 失败应上抛")
	var layers: Dictionary = faulty.read_layers(pid)
	var main_ok: bool = layers.main.has("record") \
		and CodecScript.restore(layers.main.record).get("ok", false)
	_expect(main_ok, "bakheal: 落盘失败后主档位应是自愈后的好档，而非残留坏档")
	var bak_ok: bool = layers.bak.has("record") \
		and CodecScript.restore(layers.bak.record).get("ok", false)
	_expect(bak_ok, "bakheal: 失败路径中备份不应被破坏")
	var checker := _mk_session()
	_expect(checker.load_profile(pid).ok, "bakheal: 落盘失败后新会话仍应能加载好档")
	# 2) 损坏主档 + 合法备份 + 落盘成功：坏内容不得存活于任何一层
	_write_file(main_path, "{oops")
	var s3 := _mk_session()
	_expect(s3.load_profile(pid).ok, "bakheal: 前置：再次损坏后仍可从备份恢复")
	var healed_save: Dictionary = s3.save_current()
	_expect(healed_save.ok, "bakheal: 自愈后保存应成功，实际 %s" % str(healed_save.get("error", "")))
	var after: Dictionary = s3._ensure_store().read_layers(pid)
	for layer_name in ["main", "bak"]:
		var layer: Dictionary = after[layer_name]
		var layer_ok: bool = not layer.get("present", false) \
			or (layer.has("record") and CodecScript.restore(layer.record).get("ok", false))
		_expect(layer_ok, "bakheal: 保存成功后 %s 层不应残留坏内容" % layer_name)
	var s4 := _mk_session()
	_expect(s4.load_profile(pid).ok, "bakheal: 最终磁盘态健康")
	# 3) 未来版本主档：save_profile 必须在轮换发生前直接拒绝（任何写入都不得
	#    覆盖未来版本文件），重命名/加载同样拒绝
	var good: Dictionary = after.main.record.duplicate(true)
	var future: Dictionary = good.duplicate(true)
	future["version"] = 99
	_write_file(main_path, JSON.stringify(future))
	var raw_store := StoreScript.new()
	raw_store.base_dir = session.base_dir
	var saved_newer: Dictionary = raw_store.save_profile(good)
	_expect(not saved_newer.ok and saved_newer.get("newer", false),
		"bakheal: 未来主档应拒绝写入，实际 %s" % str(saved_newer.get("error", "")))
	var layers99: Dictionary = raw_store.read_layers(pid)
	_expect(layers99.main.has("record") and int(layers99.main.record.get("version", 0)) == 99,
		"bakheal: 拒绝写入后未来主档应原样保留")
	_expect(layers99.bak.has("record") and int(layers99.bak.record.get("version", 0)) == 1,
		"bakheal: 备份不应被轮换破坏")
	var s5 := _mk_session()
	var renamed_future: Dictionary = s5.rename_profile(pid, "未来名")
	_expect(not renamed_future.ok and renamed_future.get("newer", false),
		"bakheal: 未来主档重命名应被拒绝")
	_expect(not s5.load_profile(pid).ok, "bakheal: 未来主档加载应被拒绝（newer）")
	_expect(s5.delete_profile(pid).ok, "bakheal: 未来主档删除应仍可用（用户显式清理）")


# ============================================================
# 最近使用标记
# ============================================================

func _test_recent_marker() -> void:
	var session := _begin("recent")
	var y: Dictionary = session.create_profile("乙")
	_expect(_recent_id(session) == str(y.profile_id), "recent: 新建后应标记最近")
	var j: Dictionary = session.create_profile("甲")
	_expect(_recent_id(session) == str(j.profile_id), "recent: 后建的档案应成为最近")
	session.load_profile(str(y.profile_id))
	_expect(_recent_id(session) == str(y.profile_id), "recent: 加载旧档应成为最近")
	var fresh := _mk_session()
	_expect(_recent_id(fresh) == str(y.profile_id), "recent: 新会话应从磁盘索引恢复最近")
	fresh.delete_profile(str(y.profile_id))
	_expect(_recent_id(fresh) == str(j.profile_id), "recent: 删除后应回退到剩余档案")
	# 手删索引 → saved_at 扫描自恢复
	_remove_file(_cur_dir.path_join("index.json"))
	_remove_file(_cur_dir.path_join("index.json.bak"))
	_expect(_recent_id(fresh) == str(j.profile_id), "recent: 索引丢失时应回退最新保存档案")


func _recent_id(session: SessionScript) -> String:
	for s in session.list_profiles():
		if bool(s.get("is_recent", false)):
			return str(s.id)
	return ""


# ============================================================
# 目录隔离
# ============================================================

func _test_configure_store_dir() -> void:
	var session := _begin("dir")
	var main_dir := session.base_dir
	session.create_profile("隔离队")
	var alt_dir := ROOT.path_join("alt")
	_remove_recursive(alt_dir)
	session.configure_store_dir(alt_dir)
	_expect(session.get_profile().is_empty(), "dir: 切目录后内存应清空")
	_expect(session.list_profiles().is_empty(), "dir: 新目录应无档案")
	session.create_profile("二号目录")
	_expect(session.list_profiles().size() == 1, "dir: 新目录写入应生效")
	session.configure_store_dir(main_dir)
	var back: Array = session.list_profiles()
	_expect(back.size() == 1, "dir: 切回原目录档案应在，实际 %d" % back.size())
	_expect(str(back[0].name) == "隔离队", "dir: 原目录档案未丢失")


# ============================================================
# 商店购买（W2）：原子性 / 失败无副作用 / 模板补齐 / 限购周期
# ============================================================

func _test_shop_buy() -> void:
	# 无档拒绝
	var session := _begin("shop_buy")
	var no_profile := session.list_shop()
	_expect(not no_profile.ok, "shop: 无档 list_shop 应失败")
	var no_buy: Dictionary = session.buy_item("hpPotion", 1)
	_expect(not no_buy.ok, "shop: 无档购买应失败")
	# 创建档（gold=0）
	session.create_profile("采购队")
	var listed: Dictionary = session.list_shop()
	_expect(listed.ok, "shop: list_shop 应成功")
	_expect(int(listed.gold) == 0 and int(listed.clear_index) == 0, "shop: 新档 gold=0 周期=0")
	var stock: Array = listed.stock
	_expect(stock.size() == 4, "shop: 货架应 4 条，实际 %d" % stock.size())
	var by_id := {}
	for e in stock:
		by_id[String(e.id)] = e
	_expect(by_id.has("hpPotion") and int(by_id["hpPotion"].price) == 80
		and int(by_id["hpPotion"].limit_per_clear) == 0 and int(by_id["hpPotion"].remaining) == -1,
		"shop: hpPotion 应 80 金不限购（remaining -1）")
	_expect(by_id.has("mpPotion") and int(by_id["mpPotion"].limit_per_clear) == 2
		and int(by_id["mpPotion"].remaining) == 2,
		"shop: mpPotion 应限购 2 剩 2")
	# 校验失败链（每条都不得有副作用）；1.5/"2"/true 为真实调用——
	# int 形参会在调用点截断/抛错，Variant 形参必须函数内拒绝
	var before := JSON.stringify(session.get_profile())
	_expect(not session.buy_item("notAThing", 1).ok, "shop: 未知物应拒绝")
	for bad_count: Variant in [0, -3, 1.5, "2", true]:
		var bad: Dictionary = session.buy_item("hpPotion", bad_count)
		_expect(not bad.ok and str(bad.error).contains("正整数"),
			"shop: 非法 count=%s 应拒正整数，实际 %s" % [str(bad_count), str(bad.error)])
	var poor: Dictionary = session.buy_item("hpPotion", 1)
	_expect(str(poor.error).contains("金币不足"), "shop: 0 金应报金币不足，实际 %s" % str(poor.error))
	_expect(JSON.stringify(session.get_profile()) == before, "shop: 失败购买不得改变 state")
	# 首胜得 200 金后购买
	_win_once(session, L0)
	var rich: Dictionary = session.list_shop()
	_expect(int(rich.gold) == 200, "shop: 首胜后应 200 金")
	var hp_entry: Dictionary = {}
	for e in rich.stock:
		if String(e.id) == "hpPotion":
			hp_entry = e
	_expect(int(hp_entry.affordable_count) == 2 and int(hp_entry.max_buyable) == 2,
		"shop: 200 金 hpPotion 应可购 2，实际 %s" % str([hp_entry.affordable_count, hp_entry.max_buyable]))
	_expect(not session.buy_item("hpPotion", 3).ok, "shop: 超额购买（240>200）应金币不足")
	var template_hp_before := _template_entries(session, "hpPotion")
	var hp_pre := _count_items(session.get_profile().inventory, "hpPotion")
	var bought: Dictionary = session.buy_item("hpPotion", 2)
	_expect(bought.ok, "shop: 买 2×hpPotion 应成功，实际 %s" % str(bought.error))
	_expect(int(bought.total_cost) == 160 and int(bought.gold) == 40, "shop: 应扣 160 剩 40")
	var inv: Array = session.get_profile().inventory
	_expect(_count_items(inv, "hpPotion") == hp_pre + 2,
		"shop: 库存 hpPotion 应恰 +2，实际 %s" % _inv_str(inv))
	var hp_tail_full := 0
	for idx in range(inv.size() - 1, -1, -1):
		if String((inv[idx] as Dictionary).get("id", "")) == "hpPotion":
			if int((inv[idx] as Dictionary).uses) == 3:
				hp_tail_full += 1
			else:
				break
	_expect(hp_tail_full >= 2, "shop: 买入的 2 件 hpPotion 应满充 uses=3（尾部），实际 %s" % _inv_str(inv))
	if template_hp_before > 0:
		_expect(_template_entries(session, "hpPotion") == template_hp_before,
			"shop: hpPotion 已被模板覆盖，购买不得重复追加")
	else:
		_expect(_template_entries(session, "hpPotion") == 1,
			"shop: hpPotion 未覆盖时购买应补模板 1 条")
	# 模板补齐：买新物品给队长行追加 {id,1}；已覆盖再买不重复
	_win_once(session, L0)
	_win_once(session, L0)
	_expect(int(session.get_profile().gold) == 140, "shop: 前置凑钱应 140")
	_expect(_template_entries(session, "shuriken") == 0, "shop: 前置 shuriken 应无模板")
	var bought_shuriken: Dictionary = session.buy_item("shuriken", 1)
	_expect(bought_shuriken.ok, "shop: 买 shuriken 应成功")
	_expect(_template_entries(session, "shuriken") == 1, "shop: 买新物品应补模板 1 条")
	_win_once(session, L0)
	_win_once(session, L0)
	var bought_again: Dictionary = session.buy_item("shuriken", 1)
	_expect(bought_again.ok, "shop: 二买 shuriken 应成功")
	_expect(_template_entries(session, "shuriken") == 1, "shop: 已覆盖物品不得重复追加模板")
	# 出征挂起时拒绝购买
	var prepared: Dictionary = session.prepare_battle(L0)
	_expect(prepared.ok, "shop: 前置出征应成功")
	_expect(str(session.buy_item("hpPotion", 1).error).contains("战斗进行中"),
		"shop: 出征挂起应拒绝购买")
	session.settle_battle(str(prepared.token), &"lose", {})
	_win_once(session, L0)
	_win_once(session, L0)
	_expect(session.buy_item("hpPotion", 1).ok, "shop: 战斗结束后购买应恢复")
	# 落盘失败：未扣费、state 不变；修复后重试成功
	_win_once(session, L0)
	var gold_before_fail := int(session.get_profile().gold)
	_expect(gold_before_fail >= 80, "shop: 前置应有购买资金，实际 %d" % gold_before_fail)
	var faulty := FaultyStore.new()
	faulty.base_dir = session.base_dir
	session._store = faulty
	var failed_buy: Dictionary = session.buy_item("hpPotion", 1)
	_expect(not failed_buy.ok and str(failed_buy.error).contains("落盘失败"), "shop: 落盘失败应报错")
	_expect(int(session.get_profile().gold) == gold_before_fail, "shop: 落盘失败不得扣费")
	faulty.fail_saves = false
	_expect(session.buy_item("hpPotion", 1).ok, "shop: 修复后重试应成功")
	# 重载：限购计数与库存持久（与 session 终态精确对拍，规避随机掷落影响）
	var hp_final := _count_items(session.get_profile().inventory, "hpPotion")
	var shuriken_final := _count_items(session.get_profile().inventory, "shuriken")
	var fresh := _mk_session()
	fresh.load_profile(str(session.get_profile().id))
	var reloaded: Array = fresh.get_profile().inventory
	_expect(_count_items(reloaded, "shuriken") == shuriken_final
		and _count_items(reloaded, "hpPotion") == hp_final,
		"shop: 重载库存应与终态一致（%d hp / %d shuriken），实际 %s"
			% [hp_final, shuriken_final, _inv_str(reloaded)])
	var purchases: Dictionary = fresh._state.shop_purchases
	_expect(int(purchases.clear_index) == 1 and int(purchases.counts.get("hpPotion", 0)) == 4
		and int(purchases.counts.get("shuriken", 0)) == 2,
		"shop: 重载限购记录应持久（clear1 hp4 shuriken2），实际 %s" % str(purchases))
	# 买的物品真实可用：部署进战斗并由 Resolver 结算
	var deploy_prepared: Dictionary = fresh.prepare_battle(L0)
	_expect(deploy_prepared.ok, "shop: 部署出征应成功，实际 %s" % str(deploy_prepared.error))
	if deploy_prepared.ok:
		var units: Array = deploy_prepared.chapter.playerUnits
		var carried := 0
		for it in units[0].items:
			if String(it.id) == "shuriken":
				carried += 1
		_expect(carried >= 1, "shop: 队长应实际带上新买的 shuriken（模板补齐 + FIFO 补给）")
		var enemy: Dictionary = deploy_prepared.chapter.enemyUnits[0]
		var enemy_hp := int(enemy.hp)
		var shuriken_entry := {}
		for it in units[0].items:
			if String(it.id) == "shuriken":
				shuriken_entry = it
				break
		if not shuriken_entry.is_empty():
			var used: Dictionary = ResolverScript.resolve_item(units[0], [enemy], shuriken_entry)
			_expect(used.has("item"), "shop: resolve_item 应可结算购买的 shuriken")
			_expect(int(enemy.hp) < enemy_hp, "shop: shuriken 应造成实际伤害 %d→%d" % [enemy_hp, int(enemy.hp)])


func _template_entries(session: SessionScript, iid: String) -> int:
	var n := 0
	var state: Dictionary = session._state
	for row: Variant in state.get("carry_templates", []):
		if row is not Array:
			continue
		for entry: Variant in row:
			if entry is Dictionary and String((entry as Dictionary).get("id", "")) == iid:
				n += 1
	return n


## 限购周期：completed_levels.size() 推进（新关首通）才刷新；repeat 与重载不刷新。
func _test_shop_limit_cycle() -> void:
	var session := _begin("shop_limit")
	session.create_profile("限购队")
	_win_once(session, L0)
	_win_once(session, L0)
	_win_once(session, L0)
	_expect(int(session.get_profile().gold) == 300, "limit: 前置应 300 金")
	# 超 limit 拒绝（0+3 > 2）
	var over: Dictionary = session.buy_item("mpPotion", 3)
	_expect(str(over.error).contains("限购"), "limit: 超限购应拒绝，实际 %s" % str(over.error))
	# 顶格买 2 → remaining 0
	var bought: Dictionary = session.buy_item("mpPotion", 2)
	_expect(bought.ok and int(bought.remaining) == 0, "limit: 顶格购买后 remaining 应 0")
	var listed: Dictionary = session.list_shop()
	for e in listed.stock:
		if String(e.id) == "mpPotion":
			_expect(int(e.remaining) == 0 and int(e.max_buyable) == 0,
				"limit: 售罄后 remaining/max_buyable 应 0")
	_expect(str(session.buy_item("mpPotion", 1).error).contains("限购"), "limit: 售罄再买应拒绝")
	_expect(int(session.get_profile().gold) == 60, "limit: 应扣 240 剩 60")
	# 重载：计数持久、仍售罄
	var fresh := _mk_session()
	fresh.load_profile(str(session.get_profile().id))
	for e in fresh.list_shop().stock:
		if String(e.id) == "mpPotion":
			_expect(int(e.remaining) == 0, "limit: 重载后仍应售罄（计数持久）")
	# repeat 通关：completed 不变 → 不刷新
	_win_once(fresh, L0)
	for e in fresh.list_shop().stock:
		if String(e.id) == "mpPotion":
			_expect(int(e.remaining) == 0, "limit: repeat 通关不得刷新额度")
	# 首通新关：周期推进 → 额度重置
	_win_once(fresh, L1)
	var refreshed: Dictionary = fresh.list_shop()
	_expect(int(refreshed.clear_index) == 2, "limit: 首通后周期应为 2")
	for e in refreshed.stock:
		if String(e.id) == "mpPotion":
			_expect(int(e.remaining) == 2, "limit: 新关首通应刷新限购额度")
	var rebuy: Dictionary = fresh.buy_item("mpPotion", 1)
	_expect(rebuy.ok, "limit: 新周期购买应成功，实际 %s" % str(rebuy.error))
	var purchases: Dictionary = fresh._state.shop_purchases
	_expect(int(purchases.clear_index) == 2 and int(purchases.counts.get("mpPotion", 0)) == 1
		and not purchases.counts.has("hpPotion"),
		"limit: 周期推进后计数应重起（clear_index=2 mp=1），实际 %s" % str(purchases))


## 胜利掉落：seed 精确复现 / pending 合并 / 固定奖不污染 / 幂等 / 落盘
func _test_victory_loot() -> void:
	var session := _begin("loot")
	session.create_profile("拾荒队")
	# 无表关（L3）行为与现网一致：receipt.loot == []
	_win_once(session, L0)
	_win_once(session, L1)
	_win_once(session, L2)
	var no_table: Dictionary = session.prepare_battle(L3)
	_expect(no_table.ok, "loot: L3 出征应成功，实际 %s" % str(no_table.error))
	if no_table.ok:
		var r3: Dictionary = session.settle_battle(str(no_table.token), &"win", no_table.chapter)
		_expect(r3.ok and (r3.loot as Array).is_empty(), "loot: 无表关 receipt.loot 应为空数组")
	# 有表关（L0 首胜）：注入 loot_seed 精确对拍 roll_loot
	var seed_session := _begin("loot_seed")
	seed_session.create_profile("对拍队")
	var prepared: Dictionary = seed_session.prepare_battle(L0)
	_expect(prepared.ok, "loot: L0 出征应成功")
	seed_session._attempt["loot_seed"] = 42
	var rewards: Dictionary = CampaignConfigScript.rewards_for(L0, true)
	var rng_e := RandomNumberGenerator.new()
	rng_e.seed = 42
	var expected: Array = CampaignConfigScript.roll_loot(rewards.loot_table, int(rewards.loot_rolls), rng_e)
	var chapter: Dictionary = prepared.chapter
	chapter["pending_loot"] = [{"id": "shuriken", "count": 2}]
	var receipt: Dictionary = seed_session.settle_battle(str(prepared.token), &"win", chapter)
	_expect(receipt.ok, "loot: 胜利结算应成功，实际 %s" % str(receipt.error))
	if not receipt.ok:
		return
	# 期望 = 掷出（seed 42 确定性）+ pending shuriken×2 同 id 合并
	var expect_counts := {}
	for e in expected:
		expect_counts[String(e.id)] = int(e.count)
	expect_counts["shuriken"] = int(expect_counts.get("shuriken", 0)) + 2
	var loot: Array = receipt.loot
	var loot_counts := {}
	for e in loot:
		loot_counts[String(e.id)] = int(e.count)
	_expect(JSON.stringify(loot_counts) == JSON.stringify(expect_counts),
		"loot: seed42 掉落应精确对拍 roll_loot+pending，期望 %s 实际 %s" % [str(expect_counts), str(loot_counts)])
	for e in loot:
		var max_uses := 4 if String(e.id) == "shuriken" else 2
		_expect(int(e.uses) == max_uses, "loot: %s 应满充 uses=%d" % [String(e.id), max_uses])
	# 固定奖与 loot 分离；level_ups 保留
	_expect((receipt.items as Array).size() == 1, "loot: items 固定奖应仍 1×hpPotion")
	_expect(receipt.has("level_ups"), "loot: receipt 应保留 level_ups 键")
	# 库存入账 + 磁盘持久
	var inv: Array = seed_session.get_profile().inventory
	_expect(_count_items(inv, "shuriken") == int(loot_counts.get("shuriken", 0)),
		"loot: 库存 shuriken 应等于 receipt 掉落数")
	var replay: Dictionary = seed_session.settle_battle(str(prepared.token), &"win", chapter)
	_expect(replay.ok and bool(replay.already_settled) and JSON.stringify(replay.loot) == JSON.stringify(loot),
		"loot: 幂等重放应回带同一 loot")
	var fresh := _mk_session()
	fresh.load_profile(str(seed_session.get_profile().id))
	var disk_inv: Array = fresh.get_profile().inventory
	_expect(_count_items(disk_inv, "shuriken") == int(loot_counts.get("shuriken", 0)),
		"loot: 磁盘库存应持久掉落")


## pending_loot：胜利并入（非法条目跳过）；失败/撤退不入账、库存恢复出征前。
func _test_victory_loot_pending() -> void:
	var session := _begin("loot_pending")
	session.create_profile("缴获队")
	var prepared: Dictionary = session.prepare_battle(L0)
	_expect(prepared.ok, "pending: 出征应成功")
	var chapter: Dictionary = prepared.chapter
	chapter["pending_loot"] = [
		{"id": "antidote", "count": 2},
		{"id": "noSuchItem", "count": 5},
		"garbage-entry",
		{"id": "hpPotion", "count": 1},
	]
	var receipt: Dictionary = session.settle_battle(str(prepared.token), &"win", chapter)
	_expect(receipt.ok, "pending: 胜利应成功（非法条目跳过不报错）")
	var inv: Array = session.get_profile().inventory
	_expect(_count_items(inv, "antidote") == 2 and _uses_of_first(inv, "antidote") == 2,
		"pending: antidote 应 2 件满充 2 入账")
	# 失败/撤退：pending 不入账，库存恢复出征前精确值
	for mode in ["lose", "abandon"]:
		var s2 := _begin("loot_" + mode)
		s2.create_profile("撤退队" + mode)
		var p2: Dictionary = s2.prepare_battle(L0)
		_expect(p2.ok, "pending: %s 出征应成功" % mode)
		p2.chapter["pending_loot"] = [{"id": "antidote", "count": 3}]
		var r2: Dictionary = s2.settle_battle(str(p2.token), StringName(mode), {})
		_expect(r2.ok and not r2.has("loot"), "pending: %s receipt 不应带 loot" % mode)
		var inv2: Array = s2.get_profile().inventory
		_expect(_count_items(inv2, "antidote") == 0 and _count_items(inv2, "hpPotion") == 4
			and _count_items(inv2, "mpPotion") == 4,
			"pending: %s 库存应恢复出征前，实际 %s" % [mode, _inv_str(inv2)])


## 胜利落盘失败：掷出结果缓存，同 token 重试不重掷、恰入账一次。
func _test_victory_loot_persist_retry() -> void:
	var session := _begin("loot_retry")
	session.create_profile("重掷队")
	var prepared: Dictionary = session.prepare_battle(L0)
	_expect(prepared.ok, "loot_retry: 出征应成功")
	session._attempt["loot_seed"] = 12345
	var faulty := FaultyStore.new()
	faulty.base_dir = session.base_dir
	session._store = faulty
	var token := str(prepared.token)
	var failed: Dictionary = session.settle_battle(token, &"win", prepared.chapter)
	_expect(not failed.ok and bool(failed.get("retryable", false)), "loot_retry: 落盘失败应可重试")
	_expect(not failed.has("loot"), "loot_retry: 失败 receipt 不应发布 loot")
	_expect(session._attempt.has("loot_rolled"), "loot_retry: 失败后掷出结果应已缓存")
	# 篡改缓存为已知值：重试若重掷，结果（几乎）不可能等于篡改值
	var tampered := [{"id": &"bomb", "name": "炸弹", "count": 9, "uses": 2}]
	session._attempt["loot_rolled"] = tampered
	faulty.fail_saves = false
	var retried: Dictionary = session.settle_battle(token, &"win", prepared.chapter)
	_expect(retried.ok, "loot_retry: 修复后重试应成功，实际 %s" % str(retried.error))
	if retried.ok:
		var loot: Array = retried.loot
		_expect(loot.size() == 1 and String(loot[0].id) == "bomb" and int(loot[0].count) == 9,
			"loot_retry: 重试应复用缓存掷出结果（不重掷）")
		var inv: Array = session.get_profile().inventory
		_expect(_count_items(inv, "bomb") == 9, "loot_retry: 库存应恰 9×bomb")
		_expect(int(session.get_profile().gold) == 200, "loot_retry: 奖励应恰入账一次")
	var fresh := _mk_session()
	fresh.load_profile(str(session.get_profile().id))
	_expect(_count_items(fresh.get_profile().inventory, "bomb") == 9, "loot_retry: 磁盘应持久 9×bomb")


# ============================================================
# 工具
# ============================================================

class FaultyStore extends "res://scripts/campaign/campaign_profile_store.gd":
	var fail_saves := true

	func save_profile(record: Dictionary) -> Dictionary:
		if fail_saves:
			return {"ok": false, "error": "注入故障：save 失败"}
		return super.save_profile(record)


## save_record 级故障注入：自愈预检之后、轮换写之前失败——
## 用于验证"落盘失败仍有好档"（自愈必须发生在进入旧 store 之前）。
class HealFaultyStore extends "res://scripts/campaign/campaign_profile_store.gd":
	var _broken: RefCounted = null

	func _ensure() -> RefCounted:
		if _broken == null:
			_broken = BrokenRecordStore.new()
			_broken.base_dir = base_dir
		return _broken

	class BrokenRecordStore extends "res://scripts/core/battle_save_store.gd":
		func save_record(_identity: String, _record: Dictionary) -> Dictionary:
			return {"ok": false, "error": "注入故障：save_record 失败"}


## 每个测试独立子目录：先清空再建会话，杜绝跨测试污染。
func _begin(tag: String) -> SessionScript:
	var dir := ROOT.path_join(tag)
	_remove_recursive(dir)
	_cur_dir = dir
	return _mk_session()


func _mk_session() -> SessionScript:
	var session := SessionScript.new()
	session.base_dir = _cur_dir
	_sessions.append(session)
	return session


func _write_file(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _count_items(inventory: Array, iid: String) -> int:
	var n := 0
	for e in inventory:
		if String(e.get("id", "")) == iid:
			n += 1
	return n


func _uses_of_first(inventory: Array, iid: String) -> int:
	for e in inventory:
		if String(e.get("id", "")) == iid:
			return int(e.get("uses", -1))
	return -1


func _inv_str(inventory: Array) -> String:
	var parts: Array = []
	for e in inventory:
		parts.append("%s:%d" % [String(e.get("id", "?")), int(e.get("uses", -1))])
	parts.sort()
	return ",".join(parts)


func _cleanup_root() -> void:
	_remove_recursive(ROOT)


func _remove_recursive(dir_path: String) -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	var target := dir_path.replace("user://", "")
	if not dir.dir_exists(target):
		return
	var sub := DirAccess.open(dir_path)
	if sub == null:
		return
	sub.list_dir_begin()
	var fname := sub.get_next()
	while fname != "":
		if fname != "." and fname != "..":
			if sub.current_is_dir():
				_remove_recursive(dir_path.path_join(fname))
			else:
				sub.remove(fname)
		fname = sub.get_next()
	sub.list_dir_end()
	DirAccess.open("user://").remove(target)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
