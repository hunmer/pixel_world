## core/equipment.gd — 装备目录与四槽装卸（全静态）
##
## 数据源 res://data/equipment.json（v1）。固定四槽：weapon / shield / armor / accessory。
## 条目形状（加载时归一）：{ id:StringName, name:String, slot:StringName,
##   stats:Dictionary(StringName->int 正加成，九键子集，不含 mov),
##   allowed_professions:Array[StringName]（空 = 通用）, weapon_id:StringName（仅 weapon 槽）,
##   icon_id:String(SkillIcons 稳定 ID), acquisition:String }。
##
## 严格校验：任何一条非法 → 整目录置空并 push_error（查询一律回退"无装备"，
## 游戏不崩但装备全失效）；load_status() 供契约测试取失败原因。
## 授权 = allowed_professions（空通用）+ 已知职业 + weapon 槽与职业 weaponType 一致。
##
## 单位侧约定：unit.equipment 为「可选」槽位->装备 ID 字典（空装单位没有该键，
## UnitFactory 原始签名不动）；装卸事务性 = 先校验后单点写入；装上不补满 HP/MP，
## 卸下只在超出新容量时钳制。既有 items.json equip 环（unit.equipped 戒指）与本系统
## 互不接触：那是 ItemSystem 的永久 stats 改写路径，这里是槽位字典。
##
## 循环依赖：与 WeaponData / ProfessionData 一样以 class_name 静态体互引
## （weapons.gd <-> professions.gd 已有同款先例），不建 const preload 环。

class_name EquipmentData
extends RefCounted

const VERSION: int = 1
const EQUIPMENT_PATH: String = "res://data/equipment.json"
const SLOTS: Array[StringName] = [&"weapon", &"shield", &"armor", &"accessory"]

## 测试可换源（坏档注入）。改后调用 force_reload()。
static var equipment_path: String = EQUIPMENT_PATH

static var _entries: Dictionary = {}   # id:StringName -> entry
static var _loaded: bool = false
static var _last_error: String = ""


# ============================================================
# 目录装载与校验
# ============================================================

static func _ensure_loaded() -> void:
	if _loaded:
		return
	force_reload()


## 强制重新装载（测试注入坏档后用）。注意不能命名 reload()：会撞 GDScript 资源原生
## reload()（重编译脚本并重置 static var）。任何失败都会清空目录并记录错误。
static func force_reload() -> void:
	_loaded = true
	_last_error = ""
	_entries = {}
	if not FileAccess.file_exists(equipment_path):
		_last_error = "装备目录不存在：%s" % equipment_path
		push_error("[equipment] " + _last_error)
		return
	var f := FileAccess.open(equipment_path, FileAccess.READ)
	if f == null:
		_last_error = "装备目录无法打开：%s" % equipment_path
		push_error("[equipment] " + _last_error)
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		_last_error = "装备目录不是 JSON 对象"
		push_error("[equipment] " + _last_error)
		return
	var root: Dictionary = parsed
	var ver: Variant = _json_int(root.get("version", null))
	if ver == null or int(ver) != VERSION:
		_last_error = "装备目录版本不支持：%s（当前 %d）" % [str(root.get("version", null)), VERSION]
		push_error("[equipment] " + _last_error)
		return
	var raw_entries: Variant = root.get("equipment", null)
	if raw_entries is not Array:
		_last_error = "equipment 不是数组"
		push_error("[equipment] " + _last_error)
		return
	var seen := {}  # String id -> true，查重
	var stat_keys := _equippable_stat_keys()
	for i in raw_entries.size():
		var err := _validate_entry(raw_entries[i], i, seen, stat_keys)
		if err != "":
			_last_error = err
			push_error("[equipment] " + err)
			_entries = {}
			return


## 可作为装备加成的属性键（九键，排除 mov）。
static func _equippable_stat_keys() -> Dictionary:
	var keys := {}
	for k in UnitFactory.empty_stats():
		if StringName(k) != &"mov":
			keys[StringName(k)] = true
	return keys


## JSON 数字一律解析为 float：整数判定 = int 或整值 float；bool 明确拒绝（返回 null）。
static func _json_int(v: Variant) -> Variant:
	if v is bool:
		return null
	if v is int:
		return v
	if v is float and is_finite(v) and v == floorf(v):
		return int(v)
	return null


## 校验并归一单条目（就地写入归一结果）。返回 "" 或错误描述。
static func _validate_entry(raw: Variant, index: int, seen: Dictionary, stat_keys: Dictionary) -> String:
	if raw is not Dictionary:
		return "equipment[%d] 不是对象" % index
	var src: Dictionary = raw
	var id_str := String(src.get("id", ""))
	if id_str.strip_edges() == "":
		return "equipment[%d] 缺少 id" % index
	var id := StringName(id_str)
	if seen.has(id_str):
		return "装备 id 重复：%s" % id_str
	var slot := StringName(String(src.get("slot", "")))
	if not SLOTS.has(slot):
		return "装备 %s 槽位非法：%s（固定四槽 %s）" % [id_str, String(slot), str(SLOTS)]
	var name_str := String(src.get("name", ""))
	if name_str.strip_edges() == "":
		return "装备 %s 缺少 name" % id_str
	# stats：非空、九键子集、正整数加成（bool 一律拒绝）
	var raw_stats: Variant = src.get("stats", null)
	if raw_stats is not Dictionary or (raw_stats as Dictionary).is_empty():
		return "装备 %s stats 必须是非空对象" % id_str
	var stats := {}
	for k in raw_stats:
		var sk := StringName(String(k))
		if not stat_keys.has(sk):
			return "装备 %s 属性 %s 不可加成（九键子集，不含 mov）" % [id_str, String(sk)]
		var sv: Variant = _json_int((raw_stats as Dictionary)[k])
		if sv == null or int(sv) < 1:
			return "装备 %s 加成 %s 必须是 >=1 的整数：%s" % [id_str, String(sk), str((raw_stats as Dictionary)[k])]
		stats[sk] = int(sv)
	# allowed_professions：数组，逐项已知职业；空 = 通用
	var raw_allowed: Variant = src.get("allowed_professions", null)
	if raw_allowed is not Array:
		return "装备 %s allowed_professions 不是数组" % id_str
	var allowed: Array[StringName] = []
	for p in raw_allowed:
		var pid := StringName(String(p))
		if not ProfessionData.has_profession(pid):
			return "装备 %s 授权未知职业：%s" % [id_str, String(pid)]
		if not allowed.has(pid):
			allowed.append(pid)
	# weapon_id：weapon 槽必有且类型与全部授权职业一致；非 weapon 槽禁止携带
	var weapon_id := &""
	var has_weapon_key: bool = src.has("weapon_id")
	if slot == &"weapon":
		if not has_weapon_key:
			return "weapon 槽装备 %s 缺少 weapon_id" % id_str
		weapon_id = StringName(String(src.get("weapon_id", "")))
		if not WeaponData.WEAPONS.has(weapon_id):
			return "weapon 槽装备 %s 引用未知武器：%s" % [id_str, String(weapon_id)]
		if allowed.is_empty():
			return "weapon 槽装备 %s 必须声明 allowed_professions（通用武器绕过类型一致性）" % id_str
		var wtype: StringName = WeaponData.WEAPONS[weapon_id][&"type"]
		for pid in allowed:
			var prof := ProfessionData.get_profession(pid)
			if prof.is_empty() or StringName(prof[&"weaponType"]) != wtype:
				return "装备 %s 授权职业 %s 的武器类型与 %s 不一致" % [id_str, String(pid), String(weapon_id)]
	elif has_weapon_key:
		return "非 weapon 槽装备 %s 不得携带 weapon_id" % id_str
	# iconId：SkillIcons 已知稳定 ID
	var icon_id := String(src.get("iconId", ""))
	if icon_id == "" or not SkillIcons.has_icon(StringName(icon_id)):
		return "装备 %s iconId 非法：%s" % [id_str, icon_id]
	var acquisition := String(src.get("acquisition", ""))
	if acquisition.strip_edges() == "":
		return "装备 %s 缺少 acquisition" % id_str
	seen[id_str] = true
	_entries[id] = {
		id = id,
		name = name_str,
		slot = slot,
		stats = stats,
		allowed_professions = allowed,
		weapon_id = weapon_id,
		icon_id = icon_id,
		acquisition = acquisition,
	}
	return ""


## 装载状态（契约测试用）：{ ok:bool, error:String, count:int }。
static func load_status() -> Dictionary:
	_ensure_loaded()
	return { ok = _last_error == "", error = _last_error, count = _entries.size() }


# ============================================================
# 目录查询
# ============================================================

static func has_entry(id: StringName) -> bool:
	_ensure_loaded()
	return _entries.has(id)


## 取条目（内部字典，调用方只读；未知返回 {}）。
static func get_entry(id: StringName) -> Dictionary:
	_ensure_loaded()
	return _entries.get(id, {})


static func entry_name(id: StringName) -> String:
	_ensure_loaded()
	var e: Dictionary = _entries.get(id, {})
	return String(e.get(&"name", "")) if not e.is_empty() else ""


static func slot_of(id: StringName) -> StringName:
	_ensure_loaded()
	var e: Dictionary = _entries.get(id, {})
	return StringName(e.get(&"slot", &"")) if not e.is_empty() else &""


## 该职业可穿的条目摘要（通用 + 显式授权），供营地装卸 UI。
## 形状：[{ id:String, name:String, slot:String, icon_id:String, stats:Dictionary, universal:bool }]
static func catalog_for(class_id: StringName) -> Array:
	_ensure_loaded()
	var out: Array = []
	for key in _entries:
		var e: Dictionary = _entries[key]
		var allowed: Array = e[&"allowed_professions"]
		if not allowed.is_empty() and not allowed.has(class_id):
			continue
		out.append({
			id = String(e[&"id"]),
			name = String(e[&"name"]),
			slot = String(e[&"slot"]),
			icon_id = String(e[&"icon_id"]),
			stats = (e[&"stats"] as Dictionary).duplicate(),
			universal = allowed.is_empty(),
		})
	return out


## 授权检查：{ ok:bool, reason:String, slot:StringName }。不检查槽位占用。
static func can_equip(unit: Dictionary, entry_id: StringName) -> Dictionary:
	_ensure_loaded()
	var e: Dictionary = _entries.get(entry_id, {})
	if e.is_empty():
		return { ok = false, reason = "未知装备：%s" % String(entry_id), slot = &"" }
	var slot: StringName = e[&"slot"]
	var class_id := StringName(String(unit.get(&"classId", "")))
	var allowed: Array = e[&"allowed_professions"]
	if not allowed.is_empty():
		if not ProfessionData.has_profession(class_id):
			return { ok = false, reason = "单位职业未知：%s" % String(class_id), slot = slot }
		if not allowed.has(class_id):
			return { ok = false, reason = "%s 不能装备 %s（职业不符）" % [String(class_id), String(entry_id)], slot = slot }
	if slot == &"weapon":
		# 数据装载期已保证类型一致；这里兜底挡住 classId 与档内数据错配的单位。
		var prof := ProfessionData.get_profession(class_id)
		var wtype: StringName = WeaponData.WEAPONS[e[&"weapon_id"]][&"type"]
		if prof.is_empty() or StringName(prof[&"weaponType"]) != wtype:
			return { ok = false, reason = "%s 武器类型与 %s 不一致" % [String(class_id), String(entry_id)], slot = slot }
	return { ok = true, reason = "", slot = slot }


# ============================================================
# 单位槽位状态（unit.equipment：可选 槽位->装备ID 字典）
# ============================================================

## 当前装备快照（{ 槽位:StringName -> 装备ID:StringName }；无装备返回 {}）。
## 兼容 String 键（存档解码未归一前的中间态）。
static func equipment_of(unit: Dictionary) -> Dictionary:
	var raw: Variant = unit.get(&"equipment", null)
	if raw is not Dictionary:
		return {}
	var out := {}
	for k in raw:
		var slot := StringName(String(k))
		if SLOTS.has(slot):
			out[slot] = StringName(String((raw as Dictionary)[k]))
	return out


static func _slot_load(eq: Dictionary, slot: StringName) -> StringName:
	if eq.has(slot):
		return StringName(String(eq[slot]))
	if eq.has(String(slot)):
		return StringName(String(eq[String(slot)]))
	return &""


## 装备加成合计：九键 -> int（无装备/目录失效一律 0，不参与结算）。
static func stat_bonuses(unit: Dictionary) -> Dictionary:
	var out := {}
	_ensure_loaded()
	var eq := equipment_of(unit)
	for slot in eq:
		var e: Dictionary = _entries.get(eq[slot], {})
		if e.is_empty():
			continue
		for k in e[&"stats"]:
			out[k] = int(out.get(k, 0)) + int(e[&"stats"][k])
	return out


## 单键装备加成（BuffSystem.effective_stat 每次取值调用，保持轻量）。
static func stat_bonus(unit: Dictionary, stat: StringName) -> int:
	var eq := equipment_of(unit)
	if eq.is_empty():
		return 0
	if not _loaded:
		_ensure_loaded()
	var total := 0
	for slot in eq:
		var e: Dictionary = _entries.get(eq[slot], {})
		if e.is_empty():
			continue
		total += int((e[&"stats"] as Dictionary).get(stat, 0))
	return total


## HP 容量 = base stats + 装备（不含 buff；治疗/药水上限与营地补满都用它）。
static func capacity_hp(unit: Dictionary) -> int:
	return int((unit.get(&"stats", {}) as Dictionary).get(&"hp", 0)) + stat_bonus(unit, &"hp")


## MP 容量 = base stats + 装备。
static func capacity_mp(unit: Dictionary) -> int:
	return int((unit.get(&"stats", {}) as Dictionary).get(&"mp", 0)) + stat_bonus(unit, &"mp")


## 已装备的实际武器 id（weapon 槽条目解析 weapon_id；无/失效返回 &""）。
## WeaponData.unit_weapon 据此做「装备优先，空装回退 unit.weapon」。
static func equipped_weapon_id(unit: Dictionary) -> StringName:
	var eq := equipment_of(unit)
	if eq.is_empty():
		return &""
	var entry_id := _slot_load(eq, &"weapon")
	if entry_id == &"":
		return &""
	if not _loaded:
		_ensure_loaded()
	var e: Dictionary = _entries.get(entry_id, {})
	if e.is_empty():
		return &""
	return StringName(e[&"weapon_id"])


# ============================================================
# 事务性装卸
# ============================================================

## 装上：校验通过后单点写入 unit.equipment[slot]（替换旧装备，返回 prev）。
## 不改 HP/MP（装上不补满）；同槽同装幂等（changed=false）。
## 返回 { ok, reason, changed, prev:StringName, slot:StringName }。
static func equip(unit: Dictionary, entry_id: StringName) -> Dictionary:
	var check := can_equip(unit, entry_id)
	if not bool(check.ok):
		return { ok = false, reason = String(check.reason), changed = false, prev = &"", slot = check.slot }
	var slot: StringName = check.slot
	var eq := equipment_of(unit)
	var prev := _slot_load(eq, slot)
	if prev == entry_id:
		return { ok = true, reason = "", changed = false, prev = prev, slot = slot }
	eq[slot] = entry_id
	unit[&"equipment"] = eq   # 单点写入：要么整体生效，要么不动
	return { ok = true, reason = "", changed = true, prev = prev, slot = slot }


## 卸下：移除槽位条目；只在 HP/MP 超出新容量时钳制（卸下才钳，装上不补满）。
## 返回 { ok, reason, changed, prev, slot, hp_clamped, mp_clamped }。
static func unequip(unit: Dictionary, slot: StringName) -> Dictionary:
	if not SLOTS.has(slot):
		return { ok = false, reason = "未知槽位：%s" % String(slot), changed = false, prev = &"", slot = slot, hp_clamped = false, mp_clamped = false }
	var eq := equipment_of(unit)
	var prev := _slot_load(eq, slot)
	if prev == &"":
		return { ok = true, reason = "", changed = false, prev = &"", slot = slot, hp_clamped = false, mp_clamped = false }
	var eq_new := eq.duplicate()
	eq_new.erase(slot)
	if eq_new.is_empty():
		# 保持「空装单位没有 equipment 键」约定
		unit.erase(&"equipment")
	else:
		unit[&"equipment"] = eq_new
	var hp_c := false
	var mp_c := false
	if unit.has(&"hp"):
		var cap := capacity_hp(unit)
		if int(unit[&"hp"]) > cap:
			unit[&"hp"] = cap
			hp_c = true
	if unit.has(&"mp"):
		var cap_m := capacity_mp(unit)
		if int(unit[&"mp"]) > cap_m:
			unit[&"mp"] = cap_m
			mp_c = true
	return { ok = true, reason = "", changed = true, prev = prev, slot = slot, hp_clamped = hp_c, mp_clamped = mp_c }


# ============================================================
# 存档归一（codec 钩子：字段存在才严格校验，String 键归一 StringName）
# ============================================================

## 校验并就地归一 unit.equipment（无该键直接通过）。
## 校验：形状、槽位合法、条目存在、槽位类型一致、职业授权一致。
## 返回 "" 或错误描述（codec 层转为存档报错）。
static func normalize_unit_equipment(unit: Dictionary) -> String:
	if not unit.has(&"equipment") and not unit.has("equipment"):
		return ""
	var raw: Variant = unit.get(&"equipment", unit.get("equipment", null))
	if raw is not Dictionary:
		return "单位 %s equipment 不是对象" % String(unit.get(&"id", "?"))
	_ensure_loaded()
	var eq_in: Dictionary = raw
	var eq_out := {}
	for k in eq_in:
		var slot := StringName(String(k))
		if not SLOTS.has(slot):
			return "单位 %s 装备槽位非法：%s" % [String(unit.get(&"id", "?")), String(k)]
		var entry_id := StringName(String(eq_in[k]))
		var e: Dictionary = _entries.get(entry_id, {})
		if e.is_empty():
			return "单位 %s 引用未知装备：%s" % [String(unit.get(&"id", "?")), String(entry_id)]
		if StringName(e[&"slot"]) != slot:
			return "单位 %s 装备 %s 槽位不符（%s 应在 %s 槽）" % [String(unit.get(&"id", "?")), String(entry_id), String(entry_id), String(e[&"slot"])]
		eq_out[slot] = entry_id
	# 授权一致性（职业不符的存档视为坏档）
	var check := { ok = true, reason = "" }
	for slot in eq_out:
		check = can_equip(unit, eq_out[slot])
		if not bool(check.ok):
			return "单位 %s 装备授权失效：%s" % [String(unit.get(&"id", "?")), String(check.reason)]
	unit[&"equipment"] = eq_out
	return ""
