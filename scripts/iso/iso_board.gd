## iso/iso_board.gd — 等距棋盘 2D 控制器（从 phaserjs 的 Node3D 版重写）
##
## pixel_world 是 Node2D + Camera2D 项目。本类把原 Node3D + Sprite3D + Camera3D 的棋盘
## 重写为 Node2D + Camera2D + Line2D/Polygon2D，**保留原公开 API 签名**，让 battle.gd /
## battle_ui.gd / turn_director.gd / range_overlay.gd 的状态机和交互逻辑几乎不用改。
##
## 职责（与原版一致）：
##   - 渲染每个 cell 的 block（2D 下用色块菱形代替 3D sprite；战棋走 terrain fallback）
##   - pan（相机平移）+ zoom（滚轮调 Camera2D.zoom）
##   - 屏幕坐标 → cell 拾取（2D 反投影）
##   - redraw_cells(cells) / clear()
##   - make_cell_quad / make_cell_outline / set_cell_tint / clear_cell_tint
##
## 节点结构：
##   board: Node2D
##     ├ camera (Camera2D)
##     ├ blocks_root (Node2D) — 持有所有 block 视图（Node2D，含 _draw 画菱形）
##     └ grid_root (Node2D)   — 网格线 + 黄色边界

class_name IsoBoard
extends Node2D

## 暴露给外部（原 API：camera）。类型从 Camera3D 改为 Camera2D。
## battle_ui / battle.gd 里 board.camera.unproject_position(...) 在 2D 下等价于
## 直接用 cell_to_screen 结果，所以本字段实际不再被读取——但保留以避免编译错误。
var camera: Camera2D
var _blocks_root: Node2D
var _grid_root: Node2D   # 网格线 + 黄色边界（空地图也可见）

## { cellKey("x,y") -> Node2D }；与原版 _block_pool 同义。
## range_overlay._cell_top_y 会读它（虽然 2D 下顶面 Y 已无意义，返回 fallback）。
var _block_pool: Dictionary = {}
var _current_width: int = 0
var _current_height: int = 0

## 兼容旧 API 常量（原版用于 Sprite3D pixel_size 计算；2D 不需要，但 range_overlay 引用了
## SURFACE_OVERLAY_Y，这里保留并视作 0）。
const SURFACE_OVERLAY_Y := 0.0
## 兼容旧 API 常量（原 PIXEL_SIZE 用于 3D sprite 缩放）。UnitSprite 2D 版会读取它，
## 保留为 1.0 让旧 unit_sprite.gd 的 _build_visual 中 pixel_size 字段不报错（虽然不再使用）。
const PIXEL_SIZE := 1.0

## 缩放档位（与 main.gd 一致，像素安全）。
const ZOOM_LEVELS: Array[float] = [0.5, 1.0, 2.0, 3.0, 4.0]
const DEFAULT_ZOOM_INDEX := 2   # 默认 2.0x
var _zoom_index: int = DEFAULT_ZOOM_INDEX


func _ready() -> void:
	_blocks_root = Node2D.new()
	_blocks_root.name = "BlocksRoot"
	add_child(_blocks_root)
	_grid_root = Node2D.new()
	_grid_root.name = "GridRoot"
	add_child(_grid_root)
	_setup_camera()


func _setup_camera() -> void:
	if camera == null:
		camera = Camera2D.new()
		camera.name = "IsoCamera"
		camera.position_smoothing_enabled = false
		camera.rotation_smoothing_enabled = false
		add_child(camera)
		camera.make_current()
	_apply_zoom()


func _apply_zoom() -> void:
	var v := ZOOM_LEVELS[_zoom_index]
	camera.zoom = Vector2(v, v)


# ============================================================
# 相机控制
# ============================================================

## 居中相机到地图中心（cell 坐标）。原 API：center_on_map(width, height)。
func center_on_map(width: int, height: int) -> void:
	var cx := int(width / 2.0)
	var cy := int(height / 2.0)
	camera.position = IsoCoords.to_screen(cx, cy)


## pan：移动相机（屏幕方向像素 → 世界方向平移）。原 API：pan(dx_screen, dy_screen)。
## 2D 下相机 zoom 把屏幕像素换算成世界像素。
func pan(dx_screen: float, dy_screen: float) -> void:
	var z := camera.zoom.x
	# 拖拽地图：屏幕移动反方向施加到相机（与原 Node3D 版语义一致）
	camera.position -= Vector2(dx_screen, dy_screen) / z


## zoom：调 Camera2D.zoom 档位。原 API：zoom_by(factor, anchor_screen, viewport_size)。
## factor<1 放大（zoom 档位+），>1 缩小（zoom 档位-）；以 anchor 为锚保持该世界点不动。
func zoom_by(factor: float, anchor_screen: Vector2, _viewport_size: Vector2) -> void:
	# 简单实现：按 factor 方向调档位（步进 1）
	var step := -1 if factor < 1.0 else 1
	var new_idx := clampi(_zoom_index + step, 0, ZOOM_LEVELS.size() - 1)
	if new_idx == _zoom_index:
		return
	# 锚点保持：先记录 anchor 对应的世界点，改 zoom 后再平移相机让该点屏幕位置不变
	var anchor_world := _screen_to_world(anchor_screen)
	_zoom_index = new_idx
	_apply_zoom()
	var new_screen := _world_to_screen(anchor_world)
	# 相机位置补偿 = (原屏幕 - 新屏幕) / zoom
	camera.position += (anchor_screen - new_screen) / camera.zoom.x


# ============================================================
# 屏幕坐标 ↔ 世界坐标 ↔ cell
# ============================================================

## 屏幕坐标（viewport） → 世界坐标（Node2D 局部）。
func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var canvas := get_viewport().get_canvas_transform()
	return canvas.affine_inverse() * screen_pos


## 世界坐标 → 屏幕坐标（viewport）。
func _world_to_screen(world_pos: Vector2) -> Vector2:
	var canvas := get_viewport().get_canvas_transform()
	return canvas * world_pos


## 屏幕坐标 → cell（拾取）。原 API：pick_cell(screen_pos, viewport_size)。
func pick_cell(screen_pos: Vector2, _viewport_size: Vector2) -> Vector2i:
	var world := _screen_to_world(screen_pos)
	return IsoCoords.to_cell(world)


## cell → 屏幕像素（公开，供 battle_ui / battle.gd 飘字定位用）。
func cell_to_screen(x: int, y: int) -> Vector2:
	return IsoCoords.to_screen(x, y)


# ============================================================
# Block 渲染（战棋默认走 terrain fallback，不依赖 BlockAtlas/blocks.json）
# ============================================================

## 用 cells 矩阵（block title 或 null）重绘整张地图。原 API：redraw_cells(cells)。
## 注意：pixel_world 不迁移 blocks.json，所以 BlockAtlas.TITLE_TO_TEX 总是空——
## 战棋路径走 block_titles.is_empty() 分支（range_overlay.render_terrain_fallback），
## 不会真正调用本方法渲染方块。本实现保留以兼容 API。
func redraw_cells(cells: Array) -> void:
	clear()
	if cells.is_empty():
		return
	var h := cells.size()
	var w := (cells[0] as Array).size()
	var dimensions_changed := w != _current_width or h != _current_height
	_current_width = w
	_current_height = h
	# 2D 版：没有方块 PNG，只画网格线（让玩家看到棋盘轮廓）
	# 实际地形着色由 range_overlay.render_terrain_fallback 负责
	draw_grid(w, h)
	if dimensions_changed:
		center_on_map(w, h)


## 画格子线（细灰菱形）+ 黄色边界。原 API：draw_grid(map_w, map_h)。
func draw_grid(map_w: int, map_h: int) -> void:
	for c in _grid_root.get_children():
		c.queue_free()
	# 细灰菱形网格线（每个 cell 一圈描边）
	for y in range(map_h):
		for x in range(map_w):
			_add_grid_diamond(x, y, Color(0.278, 0.333, 0.412, 0.5), 1.0)
	# 黄色边界（地图整体外框菱形 4 个外角）：
	# 左上角 cell 的 top → 右上角 cell 的 right → 右下角 cell 的 bottom → 左下角 cell 的 left
	var tl := _diamond_corners_screen(0, 0)
	var tr_corners := _diamond_corners_screen(map_w - 1, 0)
	var br := _diamond_corners_screen(map_w - 1, map_h - 1)
	var bl := _diamond_corners_screen(0, map_h - 1)
	var top: Vector2 = tl[0]       # [top, right, bottom, left]
	var right: Vector2 = tr_corners[1]
	var bottom: Vector2 = br[2]
	var left: Vector2 = bl[3]
	var bc := Color(0.984, 0.749, 0.141, 0.9)
	_add_grid_line(top, right, bc, 2.0)
	_add_grid_line(right, bottom, bc, 2.0)
	_add_grid_line(bottom, left, bc, 2.0)
	_add_grid_line(left, top, bc, 2.0)


## cell(x,y) 菱形四角的屏幕坐标（顺时针：top/right/bottom/left）。
## 顶面菱形宽 TILE_W、高 TILE_H，中心点对齐 cell 屏幕坐标。
func _diamond_corners_screen(x: int, y: int) -> Array:
	var c := IsoCoords.to_screen(x, y)
	var hw := TILE_W * 0.5
	var hh := TILE_H * 0.5
	return [
		c + Vector2(0, -hh),    # top
		c + Vector2(hw, 0),     # right
		c + Vector2(0, hh),     # bottom
		c + Vector2(-hw, 0),    # left
	]


const TILE_W := IsoCoords.TILE_W
const TILE_H := IsoCoords.TILE_H


## 画一个 cell 的菱形描边（4 条 Line2D）。
func _add_grid_diamond(x: int, y: int, color: Color, width: float) -> void:
	var pts := _diamond_corners_screen(x, y)
	for i in range(4):
		_add_grid_line(pts[i], pts[(i + 1) % 4], color, width)


## 用 Line2D 画一条线段。
func _add_grid_line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	if (b - a).length() < 0.5:
		return
	var line := Line2D.new()
	line.points = [a, b]
	line.default_color = color
	line.width = width
	_grid_root.add_child(line)


## 在 cell(x,y) 画一个色块菱形（terrain fallback 用）。存到 _block_pool。
## 原版 _place_block(title, x, y) 依赖 BlockAtlas；这里改为接收 Color 直接画。
func _place_color_block(color: Color, x: int, y: int) -> void:
	var node := _ColorBlock.new()
	node.color = color
	node.corners = _diamond_corners_screen(x, y)
	_blocks_root.add_child(node)
	_block_pool["%d,%d" % [x, y]] = node


## 给指定 cell 叠加色调（modulate）。原 API：set_cell_tint(x, y, tint)。
func set_cell_tint(x: int, y: int, tint: Color) -> void:
	var key := "%d,%d" % [x, y]
	if _block_pool.has(key):
		var n: Node2D = _block_pool[key]
		if is_instance_valid(n):
			n.modulate = tint


## 清除指定 cell 的色调。原 API：clear_cell_tint(x, y)。
func clear_cell_tint(x: int, y: int) -> void:
	var key := "%d,%d" % [x, y]
	if _block_pool.has(key):
		var n: Node2D = _block_pool[key]
		if is_instance_valid(n):
			n.modulate = Color.WHITE


func clear() -> void:
	for k in _block_pool.keys():
		var s: Node = _block_pool[k]
		if is_instance_valid(s):
			s.queue_free()
	_block_pool.clear()
	if _grid_root != null:
		for c in _grid_root.get_children():
			c.queue_free()


# ============================================================
# 通用标记生成器（原 API：make_cell_quad / make_cell_outline）
# range_overlay._add_cell_quad / _make_flat_quad 会调用。
# 原版返回 MeshInstance3D / Node3D；2D 版返回 Node2D（功能等价：一个色块/描边）。
# ============================================================

## 在 cell(x,y) 画实心菱形（terrain fallback / 范围铺底用）。
## 原 API：make_cell_quad(x, y, y_height, color) -> MeshInstance3D
## 2D 版：y_height 无意义（2D 无高度），忽略；返回 Node2D（_ColorBlock）。
func make_cell_quad(x: int, y: int, _y_height: float, color: Color) -> Node2D:
	var node := _ColorBlock.new()
	node.color = color
	node.corners = _diamond_corners_screen(x, y)
	return node


## 在 cell(x,y) 画一圈菱形描边（4 条 Line2D）。
## 原 API：make_cell_outline(x, y, y_height, color, line_radius) -> Node3D
## 2D 版：返回 Node2D（_OutlineBlock）。
func make_cell_outline(x: int, y: int, _y_height: float, color: Color, line_radius: float = 1.5) -> Node2D:
	var node := _OutlineBlock.new()
	node.color = color
	node.width = line_radius
	# 缩小一圈（_QUAD_INSET_SCALE）让相邻描边不相连
	var c := IsoCoords.to_screen(x, y)
	var hw := TILE_W * 0.5 * 0.85
	var hh := TILE_H * 0.5 * 0.85
	node.corners = [
		c + Vector2(0, -hh),
		c + Vector2(hw, 0),
		c + Vector2(0, hh),
		c + Vector2(-hw, 0),
	]
	return node


# ============================================================
# 内部节点类型（_draw 自绘菱形）
# ============================================================

## 实心菱形色块（terrain fallback / 范围铺底用）。
class _ColorBlock:
	extends Node2D
	var color: Color = Color.WHITE
	var corners: Array = []   # [Vector2, Vector2, Vector2, Vector2]
	func _draw() -> void:
		if corners.size() < 3:
			return
		var pts := PackedVector2Array()
		for p in corners:
			pts.append(p)
		draw_colored_polygon(pts, color)


## 菱形描边（4 条线）。
class _OutlineBlock:
	extends Node2D
	var color: Color = Color.WHITE
	var width: float = 1.5
	var corners: Array = []
	func _draw() -> void:
		if corners.size() < 3:
			return
		for i in range(corners.size()):
			var a: Vector2 = corners[i]
			var b: Vector2 = corners[(i + 1) % corners.size()]
			draw_line(a, b, color, width)
