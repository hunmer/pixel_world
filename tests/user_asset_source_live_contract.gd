## user_asset_source_live_contract.gd — 端到端活源契约
## 依赖 127.0.0.1:8076 的 http-server（F:/blocks，procm 进程 pixelworld_assets_http）。
## 验证：默认源 URL 正确 → request_manifest 拉到 1455 条 → 描述符字段（sha256/尺寸）与清单一致
## → 按需下载图片 asset_ready → adapter 解析出真视觉（非占位）→ 缺图占位 → 离线 blob 缓存可解析。
## 运行：godot --headless --path . --script res://tests/user_asset_source_live_contract.gd

extends SceneTree

const ServiceScript := preload("res://scripts/assets/user_asset_service.gd")
const AdapterScript := preload("res://scripts/assets/user_asset_visual_adapter.gd")
const PanelScript := preload("res://scripts/editor/asset_library_panel.gd")

var _failures: Array = []
var _got_manifest := false
var _manifest_result: Dictionary = {}
var _ready_id := ""
var _failed_id := ""

func _initialize() -> void:
	call_deferred("_run")


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("CHECK_OK: ", msg)
	else:
		_failures.append(msg)
		print("LIVE_FAIL: ", msg)


func _run() -> void:
	var root := get_root()
	var tmp_root := "user://user_asset_live_tmp"
	_remove_recursive(tmp_root)

	var svc: Node = ServiceScript.new(tmp_root)
	svc.name = "LiveAssetService"
	root.add_child(svc)

	# S1 默认源 URL 必须是本机素材服务（不接受空/外网兜底）
	_expect(svc.get_source_url() == "http://127.0.0.1:8076/blocks.json",
		"默认 source URL = http://127.0.0.1:8076/blocks.json")

	# S2 拉清单（带 30s 超时；HTTPRequest 在 headless 下仍走内置 HTTPClient）
	svc.manifest_loaded.connect(func(r: Dictionary) -> void:
		_manifest_result = r
		_got_manifest = true)
	var req: Dictionary = svc.request_manifest()
	_expect(bool(req.get("ok", false)), "request_manifest 已排队")
	var deadline := Time.get_ticks_msec() + 30000
	while not _got_manifest and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(_got_manifest, "manifest_loaded 信号到达")
	if _got_manifest:
		_expect(bool(_manifest_result.get("ok", false)), "manifest ok=true")
		_expect(int(_manifest_result.get("total", 0)) == 1455, "清单 total=1455")
		_expect(int(_manifest_result.get("added", 0)) == 1455, "首次全量 added=1455")

	# S3 描述符字段与清单一致（抽查 grassland_0 / volcano_99 / basic_0 首中末代表）
	var spot := {"grassland_0": Vector2i(174, 202), "volcano_99": Vector2i.ZERO, "basic_0": Vector2i(138, 176)}
	for id in spot.keys():
		var d: Variant = svc.find_by_id(id)
		_expect(d is Dictionary, "find_by_id(%s) 存在" % id)
		if d is Dictionary:
			_expect(String(d.get("kind", "")) == "terrain", "%s kind=terrain" % id)
			_expect(String(d.get("sha256", "")).length() == 64, "%s sha256 64hex" % id)
			if spot[id] != Vector2i.ZERO:
				_expect(int(d.get("width", 0)) == spot[id].x and int(d.get("height", 0)) == spot[id].y,
					"%s 尺寸 %dx%d" % [id, spot[id].x, spot[id].y])
			_expect(Array(d.get("tags", [])).has(id.split("_")[0]), "%s tags 含前缀" % id)

	# S4 按需下载：volcano_99（末条）→ asset_ready → 纹理尺寸正确
	svc.asset_ready.connect(func(asset_id: String) -> void:
		_ready_id = asset_id)
	svc.asset_failed.connect(func(asset_id: String, _error: String) -> void:
		_failed_id = asset_id)
	svc.request_asset_image("volcano_99")
	deadline = Time.get_ticks_msec() + 30000
	while _ready_id == "" and _failed_id == "" and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(_ready_id == "volcano_99", "volcano_99 asset_ready")
	if _failed_id != "":
		_expect(false, "volcano_99 意外 asset_failed=%s" % _failed_id)
	var state_res: Dictionary = svc.get_asset_state("volcano_99")
	_expect(String(state_res.get("status", "")) == "ready", "volcano_99 status=ready")
	var tex: Variant = svc.get_texture("volcano_99")
	_expect(tex is Texture2D, "volcano_99 纹理非空")
	if tex is Texture2D:
		var img: Image = tex.get_image()
		_expect(img != null and img.get_width() > 0, "volcano_99 纹理可解码 %s" % (str(img.get_size()) if img else "null"))

	# S5 adapter 解析：已下载 → 真视觉；未下载 → 占位（missing 不崩溃）
	var adapter: RefCounted = AdapterScript.new(tmp_root)
	var v_ready: Dictionary = adapter.resolve("volcano_99")
	_expect(not bool(v_ready.get("missing", true)), "adapter resolve(volcano_99) 非占位")
	_expect(v_ready.get("texture") is Texture2D, "volcano_99 visual.texture 存在")
	var v_missing: Dictionary = adapter.resolve("no_such_asset")
	_expect(bool(v_missing.get("missing", false)), "缺图 resolve 返回占位 missing=true")
	_expect(v_missing.get("texture") is Texture2D, "缺图占位也有程序纹理")

	# S6 离线：adapter 直接读 blob 目录（不走网络）——换一个未下载的 id 也应解析（库内有描述符、blob 未下载 → 占位是允许的，
	# 但已下载的必须离线可读）。这里验证已下载条目离线路径已覆盖（resolve 本就读磁盘）。
	_expect(adapter.cache_size() >= 1, "adapter 缓存已填充")

	# S7 面板回归（在线素材自动加载语义）：
	# 懒预览对「http 来源且本地无 blob」的可见素材自动 request_asset_image，
	# 图片加载后缓存进 blob 目录；asset_ready 后必须清掉 adapter 占位缓存换真图（陈旧占位 Bug）。
	var panel: Node = PanelScript.new()
	root.add_child(panel)
	panel.setup(svc, adapter)
	var pid := "basic_21"
	_expect(String(svc.get_asset_state(pid).get("status", "")) == "missing", "%s 加载前 status=missing" % pid)
	# 预览泵跑若干帧（面板可见）→ 触发自动加载；随后等 HTTP 完成至 ready
	for i in 10:
		await process_frame
	deadline = Time.get_ticks_msec() + 30000
	while String(svc.get_asset_state(pid).get("status", "")) != "ready" \
			and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(String(svc.get_asset_state(pid).get("status", "")) == "ready",
		"懒预览自动加载 %s 至 ready" % pid)
	var v_after: Dictionary = adapter.resolve(pid)
	_expect(not bool(v_after.get("missing", true)),
		"asset_ready 后 adapter.resolve(%s) 非占位（占位缓存已清）" % pid)
	if panel._cells.has(pid):
		var icon: Texture2D = panel._asset_list.get_item_icon(int(panel._cells[pid]))
		var v_size: Vector2 = (v_after["texture"] as Texture2D).get_size()
		_expect(icon != null and icon.get_size() == v_size,
			"面板行图标已换真图（与 resolve 视觉一致 %s）" % str(v_size))
	else:
		_expect(false, "basic_21 应在第 1 页（id 稳定排序）")

	# S8 多选 + 保存标记（✓=用户标记，与图片是否已缓存无关）：
	# select_mode=MULTI；Ctrl+点击语义（程序模拟 multi_selected 信号）；
	# 「保存标记」切换 descriptor.saved 并持久化到库，图片本身由懒预览自动加载。
	var lst: ItemList = panel.get_node("AssetList")
	_expect(lst.select_mode == ItemList.SELECT_MULTI, "AssetList 为多选模式")
	_expect(panel.get_node("ImportRow/DownloadSelectedButton") is Button, "保存标记按钮存在")
	if panel._cells.has("basic_21"):
		_expect(not lst.get_item_text(int(panel._cells["basic_21"])).begins_with("✓ "),
			"S7 已自动加载的 basic_21 未标记保存 → 行文本无 ✓ 前缀")
	# 隐藏面板只为跳过本页预览泵解码（加快断言）；未加载也不影响标记
	panel.visible = false
	panel._goto_page(1)
	var id_a := str(lst.get_item_metadata(0))
	var id_b := str(lst.get_item_metadata(1))
	_expect(not id_a.is_empty() and not id_b.is_empty() and id_a != id_b, "第 2 页前两个素材 id 可读")
	# 程序模拟：普通点击选 id_a 为主选，Ctrl+点击（single=false）加选 id_b
	lst.select(0)
	lst.multi_selected.emit(0, true)
	lst.select(1, false)
	lst.multi_selected.emit(1, true)
	_expect(lst.get_selected_items().size() == 2, "多选后选中 2 行")
	_expect(panel._selected_id == id_b, "最后选中行为画笔主选（%s）" % id_b)
	var status_label: Label = panel.get_node("AssetStatusLabel")
	panel._on_download_selected()
	_expect(status_label.text.contains("已标记保存 2"), "标记 2 个：状态栏=%s" % status_label.text)
	_expect(bool((svc.find_by_id(id_a) as Dictionary).get("saved", false))
		and bool((svc.find_by_id(id_b) as Dictionary).get("saved", false)),
		"两个选中素材 saved=true")
	_expect(lst.get_item_text(0).begins_with("✓ ") and lst.get_item_text(1).begins_with("✓ "),
		"标记后两行文本均带 ✓ 前缀")
	# 持久化：同一 root 新服务实例读 library.json 应看到标记
	var svc2: Node = ServiceScript.new(tmp_root)
	root.add_child(svc2)
	_expect(bool((svc2.find_by_id(id_b) as Dictionary).get("saved", false)),
		"保存标记已持久化到 library.json")
	svc2.queue_free()
	# 再选已标记行 → 取消标记（toggle）
	lst.deselect_all()
	lst.select(0)
	lst.multi_selected.emit(0, true)
	panel._on_download_selected()
	_expect(status_label.text.contains("取消标记 1"), "再选已标记行取消标记：状态栏=%s" % status_label.text)
	_expect(not bool((svc.find_by_id(id_a) as Dictionary).get("saved", true)),
		"%s 取消标记后 saved=false" % id_a)
	# 空选提示
	lst.deselect_all()
	panel._on_download_selected()
	_expect(status_label.text.contains("未选中"), "空选择点保存标记给出提示（%s）" % status_label.text)
	panel.visible = true
	panel.queue_free()

	# S9 一键清空在线缓存：在线 blob/烘焙图删除、本地导入保留、库描述符保留、状态回 missing
	var local_src := "user://zz_live_local_src.png"
	var local_img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	local_img.fill(Color(0.2, 0.8, 0.3, 1.0))
	local_img.save_png(local_src)
	var imp: Dictionary = svc.import_local_file(local_src, "terrain")
	_expect(bool(imp.get("ok", false)), "S9 本地导入成功")
	var local_id := String(imp.get("asset_id", ""))
	var online_sha := String((svc.find_by_id("volcano_99") as Dictionary).get("sha256", ""))
	var online_blob: String = svc.blob_path_for_sha(online_sha)
	var online_baked := tmp_root.path_join("baked").path_join("volcano_99.png")
	var local_blob := ""
	if local_id != "":
		local_blob = String(svc.blob_path_for_sha(String((svc.find_by_id(local_id) as Dictionary).get("sha256", ""))))
	_expect(FileAccess.file_exists(online_blob), "S9 清空前在线 blob 存在")
	_expect(FileAccess.file_exists(online_baked), "S9 清空前在线烘焙图存在")
	_expect(local_blob != "" and FileAccess.file_exists(local_blob), "S9 清空前本地 blob 存在")
	var clear_res: Dictionary = svc.clear_online_cache()
	_expect(bool(clear_res.get("ok", false)), "S9 clear_online_cache ok")
	_expect(int(clear_res.get("removed_blobs", 0)) >= 1,
		"S9 removed_blobs>=1（实际 %d）" % int(clear_res.get("removed_blobs", 0)))
	_expect(not FileAccess.file_exists(online_blob), "S9 在线 blob 已删除")
	_expect(not FileAccess.file_exists(online_baked), "S9 在线烘焙图已删除")
	_expect(FileAccess.file_exists(local_blob), "S9 本地导入 blob 保留")
	_expect(svc.find_by_id("volcano_99") is Dictionary, "S9 库描述符保留（素材仍在列表）")
	_expect(String(svc.get_asset_state("volcano_99").get("status", "")) == "missing",
		"S9 清空后状态回 missing（可自动重新下载）")
	DirAccess.remove_absolute(local_src)

	svc.queue_free()
	_remove_recursive(tmp_root)

	if _failures.is_empty():
		print("USER_ASSET_SOURCE_LIVE_OK")
		quit(0)
	else:
		print("USER_ASSET_SOURCE_LIVE_FAILURES %d" % _failures.size())
		for f in _failures:
			push_error(f)
		quit(1)


func _remove_recursive(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if n != "." and n != "..":
			var p := path + "/" + n
			if d.current_is_dir():
				_remove_recursive(p)
			else:
				DirAccess.remove_absolute(p)
		n = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)
