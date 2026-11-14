## user_asset_catalog.gd — 用户自定义素材库：v1 描述符 schema 与库 JSON 持久化
##
## 纯数据层（全 static，不依赖 Node / 网络 / 纹理）。职责：
## 1. 定义素材描述符字段：id / kind / name / tags / image / sha256 / bytes /
##    width / height / render（mode/crop/pivot/scale/footprint）。
##    「元数据先行」：sha256 / bytes / width / height 允许未知（空串 / 0），
##    图片拉取成功后由服务层回填；稳定 id 与显示名、路径严格分离。
## 2. 库文件结构（version / settings / assets）解析、逐条校验、整型字段归一化
##    （JSON 数字一律 parse 成 float，加载时转回 int，保证 round-trip 稳定）。
## 3. 原子保存：写 .tmp → 回读验证 → 旧库转 .bak → rename 落位；
##    主文件损坏/校验失败时 load 自动回退 .bak，失败保留上一份有效库。
## 4. blob 存储约定：内容寻址，路径由 sha256 派生（blobs/<sha前2位>/<sha>，
##    无扩展名，解码按魔数判断格式），描述符不落任何文件路径，杜绝路径穿越。

class_name UserAssetCatalog
extends RefCounted

const SCHEMA_VERSION := 1

const KIND_TERRAIN := "terrain"
const KIND_PLANT := "plant"
const KINDS: PackedStringArray = [KIND_TERRAIN, KIND_PLANT]

const RENDER_MODE_FULL := "full"
const RENDER_MODE_CROP := "crop"
const RENDER_MODES: PackedStringArray = [RENDER_MODE_FULL, RENDER_MODE_CROP]

## 单图字节上限（网络与本地导入共用防御；服务层可收紧不可放宽）
const MAX_IMAGE_BYTES := 32 * 1024 * 1024
## 单边像素上限（防超大分辨率解码耗尽内存）
const MAX_SIDE_PIXELS := 8192

const BACKUP_SUFFIX := ".bak"
const TEMP_SUFFIX := ".tmp"


## 渲染元数据默认值：整图、底部中心锚点、原始比例、占 1 逻辑格。
static func default_render() -> Dictionary:
	return {
		"mode": RENDER_MODE_FULL,
		"crop": null,
		"pivot": {"x": 0.5, "y": 1.0},
		"scale": 1.0,
		"footprint": {"w": 1, "h": 1},
	}


## 构建一份 v1 描述符（render 缺省时补默认值）。
static func make_descriptor(id: String, kind: String, name: String,
		tags: Array, image: String, sha256: String, bytes: int,
		width: int, height: int, render: Dictionary = {}) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"name": name,
		"tags": tags.duplicate(),
		"image": image,
		"sha256": sha256,
		"bytes": bytes,
		"width": width,
		"height": height,
		"render": render if not render.is_empty() else default_render(),
	}


## 校验单个描述符，返回错误列表（空 = 通过）。ctx 用于错误消息定位。
## max_bytes 可由服务层收紧（测试 / 小图源）；无法放宽超过 MAX_IMAGE_BYTES。
static func validate_descriptor(d: Dictionary, ctx: String,
		max_bytes: int = MAX_IMAGE_BYTES) -> Array[String]:
	var errors: Array[String] = []
	var cap: int = clampi(max_bytes, 1, MAX_IMAGE_BYTES)
	var asset_id := str(d.get("id", "?"))

	var raw_id: Variant = d.get("id", null)
	if not (raw_id is String) or (raw_id as String).is_empty():
		errors.append("%s: id 必须是非空字符串" % ctx)
	elif not _is_valid_id(raw_id as String):
		errors.append("%s: id 非法（小写字母数字开头，仅含 a-z0-9_.-，≤64 字符）: %s" % [ctx, raw_id])

	var kind := str(d.get("kind", ""))
	if not KINDS.has(kind):
		errors.append("%s(%s): kind 必须是 %s 之一，实际 %s" % [ctx, asset_id, "/".join(KINDS), kind])

	var raw_name: Variant = d.get("name", null)
	if not (raw_name is String) or (raw_name as String).is_empty():
		errors.append("%s(%s): name 必须是非空字符串" % [ctx, asset_id])

	var raw_tags: Variant = d.get("tags", null)
	if not (raw_tags is Array):
		errors.append("%s(%s): tags 必须是数组" % [ctx, asset_id])
	else:
		for t in (raw_tags as Array):
			if not (t is String):
				errors.append("%s(%s): tags 含非字符串元素 %s" % [ctx, asset_id, str(t)])

	var raw_image: Variant = d.get("image", null)
	if not (raw_image is String) or (raw_image as String).is_empty():
		errors.append("%s(%s): image 必须是非空字符串（源 URL 或源文件名）" % [ctx, asset_id])

	var raw_sha: Variant = d.get("sha256", "")
	if not (raw_sha is String):
		errors.append("%s(%s): sha256 必须是字符串" % [ctx, asset_id])
	else:
		var sha := raw_sha as String
		if not sha.is_empty() and not _is_valid_sha256(sha):
			errors.append("%s(%s): sha256 非法（64 位小写十六进制或空表示未知）: %s" % [ctx, asset_id, sha.substr(0, 20)])

	var byte_count := int(d.get("bytes", 0))
	if byte_count < 0 or byte_count > cap:
		errors.append("%s(%s): bytes 越界（0=未知 或 1..%d），实际 %d" % [ctx, asset_id, cap, byte_count])

	var w := int(d.get("width", 0))
	var h := int(d.get("height", 0))
	if w < 0 or h < 0 or w > MAX_SIDE_PIXELS or h > MAX_SIDE_PIXELS:
		errors.append("%s(%s): width/height 越界（0=未知 或 1..%d），实际 %dx%d" % [ctx, asset_id, MAX_SIDE_PIXELS, w, h])
	if (w == 0) != (h == 0):
		errors.append("%s(%s): width/height 必须同时已知或同时未知（%dx%d）" % [ctx, asset_id, w, h])

	if d.has("saved") and typeof(d["saved"]) != TYPE_BOOL:
		errors.append("%s(%s): saved 必须是布尔值（用户保存标记）" % [ctx, asset_id])
	errors.append_array(_validate_render(d.get("render", null), "%s(%s)" % [ctx, asset_id], w, h))
	return errors


## 渲染元数据契约校验：mode ∈ full|crop；crop 仅 crop 模式生效且须为图内有效矩形；
## pivot 归一化 0-1；scale ∈ (0,16]；footprint 为 1..8 的整数格（占地）。
static func _validate_render(render: Variant, ctx: String, img_w: int, img_h: int) -> Array[String]:
	var errors: Array[String] = []
	if not (render is Dictionary):
		return ["%s: render 必须是对象" % ctx]
	var r: Dictionary = render
	var mode := str(r.get("mode", ""))
	if not RENDER_MODES.has(mode):
		errors.append("%s: render.mode 必须是 full|crop，实际 %s" % [ctx, mode])

	var crop: Variant = r.get("crop", null)
	if crop != null:
		if not (crop is Dictionary):
			errors.append("%s: render.crop 必须是对象或 null" % ctx)
		else:
			var c: Dictionary = crop
			var x := int(c.get("x", -1))
			var y := int(c.get("y", -1))
			var cw := int(c.get("w", 0))
			var ch := int(c.get("h", 0))
			if x < 0 or y < 0 or cw <= 0 or ch <= 0:
				errors.append("%s: render.crop 矩形非法（x,y≥0 且 w,h>0），实际 %d,%d %dx%d" % [ctx, x, y, cw, ch])
			elif img_w > 0 and img_h > 0 and (x + cw > img_w or y + ch > img_h):
				errors.append("%s: render.crop 超出图像范围 %dx%d" % [ctx, img_w, img_h])
		if mode == RENDER_MODE_FULL:
			errors.append("%s: render.mode=full 时 crop 必须为 null" % ctx)
	elif mode == RENDER_MODE_CROP:
		errors.append("%s: render.mode=crop 时 crop 必须是有效矩形" % ctx)

	var pivot: Variant = r.get("pivot", null)
	if not (pivot is Dictionary):
		errors.append("%s: render.pivot 必须是 {x,y} 对象" % ctx)
	else:
		var px := float((pivot as Dictionary).get("x", -1.0))
		var py := float((pivot as Dictionary).get("y", -1.0))
		if px < 0.0 or px > 1.0 or py < 0.0 or py > 1.0:
			errors.append("%s: render.pivot 必须归一化到 [0,1]，实际 (%.3f,%.3f)" % [ctx, px, py])

	var scale := float(r.get("scale", 0.0))
	if scale <= 0.0 or scale > 16.0:
		errors.append("%s: render.scale 必须在 (0,16]，实际 %.3f" % [ctx, scale])

	var fp: Variant = r.get("footprint", null)
	if not (fp is Dictionary):
		errors.append("%s: render.footprint 必须是 {w,h} 对象" % ctx)
	else:
		var fw := int((fp as Dictionary).get("w", 0))
		var fh := int((fp as Dictionary).get("h", 0))
		if fw < 1 or fh < 1 or fw > 8 or fh > 8:
			errors.append("%s: render.footprint 必须是 1..8 的整数格，实际 %dx%d" % [ctx, fw, fh])
	return errors


## 空库骨架（source_url 放库内 settings 段，独立于全局 settings.cfg）。
static func default_library(source_url: String) -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"updated_ms": 0,
		"settings": {"source_url": source_url},
		"assets": [],
	}


## 解析库 JSON 文本 → {ok, library, errors}。成功时 library 为归一化后的规范库。
## version 超前拒绝加载（防止半加载新版本数据）；逐条校验任一失败整体拒绝。
static func parse_library_text(text: String) -> Dictionary:
	var errors: Array[String] = []
	var parser := JSON.new()
	var err := parser.parse(text)
	if err != OK:
		return {"ok": false, "library": {},
			"errors": ["库 JSON 解析失败（行 %d）: %s" % [parser.get_error_line(), parser.get_error_message()]]}
	var parsed: Variant = parser.data
	if not (parsed is Dictionary):
		return {"ok": false, "library": {}, "errors": ["库 JSON 根必须是对象"]}

	var raw: Dictionary = parsed
	var version := int(raw.get("version", 0))
	if version <= 0:
		errors.append("库缺有效 version 字段")
	elif version > SCHEMA_VERSION:
		errors.append("库版本 %d 超过当前支持的 %d（来自更新构建，拒绝加载）" % [version, SCHEMA_VERSION])

	var settings_raw: Variant = raw.get("settings", {})
	if not (settings_raw is Dictionary):
		errors.append("settings 必须是对象")
		settings_raw = {}
	var source_url := str((settings_raw as Dictionary).get("source_url", ""))

	var assets_raw: Variant = raw.get("assets", [])
	if not (assets_raw is Array):
		errors.append("assets 必须是数组")
		assets_raw = []

	var assets: Array = []
	var seen_ids := {}
	for i in (assets_raw as Array).size():
		var entry: Variant = (assets_raw as Array)[i]
		var ctx := "assets[%d]" % i
		if not (entry is Dictionary):
			errors.append("%s: 条目必须是对象" % ctx)
			continue
		var d: Dictionary = entry
		var asset_errors := validate_descriptor(d, ctx)
		if not asset_errors.is_empty():
			errors.append_array(asset_errors)
			continue
		var asset_id := str(d["id"])
		if seen_ids.has(asset_id):
			errors.append("assets 内 id 重复: %s" % asset_id)
			continue
		seen_ids[asset_id] = true
		assets.append(_normalize_descriptor(d))

	if not errors.is_empty():
		return {"ok": false, "library": {}, "errors": errors}

	var library := default_library(source_url)
	library["updated_ms"] = int(raw.get("updated_ms", 0))
	library["assets"] = assets
	return {"ok": true, "library": library, "errors": []}


## 整型/浮点字段归一化：JSON 数字 parse 后全是 float，此处转回 int/float，
## 保证保存 round-trip 后字节级稳定（138.0 → 138）。
static func _normalize_descriptor(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	out["bytes"] = int(d.get("bytes", 0))
	out["width"] = int(d.get("width", 0))
	out["height"] = int(d.get("height", 0))
	var tags: Array = []
	for t in (d.get("tags", []) as Array):
		tags.append(str(t))
	out["tags"] = tags
	var render: Dictionary = (d.get("render", {}) as Dictionary).duplicate(true)
	var crop: Variant = render.get("crop", null)
	if crop is Dictionary:
		var c: Dictionary = (crop as Dictionary).duplicate()
		c["x"] = int(c.get("x", 0))
		c["y"] = int(c.get("y", 0))
		c["w"] = int(c.get("w", 0))
		c["h"] = int(c.get("h", 0))
		render["crop"] = c
	var pivot: Dictionary = render.get("pivot", {})
	render["pivot"] = {"x": float(pivot.get("x", 0.5)), "y": float(pivot.get("y", 1.0))}
	render["scale"] = float(render.get("scale", 1.0))
	var fp: Dictionary = render.get("footprint", {})
	render["footprint"] = {"w": int(fp.get("w", 1)), "h": int(fp.get("h", 1))}
	out["render"] = render
	return out


## 加载库文件：主文件 → .bak 回退。返回 {ok, library, error, used_backup}。
## 两者都不可用返回 ok=false（调用方落回默认空库），不抛引擎错误。
static func load_library(path: String) -> Dictionary:
	var primary_error := "库文件不存在: %s" % path
	if FileAccess.file_exists(path):
		var res := parse_library_text(FileAccess.get_file_as_string(path))
		if bool(res["ok"]):
			return {"ok": true, "library": res["library"], "error": "", "used_backup": false}
		primary_error = _join_errors(res["errors"])
	if FileAccess.file_exists(path + BACKUP_SUFFIX):
		var bak := parse_library_text(FileAccess.get_file_as_string(path + BACKUP_SUFFIX))
		if bool(bak["ok"]):
			return {"ok": true, "library": bak["library"], "error": "", "used_backup": true}
		return {"ok": false, "library": {},
			"error": "主库无效: %s；.bak 也无效: %s" % [primary_error, _join_errors(bak["errors"])],
			"used_backup": true}
	return {"ok": false, "library": {}, "error": primary_error, "used_backup": false}


## 原子保存：tmp 写入 → 回读验证 → 旧库转 .bak → rename 落位。
## 任一步失败保留原库不动（tmp 清理），返回 {ok, error}。
static func save_library(path: String, library: Dictionary) -> Dictionary:
	var to_write := library.duplicate(true)
	to_write["updated_ms"] = now_ms()
	var parse_check := parse_library_text(JSON.stringify(to_write))
	if not bool(parse_check["ok"]):
		return {"ok": false, "error": "待保存库未通过自校验: %s" % _join_errors(parse_check["errors"])}

	var text := JSON.stringify(to_write, "\t")
	var tmp_path := path + TEMP_SUFFIX
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "无法写临时文件 %s (err=%d)" % [tmp_path, FileAccess.get_open_error()]}
	f.store_string(text)
	f.close()

	# 回读验证：确认落盘内容可解析且结构一致（防截断写）。
	var reread := parse_library_text(FileAccess.get_file_as_string(tmp_path))
	if not bool(reread["ok"]):
		DirAccess.remove_absolute(tmp_path)
		return {"ok": false, "error": "临时文件回读校验失败，已保留原库"}

	var had_old := FileAccess.file_exists(path)
	if had_old:
		var bak_err := DirAccess.rename_absolute(path, path + BACKUP_SUFFIX)
		if bak_err != OK:
			DirAccess.remove_absolute(tmp_path)
			return {"ok": false, "error": "旧库转 .bak 失败 (err=%d)，已保留原库" % bak_err}
	var rename_err := DirAccess.rename_absolute(tmp_path, path)
	if rename_err != OK:
		if had_old:
			DirAccess.rename_absolute(path + BACKUP_SUFFIX, path)  # 尽力恢复
		DirAccess.remove_absolute(tmp_path)
		return {"ok": false, "error": "临时文件落位失败 (err=%d)，已尽力恢复原库" % rename_err}
	return {"ok": true, "error": ""}


static func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## id 规则：小写字母/数字开头，仅 a-z 0-9 _ . -，长度 1..64。
static func _is_valid_id(id: String) -> bool:
	if id.length() < 1 or id.length() > 64:
		return false
	for i in id.length():
		var c := id.substr(i, 1)
		if _is_lower_alnum(c):
			continue
		if i > 0 and (c == "_" or c == "." or c == "-"):
			continue
		return false
	return true


static func _is_lower_alnum(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "0" and c <= "9")


## sha256 规则：64 位小写十六进制（大写拒绝，保证内容寻址路径一致）。
static func _is_valid_sha256(sha: String) -> bool:
	if sha.length() != 64:
		return false
	return sha.is_valid_hex_number(false) and sha.to_lower() == sha


static func _join_errors(errors: Array) -> String:
	var parts := PackedStringArray()
	for e in errors:
		parts.append(str(e))
	return " ; ".join(parts)
