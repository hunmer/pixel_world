## prepare_building_demo.gd — 直接构造四向建筑示例快照，不读取或写入用户素材库。
## godot --headless --path . --script res://tools/prepare_building_demo.gd -- --sheet=<4:1横排PNG>
extends SceneTree

const Builtin = preload("res://scripts/assets/builtin_building_assets.gd")
const Catalog = preload("res://scripts/assets/user_asset_catalog.gd")
const Service = preload("res://scripts/assets/user_asset_service.gd")
const Doc = preload("res://scripts/editor/battlefield_doc.gd")
const Loader = preload("res://scripts/core/battlefield_loader.gd")
const OUTPUT := "res://data/battlefields/building_demo.json"

func _initialize() -> void:
	call_deferred("_prepare")

func _prepare() -> void:
	var sheet := Builtin.SHEET_PNG
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--sheet=") and not argument.trim_prefix("--sheet=").is_empty():
			sheet = argument.trim_prefix("--sheet=")
		else:
			_fail("只接受 --sheet=<四方向横排图>；旧 --single / --back 已停用：%s" % argument)
			return
	# 快照的离线取图仅支持随项目分发的建筑源目录；先归一化以拒绝 ../ 越界。
	sheet = sheet.simplify_path()
	if not sheet.begins_with("res://assets/buildings/"):
		_fail("--sheet 必须位于 res://assets/buildings/ 内并随项目分发；外部路径无法保证示例离线显示")
		return
	var bytes := FileAccess.get_file_as_bytes(sheet)
	var image := Image.new()
	if Service.decode_image_bytes(bytes, image).is_empty() or image.get_height() <= 0 or image.get_width() != image.get_height() * 4:
		_fail("建筑必须是四个等大正方形帧组成的 4:1 横排 sheet")
		return
	var sha := Service.compute_sha256_hex(bytes)
	var asset_id := "medieval_watchtower_" + sha.substr(0, 12)
	var render := Catalog.default_render()
	Builtin._apply_default_render(render)
	var descriptor := Catalog.make_descriptor(asset_id, "building", Builtin.DISPLAY_NAME,
		["builtin", "watchtower"], sheet, sha, bytes.size(), image.get_width(), image.get_height(), render)
	descriptor["saved"] = true
	var errors := Catalog.validate_descriptor(descriptor, "building_demo")
	if not errors.is_empty():
		_fail("素材校验失败：%s" % " ; ".join(errors))
		return
	var model: Dictionary = Doc.create_empty(12, 10)
	model["id"] = "building_demo"
	model["name"] = "建筑视觉验收：中世纪瞭望塔"
	model["description"] = "原始四方向横排精灵图、2×2占地；yaw45/pitch30，底座232.44px，单帧地基中心(259.49,416.90)。请人工检查落地与遮挡。"
	model["user_assets"] = {asset_id: descriptor}
	model["buildings"] = [{"instance_id": "demo_tower_1", "asset_id": asset_id,
		"x": 4, "y": 4, "rotation": 0}]
	model["units"] = [
		{"class": "swordsman", "name": "验收友军", "level": 3, "x": 2, "y": 5, "faction": "player"},
		{"class": "berserker", "name": "验收敌军", "level": 3, "x": 9, "y": 5, "faction": "enemy"}]
	var document := Doc.to_json_dict(model)
	var validated := Loader.load_battlefield_inline(document, "building_demo")
	if not bool(validated.get("ok", false)):
		_fail("示例校验失败：%s" % validated.get("error", ""))
		return
	# 专用生成文件可覆盖；不调用 save_model，避免 .bak 和 user:// 回退。
	var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if output == null:
		_fail("无法写入专用示例：%s" % OUTPUT)
		return
	output.store_string(JSON.stringify(document, "\t") + "\n")
	output.close()
	print("BUILDING_DEMO_PASS: ", OUTPUT, " sheet_sha256=", sha)
	quit(0)

func _fail(message: String) -> void:
	push_error("[BuildingDemo] " + message)
	quit(1)
