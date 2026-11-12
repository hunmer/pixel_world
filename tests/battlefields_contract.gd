extends SceneTree

## tests/battlefields_contract.gd — JSON 战场加载器契约测试
## 运行：godot --headless --path . --script res://tests/battlefields_contract.gd
## 覆盖：目录扫描 / 两种地形写法 / 单位构建 / 全部校验错误分支 / chapter 结构。

const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")

const TMP_DIR := "user://battlefield_contract_tmp"

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_listing()
	_test_examples_valid()
	_test_custom_legend()
	_test_block_layout()
	_test_error_cases()
	# 清理临时目录
	var dir := DirAccess.open(TMP_DIR)
	if dir != null:
		for f in ["bad_glyph.json", "ragged.json", "bad_class.json", "oob.json",
				"on_water.json", "overlap.json", "no_terrain.json", "empty_units.json",
				"map_string_rows.json", "bad_layout_version.json", "bad_layout_range.json",
				"bad_layout_duplicate.json", "bad_layout_type.json", "bad_layout_oob.json"]:
			if dir.file_exists(f):
				dir.remove(f)
		var err := dir.change_dir("..")
		if err == OK:
			dir.remove(TMP_DIR.get_file())
	if failures.is_empty():
		print("BATTLEFIELDS_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


## 1) 目录扫描：≥4 个示例、按文件名排序、条目元信息完整
func _test_listing() -> void:
	var bfs: Array = BattlefieldLoaderScript.list_battlefields()
	_expect(bfs.size() >= 4, "示例战场不足 4 个（当前 %d）" % bfs.size())
	var prev_file := ""
	var ids := {}
	for e in bfs:
		var entry: Dictionary = e
		_expect(String(entry.get("error", "x")) == "", "示例 %s 加载失败: %s" % [entry.get("file", "?"), entry.get("error", "")])
		_expect(int(entry.get("width", 0)) > 0 and int(entry.get("height", 0)) > 0,
			"示例 %s 尺寸无效" % entry.get("file", "?"))
		_expect(int(entry.get("players", 0)) >= 1 and int(entry.get("enemies", 0)) >= 1,
			"示例 %s 双方单位数必须 ≥1" % entry.get("file", "?"))
		_expect(not String(entry.get("name", "")).is_empty(), "示例 %s 缺 name" % entry.get("file", "?"))
		ids[String(entry.get("id", ""))] = true
		if not prev_file.is_empty():
			_expect(String(entry["file"]) >= prev_file, "列表未按文件名排序")
		prev_file = String(entry["file"])
	# 两个地形写法都要有示例覆盖（rows 与 map）
	_expect(ids.has("plains_skirmish") or ids.has("arena_1v1") or ids.has("mountain_pass"),
		"缺少 rows 字符画写法的示例")
	_expect(ids.has("river_crossing"), "缺少 map 全名写法的示例")


## 2) 每个示例：chapter 结构与 world_to_chapter 输出同构
func _test_examples_valid() -> void:
	var bfs: Array = BattlefieldLoaderScript.list_battlefields()
	for e in bfs:
		var entry: Dictionary = e
		var res := BattlefieldLoaderScript.load_battlefield(String(entry["path"]))
		_expect(bool(res.get("ok", false)), "加载 %s 失败: %s" % [entry["file"], res.get("error", "")])
		if not bool(res.get("ok", false)):
			continue
		var ch: Dictionary = res["chapter"]
		var w := int(ch["width"])
		var h := int(ch["height"])
		_expect((ch["map"] as Array).size() == h, "%s map 行数 != height" % entry["file"])
		for y in range(h):
			_expect((ch["map"][y] as Array).size() == w, "%s map 第 %d 行宽 != width" % [entry["file"], y])
		var occupied := {}
		for key in ["playerUnits", "enemyUnits"]:
			var expect_faction := &"player" if key == "playerUnits" else &"enemy"
			for u in ch[key]:
				var unit: Dictionary = u
				_expect(unit[&"faction"] == expect_faction, "%s %s 阵营错误" % [entry["file"], key])
				var pos: Vector2i = unit[&"position"]
				_expect(pos.x >= 0 and pos.y >= 0 and pos.x < w and pos.y < h,
					"%s 单位 %s 坐标越界 %s" % [entry["file"], unit[&"name"], str(pos)])
				_expect(not occupied.has(pos), "%s 单位重叠在 %s" % [entry["file"], str(pos)])
				occupied[pos] = true
				_expect(int(unit[&"hp"]) > 0 and int(unit[&"stats"][&"hp"]) > 0,
					"%s 单位 %s HP 无效" % [entry["file"], unit[&"name"]])
				_expect(not (unit[&"weapon"] as Dictionary).is_empty(),
					"%s 单位 %s 缺武器" % [entry["file"], unit[&"name"]])
		_expect(String(ch["name"]) != "", "%s chapter 缺 name" % entry["file"])


## 3) legend 覆盖：自定义图例生效
func _test_custom_legend() -> void:
	var json := """{
		"rows": ["ab", "ba"],
		"legend": { "a": "forest", "b": "village" },
		"playerUnits": [{ "class": "swordsman", "x": 0, "y": 0 }],
		"enemyUnits": [{ "class": "archer", "x": 1, "y": 1 }]
	}"""
	var path := _write_tmp("legend_check.json", json)
	var res := BattlefieldLoaderScript.load_battlefield(path)
	_expect(bool(res.get("ok", false)), "legend 覆盖加载失败: %s" % res.get("error", ""))
	if bool(res.get("ok", false)):
		var ch: Dictionary = res["chapter"]
		_expect(ch["map"][0][0] == &"forest" and ch["map"][0][1] == &"village", "legend 映射未生效")
		_expect(ch["map"][1][0] == &"village" and ch["map"][1][1] == &"forest", "legend 映射未生效(第2行)")
	var dir := DirAccess.open(TMP_DIR)
	if dir != null:
		dir.remove("legend_check.json")


## 4) 显式 block_layout：部分 cells 归一化、default_z 与 chapter 透传
func _test_block_layout() -> void:
	var json := """{
		"rows": ["..", ".."],
		"playerUnits": [{ "class": "swordsman", "x": 0, "y": 0 }],
		"enemyUnits": [{ "class": "archer", "x": 1, "y": 1 }],
		"block_layout": {"version": 1, "default_z": 4,
			"cells": [{"x": 1, "y": 1, "z": 12}, {"x": 0, "y": 1}]}
	}"""
	var path := _write_tmp("partial_block_layout.json", json)
	var res := BattlefieldLoaderScript.load_battlefield(path)
	_expect(bool(res.get("ok", false)), "部分 block_layout 加载失败: %s" % res.get("error", ""))
	if bool(res.get("ok", false)):
		var layout: Dictionary = res["chapter"].get("block_layout", {})
		_expect(int(layout.get("version", 0)) == 1 and int(layout.get("default_z", -1)) == 4,
			"loader 透传 block_layout version/default_z")
		_expect((layout.get("cells", []) as Array).size() == 4, "loader 将部分 cells 归一化为全格")
		var heights := {}
		for raw in layout.get("cells", []):
			var cell: Dictionary = raw
			heights[Vector2i(int(cell.x), int(cell.y))] = int(cell.z)
		_expect(int(heights.get(Vector2i(0, 0), -1)) == 4
			and int(heights.get(Vector2i(1, 0), -1)) == 4,
			"缺失格补 default_z=4")
		_expect(int(heights.get(Vector2i(0, 1), -1)) == 0
			and int(heights.get(Vector2i(1, 1), -1)) == 12,
			"已有格 z 缺省 0，显式 z 原样透传")
	var dir := DirAccess.open(TMP_DIR)
	if dir != null:
		dir.remove("partial_block_layout.json")


## 5) 错误分支：每个坏文件必须被对应错误拦下（ok=false 且 error 含关键词）
func _test_error_cases() -> void:
	var cases := [
		["bad_glyph.json", '{"rows": ["..z."], "playerUnits": [{"class":"swordsman","x":0,"y":0}], "enemyUnits": [{"class":"archer","x":1,"y":0}]}', "z"],
		["ragged.json", '{"rows": ["...", ".."], "playerUnits": [{"class":"swordsman","x":0,"y":0}], "enemyUnits": [{"class":"archer","x":1,"y":0}]}', "不一致"],
		["bad_class.json", '{"rows": ["..."], "playerUnits": [{"class":"samurai","x":0,"y":0}], "enemyUnits": [{"class":"archer","x":1,"y":0}]}', "职业不存在"],
		["oob.json", '{"rows": ["..."], "playerUnits": [{"class":"swordsman","x":9,"y":0}], "enemyUnits": [{"class":"archer","x":1,"y":0}]}', "越界"],
		["on_water.json", '{"rows": [".w."], "playerUnits": [{"class":"swordsman","x":1,"y":0}], "enemyUnits": [{"class":"archer","x":2,"y":0}]}', "不可通行"],
		["overlap.json", '{"rows": ["....", "...."], "playerUnits": [{"class":"swordsman","x":1,"y":1}], "enemyUnits": [{"class":"archer","x":1,"y":1}]}', "重叠"],
		["no_terrain.json", '{"playerUnits": [{"class":"swordsman","x":0,"y":0}], "enemyUnits": [{"class":"archer","x":1,"y":0}]}', "地形"],
		["empty_units.json", '{"rows": ["..."], "playerUnits": [], "enemyUnits": [{"class":"archer","x":1,"y":0}]}', "playerUnits"],
		["bad_layout_version.json", '{"rows":["..",".."],"playerUnits":[{"class":"swordsman","x":0,"y":0}],"enemyUnits":[{"class":"archer","x":1,"y":1}],"block_layout":{"version":2,"default_z":0,"cells":[]}}', "version"],
		["bad_layout_range.json", '{"rows":["..",".."],"playerUnits":[{"class":"swordsman","x":0,"y":0}],"enemyUnits":[{"class":"archer","x":1,"y":1}],"block_layout":{"version":1,"default_z":0,"cells":[{"x":0,"y":0,"z":17}]}}', "0..16"],
		["bad_layout_duplicate.json", '{"rows":["..",".."],"playerUnits":[{"class":"swordsman","x":0,"y":0}],"enemyUnits":[{"class":"archer","x":1,"y":1}],"block_layout":{"version":1,"default_z":0,"cells":[{"x":0,"y":0},{"x":0,"y":0}]}}', "重复"],
		["bad_layout_type.json", '{"rows":["..",".."],"playerUnits":[{"class":"swordsman","x":0,"y":0}],"enemyUnits":[{"class":"archer","x":1,"y":1}],"block_layout":{"version":1,"default_z":0,"cells":[{"x":0,"y":0,"z":1.5}]}}', "整数"],
		["bad_layout_oob.json", '{"rows":["..",".."],"playerUnits":[{"class":"swordsman","x":0,"y":0}],"enemyUnits":[{"class":"archer","x":1,"y":1}],"block_layout":{"version":1,"default_z":0,"cells":[{"x":2,"y":0,"z":1}]}}', "越界"],
	]
	for c in cases:
		var path := _write_tmp(String(c[0]), String(c[1]))
		var res := BattlefieldLoaderScript.load_battlefield(path)
		_expect(not bool(res.get("ok", true)), "坏文件 %s 应该加载失败但成功了" % c[0])
		var err := String(res.get("error", ""))
		_expect(err.find(String(c[2])) != -1, "错误信息没提到 '%s'：%s" % [c[2], err])
	# map 写法：行字符串（空格分隔）也应可用（正向用例）
	var ok_path := _write_tmp("map_string_rows.json",
		'{"map": ["plain forest", "water plain"], "playerUnits": [{"class":"swordsman","x":0,"y":0}], "enemyUnits": [{"class":"archer","x":1,"y":1}]}')
	var ok_res := BattlefieldLoaderScript.load_battlefield(ok_path)
	_expect(bool(ok_res.get("ok", false)), "map 字符串行写法加载失败: %s" % ok_res.get("error", ""))
	if bool(ok_res.get("ok", false)):
		var ch: Dictionary = ok_res["chapter"]
		_expect(int(ch["width"]) == 2 and int(ch["height"]) == 2, "map 字符串行尺寸错误")
		_expect(not ch.has("block_layout"), "旧 JSON 缺布局时不注入，继续走旧柱逻辑")


func _write_tmp(file_name: String, content: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var path := TMP_DIR + "/" + file_name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f.close()
	return path
