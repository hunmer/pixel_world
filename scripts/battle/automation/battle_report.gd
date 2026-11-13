## battle_report.gd — 声明式战场战报写盘：events.jsonl / result.json / summary.txt
extends RefCounted
class_name BattleReport

const REPORT_VERSION := 1


## 写出完整战报目录。返回 {ok, dir, files} 或 {ok:false, error}。
static func write_all(out_dir: String, events: Array, result: Dictionary) -> Dictionary:
	var abs_dir := _ensure_dir(out_dir)
	if abs_dir == "":
		return {"ok": false, "error": "无法创建输出目录: %s" % out_dir}
	var files: Array[String] = []
	# events.jsonl —— 每行一个事件（JSON Lines）
	var ev_path := abs_dir.path_join("events.jsonl")
	var ev := FileAccess.open(ev_path, FileAccess.WRITE)
	if ev == null:
		return {"ok": false, "error": "无法写入 %s (err=%d)" % [ev_path, FileAccess.get_open_error()]}
	for e in events:
		ev.store_line(JSON.stringify(_plain(e)))
	ev.close()
	files.append(ev_path)
	# result.json —— 结构化结果（含断言评估）
	var res_path := abs_dir.path_join("result.json")
	var res := FileAccess.open(res_path, FileAccess.WRITE)
	if res == null:
		return {"ok": false, "error": "无法写入 %s (err=%d)" % [res_path, FileAccess.get_open_error()]}
	res.store_string(JSON.stringify(_plain(result), "  "))
	res.close()
	files.append(res_path)
	# summary.txt —— 人读摘要
	var sum_path := abs_dir.path_join("summary.txt")
	var sum := FileAccess.open(sum_path, FileAccess.WRITE)
	if sum == null:
		return {"ok": false, "error": "无法写入 %s (err=%d)" % [sum_path, FileAccess.get_open_error()]}
	sum.store_string(build_summary(events, result))
	sum.close()
	files.append(sum_path)
	return {"ok": true, "dir": abs_dir, "files": files}


## 生成人读摘要文本。
static func build_summary(events: Array, result: Dictionary) -> String:
	var l: Array[String] = []
	var outcome: Dictionary = result.get("outcome", {})
	l.append("=== 战场自动化战报 ===")
	l.append("场景: %s (来源: %s)" % [result.get("scenario_id", "?"), result.get("source", "?")])
	l.append("seed: %d    版本: %d" % [int(result.get("seed", 0)), int(result.get("version", REPORT_VERSION))])
	l.append("结果: %s    胜方: %s" % [String(outcome.get("stop_reason", "?")), _winner_text(outcome.get("winner", &""))])
	l.append("轮数: %d    步数: %d" % [int(outcome.get("turns", 0)), int(outcome.get("steps", 0))])
	if String(outcome.get("stop_reason", "")) == &"illegal_action":
		l.append("非法操作: %s" % result.get("error", ""))
	l.append("")
	l.append("--- 事件流 ---")
	for e in events:
		var line := _event_line(e)
		if line != "":
			l.append(line)
	l.append("")
	l.append("--- 最终单位 ---")
	for u in (result.get("final_units", []) as Array):
		l.append("%s [%s %s Lv%d] HP %d/%d MP %d @(%d,%d)%s%s" % [
			u.get("name", u.get("id", "?")),
			u.get("faction", "?"),
			u.get("class_id", "?"),
			int(u.get("level", 1)),
			int(u.get("hp", 0)), int(u.get("stats", {}).get("hp", 0)),
			int(u.get("mp", 0)),
			int(u.get("x", -1)), int(u.get("y", -1)),
			" [已阵亡]" if bool(u.get("is_dead", false)) else "",
			" exp=%d" % int(u.get("exp", 0)),
		])
	l.append("")
	l.append("--- 断言 ---")
	var assertions: Array = result.get("assertions", [])
	if assertions.is_empty():
		l.append("(无)")
	for a in assertions:
		l.append("[%s] %s" % ["PASS" if bool(a.get("passed", false)) else "FAIL", String(a.get("summary", JSON.stringify(a)))])
	return "\n".join(l) + "\n"


static func _winner_text(w: Variant) -> String:
	if w == &"player":
		return "玩家方"
	if w == &"enemy":
		return "敌方"
	return "(无)"


## 单事件摘要行。
static func _event_line(e: Dictionary) -> String:
	var t := String(e.get("type", ""))
	var who := "T%d.%s %s" % [int(e.get("turn", 0)), String(e.get("phase", "?")), String(e.get("actor", ""))]
	match t:
		"battle_start":
			return "[开场] seed=%d 场景=%s" % [int(e.get("seed", 0)), String(e.get("scenario_id", ""))]
		"phase_start":
			return "[回合开始] 第 %d 轮 — %s 相位" % [int(e.get("turn", 0)), _side_text(e.get("phase", ""))]
		"turn_end":
			return "[回合结束] 第 %d 轮" % int(e.get("turn", 0))
		"move":
			return "%s → 移动 (%d,%d)→(%d,%d) 路径长 %d" % [who, (e.get("from", {}) as Dictionary).get("x", -1), (e.get("from", {}) as Dictionary).get("y", -1), (e.get("to", {}) as Dictionary).get("x", -1), (e.get("to", {}) as Dictionary).get("y", -1), (e.get("path", []) as Array).size()]
		"attack":
			var parts: Array[String] = []
			parts.append("%s → 普攻 %s" % [who, String(e.get("target", ""))])
			if bool(e.get("hit", false)):
				parts.append("命中 %d 伤害" % int(e.get("damage", 0)))
				if bool(e.get("crit", false)):
					parts.append("必杀!")
			else:
				parts.append("未命中")
			if bool(e.get("counter", false)):
				parts.append("遭反击 %d 伤害" % int(e.get("counter_damage", 0)))
			if bool(e.get("double", false)):
				parts.append("追击")
			return " ".join(parts)
		"skill":
			var hits: Array = e.get("hits", [])
			var n_hit := 0
			var n_miss := 0
			for h in hits:
				if bool((h as Dictionary).get("hit", false)):
					n_hit += 1
				else:
					n_miss += 1
			var extra := ""
			if (e.get("healed", []) as Array).size() > 0:
				extra += " 治疗×%d" % (e.get("healed", []) as Array).size()
			if (e.get("buffed", []) as Array).size() > 0:
				extra += " 增益×%d" % (e.get("buffed", []) as Array).size()
			return "%s → 技能 %s MP-%d 命中%d/未中%d CD=%d%s" % [who, String(e.get("skill", "")), int(e.get("mp_cost", 0)), n_hit, n_miss, int(e.get("cooldown", 0)), extra]
		"item":
			return "%s → 物品 %s 剩余%d次" % [who, String(e.get("item", "")), int(e.get("uses_left", 0))]
		"death":
			return "[阵亡] %s" % String(e.get("unit", ""))
		"exp":
			return "%s → 经验 +%d (累计 %d)" % [who, int(e.get("amount", 0)), int(e.get("exp_total", 0))]
		"level_up":
			return "%s → 升级到 Lv%d" % [who, int(e.get("level", 0))]
		"wait":
			return "%s → 等待%s" % [who, "（脚本耗尽）" if String(e.get("source", "")) == "script_exhausted" else ""]
		"battle_end":
			return "[战斗结束] 胜方=%s" % _winner_text(e.get("winner", ""))
		"stop":
			return "[停止] 原因=%s 步数=%d" % [String(e.get("reason", "")), int(e.get("steps", 0))]
		_:
			return "%s → %s" % [who, t]


static func _side_text(s: String) -> String:
	return "玩家" if s == "player" else "敌方"


## 保证目录存在，返回绝对路径（失败返回 ""）。
static func _ensure_dir(out_dir: String) -> String:
	var abs := ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("res://") or out_dir.begins_with("user://") else out_dir
	if not abs.is_absolute_path():
		abs = ProjectSettings.globalize_path("res://").path_join(abs)
	if not DirAccess.dir_exists_absolute(abs):
		var err := DirAccess.make_dir_recursive_absolute(abs)
		if err != OK:
			push_error("BattleReport: 创建目录失败 %s (err=%d)" % [abs, err])
			return ""
	return abs


## 递归把 StringName/Vector2i 等转成 JSON 可序列化的普通类型。
static func _plain(v: Variant) -> Variant:
	match typeof(v):
		TYPE_STRING_NAME:
			return String(v)
		TYPE_VECTOR2I:
			return {"x": (v as Vector2i).x, "y": (v as Vector2i).y}
		TYPE_DICTIONARY:
			var d := {}
			for k in (v as Dictionary):
				d[String(k) if typeof(k) == TYPE_STRING_NAME else k] = _plain(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for item in (v as Array):
				a.append(_plain(item))
			return a
		_:
			if v is Object:
				return str(v)
			return v
