## battle/range_overlay.gd — 战场范围/光标可视化层（从 phaserjs 的 Node3D 版重写为 Node2D）
##
## pixel_world 是 2D 项目，所有 mesh（.obj + CylinderMesh）改为 Line2D + 自绘 _draw。
## **保留原 API 签名**（setup/render_terrain_fallback/highlight_range/clear_range_highlight/
## create_cursor_particles/update_cursor_particles/show_path/clear_path），让 battle.gd 不用改。
##
## 视觉风格：扁平贴地菱形描边（不用 3D 高墙）。
##   - 光标框（金色）：上下浮动
##   - 移动范围（蓝/红）：静态贴地
##   - 攻击范围（紫）：脉冲透明度（2D 无法绕 Y 旋转，改用 alpha 脉冲代替）
##   - 路径箭头：_draw 画三角形

class_name RangeOverlay
extends Node2D

# ---- 注入的只读引用（setup 时由 battle.gd 设置）----
var board: IsoBoard                     # B2 模式：IsoBoard 实例（保留兼容）
var grid: GridSystem
var block_titles: Array = []
# B1 就地模式注入：marker 挂载点 + 坐标/sort 转换函数（B2 时为 null，走 board 路径）
var _parent: Node2D = null              # marker 挂哪（B1=main.gd；B2=null→用 board）
var _coord_fn := Callable()            # (x, y) -> Vector2 屏幕坐标（B1=main._grid_to_screen；B2=空→IsoCoords.to_screen）
var _sort_fn := Callable()             # (x, y) -> float sort_y（B1=main._column_sort_y；B2=空→固定 0）
var _level_fn := Callable()            # (x, y) -> int，高度层（B1 用于范围描边透明度）

# ---- 内部状态 ----
var _fallback_cells: Dictionary = {}   # { "x,y" -> _ColorBlock(Node2D) }
var _cursor_marker: Node2D = null
var _cursor_float_root: Node2D = null
var _cursor_float_tween: Tween = null
var _range_markers: Array = []         # Array[Node2D]
var _range_tweens: Array = []

# ---- 常量（颜色与原版一致）----
const _RANGE_COLOR_MOVABLE := Color(0.25, 0.55, 1.0)
const _RANGE_COLOR_BLOCKED := Color(1.0, 0.25, 0.25)
const _RANGE_COLOR_ATTACK  := Color(0.75, 0.35, 1.0)
const _CURSOR_COLOR := Color(1.0, 0.82, 0.2)

# 光标浮动（像素；原版世界单位 0.40，2D 下放大到 4px 让浮动可见）
const _CURSOR_FLOAT_HEIGHT := 4.0
const _CURSOR_FLOAT_PERIOD := 1.0
# 范围菱形相对格子的缩放（与原版 _QUAD_INSET_SCALE 一致）
const _QUAD_INSET_SCALE := 0.85


## B2 模式入口（保留原签名，向后兼容 battle.gd 现有调用）
func setup(p_board: IsoBoard, p_grid: GridSystem, p_block_titles: Array) -> void:
	board = p_board
	grid = p_grid
	block_titles = p_block_titles


## B1 就地模式入口：注入 marker 挂载点 + 坐标/sort 转换函数。
## p_parent：marker 挂哪（通常传 main.gd 自身，参与其 y_sort）
## p_coord_fn：(x: int, y: int) -> Vector2，cell 局部坐标 → 屏幕坐标
## p_sort_fn：(x: int, y: int) -> float，cell 局部坐标 → sort_y（参与父节点 y_sort）
func setup_world(p_parent: Node2D, p_grid: GridSystem, p_block_titles: Array,
		p_coord_fn: Callable, p_sort_fn: Callable, p_level_fn := Callable()) -> void:
	_parent = p_parent
	grid = p_grid
	block_titles = p_block_titles
	_coord_fn = p_coord_fn
	_sort_fn = p_sort_fn
	_level_fn = p_level_fn


## 当前模式：true=B1 就地（有 _parent），false=B2 切场景（有 board）
func is_world_mode() -> bool:
	return _parent != null


## 统一入口：marker 挂哪。B1=_parent，B2=board
func _attach(n: Node2D) -> void:
	if _parent != null:
		_parent.add_child(n)
	else:
		board.add_child(n)


## 统一入口：cell (x,y) → 屏幕坐标。B1 走 _coord_fn，B2 走 IsoCoords
func _cell_to_screen(x: int, y: int) -> Vector2:
	if _coord_fn.is_valid():
		return _coord_fn.call(x, y)
	return IsoCoords.to_screen(x, y)


## 统一入口：cell (x,y) → sort_y。B1 走 _sort_fn，B2 返回 0（B2 不用 y_sort）
func _cell_to_sort_y(x: int, y: int) -> float:
	if _sort_fn.is_valid():
		return _sort_fn.call(x, y)
	return 0.0


func _cell_level(x: int, y: int) -> int:
	if _level_fn.is_valid():
		return int(_level_fn.call(x, y))
	return 0


## 在 cell(x,y) 画实心菱形（替代 board.make_cell_quad，自带工厂）
func _make_color_block(x: int, y: int, color: Color) -> Node2D:
	var node := _ColorBlock.new()
	node.color = color
	var c := _cell_to_screen(x, y)
	var hw := IsoCoords.TILE_W * 0.5
	var hh := IsoCoords.TILE_H * 0.5
	node.corners = PackedVector2Array([
		c + Vector2(0, -hh),
		c + Vector2(hw, 0),
		c + Vector2(0, hh),
		c + Vector2(-hw, 0),
	])
	# B1 模式：直接 position=屏幕坐标 + z_index 保证在地形之上
	if is_world_mode():
		node.z_index = 5  # 地形之上、单位之下（单位 z_index=10）
	return node


## 在 cell(x,y) 画菱形描边（替代 board.make_cell_outline，自带工厂）
func _make_outline_block(x: int, y: int, color: Color, line_width: float = 2.0) -> Node2D:
	var node := _OutlineDraw.new()
	node.color = color
	node.width = line_width
	var c := _cell_to_screen(x, y)
	var hw := IsoCoords.TILE_W * 0.5 * _QUAD_INSET_SCALE
	var hh := IsoCoords.TILE_H * 0.5 * _QUAD_INSET_SCALE
	node.corners = [
		c + Vector2(0, -hh),
		c + Vector2(hw, 0),
		c + Vector2(0, hh),
		c + Vector2(-hw, 0),
	]
	if is_world_mode():
		node.z_index = 5
	return node


# ============================================================
# 渲染：chapter_1 无 blockTitles 时的退化（纯色菱形铺底）
# ============================================================
func render_terrain_fallback() -> void:
	var colors := {
		&"plain": Color(0.29, 0.48, 0.16),
		&"forest": Color(0.10, 0.35, 0.10),
		&"mountain": Color(0.35, 0.29, 0.23),
		&"water": Color(0.16, 0.35, 0.60),
		&"fort": Color(0.40, 0.40, 0.40),
		&"village": Color(0.53, 0.42, 0.23),
		&"wall": Color(0.13, 0.13, 0.13),
	}
	for y in range(grid.height):
		for x in range(grid.width):
			var tile: Dictionary = grid.tiles[y][x]
			var c: Color = colors.get(tile.type, colors[&"plain"])
			_add_cell_quad(x, y, c)


func _add_cell_quad(x: int, y: int, color: Color) -> void:
	var node := _make_color_block(x, y, color)
	_attach(node)
	_fallback_cells["%d,%d" % [x, y]] = node


# ============================================================
# 范围高亮
# ============================================================
func highlight_range(move_range: Dictionary, attack_tiles: Dictionary, selected_unit: Dictionary) -> void:
	_clear_range_markers()
	var sel_x := -1
	var sel_y := -1
	if not selected_unit.is_empty():
		sel_x = selected_unit.position.x
		sel_y = selected_unit.position.y
	var markers: Dictionary = {}
	# 攻击范围 → 紫
	for key in attack_tiles.keys():
		var ap := (key as String).split(",")
		var ax := ap[0].to_int()
		var ay := ap[1].to_int()
		if not _has_visible_cell(ax, ay):
			continue
		if ax == sel_x and ay == sel_y:
			continue
		markers[key] = { "color": _RANGE_COLOR_ATTACK, "x": ax, "y": ay, "attack": true }
	# 移动范围 → 蓝/红
	for key in move_range.keys():
		if markers.has(key):
			continue
		var mp := (key as String).split(",")
		var mx := mp[0].to_int()
		var my := mp[1].to_int()
		if not _has_visible_cell(mx, my):
			continue
		if mx == sel_x and my == sel_y:
			continue
		var col: Color = _RANGE_COLOR_MOVABLE if grid.unit_at(mx, my).is_empty() else _RANGE_COLOR_BLOCKED
		markers[key] = { "color": col, "x": mx, "y": my, "attack": false }
	# 逐格生成描边
	for key in markers.keys():
		var info: Dictionary = markers[key]
		var x: int = info["x"]
		var y: int = info["y"]
		var col: Color = info["color"]
		col.a *= _range_alpha_for_cell(x, y, selected_unit)
		var marker := _make_outline_block(x, y, col, 2.0)
		_attach(marker)
		_range_markers.append(marker)
		# 攻击格：alpha 脉冲（2D 替代原版的绕 Y 旋转）
		if bool(info["attack"]):
			var tw := create_tween()
			tw.set_loops(0)
			tw.tween_property(marker, "modulate:a", 0.45, 0.5)
			tw.tween_property(marker, "modulate:a", 1.0, 0.5)
			_range_tweens.append(tw)


func _has_visible_cell(x: int, y: int) -> bool:
	if block_titles.is_empty():
		return grid.in_bounds(x, y)
	if y < 0 or y >= block_titles.size():
		return false
	var row: Array = block_titles[y]
	return x >= 0 and x < row.size() and row[x] != null


func _range_alpha_for_cell(x: int, y: int, selected_unit: Dictionary) -> float:
	if not _level_fn.is_valid() or selected_unit.is_empty():
		return 1.0
	var level := _cell_level(x, y)
	var selected_pos: Vector2i = selected_unit.position
	var selected_level := _cell_level(selected_pos.x, selected_pos.y)
	var lower_penalty := clampf(float(selected_level - level) * 0.07, 0.0, 0.32)
	var occlusion_penalty := float(_higher_neighbor_count(x, y, level)) * 0.08
	return clampf(1.0 - lower_penalty - occlusion_penalty, 0.28, 1.0)


func _higher_neighbor_count(x: int, y: int, level: int) -> int:
	var count := 0
	for dir in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var nx: int = x + dir.x
		var ny: int = y + dir.y
		if grid.in_bounds(nx, ny) and _cell_level(nx, ny) > level:
			count += 1
	return count


func clear_range_highlight() -> void:
	_clear_range_markers()
	clear_path()


# ============================================================
# 光标框（金色浮动）
# ============================================================
func create_cursor_particles() -> void:
	var root := Node2D.new()
	root.name = "CursorMarker"
	root.visible = false
	_attach(root)

	_cursor_float_root = Node2D.new()
	_cursor_float_root.name = "FloatRoot"
	root.add_child(_cursor_float_root)

	var frame := _make_diamond_frame(_CURSOR_COLOR)
	_cursor_float_root.add_child(frame)

	_start_cursor_float(_cursor_float_root)
	_cursor_marker = root


func update_cursor_particles(x: int, y: int, can_show: bool) -> void:
	if _cursor_marker == null or not is_instance_valid(_cursor_marker):
		return
	if not can_show:
		_cursor_marker.visible = false
		return
	_cursor_marker.visible = true
	# 定位：B1 走双轨（position=sort_y, offset 补偿），B2 直接设 global_position
	var c := _cell_to_screen(x, y)
	if is_world_mode():
		_cursor_marker.position = c
		_cursor_marker.z_index = 6
	else:
		_cursor_marker.global_position = c


# ---- 路径指示 ----
var _path_marker: Node2D = null


func show_path(path: Array, color: Color) -> void:
	clear_path()
	if path.size() < 2:
		return
	if _path_marker == null or not is_instance_valid(_path_marker):
		_path_marker = _PathDrawer.new()
		_path_marker.name = "PathMarker"
		_attach(_path_marker)
	_path_marker.color = color
	_path_marker.coord_fn = _coord_fn
	# 收集每段的方向，画箭头
	var segs: Array = []
	var last_dir := Vector2i(1, 0)
	for i in range(path.size() - 1):
		var cur = path[i]
		var nxt = path[i + 1]
		var dir := Vector2i(nxt.x - cur.x, nxt.y - cur.y)
		last_dir = dir
		segs.append({ cell = cur, dir = dir })
	# 终点格沿用上一段方向
	var last = path[path.size() - 1]
	segs.append({ cell = last, dir = last_dir })
	_path_marker.segments = segs
	_path_marker.queue_redraw()


func clear_path() -> void:
	if _path_marker != null and is_instance_valid(_path_marker):
		_path_marker.segments = []
		_path_marker.queue_redraw()


# ============================================================
# 内部：标记生成
# ============================================================
## 金色菱形描边（光标用）。
func _make_diamond_frame(color: Color) -> Node2D:
	var node := _OutlineDraw.new()
	node.color = color
	node.width = 2.0
	# 整格大小（不 inset，让光标比范围框大一点更醒目）
	var hw := IsoCoords.TILE_W * 0.5
	var hh := IsoCoords.TILE_H * 0.5
	node.corners = [
		Vector2(0, -hh),
		Vector2(hw, 0),
		Vector2(0, hh),
		Vector2(-hw, 0),
	]
	return node


## 光标浮动：sin 驱动 _float_root.position.y。
func _start_cursor_float(root: Node2D) -> void:
	if _cursor_float_tween != null and _cursor_float_tween.is_valid():
		_cursor_float_tween.kill()
	var base_y := 0.0
	_cursor_float_tween = create_tween()
	_cursor_float_tween.set_loops(0)
	_cursor_float_tween.tween_method(func(phi: float) -> void:
		if is_instance_valid(root):
			root.position.y = base_y + (sin(phi) * 0.5 + 0.5) * _CURSOR_FLOAT_HEIGHT,
		0.0, TAU, _CURSOR_FLOAT_PERIOD)


func _clear_range_markers() -> void:
	for tw in _range_tweens:
		if tw != null and tw is Tween and tw.is_valid():
			tw.kill()
	_range_tweens.clear()
	for node in _range_markers:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_range_markers.clear()


# ============================================================
# 辅助：取 cell 顶面 Y（2D 下无高度概念，返回 fallback）
# ============================================================
func _cell_top_y(_cell_key: String, fallback_y: float) -> float:
	# 2D 下 block 顶面 Y 已无意义；返回 fallback。
	return fallback_y


# ============================================================
# 自绘节点类型
# ============================================================
## 实心菱形色块（terrain fallback / 范围铺底用）。
class _ColorBlock:
	extends Node2D
	var color: Color = Color.WHITE
	var corners: PackedVector2Array = PackedVector2Array()
	func _draw() -> void:
		if corners.size() < 3:
			return
		draw_colored_polygon(corners, color)


## 描边菱形（_draw 画 4 条线）。
class _OutlineDraw:
	extends Node2D
	var color: Color = Color.WHITE
	var width: float = 2.0
	var corners: Array = []
	func _draw() -> void:
		if corners.size() < 3:
			return
		for i in range(corners.size()):
			var a: Vector2 = corners[i]
			var b: Vector2 = corners[(i + 1) % corners.size()]
			draw_line(a, b, color, width)


## 路径箭头容器（_draw 按每段方向画三角形）。
class _PathDrawer:
	extends Node2D
	var color: Color = Color.WHITE
	var segments: Array = []   # [{ cell: Vector2i, dir: Vector2i }, ...]
	var coord_fn := Callable()   # B1 注入的坐标转换；(x,y)->Vector2。空时用 IsoCoords
	func _draw() -> void:
		for seg in segments:
			var cell: Vector2i = seg.cell
			var dir: Vector2i = seg.dir
			var center := _to_screen(cell.x, cell.y)
			_draw_arrow(center, dir)
	# 坐标转换（B1 用注入的 coord_fn，B2 用 IsoCoords）
	func _to_screen(x: int, y: int) -> Vector2:
		if coord_fn.is_valid():
			return coord_fn.call(x, y)
		return IsoCoords.to_screen(x, y)
	# 画一个朝 dir 方向的小三角箭头
	func _draw_arrow(center: Vector2, dir: Vector2i) -> void:
		# cell 屏幕方向：dx>0=east(右下), dx<0=west(左上), dy>0=south(左下), dy<0=north(右上)
		# 等距投影下，cell 方向 (dx,dy) → 屏幕方向向量
		var s := _to_screen(dir.x, dir.y) - _to_screen(0, 0)
		if s.length() < 0.001:
			return
		s = s.normalized()
		# 箭头尺寸
		var arrow_len := 6.0
		var half := 4.0
		var tip := center + s * arrow_len
		var back := center - s * arrow_len * 0.5
		# 垂直 s 的方向
		var perp := Vector2(-s.y, s.x)
		var left := back + perp * half
		var right := back - perp * half
		draw_colored_polygon(PackedVector2Array([tip, left, right]), color)
