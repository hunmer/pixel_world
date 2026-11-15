## terrain_texture_catalog.gd — 世界引擎的方块贴图目录与纹理工具
## 从 main.gd 簇6/簇10 原样迁移：持有水面 mask 与各地表补齐贴图（初始化顺序与
## 旧 _ready 完全一致），按格确定性挑选实心柱材质，生成湖底/水下弱化纹理。
## 依赖通过 setup() 显式注入（材质注册表、采样器、_cell_rand 回调、共享常量），
## 不反向依赖 main.gd。

class_name TerrainTextureCatalog
extends RefCounted

var water_tex: ImageTexture  ## 只含顶面菱形的透明水面 mask
var water_left_tex: ImageTexture  ## 单层左侧水墙 mask
var water_right_tex: ImageTexture  ## 单层右侧水墙 mask
var _underwater_texture_cache := {}  ## biome/surface/depth -> 随深度弱化后的湖底材质
var _rock_tex: ImageTexture   ## 石头方块（rock 补齐到 32x32）
var _rock_grass_tex: ImageTexture  ## 草顶石（rock_with_grass 补齐，山麓草地）
var _moss_tex: ImageTexture   ## 苔石（rock-with-moss 补齐，高山处混杂）
var _soil_tex: ImageTexture   ## 泥土（soil 补齐）
var _moist_tex: ImageTexture  ## 湿土（moist_soil 补齐，河底与水边一格）
var _grass_tex: ImageTexture  ## 草顶泥土（soil_with_grass 补齐，普通草地）
var _little_grass_tex: ImageTexture  ## 稀草泥土（soil_with_little_grass 补齐，泥土里少量混入）
var _parched_tex: ImageTexture  ## 干裂土（沙漠过渡带的主地表）
var _sand_tex: ImageTexture  ## 沙漠基础方块（sand 补齐到 32x32）
var _snow_tex: ImageTexture  ## 雪地贴图补齐到 32x32，和其他地块共用同一锚点

var _materials  ## TerrainMaterialRegistry
var _sampler  ## TerrainSampler（_solid_tex 无 context 时的回退采样）
var _cell_rand: Callable  ## main 的 _cell_rand(cell, salt) 确定性随机
var _tile_w := 32  ## 菱形宽（像素）；由 setup 注入，与 main.TILE_W 同值
var _water_color := Color(0.070, 0.320, 0.520, 1.0)
var _water_depth_color := Color(0.035, 0.180, 0.270, 1.0)
var _water_max := 5  ## 水体最大柱高；由 setup 注入，与 main.WATER_MAX 同值


## 初始化顺序与旧 main._ready 逐行一致：水面 mask 先建，
## rock..sand 之后清一次湖底缓存，再取 grass/sparse_grass/snow。
func setup(
	materials,
	sampler,
	cell_rand: Callable,
	tile_w: int,
	water_color: Color,
	water_depth_color: Color,
	water_max: int
) -> void:
	_materials = materials
	_sampler = sampler
	_cell_rand = cell_rand
	_tile_w = tile_w
	_water_color = water_color
	_water_depth_color = water_depth_color
	_water_max = water_max
	water_tex = make_water_face_texture(&"surface")
	water_left_tex = make_water_face_texture(&"left")
	water_right_tex = make_water_face_texture(&"right")
	_rock_tex = _materials.get_texture(&"rock")
	_rock_grass_tex = _materials.get_texture(&"rock_grass")
	_moss_tex = _materials.get_texture(&"mossy_rock")
	_soil_tex = _materials.get_texture(&"soil")
	_moist_tex = _materials.get_texture(&"moist_soil")
	_parched_tex = _materials.get_texture(&"parched_soil")
	_sand_tex = _materials.get_texture(&"sand")
	_underwater_texture_cache.clear()
	_grass_tex = _materials.get_texture(&"grass")
	_little_grass_tex = _materials.get_texture(&"sparse_grass")
	_snow_tex = _materials.get_texture(&"snow")


## 实心柱第 level 层的材质：q 为柱顶所在层号
func solid_tex(
	q: int,
	level: int,
	cell: Vector2i,
	cell_context = null
) -> Texture2D:
	if q <= _water_max:
		return _moist_tex  # 河底/湖底用湿土
	var context = cell_context if cell_context != null else _sampler.sample(cell)
	var surface_id: StringName = context.surface_id
	var biome_id: StringName = context.biome_id
	# 保留当前高山苔石的确定性整柱变体；它也是一个注册材质，不再是 preload 特例。
	if (
		surface_id == &"rock"
		and biome_id not in [&"desert", &"desert_transition"]
		and q >= 15
		and _cell_rand.call(cell, 77) < 0.4
	):
		return _materials.get_texture(&"mossy_rock", &"top", biome_id)
	# 当前温带柱壁曾有少量稀草纹理，继续保留该视觉随机流；其他（包括未来新增）
	# surface 直接使用自身声明的 top/column 材质，无需在这里增加 biome 分支。
	if level < q and surface_id in [&"grass", &"rock_grass", &"moist_soil"]:
		return soil_or_little_grass(cell, level)
	var role := &"top" if level == q else &"column"
	var texture: Texture2D = _materials.get_texture(
		surface_id,
		role,
		biome_id
	)
	return texture if texture != null else _soil_tex


## 湖底来源由 surface material 决定；新 biome 只需覆盖 underwater_texture，
## 不再向 renderer 增加 desert/volcanic/ice 等名称分支。
func underwater_texture_for_context(context, water_depth: int) -> Texture2D:
	var safe_depth := maxi(1, water_depth)
	var cache_key := "%s/%s/%d" % [
		context.surface_id,
		context.biome_id,
		safe_depth,
	]
	if _underwater_texture_cache.has(cache_key):
		return _underwater_texture_cache[cache_key]
	var base_texture: Texture2D = _materials.get_texture(
		context.surface_id,
		&"underwater",
		context.biome_id
	)
	if base_texture == null:
		base_texture = _moist_tex
	var texture := make_underwater_ground_texture(safe_depth, base_texture, _water_depth_color)
	_underwater_texture_cache[cache_key] = texture
	return texture


## 泥土里按 8% 混入稀草泥土（按格+层确定性随机）
func soil_or_little_grass(cell: Vector2i, level: int) -> Texture2D:
	return _little_grass_tex if _cell_rand.call(cell, 88 + level) < 0.08 else _soil_tex


## 生成互不重叠的水面/侧壁 mask。顶面在所有水格只绘制一次；侧壁只用于岸线外轮廓。
static func make_water_face_texture(
	face: StringName,
	tile_w: int = 32,
	water_color: Color = Color(0.070, 0.320, 0.520, 1.0)
) -> ImageTexture:
	var img := Image.create(tile_w, tile_w, false, Image.FORMAT_RGBA8)
	for y in tile_w:
		for x in tile_w:
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			var dx := absf(px - tile_w * 0.5)
			var top_y := 6.0 + dx * 0.5
			var seam_y := 22.0 - dx * 0.5
			var inside_top := py >= top_y and py < seam_y
			var inside_left := px < tile_w * 0.5 and py >= seam_y and py < 24.0 + px * 0.5
			var inside_right := px >= tile_w * 0.5 and py >= seam_y and py < 32.0 - (px - 16.0) * 0.5
			var inside := (
				(face == &"surface" and inside_top)
				or (face == &"left" and inside_left)
				or (face == &"right" and inside_right)
			)
			if inside:
				img.set_pixel(x, y, water_color)
	return ImageTexture.create_from_image(img)


## 湖底从所属生态的基础方块取色，但随水深向统一深蓝收敛：浅水保留细节，深水不露网格。
static func make_underwater_ground_texture(
	water_depth: int,
	base_texture: Texture2D,
	water_depth_color: Color = Color(0.035, 0.180, 0.270, 1.0)
) -> ImageTexture:
	var source := base_texture.get_image()
	var detail_visibility := clampf(0.48 - (water_depth - 1) * 0.18, 0.0, 0.48)
	var depth_blend := 1.0 - detail_visibility
	var image := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	for y in source.get_height():
		for x in source.get_width():
			var pixel := source.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			var underwater_pixel := Color(pixel.r, pixel.g, pixel.b, 1.0).lerp(
				water_depth_color,
				depth_blend
			)
			underwater_pixel.a = pixel.a
			image.set_pixel(x, y, underwater_pixel)
	return ImageTexture.create_from_image(image)


static func underwater_flora_modulate(water_depth: int) -> Color:
	var visibility := 0.78 if water_depth <= 1 else 0.48
	return Color(0.72, 0.88, 0.94, visibility)


## 把非 32x32 的方块贴图底部对齐补到 32x32（顶面菱形中心与其他 tile 一致）
static func pad_texture_to_32(tex: Texture2D, tile_w: int = 32) -> ImageTexture:
	var src := tex.get_image()
	if src.get_width() == tile_w and src.get_height() == tile_w:
		return ImageTexture.create_from_image(src)
	var img := Image.create(tile_w, tile_w, false, Image.FORMAT_RGBA8)
	img.blit_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i(0, tile_w - src.get_height()))
	return ImageTexture.create_from_image(img)
