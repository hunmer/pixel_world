## tests/backstab_contract.gd — 背击（按受击者朝向判定）伤害增幅与接线契约
##
## 覆盖：
##   1. FacingRules 判定：正面/背面/侧面/无朝向(旧档)/同格 全不误判
##   2. 倍率：BACKSTAB_DAMAGE_MULTIPLIER=1.25、roundi 取整、0 伤害不放大
##   3. CombatSystem：preview.atkBackstab 标记 + atkDmg 增幅（execute 同公式）
##   4. SkillSystem：伤害技能增幅、治疗不增幅
##   5. ItemSystem：投掷物增幅、治疗药不增幅
##   6. AttackEvent：impact.backstab 与顶层聚合标记
##   7. GridSystem.place_unit：移动落位维护逻辑朝向（零位移不动）
##   8. FacingRules.initialize_facings：开场面向最近敌（含平手取先遍历者，确定性）
##   9. 总伤害口径：三角修正合并后统一 ×1.25（攻击/反击同口径）
##  10. 生命周期：initialize 不覆盖已有朝向（读档兼容）、resolver 出手转身只转攻击方、
##       移动逻辑朝向取末段方向（与 sprite 逐段动画一致）
extends SceneTree

const Facing = preload("res://scripts/systems/facing_rules.gd")
const Combat = preload("res://scripts/systems/combat_system.gd")
const Skills = preload("res://scripts/systems/skill_system.gd")
const Items = preload("res://scripts/systems/item_system.gd")
const AttackEventScript = preload("res://scripts/systems/attack_event.gd")
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


## 与 attack_event_contract 同款夹具：weapon hit=100 必中、crit=0 必不暴击、
## spd 差>=4 触发双击；facing 由用例按需注入（不注入 = 旧档无朝向兼容口径）。
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


func _run() -> void:
	print("== backstab_contract ==")

	# ---------- 1. 判定 ----------
	print(" [1] FacingRules.is_backstab 判定")
	# defender 站 (3,0) 面朝 +x（右）。
	var defender := _unit(&"defender", &"enemy", Vector2i(3, 0))
	defender[&"facing"] = Vector2i(1, 0)
	_expect(not Facing.is_backstab(Vector2i(4, 0), defender), "攻击者在前方（面朝方向）：非背击")
	_expect(Facing.is_backstab(Vector2i(1, 0), defender), "攻击者在身后：背击")
	# 侧面：攻击者位于 (3,2)，受击者面朝 +x → to_attacker=(0,1) 点积 0
	_expect(not Facing.is_backstab(Vector2i(3, 2), defender), "侧面攻击（点积 0）：非背击")
	# 斜向：身后象限 (1,1) → to_attacker=(-1,-1)，dot=-1 背击；前方象限 (4,1) → (1,1) dot=1 正面
	_expect(Facing.is_backstab(Vector2i(1, 1), defender), "斜后 45°：背击")
	_expect(not Facing.is_backstab(Vector2i(4, 1), defender), "斜前 45°：非背击")
	# 同格 / 无朝向容错
	_expect(not Facing.is_backstab(Vector2i(3, 0), defender), "同格（零向量）：非背击")
	var legacy := _unit(&"legacy", &"enemy", Vector2i(3, 0))
	_expect(not Facing.is_backstab(Vector2i(1, 0), legacy), "旧档无 facing 字段：永不背击（兼容）")
	legacy[&"facing"] = Facing.NO_FACING
	_expect(not Facing.is_backstab(Vector2i(1, 0), legacy), "显式 NO_FACING：永不背击")

	# ---------- 2. 倍率 ----------
	print(" [2] FacingRules.apply_backstab 倍率")
	_expect(Facing.BACKSTAB_DAMAGE_MULTIPLIER == 1.25, "常量倍率 = 1.25（可配置单点）")
	_expect(Facing.apply_backstab(Vector2i(1, 0), defender, 25) == 31, "25 → 31（roundi 31.25）")
	_expect(Facing.apply_backstab(Vector2i(1, 0), defender, 30) == 38, "30 → 38（roundi 37.5）")
	_expect(Facing.apply_backstab(Vector2i(1, 0), defender, 8) == 10, "8 → 10（整除无歧义）")
	_expect(Facing.apply_backstab(Vector2i(1, 0), defender, 0) == 0, "0 伤害不放大")
	_expect(Facing.apply_backstab(Vector2i(1, 0), defender, -3) == -3, "非正值原样返回")
	_expect(Facing.apply_backstab(Vector2i(4, 0), defender, 25) == 25, "正面攻击原样返回")

	# ---------- 3. CombatSystem ----------
	print(" [3] CombatSystem preview/execute")
	var atk_front := _unit(&"attacker", &"player", Vector2i(4, 0))
	var atk_back := _unit(&"attacker2", &"player", Vector2i(1, 0))
	var target := _unit(&"target", &"enemy", Vector2i(3, 0), &"staff")
	target[&"stats"][&"spd"] = 0
	target[&"facing"] = Vector2i(1, 0)
	# 基础伤害 = str20 + might5 - def0 = 25；背击 31。
	var pv_front: Dictionary = Combat.preview(atk_front, target, 0, 0)
	var pv_back: Dictionary = Combat.preview(atk_back, target, 0, 0)
	_expect(not bool(pv_front[&"atkBackstab"]), "正面 preview 标记 atkBackstab=false")
	_expect(bool(pv_back[&"atkBackstab"]), "背面 preview 标记 atkBackstab=true")
	_expect(int(pv_front[&"atkDmg"]) == 25, "正面 preview 伤害 25（不增幅）")
	_expect(int(pv_back[&"atkDmg"]) == 31, "背面 preview 伤害 31（×1.25）")
	# 旧档无 facing 的防守方：无增幅
	var target_legacy := _unit(&"target2", &"enemy", Vector2i(3, 0), &"staff")
	var pv_legacy: Dictionary = Combat.preview(atk_back, target_legacy, 0, 0)
	_expect(not bool(pv_legacy[&"atkBackstab"]) and int(pv_legacy[&"atkDmg"]) == 25, "旧档防守方无朝向：preview 不增幅")
	# execute 同公式（seed 固定；命中 100/必杀 0/双击必出 → 两击各 preview 伤害）
	seed(731)
	var ex_back: Dictionary = Combat.execute(atk_back.duplicate(true), target.duplicate(true), 0, 0)
	_expect(int(ex_back[&"attackerDamage"]) == 62, "背面 execute 双击总伤 62（31×2）")
	seed(731)
	var ex_front: Dictionary = Combat.execute(atk_front.duplicate(true), target.duplicate(true), 0, 0)
	_expect(int(ex_front[&"attackerDamage"]) == 50, "正面 execute 双击总伤 50（25×2）")

	# ---------- 9. 总伤害口径：三角修正合并后统一 ×1.25 ----------
	print(" [9] 三角修正合并后统一增幅")
	# sword 克 axe：tri damage +1。base 25 + tri 1 = 26；背击 26×1.25 → 33（而非 25×1.25+1=32）。
	var axe_hater := _unit(&"tri_atk", &"player", Vector2i(4, 0))  # sword
	var axe_target := _unit(&"tri_def", &"enemy", Vector2i(3, 0), &"axe")
	axe_target[&"stats"][&"spd"] = 0
	axe_target[&"facing"] = Vector2i(1, 0)
	var pv_tri: Dictionary = Combat.preview(axe_hater, axe_target, 0, 0)
	_expect(int(pv_tri[&"atkDmg"]) == 26, "正面克制伤害 26（25+tri1）")
	axe_target[&"facing"] = Vector2i(-1, 0)
	var pv_tri_back: Dictionary = Combat.preview(axe_hater, axe_target, 0, 0)
	_expect(int(pv_tri_back[&"atkDmg"]) == 33, "背面克制总伤 33（(25+1)×1.25 四舍五入）")
	# 反击同口径：resolver 出手转身后反击恒打攻击者正面 —— preview 按转身快照计算，
	# 与真实结算一致（预览不再出现「显示背击增伤而实际没有」）。
	# 反击方(sword) base 25 - tri 1 = 24，无论攻击者(lance)出手前朝向如何。
	var lanceman := _unit(&"lance_atk", &"player", Vector2i(4, 0), &"lance")
	var swordman := _unit(&"sword_def", &"enemy", Vector2i(3, 0))
	swordman[&"stats"][&"spd"] = 0  # 不触发防守方双击，只看单次反击
	lanceman[&"stats"][&"spd"] = 0  # 攻击方也不追击，聚焦反击伤害
	swordman[&"facing"] = Vector2i(1, 0)
	lanceman[&"facing"] = Vector2i(1, 0)  # 攻击者背对防守方（防守方在其 -x 侧，面朝 +x）
	var pv_counter_back: Dictionary = Combat.preview(lanceman, swordman, 0, 0)
	_expect(int(pv_counter_back[&"defDmg"]) == 24, "攻击者背对时 preview 反击仍 24（按转身快照口径）")
	lanceman[&"facing"] = Vector2i(-1, 0)  # 攻击者面向防守方出手
	var pv_counter: Dictionary = Combat.preview(lanceman, swordman, 0, 0)
	_expect(int(pv_counter[&"defDmg"]) == 24, "攻击者面向防守方：正面反击 24（25-tri1）")
	_expect(Facing.get_facing(lanceman) == Vector2i(-1, 0), "preview 不 mutate 攻击者朝向")

	# ---------- 10. 生命周期与出手转身 ----------
	print(" [10] 生命周期与出手转身")
	# 10a. initialize_facings 不覆盖已有朝向（读档兼容：facing 已随存档持久化）
	var saved := _unit(&"saved", &"player", Vector2i(0, 0))
	saved[&"facing"] = Vector2i(0, 1)
	var foe_saved := _unit(&"foe_saved", &"enemy", Vector2i(2, 0))
	Facing.initialize_facings([saved, foe_saved])
	_expect(Facing.get_facing(saved) == Vector2i(0, 1), "已有朝向不被 initialize_facings 覆盖（读档兼容）")
	_expect(Facing.get_facing(foe_saved) == Vector2i(-1, 0), "无朝向的新单位照常定向")
	# 10b. resolver 出手转身：只转攻击方，不动受击方；背击判定不受影响
	var r_grid: GridSystem = Grid.new(6, 6, _walkable_terrain(6, 6))
	var r_atk := _unit(&"r_atk", &"player", Vector2i(1, 0))
	var r_def := _unit(&"r_def", &"enemy", Vector2i(3, 0), &"staff")
	r_def[&"stats"][&"spd"] = 0
	r_def[&"facing"] = Vector2i(1, 0)  # 背对攻击者
	r_grid.place_unit(r_atk, 1, 0)
	r_grid.place_unit(r_def, 3, 0)
	seed(731)
	var resolved: Dictionary = Resolver.resolve_attack(r_atk, r_def, r_grid)
	_expect(Facing.get_facing(r_atk) == Vector2i(1, 0), "resolve_attack 出手转身面向目标")
	_expect(Facing.get_facing(r_def) == Vector2i(1, 0), "受击方朝向不被转身改动")
	_expect(int(resolved[&"combat"][&"attackerDamage"]) == 62, "resolver 链路背击双击 62（与 CombatSystem 一致）")
	_expect(bool(resolved[&"combat"][&"attack_event"][&"impacts"][0][&"backstab"]), "resolver 链路 impact 标记背击")
	# 10c. resolve_skill / resolve_item 同样转身
	var r_caster := _unit(&"r_caster", &"player", Vector2i(4, 0), &"anima")
	var r_hurt := _unit(&"r_hurt", &"enemy", Vector2i(2, 0))
	r_hurt[&"facing"] = Vector2i(-1, 0)  # 背对施放者（施放者在其 +x）
	r_grid.place_unit(r_caster, 4, 0)
	r_grid.place_unit(r_hurt, 2, 0)
	seed(991)
	Resolver.resolve_skill(r_caster, [r_hurt], &"fireball")
	_expect(Facing.get_facing(r_caster) == Vector2i(-1, 0), "resolve_skill 出手转身面向目标")
	_expect(Facing.get_facing(r_hurt) == Vector2i(-1, 0), "技能受击方朝向不变")
	var r_thrower := _unit(&"r_thrower", &"player", Vector2i(4, 2))
	var r_victim := _unit(&"r_victim", &"enemy", Vector2i(3, 2))
	r_grid.place_unit(r_thrower, 4, 2)
	r_grid.place_unit(r_victim, 3, 2)
	Resolver.resolve_item(r_thrower, [r_victim], { &"id": &"shuriken", &"uses": 4 })
	_expect(Facing.get_facing(r_thrower) == Vector2i(-1, 0), "resolve_item 出手转身面向目标")
	# 10d. 移动逻辑朝向 = 末段方向（L 形路径 (0,0)→(1,0)→(1,1)：末段向下 (0,1)；
	# 净位移口径会得斜向 (1,1) —— battle.gd/runner 均按末段覆盖）
	var walker := _unit(&"walker", &"player", Vector2i(0, 0))
	Facing.face_move(walker, Vector2i(1, 0), Vector2i(1, 1))
	_expect(Facing.get_facing(walker) == Vector2i(0, 1), "L 形路径末段朝向 (0,1)（与 sprite 一致）")

	# ---------- 4. SkillSystem ----------

	print(" [4] SkillSystem 技能")
	var caster := _unit(&"caster", &"player", Vector2i(4, 0), &"anima")
	var hurt := _unit(&"hurt", &"enemy", Vector2i(3, 0))
	hurt[&"facing"] = Vector2i(1, 0)  # 面朝攻击者 → 正面
	var pv_skill: Dictionary = Skills.preview(caster, hurt, &"fireball")
	_expect(int(pv_skill[&"hp_delta"]) == -30, "正面火球伤害 30（mag20+power10-res0）")
	hurt[&"facing"] = Vector2i(-1, 0)  # 背对攻击者 → 背击
	var pv_skill_back: Dictionary = Skills.preview(caster, hurt, &"fireball")
	_expect(int(pv_skill_back[&"hp_delta"]) == -38, "背面火球伤害 38（30×1.25）")
	# 治疗不受背击影响：奶妈背对/面向目标，治疗量一致
	var healer := _unit(&"healer", &"player", Vector2i(4, 0), &"staff")
	var ally := _unit(&"ally", &"player", Vector2i(3, 0))
	ally[&"hp"] = 50
	ally[&"facing"] = Vector2i(-1, 0)  # 背对治疗者
	healer[&"facing"] = Vector2i(1, 0)
	var pv_heal: Dictionary = Skills.preview(healer, ally, &"heal")
	_expect(int(pv_heal[&"hp_delta"]) == 25, "治疗不受朝向影响（15+floor(20/2)=25）")
	seed(991)
	var ally_exec := ally.duplicate(true)
	var he := Skills.execute(healer.duplicate(true), [ally_exec], &"heal")
	_expect(int(he[&"healed"][0][&"hp_delta"]) == 25, "execute 治疗同样不增幅")

	# ---------- 5. ItemSystem ----------
	print(" [5] ItemSystem 物品")
	# shuriken power 8：正面 8、背面 10
	var thrower := _unit(&"thrower", &"player", Vector2i(4, 0))
	var victim := _unit(&"victim", &"enemy", Vector2i(3, 0))
	victim[&"facing"] = Vector2i(1, 0)
	_expect(int(Items.preview(thrower, victim, &"shuriken")[&"hp_delta"]) == -8, "正面手里剑 8")
	victim[&"facing"] = Vector2i(-1, 0)
	_expect(int(Items.preview(thrower, victim, &"shuriken")[&"hp_delta"]) == -10, "背面手里剑 10（8×1.25）")
	seed(991)
	var thrown := Items.execute(thrower.duplicate(true), [victim.duplicate(true)], { &"id": &"shuriken", &"uses": 4 })
	_expect(int(thrown[&"hp_deltas"][0][&"delta"]) == -10, "execute 手里剑与 preview 同公式")
	# hpPotion 治疗不增幅
	var drinker := _unit(&"drinker", &"player", Vector2i(3, 0))
	drinker[&"hp"] = 50
	drinker[&"facing"] = Vector2i(-1, 0)  # 背对使用者也无影响
	var potion_used := Items.execute(thrower.duplicate(true), [drinker.duplicate(true)], { &"id": &"hpPotion", &"uses": 3 })
	_expect(int(potion_used[&"hp_deltas"][0][&"delta"]) == 20, "治疗药不受朝向影响（+20）")

	# ---------- 6. AttackEvent 标记 ----------
	print(" [6] AttackEvent backstab 标记")
	var src := _unit(&"src", &"player", Vector2i(1, 0))
	var dst := _unit(&"dst", &"enemy", Vector2i(3, 0))
	dst[&"facing"] = Vector2i(1, 0)
	var impact_back: Dictionary = AttackEventScript.make_impact(src, dst, true, 31, 100, 69, false, false)
	_expect(bool(impact_back[&"backstab"]), "impact 标记 backstab=true（命中且有伤害）")
	var impact_front: Dictionary = AttackEventScript.make_impact(dst, src, true, 20, 100, 80, false, false)
	_expect(not bool(impact_front[&"backstab"]), "正面 impact 不标记")
	var impact_miss: Dictionary = AttackEventScript.make_impact(src, dst, false, 0, 100, 100, false, false)
	_expect(not bool(impact_miss[&"backstab"]), "MISS impact 不标记背击")

	# ---------- 7. GridSystem.place_unit 朝向接线 ----------
	print(" [7] GridSystem.place_unit 维护朝向")
	var grid: GridSystem = Grid.new(5, 5, _walkable_terrain(5, 5))
	var mover := _unit(&"mover", &"player", Vector2i(2, 0))
	grid.place_unit(mover, 2, 0)
	_expect(Facing.get_facing(mover) == Facing.NO_FACING, "原地落位（零位移）不设朝向")
	grid.place_unit(mover, 2, 3)
	_expect(Facing.get_facing(mover) == Vector2i(0, 1), "向下移动后朝向 (0,1)")
	grid.place_unit(mover, 4, 3)
	_expect(Facing.get_facing(mover) == Vector2i(1, 0), "向右移动后朝向 (1,0)")
	# 朝向随移动翻转后，原方向攻击者不再背击
	var foe := _unit(&"foe", &"enemy", Vector2i(3, 3))
	foe[&"facing"] = Vector2i(-1, 0)
	grid.place_unit(foe, 3, 3)
	foe[&"facing"] = Vector2i(-1, 0)  # 开场背对 +x
	grid.place_unit(foe, 1, 3)
	_expect(Facing.get_facing(foe) == Vector2i(-1, 0), "向左移动后朝向 (-1,0)")
	_expect(Facing.is_backstab(Vector2i(4, 3), foe), "移动背对后受右侧攻击判定背击")

	# ---------- 8. initialize_facings 确定性 ----------
	print(" [8] initialize_facings 开场朝向")
	var p1 := _unit(&"p1", &"player", Vector2i(0, 0))
	var e1 := _unit(&"e1", &"enemy", Vector2i(2, 0))
	Facing.initialize_facings([p1, e1])
	_expect(Facing.get_facing(p1) == Vector2i(1, 0), "玩家开场面向最近敌 (+x)")
	_expect(Facing.get_facing(e1) == Vector2i(-1, 0), "敌开场面向最近玩家 (-x)")
	# 平手（两敌同距）取先遍历者：e1 在 +x、e2 在 +y，均距 2 → facing (1,0)
	var p2 := _unit(&"p2", &"player", Vector2i(1, 1))
	var e2 := _unit(&"e2", &"enemy", Vector2i(3, 1))
	var e3 := _unit(&"e3", &"enemy", Vector2i(1, 3))
	Facing.initialize_facings([p2, e2, e3])
	_expect(Facing.get_facing(p2) == Vector2i(1, 0), "距离平手取先遍历者（确定性）")
	# face_move 零位移
	var still := _unit(&"still", &"player", Vector2i(2, 2))
	still[&"facing"] = Vector2i(0, 1)
	Facing.face_move(still, Vector2i(2, 2), Vector2i(3, 2))
	Facing.face_move(still, Vector2i(3, 2), Vector2i(3, 2))
	_expect(Facing.get_facing(still) == Vector2i(1, 0), "face_move 零位移不改变朝向")

	print("failures=%d" % failures)
	quit(1 if failures > 0 else 0)


func _walkable_terrain(w: int, h: int) -> Array:
	# GridSystem._init 期望 terrain[y][x] = 地形类型名（TerrainData.get_tile 归一化）
	var rows: Array = []
	for y in h:
		var row: Array = []
		for x in w:
			row.append(&"plain")
		rows.append(row)
	return rows
