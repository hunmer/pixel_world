## shop_catalog.gd — 商店货架数据装载与校验（纯静态，带缓存）
##
## 数据源 res://data/shop.json（version 1）。条目 {id, price, limit_per_clear}：
## id 必须存在于 ItemData 且不重复；price 必填非负整数；limit_per_clear 可选
## 非负整数（缺省 0 = 不限购）。
## 唯一限购周期 = completed_levels.size()（W2 CampaignSession 按此刷新限购额度：
## 每新通关一关额度重置，repeat 通关不重置；purchase 形状 {clear_index, counts}）。
## 本模块只负责数据与校验，不持有购买状态。

class_name ShopCatalog
extends RefCounted

const SHOP_PATH := "res://data/shop.json"
const SUPPORTED_VERSION := 1

const ItemDataScript := preload("res://scripts/core/items.gd")

static var _cache: Dictionary = {}
static var _cache_loaded := false


## 读取并校验货架（带缓存）。返回 {ok:true, catalog} 或 {ok:false, error}。
## catalog = {version:int, stock:[{id:StringName, price:int, limit_per_clear:int}]}。
static func load_catalog(force_reload := false) -> Dictionary:
	if _cache_loaded and not force_reload:
		return _cache
	_cache_loaded = true
	_cache = {"ok": false, "error": ""}
	if not FileAccess.file_exists(SHOP_PATH):
		_cache.error = "商店配置缺失：%s" % SHOP_PATH
		return _cache
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(SHOP_PATH))
	if err != OK:
		_cache.error = "商店配置 JSON 解析失败（行 %d）：%s" % [json.get_error_line(), json.get_error_message()]
		return _cache
	if json.data is not Dictionary:
		_cache.error = "商店配置根节点必须是对象"
		return _cache
	_cache = parse_catalog(json.data)
	return _cache


## 校验一个货架字典（不读文件）。load_catalog 与测试共用。
static func parse_catalog(data: Dictionary) -> Dictionary:
	var version: Variant = data.get("version", 0)
	if not _is_json_int(version) or int(version) != SUPPORTED_VERSION:
		return {"ok": false, "error": "商店配置版本不支持：%s（支持 %d）" % [str(version), SUPPORTED_VERSION]}
	var raw_stock: Variant = data.get("stock", [])
	if raw_stock is not Array:
		return {"ok": false, "error": "商店配置 stock 必须是数组"}
	var stock: Array = []
	var seen_ids := {}
	for i in (raw_stock as Array).size():
		var raw_entry: Variant = (raw_stock as Array)[i]
		if raw_entry is not Dictionary:
			return {"ok": false, "error": "stock[%d] 必须是对象" % i}
		var entry: Dictionary = raw_entry
		var item_id := str(entry.get("id", ""))
		if item_id == "":
			return {"ok": false, "error": "stock[%d] 缺少 id" % i}
		if ItemDataScript.get_item(item_id).get("id", &"") != StringName(item_id):
			return {"ok": false, "error": "stock[%d] 引用未知物品：%s" % [i, item_id]}
		if seen_ids.has(item_id):
			return {"ok": false, "error": "stock[%d] id 重复：%s" % [i, item_id]}
		seen_ids[item_id] = true
		var price: Variant = entry.get("price", null)
		if not _is_json_int(price) or int(price) < 0:
			return {"ok": false, "error": "stock[%d]（%s）price 必须是 >= 0 的整数" % [i, item_id]}
		var limit: Variant = entry.get("limit_per_clear", 0)
		if not _is_json_int(limit) or int(limit) < 0:
			return {"ok": false, "error": "stock[%d]（%s）limit_per_clear 必须是 >= 0 的整数" % [i, item_id]}
		stock.append({
			"id": StringName(item_id),
			"price": int(price),
			"limit_per_clear": int(limit),
		})
	return {
		"ok": true,
		"error": "",
		"catalog": {"version": int(version), "stock": stock},
	}


## 货架列表（已校验）。配置无效时为空数组。
static func stock() -> Array:
	var loaded := load_catalog()
	if not loaded.ok:
		return []
	return loaded.catalog.stock


## 按 id 查货架条目；不存在返回 {}。
static func entry_for(item_id: String) -> Dictionary:
	for entry in stock():
		if String(entry.id) == item_id:
			return entry
	return {}


static func _is_json_int(v: Variant) -> bool:
	if v is int:
		return true
	if v is float:
		return is_finite(v) and float(int(v)) == v
	return false
