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
## 返回 {gold:int, items:[{id:StringName, name:String, count:int}]}。
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
	return {"gold": maxi(0, _as_int(branch.get("gold", 0))), "items": items}


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
		return {"ok": true, "error": "", "rewards": {"gold": gold, "items": items}}

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
