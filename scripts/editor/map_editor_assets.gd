## map_editor_assets.gd — 地图编辑器用户素材选择与方块素材网格
##
## 素材面板选中回写（地块素材进前景槽）、方块页「素材方块」网格的重建与
## 选中互斥、素材图片下载的 0.3s 合批缩略图刷新、库变化（导入/隐藏/编辑/
## 清单同步）后的网格与替换候选校正、画布预览格跟随。
## 全部 static，ed=map_editor 实例；逻辑与原 map_editor.gd 内联实现逐行一致。

class_name MapEditorAssets
extends RefCounted

const UserAssetCatalogScript = preload("res://scripts/assets/user_asset_catalog.gd")
const MapEditorOverlaysScript = preload("res://scripts/editor/map_editor_overlays.gd")
const MapEditorCellToolsScript = preload("res://scripts/editor/map_editor_cell_tools.gd")
const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const BuildingPaletteScript = preload("res://scripts/editor/map_editor_buildings.gd")


## 素材面板选中变化：写入选中态并同步画布预览格
## （建筑素材不进前景槽——画布点击走整栋放置，T 换朝向）
static func on_asset_selected(ed, descriptor: Dictionary) -> void:
	if ed._building_place_mode:
		ed._building_place_mode = false
		ed._canvas.clear_paste_preview()
	ed._selected_asset = descriptor
	BuildingPaletteScript.sync_selection(ed)
	if String(descriptor.get("kind", "")) == UserAssetCatalogScript.KIND_TERRAIN:
		ed._set_block_slot("fg", {"kind": "asset", "id": String(descriptor.get("id", "")), "z": int(ed._block_fg.z)})
	ed._clear_block_asset_selection()  # 与方块页选中互斥
	if String(descriptor.get("kind", "")) == BattlefieldDocScript.ASSET_KIND_BUILDING:
		ed._status("建筑素材 %s（点击画布放置整栋，T 换朝向，再点删除）" % String(descriptor.get("id", "")))
	update_asset_preview(ed)


## 重建方块页「素材方块」网格：全部地形素材（未缓存的顺手触发自动加载），按 id 稳定排序；
## 缩略图走 adapter.resolve_many 一次库加载批量出图（逐 id resolve 会重复整库 JSON 解析，
## 1455 素材 × 每 asset_ready 全网格重建曾直接把编辑器卡死）；asset_ready 只换单按钮缩略图。
## 选中项仍存在则恢复按下态，已消失（被隐藏）则清空选中。
static func rebuild_block_asset_grid(ed) -> void:
	if ed._block_asset_grid == null or ed._asset_service == null or ed._asset_adapter == null:
		return
	ed._block_asset_buttons.clear()
	var assets: Array = ed._asset_service.list_assets()
	assets.sort_custom(func(a, b): return String((a as Dictionary).get("id", "")) < String((b as Dictionary).get("id", "")))
	var ids: Array = []
	var items: Array[Dictionary] = []
	for raw in assets:
		var d := raw as Dictionary
		if String(d.get("kind", "")) != UserAssetCatalogScript.KIND_TERRAIN:
			continue
		var aid := String(d.get("id", ""))
		# 只列用户保存（✓）的方块：浏览在线列表会自动下载缓存，按缓存过滤等于全量进来；
		# 未下载的已保存方块保持占位，下面顺手触发下载，完成后经 asset_ready 合批重建换真图
		if not bool(d.get("saved", false)):
			continue
		ids.append(aid)
		if String(ed._asset_service.get_asset_state(aid).get("status", "")) != "ready":
			ed._asset_service.request_asset_image(aid)
	# p_cache=false：不灌 LRU（防挤穿热缓存）；列表规模=已下载数，resolve_many 单次库加载可承受
	var visuals: Dictionary = ed._asset_adapter.resolve_many(ids, false)
	for aid in ids:
		var d: Dictionary = ed._asset_service.find_by_id(aid)
		var visual: Dictionary = visuals.get(aid, {})
		items.append({"kind": "asset", "id": aid,
			"label": String(d.get("name", aid)), "texture": visual.get("texture")})
	var selected := "" if ed._selected_block_asset.is_empty() else "asset:%s" % ed._selected_block_asset
	ed._block_asset_grid.configure(items, selected, true)
	for i in range(ids.size()):
		var tb: Button = ed._block_asset_grid.get_button(i)
		UIThemeScript.style_button(tb)
		ed._block_asset_buttons[ids[i]] = tb
	if ed._block_asset_empty != null:
		ed._block_asset_empty.visible = ids.is_empty()
	if not ed._selected_block_asset.is_empty() and not ed._block_asset_buttons.has(ed._selected_block_asset):
		ed._selected_block_asset = ""
		update_asset_preview(ed)


static func on_block_asset_btn_pressed(ed, asset_id: String) -> void:
	if ed._selected_block_asset == asset_id:
		ed._selected_block_asset = ""
	else:
		ed._selected_block_asset = asset_id
		ed._clear_asset_selection()  # 与素材 Tab 选中互斥（先清再写前景槽：清空的素材回落不覆盖刚选的方块素材）
		# 与地形/植物调色板同页互斥：清按钮按下态（no_signal 不触发 pressed，避免反向清刚选的素材）
		# 并清 current_prop，让画笔语义让位给素材放置（与选地形按钮的行为一致）
		if ed._terrain_group != null:
			for b: BaseButton in ed._terrain_group.get_buttons():
				b.set_pressed_no_signal(false)
		ed.current_prop = ""
		ed._set_block_slot("fg", {"kind": "asset", "id": asset_id, "z": int(ed._block_fg.z)})
	update_asset_preview(ed)
	if ed._selected_block_asset.is_empty():
		ed._status("已取消方块素材选择")
	else:
		ed._status("方块素材 %s（画笔放置）" % asset_id)


## 清空方块页素材选中（素材 Tab 选中 / 地形调色板选中时调用，互斥）
static func clear_block_asset_selection(ed) -> void:
	if ed._selected_block_asset.is_empty():
		return
	ed._selected_block_asset = ""
	if ed._block_asset_grid != null:
		ed._block_asset_grid.set_selected("")


## 当前生效的素材描述符：素材 Tab 选中优先，其次方块页选中
static func active_asset(ed) -> Dictionary:
	if not ed._selected_asset.is_empty():
		return ed._selected_asset
	if ed._selected_block_asset.is_empty() or ed._asset_service == null:
		return {}
	var d: Variant = ed._asset_service.find_by_id(ed._selected_block_asset)
	return d if d is Dictionary else {}


## 素材图片下载完成：不立即逐张刷新——下载洪流期间每个事件都 clear_cache+resolve
## 会反复整库解析刷屏（每事件一次 654KB JSON parse）。记入待刷集合，0.3s 合批一次
## resolve_many 单库解析，只换受影响按钮的缩略图（全网格重建曾是进编辑器卡死的根因）。
static func on_block_asset_ready(ed, asset_id: String) -> void:
	ed._pending_asset_thumbs[asset_id] = true
	if ed._asset_thumb_timer == null or not is_instance_valid(ed._asset_thumb_timer):
		ed._asset_thumb_timer = Timer.new()
		ed._asset_thumb_timer.name = "AssetThumbBatchTimer"
		ed._asset_thumb_timer.one_shot = true
		ed._asset_thumb_timer.wait_time = 0.3
		ed._asset_thumb_timer.timeout.connect(func(): flush_asset_thumbs(ed))
		ed.add_child(ed._asset_thumb_timer)
	ed._asset_thumb_timer.start()
	# 选中素材刚下载完时预览立即升级真图（单个 resolve，量小；先清陈旧占位缓存）
	if asset_id == String(ed._selected_asset.get("id", "")) or asset_id == ed._selected_block_asset:
		if ed._asset_adapter != null:
			ed._asset_adapter.clear_cache(asset_id)
		update_asset_preview(ed)


## 合批刷新待刷缩略图：整批一次 clear_cache + 一次 resolve_many（单库解析）。
static func flush_asset_thumbs(ed) -> void:
	# 0.3s 合批：新下载的素材整体重建网格加入（列表=已下载集，重建即增量；不做逐按钮补丁）
	ed._pending_asset_thumbs.clear()
	rebuild_block_asset_grid(ed)
	BuildingPaletteScript.rebuild(ed)


## 选地形/植物调色板时清空素材选中（两组互斥，避免误放置）。
## 前景槽若仍是选中素材时写入的素材块，一并回落到当前地形：否则取消选择后
## 画笔仍在"隐形"刷素材，内置画笔/填充无法覆盖素材格（tile_override 清不掉）。
static func clear_asset_selection(ed) -> void:
	if ed._selected_asset.is_empty():
		return
	var was_building_place: bool = ed._building_place_mode
	ed._building_place_mode = false
	ed._selected_asset = {}
	if was_building_place and ed._canvas != null:
		ed._canvas.clear_paste_preview()
	BuildingPaletteScript.sync_selection(ed)
	if String(ed._block_fg.get("kind", "")) == "asset":
		ed._set_block_slot("fg", {"kind": "terrain", "id": String(ed.current_terrain), "z": int(ed._block_fg.z)})
	if ed._asset_panel != null:
		ed._asset_panel.deselect()
	update_asset_preview(ed)


## 库内容变化（导入/隐藏/编辑/清单同步）：校正方块页素材网格；
## 选中素材已不存在则清空选中；画布烘焙缓存已随库失效，整图刷新
static func on_asset_library_changed(ed) -> void:
	rebuild_block_asset_grid(ed)
	BuildingPaletteScript.rebuild(ed)
	MapEditorOverlaysScript.replace_populate_options(ed)
	if ed._selected_asset.is_empty():
		ed._refresh_canvas()
		return
	var aid := String(ed._selected_asset.get("id", ""))
	if not (ed._asset_service.find_by_id(aid) is Dictionary):
		clear_asset_selection(ed)
		if ed._asset_panel != null:
			ed._asset_panel.deselect()
	update_asset_preview(ed)
	ed._refresh_canvas()


## 画布预览格跟随素材选中（地块/植物素材统一走 adapter.resolve 烘焙视觉；
## 建筑素材关闭单格预览防双预览，改走整栋放置预览——跟随悬停格）
static func update_asset_preview(ed) -> void:
	if ed._canvas == null:
		return
	var d := active_asset(ed)
	if d.is_empty():
		ed._canvas.asset_preview_visual = {}
		MapEditorCellToolsScript.clear_building_preview(ed)
		return
	if String(d.get("kind", "")) == BattlefieldDocScript.ASSET_KIND_BUILDING:
		ed._canvas.asset_preview_visual = {}  # 建筑不走单格贴图预览
		MapEditorCellToolsScript.update_building_preview(
			ed, ed._canvas.hover_cell)
		return
	MapEditorCellToolsScript.clear_building_preview(ed)  # 非建筑素材不占建筑预览
	ed._canvas.asset_preview_visual = ed._asset_adapter.resolve(String(d.get("id", "")))


## 地形页建筑分组：选择即进入连续单击放置，与区域预设/粘贴/移动互斥。
static func on_building_selected(ed, asset_id: String) -> void:
	if ed._building_place_mode and String(ed._selected_asset.get("id", "")) == asset_id:
		clear_asset_selection(ed)
		ed._status("已退出建筑放置")
		return
	var descriptor: Variant = ed._asset_service.find_by_id(asset_id)
	if not descriptor is Dictionary or String(descriptor.get("kind", "")) != "building":
		return
	ed._seal_pending()
	ed._cancel_place_mode()
	ed._cancel_paste()
	if ed._move_tool_active:
		ed._set_move_tool(false)
	clear_asset_selection(ed)
	clear_block_asset_selection(ed)
	ed._selected_asset = descriptor.duplicate(true)
	ed._building_place_mode = true
	ed.current_prop = ""
	if ed._terrain_group != null:
		for button: BaseButton in ed._terrain_group.get_buttons():
			button.set_pressed_no_signal(false)
	BuildingPaletteScript.sync_selection(ed)
	update_asset_preview(ed)
	ed._status("建筑放置：移动鼠标实时预览，单击连续放置；T 换朝向，Esc 退出")


## 提交前在副本校验，失败不入历史；点击已有建筑不删除，拖动不提交。
static func commit_building_placement(ed, cell: Vector2i) -> void:
	var asset_id := String(ed._selected_asset.get("id", ""))
	if asset_id.is_empty():
		return
	var snapshot: Dictionary = preload("res://scripts/editor/map_editor_model_ops.gd").building_assets_snapshot(ed, asset_id)
	var candidate: Dictionary = ed.model.duplicate(true)
	var result: Dictionary = BattlefieldDocScript.add_building(candidate, asset_id, cell, int(ed._building_rotation), snapshot)
	if not bool(result.get("ok", false)):
		ed._status("放置失败：%s" % String(result.get("error", "建筑位置无效")), true)
		MapEditorCellToolsScript.update_building_preview(ed, cell)
		return
	ed._push_undo("放置建筑")
	ed.model = candidate
	ed._refresh_canvas()
	ed._seal_pending()
	MapEditorCellToolsScript.update_building_preview(ed, cell)
	ed._status("已放置建筑 → (%d,%d)，可继续放置；Esc 退出" % [cell.x, cell.y])
	print("[editor] 建筑连续放置 asset=%s cell=%s" % [asset_id, str(cell)])
