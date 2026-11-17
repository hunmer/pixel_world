## prepare_house_demo.gd — 生成独立房屋室内验收地图，不读取或修改用户素材库。
## godot --headless --path . --script res://tools/prepare_house_demo.gd
extends SceneTree
const House = preload("res://scripts/assets/builtin_house_assets.gd")
const Doc = preload("res://scripts/editor/battlefield_doc.gd")
const Catalog = preload("res://scripts/assets/user_asset_catalog.gd")
const Loader = preload("res://scripts/core/battlefield_loader.gd")
const OUTPUT := "res://data/battlefields/house_interior_demo.json"

func _initialize() -> void:
	call_deferred("_prepare")

func _prepare() -> void:
	var descriptor: Dictionary = House.snapshot()
	var errors: Array = Catalog.validate_descriptor(descriptor, "house_interior_demo")
	if not errors.is_empty():
		_fail("素材无效：%s" % "; ".join(errors))
		return
	var id: String = descriptor["id"]
	var model: Dictionary = Doc.create_empty(14, 12)
	model["id"] = "house_interior_demo"
	model["name"] = "宽敞房屋：室内与门口验收"
	model["description"] = "6×6单层房屋：室内可走、墙和家具阻挡；缩放≥1.8展示内部，≤1.5恢复外观。门在南侧中部。"
	model["user_assets"] = {id: descriptor}
	model["buildings"] = [{"instance_id": "house_001", "asset_id": id, "x": 4, "y": 3, "rotation": 0}]
	model["units"] = [
		{"class": "swordsman", "name": "室内友军", "level": 3, "x": 7, "y": 6, "faction": "player"},
		{"class": "berserker", "name": "门外敌军", "level": 3, "x": 7, "y": 9, "faction": "enemy"},
	]
	var document: Dictionary = Doc.to_json_dict(model)
	var checked: Dictionary = Loader.load_battlefield_inline(document, "house_interior_demo")
	if not bool(checked.get("ok", false)):
		_fail("地图无效：%s" % checked.get("error", ""))
		return
	var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if output == null:
		_fail("无法写入：%s" % OUTPUT)
		return
	output.store_string(JSON.stringify(document, "\t") + "\n")
	output.close()
	print("HOUSE_DEMO_PASS: ", OUTPUT, " sha256=", descriptor["sha256"])
	quit(0)

func _fail(message: String) -> void:
	push_error("[HouseDemo] " + message)
	quit(1)
