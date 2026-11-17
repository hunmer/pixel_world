## builtin_house_assets_contract.gd — 宽敞单层房屋源图、幂等注册、标定和快照契约。
extends SceneTree
const House = preload("res://scripts/assets/builtin_house_assets.gd")
const Service = preload("res://scripts/assets/user_asset_service.gd")
const Catalog = preload("res://scripts/assets/user_asset_catalog.gd")
const Adapter = preload("res://scripts/assets/user_asset_visual_adapter.gd")
var failures: int = 0
var checks: int = 0
var tmp_root: String = "user://tmp/builtin_house_contract_%d" % Time.get_ticks_usec()

func _initialize() -> void:
	call_deferred("_run")

func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("HOUSE_ASSET_FAIL: " + message)

func _run() -> void:
	var source: Dictionary = House.snapshot()
	_expect(not source.is_empty(), "工程房屋源图可读取")
	_expect(Catalog.validate_descriptor(source, "house_source").is_empty(), "快照符合严格四方向建筑契约")
	_expect(source["sha256"] == House.SHEET_SHA256, "真实源图哈希一致")
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(House.RECIPE_PATH))
	_expect(recipe["profile"]["typeId"] == "house" and int(recipe["profile"]["params"]["floors"]) == 1, "源图为真正单层房屋而非塔复制")
	_expect(float(recipe["view"]["baseYaw"]) == 45.0 and float(recipe["view"]["pitch"]) == 30.0 and int(recipe["view"]["directions"]) == 4, "CLI导出角度/帧数正确")
	_expect(recipe["view"]["projection"] == "orthographic", "正交投影")
	var adapter := Adapter.new(tmp_root)
	var visual: Dictionary = adapter.resolve_snapshot(source)
	var frames: Array = visual.get("directions", [])
	_expect(not visual.get("missing", true) and frames.size() == 4, "空用户库也能离线解析四帧")
	var hashes: Dictionary = {}
	for frame: Dictionary in frames:
		var texture: Texture2D = frame["texture"]
		_expect(texture.get_size() == Vector2(512, 512), "保留512单帧清晰度")
		hashes[Service.compute_sha256_hex(texture.get_image().get_data())] = true
		var size: Vector2 = frame["canvas_size"]
		var center: Vector2 = Vector2(257.2899141071015, 342.9140931144665) * size.y / 512.0
		_expect((center - size * 0.5 + frame["render_offset"]).length() < 0.001, "CLI地基中心精确落在锚点")
	_expect(hashes.size() == 4, "四方向实际像素不同")
	var service := Service.new(tmp_root)
	service.remote_enabled = false
	root.add_child(service)
	var first: Dictionary = House.ensure(service)
	_expect(first.get("ok", false) and first.get("changed", false), "首次注册成功")
	var id: String = first.get("asset_id", "")
	_expect(service.asset_count() == 1, "只注册一栋房屋")
	var descriptor: Dictionary = service.find_by_id(id)
	_expect(descriptor["render"]["footprint"] == {"w": 6, "h": 6}, "6x6宽敞占地")
	_expect(descriptor["render"]["interior"] == House.INTERIOR, "室内布局与缩放阈值持久化")
	var before: PackedByteArray = FileAccess.get_file_as_bytes(tmp_root + "/library.json")
	var again: Dictionary = House.ensure(service)
	_expect(again.get("ok", false) and not again.get("changed", true), "重复注册零改动")
	_expect(FileAccess.get_file_as_bytes(tmp_root + "/library.json") == before, "幂等零写入")
	var custom: Dictionary = descriptor["render"].duplicate(true)
	custom["pivot"] = {"x": 0.4, "y": 0.7}
	custom["scale"] = 1.2
	service.update_asset(id, {"name": "我的房子", "render": custom})
	House.ensure(service)
	_expect(service.find_by_id(id)["name"] == "我的房子" and service.find_by_id(id)["render"] == custom, "重注册保留用户改名与标定")
	service.free()
	var loaded: Dictionary = Catalog.load_library(tmp_root + "/library.json")
	_expect(loaded.get("ok", false), "房屋素材库保存回读有效")
	_remove_tree(tmp_root)
	print("BUILTIN_HOUSE_ASSETS_CONTRACT %s checks=%d" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _remove_tree(path: String) -> void:
	assert(path.begins_with(tmp_root))
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child: String in directory.get_directories():
		_remove_tree(path + "/" + child)
	for child: String in directory.get_files():
		directory.remove(child)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
