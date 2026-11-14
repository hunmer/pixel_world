## user_asset_catalog_contract.gd — UserAssetCatalog 契约测试（纯数据 + 持久化，无网络）
##
## 覆盖：描述符构建/校验各分支、库解析拒绝分支、原子保存 round-trip、
## .bak 回退、损坏主文件恢复、保存失败保留旧库、float→int 归一化。
## 运行：godot --headless --path . --script res://tests/user_asset_catalog_contract.gd

extends SceneTree

const Catalog := preload("res://scripts/assets/user_asset_catalog.gd")

const TMP_DIR := "user://user_asset_catalog_tmp"
const LIB_PATH := TMP_DIR + "/library.json"

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_prepare_tmp()
	_test_descriptor_defaults()
	_test_validate_ok()
	_test_validate_rejects()
	_test_parse_library()
	_test_save_load_roundtrip()
	_test_backup_fallback()
	_test_save_failure_keeps_old()
	_cleanup_tmp()
	if failures.is_empty():
		print("USER_ASSET_CATALOG_CONTRACT_OK (%d checks)" % checks)
		quit(0)
	else:
		for f in failures:
			print("FAIL: " + f)
		print("USER_ASSET_CATALOG_CONTRACT_FAILED (%d failures / %d checks)" % [failures.size(), checks])
		quit(1)


func _expect(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures.append(what)


func _prepare_tmp() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	# 清掉上次残留，保证测试从干净状态开始
	DirAccess.remove_absolute(LIB_PATH)
	DirAccess.remove_absolute(LIB_PATH + Catalog.BACKUP_SUFFIX)
	DirAccess.remove_absolute(LIB_PATH + Catalog.TEMP_SUFFIX)


func _cleanup_tmp() -> void:
	_remove_recursive(TMP_DIR)


func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var names: Array[String] = []
	var n := dir.get_next()
	while n != "":
		if n != "." and n != "..":
			names.append(n)
		n = dir.get_next()
	dir.list_dir_end()
	for name in names:
		var full := path + "/" + name
		if dir.dir_exists(name):
			_remove_recursive(full)
		else:
			dir.remove(name)
	DirAccess.remove_absolute(path)


func _valid_sha() -> String:
	## 64 位小写 hex 占位
	return "a1b2c3d4e5f60718293a4b5c6d7e8f990102030405060708090a0b0c0d0e0f10"


func _good_descriptor() -> Dictionary:
	return Catalog.make_descriptor("basic_0", Catalog.KIND_TERRAIN, "basic_0.png",
		["basic"], "basic_0.png", _valid_sha(), 1024, 174, 206, {})


## ---------------------------------------------------------------- 默认值与构建


func _test_descriptor_defaults() -> void:
	var dr := Catalog.default_render()
	_expect(dr["mode"] == Catalog.RENDER_MODE_FULL, "default_render.mode == full")
	_expect(dr["crop"] == null, "default_render.crop == null")
	_expect(absf(float(dr["pivot"]["x"]) - 0.5) < 0.0001, "default_render.pivot.x == 0.5")
	_expect(absf(float(dr["pivot"]["y"]) - 1.0) < 0.0001, "default_render.pivot.y == 1.0")
	_expect(absf(float(dr["scale"]) - 1.0) < 0.0001, "default_render.scale == 1.0")
	_expect(int(dr["footprint"]["w"]) == 1 and int(dr["footprint"]["h"]) == 1, "default_render.footprint 1x1")

	var d := Catalog.make_descriptor("grassland_1", Catalog.KIND_PLANT, "草地",
		["grassland"], "grassland_1.png", "", 0, 0, 0, {})
	_expect(d["kind"] == Catalog.KIND_PLANT, "make_descriptor.kind")
	_expect(d["name"] == "草地", "make_descriptor.name 中文显示名")
	_expect(typeof(d["width"]) == TYPE_INT, "make_descriptor.width 为 int（非 float）")
	_expect(d["render"]["mode"] == Catalog.RENDER_MODE_FULL, "make_descriptor.render 补默认")


## ---------------------------------------------------------------- 校验通过分支


func _test_validate_ok() -> void:
	var d := _good_descriptor()
	_expect(Catalog.validate_descriptor(d, "ok-full", Catalog.MAX_IMAGE_BYTES).is_empty(),
		"完整合法描述符应通过")

	# 元数据先行：sha 空 / bytes 0 / wh 0 合法（代表未知，待下载回填）
	var meta := d.duplicate(true)
	meta["sha256"] = ""
	meta["bytes"] = 0
	meta["width"] = 0
	meta["height"] = 0
	_expect(Catalog.validate_descriptor(meta, "ok-meta", Catalog.MAX_IMAGE_BYTES).is_empty(),
		"元数据先行（sha/bytes/wh 全空）应通过")

	# crop 模式合法分支
	var cropped := d.duplicate(true)
	cropped["render"] = {"mode": Catalog.RENDER_MODE_CROP,
		"crop": {"x": 1, "y": 2, "w": 100, "h": 200},
		"pivot": {"x": 0.5, "y": 0.5}, "scale": 2.0,
		"footprint": {"w": 2, "h": 3}}
	_expect(Catalog.validate_descriptor(cropped, "ok-crop", Catalog.MAX_IMAGE_BYTES).is_empty(),
		"crop 模式合法描述符应通过")

	# 部分元数据未知 + 已知 sha：允许（网络清单常见：有 sha 无尺寸）
	var partial := d.duplicate(true)
	partial["width"] = 0
	partial["height"] = 0
	_expect(Catalog.validate_descriptor(partial, "ok-partial", Catalog.MAX_IMAGE_BYTES).is_empty(),
		"sha 已知 + 尺寸未知应通过")


## ---------------------------------------------------------------- 校验拒绝分支


func _reject_case(mut: Callable, why: String) -> void:
	var d := _good_descriptor().duplicate(true)
	mut.call(d)
	var errs := Catalog.validate_descriptor(d, "reject", Catalog.MAX_IMAGE_BYTES)
	_expect(not errs.is_empty(), why)


func _test_validate_rejects() -> void:
	_reject_case(func(d: Dictionary) -> void: d["id"] = "", "id 为空必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["id"] = "Basic_0", "id 含大写必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["id"] = "-basic", "id 首字符 - 必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["id"] = "ba/../../x", "id 含 / 必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["kind"] = "tree", "kind 非白名单必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["name"] = "", "name 为空必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["tags"] = "basic", "tags 非数组必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["tags"] = ["ok", 3], "tags 含非字符串必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["image"] = "", "image 为空必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["sha256"] = _valid_sha().to_upper(),
		"sha256 大写必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["sha256"] = _valid_sha().substr(1),
		"sha256 长度 63 必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["sha256"] = "z" + _valid_sha().substr(1),
		"sha256 非 hex 字符必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["bytes"] = -1, "bytes 为负必须拒绝")
	var inconsistent := func(d: Dictionary) -> void:
		d["width"] = 0
		d["height"] = 4
	_reject_case(inconsistent, "width/height 不一致必须拒绝")
	var too_wide := func(d: Dictionary) -> void:
		d["width"] = Catalog.MAX_SIDE_PIXELS + 1
		d["height"] = 4
	_reject_case(too_wide, "width 超像素上限必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["render"] = "full", "render 非对象必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["render"] = {"mode": "sprite"},
		"render.mode 非白名单必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["render"] = {"mode": "full",
		"crop": {"x": 0, "y": 0, "w": 1, "h": 1}}, "full 模式带 crop 必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["render"] = {"mode": "crop", "crop": null},
		"crop 模式缺 crop 必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["render"] = {"mode": "crop",
		"crop": {"x": 0, "y": 0, "w": 0, "h": 4}}, "crop.w=0 必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["render"] = {"mode": "crop",
		"crop": {"x": 2, "y": 0, "w": 4, "h": 4}}, "crop 超出图像边界必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["render"] = {"mode": "full",
		"pivot": {"x": 1.5, "y": 1.0}}, "pivot.x 超界必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["render"] = {"mode": "full", "scale": 0.0},
		"scale=0 必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["render"] = {"mode": "full",
		"footprint": {"w": 0, "h": 1}}, "footprint.w=0 必须拒绝")
	_reject_case(func(d: Dictionary) -> void: d["render"] = {"mode": "full",
		"footprint": {"w": 9, "h": 1}}, "footprint.w=9 必须拒绝")

	# bytes 上限参数收紧生效
	var d := _good_descriptor()
	d["bytes"] = 200
	_expect(not Catalog.validate_descriptor(d, "reject", 100).is_empty(),
		"bytes 超自定义上限必须拒绝")
	_expect(Catalog.validate_descriptor(d, "reject", 200).is_empty(),
		"bytes 恰等于自定义上限应通过")


## ---------------------------------------------------------------- 库文本解析


func _test_parse_library() -> void:
	# 合法文本：JSON 里数字是 float 形态（Godot JSON.parse 全 float），须归一回 int
	var entry := _good_descriptor().duplicate(true)
	var lib := {"version": 1, "updated_ms": 123456,
		"settings": {"source_url": "http://127.0.0.1:8076/blocks.json"},
		"assets": [entry]}
	var text := JSON.stringify(lib)
	var parsed := Catalog.parse_library_text(text)
	_expect(parsed["ok"], "合法库文本应解析通过")
	if parsed["ok"]:
		var assets: Array = parsed["library"]["assets"]
		_expect(assets.size() == 1, "解析后资产数 == 1")
		_expect(typeof(assets[0]["width"]) == TYPE_INT, "width 应从 float 归一为 int")
		_expect(typeof(assets[0]["bytes"]) == TYPE_INT, "bytes 应从 float 归一为 int")
		_expect(parsed["library"]["settings"]["source_url"] == "http://127.0.0.1:8076/blocks.json",
			"settings.source_url 应保留")

	# 拒绝分支
	var bad_texts: Array = [
		["{ 截断", "坏 JSON 必须整体拒绝"],
		["[]", "根为数组必须拒绝"],
		[JSON.stringify({"updated_ms": 1, "assets": []}), "缺 version 必须拒绝"],
		[JSON.stringify({"version": 2, "assets": []}), "version 超前必须拒绝"],
		[JSON.stringify({"version": 1, "assets": "nope"}), "assets 非数组必须拒绝"],
		[JSON.stringify({"version": 1, "assets": [
			_good_descriptor(), _good_descriptor()]}), "重复 id 必须整体拒绝"],
		[JSON.stringify({"version": 1, "assets": [
			{"id": "x", "kind": "terrain", "name": "n", "tags": [], "image": "i"}]}),
			"条目缺必填键必须整体拒绝"],
	]
	for bad in bad_texts:
		var res := Catalog.parse_library_text(bad[0])
		_expect(not res["ok"], bad[1])


## ---------------------------------------------------------------- 保存 / 加载 round-trip


func _test_save_load_roundtrip() -> void:
	var lib := Catalog.default_library("http://127.0.0.1:8076/blocks.json")
	lib["assets"].append(_good_descriptor())
	var res := Catalog.save_library(LIB_PATH, lib)
	_expect(res["ok"], "首次保存应成功： " + str(res.get("error", "")))
	var loaded := Catalog.load_library(LIB_PATH)
	_expect(loaded["ok"], "保存后应可加载")
	_expect(not loaded["used_backup"], "主文件在时不应走 .bak")
	if loaded["ok"]:
		# save_library 会刷新 updated_ms（保存即更新时间戳），round-trip 只比较其余字段
		var back: Dictionary = loaded["library"]
		_expect(int(back["version"]) == int(lib["version"]), "round-trip version 一致")
		_expect(JSON.stringify(back["settings"]) == JSON.stringify(lib["settings"]),
			"round-trip settings 一致")
		_expect(JSON.stringify(back["assets"]) == JSON.stringify(lib["assets"]),
			"round-trip assets 一致")
		_expect(int(back["updated_ms"]) >= 123456, "round-trip updated_ms 被刷新且不早于原值")
		_expect(DirAccess.dir_exists_absolute(TMP_DIR + "/blobs") == false,
			"库保存不应产生 blobs 目录")

	# 二次保存：旧内容进 .bak，主文件是新内容
	var ms_before := int(lib["updated_ms"])
	lib["updated_ms"] = Catalog.now_ms() + 1000
	lib["assets"].append(Catalog.make_descriptor("grassland_1", Catalog.KIND_PLANT,
		"g1", ["grassland"], "grassland_1.png", "", 0, 0, 0, {}))
	res = Catalog.save_library(LIB_PATH, lib)
	_expect(res["ok"], "二次保存应成功")
	var loaded2 := Catalog.load_library(LIB_PATH)
	_expect(loaded2["ok"] and loaded2["library"]["assets"].size() == 2,
		"二次保存后主文件应有 2 条资产")
	var bak_text := FileAccess.get_file_as_string(LIB_PATH + Catalog.BACKUP_SUFFIX)
	_expect(bak_text != "", "二次保存后 .bak 应存在且非空")
	var bak_lib := Catalog.parse_library_text(bak_text)
	_expect(bak_lib["ok"] and bak_lib["library"]["assets"].size() == 1,
		".bak 内容应为旧库（1 条资产）")

	# 库无 assets 键时 load 报告明确错误
	var missing := Catalog.load_library("user://user_asset_catalog_tmp/not_exist.json")
	_expect(not missing["ok"], "加载不存在的库应失败")


## ---------------------------------------------------------------- .bak 回退


func _test_backup_fallback() -> void:
	# 保留 .bak（上一轮的旧库：1 条资产），把主文件写坏
	var bak_text := FileAccess.get_file_as_string(LIB_PATH + Catalog.BACKUP_SUFFIX)
	var f := FileAccess.open(LIB_PATH, FileAccess.WRITE)
	f.store_string("{ 截断的坏 JSON")
	f.close()
	var loaded := Catalog.load_library(LIB_PATH)
	_expect(loaded["ok"], "主文件损坏时应回退 .bak 成功")
	_expect(loaded["used_backup"], "主文件损坏时 used_backup 应为 true")
	if loaded["ok"]:
		_expect(loaded["library"]["assets"].size() == 1, ".bak 回退应拿到旧库 1 条资产")

	# 主文件与 .bak 都坏 → 明确失败
	var f2 := FileAccess.open(LIB_PATH + Catalog.BACKUP_SUFFIX, FileAccess.WRITE)
	f2.store_string("also broken")
	f2.close()
	var both_bad := Catalog.load_library(LIB_PATH)
	_expect(not both_bad["ok"], "主与 .bak 都坏时必须明确失败")


## ---------------------------------------------------------------- 保存失败保留旧库


func _test_save_failure_keeps_old() -> void:
	# 恢复一个有效主库
	var lib := Catalog.default_library("http://127.0.0.1:8076/blocks.json")
	lib["assets"].append(_good_descriptor())
	Catalog.save_library(LIB_PATH, lib)
	var good_text := FileAccess.get_file_as_string(LIB_PATH)

	# 塞非法描述符 → save_library 必须拒绝且不动主文件
	var bad_lib := lib.duplicate(true)
	bad_lib["assets"].append({"id": "BAD", "kind": "terrain"})
	var res := Catalog.save_library(LIB_PATH, bad_lib)
	_expect(not res["ok"], "含非法描述符的库保存必须失败")
	var after := FileAccess.get_file_as_string(LIB_PATH)
	_expect(after == good_text, "保存失败必须保留原主文件内容")
	# 失败后不应留下 tmp 残留
	_expect(not FileAccess.file_exists(LIB_PATH + Catalog.TEMP_SUFFIX),
		"保存失败后不应残留 .tmp")
