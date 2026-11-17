## builtin_house_assets.gd — 内置6×6单层可进入房屋，源图由建筑CLI真实生成。
const Catalog = preload("res://scripts/assets/user_asset_catalog.gd")
const Service = preload("res://scripts/assets/user_asset_service.gd")

const SHEET_PNG := "res://assets/buildings/spacious_house/sheet.png"
const RECIPE_PATH := "res://assets/buildings/spacious_house/recipe.json"
const DISPLAY_NAME := "宽敞单层房屋"
const SHEET_SHA256 := "25b3ae98b249b5896dc90b5b37db3db8e494454cf384200f9e9ef18fd2653734"
const FOOTPRINT := {"w": 6, "h": 6}
## CLI prefabStats 原点(257.289914,342.914093)，8.24米方台基投影宽404.910107px。
const GROUND_WIDTH_PX := 404.91010711440094
const PIVOT := {"x": 0.5025193634904326, "y": 0.6697540881141923}
const INTERIOR := {
	"enabled": true,
	"rows": ["######", "#....#", "#.F..#", "#....#", "#....#", "##DD##"],
	"reveal_zoom": 1.8,
	"hide_zoom": 1.5,
}


## 注册与重入收敛；保留已有用户标定和改名，不修改其他条目。
static func ensure(service) -> Dictionary:
	if service == null:
		return {"ok": false, "error": "service_null"}
	if not FileAccess.file_exists(SHEET_PNG):
		return {"ok": false, "error": "house_sheet_missing"}
	var imported: Dictionary = service.import_local_file(
		SHEET_PNG, Catalog.KIND_BUILDING, PackedStringArray(["builtin", "enterable_house"]), DISPLAY_NAME)
	if not bool(imported.get("ok", false)):
		return {"ok": false, "error": "house_import_failed: %s" % imported.get("error", "")}
	var asset_id: String = String(imported["asset_id"])
	var descriptor: Dictionary = service.find_by_id(asset_id)
	var before: Dictionary = descriptor.duplicate(true)
	var render: Dictionary = descriptor.get("render", {}).duplicate(true)
	if float(render.get("ground_width_px", 0.0)) <= 0.0:
		render = default_render()
	elif not render.has("interior"):
		# 已自行导入同一真实房屋时补室内布局；不覆盖已有室内编辑。
		render["interior"] = INTERIOR.duplicate(true)
	descriptor["render"] = render
	var changed: bool = descriptor != before
	if changed:
		var errors: Array = Catalog.validate_descriptor(descriptor, "builtin_house.ensure")
		if not errors.is_empty():
			descriptor.assign(before)
			return {"ok": false, "error": "house_descriptor_invalid: %s" % "; ".join(errors)}
		var saved: Dictionary = service.save_library()
		if not bool(saved.get("ok", false)):
			descriptor.assign(before)
			return {"ok": false, "error": "house_save_failed: %s" % saved.get("error", "")}
	return {"ok": true, "asset_id": asset_id, "changed": changed or not bool(imported.get("deduped", false))}


static func default_render() -> Dictionary:
	var render: Dictionary = Catalog.default_render()
	render.merge({
		"direction_mode": "four_directions", "mode": "full", "crop": null,
		"footprint": FOOTPRINT.duplicate(), "pivot": PIVOT.duplicate(), "pivot_space": "frame",
		"ground_width_px": GROUND_WIDTH_PX, "scale": 1.0, "interior": INTERIOR.duplicate(true),
	}, true)
	return render


## 工程内自包含快照，不实例化服务、不写入用户库。
static func snapshot() -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SHEET_PNG)
	var image := Image.new()
	if Service.decode_image_bytes(bytes, image).is_empty():
		return {}
	var sha: String = Service.compute_sha256_hex(bytes)
	var asset_id: String = "spacious_house_" + sha.substr(0, 12)
	var descriptor: Dictionary = Catalog.make_descriptor(asset_id, "building", DISPLAY_NAME,
		["builtin", "enterable_house"], SHEET_PNG, sha, bytes.size(), image.get_width(), image.get_height(), default_render())
	descriptor["saved"] = true
	return descriptor
