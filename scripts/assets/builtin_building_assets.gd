## builtin_building_assets.gd — 内置四方向中世纪瞭望塔注册（内容寻址、幂等）
## 仅注册原始横排 sheet；不注册旧石墙或用单帧伪造四向。
## 已标定条目保留名称、底座宽度、锚点、缩放及占地；方向格式始终收敛。
const Catalog := preload("res://scripts/assets/user_asset_catalog.gd")

const SHEET_PNG := "res://assets/buildings/medieval_watchtower/sheet.png"
const DISPLAY_NAME := "中世纪瞭望塔"
const FOOTPRINT := {"w": 2, "h": 2}
const GROUND_WIDTH_PX := 232.44195804706033
## CLI 地基投影：yaw45/pitch30，原点(259.49485,416.90407)，台基宽232.44px。
const PIVOT := {"x": 0.5068258805742822, "y": 0.8142657649984744}
const SHEET_SHA256 := "3a44869debc92e0d7bbdd3811320e1500611cb549021b355ca9eeee60cb5a377"
const ASSET_SCALE := 1.0
const BUILTIN_TAG := "builtin"


## {ok:true, asset_id, changed} 或 {ok:false, error}。
## changed=false 表示同内容条目已经符合目标态，本次零写入。
static func ensure(service) -> Dictionary:
	if service == null:
		return {"ok": false, "error": "service_null"}
	if not FileAccess.file_exists(SHEET_PNG):
		return {"ok": false, "error": "sheet_source_missing: %s" % SHEET_PNG}
	var imported: Dictionary = service.import_local_file(
		SHEET_PNG, Catalog.KIND_BUILDING, PackedStringArray([BUILTIN_TAG]), DISPLAY_NAME)
	if not bool(imported.get("ok", false)):
		return {"ok": false, "error": "sheet_import_failed: %s" % String(imported.get("error", ""))}
	var asset_id := String(imported["asset_id"])
	var found: Variant = service.find_by_id(asset_id)
	if not (found is Dictionary):
		return {"ok": false, "error": "entry_missing_after_import: %s" % asset_id}
	var desc: Dictionary = found
	if int(desc.get("height", 0)) <= 0 or int(desc.get("width", 0)) != int(desc.get("height", 0)) * 4:
		return {"ok": false, "error": "building_requires_four_direction_sheet"}
	var backup := desc.duplicate(true)
	var render: Dictionary = corrected_render(desc)
	if String(desc.get("kind", "")) != Catalog.KIND_BUILDING or float(render.get("ground_width_px", 0.0)) <= 0.0:
		_apply_default_render(render)
	desc["kind"] = Catalog.KIND_BUILDING
	render["direction_mode"] = "four_directions"
	render["mode"] = Catalog.RENDER_MODE_FULL
	render["crop"] = null
	render.erase("back_mode")
	render.erase("back_asset_id")
	desc["render"] = render
	var changed := desc != backup
	if changed:
		var errors: Array = Catalog.validate_descriptor(desc, "builtin.ensure(%s)" % asset_id, int(service.max_image_bytes))
		if not errors.is_empty():
			desc.assign(backup)
			return {"ok": false, "error": "descriptor_invalid: %s" % " ; ".join(PackedStringArray(errors))}
		var saved: Dictionary = service.save_library()
		if not bool(saved.get("ok", false)):
			desc.assign(backup)
			return {"ok": false, "error": "library_save_failed: %s" % String(saved.get("error", ""))}
	return {"ok": true, "asset_id": asset_id,
		"changed": changed or not bool(imported.get("deduped", false))}


## 瞭望塔以固定单帧画布标定，避免四个方向的挑檐改变内容包围盒。
static func _apply_default_render(render: Dictionary) -> void:
	render["mode"] = Catalog.RENDER_MODE_FULL
	render["crop"] = null
	render["direction_mode"] = "four_directions"
	render["pivot"] = PIVOT.duplicate()
	render["pivot_space"] = "frame"
	render["scale"] = ASSET_SCALE
	render["footprint"] = FOOTPRINT.duplicate()
	render["ground_width_px"] = GROUND_WIDTH_PX


## 仅纠正这张塔图的旧默认标定；旧地图快照也可用，不修改用户自定义值。
static func corrected_render(descriptor: Dictionary) -> Dictionary:
	var render: Dictionary = descriptor.get("render", {}).duplicate(true)
	if String(descriptor.get("sha256", "")) != SHEET_SHA256:
		return render
	var pivot: Dictionary = render.get("pivot", {})
	var footprint: Dictionary = render.get("footprint", {})
	if render.get("pivot_space", "content") == "content" \
			and is_equal_approx(float(pivot.get("x", 0.0)), 0.5) \
			and is_equal_approx(float(pivot.get("y", 0.0)), 0.87) \
			and is_equal_approx(float(render.get("ground_width_px", 0.0)), GROUND_WIDTH_PX) \
			and is_equal_approx(float(render.get("scale", 0.0)), ASSET_SCALE) \
			and int(footprint.get("w", 0)) == 2 and int(footprint.get("h", 0)) == 2:
		render["pivot"] = PIVOT.duplicate()
		render["pivot_space"] = "frame"
	return render
