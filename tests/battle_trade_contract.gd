## tests/battle_trade_contract.gd — C1 相邻友军物品交换契约（纯逻辑，headless --script 可跑）
##
## 覆盖：转移后双方背包正确、uses 保留、非法目标拒绝（距离/阵营/死亡/自身/非持有条目）。
extends SceneTree

const TradeSystemScript = preload("res://scripts/systems/trade_system.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)


func _mkunit(id: StringName, faction: StringName, pos: Vector2i, items: Array) -> Dictionary:
	return {
		id = id, name = String(id), faction = faction, position = pos,
		isDead = false, hasActed = false, items = items,
	}


## 极简 grid 桩：只需要 units 字典（adjacent_trade_targets 的依赖面）。
class FakeGrid:
	extends RefCounted
	var units := {}


func _run() -> void:
	_test_transfer_and_uses()
	_test_rejects()
	_test_adjacent_targets()
	_test_swap_roundtrip()
	if failures == 0:
		print("BATTLE_TRADE_CONTRACT_OK")
	else:
		printerr("BATTLE_TRADE_CONTRACT_FAILED: %d 处失败" % failures)
	quit(0 if failures == 0 else 1)


## 转移后双方背包正确 + uses 保留 + 条目不共享引用。
func _test_transfer_and_uses() -> void:
	var potion := { id = &"hpPotion", uses = 2 }
	var a := _mkunit(&"a", &"player", Vector2i(0, 0), [potion])
	var b := _mkunit(&"b", &"player", Vector2i(1, 0), [])
	var res: Dictionary = TradeSystemScript.execute_trade(a, b, potion)
	_expect(bool(res.get(&"ok", false)), "相邻友军合法转移应成功（res=%s）" % str(res))
	_expect((a[&"items"] as Array).is_empty(), "转移后 from 背包应清空该条目")
	_expect((b[&"items"] as Array).size() == 1, "转移后 to 背包应恰有 1 件")
	var moved: Dictionary = (b[&"items"] as Array)[0]
	_expect(moved[&"id"] == &"hpPotion" and int(moved[&"uses"]) == 2,
		"转移后物品 id 与 uses 应保留（got=%s）" % str(moved))
	# 引用独立性：改 moved 的 uses 不应影响原条目（GDScript 字典 == 按值比较，须用变异验证）
	moved[&"uses"] = 99
	_expect(int(potion[&"uses"]) == 2, "转移后条目应为新 Dictionary，改 moved 不应影响原条目")
	# 装备类同样可转移
	var sword := { id = &"ironSword", uses = 1 }
	var c := _mkunit(&"c", &"player", Vector2i(2, 0), [sword])
	var d := _mkunit(&"d", &"player", Vector2i(2, 1), [])
	var res2: Dictionary = TradeSystemScript.execute_trade(c, d, sword)
	_expect(bool(res2.get(&"ok", false)) and (c[&"items"] as Array).is_empty()
		and (d[&"items"] as Array).size() == 1
		and (d[&"items"] as Array)[0][&"id"] == &"ironSword", "装备类条目也应可转移")


## 非法目标 / 非法条目拒绝，且失败时不改动任何一方。
func _test_rejects() -> void:
	var potion := { id = &"hpPotion", uses = 2 }
	var a := _mkunit(&"a", &"player", Vector2i(0, 0), [potion])
	# 距离 2
	var far := _mkunit(&"far", &"player", Vector2i(2, 0), [])
	var r1: Dictionary = TradeSystemScript.execute_trade(a, far, potion)
	_expect(not bool(r1.get(&"ok", true)) and StringName(r1.get(&"reason", &"")) == &"distance",
		"距离 2 的友军应被拒绝（res=%s）" % str(r1))
	# 敌对阵营（相邻）
	var foe := _mkunit(&"foe", &"enemy", Vector2i(0, 1), [])
	var r2: Dictionary = TradeSystemScript.execute_trade(a, foe, potion)
	_expect(not bool(r2.get(&"ok", true)) and StringName(r2.get(&"reason", &"")) == &"faction",
		"相邻敌方应被拒绝（res=%s）" % str(r2))
	# 死亡友军（相邻）
	var dead := _mkunit(&"dead", &"player", Vector2i(1, 0), [])
	dead[&"isDead"] = true
	var r3: Dictionary = TradeSystemScript.execute_trade(a, dead, potion)
	_expect(not bool(r3.get(&"ok", true)) and StringName(r3.get(&"reason", &"")) == &"dead",
		"相邻死亡友军应被拒绝（res=%s）" % str(r3))
	# 自身
	var r4: Dictionary = TradeSystemScript.execute_trade(a, a, potion)
	_expect(not bool(r4.get(&"ok", true)) and StringName(r4.get(&"reason", &"")) == &"self",
		"自身应被拒绝（res=%s）" % str(r4))
	# 条目不属于 from（第三方条目）
	var stranger := { id = &"mpPotion", uses = 1 }
	var r5: Dictionary = TradeSystemScript.execute_trade(a, dead, stranger)
	_expect(not bool(r5.get(&"ok", true)) and StringName(r5.get(&"reason", &"")) != &"",
		"非 from 持有的条目应被拒绝（res=%s）" % str(r5))
	var valid := _mkunit(&"valid", &"player", Vector2i(1, 0), [])
	var r5b: Dictionary = TradeSystemScript.execute_trade(a, valid, stranger)
	_expect(not bool(r5b.get(&"ok", true)) and StringName(r5b.get(&"reason", &"")) == &"not_owned",
		"合法目标 + 非 from 持有的条目应被拒绝为 not_owned（res=%s）" % str(r5b))
	# 拒绝路径全部不改动双方
	_expect((a[&"items"] as Array).size() == 1 and (a[&"items"] as Array)[0] == potion,
		"被拒绝的转移不应改动 from 背包")
	_expect((valid[&"items"] as Array).is_empty(), "被拒绝的转移不应改动 to 背包")


## adjacent_trade_targets：仅相邻 1 格、同阵营、存活、带物品的友军。
func _test_adjacent_targets() -> void:
	var me := _mkunit(&"me", &"player", Vector2i(5, 5), [{ id = &"hpPotion", uses = 1 }])
	var ally_with := _mkunit(&"ally_with", &"player", Vector2i(5, 6), [{ id = &"hpPotion", uses = 1 }])
	var ally_empty := _mkunit(&"ally_empty", &"player", Vector2i(6, 5), [])
	var ally_far := _mkunit(&"ally_far", &"player", Vector2i(5, 7), [{ id = &"hpPotion", uses = 1 }])
	var ally_dead := _mkunit(&"ally_dead", &"player", Vector2i(4, 5), [{ id = &"hpPotion", uses = 1 }])
	ally_dead[&"isDead"] = true
	var foe := _mkunit(&"foe", &"enemy", Vector2i(5, 4), [{ id = &"hpPotion", uses = 1 }])
	var grid := FakeGrid.new()
	for u in [me, ally_with, ally_empty, ally_far, ally_dead, foe]:
		grid.units[u[&"id"]] = u
	var targets: Array = TradeSystemScript.adjacent_trade_targets(me, grid)
	_expect(targets.size() == 1 and targets[0][&"id"] == &"ally_with",
		"相邻目标应只含带物品的存活友军（got=%s）" % str(targets.map(func(u): return u[&"id"])))
	_expect((TradeSystemScript.adjacent_trade_targets(me, null) as Array).is_empty(),
		"grid 为 null 时应返回空数组")


## 来回两次转移 = 交换（roundtrip）。
func _test_swap_roundtrip() -> void:
	var pa := { id = &"hpPotion", uses = 3 }
	var pb := { id = &"mpPotion", uses = 1 }
	var a := _mkunit(&"a", &"player", Vector2i(0, 0), [pa])
	var b := _mkunit(&"b", &"player", Vector2i(0, 1), [pb])
	_expect(bool(TradeSystemScript.execute_trade(a, b, pa).get(&"ok", false)), "a→b 转移应成功")
	_expect(bool(TradeSystemScript.execute_trade(b, a, pb).get(&"ok", false)), "b→a 转移应成功")
	_expect((a[&"items"] as Array).size() == 1 and (a[&"items"] as Array)[0][&"id"] == &"mpPotion",
		"两次转移后 a 应持有 b 原物品")
	_expect((b[&"items"] as Array).size() == 1 and (b[&"items"] as Array)[0][&"id"] == &"hpPotion",
		"两次转移后 b 应持有 a 原物品")
	_expect(int((b[&"items"] as Array)[0][&"uses"]) == 3, "交换后 uses 应保留")
	_expect(not bool(a.get(&"hasActed", false)) and not bool(b.get(&"hasActed", false)),
		"转移逻辑本身不应置 hasActed")
