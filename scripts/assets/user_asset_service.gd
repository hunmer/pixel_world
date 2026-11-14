## user_asset_service.gd — 用户自定义素材服务：本地导入 + 网络清单/图片按需加载
##
## 由场景持有（如地图编辑器面板）或注入，非 autoload。职责：
## 1. 本地导入：PNG/JPG/WebP 字节校验（魔数 + 解码）、sha256 内容寻址缓存到
##    user://custom_assets/blobs/<sha前2>/<sha>（无扩展名，按魔数解码，不依赖
##    .import）、同内容去重（重复导入返回既有 id）、原图字节原样保留。
## 2. 网络加载：HTTPRequest 拉清单（blocks.json）与图片按需下载；来源仅限
##    http(s)；同请求去重、有限并发、超时与有限重试、字节上限与（声明时）哈希
##    校验；断网时已缓存 blob 仍可离线取纹理。
## 3. 纹理：Image 运行时解码 → ImageTexture，LRU 有界缓存（默认 64 张），
##    绝不一次性解码整库（1455 张清单只存元数据）。
## 4. 状态：get_asset_state 表达 missing / pending / ready，供 UI 阶段复用；
##    remove_asset 默认保留 blob（地图或历史快照仍可能引用）。
##
## 信号驱动异步；所有持久化走 UserAssetCatalog 的原子保存（tmp → bak → rename）。

class_name UserAssetService
extends Node

## 用 preload 引用而非裸类名，避免 headless --script 模式下全局类缓存过期时解析失败
const Catalog := preload("res://scripts/assets/user_asset_catalog.gd")

signal manifest_loaded(result: Dictionary)  ## {ok, added, updated, total, error}
signal asset_ready(asset_id: String)        ## 图片就绪（blob 已落盘可取纹理）
signal asset_failed(asset_id: String, error: String)
signal source_changed(url: String)

const DEFAULT_SOURCE_URL := "http://127.0.0.1:8076/blocks.json"
const MAX_CONCURRENT_REQUESTS := 3
const MAX_TEXTURE_CACHE := 64
const REQUEST_TIMEOUT_SEC := 10.0
const MAX_RETRIES := 2
const BLOB_DIRNAME := "blobs"

var root_dir: String
var library_path: String
var library: Dictionary

## 运行参数（测试可覆盖；max_image_bytes 只能收紧，catalog 层夹紧上限）
var max_concurrent_requests := MAX_CONCURRENT_REQUESTS
var max_texture_cache := MAX_TEXTURE_CACHE
var request_timeout := REQUEST_TIMEOUT_SEC
var max_retries := MAX_RETRIES
var max_image_bytes := Catalog.MAX_IMAGE_BYTES

var _queue: Array[Dictionary] = []      ## 待发请求 {kind: manifest|image, url, asset_id}
var _inflight: Array[Dictionary] = []   ## 在途请求 {req, kind, url, asset_id, attempts}
var _manifest_pending := false          ## 清单请求去重（queued 或 inflight）
var _pending_assets := {}               ## asset_id -> true（queued 或 inflight 的图片请求）
var _textures := {}                     ## asset_id -> Texture2D（LRU 缓存）
var _texture_lru: Array[String] = []


func _init(custom_root: String = "user://custom_assets") -> void:
	root_dir = custom_root
	library_path = root_dir + "/library.json"
	library = Catalog.default_library(DEFAULT_SOURCE_URL)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(blob_root())
	var res := Catalog.load_library(library_path)
	if bool(res["ok"]):
		library = res["library"]
	elif FileAccess.file_exists(library_path) or FileAccess.file_exists(library_path + Catalog.BACKUP_SUFFIX):
		push_warning("[UserAsset] 库文件无效，暂用内存默认库（磁盘文件保留未动）: %s" % res["error"])


func _exit_tree() -> void:
	for rec in _inflight:
		var req: HTTPRequest = rec.get("req")
		if req != null and is_instance_valid(req):
			req.cancel_request()
			req.queue_free()
	_inflight.clear()
	_queue.clear()
	_pending_assets.clear()
	_manifest_pending = false


# ---------------------------------------------------------------------------
# 源设置（库内 settings 段持久化，独立于全局 settings.cfg）
# ---------------------------------------------------------------------------

func get_source_url() -> String:
	return str((library["settings"] as Dictionary).get("source_url", DEFAULT_SOURCE_URL))


## 设置清单源 URL。仅接受 http(s)，拒绝 file:// 与裸路径；持久化失败回滚。
func set_source_url(url: String) -> Dictionary:
	if not is_http_url(url):
		return {"ok": false, "error": "source_url_must_be_http_s: %s" % url}
	var settings: Dictionary = library["settings"]
	var old := str(settings.get("source_url", ""))
	if old == url:
		return {"ok": true, "changed": false}
	settings["source_url"] = url
	var save_res := save_library()
	if not bool(save_res["ok"]):
		settings["source_url"] = old
		return {"ok": false, "error": str(save_res["error"])}
	source_changed.emit(url)
	return {"ok": true, "changed": true}


func save_library() -> Dictionary:
	return Catalog.save_library(library_path, library)


# ---------------------------------------------------------------------------
# 本地导入（同步）
# ---------------------------------------------------------------------------

## 从本地文件导入（FileDialog 选中路径）。返回 {ok, asset_id, deduped, error, ...}。
func import_local_file(src_path: String, kind: String = Catalog.KIND_TERRAIN,
		extra_tags: PackedStringArray = [], display_name: String = "") -> Dictionary:
	if not FileAccess.file_exists(src_path):
		return {"ok": false, "error": "file_not_found: %s" % src_path}
	return import_image_bytes(FileAccess.get_file_as_bytes(src_path),
		src_path.get_file(), kind, extra_tags, display_name)


## 核心导入：校验 → 哈希 → 去重 → 写 blob → 入库。失败不产生任何半成品状态。
func import_image_bytes(bytes: PackedByteArray, source_name: String,
		kind: String = Catalog.KIND_TERRAIN, extra_tags: PackedStringArray = [],
		display_name: String = "") -> Dictionary:
	if bytes.is_empty():
		return {"ok": false, "error": "empty_content"}
	if bytes.size() > max_image_bytes:
		return {"ok": false, "error": "image_too_large: %d > %d" % [bytes.size(), max_image_bytes]}
	var img := Image.new()
	var fmt := decode_image_bytes(bytes, img)
	if fmt.is_empty():
		return {"ok": false, "error": "unsupported_or_corrupt_image"}
	if img.get_width() > Catalog.MAX_SIDE_PIXELS or img.get_height() > Catalog.MAX_SIDE_PIXELS:
		return {"ok": false, "error": "image_dimensions_exceed: %dx%d" % [img.get_width(), img.get_height()]}

	var sha := compute_sha256_hex(bytes)
	var existing: Variant = find_by_sha(sha)
	if existing is Dictionary:
		return {"ok": true, "asset_id": str(existing["id"]), "deduped": true,
			"sha256": sha, "width": int(existing["width"]), "height": int(existing["height"])}

	var blob_path := blob_path_for_sha(sha)
	var write_err := _write_blob(blob_path, bytes)
	if not write_err.is_empty():
		return {"ok": false, "error": "blob_write_failed: %s" % write_err}

	var stem := source_name.get_file().get_basename()
	var asset_id := slugify(stem)
	if find_by_id(asset_id) is Dictionary:
		asset_id = (asset_id.substr(0, 56) + "-" + sha.substr(0, 6))
	var tags: Array = [stem_prefix(source_name.get_file())]
	for t in extra_tags:
		var ts := String(t)
		if not tags.has(ts):
			tags.append(ts)

	var descriptor := Catalog.make_descriptor(asset_id, kind,
		display_name if not display_name.is_empty() else stem,
		tags, source_name.get_file(), sha, bytes.size(),
		img.get_width(), img.get_height())
	# 本地导入的素材 blob 即唯一副本，天然属于「用户保存」范畴
	descriptor["saved"] = true
	var validate_errors := Catalog.validate_descriptor(descriptor, "import(%s)" % source_name, max_image_bytes)
	if not validate_errors.is_empty():
		DirAccess.remove_absolute(blob_path)
		return {"ok": false, "error": " ; ".join(PackedStringArray(validate_errors))}

	(library["assets"] as Array).append(descriptor)
	var save_res := save_library()
	if not bool(save_res["ok"]):
		(library["assets"] as Array).erase(descriptor)
		return {"ok": false, "error": "library_save_failed: %s" % save_res["error"]}
	asset_ready.emit(asset_id)
	return {"ok": true, "asset_id": asset_id, "deduped": false, "sha256": sha,
		"width": img.get_width(), "height": img.get_height(), "format": fmt}


# ---------------------------------------------------------------------------
# 网络加载（异步，信号驱动）
# ---------------------------------------------------------------------------

## 拉取清单（默认源 blocks.json）。在途/排队中重复调用直接去重返回。
## 完成后 emit manifest_loaded({ok, added, updated, total, error})。
func request_manifest() -> Dictionary:
	if _manifest_pending:
		return {"ok": true, "queued": true, "deduped": true}
	var url := get_source_url()
	if not is_http_url(url):
		return {"ok": false, "error": "source_url_not_http: %s" % url}
	_manifest_pending = true
	_queue.append({"kind": "manifest", "url": url})
	_pump()
	return {"ok": true, "queued": true}


## 按需拉取某素材图片。blob 已在 → 立即 emit asset_ready；在途 → 去重；
## 否则入队下载，完成后 emit asset_ready / asset_failed。
func request_asset_image(asset_id: String) -> Dictionary:
	var d: Variant = find_by_id(asset_id)
	if not (d is Dictionary):
		return {"ok": false, "error": "unknown_asset: %s" % asset_id}
	if has_blob(d):
		asset_ready.emit(asset_id)
		return {"ok": true, "ready": true, "queued": false}
	if _pending_assets.has(asset_id):
		return {"ok": true, "ready": false, "queued": true, "deduped": true}
	var url := str(d["image"])
	if not is_http_url(url):
		return {"ok": false, "error": "asset_image_source_not_http: %s" % url}
	_pending_assets[asset_id] = true
	_queue.append({"kind": "image", "url": url, "asset_id": asset_id})
	_pump()
	return {"ok": true, "ready": false, "queued": true}


# ---------------------------------------------------------------------------
# 查询 / 纹理 / 移除
# ---------------------------------------------------------------------------

func asset_count() -> int:
	return (library["assets"] as Array).size()


func list_assets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in library["assets"]:
		out.append(d)
	return out


func find_by_id(asset_id: String) -> Variant:
	for d in library["assets"]:
		if str(d["id"]) == asset_id:
			return d
	return null


func find_by_sha(sha256: String) -> Variant:
	for d in library["assets"]:
		if str(d.get("sha256", "")) == sha256:
			return d
	return null


## 素材状态：unknown（不在库）/ missing（无 blob 且不在途）/ pending（拉取中）/
## ready（blob 已缓存，断网也可用）。cached_texture 表示纹理已解码在 LRU 中。
func get_asset_state(asset_id: String) -> Dictionary:
	var d: Variant = find_by_id(asset_id)
	if not (d is Dictionary):
		return {"status": "unknown", "has_blob": false, "cached_texture": false, "descriptor": {}}
	var ready := has_blob(d)
	var status := "missing"
	if ready:
		status = "ready"
	elif _pending_assets.has(asset_id):
		status = "pending"
	return {"status": status, "has_blob": ready,
		"cached_texture": _textures.has(asset_id), "descriptor": d}


## 取纹理（懒解码 + LRU）。无 blob 或解码失败返回 null；返回 null 不代表坏库，
## 调用方可配合 request_asset_image 补图。
func get_texture(asset_id: String) -> Texture2D:
	if _textures.has(asset_id):
		_touch_lru(asset_id)
		return _textures[asset_id]
	var d: Variant = find_by_id(asset_id)
	if not (d is Dictionary):
		return null
	var sha := str(d.get("sha256", ""))
	if sha.is_empty():
		return null
	var blob_path := blob_path_for_sha(sha)
	if not FileAccess.file_exists(blob_path):
		return null
	var img := Image.new()
	if decode_image_bytes(FileAccess.get_file_as_bytes(blob_path), img).is_empty():
		return null
	var tex := ImageTexture.create_from_image(img)
	_put_lru(asset_id, tex)
	return tex


## 从库移除描述符。默认保留 blob（keep_blob=true，地图/历史快照仍引用时安全）；
## keep_blob=false 仅当无其他描述符共享该 sha 时才删文件。
func remove_asset(asset_id: String, keep_blob: bool = true) -> Dictionary:
	var idx := _index_of_id(asset_id)
	if idx < 0:
		return {"ok": false, "error": "unknown_asset: %s" % asset_id}
	var d: Dictionary = (library["assets"] as Array)[idx]
	(library["assets"] as Array).remove_at(idx)
	_textures.erase(asset_id)
	_texture_lru.erase(asset_id)
	_pending_assets.erase(asset_id)
	var removed_blob := false
	if not keep_blob:
		var sha := str(d.get("sha256", ""))
		if not sha.is_empty() and not (find_by_sha(sha) is Dictionary):
			removed_blob = DirAccess.remove_absolute(blob_path_for_sha(sha)) == OK
	var save_res := save_library()
	if not bool(save_res["ok"]):
		return {"ok": false, "error": "library_save_failed: %s" % save_res["error"], "removed_blob": removed_blob}
	return {"ok": true, "error": "", "removed_blob": removed_blob}


## 更新素材的用户可编辑字段（白名单：name / kind / tags / render）。
## 合并后过 Catalog.validate_descriptor 全量校验；校验或保存失败回滚库内副本。
## 不改 id / image / sha256 / bytes / width / height（内容与寻址字段不可编辑）。
## 返回 {ok, error, descriptor?}。
func update_asset(asset_id: String, changes: Dictionary) -> Dictionary:
	var idx := _index_of_id(asset_id)
	if idx < 0:
		return {"ok": false, "error": "unknown_asset: %s" % asset_id}
	var assets: Array = library["assets"]
	var before: Dictionary = (assets[idx] as Dictionary).duplicate(true)
	var d: Dictionary = assets[idx]
	if changes.has("name"):
		d["name"] = str(changes["name"]).strip_edges()
	if changes.has("kind"):
		d["kind"] = str(changes["kind"])
	if changes.has("tags"):
		var tags: Array = []
		for t in changes["tags"] as Array:
			tags.append(str(t))
		d["tags"] = tags
	if changes.has("render"):
		var render: Variant = changes["render"]
		if not (render is Dictionary):
			assets[idx] = before
			return {"ok": false, "error": "render_must_be_dictionary"}
		d["render"] = (render as Dictionary).duplicate(true)
	if changes.has("saved"):
		d["saved"] = bool(changes["saved"])
	var errors: Array[String] = Catalog.validate_descriptor(d, "update_asset(%s)" % asset_id, max_image_bytes)
	if not errors.is_empty():
		assets[idx] = before
		return {"ok": false, "error": "invalid_descriptor: %s" % "; ".join(errors)}
	var save_res := save_library()
	if not bool(save_res["ok"]):
		assets[idx] = before
		return {"ok": false, "error": "library_save_failed: %s" % save_res["error"]}
	return {"ok": true, "error": "", "descriptor": (d as Dictionary).duplicate(true)}


## 批量设置用户保存标记（✓）。已是指定状态的条目跳过；全部无需变更时不落盘。
## 返回 {ok, changed, error}。manifest 重跑经 _merge_net_descriptor（duplicate 全量保留旧字段）
## 不会丢 saved。
func set_assets_saved(asset_ids: Array, saved: bool) -> Dictionary:
	var pending: Array[int] = []
	for raw_id in asset_ids:
		var idx := _index_of_id(str(raw_id))
		if idx < 0:
			continue
		var d: Dictionary = library["assets"][idx]
		if bool(d.get("saved", false)) != saved:
			pending.append(idx)
	if pending.is_empty():
		return {"ok": true, "changed": 0, "error": ""}
	for idx in pending:
		(library["assets"][idx] as Dictionary)["saved"] = saved
	var save_res := save_library()
	if not bool(save_res["ok"]):
		for idx in pending:
			(library["assets"][idx] as Dictionary)["saved"] = not saved
		return {"ok": false, "changed": 0, "error": "library_save_failed: %s" % save_res["error"]}
	return {"ok": true, "changed": pending.size(), "error": ""}


# ---------------------------------------------------------------------------
# HTTP 请求调度（有限并发 + 去重 + 重试）
# ---------------------------------------------------------------------------

func _pump() -> void:
	while not _queue.is_empty() and _inflight.size() < max_concurrent_requests:
		var job: Dictionary = _queue.pop_front()
		_start_request(job)


func _start_request(job: Dictionary) -> void:
	var req := HTTPRequest.new()
	req.timeout = request_timeout
	req.use_threads = false
	req.download_chunk_size = 65536
	# 清单走固定大上限（元数据本来就该拉全）；图片按可配置上限截断。
	req.body_size_limit = Catalog.MAX_IMAGE_BYTES if job["kind"] == "manifest" else max_image_bytes
	var rec := {"req": req, "kind": job["kind"], "url": job["url"],
		"asset_id": str(job.get("asset_id", "")), "attempts": int(job.get("attempts", 0))}
	add_child(req)
	req.request_completed.connect(_on_request_completed.bind(rec))
	var err := req.request(job["url"])
	if err != OK:
		_inflight.append(rec)  # 便于统一清理路径
		_finish_inflight(rec)
		_dispatch_failure(rec, "request_error_%d" % err)
		_pump()
		return
	_inflight.append(rec)


func _on_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray, rec: Dictionary) -> void:
	## bind(rec) 的绑定参数排在信号参数之后，rec 必须是最后一个形参
	_finish_inflight(rec)
	var transport_ok := result == HTTPRequest.RESULT_SUCCESS
	var code_ok := response_code >= 200 and response_code < 300
	if transport_ok and code_ok:
		if rec["kind"] == "manifest":
			_handle_manifest_body(body)
		else:
			_handle_image_body(rec, body)
		_pump()
		return
	var retryable := result in [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE,
		HTTPRequest.RESULT_CONNECTION_ERROR, HTTPRequest.RESULT_NO_RESPONSE,
		HTTPRequest.RESULT_TIMEOUT] or response_code >= 500
	if retryable and rec["attempts"] < max_retries:
		rec["attempts"] = int(rec["attempts"]) + 1
		rec["req"] = null
		_queue.push_front(rec)
		_pump()
		return
	_dispatch_failure(rec, "http_result_%d_code_%d" % [result, response_code])
	_pump()


func _finish_inflight(rec: Dictionary) -> void:
	_inflight.erase(rec)
	var req: HTTPRequest = rec.get("req")
	if req != null and is_instance_valid(req):
		req.queue_free()
	rec["req"] = null


func _dispatch_failure(rec: Dictionary, error: String) -> void:
	if rec["kind"] == "manifest":
		_manifest_pending = false
		manifest_loaded.emit({"ok": false, "added": 0, "updated": 0,
			"total": asset_count(), "error": error})
	else:
		var asset_id := str(rec["asset_id"])
		_pending_assets.erase(asset_id)
		asset_failed.emit(asset_id, error)


func _handle_manifest_body(body: PackedByteArray) -> void:
	_manifest_pending = false
	var parser := JSON.new()
	var err := parser.parse(body.get_string_from_utf8())
	if err != OK:
		manifest_loaded.emit({"ok": false, "added": 0, "updated": 0, "total": asset_count(),
			"error": "manifest_json_invalid: line %d %s" % [parser.get_error_line(), parser.get_error_message()]})
		return
	var extracted := extract_manifest_entries(parser.data)
	if not bool(extracted["ok"]):
		manifest_loaded.emit({"ok": false, "added": 0, "updated": 0, "total": asset_count(),
			"error": "manifest_shape_unrecognized"})
		return
	var added := 0
	var updated := 0
	var manifest_url := get_source_url()
	for raw_entry in (extracted["entries"] as Array):
		if not (raw_entry is Dictionary):
			continue
		var desc := _descriptor_from_manifest_entry(raw_entry, manifest_url)
		if desc.is_empty():
			continue
		var asset_id := str(desc["id"])
		var idx := _index_of_id(asset_id)
		if idx < 0:
			(library["assets"] as Array).append(desc)
			added += 1
		else:
			var merged := _merge_net_descriptor((library["assets"] as Array)[idx], desc)
			(library["assets"] as Array)[idx] = merged["value"]
			if bool(merged["changed"]):
				updated += 1
	var save_res := save_library()
	manifest_loaded.emit({"ok": bool(save_res["ok"]), "added": added, "updated": updated,
		"total": asset_count(), "error": str(save_res["error"])})


func _handle_image_body(rec: Dictionary, body: PackedByteArray) -> void:
	var asset_id := str(rec["asset_id"])
	_pending_assets.erase(asset_id)
	var d: Variant = find_by_id(asset_id)
	if not (d is Dictionary):
		asset_failed.emit(asset_id, "asset_removed_during_fetch")
		return
	if body.is_empty() or body.size() > max_image_bytes:
		asset_failed.emit(asset_id, "body_size_invalid: %d" % body.size())
		return
	var sha := compute_sha256_hex(body)
	var expect := str(d.get("sha256", ""))
	if not expect.is_empty() and expect != sha:
		asset_failed.emit(asset_id, "sha256_mismatch")
		return
	var img := Image.new()
	if decode_image_bytes(body, img).is_empty():
		asset_failed.emit(asset_id, "image_decode_failed")
		return
	if img.get_width() > Catalog.MAX_SIDE_PIXELS or img.get_height() > Catalog.MAX_SIDE_PIXELS:
		asset_failed.emit(asset_id, "image_dimensions_exceed: %dx%d" % [img.get_width(), img.get_height()])
		return
	var blob_path := blob_path_for_sha(sha)
	if not FileAccess.file_exists(blob_path):
		var write_err := _write_blob(blob_path, body)
		if not write_err.is_empty():
			asset_failed.emit(asset_id, "blob_write_failed: %s" % write_err)
			return
	# 回填元数据（Dictionary 引用语义，直接改库内对象）
	d["sha256"] = sha
	d["bytes"] = body.size()
	d["width"] = img.get_width()
	d["height"] = img.get_height()
	var save_res := save_library()
	if not bool(save_res["ok"]):
		push_warning("[UserAsset] 图片元数据回填后库保存失败（内存已更新）: %s" % save_res["error"])
	asset_ready.emit(asset_id)


# ---------------------------------------------------------------------------
# 静态工具：URL / 哈希 / 解码 / 清单解析
# ---------------------------------------------------------------------------

static func is_http_url(url: String) -> bool:
	return url.begins_with("http://") or url.begins_with("https://")


## 内容寻址 blob 路径（纯函数版）：<root>/blobs/<sha前2>/<sha>。非法 sha 返回空串。
static func blob_path(root: String, sha: String) -> String:
	if sha.length() != 64 or not sha.is_valid_hex_number(false) or sha.to_lower() != sha:
		return ""
	return "%s/%s/%s/%s" % [root, BLOB_DIRNAME, sha.substr(0, 2), sha]


## 实例便捷版（绑定服务自身 root_dir）。
func blob_path_for_sha(sha: String) -> String:
	return blob_path(root_dir, sha)


## 归一化为小写 slug（a-z0-9 与 _），空回 "asset"，截断保 id 后缀空间。
static func slugify(text: String) -> String:
	var src := text.to_lower().strip_edges()
	var out := ""
	for i in src.length():
		var c := src.substr(i, 1)
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		else:
			out += "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	while out.begins_with("_"):
		out = out.substr(1)
	while out.ends_with("_"):
		out = out.substr(0, out.length() - 1)
	if out.is_empty():
		out = "asset"
	return out.substr(0, 56)


## 文件名前缀（第一个 `_` 之前）作为 tag；无前缀回 stem 本身。
static func stem_prefix(file_name: String) -> String:
	var stem := file_name.get_file().get_basename()
	var idx := stem.find("_")
	if idx > 0:
		return stem.substr(0, idx)
	return stem if not stem.is_empty() else "misc"


static func compute_sha256_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## 魔数检测格式：png / jpg / webp；不认识返回空串。
static func detect_image_format(bytes: PackedByteArray) -> String:
	if bytes.size() >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50 \
			and bytes[2] == 0x4E and bytes[3] == 0x47:
		return "png"
	if bytes.size() >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF:
		return "jpg"
	if bytes.size() >= 12 and bytes.slice(0, 4) == "RIFF".to_ascii_buffer() \
			and bytes.slice(8, 12) == "WEBP".to_ascii_buffer():
		return "webp"
	return ""


## 解码到给定 Image，返回格式名；失败返回空串（img 内容未定义）。
static func decode_image_bytes(bytes: PackedByteArray, img: Image) -> String:
	var format := detect_image_format(bytes)
	match format:
		"png":
			return format if img.load_png_from_buffer(bytes) == OK else ""
		"jpg":
			return format if img.load_jpg_from_buffer(bytes) == OK else ""
		"webp":
			return format if img.load_webp_from_buffer(bytes) == OK else ""
		_:
			return ""


## 清单形态宽容提取：顶层数组，或对象的 blocks/assets/images/items/files/entries
## 数组字段。返回 {ok, entries}；形态不认识 ok=false。
static func extract_manifest_entries(parsed: Variant) -> Dictionary:
	if parsed is Array:
		return {"ok": true, "entries": parsed}
	if parsed is Dictionary:
		var d := parsed as Dictionary
		for key in ["blocks", "assets", "images", "items", "files", "entries"]:
			if d.has(key) and d[key] is Array:
				return {"ok": true, "entries": d[key]}
	return {"ok": false, "entries": []}


## 清单条目 → 描述符候选（空 Dictionary = 跳过）。默认 kind=terrain 整图、
## 文件名前缀做 tag、显示名与 URL 分离；相对 URL 基于清单源归一化。
static func _descriptor_from_manifest_entry(entry: Dictionary, manifest_url: String) -> Dictionary:
	var file_name := ""
	for key in ["file", "name", "path", "url", "filename", "image"]:
		if entry.has(key) and str(entry[key]) != "":
			file_name = str(entry[key]).get_file()
			if not file_name.is_empty():
				break
	if file_name.is_empty() or file_name.get_basename().is_empty():
		return {}

	var raw_url := ""
	for key in ["url", "image", "path", "file"]:
		if entry.has(key) and str(entry[key]) != "":
			raw_url = str(entry[key])
			break
	if raw_url.contains("../") or raw_url.contains("..\\") or raw_url.to_lower().contains("%2e%2e"):
		return {}  # 路径穿越直接拒绝
	var url := resolve_url(raw_url, manifest_url)
	if not is_http_url(url):
		return {}

	var sha := ""
	for key in ["sha256", "sha256_hash", "hash"]:
		if entry.has(key):
			var s := str(entry[key]).to_lower()
			if s.length() == 64 and s.is_valid_hex_number(false):
				sha = s
			break

	var w := int(entry.get("width", 0)) if entry.has("width") else 0
	var h := int(entry.get("height", 0)) if entry.has("height") else 0
	if w < 0:
		w = 0
	if h < 0:
		h = 0

	var kind := str(entry.get("kind", ""))
	if not Catalog.KINDS.has(kind):
		kind = Catalog.KIND_TERRAIN

	var display_name := file_name.get_basename()
	for key in ["title", "label", "display_name"]:
		if entry.has(key) and str(entry[key]) != "":
			display_name = str(entry[key])
			break

	var tags: Array = [stem_prefix(file_name)]
	if entry.has("tags") and entry["tags"] is Array:
		for t in (entry["tags"] as Array):
			var ts := str(t)
			if not ts.is_empty() and not tags.has(ts):
				tags.append(ts)

	var byte_count := int(entry.get("bytes", 0)) if entry.has("bytes") else 0
	if byte_count < 0:
		byte_count = 0

	return Catalog.make_descriptor(slugify(file_name.get_basename()), kind,
		display_name, tags, url, sha, byte_count, w, h)


## 相对 URL 归一化（仅拼目录，不做文件系统访问）；已是 http(s) 原样返回。
static func resolve_url(candidate: String, base_url: String) -> String:
	if is_http_url(candidate):
		return candidate
	if base_url.is_empty():
		return candidate
	var dir := base_url.substr(0, base_url.rfind("/"))
	if dir.is_empty():
		return candidate
	return dir + "/" + candidate


## 网络条目合并进库：更新源侧字段（image/sha256/bytes/width/height），
## 保留用户自定义（name/tags/render）。返回 {changed, value}。
static func _merge_net_descriptor(old: Dictionary, incoming: Dictionary) -> Dictionary:
	var out := old.duplicate(true)
	var changed := false
	if str(incoming["image"]) != str(out["image"]):
		out["image"] = incoming["image"]
		changed = true
	if str(incoming["sha256"]) != "" and str(incoming["sha256"]) != str(out["sha256"]):
		out["sha256"] = incoming["sha256"]
		changed = true
	if int(incoming["bytes"]) > 0 and int(incoming["bytes"]) != int(out["bytes"]):
		out["bytes"] = int(incoming["bytes"])
		changed = true
	if int(incoming["width"]) > 0 and int(incoming["width"]) != int(out["width"]):
		out["width"] = int(incoming["width"])
		changed = true
	if int(incoming["height"]) > 0 and int(incoming["height"]) != int(out["height"]):
		out["height"] = int(incoming["height"])
		changed = true
	return {"changed": changed, "value": out}


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

func blob_root() -> String:
	return root_dir + "/" + BLOB_DIRNAME


func has_blob(d: Dictionary) -> bool:
	var sha := str(d.get("sha256", ""))
	if sha.is_empty():
		return false
	return FileAccess.file_exists(blob_path_for_sha(sha))


func _index_of_id(asset_id: String) -> int:
	var assets: Array = library["assets"]
	for i in assets.size():
		if str((assets[i] as Dictionary)["id"]) == asset_id:
			return i
	return -1


## 写 blob：建目录 → 写原始字节 → 回读验证。返回错误串（空 = 成功）。
func _write_blob(blob_path: String, bytes: PackedByteArray) -> String:
	var dir_err := DirAccess.make_dir_recursive_absolute(blob_path.get_base_dir())
	if dir_err != OK:
		return "mkdir_%d" % dir_err
	var f := FileAccess.open(blob_path, FileAccess.WRITE)
	if f == null:
		return "open_%d" % FileAccess.get_open_error()
	f.store_buffer(bytes)
	f.close()
	if FileAccess.get_file_as_bytes(blob_path) != bytes:
		DirAccess.remove_absolute(blob_path)
		return "verify_mismatch"
	return ""


func _put_lru(asset_id: String, tex: Texture2D) -> void:
	if _textures.has(asset_id):
		_touch_lru(asset_id)
		_textures[asset_id] = tex
		return
	_textures[asset_id] = tex
	_texture_lru.append(asset_id)
	while _texture_lru.size() > max_texture_cache:
		var oldest: String = _texture_lru.pop_front()
		_textures.erase(oldest)


func _touch_lru(asset_id: String) -> void:
	if _texture_lru.has(asset_id):
		_texture_lru.erase(asset_id)
		_texture_lru.append(asset_id)
