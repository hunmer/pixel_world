## prepare_building_demo.gd — 用真实塔楼准备建筑视觉验收地图（不启动游戏、不截图）。
## 用法：godot --headless --path . --script res://tools/prepare_building_demo.gd
## 可选：-- --back=<真实背面图片路径>；没有背图时只创建单图建筑。
extends SceneTree

const ServiceScript = preload("res://scripts/assets/user_asset_service.gd")
const DocScript = preload("res://scripts/editor/battlefield_doc.gd")
const SOURCE := "res://meowa_tiles/generated/citywall_1to9.png"

func _initialize() -> void:
	call_deferred("_prepare")

func _prepare() -> void:
	var service = ServiceScript.new()
	root.add_child(service)
	await process_frame
	var imported: Dictionary = service.import_local_file(SOURCE, "building", [], "石塔（视觉验收）")
	if not _require(bool(imported.get("ok", false)), "塔楼导入失败：%s" % imported):
		return
	var asset_id := String(imported["asset_id"])
	var front: Dictionary = (service.find_by_id(asset_id) as Dictionary).duplicate(true)
	var render: Dictionary = front.get("render", {}).duplicate(true)
	# 初始标定值；未进行视觉验收，最终可在素材面板里微调。
	render.merge({"footprint": {"w": 2, "h": 2}, "ground_width_px": 1150.0,
		"pivot": {"x": 0.425, "y": 0.9}, "scale": 1.0,
		"back_mode": "single", "back_asset_id": ""}, true)
	front["kind"] = "building"
	front["render"] = render
	var snapshots: Dictionary = {asset_id: front}
	var back_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--back="):
			back_path = argument.trim_prefix("--back=")
	if not back_path.is_empty():
		var back_import: Dictionary = service.import_local_file(back_path, "building", [], "石塔背面（视觉验收）")
		if not _require(bool(back_import.get("ok", false)), "背面导入失败：%s" % back_import):
			return
		var back_id := String(back_import["asset_id"])
		if not _require(back_id != asset_id, "背面必须使用另一张图片，不能把正面冒充背面"):
			return
		var back: Dictionary = (service.find_by_id(back_id) as Dictionary).duplicate(true)
		back["kind"] = "building"
		back["render"] = render.duplicate(true)
		snapshots[back_id] = back
		render["back_mode"] = "front_back"
		render["back_asset_id"] = back_id
	# 新导入素材同步标定到素材库；已存在的素材只在本示例快照中覆盖，保留用户设置。
	if not bool(imported.get("deduped", false)):
		var updated: Dictionary = service.update_asset(asset_id, {"kind": "building", "render": render})
		if not _require(bool(updated.get("ok", false)), "素材配置保存失败：%s" % updated):
			return
	var model: Dictionary = DocScript.create_empty(12, 10)
	model["id"] = "building_demo"
	model["name"] = "建筑视觉验收：石塔"
	model["description"] = "真实高塔、2×2占地；请验收落地锚点、四向展示、编辑与阻挡。标定值尚待视觉确认。"
	model["user_assets"] = snapshots
	model["buildings"] = [{"instance_id": "demo_tower_1", "asset_id": asset_id,
		"x": 4, "y": 4, "rotation": 0}]
	model["units"] = [
		{"class": "swordsman", "name": "验收友军", "level": 3, "x": 2, "y": 5, "faction": "player"},
		{"class": "berserker", "name": "验收敌军", "level": 3, "x": 9, "y": 5, "faction": "enemy"}]
	var result: Dictionary = DocScript.save_model(model)
	if not _require(bool(result.get("ok", false)), "示例地图保存失败：%s" % result):
		return
	print("[BuildingDemo] PASS：", result)
	print("[BuildingDemo] 素材类型：", render["back_mode"], "；请从编辑器加载 building_demo，视觉效果待人工验收。")
	service.queue_free()
	await process_frame
	quit(0)

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("[BuildingDemo] " + message)
	quit(1)
	return false
