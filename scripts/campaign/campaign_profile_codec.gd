## campaign_profile_codec.gd — 冒险档案磁盘编码/解码/归一化
##
## 职责：内存态 profile state <-> 磁盘 record 的互转与校验。
## - capture(state) -> record：先按原生形状校验归一化，再经 BattleSaveCodec.encode 落盘。
## - restore(record) -> state：decode 后逐字段校验（含单位归一化，范式对齐 battle_save_codec），
##   版本更新拒绝（newer=true），损坏返回错误（上层回退 .bak）。
## - summarize(record)：restore 的轻量摘要（列表用）。
##
## 单位归一化比 battle_save_codec 宽松两点（Hub 语境）：坐标不做地图越界/重叠检查；
## 其余（职业存在性、stats/growths/weapon/skills/items/buffs/cooldowns）一致。

class_name CampaignProfileCodec
extends RefCounted

const VERSION := 1

const BattleSaveCodecScript := preload("res://scripts/core/battle_save_codec.gd")
const ItemDataScript := preload("res://scripts/core/items.gd")
const ProfessionDataScript := preload("res://scripts/core/professions.gd")
const SkillDataScript := preload("res://scripts/core/skills.gd")
const EnumsScript := preload("res://scripts/core/enums.gd")
const UnitFactoryScript := preload("res://scripts/core/unit.gd")
const EquipmentDataScript := preload("res://scripts/core/equipment.gd")
const AIDifficultyScript := preload("res://scripts/systems/ai_difficulty.gd")

const UNIT_INT_FIELDS: Array[String] = ["level", "exp", "hp", "mp"]
const UNIT_BOOL_FIELDS: Array[String] = ["hasMoved", "hasActed", "isDead"]
const WEAPON_INT_FIELDS: Array[String] = ["might", "hit", "crit", "weight", "uses"]


## ItemData.get_item 对未知 id 会静默回退默认物品（hpPotion）而非返回空，
## 故用「返回条目的 id 是否等于请求 id」判存在性；技能同理（回退 fireball）。
static func item_exists(iid: StringName) -> bool:
	return ItemDataScript.get_item(iid).get("id", &"") == iid


static func skill_exists(sid: StringName) -> bool:
	return SkillDataScript.get_skill(sid).get("id", &"") == sid


## 内存态 -> 磁盘 record。state 见 campaign_session：id/name/gold/roster/inventory/
## completed_levels/carry_templates/created_at/saved_at/(attempt 可选)。
static func capture(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return {"ok": false, "error": "档案状态为空"}
	var err := _validate_head(state)
	if err != "":
		return {"ok": false, "error": err}
	err = _validate_roster(state.roster)
	if err != "":
		return {"ok": false, "error": "队伍校验失败：%s" % err}
	err = _normalize_inventory(state.inventory)
	if err != "":
		return {"ok": false, "error": "库存校验失败：%s" % err}
	err = _normalize_templates(state.carry_templates)
	if err != "":
		return {"ok": false, "error": "携带方案校验失败：%s" % err}
	var purchases: Dictionary = _normalize_purchases(state.get("shop_purchases", null))
	if not purchases.get("ok", false):
		return {"ok": false, "error": "限购记录校验失败：%s" % str(purchases.error)}
	# 难度档（v1 存量档无此字段 → DEFAULT；capture 严格校验，防坏值落盘）
	var difficulty_raw: Variant = state.get("difficulty", AIDifficultyScript.DEFAULT)
	if not AIDifficultyScript.validate(difficulty_raw):
		return {"ok": false, "error": "难度档非法：%s" % str(difficulty_raw)}
	var attempt: Variant = null
	if state.get("attempt", null) != null:
		var marker: Dictionary = state.attempt
		if str(marker.get("level_id", "")) == "":
			return {"ok": false, "error": "attempt 标记缺少 level_id"}
		attempt = {
			"level_id": str(marker.level_id),
			"prepared_at": float(marker.get("prepared_at", 0.0)),
		}
	var record := {
		"version": VERSION,
		"id": str(state.id),
		"name": str(state.name),
		"gold": int(state.gold),
		"roster": state.roster.duplicate(true),
		"inventory": state.inventory.duplicate(true),
		"completed_levels": state.completed_levels.duplicate(true),
		"carry_templates": state.carry_templates.duplicate(true),
		"shop_purchases": (purchases.value as Dictionary).duplicate(true),
		"created_at": float(state.get("created_at", 0.0)),
		"saved_at": float(state.get("saved_at", 0.0)),
		"attempt": attempt,
		"last_opened_level": str(state.get("last_opened_level", "")).strip_edges(),
		"difficulty": str(difficulty_raw),
	}
	return {"ok": true, "record": BattleSaveCodecScript.encode(record)}


## 磁盘 record -> 内存态。版本更新返回 {ok:false, newer:true}；其余失败返回错误
## （上层回退 .bak 或标记不可读）。
static func restore(record: Variant) -> Dictionary:
	if record is not Dictionary:
		return {"ok": false, "newer": false, "error": "档案不是对象"}
	var decoded: Variant = BattleSaveCodecScript.decode(record)
	if decoded is not Dictionary:
		return {"ok": false, "newer": false, "error": "档案解码失败"}
	var data: Dictionary = decoded
	var raw_version: Variant = data.get("version", null)
	var version_check := _validate_version(raw_version)
	if not version_check.get("ok", false):
		return {"ok": false, "newer": false, "error": str(version_check.error)}
	var version: int = int(version_check.version)
	if version > VERSION:
		return {"ok": false, "newer": true, "error": "档案来自更新版本的游戏（v%d > v%d）" % [version, VERSION]}
	if version < VERSION:
		return {"ok": false, "newer": false, "error": "档案版本过旧（v%d）且无迁移" % version}
	var err := _validate_head(data)
	if err != "":
		return {"ok": false, "newer": false, "error": err}
	var roster: Variant = data.get("roster", [])
	if roster is not Array:
		return {"ok": false, "newer": false, "error": "roster 不是数组"}
	err = _validate_roster(roster)
	if err != "":
		return {"ok": false, "newer": false, "error": "队伍校验失败：%s" % err}
	var inventory: Variant = data.get("inventory", [])
	if inventory is not Array:
		return {"ok": false, "newer": false, "error": "inventory 不是数组"}
	err = _normalize_inventory(inventory)
	if err != "":
		return {"ok": false, "newer": false, "error": "库存校验失败：%s" % err}
	var completed: Variant = data.get("completed_levels", [])
	if completed is not Array:
		return {"ok": false, "newer": false, "error": "completed_levels 不是数组"}
	var completed_out: Array = []
	for level_id: Variant in completed:
		var id_str := str(level_id).strip_edges()
		if id_str != "" and not completed_out.has(id_str):
			completed_out.append(id_str)
	var templates: Variant = data.get("carry_templates", [])
	if templates is not Array:
		return {"ok": false, "newer": false, "error": "carry_templates 不是数组"}
	err = _normalize_templates(templates)
	if err != "":
		return {"ok": false, "newer": false, "error": "携带方案校验失败：%s" % err}
	var attempt: Variant = data.get("attempt", null)
	if attempt != null and attempt is not Dictionary:
		return {"ok": false, "newer": false, "error": "attempt 标记不是对象"}
	var purchases: Dictionary = _normalize_purchases(data.get("shop_purchases", null))
	if not purchases.get("ok", false):
		return {"ok": false, "newer": false, "error": "限购记录校验失败：%s" % str(purchases.error)}
	return {
		"ok": true,
		"state": {
			"id": str(data.id),
			"name": str(data.name),
			"gold": int(data.gold),
			"roster": roster,
			"inventory": inventory,
			"completed_levels": completed_out,
			"carry_templates": templates,
			"shop_purchases": purchases.value,
			"created_at": float(data.get("created_at", 0.0)),
			"saved_at": float(data.get("saved_at", 0.0)),
			"attempt": attempt,
			"last_opened_level": str(data.get("last_opened_level", "")).strip_edges(),
			# 旧档无 difficulty → DEFAULT；档内非法值按运行时宽容口径归一（normalize）
			"difficulty": str(AIDifficultyScript.normalize(data.get("difficulty", AIDifficultyScript.DEFAULT))),
		},
	}


## 版本号严格校验：只接受整数语义的数字（int 或整值 float；JSON 数字经 decode
## 后整值已是 int）。拒绝字符串、布尔、分数（1.5 截断成 1 会伪装成合法版本）、
## 非有限数（NaN/inf）与缺失。
static func _validate_version(raw: Variant) -> Dictionary:
	var t := typeof(raw)
	if t == TYPE_BOOL or not (t == TYPE_INT or t == TYPE_FLOAT):
		return {"ok": false, "error": "档案版本号必须是数字，实际 %s" % type_string(t)}
	if not is_finite(float(raw)):
		return {"ok": false, "error": "档案版本号非有限数"}
	var value := float(raw)
	if value != floorf(value) or value < 0:
		return {"ok": false, "error": "档案版本号必须是整数（实际 %s）" % str(raw)}
	return {"ok": true, "version": int(value)}


## 轻量摘要（列表页用）。返回 {ok, summary} 或 {ok:false, newer, error}。
static func summarize(record: Variant) -> Dictionary:
	var restored := restore(record)
	if not restored.ok:
		return restored
	var state: Dictionary = restored.state
	return {
		"ok": true,
		"summary": {
			"id": str(state.id),
			"name": str(state.name),
			"gold": int(state.gold),
			"completed_count": state.completed_levels.size(),
			"saved_at": float(state.saved_at),
			"difficulty": str(state.get("difficulty", AIDifficultyScript.DEFAULT)),
			"loadable": true,
			"notice": "",
		},
	}


static func _validate_head(data: Dictionary) -> String:
	var id := str(data.get("id", ""))
	if id.strip_edges() == "":
		return "档案缺少 id"
	var name := str(data.get("name", ""))
	if name.strip_edges() == "":
		return "档案缺少 name"
	var gold: Variant = data.get("gold", 0)
	if gold is not int or int(gold) < 0:
		return "档案 gold 无效"
	return ""


## 原地校验归一化队伍（单位为 UnitData 字典）。返回错误串或 ""。
static func _validate_roster(roster: Array) -> String:
	if roster.is_empty():
		return "队伍为空"
	var seen := {}
	for i in roster.size():
		var raw: Variant = roster[i]
		if raw is not Dictionary:
			return "roster[%d] 不是对象" % i
		var unit: Dictionary = raw
		var id := String(unit.get("id", ""))
		if id.is_empty():
			return "roster[%d] 缺少 id" % i
		if seen.has(id):
			return "队伍 id 重复：%s" % id
		seen[id] = true
		var class_id := StringName(String(unit.get("classId", "")))
		if class_id == &"" or not ProfessionDataScript.has_profession(class_id):
			return "单位 %s 未知职业: %s" % [id, String(class_id)]
		unit["id"] = StringName(id)
		unit["classId"] = class_id
		unit["name"] = String(unit.get("name", id))
		if StringName(String(unit.get("faction", ""))) != &"player":
			return "单位 %s 阵营不是 player" % id
		unit["faction"] = &"player"
		var move_type := StringName(String(unit.get("moveType", "foot")))
		if not EnumsScript.MOVE_TYPES.has(move_type):
			return "单位 %s moveType 无效: %s" % [id, String(move_type)]
		unit["moveType"] = move_type
		var pos: Variant = unit.get("position")
		if pos is not Vector2i:
			return "单位 %s 缺少 Vector2i 坐标" % id
		for f in UNIT_INT_FIELDS:
			var v: Variant = unit.get(f)
			if v is not int or int(v) < 0:
				return "单位 %s 字段 %s 无效: %s" % [id, f, str(v)]
		for f in UNIT_BOOL_FIELDS:
			var bv: Variant = unit.get(f)
			if bv is not bool:
				return "单位 %s 字段 %s 无效: %s" % [id, f, str(bv)]
		unit["level"] = int(unit["level"])
		unit["exp"] = int(unit["exp"])
		unit["hp"] = max(0, int(unit["hp"]))
		unit["mp"] = max(0, int(unit["mp"]))
		unit["hasMoved"] = false
		unit["hasActed"] = false
		unit["isDead"] = bool(unit["isDead"])
		var stats: Variant = unit.get("stats")
		if stats is not Dictionary:
			return "单位 %s 缺少 stats" % id
		var stat_err := _validate_stats(stats, UnitFactoryScript.empty_stats(), id)
		if stat_err != "":
			return stat_err
		var growths: Variant = unit.get("growths")
		if growths is not Dictionary:
			return "单位 %s 缺少 growths" % id
		var default_growths: Dictionary = UnitFactoryScript.default_growths()
		for gk in default_growths:
			var gv: Variant = growths.get(String(gk), growths.get(gk))
			if gv is not int:
				return "单位 %s 成长 %s 无效" % [id, String(gk)]
			growths[String(gk)] = int(gv)
		var weapon: Variant = unit.get("weapon")
		if weapon is not Dictionary:
			return "单位 %s 缺少 weapon" % id
		var w_err := _validate_weapon(weapon, id)
		if w_err != "":
			return w_err
		var attack_range: Variant = unit.get("attackRange", [0, 0])
		if attack_range is not Array or attack_range.size() != 2:
			return "单位 %s attackRange 无效" % id
		unit["attackRange"] = [int(attack_range[0]), int(attack_range[1])]
		var skills: Variant = unit.get("skills", [])
		if skills is not Array:
			return "单位 %s skills 不是数组" % id
		for si in skills.size():
			var sid := StringName(String(skills[si]))
			if sid != &"" and not skill_exists(sid):
				return "单位 %s 未知技能: %s" % [id, String(sid)]
			skills[si] = sid
		var items: Variant = unit.get("items", [])
		if items is not Array:
			return "单位 %s items 不是数组" % id
		for ii in items.size():
			var item: Variant = items[ii]
			if item is not Dictionary:
				return "单位 %s items[%d] 不是对象" % [id, ii]
			var iid := StringName(String(item.get("id", "")))
			if iid == &"" or not item_exists(iid):
				return "单位 %s 未知物品: %s" % [id, String(iid)]
			item["id"] = iid
			if item.get("uses") is not int:
				return "单位 %s 物品 %s uses 无效" % [id, String(iid)]
			item["uses"] = int(item["uses"])
		var buffs: Variant = unit.get("buffs", [])
		if buffs is not Array:
			return "单位 %s buffs 不是数组" % id
		for bi in buffs.size():
			var buff: Variant = buffs[bi]
			if buff is not Dictionary:
				return "单位 %s buffs[%d] 不是对象" % [id, bi]
			var stat := StringName(String(buff.get("stat", "")))
			if not UnitFactoryScript.empty_stats().has(stat):
				return "单位 %s buff 未知属性: %s" % [id, String(stat)]
			buff["stat"] = stat
			buff["value"] = int(buff.get("value", 0))
			buff["turns"] = int(buff.get("turns", 0))
			buff["label"] = String(buff.get("label", ""))
		var cds: Variant = unit.get("skillCooldowns", {})
		if cds is not Dictionary:
			return "单位 %s skillCooldowns 不是对象" % id
		var cd_out := {}
		for cdk in cds:
			var cd_skill := StringName(String(cdk))
			var cd_val: Variant = cds[cdk]
			if cd_val is not int:
				return "单位 %s 冷却 %s 无效" % [id, String(cd_skill)]
			cd_out[cd_skill] = int(cd_val)
		unit["skillCooldowns"] = cd_out
		# 装备槽（可选字段）：存在时严格校验并就地归一（String 键 → StringName）。
		var eq_err := EquipmentDataScript.normalize_unit_equipment(unit)
		if eq_err != "":
			return eq_err
	return ""


static func _validate_stats(stats: Dictionary, empty_stats: Dictionary, unit_id: String) -> String:
	for sk in empty_stats:
		var key := String(sk)
		var v: Variant = stats.get(key, stats.get(sk))
		if v is not int:
			return "单位 %s 属性 %s 无效: %s" % [unit_id, key, str(v)]
		stats[key] = int(v)
	if int(stats["hp"]) < 0 or int(stats["mp"]) < 0:
		return "单位 %s 属性上限为负" % unit_id
	return ""


static func _validate_weapon(weapon: Dictionary, unit_id: String) -> String:
	var wid := StringName(String(weapon.get("id", "")))
	if wid == &"":
		return "单位 %s 武器缺少 id" % unit_id
	weapon["id"] = wid
	weapon["name"] = String(weapon.get("name", ""))
	weapon["type"] = StringName(String(weapon.get("type", "sword")))
	for f in WEAPON_INT_FIELDS:
		var v: Variant = weapon.get(f)
		if v is not int:
			return "单位 %s 武器字段 %s 无效" % [unit_id, f]
		weapon[f] = int(v)
	var rng: Variant = weapon.get("range")
	if rng is not Array or rng.size() != 2:
		return "单位 %s 武器 range 无效" % unit_id
	weapon["range"] = [int(rng[0]), int(rng[1])]
	return ""


## 原地归一化库存：{id:StringName, uses:int}，uses 夹到 [0, 物品最大充]，丢弃耗尽项。
static func _normalize_inventory(inventory: Array) -> String:
	for i in range(inventory.size() - 1, -1, -1):
		var raw: Variant = inventory[i]
		if raw is not Dictionary:
			return "inventory[%d] 不是对象" % i
		var iid := StringName(String(raw.get("id", "")))
		if iid == &"" or not item_exists(iid):
			return "库存条目 %s 未知物品" % String(iid)
		var uses: Variant = raw.get("uses", 0)
		if uses is not int:
			return "库存条目 %s uses 无效" % String(iid)
		var max_uses := int(ItemDataScript.get_item(iid).get("uses", 0))
		var clamped := clampi(int(uses), 0, maxi(1, max_uses))
		if clamped <= 0:
			inventory.remove_at(i)
			continue
		raw["id"] = iid
		raw["uses"] = clamped
	return ""


## 原地归一化携带方案：Array(按队伍序) of Array[{id:StringName, count:int}]。
static func _normalize_templates(templates: Array) -> String:
	for ti in templates.size():
		var row: Variant = templates[ti]
		if row is not Array:
			return "carry_templates[%d] 不是数组" % ti
		for ri in row.size():
			var entry: Variant = row[ri]
			if entry is not Dictionary:
				return "carry_templates[%d][%d] 不是对象" % [ti, ri]
			var iid := StringName(String(entry.get("id", "")))
			if iid == &"" or not item_exists(iid):
				return "携带方案引用未知物品：%s" % String(iid)
			var count: Variant = entry.get("count", 0)
			if count is not int or int(count) < 1:
				return "携带方案 %s count 无效" % String(iid)
			entry["id"] = iid
			entry["count"] = int(count)
	return ""


## 校验限购记录（v1 可选字段，旧档缺失回填缺省）。形状 {clear_index:int, counts:{id:int}}：
## clear_index = 记录所属限购周期（购买时的 completed_levels.size()，整数 >= 0）；
## counts 键为物品 id（必须存在）且值为非负整数。缺失/null 视为全新记录（周期 0 空计数）。
## 返回 {ok:true, value:{clear_index, counts}}（counts 键归一为 String）或 {ok:false, error}。
static func _normalize_purchases(raw: Variant) -> Dictionary:
	if raw == null:
		return {"ok": true, "value": {"clear_index": 0, "counts": {}}}
	if raw is not Dictionary:
		return {"ok": false, "error": "shop_purchases 不是对象"}
	var clear_index: Variant = raw.get("clear_index", 0)
	if clear_index is not int or int(clear_index) < 0:
		return {"ok": false, "error": "shop_purchases.clear_index 必须是 >= 0 的整数"}
	var raw_counts: Variant = raw.get("counts", {})
	if raw_counts is not Dictionary:
		return {"ok": false, "error": "shop_purchases.counts 不是对象"}
	var counts := {}
	for key: Variant in raw_counts:
		var iid := StringName(String(key))
		if iid == &"" or not item_exists(iid):
			return {"ok": false, "error": "限购计数引用未知物品：%s" % String(key)}
		var value: Variant = raw_counts[key]
		if value is not int or int(value) < 0:
			return {"ok": false, "error": "限购计数 %s 必须是 >= 0 的整数" % String(key)}
		counts[String(iid)] = int(value)
	return {"ok": true, "value": {"clear_index": int(clear_index), "counts": counts}}
