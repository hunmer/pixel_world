## editor/editor_canvas.gd — 编辑器画布：自绘地形格 + 单位标记 + 悬停高亮
##
## 单 Control 节点（_draw 自绘），左键按下/拖动发出 cell 信号，由 map_editor.gd 按工具解释。
## 地形配色复用战棋 range_overlay.render_terrain_fallback 的色板，与战斗内观感一致。

class_name EditorCanvas
extends Control

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")

signal cell_pressed(cell: Vector2i)
signal cell_dragged(cell: Vector2i)

const CELL := 30.0
const LINE := Color(0, 0, 0, 0.25)
const HOVER := Color(1.0, 0.85, 0.3, 0.45)
const PLAYER_COLOR := Color(0.376, 0.647, 0.980)
const ENEMY_COLOR := Color(0.973, 0.443, 0.443)

const TERRAIN_COLORS := {
	&"plain": Color(0.29, 0.48, 0.16),
	&"forest": Color(0.10, 0.35, 0.10),
	&"mountain": Color(0.35, 0.29, 0.23),
	&"water": Color(0.16, 0.35, 0.60),
	&"fort": Color(0.40, 0.40, 0.40),
	&"village": Color(0.53, 0.42, 0.23),
	&"wall": Color(0.13, 0.13, 0.13),
}

## 编辑器模型引用（BattlefieldDoc 模型 dict；由 map_editor.gd 维护并触发 redraw）
var model: Dictionary = {}:
	set(v):
		model = v
		_recompute_size()
		queue_redraw()

var hover_cell := Vector2i(-1, -1)
var _dragging := false


func _ready() -> void:
	custom_minimum_size = Vector2(320, 240)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_recompute_size()


func _recompute_size() -> void:
	if model.is_empty():
		return
	custom_minimum_size = Vector2(model.width * CELL, model.height * CELL)
	size = custom_minimum_size


func _gui_input(event: InputEvent) -> void:
	if model.is_empty():
		return
	if event is InputEventMouseMotion:
		var c := _cell_at(event.position)
		if c != hover_cell:
			hover_cell = c
			queue_redraw()
		if _dragging and c.x >= 0:
			cell_dragged.emit(c)
			accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var c := _cell_at(event.position)
		if event.pressed:
			_dragging = true
			if c.x >= 0:
				cell_pressed.emit(c)
			accept_event()
		else:
			_dragging = false


func _cell_at(pos: Vector2) -> Vector2i:
	var c := Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))
	if model.is_empty() or c.x < 0 or c.y < 0 or c.x >= model.width or c.y >= model.height:
		return Vector2i(-1, -1)
	return c


func _draw() -> void:
	if model.is_empty():
		return
	var rows: Array = model.rows
	for y in range(model.height):
		var row: String = rows[y]
		for x in range(model.width):
			var t := BattlefieldDocScript.glyph_to_terrain(row.substr(x, 1))
			draw_rect(Rect2(x * CELL, y * CELL, CELL, CELL), TERRAIN_COLORS.get(t, TERRAIN_COLORS[&"plain"]))
			draw_rect(Rect2(x * CELL, y * CELL, CELL, 1), LINE)
			draw_rect(Rect2(x * CELL, y * CELL, 1, CELL), LINE)
	# 网格外框
	draw_rect(Rect2(0, 0, model.width * CELL, model.height * CELL), LINE, false, 1.5)
	# 单位标记：阵营色圆 + 职业+等级 文本
	var font := ThemeDB.fallback_font
	for u in model.units:
		var cx := (int(u.x) + 0.5) * CELL
		var cy := (int(u.y) + 0.5) * CELL
		var color := ENEMY_COLOR if String(u.get("faction", "player")) == "enemy" else PLAYER_COLOR
		draw_circle(Vector2(cx, cy), CELL * 0.36, Color(color, 0.85))
		draw_circle(Vector2(cx, cy), CELL * 0.36, Color(0, 0, 0, 0.6), false, 2.0)
		var tag := "%s%d" % [String(u.get("tag", "?")), int(u.get("level", 1))]
		draw_string(font, Vector2(cx - CELL * 0.30, cy + CELL * 0.14), tag,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.95))
	# 悬停高亮
	if hover_cell.x >= 0:
		draw_rect(Rect2(hover_cell.x * CELL, hover_cell.y * CELL, CELL, CELL), HOVER)
