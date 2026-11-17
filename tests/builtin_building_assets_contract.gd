## builtin_building_assets_contract.gd — 四方向内置瞭望塔纯 headless 契约。
## godot --headless --path . --script res://tests/builtin_building_assets_contract.gd
## 用独立临时 root，验证单条注册、幂等、标定保留、严格四向与失败回滚。
extends SceneTree
const Service = preload("res://scripts/assets/user_asset_service.gd")
const Builtin = preload("res://scripts/assets/builtin_building_assets.gd")
const Catalog = preload("res://scripts/assets/user_asset_catalog.gd")
var _tmp_root := "user://builtin_contract_assets_%d" % Time.get_ticks_usec()
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("BUILTIN_BUILDING_FAIL: " + message)

func _run() -> void:
	var service := Service.new(_tmp_root)
	root.add_child(service)
	var first: Dictionary = Builtin.ensure(service)
	_expect(bool(first.get("ok", false)), "首次注册成功：%s" % first)
	if not bool(first.get("ok", false)):
		service.free()
		_remove_tree(_tmp_root)
		quit(1)
		return
	var asset_id := String(first["asset_id"])
	_expect(bool(first.get("changed", false)), "首次 changed=true")
	_expect(not first.has("back_asset_id"), "返回仅一个 sheet id")
	_expect(service.asset_count() == 1, "只注册一个建筑，不再注册旧石墙")
	var desc: Dictionary = service.find_by_id(asset_id)
	var render: Dictionary = desc["render"]
	_expect(desc["name"] == "中世纪瞭望塔" and desc["kind"] == "building", "内置名称与类型")
	_expect(int(desc["width"]) == 2048 and int(desc["height"]) == 512, "保留原始 sheet 尺寸")
	_expect(Catalog.is_four_direction_building(desc), "严格四向描述符")
	_expect(render["mode"] == "full" and render["crop"] == null, "整张横排，不裁切")
	_expect(render["footprint"] == {"w": 2, "h": 2}, "2x2 占地")
	_expect(is_equal_approx(float(render["ground_width_px"]), Builtin.GROUND_WIDTH_PX), "单帧底座与CLI地基投影一致")
	_expect(render["pivot"] == Builtin.PIVOT and float(render["scale"]) == 1.0, "初始锚点与缩放")
	_expect(not render.has("back_mode") and not render.has("back_asset_id"), "无旧背面关联")
	var before := FileAccess.get_file_as_bytes(_tmp_root + "/library.json")
	var again: Dictionary = Builtin.ensure(service)
	_expect(bool(again.get("ok", false)) and not bool(again.get("changed", true)), "重跑幂等")
	_expect(FileAccess.get_file_as_bytes(_tmp_root + "/library.json") == before, "幂等零写入")
	_expect(again.get("asset_id") == asset_id, "内容寻址id稳定")

	var legacy := render.duplicate(true)
	legacy["pivot"] = {"x": 0.5, "y": 0.87}
	legacy.erase("pivot_space")
	service.update_asset(asset_id, {"render": legacy})
	var migrated: Dictionary = Builtin.ensure(service)
	_expect(bool(migrated.get("changed", false)), "已注册旧默认锚点自动修复")
	_expect(service.find_by_id(asset_id)["render"]["pivot"] == Builtin.PIVOT, "修复落盘且不保留错误默认值")
	_expect(not bool(Builtin.ensure(service).get("changed", true)), "修复后仍幂等")
	# 保存用户标定再重新创建服务，确保磁盘往返不丢失参数。
	var custom := render.duplicate(true)
	custom.merge({"ground_width_px": 198.0, "pivot": {"x": 0.4, "y": 0.82},
		"scale": 1.25, "footprint": {"w": 3, "h": 2}}, true)
	var update: Dictionary = service.update_asset(asset_id, {"name": "我的瞭望塔", "render": custom})
	_expect(bool(update.get("ok", false)), "用户标定保存")
	service.free()
	service = Service.new(_tmp_root)
	root.add_child(service)
	var preserved: Dictionary = Builtin.ensure(service)
	_expect(bool(preserved.get("ok", false)) and not bool(preserved.get("changed", true)), "已有标定不重写")
	desc = service.find_by_id(asset_id)
	_expect(desc["name"] == "我的瞭望塔" and desc["render"] == custom, "保留改名和全套标定")

	# 严格格式：单帧、双帧、未知尺寸及裁切均不能作为四向建筑。
	for dimensions in [Vector2i(512, 512), Vector2i(1024, 512), Vector2i(0, 0), Vector2i(2047, 512)]:
		var invalid := desc.duplicate(true)
		invalid["width"] = dimensions.x
		invalid["height"] = dimensions.y
		_expect(not Catalog.validate_descriptor(invalid, "invalid_sheet").is_empty(), "拒绝非法尺寸 %s" % dimensions)
	var invalid_mode := desc.duplicate(true)
	invalid_mode["render"]["direction_mode"] = "single"
	_expect(not Catalog.validate_descriptor(invalid_mode, "single").is_empty(), "拒绝旧单图模式")
	var invalid_crop := desc.duplicate(true)
	invalid_crop["render"]["mode"] = "crop"
	invalid_crop["render"]["crop"] = {"x": 0, "y": 0, "w": 512, "h": 512}
	_expect(not Catalog.validate_descriptor(invalid_crop, "crop").is_empty(), "拒绝裁成单帧")
	var single_bytes := FileAccess.get_file_as_bytes(Builtin.SHEET_PNG)
	var image := Image.new()
	Service.decode_image_bytes(single_bytes, image)
	var one_frame := image.get_region(Rect2i(0, 0, 512, 512)).save_png_to_buffer()
	var rejected: Dictionary = service.import_image_bytes(one_frame, "single.png", "building")
	_expect(not bool(rejected.get("ok", true)), "实际单帧导入被拒绝")
	_expect(service.asset_count() == 1, "拒绝导入不污染素材库")
	service.free()

	_expect(Builtin.ensure(null).get("error") == "service_null", "拒绝空service")
	var fake := FakeService.new()
	fake.import_error = "boom"
	_expect(String(Builtin.ensure(fake).get("error", "")).contains("boom"), "导入失败传播")
	fake.import_error = ""
	fake.fail_save = true
	_expect(String(Builtin.ensure(fake).get("error", "")).contains("disk_full"), "保存失败传播")
	_expect(float(fake.descriptor["render"]["ground_width_px"]) == 0.0, "保存失败回滚标定")
	fake.fail_save = false
	fake.descriptor["width"] = 512
	_expect(not bool(Builtin.ensure(fake).get("ok", true)), "注册不能将旧单帧伪造为四向")
	_remove_tree(_tmp_root)
	if _failures == 0:
		print("BUILTIN_BUILDING_PASS: registration / idempotence / calibration / strict-four-directions / rollback")
	quit(0 if _failures == 0 else 1)

func _remove_tree(path: String) -> void:
	# 唯一临时 root 内递归清理，不接触真实 custom_assets。
	assert(path.begins_with(_tmp_root))
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child in directory.get_directories():
		_remove_tree(path + "/" + child)
	for filename in directory.get_files():
		directory.remove(filename)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

class FakeService:
	extends RefCounted
	var import_error := ""
	var fail_save := false
	var max_image_bytes := 32 * 1024 * 1024
	var descriptor: Dictionary = Catalog.make_descriptor("fake_sheet", "building", "测试塔",
		[], "sheet.png", "a".repeat(64), 1, 16, 4)
	func import_local_file(_source: String, _kind: String, _tags: PackedStringArray, _name: String) -> Dictionary:
		return {"ok": false, "error": import_error} if not import_error.is_empty() else {"ok": true, "asset_id": "fake_sheet", "deduped": true}
	func find_by_id(_asset_id: String) -> Dictionary:
		return descriptor
	func save_library() -> Dictionary:
		return {"ok": false, "error": "disk_full"} if fail_save else {"ok": true}
