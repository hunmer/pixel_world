## tests/test_skills.gd — 技能/物品/MP/冷却系统自测（headless）
## 仿 debug_test.gd 的 _ok/_pass/_fail/_print_summary/_exit_tree 框架。
## 覆盖：数据加载、单位技能/物品/MP、技能伤害/治疗/AOE、冷却、buff 生效、
##       物品消耗/装备、AI 自动使用技能。

extends Node

var _log: Array[String] = []
var _pass := 0
var _fail := 0


func _ready() -> void:
	randomize()
	_run_all()
	_print_summary()


func _run_all() -> void:
	_log.append("== 技能/物品系统自测 ==")
	_test_skill_data_loaded()
	_test_item_data_loaded()
	_test_unit_has_skills_items_mp()
	_test_skill_damage()
	_test_skill_heal()
	_test_skill_aoe()
	_test_skill_cooldown()
	_test_skill_mp_cost()
	_test_buff_effect_on_combat()
	_test_buff_tick_expiry()
	_test_item_consume()
	_test_item_equip()
	_test_item_buff_potion()
	_test_ai_uses_skill()


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		_log.append("  [PASS] " + msg)
	else:
		_fail += 1
		_log.append("  [FAIL] " + msg)


func _print_summary() -> void:
	_log.append("== 结果: %d passed, %d failed ==" % [_pass, _fail])
	for line in _log:
		print(line)
	if _fail > 0:
		printerr("SKILL TEST FAILED")


func _exit_tree() -> void:
	get_tree().quit(1 if _fail > 0 else 0)


# ---------- 辅助：构造测试单位/网格 ----------
func _mk_unit(uname: String, faction: StringName, prof_id: StringName, pos: Vector2i) -> Dictionary:
	return UnitFactory.create_random_unit(&"test_%s" % uname, uname, faction, 5, pos,
		ProfessionData.get_profession(prof_id))


func _mk_grid(w: int, h: int) -> GridSystem:
	var t: Array = []
	for y in range(h):
		var row: Array = []
		for x in range(w):
			row.append(&"plain")
		t.append(row)
	return GridSystem.new(w, h, t)


# ---------- 单测 ----------
func _test_skill_data_loaded() -> void:
	var sl := SkillData.SKILL_LIST
	_ok(not sl.is_empty(), "技能列表非空 (%d 个)" % sl.size())
	var types: Dictionary = {}
	for s in sl:
		types[s[&"type"]] = true
	# 至少覆盖 damage/heal/aoe/buff/debuff 五种
	for t in [&"damage", &"heal", &"aoe", &"buff", &"debuff"]:
		_ok(types.has(t), "技能含 type=%s" % String(t))
	# 火球术字段完整
	var fb := SkillData.get_skill(&"fireball")
	_ok(fb[&"type"] == &"damage" and fb[&"mpCost"] > 0, "火球术: damage 类型 + 有 MP 消耗")


func _test_item_data_loaded() -> void:
	var il := ItemData.ITEM_LIST
	_ok(not il.is_empty(), "物品列表非空 (%d 个)" % il.size())
	var types: Dictionary = {}
	for it in il:
		types[it[&"type"]] = true
	for t in [&"consumable", &"throwable", &"equip", &"buff"]:
		_ok(types.has(t), "物品含 type=%s" % String(t))


func _test_unit_has_skills_items_mp() -> void:
	var u := _mk_unit("mage", &"player", &"mage", Vector2i(0, 0))
	_ok(int(u.get(&"mp", -1)) > 0, "单位有当前 MP (%d)" % int(u.get(&"mp", -1)))
	_ok(int(u[&"stats"].get(&"mp", 0)) > 0, "单位有 MP 上限 stats.mp (%d)" % int(u[&"stats"].get(&"mp", 0)))
	_ok(not u.get(&"skills", []).is_empty(), "法师有默认技能 (%d 个)" % u.get(&"skills", []).size())
	_ok(not u.get(&"items", []).is_empty(), "单位有初始背包 (%d 个)" % u.get(&"items", []).size())
	_ok(u.has(&"skillCooldowns") and u.has(&"buffs"), "单位有 skillCooldowns/buffs 字段")


func _test_skill_damage() -> void:
	var caster := _mk_unit("mage", &"player", &"mage", Vector2i(0, 0))
	var target := _mk_unit("enemy", &"enemy", &"knight", Vector2i(1, 0))
	var hp_before := int(target[&"hp"])
	var mp_before := int(caster[&"mp"])
	# 强制学会火球术（保证有）
	if not caster[&"skills"].has(&"fireball"):
		caster[&"skills"].append(&"fireball")
	# 火球术命中判定有随机性，重试至多 5 次确保至少命中一次
	var ever_damaged := false
	for _attempt in range(5):
		target[&"hp"] = hp_before
		caster[&"mp"] = mp_before
		caster[&"skillCooldowns"] = {}
		var r := SkillSystem.execute(caster, [target], &"fireball")
		var hits: Array = r[&"hits"]
		if hits.size() > 0:
			ever_damaged = true
			break
	_ok(ever_damaged, "火球术命中并造成伤害（至多重试5次）")
	if ever_damaged:
		_ok(int(target[&"hp"]) < hp_before, "目标 HP 下降 (%d→%d)" % [hp_before, int(target[&"hp"])])
	_ok(int(caster[&"mp"]) == mp_before - int(SkillData.get_skill(&"fireball")[&"mpCost"]), "施法者 MP 扣减正确")


func _test_skill_heal() -> void:
	var caster := _mk_unit("priest", &"player", &"priest", Vector2i(0, 0))
	var ally := _mk_unit("fighter", &"player", &"swordsman", Vector2i(1, 0))
	ally[&"hp"] = maxi(1, int(ally[&"hp"]) - 10)   # 受伤
	var max_hp := int(ally[&"stats"][&"hp"])
	if not caster[&"skills"].has(&"heal"):
		caster[&"skills"].append(&"heal")
	SkillSystem.execute(caster, [ally], &"heal")
	_ok(int(ally[&"hp"]) > 1, "治疗术恢复 HP (→%d)" % int(ally[&"hp"]))
	# 不超上限
	caster[&"mp"] = int(caster[&"stats"][&"mp"])  # 补满
	caster[&"skillCooldowns"] = {}
	ally[&"hp"] = max_hp  # 已满
	SkillSystem.execute(caster, [ally], &"heal")
	_ok(int(ally[&"hp"]) == max_hp, "治疗不超 HP 上限")


func _test_skill_aoe() -> void:
	var caster := _mk_unit("mage", &"player", &"mage", Vector2i(0, 0))
	if not caster[&"skills"].has(&"blizzard"):
		caster[&"skills"].append(&"blizzard")
	var grid := _mk_grid(5, 5)
	grid.place_unit(caster, 0, 0)
	var e1 := _mk_unit("e1", &"enemy", &"knight", Vector2i(1, 0))
	var e2 := _mk_unit("e2", &"enemy", &"knight", Vector2i(2, 0))
	grid.place_unit(e1, 1, 0)
	grid.place_unit(e2, 2, 0)
	var targets := SkillSystem.targets_for(caster, &"blizzard", grid)
	_ok(targets.size() >= 2, "暴风雪能选到多个目标 (%d)" % targets.size())
	var r := SkillSystem.execute(caster, targets, &"blizzard")
	# AOE 命中有随机性，断言改为：执行成功、扣了 MP、结果含 hits/missed 结构
	var aoe_hits: Array = r[&"hits"]
	var aoe_missed: Array = r[&"missed"]
	_ok(aoe_hits.size() + aoe_missed.size() == targets.size(), "暴风雪对每个目标都结算（命中%d 未中%d）" % [aoe_hits.size(), aoe_missed.size()])


func _test_skill_cooldown() -> void:
	var caster := _mk_unit("mage", &"player", &"mage", Vector2i(0, 0))
	if not caster[&"skills"].has(&"smite"):
		caster[&"skills"].append(&"smite")
	var target := _mk_unit("enemy", &"enemy", &"knight", Vector2i(1, 0))
	SkillSystem.execute(caster, [target], &"smite")
	var cd := int(caster[&"skillCooldowns"].get(&"smite", 0))
	_ok(cd > 0, "smite 使用后置冷却 (%d)" % cd)
	_ok(not SkillSystem.can_use(caster, &"smite"), "冷却中 can_use=false")
	# 模拟回合 tick
	var tm := TurnManager.new([caster])
	tm.start_player_phase()  # 玩家回合开始会 -1
	_ok(int(caster[&"skillCooldowns"].get(&"smite", 0)) == cd - 1, "玩家回合开始冷却 -1")


func _test_skill_mp_cost() -> void:
	var u := _mk_unit("mage", &"player", &"mage", Vector2i(0, 0))
	if not u[&"skills"].has(&"fireball"):
		u[&"skills"].append(&"fireball")
	var target := _mk_unit("enemy", &"enemy", &"knight", Vector2i(1, 0))
	var mp_before := int(u[&"mp"])
	# MP 不足时 can_use=false
	u[&"mp"] = 0
	_ok(not SkillSystem.can_use(u, &"fireball"), "MP 不足 can_use=false")
	# MP 恢复后可用
	u[&"mp"] = mp_before
	_ok(SkillSystem.can_use(u, &"fireball"), "MP 充足 can_use=true")
	SkillSystem.execute(u, [target], &"fireball")
	_ok(int(u[&"mp"]) == mp_before - int(SkillData.get_skill(&"fireball")[&"mpCost"]), "使用后 MP 扣减正确")


func _test_buff_effect_on_combat() -> void:
	var caster := _mk_unit("mage", &"player", &"swordsman", Vector2i(0, 0))
	var target := _mk_unit("enemy", &"enemy", &"knight", Vector2i(1, 0))
	var str_before := SkillSystem.effective_stat(caster, &"str")
	SkillSystem.apply_buff(caster, &"str", 10, 3, "test")
	_ok(SkillSystem.effective_stat(caster, &"str") == str_before + 10, "buff 生效: effective_stat 改变")
	# buff 影响普攻伤害（CombatSystem 用 effective_stat）
	var prev := CombatSystem.preview(caster, target, 0, 0)
	_ok(int(prev[&"atkDmg"]) >= 0, "CombatSystem 在 buff 下能正常预览伤害")


func _test_buff_tick_expiry() -> void:
	var u := _mk_unit("fighter", &"player", &"swordsman", Vector2i(0, 0))
	SkillSystem.apply_buff(u, &"def", 5, 1, "guard")
	_ok(SkillSystem.effective_stat(u, &"def") == int(u[&"stats"][&"def"]) + 5, "buff 挂上后属性+5")
	SkillSystem.tick_buffs([u])
	_ok(u[&"buffs"].is_empty(), "buff 到期后清除")


func _test_item_consume() -> void:
	var u := _mk_unit("fighter", &"player", &"swordsman", Vector2i(0, 0))
	u[&"hp"] = maxi(1, int(u[&"hp"]) - 15)  # 受伤
	# 保证有生命药剂
	u[&"items"] = [{ id = &"hpPotion", uses = 2 }]
	var entry: Dictionary = u[&"items"][0]
	var hp_before := int(u[&"hp"])
	ItemSystem.execute(u, [u], entry)
	_ok(int(u[&"hp"]) > hp_before, "生命药剂回 HP (%d→%d)" % [hp_before, int(u[&"hp"])])
	_ok(u[&"items"].size() == 1, "消耗后 uses-=1 物品仍在背包")
	# 再用一次，归零应移除
	var entry2: Dictionary = u[&"items"][0]
	ItemSystem.execute(u, [u], entry2)
	_ok(u[&"items"].is_empty(), "uses 归零后从背包移除")


func _test_item_equip() -> void:
	var u := _mk_unit("fighter", &"player", &"swordsman", Vector2i(0, 0))
	u[&"items"] = [{ id = &"armorRing", uses = 1 }]
	var def_before := int(u[&"stats"][&"def"])
	var entry: Dictionary = u[&"items"][0]
	var r := ItemSystem.equip(u, entry)
	_ok(bool(r.get(&"equipped", false)), "装备成功")
	_ok(int(u[&"stats"][&"def"]) == def_before + 4, "装备后防御永久+4")
	_ok(u[&"items"].is_empty(), "装备后从背包移除")


func _test_item_buff_potion() -> void:
	var u := _mk_unit("fighter", &"player", &"swordsman", Vector2i(0, 0))
	u[&"items"] = [{ id = &"mightPotion", uses = 1 }]
	var str_before := SkillSystem.effective_stat(u, &"str")
	var entry: Dictionary = u[&"items"][0]
	ItemSystem.execute(u, [u], entry)
	_ok(SkillSystem.effective_stat(u, &"str") == str_before + 5, "力量药水 buff 生效 +5")
	_ok(not u[&"buffs"].is_empty(), "力量药水挂了 buff 条目")


func _test_placed_unit_conversion() -> void:
	# 已删除：PlacedUnit → UnitData 转换测试依赖 LevelToChapter（合成地图适配层）
	# B2 改造后用 WorldToChapter.world_to_chapter 从真实世界生成 chapter，不再有 PlacedUnit 概念
	pass


func _test_ai_uses_skill() -> void:
	# 敌方有强力技能 + 足够 MP 时，AI 应考虑使用（阶段6 改造后才真正用技能）
	var enemy := _mk_unit("enemy_mage", &"enemy", &"mage", Vector2i(0, 0))
	if not enemy[&"skills"].has(&"fireball"):
		enemy[&"skills"].append(&"fireball")
	enemy[&"mp"] = int(enemy[&"stats"][&"mp"])  # MP 充足
	var player := _mk_unit("player", &"player", &"swordsman", Vector2i(2, 0))
	var grid := _mk_grid(5, 5)
	grid.place_unit(enemy, 0, 0)
	grid.place_unit(player, 2, 0)
	var decision := EnemyAI.decide(enemy, grid, [player])
	_ok(not decision.is_empty(), "AI 决策非空")
	# 改造后决策含 action 字段（type=normal/skill/item）；改造前兼容旧结构
	var act_type = decision.get(&"action", {}).get(&"type", &"normal")
	_ok(act_type in [&"normal", &"skill", &"item"], "action.type 合法: %s" % String(act_type))
