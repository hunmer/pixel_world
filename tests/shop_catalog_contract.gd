## shop_catalog_contract.gd — 商店货架数据契约（W1）
##
## 覆盖：真实 data/shop.json 装载与条目形状（price/limit/id StringName 归一）、
## entry_for 查询、parse_catalog 严格校验（版本整数语义/stock 类型/条目对象/
## id 空缺·未知·重复/price 非负整数必填/limit_per_clear 非负整数缺省 0）。
## 纯静态数据测试：无场景、无存档写入、不动玩家档案。

extends SceneTree

const CatalogScript := preload("res://scripts/campaign/shop_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_real_catalog()
	_test_entry_for()
	_test_parse_validation()
	if failures.is_empty():
		print("SHOP_CATALOG_CONTRACT_OK")
		quit(0)
	else:
		for f in failures:
			print("FAIL: " + f)
		print("SHOP_CATALOG_CONTRACT_FAIL (%d)" % failures.size())
		quit(1)


func _test_real_catalog() -> void:
	var loaded: Dictionary = CatalogScript.load_catalog(true)
	_expect(loaded.ok, "catalog: 真实货架应装载成功，实际 %s" % str(loaded.error))
	if not loaded.ok:
		return
	var stock: Array = loaded.catalog.stock
	_expect(stock.size() == 4, "catalog: 应有 4 条货架，实际 %d" % stock.size())
	var by_id := {}
	for entry: Dictionary in stock:
		by_id[String(entry.id)] = entry
	_expect(by_id.has("hpPotion") and int(by_id["hpPotion"].price) == 80 and int(by_id["hpPotion"].limit_per_clear) == 0,
		"catalog: hpPotion 应 80 金不限购")
	_expect(by_id.has("mpPotion") and int(by_id["mpPotion"].price) == 120 and int(by_id["mpPotion"].limit_per_clear) == 2,
		"catalog: mpPotion 应 120 金每周期限购 2")
	_expect(by_id.has("antidote") and int(by_id["antidote"].price) == 60,
		"catalog: antidote 应 60 金")
	_expect(by_id.has("shuriken") and int(by_id["shuriken"].price) == 100,
		"catalog: shuriken 应 100 金")
	_expect(typeof(stock[0].id) == TYPE_STRING_NAME, "catalog: 货架 id 应归一为 StringName")


func _test_entry_for() -> void:
	var entry: Dictionary = CatalogScript.entry_for("mpPotion")
	_expect(not entry.is_empty() and int(entry.limit_per_clear) == 2,
		"catalog: entry_for 应命中 mpPotion 且 limit=2")
	_expect(CatalogScript.entry_for("no_such").is_empty(),
		"catalog: entry_for 未命中应返回空")


func _test_parse_validation() -> void:
	_expect(CatalogScript.parse_catalog({"version": 1, "stock": []}).ok,
		"catalog: 空货架应合法")
	var mk := func(stock: Variant) -> Dictionary:
		return {"version": 1, "stock": stock}
	var cases := [
		{"d": {"version": 2, "stock": []}, "why": "版本不支持"},
		{"d": {"version": 1.5, "stock": []}, "why": "版本非整数"},
		{"d": {"stock": []}, "why": "版本缺失"},
		{"d": {"version": 1, "stock": "x"}, "why": "stock 非数组"},
		{"d": mk.call(["x"]), "why": "条目非对象"},
		{"d": mk.call([{"price": 10}]), "why": "条目缺 id"},
		{"d": mk.call([{"id": "no_such_item", "price": 10}]), "why": "未知物品"},
		{"d": mk.call([{"id": "hpPotion", "price": 10}, {"id": "hpPotion", "price": 20}]), "why": "id 重复"},
		{"d": mk.call([{"id": "hpPotion"}]), "why": "缺 price"},
		{"d": mk.call([{"id": "hpPotion", "price": -1}]), "why": "price 负数"},
		{"d": mk.call([{"id": "hpPotion", "price": 1.5}]), "why": "price 非整数"},
		{"d": mk.call([{"id": "hpPotion", "price": "80"}]), "why": "price 字符串"},
		{"d": mk.call([{"id": "hpPotion", "price": 80, "limit_per_clear": -1}]), "why": "limit 负数"},
		{"d": mk.call([{"id": "hpPotion", "price": 80, "limit_per_clear": 1.5}]), "why": "limit 非整数"},
	]
	for case in cases:
		_expect(not CatalogScript.parse_catalog(case.d).ok,
			"catalog: %s 应被拒绝" % case.why)
	var norm: Dictionary = CatalogScript.parse_catalog(mk.call([{"id": "hpPotion", "price": 80}]))
	_expect(norm.ok and int(norm.catalog.stock[0].limit_per_clear) == 0,
		"catalog: limit 缺省应为 0（不限购）")


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
