## tests/editor_selection_contract.gd — 编辑器选择组件契约测试（headless）
##
## 跑法：godot --headless --path . --script res://tests/editor_selection_contract.gd
## 覆盖：EditorSelectionRange（归一/包含/clamp 坐标校验/尺寸/changed 信号）、
##       BlockSelector（内置地形全量/素材过滤排序/统一选中信号/再点取消/
##       asset_ready 0.3s 合批/选中恢复与消失清空）、
##       EditorCanvas 区域虚线投影接口（固定高度四边形/跟随地形周界/归一/
##       越界 clamp/无交集清空/模型 resize 收敛/标记可见性）。

extends SceneTree

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const SelectionRangeScript = preload("res://scripts/editor/selection_range.gd")
const BlockSelectorScript = preload("res://scripts/editor/block_selector.gd")
const EditorCanvasScript = preload("res://scripts/editor/editor_canvas.gd")

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("[editor_selection_contract] FAIL: %s" % msg)
		print("EDITOR_SELECTION_FAIL: %s" % msg)


func _run() -> void:
	_test_selection_range()
	_test_block_selector()
	_test_canvas_region()
	if _failures > 0:
		print("EDITOR_SELECTION_CONTRACT_FAIL: %d 项未过" % _failures)
		quit(1)
		return
	print("EDITOR_SELECTION_CONTRACT_OK")
	quit(0)


# ============================================================
# A. EditorSelectionRange
# ============================================================

func _test_selection_range() -> void:
	# ---- A1 初始未激活 ----
	var r := SelectionRangeScript.new()
	_expect(not r.is_active(), "A1 初始未激活")
	_expect(r.size() == Vector3i.ZERO, "A1 未激活 size=(0,0,0)")
	_expect(r.normalized().is_empty(), "A1 未激活 normalized 为空")
	_expect(r.cell_count() == 0, "A1 未激活 cell_count=0")

	# ---- A2 归一化与尺寸 ----
	r.begin(Vector3i(5, 2, 0))
	_expect(r.is_active(), "A2 begin 后激活")
	r.update_focus(Vector3i(1, 4, 3))
	_expect(r.min_corner() == Vector3i(1, 2, 0), "A2 min 归一")
	_expect(r.max_corner() == Vector3i(5, 4, 3), "A2 max 归一")
	_expect(r.size() == Vector3i(5, 3, 4), "A2 尺寸=闭区间边长 (5,3,4)")
	_expect(r.cell_count() == 60, "A2 体积 5*3*4=60")
	_expect(r.z_span() == Vector2i(0, 3), "A2 z_span=(0,3)")
	var n: Dictionary = r.normalized()
	_expect(n.get("min") == Vector3i(1, 2, 0) and n.get("max") == Vector3i(5, 4, 3), "A2 normalized 字典")

	# ---- A3 包含判断 ----
	_expect(r.contains(Vector3i(1, 2, 0)), "A3 含最小角")
	_expect(r.contains(Vector3i(5, 4, 3)), "A3 含最大角")
	_expect(not r.contains(Vector3i(0, 2, 0)), "A3 x 出界不含")
	_expect(not r.contains(Vector3i(1, 2, 4)), "A3 z 出界不含")
	_expect(r.contains_2i(Vector2i(5, 4)), "A3 2D 含")
	_expect(not r.contains_2i(Vector2i(6, 4)), "A3 2D 出界不含")
	_expect(r.cells_2d().size() == 15, "A3 平面格 5*3=15")

	# ---- A4 clamp_to 坐标校验/尺寸更新 ----
	var model := BattlefieldDocScript.create_empty(6, 4)
	r.update_focus(Vector3i(9, -1, 99))
	var still := r.clamp_to(model)
	_expect(still, "A4 clamp 后仍激活")
	_expect(r.focus == Vector3i(5, 0, 16), "A4 focus 夹进 [0,5]x[0,3]x[0,16]")
	_expect(r.size() == Vector3i(1, 3, 17), "A4 clamp 后尺寸更新")

	var r2 := SelectionRangeScript.new()
	r2.begin(Vector3i(-3, 7, 5))
	r2.update_focus(Vector3i(9, 9, 9))
	r2.clamp_to(model)
	_expect(r2.anchor == Vector3i(0, 3, 5), "A4 anchor 负端夹到 (0,3,5)")
	_expect(r2.focus == Vector3i(5, 3, 9), "A4 focus 超大端夹到 (5,3,9)（z=9 在界内保留）")

	# ---- A5 clamp 无交集/空模型/未激活 ----
	var r3 := SelectionRangeScript.new()
	_expect(not r3.clamp_to(model), "A5 未激活 clamp 返回 false")
	var r4 := SelectionRangeScript.new()
	r4.begin_2i(Vector2i(0, 0))
	r4.clamp_to({})
	_expect(not r4.is_active(), "A5 空模型 clamp 清空")

	# ---- A6 平面框选默认 z=0 ----
	var r5 := SelectionRangeScript.new()
	r5.begin_2i(Vector2i(2, 1))
	r5.update_focus(Vector3i(4, 1, 0))
	_expect(r5.min_corner() == Vector3i(2, 1, 0) and r5.max_corner() == Vector3i(4, 1, 0), "A6 平面框选 z 恒 0")

	# ---- A7 changed 信号（lambda 按值捕获：用 Dictionary 引用计数） ----
	var r6 := SelectionRangeScript.new()
	var counter := {"n": 0}
	r6.changed.connect(func(): counter["n"] += 1)
	r6.begin_2i(Vector2i(0, 0))
	_expect(counter["n"] == 1, "A7 begin 发射 changed")
	r6.update_focus(Vector3i(0, 0, 0))
	_expect(counter["n"] == 1, "A7 同值 focus 不发射")
	r6.update_focus(Vector3i(1, 0, 0))
	_expect(counter["n"] == 2, "A7 变值 focus 发射")
	r6.clear()
	_expect(counter["n"] == 3, "A7 clear 发射")
	r6.clear()
	_expect(counter["n"] == 3, "A7 重复 clear 不发射")


# ============================================================
# B. BlockSelector（注入假 service/adapter）
# ============================================================

class FakeAssetService:
	extends RefCounted
	signal asset_ready(asset_id: String)
	var entries: Array = []
	var requested: Array = []
	var missing: Dictionary = {}  # id -> true 表示视觉未就绪
	func list_assets() -> Array:
		return entries
	func get_asset_state(_asset_id: String) -> Dictionary:
		if missing.has(_asset_id):
			return {"status": "missing"}
		return {"status": "ready"}
	func request_asset_image(asset_id: String) -> void:
		requested.append(asset_id)


class FakeAdapter:
	extends RefCounted
	var resolve_many_calls := 0
	var resolved_ids: Array = []
	func resolve(_asset_id: String) -> Dictionary:
		return {}
	func resolve_many(ids: Array, _p_cache: bool = true) -> Dictionary:
		resolve_many_calls += 1
		resolved_ids = ids.duplicate()
		var out := {}
		for id in ids:
			out[id] = {}
		return out
	func clear_cache(_asset_id: String = "") -> void:
		pass


func _test_block_selector() -> void:
	var service := FakeAssetService.new()
	service.missing = {"e_missing": true}
	service.entries = [
		{"id": "b_land", "kind": "terrain", "saved": true, "name": "地块B"},
		{"id": "a_land", "kind": "terrain", "saved": true, "name": "地块A"},
		{"id": "c_plant", "kind": "plant", "saved": true, "name": "植物C"},
		{"id": "d_unsaved", "kind": "terrain", "saved": false, "name": "未保存D"},
		{"id": "e_missing", "kind": "terrain", "saved": true, "name": "缺图E"},
	]
	var adapter := FakeAdapter.new()

	var host := Control.new()
	host.name = "BlockSelectorHost"
	get_root().add_child(host)
	var sel := BlockSelectorScript.new()
	host.add_child(sel)
	sel.setup(service, adapter)

	var sigs: Array = []
	sel.selection_changed.connect(func(kind: StringName, id: String): sigs.append([kind, id]))

	# ---- B1 内置地形全量 ----
	var terrain_count: int = BattlefieldDocScript.TERRAIN_GLYPH.size()
	_expect(sel._terrain_buttons.size() == terrain_count, "B1 内置地形按钮全量 %d" % terrain_count)
	var first_terrain: StringName = BattlefieldDocScript.TERRAIN_GLYPH.keys()[0]

	# ---- B2 素材过滤（terrain+saved）与稳定排序 ----
	_expect(sel._asset_buttons.size() == 3, "B2 只列已保存 terrain（a/b/e）")
	var asset_ids: Array = sel._asset_buttons.keys()
	asset_ids.sort()
	_expect(String(asset_ids[0]) == "a_land" and String(asset_ids[2]) == "e_missing", "B2 按 id 排序")
	_expect(service.requested.has("e_missing"), "B2 缺图素材触发 request_asset_image")

	# ---- B3 统一选中信号：地形/素材/程序化 ----
	_expect(sel.select_terrain(first_terrain), "B3 select_terrain 成功")
	_expect(sigs.size() == 1 and sigs[0][0] == &"terrain" and String(sigs[0][1]) == String(first_terrain), "B3 地形选中信号")
	var got: Dictionary = sel.selected()
	_expect(got.get("kind") == &"terrain", "B3 selected().kind=terrain")
	_expect(sel.select_asset("a_land"), "B3 select_asset 成功")
	_expect(sigs.size() == 2 and sigs[1][0] == &"asset" and String(sigs[1][1]) == "a_land", "B3 素材选中信号")
	_expect(sel.selected().get("id") == "a_land", "B3 selected().id=a_land")
	_expect(not sel.select_terrain(&"__nope__"), "B3 未知地形返回 false")
	_expect(not sel.select_asset("__missing__"), "B3 网格外素材返回 false")
	_expect(sel.selected().get("id") == "a_land", "B3 失败选择不改状态")

	# ---- B4 再点取消（allow_unpress 路径） ----
	var water_btn: Button = sel._asset_buttons["a_land"]
	water_btn.set_pressed_no_signal(false)
	water_btn.pressed.emit()
	_expect(sigs.size() == 3 and sigs[2][0] == &"" and String(sigs[2][1]) == "", "B4 取消选中广播空")
	_expect(sel.selected().get("kind") == &"", "B4 selected().kind=空")

	# ---- B5 deselect ----
	sel.select_asset("a_land")
	sel.deselect()
	_expect(sigs.size() == 5 and String(sigs[4][1]) == "", "B5 deselect 广播空")

	# ---- B6 asset_ready 0.3s 合批 ----
	var rebuild0: int = sel.debug_rebuild_count
	var many0: int = adapter.resolve_many_calls
	sel.on_asset_ready("a_land")
	sel.on_asset_ready("b_land")
	_expect(sel.debug_rebuild_count == rebuild0, "B6 事件到达不立即重建")
	_expect(adapter.resolve_many_calls == many0, "B6 事件到达不触发 resolve_many")
	sel._flush_thumbs()
	_expect(sel.debug_rebuild_count == rebuild0 + 1, "B6 合批后整体重建一次")
	_expect(adapter.resolve_many_calls == many0 + 1, "B6 合批只一次库加载")

	# ---- B7 选中恢复与消失清空 ----
	sel.select_asset("b_land")
	_expect(sel.selected().get("id") == "b_land", "B7 选中 b_land")
	service.entries = service.entries.filter(func(e): return String(e.get("id")) != "b_land")
	sel.refresh_assets()
	_expect(not sel._asset_buttons.has("b_land"), "B7 消失素材不在网格")
	_expect(sel.selected().get("kind") == &"", "B7 消失素材清空选中")
	_expect(sigs.size() >= 6 and String(sigs[sigs.size() - 1][1]) == "", "B7 清空广播取消")
	sel.select_asset("a_land")
	sel.refresh_assets()
	_expect(sel.selected().get("id") == "a_land", "B7 仍存在的选中经重建恢复")

	# ---- B8 无 service：仅内置地形 ----
	var sel2 := BlockSelectorScript.new()
	host.add_child(sel2)
	sel2.setup(null, null)
	_expect(sel2._terrain_buttons.size() == terrain_count, "B8 无 service 内置地形仍全量")
	_expect(sel2._asset_buttons.is_empty(), "B8 无 service 素材组为空")
	_expect(not sel2.select_asset("a_land"), "B8 无 service select_asset 失败")
	_expect(sel2.select_terrain(first_terrain), "B8 无 service 仍可选地形")


# ============================================================
# C. EditorCanvas 区域虚线投影接口
# ============================================================

func _test_canvas_region() -> void:
	var host := Control.new()
	host.name = "CanvasRegionHost"
	get_root().add_child(host)
	var canvas := EditorCanvasScript.new()
	host.add_child(canvas)
	canvas.model = BattlefieldDocScript.create_empty(6, 4)

	# ---- C1 初始无区域 ----
	_expect(not canvas.has_selection_region(), "C1 初始无区域")

	# ---- C2 固定高度平面四边形 ----
	canvas.set_selection_region(Vector2i(1, 1), Vector2i(3, 2), 0)
	_expect(canvas.has_selection_region(), "C2 设置后有效")
	var flat: Array = canvas.region_outline_polylines(Vector2i(1, 1), Vector2i(3, 2), 0)
	_expect(flat.size() == 1, "C2 平面模式单条闭合折线")
	if flat.size() == 1:
		var poly: PackedVector2Array = flat[0]
		_expect(poly.size() == 5, "C2 四角+闭合点=5")
		var spread := false
		for i in poly.size():
			if poly[i].distance_to(poly[0]) > 1.0:
				spread = true
		_expect(spread, "C2 四角不共点（真实四边形）")
	_expect(canvas._region_marker.visible, "C2 设置后标记可见")
	_expect(canvas._region_marker.polylines.size() == 1, "C2 标记已刷入折线")

	# ---- C3 归一化：端点顺序无关 ----
	var a: PackedVector2Array = canvas.region_outline_polylines(Vector2i(1, 1), Vector2i(3, 2), 0)[0]
	var b: PackedVector2Array = canvas.region_outline_polylines(Vector2i(3, 2), Vector2i(1, 1), 0)[0]
	_expect(a.size() == b.size(), "C3 归一后点数一致")
	var same := true
	for i in a.size():
		if a[i].distance_to(b[i]) > 0.001:
			same = false
	_expect(same, "C3 端点顺序不改变折线")

	# ---- C4 跟随地形周界（默认 z=-1） ----
	var follow: Array = canvas.region_outline_polylines(Vector2i(1, 1), Vector2i(3, 2))
	_expect(follow.size() == 4, "C4 北/东/南/西四条周界折线")
	if follow.size() == 4:
		_expect((follow[0] as PackedVector2Array).size() == 4, "C4 北边=宽+1 点")
		_expect((follow[1] as PackedVector2Array).size() == 3, "C4 东边=高+1 点")
		_expect((follow[2] as PackedVector2Array).size() == 4, "C4 南边=宽+1 点")
		_expect((follow[3] as PackedVector2Array).size() == 3, "C4 西边=高+1 点")
	canvas.set_selection_region(Vector2i(1, 1), Vector2i(3, 2))
	_expect(canvas.has_selection_region(), "C4 默认 z=-1 跟随地形")
	_expect(canvas._region_marker.polylines.size() == 4, "C4 跟随地形标记四段")

	# ---- C5 越界 clamp 与无交集清空 ----
	canvas.set_selection_region(Vector2i(10, 10), Vector2i(12, 12))
	_expect(not canvas.has_selection_region(), "C5 正向完全越界无交集清空")
	canvas.set_selection_region(Vector2i(-9, -9), Vector2i(-1, -1))
	_expect(not canvas.has_selection_region(), "C5 负向无交集自动清空")
	canvas.set_selection_region(Vector2i(0, 0), Vector2i(20, 20))
	_expect(canvas.has_selection_region(), "C5 部分越界保留交集")
	_expect(canvas.selection_region.get("max") == Vector2i(5, 3), "C5 交集右下角=模型边界")
	canvas.set_selection_region(Vector2i(4, 2), Vector2i(10, 10))
	_expect(canvas.selection_region.get("min") == Vector2i(4, 2) and canvas.selection_region.get("max") == Vector2i(5, 3), "C5 正向部分越界夹回 (5,3)")

	# ---- C6 清空 ----
	canvas.clear_selection_region()
	_expect(not canvas.has_selection_region(), "C6 clear 后无效")
	_expect(not canvas._region_marker.visible, "C6 标记隐藏")

	# ---- C7 模型 resize 收敛 ----
	canvas.set_selection_region(Vector2i(1, 1), Vector2i(5, 3))
	# create_empty 下限 MIN_SIZE=4：3x3 请求实际生成 4x4 模型
	canvas.model = BattlefieldDocScript.create_empty(3, 3)
	_expect(canvas.has_selection_region(), "C7 resize 后仍有效（交集）")
	_expect(int(canvas.model.get("width")) == 4 and int(canvas.model.get("height")) == 4, "C7 MIN_SIZE=4 生效")
	_expect(canvas.selection_region.get("min") == Vector2i(1, 1) and canvas.selection_region.get("max") == Vector2i(3, 3), "C7 端点收敛到新边界")
	host.queue_free()
