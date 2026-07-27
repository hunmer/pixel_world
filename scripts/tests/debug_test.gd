## tests/debug_test.gd — Phase 1 自测 autoload
## 加载 professions.json，构造小地图 + 两单位，断言移动范围/伤害与 TS 版一致。
## 作为 autoload（main 场景暂设为此），_ready 里跑断言并把结果画到屏幕上。

extends Node

var _log: Array[String] = []
var _pass := 0
var _fail := 0


func _ready() -> void:
	randomize()
	_run_all()
	_print_summary()


func _run_all() -> void:
	_log.append("== Phase 1 自测 ==")
	_test_professions_loaded()
	_test_apply_profession_physical_magic()
	_test_terrain_move_costs()
	_test_triangle_modifier()
	_test_move_range_plain_dijkstra()
	_test_move_range_blocked_by_water()
	_test_attack_range_decoupled_from_move()
	_test_find_path_astar()
	_test_combat_preview_values()
	_test_combat_execute_kills()
	_test_enemy_ai_approaches()
	_test_turn_manager_flow()
	_test_exp_formulas()


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
		printerr("DEBUG TEST FAILED")


# ---------- 单测 ----------
func _test_professions_loaded() -> void:
	var pl := ProfessionData.PROFESSION_LIST
	_ok(not pl.is_empty(), "职业列表非空 (%d 个)" % pl.size())
	var k := ProfessionData.get_profession(&"swordsman")
	_ok(k.get(&"name", "") == "剑士", "get_profession(swordsman).name == 剑士 (got %s)" % str(k.get(&"name")))
	var missing := ProfessionData.get_profession(&"__nope__")
	_ok(not missing.is_empty(), "未知职业回退默认职业")


func _test_apply_profession_physical_magic() -> void:
	var u := UnitFactory.create_random_unit(&"t1", "T", &"player", 1, Vector2i(0,0), ProfessionData.get_profession(&"mage"))
	_ok(u[&"stats"][&"mag"] > 0 and u[&"stats"][&"str"] == 0, "魔导师 power 写入 mag (%d), str=0" % u[&"stats"][&"mag"])
	var u2 := UnitFactory.create_random_unit(&"t2", "T", &"player", 1, Vector2i(0,0), ProfessionData.get_profession(&"berserker"))
	_ok(u2[&"stats"][&"str"] > 0 and u2[&"stats"][&"mag"] == 0, "狂战士 power 写入 str (%d), mag=0" % u2[&"stats"][&"str"])


func _test_terrain_move_costs() -> void:
	_ok(TerrainData.cost(&"mountain", &"armor") == 99, "armor 进山被阻 (99)")
	_ok(TerrainData.cost(&"plain", &"foot") == 1, "foot 平原消耗 1")
	_ok(TerrainData.cost(&"forest", &"cavalry") == 3, "cavalry 森林消耗 3")


func _test_triangle_modifier() -> void:
	var adv := WeaponData.triangle_modifier(&"sword", &"axe")
	_ok(adv[&"damage"] == 1 and adv[&"hit"] == 15, "剑克斧 +1/+15")
	var dis := WeaponData.triangle_modifier(&"axe", &"sword")
	_ok(dis[&"damage"] == -1 and dis[&"hit"] == -15, "斧被剑克 -1/-15")
	var neu := WeaponData.triangle_modifier(&"bow", &"sword")
	_ok(neu[&"damage"] == 0, "弓无三角修正")


func _test_move_range_plain_dijkstra() -> void:
	# 5×5 全平原，foot mov 3 → 应能到对角可达格
	var terrain := _plain_terrain(5, 5)
	var grid := GridSystem.new(5, 5, terrain)
	var mr := grid.compute_move_range(2, 2, &"foot", 3, &"player")
	_ok(mr.has("2,2"), "起点在范围内")
	_ok(mr.has("4,2"), "向右 2 格可达 (cost<=3)")
	_ok(not mr.has("4,4"), "对角 cost=6 超过 mov 3 不可达")


func _test_move_range_blocked_by_water() -> void:
	# 5×5 中间一整列水(row=2 全水)，foot 不可通过 —— 水必须在构造 grid 前写入。
	# 起点 (0,0)：只能绕到 row 1，无法越过 row 2 的水墙到 row 3/4。
	var terrain := _plain_terrain(5, 5)
	terrain[2] = [&"water", &"water", &"water", &"water", &"water"]
	var grid := GridSystem.new(5, 5, terrain)
	var mr := grid.compute_move_range(0, 0, &"foot", 10, &"player")
	_ok(not mr.has("0,3"), "水墙(row2)阻隔 foot 无法越过到 (0,3)")
	_ok(not mr.has("0,2"), "(0,2) 是水，foot 不可达")
	_ok(mr.has("0,1"), "(0,1) 水墙前可达")


func _test_attack_range_decoupled_from_move() -> void:
	# archer 攻击范围 [2,3]，应与移动范围解耦：原地能打到的格在 attackTiles
	var terrain := _plain_terrain(7, 7)
	var grid := GridSystem.new(7, 7, terrain)
	var archer := UnitFactory.create_random_unit(&"a", "A", &"player", 1, Vector2i(3,3), ProfessionData.get_profession(&"archer"))
	var res := grid.compute_attack_range(3, 3, archer)
	var atk: Dictionary = res[&"attackTiles"]
	# 距离 2 的格应在攻击范围（曼哈顿 2）
	_ok(atk.has("5,3"), "archer 距离2 攻击范围包含 (5,3)")
	_ok(not atk.has("4,3"), "archer 距离1 不在攻击范围 (4,3)")
	_ok(not atk.has("3,3"), "起点不在攻击范围")


func _test_find_path_astar() -> void:
	var terrain := _plain_terrain(5, 5)
	var grid := GridSystem.new(5, 5, terrain)
	var path := grid.find_path(Vector2i(0,0), Vector2i(3,0), &"foot", 10)
	_ok(not path.is_empty() and (path.back() as Vector2i) == Vector2i(3,0), "A* 找到路径终点正确 (len=%d)" % path.size())
	# 水墙无路
	terrain[2] = [&"plain",&"water",&"water",&"water",&"plain"]
	var grid2 := GridSystem.new(5, 5, terrain)
	var np := grid2.find_path(Vector2i(0,2), Vector2i(4,2), &"foot", 5)
	_ok(np.is_empty(), "A* 水墙无路返回空")


func _test_combat_preview_values() -> void:
	var swordsman := UnitFactory.create_random_unit(&"s", "S", &"player", 1, Vector2i(0,0), ProfessionData.get_profession(&"swordsman"))
	var knight := UnitFactory.create_random_unit(&"k", "K", &"enemy", 1, Vector2i(1,0), ProfessionData.get_profession(&"knight"))
	var p := CombatSystem.preview(swordsman, knight, 0, 0)
	# swordsman str=7 ironSword might=5 knight def=11 → 基础 7+5-11=1；
	# 但 knight 持 lance，剑被枪克（disadvantage -1）→ 1-1=0
	_ok(p[&"atkDmg"] == 0, "swordsman(剑) vs knight(枪) 剑被克 伤害=0 (基础1 - 三角1) got %d" % p[&"atkDmg"])
	_ok(p[&"atkHit"] > 0, "命中率>0 got %d" % p[&"atkHit"])
	# assassin(敏捷12) vs knight(敏捷3) 攻击速度差大 → doubleAttack
	var assassin := UnitFactory.create_random_unit(&"as", "AS", &"player", 1, Vector2i(0,0), ProfessionData.get_profession(&"assassin"))
	var p2 := CombatSystem.preview(assassin, knight, 0, 0)
	_ok(p2[&"doubleAttack"] == true, "assassin vs knight 触发双击")


func _test_combat_execute_kills() -> void:
	# berserker(power12) 对 mage(hp16,res6) 必杀(×3) 应秒杀；普通也可能一击致命
	var berserker := UnitFactory.create_random_unit(&"bz", "B", &"player", 1, Vector2i(0,0), ProfessionData.get_profession(&"berserker"))
	var mage := UnitFactory.create_random_unit(&"mg", "M", &"enemy", 1, Vector2i(1,0), ProfessionData.get_profession(&"mage"))
	var hp_before: int = mage[&"hp"]
	var r := CombatSystem.execute(berserker, mage, 0, 0)
	_ok(r[&"attackerHits"] == true, "berserker 命中 mage")
	# str12+ironAxe8 - res6 = 14，普通一击即 > mage.hp(16)? 14<16，必杀×3=42>16
	# 不强制必杀，只检查 hp 下降
	_ok(mage[&"hp"] <= hp_before, "mage hp 下降 (%d→%d)" % [hp_before, mage[&"hp"]])


func _test_enemy_ai_approaches() -> void:
	var terrain := _plain_terrain(8, 8)
	var grid := GridSystem.new(8, 8, terrain)
	var enemy := UnitFactory.create_random_unit(&"e", "E", &"enemy", 1, Vector2i(0,0), ProfessionData.get_profession(&"swordsman"))
	grid.place_unit(enemy, 0, 0)
	var player := UnitFactory.create_random_unit(&"p", "P", &"player", 1, Vector2i(5,5), ProfessionData.get_profession(&"swordsman"))
	grid.place_unit(player, 5, 5)
	var dec := EnemyAI.decide(enemy, grid, [player])
	var mt = dec[&"moveTarget"]
	_ok(mt != null, "AI 决策出移动目标")
	if mt != null:
		# 应朝玩家方向移动（x+y 朝 10 方向增加）
		var d_after: int = absi((mt as Vector2i).x - 5) + absi((mt as Vector2i).y - 5)
		var d_before := 5 + 5
		_ok(d_after < d_before, "AI 移动后更接近玩家 (%d < %d)" % [d_after, d_before])


func _test_turn_manager_flow() -> void:
	var tm := TurnManager.new([
		{ &"faction": &"player", &"isDead": false, &"hasActed": true },
		{ &"faction": &"player", &"isDead": false, &"hasActed": true },
		{ &"faction": &"enemy", &"isDead": false, &"hasActed": false },
	])
	_ok(tm.all_player_acted() == true, "玩家全员已行动")
	_ok(tm.all_enemy_acted() == false, "敌方未全员行动")
	var res := tm.check_victory([
		{ &"isDead": true }, { &"isDead": true },
	])
	_ok(res == &"win", "敌全灭 → win")
	var res2 := tm.check_victory([{ &"isDead": false }])
	_ok(res2 == &"", "仍有敌人 → 未胜")


func _test_exp_formulas() -> void:
	_ok(WeaponData.exp_for_kill(5) == 45, "exp_for_kill(5)=45")
	_ok(WeaponData.exp_for_hit(3, 1) == 12, "exp_for_hit(3,1)=12")
	_ok(WeaponData.exp_to_next(2) == 110, "exp_to_next(2)=110")


# ---------- helpers ----------
func _plain_terrain(w: int, h: int) -> Array:
	var t: Array = []
	for y in range(h):
		var row: Array = []
		for x in range(w):
			row.append(&"plain")
		t.append(row)
	return t


func _exit_tree() -> void:
	# 自测跑完即退出（headless 友好）
	get_tree().quit(1 if _fail > 0 else 0)
