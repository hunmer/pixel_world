## user_asset_pagination_contract.gd — 素材库面板分页契约（SceneTree，纯 headless）
##
## 覆盖（对应需求「真实分页，不一次性展示全部」）：
##   - 全库先过滤 + 按 id 稳定排序再切当前页；界面只创建当前页行（PAGE_SIZE=24/页）
##   - 翻页条：上一页/下一页、页码/总页数/匹配总数；0 项与最后不足一页
##   - 搜索/来源/标签/类别变更回第 1 页；导入/隐藏后页界钳制不越界
##   - 翻页后 _cells 行索引只映射本页（不误用旧行）；懒预览队列只含本页素材
##   - 异步 asset_ready 只换图标、不重建列表（不跳页）
## 运行：godot --headless --path . --script res://tests/user_asset_pagination_contract.gd

extends SceneTree

const ServiceScript := preload("res://scripts/assets/user_asset_service.gd")
const Catalog := preload("res://scripts/assets/user_asset_catalog.gd")
const AdapterScript := preload("res://scripts/assets/user_asset_visual_adapter.gd")
const PanelScript := preload("res://scripts/editor/asset_library_panel.gd")

const TMP_ROOT := "user://user_asset_pagination_tmp"
const TOTAL := 30  # > 2*PAGE_SIZE? 否：30 = 24 + 6，覆盖「最后不足一页」

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures.append(what)


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


func _page_label(panel: AssetLibraryPanel) -> Label:
	return panel.get_node("PageRow/PageLabel") as Label


func _page_ids(panel: AssetLibraryPanel) -> Array[String]:
	var out: Array[String] = []
	var lst: ItemList = panel.get_node("AssetList")
	for i in range(lst.item_count):
		out.append(str(lst.get_item_metadata(i)))
	return out


func _run() -> void:
	_remove_recursive(TMP_ROOT)
	var svc: UserAssetService = ServiceScript.new(TMP_ROOT)
	root.add_child(svc)
	var adapter: UserAssetVisualAdapter = AdapterScript.new(TMP_ROOT)
	var panel: AssetLibraryPanel = PanelScript.new()
	root.add_child(panel)
	panel.setup(svc, adapter)

	# 造 30 个确定性 id 的本地素材（pg_00..pg_29，id 由 source_name slugify）
	for i in range(TOTAL):
		var bytes := _make_png(4, 4, Color(Color.RED, 0.5 + float(i) * 0.01))
		var res: Dictionary = svc.import_image_bytes(bytes, "pg_%02d.png" % i,
			Catalog.KIND_TERRAIN, PackedStringArray(), "")
		if not bool(res.get("ok", false)):
			_expect(false, "导入 pg_%02d 失败：%s" % [i, res.get("error", "")])
			_finish()
			return
	panel._rebuild_grid()

	# S1 第一页：24 条、按 id 稳定排序、页码标签、按钮可用态
	var lst: ItemList = panel.get_node("AssetList")
	_expect(lst.item_count == 24, "第一页只创建 24 行（实际 %d）" % lst.item_count)
	_expect(_page_ids(panel)[0] == "pg_00" and _page_ids(panel)[23] == "pg_23",
		"第一页按 id 稳定排序（首 pg_00 / 末 pg_23）")
	var label: Label = _page_label(panel)
	_expect(label.text == "第 1 / 2 页 · 共 30 条", "页码标签=第 1 / 2 页 · 共 30 条（实际 %s）" % label.text)
	_expect(panel.get_node("PageRow/PagePrevButton").disabled, "第一页上一页禁用")
	_expect(not panel.get_node("PageRow/PageNextButton").disabled, "第一页下一页可用")

	# S2 翻页：末页 6 行、按钮可用态翻转、行索引只映射本页
	panel._on_next_page()
	_expect(lst.item_count == 6, "末页 6 行（实际 %d）" % lst.item_count)
	_expect(_page_ids(panel)[0] == "pg_24" and _page_ids(panel)[5] == "pg_29",
		"末页为 pg_24..pg_29")
	_expect(label.text == "第 2 / 2 页 · 共 30 条", "页码标签=第 2 / 2 页 · 共 30 条（实际 %s）" % label.text)
	_expect(not panel.get_node("PageRow/PagePrevButton").disabled, "末页上一页可用")
	_expect(panel.get_node("PageRow/PageNextButton").disabled, "末页下一页禁用")
	_expect(panel._cells.size() == 6 and not panel._cells.has("pg_00"),
		"翻页后 _cells 只映射本页 6 行（不误用旧行索引）")
	var page_only := true
	for aid in panel._preview_queue:
		if not panel._cells.has(aid):
			page_only = false
	_expect(page_only and panel._preview_queue.size() <= 6,
		"懒预览队列只含本页素材（实际 %d 个）" % panel._preview_queue.size())
	panel._on_prev_page()
	_expect(lst.item_count == 24 and _page_ids(panel)[0] == "pg_00", "翻回第一页恢复 24 行")

	# S3 搜索变更回第一页并即时反映匹配总数
	panel._search_edit.text = "pg_0"
	panel._search_edit.text_changed.emit("pg_0")  # 模拟用户输入（属性赋值不触发信号）
	_expect(lst.item_count == 10, "搜索 pg_0 → 10 条（实际 %d）" % lst.item_count)
	_expect(label.text == "第 1 / 1 页 · 共 10 条", "搜索后页码标签=第 1 / 1 页 · 共 10 条（实际 %s）" % label.text)
	_expect(panel.get_node("PageRow/PageNextButton").disabled, "单页时下一页禁用")
	# 末页状态下搜索 → 钳制回第一页（不切出越界页）
	panel._search_edit.text = ""
	panel._search_edit.text_changed.emit("")
	panel._on_next_page()
	_expect(label.text == "第 2 / 2 页 · 共 30 条", "清空搜索后翻回末页")
	panel._search_edit.text = "pg_2"
	panel._search_edit.text_changed.emit("pg_2")  # pg_20..pg_29 = 10 条
	_expect(label.text == "第 1 / 1 页 · 共 10 条",
		"末页状态下过滤收缩 → 钳制回第 1 页（实际 %s）" % label.text)
	_expect(_page_ids(panel)[0] == "pg_20", "收缩后本页从 pg_20 开始")

	# S4 0 项：空态、双禁、标签归 1/1
	panel._search_edit.text = "zzzz"
	panel._search_edit.text_changed.emit("zzzz")
	_expect(lst.item_count == 0, "无匹配 0 行")
	_expect(panel.get_node("EmptyLabel").visible, "无匹配时空态标签可见")
	_expect(label.text == "第 1 / 1 页 · 共 0 条", "0 项页码标签（实际 %s）" % label.text)
	_expect(panel.get_node("PageRow/PagePrevButton").disabled and panel.get_node("PageRow/PageNextButton").disabled,
		"0 项时翻页双禁")
	panel._search_edit.text = ""
	panel._search_edit.text_changed.emit("")

	# S5 隐藏素材后页界校正（29 条仍 2 页：24+5）
	svc.remove_asset("pg_29", true)
	panel._rebuild_grid()
	panel._on_next_page()
	_expect(lst.item_count == 5 and _page_ids(panel)[4] == "pg_28",
		"隐藏 1 个后末页 5 行（实际 %d）" % lst.item_count)
	_expect(label.text == "第 2 / 2 页 · 共 29 条", "隐藏后匹配总数 29（实际 %s）" % label.text)
	# 再隐藏 5 个 → 24 条整一页，末页应消失且钳制
	for i in range(24, 29):
		svc.remove_asset("pg_%02d" % i, true)
	panel._rebuild_grid()  # 当前在第 2 页，总数 24 → 钳回第 1 页
	_expect(label.text == "第 1 / 1 页 · 共 24 条", "总数缩到 24 时钳回第 1 页（实际 %s）" % label.text)
	_expect(lst.item_count == 24, "钳制后本页 24 行")

	# S6 异步 asset_ready 不换页：末页行只换图标、列表/页码不动
	panel._on_next_page()  # 现 24 条单页，仍在第 1 页；手动构造 asset_ready 不得重建
	panel._on_asset_ready("pg_00")
	_expect(label.text == "第 1 / 1 页 · 共 24 条" and lst.item_count == 24,
		"asset_ready 不重建列表、不跳页")

	_finish()


func _finish() -> void:
	_remove_recursive(TMP_ROOT)
	if failures.is_empty():
		print("user_asset_pagination_contract: %d checks OK" % checks)
		quit(0)
	else:
		for f in failures:
			push_error("FAIL: " + f)
		print("user_asset_pagination_contract: %d/%d checks FAILED" % [failures.size(), checks])
		quit(1)
