## scripts/scenes/campaign_format.gd — 冒险 UI 共享取值/格式化工具
##
## 纯静态、无状态：把 CampaignSession 返回的宽松 Dictionary 安全转成展示
## 文本；对缺失字段/未知类型给出可读回退，绝不抛错。所有会话调用统一经
## 本类入口，session 缺失/方法缺失/返回类型不符时回退成约定形状，
## 调用方只处理一种形态。
## 角色行 unit_label 带 exp 时显示 EXP 当前/阈值（WeaponData.exp_to_next）；
## level_up_lines 把胜利 receipt 的 level_ups 差分转成中文升级行。
extends RefCounted

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const WeaponDataScript = preload("res://scripts/core/weapons.gd")

## 详情弹窗里跳过的内部键（只读查看其余全部键）。
const DETAIL_SKIP_KEYS: Array[String] = ["token"]

## 属性键 → 升级回显短名（str→力 等；未知键原样显示）。
const STAT_LABELS := {
	"hp": "HP", "mp": "MP", "str": "力", "mag": "魔", "skl": "技",
	"spd": "速", "luk": "运", "def": "防", "res": "魔防",
}

## 升级行的成长固定输出序（与战斗侧属性展示一致）；不依赖输入字典插入顺序。
const STAT_ORDER: Array[String] = ["hp", "mp", "str", "mag", "skl", "spd", "luk", "def", "res"]


static func session_ready(session: Node) -> bool:
	return session != null and is_instance_valid(session)


## 列表重建的安全清空：先脱离树再延迟释放。同步 free 会打断仍处于
## pressed 信号栈上的按钮（load_profile 同步 emit changed → refresh →
## 重建时，信号源按钮正在发射中），并使 sfx lambda 捕获失效报错。
static func detach_children(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


## 安全抓焦：控件有效、可见于树、且未被打断焦点（FOCUS_NONE）才允许
## grab_focus，避免「This control can't grab focus」警告（弹层陷阱禁用
## 背景焦点期间的同帧抓焦、不可见屏的 on_shown 等）。
static func can_grab_focus(control: Control) -> bool:
	return (
		control != null
		and is_instance_valid(control)
		and control.is_visible_in_tree()
		and control.focus_mode != Control.FOCUS_NONE
	)


## 调用返回 {ok,error,...} Dictionary 的会话方法；异常统一回退
## {ok:false, error:可操作提示}。
static func call_dict(session: Node, method: String, args: Array = []) -> Dictionary:
	if not session_ready(session):
		return {
			"ok": false,
			"error": "CampaignSession 未注册：请确认 project.godot autoload 已含 "
				+ "scripts/campaign/campaign_session.gd（lead 负责）。",
		}
	if not session.has_method(method):
		return {"ok": false, "error": "CampaignSession 缺少方法 %s()，请与数据层核对 API。" % method}
	var result: Variant = session.callv(method, args)
	if result is Dictionary:
		return result
	return {"ok": false, "error": "CampaignSession.%s() 返回非 Dictionary 结果。" % method}


## 调用返回数组（list_profiles / list_levels）的会话方法；异常回退空数组。
static func call_array(session: Node, method: String, args: Array = []) -> Array:
	if not session_ready(session) or not session.has_method(method):
		return []
	var result: Variant = session.callv(method, args)
	if result is Array:
		return result
	return []


## 调用返回裸 Dictionary（get_profile / get_last_result）的方法；异常回退空字典。
static func call_raw_dict(session: Node, method: String, args: Array = []) -> Dictionary:
	if not session_ready(session) or not session.has_method(method):
		return {}
	var result: Variant = session.callv(method, args)
	if result is Dictionary:
		return result
	return {}


## 调用无返回值方法（leave_profile / clear_last_result）；异常静默跳过。
static func call_void(session: Node, method: String, args: Array = []) -> void:
	if session_ready(session) and session.has_method(method):
		session.callv(method, args)


## saved_at 宽松格式化：数字按 Unix 时间，字符串原样，缺失显示占位。
static func format_saved_at(value: Variant) -> String:
	if value is float or value is int:
		var seconds := int(value)
		if seconds <= 0:
			return "—"
		return Time.get_datetime_string_from_unix_time(seconds).replace("T", " ")
	if value is String and String(value) != "":
		return String(value)
	return "—"


static func as_int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	return fallback


static func as_text(value: Variant, fallback: String = "—") -> String:
	if value == null:
		return fallback
	if value is String:
		return String(value) if String(value) != "" else fallback
	return str(value)


static func profile_name(profile: Dictionary) -> String:
	return as_text(profile.get("name", profile.get("id", null)), "未命名存档")


## 排序比较：saved_at 新→旧；数字比数值，其余比字符串（ISO 串字典序即时间序）。
static func saved_later_than(a: Dictionary, b: Dictionary) -> bool:
	var av: Variant = a.get("saved_at", null)
	var bv: Variant = b.get("saved_at", null)
	var a_num := av is float or av is int
	var b_num := bv is float or bv is int
	if a_num and b_num:
		return float(av) > float(bv)
	return String(av) > String(bv)


## 角色行摘要：名称 + 白名单字段（缺失即跳过，字段名由数据层演进时自动降级）。
## 带有效 exp（等级为数字）时追加 EXP 当前/阈值，阈值 = WeaponData.exp_to_next(level)；
## 无 exp 键的旧形状单位不显示，保证向后兼容。
static func unit_label(unit: Dictionary) -> String:
	var label := as_text(unit.get("name", unit.get("id", null)), "未命名单位")
	var parts: Array[String] = []
	var level: Variant = unit.get("level", null)
	if level != null:
		parts.append("Lv%s" % as_text(level, "?"))
	if unit.has("exp") and (level is int or level is float):
		parts.append(
			"EXP %s/%d"
			% [as_text(unit.get("exp"), "?"), WeaponDataScript.exp_to_next(maxi(1, int(level)))]
		)
	if unit.has("hp"):
		parts.append("HP %s/%s" % [as_text(unit.get("hp"), "?"), as_text(unit.get("max_hp"), "?")])
	if unit.has("mp"):
		parts.append("MP %s/%s" % [as_text(unit.get("mp"), "?"), as_text(unit.get("max_mp"), "?")])
	if parts.is_empty():
		return label
	return "%s · %s" % [label, " · ".join(parts)]


## 物品行标签：{id,name,uses,count} 或裸字符串都能出可读文本。
static func item_label(item: Variant) -> String:
	if item is String:
		return String(item)
	if item is Dictionary:
		var dict: Dictionary = item
		var label := as_text(dict.get("name", dict.get("id", null)), "未知物品")
		if dict.has("count"):
			return "%s ×%s" % [label, as_text(dict.get("count"), "?")]
		if dict.has("uses"):
			return "%s（剩余 %s 次）" % [label, as_text(dict.get("uses"), "?")]
		return label
	return str(item)


## 奖励/获得物品的一行文本；空数组显示「无」。
static func items_line(items: Variant) -> String:
	if items is Array:
		var array: Array = items
		if array.is_empty():
			return "无"
		var labels: Array[String] = []
		for item: Variant in array:
			labels.append(item_label(item))
		return "、".join(labels)
	return as_text(items)


## 胜利结算的升级行：每条 {id,name,from_level,to_level,stat_deltas} 一行
## 「升级：罗兰 3→4（力+1 速+1）」，成长空则省略括号。成长按 STAT_ORDER
## 固定序输出（未知键排序后追加），同一条差分永远得到同一段文本。
## 旧 receipt 无 level_ups 键 → 返回空数组（调用方不追加任何行）。
static func level_up_lines(level_ups: Variant) -> Array[String]:
	var lines: Array[String] = []
	if level_ups is not Array:
		return lines
	for entry: Variant in level_ups:
		if entry is not Dictionary:
			continue
		var dict: Dictionary = entry
		var unit_name := as_text(dict.get("name", dict.get("id", null)), "未知单位")
		var from_level := as_int(dict.get("from_level", 0), 0)
		var to_level := as_int(dict.get("to_level", 0), 0)
		var growths: Array[String] = _stat_growth_labels(dict.get("stat_deltas", {}))
		if growths.is_empty():
			lines.append("升级：%s %d→%d" % [unit_name, from_level, to_level])
		else:
			lines.append("升级：%s %d→%d（%s）" % [unit_name, from_level, to_level, " ".join(growths)])
	return lines


## stat_deltas → 「力+1」标签列表：九属性按 STAT_ORDER 固定序（不依赖输入
## 字典插入顺序），未知键按字典序稳定追加；零差分不显示。
static func _stat_growth_labels(deltas: Variant) -> Array[String]:
	var labels: Array[String] = []
	if deltas is not Dictionary:
		return labels
	var deltas_dict: Dictionary = deltas
	var handled := {}
	for key: String in STAT_ORDER:
		if not deltas_dict.has(key):
			continue
		handled[key] = true
		var delta := as_int(deltas_dict[key], 0)
		if delta != 0:
			labels.append("%s%+d" % [String(STAT_LABELS.get(key, key)), delta])
	var extra: Array[String] = []
	for key: Variant in deltas_dict.keys():
		var key_text := String(key)
		if not handled.has(key_text):
			extra.append(key_text)
	extra.sort()
	for key: String in extra:
		var delta := as_int(deltas_dict[key], 0)
		if delta != 0:
			labels.append("%s%+d" % [String(STAT_LABELS.get(key, key)), delta])
	return labels


## 详情弹窗正文：逐键只读展示，复杂值折叠成计数行。
static func detail_lines(data: Dictionary) -> String:
	var lines: Array[String] = []
	for key: Variant in data.keys():
		var key_text := String(key)
		if key_text in DETAIL_SKIP_KEYS:
			continue
		var value: Variant = data[key]
		if value is Array:
			lines.append("%s：%d 项" % [key_text, (value as Array).size()])
		elif value is Dictionary:
			lines.append("%s：%d 键" % [key_text, (value as Dictionary).size()])
		else:
			lines.append("%s：%s" % [key_text, as_text(value, "—")])
	if lines.is_empty():
		return "（暂无数据）"
	return "\n".join(lines)
