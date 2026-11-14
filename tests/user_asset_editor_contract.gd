## user_asset_editor_contract.gd — 素材编辑器集成契约（SceneTree，headless）
##
## 覆盖：
##  S1 UserAssetService.update_asset —— 改名/分类/标签/render 编辑、校验失败回滚、持久化 round-trip
##  S2 UserAssetVisualAdapter.clear_cache —— 单素材逐出与全量清空
##  S3 map_editor 接入 —— 素材 Tab 工具互斥（选中素材→Tool.ASSET）、地块/植物放置与再点取消、
##      橡皮三层清除、历史撤销/重做含 tile_overrides、save_current 写入 user_assets 快照、
##      库中隐藏素材后重存保留旧快照、loader 回读 + 渲染层区块断言
## 运行：godot --headless --path . --script res://tests/user_asset_editor_contract.gd

extends SceneTree

const ServiceScript := preload("res://scripts/assets/user_asset_service.gd")
const Catalog := preload("res://scripts/assets/user_asset_catalog.gd")
const AdapterScript := preload("res://scripts/assets/user_asset_visual_adapter.gd")
const DocScript := preload("res://scripts/editor/battlefield_doc.gd")
const LoaderScript := preload("res://scripts/core/battlefield_loader.gd")
const RendererScript := preload("res://scripts/iso/battlefield_renderer.gd")

const TMP_ROOT := "user://user_asset_editor_tmp"
const MAP_PATH := "user://battlefields/contract_asset_map.json"
const MAP_PATH_RES := "res://data/battlefields/contract_asset_map.json"  # save_model 开发版优先写 res://

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)
		push_error("FAIL: " + msg)


func _make_png(w: int, h: int, color: Color) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img.save_png_to_buffer()


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


func _finish() -> void:
	if failures.is_empty():
		print("user_asset_editor_contract: %d checks OK" % checks)
		quit(0)
	else:
		print("user_asset_editor_contract: %d FAILURES / %d checks" % [failures.size(), checks])
		quit(1)


func _run() -> void:
	_remove_recursive(TMP_ROOT)
	if FileAccess.file_exists(MAP_PATH):
		DirAccess.remove_absolute(MAP_PATH)
	if FileAccess.file_exists(MAP_PATH_RES):
		DirAccess.remove_absolute(MAP_PATH_RES)
	DirAccess.make_dir_recursive_absolute(TMP_ROOT + "/src")
	var png_a := _make_png(4, 4, Color.RED)
	var png_b := _make_png(3, 5, Color.BLUE)
	for pair in [["terra_a.png", png_a], ["flora_b.png", png_b]]:
		var f := FileAccess.open(TMP_ROOT + "/src/" + pair[0], FileAccess.WRITE)
		f.store_buffer(pair[1])
		f.close()

	var svc: Node = ServiceScript.new(TMP_ROOT)
	root.add_child(svc)
	var r_a: Dictionary = svc.import_local_file(TMP_ROOT + "/src/terra_a.png", Catalog.KIND_TERRAIN)
	_expect(bool(r_a.get("ok", false)), "S0 导入 terra_a 应成功: " + str(r_a.get("error", "")))
	var r_b: Dictionary = svc.import_local_file(TMP_ROOT + "/src/flora_b.png", Catalog.KIND_PLANT)
	_expect(bool(r_b.get("ok", false)), "S0 导入 flora_b 应成功: " + str(r_b.get("error", "")))
	var terra_a: Dictionary = svc.find_by_id("terra_a")
	var flora_b: Dictionary = svc.find_by_id("flora_b")
	_expect(not terra_a.is_empty() and not flora_b.is_empty(), "S0 两条素材应在库中")

	# --- S1 update_asset ---
	var upd: Dictionary = svc.update_asset("terra_a", {
		"name": "赤红地块", "kind": Catalog.KIND_PLANT,
		"tags": ["stone", "road"],
		"render": {"mode": Catalog.RENDER_MODE_CROP, "crop": {"x": 0, "y": 0, "w": 2, "h": 2},
			"pivot": {"x": 0.5, "y": 1.0}, "scale": 1.0, "footprint": {"w": 1, "h": 1}},
	})
	_expect(bool(upd.get("ok", false)), "S1 合法 update_asset 应成功: " + str(upd.get("error", "")))
	var after: Dictionary = svc.find_by_id("terra_a")
	_expect(String(after.get("name", "")) == "赤红地块", "S1 名称应更新")
	_expect(String(after.get("kind", "")) == Catalog.KIND_PLANT, "S1 分类应更新")
	_expect((after.get("tags", []) as Array).has("stone"), "S1 标签应更新")
	_expect(String((after.get("render", {}) as Dictionary).get("mode", "")) == Catalog.RENDER_MODE_CROP, "S1 render.mode 应更新")

	var svc_reload: Node = ServiceScript.new(TMP_ROOT)
	root.add_child(svc_reload)
	var reloaded: Dictionary = svc_reload.find_by_id("terra_a")
	_expect(String(reloaded.get("name", "")) == "赤红地块", "S1 更新应持久化（新实例可读回）")

	var bad: Dictionary = svc.update_asset("terra_a", {"render": {"mode": "weird"}})
	_expect(not bool(bad.get("ok", false)), "S1 非法 render.mode 应失败")
	_expect(String((svc.find_by_id("terra_a").get("render", {}) as Dictionary).get("mode", "")) == Catalog.RENDER_MODE_CROP,
		"S1 非法更新应回滚（render.mode 不变）")
	var not_dict: Dictionary = svc.update_asset("terra_a", {"render": "nope"})
	_expect(not bool(not_dict.get("ok", false)), "S1 render 非对象应失败")
	var missing: Dictionary = svc.update_asset("ghost_asset", {"name": "x"})
	_expect(not bool(missing.get("ok", false)), "S1 未知 id 应失败")
	# S1 把 terra_a 分类改为了 plant，恢复 terrain 供 S3 地块放置使用
	svc.update_asset("terra_a", {"kind": Catalog.KIND_TERRAIN})

	# --- S2 adapter.clear_cache ---
	var adapter: RefCounted = AdapterScript.new(TMP_ROOT)
	var vis: Dictionary = adapter.resolve("terra_a")
	_expect(not vis.is_empty() and vis.has("texture"), "S2 resolve 应返回视觉")
	_expect(adapter.cache_size() >= 1, "S2 缓存应有条目")
	var size_before: int = adapter.cache_size()
	adapter.clear_cache("terra_a")
	_expect(adapter.cache_size() <= size_before, "S2 clear_cache(单素材) 应逐出该素材缓存")
	adapter.clear_cache()
	_expect(adapter.cache_size() == 0, "S2 clear_cache() 全量清空应为 0")

	# --- S3 map_editor 接入 ---
	var packed: PackedScene = load("res://scenes/MapEditor.tscn")
	_expect(packed != null, "S3 MapEditor.tscn 应可加载")
	var editor: Control = packed.instantiate()
	root.add_child(editor)
	await process_frame
	await process_frame
	# 换入隔离的 service/adapter（编辑器默认指向 user://custom_assets）
	var ed_svc: Node = ServiceScript.new(TMP_ROOT)
	root.add_child(ed_svc)
	var ed_adapter: RefCounted = AdapterScript.new(TMP_ROOT)
	editor._asset_service = ed_svc
	editor._asset_adapter = ed_adapter
	editor._canvas.asset_adapter = ed_adapter
	editor._asset_panel.setup(ed_svc, ed_adapter)

	_expect(int(editor.Tool.ASSET) == 8, "S3 Tool.ASSET 应为 8")
	_expect(editor._asset_panel.service == ed_svc and editor._asset_panel.adapter == ed_adapter, "S3 面板 setup 应换源成功")

	var tabs: TabContainer = editor.find_child("ToolTabs", true, false)
	_expect(tabs != null and tabs.get_tab_count() == 7, "S3 应有 7 个 Tab")
	tabs.current_tab = 2  # 地形
	await process_frame
	_expect(editor._active_tool() == editor.Tool.PAINT, "S3 地形页无选中素材时应为 PAINT")

	# 选中地块素材 → ASSET 工具
	editor._on_asset_selected(ed_svc.find_by_id("terra_a"))
	_expect(editor._active_tool() == editor.Tool.ASSET, "S3 选中素材后地形页工具应为 ASSET")
	_expect(not (editor._canvas.asset_preview_visual as Dictionary).is_empty(), "S3 选中素材后画布应有预览 visual")

	editor._apply_tool(Vector2i(1, 1))
	_expect(String(DocScript.tile_override_at(editor.model, Vector2i(1, 1))) == "terra_a", "S3 地块素材应写入 tile_override")
	editor._apply_tool(Vector2i(1, 1))  # 再点取消
	_expect(String(DocScript.tile_override_at(editor.model, Vector2i(1, 1))).is_empty(), "S3 地块素材再点应取消")

	editor._on_asset_selected(ed_svc.find_by_id("flora_b"))
	_expect(editor._active_tool() == editor.Tool.ASSET, "S3 选中植物素材工具仍为 ASSET")
	editor._apply_tool(Vector2i(2, 2))
	_expect(String(DocScript.prop_asset_at(editor.model, Vector2i(2, 2))) == "flora_b", "S3 植物素材应写入 prop_asset 通道")
	editor._apply_tool(Vector2i(2, 2))
	_expect(String(DocScript.prop_asset_at(editor.model, Vector2i(2, 2))).is_empty(), "S3 植物素材再点应取消")

	# 放置后历史撤销/重做
	editor._on_asset_selected(ed_svc.find_by_id("terra_a"))
	editor._apply_tool(Vector2i(1, 1))
	editor._undo()
	_expect(String(DocScript.tile_override_at(editor.model, Vector2i(1, 1))).is_empty(), "S3 撤销应回退 tile_override")
	editor._redo()
	_expect(String(DocScript.tile_override_at(editor.model, Vector2i(1, 1))) == "terra_a", "S3 重做应恢复 tile_override")

	# 选地形图例按钮 → 清空素材选择（须选一个"当前未选中"的按钮：对已是 pressed 的
	# 按钮再赋 button_pressed 是 no-op，不触发 ButtonGroup.pressed 处理器）
	var prev_terrain: StringName = editor.current_terrain
	var pick_btn: Button = null
	for t: StringName in editor._terrain_buttons:
		if t != editor.current_terrain:
			pick_btn = editor._terrain_buttons[t]
			break
	pick_btn.button_pressed = true
	await process_frame
	_expect(editor.current_terrain != prev_terrain, "S3 地形按钮按下应切换 current_terrain")
	_expect((editor._selected_asset as Dictionary).is_empty(), "S3 选地形按钮应清空素材选择")
	_expect(editor._active_tool() != editor.Tool.ASSET, "S3 清空素材后工具不应为 ASSET")

	# 植物素材放 (2,2)，然后橡皮三层清除
	editor._on_asset_selected(ed_svc.find_by_id("flora_b"))
	editor._apply_tool(Vector2i(2, 2))
	tabs.current_tab = 0  # 文件页：工具栏 ERASE 生效
	await process_frame
	editor._tool_buttons[editor.Tool.ERASE].button_pressed = true
	await process_frame
	_expect(editor.current_tool == editor.Tool.ERASE, "S3 ERASE 应为当前工具")
	editor._apply_tool(Vector2i(2, 2))
	_expect(String(DocScript.prop_asset_at(editor.model, Vector2i(2, 2))).is_empty(), "S3 橡皮应清除素材 prop")
	editor._apply_tool(Vector2i(1, 1))
	_expect(String(DocScript.tile_override_at(editor.model, Vector2i(1, 1))).is_empty(), "S3 橡皮应清除 tile_override")

	# --- S9 方块页「素材方块」列表：本地就绪的地形素材出现在方块 Tab，点选后画笔放置 ---
	editor._rebuild_block_asset_grid()
	var block_grid: GridContainer = editor.find_child("BlockAssetGrid", true, false)
	_expect(block_grid != null, "S9 方块页应有 BlockAssetGrid")
	_expect(editor._block_asset_buttons.has("terra_a"), "S9 terra_a 应在素材方块列表")
	_expect(not editor._block_asset_buttons.has("flora_b"), "S9 flora_b(plant) 不应出现在素材方块列表")
	# 只列已下载（本地有缓存）的方块：删掉 blob 后应从列表消失（一键清空按钮同理），恢复后回归
	var terra_sha: String = String((ed_svc.find_by_id("terra_a") as Dictionary).get("sha256", ""))
	var terra_blob: String = ed_svc.blob_path_for_sha(terra_sha)
	DirAccess.remove_absolute(terra_blob)
	editor._rebuild_block_asset_grid()
	_expect(not editor._block_asset_buttons.has("terra_a"), "S9 删掉本地缓存后 terra_a 应从素材方块列表消失")
	var rf := FileAccess.open(TMP_ROOT + "/src/terra_a.png", FileAccess.READ)
	var restored := false
	if rf != null:
		var rbytes := rf.get_buffer(rf.get_length())
		rf.close()
		# 直接按内容寻址路径写回 blob（等价于重新下载落盘；import_image_bytes 对同 sha 走
		# 去重捷径不重写文件，故不用它恢复）
		DirAccess.make_dir_recursive_absolute(terra_blob.get_base_dir())
		var wf := FileAccess.open(terra_blob, FileAccess.WRITE)
		if wf != null:
			wf.store_buffer(rbytes)
			wf.close()
		restored = FileAccess.file_exists(terra_blob)
	_expect(restored, "S9 写回 blob 后文件恢复（等价重新下载落盘）")
	editor._rebuild_block_asset_grid()
	_expect(editor._block_asset_buttons.has("terra_a"), "S9 缓存恢复后 terra_a 回到素材方块列表")
	(editor._block_asset_buttons["terra_a"] as Button).pressed.emit()  # 模拟点选按钮
	_expect(editor._selected_block_asset == "terra_a", "S9 点选后方块页选中 terra_a")
	tabs.current_tab = 3  # 方块
	await process_frame
	_expect(editor._active_tool() == editor.Tool.ASSET, "S9 方块页选中素材后工具应为 ASSET")
	editor._apply_tool(Vector2i(3, 3))
	_expect(String(DocScript.tile_override_at(editor.model, Vector2i(3, 3))) == "terra_a", "S9 方块页素材应写入 tile_override")
	editor._apply_tool(Vector2i(3, 3))  # 同格再点取消
	_expect(String(DocScript.tile_override_at(editor.model, Vector2i(3, 3))).is_empty(), "S9 方块页素材再点应取消")
	# 再点已选中按钮 = 取消选中 → 工具回 SELECT
	editor._on_block_asset_btn_pressed("terra_a")
	_expect(editor._selected_block_asset.is_empty(), "S9 再点应取消方块页选中")
	_expect(editor._active_tool() == editor.Tool.SELECT, "S9 取消后方块页工具回 SELECT")
	# 互斥：素材 Tab 选中应清空方块页选中（反之亦然）
	editor._on_block_asset_btn_pressed("terra_a")
	editor._on_asset_selected(ed_svc.find_by_id("flora_b"))
	_expect(editor._selected_block_asset.is_empty(), "S9 素材 Tab 选中应清空方块页选中")
	tabs.current_tab = 2  # 回地形页
	await process_frame

	# 重新放两样（先切回地形页，否则 _active_tool 仍是文件页工具栏的 ERASE）
	tabs.current_tab = 2  # 地形
	await process_frame
	editor._on_asset_selected(ed_svc.find_by_id("terra_a"))
	editor._apply_tool(Vector2i(1, 1))
	editor._on_asset_selected(ed_svc.find_by_id("flora_b"))
	editor._apply_tool(Vector2i(2, 2))
	editor.place_unit(Vector2i(0, 0), "player", "swordsman", 1)
	editor.place_unit(Vector2i(4, 4), "enemy", "berserker", 1)
	editor._id_edit.text = "contract_asset_map"
	var save_res: Dictionary = editor.save_current()
	_expect(bool(save_res.get("ok", false)), "S3 save_current 应成功: " + str(save_res.get("error", "")))

	var save_path := String(save_res.get("path", ""))
	_expect(not save_path.is_empty(), "S3 save_current 应返回存档路径")
	var raw := FileAccess.get_file_as_string(save_path)
	_expect(not raw.is_empty(), "S3 存档文件应存在且非空")
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		_expect(false, "S3 存档应可解析为对象")
		_finish()
		return
	var load_res: Dictionary = LoaderScript.load_battlefield_inline(parsed, "contract_asset_map")
	_expect(bool(load_res.get("ok", false)), "S3 loader 回读应通过权威校验: " + str(load_res.get("error", "")))
	var chapter: Dictionary = load_res.get("chapter", {})
	var tile_entry: Variant = (chapter.get("tile_overrides", {}) as Dictionary).get("1,1", {})
	_expect(tile_entry is Dictionary and String((tile_entry as Dictionary).get("asset_id", "")) == "terra_a",
		"S3 回读 tile_overrides 应含 terra_a")
	var found_prop := false
	for p in chapter.get("props", []):
		var pd: Dictionary = p
		if String(pd.get("asset_id", "")) == "flora_b" and int(pd.get("x", -1)) == 2 and int(pd.get("y", -1)) == 2:
			found_prop = true
	_expect(found_prop, "S3 回读 props 应含 flora_b 素材条目")
	_expect((chapter.get("user_assets", {}) as Dictionary).has("terra_a")
		and (chapter.get("user_assets", {}) as Dictionary).has("flora_b"),
		"S3 存档应内嵌两条 user_assets 快照")

	# 渲染层：从回读 chapter 建 grid + renderer，断言素材块存在
	var map_rows: Array = chapter.get("map", [])
	var grid: GridSystem = GridSystem.new(int(chapter.get("width", 0)), int(chapter.get("height", 0)), map_rows)
	var renderer: Node2D = RendererScript.new()
	root.add_child(renderer)
	# 与 battle.gd B2 同序：先注入素材覆盖，再 setup 建柱
	renderer.set_custom_assets(ed_adapter.visual_for_entries(chapter.get("props", []), chapter.get("tile_overrides", {})))
	renderer.setup(grid)
	await process_frame
	await process_frame
	var blocks: Array = renderer.cell_blocks_snapshot(Vector2i(1, 1))
	_expect(blocks.size() >= 1, "S3 (1,1) 覆盖格应有渲染块")
	var has_asset_block := false
	for b in blocks:
		var bd: Dictionary = b
		if String(bd.get("asset_id", "")) == "terra_a":
			has_asset_block = true
	_expect(has_asset_block, "S3 (1,1) 应渲染 terra_a 素材块")

	# 隐藏素材后重存：旧快照保留（存档不自拆引用）
	var hid: Dictionary = ed_svc.remove_asset("terra_a", true)
	_expect(bool(hid.get("ok", false)), "S3 隐藏素材(keep_blob) 应成功")
	var save_res2: Dictionary = editor.save_current()
	var raw2 := FileAccess.get_file_as_string(String(save_res2.get("path", save_path)))
	var parsed2: Variant = JSON.parse_string(raw2)
	if not (parsed2 is Dictionary):
		_expect(false, "S3 隐藏素材后重存应可解析")
		_finish()
		return
	var load_res2: Dictionary = LoaderScript.load_battlefield_inline(parsed2, "contract_asset_map")
	_expect(bool(load_res2.get("ok", false)), "S3 隐藏素材后重存仍可回读")
	var chapter2: Dictionary = load_res2.get("chapter", {})
	_expect((chapter2.get("user_assets", {}) as Dictionary).has("terra_a"), "S3 隐藏素材后存档应保留旧快照")

	# 清理
	editor.queue_free()
	_remove_recursive(TMP_ROOT)
	if FileAccess.file_exists(MAP_PATH):
		DirAccess.remove_absolute(MAP_PATH)
	if FileAccess.file_exists(MAP_PATH_RES):
		DirAccess.remove_absolute(MAP_PATH_RES)
	_finish()
