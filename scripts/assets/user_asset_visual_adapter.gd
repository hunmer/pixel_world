## assets/user_asset_visual_adapter.gd — 用户素材视觉适配器
##
## 职责：把素材库描述符（descriptor）+ 位图烘焙成渲染层可直接使用的「视觉块」：
##   visual = { texture: ImageTexture, render_offset: Vector2, canvas_size: Vector2,
##              asset_id: String, kind: String, missing: bool }
## 烘焙规则（预览与战场落地同一条路径，保证所见即所得）：
##   render.crop  → 先按 Rect2i 裁切原图（mode="crop" 时生效）
##   render.scale → 非 1 时最近邻 resize（像素风不插值）
##   render.pivot → render_offset = (W*(0.5-pivot.x), H*(0.5-pivot.y))，W/H 为烘焙后画布尺寸
##                  （与 battlefield_renderer._prop_for 的底缘对齐公式一致：满图 pivot=(0.5,1) → offset=(0,-H/2)）
##
## resolve(asset_id)：离线只读磁盘库（root/library.json + blobs），不做网络请求；
##   缺图（blob 未下载/素材被隐藏删除）返回程序生成的灰紫占位（missing=true），引用不丢失。
##
## 实例级 LRU 缓存（默认 64 条）；编辑器/战斗场景各持一个实例即可。

class_name UserAssetVisualAdapter
extends RefCounted

const Catalog := preload("res://scripts/assets/user_asset_catalog.gd")
const ServiceScript := preload("res://scripts/assets/user_asset_service.gd")

## blob 目录名（与 user_asset_service.gd 的内容寻址布局保持一致：<root>/blobs/<sha前2>/<sha>）
const BLOB_DIRNAME := "blobs"

## 视觉缓存上限（LRU；1455 张素材懒解析，超出淘汰最旧）
const MAX_VISUAL_CACHE := 64

## 占位图尺寸（缺图提示：灰紫底 + 亮紫边框 + 对角纹）
const PLACEHOLDER_W := 32
const PLACEHOLDER_H := 48

## 烘焙图落盘目录：<root>/baked/<id>.png——像素处理（crop/归一化/scale）只做一次，
## 之后 resolve 直接读盘；render 参数编辑后 invalidate_baked 作废重烘。源 blob 不动。
const BAKED_DIR := "baked"

## 烘焙管线版本：归一化/裁剪规则变更时 +1，使旧烘焙图自然失效重烘（文件名含版本）。
const BAKED_VERSION := 2

var root: String = "user://custom_assets"

## asset_id -> visual（LRU 缓存；missing 占位也缓存，键前缀区分）
var _cache: Dictionary = {}
var _lru: Array = []


func _init(p_root: String = "user://custom_assets") -> void:
	root = p_root


## 不透明内容包围盒 → {min_x,max_x,min_y,max_y}（含端点的像素坐标）；
## 全透明图返回 {}（调用方回退整图锚定）。
func _opaque_bounds(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.04:
				if x < min_x:
					min_x = x
				if x > max_x:
					max_x = x
				if y < min_y:
					min_y = y
				if y > max_y:
					max_y = y
	if max_x < 0:
		return {}
	return {"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y}


## 纯函数烘焙：descriptor.render（crop/scale/pivot）+ 源图 → visual。
## 不修改入参 image 与 descriptor；规则与预览/落地共用。
func build_visual(descriptor: Dictionary, image: Image) -> Dictionary:
	return _visual_from_image(descriptor, bake_image(descriptor, image))


## 像素处理主体：crop → terrain 尺寸归一化 → render.scale。返回处理后的新图（不改入参）。
func bake_image(descriptor: Dictionary, image: Image) -> Image:
	var img: Image = image
	var render: Dictionary = descriptor.get("render", {})
	if render.is_empty():
		render = Catalog.default_render()
	var mode := String(render.get("mode", Catalog.RENDER_MODE_FULL))
	# 1) 裁切（仅 crop 模式；矩形越界部分自动夹到图像内）
	if mode == Catalog.RENDER_MODE_CROP:
		var crop: Dictionary = render.get("crop", {})
		if not crop.is_empty():
			var cx := clampi(int(crop.get("x", 0)), 0, img.get_width() - 1)
			var cy := clampi(int(crop.get("y", 0)), 0, img.get_height() - 1)
			var cw := clampi(int(crop.get("w", 0)), 0, img.get_width() - cx)
			var ch := clampi(int(crop.get("h", 0)), 0, img.get_height() - cy)
			if cw > 0 and ch > 0 and (cw != img.get_width() or ch != img.get_height()):
				var cropped := Image.create(cw, ch, false, img.get_format())
				cropped.blit_rect(img, Rect2i(cx, cy, cw, ch), Vector2i.ZERO)
				img = cropped
	# 2) 尺寸归一化（仅 terrain）：F 盘整图方块约 174px 宽，直接放会比内建方块大数倍。
	# 目标盒=内建方块内容盒 32 宽 × 26 高（图集顶面 y6..22 + 侧面到 y32，见
	# isometric_column_batch.gd 的 UV 区域）；先裁到不透明内容（去透明留白——
	# 整图归一化会把底部留白的高度一起算进去，结果 32x40 比正常方块 32x26 高），
	# 再等比缩放到恰好装进 32*fw × 26*fh 盒（不拉伸变形）；render.scale 在其上再乘。
	const BLOCK_NORM_WIDTH := 32.0
	const BLOCK_NORM_HEIGHT := 26.0
	if String(descriptor.get("kind", "")) == Catalog.KIND_TERRAIN:
		var footprint: Dictionary = render.get("footprint", {})
		var fw := clampi(int(footprint.get("w", 1)), 1, 8)
		var fh := clampi(int(footprint.get("h", 1)), 1, 8)
		var content_bounds := _opaque_bounds(img)
		if not content_bounds.is_empty():
			var bx := int(content_bounds.get("min_x", 0))
			var by := int(content_bounds.get("min_y", 0))
			var bw := int(content_bounds.get("max_x", 0)) - bx + 1
			var bh := int(content_bounds.get("max_y", 0)) - by + 1
			if bw > 0 and bh > 0 and (bw != img.get_width() or bh != img.get_height()):
				var content := Image.create(bw, bh, false, img.get_format())
				content.blit_rect(img, Rect2i(bx, by, bw, bh), Vector2i.ZERO)
				img = content
		var box_w := BLOCK_NORM_WIDTH * fw
		var box_h := BLOCK_NORM_HEIGHT * fh
		var fit := minf(box_w / float(img.get_width()), box_h / float(img.get_height()))
		if absf(fit - 1.0) > 0.001:
			var nw := maxi(1, roundi(img.get_width() * fit))
			var nh := maxi(1, roundi(img.get_height() * fit))
			var normed: Image = img.duplicate()
			normed.resize(nw, nh, Image.INTERPOLATE_NEAREST)
			img = normed
	# 3) 缩放（非 1 时最近邻；duplicate 后 resize，不改入参，目标至少 1x1）
	var scale := float(render.get("scale", 1.0))
	if absf(scale - 1.0) > 0.001 and scale > 0.0:
		var tw := maxi(1, roundi(img.get_width() * scale))
		var th := maxi(1, roundi(img.get_height() * scale))
		var scaled: Image = img.duplicate()
		scaled.resize(tw, th, Image.INTERPOLATE_NEAREST)
		img = scaled
	return img


## 烘焙后的图 → visual：pivot 内容锚定偏移 + 元数据（无像素处理，纯算术）。
func _visual_from_image(descriptor: Dictionary, img: Image) -> Dictionary:
	var render: Dictionary = descriptor.get("render", {})
	if render.is_empty():
		render = Catalog.default_render()
	# 留白，按整图底缘锚会把块体顶高悬空（与渲染层内建装饰 _prop_content_bottom
	# 同思路）。pivot=(px,py) 表示锚点落在内容包围盒宽/高的 px/py 分位；
	# 全不透明图退化为旧整图公式（w*(0.5-px), h*(0.5-py)），行为完全兼容。
	var pivot: Dictionary = render.get("pivot", {})
	var px := clampf(float(pivot.get("x", 0.5)), 0.0, 1.0)
	var py := clampf(float(pivot.get("y", 1.0)), 0.0, 1.0)
	var w := float(img.get_width())
	var h := float(img.get_height())
	var bounds := _opaque_bounds(img)
	var min_x := 0.0
	var span_x := w
	var min_y := 0.0
	var span_y := h
	if bounds.has_all(["min_x", "max_x", "min_y", "max_y"]):
		min_x = float(bounds["min_x"])
		span_x = float(bounds["max_x"] - bounds["min_x"] + 1)
		min_y = float(bounds["min_y"])
		span_y = float(bounds["max_y"] - bounds["min_y"] + 1)
	var offset := Vector2(w * 0.5 - (min_x + px * span_x), h * 0.5 - (min_y + py * span_y))
	return {
		"texture": ImageTexture.create_from_image(img),
		"render_offset": offset,
		"canvas_size": Vector2(w, h),
		"asset_id": String(descriptor.get("id", "")),
		"kind": String(descriptor.get("kind", Catalog.KIND_TERRAIN)),
		"missing": false,
	}


## 解析 asset_id → visual（离线：只读 root/library.json 与 blob 文件）。
## 缺库/缺描述符/缺 blob 一律返回占位（missing=true），绝不返回空。
func resolve(asset_id: String) -> Dictionary:
	if asset_id.is_empty():
		return placeholder_visual(asset_id)
	var cache_key := "v:" + asset_id
	if _cache.has(cache_key):
		_touch(cache_key)
		return _cache[cache_key]
	var visual: Dictionary = {}
	var loaded: Dictionary = Catalog.load_library(root + "/library.json")
	if bool(loaded.get("ok", false)):
		var descriptor: Dictionary = {}
		for d in loaded["library"].get("assets", []):
			if String(d.get("id", "")) == asset_id:
				descriptor = d
				break
		if not descriptor.is_empty():
			var img := _load_baked_or_blob(descriptor)
			if img != null:
				visual = _visual_from_image(descriptor, img)
	if visual.is_empty():
		visual = placeholder_visual(asset_id)
	_put(cache_key, visual)
	return visual


## 批量解析：一次库加载解析多个 id → { id: visual }（未命中 blob 的给占位 visual）。
## 给方块页网格等高频调用方用——逐 id 调 resolve() 会重复整库 JSON 解析，
## 1455 素材规模下曾直接把地图编辑器卡死。
## p_cache=false 时不写入 LRU（网格一次灌 1455 项会把热缓存挤穿，
## 代价是这些素材之后首次放置要重新解析——放置是低频操作，可接受）。
func resolve_many(asset_ids: Array, p_cache: bool = true) -> Dictionary:
	var out := {}
	if asset_ids.is_empty():
		return out
	var descriptors := {}
	var loaded: Dictionary = Catalog.load_library(root + "/library.json")
	if bool(loaded.get("ok", false)):
		for raw in loaded["library"].get("assets", []):
			var d: Dictionary = raw
			descriptors[String(d.get("id", ""))] = d
	for raw_id in asset_ids:
		var aid := String(raw_id)
		var cache_key := "v:" + aid
		if _cache.has(cache_key):
			_touch(cache_key)
			out[aid] = _cache[cache_key]
			continue
		var visual: Dictionary = {}
		if descriptors.has(aid):
			var img := _load_baked_or_blob(descriptors[aid])
			if img != null:
				visual = _visual_from_image(descriptors[aid], img)
		if visual.is_empty():
			visual = placeholder_visual(aid)
		if p_cache:
			_put(cache_key, visual)
		out[aid] = visual
	return out


## 程序生成缺图占位（灰紫底 + 亮紫边框 + 对角纹），pivot 底中。
func placeholder_visual(asset_id: String) -> Dictionary:
	var cache_key := "p:" + asset_id
	if _cache.has(cache_key):
		_touch(cache_key)
		return _cache[cache_key]
	var img := Image.create(PLACEHOLDER_W, PLACEHOLDER_H, false, Image.FORMAT_RGBA8)
	var base := Color(0.32, 0.24, 0.42, 1.0)
	var edge := Color(0.72, 0.56, 0.88, 1.0)
	img.fill(base)
	for x in range(PLACEHOLDER_W):
		img.set_pixel(x, 0, edge)
		img.set_pixel(x, PLACEHOLDER_H - 1, edge)
		var d := (x * PLACEHOLDER_H) / PLACEHOLDER_W
		img.set_pixel(x, clampi(d, 0, PLACEHOLDER_H - 1), edge)
	for y in range(PLACEHOLDER_H):
		img.set_pixel(0, y, edge)
		img.set_pixel(PLACEHOLDER_W - 1, y, edge)
		var d2 := (y * PLACEHOLDER_W) / PLACEHOLDER_H
		img.set_pixel(clampi(d2, 0, PLACEHOLDER_W - 1), y, edge)
	var w := float(PLACEHOLDER_W)
	var h := float(PLACEHOLDER_H)
	var visual := {
		"texture": ImageTexture.create_from_image(img),
		"render_offset": Vector2(0.0, -h * 0.5),
		"canvas_size": Vector2(w, h),
		"asset_id": asset_id,
		"kind": "",
		"missing": true,
	}
	_put(cache_key, visual)
	return visual


## 把 chapter.props（asset_id 条目）与 tile_overrides 翻译成渲染层条目列表：
##   [{ x:int, y:int, layer:"prop"|"tile", visual:Dictionary }]
## 坏条目（坐标非法/asset_id 空）直接跳过。
func visual_for_entries(props: Array, tile_overrides: Dictionary) -> Array:
	var out: Array = []
	for p in props:
		if not (p is Dictionary):
			continue
		var aid := String(p.get("asset_id", ""))
		if aid.is_empty():
			continue  # texture 条目走 renderer 原 _custom_props 通道
		var cell := Vector2i(int(p.get("x", -1)), int(p.get("y", -1)))
		if cell.x < 0 or cell.y < 0:
			continue
		out.append({ "x": cell.x, "y": cell.y, "layer": "prop", "visual": resolve(aid) })
	for key in tile_overrides.keys():
		var entry: Dictionary = tile_overrides[key] if tile_overrides[key] is Dictionary else {}
		var aid := String(entry.get("asset_id", ""))
		if aid.is_empty():
			continue
		var parts := String(key).split(",")
		if parts.size() != 2:
			continue
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		if cell.x < 0 or cell.y < 0:
			continue
		out.append({ "x": cell.x, "y": cell.y, "layer": "tile", "visual": resolve(aid) })
	return out


## 当前缓存条目数（测试用）
func cache_size() -> int:
	return _cache.size()


## 清缓存：asset_id 非空只清该素材（含占位条目）；空串清全部。
## 库内容变化（导入/隐藏/render 参数编辑）后由调用方触发，避免读到旧烘焙结果。
func clear_cache(asset_id: String = "") -> void:
	if asset_id.is_empty():
		_cache.clear()
		_lru.clear()
		return
	for key in ["v:" + asset_id, "p:" + asset_id]:
		_cache.erase(key)
		_lru.erase(key)


func _load_blob_image(sha: String) -> Image:
	if sha.length() != 64:
		return null
	var path := _blob_path(sha)
	if not FileAccess.file_exists(path):
		return null
	# blob 为无扩展名内容寻址文件，load_from_file 按扩展名识别会失败（ERR_FILE_UNRECOGNIZED），
	# 必须读字节后走魔数解码（png/jpg/webp），与导入路径同一条解码链。
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if ServiceScript.decode_image_bytes(bytes, img).is_empty():
		return null
	return img


func _blob_path(sha: String) -> String:
	return root + "/" + BLOB_DIRNAME + "/" + sha.substr(0, 2) + "/" + sha


## 烘焙图路径：<root>/baked/<id>.png。烘焙图 = crop/归一化/scale 已完成的像素结果，
## resolve 优先读它（免重复像素处理）；源 blob 永不被修改（原图保全）。
func baked_path_for(asset_id: String) -> String:
	return root + "/" + BAKED_DIR + "/" + asset_id + ".v" + str(BAKED_VERSION) + ".png"


## render 参数（mode/crop/pivot/scale/footprint）被编辑后调用：删烘焙图，下次 resolve 重烘。
func invalidate_baked(asset_id: String) -> void:
	var path := baked_path_for(asset_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## 优先读烘焙图（零像素处理）；没有则读 blob 现场烘焙并落盘（下次直接读盘）。
func _load_baked_or_blob(descriptor: Dictionary) -> Image:
	var baked_path := baked_path_for(String(descriptor.get("id", "")))
	if FileAccess.file_exists(baked_path):
		var baked := Image.new()
		if baked.load(baked_path) == OK:
			return baked
	var img := _load_blob_image(String(descriptor.get("sha256", "")))
	if img == null:
		return null
	img = bake_image(descriptor, img)
	DirAccess.make_dir_recursive_absolute(root + "/" + BAKED_DIR)
	img.save_png(baked_path)  # 写盘失败无害：下次 resolve 重烘
	return img


func _touch(key: String) -> void:
	var idx := _lru.find(key)
	if idx >= 0:
		_lru.remove_at(idx)
		_lru.append(key)


func _put(key: String, visual: Dictionary) -> void:
	_cache[key] = visual
	_lru.append(key)
	while _lru.size() > MAX_VISUAL_CACHE:
		var oldest: String = _lru.pop_front()
		_cache.erase(oldest)
