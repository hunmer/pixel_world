## tests/backstab_save_roundtrip_contract.gd — 朝向存档往返 + 背击真实结算/预览一致契约
##
## 覆盖：
##   1. 朝向持久化：unit.facing(Vector2i) 经 battle_save_codec capture/restore 完整往返
##      （含显式 ZERO 与未设键的旧档单位）；带 facing 的 chapter 不破坏 validate_chapter。
##   2. 真实结算/预览一致：托管与敌方 AI 链路最终都走 BattleActionResolver，
##      resolver 结果（impacts 扣血/背击标记）与 CombatSystem.preview 同口径 ——
##      背面增幅、正面不增幅、反击按出手转身快照恒无增幅。
## 运行：godot --headless --path . --script res://tests/backstab_save_roundtrip_contract.gd
extends SceneTree

const Facing = preload("res://scripts/systems/facing_rules.gd")
const Combat = preload("res://scripts/systems/combat_system.gd")
const Grid = preload("res://scripts/systems/grid_system.gd")
const Resolver = preload("res://scripts/battle/battle_action_resolver.gd")
const Codec = preload("res://scripts/core/battle_save_codec.gd")
const Loader = preload("res://scripts/core/battlefield_loader.gd")

const SRC := "res://data/battlefields/plains_skirmish.json"

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok: %s" % message)
	else:
		failures += 1
		printerr("  FAIL: %s" % message)


## 与 backstab_contract 同款夹具，但 spd=0：_hit_chance 减 avoid=spd×1.5，
## spd=10 时 defHit=85 有 15% 随机 miss，契约会随机挂 —— 置 0 后双方恒命中；
## spd 相等不触发追击，伤害公式不含 spd，数值口径不变。
func _unit(id: StringName, faction: StringName, cell: Vector2i, weapon_type: StringName = &"sword") -> Dictionary:
	return {
		&"id": id, &"name": String(id), &"classId": &"swordsman", &"faction": faction,
		&"position": cell, &"hp": 100, &"mp": 30, &"isDead": false,
		&"stats": { &"hp": 100, &"mp": 30, &"str": 20, &"mag": 20, &"skl": 0,
			&"spd": 0, &"luk": 0, &"def": 0, &"res": 0, &"mov": 5 },
		&"weapon": { &"type": weapon_type, &"hit": 100, &"might": 5, &"weight": 1, &"crit": 0 },
		&"attackRange": [1, 1], &"moveType": &"infantry", &"buffs": [],
		&"skills": [], &"skillCooldowns": {}, &"items": [], &"weaknesses": [],
		&"exp": 0, &"level": 1, &"growths": {},
	}


func _run() -> void:
	print("== backstab_save_roundtrip_contract ==")
	_test_facing_roundtrip()
	_test_settlement_matches_preview()
	_finish()


# ------------------------------------------------------------------
# 1. 朝向存档往返（真实战场 chapter 快照）
# ------------------------------------------------------------------
func _test_facing_roundtrip() -> void:
	print(" [1] 朝向存档往返")
	var loaded: Dictionary = Loader.load_battlefield(SRC)
	if not bool(loaded.get("ok", false)):
		_expect(false, "plains_skirmish 加载失败: %s" % String(loaded.get("error", "")))
		return
	var chapter: Dictionary = (loaded["chapter"] as Dictionary).duplicate(true)

	# 注入有代表性的朝向：正向 / 反向 / 显式 ZERO（无朝向语义也必须原样保留）；
	# 其余单位不设键（旧档形状，往返后不得被注入 facing 键）。
	var players: Array = chapter["playerUnits"]
	var enemies: Array = chapter["enemyUnits"]
	(players[0] as Dictionary)[&"facing"] = Vector2i(1, 0)
	(enemies[0] as Dictionary)[&"facing"] = Vector2i(-1, 0)
	if enemies.size() > 1:
		(enemies[1] as Dictionary)[&"facing"] = Vector2i.ZERO

	# 带 facing 的 chapter 不得破坏校验（未知键不参与 validate）。
	_expect(Codec.validate_chapter(chapter) == "",
		"注入 facing 后 validate_chapter 应通过，实际: %s" % Codec.validate_chapter(chapter))

	var state := { "turn_number": 2, "phase": &"player", "hosting": false,
		"prefs": {}, "result": &"" }
	var cap: Dictionary = Codec.capture("bf:res/plains_skirmish", "battlefield",
		SRC, chapter, chapter, state, "sig-1")
	if not bool(cap.get("ok", false)):
		_expect(false, "capture 失败: %s" % String(cap.get("error", "")))
		return
	var rr: Dictionary = Codec.restore(cap["record"])
	if not bool(rr.get("ok", false)):
		_expect(false, "restore 失败: %s" % String(rr.get("error", "")))
		return
	var rt_players: Array = rr["chapter"]["playerUnits"]
	var rt_enemies: Array = rr["chapter"]["enemyUnits"]

	_expect((rt_players[0] as Dictionary).get(&"facing", Vector2i(9, 9)) == Vector2i(1, 0),
		"player[0] facing (1,0) 往返一致")
	_expect((rt_enemies[0] as Dictionary).get(&"facing", Vector2i(9, 9)) == Vector2i(-1, 0),
		"enemy[0] facing (-1,0) 往返一致")
	if enemies.size() > 1:
		_expect((rt_enemies[1] as Dictionary).get(&"facing", Vector2i(9, 9)) == Vector2i.ZERO,
			"enemy[1] 显式 ZERO 往返保留（无朝向语义）")
	# 未设键单位不得被注入 facing（旧档读档后 get_facing 走缺省路径）。
	var injected := 0
	for u in rt_players.slice(1):
		if (u as Dictionary).has(&"facing"):
			injected += 1
	for u in rt_enemies.slice(2 if enemies.size() > 1 else 1):
		if (u as Dictionary).has(&"facing"):
			injected += 1
	_expect(injected == 0, "未设 facing 键的单位往返后不被注入（实际注入 %d 个）" % injected)
	# 往返后的单位直接可用作背击判定输入（Vector2i 类型还原而非 dict）。
	_expect(Facing.get_facing(rt_players[0]) == Vector2i(1, 0),
		"往返后 get_facing 还原为 Vector2i(1,0)")


# ------------------------------------------------------------------
# 2. 背击真实结算/预览一致（托管与敌方 AI 的公共出口 = resolver）
# ------------------------------------------------------------------
func _test_settlement_matches_preview() -> void:
	print(" [2] 真实结算/预览一致")
	# 背面：defender(3,0) 面朝 -x，attacker 在 (4,0)（其 +x 侧）→ 背击。
	var atk := _unit(&"atk", &"player", Vector2i(4, 0))
	var def := _unit(&"def", &"enemy", Vector2i(3, 0))
	atk[&"facing"] = Vector2i(-1, 0)
	def[&"facing"] = Vector2i(-1, 0)
	var grid: GridSystem = Grid.new(6, 6, _walkable_terrain(6, 6))
	grid.place_unit(atk, 4, 0)
	grid.place_unit(def, 3, 0)

	var pv: Dictionary = Combat.preview(atk, def, 0, 0)
	_expect(bool(pv[&"atkBackstab"]), "背面 preview.atkBackstab=true")
	_expect(int(pv[&"atkDmg"]) == 31, "背面 preview.atkDmg=31（25×1.25 取整）")
	_expect(int(pv[&"defDmg"]) == 25, "背面 preview.defDmg=25（反击按转身快照，无增幅）")

	var hp_before := int(def[&"hp"])
	var resolved: Dictionary = Resolver.resolve_attack(atk, def, grid)
	var combat: Dictionary = resolved["combat"]
	# execute 返回裸结果 + attack_event（含逐次 impacts，演出层直接消费）。
	_expect(int(combat[&"attackerDamage"]) == int(pv[&"atkDmg"]),
		"结算 attackerDamage %d == preview.atkDmg %d" % [int(combat[&"attackerDamage"]), int(pv[&"atkDmg"])])
	_expect(int(combat[&"defenderDamage"]) == int(pv[&"defDmg"]),
		"结算 defenderDamage %d == preview.defDmg %d" % [int(combat[&"defenderDamage"]), int(pv[&"defDmg"])])
	_expect(int(def[&"hp"]) == hp_before - int(pv[&"atkDmg"]),
		"defender 实际 hp=%d 与预览扣血一致" % int(def[&"hp"]))
	var impacts: Array = (combat[&"attack_event"] as Dictionary).get(&"impacts", [])
	_expect(impacts.size() >= 2, "攻击+反击应产生 2 个 impact（实际 %d）" % impacts.size())
	if impacts.size() >= 2:
		var first: Dictionary = impacts[0]
		var counter: Dictionary = impacts[1]
		_expect(int(first[&"damage"]) == int(pv[&"atkDmg"]),
			"impact 第一击伤害与 preview.atkDmg 一致（%d）" % int(first[&"damage"]))
		_expect(bool(first.get(&"backstab", false)), "结算第一击 impact.backstab=true")
		# 反击：resolver 出手转身（attacker 面向 defender）→ 反击恒打正面。
		_expect(int(counter[&"damage"]) == int(pv[&"defDmg"]),
			"反击伤害 %d == preview.defDmg %d" % [int(counter[&"damage"]), int(pv[&"defDmg"])])
		_expect(not bool(counter.get(&"backstab", false)), "反击 impact.backstab=false（转身口径）")
	_expect(Facing.get_facing(atk) == Vector2i(-1, 0), "出手转身后面向防守方")

	# 正面：defender 面朝 +x 迎战 → 不增幅，结算与预览同为 25。
	var atk2 := _unit(&"atk2", &"player", Vector2i(4, 2))
	var def2 := _unit(&"def2", &"enemy", Vector2i(3, 2))
	atk2[&"facing"] = Vector2i(-1, 0)
	def2[&"facing"] = Vector2i(1, 0)
	var grid2: GridSystem = Grid.new(6, 6, _walkable_terrain(6, 6))
	grid2.place_unit(atk2, 4, 2)
	grid2.place_unit(def2, 3, 2)
	var pv2: Dictionary = Combat.preview(atk2, def2, 0, 0)
	_expect(not bool(pv2[&"atkBackstab"]), "正面 preview.atkBackstab=false")
	_expect(int(pv2[&"atkDmg"]) == 25, "正面 preview.atkDmg=25（无增幅）")
	var resolved2: Dictionary = Resolver.resolve_attack(atk2, def2, grid2)
	var combat2: Dictionary = resolved2["combat"]
	var impacts2: Array = (combat2[&"attack_event"] as Dictionary).get(&"impacts", [])
	_expect(int(combat2[&"attackerDamage"]) == 25, "正面结算 attackerDamage=25（与预览一致）")
	_expect(int(def2[&"hp"]) == 100 - 25, "正面扣血 25 与预览一致")
	if not impacts2.is_empty():
		var first2: Dictionary = impacts2[0]
		_expect(not bool(first2.get(&"backstab", false)),
			"正面结算第一击 backstab=false（与预览一致）")
	else:
		_expect(false, "正面结算应产生 impact")


func _walkable_terrain(w: int, h: int) -> Array:
	var rows: Array = []
	for y in h:
		var row: Array = []
		for x in w:
			row.append(&"plain")
		rows.append(row)
	return rows


func _finish() -> void:
	if failures == 0:
		print("BACKSTAB_SAVE_ROUNDTRIP_CONTRACT_OK")
	else:
		printerr("backstab_save_roundtrip 契约失败 %d 项" % failures)
	quit(1 if failures > 0 else 0)
