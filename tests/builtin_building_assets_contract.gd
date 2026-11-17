## builtin_building_assets_contract.gd — 内置石墙正背自注册契约（headless）
##
## 跑法：godot --headless --path . --script res://tests/builtin_building_assets_contract.gd
## 覆盖：首注册默认标定 / 幂等重跑零写入 / 用户标定保留 / 关联纠偏 /
##       背面清关联 / 旧 terrain 条目归位 / 名字保留 / 失败路径（null service、假导入失败）。
## 隔离：全部用 user://builtin_contract_assets/ 临时 root，测后清理。

extends SceneTree

const UserAssetServiceScript = preload("res://scripts/assets/user_asset_service.gd")
const BuiltinScript = preload("res://scripts/assets/builtin_building_assets.gd")
const CatalogScript = preload("res://scripts/assets/user_asset_catalog.gd")

const TMP_ROOT := "user://builtin_contract_assets"


func _initialize() -> void:
	call_deferred("_run")


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		push_error("[builtin_building_assets_contract] FAIL: %s" % msg)
		print("BUILTIN_BUILDING_FAIL: %s" % msg)
		quit(1)


## 建一个已就绪（_ready 已跑、库已从磁盘加载）的服务；首次时目录为空
func _make_service() -> Node:
	var svc: Node = UserAssetServiceScript.new(TMP_ROOT)
	get_root().add_child(svc)
	return svc


func _cleanup() -> void:
	var dir := DirAccess.open("user://")
	if dir.dir_exists(TMP_ROOT.replace("user://", "")):
		for f in ["library.json", "library.json.tmp", "library.json.bak"]:
			dir.remove(TMP_ROOT.replace("user://", "") + "/" + f)
		dir.remove(TMP_ROOT.replace("user://", "") + "/asset_source.cfg")
		# blobs 目录递归删
		var blobs := TMP_ROOT.replace("user://", "") + "/blobs"
		if dir.dir_exists(blobs):
			var bdir := DirAccess.open("user://" + blobs)
			if bdir != null:
				for sub in bdir.get_directories():
					var sub_dir := DirAccess.open(blobs + "/" + sub)
					if sub_dir != null:
						for blob in sub_dir.get_files():
							sub_dir.remove(blob)
					bdir.remove(sub)
			dir.remove(blobs)
		dir.remove(TMP_ROOT.replace("user://", ""))


func _run() -> void:
	# ---- 1. 首次注册：默认标定 + 正背关联 ----
	var svc: Node = _make_service()
	var res: Dictionary = BuiltinScript.ensure(svc)
	_expect(bool(res.get("ok", false)), "首次 ensure ok（实际：%s）" % JSON.stringify(res))
	var front_id := String(res.get("asset_id", ""))
	var back_id := String(res.get("back_asset_id", ""))
	_expect(not front_id.is_empty() and not back_id.is_empty() and front_id != back_id,
		"正背 id 非空且不同（front=%s back=%s）" % [front_id, back_id])
	_expect(bool(res.get("changed", false)), "首次注册 changed=true")
	var fd: Dictionary = svc.find_by_id(front_id)
	var bd: Dictionary = svc.find_by_id(back_id)
	_expect(String(fd["name"]) == "石墙", "正面默认名（实际：%s）" % String(fd["name"]))
	_expect(String(bd["name"]) == "石墙背面", "背面默认名（实际：%s）" % String(bd["name"]))
	var fr: Dictionary = fd["render"]
	var br: Dictionary = bd["render"]
	_expect(String(fd["kind"]) == "building" and String(bd["kind"]) == "building", "正背 kind=building")
	_expect(String(fr["back_mode"]) == "front_back" and String(fr["back_asset_id"]) == back_id,
		"正面 front_back 关联真实背面")
	_expect(String(br["back_mode"]) == "single" and String(br["back_asset_id"]) == "",
		"背面 single 无引用")
	_expect(int(fr["footprint"]["w"]) == 2 and int(fr["footprint"]["h"]) == 2, "footprint 2x2")
	_expect(is_equal_approx(float(fr["ground_width_px"]), 1150.0), "ground_width_px=1150")
	_expect(is_equal_approx(float(fr["pivot"]["x"]), 0.425) and is_equal_approx(float(fr["pivot"]["y"]), 0.9),
		"正面 pivot(0.425,0.9)")
	_expect(is_equal_approx(float(br["pivot"]["x"]), 0.575) and is_equal_approx(float(br["pivot"]["y"]), 0.9),
		"背面 pivot(0.575,0.9)")
	_expect(is_equal_approx(float(fr["scale"]), 1.0), "scale=1")
	_expect(bool(fd.get("saved", false)) and bool(bd.get("saved", false)), "本地导入条目 saved=true")
	# blob 已落盘（内容寻址目录存在）
	_expect(DirAccess.dir_exists_absolute(TMP_ROOT + "/blobs"), "blob 目录已建")

	# ---- 2. 幂等重跑：零写入 ----
	svc.queue_free()
	var svc2: Node = _make_service()
	var res2: Dictionary = BuiltinScript.ensure(svc2)
	_expect(bool(res2.get("ok", false)) and not bool(res2.get("changed", true)),
		"重跑 ok 且 changed=false（实际：%s）" % JSON.stringify(res2))
	_expect(String(res2["asset_id"]) == front_id and String(res2["back_asset_id"]) == back_id,
		"重跑 id 稳定（内容寻址复用）")
	_expect(svc2.asset_count() == 2, "库中仅 2 条（实际 %d）" % svc2.asset_count())

	# ---- 3. 用户标定保留 + 关联纠偏 ----
	var fd2: Dictionary = svc2.find_by_id(front_id)
	fd2["render"]["ground_width_px"] = 900.0
	fd2["render"]["pivot"] = {"x": 0.3, "y": 0.8}
	fd2["render"]["back_asset_id"] = "ghost_asset"
	fd2["name"] = "我的城墙"
	var save_res: Dictionary = svc2.save_library()
	_expect(bool(save_res["ok"]), "写用户标定")
	svc2.queue_free()
	var svc3: Node = _make_service()
	var res3: Dictionary = BuiltinScript.ensure(svc3)
	_expect(bool(res3.get("ok", false)), "纠偏 ensure ok")
	var fd3: Dictionary = svc3.find_by_id(front_id)
	_expect(String(fd3["name"]) == "我的城墙", "用户改名保留")
	_expect(is_equal_approx(float(fd3["render"]["ground_width_px"]), 900.0), "用户标定 ground_width 保留")
	_expect(is_equal_approx(float(fd3["render"]["pivot"]["x"]), 0.3), "用户标定 pivot 保留")
	_expect(String(fd3["render"]["back_asset_id"]) == String(res3["back_asset_id"]),
		"ghost 关联纠回真实背面")
	# 背面被用户加过引用 → 清回 single
	var bd3: Dictionary = svc3.find_by_id(String(res3["back_asset_id"]))
	bd3["render"]["back_mode"] = "front_back"
	bd3["render"]["back_asset_id"] = front_id
	svc3.save_library()
	svc3.queue_free()
	var svc4: Node = _make_service()
	var res4: Dictionary = BuiltinScript.ensure(svc4)
	_expect(bool(res4.get("ok", false)), "背面清关联 ensure ok")
	var bd4: Dictionary = svc4.find_by_id(String(res4["back_asset_id"]))
	_expect(String(bd4["render"]["back_mode"]) == "single" and String(bd4["render"]["back_asset_id"]) == "",
		"背面引用被清空")

	# ---- 4. 旧 terrain 导入归位（kind 修正 + 默认标定）----
	var fd4: Dictionary = svc4.find_by_id(String(res4["asset_id"]))
	fd4["kind"] = "terrain"
	fd4["render"]["ground_width_px"] = 0.0
	fd4["name"] = "旧地形导入"
	svc4.save_library()
	svc4.queue_free()
	var svc5: Node = _make_service()
	var res5: Dictionary = BuiltinScript.ensure(svc5)
	_expect(bool(res5.get("ok", false)), "归位 ensure ok")
	var fd5: Dictionary = svc5.find_by_id(String(res5["asset_id"]))
	_expect(String(fd5["kind"]) == "building", "kind 归位 building")
	_expect(is_equal_approx(float(fd5["render"]["ground_width_px"]), 1150.0), "未标定 → 默认 ground_width")
	_expect(String(fd5["name"]) == "旧地形导入", "归位不改名")
	svc5.queue_free()

	# ---- 5. 失败路径 ----
	var r_null: Dictionary = BuiltinScript.ensure(null)
	_expect(not bool(r_null.get("ok", true)) and String(r_null.get("error", "")) == "service_null",
		"null service 拒绝")
	var fake := FakeService.new()
	fake.import_result = {"ok": false, "error": "boom"}
	var r_fake: Dictionary = BuiltinScript.ensure(fake)
	_expect(not bool(r_fake.get("ok", true)) and String(r_fake.get("error", "")).begins_with("back_import_failed"),
		"导入失败传播错误（实际：%s）" % String(r_fake.get("error", "")))
	var fake2 := FakeService.new()
	fake2.save_result = {"ok": false, "error": "disk_full"}
	var r_fake2: Dictionary = BuiltinScript.ensure(fake2)
	_expect(not bool(r_fake2.get("ok", true)) and String(r_fake2.get("error", "")).contains("disk_full"),
		"保存失败传播错误且回滚（实际：%s）" % String(r_fake2.get("error", "")))
	_expect(fake2.library.size() == 2, "保存失败时已入库条目保留（下次启动重新收敛）")
	_expect(float((fake2.library[0] as Dictionary)["render"]["ground_width_px"]) == 0.0,
		"保存失败回滚：收敛改动被撤销（ground_width 保持导入默认 0）")

	_cleanup()
	print("BUILTIN_BUILDING_PASS: all 5 sections")
	quit(0)


## 假服务：可注入导入/保存失败；成功路径最小实现 ensure 用到的接口
class FakeService:
	extends RefCounted
	var import_result: Dictionary = {}
	var save_result: Dictionary = {}
	var library: Array = []
	var max_image_bytes := 32 * 1024 * 1024

	func import_local_file(_src_path: String, _kind: String = "terrain",
			_extra_tags: PackedStringArray = [], _display_name: String = "") -> Dictionary:
		if not import_result.is_empty():
			return import_result
		var d := {
			"id": "fake_%d" % library.size(), "kind": _kind, "name": _display_name,
			"tags": [], "image": "x.png", "sha256": "a".repeat(64), "bytes": 1,
			"width": 4, "height": 4, "render": preload(
				"res://scripts/assets/user_asset_catalog.gd").default_render(),
			"saved": true,
		}
		library.append(d)
		return {"ok": true, "asset_id": String(d["id"]), "deduped": false}

	func find_by_id(asset_id: String) -> Variant:
		for d in library:
			if String(d["id"]) == asset_id:
				return d
		return null

	func save_library() -> Dictionary:
		if not save_result.is_empty():
			return save_result
		return {"ok": true}
