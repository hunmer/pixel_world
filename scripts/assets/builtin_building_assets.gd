## builtin_building_assets.gd — 内置建筑素材自注册（石墙正背对）
##
## 职责：把工程自带的石墙正面/背面 PNG 注册进用户素材库（内容寻址、幂等），
## 并补齐 building 渲染标定。由编辑器启动装配调用（ensure(service)），失败返回
## {ok:false,error} 由调用方决定提示方式；不抛异常、不 touch 其他库条目。
##
## 收敛目标（每次调用后成立的库不变式）：
## 1. 正/背两条 descriptor 存在，kind=building；
## 2. 未标定（ground_width_px<=0）的条目打默认标定：footprint 2x2、
##    ground_width_px=1150、front pivot(0.425,0.9)、back pivot(0.575,0.9)、scale 1；
##    已正确标定（kind=building 且 ground_width_px>0）的条目保留用户标定，不重置；
## 3. front.render 恒为 front_back 且 back_asset_id 指向真实背面条目；
##    back.render 恒为 single（back 不再引用任何素材）；
## 4. 已存在条目的名字不动（含用户改名）。

const Catalog := preload("res://scripts/assets/user_asset_catalog.gd")

## 工程内自带正背图（内容寻址导入：同 sha 重复导入直接复用既有条目）
const FRONT_PNG := "res://meowa_tiles/generated/citywall_1to9.png"
const BACK_PNG := "res://meowa_tiles/generated/citywall_1to9_back.png"

const FRONT_NAME := "石墙"
const BACK_NAME := "石墙背面"

const FOOTPRINT := {"w": 2, "h": 2}
const GROUND_WIDTH_PX := 1150.0
const FRONT_PIVOT := {"x": 0.425, "y": 0.9}
const BACK_PIVOT := {"x": 0.575, "y": 0.9}
const ASSET_SCALE := 1.0
const BUILTIN_TAG := "builtin"


## 确保内置石墙正背对已注册且标定收敛。返回：
## {ok:true, asset_id, back_asset_id, changed} 或 {ok:false, error}。
## changed=false 表示库已是目标态（本次零写入）。
static func ensure(service) -> Dictionary:
	if service == null:
		return {"ok": false, "error": "service_null"}
	if not FileAccess.file_exists(FRONT_PNG):
		return {"ok": false, "error": "front_source_missing: %s" % FRONT_PNG}
	if not FileAccess.file_exists(BACK_PNG):
		return {"ok": false, "error": "back_source_missing: %s" % BACK_PNG}
	# 先导背面：正面引用它的真实 asset_id，且 deduped 命中旧条目时也能拿到既有 id
	var back_res: Dictionary = service.import_local_file(
		BACK_PNG, Catalog.KIND_BUILDING, PackedStringArray([BUILTIN_TAG]), BACK_NAME)
	if not bool(back_res.get("ok", false)):
		return {"ok": false, "error": "back_import_failed: %s" % String(back_res.get("error", ""))}
	var back_id := String(back_res["asset_id"])
	var front_res: Dictionary = service.import_local_file(
		FRONT_PNG, Catalog.KIND_BUILDING, PackedStringArray([BUILTIN_TAG]), FRONT_NAME)
	if not bool(front_res.get("ok", false)):
		return {"ok": false, "error": "front_import_failed: %s" % String(front_res.get("error", ""))}
	var front_id := String(front_res["asset_id"])

	var back_res_inner: Dictionary = _converge_entry(service, back_id, false, "")
	if not String(back_res_inner["err"]).is_empty():
		return {"ok": false, "error": String(back_res_inner["err"])}
	var front_res_inner: Dictionary = _converge_entry(service, front_id, true, back_id)
	if not String(front_res_inner["err"]).is_empty():
		return {"ok": false, "error": String(front_res_inner["err"])}

	return {"ok": true, "asset_id": front_id, "back_asset_id": back_id,
		"changed": bool(back_res_inner["changed"]) or bool(front_res_inner["changed"])}


# ---------------------------------------------------------------------------
# 内部：条目收敛（返回错误文案，空 = 成功）
# ---------------------------------------------------------------------------

## 就地收敛单个条目；is_front 时强制关联 back_id。返回 {err: String, changed: bool}。
static func _converge_entry(service, asset_id: String, is_front: bool, back_id: String) -> Dictionary:
	var d: Variant = service.find_by_id(asset_id)
	if not (d is Dictionary):
		return {"err": "entry_missing_after_import: %s" % asset_id, "changed": false}
	var desc: Dictionary = d
	var render: Dictionary = desc.get("render", {})
	var calibrated := String(desc.get("kind", "")) == Catalog.KIND_BUILDING \
		and float(render.get("ground_width_px", 0.0)) > 0.0
	var backup: Dictionary = desc.duplicate(true)
	var changed := false

	# 未正确标定 → 打默认全套（含 kind 归位；用户从未调过，无标定损失）
	if not calibrated:
		desc["kind"] = Catalog.KIND_BUILDING
		_apply_default_render(render, FRONT_PIVOT if is_front else BACK_PIVOT)
		desc["render"] = render
		changed = true

	# 关联收敛（已标定条目也执行——这是内置正背对的存在语义）：
	# front 恒 front_back + 真实 back；back 恒 single + 无引用
	if is_front:
		if String(render.get("back_mode", "")) != Catalog.BACK_MODE_FRONT_BACK \
				or String(render.get("back_asset_id", "")) != back_id:
			render["back_mode"] = Catalog.BACK_MODE_FRONT_BACK
			render["back_asset_id"] = back_id
			desc["render"] = render
			changed = true
	elif String(render.get("back_mode", Catalog.BACK_MODE_SINGLE)) != Catalog.BACK_MODE_SINGLE \
			or not String(render.get("back_asset_id", "")).is_empty():
		render["back_mode"] = Catalog.BACK_MODE_SINGLE
		Catalog.enforce_single_back(render)
		desc["render"] = render
		changed = true

	if not changed:
		return {"err": "", "changed": false}
	# 改动过才校验；失败回滚（库保持原样，由调用方报错）
	var errs: Array = Catalog.validate_descriptor(
		desc, "builtin_building_assets.ensure(%s)" % asset_id, int(service.max_image_bytes))
	if not errs.is_empty():
		desc.assign(backup)
		return {"err": "descriptor_invalid(%s): %s" % [asset_id, " ; ".join(PackedStringArray(errs))], "changed": false}
	var save_res: Dictionary = service.save_library()
	if not bool(save_res.get("ok", false)):
		desc.assign(backup)
		return {"err": "library_save_failed: %s" % String(save_res.get("error", "")), "changed": false}
	return {"err": "", "changed": true}


## 打默认标定（就地修改 render）：整图、指定 pivot、scale 1、footprint 2x2、
## ground_width 1150、single 无背面引用（front 的关联由调用方随后收敛）。
static func _apply_default_render(render: Dictionary, pivot: Dictionary) -> void:
	render["mode"] = Catalog.RENDER_MODE_FULL
	render["crop"] = null
	render["pivot"] = {"x": float(pivot["x"]), "y": float(pivot["y"])}
	render["scale"] = ASSET_SCALE
	render["footprint"] = {"w": int(FOOTPRINT["w"]), "h": int(FOOTPRINT["h"])}
	render["back_mode"] = Catalog.BACK_MODE_SINGLE
	render["back_asset_id"] = ""
	render["ground_width_px"] = GROUND_WIDTH_PX
