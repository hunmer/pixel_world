## tests/pincer_contract.gd — 夹击追击（对侧相邻友军半强度追击）判定与结算契约
##
## 覆盖：
##   1. PincerRules.opposite_cell：正交攻击线对侧格（近战/远程/竖直），斜向/同格 NO_CELL
##   2. PincerRules.is_physical_weapon：物理/魔法武器口径（与 CombatSystem._weapon_element 一致）
##   3. PincerRules.pincer_partner：对侧友军命中 / 空池 / 敌军 / 已死友军 / 斜向线
##   4. CombatSystem.pincer_damage：基础 ×0.5 roundi、追击友军背击增幅、地形防御、钳 0
##   5. CombatSystem.preview 尾参 allies：触发/缺省恒 inactive/魔法攻击者/与结算同公式
##   6. resolver.resolve_attack：触发链路（伤害/impact 标志/顶层聚合/友军转身/不耗行动/不递归）
##   7. 不触发：主攻未命中 / 主攻击杀 / 魔法攻击者 / 对侧敌军 / 对侧友军已死 / 斜向攻击线
##   8. 攻击者被反击致死不阻止追击
##   9. 双击整场只追一次
##  10. 追击致死：deaths/defenderDied/经验/掉落统一管线
##  11. resolver.resolve_skill：物理伤害技能触发；grid=null 不触发；heal/魔法技能/技能 miss 不触发
##  12. resolver.resolve_item：物品投掷不触发（无追击路径）
extends SceneTree

const Pincer = preload("res://scripts/systems/pincer_rules.gd")
const Combat = preload("res://scripts/systems/combat_system.gd")
const Skills = preload("res://scripts/systems/skill_system.gd")
const Items = preload("res://scripts/systems/item_system.gd")
const AttackEventScript = preload("res://scripts/systems/attack_event.gd")
const Facing = preload("res://scripts/systems/facing_rules.gd")
const Grid = preload("res://scripts/systems/grid_system.gd")
const Resolver = preload("res://scripts/battle/battle_action_resolver.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok: %s" % message)
	else:
		failures += 1
		printerr("  FAIL: %s" % message)


## 与 backstab_contract 同款夹具：weapon hit=100 必中、crit=0 必不暴击、
## spd 双方 10 无双击；str20+might5−def0 = 普攻 25，追击 25×0.5 = roundi(12.5) = 13。
func _unit(id: StringName, faction: StringName, cell: Vector2i, weapon_type: StringName = &"sword") -> Dictionary:
	return {
		&"id": id, &"name": String(id), &"classId": &"swordsman", &"faction": faction,
		&"position": cell, &"hp": 100, &"mp": 30, &"isDead": false,
		&"stats": { &"hp": 100, &"mp": 30, &"str": 20, &"mag": 20, &"skl": 0,
			&"spd": 10, &"luk": 0, &"def": 0, &"res": 0, &"mov": 5 },
		&"weapon": { &"type": weapon_type, &"hit": 100, &"might": 5, &"weight": 1, &"crit": 0 },
		&"attackRange": [1, 1], &"moveType": &"infantry", &"buffs": [],
		&"skills": [], &"skillCooldowns": {}, &"items": [], &"weaknesses": [],
		&"exp": 0, &"level": 1, &"growths": {},
	}


## 标准夹击三件套：A(player,1,0) — T(enemy,2,0) — F(player,3,0)，全 walkable 网格。
## T 用 staff（不反击），断言干净；facing 由用例按需注入。
func _pincer_fixture() -> Array:
	var grid: GridSystem = Grid.new(5, 3, _walkable_terrain(5, 3))
	var a := _unit(&"A", &"player", Vector2i(1, 0))
	var t := _unit(&"T", &"enemy", Vector2i(2, 0), &"staff")
	var f := _unit(&"F", &"player", Vector2i(3, 0))
	grid.place_unit(a, 1, 0)
	grid.place_unit(t, 2, 0)
	grid.place_unit(f, 3, 0)
	return [grid, a, t, f]


func _run() -> void:
	print("== pincer_contract ==")

	# ---------- 1. opposite_cell 几何 ----------
	print(" [1] PincerRules.opposite_cell")
	_expect(Pincer.opposite_cell(Vector2i(1, 0), Vector2i(2, 0)) == Vector2i(3, 0), "近战攻击线对侧 = T+signi(T−A)")
	_expect(Pincer.opposite_cell(Vector2i(0, 0), Vector2i(2, 0)) == Vector2i(3, 0), "远程距 2 对侧取目标相邻格（非等距镜像）")
	_expect(Pincer.opposite_cell(Vector2i(0, 0), Vector2i(0, 3)) == Vector2i(0, 4), "竖直攻击线对侧 (0,4)")
	_expect(Pincer.opposite_cell(Vector2i(0, 0), Vector2i(1, 1)) == Pincer.NO_CELL, "斜向攻击线无对侧 → NO_CELL")
	_expect(Pincer.opposite_cell(Vector2i(2, 0), Vector2i(2, 0)) == Pincer.NO_CELL, "同格无对侧 → NO_CELL")

	# ---------- 2. is_physical_weapon ----------
	print(" [2] PincerRules.is_physical_weapon")
	var w_sword := _unit(&"w1", &"player", Vector2i.ZERO)
	_expect(Pincer.is_physical_weapon(w_sword), "sword 物理")
	_expect(Pincer.is_physical_weapon(_unit(&"w2", &"player", Vector2i.ZERO, &"bow")), "bow 物理")
	_expect(not Pincer.is_physical_weapon(_unit(&"w3", &"player", Vector2i.ZERO, &"anima")), "anima 魔法不触发")
	_expect(not Pincer.is_physical_weapon(_unit(&"w4", &"player", Vector2i.ZERO, &"dark")), "dark 魔法不触发")
	_expect(not Pincer.is_physical_weapon(_unit(&"w5", &"player", Vector2i.ZERO, &"staff")), "staff 治疗杖不触发")

	# ---------- 3. pincer_partner ----------
	print(" [3] PincerRules.pincer_partner")
	var fixture := _pincer_fixture()
	var grid: GridSystem = fixture[0]
	var a: Dictionary = fixture[1]
	var t: Dictionary = fixture[2]
	var f: Dictionary = fixture[3]
	var allies: Array = grid.units.values()
	var found: Dictionary = Pincer.pincer_partner(a, t, allies)
	_expect(StringName(found.get(&"id", &"")) == &"F", "对侧格友军 F 命中")
	_expect(Pincer.pincer_partner(a, t, [a, t]).is_empty(), "池中无对侧单位 → {}")
	var enemy_behind := _unit(&"E", &"enemy", Vector2i(3, 0))
	_expect(Pincer.pincer_partner(a, t, [a, t, enemy_behind]).is_empty(), "对侧是敌军 → {}")
	var dead_f := f.duplicate(true)
	dead_f[&"isDead"] = true
	_expect(Pincer.pincer_partner(a, t, [a, t, dead_f]).is_empty(), "对侧友军 isDead → {}")
	var zero_f := f.duplicate(true)
	zero_f[&"hp"] = 0
	_expect(Pincer.pincer_partner(a, t, [a, t, zero_f]).is_empty(), "对侧友军 hp=0 → {}")
	var diag_a := _unit(&"dA", &"player", Vector2i(0, 0))
	var diag_t := _unit(&"dT", &"enemy", Vector2i(1, 1))
	var diag_f := _unit(&"dF", &"player", Vector2i(2, 2))
	_expect(Pincer.pincer_partner(diag_a, diag_t, [diag_a, diag_t, diag_f]).is_empty(), "斜向攻击线（即使对侧镜像有友军）→ {}")

	# ---------- 4. pincer_damage ----------
	print(" [4] CombatSystem.pincer_damage")
	_expect(Pincer.DAMAGE_RATIO == 0.5, "倍率常量 0.5（可配置单点）")
	_expect(Combat.pincer_damage(f, t, 0) == 13, "基础 25×0.5 → 13（roundi 12.5）")
	t[&"facing"] = Vector2i(-1, 0)  # T 背对 F（面朝 A 侧）
	_expect(Combat.pincer_damage(f, t, 0) == 16, "追击友军背击 (25×1.25=31)×0.5 → 16")
	t.erase(&"facing")
	_expect(Combat.pincer_damage(f, t, 10) == 8, "地形防御 10：(25−10)×0.5 → 8（roundi 7.5）")
	var weak_f := f.duplicate(true)
	weak_f[&"stats"] = f[&"stats"].duplicate(true)
	weak_f[&"stats"][&"str"] = 0
	weak_f[&"weapon"] = (f[&"weapon"] as Dictionary).duplicate(true)
	weak_f[&"weapon"][&"might"] = 0
	_expect(Combat.pincer_damage(weak_f, t, 0) == 0, "零攻追击钳 0（不产生负伤害）")

	# ---------- 5. preview 尾参 ----------
	print(" [5] CombatSystem.preview 尾参 allies")
	var pv_pin: Dictionary = Combat.preview(a, t, 0, 0, allies)
	_expect(bool(pv_pin[&"pincer"][&"active"]), "preview 标记 pincer.active")
	_expect(StringName(pv_pin[&"pincer"][&"partner_id"]) == &"F", "preview pincer.partner_id = F")
	_expect(int(pv_pin[&"pincer"][&"damage"]) == 13, "preview pincer.damage = 13（与 pincer_damage 同式）")
	var pv_default: Dictionary = Combat.preview(a, t, 0, 0)
	_expect(not bool(pv_default[&"pincer"][&"active"]), "缺省 allies 恒 inactive（旧调用兼容）")
	var magic_a := _unit(&"M", &"player", Vector2i(1, 0), &"anima")
	_expect(not bool(Combat.preview(magic_a, t, 0, 0, allies)[&"pincer"][&"active"]), "魔法攻击者 preview 不触发")

	# ---------- 6. resolve_attack 触发链路 ----------
	print(" [6] resolver.resolve_attack 追击结算")
	seed(731)
	var outcome: Dictionary = Resolver.resolve_attack(a, t, grid)
	var combat: Dictionary = outcome[&"combat"]
	var pc: Dictionary = combat[&"pincer"]
	_expect(bool(pc[&"active"]), "result.pincer.active")
	_expect(StringName(pc[&"partner_id"]) == &"F", "result.pincer.partner_id = F")
	_expect(int(pc[&"damage"]) == 13, "result.pincer.damage = 13")
	_expect(int(t[&"hp"]) == 62, "T.hp = 100−25(主攻)−13(追击) = 62")
	_expect(int(a[&"hp"]) == 100, "追击方 A 不掉血（T 用 staff 无反击）")
	_expect(Facing.get_facing(f) == Vector2i(-1, 0), "追击友军 F 转身面向 T")
	_expect(not bool(f.get(&"hasActed", false)) and not bool(f.get(&"hasMoved", false)), "追击不消耗 F 行动（hasActed/hasMoved 不动）")
	var impacts: Array = combat[&"attack_event"][&"impacts"]
	var last_impact: Dictionary = impacts[impacts.size() - 1]
	_expect(bool(last_impact.get(&"pincer", false)), "末位 impact 带 pincer=true 标志")
	_expect(StringName(last_impact[&"source_id"]) == &"F", "追击 impact.source_id = F（演出按此定位）")
	_expect(int(last_impact[&"hp_after"]) == 62, "追击 impact.hp_after = 62")
	var pincer_count := 0
	for raw in impacts:
		if bool((raw as Dictionary).get(&"pincer", false)):
			pincer_count += 1
	_expect(pincer_count == 1, "整场恰 1 次追击 impact（不递归、双击不重复）")
	var event: Dictionary = combat[&"attack_event"]
	_expect(bool(event.get(&"pincer", false)) and StringName(event.get(&"pincer_id", &"")) == &"F", "顶层 event.pincer/pincer_id 聚合")

	# ---------- 7. 不触发条件 ----------
	print(" [7] 不触发条件")
	# 7a. 主攻未命中（weapon hit=0 → atkHit=0）
	var fx_miss := _pincer_fixture()
	var miss_outcome: Dictionary = Resolver.resolve_attack(
		_make_hitter_zero(fx_miss[1]), fx_miss[2], fx_miss[0])
	_expect(not bool(miss_outcome[&"combat"][&"pincer"][&"active"]), "主攻 MISS 不追击")
	_expect(int((fx_miss[2] as Dictionary)[&"hp"]) == 100, "MISS 场景 T.hp 不变")
	# 7b. 主攻击杀（T.hp=25 恰被主攻 25 击杀；staff 无反击无双击）
	var fx_kill := _pincer_fixture()
	(fx_kill[2] as Dictionary)[&"hp"] = 25
	var kill_outcome: Dictionary = Resolver.resolve_attack(fx_kill[1], fx_kill[2], fx_kill[0])
	_expect(bool(kill_outcome[&"combat"][&"defenderDied"]), "主攻一击致死 defenderDied")
	_expect(not bool(kill_outcome[&"combat"][&"pincer"][&"active"]), "主攻击杀不追击（尸体不挨打）")
	# 7c. 魔法攻击者（anima 普攻 25；T staff 无反击）
	var fx_magic := _pincer_fixture()
	var magic_attacker := _unit(&"MA", &"player", Vector2i(1, 0), &"anima")
	(fx_magic[0] as GridSystem).place_unit(magic_attacker, 1, 0)
	var magic_outcome: Dictionary = Resolver.resolve_attack(magic_attacker, fx_magic[2], fx_magic[0])
	_expect(not bool(magic_outcome[&"combat"][&"pincer"][&"active"]), "魔法普攻不触发追击")
	_expect(int((fx_magic[2] as Dictionary)[&"hp"]) == 75, "魔法场景 T 只掉主攻 25")
	# 7d. 对侧是敌军
	var fx_foe := _pincer_fixture()
	var foe := _unit(&"EF", &"enemy", Vector2i(3, 0))
	(fx_foe[0] as GridSystem).remove_unit(fx_foe[3])
	(fx_foe[0] as GridSystem).place_unit(foe, 3, 0)
	var foe_outcome: Dictionary = Resolver.resolve_attack(fx_foe[1], fx_foe[2], fx_foe[0])
	_expect(not bool(foe_outcome[&"combat"][&"pincer"][&"active"]), "对侧是敌军不触发")
	# 7e. 对侧友军已死（isDead 但仍占格）
	var fx_dead := _pincer_fixture()
	(fx_dead[3] as Dictionary)[&"isDead"] = true
	var dead_outcome: Dictionary = Resolver.resolve_attack(fx_dead[1], fx_dead[2], fx_dead[0])
	_expect(not bool(dead_outcome[&"combat"][&"pincer"][&"active"]), "对侧友军 isDead 不触发")
	_expect(int((fx_dead[2] as Dictionary)[&"hp"]) == 75, "死亡友军场景 T 只掉主攻 25")
	# 7f. 斜向攻击线（A(0,0)→T(1,1)，镜像位 (2,2) 有友军也不触发）
	var diag_grid: GridSystem = Grid.new(4, 4, _walkable_terrain(4, 4))
	var diag_a2 := _unit(&"da", &"player", Vector2i(0, 0))
	var diag_t2 := _unit(&"dt", &"enemy", Vector2i(1, 1), &"staff")
	var diag_f2 := _unit(&"df", &"player", Vector2i(2, 2))
	diag_grid.place_unit(diag_a2, 0, 0)
	diag_grid.place_unit(diag_t2, 1, 1)
	diag_grid.place_unit(diag_f2, 2, 2)
	var diag_outcome: Dictionary = Resolver.resolve_attack(diag_a2, diag_t2, diag_grid)
	_expect(not bool(diag_outcome[&"combat"][&"pincer"][&"active"]), "斜向攻击线不触发（无对侧概念）")
	_expect(int(diag_t2[&"hp"]) == 75, "斜向场景 T 只掉主攻 25")

	# ---------- 8. 攻击者被反杀不阻止 ----------
	print(" [8] 攻击者被反击致死仍追击")
	var fx_rev := _pincer_fixture()
	var rev_a: Dictionary = fx_rev[1]
	var rev_t: Dictionary = fx_rev[2]
	rev_t[&"weapon"] = { &"type": &"sword", &"hit": 100, &"might": 95, &"weight": 1, &"crit": 0 }
	rev_t[&"stats"] = (rev_t[&"stats"] as Dictionary).duplicate(true)
	rev_t[&"stats"][&"skl"] = 20  # 反击命中 100（100+30−15 clamp）
	seed(733)
	var rev_outcome: Dictionary = Resolver.resolve_attack(rev_a, rev_t, fx_rev[0])
	_expect(bool(rev_outcome[&"combat"][&"attackerDied"]), "A 被反击致死（115 ≥ 100）")
	_expect(bool(rev_outcome[&"combat"][&"pincer"][&"active"]), "攻击者阵亡不阻止追击")
	_expect(int(rev_t[&"hp"]) == 62, "反杀场景 T 仍掉 25+13 = 62 剩余")
	_expect(bool(rev_a[&"isDead"]), "A isDead 已置位")

	# ---------- 9. 双击只追一次 ----------
	print(" [9] 双击整场只追一次")
	var fx_dbl := _pincer_fixture()
	var dbl_a: Dictionary = fx_dbl[1]
	dbl_a[&"stats"] = (dbl_a[&"stats"] as Dictionary).duplicate(true)
	dbl_a[&"stats"][&"spd"] = 14  # aspd 差 4 → 双击
	seed(734)
	var dbl_outcome: Dictionary = Resolver.resolve_attack(dbl_a, fx_dbl[2], fx_dbl[0])
	_expect(bool(dbl_outcome[&"combat"][&"isDoubleAttack"]), "确认双击发生")
	_expect(int((fx_dbl[2] as Dictionary)[&"hp"]) == 37, "双击 50 + 追击 13 → T.hp 37")
	_expect(int(dbl_outcome[&"combat"][&"pincer"][&"damage"]) == 13, "双击场景追击仍一次 13")
	var dbl_impacts: Array = dbl_outcome[&"combat"][&"attack_event"][&"impacts"]
	_expect(dbl_impacts.size() == 3, "双击场景 impacts = 击1+击2+追击 共 3 个")

	# ---------- 10. 追击致死 ----------
	print(" [10] 追击致死统一管线")
	var fx_death := _pincer_fixture()
	var death_t: Dictionary = fx_death[2]
	death_t[&"hp"] = 30
	death_t[&"drop_table"] = [{ "id": "ironOre", "count": 1, "weight": 1.0 }]
	var loot: Array = []
	var rolled: Dictionary = {}
	var loot_rng := RandomNumberGenerator.new()
	loot_rng.seed = 42
	seed(735)
	var death_outcome: Dictionary = Resolver.resolve_attack(
		fx_death[1], death_t, fx_death[0], { rng = loot_rng, loot = loot, rolled = rolled })
	var dpc: Dictionary = death_outcome[&"combat"][&"pincer"]
	_expect(bool(dpc[&"active"]) and bool(dpc[&"died"]), "追击致死 pincer.died=true")
	_expect(bool(death_t[&"isDead"]), "追击致死 isDead 置位")
	_expect((death_outcome[&"deaths"] as Array).has(death_t), "追击致死进 deaths（胜负/移除走统一管线）")
	_expect(bool(death_outcome[&"combat"][&"defenderDied"]), "普攻路径追击致死置 defenderDied（攻击方拿击杀经验）")
	_expect(bool(death_outcome[&"exp"][&"gained"]) and int(death_outcome[&"exp"][&"amount"]) > 0, "追击致死攻击方获击杀经验")
	_expect(loot.size() == 1 and String((loot[0] as Dictionary)["id"]) == "ironOre", "追击致死掉落走 _settle_drop_loot")
	_expect(rolled.has(&"T"), "掉落幂等表记录 T")

	# ---------- 11. resolve_skill 技能路径 ----------
	print(" [11] resolver.resolve_skill 技能路径")
	# 11a. 物理伤害技能 smite（power 8）：T.spd=0 → 技能命中 100 必中
	var fx_sk := _pincer_fixture()
	var sk_c: Dictionary = fx_sk[1]
	var sk_t: Dictionary = fx_sk[2]
	sk_t[&"stats"] = (sk_t[&"stats"] as Dictionary).duplicate(true)
	sk_t[&"stats"][&"spd"] = 0
	sk_c[&"mp"] = 30
	seed(736)
	var sk_outcome: Dictionary = Resolver.resolve_skill(sk_c, [sk_t], &"smite", {}, fx_sk[0])
	var sk_res: Dictionary = sk_outcome[&"skill"]
	_expect(bool(sk_res[&"pincer"][&"active"]), "物理伤害技能触发追击")
	_expect(int(sk_t[&"hp"]) == 59, "smite 28 + 追击 13 → T.hp 59")
	_expect(int(sk_res[&"pincer"][&"damage"]) == 13, "技能路径追击伤害 13（同公式）")
	var sk_impacts: Array = sk_res[&"attack_event"][&"impacts"]
	_expect(bool((sk_impacts[sk_impacts.size() - 1] as Dictionary).get(&"pincer", false)), "技能事件末位 impact 带 pincer 标志")
	_expect(bool((sk_res[&"attack_event"] as Dictionary).get(&"pincer", false)), "技能事件顶层聚合 pincer")
	# 11b. grid=null（旧调用）不触发
	var fx_nogrid := _pincer_fixture()
	var ng_t: Dictionary = fx_nogrid[2]
	ng_t[&"stats"] = (ng_t[&"stats"] as Dictionary).duplicate(true)
	ng_t[&"stats"][&"spd"] = 0
	(fx_nogrid[1] as Dictionary)[&"mp"] = 30
	seed(736)
	var ng_outcome: Dictionary = Resolver.resolve_skill(fx_nogrid[1], [ng_t], &"smite", {})
	_expect(int(ng_t[&"hp"]) == 72, "grid 缺省只掉技能 28（追击不触发，旧调用兼容）")
	_expect(not bool((ng_outcome[&"skill"] as Dictionary).get(&"pincer", { &"active": false }).get(&"active", false)), "grid=null result 无追击")
	# 11c. 治疗技能不触发（type 分支）
	var fx_heal := _pincer_fixture()
	var healer := _unit(&"H", &"player", Vector2i(4, 1), &"staff")
	(fx_heal[0] as GridSystem).place_unit(healer, 4, 1)
	var heal_f: Dictionary = fx_heal[3]
	heal_f[&"hp"] = 50
	var heal_outcome: Dictionary = Resolver.resolve_skill(healer, [heal_f], &"heal", {}, fx_heal[0])
	_expect(int(heal_f[&"hp"]) == 75, "治疗 +25 正常落地")
	_expect(not bool((heal_outcome[&"skill"] as Dictionary).get(&"pincer", { &"active": false }).get(&"active", false)), "治疗技能不触发追击")
	# 11d. 魔法伤害技能（fireball, element=fire）不触发
	var fx_fb := _pincer_fixture()
	var fb_c := _unit(&"FB", &"player", Vector2i(1, 0), &"anima")
	var fb_t: Dictionary = fx_fb[2]
	fb_t[&"stats"] = (fb_t[&"stats"] as Dictionary).duplicate(true)
	fb_t[&"stats"][&"spd"] = 0
	(fx_fb[0] as GridSystem).place_unit(fb_c, 1, 0)
	seed(737)
	var fb_outcome: Dictionary = Resolver.resolve_skill(fb_c, [fb_t], &"fireball", {}, fx_fb[0])
	_expect(int(fb_t[&"hp"]) == 70, "火球 30 正常落地（30=res 公式无追击加成）")
	_expect(not bool(fb_outcome[&"skill"].get(&"pincer", { &"active": false }).get(&"active", false)), "魔法伤害技能不触发追击")
	# 11e. 物理技能 MISS 不触发（T.spd=10 → 技能命中 90；seed 14 首掷 97.9 ≥ 90 必 miss）
	var fx_sm := _pincer_fixture()
	var sm_c: Dictionary = fx_sm[1]
	var sm_t: Dictionary = fx_sm[2]
	sm_c[&"mp"] = 30
	seed(14)
	var sm_outcome: Dictionary = Resolver.resolve_skill(sm_c, [sm_t], &"smite", {}, fx_sm[0])
	_expect((sm_outcome[&"skill"][&"missed"] as Array).size() == 1, "seed 14 smite 确认 MISS")
	_expect(not bool(sm_outcome[&"skill"][&"pincer"][&"active"]), "技能 MISS 不触发追击")
	_expect(int(sm_t[&"hp"]) == 100, "MISS 场景 T.hp 不变")
	# 11f. 物理技能击杀不触发（T.hp=28 恰被 smite 击杀）
	var fx_skd := _pincer_fixture()
	var skd_t: Dictionary = fx_skd[2]
	skd_t[&"stats"] = (skd_t[&"stats"] as Dictionary).duplicate(true)
	skd_t[&"stats"][&"spd"] = 0
	skd_t[&"hp"] = 28
	(fx_skd[1] as Dictionary)[&"mp"] = 30
	seed(736)
	var skd_outcome: Dictionary = Resolver.resolve_skill(fx_skd[1], [skd_t], &"smite", {}, fx_skd[0])
	_expect(bool(skd_t[&"isDead"]) and (skd_outcome[&"deaths"] as Array).has(skd_t), "smite 击杀进 deaths")
	_expect(not bool(skd_outcome[&"skill"][&"pincer"][&"active"]), "技能击杀不追击")

	# ---------- 12. 物品不触发 ----------
	print(" [12] resolver.resolve_item 物品路径")
	var fx_it := _pincer_fixture()
	var thrower := _unit(&"TH", &"player", Vector2i(1, 0))
	var it_t: Dictionary = fx_it[2]
	(fx_it[0] as GridSystem).place_unit(thrower, 1, 0)
	seed(738)
	var it_outcome: Dictionary = Resolver.resolve_item(
		thrower, [it_t], { &"id": &"shuriken", &"uses": 4 })
	_expect(int(it_t[&"hp"]) == 92, "手里剑 8 正常落地")
	_expect(not (it_outcome[&"item"] as Dictionary).has(&"pincer"), "物品路径无追击（设计边界）")

	print("failures=%d" % failures)
	quit(1 if failures > 0 else 0)


## 把攻击者 weapon.hit 置 0（atkHit 钳 0 → 恒 MISS），其余不动。
func _make_hitter_zero(u: Dictionary) -> Dictionary:
	var w: Dictionary = (u[&"weapon"] as Dictionary).duplicate(true)
	w[&"hit"] = 0
	u[&"weapon"] = w
	return u


func _walkable_terrain(w: int, h: int) -> Array:
	# GridSystem._init 期望 terrain[y][x] = 地形类型名（TerrainData.get_tile 归一化）
	var rows: Array = []
	for y in h:
		var row: Array = []
		for x in w:
			row.append(&"plain")
		rows.append(row)
	return rows
