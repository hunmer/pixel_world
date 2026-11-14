## iso/battlefield_renderer.gd — JSON 战场的等距方块渲染器（像素版 Minecraft 风格）
##
## 复用世界渲染管线（isometric_column_batch + TerrainMaterialRegistry 贴图 + 程序化水面），
## 把战棋 GridSystem 的 11 种地形渲染成高低起伏的方块柱，替代旧的平面色块 fallback。
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
const Terrain3DScript = preload("res://scripts/iso/isometric_terrain_3d.gd")
const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
const TerrainMaterialRegistryScript = preload("res://scripts/world/terrain_material_registry.gd")
const BlockLayoutScript = preload("res://scripts/core/block_layout.gd")

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
	&"sand":    {"top": &"sand",         "column": &"sand",   "height": 2},
	&"snow":    {"top": &"snow",         "column": &"snow",   "height": 2},
	&"grass":   {"top": &"sparse_grass", "column": &"soil",   "height": 2},
	&"rocky":   {"top": &"rock_grass",   "column": &"rock",   "height": 3},
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
	&"snow":    [
		"res://meowa_tiles/decorations/snowy_tree_stump.png",
		"res://meowa_tiles/decorations/snowy_tree_stump_tall.png",
	],
}

## 柱顶贴图的绘制高度（32×32 补齐后顶面菱形底部距中心 13px，见 _pad_texture_to_32）
const TOP_TEXTURE_BASE := 26.0

## 水体参数（语义同 main.gd：WATER_SURFACE_LEVEL 是水面层，侧壁逐层填充到水面）
const WATER_SURFACE_ALPHA := 0.38
const WATER_SIDE_ALPHA := 0.50
const WATER_COLOR := Color(0.070, 0.320, 0.520, 1.0)
const SORT_DIAGONAL_STRIDE := 128.0

## 拾取时尝试的最高层（显式布局允许 0..16，旧柱最高 5）
const PICK_MAX_LEVEL := BlockLayoutScript.MAX_Z

var grid: GridSystem = null
var _columns: Dictionary = {}  # 2D 编辑器: Vector2i -> ColumnBatch；3D: cell -> block 记录
var _terrain_3d: Node3D = null
## 自定义植物覆盖表（编辑器植物层 / JSON 战场 props）：cell -> 贴图路径。
## ""=显式无植物（压制该地形默认装饰）；缺省格走 TERRAIN_PROPS 确定性选取。
var _custom_props: Dictionary = {}
## 空字典 = 旧柱体模式；非空 = 每格仅在指定 z 绘制一个独立方块。
var _block_layout: Dictionary = {}
## 用户素材视觉覆盖表（运行时 Texture，不参与序列化）：cell -> {layer:"tile"|"prop", visual}。
## visual 来自 UserAssetVisualAdapter：{texture, render_offset, canvas_size, asset_id, kind, missing}。
## layer="tile"：整图替换该格地块视觉（隐藏常规柱/装饰，避免与预渲染场景块重复叠画），
##               逻辑地形/高度/拾取不变；layer="prop"：素材植物块替代该格装饰物选取。
var _asset_overrides: Dictionary = {}

## ---- 材质/贴图缓存（battle 与 editor 场景共享，静态避免重复加载） ----
static var _shared_registry: TerrainMaterialRegistry = null
static var _shared_textures: Dictionary = {}   # surface_id -> {top: Texture2D, column: Texture2D, underwater: Texture2D}
static var _shared_water: Dictionary = {}      # face -> Texture2D
static var _shared_props: Dictionary = {}      # path -> Texture2D
static var _shared_prop_bottoms: Dictionary = {}  # path -> 最底非透明像素行的下边界（贴图像素坐标）


func _init() -> void:
	# refresh_cell 会删除并重新 append 单柱；必须按 sort_for 的 Y 键排序，
	# 否则新节点落到末尾，反向/前后相邻块的遮挡随编辑顺序改变。
	y_sort_enabled = true


func _active_camera() -> Camera3D:
	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport != null else null


func _ready() -> void:
	name = "TerrainLayer"
	if _active_camera() != null:
		_ensure_terrain_3d()

func _ensure_terrain_3d() -> void:
	if _terrain_3d != null:
		return
	_terrain_3d = Terrain3DScript.new()
	_terrain_3d.name = "BattlefieldTerrain3D"
	add_child(_terrain_3d)


## 构建整张地图的地形柱。grid: GridSystem。
func setup(p_grid: GridSystem) -> void:
	grid = p_grid
	_clear_columns()
	if grid == null:
		return
	for y in range(grid.height):
		for x in range(grid.width):
			_build_column(Vector2i(x, y))
	if _terrain_3d != null:
		_terrain_3d.flush()
	print("[battlefield-render] 等距 3D 方块渲染完成: %dx%d, %d 柱" % [
		grid.width, grid.height, _columns.size()
	])


## 编辑器：重设网格后整体重建
func rebuild_all() -> void:
	setup(grid)


## 编辑器：重建单格（画笔/填充后调用）
func refresh_cell(x: int, y: int) -> void:
	var cell := Vector2i(x, y)
	if _columns.has(cell):
		var old: Variant = _columns[cell]
		_columns.erase(cell)
		if old is Node:
			old.queue_free()
		elif _terrain_3d != null:
			_terrain_3d.remove_cell(cell)
	if grid != null and _in_bounds(cell):
		_build_column(cell)
	if _terrain_3d != null:
		_terrain_3d.flush()


## 批量设置自定义植物覆盖（setup 前调用即可生效；setup 后需 rebuild_all）。
## props: [{x,y,texture}]
func set_custom_props(props: Array) -> void:
	_custom_props.clear()
	for p in props:
		_custom_props[Vector2i(int(p.x), int(p.y))] = String(p.texture)


## setup 前注入显式单块布局；传空字典恢复旧柱体模式。
func set_block_layout(layout: Dictionary) -> void:
	_block_layout = layout.duplicate(true)


func has_explicit_block_layout() -> bool:
	return not _block_layout.is_empty()


func cell_z(cell: Vector2i) -> int:
	return BlockLayoutScript.z_at(_block_layout, cell) if has_explicit_block_layout() else 0


## 单格设置自定义植物（不重建，随下一次 refresh_cell 生效）；
## texture 为空 = 清除该格覆盖（恢复地形默认装饰选取）
func set_cell_prop(cell: Vector2i, texture: String) -> void:
	if texture.is_empty():
		_custom_props.erase(cell)
	else:
		_custom_props[cell] = texture


## 批量设置用户素材视觉覆盖（setup 前调用生效；setup 后需 rebuild_all）。
## entries: [{x:int, y:int, layer:"prop"|"tile", visual:Dictionary}]（UserAssetVisualAdapter.visual_for_entries 产出）。
## 同格允许 tile+prop 两层并存（地块整图 + 素材植物叠加）。
func set_custom_assets(entries: Array) -> void:
	_asset_overrides.clear()
	for e in entries:
		if not (e is Dictionary):
			continue
		var cell := Vector2i(int(e.get("x", -1)), int(e.get("y", -1)))
		if cell.x < 0 or cell.y < 0:
			continue
		var visual: Dictionary = e.get("visual", {})
		if visual.is_empty():
			continue
		var rec: Dictionary = _asset_overrides.get(cell, {})
		rec[String(e.get("layer", "prop"))] = visual
		_asset_overrides[cell] = rec


## 单格设置/清除某层素材视觉覆盖（不重建，随下一次 refresh_cell 生效）。
## visual 为空 Dictionary = 清除该层；两层都清空后整格记录移除。
func set_cell_asset(cell: Vector2i, layer: String, visual: Dictionary) -> void:
	var rec: Dictionary = _asset_overrides.get(cell, {})
	if visual.is_empty():
		rec.erase(layer)
	else:
		rec[layer] = visual
	if rec.is_empty():
		_asset_overrides.erase(cell)
	else:
		_asset_overrides[cell] = rec


## 某格当前素材覆盖记录（无则空字典；形如 {"tile": visual, "prop": visual}；调试/测试用）
func asset_override_at(cell: Vector2i) -> Dictionary:
	return _asset_overrides.get(cell, {})


## 只读快照：该格当前渲染 blocks（测试契约用；须在 setup/refresh_cell 之后调用）。
## 3D 路径返回 _columns[cell]["_blocks"]；2D 路径读 ColumnBatch._blocks（只读 duplicate）。
func cell_blocks_snapshot(cell: Vector2i) -> Array:
	var rec: Variant = _columns.get(cell, null)
	if rec == null:
		return []
	if rec is Dictionary:
		return (rec["_blocks"] as Array).duplicate(true)
	if rec is Node and is_instance_valid(rec):
		return (rec._blocks as Array).duplicate(true)
	return []


func column_count() -> int:
	return _columns.size()


## 格心屏幕坐标（含站立层高度）——供 range_overlay / 单位定位
func coord_for(x: int, y: int) -> Vector2:
	var camera := _active_camera()
	if camera != null:
		return IsoProjection.world_to_screen(camera, IsoProjection.grid_to_world(Vector2i(x, y), stand_level(x, y)))
	return IsoCoords.to_screen(x, y, stand_level(x, y))


## 真实顶面中心：2D 与贴图 TOP_CENTER_OFFSET 对齐；3D 与实际单块/柱顶同层。
## coord_for 保留旧战斗站立层契约，编辑器高光/锚点/拾取统一改用这里。
func top_center_for(x: int, y: int) -> Vector2:
	var level := visual_top_level(x, y)
	var camera := _active_camera()
	if camera != null:
		return IsoProjection.world_to_screen(camera, IsoProjection.grid_to_world(Vector2i(x, y), level))
	return IsoCoords.to_screen(x, y, level) + ColumnBatchScript.TOP_CENTER_OFFSET


## 顶面多边形（上、右、下、左），与 isometric_column_batch._terrain_top_corners 同构。
func top_polygon_for(x: int, y: int) -> PackedVector2Array:
	var cell := Vector2i(x, y)
	var level := visual_top_level(x, y)
	var camera := _active_camera()
	if camera != null:
		var center := IsoProjection.grid_to_world(cell, level)
		var half := IsoProjection.GRID_STEP * 0.5
		return PackedVector2Array([
			IsoProjection.world_to_screen(camera, center + Vector3(-half, 0, -half)),
			IsoProjection.world_to_screen(camera, center + Vector3(half, 0, -half)),
			IsoProjection.world_to_screen(camera, center + Vector3(half, 0, half)),
			IsoProjection.world_to_screen(camera, center + Vector3(-half, 0, half)),
		])
	var center := top_center_for(x, y)
	var half_x := ColumnBatchScript.DEFAULT_BASIS_X * 0.5
	var half_y := ColumnBatchScript.DEFAULT_BASIS_Y * 0.5
	return PackedVector2Array([
		center - half_x - half_y,
		center + half_x - half_y,
		center + half_x + half_y,
		center - half_x + half_y,
	])


## 单位/描边/菜单锚定的可视顶面层（各格最上块顶面）。
## 显式 block_layout 单层块顶面=cell_z；旧柱体模式陆地=stand_level-1（柱只建
## 0..height-1 块）、水面=stand_level。
func visual_top_level(x: int, y: int) -> int:
	if has_explicit_block_layout():
		return stand_level(x, y)
	if grid == null:
		return 0
	# 越界钳到边缘格：地图边缘描边的顶点沿用本格高度，避免幻影 0 层造成倾斜。
	var cx := clampi(x, 0, grid.width - 1)
	var cy := clampi(y, 0, grid.height - 1)
	# 旧陆柱最上块 level=height-1；旧水面 block.level=height。
	return stand_level(cx, cy) - (0 if _tile_type(cx, cy) == &"water" else 1)


## Y-sort 深度（与世界 main.gd._column_sort_y 同构）
func sort_for(x: int, y: int) -> float:
	return (x + y) * SORT_DIAGONAL_STRIDE + x


## 该格的站立层（柱顶高度）。未知地形按 plain 处理；越界返回 0。
func stand_level(x: int, y: int) -> int:
	if grid == null or not _in_bounds(Vector2i(x, y)):
		return 0
	if has_explicit_block_layout():
		return cell_z(Vector2i(x, y))
	var style: Dictionary = TERRAIN_STYLES.get(_tile_type(x, y), TERRAIN_STYLES[&"plain"])
	return int(style["height"])


## 屏幕坐标 → 格子。共享真实顶面射线，按正向距离而非高度顺序选择遮挡面。
func pick_cell(screen_pos: Vector2, _viewport_size: Vector2) -> Vector2i:
	var camera := _active_camera()
	if camera != null:
		var hit := IsoProjection.pick_top_face(
			camera, screen_pos, 0, PICK_MAX_LEVEL, Callable(self, "_pick_visual_top_level")
		)
		return hit.get("cell", Vector2i(-1, -1)) as Vector2i
	var canvas := get_viewport().get_canvas_transform()
	var world := canvas.affine_inverse() * screen_pos
	return pick_world(world)


func _pick_visual_top_level(cell: Vector2i) -> float:
	# 拾取必须落在玩家实际看到的顶面；旧陆柱站立层比最上块高一层。
	return float(visual_top_level(cell.x, cell.y)) if _in_bounds(cell) else -1.0


## 全局（viewport canvas）坐标 → 格子。逐层尝试：命中层的投影点落在该格柱顶。
func pick_world(world: Vector2) -> Vector2i:
	var local := global_transform.affine_inverse() * world
	if has_explicit_block_layout():
		if grid == null:
			return Vector2i(-1, -1)
		# ColumnBatch 由 renderer.y_sort_enabled 按 sort_for 绘制；按对角线逆序命中，
		# 与刷新后仍稳定的真实遮挡次序一致，不能依赖会被 refresh_cell 改变的节点顺序。
		for diagonal in range(grid.width + grid.height - 2, -1, -1):
			var x_max := mini(grid.width - 1, diagonal)
			var x_min := maxi(0, diagonal - grid.height + 1)
			for x in range(x_max, x_min - 1, -1):
				var y := diagonal - x
				if Geometry2D.is_point_in_polygon(local, top_polygon_for(x, y)):
					return Vector2i(x, y)
		return Vector2i(-1, -1)  # 悬空布局没有空白地面 fallback。
	for lvl in range(PICK_MAX_LEVEL, -1, -1):
		var candidate := IsoCoords.to_cell(
			local - ColumnBatchScript.TOP_CENTER_OFFSET + Vector2(0.0, lvl * IsoCoords.LEVEL_H)
		)
		if _in_bounds(candidate) and visual_top_level(candidate.x, candidate.y) == lvl:
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
	var height := stand_level(cell.x, cell.y) if has_explicit_block_layout() else int(style["height"])

	# 用户素材地块整图覆盖：隐藏常规柱与装饰（预渲染场景块自带块体，
	# 与常规柱重复叠画会穿帮）；素材植物层仍叠加。逻辑高度/拾取不变（stand_level 照传）
	var asset_rec: Dictionary = _asset_overrides.get(cell, {})
	var tile_visual: Dictionary = asset_rec.get("tile", {})
	if not tile_visual.is_empty():
		var tile_asset := _asset_block_for(cell, tile_visual)
		if not tile_asset.is_empty():
			blocks.append(tile_asset)
			var prop_visual: Dictionary = asset_rec.get("prop", {})
			if not prop_visual.is_empty():
				var pb := _asset_block_for(cell, prop_visual)
				if not pb.is_empty():
					blocks.append(pb)
			_commit_column(cell, blocks, height)
			return

	if has_explicit_block_layout():
		_append_explicit_block(cell, blocks, tile_type, style, asset_rec)
	elif tile_type == &"water":
		_append_water_column(cell, blocks)
	else:
		var top_tex := _surface_texture(style["top"], &"top")
		var col_tex := _surface_texture(style["column"], &"column")
		var tint := _terrain_tint(tile_type)
		for lvl in range(height):
			var tex: Texture2D = top_tex if lvl == height - 1 else col_tex
			blocks.append(_block(tex, lvl, tint))
		var prop := _asset_prop_or_default(cell, asset_rec, tile_type)
		if not prop.is_empty():
			blocks.append(prop)

	_commit_column(cell, blocks, height)


func _commit_column(cell: Vector2i, blocks: Array[Dictionary], height: int) -> void:
	if _active_camera() != null:
		_ensure_terrain_3d()
	if _terrain_3d != null:
		_columns[cell] = {"_blocks": blocks, "stand_level": height}
		_terrain_3d.set_cell(cell, blocks, height)
		return
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


## 显式布局：只生成所在 z 的一个顶块，绝不补地下层；水也只有水面，无湖床/侧壁。
func _append_explicit_block(
	cell: Vector2i,
	blocks: Array[Dictionary],
	tile_type: StringName,
	style: Dictionary,
	asset_rec: Dictionary
) -> void:
	var z := cell_z(cell)
	if tile_type == &"water":
		var surface := _water_block(_water_tex(&"surface"), z, WATER_SURFACE_ALPHA, &"surface")
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
		return
	var top_tex := _surface_texture(style["top"], &"top")
	blocks.append(_block(top_tex, z, _terrain_tint(tile_type)))
	var prop := _asset_prop_or_default(cell, asset_rec, tile_type)
	if not prop.is_empty():
		blocks.append(prop)


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


## 装饰物 block（树/巨石）。实际非透明底部对齐本格真实可见顶面中心，
## 不用整张 PNG 底边（含透明留白）或站立层猜位置，避免陷入方块/旧柱浮空。
## 选取顺序：自定义覆盖表（编辑器植物层/JSON props，""=压制默认）>
## 该地形 TERRAIN_PROPS 按格确定性选取。
func _prop_for(cell: Vector2i, tile_type: StringName) -> Dictionary:
	var path := ""
	if _custom_props.has(cell):
		path = String(_custom_props[cell])
		if path.is_empty():
			return {}  # 显式无植物
	else:
		var candidates: Array = TERRAIN_PROPS.get(tile_type, [])
		if candidates.is_empty():
			return {}
		path = candidates[(cell.x * 31 + cell.y * 17) % candidates.size()]
	var tex := _prop_texture(path)
	if tex == null:
		return {}
	var bottom_from_center := _prop_content_bottom(path, tex) - tex.get_size().y * 0.5
	# 2D 顶面中心比格原点高 2px；3D 锚点本身就是真实顶面，不能再加这份屏幕偏移。
	var top_offset_y := 0.0 if _terrain_3d != null else ColumnBatchScript.TOP_CENTER_OFFSET.y
	var offset := Vector2(0.0, top_offset_y - bottom_from_center)
	var block := _block(tex, visual_top_level(cell.x, cell.y), Color.WHITE, 1, offset)
	block["occluder_class"] = &"prop"
	return block


## 装饰物选取：用户素材 prop 覆盖优先（渲染层资产视觉替代默认/贴图装饰），
## 否则走 _prop_for（自定义贴图表 > TERRAIN_PROPS 确定性选取）。
## asset_rec: 该格素材覆盖记录 {"tile":visual?, "prop":visual?}（可为空字典）。
func _asset_prop_or_default(cell: Vector2i, asset_rec: Dictionary, tile_type: StringName) -> Dictionary:
	var prop_visual: Dictionary = asset_rec.get("prop", {})
	if not prop_visual.is_empty():
		return _asset_block_for(cell, prop_visual)
	return _prop_for(cell, tile_type)


## 素材 visual（UserAssetVisualAdapter 产出）→ 渲染 block。
## render_offset 已按 pivot 烘焙（相对纹理中心）；2D 路径再加顶面中心屏幕偏移（同 _prop_for）。
## 缺图占位（missing=true）淡红染色提示，引用不丢失。
func _asset_block_for(cell: Vector2i, visual: Dictionary) -> Dictionary:
	var tex: Texture2D = visual.get("texture", null)
	if tex == null:
		return {}
	var top_offset_y := 0.0 if _terrain_3d != null else ColumnBatchScript.TOP_CENTER_OFFSET.y
	var offset: Vector2 = visual.get("render_offset", Vector2.ZERO)
	offset.y += top_offset_y
	var block := _block(tex, visual_top_level(cell.x, cell.y), Color.WHITE, 1, offset)
	block["occluder_class"] = &"prop"
	block["asset_id"] = String(visual.get("asset_id", ""))  # cell_blocks_snapshot 测试可断言
	if bool(visual.get("missing", false)):
		block["modulate"] = Color(1.0, 0.55, 0.55, 0.92)
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
	if _terrain_3d != null:
		_terrain_3d.clear()
	for cell in _columns.keys():
		var column: Variant = _columns[cell]
		if column is Node and is_instance_valid(column):
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


## 最底可见像素行的下边界（不是整张图底边）；阈值与 ColumnBatch 遮挡采样一致。
static func _prop_content_bottom(path: String, tex: Texture2D) -> float:
	if _shared_prop_bottoms.has(path):
		return float(_shared_prop_bottoms[path])
	var bottom := float(tex.get_size().y)
	var image: Image = tex.get_image()
	if image != null and not image.is_empty():
		var found := false
		for y in range(image.get_height() - 1, -1, -1):
			for x in range(image.get_width()):
				if image.get_pixel(x, y).a > 0.01:
					bottom = float(y + 1)
					found = true
					break
			if found:
				break
	_shared_prop_bottoms[path] = bottom
	return bottom


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
		&"sand", &"snow", &"sparse_grass", &"rock_grass",
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


# ============================================================
# 编辑器调色板预览（静态：无网格依赖）
# ============================================================

## 给定地形生成单柱预览 blocks（tile_preview.gd 调色板缩略图用）。
## 水面不带岸线/侧壁；with_prop=false 时不叠装饰物；single=true 时只保留
## 顶块并压到 level 0（调色板每个地形就是一个 tile，不再叠成高塔）。
## 装饰物固定取该地形的第一个候选（无网格坐标可做确定性选取）。
static func preview_blocks(terrain: StringName, with_prop := true, single := false) -> Array:
	_ensure_shared_textures()
	var style: Dictionary = TERRAIN_STYLES.get(terrain, TERRAIN_STYLES[&"plain"])
	var height := int(style["height"])
	var blocks: Array = []
	if terrain == &"water":
		blocks.append(_preview_block(_shared_tex(&"moist_soil", &"top"), 0, Color.WHITE))
		var surf := _preview_block(_shared_water.get(&"surface", null), 1, Color(1.0, 1.0, 1.0, WATER_SURFACE_ALPHA))
		surf["water_part"] = &"surface"
		blocks.append(surf)
	else:
		var top_tex: Texture2D = _shared_tex(style["top"], &"top")
		var col_tex: Texture2D = _shared_tex(style["column"], &"column")
		var tint := Color(0.58, 0.58, 0.62, 1.0) if terrain == &"wall" else Color.WHITE
		for lvl in range(height):
			blocks.append(_preview_block(top_tex if lvl == height - 1 else col_tex, lvl, tint))
		if with_prop:
			var prop := _preview_prop(terrain, height)
			if not prop.is_empty():
				blocks.append(prop)
	if single and blocks.size() > 1:
		var top: Dictionary = blocks[blocks.size() - 1]
		top["level"] = 0
		blocks = [top]
	return blocks


## 植物调色板 tile：装饰物贴图单独成一块（不叠在柱上）。无候选返回 {}。
static func preview_prop_block(terrain: StringName) -> Dictionary:
	_ensure_shared_textures()
	return _preview_prop(terrain, 0)


## 按贴图路径生成独立植物 tile（调色板枚举全部 trees/plants/decorations 用）。
## 路径加载失败返回 {}。
static func preview_path_block(path: String) -> Dictionary:
	_ensure_shared_textures()
	var tex: Texture2D = load(path)
	if tex == null:
		return {}
	var lift := (tex.get_size().y - TOP_TEXTURE_BASE) * 0.5
	var prop := _preview_block(tex, 0, Color.WHITE)
	prop["render_offset"] = Vector2(0.0, -lift)
	prop["occluder_class"] = &"prop"
	return prop


## 用户素材 visual → 调色板预览块（tile_preview 素材缩略图用）。
## 偏移沿用落地的 pivot 规则（visual.render_offset）+ 底缘对齐 TOP_TEXTURE_BASE/2，
## 预览与战场同一烘焙结果（crop/scale 已烘进 texture），所见即所得。
static func preview_visual_block(visual: Dictionary) -> Dictionary:
	var tex: Texture2D = visual.get("texture", null)
	if tex == null:
		return {}
	var offset: Vector2 = visual.get("render_offset", Vector2.ZERO)
	offset.y += TOP_TEXTURE_BASE * 0.5
	var prop := _preview_block(tex, 0, Color.WHITE)
	prop["render_offset"] = offset
	prop["occluder_class"] = &"prop"
	if bool(visual.get("missing", false)):
		prop["modulate"] = Color(1.0, 0.55, 0.55, 0.92)
	return prop


static func _preview_prop(terrain: StringName, level: int) -> Dictionary:
	var candidates: Array = TERRAIN_PROPS.get(terrain, [])
	if candidates.is_empty():
		return {}
	var tex: Texture2D = load(String(candidates[0]))
	if tex == null:
		return {}
	var lift := (tex.get_size().y - TOP_TEXTURE_BASE) * 0.5
	var prop := _preview_block(tex, level, Color.WHITE)
	prop["render_offset"] = Vector2(0.0, -lift)
	prop["occluder_class"] = &"prop"
	return prop


static func _shared_tex(surface_id: StringName, role: StringName) -> Texture2D:
	var entry: Dictionary = _shared_textures.get(surface_id, {})
	var tex: Texture2D = entry.get(role, null)
	if tex == null:
		tex = entry.get(&"top", null)
	return tex


static func _preview_block(tex: Texture2D, level: int, modulate: Color) -> Dictionary:
	return {
		"level": level,
		"texture": tex,
		"modulate": modulate,
		"render_priority": 0,
		"render_offset": Vector2.ZERO,
		"occluder_class": &"terrain",
	}
