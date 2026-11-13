## battle_ai_difficulty_contract.gd — AI 四档难度契约（profile / 决策差异 / 注入链路 / 确定性）
##
## 验证面：
##   1) AIDifficulty 元数据（validate/normalize/OPTIONS/normal 历史参数）
##   2) normal 档与历史行为逐值等价（缺省参 == 显式 normal == PlayerAI auto 透传）
##   3) 集火残血：hard/nightmare 选残血目标，normal 选高伤目标，novice 选最差
##   4) 追击：normal 朝最近敌移动，novice 原地待命
##   5) 击杀意识：normal/hard/nightmare 收割可杀目标，novice 选最差
##   6) PlayerAI 托管路径对称（auto 透传 + 非 auto 策略叠加 focus/worst）
##   7) 声明式场景 ai_pref.difficulty 注入（runner 进程内 + CLI 子进程 + loader 校验）
##   8) 确定性：nightmare 同 seed 双跑事件流一致
##   10) 类型安全：loader difficulty 非字符串报错；Settings._clamp_difficulty 任意类型宽容
##   11) 优先目标语义：显式 priorityTargetId 在任何难度（含 novice worst）下都胜出
##   12) focus 集火统一：伤害型技能/物品评分与普攻同款残血加分
##   13) 非 auto 策略 fallback：novice 不追击（pursue=false）
##
## 局面用手工 UnitData 构造（数值完全可控，不依赖职业表），技能/物品置空
## 以隔离出普攻评分路径；runner 链路用标准职业（覆盖真实数据面）。

extends SceneTree


const AIDifficulty := preload("res://scripts/systems/ai_difficulty.gd")
const AIDifficultyScoring := preload("res://scripts/systems/ai_difficulty_scoring.gd")
const EnemyAI := preload("res://scripts/systems/enemy_ai.gd")
const PlayerAI := preload("res://scripts/systems/player_ai.gd")
const ScenarioLoader := preload("res://scripts/battle/automation/battle_scenario_loader.gd")
const Runner := preload("res://scripts/battle/automation/battle_runner.gd")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[battle_ai_difficulty_contract] start")
	_test_profile_metadata()
	_test_normal_equivalence()
	_test_focus_wounded()
	_test_pursue()
	_test_kill_preference()
	_test_player_ai_hosting()
	_test_scenario_runner()
	_test_cli_subprocess()
	_test_determinism()
	_test_type_safety()
	_test_priority_semantics()
	_test_focus_unified()
	_test_nonauto_fallback_pursue()
	_test_priority_limits_skills()
	if _failures > 0:
		push_error("[battle_ai_difficulty_contract] FAILED: %d 处断言未过" % _failures)
		quit(1)
		return
	print("BATTLE_AI_DIFFICULTY_CONTRACT_OK")
	quit(0)


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  [ok] %s" % label)
	else:
		_failures += 1
		push_error("  [FAIL] %s" % label)


# ============================================================
# 局面构造（手工 UnitData，数值可控）
# ============================================================

## 武器模板（CombatSystem 访问键：type/hit/might/crit/weight）
func _wpn(type_name: String, might: int, hit: int, weight: int) -> Dictionary:
	return {
		&"id": StringName(type_name), &"name": type_name, &"type": StringName(type_name),
		&"might": might, &"hit": hit, &"crit": 0, &"weight": weight,
		&"range": [1, 1],
	}


func _mk_unit(
	id: StringName, faction: StringName, x: int, y: int,
	weapon: Dictionary, stats: Dictionary, hp: int, rng: Array
) -> Dictionary:
	var s: Dictionary = {
		&"hp": 30, &"str": 1, &"mag": 0, &"skl": 1, &"spd": 1, &"luk": 1,
		&"def": 1, &"res": 1, &"mov": 1,
	}
	s.merge(stats, true)
	return {
		&"id": id, &"name": String(id), &"classId": &"test", &"faction": faction,
		&"level": 1, &"exp": 0,
		&"stats": s, &"growths": {},
		&"weapon": weapon, &"moveType": &"foot",
		&"attackRange": [int(rng[0]), int(rng[1])],
		&"hp": hp, &"mp": 0,
		&"position": Vector2i(x, y),
		&"hasMoved": false, &"hasActed": false, &"isDead": false,
		&"skills": [], &"skillCooldowns": {}, &"items": [], &"buffs": [],
	}


func _mk_grid(units: Array, w: int = 5, h: int = 5) -> GridSystem:
	var map: Array = []
	for y in h:
		var row: Array = []
		for x in w:
			row.append(&"plain")
		map.append(row)
	var g := GridSystem.new(w, h, map)
	for u in units:
		g.place_unit(u, u[&"position"].x, u[&"position"].y)
	return g


## 组3 标准局面：弓手决策者 (2,2) rng[2,3]；
## 玩家 knight_t (0,2) def20 残血 + mage_t (4,2) def0 满血；距离均 2。
## 预期分数（plain 0/0，bow 无三角）：
##   打 knight_t：atkDmg=0（10+5-20<0）double → base=0；反击 1 点
##   打 mage_t ：atkDmg=15 double → base=45；反击 20 点（mag20+5-def5）
func _duel_setup() -> Array:
	var archer := _mk_unit(
		&"u_e_arch", &"enemy", 2, 2, _wpn("bow", 5, 90, 0),
		{&"str": 10, &"skl": 10, &"spd": 10, &"luk": 10, &"def": 5, &"res": 5},
		30, [2, 3]
	)
	var knight_t := _mk_unit(
		&"u_p_knight", &"player", 0, 2, _wpn("lance", 5, 80, 0),
		{&"str": 1, &"def": 20, &"res": 5}, 2, [1, 1]
	)
	var mage_t := _mk_unit(
		&"u_p_mage", &"player", 4, 2, _wpn("anima", 5, 90, 0),
		{&"mag": 20, &"def": 0, &"res": 0}, 30, [1, 2]
	)
	return [archer, knight_t, mage_t]


func _target_id(decision: Dictionary) -> String:
	var t: Dictionary = decision.get(&"attackTarget", {})
	return String(t.get(&"id", ""))


# ============================================================
# 组 1：profile 元数据
# ============================================================

func _test_profile_metadata() -> void:
	print("[1] profile 元数据")
	_expect(AIDifficulty.validate(&"novice") and AIDifficulty.validate(&"normal")
		and AIDifficulty.validate(&"hard") and AIDifficulty.validate(&"nightmare"),
		"validate 四档全真")
	_expect(not AIDifficulty.validate("insane") and not AIDifficulty.validate("hard ")
		and not AIDifficulty.validate(""), "validate 非法名全假")
	_expect(AIDifficulty.DEFAULT == &"normal", "DEFAULT=normal")
	_expect(AIDifficulty.normalize("insane") == &"normal"
		and AIDifficulty.normalize(&"hard") == &"hard", "normalize 非法回 normal")
	_expect(AIDifficulty.OPTIONS.size() == 4, "OPTIONS 4 项")

	var n: Dictionary = AIDifficulty.profile(&"normal")
	_expect(int(n[&"kill_bonus"]) == 5000 and int(n[&"skill_kill_bonus"]) == 4000
		and int(n[&"item_kill_bonus"]) == 3000 and float(n[&"counter_weight"]) == 1.0
		and float(n[&"focus_wounded"]) == 0.0 and n[&"selection"] == &"best"
		and bool(n[&"pursue"]) == true, "normal 档参数=历史公式值")
	var nov: Dictionary = AIDifficulty.profile(&"novice")
	_expect(int(nov[&"kill_bonus"]) == 0 and float(nov[&"counter_weight"]) == 0.0
		and nov[&"selection"] == &"worst" and bool(nov[&"pursue"]) == false,
		"novice 档：无击杀意识/无视反击/选最差/不追击")
	var hard: Dictionary = AIDifficulty.profile(&"hard")
	var nm: Dictionary = AIDifficulty.profile(&"nightmare")
	_expect(float(hard[&"focus_wounded"]) == 3.0 and float(nm[&"focus_wounded"]) == 8.0
		and int(nm[&"kill_bonus"]) == 20000, "hard/nightmare 集火与击杀权重递增")

	# focus_bonus 边界：满血/死亡/权重 0 恒 0
	var prof_w: Dictionary = {&"focus_wounded": 3.0}
	var full: Dictionary = {&"hp": 30, &"stats": {&"hp": 30}, &"isDead": false}
	var dead: Dictionary = {&"hp": 0, &"stats": {&"hp": 30}, &"isDead": true}
	var hurt: Dictionary = {&"hp": 2, &"stats": {&"hp": 30}, &"isDead": false}
	_expect(AIDifficultyScoring.focus_bonus(full, prof_w) == 0.0
		and AIDifficultyScoring.focus_bonus(dead, prof_w) == 0.0
		and AIDifficultyScoring.focus_bonus(hurt, {&"focus_wounded": 0.0}) == 0.0,
		"focus_bonus 满血/死亡/零权重恒 0")
	_expect(AIDifficultyScoring.focus_bonus(hurt, prof_w) == 84.0,
		"focus_bonus 缺 28 血 ×3.0 = 84")
	# better：best 取高、worst 取低
	var worst_p: Dictionary = {&"selection": &"worst"}
	var best_p: Dictionary = {&"selection": &"best"}
	_expect(AIDifficultyScoring.better(5.0, 10.0, best_p) == false
		and AIDifficultyScoring.better(5.0, 10.0, worst_p) == true,
		"better：best 取高 / worst 取低")


# ============================================================
# 组 2：normal 档与历史行为等价
# ============================================================

func _test_normal_equivalence() -> void:
	print("[2] normal 等价性")
	var units := _duel_setup()
	var archer: Dictionary = units[0]
	var players: Array = [units[1], units[2]]
	var grid := _mk_grid(units)

	var d_default: Dictionary = EnemyAI.decide(archer, grid, players)
	var d_normal: Dictionary = EnemyAI.decide(archer, grid, players, &"normal")
	_expect(d_default == d_normal, "decide 缺省参 == 显式 normal")

	var d_auto: Dictionary = PlayerAI.decide(archer, grid, players, {})
	var d_auto_n: Dictionary = PlayerAI.decide(archer, grid, players, {&"difficulty": &"normal"})
	_expect(d_auto == d_default and d_auto_n == d_default,
		"PlayerAI auto 空 pref / 带难度 pref == EnemyAI 缺省")

	# normal 行为锚定：选高伤目标 mage_t（base 45-20 > 0-1）
	_expect(_target_id(d_default) == &"u_p_mage", "normal 选高伤目标（mage）")


# ============================================================
# 组 3：集火残血
# ============================================================

func _test_focus_wounded() -> void:
	print("[3] 集火残血")
	var units := _duel_setup()
	var archer: Dictionary = units[0]
	var players: Array = [units[1], units[2]]
	var grid := _mk_grid(units)

	_expect(_target_id(EnemyAI.decide(archer, grid, players, &"normal")) == &"u_p_mage",
		"normal：无集火 → 高伤 mage")
	_expect(_target_id(EnemyAI.decide(archer, grid, players, &"novice")) == &"u_p_knight",
		"novice：worst → 低分 knight")
	_expect(_target_id(EnemyAI.decide(archer, grid, players, &"hard")) == &"u_p_knight",
		"hard：3.0×28=84 集火残血 knight")
	_expect(_target_id(EnemyAI.decide(archer, grid, players, &"nightmare")) == &"u_p_knight",
		"nightmare：8.0×28=224 集火残血 knight")

	# 局面 1b：knight 回满血 → focus 恒 0 → hard 回到 mage（证明 focus 仅残血生效）
	var units_b := _duel_setup()
	units_b[1][&"hp"] = 30
	var grid_b := _mk_grid(units_b)
	var players_b: Array = [units_b[1], units_b[2]]
	_expect(_target_id(EnemyAI.decide(units_b[0], grid_b, players_b, &"hard")) == &"u_p_mage",
		"满血时 hard 不集火 → mage")
	_expect(_target_id(EnemyAI.decide(units_b[0], grid_b, players_b, &"novice")) == &"u_p_knight",
		"满血时 novice worst 仍选最低分 knight")


# ============================================================
# 组 4：追击
# ============================================================

func _test_pursue() -> void:
	print("[4] 追击")
	# 9x9：敌方短手 knight_king (2,4) rng[1,1] mov1，玩家 mage_far (6,4) 距 4 够不着
	var king := _mk_unit(
		&"u_e_king", &"enemy", 2, 4, _wpn("lance", 5, 80, 0),
		{&"str": 1, &"def": 5, &"res": 5}, 30, [1, 1]
	)
	var far := _mk_unit(
		&"u_p_far", &"player", 6, 4, _wpn("anima", 5, 90, 0),
		{&"mag": 3, &"def": 1, &"res": 1}, 30, [1, 2]
	)
	var grid := _mk_grid([king, far], 9, 9)

	var d_normal: Dictionary = EnemyAI.decide(king, grid, [far], &"normal")
	_expect(d_normal[&"moveTarget"] != null, "normal：够不着也朝最近敌移动")
	var d_novice: Dictionary = EnemyAI.decide(king, grid, [far], &"novice")
	_expect(d_novice[&"moveTarget"] == null, "novice：原地待命（pursue=false）")


# ============================================================
# 组 5：击杀意识 + worst
# ============================================================

func _test_kill_preference() -> void:
	print("[5] 击杀意识")
	# sword_king (2,2) rng1：A=残血可杀 mage (2,1) def0；B=厚血 knight (2,3) def25
	var king := _mk_unit(
		&"u_e_sword", &"enemy", 2, 2, _wpn("sword", 5, 90, 0),
		{&"str": 12, &"skl": 10, &"spd": 10, &"luk": 10, &"def": 5, &"res": 5},
		30, [1, 1]
	)
	var frag := _mk_unit(
		&"u_p_frag", &"player", 2, 1, _wpn("anima", 5, 90, 0),
		{&"mag": 20, &"def": 0, &"res": 0}, 3, [1, 2]
	)
	var wall := _mk_unit(
		&"u_p_wall", &"player", 2, 3, _wpn("lance", 5, 80, 0),
		{&"str": 1, &"def": 25, &"res": 5}, 999, [1, 1]
	)
	var grid := _mk_grid([king, frag, wall])
	var ps: Array = [frag, wall]

	_expect(_target_id(EnemyAI.decide(king, grid, ps, &"normal")) == &"u_p_frag",
		"normal：击杀 5000 加分 → 收割残血 mage")
	_expect(_target_id(EnemyAI.decide(king, grid, ps, &"hard")) == &"u_p_frag",
		"hard：击杀 12000 → 收割")
	_expect(_target_id(EnemyAI.decide(king, grid, ps, &"nightmare")) == &"u_p_frag",
		"nightmare：击杀 20000 → 收割")
	_expect(_target_id(EnemyAI.decide(king, grid, ps, &"novice")) == &"u_p_wall",
		"novice：kill_bonus=0 → worst 选打不动的 knight")


# ============================================================
# 组 6：PlayerAI 托管路径
# ============================================================

func _test_player_ai_hosting() -> void:
	print("[6] PlayerAI 托管")
	# 玩家弓手做决策者，打敌方双目标（faction 反转的组3 局面）
	var units := _duel_setup()
	units[0][&"faction"] = &"player"
	units[1][&"faction"] = &"enemy"
	units[2][&"faction"] = &"enemy"
	var host: Dictionary = units[0]
	var foes: Array = [units[1], units[2]]
	var grid := _mk_grid(units)

	# auto 路径透传难度（等价 EnemyAI 同档）
	_expect(_target_id(PlayerAI.decide(host, grid, foes, {&"difficulty": &"nightmare"})) == &"u_p_knight",
		"auto+nightmare：透传 EnemyAI → 集火残血")
	_expect(_target_id(PlayerAI.decide(host, grid, foes, {&"difficulty": &"novice"})) == &"u_p_knight",
		"auto+novice：worst → 低分目标")

	# 非 auto 策略：weakest 本身偏残血，nightmare focus 叠加仍是残血
	_expect(_target_id(PlayerAI.decide(host, grid, foes, {&"strategy": &"weakest", &"difficulty": &"nightmare"})) == &"u_p_knight",
		"weakest+nightmare：focus 叠加 → 残血目标")
	# aggressive+novice：无击杀（均打不死）→ 都回 base 分，worst 选最低
	_expect(_target_id(PlayerAI.decide(host, grid, foes, {&"strategy": &"aggressive", &"difficulty": &"novice"})) == &"u_p_knight",
		"aggressive+novice：worst 选最低分目标")
	# 非 auto + normal：aggressive 无 kill → base → 高伤 mage
	_expect(_target_id(PlayerAI.decide(host, grid, foes, {&"strategy": &"aggressive"})) == &"u_p_mage",
		"aggressive+缺省难度：base 高分 mage")


# ============================================================
# 组 7：声明式场景 ai_pref.difficulty（runner 进程内 + loader 校验）
# ============================================================

func _nightmare_scenario() -> Dictionary:
	return {
		"version": 1,
		"id": "ai_diff_focus",
		"description": "敌方噩梦难度集火残血：archer 普攻残血 knight 分数 = base+72（focus 3.0×24）压过 powerSurge(38) 与高伤 swordsman",
		"inline": {
			"rows": [".....", ".....", ".....", ".....", "....."],
			"playerUnits": [
				{ "class": "knight", "name": "铁壁", "x": 0, "y": 2 },
				{ "class": "swordsman", "name": "剑士", "x": 4, "y": 2 }
			],
			"enemyUnits": [
				{ "class": "archer", "name": "猎手", "x": 2, "y": 2 }
			]
		},
		"seed": 5,
		"limits": { "max_turns": 8, "max_steps": 60 },
		"overrides": { "u_p_0": { "hp": 10 } },
		"factions": {
			"player": { "mode": "script", "script": [], "script_exhausted": "wait" },
			"enemy": { "mode": "ai", "ai_pref": { "difficulty": "nightmare" } }
		},
		"assertions": [
			{ "type": "battle_over", "op": "==", "value": true }
		]
	}


func _test_scenario_runner() -> void:
	print("[7] 声明式场景难度注入")
	# loader 校验：非法难度严格报错
	var bad: Dictionary = _nightmare_scenario()
	(bad["factions"]["enemy"]["ai_pref"])["difficulty"] = "insane"
	var r_bad: Dictionary = ScenarioLoader.load_from_dict(bad)
	_expect(not bool(r_bad.get("ok", false))
		and String(r_bad.get("error", "")).contains("difficulty"),
		"loader：非法 difficulty 报错（CLI 侧严格）")
	# loader 校验：ai_pref 未知键拒绝
	var bad2: Dictionary = _nightmare_scenario()
	bad2["factions"]["enemy"]["ai_pref"]["foo"] = 1
	var r_bad2: Dictionary = ScenarioLoader.load_from_dict(bad2)
	_expect(not bool(r_bad2.get("ok", false)), "loader：ai_pref 未知字段报错")

	# runner：nightmare 敌方首个攻击事件目标 = 残血 knight（u_p_0）
	var loaded: Dictionary = ScenarioLoader.load_from_dict(_nightmare_scenario())
	_expect(bool(loaded.get("ok", false)), "nightmare 场景加载成功")
	if not bool(loaded.get("ok", false)):
		return
	var run: Dictionary = Runner.run(loaded["scenario"])
	_expect(int(run["exit_code"]) == 0, "runner exit 0（%s）" % String(run["result"]["outcome"].get("error", "")))
	var first_target := ""
	var acted_type := ""
	for e in run["events"]:
		if String(e.get("actor", "")) == "u_e_0" and (e.get("type", "") == "attack" or e.get("type", "") == "skill"):
			acted_type = String(e.get("type", ""))
			first_target = String(e.get("target", e.get("hits", [{}])[0].get("unit", "") if e.get("type", "") == "skill" else ""))
			break
	_expect(first_target == "u_p_0",
		"nightmare 敌方首个攻击目标=残血 knight（事件类型 %s，目标 %s）" % [acted_type, first_target])


# ============================================================
# 组 8：CLI 子进程
# ============================================================

func _test_cli_subprocess() -> void:
	print("[8] CLI 子进程")
	# 直接跑 fixture（res:// 路径）；CLI 用户参数须以 -- 分隔（OS.get_cmdline_user_args）
	var exe := OS.get_executable_path()
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://").replace("\\", "/"),
		"--script", "res://tools/battle_cli.gd", "--",
		"--scenario", "res://tests/fixtures/battle_scenarios/ai_difficulty_focus.json", "--seed", "5"]
	var out: Array = []
	var code := OS.execute(exe, args, out)
	_expect(code == 0, "CLI 跑 nightmare fixture exit 0（得到 %d）" % code)


# ============================================================
# 组 9：确定性
# ============================================================

func _test_determinism() -> void:
	print("[9] 确定性")
	# 注意：UnitData 是引用共享——run 会 mutate hp/hasActed，双跑必须各自重新 load 重建
	var a: Dictionary = Runner.run(ScenarioLoader.load_from_dict(_nightmare_scenario())["scenario"])
	var b: Dictionary = Runner.run(ScenarioLoader.load_from_dict(_nightmare_scenario())["scenario"])
	_expect(JSON.stringify(a["events"]) == JSON.stringify(b["events"]),
		"nightmare 同 seed 双跑事件流一致")
	var other: Dictionary = _nightmare_scenario()
	other["seed"] = 6
	var run_c: Dictionary = Runner.run(ScenarioLoader.load_from_dict(other)["scenario"])
	# 不同 seed：决策本身无 RNG（目标选择不变），事件流仍完整产出
	_expect(int(run_c["exit_code"]) == 0 and not (run_c["events"] as Array).is_empty(),
		"seed6 同样 exit 0 且事件流非空（实际 exit %d）" % int(run_c["exit_code"]))


# ============================================================
# 组 10：类型安全（loader 严格 / Settings 宽容）
# ============================================================

func _test_type_safety() -> void:
	print("[10] 类型安全")
	# loader：difficulty 非字符串 → 明确报「必须是字符串」（不做 String() 转换）
	for bad_val in [123, true, {}]:
		var sc: Dictionary = _nightmare_scenario()
		sc["factions"]["enemy"]["ai_pref"]["difficulty"] = bad_val
		var r: Dictionary = ScenarioLoader.load_from_dict(sc)
		_expect(not bool(r.get("ok", false))
			and String(r.get("error", "")).contains("必须是字符串"),
			"loader：difficulty=%s 报「必须是字符串」" % typeof(bad_val))

	# Settings._clamp_difficulty：任意脏类型宽容回 normal（Node.new 不进树不触发 _ready）
	var SettingsScript := preload("res://scripts/settings.gd")
	var st2: Node = SettingsScript.new()
	for dirty in [123, true, {}, "insane"]:
		var got: String = st2._clamp_difficulty(dirty)
		_expect(got == "normal", "Settings 宽容：%s → normal" % typeof(dirty))
	_expect(st2._clamp_difficulty("hard") == "hard", "Settings 合法值 hard 保留")
	st2.free()


# ============================================================
# 组 11：优先目标语义（显式 priorityTargetId vs worst 档）
# ============================================================

func _test_priority_semantics() -> void:
	print("[11] 优先目标语义")
	# 组3 局面 faction 反转：玩家弓手 host，敌方 knight_t（低分残血）/mage_t（高分满血）
	var units := _duel_setup()
	units[0][&"faction"] = &"player"
	units[1][&"faction"] = &"enemy"
	units[2][&"faction"] = &"enemy"
	var host: Dictionary = units[0]
	var foes: Array = [units[1], units[2]]
	var grid := _mk_grid(units)

	# 对照：novice 无优先目标 → worst 选低分 knight
	_expect(_target_id(PlayerAI.decide(host, grid, foes, {&"difficulty": &"novice"})) == &"u_p_knight",
		"novice 无优先目标：worst → 低分 knight（对照）")
	# auto 路径 + 优先目标：限定目标列表（单目标无选择余地）
	_expect(_target_id(PlayerAI.decide(host, grid, foes,
		{&"strategy": &"auto", &"priorityTargetId": "u_p_mage"})) == &"u_p_mage",
		"auto+priority=mage：目标列表限定 → mage（即便 novice worst）")
	_expect(_target_id(PlayerAI.decide(host, grid, foes,
		{&"difficulty": &"novice", &"priorityTargetId": "u_p_mage"})) == &"u_p_mage",
		"无 strategy+priority=mage：auto 限定 → novice 也打 mage")
	# 非 auto + worst：反转加权推高非优先目标 → 优先目标胜出
	_expect(_target_id(PlayerAI.decide(host, grid, foes,
		{&"strategy": &"weakest", &"difficulty": &"novice", &"priorityTargetId": "u_p_mage"})) == &"u_p_mage",
		"weakest+novice+priority=mage：worst 反转加权 → mage 胜出")


# ============================================================
# 组 12：focus 集火统一（伤害技能/物品 vs 普攻）
# ============================================================

func _test_focus_unified() -> void:
	print("[12] focus 集火统一")
	var prof_hard: Dictionary = AIDifficulty.profile(&"hard")
	var caster := _mk_unit(
		&"u_e_magek", &"enemy", 2, 2, _wpn("anima", 5, 90, 0),
		{&"mag": 10, &"str": 1, &"skl": 1, &"spd": 1, &"luk": 1, &"def": 5, &"res": 5},
		30, [1, 2]
	)
	# hurt/full 同防（res5），火球对两者伤害相同（15），分数差 = 纯 focus；
	# hurt hp16：15 < 16 不触发击杀加分，missing=14
	var hurt := _mk_unit(&"u_p_hurt", &"player", 0, 2, _wpn("lance", 5, 80, 0),
		{&"str": 1, &"def": 5, &"res": 5}, 16, [1, 1])
	var full := _mk_unit(&"u_p_full", &"player", 4, 2, _wpn("lance", 5, 80, 0),
		{&"str": 1, &"def": 5, &"res": 5}, 30, [1, 1])

	var fireball: Dictionary = SkillData.get_skill(&"fireball")
	_expect(not fireball.is_empty(), "fireball 技能存在（懒加载）")
	var s_hurt: float = EnemyAI._score_skill(caster, fireball, [hurt], prof_hard)
	var s_full: float = EnemyAI._score_skill(caster, fireball, [full], prof_hard)
	_expect(absf(s_hurt - s_full - 14.0 * 3.0) < 0.001,
		"_score_skill：残血加分 = 14×3.0 = 42（差 %.1f）" % (s_hurt - s_full))

	var shuriken: Dictionary = ItemData.get_item(&"shuriken")
	_expect(not shuriken.is_empty(), "shuriken 物品存在（懒加载）")
	var i_hurt: float = EnemyAI._score_item(caster, shuriken, [hurt], prof_hard)
	var i_full: float = EnemyAI._score_item(caster, shuriken, [full], prof_hard)
	_expect(absf(i_hurt - i_full - 14.0 * 3.0) < 0.001,
		"_score_item：投掷伤害同样集火加分（差 %.1f）" % (i_hurt - i_full))

	# 行为级：damage 技能的 targets_for 是「射程内全部敌人」（组评分，非单目标选择），
	# 因此难度不改变技能 targets；行为断言锁定「技能候选不被系统性低估」：
	# 单敌 hurt=res5 hp16：普攻 10×2-反1=19，火球 15×2-3=27 → 两档都应放火球。
	# （修复前技能分无 focus：hard 下普攻 19+42=61 vs 技能 27，普攻反超 → 选普攻即缺陷）
	var king := _mk_unit(
		&"u_e_magek2", &"enemy", 2, 2, _wpn("anima", 5, 90, 0),
		{&"mag": 10, &"str": 1, &"skl": 1, &"spd": 1, &"luk": 1, &"def": 5, &"res": 5},
		30, [1, 2]
	)
	king[&"mp"] = 20
	king[&"skills"] = [&"fireball"]
	var units := [king, hurt]
	var grid := _mk_grid(units)
	var ps: Array = [hurt]
	var d_n: Dictionary = EnemyAI.decide(king, grid, ps, &"normal")
	var d_h: Dictionary = EnemyAI.decide(king, grid, ps, &"hard")
	var act_n: Dictionary = d_n.get(&"action", {})
	var act_h: Dictionary = d_h.get(&"action", {})
	_expect(String(act_n.get(&"type", &"")) == &"skill",
		"normal：火球 27 分 > 普攻 19 → 放技能")
	_expect(String(act_h.get(&"type", &"")) == &"skill",
		"hard：火球 27+42=69 > 普攻 19+42=61 → 仍放技能（focus 两边一致，不再低估技能）")


# ============================================================
# 组 13：非 auto 策略 fallback 追击（novice 不追）
# ============================================================

func _test_nonauto_fallback_pursue() -> void:
	print("[13] 非 auto fallback 追击")
	# 组4 局面 faction 反转：玩家 knight 够不着远处敌方 mage
	var king := _mk_unit(
		&"u_p_king", &"player", 2, 4, _wpn("lance", 5, 80, 0),
		{&"str": 1, &"def": 5, &"res": 5}, 30, [1, 1]
	)
	var far := _mk_unit(
		&"u_e_far", &"enemy", 6, 4, _wpn("anima", 5, 90, 0),
		{&"mag": 3, &"def": 1, &"res": 1}, 30, [1, 2]
	)
	var grid := _mk_grid([king, far], 9, 9)

	var d_nov: Dictionary = PlayerAI.decide(king, grid, [far],
		{&"strategy": &"aggressive", &"difficulty": &"novice"})
	_expect(d_nov[&"moveTarget"] == null,
		"aggressive+novice：够不着 → 原地待命（不追击）")
	var d_nrm: Dictionary = PlayerAI.decide(king, grid, [far],
		{&"strategy": &"aggressive", &"difficulty": &"normal"})
	_expect(d_nrm[&"moveTarget"] != null,
		"aggressive+normal：够不着 → 朝最近敌移动")


# ============================================================
# 组 14：优先目标约束技能/物品候选（穿透回归）
# ============================================================

## 决策者（玩家 mage 托管）：普攻 rng[1,2]、fireball(blizzard) rng[1,3]、shuriken rng[1,3]。
## 敌方 kf=优先目标（res5 hp16）、mf=诱饵（res0 hp30 满血，技能/普攻分更高）。
func _priority_host() -> Dictionary:
	var host := _mk_unit(
		&"u_p_host", &"player", 2, 2, _wpn("anima", 5, 90, 0),
		{&"mag": 10, &"str": 1, &"skl": 1, &"spd": 1, &"luk": 1, &"def": 5, &"res": 5},
		30, [1, 2]
	)
	host[&"mp"] = 30
	host[&"items"] = [{ &"id": &"shuriken", &"uses": 2 }]
	return host


func _test_priority_limits_skills() -> void:
	print("[14] 优先目标约束技能/物品")

	# --- 局面 A：单体技能收紧。kf(0,2)/mf(4,2) 距 host 均 2（都在 fireball rng[1,3]）。
	# 带 priority=kf：fireball（targetType=enemy 单体语义）目标集收紧为 [kf]（27 分）
	# 仍压过普攻 kf(19) 与 shuriken[kf](16)；修复前 targets 是射程内全集 [kf,mf]
	# 含 mf → 单体攻击越过优先目标。
	var host := _priority_host()
	host[&"skills"] = [&"fireball"]
	var kf := _mk_unit(&"u_e_kf", &"enemy", 0, 2, _wpn("lance", 5, 80, 0),
		{&"str": 1, &"def": 5, &"res": 5}, 16, [1, 1])
	var mf := _mk_unit(&"u_e_mf", &"enemy", 4, 2, _wpn("anima", 5, 90, 0),
		{&"mag": 20, &"def": 0, &"res": 0}, 30, [1, 2])
	var grid_a := _mk_grid([host, kf, mf])
	var d_a: Dictionary = PlayerAI.decide(host, grid_a, [kf, mf],
		{&"priorityTargetId": "u_e_kf"})
	var act_a: Dictionary = d_a.get(&"action", {})
	var tg_a: Array = act_a.get(&"targets", [])
	var has_mf := false
	for t in tg_a:
		if (t as Dictionary).get(&"id", &"") == &"u_e_mf":
			has_mf = true
	_expect(String(act_a.get(&"type", &"")) == &"skill"
		and tg_a.size() == 1
		and (tg_a[0] as Dictionary).get(&"id", &"") == &"u_e_kf"
		and not has_mf,
		"单体技能收紧：priority=kf → fireball 只打 kf（targets=%d，含 mf=%s）" % [tg_a.size(), has_mf])

	# --- 局面 B：AOE 覆盖优先目标可保留（波及 mf 允许）。
	# skills=[blizzard, fireball]：blizzard(aoe_enemy) 覆盖 kf+mf → 保留全集（分最高）。
	var host_b := _priority_host()
	host_b[&"skills"] = [&"fireball", &"blizzard"]
	var grid_b := _mk_grid([host_b, kf, mf])
	var d_b: Dictionary = PlayerAI.decide(host_b, grid_b, [kf, mf],
		{&"priorityTargetId": "u_e_kf"})
	var act_b: Dictionary = d_b.get(&"action", {})
	var tg_b: Array = act_b.get(&"targets", [])
	var has_kf_b := false
	for t in tg_b:
		if (t as Dictionary).get(&"id", &"") == &"u_e_kf":
			has_kf_b = true
	_expect(String(act_b.get(&"type", &"")) == &"skill"
		and StringName(act_b.get(&"skillId", &"")) == &"blizzard"
		and has_kf_b,
		"AOE 覆盖优先目标：blizzard 保留（含 kf，波及 mf 允许）")

	# --- 局面 C：AOE 完全不命中优先目标 → 候选全灭，不得绕开。
	# 7x7：host(3,3)、mf(0,3) 距 3（技能射程内）、kf(6,6) 距 9（一切攻击射程外）。
	# priority=kf：单体技能 ∩=空 丢弃；AOE 不含 kf 丢弃；普攻枚举 [kf] 超程 →
	# 无攻击候选 → fallback 朝 kf 移动。修复前 blizzard 会选中打 mf（完全绕开）。
	var host_c := _priority_host()
	host_c[&"skills"] = [&"fireball", &"blizzard"]
	var kf_c := _mk_unit(&"u_e_kf", &"enemy", 6, 6, _wpn("lance", 5, 80, 0),
		{&"str": 1, &"def": 5, &"res": 5}, 16, [1, 1])
	var mf_c := _mk_unit(&"u_e_mf", &"enemy", 0, 3, _wpn("anima", 5, 90, 0),
		{&"mag": 20, &"def": 0, &"res": 0}, 30, [1, 2])
	var grid_c := _mk_grid([host_c, mf_c, kf_c], 7, 7)
	var d_c: Dictionary = PlayerAI.decide(host_c, grid_c, [kf_c, mf_c],
		{&"priorityTargetId": "u_e_kf"})
	var act_c: Dictionary = d_c.get(&"action", {})
	_expect(d_c[&"attackTarget"].is_empty()
		and String(act_c.get(&"type", &"")) == &"normal"
		and d_c[&"moveTarget"] != null,
		"AOE/单体均够不到 kf：不绕打 mf，朝 kf 移动（attackTarget 空 + moveTarget 非 null）")
