## minimap_renderer.gd — 小地图：右上角 UI 挂载、已探索格着色缓存与全图重绘。
##
## 从 main.gd 小地图簇整体迁出（结构性拆分，行为不变）。探索缓存字典由调用方
## （main.gd `_explored`）持有并以引用传入：地图打开时直接读缓存，不再采样地形。
class_name MinimapRenderer
extends RefCounted

## 小地图边长（1 像素 = 1 格，奇数使角色居中）。
const MINIMAP_SIZE := 129

var _img: Image
var _tex: ImageTexture
var _materials: TerrainMaterialRegistry = null
var _sampler: TerrainSampler = null
var _water_max := 5


## 注入地形着色依赖（main.gd 在生态配置加载后调用一次）。
func configure(materials: TerrainMaterialRegistry, sampler: TerrainSampler, water_max: int) -> void:
	_materials = materials
	_sampler = sampler
	_water_max = water_max


## 创建右上角小地图 UI（CanvasLayer 层级 100），挂在 host 场景节点下。
func setup_ui(host: Node, side_panel_width: int) -> void:
	_img = Image.create(MINIMAP_SIZE, MINIMAP_SIZE, false, Image.FORMAT_RGBA8)
	_img.fill(Color.BLACK)
	_tex = ImageTexture.create_from_image(_img)
	var layer := CanvasLayer.new()
	layer.layer = 100
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1, 0.9)
	bg.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# 舞台右上角 = 窗口右上角让出右侧侧栏列（小地图等游戏 UI 不压到面板下方）
	bg.offset_left = -MINIMAP_SIZE - 12 - side_panel_width
	bg.offset_top = 8
	bg.offset_right = -8 - side_panel_width
	bg.offset_bottom = MINIMAP_SIZE + 12
	var rect := TextureRect.new()
	rect.texture = _tex
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.position = Vector2(2, 2)
	bg.add_child(rect)
	layer.add_child(bg)
	host.add_child(layer)


## 角色周围 sight_radius 范围变为已探索（永久保留）。
func reveal(
	center: Vector2i,
	sight_radius: int,
	explored: Dictionary,
	sample_cell_context: Callable
) -> void:
	for dy in range(-sight_radius, sight_radius + 1):
		for dx in range(-sight_radius, sight_radius + 1):
			var cell := center + Vector2i(dx, dy)
			if not explored.has(cell):
				var context = sample_cell_context.call(cell)
				explored[cell] = map_color_for_context(context)


## 以 center 为中心重绘整张小地图并标记角色红点。
func update(center: Vector2i, explored: Dictionary) -> void:
	var half := MINIMAP_SIZE / 2
	for py in MINIMAP_SIZE:
		for px in MINIMAP_SIZE:
			var cell := center + Vector2i(px - half, py - half)
			var c: Color = explored.get(cell, Color.BLACK)
			_img.set_pixel(px, py, c)
	_img.set_pixel(half, half, Color(1.0, 0.2, 0.2))  # 角色标记
	_tex.update(_img)


func map_color_for_context(context, sampler = null) -> Color:
	var color_sampler = sampler if sampler != null else _sampler
	if int(context.height) <= _water_max:
		return Color(0.08, 0.2, 0.5).lerp(
			Color(0.3, 0.6, 0.95),
			float(context.height) / float(_water_max)
		)
	if context.is_shore or context.surface_id in [&"rock", &"mossy_rock"]:
		return _materials.get_minimap_color(
			context.surface_id,
			context.biome_id
		)
	var module_color: Color = color_sampler.biome_registry.minimap_color(
		context.cell,
		context.height,
		context.biome_id
	)
	if module_color.a > 0.0:
		return module_color
	return _materials.get_minimap_color(
		context.surface_id,
		context.biome_id
	)
