## tests/equipment_contract.gd — 装备目录/四槽装卸/统一实际武器读取 契约
##
## 覆盖：data/equipment.json 严格装载（v1/11 件/四槽）、查询与授权、
## 事务性 equip/unequip（装上不补满、卸下超容才钳）、equipment 键可选、
## WeaponData.unit_weapon 装备优先空装回退、BuffSystem=base+装备+buff 而
## 容量=base+装备、normalize_unit_equipment 存档归一、坏档整体拒绝。
## 坏档注入：user://equipment_contract_tmp/ 临时 JSON + EquipmentData.force_reload()。

extends SceneTree

const TMP_DIR := "user://equipment_contract_tmp"

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("EQUIPMENT_CONTRACT_FAIL: " + msg)


func _mk_unit(id: String, class_id: StringName) -> Dictionary:
	return UnitFactory.create_random_unit(
		StringName(id), id, &"player", 1, Vector2i.ZERO,
		ProfessionData.get_profession(class_id)
	)


func _inject(json_text: String, fname: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var path := ProjectSettings.globalize_path(TMP_DIR + "/" + fname)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(json_text)
	f.close()
	EquipmentData.equipment_path = path
	EquipmentData.force_reload()
	return path


func _restore() -> void:
	EquipmentData.equipment_path = EquipmentData.EQUIPMENT_PATH
	EquipmentData.force_reload()


func _run() -> void:
	_test_catalog()
	_test_query_and_authorize()
	_test_factory_signature()
	_test_equip_unequip()
	_test_weapon_priority()
	_test_buff_and_capacity()
	_test_normalize()
	_test_bad_files()
	_test_injected_good_file()
	# 还原真实目录，清理临时文件
	_restore()
	var d := DirAccess.open(TMP_DIR)
	if d != null:
		for fn in d.get_files():
			d.remove(fn)
		d.change_dir("..")
		d.remove("equipment_contract_tmp")
	if failures == 0:
		print("EQUIPMENT_CONTRACT_OK")
	else:
		printerr("EQUIPMENT_CONTRACT_FAILED: %d 项断言失败" % failures)
	quit(0 if failures == 0 else 1)


# ============================================================
# 1) 真实目录装载
# ============================================================

func _test_catalog() -> void:
	var st: Dictionary = EquipmentData.load_status()
	_expect(bool(st.ok), "真实目录应装载成功，error=%s" % String(st.error))
	_expect(int(st.count) == 11, "目录应 11 件，实际 %d" % int(st.count))
	_expect(EquipmentData.SLOTS == [&"weapon", &"shield", &"armor", &"accessory"], "固定四槽不符")
	var ids := [&"ironSword", &"steelSword", &"ironLance", &"ironAxe", &"ironBow", &"fire", &"heal",
		&"leatherShield", &"kiteShield", &"campaignCloak", &"luckyPendant"]
	for id in ids:
		_expect(EquipmentData.has_entry(id), "缺少装备条目 %s" % String(id))
		_expect(EquipmentData.entry_name(id) != "", "条目 %s 无 name" % String(id))
	_expect(EquipmentData.slot_of(&"ironSword") == &"weapon", "ironSword 槽位应 weapon")
	_expect(EquipmentData.slot_of(&"leatherShield") == &"shield", "leatherShield 槽位应 shield")
	_expect(EquipmentData.slot_of(&"campaignCloak") == &"armor", "campaignCloak 槽位应 armor")
	_expect(EquipmentData.slot_of(&"luckyPendant") == &"accessory", "luckyPendant 槽位应 accessory")
	# 全条目 stats 键必须是九键子集（排除 mov）
	var nine := {}
	for k in UnitFactory.empty_stats():
		if StringName(k) != &"mov":
			nine[StringName(k)] = true
	for id in ids:
		for k in EquipmentData.get_entry(id)[&"stats"]:
			_expect(nine.has(StringName(k)), "装备 %s 加成键 %s 越界" % [String(id), String(k)])


# ============================================================
# 2) 查询与授权
# ============================================================

func _test_query_and_authorize() -> void:
	var cat_knight: Array = EquipmentData.catalog_for(&"knight")
	var ids_knight := {}
	for c in cat_knight:
		ids_knight[StringName(String(c["id"]))] = c
	_expect(ids_knight.has(&"ironLance"), "knight 目录应含 ironLance")
	_expect(not ids_knight.has(&"ironSword"), "knight 目录不应含 ironSword")
	_expect(ids_knight.has(&"leatherShield") and ids_knight.has(&"luckyPendant"), "knight 目录应含通用盾/秘宝")
	_expect(not bool(ids_knight[&"ironLance"]["universal"]), "ironLance 非通用")
	_expect(bool(ids_knight[&"leatherShield"]["universal"]), "leatherShield 应通用")
	var cat_mage: Array = EquipmentData.catalog_for(&"mage")
	var mage_ids := {}
	for c in cat_mage:
		mage_ids[StringName(String(c["id"]))] = true
	_expect(mage_ids.has(&"fire"), "mage 目录应含 fire")
	_expect(not mage_ids.has(&"ironBow"), "mage 目录不应含 ironBow")

	var knight := _mk_unit("eq_auth_knight", &"knight")
	var ok_lance: Dictionary = EquipmentData.can_equip(knight, &"ironLance")
	_expect(bool(ok_lance.ok), "knight 应能装 ironLance：%s" % String(ok_lance.reason))
	var bad_sword: Dictionary = EquipmentData.can_equip(knight, &"ironSword")
	_expect(not bool(bad_sword.ok), "knight 不应能装 ironSword")
	var ok_shield: Dictionary = EquipmentData.can_equip(knight, &"leatherShield")
	_expect(bool(ok_shield.ok), "通用皮盾任何职业可装")
	var unknown: Dictionary = EquipmentData.can_equip(knight, &"ghostGear")
	_expect(not bool(unknown.ok), "未知装备应拒绝")


# ============================================================
# 3) UnitFactory 原始签名不动：空装单位没有 equipment 键
# ============================================================

func _test_factory_signature() -> void:
	var u := _mk_unit("eq_blank", &"archer")
	_expect(not u.has(&"equipment"), "空装单位不应有 equipment 键")
	_expect(EquipmentData.equipment_of(u).is_empty(), "空装 equipment_of 应空")
	_expect(EquipmentData.stat_bonus(u, &"def") == 0, "空装加成应为 0")
	# 旧 weapon 字段仍是回退源
	var w: Dictionary = WeaponData.unit_weapon(u)
	_expect(not w.is_empty() and int(w[&"might"]) == int(u[&"weapon"][&"might"]), "空装应回退 unit.weapon")


# ============================================================
# 4) 事务性装卸
# ============================================================

func _test_equip_unequip() -> void:
	var u := _mk_unit("eq_flow", &"knight")
	# 装上不补满：HP 低于容量时不动
	u[&"hp"] = 3
	var r1: Dictionary = EquipmentData.equip(u, &"leatherShield")
	_expect(bool(r1.ok) and bool(r1.changed) and StringName(r1.prev) == &"", "皮盾首装应成功且无前装")
	_expect(int(u[&"hp"]) == 3, "装上不补满 HP")
	_expect(EquipmentData.equipment_of(u) == {&"shield": &"leatherShield"}, "槽位写入不符")
	# 幂等
	var r2: Dictionary = EquipmentData.equip(u, &"leatherShield")
	_expect(bool(r2.ok) and not bool(r2.changed), "同槽同装应幂等")
	# 同槽替换
	var r3: Dictionary = EquipmentData.equip(u, &"kiteShield")
	_expect(bool(r3.changed) and StringName(r3.prev) == &"leatherShield", "同槽替换应返回 prev")
	_expect(EquipmentData.equipment_of(u) == {&"shield": &"kiteShield"}, "替换后槽位应为 kiteShield")
	# 非法装备：整体不动（事务性）
	var r4: Dictionary = EquipmentData.equip(u, &"ironSword")
	_expect(not bool(r4.ok), "knight 装 ironSword 应拒绝")
	_expect(EquipmentData.equipment_of(u) == {&"shield": &"kiteShield"}, "失败操作不得改动槽位")
	var r5: Dictionary = EquipmentData.equip(u, &"ghostGear")
	_expect(not bool(r5.ok) and not u.has(&"ghostGear"), "未知装备应拒绝")
	# 卸下：空 dict 时 erase 键
	var r6: Dictionary = EquipmentData.unequip(u, &"shield")
	_expect(bool(r6.ok) and bool(r6.changed) and StringName(r6.prev) == &"kiteShield", "卸盾应成功")
	_expect(not u.has(&"equipment"), "空装应移除 equipment 键")
	var r7: Dictionary = EquipmentData.unequip(u, &"shield")
	_expect(bool(r7.ok) and not bool(r7.changed), "重复卸应幂等")
	var r8: Dictionary = EquipmentData.unequip(u, &"helm")
	_expect(not bool(r8.ok), "未知槽位应拒绝")
	# 卸下超容才钳：披风 hp+1
	var v := _mk_unit("eq_clamp", &"priest")
	var base_hp := int(v[&"stats"][&"hp"])
	var rc: Dictionary = EquipmentData.equip(v, &"campaignCloak")
	_expect(bool(rc.ok), "priest 应能装远征披风：%s" % String(rc.reason))
	_expect(EquipmentData.capacity_hp(v) == base_hp + 1, "披风 HP 容量应 +1")
	v[&"hp"] = base_hp + 1
	var ru: Dictionary = EquipmentData.unequip(v, &"armor")
	_expect(bool(ru.ok) and bool(ru.hp_clamped), "卸披风应触发 HP 钳制")
	_expect(int(v[&"hp"]) == base_hp, "HP 应钳回 base")
	# 装上高于容量不钳（装上不补满也不削）
	var v2 := _mk_unit("eq_clamp2", &"priest")
	v2[&"hp"] = int(v2[&"stats"][&"hp"]) - 2
	EquipmentData.equip(v2, &"campaignCloak")
	_expect(int(v2[&"hp"]) == int(v2[&"stats"][&"hp"]) - 2, "装上不改变当前 HP")


# ============================================================
# 5) 统一实际武器读取
# ============================================================

func _test_weapon_priority() -> void:
	var u := _mk_unit("eq_weapon", &"assassin")
	# UnitFactory 给 sword 职业默认铁剑
	_expect(int(u[&"weapon"][&"might"]) == 5, "assassin 默认武器应为铁剑")
	var r: Dictionary = EquipmentData.equip(u, &"steelSword")
	_expect(bool(r.ok), "assassin 应能装钢剑：%s" % String(r.reason))
	var w: Dictionary = WeaponData.unit_weapon(u)
	_expect(StringName(w[&"id"]) == &"steelSword" and int(w[&"might"]) == 8, "装备后实际武器应为钢剑")
	_expect(int(u[&"weapon"][&"might"]) == 5, "旧 weapon 字段不得被覆写")
	EquipmentData.unequip(u, &"weapon")
	var w2: Dictionary = WeaponData.unit_weapon(u)
	_expect(StringName(w2[&"id"]) == &"ironSword", "卸下后应回退 unit.weapon 铁剑")


# ============================================================
# 6) 有效属性 = base+装备+buff；容量 = base+装备
# ============================================================

func _test_buff_and_capacity() -> void:
	var u := _mk_unit("eq_buff", &"knight")
	var def_base := int(u[&"stats"][&"def"])
	EquipmentData.equip(u, &"leatherShield")
	_expect(BuffSystem.effective_stat(u, &"def") == def_base + 1, "有效 def 应=base+装备")
	BuffSystem.apply_buff(u, &"def", 2, 1, "契约测试")
	_expect(BuffSystem.effective_stat(u, &"def") == def_base + 3, "有效 def 应=base+装备+buff")
	# hp 语义：buff 抬有效值但不抬容量
	var hp_base := int(u[&"stats"][&"hp"])
	BuffSystem.apply_buff(u, &"hp", 2, 1, "契约测试")
	_expect(BuffSystem.effective_stat(u, &"hp") == hp_base + 2, "有效 hp 含 buff")
	_expect(EquipmentData.capacity_hp(u) == hp_base, "HP 容量不含 buff")
	_expect(EquipmentData.capacity_mp(u) == int(u[&"stats"][&"mp"]), "MP 容量=base（无 mp 装备）")
	# 披风 hp+1：容量=base+1，有效=base+1+buff
	var v := _mk_unit("eq_buff2", &"mage")
	var hp_b := int(v[&"stats"][&"hp"])
	EquipmentData.equip(v, &"campaignCloak")
	BuffSystem.apply_buff(v, &"hp", 2, 1, "契约测试")
	_expect(EquipmentData.capacity_hp(v) == hp_b + 1, "披风容量=base+1")
	_expect(BuffSystem.effective_stat(v, &"hp") == hp_b + 3, "有效 hp=base+装备+buff")


# ============================================================
# 7) 存档归一
# ============================================================

func _test_normalize() -> void:
	var a := _mk_unit("eq_norm_a", &"knight")
	_expect(EquipmentData.normalize_unit_equipment(a) == "", "无 equipment 键应直接通过")
	var b := _mk_unit("eq_norm_b", &"knight")
	b["equipment"] = {"shield": "leatherShield", "accessory": "luckyPendant"}  # String 键（JSON 往返态）
	var err_b := EquipmentData.normalize_unit_equipment(b)
	_expect(err_b == "", "合法 String 键应归一通过：%s" % err_b)
	var eq_b: Dictionary = EquipmentData.equipment_of(b)
	_expect(eq_b.has(&"shield") and StringName(eq_b[&"shield"]) == &"leatherShield", "归一后应为 StringName 键")
	var c := _mk_unit("eq_norm_c", &"knight")
	c["equipment"] = {"shield": "ghostGear"}
	_expect(EquipmentData.normalize_unit_equipment(c) != "", "未知装备应报错")
	var d := _mk_unit("eq_norm_d", &"knight")
	d["equipment"] = {"weapon": "leatherShield"}
	_expect(EquipmentData.normalize_unit_equipment(d) != "", "槽位不符应报错")
	var e := _mk_unit("eq_norm_e", &"knight")
	e["equipment"] = {"weapon": "ironSword"}
	_expect(EquipmentData.normalize_unit_equipment(e) != "", "职业授权失效应报错（knight 装 ironSword）")
	var f := _mk_unit("eq_norm_f", &"knight")
	f["equipment"] = ["shield"]
	_expect(EquipmentData.normalize_unit_equipment(f) != "", "非对象 equipment 应报错")


# ============================================================
# 8) 坏档整体拒绝（任一条目非法 → 目录清空 + 明确错误）
# ============================================================

func _test_bad_files() -> void:
	var good_entry := '{"id":"t1","name":"T1","slot":"weapon","stats":{"str":1},"allowed_professions":["swordsman"],"weapon_id":"ironSword","iconId":"01","acquisition":"test"}'
	var cases := [
		["坏版本", '{"version":2,"equipment":[]}'],
		["根非对象", '[]'],
		["缺条目数组", '{"version":1}'],
		["weapon槽缺weapon_id", '{"version":1,"equipment":[{"id":"t1","name":"T1","slot":"weapon","stats":{"str":1},"allowed_professions":["swordsman"],"iconId":"01","acquisition":"test"}]}'],
		["weapon槽通用", '{"version":1,"equipment":[{"id":"t1","name":"T1","slot":"weapon","stats":{"str":1},"allowed_professions":[],"weapon_id":"ironSword","iconId":"01","acquisition":"test"}]}'],
		["未知武器", '{"version":1,"equipment":[{"id":"t1","name":"T1","slot":"weapon","stats":{"str":1},"allowed_professions":["swordsman"],"weapon_id":"excalibur","iconId":"01","acquisition":"test"}]}'],
		["武器类型不一致", '{"version":1,"equipment":[{"id":"t1","name":"T1","slot":"weapon","stats":{"str":1},"allowed_professions":["assassin"],"weapon_id":"ironLance","iconId":"01","acquisition":"test"}]}'],
		["非weapon槽带weapon_id", '{"version":1,"equipment":[{"id":"t1","name":"T1","slot":"shield","stats":{"def":1},"allowed_professions":[],"weapon_id":"ironSword","iconId":"01","acquisition":"test"}]}'],
		["bool加成", '{"version":1,"equipment":[{"id":"t1","name":"T1","slot":"shield","stats":{"def":true},"allowed_professions":[],"iconId":"01","acquisition":"test"}]}'],
		["零加成", '{"version":1,"equipment":[{"id":"t1","name":"T1","slot":"shield","stats":{"def":0},"allowed_professions":[],"iconId":"01","acquisition":"test"}]}'],
		["mov加成", '{"version":1,"equipment":[{"id":"t1","name":"T1","slot":"shield","stats":{"mov":1},"allowed_professions":[],"iconId":"01","acquisition":"test"}]}'],
		["未知职业", '{"version":1,"equipment":[{"id":"t1","name":"T1","slot":"shield","stats":{"def":1},"allowed_professions":["ninja"],"iconId":"01","acquisition":"test"}]}'],
		["重复id", '{"version":1,"equipment":[%s,%s]}' % [good_entry, good_entry]],
		["未知iconId", '{"version":1,"equipment":[{"id":"t1","name":"T1","slot":"shield","stats":{"def":1},"allowed_professions":[],"iconId":"zz","acquisition":"test"}]}'],
		["缺name", '{"version":1,"equipment":[{"id":"t1","slot":"shield","stats":{"def":1},"allowed_professions":[],"iconId":"01","acquisition":"test"}]}'],
		["坏槽位", '{"version":1,"equipment":[{"id":"t1","name":"T1","slot":"helm","stats":{"def":1},"allowed_professions":[],"iconId":"01","acquisition":"test"}]}'],
	]
	for i in cases.size():
		var label: String = cases[i][0]
		var body: String = cases[i][1]
		_inject(body, "bad_%d.json" % i)
		var st: Dictionary = EquipmentData.load_status()
		_expect(not bool(st.ok) and String(st.error) != "", "[%s] 应拒绝装载" % label)
		_expect(not EquipmentData.has_entry(&"ironSword"), "[%s] 坏档应清空目录" % label)
		_expect(EquipmentData.stat_bonus(_mk_unit("eq_bad_%d" % i, &"knight"), &"def") == 0, "[%s] 目录失效时加成为 0" % label)
	# 好档在坏档之后仍可恢复
	_restore()
	var st2: Dictionary = EquipmentData.load_status()
	_expect(bool(st2.ok) and int(st2.count) == 11, "恢复真实目录应重新装载 11 件")


# ============================================================
# 9) 注入好档：mp 加成与 MP 钳制路径（真实目录无 mp 装备）
# ============================================================

func _test_injected_good_file() -> void:
	_inject('{"version":1,"equipment":[{"id":"blueRobe","name":"蓝袍","slot":"armor","stats":{"mp":2,"res":1},"allowed_professions":[],"iconId":"01","acquisition":"test"}]}', "good_mp.json")
	var st: Dictionary = EquipmentData.load_status()
	_expect(bool(st.ok) and int(st.count) == 1, "注入蓝袍应装载 1 件：%s" % String(st.error))
	var u := _mk_unit("eq_mp", &"mage")
	var mp_base := int(u[&"stats"][&"mp"])
	var r: Dictionary = EquipmentData.equip(u, &"blueRobe")
	_expect(bool(r.ok), "蓝袍应可装：%s" % String(r.reason))
	_expect(EquipmentData.capacity_mp(u) == mp_base + 2, "MP 容量应 +2")
	_expect(BuffSystem.effective_stat(u, &"res") == int(u[&"stats"][&"res"]) + 1, "res 有效值含装备")
	u[&"mp"] = mp_base + 2
	var ru: Dictionary = EquipmentData.unequip(u, &"armor")
	_expect(bool(ru.mp_clamped) and int(u[&"mp"]) == mp_base, "卸蓝袍应触发 MP 钳制")
	# 恢复真实目录（_run 末尾统一清理）
	_restore()
