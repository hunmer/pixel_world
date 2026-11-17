## map_editor_model_ops.gd — 地图编辑器模型写操作原语
##
## 画笔/吸管、植物与素材覆盖双层写入、地形图例字符、洪水/区域填充路由、
## 角色放置与移除。填充内核在 map_editor_paint_ops.gd，文档读写内核在
## battlefield_doc.gd。全部 static，ed=map_editor 实例；
## 逻辑与原 map_editor.gd 内联实现逐行一致。

class_name MapEditorModelOps
extends RefCounted

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const ProfessionDataScript = preload("res://scripts/core/professions.gd")
const UserAssetCatalogScript = preload("res://scripts/assets/user_asset_catalog.gd")
const MapEditorPaintOpsScript = preload("res://scripts/editor/map_editor_paint_ops.gd")


## 画笔统一消费前景槽：素材写覆盖层，内置地形写 rows 并清覆盖。
static func apply_paint_block(ed, cell: Vector2i) -> void:
	if String(ed._block_fg.get("kind", "terrain")) == "asset":
		var asset_id := String(ed._block_fg.get("id", ""))
		if not asset_id.is_empty():
			ed._set_tile_override(cell, asset_id)
		return
	var terrain := StringName(ed._block_fg.get("id", "plain"))
	ed._set_glyph(cell, BattlefieldDocScript.TERRAIN_GLYPH.get(terrain, "."))
	ed._set_tile_override(cell, "")


## 吸管只读取模型：素材覆盖优先，否则取 rows 图例；Alt/背景参数决定写入哪个槽。
static func pick_block(ed, cell: Vector2i, to_background: bool = false) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(ed.model.width) or cell.y >= int(ed.model.height):
		ed._status("吸取失败：坐标越界", true)
		return
	var asset_id := BattlefieldDocScript.tile_override_at(ed.model, cell)
	var block: Dictionary
	if not asset_id.is_empty():
		block = {"kind": "asset", "id": asset_id, "z": BattlefieldDocScript.cell_z(ed.model, cell)}
	else:
		var row: String = ed.model.rows[cell.y]
		var terrain := BattlefieldDocScript.glyph_to_terrain(row.substr(cell.x, 1))
		block = {"kind": "terrain", "id": String(terrain), "z": BattlefieldDocScript.cell_z(ed.model, cell)}
	ed._set_block_slot("bg" if to_background else "fg", block)
	ed._remember_recent_pick(block)
	ed._status("已吸取：%s（%s）" % [ed._block_label(block), "背景" if to_background else "前景"])
	print("[editor] 吸取方块 cell=%s slot=%s kind=%s id=%s z=%d"
		% [str(cell), "bg" if to_background else "fg", String(block.kind), String(block.id), int(block.z)])  # L1 埋点


## 放置/清除（path 为空）某格的具体植物；与地形解耦，同格至多一株
static func set_prop(ed, cell: Vector2i, path: String) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(ed.model.width) or cell.y >= int(ed.model.height):
		return
	if path.is_empty():
		if BattlefieldDocScript.remove_prop(ed.model, cell):
			ed._canvas._refresh_cell(cell)
		return
	if not BattlefieldDocScript.set_prop(ed.model, cell, path):
		return
	ed._canvas._refresh_cell(cell)
	ed._status("放置植物 %s @(%d,%d)" % [path.get_file().get_basename(), cell.x, cell.y])


## 放置/清除某格的素材覆盖（asset_id 为空=清除）：
## kind=terrain → tile_overrides 层（整格替换为素材块，与地形字符解耦）；
## kind=plant   → props 层 asset 通道（与 texture 通道植物同层共存，同格至多一株）
static func set_tile_override(ed, cell: Vector2i, asset_id: String) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(ed.model.width) or cell.y >= int(ed.model.height):
		return
	if not BattlefieldDocScript.set_tile_override(ed.model, cell, asset_id):
		return
	ed._canvas._refresh_cell(cell)
	if not asset_id.is_empty():
		ed._status("地块素材 %s @(%d,%d)" % [asset_id, cell.x, cell.y])


static func set_prop_asset(ed, cell: Vector2i, asset_id: String) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(ed.model.width) or cell.y >= int(ed.model.height):
		return
	if not BattlefieldDocScript.set_prop_asset(ed.model, cell, asset_id):
		return
	ed._canvas._refresh_cell(cell)
	if not asset_id.is_empty():
		ed._status("植物素材 %s @(%d,%d)" % [asset_id, cell.x, cell.y])


## 素材放置 / 同格再点取消覆盖（拖动路径只放置不取消）
static func apply_asset_tool(ed, cell: Vector2i) -> void:
	var d: Dictionary = ed._active_asset()
	var asset_id := String(d.get("id", ""))
	if asset_id.is_empty():
		return
	if String(d.get("kind", "")) == UserAssetCatalogScript.KIND_PLANT:
		if BattlefieldDocScript.prop_asset_at(ed.model, cell) == asset_id:
			ed._set_prop_asset(cell, "")
		else:
			ed._set_prop_asset(cell, asset_id)
	elif String(d.get("kind", "")) == BattlefieldDocScript.ASSET_KIND_BUILDING:
		apply_building_tool(ed, cell)
	else:
		if BattlefieldDocScript.tile_override_at(ed.model, cell) == asset_id:
			ed._set_tile_override(cell, "")
		else:
			ed._set_tile_override(cell, asset_id)


## 组装建筑放置用的素材快照 {asset_id: descriptor}：主素材 + render.back_asset_id
## 背面依赖（渲染 front_back 模式离线自包含；服务缺失/素材未就绪时返回空表，
## 占用校验会回退 1x1 并 warning，不会静默放错位置）。
static func building_assets_snapshot(ed, asset_id: String) -> Dictionary:
	var snapshot: Dictionary = {}
	if ed._asset_service == null:
		return snapshot
	var main: Variant = ed._asset_service.find_by_id(asset_id)
	if main is Dictionary and not (main as Dictionary).is_empty():
		snapshot[asset_id] = main
		var back_id := String(
			((main as Dictionary).get("render", {}) as Dictionary).get("back_asset_id", ""))
		if not back_id.is_empty() and not snapshot.has(back_id):
			var back: Variant = ed._asset_service.find_by_id(back_id)
			if back is Dictionary and not (back as Dictionary).is_empty():
				snapshot[back_id] = back
	return snapshot


## 建筑放置 / 命中同素材建筑再点整栋删除（拖动路径只放置不删除）。
## 命中其他建筑只提示不覆盖；空位放置走 can_place 全规则校验
## （界内/底面等高/建筑不重叠/不压单位），rotation 用 ed._building_rotation。
static func apply_building_tool(ed, cell: Vector2i) -> void:
	var d: Dictionary = ed._active_asset()
	var asset_id := String(d.get("id", ""))
	if asset_id.is_empty():
		return
	var hit := BattlefieldDocScript.building_at(ed.model, cell)
	if not hit.is_empty():
		if String(hit.get("asset_id", "")) == asset_id:
			if BattlefieldDocScript.remove_building(ed.model, String(hit["instance_id"])):
				ed._refresh_canvas()
				ed._status("删除建筑 %s @(%d,%d)" % [asset_id, cell.x, cell.y])
				print("[editor] 建筑删除 asset=%s cell=%s" % [asset_id, str(cell)])  # L1 埋点
		else:
			ed._status("(%d,%d) 已有其他建筑 %s" % [cell.x, cell.y, String(hit.get("asset_id", ""))], true)
		return
	var snapshot := building_assets_snapshot(ed, asset_id)
	var result: Dictionary = BattlefieldDocScript.add_building(
		ed.model, asset_id, cell, int(ed._building_rotation), snapshot)
	if not bool(result.get("ok", false)):
		ed._status(String(result.get("error", "建筑放置失败")), true)
		return
	ed._refresh_canvas()
	ed._status("放置建筑 %s r=%d @(%d,%d)" % [asset_id, int(ed._building_rotation), cell.x, cell.y])
	print("[editor] 建筑放置 asset=%s cell=%s rotation=%d" % [asset_id, str(cell), int(ed._building_rotation)])  # L1 埋点


## 删除命中格所在建筑（整栋）；无建筑时静默（橡皮路径复用）
static func remove_building_at(ed, cell: Vector2i) -> bool:
	var entry := BattlefieldDocScript.building_at(ed.model, cell)
	if entry.is_empty():
		return false
	var removed := BattlefieldDocScript.remove_building(ed.model, String(entry["instance_id"]))
	if removed:
		ed._refresh_canvas()
		ed._status("删除建筑 %s @(%d,%d)" % [String(entry.get("asset_id", "")), cell.x, cell.y])
	return removed


## T 键意图：选中建筑素材 → 循环预放置朝向并刷新预览；
## 否则旋转选中格/悬停格上的已放置建筑（整栋，一步历史）。
static func rotate_building_intent(ed) -> void:
	var d: Dictionary = ed._active_asset()
	var asset_id := String(d.get("id", ""))
	if String(d.get("kind", "")) == BattlefieldDocScript.ASSET_KIND_BUILDING and not asset_id.is_empty():
		ed._building_rotation = (int(ed._building_rotation) + 1) % 4
		ed._status("建筑朝向 r=%d（T 切换）" % int(ed._building_rotation))
		ed._update_building_preview(
			ed._canvas.hover_cell if ed._canvas != null else Vector2i(-1, -1))
		return
	var cell2: Vector2i = ed._canvas.selected_cell if ed._canvas != null else Vector2i(-1, -1)
	if cell2.x < 0 and ed._canvas != null:
		cell2 = ed._canvas.hover_cell
	if cell2.x < 0:
		ed._status("先选中或悬停一个建筑再旋转", true)
		return
	var entry := BattlefieldDocScript.building_at(ed.model, cell2)
	if entry.is_empty():
		ed._status("(%d,%d) 没有建筑" % [cell2.x, cell2.y], true)
		return
	ed._push_undo("旋转建筑")
	var err := BattlefieldDocScript.rotate_building(ed.model, cell2)
	if not err.is_empty():
		ed._status(err, true)
		return
	ed._refresh_canvas()
	ed._status("旋转建筑 %s → r=%d" % [String(entry.get("asset_id", "")), (int(entry.get("rotation", 0)) + 1) % 4])


## 设置地形图例字符（含画笔/橡皮/拖动路径）
static func set_glyph(ed, cell: Vector2i, glyph: String) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= ed.model.width or cell.y >= ed.model.height:
		return
	var rows: Array = ed.model.rows
	var row: String = rows[cell.y]
	if row.substr(cell.x, 1) == glyph:
		return
	rows[cell.y] = row.substr(0, cell.x) + glyph + row.substr(cell.x + 1)
	ed._canvas._refresh_cell(cell)


## 洪水填充：同图例连通区域 -> 目标地形（内核在 MapEditorPaintOpsScript.flood_fill_terrain）
static func fill_cell(ed, cell: Vector2i, terrain: StringName) -> void:
	var filled := MapEditorPaintOpsScript.flood_fill_terrain(ed.model, cell, terrain)
	if filled <= 0:
		return
	ed._refresh_canvas()
	ed._status("填充 %s ×%d 格" % [BattlefieldDocScript.TERRAIN_CN[terrain], filled])


## 放置阵营角色：站不住的地形拒绝；同格已有单位则先移除
static func place_unit(ed, cell: Vector2i, faction: String, class_id: String, level: int, uname: String = "") -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= ed.model.width or cell.y >= ed.model.height:
		ed._status("越界：(%d,%d)" % [cell.x, cell.y], true)
		return false
	var terrain := BattlefieldDocScript.glyph_to_terrain((ed.model.rows[cell.y] as String).substr(cell.x, 1))
	if not BattlefieldLoaderScript._is_standable(terrain):
		ed._status("%s 不可站人（%s）" % [BattlefieldDocScript.TERRAIN_CN[terrain], str(cell)], true)
		return false
	var building_hit := BattlefieldDocScript.building_at(ed.model, cell)
	if not building_hit.is_empty():
		ed._status("该格被建筑 %s 占用，不能放置单位（先移除建筑）" % [
			String(building_hit.get("instance_id", "?"))], true)
		return false
	ed._remove_unit_at(cell)
	var cn := ProfessionDataScript.profession_name(StringName(class_id))
	var seq := 1
	for u in ed.model.units:
		if String(u.get("class", "")) == class_id and String(u.get("faction", "")) == faction:
			seq += 1
	var unit := {
		"class": class_id,
		"name": uname.strip_edges() if not uname.strip_edges().is_empty() else "%s%d" % [cn, seq],
		"level": clampi(level, 1, 9),
		"x": cell.x,
		"y": cell.y,
		"faction": faction,
		"tag": cn.substr(0, 1),
	}
	(ed.model.units as Array).append(unit)
	ed._canvas._refresh_cell(cell)
	ed._status("放置 %s·%s Lv%d @(%d,%d)" % [cn, unit.name, unit.level, cell.x, cell.y])
	return true


## 删除 (cell) 处单位；返回是否删到
static func remove_unit_at(ed, cell: Vector2i) -> bool:
	for i in range((ed.model.units as Array).size()):
		var u: Dictionary = ed.model.units[i]
		if int(u.x) == cell.x and int(u.y) == cell.y:
			ed.model.units.remove_at(i)
			ed._canvas._refresh_cell(cell)
			ed.MapEditorUnitsScript.sync_panel(ed)
			ed._status("移除 %s @(%d,%d)" % [u.name, cell.x, cell.y])
			return true
	return false


## 填充路由：完整区域 → 区域填充；否则按前景槽做素材/地形洪水填充。
static func apply_fill(ed, cell: Vector2i) -> void:
	if ed._selection_mode == &"region" and ed._region_pos2_set and ed._selection_range.is_active():
		fill_region(ed)
		return
	match StringName(ed._block_fg.get("kind", "terrain")):
		&"asset":
			var asset_id := String(ed._block_fg.get("id", ""))
			var filled := MapEditorPaintOpsScript.flood_fill_asset(ed.model, cell, asset_id)
			if filled > 0:
				ed._refresh_canvas()
				ed._status("素材填充 %s ×%d 格" % [asset_id, filled])
				print("[editor] 素材洪水填充 asset=%s cells=%d" % [asset_id, filled])  # L1 埋点
		_:
			fill_cell(ed, cell, StringName(ed._block_fg.get("id", "plain")))


## 区域填充：区域内每格应用选择器内容——内置地形写 rows 并清素材覆盖；
## 已保存素材方块写 tile_overrides 不动 rows（两层正确区分）。
## 立体选择（pos1/pos2 异高）= 体积填充语义：矩形内每列都填充，且每列顶面统一
## 找平至带顶 z_hi（单块列模型每列只有一块立方体——选择 0..4 填充即整片抬成 z4
## 平台，「填充整个选择范围」而不是只刷表层）；同高选择保持平面行为（全 footprint
## 写材质、不动块高）。调用方负责 _push_undo：填充与高度变化同一步历史（原子）。
##（填充内核在 MapEditorPaintOpsScript.fill_region）
static func fill_region(ed) -> void:
	var mn: Vector3i = ed._selection_range.min_corner()
	var mx: Vector3i = ed._selection_range.max_corner()
	var result: Dictionary = MapEditorPaintOpsScript.fill_region(ed.model, mn, mx,
		StringName(ed._block_fg.get("kind", "terrain")), String(ed._block_fg.get("id", "plain")),
		ed._selection_range.cells_2d())
	var kind := StringName(result.get("kind", &"terrain"))
	var id := String(result.get("id", "plain"))
	var count := int(result.get("count", 0))
	var leveled := int(result.get("leveled", 0))
	var volume := mn.z != mx.z
	var z_hi := maxi(mn.z, mx.z)
	ed._refresh_canvas()
	var label := id if kind == &"asset" else String(BattlefieldDocScript.TERRAIN_CN.get(StringName(id), id))
	if volume:
		ed._status("区域填充 %s ×%d 格（体积填充至 z%d，调整高度 %d 列）" % [label, count, z_hi, leveled])
	else:
		ed._status("区域填充 %s ×%d 格" % [label, count])
	print("[editor] 区域填充 kind=%s id=%s cells=%d volume=%s z_hi=%d leveled=%d"
		% [String(kind), id, count, str(volume), z_hi, leveled])  # L1 埋点
