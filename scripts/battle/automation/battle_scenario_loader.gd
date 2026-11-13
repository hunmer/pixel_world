## battle/automation/battle_scenario_loader.gd — 声明式战场场景加载器
##
## 职责：把版本化的 scenario JSON（内联战场或引用已有战场 + seed + 限制 +
## 初始化覆盖 + 双阵营执行模式 + 断言）解析为 runner 可执行的标准结构。
## 只做加载与静态校验（结构/引用/类型），不执行任何战斗逻辑。
##
## scenario JSON 格式（version 1）：
##   {
##     "version": 1,
##     "id": "quick_duel",                       # 可选，缺省用文件名或 "inline"
##     "battlefield": "res://data/battlefields/arena_1v1.json",   # 与 inline 二选一
##     "inline": { "rows": [...], "playerUnits": [...], "enemyUnits": [...] },
##     "seed": 42,                                # 必填 int（CLI --seed 可覆盖）
##     "limits": { "max_turns": 30, "max_steps": 500 },   # 可选，缺省 50/1000
##     "stop_after_steps": -1,                    # 可选，短复现用
##     "overrides": { "u_p_0": { "hp": 99, "mp": 99 } },  # 可选，按单位 ID 覆盖初始值
##     "factions": {
##       "player": { "mode": "script", "script": [ ... ], "exhausted": "wait" },
##       "enemy":  { "mode": "ai", "ai_pref": { "strategy": "aggressive" } }
##     },
##     "assertions": [ { "type": "winner", "value": "player" }, ... ]
##   }
##
## 脚本动作条目（factions.<f>.script 数组元素）：
##   { "unit": "u_p_0", "move": {"x":2,"y":2}, "attack": "u_e_0" }   # move 可与终结构动作组合
##   { "unit": "u_p_0", "attack": "u_e_0" }
##   { "unit": "u_p_0", "skill": "fireball", "targets": ["u_e_0"] }
##   { "unit": "u_p_0", "item": "hpPotion", "targets": ["u_p_0"] }
##   { "unit": "u_p_0", "wait": true }                                # 裸 {"unit":..} 等价 wait
##   { "end_turn": true }                                             # 阵营级：提前结束本 phase
##
## 公开 API：
##   load_from_file(path) -> Dictionary { ok, scenario? , error? }
##   load_from_dict(d)    -> Dictionary 同上（CLI --scenario-json / 进程内测试用）

class_name BattleScenarioLoader
extends RefCounted

const Loader = preload("res://scripts/core/battlefield_loader.gd")
const AIDifficulty = preload("res://scripts/systems/ai_difficulty.gd")

const SUPPORTED_VERSION := 1
const DEFAULT_MAX_TURNS := 50
const DEFAULT_MAX_STEPS := 1000
const ASSERTION_TYPES := ["winner", "battle_over", "unit_hp", "unit_alive", "unit_position", "turn_number", "steps", "event_count"]
const NUMERIC_OPS := ["==", "!=", "<=", ">=", "<", ">"]
const OVERRIDEABLE_FIELDS := ["hp", "mp", "level", "exp", "hasMoved", "hasActed"]


## 从文件加载（res:// / user:// / 绝对路径均可，遵循 FileAccess 规则）；seed_override 非 null 覆盖场景 seed（CLI --seed）。
static func load_from_file(path: String, seed_override: Variant = null) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _err("场景文件不存在: %s" % path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _err("场景文件无法打开: %s（%s）" % [path, error_string(FileAccess.get_open_error())])
	var text := f.get_as_text()
	var json := JSON.new()
	if json.parse(text) != OK:
		return _err("场景 JSON 解析失败: %s: %s" % [path, json.get_error_message()])
	var data = json.data
	if not (data is Dictionary):
		return _err("场景 JSON 顶层必须是对象: %s" % path)
	var fallback_id := path.get_file().get_basename()
	return load_from_dict(data, fallback_id, seed_override)


## 从 dict 加载；seed_override 非 null 时覆盖场景 seed（CLI --seed）。
static func load_from_dict(d: Dictionary, fallback_id: String = "inline", seed_override: Variant = null) -> Dictionary:
	# 1) 版本
	var ver := int(d.get("version", 0))
	if ver != SUPPORTED_VERSION:
		return _err("不支持的 scenario version %d（当前支持 %d）" % [ver, SUPPORTED_VERSION])
	# 2) 战场：battlefield 路径 或 inline 声明（二选一）
	var chapter: Dictionary = {}
	var source := ""
	if d.has("battlefield") and d.has("inline"):
		return _err("\"battlefield\" 与 \"inline\" 只能二选一")
	if d.has("battlefield"):
		var bf_path := String(d["battlefield"])
		if bf_path.is_empty():
			return _err("\"battlefield\" 不能为空字符串")
		var res := Loader.load_battlefield(bf_path)
		if not bool(res.get("ok", false)):
			return _err("战场加载失败（%s）: %s" % [bf_path, String(res.get("error", ""))])
		chapter = res["chapter"]
		source = bf_path
	elif d.has("inline"):
		if not (d["inline"] is Dictionary):
			return _err("\"inline\" 必须是对象（与 data/battlefields/*.json 同 schema）")
		var inline_id := String(d.get("id", fallback_id))
		var ires := Loader.load_battlefield_inline(d["inline"], inline_id)
		if not bool(ires.get("ok", false)):
			return _err("内联战场构建失败: %s" % String(ires.get("error", "")))
		chapter = ires["chapter"]
		source = "inline"
	else:
		return _err("缺少 \"battlefield\"（路径）或 \"inline\"（内联声明）")
	# 3) seed
	var seed_value := 0
	if seed_override != null:
		if not (seed_override is float) and not (seed_override is int):
			return _err("--seed 覆盖值必须是整数")
		seed_value = int(seed_override)
	else:
		var raw_seed: Variant = d.get("seed", null)
		if raw_seed == null:
			return _err("缺少 \"seed\"（整数，驱动全部随机判定）")
		if not (raw_seed is float) and not (raw_seed is int):
			return _err("\"seed\" 必须是整数")
		seed_value = int(raw_seed)
	# 4) limits / stop_after_steps
	var limits := {
		"max_turns": _opt_int(d, "limits", "max_turns", DEFAULT_MAX_TURNS),
		"max_steps": _opt_int(d, "limits", "max_steps", DEFAULT_MAX_STEPS),
	}
	if int(limits["max_turns"]) < 1 or int(limits["max_steps"]) < 1:
		return _err("\"limits.max_turns\"/\"max_steps\" 必须 ≥ 1")
	var stop_after_steps := -1
	if d.has("stop_after_steps"):
		if not _is_int_like(d["stop_after_steps"]) or int(d["stop_after_steps"]) < 1:
			return _err("\"stop_after_steps\" 必须是 ≥ 1 的整数")
		stop_after_steps = int(d["stop_after_steps"])
	# 5) 阵营执行模式
	var raw_factions: Variant = d.get("factions", null)
	if not (raw_factions is Dictionary):
		return _err("缺少 \"factions\"（player/enemy 执行模式）")
	var factions := {}
	for faction in [&"player", &"enemy"]:
		var key := String(faction)
		var raw_cfg: Variant = (raw_factions as Dictionary).get(key, null)
		if raw_cfg == null:
			# 缺省该阵营走 AI
			factions[faction] = {"mode": &"ai", "script": [], "exhausted": &"wait", "ai_pref": {}}
			continue
		if not (raw_cfg is Dictionary):
			return _err("factions.%s 必须是对象" % key)
		var cfg: Dictionary = raw_cfg
		var mode_str := String(cfg.get("mode", "ai"))
		if mode_str != "script" and mode_str != "ai":
			return _err("factions.%s.mode 必须是 \"script\" 或 \"ai\"（得到 \"%s\"）" % [key, mode_str])
		var norm := {"mode": StringName(mode_str), "script": [], "exhausted": &"wait", "ai_pref": {}}
		if mode_str == "script":
			var raw_script: Variant = cfg.get("script", null)
			if not (raw_script is Array):
				return _err("factions.%s.mode=script 时必须提供 \"script\" 数组" % key)
			var check := _normalize_script(raw_script as Array, key)
			if not bool(check.get("ok", false)):
				return _err(String(check.get("error", "")))
			norm["script"] = check["script"]
			var exhausted := String(cfg.get("script_exhausted", "wait"))
			if exhausted != "wait" and exhausted != "fail":
				return _err("factions.%s.script_exhausted 必须是 \"wait\" 或 \"fail\"（得到 \"%s\"）" % [key, exhausted])
			norm["exhausted"] = StringName(exhausted)
		elif cfg.has("script"):
			return _err("factions.%s.mode=ai 时不应提供 \"script\"（AI 阵营不存在脚本耗尽问题）" % key)
		# cfg 未知字段拒绝（防笔误静默失效）
		var known_cfg := ["mode", "script", "script_exhausted", "ai_pref"]
		for k in cfg:
			if not known_cfg.has(String(k)):
				return _err("factions.%s 含未知字段 \"%s\"（可用: %s）" % [key, String(k), ", ".join(known_cfg)])
		if cfg.has("ai_pref"):
			if not (cfg["ai_pref"] is Dictionary):
				return _err("factions.%s.ai_pref 必须是对象" % key)
			var raw_pref: Dictionary = cfg["ai_pref"]
			var known_pref := ["strategy", "priorityTargetId", "difficulty"]
			for pk in raw_pref:
				if not known_pref.has(String(pk)):
					return _err("factions.%s.ai_pref 含未知字段 \"%s\"（可用: %s）" % [key, String(pk), ", ".join(known_pref)])
			if raw_pref.has("difficulty"):
				var dstr := String(raw_pref["difficulty"])
				if not AIDifficulty.validate(dstr):
					return _err("factions.%s.ai_pref.difficulty 非法: \"%s\"（合法: %s）" % [key, dstr, ", ".join(AIDifficulty.VALID)])
			norm["ai_pref"] = raw_pref
		factions[faction] = norm
	# 6) overrides：单位 ID 必须存在于 chapter 单位
	var unit_ids := {}
	for u in (chapter["playerUnits"] as Array):
		unit_ids[u[&"id"]] = true
	for u in (chapter["enemyUnits"] as Array):
		unit_ids[u[&"id"]] = true
	var overrides := {}
	if d.has("overrides"):
		if not (d["overrides"] is Dictionary):
			return _err("\"overrides\" 必须是对象（单位 ID → 覆盖字段）")
		for uid in (d["overrides"] as Dictionary):
			if not unit_ids.has(StringName(String(uid))):
				var ids: Array[String] = []
				for k in unit_ids.keys():
					ids.append(String(k))
				return _err("overrides 引用了不存在的单位 ID \"%s\"（可用: %s）" % [String(uid), ", ".join(ids)])
			var raw_over: Variant = (d["overrides"] as Dictionary)[uid]
			if not (raw_over is Dictionary):
				return _err("overrides.%s 必须是对象" % String(uid))
			var norm_over := {}
			for field in (raw_over as Dictionary):
				var fname := String(field)
				if not OVERRIDEABLE_FIELDS.has(fname):
					return _err("overrides.%s 含不支持的字段 \"%s\"（可用: %s）" % [String(uid), fname, ", ".join(OVERRIDEABLE_FIELDS)])
				norm_over[fname] = _coerce_override(fname, (raw_over as Dictionary)[field])
			overrides[StringName(String(uid))] = norm_over
	# 7) assertions
	var assertions: Array = []
	if d.has("assertions"):
		if not (d["assertions"] is Array):
			return _err("\"assertions\" 必须是数组")
		for i in range((d["assertions"] as Array).size()):
			var raw_a: Variant = (d["assertions"] as Array)[i]
			if not (raw_a is Dictionary):
				return _err("assertions[%d] 必须是对象" % i)
			var check_a := _normalize_assertion(raw_a as Dictionary, i, unit_ids)
			if not bool(check_a.get("ok", false)):
				return _err(String(check_a.get("error", "")))
			assertions.append(check_a["assertion"])
	var scenario := {
		"version": SUPPORTED_VERSION,
		"id": String(d.get("id", fallback_id)),
		"seed": seed_value,
		"chapter": chapter,
		"source": source,
		"limits": limits,
		"stop_after_steps": stop_after_steps,
		"factions": factions,
		"overrides": overrides,
		"assertions": assertions,
	}
	return {"ok": true, "scenario": scenario}


## ---- 内部实现 ----------------------------------------------------------


static func _normalize_script(raw_script: Array, faction_key: String) -> Dictionary:
	var out: Array = []
	for i in range(raw_script.size()):
		var raw: Variant = raw_script[i]
		if not (raw is Dictionary):
			return _err("factions.%s.script[%d] 必须是对象" % [faction_key, i])
		var e: Dictionary = raw
		var entry := {"unit": &"", "move": {}, "action": {}, "kind": &"wait"}
		if e.has("end_turn"):
			if bool(e["end_turn"]) != true:
				return _err("factions.%s.script[%d].end_turn 只接受 true" % [faction_key, i])
			if e.size() != 1:
				return _err("factions.%s.script[%d] end_turn 条目不能携带其他字段" % [faction_key, i])
			entry["kind"] = &"end_turn"
			out.append(entry)
			continue
		var uid := String(e.get("unit", ""))
		if uid.is_empty():
			return _err("factions.%s.script[%d] 缺少 \"unit\"（或使用 {\"end_turn\":true}）" % [faction_key, i])
		entry["unit"] = StringName(uid)
		# move（可选）
		if e.has("move"):
			var m: Variant = e["move"]
			if not (m is Dictionary) or not m.has("x") or not m.has("y"):
				return _err("factions.%s.script[%d].move 必须是 {\"x\":int,\"y\":int}" % [faction_key, i])
			if not _is_int_like((m as Dictionary)["x"]) or not _is_int_like((m as Dictionary)["y"]):
				return _err("factions.%s.script[%d].move.x/y 必须是整数" % [faction_key, i])
			entry["move"] = {
				"x": int((m as Dictionary)["x"]),
				"y": int((m as Dictionary)["y"]),
			}
		# 终结构动作（attack/skill/item/wait，至多一个；无则为 wait）
		var action_count := 0
		var kind := &"wait"
		var payload: Dictionary = {}
		if e.has("attack"):
			action_count += 1
			kind = &"attack"
			payload["target"] = StringName(String(e["attack"]))
		if e.has("skill"):
			action_count += 1
			kind = &"skill"
			payload["skill_id"] = StringName(String(e["skill"]))
			payload["targets"] = _str_name_array(e.get("targets", null), "factions.%s.script[%d].skill.targets" % [faction_key, i])
			if payload["targets"] == null:
				return _err("factions.%s.script[%d].skill 需要非空 \"targets\": [\"unit_id\",...] 数组" % [faction_key, i])
		if e.has("item"):
			action_count += 1
			kind = &"item"
			payload["item_id"] = StringName(String(e["item"]))
			payload["targets"] = _str_name_array(e.get("targets", null), "factions.%s.script[%d].item.targets" % [faction_key, i])
			if payload["targets"] == null:
				return _err("factions.%s.script[%d].item 需要非空 \"targets\": [\"unit_id\",...] 数组" % [faction_key, i])
		if e.has("wait"):
			if bool(e["wait"]) != true:
				return _err("factions.%s.script[%d].wait 只接受 true" % [faction_key, i])
			if action_count > 0:
				return _err("factions.%s.script[%d] wait 不能与 attack/skill/item 组合" % [faction_key, i])
			action_count += 1
			kind = &"wait"
		if action_count > 1:
			return _err("factions.%s.script[%d] 只能携带一个终结构动作（attack/skill/item/wait）" % [faction_key, i])
		# 必须至少携带一个显式动作（move/attack/skill/item/wait 之一；裸 unit 条目易掩盖笔误）
		if not e.has("move") and action_count == 0:
			return _err("factions.%s.script[%d] 缺少动作（至少给 move/attack/skill/item/wait 之一）" % [faction_key, i])
		# 未知字段检查
		var known := ["unit", "move", "attack", "skill", "item", "wait", "targets"]
		for k in e:
			if not known.has(String(k)):
				return _err("factions.%s.script[%d] 含未知字段 \"%s\"" % [faction_key, i, String(k)])
		entry["action"] = {"kind": kind, "payload": payload}
		out.append(entry)
	return {"ok": true, "script": out}


static func _normalize_assertion(a: Dictionary, idx: int, unit_ids: Dictionary) -> Dictionary:
	var atype := String(a.get("type", ""))
	if not ASSERTION_TYPES.has(atype):
		return _err("assertions[%d].type \"%s\" 不在支持列表（%s）" % [idx, atype, ", ".join(ASSERTION_TYPES)])
	var op := "=="
	if a.has("op"):
		op = String(a["op"])
		if not NUMERIC_OPS.has(op):
			return _err("assertions[%d].op \"%s\" 不在支持列表（%s）" % [idx, op, ", ".join(NUMERIC_OPS)])
	var norm := {"index": idx, "type": StringName(atype), "op": StringName(op)}
	match atype:
		"winner":
			var w := String(a.get("value", ""))
			if w != "player" and w != "enemy" and not w.is_empty():
				return _err("assertions[%d].value 必须是 \"player\"/\"enemy\"/\"\"（得到 \"%s\"）" % [idx, w])
			norm["value"] = StringName(w)
			if op != "==" and op != "!=":
				return _err("assertions[%d] winner 断言只支持 ==/!=" % idx)
		"battle_over":
			norm["value"] = bool(a.get("value", true))
			if op != "==" and op != "!=":
				return _err("assertions[%d] battle_over 断言只支持 ==/!=" % idx)
		"unit_alive":
			var bad_a := _require_unit(a, idx, unit_ids, norm)
			if bad_a != "":
				return _err(bad_a)
			norm["value"] = bool(a.get("value", true))
			if op != "==" and op != "!=":
				return _err("assertions[%d] unit_alive 断言只支持 ==/!=" % idx)
		"unit_hp":
			var bad_b := _require_unit(a, idx, unit_ids, norm)
			if bad_b != "":
				return _err(bad_b)
			if not _is_int_like(a.get("value", null)):
				return _err("assertions[%d] unit_hp 需要整数 value" % idx)
			norm["value"] = int(a["value"])
		"unit_position":
			var bad_c := _require_unit(a, idx, unit_ids, norm)
			if bad_c != "":
				return _err(bad_c)
			if not _is_int_like(a.get("x", null)) or not _is_int_like(a.get("y", null)):
				return _err("assertions[%d] unit_position 需要整数 x/y" % idx)
			norm["x"] = int(a["x"])
			norm["y"] = int(a["y"])
		"turn_number", "steps", "event_count":
			if not _is_int_like(a.get("value", null)):
				return _err("assertions[%d] %s 需要整数 value" % [idx, atype])
			norm["value"] = int(a["value"])
	return {"ok": true, "assertion": norm}


static func _require_unit(a: Dictionary, idx: int, unit_ids: Dictionary, norm: Dictionary) -> String:
	var uid := String(a.get("unit", ""))
	if not unit_ids.has(StringName(uid)):
		return "assertions[%d].unit 引用了不存在的单位 \"%s\"" % [idx, uid]
	norm["unit"] = StringName(uid)
	return ""


static func _str_name_array(v: Variant, where: String) -> Variant:
	if not (v is Array) or (v as Array).is_empty():
		return null
	var out: Array[StringName] = []
	for item in (v as Array):
		var s := String(item)
		if s.is_empty():
			push_error("%s 含空单位 ID" % where)
			return null
		out.append(StringName(s))
	return out


static func _opt_int(d: Dictionary, section: String, key: String, fallback: int) -> int:
	var sec: Variant = d.get(section, {})
	if sec is Dictionary and (sec as Dictionary).has(key):
		var v: Variant = (sec as Dictionary)[key]
		if not _is_int_like(v):
			push_error("\"%s.%s\" 必须是整数（用缺省 %d）" % [section, key, fallback])
			return fallback
		return int(v)
	return fallback


static func _is_int_like(v: Variant) -> bool:
	return v is int or (v is float and float(v) == floorf(float(v)))


static func _coerce_override(field: String, v: Variant) -> Variant:
	match field:
		"hp", "mp", "level", "exp":
			return int(v)
		"hasMoved", "hasActed":
			return bool(v)
	return v


static func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}
