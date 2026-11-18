## battle_threat_data_contract.gd — 范围/威胁纯逻辑契约，不启动战斗场景。
extends SceneTree

const Threat = preload("res://scripts/battle/battle_threat_data.gd")
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_ranges()
	_test_prediction()
	if _failures == 0:
		print("[battle_threat_data] PASS")
	quit(0 if _failures == 0 else 1)


func _test_ranges() -> void:
	var grid: GridSystem = GridSystem.new(7, 1, [[&"plain", &"plain", &"plain", &"forest", &"plain", &"plain", &"plain"]])
	var enemy: Dictionary = _unit(&"enemy", &"enemy", Vector2i(0, 0), &"ironSword", 2)
	grid.place_unit(enemy, 0, 0)
	var ranges: Dictionary = Threat.unit_ranges(grid, enemy)
	_check(ranges.moveRange.has("2,0"), "移动范围使用真实移动力")
	_check(not ranges.moveRange.has("3,0"), "森林消耗阻止超额移动")
	var danger: Dictionary = Threat.danger_tiles(grid, [enemy])
	_check(danger.has("1,0"), "危险区包含移动范围内部攻击格")
	_check(danger.has("3,0"), "危险区包含移动边缘外武器格")
	_check(not danger.has("4,0"), "危险区不使用简单移动力加射程圆")
	var ally: Dictionary = _unit(&"ally", &"enemy", Vector2i(2, 0), &"ironSword", 0)
	grid.place_unit(ally, 2, 0)
	ranges = Threat.unit_ranges(grid, enemy)
	_check(ranges.moveRange.has("2,0"), "友军占位仍允许穿越")
	_check(not ranges.attackTiles.has("3,0"), "友军占位不能作为攻击落点")
	var archer: Dictionary = _unit(&"archer", &"enemy", Vector2i(0, 0), &"ironBow", 0)
	grid.remove_unit(enemy)
	grid.place_unit(archer, 0, 0)
	var bow: Dictionary = Threat.unit_ranges(grid, archer, false)
	_check(not bow.attackTiles.has("1,0") and bow.attackTiles.has("2,0"), "弓保留最小射程")
	archer[&"attackRange"] = [1, 3]
	bow = Threat.unit_ranges(grid, archer, false)
	_check(bow.attackTiles.has("1,0") and bow.attackTiles.has("3,0"), "射程服从真实职业优先规则")
	var healer: Dictionary = _unit(&"healer", &"enemy", Vector2i(0, 0), &"heal", 0)
	grid.remove_unit(archer)
	grid.place_unit(healer, 0, 0)
	var support: Dictionary = Threat.unit_ranges(grid, healer, false)
	_check(support.attackTiles.is_empty() and support.supportTiles.has("1,0"), "治疗杖只显示辅助范围")
	_check(Threat.danger_tiles(grid, [healer]).is_empty(), "治疗杖不制造危险格")
	enemy[&"isDead"] = true
	_check(Threat.danger_tiles(grid, [enemy]).is_empty(), "死亡敌人不制造危险格")


func _test_prediction() -> void:
	var grid: GridSystem = GridSystem.new(5, 1, [[&"plain", &"plain", &"forest", &"plain", &"plain"]])
	var enemy: Dictionary = _unit(&"enemy", &"enemy", Vector2i(0, 0), &"ironLance", 3)
	var player: Dictionary = _unit(&"player", &"player", Vector2i(3, 0), &"ironSword", 3)
	grid.place_unit(enemy, 0, 0)
	grid.place_unit(player, 3, 0)
	var original_units: Dictionary = grid.units.duplicate(true)
	var original_cells: Array = grid.cell_to_unit.duplicate(true)
	var threats: Array = Threat.threats_to(grid, [enemy], player, Vector2i(1, 0))
	_check(threats.size() == 1, "原位射程内产生威胁箭头")
	if not threats.is_empty():
		_check(bool(threats[0].high_risk), "真实武器克制产生黄线")
		var defender: Dictionary = player.duplicate()
		defender[&"position"] = Vector2i(1, 0)
		var expected: Dictionary = CombatSystem.preview(enemy, defender, 0, 0)
		_check(threats[0].preview.atkCrit == expected.atkCrit, "必杀来自真实战斗预测")
	_check(Threat.threats_to(grid, [enemy], player, Vector2i(2, 0)).is_empty(), "默认不把敌人移动射程算作原位箭头")
	var moving: Array = Threat.threats_to(grid, [enemy], player, Vector2i(2, 0), 20, true)
	_check(moving.size() == 1, "显式选项支持移动后敌方预测")
	if not moving.is_empty():
		var defender: Dictionary = player.duplicate()
		defender[&"position"] = Vector2i(2, 0)
		var attacker: Dictionary = enemy.duplicate()
		attacker[&"position"] = moving[0].attack_from
		var expected: Dictionary = CombatSystem.preview(attacker, defender, 20, 1)
		_check(moving[0].preview.atkDmg == expected.atkDmg and moving[0].preview.atkHit == expected.atkHit, "预测计入候选落点森林防御与回避")
	_check(grid.units == original_units and grid.cell_to_unit == original_cells, "预测不改变原单位、位置、朝向、占位")
	var neutral: Dictionary = _unit(&"bow", &"enemy", Vector2i(0, 0), &"ironBow", 0)
	neutral[&"weapon"][&"crit"] = 30
	grid.remove_unit(enemy)
	grid.place_unit(neutral, 0, 0)
	var crit: Array = Threat.threats_to(grid, [neutral], player, Vector2i(2, 0))
	_check(crit.size() == 1 and bool(crit[0].high_risk), "高必杀无克制也产生黄线")


func _unit(id: StringName, faction: StringName, position: Vector2i, weapon_id: StringName, mov: int) -> Dictionary:
	return {
		id = id, faction = faction, position = position, isDead = false,
		weapon = WeaponData.WEAPONS[weapon_id].duplicate(true), moveType = &"foot",
		stats = {hp = 30, str = 10, mag = 8, skl = 8, spd = 7, luk = 4, def = 5, res = 3, mov = mov},
		hp = 30, buffs = [],
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("[battle_threat_data] " + message)
