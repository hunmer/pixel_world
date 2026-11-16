## block_selector.gd — 通用方块选择器（内置地形 + 已保存地块素材，统一选中信号）
##
## 从 map_editor.gd「地形页调色板 + 方块页素材网格」抽出的可复用选择组件：
##   - 内置地形组：BattlefieldDoc.TERRAIN_GLYPH 全量地形单块 tile（TilePreview 缩略图）
##   - 素材方块组：素材库中 kind=terrain 且 saved=true 的资产（resolve_many 单次
##     库加载批量出图——逐 id resolve 会反复整库 JSON 解析把编辑器卡死；
##     asset_ready 下载完成事件 0.3s 合批后整体重建，只换受影响缩略图）
## 两组共用一个 ButtonGroup（allow_unpress：再点一次取消选中），经统一信号上报：
##   selection_changed(kind, id)
##     kind=&"terrain"（id=地形名，如 &"water"） / &"asset"（id=素材 id）
##     取消选中：(&"", "")
## 宿主（map_editor / Kimi 的框选工具）可用 selected()/select_terrain()/
## select_asset()/deselect() 程序化同步，refresh_assets() 在库内容变化后重建，
## on_asset_ready(asset_id) 对接 service.asset_ready（setup 时若 service 有该信号
## 会自动连接）。依赖注入 setup(service, adapter) 鸭子类型：service 需
## list_assets/get_asset_state/request_asset_image（+可选 asset_ready 信号），
## adapter 需 resolve_many/resolve（+可选 clear_cache）；传 null 则该组不可用
## （service=null 时只显示内置地形）。假对象可注入，headless 契约可测。

class_name BlockSelector
extends VBoxContainer

const BattlefieldDocScript := preload("res://scripts/editor/battlefield_doc.gd")
const TilePreviewScript := preload("res://scripts/editor/tile_preview.gd")
const UIThemeScript := preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript := preload("res://scripts/ui/ui_factory.gd")

## 选中项类别常量（selection_changed 的 kind / selected() 的 kind）。
const KIND_TERRAIN := &"terrain"
const KIND_ASSET := &"asset"
const KIND_NONE := &""

## 统一选中信号：kind=KIND_TERRAIN/KIND_ASSET，取消选中时 (KIND_NONE, "")。
signal selection_changed(kind: StringName, id: String)

const GRID_COLUMNS := 4
const THUMB_BATCH_DELAY := 0.3

var _group: ButtonGroup = null
var _terrain_grid: GridContainer = null
var _asset_header: Control = null
var _asset_grid: GridContainer = null
var _asset_empty: Label = null

var _terrain_buttons: Dictionary = {}  # StringName terrain -> Button
var _asset_buttons: Dictionary = {}  # String asset_id -> Button

var _service = null  # UserAssetService（鸭子类型，可 null）
var _adapter = null  # UserAssetVisualAdapter（鸭子类型，可 null）

var _pending_thumbs: Dictionary = {}  # asset_id -> true（0.3s 合批待刷）
var _thumb_timer: Timer = null

## 测试观测：素材网格重建次数（合批前后各 +1 次 resolve_many 的依据）。
var debug_rebuild_count := 0

var _selected_kind: StringName = KIND_NONE
var _selected_id := ""


## 注入依赖并构建 UI；可重复调用（重建）。service/adapter 皆可传 null。
func setup(p_service = null, p_adapter = null) -> void:
	if _service != null and _service != p_service and _service.has_signal("asset_ready"):
		if _service.is_connected("asset_ready", on_asset_ready):
			_service.disconnect("asset_ready", on_asset_ready)
	_service = p_service
	_adapter = p_adapter
	if _service != null and _service.has_signal("asset_ready"):
		_service.asset_ready.connect(on_asset_ready)
	_rebuild_ui()


func _rebuild_ui() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_terrain_buttons.clear()
	_asset_buttons.clear()
	_pending_thumbs.clear()

	_group = ButtonGroup.new()
	_group.allow_unpress = true

	add_theme_constant_override("separation", 6)

	var terrain_label := _section_label("内置地形")
	add_child(terrain_label)
	_terrain_grid = GridContainer.new()
	_terrain_grid.columns = GRID_COLUMNS
	_terrain_grid.add_theme_constant_override("h_separation", 4)
	_terrain_grid.add_theme_constant_override("v_separation", 4)
	add_child(_terrain_grid)
	for t: StringName in BattlefieldDocScript.TERRAIN_GLYPH:
		var tb := _terrain_btn(t)
		_terrain_grid.add_child(tb)
		_terrain_buttons[t] = tb

	_asset_header = _section_label("素材方块（已保存）")
	add_child(_asset_header)
	_asset_grid = GridContainer.new()
	_asset_grid.columns = GRID_COLUMNS
	_asset_grid.add_theme_constant_override("h_separation", 4)
	_asset_grid.add_theme_constant_override("v_separation", 4)
	add_child(_asset_grid)
	_asset_empty = _section_label("（暂无已保存方块素材）")
	add_child(_asset_empty)
	_has_asset_section_changed()
	refresh_assets(true)


func _has_asset_section_changed() -> void:
	var has_assets := _service != null and _adapter != null
	if _asset_header != null:
		_asset_header.visible = has_assets
	if _asset_grid != null:
		_asset_grid.visible = has_assets
	if _asset_empty != null:
		_asset_empty.visible = false


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UIThemeScript.TEXT_DIM)
	return l


## 内置地形按钮：tile 缩略图（无文字，悬停提示地形名），meta=terrain。
## 按钮经 UIFactory.button 创建（PixelButton 组件、音效已关、默认叠
## style_button，等价原 _pixel_btn 直建 + 手动样式两步）。
func _terrain_btn(t: StringName) -> Button:
	var tb := UIFactoryScript.button()
	tb.toggle_mode = true
	tb.button_group = _group
	tb.custom_minimum_size = Vector2(46, 96)
	tb.tooltip_text = "%s（%s）" % [
		String(BattlefieldDocScript.TERRAIN_CN.get(t, String(t))),
		String(BattlefieldDocScript.TERRAIN_GLYPH[t]),
	]
	tb.set_meta("terrain", t)
	var prev := TilePreviewScript.new(t, false)
	tb.add_child(prev)
	tb.pressed.connect(_on_tile_pressed.bind(tb))
	return tb


## 素材方块按钮：与地形按钮同风格；visual 由 resolve_many 批量传入，
## 缺省才回退单条 resolve（避免整库 JSON 反复解析）。
func _asset_btn(asset_id: String, d: Dictionary, visual: Dictionary = {}) -> Button:
	var tb := UIFactoryScript.button()
	tb.toggle_mode = true
	tb.button_group = _group
	tb.custom_minimum_size = Vector2(46, 96)
	tb.tooltip_text = "%s（%s）" % [String(d.get("name", asset_id)), asset_id]
	tb.set_meta("block_asset", asset_id)
	var prev := TilePreviewScript.new(&"plain", false)
	if not visual.is_empty():
		prev.asset_visual = visual
	elif _adapter != null:
		prev.asset_visual = _adapter.resolve(asset_id)
	tb.add_child(prev)
	tb.pressed.connect(_on_tile_pressed.bind(tb))
	return tb


## 按钮按下/取消统一入口：allow_unpress 下再点已选中项 = 取消选中。
func _on_tile_pressed(btn: Button) -> void:
	if not btn.button_pressed:
		_set_selection(KIND_NONE, "", btn)
		return
	if btn.has_meta("terrain"):
		_set_selection(KIND_TERRAIN, String(btn.get_meta("terrain")), btn)
	elif btn.has_meta("block_asset"):
		_set_selection(KIND_ASSET, String(btn.get_meta("block_asset")), btn)


func _set_selection(kind: StringName, id: String, skip_btn: Button = null) -> void:
	_selected_kind = kind
	_selected_id = id
	if skip_btn == null:
		_unpress_all()
	selection_changed.emit(kind, id)


func _unpress_all() -> void:
	if _group == null:
		return
	var pb := _group.get_pressed_button()
	if pb != null:
		pb.set_pressed_no_signal(false)


## 重建素材方块网格（库内容变化/合批刷新后调用）：过滤 kind=terrain 且
## saved=true，按 id 稳定排序，resolve_many 单次批量出图；未下载的顺手触发
## 自动加载（完成后经 asset_ready 合批换真图）。选中项仍存在则恢复按下态，
## 已消失则清空并广播取消。默认广播；首次构建传 silent=true 只恢复不广播。
func refresh_assets(silent := false) -> void:
	if _asset_grid == null:
		return
	for child in _asset_grid.get_children():
		_asset_grid.remove_child(child)
		child.queue_free()
	_asset_buttons.clear()
	debug_rebuild_count += 1
	var ids: Array = []
	var descs := {}
	if _service != null and _adapter != null:
		var assets: Array = _service.list_assets()
		assets.sort_custom(
			func(a, b): return String((a as Dictionary).get("id", "")) < String((b as Dictionary).get("id", ""))
		)
		for raw in assets:
			var d := raw as Dictionary
			if String(d.get("kind", "")) != "terrain":
				continue
			if not bool(d.get("saved", false)):
				continue
			var aid := String(d.get("id", ""))
			ids.append(aid)
			descs[aid] = d
			if String(_service.get_asset_state(aid).get("status", "")) != "ready":
				_service.request_asset_image(aid)
		var visuals: Dictionary = _adapter.resolve_many(ids, false)
		for aid in ids:
			var tb := _asset_btn(aid, descs[aid], visuals.get(aid, {}))
			_asset_grid.add_child(tb)
			_asset_buttons[aid] = tb
	if _asset_empty != null:
		_asset_empty.visible = _service != null and _adapter != null and ids.is_empty()
	# 选中项恢复：仍存在→恢复按下态；已消失→清空选中并广播取消
	if _selected_kind == KIND_ASSET and not _asset_buttons.has(_selected_id):
		_selected_kind = KIND_NONE
		_selected_id = ""
		if not silent:
			selection_changed.emit(KIND_NONE, "")
	_restore_selection_buttons()


func _restore_selection_buttons() -> void:
	if _group == null:
		return
	if _selected_kind == KIND_TERRAIN and _terrain_buttons.has(_selected_id):
		(_terrain_buttons[_selected_id] as Button).set_pressed_no_signal(true)
	elif _selected_kind == KIND_ASSET and _asset_buttons.has(_selected_id):
		(_asset_buttons[_selected_id] as Button).set_pressed_no_signal(true)


## 素材图片下载完成（service.asset_ready）：记入待刷集合，0.3s 合批一次重建
## （下载洪流期间逐事件重建/解析会反复整库 JSON 解析刷屏）。选中素材刚下载完
## 时立即单按钮换真图（量小，先清陈旧占位缓存）。
func on_asset_ready(asset_id: String) -> void:
	_pending_thumbs[asset_id] = true
	if _thumb_timer == null or not is_instance_valid(_thumb_timer):
		_thumb_timer = Timer.new()
		_thumb_timer.name = "AssetThumbBatchTimer"
		_thumb_timer.one_shot = true
		_thumb_timer.wait_time = THUMB_BATCH_DELAY
		_thumb_timer.timeout.connect(_flush_thumbs)
		add_child(_thumb_timer)
	_thumb_timer.start()
	if _selected_kind == KIND_ASSET and asset_id == _selected_id:
		if _adapter != null and _adapter.has_method("clear_cache"):
			_adapter.clear_cache(asset_id)
		_swap_asset_thumb(asset_id)


func _flush_thumbs() -> void:
	_pending_thumbs.clear()
	refresh_assets()


## 单按钮缩略图换新（不重建网格）：选中素材下载完成的立即升级路径。
func _swap_asset_thumb(asset_id: String) -> void:
	var btn: Button = _asset_buttons.get(asset_id)
	if btn == null or _adapter == null:
		return
	var visual: Dictionary = _adapter.resolve(asset_id)
	if visual.is_empty():
		return
	for child in btn.get_children():
		if child is TilePreviewScript:
			(child as TilePreviewScript).asset_visual = visual
			return


## 当前选中项：{"kind": StringName, "id": String}；未选中 kind=KIND_NONE、id=""。
func selected() -> Dictionary:
	return {"kind": _selected_kind, "id": _selected_id}


## 程序化选中内置地形（不存在返回 false，不改状态）。
func select_terrain(t: StringName) -> bool:
	if not _terrain_buttons.has(t):
		return false
	_selected_kind = KIND_TERRAIN
	_selected_id = String(t)
	_restore_selection_buttons()
	selection_changed.emit(KIND_TERRAIN, String(t))
	return true


## 程序化选中素材方块（当前网格中不存在返回 false，不改状态）。
func select_asset(asset_id: String) -> bool:
	if not _asset_buttons.has(asset_id):
		return false
	_selected_kind = KIND_ASSET
	_selected_id = asset_id
	_restore_selection_buttons()
	selection_changed.emit(KIND_ASSET, asset_id)
	return true


## 清空选中；silent=true 不广播（构建期恢复用）。
func deselect(silent := false) -> void:
	if _selected_kind == KIND_NONE and _selected_id.is_empty():
		if not silent:
			selection_changed.emit(KIND_NONE, "")
		return
	_selected_kind = KIND_NONE
	_selected_id = ""
	_unpress_all()
	if not silent:
		selection_changed.emit(KIND_NONE, "")
