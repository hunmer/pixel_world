extends SceneTree

## tests/building_layout_contract.gd — 建筑数据契约测试
## 运行：godot --headless --path . --script res://tests/building_layout_contract.gd
## 覆盖：BuildingLayout 占用派生与校验 / GridSystem 建筑阻挡 /
##       loader buildings 文档校验（真实磁盘 JSON 往返，float 整值兼容）/
##       save codec buildings roundtrip / catalog building kind 描述符校验与旧素材兼容。

const BuildingLayoutScript = preload("res://scripts/core/building_layout.gd")
const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const BattleSaveCodecScript = preload("res://scripts/core/battle_save_codec.gd")
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const UserAssetCatalogScript = preload("res://scripts/assets/user_asset_catalog.gd")

const TMP_DIR := "user://building_layout_contract_tmp"

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_as_json_int()
	_test_footprint_and_cells()
	_test_validate_entries()
	_test_grid_blocking()
	_test_loader_roundtrip()
	_test_loader_error_cases()
	_test_save_codec_roundtrip()
	_test_catalog_building()
	# 清理临时目录
	var dir := DirAccess.open(TMP_DIR)
	if dir != null:
		for f in ["ok_building.json", "float_rotation.json", "bad_rotation_frac.json",
				"building_on_unit.json", "building_overlap.json", "building_oob.json",
				"missing_asset.json"]:
			if dir.file_exists(f):
				dir.remove(f)
		var err := dir.change_dir("..")
		if err == OK:
			dir.remove(TMP_DIR.get_file())
	if failures.is_empty():
		print("BUILDING_LAYOUT_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


## 测试素材快照：BuildingLayout 只读 render.footprint
static func _asset(id: String, w: int, h: int) -> Dictionary:
	return {
		"id": id,
		"kind": "building",
		"render": {"footprint": {"w": w, "h": h}},
	}


static func _entry(instance_id: String, asset_id: String, x: int, y: int, rotation: int = 0) -> Dictionary:
	return {
		"instance_id": instance_id,
		"asset_id": asset_id,
		"x": x,
		"y": y,
		"rotation": rotation,
	}


# ---------------------------------------------------------------------------
# 1) as_json_int：int 直返 / 整值 float 转 int / 非整值与非法类型返 null
# ---------------------------------------------------------------------------
func _test_as_json_int() -> void:
	_expect(int(BuildingLayoutScript.as_json_int(3)) == 3 and typeof(BuildingLayoutScript.as_json_int(3)) == TYPE_INT,
		"as_json_int(3) 应返回 int 3")
	_expect(int(BuildingLayoutScript.as_json_int(3.0)) == 3 and typeof(BuildingLayoutScript.as_json_int(3.0)) == TYPE_INT,
		"as_json_int(3.0) 应返回 int 3（JSON 整值 float 兼容）")
	_expect(BuildingLayoutScript.as_json_int(1.5) == null, "as_json_int(1.5) 应返回 null")
	_expect(BuildingLayoutScript.as_json_int("2") == null, "as_json_int(\"2\") 应返回 null")
	_expect(BuildingLayoutScript.as_json_int(null) == null, "as_json_int(null) 应返回 null")
	_expect(BuildingLayoutScript.as_json_int(NAN) == null, "as_json_int(NAN) 应返回 null")


# ---------------------------------------------------------------------------
# 2) footprint / occupied_cells / occupancy
# ---------------------------------------------------------------------------
func _test_footprint_and_cells() -> void:
	var assets := {
		"wall_a": _asset("wall_a", 2, 3),
		"missing": _asset("missing", 2, 2),
	}
	# 基础矩形（rotation 0）
	var size0: Vector2i = BuildingLayoutScript.footprint_size(_entry("b1", "wall_a", 0, 0, 0), assets)
	_expect(size0 == Vector2i(2, 3), "footprint_size rotation=0 应为 2x3，实际 %s" % size0)
	# 奇数 rotation 交换 w/h
	var size1: Vector2i = BuildingLayoutScript.footprint_size(_entry("b1", "wall_a", 0, 0, 1), assets)
	_expect(size1 == Vector2i(3, 2), "footprint_size rotation=1 应交换为 3x2，实际 %s" % size1)
	var size3: Vector2i = BuildingLayoutScript.footprint_size(_entry("b1", "wall_a", 0, 0, 3), assets)
	_expect(size3 == Vector2i(3, 2), "footprint_size rotation=3 应交换为 3x2，实际 %s" % size3)
	# 缺素材回退 1x1（引用不丢，不中断）
	var size_miss: Vector2i = BuildingLayoutScript.footprint_size(_entry("b2", "ghost", 0, 0), assets)
	_expect(size_miss == Vector2i(1, 1), "缺素材应回退 1x1，实际 %s" % size_miss)
	# occupied_cells 展开：2x3 于 (1,1) → 6 格
	var cells: Array[Vector2i] = BuildingLayoutScript.occupied_cells(_entry("b3", "wall_a", 1, 1, 0), assets)
	_expect(cells.size() == 6, "occupied_cells 2x3 应展开 6 格，实际 %d" % cells.size())
	var expect_set := {"1,1": true, "2,1": true, "1,2": true, "2,2": true, "1,3": true, "2,3": true}
	for c in cells:
		expect_set.erase(BuildingLayoutScript.cell_key(c.x, c.y))
	_expect(expect_set.is_empty(), "occupied_cells 展开格子集合不符")
	# rotation=1（3x2）于 (0,0) → 覆盖 x:0..2, y:0..1
	var cells_r1: Array[Vector2i] = BuildingLayoutScript.occupied_cells(_entry("b4", "wall_a", 0, 0, 1), assets)
	_expect(cells_r1.size() == 6, "rotation=1 应展开 6 格，实际 %d" % cells_r1.size())
	var has_2_0 := false
	var has_0_1 := false
	for c in cells_r1:
		if c == Vector2i(2, 0):
			has_2_0 = true
		if c == Vector2i(0, 1):
			has_0_1 = true
	_expect(has_2_0 and has_0_1, "rotation=1 占用应为宽 3 高 2（含 (2,0) 与 (0,1)）")
	# occupancy 字符串 key -> instance_id
	var occ: Dictionary = BuildingLayoutScript.occupancy(
		[_entry("keep", "wall_a", 0, 0, 0)], assets)
	_expect(String(occ.get("0,0", "")) == "keep" and String(occ.get("1,2", "")) == "keep",
		"occupancy 应映射 \"x,y\"->instance_id")
	_expect(not occ.has("2,0"), "2x3 于 (0,0) 不应占用 (2,0)")


# ---------------------------------------------------------------------------
# 3) validate_entries：全部错误分支 + 两种 occupied key 兼容
# ---------------------------------------------------------------------------
func _test_validate_entries() -> void:
	var assets := {"wall_a": _asset("wall_a", 2, 2), "wall_b": _asset("wall_b", 2, 2)}
	var w := 10
	var h := 10
	# 合法：两个不重叠建筑
	var ok_err: String = BuildingLayoutScript.validate_entries(
		[_entry("a1", "wall_a", 0, 0), _entry("a2", "wall_b", 5, 5)], w, h, assets, {})
	_expect(ok_err.is_empty(), "合法双建筑不应报错，实际: %s" % ok_err)
	# instance_id 空
	var e: String = BuildingLayoutScript.validate_entries([_entry("", "wall_a", 0, 0)], w, h, assets, {})
	_expect(not e.is_empty(), "空 instance_id 应报错")
	# instance_id 重复
	e = BuildingLayoutScript.validate_entries(
		[_entry("dup", "wall_a", 0, 0), _entry("dup", "wall_b", 5, 5)], w, h, assets, {})
	_expect(not e.is_empty(), "重复 instance_id 应报错")
	# asset_id 空
	e = BuildingLayoutScript.validate_entries([_entry("a1", "", 0, 0)], w, h, assets, {})
	_expect(not e.is_empty(), "空 asset_id 应报错")
	# rotation 越界 / 非整数
	e = BuildingLayoutScript.validate_entries([_entry("a1", "wall_a", 0, 0, 4)], w, h, assets, {})
	_expect(not e.is_empty(), "rotation=4 应报错")
	e = BuildingLayoutScript.validate_entries(
		[_entry("a1", "wall_a", 0, 0, 0).duplicate(true)], w, h, assets, {})
	_expect(not e.is_empty() == false, "rotation 缺省应为 0 合法")
	var frac_entry := _entry("a1", "wall_a", 0, 0, 0)
	frac_entry["rotation"] = 1.5
	e = BuildingLayoutScript.validate_entries([frac_entry], w, h, assets, {})
	_expect(not e.is_empty(), "rotation=1.5 应报错（JSON 非整值 float 拒绝）")
	# 整值 float 接受
	var float_entry := _entry("a1", "wall_a", 1, 1, 0)
	float_entry["rotation"] = 2.0
	float_entry["x"] = 2.0
	e = BuildingLayoutScript.validate_entries([float_entry], w, h, assets, {})
	_expect(e.is_empty(), "整值 float（rotation 2.0 / x 2.0）应接受，实际: %s" % e)
	# 越界
	e = BuildingLayoutScript.validate_entries([_entry("a1", "wall_a", 9, 9)], w, h, assets, {})
	_expect(not e.is_empty(), "占用越界（2x2 于 9,9 超 10x10）应报错")
	# 建筑间重叠
	e = BuildingLayoutScript.validate_entries(
		[_entry("a1", "wall_a", 0, 0), _entry("a2", "wall_b", 1, 1)], w, h, assets, {})
	_expect(not e.is_empty(), "建筑重叠（2x2 于 0,0 与 1,1）应报错")
	# 与既有占用冲突：Vector2i key（loader 链路）
	e = BuildingLayoutScript.validate_entries(
		[_entry("a1", "wall_a", 0, 0)], w, h, assets, {Vector2i(1, 1): true})
	_expect(not e.is_empty(), "与 Vector2i key 单位占用冲突应报错")
	# 与既有占用冲突："x,y" 字符串 key（save codec 链路）
	e = BuildingLayoutScript.validate_entries(
		[_entry("a1", "wall_a", 0, 0)], w, h, assets, {"1,1": true})
	_expect(not e.is_empty(), "与 \"x,y\" 字符串 key 单位占用冲突应报错")
	# 缺素材：回退 1x1 不报错（引用不丢）
	e = BuildingLayoutScript.validate_entries([_entry("a1", "ghost", 0, 0)], w, h, assets, {})
	_expect(e.is_empty(), "缺素材回退 1x1 后应通过校验，实际: %s" % e)


# ---------------------------------------------------------------------------
# 4) GridSystem：阻挡语义（移动/寻路挡，攻击射程不挡，place_unit 拒绝）
# ---------------------------------------------------------------------------
func _test_grid_blocking() -> void:
	var size := 5
	var terrain: Array = []
	for y in range(size):
		var row: Array = []
		for x in range(size):
			row.append(&"plain")
		terrain.append(row)
	var grid: GridSystem = GridSystemScript.new(size, size, terrain)
	var assets := {"wall_a": _asset("wall_a", 1, 2)}
	grid.apply_buildings([_entry("wall", "wall_a", 2, 1)], assets)
	# 占用 (2,1) 与 (2,2)
	_expect(grid.is_building_cell(2, 1) and grid.is_building_cell(2, 2),
		"apply_buildings 后 (2,1)/(2,2) 应为建筑格")
	_expect(not grid.is_building_cell(0, 0), "(0,0) 不应是建筑格")
	_expect(grid.can_stand(0, 0) and not grid.can_stand(2, 1),
		"can_stand：空地 true / 建筑格 false")
	# 替换语义：二次调用不残留
	grid.apply_buildings([], assets)
	_expect(not grid.is_building_cell(2, 1), "apply_buildings([]) 应清空占用（替换语义）")
	grid.apply_buildings([_entry("wall", "wall_a", 2, 1)], assets)
	# 单位（移动范围避开建筑）
	var unit := {
		&"id": &"u_test",
		&"faction": &"player",
		&"moveType": &"foot",
		&"position": Vector2i(0, 1),
		&"stats": {&"mov": 5},
		&"attackRange": [1, 1],
	}
	grid.place_unit(unit, 0, 1)
	var move_range: Dictionary = grid.compute_move_range(0, 1, &"foot", 5, &"player")
	_expect(not move_range.has("2,1") and not move_range.has("2,2"),
		"移动范围应排除建筑格 (2,1)/(2,2)")
	_expect(move_range.has("3,0"), "绕行后 (3,0) 仍可达（建筑只挡不封路）")
	# A* 不穿过建筑格
	var path: Array = grid.find_path(Vector2i(0, 1), Vector2i(4, 1), &"foot", 99)
	var path_clean := true
	for p in path:
		if grid.is_building_cell((p as Vector2i).x, (p as Vector2i).y):
			path_clean = false
	_expect(path.size() > 0 and path_clean, "A* 路径应绕开建筑格")
	# 攻击射程不受建筑阻挡（原地 BFS 只查界内）
	var atk: Dictionary = grid.compute_attack_range(1, 1, unit)
	var tiles: Dictionary = atk[&"attackTiles"]
	_expect(tiles.has("2,1"), "攻击射程应覆盖建筑格 (2,1)（建筑不挡攻击）")
	# place_unit 落建筑格被拒（单位留在原地）
	grid.place_unit(unit, 2, 2)
	_expect((unit[&"position"] as Vector2i) == Vector2i(0, 1),
		"place_unit 到建筑格应被拒绝，单位留在原地")
	_expect(grid.unit_at(2, 2).is_empty(), "被拒绝后建筑格不应注册单位")


# ---------------------------------------------------------------------------
# 5) loader 磁盘 JSON 真实往返：合法文档 → chapter.buildings 归一化
# ---------------------------------------------------------------------------
func _test_loader_roundtrip() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var doc := {
		"id": "ok_building",
		"name": "建筑往返测试",
		"rows": [
			"......",
			"......",
			"......",
			"......",
			"......",
			"......",
		],
		"playerUnits": [
			{"class": "swordsman", "name": "罗兰", "level": 3, "x": 0, "y": 0},
		],
		"enemyUnits": [
			{"class": "berserker", "name": "血斧", "level": 3, "x": 5, "y": 5},
		],
		"buildings": [
			{"instance_id": "keep_main", "asset_id": "wall_a", "x": 2, "y": 2, "rotation": 1},
		],
		"user_assets": {
			"wall_a": _asset("wall_a", 2, 2),
		},
	}
	# 真实磁盘往返：stringify → 磁盘 → parse（数字全部变 float）
	var path := TMP_DIR + "/ok_building.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	var res: Dictionary = BattlefieldLoaderScript.load_battlefield(path)
	_expect(bool(res.get("ok", false)), "合法建筑文档应加载成功，实际: %s" % str(res.get("error", "")))
	var chapter_rt: Dictionary = res.get("chapter", {})
	var buildings: Variant = chapter_rt.get("buildings", [])
	_expect(buildings is Array and (buildings as Array).size() == 1, "chapter 应含 1 条建筑")
	if buildings is Array and (buildings as Array).size() == 1:
		var b: Dictionary = (buildings as Array)[0]
		_expect(String(b.get("instance_id", "")) == "keep_main", "instance_id roundtrip 失败")
		_expect(String(b.get("asset_id", "")) == "wall_a", "asset_id roundtrip 失败")
		_expect(typeof(b.get("x", null)) == TYPE_INT and int(b.get("x", -1)) == 2,
			"x 应归一化为 int 2（JSON float 2.0 → int），实际类型 %s" % str(typeof(b.get("x", null))))
		_expect(typeof(b.get("rotation", null)) == TYPE_INT and int(b.get("rotation", -1)) == 1,
			"rotation 应归一化为 int 1，实际类型 %s" % str(typeof(b.get("rotation", null))))
	# 空文档（无 buildings）不写键：旧文档兼容
	var plain_doc := doc.duplicate(true)
	plain_doc.erase("buildings")
	plain_doc.erase("user_assets")
	plain_doc["id"] = "no_buildings"
	var path2 := TMP_DIR + "/no_buildings.json"
	var f2 := FileAccess.open(path2, FileAccess.WRITE)
	f2.store_string(JSON.stringify(plain_doc, "\t"))
	f2.close()
	var res2: Dictionary = BattlefieldLoaderScript.load_battlefield(path2)
	_expect(bool(res2.get("ok", false)), "无 buildings 旧文档应正常加载")
	_expect(not (res2.get("chapter", {}) as Dictionary).has("buildings"),
		"无 buildings 时 chapter 不应写入空 buildings 键")
	# 增援落点与建筑冲突（loader occupied 链路；schema：units/positions 按索引配对）
	var doc_reinforce := doc.duplicate(true)
	doc_reinforce["reinforcements"] = [
		{"turn": 2, "units": [{"class": "archer", "level": 2}], "positions": [{"x": 2, "y": 2}]},
	]
	doc_reinforce["id"] = "reinforce_conflict"
	var path3 := TMP_DIR + "/reinforce_conflict.json"
	var f3 := FileAccess.open(path3, FileAccess.WRITE)
	f3.store_string(JSON.stringify(doc_reinforce, "\t"))
	f3.close()
	# rotation=1 → 2x2 交换仍 2x2，(2,2) 在占用内；增援落点冲突应整体拒绝
	var res3: Dictionary = BattlefieldLoaderScript.load_battlefield(path3)
	_expect(not bool(res3.get("ok", true)), "增援落点与建筑冲突应 ok:false")
	var dir := DirAccess.open(TMP_DIR)
	if dir != null:
		for extra in ["no_buildings.json", "reinforce_conflict.json"]:
			if dir.file_exists(extra):
				dir.remove(extra)


# ---------------------------------------------------------------------------
# 6) loader 错误分支：rotation 非整值 / 单位冲突 / 重叠 / 越界 / 缺素材回退
# ---------------------------------------------------------------------------
func _test_loader_error_cases() -> void:
	var base := {
		"id": "base",
		"name": "错误分支基底",
		"rows": ["......", "......", "......", "......"],
		"playerUnits": [
			{"class": "swordsman", "name": "罗兰", "level": 3, "x": 0, "y": 0},
		],
		"enemyUnits": [
			{"class": "berserker", "name": "血斧", "level": 3, "x": 5, "y": 3},
		],
		"buildings": [
			{"instance_id": "b1", "asset_id": "wall_a", "x": 2, "y": 1, "rotation": 0},
		],
		"user_assets": {"wall_a": _asset("wall_a", 2, 2)},
	}
	var cases := {
		"bad_rotation_frac": func(d: Dictionary) -> void:
			(d["buildings"] as Array)[0]["rotation"] = 1.5,
		"building_on_unit": func(d: Dictionary) -> void:
			(d["playerUnits"] as Array)[0]["x"] = 2
			(d["playerUnits"] as Array)[0]["y"] = 1,
		"building_overlap": func d_fn(d: Dictionary) -> void:
			(d["buildings"] as Array).append(
				{"instance_id": "b2", "asset_id": "wall_a", "x": 3, "y": 2, "rotation": 0}),
		"building_oob": func(d: Dictionary) -> void:
			(d["buildings"] as Array)[0]["x"] = 5,
	}
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	for file_name in cases:
		var doc: Dictionary = base.duplicate(true)
		(cases[file_name] as Callable).call(doc)
		doc["id"] = String(file_name)
		var path := TMP_DIR + "/" + String(file_name) + ".json"
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(doc, "\t"))
		f.close()
		var res: Dictionary = BattlefieldLoaderScript.load_battlefield(path)
		_expect(not bool(res.get("ok", true)),
			"错误分支 %s 应 ok:false，实际 ok=%s error=%s" % [file_name, str(res.get("ok")), str(res.get("error", ""))])
	# 缺素材：回退 1x1，文档仍加载成功（引用不丢）
	var doc_missing: Dictionary = base.duplicate(true)
	doc_missing["id"] = "missing_asset"
	doc_missing.erase("user_assets")
	var path_missing := TMP_DIR + "/missing_asset.json"
	var fm := FileAccess.open(path_missing, FileAccess.WRITE)
	fm.store_string(JSON.stringify(doc_missing, "\t"))
	fm.close()
	var res_missing: Dictionary = BattlefieldLoaderScript.load_battlefield(path_missing)
	_expect(bool(res_missing.get("ok", false)),
		"缺素材应回退 1x1 而非拒绝加载，实际: %s" % str(res_missing.get("error", "")))


# ---------------------------------------------------------------------------
# 7) save codec：capture/encode/decode roundtrip 后 validate_chapter 通过；
#    buildings 与单位冲突在 validate_chapter 被拒
# ---------------------------------------------------------------------------
func _test_save_codec_roundtrip() -> void:
	var doc := {
		"id": "codec_case",
		"name": "codec 建筑往返",
		"rows": ["......", "......", "......", "......"],
		"playerUnits": [
			{"class": "swordsman", "name": "罗兰", "level": 3, "x": 0, "y": 0},
		],
		"enemyUnits": [
			{"class": "berserker", "name": "血斧", "level": 3, "x": 5, "y": 3},
		],
		"buildings": [
			{"instance_id": "keep_main", "asset_id": "wall_a", "x": 2, "y": 1, "rotation": 1},
		],
		"user_assets": {"wall_a": _asset("wall_a", 2, 2)},
	}
	var res: Dictionary = BattlefieldLoaderScript.load_battlefield_inline(doc)
	_expect(bool(res.get("ok", false)), "inline 文档应加载成功: %s" % str(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var chapter: Dictionary = (res["chapter"] as Dictionary).duplicate(true)
	# validate_chapter 直接通过
	var err: String = BattleSaveCodecScript.validate_chapter(chapter)
	_expect(err.is_empty(), "loader 出的 chapter 应通过 validate_chapter，实际: %s" % err)
	# encode → decode 通用递归 roundtrip 后仍通过（buildings 纯 JSON 无损）
	var encoded: Variant = BattleSaveCodecScript.encode(chapter)
	var decoded: Variant = BattleSaveCodecScript.decode(encoded)
	_expect(decoded is Dictionary, "decode 应返回 Dictionary")
	if decoded is Dictionary:
		var err2: String = BattleSaveCodecScript.validate_chapter(decoded as Dictionary)
		_expect(err2.is_empty(), "roundtrip 后 validate_chapter 应通过，实际: %s" % err2)
		var rt_buildings: Variant = (decoded as Dictionary).get("buildings", [])
		_expect(rt_buildings is Array and (rt_buildings as Array).size() == 1,
			"roundtrip 后 buildings 应保留 1 条")
	# 冲突分支：把单位挪进建筑占用（validate_chapter 的 occupied 是 "x,y" 字符串 key）
	var bad: Dictionary = chapter.duplicate(true)
	var pu: Array = bad["playerUnits"]
	(pu[0] as Dictionary)[&"position"] = Vector2i(3, 2)
	var err3: String = BattleSaveCodecScript.validate_chapter(bad)
	_expect(not err3.is_empty(), "单位挪进建筑占用后 validate_chapter 应报错")


# ---------------------------------------------------------------------------
# 8) catalog building kind：新字段校验分支 + 旧 kind 旧 render 兼容
# ---------------------------------------------------------------------------
static func _descriptor(id: String, kind: String, render: Dictionary) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"name": "测试素材",
		"tags": ["test"],
		"image": "test.png",
		"sha256": "",
		"bytes": 100,
		"width": 64,
		"height": 64,
		"render": render,
	}


func _test_catalog_building() -> void:
	# building kind + 合法新字段（front_back + back_asset_id + ground_width_px）
	var good := _descriptor("bld_a", "building", (UserAssetCatalogScript.default_render().duplicate(true) as Dictionary).merged({
		"footprint": {"w": 2, "h": 2},
		"back_mode": "front_back",
		"back_asset_id": "bld_b",
		"ground_width_px": 1150.0,
	}, true))
	var errs: Array[String] = UserAssetCatalogScript.validate_descriptor(good, "test")
	_expect(errs.is_empty(), "合法 building 描述符不应报错，实际: %s" % ", ".join(errs))
	# single + 残留 back_asset_id → 不报错（自愈语义：加载/更新路径强制清空）
	var single_with_back := good.duplicate(true)
	(single_with_back["render"] as Dictionary)["back_mode"] = "single"
	errs = UserAssetCatalogScript.validate_descriptor(single_with_back, "test")
	_expect(errs.is_empty(), "single 携带残留 back_asset_id 应自愈放行（不报错），实际: %s" % ", ".join(errs))
	# normalize 强制清空：single 时 back_asset_id 归一化为空串
	var normalized: Dictionary = UserAssetCatalogScript._normalize_descriptor(single_with_back)
	_expect(String((normalized["render"] as Dictionary).get("back_asset_id", "?")) == "",
		"normalize 应强制清空 single 的 back_asset_id")
	# parse_library_text 全链路自愈：库文件含 single+残留 id → 加载成功且清空
	var lib_text := JSON.stringify({
		"version": UserAssetCatalogScript.SCHEMA_VERSION,
		"settings": {"source_url": ""},
		"assets": [single_with_back],
	})
	var lib_res: Dictionary = UserAssetCatalogScript.parse_library_text(lib_text)
	_expect(bool(lib_res.get("ok", false)), "含 single+残留 back_asset_id 的库应加载成功: %s" % str(lib_res.get("errors", [])))
	if bool(lib_res.get("ok", false)):
		var lib_assets: Array = (lib_res["library"] as Dictionary).get("assets", [])
		_expect(lib_assets.size() == 1, "库应保留 1 条素材")
		if lib_assets.size() == 1:
			var healed: Dictionary = (lib_assets[0] as Dictionary).get("render", {})
			_expect(String(healed.get("back_asset_id", "?")) == "",
				"库加载归一化后 single 的 back_asset_id 应为空串")
	# front_back 缺 back_asset_id → 拒绝
	var front_no_back := good.duplicate(true)
	(front_no_back["render"] as Dictionary)["back_asset_id"] = ""
	errs = UserAssetCatalogScript.validate_descriptor(front_no_back, "test")
	_expect(not errs.is_empty(), "front_back 缺 back_asset_id 应报错")
	# back_mode 非法枚举 → 拒绝
	var bad_mode := good.duplicate(true)
	(bad_mode["render"] as Dictionary)["back_mode"] = "both"
	errs = UserAssetCatalogScript.validate_descriptor(bad_mode, "test")
	_expect(not errs.is_empty(), "back_mode=both 应报错")
	# back_asset_id 非法 id → 拒绝
	var bad_back_id := good.duplicate(true)
	(bad_back_id["render"] as Dictionary)["back_asset_id"] = "UPPER!"
	errs = UserAssetCatalogScript.validate_descriptor(bad_back_id, "test")
	_expect(not errs.is_empty(), "back_asset_id 非法 id 应报错")
	# ground_width_px 负数 → 拒绝
	var neg_gw := good.duplicate(true)
	(neg_gw["render"] as Dictionary)["ground_width_px"] = -5.0
	errs = UserAssetCatalogScript.validate_descriptor(neg_gw, "test")
	_expect(not errs.is_empty(), "ground_width_px 负数应报错")
	# ground_width_px int 也接受（JSON int）
	var int_gw := good.duplicate(true)
	(int_gw["render"] as Dictionary)["ground_width_px"] = 1150
	errs = UserAssetCatalogScript.validate_descriptor(int_gw, "test")
	_expect(errs.is_empty(), "ground_width_px int 1150 应接受，实际: %s" % ", ".join(errs))
	# 旧 terrain 描述符（render 无任何新字段）仍合法
	var legacy := _descriptor("old_grass", "terrain", {
		"mode": "full",
		"crop": null,
		"pivot": {"x": 0.5, "y": 0.5},
		"scale": 1.0,
		"footprint": {"w": 1, "h": 1},
	})
	errs = UserAssetCatalogScript.validate_descriptor(legacy, "test")
	_expect(errs.is_empty(), "旧 terrain 描述符（缺省新字段）应兼容通过，实际: %s" % ", ".join(errs))
	# default_render 含新字段缺省值且合法
	var defaults := UserAssetCatalogScript.default_render()
	_expect(String(defaults.get("back_mode", "")) == "single", "default_render.back_mode 应为 single")
	_expect(String(defaults.get("back_asset_id", "?")) == "", "default_render.back_asset_id 应为空串")
	_expect(float(defaults.get("ground_width_px", -1.0)) == 0.0, "default_render.ground_width_px 应为 0.0")
	var with_default := _descriptor("bld_d", "building", defaults)
	errs = UserAssetCatalogScript.validate_descriptor(with_default, "test")
	_expect(errs.is_empty(), "default_render 构造的 building 描述符应通过，实际: %s" % ", ".join(errs))
