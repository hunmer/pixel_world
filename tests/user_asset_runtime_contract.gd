## user_asset_runtime_contract.gd — UserAssetService 运行时契约（SceneTree + 内嵌 TCP 假源）
##
## 覆盖：本地导入（成功/去重/非图/超大/超尺寸）、清单拉取与元数据先行、
## 跨源内容去重（本地导入 sha 与清单同图共享 blob）、图片下载回填、
## 声明哈希不匹配拒绝、同请求去重、并发上限、超时+重试、断网离线取纹理、
## remove_asset blob 引用保护、LRU 逐出、库持久化 round-trip（新实例）。
## 运行：godot --headless --path . --script res://tests/user_asset_runtime_contract.gd

extends SceneTree

const ServiceScript := preload("res://scripts/assets/user_asset_service.gd")
const Catalog := preload("res://scripts/assets/user_asset_catalog.gd")
const AdapterScript := preload("res://scripts/assets/user_asset_visual_adapter.gd")

const TMP_ROOT := "user://user_asset_runtime_tmp"

var failures: Array[String] = []
var checks := 0


## ---------------------------------------------------------------- 假 HTTP 源


## 内嵌 TCP_Server 假源：路径映射字节、延迟、挂起不响应、连接计数与峰值统计
class FakeHTTPServer:
	extends Node

	var server := TCPServer.new()
	var port := 0
	var files := {}            # path("/x.png") -> PackedByteArray
	var manifest := ""         # /blocks.json 响应体
	var hang_paths := {}       # path -> true：接受连接但永不响应
	var delay_ms := {}         # path -> int
	var connection_count := {} # path -> int
	var peak_active := 0

	var _readers: Array[Dictionary] = []

	func start() -> bool:
		var err := server.listen(0, "127.0.0.1")
		if err != OK:
			return false
		port = server.get_local_port()
		return true

	func stop() -> void:
		server.stop()

	func base_url() -> String:
		return "http://127.0.0.1:%d" % port

	func _process(_dt: float) -> void:
		while server.is_connection_available():
			var peer := server.take_connection()
			_readers.append({"peer": peer, "path": "", "got_request": false,
				"respond_at": 0, "done": false})
			if _readers.size() > peak_active:
				peak_active = _readers.size()
		var done_count := 0
		for r in _readers:
			if r["done"]:
				done_count += 1
		# 峰值按同时在途的未完成连接算
		var active := _readers.size() - done_count
		if active > peak_active:
			peak_active = active
		var i := _readers.size() - 1
		while i >= 0:
			_poll_reader(_readers[i])
			i -= 1
		_readers = _readers.filter(func(r: Dictionary) -> bool: return not r["done"])

	func _poll_reader(r: Dictionary) -> void:
		var peer: StreamPeerTCP = r["peer"]
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_ERROR:
			r["done"] = true
			return
		if status != StreamPeerTCP.STATUS_CONNECTED:
			return
		peer.poll()
		if not r["got_request"]:
			var avail := peer.get_available_bytes()
			if avail <= 0:
				return
			var data := peer.get_string(avail)
			var lines := data.split("\r\n")
			if lines.is_empty():
				return
			var parts := (lines[0] as String).split(" ")
			if parts.size() < 2 or parts[0] != "GET":
				r["done"] = true
				return
			r["path"] = parts[1]
			r["got_request"] = true
			connection_count[r["path"]] = int(connection_count.get(r["path"], 0)) + 1
			r["respond_at"] = Time.get_ticks_msec() + int(delay_ms.get(r["path"], 0))
			return
		# 已收到请求：到点响应（hang 路径保持连接挂起等对端超时断开，
		# 否则 peer 失去引用被释放会让对端报 CONNECTION_ERROR 而非 TIMEOUT）
		if Time.get_ticks_msec() >= r["respond_at"]:
			if hang_paths.has(r["path"]):
				r["respond_at"] += 100000
				return
			_respond(r, r["path"])

	func _respond(r: Dictionary, path: String) -> void:
		r["done"] = true
		var peer: StreamPeerTCP = r["peer"]
		var body: PackedByteArray = files.get(path, PackedByteArray())
		if path == "/blocks.json":
			body = manifest.to_utf8_buffer()
		var header := "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % body.size()
		peer.put_data(header.to_utf8_buffer())
		peer.put_data(body)
		peer.disconnect_from_host()


## ---------------------------------------------------------------- 基础设施


func _initialize() -> void:
	call_deferred("_run")


func _expect(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures.append(what)


func _await_sig(sig: Signal, timeout_ms: int) -> Array:
	## 等一个信号触发，返回 [fired, *args]；超时返回 [false]
	var box := {"fired": false, "args": []}
	var cb := func(...args) -> void:
		if not box["fired"]:
			box["fired"] = true
			box["args"] = args
	sig.connect(cb)
	var start := Time.get_ticks_msec()
	while not box["fired"] and Time.get_ticks_msec() - start < timeout_ms:
		await process_frame
	sig.disconnect(cb)
	var out: Array = [box["fired"]]
	out.append_array(box["args"])
	# 超时时垫占位，防止后续断言访问参数越界
	while out.size() < 4:
		out.append(null)
	return out


func _await_count(sig: Signal, want: int, timeout_ms: int) -> int:
	## 等信号累计触发 want 次，返回实际触发数
	var box := {"n": 0}
	var cb := func(_id: String) -> void: box["n"] += 1
	sig.connect(cb)
	var start := Time.get_ticks_msec()
	while box["n"] < want and Time.get_ticks_msec() - start < timeout_ms:
		await process_frame
	sig.disconnect(cb)
	return box["n"]


func _make_png(w: int, h: int, color: Color) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img.save_png_to_buffer()


func _sha_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	var out := ctx.finish()
	return out.hex_encode()


func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var names: Array[String] = []
	var n := dir.get_next()
	while n != "":
		if n != "." and n != "..":
			names.append(n)
		n = dir.get_next()
	dir.list_dir_end()
	for name in names:
		var full := path + "/" + name
		if dir.dir_exists(name):
			_remove_recursive(full)
		else:
			dir.remove(name)
	DirAccess.remove_absolute(path)


## ---------------------------------------------------------------- 主流程


func _run() -> void:
	_remove_recursive(TMP_ROOT)
	var img_a := _make_png(4, 4, Color.RED)
	var img_b := _make_png(3, 5, Color.BLUE)
	var img_c := _make_png(5, 5, Color.GREEN)
	var img_d := _make_png(6, 4, Color.YELLOW)
	var img_e := _make_png(7, 3, Color.CYAN)
	var img_f := _make_png(4, 7, Color.MAGENTA)
	var sha_a := _sha_hex(img_a)
	var sha_b := _sha_hex(img_b)

	# --- S1 本地导入 ---
	var svc: Node = ServiceScript.new(TMP_ROOT)
	root.add_child(svc)
	DirAccess.make_dir_recursive_absolute(TMP_ROOT + "/src")
	var src_path := TMP_ROOT + "/src/red_block.png"
	var f := FileAccess.open(src_path, FileAccess.WRITE)
	f.store_buffer(img_a)
	f.close()
	var res: Dictionary = svc.import_local_file(src_path)
	_expect(bool(res.get("ok", false)), "S1 本地导入应成功: " + str(res.get("error", "")))
	_expect(str(res.get("asset_id", "")) == "red_block", "S1 导入 id 应为 red_block")
	_expect(str(res.get("sha256", "")) == sha_a, "S1 导入 sha256 应与源一致")
	_expect(int(res.get("width", -1)) == 4 and int(res.get("height", -1)) == 4, "S1 导入宽高 4x4")
	var state: Dictionary = svc.get_asset_state("red_block")
	_expect(str(state["status"]) == "ready" and bool(state["has_blob"]), "S1 导入后即 ready")
	var blob_a: String = svc.blob_path_for_sha(sha_a)
	_expect(FileAccess.file_exists(blob_a), "S1 blob 文件应存在（内容寻址）")

	var res2: Dictionary = svc.import_image_bytes(img_a, "red_block.png")
	_expect(bool(res2.get("deduped", false)), "S1 同内容重复导入应去重")
	_expect(svc.asset_count() == 1, "S1 去重后库中仍 1 条")

	var bad: Dictionary = svc.import_image_bytes("GIF89a not an image".to_utf8_buffer(), "x.gif")
	_expect(not bool(bad.get("ok", true)) and str(bad.get("error", "")).contains("unsupported_or_corrupt_image"),
		"S1 非图片内容必须拒绝")

	var old_limit: int = svc.max_image_bytes
	svc.max_image_bytes = img_b.size() - 10
	var too_big: Dictionary = svc.import_image_bytes(img_b, "blue.png")
	_expect(str(too_big.get("error", "")).contains("image_too_large"),
		"S1 超自定义字节上限必须拒绝")
	svc.max_image_bytes = old_limit

	var huge_png := _make_png(Catalog.MAX_SIDE_PIXELS + 1, 1, Color.WHITE)
	var too_tall: Dictionary = svc.import_image_bytes(huge_png, "huge.png")
	_expect(str(too_tall.get("error", "")).contains("image_dimensions_exceed"),
		"S1 超像素边长必须拒绝")
	_expect(svc.asset_count() == 1, "S1 拒绝的导入不应入库")

	# --- S2 假源清单：元数据先行 + 跨源去重 ---
	var server: FakeHTTPServer = FakeHTTPServer.new()
	root.add_child(server)
	_expect(server.start(), "S2 假源监听应成功")
	server.files["/basic_0.png"] = img_a
	server.files["/grassland_1.png"] = img_b
	server.manifest = JSON.stringify({"blocks": [
		{"file": "basic_0.png", "sha256": sha_a, "width": 4, "height": 4},
		{"file": "grassland_1.png"},
	]})
	var set_res: Dictionary = svc.set_source_url(server.base_url() + "/blocks.json")
	_expect(bool(set_res.get("ok", false)), "S2 设置假源 URL 应成功")
	var man: Dictionary = svc.request_manifest()
	_expect(bool(man.get("ok", false)), "S2 清单请求应入队")
	var fired: Array = await _await_sig(svc.manifest_loaded, 5000)
	_expect(bool(fired[0]), "S2 manifest_loaded 应触发")
	var man_result: Dictionary = fired[1]
	_expect(bool(man_result.get("ok", false)), "S2 清单结果 ok: " + str(man_result.get("error", "")))
	_expect(int(man_result.get("added", -1)) == 2, "S2 应新增 2 条")
	_expect(svc.asset_count() == 3, "S2 清单后库中 3 条")
	state = svc.get_asset_state("basic_0")
	_expect(str(state["status"]) == "ready",
		"S2 basic_0 与 red_block 同 sha 应跨源去重直接 ready")
	var g1: Dictionary = svc.find_by_id("grassland_1")
	_expect(g1 is Dictionary and str(g1["sha256"]) == "" and int(g1["width"]) == 0,
		"S2 grassland_1 元数据先行（sha/尺寸未知）")
	_expect(svc.get_texture("basic_0") != null, "S2 跨源共享 blob 应能取纹理")

	# --- S3 图片下载回填 ---
	var dl: Dictionary = svc.request_asset_image("grassland_1")
	_expect(bool(dl.get("queued", false)) and not bool(dl.get("ready", false)),
		"S3 缺图素材应入队下载")
	fired = await _await_sig(svc.asset_ready, 5000)
	_expect(bool(fired[0]) and str(fired[1]) == "grassland_1", "S3 asset_ready(grassland_1) 应触发")
	g1 = svc.find_by_id("grassland_1")
	_expect(str(g1["sha256"]) == sha_b and int(g1["width"]) == 3 and int(g1["height"]) == 5,
		"S3 下载后 sha/宽高应回填")
	_expect(int(g1["bytes"]) == img_b.size(), "S3 下载后 bytes 应回填")
	var tex: Texture2D = svc.get_texture("grassland_1")
	_expect(tex != null and tex.get_width() == 3, "S3 下载后纹理可取且宽 3")

	# --- S4 声明哈希不匹配拒绝 ---
	var fake_sha := "f".repeat(64)
	server.files["/evil.png"] = img_a
	server.manifest = JSON.stringify({"blocks": [
		{"file": "evil.png", "sha256": fake_sha, "width": 4, "height": 4},
	]})
	svc.request_manifest()
	fired = await _await_sig(svc.manifest_loaded, 5000)
	_expect(bool(fired[0]) and bool((fired[1] as Dictionary).get("ok", false)), "S4 清单 v2 应成功")
	_expect(svc.asset_count() == 4, "S4 evil 入库后 4 条")
	svc.request_asset_image("evil")
	fired = await _await_sig(svc.asset_failed, 5000)
	_expect(bool(fired[0]) and str(fired[1]) == "evil", "S4 asset_failed(evil) 应触发")
	_expect(str(fired[2]).contains("sha256_mismatch"), "S4 失败原因应为 sha256_mismatch: " + str(fired[2]))
	_expect(str(svc.get_asset_state("evil")["status"]) == "missing", "S4 失败后状态回 missing")
	_expect(not FileAccess.file_exists(svc.blob_path_for_sha(fake_sha)),
		"S4 哈希不符时不得写 blob")

	# --- S5 同请求去重 ---
	server.delay_ms["/slow_1.png"] = 300
	server.files["/slow_1.png"] = img_c
	server.manifest = JSON.stringify({"blocks": [
		{"file": "slow_1.png"},
	]})
	svc.request_manifest()
	fired = await _await_sig(svc.manifest_loaded, 5000)
	_expect(bool(fired[0]) and bool((fired[1] as Dictionary).get("ok", false)), "S5 清单 v3 应成功")
	var r1: Dictionary = svc.request_asset_image("slow_1")
	var r2: Dictionary = svc.request_asset_image("slow_1")
	_expect(bool(r1.get("queued", false)) and bool(r2.get("deduped", false)),
		"S5 第二次请求应被去重")
	fired = await _await_sig(svc.asset_ready, 5000)
	_expect(bool(fired[0]) and str(fired[1]) == "slow_1", "S5 slow_1 应就绪")
	_expect(int(server.connection_count.get("/slow_1.png", 0)) == 1,
		"S5 去重后服务器只应收到 1 次连接")

	# --- S6 并发上限 ---
	svc.max_concurrent_requests = 2
	server.files["/c1.png"] = img_c
	server.files["/c2.png"] = img_d
	server.files["/c3.png"] = img_e
	server.files["/c4.png"] = img_f
	for p in ["/c1.png", "/c2.png", "/c3.png", "/c4.png"]:
		server.delay_ms[p] = 150
	server.manifest = JSON.stringify({"blocks": [
		{"file": "c1.png"}, {"file": "c2.png"}, {"file": "c3.png"}, {"file": "c4.png"},
	]})
	svc.request_manifest()
	fired = await _await_sig(svc.manifest_loaded, 5000)
	_expect(bool(fired[0]) and bool((fired[1] as Dictionary).get("ok", false)), "S6 清单 v4 应成功")
	for cid in ["c1", "c2", "c3", "c4"]:
		svc.request_asset_image(cid)
	var got: int = await _await_count(svc.asset_ready, 4, 8000)
	_expect(got == 4, "S6 四张并发图都应就绪（实际 %d）" % got)
	_expect(server.peak_active <= 2, "S6 服务器峰值并发应 <= 2（实际 %d）" % server.peak_active)
	for cid in ["c1", "c2", "c3", "c4"]:
		_expect(str(svc.get_asset_state(cid)["status"]) == "ready", "S6 " + cid + " 应 ready")

	# --- S7 超时 + 重试 ---
	svc.request_timeout = 0.8
	svc.max_retries = 1
	server.hang_paths["/hang.png"] = true
	server.manifest = JSON.stringify({"blocks": [
		{"file": "hang.png"},
	]})
	svc.request_manifest()
	fired = await _await_sig(svc.manifest_loaded, 5000)
	_expect(bool(fired[0]) and bool((fired[1] as Dictionary).get("ok", false)), "S7 清单 v5 应成功")
	svc.request_asset_image("hang")
	fired = await _await_sig(svc.asset_failed, 8000)
	_expect(bool(fired[0]) and str(fired[1]) == "hang", "S7 asset_failed(hang) 应触发")
	_expect(str(fired[2]).contains("13"), "S7 超时错误应为 HTTP RESULT 13（实际 %s）" % str(fired[2]))
	_expect(int(server.connection_count.get("/hang.png", 0)) == 2,
		"S7 初始+1 次重试应恰好 2 次连接（实际 %d）" % int(server.connection_count.get("/hang.png", 0)))

	# --- S8 断网离线缓存 ---
	server.stop()
	tex = svc.get_texture("grassland_1")
	_expect(tex != null, "S8 断网后已缓存素材仍可取纹理")
	var off: Dictionary = svc.request_asset_image("grassland_1")
	_expect(bool(off.get("ready", false)), "S8 断网后 blob 在的请求应立即 ready")

	# --- S9 remove_asset blob 引用保护 ---
	_expect(svc.remove_asset("grassland_1", true).get("ok", false), "S9 移除 grassland_1(keep_blob) 应成功")
	_expect(FileAccess.file_exists(svc.blob_path_for_sha(sha_b)), "S9 keep_blob 后 blob 应保留")
	svc.remove_asset("red_block", false)
	_expect(svc.find_by_id("red_block") == null, "S9 red_block 应已移出库")
	_expect(FileAccess.file_exists(blob_a), "S9 basic_0 仍引用 imgA 时 blob 不应被删")
	svc.remove_asset("basic_0", false)
	_expect(not FileAccess.file_exists(blob_a), "S9 最后一个引用移除后 blob 应删除")
	_expect(svc.asset_count() == 7, "S9 移除 3 条后应剩 7 条（实际 %d）" % svc.asset_count())

	# --- S10 LRU 逐出 ---
	svc.max_texture_cache = 2
	svc.get_texture("c1")
	svc.get_texture("c2")
	svc.get_texture("c3")
	_expect(not bool(svc.get_asset_state("c1")["cached_texture"]),
		"S10 超出缓存上限后最旧纹理应被逐出")
	_expect(bool(svc.get_asset_state("c3")["cached_texture"]), "S10 最新纹理应在缓存")
	_expect(svc.get_texture("c1") != null, "S10 被逐出后仍可从 blob 重新解码")

	# --- S11 库持久化 round-trip ---
	var svc2: Node = ServiceScript.new(TMP_ROOT)
	root.add_child(svc2)
	_expect(svc2.asset_count() == svc.asset_count(),
		"S11 新实例应从磁盘恢复相同资产数（%d vs %d）" % [svc2.asset_count(), svc.asset_count()])
	_expect(str(svc2.get_asset_state("slow_1")["status"]) == "ready",
		"S11 新实例 slow_1 仍 ready（blob + 库持久化）")
	_expect(svc2.get_texture("slow_1") != null, "S11 新实例可取纹理")
	_expect(svc2.get_source_url() == server.base_url() + "/blocks.json",
		"S11 新实例 source_url 应持久化")

	# --- S12 terrain 整图尺寸适配 32x26 盒（内容裁剪 + 等比 fit，放置后与内建方块同尺寸） ---
	var adapter := AdapterScript.new(TMP_ROOT)
	var big_png := _make_png(174, 200, Color.WHITE)
	var big_img := Image.new()
	big_img.load_png_from_buffer(big_png)
	var desc_norm := Catalog.make_descriptor("norm_a", Catalog.KIND_TERRAIN,
		"norm_a", [], "norm_a.png", "", 0, 174, 200)
	var v_norm: Dictionary = adapter.build_visual(desc_norm, big_img)
	_expect(Vector2(v_norm["canvas_size"]) == Vector2(23, 26),
		"S12 terrain 174x200 等比适配 32x26 盒（fit=0.13）: %s" % str(v_norm["canvas_size"]))
	var desc_fp2 := Catalog.make_descriptor("norm_b", Catalog.KIND_TERRAIN,
		"norm_b", [], "norm_b.png", "", 0, 174, 200)
	desc_fp2["render"] = {"mode": "full", "crop": null, "pivot": {"x": 0.5, "y": 1.0},
		"scale": 1.0, "footprint": {"w": 2, "h": 1}}
	var v_fp2: Dictionary = adapter.build_visual(desc_fp2, big_img)
	_expect(Vector2(v_fp2["canvas_size"]) == Vector2(23, 26),
		"S12 footprint.w=2 → 盒 64x26，高受限 fit=0.13（等比不拉伸）: %s" % str(v_fp2["canvas_size"]))
	var desc_x2 := Catalog.make_descriptor("norm_c", Catalog.KIND_TERRAIN,
		"norm_c", [], "norm_c.png", "", 0, 174, 200)
	desc_x2["render"] = {"mode": "full", "crop": null, "pivot": {"x": 0.5, "y": 1.0},
		"scale": 2.0, "footprint": {"w": 1, "h": 1}}
	var v_x2: Dictionary = adapter.build_visual(desc_x2, big_img)
	_expect(Vector2(v_x2["canvas_size"]) == Vector2(46, 52),
		"S12 render.scale=2 在 fit 后再乘（23x26 × 2）: %s" % str(v_x2["canvas_size"]))
	var desc_plant := Catalog.make_descriptor("norm_d", Catalog.KIND_PLANT,
		"norm_d", [], "norm_d.png", "", 0, 174, 200)
	var v_plant: Dictionary = adapter.build_visual(desc_plant, big_img)
	_expect(Vector2(v_plant["canvas_size"]) == Vector2(174, 200),
		"S12 植物不归一化（保持原尺寸）: %s" % str(v_plant["canvas_size"]))
	var desc_crop := Catalog.make_descriptor("norm_e", Catalog.KIND_TERRAIN,
		"norm_e", [], "norm_e.png", "", 0, 174, 200)
	desc_crop["render"] = {"mode": "crop", "crop": {"x": 0, "y": 0, "w": 87, "h": 100},
		"pivot": {"x": 0.5, "y": 1.0}, "scale": 1.0, "footprint": {"w": 1, "h": 1}}
	var v_crop: Dictionary = adapter.build_visual(desc_crop, big_img)
	_expect(Vector2(v_crop["canvas_size"]) == Vector2(23, 26),
		"S12 crop 模式按裁后尺寸适配盒（87x100 全不透明 → 23x26）: %s" % str(v_crop["canvas_size"]))

	# --- S13 resolve_many 批量解析（方块页网格用：一次库加载出全图） ---
	# 注意 red_block/basic_0/grassland_1 已在 S9 移除，这里用 slow_1 + 新导入素材。
	var late: Dictionary = svc.import_image_bytes(img_a, "zz_late.png")
	_expect(bool(late.get("ok", false)), "S13 末期导入应成功")
	var adapter2 := AdapterScript.new(TMP_ROOT)
	var batch: Dictionary = adapter2.resolve_many(["slow_1", "zz_late", "no_such_asset"])
	_expect(batch.size() == 3, "S13 resolve_many 返回全部请求的 id（含占位）: %d" % batch.size())
	_expect(not bool(batch["slow_1"].get("missing", true)) and batch["slow_1"].get("texture") != null,
		"S13 resolve_many 已下载素材为真图: missing=%s" % str(batch["slow_1"].get("missing")))
	_expect(not bool(batch["zz_late"].get("missing", true)) and batch["zz_late"].get("texture") != null,
		"S13 resolve_many 本地导入素材为真图: missing=%s" % str(batch["zz_late"].get("missing")))
	_expect(bool(batch["no_such_asset"].get("missing", false)), "S13 resolve_many 未知 id 给占位")
	var single: Dictionary = adapter2.resolve("slow_1")
	_expect(Vector2(batch["slow_1"]["canvas_size"]) == Vector2(single["canvas_size"]),
		"S13 resolve_many 与 resolve 单条结果一致: %s vs %s" % [str(batch["slow_1"]["canvas_size"]), str(single["canvas_size"])])

	# --- S14 烘焙缓存落盘（像素处理只做一次，之后 resolve 直接读盘） ---
	var baked_path := adapter2.baked_path_for("slow_1")
	_expect(FileAccess.file_exists(baked_path), "S14 resolve 后应写出烘焙图: " + baked_path)
	var baked_img := Image.new()
	_expect(baked_img.load(baked_path) == OK and baked_img.get_width() == int(Vector2(single["canvas_size"]).x),
		"S14 烘焙图尺寸应与 visual 一致（%d vs %s）" % [baked_img.get_width(), str(single["canvas_size"])])
	adapter2.invalidate_baked("slow_1")
	_expect(not FileAccess.file_exists(baked_path), "S14 invalidate_baked 应删除烘焙图")
	adapter2.clear_cache("slow_1")
	var re: Dictionary = adapter2.resolve("slow_1")
	_expect(not bool(re.get("missing", true)) and FileAccess.file_exists(baked_path),
		"S14 烘焙失效后 resolve 应重烘并再次落盘")

	# --- 清理 ---
	root.remove_child(svc)
	root.remove_child(svc2)
	root.remove_child(server)
	svc.queue_free()
	svc2.queue_free()
	server.queue_free()
	_remove_recursive(TMP_ROOT)

	if failures.is_empty():
		print("USER_ASSET_RUNTIME_CONTRACT_OK (%d checks)" % checks)
		quit(0)
	else:
		for msg in failures:
			print("FAIL: " + msg)
		print("USER_ASSET_RUNTIME_CONTRACT_FAILED (%d failures / %d checks)" % [failures.size(), checks])
		quit(1)
