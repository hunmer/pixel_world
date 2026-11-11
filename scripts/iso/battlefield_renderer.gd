## iso/battlefield_renderer.gd — JSON 战场的等距方块渲染器（像素版 Minecraft 风格）
##
## 复用世界渲染管线（isometric_column_batch + TerrainMaterialRegistry 贴图 + 程序化水面），
## 把战棋 GridSystem 的 7 种地形渲染成高低起伏的方块柱，替代旧的平面色块 fallback。
##
## 用法（battle.gd B2 / map_editor.gd 编辑器画布共用）：
##   var r := BattlefieldRenderer.new()
##   board.add_child(r)          # 或任意 Node2D 容器
##   r.setup(grid)               # grid: GridSystem（tiles[y][x].type）
##   r.coord_for(x, y)           # 格心屏幕坐标（含站立层高度）
##   r.stand_level(x, y)         # 该格站立层（柱顶）
##   r.pick_cell(screen, rect)   # 屏幕坐标 → 格子（多高度感知拾取）
##
## 高度仅用于视觉与遮挡（range_overlay alpha / 单位 Y 定位），不改变移动/战斗逻辑。

class_name BattlefieldRenderer
extends Node2D

const ColumnBatchScript = preload("res://scripts/isometric_column_batch.gd")
const TerrainMaterialRegistryScript = preload("res://scripts/world/terrain_material_registry.gd")

## 材质配置来源（只读 materials 段，不加载整套生态配置）
const MATERIALS_CONFIG_PATH := "res://config/ecology/world/base.json"

## 地形 → 柱组合定义（top=顶面材质, column=柱体材质, height=站立层）
## 陆地柱方块占 lvl 0..height-1（顶面在 height-1）；water 的 height 即水面层
## （bed=0 + 水面=1，与 plain 顶面平齐 → pick/stand_level 测试一致）。
const TERRAIN_STYLES := {
	&"plain":    {"top": &"grass",      "column": &"soil",      "height": 2},
	&"forest":   {"top": &"grass",      "column": &"soil",      "height": 2},
	&"mountain": {"top": &"rock",       "column": &"rock",      "height": 5},
	&"water":    {"top": &"moist_soil", "column": &"moist_soil", "height": 1},
	&"fort":     {"top": &"mossy_rock", "column": &"rock",      "height": 3},
	&"village":  {"top": &"parched_soil", "column": &"soil",    "height": 2},
	&"wall":     {"top": &"rock",       "column": &"rock",      "height": 4},
}

## 装饰物（level=相对柱顶的附加层，此处全部贴柱顶；offset_y 由贴图高度自适应）
const TERRAIN_PROPS := {
	&"forest":  [
		"res://meowa_tiles/trees/broadleaf_tree.png",
		"res://meowa_tiles/trees/pine_tree.png",
		"res://meowa_tiles/trees/birch_tree.png",
	],
	&"village": ["res://meowa_tiles/trees/apple_tree.png"],
	&"fort":    ["res://meowa_tiles/decorations/mossy_boulder_large.png"],
}

## 柱顶贴图的绘制高度（32×32 补齐后顶面菱形底部距中心 13px，见 _pad_texture_to_32）
const TOP_TEXTURE_BASE := 26.0

## 水体参数（语义同 main.gd：WATER_SURFACE_LEVEL 是水面层，侧壁逐层填充到水面）
const WATER_SURFACE_ALPHA := 0.38
const WATER_SIDE_ALPHA := 0.50
const WATER_COLOR := Color(0.070, 0.320, 0.520, 1.0)
const SORT_DIAGONAL_STRIDE := 128.0

## 拾取时尝试的最高层（wall=4, mountain=5，留裕量）
const PICK_MAX_LEVEL := 8

var grid: GridSystem = null
var _columns: Dictionary = {}  # Vector2i -> ColumnBatch

## ---- 材质/贴图缓存（battle 与 editor 场景共享，静态避免重复加载） ----
static var _shared_registry: TerrainMaterialRegistry = null
static var _shared_textures: Dictionary = {}   # surface_id -> {top: Texture2D, column: Texture2D, underwater: Texture2D}
static var _shared_water: Dictionary = {}      # face -> Texture2D
static var _shared_props: Dictionary = {}      # path -> Texture2D


func _ready() -> void:
	y_sort_enabled = true
	name = "TerrainLayer"


## 构建整张地图的地形柱。grid: GridSystem。
func setup(p_grid: GridSystem) -> void:
	grid = p_grid
	_clear_columns()
	if grid == null:
		return
	for y in range(grid.height):
		for x in range(grid.width):
			_build_column(Vector2i(x, y))
	print("[battlefield-render] 等距方块渲染完成: %dx%d, %d 柱" % [
		grid.width, grid.height, _columns.size()
	])


## 编辑器：重设网格后整体重建
func rebuild_all() -> void:
	setup(grid)


## 编辑器：重建单格（画笔/填充后调用）
func refresh_cell(x: int, y: int) -> void:
	var cell := Vector2i(x, y)
	if _columns.has(cell):
		var old: Node = _columns[cell]
		_columns.erase(cell)
		old.queue_free()
	if grid != null and _in_bounds(cell):
		_build_column(cell)


func column_count() -> int:
	return _columns.size()


## 格心屏幕坐标（含站立层高度）——供 range_overlay / 单位定位
func coord_for(x: int, y: int) -> Vector2:
	return IsoCoords.to_screen(x, y, stand_level(x, y))


## Y-sort 深度（与世界 main.gd._column_sort_y 同构）
func sort_for(x: int, y: int) -> float:
	return (x + y) * SORT_DIAGONAL_STRIDE + x


## 该格的站立层（柱顶高度）。未知地形按 plain 处理；越界返回 0。
func stand_level(x: int, y: int) -> int:
	if grid == null or not _in_bounds(Vector2i(x, y)):
		return 0
	var style: Dictionary = TERRAIN_STYLES.get(_tile_type(x, y), TERRAIN_STYLES[&"plain"])
	return int(style["height"])


## 屏幕坐标 → 格子（多高度感知）。签名对齐 IsoBoard.pick_cell。
func pick_cell(screen_pos: Vector2, _viewport_size: Vector2) -> Vector2i:
	var canvas := get_viewport().get_canvas_transform()
	var world := canvas.affine_inverse() * screen_pos
	return pick_world(world)


## 全局（viewport canvas）坐标 → 格子。逐层尝试：命中层的投影点落在该格柱顶。
func pick_world(world: Vector2) -> Vector2i:
	var local := global_transform.affine_inverse() * world
	for lvl in range(PICK_MAX_LEVEL, -1, -1):
		var candidate := IsoCoords.to_cell(local + Vector2(0.0, lvl * IsoCoords.LEVEL_H))
		if _in_bounds(candidate) and stand_level(candidate.x, candidate.y) == lvl:
			return candidate
	var fallback := IsoCoords.to_cell(local)
	if _in_bounds(fallback):
		return fallback
	return Vector2i(-1, -1)


## 地图中心的屏幕坐标（供编辑器/相机定位）
func map_center() -> Vector2:
	if grid == null:
		return Vector2.ZERO
	var cx := (grid.width - 1) / 2.0
	var cy := (grid.height - 1) / 2.0
	return IsoCoords.to_screen(int(cx), int(cy), stand_level(int(cx), int(cy)))


# ============================================================
# 柱构建
# ============================================================

func _build_column(cell: Vector2i) -> void:
	var blocks: Array[Dictionary] = []
	var tile_type := _tile_type(cell.x, cell.y)
	var style: Dictionary = TERRAIN_STYLES.get(tile_type, TERRAIN_STYLES[&"plain"])
	var height := int(style["height"])

	if tile_type == &"water":
		_append_water_column(cell, blocks)
	else:
		var top_tex := _surface_texture(style["top"], &"top")
		var col_tex := _surface_texture(style["column"], &"column")
		var tint := _terrain_tint(tile_type)
		for lvl in range(height):
			var tex: Texture2D = top_tex if lvl == height - 1 else col_tex
			blocks.append(_block(tex, lvl, tint))
		var prop := _prop_for(cell, tile_type)
		if not prop.is_empty():
			blocks.append(prop)

	var column: Node2D = ColumnBatchScript.new()
	add_child(column)
	column.configure(
		cell,
		blocks,
		IsoCoords.to_screen(cell.x, cell.y),
		sort_for(cell.x, cell.y),
		IsoCoords.LEVEL_H
	)
	_columns[cell] = column


## 水格：湖床（0 层）+ 半透明水面顶块（带岸线位掩码）。
## 当前高度模型下水面=1（浅水，与平原柱顶平齐）；侧壁逻辑保留给更深的水。
func _append_water_column(cell: Vector2i, blocks: Array[Dictionary]) -> void:
	var bed_tex := _surface_texture(&"moist_soil", &"top")
	blocks.append(_block(bed_tex, 0, Color.WHITE))
	var surface_level := stand_level(cell.x, cell.y)
	var expose_left := _neighbor_is_land(cell.x, cell.y + 1, true)
	var expose_right := _neighbor_is_land(cell.x + 1, cell.y, true)
	for lvl in range(1, surface_level):
		if expose_left:
			blocks.append(_water_block(_water_tex(&"left"), lvl, WATER_SIDE_ALPHA, &"left_side"))
		if expose_right:
			blocks.append(_water_block(_water_tex(&"right"), lvl, WATER_SIDE_ALPHA, &"right_side"))
	var surface := _water_block(_water_tex(&"surface"), surface_level, WATER_SURFACE_ALPHA, &"surface")
	var shore := 0
	if _neighbor_is_land(cell.x - 1, cell.y, false):
		shore |= 1
	if _neighbor_is_land(cell.x, cell.y - 1, false):
		shore |= 2
	if _neighbor_is_land(cell.x + 1, cell.y, false):
		shore |= 4
	if _neighbor_is_land(cell.x, cell.y + 1, false):
		shore |= 8
	surface["shore_edges"] = shore
	surface["shore_seed"] = (cell.x * 73856093) ^ (cell.y * 19349663)
	blocks.append(surface)


## 邻格是否为陆地。oob_as_land=true 时把地图外当陆地（水柱在地图边缘露出剖面）。
func _neighbor_is_land(x: int, y: int, oob_as_land: bool) -> bool:
	if grid == null or not _in_bounds(Vector2i(x, y)):
		return oob_as_land
	return _tile_type(x, y) != &"water"


## 地形色调（wall 压暗做石墙感，其余原色）
func _terrain_tint(tile_type: StringName) -> Color:
	if tile_type == &"wall":
		return Color(0.58, 0.58, 0.62, 1.0)
	return Color.WHITE


## 装饰物 block（树/巨石）。贴图底部对齐柱顶菱形，同一格确定性选取。
func _prop_for(cell: Vector2i, tile_type: StringName) -> Dictionary:
	var candidates: Array = TERRAIN_PROPS.get(tile_type, [])
	if candidates.is_empty():
		return {}
	var path: String = candidates[(cell.x * 31 + cell.y * 17) % candidates.size()]
	var tex := _prop_texture(path)
	if tex == null:
		return {}
	var lift := (tex.get_size().y - TOP_TEXTURE_BASE) * 0.5
	var block := _block(tex, stand_level(cell.x, cell.y), Color.WHITE, 1, Vector2(0.0, -lift))
	block["occluder_class"] = &"prop"
	return block


func _block(
	tex: Texture2D,
	level: int,
	modulate := Color.WHITE,
	render_priority := 0,
	render_offset := Vector2.ZERO
) -> Dictionary:
	return {
		"level": level,
		"texture": tex,
		"modulate": modulate,
		"render_priority": render_priority,
		"render_offset": render_offset,
		"occluder_class": &"terrain",
	}


func _water_block(texture: Texture2D, level: int, alpha: float, part: StringName) -> Dictionary:
	var block := _block(texture, level, Color(1.0, 1.0, 1.0, alpha), 1)
	block["water_part"] = part
	block["occluder_class"] = &"none"
	return block


func _clear_columns() -> void:
	for cell in _columns.keys():
		var column: Node = _columns[cell]
		if is_instance_valid(column):
			column.queue_free()
	_columns.clear()


func _tile_type(x: int, y: int) -> StringName:
	var tile: Dictionary = grid.tiles[y][x]
	return tile.type


func _in_bounds(cell: Vector2i) -> bool:
	return grid != null and cell.x >= 0 and cell.y >= 0 and cell.x < grid.width and cell.y < grid.height


# ============================================================
# 贴图供给（TerrainMaterialRegistry + 程序化水面，进程级缓存）
# ============================================================

func _surface_texture(surface_id: StringName, role: StringName) -> Texture2D:
	_ensure_shared_textures()
	var entry: Dictionary = _shared_textures.get(surface_id, {})
	var tex: Texture2D = entry.get(role, null)
	if tex == null:
		tex = entry.get(&"top", null)
	return tex


func _water_tex(face: StringName) -> Texture2D:
	_ensure_shared_textures()
	return _shared_water.get(face, null)


func _prop_texture(path: String) -> Texture2D:
	if _shared_props.has(path):
		return _shared_props[path]
	var tex: Texture2D = load(path)
	_shared_props[path] = tex
	return tex


static func _ensure_shared_textures() -> void:
	if _shared_registry != null:
		return
	_shared_registry = TerrainMaterialRegistryScript.new()
	var file := FileAccess.open(MATERIALS_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("[battlefield-render] 材质配置缺失: %s" % MATERIALS_CONFIG_PATH)
		return
	var parsed: Dictionary = JSON.parse_string(file.get_as_text())
	var generation: Dictionary = parsed.get("world", {}).get("generation", {})
	var materials: Variant = generation.get("materials", null)
	if materials == null:
		push_error("[battlefield-render] %s 缺少 world.generation.materials" % MATERIALS_CONFIG_PATH)
		return
	if not _shared_registry.load_materials(materials):
		push_error("[battlefield-render] 材质加载失败: %s" % str(_shared_registry.get_errors()))
	_shared_registry.set_texture_processor(
		Callable(BattlefieldRenderer, "_pad_texture_to_32")
	)
	for surface_id in [
		&"grass", &"soil", &"rock", &"mossy_rock", &"moist_soil", &"parched_soil",
	]:
		var entry := {}
		for role in [&"top", &"column", &"underwater"]:
			var tex: Texture2D = _shared_registry.get_texture(surface_id, role)
			if tex != null:
				entry[role] = tex
		_shared_textures[surface_id] = entry
	for face in [&"surface", &"left", &"right"]:
		_shared_water[face] = _make_water_face_texture(face)


## 32×32 底对齐补齐（同 main.gd._pad_texture_to_32：顶面菱形中心与其他 tile 一致）。
## registry 的 texture_processor 约定签名：(raw_texture, texture_path)。
static func _pad_texture_to_32(tex: Texture2D, _texture_path: String) -> Texture2D:
	var src := tex.get_image()
	if src.get_width() == 32 and src.get_height() == 32:
		return ImageTexture.create_from_image(src)
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.blit_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i(0, 32 - src.get_height()))
	return ImageTexture.create_from_image(img)


## 程序化水面贴图（同 main.gd._make_water_face_texture：互不重叠的水面/侧壁 mask）
static func _make_water_face_texture(face: StringName) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			var dx := absf(px - 16.0)
			var top_y := 6.0 + dx * 0.5
			var seam_y := 22.0 - dx * 0.5
			var inside_top := py >= top_y and py < seam_y
			var inside_left := px < 16.0 and py >= seam_y and py < 24.0 + px * 0.5
			var inside_right := px >= 16.0 and py >= seam_y and py < 32.0 - (px - 16.0) * 0.5
			var inside := (
				(face == &"surface" and inside_top)
				or (face == &"left" and inside_left)
				or (face == &"right" and inside_right)
			)
			if inside:
				img.set_pixel(x, y, WATER_COLOR)
	return ImageTexture.create_from_image(img)
