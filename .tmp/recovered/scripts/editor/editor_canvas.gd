## editor/editor_canvas.gd — 编辑器画布（等距方块版，IsoBoard 3D 相机）
##
## 复用 BattlefieldRenderer + IsoBoard（与 B2 战棋同款 IsometricCamera3D）：
## 视角旋转（Q/E/Z/X/R）、滚轮/双指捏合缩放、右键拖拽或空格+左键平移。
## 左键按下/拖动发出 cell 信号，由 map_editor.gd 按工具解释。
## 悬停/选中标记使用屏幕空间 2D 覆盖层；已放置单位复用战场 UnitSprite3D，
## 职业精灵、脚底锚点、相机转向和深度遮挡均与 B2 战场一致。

class_name EditorCanvas
extends Control

const BattlefieldRendererScript = preload("res://scripts/iso/battlefield_renderer.gd")
const RegionClipboardScript = preload("res://scripts/editor/region_clipboard.gd")
const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const IsoBoardScript = preload("res://scripts/iso/iso_board.gd")
const SunlightSystemScript = preload("res://scripts/sunlight_system.gd")
const UserAssetVisualAdapterScript = preload("res://scripts/assets/user_asset_visual_adapter.gd")
const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")

signal cell_pressed(cell: Vector2i)
signal cell_dragged(cell: Vector2i)
signal cell_released(cell: Vector2i)
signal hover_changed(cell: Vector2i)

const HOVER_COLOR := Color(1.0, 0.85, 0.3, 0.55)
const SELECTION_COLOR := Color(0.25, 0.95, 1.0, 0.62)
## 区域虚线投影描边色（框选范围边框；深色底衬见 _RegionOutlineMark）
const REGION_COLOR := Color(0.3, 0.98, 0.75, 0.95)
const REGION_DASH := 8.0
const REGION_GAP := 6.0
const REGION_LINE_WIDTH := 2.0
## 粘贴预览描边色（与区域虚线同一套几何）：绿=合法落点，红=越界/非法
const PASTE_OK_COLOR := Color(0.45, 1.0, 0.5, 0.95)
const PASTE_BAD_COLOR := Color(1.0, 0.35, 0.3, 0.95)
## 滚轮/手势每步缩放因子（与 B2 battle.gd 一致：factor<1 = 放大一步）
const WHEEL_ZOOM_IN := 0.9
const WHEEL_ZOOM_OUT := 1.1

## 编辑器模型引用（BattlefieldDoc 模型 dict；由 map_editor.gd 维护并触发重建）
var model: Dictionary = {}:
	set(v):
		model = v
		_rebuild()

var hover_cell := Vector2i(-1, -1)
var selected_cell := Vector2i(-1, -1):
	set(value):
		selected_cell = value
		_update_selection_marker()
## 区域虚线投影（框选范围边框）：{"min": Vector2i, "max": Vector2i, "z": int}，
## z>=0 = 固定方块高度层的平面四边形；z<0 = 跟随地形逐格高度（周界分段）。
## 由 set_selection_region()/clear_selection_region() 维护（含归一与坐标校验），
## 描边随相机逐帧对齐（_process 视图缓存变化时重算）。
var selection_region: Dictionary = {}:
	set(v):
		selection_region = v
		_update_region_marker()
var _world: Node2D = null
var _renderer: Node2D = null
var _board: IsoBoard = null
## 用户素材视觉适配器（asset_id → 烘焙 visual；缺图返回占位）。
## map_editor.gd 可注入共享实例（与素材面板同库同缓存）；默认独立读 user://custom_assets。
var asset_adapter: RefCounted = UserAssetVisualAdapterScript.new()
## 素材悬停预览（map_editor 选中素材时由 adapter.resolve 烘焙写入；空=不显示）
var asset_preview_visual: Dictionary = {}:
	set(v):
		asset_preview_visual = v
		_update_asset_preview_marker()
var _asset_preview_marker: Node2D = null
var _hover_marker: Polygon2D = null
var _selection_marker: Polygon2D = null
var _region_marker: Node2D = null
## 粘贴预览标记（绿/红虚线框；与区域虚线同一套几何与 dash 参数）
var _paste_marker: Node2D = null
## 粘贴预览区域：{"min": Vector2i, "max": Vector2i, "valid": bool}
var _paste_region: Dictionary = {}
## 正式放置操作生成的显示副本；权威模型和撤销历史保持不变。
var _placement_model: Dictionary = {}
var _placement_cell_count := 0
## 建筑预览不是正式 model.buildings；instance_id 固定保留字，退出素材工具时清除。
var _building_preview: Dictionary = {}
var _building_quadrant := -1
var _unit_markers: Array[UnitSprite3D] = []
var _dragging := false
var _panning := false
## 本次左键笔画的落格 cell（press 时记下；release 无移动时 hover 可能为空）
var _press_cell := Vector2i(-1, -1)
## 视图状态缓存（相机 yaw/elevation/zoom/focus + 画布全局矩形）：
## 任一变化时重算悬停/选中多边形（相机旋转是平滑动画）。
var _view_cache := {}

## 右侧栏宽度（世界单位换算预留列，同 main.gd reserved_right_px）：
## 让 3D 取景对齐「去掉侧栏后的画布舞台」中心，而非整个窗口中心。
var sidebar_reserved_px: float = 0.0:
	set(value):
		sidebar_reserved_px = maxf(value, 0.0)
		if _board != null and _board.camera != null:
			_board.camera.reserved_right_px = sidebar_reserved_px


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	# 3D 视图轴：IsoBoard = IsometricCamera3D（旋转/缩放/平移/拾取，B2 同款）
	_board = IsoBoardScript.new()
	_board.name = "EditorBoard"
	add_child(_board)
	_board.camera.reserved_right_px = sidebar_reserved_px
	# 屏幕空间覆盖层（恒等变换，坐标 = 画布局部 = 视口坐标 - 画布全局原点）
	_world = Node2D.new()
	_world.name = "EditorWorld"
	add_child(_world)
	_renderer = BattlefieldRendererScript.new()
	_board.add_child(_renderer)
	# 编辑器没有 main.gd 的日光系统，而地形材质是逐像素着色（自 3D 日照提交起），
	# 无真实光照会把整块画布渲成黑色。挂一盏固定正午阳光（与 battle.gd B2 同款）。
	var sunlight := SunlightSystemScript.new()
	sunlight.name = "EditorSunlight"
	_board.add_child(sunlight)
	sunlight.apply_time(0.5, 0.0)
	_hover_marker = Polygon2D.new()
	_hover_marker.name = "HoverMarker"
	_hover_marker.z_index = 20
	_hover_marker.color = HOVER_COLOR
	_hover_marker.visible = false
	_world.add_child(_hover_marker)
	_selection_marker = Polygon2D.new()
	_selection_marker.name = "SelectionMarker"
	_selection_marker.z_index = 19
	_selection_marker.color = SELECTION_COLOR
	_selection_marker.visible = false
	_world.add_child(_selection_marker)
	# 区域虚线投影（框选范围边框；z 介于素材预览与选中标记之间）
	_region_marker = _RegionOutlineMark.new()
	_region_marker.name = "RegionOutlineMark"
	_region_marker.z_index = 17
	_region_marker.line_color = REGION_COLOR
	_region_marker.dash_len = REGION_DASH
	_region_marker.gap_len = REGION_GAP
	_region_marker.line_width = REGION_LINE_WIDTH
	_region_marker.visible = false
	_world.add_child(_region_marker)
	# 粘贴预览框（绿=合法/红=非法落点；置于区域虚线之下，粘贴目标与框选可并存）
	_paste_marker = _RegionOutlineMark.new()
	_paste_marker.name = "PastePreviewMark"
	_paste_marker.z_index = 16
	_paste_marker.line_color = PASTE_OK_COLOR
	_paste_marker.dash_len = REGION_DASH
	_paste_marker.gap_len = REGION_GAP
	_paste_marker.line_width = REGION_LINE_WIDTH
	_paste_marker.visible = false
	_world.add_child(_paste_marker)
	# 素材预览块（选中素材时跟随悬停格顶面中心，z 介于选中与悬停标记之间）
	_asset_preview_marker = _AssetPreviewMark.new()
	_asset_preview_marker.name = "AssetPreviewMark"
	_asset_preview_marker.z_index = 18
	_asset_preview_marker.visible = false
	_world.add_child(_asset_preview_marker)
	# 容器化布局：尺寸由父容器分配（首帧 0->实际值），变化时重居中地图
	resized.connect(_on_canvas_resized)


func _rebuild() -> void:
	if _world == null:
		return  # _ready 未跑（未进树）
	_placement_model = {}
	_placement_cell_count = 0
	_clear_unit_markers()
	if model.is_empty():
		_renderer.setup(null)
		_hover_marker.visible = false
		_selection_marker.visible = false
		if _region_marker != null:
			_region_marker.visible = false
		if _paste_marker != null:
			_paste_marker.visible = false
		clear_block_ghost()
		return
	_clamp_selection_region()
	_render_model(model)
	_center_map()


## 正式模型与放置副本共用同一条 3D 渲染路径，不重置相机。
func _render_model(document: Dictionary) -> void:
	_renderer.set_custom_props(document.get("props", []))  # 植物层（setup 前注入）
	_renderer.set_custom_assets(
		asset_adapter.visual_for_entries(document.get("props", []), document.get("tile_overrides", {}))
	)  # 用户素材视觉层（props 的 asset_id + tile_overrides）
	_sync_building_quadrant()
	_renderer.set_building_visuals(_building_entries_for(document), false)
	_renderer.set_block_layout(document.get("block_layout", {}))
	_renderer.setup(_build_grid(document))
	_rebuild_unit_markers()
	_update_hover_marker()
	_update_selection_marker()
	_update_region_marker()
	_update_paste_marker()


## 模型 rows（图例字符画）-> GridSystem（全名地形矩阵）
func _build_grid(document: Dictionary) -> GridSystem:
	var rows: Array = document.rows
	var map: Array = []
	for y in range(document.height):
		var row: String = rows[y]
		var line: Array = []
		for x in range(document.width):
			line.append(BattlefieldDocScript.glyph_to_terrain(row.substr(x, 1)))
		map.append(line)
	return GridSystem.new(document.width, document.height, map)


## 单格重建（画笔/填充/植物/橡皮后由 map_editor.gd 调 _refresh_cell）
func _refresh_cell(cell: Vector2i) -> void:
	if _renderer == null or _renderer.grid == null:
		return
	if cell.x < 0 or cell.y < 0 or cell.x >= model.width or cell.y >= model.height:
		return
	# rows 是权威源：先把该格地形同步进渲染器网格，再重建柱（否则画笔无视觉效果）
	var terrain: StringName = BattlefieldDocScript.glyph_to_terrain((model.rows[cell.y] as String).substr(cell.x, 1))
	(_renderer.grid.tiles[cell.y][cell.x] as Dictionary)["type"] = terrain
	# 植物层同步：该格 props 覆盖表条目；显式方块布局下无条目即不添加默认装饰
	_renderer.set_cell_prop(cell, BattlefieldDocScript.prop_at(model, cell))
	# 用户素材视觉层同步：prop 层（props 的 asset_id）与 tile 层（tile_overrides）独立清除
	_sync_cell_assets(cell)
	# renderer 持有布局深拷贝；每次单格刷新都必须同步，否则 z 改了模型却不改画面。
	_renderer.set_block_layout(model.get("block_layout", {}))
	_renderer.refresh_cell(cell.x, cell.y)
	_refresh_markers_at(cell)


func _center_map() -> void:
	if _board == null or _board.camera == null or model.is_empty():
		return
	_board.center_on_map(int(model.width), int(model.height))


## 单格素材视觉同步：prop 层（props 的 asset_id）与 tile 层（tile_overrides）
## 各自独立设置/清除（renderer 两层并存；空 visual = 清除该层）。
func _sync_cell_assets(cell: Vector2i) -> void:
	var prop_aid: String = BattlefieldDocScript.prop_asset_at(model, cell)
	_renderer.set_cell_asset(cell, "prop", _visual_or_empty(prop_aid))
	var tile_aid: String = BattlefieldDocScript.tile_override_at(model, cell)
	_renderer.set_cell_asset(cell, "tile", _visual_or_empty(tile_aid))


func _visual_or_empty(asset_id: String) -> Dictionary:
	if asset_id.is_empty():
		return {}
	return asset_adapter.resolve(asset_id)


## 建筑素材悬停预览：与正式建筑共用 adapter → renderer 单实例通路。
func set_building_preview(asset_id: String, origin: Vector2i, rotation: int = 0) -> void:
	if asset_id.is_empty() or origin.x < 0 or origin.y < 0:
		clear_building_preview()
		return
	_building_preview = {
		"instance_id": "__building_preview__",
		"asset_id": asset_id,
		"x": origin.x,
		"y": origin.y,
		"rotation": posmod(rotation, 4),
		"use_library": true,
	}
	asset_preview_visual = {}
	_sync_building_visuals()


func clear_building_preview() -> void:
	if _building_preview.is_empty():
		return
	_building_preview = {}
	_sync_building_visuals()


func _sync_building_visuals() -> void:
	if _renderer == null:
		return
	_renderer.set_building_visuals(_building_entries_for(_display_model()))


func _building_entries_for(document: Dictionary) -> Array:
	if document.is_empty():
		return []
	var buildings: Array = document.get("buildings", []).duplicate(true)
	if not _building_preview.is_empty():
		buildings.append(_building_preview.duplicate(true))
	return asset_adapter.visual_for_buildings(buildings, document.get("user_assets", {}))


## 建筑素材悬停预览：与正式建筑共用 adapter → renderer 单实例通路。
func set_building_preview(asset_id: String, origin: Vector2i, rotation: int = 0) -> void:
	if asset_id.is_empty() or origin.x < 0 or origin.y < 0:
		clear_building_preview()
		return
	_building_preview = {
		"instance_id": "__building_preview__",
		"asset_id": asset_id,
		"x": origin.x,
		"y": origin.y,
		"rotation": posmod(rotation, 4),
		"use_library": true,
	}
	asset_preview_visual = {}
	_sync_building_visuals()


func clear_building_preview() -> void:
	if _building_preview.is_empty():
		return
	_building_preview = {}
	_sync_building_visuals()


func _sync_building_visuals() -> void:
	if _renderer == null:
		return
	_renderer.set_building_visuals(_building_entries_for(_display_model()))


func _building_entries_for(document: Dictionary) -> Array:
	if document.is_empty():
		return []
	var buildings: Array = document.get("buildings", []).duplicate(true)
	if not _building_preview.is_empty():
		buildings.append(_building_preview.duplicate(true))
	return asset_adapter.visual_for_buildings(buildings, document.get("user_assets", {}))


## 容器尺寸变化（含首次布局 0->实际值）-> 重居中，保持地图可见。
## 相机投影以视口高为基准，侧栏预留由 reserved_right_px 处理。
func _on_canvas_resized() -> void:
	if _renderer != null and _renderer.grid != null:
		_center_map()
		_refresh_hover(get_local_mouse_position())


# ============================================================
# 输入：左键=工具操作，右键拖拽或空格+左键拖拽=平移，
# 滚轮/双指捏合=缩放，双指滚动（纵向）=缩放 —— 与 B2 战棋一致。
# 注意：_gui_input 里鼠标事件 position 是画布局部坐标，
# 手势事件（Magnify/PanGesture）position 是视口坐标，缩放锚点需区分换算。
# ============================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		# 双指捏合：捏合张开（factor>1）→ 1/factor<1 → 放大（B2 同款公式，连续平滑缩放）
		var mag := event as InputEventMagnifyGesture
		var factor := clampf(1.0 / mag.factor, 0.5, 2.0)
		_board.zoom_by(factor, mag.position, get_viewport().get_visible_rect().size)
		accept_event()
		return
	elif event is InputEventPanGesture:
		# 双指滚动：纵向主导视为缩放（B2 同款系数）
		var pan_g := event as InputEventPanGesture
		if absf(pan_g.delta.y) > absf(pan_g.delta.x):
			var factor := clampf(1.0 + pan_g.delta.y * 0.08, 0.75, 1.25)
			_board.zoom_by(factor, pan_g.position, get_viewport().get_visible_rect().size)
			accept_event()
		return
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			_board.pan(mm.relative.x, mm.relative.y)
			_refresh_hover(mm.position)
			accept_event()
			return
		_refresh_hover(mm.position)
		var c := hover_cell
		if _dragging and c.x >= 0:
			cell_dragged.emit(c)
			accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if Input.is_key_pressed(KEY_SPACE):
					# 按住空格 + 左键拖拽 = 平移（与 B1/B2 战场一致）
					_panning = true
					accept_event()
					return
				var c := _pick(mb.position)
				if c.x >= 0:
					_dragging = true
					_press_cell = c
					cell_pressed.emit(c)
					accept_event()
			else:
				if _dragging:
					# 本次笔画以 cell press 开始 → 释放即提交（拖拽终点优先，无移动回落到落格）
					var rc := hover_cell if hover_cell.x >= 0 else _press_cell
					if rc.x >= 0:
						cell_released.emit(rc)
				_dragging = false
				_panning = false
				_press_cell = Vector2i(-1, -1)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mb.pressed
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_wheel(WHEEL_ZOOM_IN, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_wheel(WHEEL_ZOOM_OUT, mb.position)
			accept_event()


## 视角旋转 ±90°（Q/E/Z/X）与复位（R）—— 转发到 IsoBoard 相机。
func rotate_view(direction: int) -> void:
	if _board != null and _board.camera != null:
		_board.camera.rotate_step(direction)
		_sync_building_quadrant()


func reset_view() -> void:
	if _board != null and _board.camera != null:
		_board.camera.reset_rotation()
		_sync_building_quadrant()


## 滚轮缩放一步：factor<1 = 放大（B2 battle.gd 语义）。anchor 为画布局部坐标。
func _zoom_wheel(factor: float, local_anchor: Vector2) -> void:
	_board.zoom_by(factor, _local_to_screen(local_anchor), get_viewport().get_visible_rect().size)


## 画布局部坐标 → 视口屏幕坐标（相机投影/拾取用）。
func _local_to_screen(local_pos: Vector2) -> Vector2:
	return get_global_rect().position + local_pos


## 视口屏幕坐标 → 画布局部坐标（屏幕空间覆盖层定位用）。
func _screen_to_local(screen_pos: Vector2) -> Vector2:
	return screen_pos - get_global_rect().position


func _refresh_hover(local_pos: Vector2) -> void:
	var cell := _pick(local_pos)
	if cell == hover_cell:
		return
	hover_cell = cell
	_update_hover_marker()
	hover_changed.emit(cell)


## 画布局部坐标 -> cell（3D 相机射线拾取，多高度感知）
func _pick(local_pos: Vector2) -> Vector2i:
	if _renderer == null or _renderer.grid == null:
		return Vector2i(-1, -1)
	if not _placement_model.is_empty() and _board != null and _board.camera != null:
		# 预览抬高/降低地形不能反过来移动落点；拾取仍以正式模型为准。
		var hit: Dictionary = IsoProjection.pick_top_face(_board.camera,
			_local_to_screen(local_pos), 0, BattlefieldRendererScript.PICK_MAX_LEVEL,
			Callable(self, "_pick_document_top_level"))
		return hit.get("cell", Vector2i(-1, -1)) as Vector2i
	return _renderer.pick_cell(_local_to_screen(local_pos), size)


func _pick_document_top_level(cell: Vector2i) -> float:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(model.width) or cell.y >= int(model.height):
		return -1.0
	return float(BattlefieldDocScript.cell_z(model, cell))


## 相机旋转/缩放是平滑动画：逐帧检查视图状态，变化时重算覆盖层。
func _process(_delta: float) -> void:
	if _board == null or _board.camera == null or _renderer == null:
		return
	var cam := _board.camera
	_sync_building_quadrant()
	var view := {
		"yaw": cam.yaw_radians,
		"elev": cam.elevation_radians,
		"zoom": cam.zoom,
		"focus": cam.focus_position,
		"origin": get_global_rect().position,
	}
	if _view_cache.is_empty() or str(view) != str(_view_cache):
		_view_cache = view
		_update_hover_marker()
		_update_selection_marker()
		_update_region_marker()
		_update_paste_marker()


func _sync_building_quadrant() -> void:
	if _board == null or _board.camera == null or _renderer == null:
		return
	var quadrant := _target_camera_quadrant()
	if quadrant == _building_quadrant:
		return
	_building_quadrant = quadrant
	_renderer.set_camera_quadrant(quadrant)


func _target_camera_quadrant() -> int:
	if _board == null or _board.camera == null:
		return 0
	var relative: float = _board.camera.target_yaw_radians - IsoProjection.CAMERA_YAW
	return posmod(int(roundf(relative / (PI * 0.5))), 4)


func _update_hover_marker() -> void:
	if _hover_marker == null:
		return
	if hover_cell.x < 0 or _renderer.grid == null:
		_hover_marker.visible = false
		return
	_hover_marker.polygon = _poly_to_local(_renderer.top_polygon_for(hover_cell.x, hover_cell.y))
	_hover_marker.visible = true
	_update_asset_preview_marker()


## 素材预览跟随悬停格（视觉烘焙含 render_offset；与 renderer 素材块同一套锚点规则）
func _update_asset_preview_marker() -> void:
	if _asset_preview_marker == null:
		return
	if asset_preview_visual.is_empty() or hover_cell.x < 0 \
			or _renderer == null or _renderer.grid == null:
		_asset_preview_marker.visible = false
		return
	_asset_preview_marker.visual = asset_preview_visual
	_asset_preview_marker.position = _screen_to_local(
		_renderer.top_center_for(hover_cell.x, hover_cell.y))
	_asset_preview_marker.visible = true


func _update_selection_marker() -> void:
	if _selection_marker == null:
		return
	if selected_cell.x < 0 or _renderer == null or _renderer.grid == null:
		_selection_marker.visible = false
		return
	if selected_cell.x >= int(model.get("width", 0)) or selected_cell.y >= int(model.get("height", 0)):
		_selection_marker.visible = false
		return
	_selection_marker.polygon = _poly_to_local(_renderer.top_polygon_for(selected_cell.x, selected_cell.y))
	_selection_marker.visible = true


## 视口坐标多边形 → 画布局部坐标多边形（覆盖层挂 _world 恒等变换下）。
func _poly_to_local(poly: PackedVector2Array) -> PackedVector2Array:
	var offset := get_global_rect().position
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in poly.size():
		out[i] = poly[i] - offset
	return out


# ============================================================
# 区域虚线投影（框选范围边框接口）
# ============================================================

## 设置区域虚线投影：闭区间 [min_cell, max_cell]（两轴顺序任意，自动归一）。
## z>=0 = 该方块高度层的平面四边形；z<0（默认）= 跟随地形逐格高度。
## z_max>z（仅 z>=0 有意义）= 立体选择体：z 底面 + z_max 顶面 + 四角立边；
## z_max<=z 时按平面处理（字典不含 z_max 键，保持旧形状）。
## 坐标校验：与模型无交集（完全在边界外）→ 清空；部分越界 → 夹回边界内。
func set_selection_region(min_cell: Vector2i, max_cell: Vector2i, z := -1, z_max := -1) -> void:
	var lo := Vector2i(mini(min_cell.x, max_cell.x), mini(min_cell.y, max_cell.y))
	var hi := Vector2i(maxi(min_cell.x, max_cell.x), maxi(min_cell.y, max_cell.y))
	var w := int(model.get("width", 0))
	var h := int(model.get("height", 0))
	if w <= 0 or h <= 0 or hi.x < 0 or hi.y < 0 or lo.x >= w or lo.y >= h:
		selection_region = {}
		return
	lo = Vector2i(clampi(lo.x, 0, w - 1), clampi(lo.y, 0, h - 1))
	hi = Vector2i(clampi(hi.x, 0, w - 1), clampi(hi.y, 0, h - 1))
	if z >= 0 and z_max > z:
		selection_region = {"min": lo, "max": hi, "z": z, "z_max": z_max}
	else:
		selection_region = {"min": lo, "max": hi, "z": z}


## 清空区域虚线投影。
func clear_selection_region() -> void:
	selection_region = {}


func has_selection_region() -> bool:
	return not selection_region.is_empty()


## 计算区域虚线边框折线（画布局部坐标；每边一条 PackedVector2Array，屏幕
## 空间覆盖层直接可用）。z>=0 = 固定高度平面四边形（一条闭合折线）；
## z<0 = 跟随地形周界（北/东/南/西各一条，逐格用 visual_top_level）；
## z_max>z（仅 z>=0）= 立体选择体六条线：z 底面闭合四边形 + z_max 顶面闭合
## 四边形 + 四角立边（各 2 点，底面角 i 连顶面角 i）。
## 纯几何无副作用，headless 契约直接调用（tests/editor_selection_contract.gd）。
func region_outline_polylines(min_cell: Vector2i, max_cell: Vector2i, z := -1, z_max := -1) -> Array:
	var out: Array = []
	if _renderer == null or _renderer.grid == null:
		return out
	var lo := Vector2i(mini(min_cell.x, max_cell.x), mini(min_cell.y, max_cell.y))
	var hi := Vector2i(maxi(min_cell.x, max_cell.x), maxi(min_cell.y, max_cell.y))
	var w := int(_renderer.grid.width)
	var h := int(_renderer.grid.height)
	if hi.x < 0 or hi.y < 0 or lo.x >= w or lo.y >= h:
		return out
	lo = Vector2i(clampi(lo.x, 0, w - 1), clampi(lo.y, 0, h - 1))
	hi = Vector2i(clampi(hi.x, 0, w - 1), clampi(hi.y, 0, h - 1))
	var offset := get_global_rect().position
	if z >= 0:
		# 固定高度平面：区域四角（世界坐标 ±half）一次性投影
		var camera := _board.camera if _board != null else null
		if camera == null:
			return out
		var half := IsoProjection.GRID_STEP * 0.5
		var quad_at := func(zz: int) -> PackedVector2Array:
			var nw := IsoProjection.world_to_screen(
				camera, IsoProjection.grid_to_world(Vector2i(lo.x, lo.y), zz) + Vector3(-half, 0, -half))
			var ne := IsoProjection.world_to_screen(
				camera, IsoProjection.grid_to_world(Vector2i(hi.x, lo.y), zz) + Vector3(half, 0, -half))
			var se := IsoProjection.world_to_screen(
				camera, IsoProjection.grid_to_world(Vector2i(hi.x, hi.y), zz) + Vector3(half, 0, half))
			var sw := IsoProjection.world_to_screen(
				camera, IsoProjection.grid_to_world(Vector2i(lo.x, hi.y), zz) + Vector3(-half, 0, half))
			return PackedVector2Array([nw - offset, ne - offset, se - offset, sw - offset, nw - offset])
		if z_max > z:
			# 立体选择体：底面 + 顶面 + 四角立边（角序 NW/NE/SE/SW 一一对应）
			var bottom: PackedVector2Array = quad_at.call(z)
			var top: PackedVector2Array = quad_at.call(z_max)
			out.append(bottom)
			out.append(top)
			for i in 4:
				out.append(PackedVector2Array([bottom[i], top[i]]))
			return out
		out.append(quad_at.call(z))
		return out
	# 跟随地形：周界格顶面外缘边（renderer.top_polygon_for 已含逐格 visual_top_level
	# 与相机投影；顶点序 [0]=NW [1]=NE [2]=SE [3]=SW，相邻格共享顶点天然连续）
	var north := PackedVector2Array()
	for x in range(lo.x, hi.x + 1):
		var poly: PackedVector2Array = _renderer.top_polygon_for(x, lo.y)
		north.append(poly[0] - offset)
		if x == hi.x:
			north.append(poly[1] - offset)
	out.append(north)
	var east := PackedVector2Array()
	for y in range(lo.y, hi.y + 1):
		var poly: PackedVector2Array = _renderer.top_polygon_for(hi.x, y)
		east.append(poly[1] - offset)
		if y == hi.y:
			east.append(poly[2] - offset)
	out.append(east)
	var south := PackedVector2Array()
	for x in range(hi.x, lo.x - 1, -1):
		var poly: PackedVector2Array = _renderer.top_polygon_for(x, hi.y)
		south.append(poly[2] - offset)
		if x == lo.x:
			south.append(poly[3] - offset)
	out.append(south)
	var west := PackedVector2Array()
	for y in range(hi.y, lo.y - 1, -1):
		var poly: PackedVector2Array = _renderer.top_polygon_for(lo.x, y)
		west.append(poly[3] - offset)
		if y == lo.y:
			west.append(poly[0] - offset)
	out.append(west)
	return out


## 模型 resize/重生成后收敛区域端点（与 set_selection_region 同一校验规则）。
func _clamp_selection_region() -> void:
	if selection_region.is_empty():
		return
	set_selection_region(selection_region["min"], selection_region["max"],
		int(selection_region.get("z", -1)), int(selection_region.get("z_max", -1)))


## 把当前 selection_region 折线刷进覆盖层标记（相机视图变化/模型变化时由
## _process 与 _rebuild/_refresh_markers_at 调用）。
func _update_region_marker() -> void:
	if _region_marker == null:
		return
	if selection_region.is_empty() or _renderer == null or _renderer.grid == null:
		_region_marker.visible = false
		return
	var lines := region_outline_polylines(
		selection_region["min"], selection_region["max"],
		int(selection_region.get("z", -1)), int(selection_region.get("z_max", -1)))
	_region_marker.polylines = lines
	_region_marker.visible = not lines.is_empty()


# ============================================================
# 粘贴预览（复制/剪切区域落点指示）
# ============================================================

## 设置粘贴预览框：闭区间 [min_cell, max_cell]（自动归一），valid 决定描边色
## （绿=合法落点 / 红=越界或非法）。设置范围提示时恢复正式地图。
func set_paste_preview(min_cell: Vector2i, max_cell: Vector2i, valid: bool) -> void:
	clear_block_ghost()
	var lo := Vector2i(mini(min_cell.x, max_cell.x), mini(min_cell.y, max_cell.y))
	var hi := Vector2i(maxi(min_cell.x, max_cell.x), maxi(min_cell.y, max_cell.y))
	var w := int(model.get("width", 0))
	var h := int(model.get("height", 0))
	if w <= 0 or h <= 0 or hi.x < 0 or hi.y < 0 or lo.x >= w or lo.y >= h:
		_paste_region = {}
		_update_paste_marker()
		return
	lo = Vector2i(clampi(lo.x, 0, w - 1), clampi(lo.y, 0, h - 1))
	hi = Vector2i(clampi(hi.x, 0, w - 1), clampi(hi.y, 0, h - 1))
	_paste_region = {"min": lo, "max": hi, "valid": valid}
	_update_paste_marker()


## 在独立副本执行正式 write；地形、素材、植物、单位与岸线均由正式渲染器生成。
func set_placement_preview(payload: Dictionary, origin: Vector2i) -> void:
	clear_building_preview()
	var candidate: Dictionary = model.duplicate(true)
	var result: Dictionary = RegionClipboardScript.write(candidate, payload, origin)
	if not bool(result.get("ok", false)):
		set_paste_preview(origin, origin + RegionClipboardScript.payload_size(payload) - Vector2i.ONE, false)
		return
	_placement_model = candidate
	var size: Vector2i = RegionClipboardScript.payload_size(payload)
	_placement_cell_count = size.x * size.y
	_paste_region = {}
	_update_paste_marker()
	_render_model(_placement_model)


func clear_placement_preview() -> void:
	var restore: bool = not _placement_model.is_empty()
	_placement_model = {}
	_placement_cell_count = 0
	if restore and _renderer != null and not model.is_empty():
		_render_model(model)


func clear_block_ghost() -> void:
	clear_placement_preview()


func placement_preview_cell_count() -> int:
	return _placement_cell_count


func ghost_cell_count() -> int:
	return placement_preview_cell_count()


## 清空粘贴范围提示并恢复正式地图。
func clear_paste_preview() -> void:
	_paste_region = {}
	clear_block_ghost()
	_update_paste_marker()


func has_paste_preview() -> bool:
	return not _paste_region.is_empty() or not _placement_model.is_empty()


func _update_paste_marker() -> void:
	if _paste_marker == null:
		return
	if _paste_region.is_empty() or _renderer == null or _renderer.grid == null:
		_paste_marker.visible = false
		return
	_paste_marker.line_color = PASTE_OK_COLOR if bool(_paste_region.get("valid", false)) else PASTE_BAD_COLOR
	var lines := region_outline_polylines(_paste_region["min"], _paste_region["max"])
	_paste_marker.polylines = lines
	_paste_marker.visible = not lines.is_empty()


# ============================================================
# 单位标记
# ============================================================

func _display_model() -> Dictionary:
	return model if _placement_model.is_empty() else _placement_model


func _rebuild_unit_markers() -> void:
	_clear_unit_markers()
	for u: Dictionary in _display_model().units:
		# 编辑器文档只存放置数据；适配战场显示所需字段，不生成战斗数值或修改文档。
		# 旧/自定义职业可能没有任何立绘；UnitSprite3D 要求 portrait 非空，显示层回退默认职业。
		var class_id := StringName(String(u.get("class", "swordsman")))
		if not CharacterSheet.sheet_exists(class_id) and not ProfessionVisual.portrait_exists(class_id):
			class_id = &"swordsman"
		var visual_unit: Dictionary = {
			classId = class_id,
			faction = StringName(String(u.get("faction", "player"))),
			level = int(u.get("level", 1)),
			position = Vector2i(int(u.x), int(u.y)),
			stats = {hp = 1}, hp = 1, hasActed = false, isDead = false,
		}
		var marker: UnitSprite3D = UnitSprite3D.new()
		_board.add_child(marker)
		marker.setup(visual_unit, _board, Callable(_renderer, "visual_top_level"))
		marker.set_persistent_bar_visible(false)
		_unit_markers.append(marker)


## 单格地形/高度变了可能影响顶面 -> 该格上的标记位置重算
func _refresh_markers_at(_cell: Vector2i) -> void:
	_rebuild_unit_markers()
	_update_hover_marker()
	_update_selection_marker()
	_update_region_marker()


func _clear_unit_markers() -> void:
	for marker in _unit_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_unit_markers.clear()


## 素材预览块（自绘）：纹理中心锚点 + render_offset（同 renderer _asset_block_for 规则）。
## 画布走 3D 管线（IsoBoard Camera3D），同 3D 路径：顶面中心不加 2D 偏移。
## 缺图占位（missing=true）淡红染色提示，与正式渲染层一致。
class _AssetPreviewMark:
	extends Node2D
	var visual: Dictionary = {}

	func _draw() -> void:
		var tex: Texture2D = visual.get("texture")
		if tex == null:
			return
		var offset: Vector2 = visual.get("render_offset", Vector2.ZERO)
		draw_texture(tex, offset - tex.get_size() * 0.5,
			Color(1.0, 0.55, 0.55) if bool(visual.get("missing", false)) else Color.WHITE)


## 区域虚线投影标记（自绘）：一组折线按 dash/gap 虚线描边，深色底衬 +1px
## 增强浅色地形上的对比度。折线坐标 = 画布局部（_world 恒等变换下直接可用）。
class _RegionOutlineMark:
	extends Node2D
	var polylines: Array = []:
		set(v):
			polylines = v
			queue_redraw()
	var line_color := Color(0.3, 0.98, 0.75, 0.95)
	var dash_len := 8.0
	var gap_len := 6.0
	var line_width := 2.0
	var underlay_color := Color(0.0, 0.0, 0.0, 0.45)

	func _draw() -> void:
		for pl in polylines:
			_draw_dashed(pl, underlay_color, Vector2(0, 1))
		for pl in polylines:
			_draw_dashed(pl, line_color, Vector2.ZERO)

	## 沿折线按固定 dash/gap 长度画虚线（跨线段连续计相位）。
	func _draw_dashed(pts: PackedVector2Array, color: Color, shift: Vector2) -> void:
		if pts.size() < 2:
			return
		var t := 0.0  # 当前 dash/gap 段已消耗长度
		var drawing := true
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var seg_len := a.distance_to(b)
			if seg_len <= 0.0001:
				continue
			var dir := (b - a) / seg_len
			var pos := 0.0
			while pos < seg_len:
				var budget := (dash_len if drawing else gap_len) - t
				var remain := seg_len - pos
				if budget <= remain:
					if drawing:
						draw_line(a + dir * pos + shift, a + dir * (pos + budget) + shift, color, line_width)
					pos += budget
					t = 0.0
					drawing = not drawing
				else:
					if drawing:
						draw_line(a + dir * pos + shift, b + shift, color, line_width)
					t += remain
					pos = seg_len
