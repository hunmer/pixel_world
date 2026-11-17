## tests/map_editor_building_contract.gd — 建筑编辑契约测试（headless）
##
## 跑法：godot --headless --path . --script res://tests/map_editor_building_contract.gd
## 覆盖：doc 层放置/占用/校验（等高、越界、重叠、单位、rotation）、
##       整栋删除/旋转回环、validate_buildings 含等高、JSON 往返、
##       resize 整栋剔除、load_candidate 坏建筑拒载、user_assets 快照
##       （含背面依赖、库缺失时旧快照兜底）、ed 层工具分发（放置/再点删除/
##       高度编辑拦截/预览驱动）、区域复制/剪切/粘贴/移动的建筑整栋语义
##       （不静默切碎、instance_id 保持、平移预校验原子拒绝）。

extends SceneTree

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const FileIoScript = preload("res://scripts/editor/map_editor_file_io.gd")
const ModelOpsScript = preload("res://scripts/editor/map_editor_model_ops.gd")
const CellToolsScript = preload("res://scripts/editor/map_editor_cell_tools.gd")
const ClipboardScript = preload("res://scripts/editor/map_editor_clipboard.gd")
const RegionClipboardScript = preload("res://scripts/editor/region_clipboard.gd")

const TMP_BAD_EQ := "user://building_contract_bad_eq.json"
const TMP_BAD_OVERLAP := "user://building_contract_bad_overlap.json"
const TMP_GOOD := "user://building_contract_good.json"


func _initialize() -> void:
	call_deferred("_run")


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		push_error("[map_editor_building_contract] FAIL: %s" % msg)
		print("MAP_EDITOR_BUILDING_FAIL: %s" % msg)
		quit(1)


## 构造建筑素材描述符（快照形：kind/render.footprint，可带背面依赖）
func _desc(w: int, h: int, back_id: String = "") -> Dictionary:
	var render := { "footprint": { "w": w, "h": h } }
	if not back_id.is_empty():
		render["back_mode"] = "front_back"
		render["back_asset_id"] = back_id
	return { "kind": "building", "render": render }


func _cells_of(model: Dictionary, entry: Dictionary) -> Array:
	var out: Array = []
	for c: Vector2i in BattlefieldDocScript.BuildingLayoutScript.occupied_cells(entry, model.user_assets):
		out.append(c)
	return out


func _has_cell(cells: Array, x: int, y: int) -> bool:
	return cells.has(Vector2i(x, y))


func _run() -> void:
	# ---- 1. 放置与占用形状 ----
	var m: Dictionary = BattlefieldDocScript.create_empty(10, 8)
	m.user_assets = {
		"hut": _desc(2, 2),
		"hall": _desc(2, 3),
		"back": _desc(1, 1),
	}
	var r1: Dictionary = BattlefieldDocScript.add_building(m, "hut", Vector2i(1, 1), 0, {})
	_expect(bool(r1.get("ok", false)), "2x2 放置成功")
	var e1: Dictionary = r1.get("entry", {})
	_expect(String(e1.get("instance_id", "")) == "b001", "首栋 instance_id=b001")
	var occ1 := BattlefieldDocScript.building_occupancy(m)
	_expect(occ1.size() == 4 and String(occ1.get("2,2", "")) == "b001", "2x2 占用 4 格")
	var r2: Dictionary = BattlefieldDocScript.add_building(m, "hall", Vector2i(4, 1), 0, {})
	_expect(bool(r2.get("ok", false)), "2x3 放置成功")
	_expect(BattlefieldDocScript.building_occupancy(m).size() == 10, "两栋共 10 格占用")

	# rotation 奇偶：1/3 交换 w/h
	var rot_cells := _cells_of(m, { "asset_id": "hall", "x": 0, "y": 0, "rotation": 1 })
	_expect(rot_cells.size() == 6 and _has_cell(rot_cells, 0, 0) and _has_cell(rot_cells, 2, 1)
		and not _has_cell(rot_cells, 2, 2) and not _has_cell(rot_cells, 3, 0),
		"rotation=1 占用 3x2（w/h 交换）")
	var rot_cells0 := _cells_of(m, { "asset_id": "hall", "x": 0, "y": 0, "rotation": 0 })
	_expect(rot_cells0.size() == 6 and _has_cell(rot_cells0, 1, 2) and not _has_cell(rot_cells0, 2, 2),
		"rotation=0 占用 2x3")

	# ---- 2. can_place 拒绝路径 ----
	_expect(not BattlefieldDocScript.can_place_building(m, "", Vector2i(0, 5), 0).is_empty(),
		"空 asset_id 拒绝")
	_expect(not BattlefieldDocScript.can_place_building(m, "hut", Vector2i(0, 5), 4).is_empty(),
		"rotation=4 拒绝")
	_expect(not BattlefieldDocScript.can_place_building(m, "hut", Vector2i(9, 6), 0).is_empty(),
		"右缘越界拒绝")
	_expect(not BattlefieldDocScript.can_place_building(m, "hut", Vector2i(0, 7), 0).is_empty(),
		"下缘越界拒绝")
	_expect(not BattlefieldDocScript.can_place_building(m, "hut", Vector2i(2, 2), 0).is_empty(),
		"与已有建筑重叠拒绝")
	_expect(BattlefieldDocScript.can_place_building(m, "hut", Vector2i(7, 5), 0).is_empty(),
		"空位合法")
	m.units = [{ "class": "swordsman", "name": "U", "level": 1, "x": 8, "y": 6, "faction": "player" }]
	_expect(not BattlefieldDocScript.can_place_building(m, "hut", Vector2i(7, 5), 0).is_empty(),
		"压单位拒绝")
	m.units = []
	BattlefieldDocScript.set_cell_z(m, Vector2i(7, 6), 2)
	_expect(not BattlefieldDocScript.can_place_building(m, "hut", Vector2i(7, 5), 0).is_empty(),
		"底面不等高拒绝")
	BattlefieldDocScript.set_cell_z(m, Vector2i(7, 6), 0)

	# ---- 3. user_assets 快照：背面依赖 + 库缺失旧快照兜底 ----
	var m3: Dictionary = BattlefieldDocScript.create_empty(10, 8)
	var snap: Dictionary = { "tower": _desc(2, 2, "back") }
	snap["back"] = _desc(1, 1)
	var r3: Dictionary = BattlefieldDocScript.add_building(m3, "tower", Vector2i(0, 0), 0, snap)
	_expect(bool(r3.get("ok", false)), "快照放置成功")
	_expect((m3.user_assets as Dictionary).has("tower") and (m3.user_assets as Dictionary).has("back"),
		"快照含主素材与背面依赖")
	# 快照维持：service 为 null → snapshot={} → 用模型旧快照同 footprint 放置
	var r3b: Dictionary = BattlefieldDocScript.add_building(m3, "tower", Vector2i(4, 0), 0, {})
	_expect(bool(r3b.get("ok", false)), "库缺失时模型旧快照兜底放置成功")
	_expect(_cells_of(m3, r3b.get("entry", {})).size() == 4, "兜底快照 footprint 仍 2x2")

	# ---- 4. 删除与旋转 ----
	_expect(BattlefieldDocScript.remove_building_at(m3, Vector2i(1, 1)), "remove_building_at 命中")
	_expect(BattlefieldDocScript.building_entries(m3).size() == 1, "整栋删除后剩 1 栋")
	_expect(not BattlefieldDocScript.remove_building_at(m3, Vector2i(1, 1)), "再删未命中")
	# 旋转回环 0→1→2→3→0（2x2 旋转后形状不变，位置不变）
	var m4: Dictionary = BattlefieldDocScript.create_empty(10, 8)
	m4.user_assets = { "hut": _desc(2, 2) }
	var r4: Dictionary = BattlefieldDocScript.add_building(m4, "hut", Vector2i(2, 2), 0, {})
	var bid: String = r4.entry.instance_id
	for want: int in [1, 2, 3, 0]:
		_expect(BattlefieldDocScript.rotate_building(m4, Vector2i(2, 2)).is_empty(),
			"旋转到 %d 成功" % want)
		_expect(int(BattlefieldDocScript.building_at(m4, Vector2i(2, 2)).get("rotation", -1)) == want,
			"rotation == %d" % want)
	_expect(not BattlefieldDocScript.rotate_building(m4, Vector2i(0, 0)).is_empty(),
		"空格旋转拒绝")
	# 旋转越界失败恢复：hall 2x3 rotation=0（宽2）贴右缘 x=8（占 8..9 ✓）；
	# 旋转到 rotation=1（宽3 → 8..10 越界）拒绝并恢复 rotation=0
	var m4b: Dictionary = BattlefieldDocScript.create_empty(10, 8)
	m4b.user_assets = { "hall": _desc(2, 3) }
	var r4b: Dictionary = BattlefieldDocScript.add_building(m4b, "hall", Vector2i(8, 0), 0, {})
	_expect(bool(r4b.get("ok", false)), "2x3 贴右缘放置成功")
	var err4b := BattlefieldDocScript.rotate_building(m4b, Vector2i(8, 0))
	_expect(not err4b.is_empty(), "旋转导致越界拒绝")
	var after4b: Dictionary = BattlefieldDocScript.building_at(m4b, Vector2i(8, 0))
	_expect(int(after4b.get("rotation", -1)) == 0, "失败后建筑恢复原 rotation=0")

	# ---- 5. validate_buildings（含等高） ----
	var m5: Dictionary = BattlefieldDocScript.create_empty(10, 8)
	m5.user_assets = { "hut": _desc(2, 2) }
	BattlefieldDocScript.add_building(m5, "hut", Vector2i(0, 0), 0, {})
	_expect(BattlefieldDocScript.validate_buildings(m5).is_empty(), "合法模型校验通过")
	BattlefieldDocScript.set_cell_z(m5, Vector2i(1, 1), 3)  # 模拟旧档/外部破坏等高
	var err5 := BattlefieldDocScript.validate_buildings(m5)
	_expect(not err5.is_empty() and err5.contains("不等高"), "底面破坏后校验报错：%s" % err5)
	BattlefieldDocScript.set_cell_z(m5, Vector2i(1, 1), 0)
	m5.units = [{ "class": "swordsman", "name": "U", "level": 1, "x": 0, "y": 0, "faction": "player" }]
	_expect(not BattlefieldDocScript.validate_buildings(m5).is_empty(), "压单位校验报错")
	m5.units = []

	# ---- 6. JSON 往返 + 宽松解析 ----
	var j: Dictionary = BattlefieldDocScript.to_json_dict(m5)
	_expect((j.get("buildings", []) as Array).size() == 1, "to_json 写 buildings 字段")
	var back: Dictionary = BattlefieldDocScript.from_json_dict(j.duplicate(true))
	_expect((back.buildings as Array).size() == 1, "from_json 读回 1 栋")
	var be: Dictionary = back.buildings[0]
	_expect(String(be.get("instance_id", "")) == "b001" and String(be.get("asset_id", "")) == "hut"
		and int(be.get("x", -1)) == 0 and int(be.get("rotation", -1)) == 0, "往返字段保持")
	# 空 buildings 不写字段（旧 JSON 兼容）
	var m6: Dictionary = BattlefieldDocScript.create_empty(6, 6)
	_expect(not BattlefieldDocScript.to_json_dict(m6).has("buildings"), "空建筑不写 buildings 字段")
	# 坏条目宽松解析：非 Dict / 缺 instance_id / 缺 asset_id 跳过；rotation wrap
	var raw := {
		"rows": ["ffffff"], "width": 6, "height": 6,
		"buildings": [
			"junk",
			{ "asset_id": "hut", "x": 1, "y": 1, "rotation": 7 },
			{ "instance_id": "b001", "x": 2, "y": 2, "rotation": 0 },
			{ "instance_id": "b002", "asset_id": "hut", "x": 1, "y": 1, "rotation": 7 },
		],
	}
	var parsed: Dictionary = BattlefieldDocScript.from_json_dict(raw)
	_expect((parsed.buildings as Array).size() == 1, "缺 id/缺 asset 的坏条目被跳过")
	_expect(int((parsed.buildings as Array)[0].rotation) == 3, "rotation=7 wrap 到 3")

	# ---- 7. resize 整栋剔除（不切碎） ----
	var m7: Dictionary = BattlefieldDocScript.create_empty(10, 8)
	m7.user_assets = { "hut": _desc(2, 2) }
	BattlefieldDocScript.add_building(m7, "hut", Vector2i(0, 0), 0, {})   # 全在保留区
	BattlefieldDocScript.add_building(m7, "hut", Vector2i(3, 3), 0, {})   # 跨界剔除
	var shrunk: Dictionary = BattlefieldDocScript.resize(m7, 4, 4)
	_expect((shrunk.buildings as Array).size() == 1, "resize 后仅保留整栋在内的 1 栋")
	_expect(BattlefieldDocScript.validate_buildings(shrunk).is_empty(), "resize 后建筑校验通过")

	# ---- 8. load_candidate：坏建筑拒载（等高/重叠），好档可载 ----
	var good_model: Dictionary = BattlefieldDocScript.create_empty(6, 6)
	good_model.id = "building_contract_good"
	good_model.user_assets = { "hut": _desc(2, 2) }
	BattlefieldDocScript.add_building(good_model, "hut", Vector2i(0, 0), 0, {})
	var good_json: String = JSON.stringify(BattlefieldDocScript.to_json_dict(good_model))
	var f := FileAccess.open(TMP_GOOD, FileAccess.WRITE)
	f.store_string(good_json)
	f.close()
	var loaded: Dictionary = FileIoScript.load_candidate(TMP_GOOD)
	_expect(bool(loaded.get("ok", false)), "好档（含建筑）可载：err=%s" % String(loaded.get("error", "")))
	_expect((FileIoScript.load_candidate(TMP_GOOD).model.buildings as Array).size() == 1,
		"载入模型含 1 栋建筑")

	# 等高破坏档：底面一格 z=3（绕过编辑器拦截直接写 JSON）
	var bad_eq: Dictionary = good_model.duplicate(true)
	BattlefieldDocScript.set_cell_z(bad_eq, Vector2i(1, 1), 3)
	var fb := FileAccess.open(TMP_BAD_EQ, FileAccess.WRITE)
	fb.store_string(JSON.stringify(BattlefieldDocScript.to_json_dict(bad_eq)))
	fb.close()
	var loaded_bad: Dictionary = FileIoScript.load_candidate(TMP_BAD_EQ)
	_expect(not bool(loaded_bad.get("ok", false)), "等高破坏档拒载")
	_expect(String(loaded_bad.get("error", "")).contains("不等高"), "拒载文案含等高原因")

	# 重叠档：两栋同 asset 同位（手工构造 JSON）
	var overlap_dict: Dictionary = BattlefieldDocScript.to_json_dict(good_model)
	(overlap_dict["buildings"] as Array).append(
		{ "instance_id": "b002", "asset_id": "hut", "x": 1, "y": 1, "rotation": 0 })
	var fo := FileAccess.open(TMP_BAD_OVERLAP, FileAccess.WRITE)
	fo.store_string(JSON.stringify(overlap_dict))
	fo.close()
	var loaded_ov: Dictionary = FileIoScript.load_candidate(TMP_BAD_OVERLAP)
	_expect(not bool(loaded_ov.get("ok", false)), "重叠建筑档拒载")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_GOOD))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_BAD_EQ))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_BAD_OVERLAP))

	# ---- 9. buildings_fully_within 边界语义 ----
	var m9: Dictionary = BattlefieldDocScript.create_empty(10, 8)
	m9.user_assets = { "hut": _desc(2, 2) }
	BattlefieldDocScript.add_building(m9, "hut", Vector2i(1, 1), 0, {})  # 完全在 (0,0)-(3,3)
	BattlefieldDocScript.add_building(m9, "hut", Vector2i(3, 3), 0, {})  # 占 (3,3)-(4,4) 跨界
	var within: Array = BattlefieldDocScript.buildings_fully_within(m9, Vector2i(0, 0), Vector2i(3, 3))
	_expect(within.size() == 1 and int(within[0].x) == 1, "fully_within 只收完全在内的建筑")

	# ---- 10. ed 层：apply_building_tool 放置/再点删除/异素材报错 ----
	var ed := FakeEd.new()
	ed.model = BattlefieldDocScript.create_empty(10, 8)
	ed.model.user_assets = { "hut": _desc(2, 2), "other": _desc(1, 1) }
	ed._selected_asset = { "id": "hut", "kind": "building" }
	ModelOpsScript.apply_building_tool(ed, Vector2i(1, 1))
	_expect(BattlefieldDocScript.building_entries(ed.model).size() == 1, "工具放置成功")
	ModelOpsScript.apply_building_tool(ed, Vector2i(2, 2))
	_expect(BattlefieldDocScript.building_entries(ed.model).size() == 0, "再点同建筑整栋删除")
	ModelOpsScript.apply_building_tool(ed, Vector2i(0, 0))
	ed._selected_asset = { "id": "other", "kind": "building" }
	ModelOpsScript.apply_building_tool(ed, Vector2i(1, 1))
	_expect(BattlefieldDocScript.building_entries(ed.model).size() == 1, "异素材点击不删除原建筑")
	_expect(ed.last_error, "异素材点击有报错提示")

	# ---- 11. ed 层：高度编辑拦截建筑格 ----
	ed._canvas.selected_cell = Vector2i(1, 1)  # 建筑占用格
	var z_before := BattlefieldDocScript.cell_z(ed.model, Vector2i(1, 1))
	CellToolsScript.on_block_z_changed(ed, 5.0)
	_expect(BattlefieldDocScript.cell_z(ed.model, Vector2i(1, 1)) == z_before,
		"SpinBox 改建筑格高度被拒")
	_expect(ed._undo_log.is_empty(), "拒绝不入历史")
	ed._canvas.selected_cell = Vector2i(8, 0)  # 空格
	CellToolsScript.on_block_z_changed(ed, 3.0)
	_expect(BattlefieldDocScript.cell_z(ed.model, Vector2i(8, 0)) == 3, "空格改高正常")

	# ---- 12. ed 层：建筑预览驱动（合法 set / 非法 clear / 无接口不崩） ----
	var ed2 := FakeEd.new()
	ed2.model = BattlefieldDocScript.create_empty(10, 8)
	ed2.model.user_assets = { "hut": _desc(2, 2) }
	ed2._selected_asset = { "id": "hut", "kind": "building" }
	ed2._canvas.hover_cell = Vector2i(2, 2)
	CellToolsScript.update_building_preview(ed2, Vector2i(2, 2))
	_expect(ed2._canvas.preview_calls.size() == 1 and ed2._canvas.preview_calls[0].x == 2,
		"合法位置触发 set_building_preview")
	CellToolsScript.update_building_preview(ed2, Vector2i(9, 7))  # 2x2 越界
	_expect(ed2._canvas.clear_calls == 1, "越界位置触发 clear_building_preview")
	var ed3 := FakeEd.new()
	ed3.model = ed2.model.duplicate(true)
	ed3._selected_asset = { "id": "hut", "kind": "building" }
	ed3._canvas = RefCounted.new()  # 裸对象：无预览接口
	CellToolsScript.update_building_preview(ed3, Vector2i(2, 2))  # 不崩即通过
	_expect(true, "canvas 无预览接口时安全跳过")

	# ---- 13. 区域复制 → 粘贴：建筑整栋平移、instance_id 重生成 ----
	var edc := FakeEd.new()
	edc.model = BattlefieldDocScript.create_empty(10, 8)
	edc.model.user_assets = { "hut": _desc(2, 2) }
	BattlefieldDocScript.add_building(edc.model, "hut", Vector2i(0, 0), 0, {})
	edc.region_bounds = [Vector2i(0, 0), Vector2i(2, 2)]
	ClipboardScript.on_region_copy_pressed(edc)
	_expect((edc._clipboard.get("buildings", []) as Array).size() == 1, "复制 payload 含 1 栋建筑")
	ClipboardScript.commit_paste(edc, Vector2i(5, 0))
	var pasted: Array = BattlefieldDocScript.building_entries(edc.model)
	_expect(pasted.size() == 2, "粘贴后原建筑+新建筑共存")
	var ids := []
	for b in pasted:
		ids.append(String(b.instance_id))
	_expect(ids.has("b001") and ids.has("b002"), "粘贴建筑 instance_id 重生成")
	var nb: Dictionary = BattlefieldDocScript.building_at(edc.model, Vector2i(5, 0))
	_expect(not nb.is_empty() and int(nb.x) == 5 and int(nb.y) == 0, "新建筑落在粘贴原点")

	# ---- 14. 区域移动：随移/保留原 id/跨界留原地/预校验原子拒绝 ----
	var edm := FakeEd.new()
	edm.model = BattlefieldDocScript.create_empty(10, 8)
	edm.model.user_assets = { "hut": _desc(2, 2) }
	BattlefieldDocScript.add_building(edm.model, "hut", Vector2i(1, 1), 0, {})  # 完全在内
	BattlefieldDocScript.add_building(edm.model, "hut", Vector2i(3, 3), 0, {})  # 跨界留原地
	ClipboardScript.commit_region_move(edm, [Vector2i(0, 0), Vector2i(3, 3)], Vector2i(0, 4), false)
	var moved_entries: Array = BattlefieldDocScript.building_entries(edm.model)
	_expect(moved_entries.size() == 2, "移动后仍是 2 栋（不切碎）")
	var at_new: Dictionary = BattlefieldDocScript.building_at(edm.model, Vector2i(1, 5))
	_expect(not at_new.is_empty() and String(at_new.instance_id) == "b001",
		"区域内建筑随移且 instance_id 保持")
	var at_old: Dictionary = BattlefieldDocScript.building_at(edm.model, Vector2i(3, 3))
	_expect(not at_old.is_empty() and String(at_old.instance_id) == "b002",
		"跨界建筑留原地")
	# 原子拒绝：移动后与跨界建筑重叠 → 整体不动
	var edm2 := FakeEd.new()
	edm2.model = BattlefieldDocScript.create_empty(10, 8)
	edm2.model.user_assets = { "hut": _desc(2, 2) }
	BattlefieldDocScript.add_building(edm2.model, "hut", Vector2i(1, 1), 0, {})  # b001 在区域内
	BattlefieldDocScript.add_building(edm2.model, "hut", Vector2i(2, 5), 0, {})  # b002 挡目标位
	ClipboardScript.commit_region_move(edm2, [Vector2i(0, 0), Vector2i(3, 3)], Vector2i(0, 4), false)
	_expect(int(BattlefieldDocScript.building_at(edm2.model, Vector2i(1, 1)).get("x", -1)) == 1,
		"预校验失败整体拒绝（b001 原位不动）")
	_expect(edm2._undo_log.is_empty(), "拒绝不入历史")

	# ---- 15. 区域剪切：完全在内删除、跨界保留 ----
	var edk := FakeEd.new()
	edk.model = BattlefieldDocScript.create_empty(10, 8)
	edk.model.user_assets = { "hut": _desc(2, 2) }
	BattlefieldDocScript.add_building(edk.model, "hut", Vector2i(0, 0), 0, {})  # 完全在内
	BattlefieldDocScript.add_building(edk.model, "hut", Vector2i(2, 2), 0, {})  # 占 (2,2)-(3,3) 跨界
	edk.region_bounds = [Vector2i(0, 0), Vector2i(2, 2)]
	ClipboardScript.on_region_cut_pressed(edk)
	var cut_entries: Array = BattlefieldDocScript.building_entries(edk.model)
	_expect(cut_entries.size() == 1 and int(cut_entries[0].x) == 2, "剪切删完全在内、跨界保留")
	_expect((edk._clipboard.get("buildings", []) as Array).size() == 1, "剪贴板带走被删建筑")

	# ---- 16. undo/redo 六件套（buildings 参与快照） ----
	var HistoryScript := preload("res://scripts/editor/map_editor_history.gd")
	var edh := FakeEd.new()
	edh.model = BattlefieldDocScript.create_empty(10, 8)
	edh.model.user_assets = { "hut": _desc(2, 2) }
	edh._selected_asset = { "id": "hut", "kind": "building" }
	var snap0: Dictionary = HistoryScript.snapshot(edh.model)
	ModelOpsScript.apply_building_tool(edh, Vector2i(1, 1))
	_expect(BattlefieldDocScript.building_entries(edh.model).size() == 1, "放置后 1 栋")
	_expect(not HistoryScript.state_equal(snap0, HistoryScript.snapshot(edh.model)),
		"放置改变模型（快照可检测）")
	HistoryScript.restore_into(edh.model, snap0)
	_expect(BattlefieldDocScript.building_entries(edh.model).size() == 0, "撤销恢复 0 栋")

	# ---- 17. 同 asset_id footprint 漂移：统一 merged 解释 + add 前既有楼模拟重校验 ----
	var eds := BattlefieldDocScript.create_empty(10, 10)
	eds.user_assets = { "hut": _desc(2, 2) }
	var r_drift: Dictionary = BattlefieldDocScript.add_building(eds, "hut", Vector2i(0, 0), 0, { "hut": _desc(2, 2) })
	_expect(bool(r_drift.ok), "漂移基线：2x2 落位成功")
	# 库改 3x3：b001 按 merged 占 (0,0)-(2,2)，新楼 (2,2) 与其重叠 → 必须拒绝（修复前按旧 2x2 放行）
	var drift_err := BattlefieldDocScript.can_place_building(eds, "hut", Vector2i(2, 2), 0, { "hut": _desc(3, 3) })
	_expect(drift_err.contains("重叠"), "漂移后重叠按新占地拒绝（实际：%s）" % drift_err)
	# 漂移使既有楼越界：b001 在右缘 2x2 合法，快照 3x3 → 模拟发现 b001 越界 → 拒绝且模型不变
	var eds2 := BattlefieldDocScript.create_empty(10, 10)
	eds2.user_assets = { "hut": _desc(2, 2) }
	var r_edge: Dictionary = BattlefieldDocScript.add_building(eds2, "hut", Vector2i(8, 0), 0, { "hut": _desc(2, 2) })
	_expect(bool(r_edge.ok), "右缘 8,0 的 2x2 落位成功")
	var r_bad: Dictionary = BattlefieldDocScript.add_building(eds2, "hut", Vector2i(0, 5), 0, { "hut": _desc(3, 3) })
	_expect(not bool(r_bad.ok), "漂移致既有楼越界 → 放置整体拒绝（实际：%s）" % String(r_bad.get("error", "")))
	_expect((BattlefieldDocScript.building_entries(eds2) as Array).size() == 1, "拒绝后条目数不变")
	var kept: Dictionary = ((eds2.user_assets.hut) as Dictionary).render as Dictionary
	_expect(int(((kept.footprint) as Dictionary).w) == 2, "拒绝后快照不被替换（仍 2x2）")
	# 同 footprint 快照提交不受影响
	var r_ok: Dictionary = BattlefieldDocScript.add_building(eds2, "hut", Vector2i(0, 5), 0, { "hut": _desc(2, 2) })
	_expect(bool(r_ok.ok) and (BattlefieldDocScript.building_entries(eds2) as Array).size() == 2,
		"正常快照提交不受影响")

	# ---- 18. 单位不得进入建筑（place_unit / 粘贴 / 移动原子拒绝） ----
	var edu := FakeEd.new()
	edu.model = BattlefieldDocScript.create_empty(10, 10)
	edu.model.user_assets = { "hut": _desc(2, 2) }
	edu._selected_asset = { "id": "hut", "kind": "building" }
	ModelOpsScript.apply_building_tool(edu, Vector2i(0, 0))
	_expect(not ModelOpsScript.place_unit(edu, Vector2i(1, 1), "player", "swordsman", 1),
		"place_unit 建筑格拒绝")
	_expect(String(edu.last_msg).contains("建筑"), "拒绝文案指向建筑")
	# 粘贴：payload 单位目标格撞既有建筑 → 整体拒绝（不写模型不入历史）
	edu._clipboard = {
		"version": RegionClipboardScript.PAYLOAD_VERSION,
		"w": 1, "h": 1, "rows": ["."], "block_z": [0],
		"tile_overrides": {}, "props": [],
		"units": [{ "dx": 0, "dy": 0, "class": "swordsman", "name": "U", "level": 1, "faction": "player", "tag": "剑" }],
	}
	edu._paste_mode = true
	edu._status_log.clear()
	edu._error_log.clear()
	edu._undo_log.clear()
	ClipboardScript.commit_paste(edu, Vector2i(0, 0))
	_expect((edu.model.units as Array).size() == 0, "粘贴单位撞建筑整体拒绝（无单位写入）")
	_expect(edu._undo_log.is_empty(), "粘贴拒绝不入历史")
	edu._paste_mode = false
	# 移动：随移单位目标格撞跨界保留建筑 → 整体拒绝；合法位移不受影响
	var edm3 := FakeEd.new()
	edm3.model = BattlefieldDocScript.create_empty(10, 10)
	edm3.model.user_assets = { "hut": _desc(2, 2) }
	edm3._selected_asset = { "id": "hut", "kind": "building" }
	ModelOpsScript.apply_building_tool(edm3, Vector2i(0, 0))  # b001 随移候选：(0,0)-(1,1)
	ModelOpsScript.apply_building_tool(edm3, Vector2i(2, 2))  # b002 跨界保留：(2,2)-(3,3)
	(edm3.model.units as Array).append({
		"class": "swordsman", "name": "M", "level": 1,
		"x": 0, "y": 2, "faction": "player", "tag": "剑",
	})
	edm3.region_bounds = [Vector2i(0, 0), Vector2i(2, 2)]
	ClipboardScript.commit_region_move(edm3, edm3.region_bounds, Vector2i(2, 0), false)
	_expect(String(edm3.last_msg).contains("建筑"), "移动单位撞建筑有指向文案（实际：%s）" % String(edm3.last_msg))
	_expect(int((edm3.model.units as Array)[0].y) == 2, "移动拒绝后单位原位")
	_expect(int((BattlefieldDocScript.building_entries(edm3.model) as Array)[0].x) == 0,
		"移动拒绝后随移建筑原位")
	_expect(edm3._undo_log.is_empty(), "移动拒绝不入历史")
	ClipboardScript.commit_region_move(edm3, edm3.region_bounds, Vector2i(0, 3), false)
	_expect(int((edm3.model.units as Array)[0].y) == 5, "合法移动单位随区平移")
	var b001_after: Dictionary = {}
	for e in BattlefieldDocScript.building_entries(edm3.model):
		if String((e as Dictionary).get("instance_id", "")) == "b001":
			b001_after = e
	_expect(not b001_after.is_empty() and int(b001_after.get("y", -1)) == 3,
		"合法移动建筑随区平移（b001 y=3）")
	_expect(edm3._undo_log.size() == 1, "合法移动一步历史")

	print("MAP_EDITOR_BUILDING_PASS: all %d sections" % 18)
	quit(0)


## 最小编辑器桩：只提供被测 static 函数访问的字段/方法
class FakeEd:
	extends RefCounted
	var model: Dictionary = {}
	var _selected_asset: Dictionary = {}
	var _selected_block_asset := ""
	var _building_rotation := 0
	var _asset_service = null
	var _canvas: RefCounted = null  # 放宽：允许裸 RefCounted 桩（无预览接口场景）
	var _block_z_box = null
	var _cell_info_label = null
	var _syncing_block_z := false
	var _height_stroke_cells: Dictionary = {}
	var _clipboard: Dictionary = {}
	var _paste_mode := false
	var _paste_origin := Vector2i(-1, -1)
	var _move_armed := false
	var _move_grab := Vector2i(-1, -1)
	var _move_preview := Vector2i(-1, -1)
	var _status_log: Array = []
	var _error_log: Array = []
	var _undo_log: Array = []
	var _refresh_count := 0
	var _block_fg: Dictionary = { "kind": "", "id": "" }
	var region_bounds: Array = []
	var last_error := false
	var last_msg := ""

	func _init() -> void:
		_canvas = FakeCanvas.new()

	func _active_asset() -> Dictionary:
		if not _selected_asset.is_empty():
			return _selected_asset
		if not _selected_block_asset.is_empty():
			return { "id": _selected_block_asset, "kind": "terrain" }
		return {}

	func _status(msg: String, is_error: bool = false) -> void:
		_status_log.append(msg)
		last_error = is_error
		last_msg = msg
		if is_error:
			_error_log.append(msg)

	func _push_undo(label: String) -> void:
		_undo_log.append(label)

	func _refresh_canvas() -> void:
		_refresh_count += 1

	func _sync_region_marker() -> void:
		pass

	func _cancel_place_mode() -> void:
		pass

	func _cancel_paste() -> void:
		_paste_mode = false

	func _region_2d_bounds() -> Array:
		return region_bounds

	func _move_tool_bounds() -> Array:
		return region_bounds

	func _set_block_slot(_slot: String, v: Dictionary) -> void:
		_block_fg = v


class FakeCanvas:
	extends RefCounted
	var selected_cell := Vector2i(-1, -1)
	var hover_cell := Vector2i(-1, -1)
	var preview_calls: Array = []
	var clear_calls := 0

	func _refresh_cell(_cell: Vector2i) -> void:
		pass

	func set_building_preview(_asset_id: String, origin: Vector2i, _rotation: int) -> void:
		preview_calls.append(origin)

	func clear_building_preview() -> void:
		clear_calls += 1

	func clear_paste_preview() -> void:
		pass
