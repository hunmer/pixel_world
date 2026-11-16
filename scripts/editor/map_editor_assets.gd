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
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")


## 素材面板选中变化：写入选中态并同步画布预览格
static func on_asset_selected(ed, descriptor: Dictionary) -> void:
	ed._selected_asset = descriptor
	if String(descriptor.get("kind", "")) == UserAssetCatalogScript.KIND_TERRAIN:
		ed._set_block_slot("fg", {"kind": "asset", "id": String(descriptor.get("id", "")), "z": int(ed._block_fg.z)})
	ed._clear_block_asset_selection()  # 与方块页选中互斥
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
		ed._set_block_slot("fg", {"kind": "asset", "id": asset_id, "z": int(ed._block_fg.z)})
		ed._clear_asset_selection()  # 与素材 Tab 选中互斥
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


## 选地形/植物调色板时清空素材选中（两组互斥，避免误放置）
static func clear_asset_selection(ed) -> void:
	if ed._selected_asset.is_empty():
		return
	ed._selected_asset = {}
	if ed._asset_panel != null:
		ed._asset_panel.deselect()
	update_asset_preview(ed)


## 库内容变化（导入/隐藏/编辑/清单同步）：校正方块页素材网格；
## 选中素材已不存在则清空选中；画布烘焙缓存已随库失效，整图刷新
static func on_asset_library_changed(ed) -> void:
	rebuild_block_asset_grid(ed)
	MapEditorOverlaysScript.replace_populate_options(ed)
	if ed._selected_asset.is_empty():
		ed._refresh_canvas()
		return
	var aid := String(ed._selected_asset.get("id", ""))
	if not (ed._asset_service.find_by_id(aid) is Dictionary):
		ed._selected_asset = {}
		if ed._asset_panel != null:
			ed._asset_panel.deselect()
	update_asset_preview(ed)
	ed._refresh_canvas()


## 画布预览格跟随素材选中（地块/植物素材统一走 adapter.resolve 烘焙视觉）
static func update_asset_preview(ed) -> void:
	if ed._canvas == null:
		return
	var d := active_asset(ed)
	if d.is_empty():
		ed._canvas.asset_preview_visual = {}
		return
	ed._canvas.asset_preview_visual = ed._asset_adapter.resolve(String(d.get("id", "")))
