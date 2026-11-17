## campaign_config.gd — 冒险模式配置装载与校验
##
## 职责：读取 res://data/campaign.json，校验关卡顺序 / 来源 / 奖励配表，
## 提供关卡查询与奖励解析（每关可覆写全局奖励）。纯静态，无状态（带缓存）。

class_name CampaignConfig
extends RefCounted

const CONFIG_PATH := "res://data/campaign.json"
const SUPPORTED_VERSION := 1

const BattlefieldLoaderScript := preload("res://scripts/core/battlefield_loader.gd")
const ItemDataScript := preload("res://scripts/core/items.gd")

static var _cache: Dictionary = {}
static var _cache_loaded := false


## 读取并校验配置（带缓存）。返回 {ok:true, config} 或 {ok:false, error}。
## config = {version, levels:[{index,id,name,source,rewards?}], rewards:{first_clear,repeat}}
static func load_config(force_reload := false) -> Dictionary:
	if _cache_loaded and not force_reload:
		return _cache
	_cache_loaded = true
	_cache = {"ok": false, "error": ""}
	if not FileAccess.file_exists(CONFIG_PATH):
		_cache.error = "冒险配置缺失：%s" % CONFIG_PATH
		return _cache
	var parsed: Variant
	var raw_text := FileAccess.get_file_as_string(CONFIG_PATH)
	var json := JSON.new()
	var err := json.parse(raw_text)
	if err != OK:
		_cache.error = "冒险配置 JSON 解析失败（行 %d）：%s" % [json.get_error_line(), json.get_error_message()]
		return _cache
	parsed = json.data
	if parsed is not Dictionary:
		_cache.error = "冒险配置根节点必须是对象"
		return _cache
	_cache = parse_config(parsed)
	return _cache


## 校验一个配置字典（不读文件）。load_config 与测试共用。
static func parse_config(data: Dictionary) -> Dictionary:
	var fail := func(msg: String) -> Dictionary:
		return {"ok": false, "error": msg}

	var version := _as_int(data.get("version", 0))
	if version != SUPPORTED_VERSION:
		return fail.call("冒险配置版本不支持：%d（支持 %d）" % [version, SUPPORTED_VERSION])

	var raw_levels: Variant = data.get("levels", [])
	if raw_levels is not Array or raw_levels.is_empty():
		return fail.call("冒险配置 levels 不能为空")
	var levels: Array = []
	var seen_ids := {}
	for i in raw_levels.size():
		var entry: Variant = raw_levels[i]
		if entry is not Dictionary:
			return fail.call("关卡 #%d 必须是对象" % i)
		var level_id := str(entry.get("id", ""))
		var level_name := str(entry.get("name", ""))
		var source := str(entry.get("source", ""))
		if level_id.strip_edges() == "":
			return fail.call("关卡 #%d 缺少 id" % i)
		if seen_ids.has(level_id):
			return fail.call("关卡 id 重复：%s" % level_id)
		seen_ids[level_id] = true
		if level_name.strip_edges() == "":
			return fail.call("关卡 %s 缺少 name" % level_id)
		if source == "" or not source.begins_with("res://"):
			return fail.call("关卡 %s source 必须是 res:// 路径" % level_id)
		if not FileAccess.file_exists(source):
			return fail.call("关卡 %s source 文件不存在：%s" % [level_id, source])
		var probe: Dictionary = BattlefieldLoaderScript.load_battlefield(source)
		if not probe.get("ok", false):
			return fail.call("关卡 %s source 无法装载：%s" % [level_id, str(probe.get("error", ""))])
		var chapter: Dictionary = probe.get("chapter", {})
		if chapter.get("playerUnits", []).is_empty():
			return fail.call("关卡 %s 没有玩家单位槽位，无法作为冒险关卡" % level_id)
		var level := {
			"index": i,
			"id": level_id,
			"name": level_name,
			"source": source,
		}
		if entry.has("rewards"):
			var level_rewards: Variant = entry["rewards"]
			if level_rewards is not Dictionary:
				return fail.call("关卡 %s rewards 必须是对象" % level_id)
			var reward_check := _validate_rewards(level_rewards, "关卡 %s rewards" % level_id)
			if not reward_check.ok:
				return fail.call(reward_check.error)
			level["rewards"] = reward_check.rewards
		levels.append(level)

	var raw_rewards: Variant = data.get("rewards", {})
	if raw_rewards is not Dictionary:
		return fail.call("rewards 必须是对象")
	var reward_check := _validate_rewards(raw_rewards, "rewards")
	if not reward_check.ok:
		return fail.call(reward_check.error)

	return {
		"ok": true,
		"error": "",
		"config": {
			"version": version,
			"levels": levels,
			"rewards": reward_check.rewards,
		},
	}


## 关卡列表（已校验、含 index）。配置无效时为空数组。
static func levels() -> Array:
	var loaded := load_config()
	if not loaded.ok:
		return []
	return loaded.config.levels


## 关卡数量。配置无效时 0。
static func level_count() -> int:
	return levels().size()


## 按 id 查关卡；不存在返回 {}。
static func get_level(level_id: String) -> Dictionary:
	for level in levels():
		if str(level.id) == level_id:
			return level
	return {}


## 关卡序号；不存在返回 -1。
static func level_index(level_id: String) -> int:
	var level := get_level(level_id)
	if level.is_empty():
		return -1
	return int(level.index)


## 第一关 id；配置无效返回 ""。
static func first_level_id() -> String:
	var all := levels()
	if all.is_empty():
		return ""
	return str(all[0].id)


## 解析某关的奖励。first_clear=true 用首胜奖励，否则用重复奖励。
## 返回 {gold:int, items:[{id:StringName, name:String, count:int}],
##       loot_table:[{id:StringName, count:int, weight:float}], loot_rolls:int}。
## 无掉落表关卡 loot_table=[] 且 loot_rolls=0（现网固定奖励行为精确不变）。
static func rewards_for(level_id: String, first_clear: bool) -> Dictionary:
	var level := get_level(level_id)
	var base: Dictionary = {}
	if not level.is_empty() and level.has("rewards"):
		base = level.rewards
	else:
		base = load_config().get("config", {}).get("rewards", {})
	var branch: Dictionary = base.get("first_clear" if first_clear else "repeat", {})
	var items: Array = []
	for raw_item: Variant in branch.get("items", []):
		var item_id := str(raw_item.get("id", ""))
		var count := _as_int(raw_item.get("count", 1))
		if item_id == "" or count <= 0:
			continue
		items.append({
			"id": StringName(item_id),
			"name": ItemDataScript.item_name(item_id),
			"count": count,
		})
	var loot_table: Array = []
	for raw_entry: Variant in branch.get("loot_table", []):
		var entry_id := str(raw_entry.get("id", ""))
		if entry_id == "":
			continue
		loot_table.append({
			"id": StringName(entry_id),
			"count": maxi(1, _as_int(raw_entry.get("count", 1))),
			"weight": maxf(0.0, float(raw_entry.get("weight", 1.0))),
		})
	return {
		"gold": maxi(0, _as_int(branch.get("gold", 0))),
		"items": items,
		"loot_table": loot_table,
		"loot_rolls": maxi(0, _as_int(branch.get("loot_rolls", 0))),
	}


## 纯函数掉落掷骰：对 loot_table 做 rolls 次有放回加权抽样，同 id 结果合并，
## 输出按表内首次出现顺序。空表或 rolls<=0 时立即返回空数组且**完全不触碰 rng**
## （无表关卡不得消耗任何随机数）；不修改入参。
## 返回 [{id:StringName, name:String, count:int}]，count 为各次抽样条目 count 之和。
static func roll_loot(table: Array, rolls: int, rng: RandomNumberGenerator) -> Array:
	if table.is_empty() or rolls <= 0:
		return []
	var order: Array = []
	var weights: Array = []
	var total := 0.0
	for raw_entry: Variant in table:
		var weight := float(raw_entry.get("weight", 1.0))
		if not is_finite(weight) or weight <= 0.0:
			continue
		order.append(raw_entry)
		weights.append(weight)
		total += weight
	if total <= 0.0:
		return []
	var counts := {}
	for _i in range(rolls):
		var pick := rng.randf() * total
		var acc := 0.0
		var chosen: Variant = null
		for j in range(order.size()):
			acc += weights[j]
			if pick < acc:
				chosen = order[j]
				break
		if chosen == null:
			chosen = order[order.size() - 1]
		var chosen_id := str(chosen.get("id", ""))
		counts[chosen_id] = int(counts.get(chosen_id, 0)) + maxi(1, int(chosen.get("count", 1)))
	var out: Array = []
	for raw_entry: Variant in order:
		var entry_id := str(raw_entry.get("id", ""))
		if counts.has(entry_id):
			out.append({
				"id": StringName(entry_id),
				"name": ItemDataScript.item_name(entry_id),
				"count": int(counts[entry_id]),
			})
			counts.erase(entry_id)
	return out


static func _validate_rewards(rewards: Dictionary, where: String) -> Dictionary:
	var check_branch := func(branch: Variant, branch_name: String) -> Dictionary:
		if branch is not Dictionary:
			return {"ok": false, "error": "%s.%s 必须是对象" % [where, branch_name]}
		var gold := _as_int(branch.get("gold", 0))
		if gold < 0:
			return {"ok": false, "error": "%s.%s.gold 不能为负" % [where, branch_name]}
		var raw_items: Variant = branch.get("items", [])
		if raw_items is not Array:
			return {"ok": false, "error": "%s.%s.items 必须是数组" % [where, branch_name]}
		var items: Array = []
		for raw_item: Variant in raw_items:
			if raw_item is not Dictionary:
				return {"ok": false, "error": "%s.%s.items 条目必须是对象" % [where, branch_name]}
			var item_id := str(raw_item.get("id", ""))
			if item_id == "":
				return {"ok": false, "error": "%s.%s.items 条目缺少 id" % [where, branch_name]}
			if ItemDataScript.get_item(item_id).get("id", &"") != StringName(item_id):
				return {"ok": false, "error": "%s.%s.items 引用未知物品：%s" % [where, branch_name, item_id]}
			var count := _as_int(raw_item.get("count", 1))
			if count < 1:
				return {"ok": false, "error": "%s.%s.items 条目 count 必须 >= 1" % [where, branch_name]}
			items.append({"id": item_id, "count": count})
		# —— 关卡掉落表（W1）：缺省无掉落；有表未设 loot_rolls 默认 1 次 ——
		var raw_loot_table: Variant = branch.get("loot_table", [])
		if raw_loot_table is not Array:
			return {"ok": false, "error": "%s.%s.loot_table 必须是数组" % [where, branch_name]}
		var loot_table: Array = []
		var seen_loot_ids := {}
		for raw_entry: Variant in raw_loot_table:
			if raw_entry is not Dictionary:
				return {"ok": false, "error": "%s.%s.loot_table 条目必须是对象" % [where, branch_name]}
			var loot_id := str(raw_entry.get("id", ""))
			if loot_id == "":
				return {"ok": false, "error": "%s.%s.loot_table 条目缺少 id" % [where, branch_name]}
			if ItemDataScript.get_item(loot_id).get("id", &"") != StringName(loot_id):
				return {"ok": false, "error": "%s.%s.loot_table 引用未知物品：%s" % [where, branch_name, loot_id]}
			if seen_loot_ids.has(loot_id):
				return {"ok": false, "error": "%s.%s.loot_table 条目 id 重复：%s" % [where, branch_name, loot_id]}
			seen_loot_ids[loot_id] = true
			var loot_count: Variant = raw_entry.get("count", 1)
			if not _is_json_int(loot_count) or int(loot_count) < 1:
				return {"ok": false, "error": "%s.%s.loot_table 条目 count 必须是 >= 1 的整数" % [where, branch_name]}
			var loot_weight: Variant = raw_entry.get("weight", 1)
			var weight_ok: bool = (loot_weight is int and loot_weight > 0) \
				or (loot_weight is float and is_finite(loot_weight) and loot_weight > 0.0)
			if not weight_ok:
				return {"ok": false, "error": "%s.%s.loot_table 条目 weight 必须是有限正数" % [where, branch_name]}
			loot_table.append({
				"id": loot_id,
				"count": int(loot_count),
				"weight": float(loot_weight),
			})
		var loot_rolls := 0
		if branch.has("loot_rolls"):
			var rolls_raw: Variant = branch.get("loot_rolls")
			if not _is_json_int(rolls_raw) or int(rolls_raw) < 0:
				return {"ok": false, "error": "%s.%s.loot_rolls 必须是 >= 0 的整数" % [where, branch_name]}
			loot_rolls = int(rolls_raw)
		elif not loot_table.is_empty():
			loot_rolls = 1
		if loot_table.is_empty():
			loot_rolls = 0
		return {"ok": true, "error": "", "rewards": {
			"gold": gold,
			"items": items,
			"loot_table": loot_table,
			"loot_rolls": loot_rolls,
		}}

	var first: Dictionary = check_branch.call(rewards.get("first_clear", {}), "first_clear")
	if not first.ok:
		return first
	var repeat: Dictionary = check_branch.call(rewards.get("repeat", {}), "repeat")
	if not repeat.ok:
		return repeat
	return {
		"ok": true,
		"error": "",
		"rewards": {"first_clear": first.rewards, "repeat": repeat.rewards},
	}


static func _as_int(value: Variant) -> int:
	if value is float:
		return int(value)
	if value is int:
		return value
	if value is String and value.is_valid_int():
		return int(value)
	return 0


## JSON 整数语义判定（数字必须是整数值：拒绝 1.5/字符串/布尔），
## 与 battlefield_loader._is_json_int 同模式，供 loot 次数等严格校验复用。
static func _is_json_int(v: Variant) -> bool:
	if v is int:
		return true
	if v is float:
		return is_finite(v) and float(int(v)) == v
	return false
