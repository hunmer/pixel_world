## editor/editor_canvas.gd — 编辑器画布（等距方块版）
##
## 复用 BattlefieldRenderer（ColumnBatch 等距方块柱 + 世界同款贴图）渲染地形，
## 与战斗内观感完全一致。左键按下/拖动发出 cell 信号，由 map_editor.gd 按工具解释。
## 右键拖拽或按住空格+左键拖拽平移、滚轮缩放（无相机，直接变换 world 节点）。

class_name EditorCanvas
extends Control

const BattlefieldRendererScript = preload("res://scripts/iso/battlefield_renderer.gd")
const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")

signal cell_pressed(cell: Vector2i)
signal cell_dragged(cell: Vector2i)

const PLAYER_COLOR := Color(0.376, 0.647, 0.980)
const ENEMY_COLOR := Color(0.973, 0.443, 0.443)
const HOVER_COLOR := Color(1.0, 0.85, 0.3, 0.55)
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0
const ZOOM_STEP := 1.15
const DEFAULT_ZOOM := 1.6

## 编辑器模型引用（BattlefieldDoc 模型 dict；由 map_editor.gd 维护并触发重建）
var model: Dictionary = {}:
	set(v):
		model = v
		_rebuild()

var hover_cell := Vector2i(-1, -1)
var _world: Node2D = null
var _renderer: Node2D = null
var _hover_marker: Polygon2D = null
var _unit_markers: Array[Node2D] = []
var _dragging := false
var _panning := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_world = Node2D.new()
	_world.name = "EditorWorld"
	add_child(_world)
	_renderer = BattlefieldRendererScript.new()
	_world.add_child(_renderer)
	_hover_marker = Polygon2D.new()
	_hover_marker.z_index = 20
	_hover_marker.color = HOVER_COLOR
	_hover_marker.visible = false
	_world.add_child(_hover_marker)


func _rebuild() -> void:
	if _world == null:
		return  # _ready 未跑（未进树）
	_clear_unit_markers()
	if model.is_empty():
		_renderer.setup(null)
		_hover_marker.visible = false
		return
	_renderer.setup(_build_grid())
	_rebuild_unit_markers()
	_center_map()


## 模型 rows（图例字符画）→ GridSystem（全名地形矩阵）
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


## 单格重建（画笔/填充/橡皮后由 map_editor.gd 调 _refresh_cell）
func _refresh_cell(cell: Vector2i) -> void:
	if _renderer == null or _renderer.grid == null:
		return
	_renderer.refresh_cell(cell.x, cell.y)
	_refresh_markers_at(cell)


func _center_map() -> void:
	var zoom := _world.scale.x if _world.scale != Vector2.ZERO else DEFAULT_ZOOM
	_world.scale = Vector2(zoom, zoom)
	_world.position = size * 0.5 - _renderer.map_center() * zoom


# ============================================================
# 输入：左键=工具操作，右键拖拽或空格+左键拖拽=平移，滚轮=缩放
# ============================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			_world.position += mm.relative
			accept_event()
			return
		var c := _pick(mm.position)
		if c != hover_cell:
			hover_cell = c
			_update_hover_marker()
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
			_zoom_at(mb.position, ZOOM_STEP)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / ZOOM_STEP)
			accept_event()


func _zoom_at(cursor: Vector2, factor: float) -> void:
	var old_zoom := _world.scale.x
	var new_zoom := clampf(old_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_zoom, old_zoom):
		return
	_world.position = cursor - (cursor - _world.position) * (new_zoom / old_zoom)
	_world.scale = Vector2(new_zoom, new_zoom)


## 画布局部坐标 → cell（多高度感知拾取）
func _pick(local_pos: Vector2) -> Vector2i:
	if _renderer == null or _renderer.grid == null:
		return Vector2i(-1, -1)
	var global_pos: Vector2 = get_global_transform() * local_pos
	return _renderer.pick_world(global_pos)


func _update_hover_marker() -> void:
	if hover_cell.x < 0:
		_hover_marker.visible = false
		return
	var c: Vector2 = _renderer.coord_for(hover_cell.x, hover_cell.y)
	var hw := 16.0
	var hh := 8.0
	_hover_marker.polygon = PackedVector2Array([
		c + Vector2(0, -hh),
		c + Vector2(hw, 0),
		c + Vector2(0, hh),
		c + Vector2(-hw, 0),
	])
	_hover_marker.visible = true


# ============================================================
# 单位标记
# ============================================================

func _rebuild_unit_markers() -> void:
	_clear_unit_markers()
	for u in model.units:
		var marker := _UnitMark.new()
		marker.faction_color = ENEMY_COLOR if String(u.get("faction", "player")) == "enemy" else PLAYER_COLOR
		marker.tag = "%s%d" % [String(u.get("tag", "?")), int(u.get("level", 1))]
		marker.position = _renderer.coord_for(int(u.x), int(u.y))
		marker.z_index = 15
		_world.add_child(marker)
		_unit_markers.append(marker)


## 单格地形变了可能影响站立层 → 该格上的标记位置重算
func _refresh_markers_at(_cell: Vector2i) -> void:
	_rebuild_unit_markers()


func _clear_unit_markers() -> void:
	for marker in _unit_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_unit_markers.clear()


## 阵营色圆 + 职业首字/等级文本（自绘，随 world 缩放）
class _UnitMark:
	extends Node2D
	var faction_color: Color = Color.WHITE
	var tag := "?"
	func _draw() -> void:
		var r := 9.0
		draw_circle(Vector2.ZERO, r, Color(faction_color, 0.85))
		draw_arc(Vector2.ZERO, r, 0, TAU, 24, Color(0, 0, 0, 0.6), 2.0)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-7, 4), tag,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.95))
