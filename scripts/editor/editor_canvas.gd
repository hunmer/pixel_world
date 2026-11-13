## editor/editor_canvas.gd — 编辑器画布（等距方块版，IsoBoard 3D 相机）
##
## 复用 BattlefieldRenderer + IsoBoard（与 B2 战棋同款 IsometricCamera3D）：
## 视角旋转（Q/E/Z/X/R）、滚轮/双指捏合缩放、右键拖拽或空格+左键平移。
## 左键按下/拖动发出 cell 信号，由 map_editor.gd 按工具解释。
## 地形走 3D 等距管线（渲染器检测到 Camera3D 自动切换）；悬停/选中/单位
## 标记为屏幕空间 2D 节点，挂 _world（恒等变换）下并随相机逐帧对齐。
## 已放置单位显示职业头像+阵营色环+等级徽标（缺图回退阵营色圆点+职业字，原视觉）。

class_name EditorCanvas
extends Control

const BattlefieldRendererScript = preload("res://scripts/iso/battlefield_renderer.gd")
const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const ProfessionVisualScript = preload("res://scripts/iso/profession_visual.gd")
const IsoBoardScript = preload("res://scripts/iso/iso_board.gd")

signal cell_pressed(cell: Vector2i)
signal cell_dragged(cell: Vector2i)
signal hover_changed(cell: Vector2i)

const PLAYER_COLOR := Color(0.376, 0.647, 0.980)
const ENEMY_COLOR := Color(0.973, 0.443, 0.443)
const HOVER_COLOR := Color(1.0, 0.85, 0.3, 0.55)
const SELECTION_COLOR := Color(0.25, 0.95, 1.0, 0.62)
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
var _world: Node2D = null
var _renderer: Node2D = null
var _board: IsoBoard = null
var _hover_marker: Polygon2D = null
var _selection_marker: Polygon2D = null
var _unit_markers: Array[Node2D] = []
var _dragging := false
var _panning := false
## 视图状态缓存（相机 yaw/elevation/zoom/focus + 画布全局矩形）：
## 任一变化时重算悬停/选中多边形与单位标记位置（相机旋转是平滑动画）。
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
	# 容器化布局：尺寸由父容器分配（首帧 0->实际值），变化时重居中地图
	resized.connect(_on_canvas_resized)


func _rebuild() -> void:
	if _world == null:
		return  # _ready 未跑（未进树）
	_clear_unit_markers()
	if model.is_empty():
		_renderer.setup(null)
		_hover_marker.visible = false
		_selection_marker.visible = false
		return
	_renderer.set_custom_props(model.get("props", []))  # 植物层（setup 前注入）
	_renderer.set_block_layout(model.get("block_layout", {}))
	_renderer.setup(_build_grid())
	_rebuild_unit_markers()
	_update_hover_marker()
	_update_selection_marker()
	_center_map()


## 模型 rows（图例字符画）-> GridSystem（全名地形矩阵）
func _build_grid() -> GridSystem:
	var rows: Array = model.rows
	var map: Array = []
	for y in range(model.height):
		var row: String = rows[y]
		var line: Array = []
		for x in range(model.width):
			line.append(BattlefieldDocScript.glyph_to_terrain(row.substr(x, 1)))
		map.append(line)
	return GridSystem.new(model.width, model.height, map)


## 单格重建（画笔/填充/植物/橡皮后由 map_editor.gd 调 _refresh_cell）
func _refresh_cell(cell: Vector2i) -> void:
	if _renderer == null or _renderer.grid == null:
		return
	if cell.x < 0 or cell.y < 0 or cell.x >= model.width or cell.y >= model.height:
		return
	# rows 是权威源：先把该格地形同步进渲染器网格，再重建柱（否则画笔无视觉效果）
	var terrain: StringName = BattlefieldDocScript.glyph_to_terrain((model.rows[cell.y] as String).substr(cell.x, 1))
	(_renderer.grid.tiles[cell.y][cell.x] as Dictionary)["type"] = terrain
	# 植物层同步：该格 props 覆盖表条目（无则清空覆盖，恢复地形默认装饰）
	_renderer.set_cell_prop(cell, BattlefieldDocScript.prop_at(model, cell))
	# renderer 持有布局深拷贝；每次单格刷新都必须同步，否则 z 改了模型却不改画面。
	_renderer.set_block_layout(model.get("block_layout", {}))
	_renderer.refresh_cell(cell.x, cell.y)
	_refresh_markers_at(cell)


func _center_map() -> void:
	if _board == null or _board.camera == null or model.is_empty():
		return
	_board.center_on_map(int(model.width), int(model.height))


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
					cell_pressed.emit(c)
					accept_event()
			else:
				_dragging = false
				_panning = false
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


func reset_view() -> void:
	if _board != null and _board.camera != null:
		_board.camera.reset_rotation()


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
	return _renderer.pick_cell(_local_to_screen(local_pos), size)


## 相机旋转/缩放是平滑动画：逐帧检查视图状态，变化时重算覆盖层。
func _process(_delta: float) -> void:
	if _board == null or _board.camera == null or _renderer == null:
		return
	var cam := _board.camera
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
		_layout_unit_markers()


func _update_hover_marker() -> void:
	if _hover_marker == null:
		return
	if hover_cell.x < 0 or _renderer.grid == null:
		_hover_marker.visible = false
		return
	_hover_marker.polygon = _poly_to_local(_renderer.top_polygon_for(hover_cell.x, hover_cell.y))
	_hover_marker.visible = true


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
# 单位标记
# ============================================================

func _rebuild_unit_markers() -> void:
	_clear_unit_markers()
	for u in model.units:
		var marker := _UnitMark.new()
		var cid := StringName(String(u.get("class", "swordsman")))
		if ProfessionVisualScript.portrait_exists(cid):
			marker.portrait = load(ProfessionVisualScript.portrait_path(cid))
		marker.faction_color = ENEMY_COLOR if String(u.get("faction", "player")) == "enemy" else PLAYER_COLOR
		marker.tag = "%s%d" % [String(u.get("tag", "?")), int(u.get("level", 1))]
		marker.level = int(u.get("level", 1))
		marker.z_index = 15
		_world.add_child(marker)
		_unit_markers.append(marker)
	_layout_unit_markers()


## 单位标记对齐当前相机投影（相机旋转/缩放/平移后由 _process 调用）。
func _layout_unit_markers() -> void:
	if _renderer == null or _renderer.grid == null:
		return
	for i in mini(_unit_markers.size(), model.units.size()):
		var u: Dictionary = model.units[i]
		_unit_markers[i].position = _screen_to_local(
			_renderer.top_center_for(int(u.x), int(u.y)))


## 单格地形/高度变了可能影响顶面 -> 该格上的标记位置重算
func _refresh_markers_at(_cell: Vector2i) -> void:
	_rebuild_unit_markers()
	_update_hover_marker()
	_update_selection_marker()


func _clear_unit_markers() -> void:
	for marker in _unit_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_unit_markers.clear()


## 阵营色环 + 职业圆形头像 + 等级徽标（自绘，随 world 缩放）；缺图回退阵营色圆点+职业字
class _UnitMark:
	extends Node2D
	const R := 14.0  # 头像半径（缺图回退圆点维持原 r=9 视觉）
	var faction_color: Color = Color.WHITE
	var tag := "?"
	var level := 1
	var portrait: Texture2D = null

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		if portrait != null:
			# 圆形头像：draw_polygon UV 映射把方形立绘贴进圆
			var seg := 40
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			var cols := PackedColorArray()
			for i in range(seg):
				var a := TAU * float(i) / float(seg)
				pts.append(Vector2(cos(a), sin(a)) * R)
				uvs.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
				cols.append(Color.WHITE)
			draw_polygon(pts, cols, uvs, portrait)
			draw_arc(Vector2.ZERO, R + 1.5, 0, TAU, 40, Color(faction_color, 0.95), 3.0)
			draw_arc(Vector2.ZERO, R + 3.0, 0, TAU, 40, Color(0, 0, 0, 0.5), 1.5)
			var lv := "Lv%d" % level
			draw_string(font, Vector2(-R + 1, R + 12), lv,
				HORIZONTAL_ALIGNMENT_CENTER, R * 2.0, 9, Color(0, 0, 0, 0.8))
			draw_string(font, Vector2(-R, R + 11), lv,
				HORIZONTAL_ALIGNMENT_CENTER, R * 2.0, 9, Color(1, 1, 1, 0.95))
		else:
			# 缺图回退：阵营色圆 + 职业首字/等级文本（原视觉不变）
			var r := 9.0
			draw_circle(Vector2.ZERO, r, Color(faction_color, 0.85))
			draw_arc(Vector2.ZERO, r, 0, TAU, 24, Color(0, 0, 0, 0.6), 2.0)
			draw_string(font, Vector2(-7, 4), tag,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.95))
