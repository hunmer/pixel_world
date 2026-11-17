## tests/profession_growths_contract.gd — 八职业成长表（growths）契约
## 覆盖：①表形状（固定九键、int 0–100、总和 250–300、八职齐全互异）
## ②成长方向（魔法职 str=0/mag>0，物理职 str>0/mag=0，极值职业差异）
## ③创建链（create_random_unit / CampaignRoster.build_initial 新档与表逐键一致）
## ④回退与隔离（growths_for 缺键/非法值逐键回退 DEFAULT_GROWTHS、String 键等价、
## 副本互不污染）。运行：godot --headless --path . --script res://tests/profession_growths_contract.gd
extends SceneTree

const NINE_KEYS: Array[StringName] = [&"hp", &"mp", &"str", &"mag", &"skl", &"spd", &"luk", &"def", &"res"]
const PHYSICAL_PROFESSIONS: Array[StringName] = [
	&"swordsman", &"knight", &"archer", &"berserker", &"assassin", &"lancer",
]
const MAGICAL_PROFESSIONS: Array[StringName] = [&"mage", &"priest"]

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)


func _run() -> void:
	_run_table_shape()
	_run_growth_direction()
	_run_create_chain()
	_run_build_initial()
	_run_fallback_and_isolation()
	if failures == 0:
		print("PROFESSION_GROWTHS_CONTRACT_OK")
	else:
		printerr("PROFESSION_GROWTHS_CONTRACT_FAILED: %d 处失败" % failures)
	quit(0 if failures == 0 else 1)


## 取九键成长表（StringName 键）；缺失返回 {}，由调用方断言。
func _growth(prof_id: StringName) -> Dictionary:
	var prof := ProfessionData.get_profession(prof_id)
	var g: Variant = prof.get(&"growths", null)
	return g if g is Dictionary else {}


func _run_table_shape() -> void:
	var list: Array = ProfessionData.PROFESSION_LIST
	_expect(list.size() == 8, "职业数应为 8，实际 %d" % list.size())
	var expected_keys: Array = NINE_KEYS.map(func(k: StringName) -> String: return String(k))
	expected_keys.sort()
	var unique_hashes := {}
	for raw in list:
		var prof: Dictionary = raw
		var pid: StringName = prof[&"id"]
		var g := _growth(pid)
		_expect(not g.is_empty(), "%s 缺 growths" % String(pid))
		if g.is_empty():
			continue
		var got_keys: Array = g.keys().map(func(k) -> String: return String(k))
		got_keys.sort()
		_expect(got_keys == expected_keys, "%s growths 键集不符：%s" % [String(pid), str(got_keys)])
		var sum := 0
		for k in NINE_KEYS:
			var v: Variant = g.get(k, null)
			_expect(v is int and v >= 0 and v <= 100,
				"%s growths.%s 应为 int 0–100，实际 %s" % [String(pid), String(k), str(v)])
			if v is int:
				sum += v
		_expect(sum >= 250 and sum <= 300, "%s growths 总和 %d 超出 250–300" % [String(pid), sum])
		unique_hashes[g.hash()] = true
	_expect(unique_hashes.size() == 8, "八职成长表应互异（唯一表 %d/8）" % unique_hashes.size())


func _run_growth_direction() -> void:
	for pid in MAGICAL_PROFESSIONS:
		var g := _growth(pid)
		_expect(int(g.get(&"str", -1)) == 0 and int(g.get(&"mag", -1)) > 0,
			"%s 成长方向应为 str=0 且 mag>0" % String(pid))
	for pid in PHYSICAL_PROFESSIONS:
		var g := _growth(pid)
		_expect(int(g.get(&"str", -1)) > 0 and int(g.get(&"mag", -1)) == 0,
			"%s 成长方向应为 str>0 且 mag=0" % String(pid))
	# 极值差异：职业间成长侧重互不相同（数据层面锁定设计意图）
	_expect(int(_growth(&"berserker")[&"str"]) >= 55, "狂战士 str 成长应极高（≥55）")
	_expect(int(_growth(&"assassin")[&"spd"]) >= 60, "刺客 spd 成长应极高（≥60）")
	_expect(int(_growth(&"knight")[&"hp"]) >= 75, "骑士 hp 成长应极高（≥75）")
	_expect(int(_growth(&"priest")[&"res"]) >= 60, "牧师 res 成长应极高（≥60）")
	_expect(int(_growth(&"mage")[&"mag"]) >= 50, "魔导师 mag 成长应极高（≥50）")


func _run_create_chain() -> void:
	for raw in ProfessionData.PROFESSION_LIST:
		var prof: Dictionary = raw
		var pid: StringName = prof[&"id"]
		var u := UnitFactory.create_random_unit(
			StringName("cg_%s" % String(pid)), "契约", &"player", 1, Vector2i.ZERO, prof
		)
		var ug: Dictionary = u[&"growths"]
		var g := _growth(pid)
		for k in NINE_KEYS:
			_expect(int(ug.get(k, -1)) == int(g.get(k, -2)),
				"create_random_unit(%s).growths.%s 与表不一致（%d != %d）" % [
					String(pid), String(k), int(ug.get(k, -1)), int(g.get(k, -2))])
	# 不指定职业（随机池）也必须拿到九键齐全的成长表
	var rnd := UnitFactory.create_random_unit(&"cg_rand", "随机", &"player", 1, Vector2i.ZERO)
	var rg: Dictionary = rnd[&"growths"]
	for k in NINE_KEYS:
		_expect(rg.has(k), "随机职业单位 growths 缺键 %s" % String(k))


func _run_build_initial() -> void:
	var first_level := CampaignConfig.first_level_id()
	_expect(first_level != "", "CampaignConfig.first_level_id() 为空，无法测 build_initial")
	if first_level == "":
		return
	var built := CampaignRoster.build_initial(first_level)
	_expect(bool(built.get("ok", false)), "build_initial 失败：%s" % str(built.get("error", "")))
	if not bool(built.get("ok", false)):
		return
	var roster: Array = built["roster"]
	_expect(not roster.is_empty(), "build_initial roster 不应为空")
	var checked := 0
	for raw in roster:
		var unit: Dictionary = raw
		var ug: Dictionary = unit.get(&"growths", {})
		for k in NINE_KEYS:
			_expect(ug.has(k), "roster 单位 %s growths 缺键 %s" % [str(unit.get("id")), String(k)])
		var pid := StringName(String(unit.get("classId", unit.get("class", ""))))
		if ProfessionData.has_profession(pid):
			var g := _growth(pid)
			for k in NINE_KEYS:
				_expect(int(ug.get(k, -1)) == int(g.get(k, -2)),
					"build_initial 单位(%s).growths.%s 与职业表不一致" % [String(pid), String(k)])
			checked += 1
	_expect(checked >= 1, "roster 中至少应有 1 个已知职业单位被核对（实际 %d）" % checked)


func _run_fallback_and_isolation() -> void:
	# 空 prof / 缺 growths → 逐键等于 DEFAULT_GROWTHS（旧档兼容基线）
	var fallback := ProfessionData.growths_for({})
	for k in NINE_KEYS:
		_expect(int(fallback.get(k, -1)) == int(UnitFactory.DEFAULT_GROWTHS.get(k, -2)),
			"growths_for({}).%s 应等于 DEFAULT_GROWTHS" % String(k))
	# 部分缺键 + String 键（旧存档/JSON 形态）：缺失键回退，存在键保留
	var partial := ProfessionData.growths_for({"growths": {"hp": 50, "spd": 90}})
	_expect(int(partial[&"hp"]) == 50 and int(partial[&"spd"]) == 90, "growths_for 应保留已给的 String 键值")
	_expect(int(partial[&"str"]) == int(UnitFactory.DEFAULT_GROWTHS[&"str"]), "growths_for 缺键 str 应回退默认")
	# 非法值：越界夹取 0–100；非数字回退默认
	var clamped := ProfessionData.growths_for({"growths": {"str": 999, "res": -5, "luk": "x"}})
	_expect(int(clamped[&"str"]) == 100, "growths str=999 应夹取 100")
	_expect(int(clamped[&"res"]) == 0, "growths res=-5 应夹取 0")
	_expect(int(clamped[&"luk"]) == int(UnitFactory.DEFAULT_GROWTHS[&"luk"]), "growths luk 非数字应回退默认")
	# 副本隔离：改返回值不污染内部表 / 职业表，两单位互不影响
	var prof := ProfessionData.get_profession(&"swordsman")
	var g1 := ProfessionData.growths_for(prof)
	var origin_hp := int(g1[&"hp"])
	g1[&"hp"] = 0
	var g2 := ProfessionData.growths_for(prof)
	_expect(int(g2[&"hp"]) == origin_hp, "改 growths_for 返回值不应污染后续取表")
	_expect(int(prof[&"growths"][&"hp"]) == origin_hp, "改返回值不应污染职业表本体")
	var ua := UnitFactory.create_random_unit(&"iso_a", "A", &"player", 1, Vector2i.ZERO, prof)
	var ub := UnitFactory.create_random_unit(&"iso_b", "B", &"player", 1, Vector2i.ZERO, prof)
	var ga: Dictionary = ua[&"growths"]
	ga[&"hp"] = 0
	_expect(int((ub[&"growths"] as Dictionary)[&"hp"]) == origin_hp, "两单位 growths 应互不污染")
	_expect(int(ProfessionData.growths_for(prof)[&"hp"]) == origin_hp, "改单位 growths 不应影响 growths_for")
