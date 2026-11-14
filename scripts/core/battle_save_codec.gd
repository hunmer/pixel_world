## battle_save_codec.gd — 战棋存档的纯数据编码 / 解码 / 校验（版本 1）
## 职责：把 chapter（地图+双方全部单位）与 battle state（回合/阶段/托管/偏好/胜负）
## 转成可 JSON 化的纯数据，并在读档时完整校验，坏档 / 新版本档明确报错、绝不静默吞。
## 约定：存档只含 String / 数值 / bool / 数组 / 字典；Vector2i 用 {"$v2i":[x,y]} 显式标记，
## StringName 统一转 String，超大整数转 "$i" 前缀字符串防 JSON 精度丢失。

class_name BattleSaveCodec
extends RefCounted

const VERSION := 1

## 块布局归一化走既有模块，保证与编辑器保存路径同一形状
const BlockLayoutScript = preload("res://scripts/core/block_layout.gd")

const UNIT_INT_FIELDS := ["level", "exp", "hp", "mp"]
const UNIT_BOOL_FIELDS := ["hasMoved", "hasActed", "isDead"]
const WEAPON_INT_FIELDS := ["might", "hit", "crit", "weight", "uses"]
const STATE_RESULTS := [&"", &"win", &"lose"]

static var _encode_error := ""


# ============================================================
# 编码（内存结构 -> 纯数据）
# ============================================================

## 把任意运行时数据编码为可 JSON 化结构。返回 null 表示遇到不支持的类型（视为失败）。
static func encode(value: Variant) -> Variant:
	if value is StringName:
		return String(value)
	if value is Vector2i:
		return {"$v2i": [value.x, value.y]}
	if value is int:
		if abs(value) >= 9007199254740992:  # 2^53，JSON 数字精度上限
			return "$i" + String(value)
		return value
	if value is float or value is bool or value is String or value == null:
		return value
	if value is Array:
		var out_arr: Array = []
		out_arr.resize(value.size())
		for i in value.size():
			out_arr[i] = encode(value[i])
		return out_arr
	if value is Dictionary:
		var out_dict := {}
		for k in value:
			var enc_key := String(k) if k is StringName or k is String or k is int else ""
			if enc_key == "" and not (k is int):
				_encode_error = "不支持的字典键类型: %s" % typeof(k)
				return null
			if k is int:
				enc_key = String(k)
			var enc_val: Variant = encode(value[k])
			if enc_val == null and value[k] != null:
				return null
			out_dict[enc_key] = enc_val
		return out_dict
	_encode_error = "不支持的数据类型: %s" % typeof(value)
	return null


# ============================================================
# 解码（纯数据 -> 内存结构）
# ============================================================

## 把 JSON 解析结果还原为运行时结构：Vector2i 复原、整数 float 归一、"$i" 大整数复原。
static func decode(value: Variant) -> Variant:
	if value is Dictionary:
		var d: Dictionary = value
		if d.size() == 1 and d.has("$v2i") and d["$v2i"] is Array:
			var arr: Array = d["$v2i"]
			if arr.size() == 2:
				return Vector2i(int(arr[0]), int(arr[1]))
		var out := {}
		for k in d:
			out[k] = decode(d[k])
		return out
	if value is Array:
		var out_arr: Array = []
		out_arr.resize(value.size())
		for i in value.size():
			out_arr[i] = decode(value[i])
		return out_arr
	if value is String:
		var s: String = value
		if s.begins_with("$i"):
			return int(s.substr(2))
		return s
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value


# ============================================================
# 记录组装 / 读取
# ============================================================

## 组装一条完整存档记录。initial 是开局时的 chapter 快照（用于重置），
## chapter/state 是当前进度。返回 {ok, record} 或 {ok:false, error}。
static func capture(identity: String, kind: String, source: String, \
		initial: Dictionary, chapter: Dictionary, state: Dictionary, \
		initial_signature: String) -> Dictionary:
	_encode_error = ""
	var enc_initial: Variant = encode(initial)
	var enc_chapter: Variant = encode(chapter)
	var enc_state: Variant = encode(state)
	if _encode_error != "" or enc_initial == null or enc_chapter == null or enc_state == null:
		return {"ok": false, "error": "编码失败: %s" % _encode_error}
	return {"ok": true, "record": {
		"version": VERSION,
		"identity": identity,
		"kind": kind,
		"source": source,
		"saved_at": Time.get_unix_time_from_system(),
		"initial_signature": initial_signature,
		"initial": enc_initial,
		"chapter": enc_chapter,
		"state": enc_state,
	}}


## 读取并完整校验一条记录。返回 {ok, identity, kind, source, chapter, state, initial,
## signature, saved_at}；版本更新返回 {ok:false, newer:true, error}；损坏返回 {ok:false, error}。
static func restore(record: Dictionary) -> Dictionary:
	if not record.has("version"):
		return _restore_fail("缺少 version 字段")
	var ver: Variant = record["version"]
	if not (ver is int or ver is float) or int(ver) != VERSION:
		var newer := (ver is int or ver is float) and int(ver) > VERSION
		return {"ok": false, "newer": newer,
			"error": "不支持的存档版本: %s（当前支持 %d）" % [str(ver), VERSION]}
	if not record.get("identity") is String or String(record["identity"]).is_empty():
		return _restore_fail("identity 无效")
	var kind := String(record.get("kind", ""))
	if kind != "battlefield" and kind != "world":
		return _restore_fail("kind 无效: %s" % kind)
	var source := String(record.get("source", ""))
	if not record.has("initial") or not record["initial"] is Dictionary:
		return _restore_fail("缺少 initial 快照")
	if not record.has("chapter") or not record["chapter"] is Dictionary:
		return _restore_fail("缺少 chapter 数据")
	if not record.has("state") or not record["state"] is Dictionary:
		return _restore_fail("缺少 state 数据")

	var chapter_res := _restore_chapter(record["chapter"])
	if not chapter_res.ok:
		return _restore_fail("chapter: " + chapter_res.error)
	var initial_res := _restore_chapter(record["initial"])
	if not initial_res.ok:
		return _restore_fail("initial: " + initial_res.error)
	var state_res := _restore_state(record["state"])
	if not state_res.ok:
		return _restore_fail("state: " + state_res.error)

	return {"ok": true,
		"identity": String(record["identity"]),
		"kind": kind,
		"source": source,
		"chapter": chapter_res.chapter,
		"initial": initial_res.chapter,
		"state": state_res.state,
		"signature": String(record.get("initial_signature", "")),
		"saved_at": float(record.get("saved_at", 0.0)),
	}


static func _restore_fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}


static func _restore_chapter(enc: Dictionary) -> Dictionary:
	var decoded: Variant = decode(enc)
	if not decoded is Dictionary:
		return {"ok": false, "error": "chapter 解码失败"}
	var chapter: Dictionary = decoded
	var err := validate_chapter(chapter)
	if err != "":
		return {"ok": false, "error": err}
	return {"ok": true, "chapter": chapter}


static func _restore_state(enc: Dictionary) -> Dictionary:
	var decoded: Variant = decode(enc)
	if not decoded is Dictionary:
		return {"ok": false, "error": "state 解码失败"}
	var state: Dictionary = decoded
	var turn_no: Variant = state.get("turn_number")
	if not (turn_no is int) or int(turn_no) < 1:
		return {"ok": false, "error": "turn_number 无效: %s" % str(turn_no)}
	var phase := String(state.get("phase", ""))
	if phase != "player" and phase != "enemy":
		return {"ok": false, "error": "phase 无效: %s" % phase}
	state["phase"] = StringName(phase)
	if not state.get("hosting") is bool:
		state["hosting"] = false
	var result := String(state.get("result", ""))
	if result != "" and result != "win" and result != "lose":
		return {"ok": false, "error": "result 无效: %s" % result}
	state["result"] = StringName(result)
	if state.get("prefs") is Dictionary:
		state["prefs"] = _restore_prefs(state["prefs"])
	else:
		state["prefs"] = {}
	return {"ok": true, "state": state}


## 偏好键（unitId / priorityTargetId）统一还原为 StringName。
static func _restore_prefs(prefs: Dictionary) -> Dictionary:
	var out := {}
	for unit_id in prefs:
		var p: Variant = prefs[unit_id]
		if not p is Dictionary:
			continue
		var np := {}
		for k in p:
			var key := String(k)
			if key == "priorityTargetId":
				np[&"priorityTargetId"] = StringName(String(p[k])) if String(p[k]) != "" else &""
			elif key == "strategy":
				np[&"strategy"] = String(p[k])
			else:
				np[StringName(key)] = p[k]
		out[StringName(String(unit_id))] = np
	return out


# ============================================================
# chapter 校验（就地归一化：String -> StringName 等）
# ============================================================

## 校验并归一化 chapter。返回 "" 表示通过，否则返回错误描述。
## 归一化点：单位 StringName 字段、武器、技能、物品、buff；地图保持 String（与 JSON 加载器一致）。
static func validate_chapter(chapter: Dictionary) -> String:
	var width: Variant = chapter.get("width")
	var height: Variant = chapter.get("height")
	if not (width is int) or not (height is int) or int(width) < 1 or int(height) < 1:
		return "地图尺寸无效: %s x %s" % [str(width), str(height)]
	var map: Variant = chapter.get("map")
	if not map is Array or map.size() != int(height):
		return "map 行数与 height 不符"
	var terrain_keys := {}
	for t in TerrainData.TERRAIN:
		terrain_keys[String(t)] = true
	var occupied := {}  # "x,y" -> true，活人不可重叠
	for y in int(height):
		var row: Variant = map[y]
		if not row is Array or row.size() != int(width):
			return "map 第 %d 行列数与 width 不符" % y
		for x in int(width):
			var cell := String(row[x])
			if not terrain_keys.has(cell):
				return "未知地形 %s 于 (%d,%d)" % [cell, x, y]

	for key in ["playerUnits", "enemyUnits"]:
		var units: Variant = chapter.get(key)
		if not units is Array:
			return "缺少 %s" % key
		var err := _validate_units(units, key, int(width), int(height), occupied)
		if err != "":
			return err

	if chapter.has("props"):
		var props: Variant = chapter["props"]
		if not props is Array:
			return "props 不是数组"
		for i in props.size():
			var prop: Variant = props[i]
			if not prop is Dictionary:
				return "props[%d] 不是对象" % i
			var px: Variant = prop.get("x")
			var py: Variant = prop.get("y")
			if not (px is int) or not (py is int):
				return "props[%d] 坐标无效" % i
			if int(px) < 0 or int(px) >= int(width) or int(py) < 0 or int(py) >= int(height):
				return "props[%d] 坐标越界: (%d,%d)" % [i, int(px), int(py)]
			# 用户素材条目：asset_id 须为非空 String（缺图不丢引用，不校验文件存在）
			if prop.has("asset_id"):
				var aid: Variant = prop.get("asset_id")
				if not (aid is String) or String(aid).is_empty():
					return "props[%d] asset_id 必须是非空字符串" % i

	# 地块视觉覆盖层（可选；存档严格：形状/坐标错报错，逻辑地形不变）
	if chapter.has("tile_overrides"):
		var overrides: Variant = chapter["tile_overrides"]
		if not overrides is Dictionary:
			return "tile_overrides 不是对象"
		for key in (overrides as Dictionary).keys():
			var entry: Variant = (overrides as Dictionary)[key]
			if not entry is Dictionary:
				return "tile_overrides[%s] 不是对象" % str(key)
			var oaid: Variant = (entry as Dictionary).get("asset_id")
			if not (oaid is String) or String(oaid).is_empty():
				return "tile_overrides[%s] asset_id 必须是非空字符串" % str(key)
			var parts := String(key).split(",")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
				return "tile_overrides 键必须是 \"x,y\" 整数坐标: %s" % str(key)
			var ox := int(parts[0])
			var oy := int(parts[1])
			if ox < 0 or ox >= int(width) or oy < 0 or oy >= int(height):
				return "tile_overrides[%s] 坐标越界" % str(key)

	# 引用素材描述符快照（可选；形状宽松：纯 JSON 字典即可，深校验在素材库层）
	if chapter.has("user_assets"):
		if not chapter["user_assets"] is Dictionary:
			return "user_assets 不是对象"

	if chapter.has("block_layout"):
		var layout: Variant = chapter["block_layout"]
		if not layout is Dictionary:
			return "block_layout 不是对象"
		var norm_res: Dictionary = BlockLayoutScript.normalize(layout, int(width), int(height))
		if not bool(norm_res.get("ok", false)):
			return "block_layout 校验失败: %s" % String(norm_res.get("error", ""))
		chapter["block_layout"] = norm_res["layout"]
	return ""


static func _validate_units(units: Array, faction_key: String, width: int, height: int, occupied: Dictionary) -> String:
	var faction := &"player" if faction_key == "playerUnits" else &"enemy"
	var empty_stats: Dictionary = UnitFactory.empty_stats()
	var default_growths: Dictionary = UnitFactory.default_growths()
	for i in units.size():
		var u: Variant = units[i]
		if not u is Dictionary:
			return "%s[%d] 不是对象" % [faction_key, i]
		var unit: Dictionary = u
		var id := String(unit.get("id", ""))
		if id.is_empty():
			return "%s[%d] 缺少 id" % [faction_key, i]
		var class_id := StringName(String(unit.get("classId", "")))
		if class_id == &"" or not ProfessionData.has_profession(class_id):
			return "单位 %s 未知职业: %s" % [id, String(class_id)]
		unit["id"] = StringName(id)
		unit["classId"] = class_id
		unit["name"] = String(unit.get("name", id))
		if StringName(String(unit.get("faction", ""))) != faction:
			return "单位 %s 阵营不符: %s" % [id, String(unit.get("faction", ""))]
		unit["faction"] = faction
		var move_type := StringName(String(unit.get("moveType", "foot")))
		if not Enums.MOVE_TYPES.has(move_type):
			return "单位 %s moveType 无效: %s" % [id, String(move_type)]
		unit["moveType"] = move_type
		var pos: Variant = unit.get("position")
		if not pos is Vector2i:
			return "单位 %s 缺少 Vector2i 坐标" % id
		if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
			return "单位 %s 坐标越界: %s" % [id, str(pos)]
		unit["position"] = pos
		for f in UNIT_INT_FIELDS:
			var v: Variant = unit.get(f)
			if not v is int or int(v) < 0:
				return "单位 %s 字段 %s 无效: %s" % [id, f, str(v)]
		for f in UNIT_BOOL_FIELDS:
			var bv: Variant = unit.get(f)
			if not bv is bool:
				return "单位 %s 字段 %s 无效: %s" % [id, f, str(bv)]
		unit["level"] = int(unit["level"])
		unit["exp"] = int(unit["exp"])
		unit["hp"] = max(0, int(unit["hp"]))
		unit["mp"] = max(0, int(unit["mp"]))
		unit["hasMoved"] = bool(unit["hasMoved"])
		unit["hasActed"] = bool(unit["hasActed"])
		unit["isDead"] = bool(unit["isDead"])
		if not unit["isDead"]:
			var cell_key := "%d,%d" % [pos.x, pos.y]
			if occupied.has(cell_key):
				return "活人单位坐标重叠: %s" % cell_key
			occupied[cell_key] = true

		var stats: Variant = unit.get("stats")
		if not stats is Dictionary:
			return "单位 %s 缺少 stats" % id
		var stat_err := _validate_stats(stats, empty_stats, id)
		if stat_err != "":
			return stat_err
		var growths: Variant = unit.get("growths")
		if not growths is Dictionary:
			return "单位 %s 缺少 growths" % id
		for gk in default_growths:
			var gv: Variant = growths.get(String(gk), growths.get(gk))
			if not gv is int:
				return "单位 %s 成长 %s 无效" % [id, String(gk)]
			growths[String(gk)] = int(gv)
		var weapon: Variant = unit.get("weapon")
		if not weapon is Dictionary:
			return "单位 %s 缺少 weapon" % id
		var w_err := _validate_weapon(weapon, id)
		if w_err != "":
			return w_err
		var skills: Variant = unit.get("skills", [])
		if not skills is Array:
			return "单位 %s skills 不是数组" % id
		for si in skills.size():
			var sid := StringName(String(skills[si]))
			if sid != &"" and SkillData.get_skill(sid).is_empty():
				return "单位 %s 未知技能: %s" % [id, String(sid)]
			skills[si] = sid
		var items: Variant = unit.get("items", [])
		if not items is Array:
			return "单位 %s items 不是数组" % id
		for ii in items.size():
			var item: Variant = items[ii]
			if not item is Dictionary:
				return "单位 %s items[%d] 不是对象" % [id, ii]
			var iid := StringName(String(item.get("id", "")))
			if iid == &"" or ItemData.get_item(iid).is_empty():
				return "单位 %s 未知物品: %s" % [id, String(iid)]
			item["id"] = iid
			if not item.get("uses") is int:
				return "单位 %s 物品 %s uses 无效" % [id, String(iid)]
			item["uses"] = int(item["uses"])
		var buffs: Variant = unit.get("buffs", [])
		if not buffs is Array:
			return "单位 %s buffs 不是数组" % id
		for bi in buffs.size():
			var buff: Variant = buffs[bi]
			if not buff is Dictionary:
				return "单位 %s buffs[%d] 不是对象" % [id, bi]
			var stat := StringName(String(buff.get("stat", "")))
			if not empty_stats.has(stat):
				return "单位 %s buff 未知属性: %s" % [id, String(stat)]
			buff["stat"] = stat
			buff["value"] = int(buff.get("value", 0))
			buff["turns"] = int(buff.get("turns", 0))
			buff["label"] = String(buff.get("label", ""))
		var cds: Variant = unit.get("skillCooldowns", {})
		if not cds is Dictionary:
			return "单位 %s skillCooldowns 不是对象" % id
		var cd_out := {}
		for cdk in cds:
			var cd_skill := StringName(String(cdk))
			var cd_val: Variant = cds[cdk]
			if not cd_val is int:
				return "单位 %s 冷却 %s 无效" % [id, String(cd_skill)]
			cd_out[cd_skill] = int(cd_val)
		unit["skillCooldowns"] = cd_out
	return ""


static func _validate_stats(stats: Dictionary, empty_stats: Dictionary, unit_id: String) -> String:
	for sk in empty_stats:
		var key := String(sk)
		var v: Variant = stats.get(key, stats.get(sk))
		if not v is int:
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
		if not v is int:
			return "单位 %s 武器字段 %s 无效" % [unit_id, f]
		weapon[f] = int(v)
	var rng: Variant = weapon.get("range")
	if not rng is Array or rng.size() != 2:
		return "单位 %s 武器 range 无效" % unit_id
	weapon["range"] = [int(rng[0]), int(rng[1])]
	return ""
