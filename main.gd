extends Node2D
## 阶段 5：Voronoi 群落分区 + 模块化地形 + 连续高度场 + 流式生成 + 小地图。
## 群落：Voronoi 图划分海洋/平原/丘陵/高山/沼泽，边界用 F2-F1 过渡带混合参数，无缝衔接。
## 地形：全局基线/细节噪声为底，各群落模块增强/削弱/变体（offset/amp/ridge/steep/peak）。
## 气候：独立低频区域场生成大陆级沙漠，海拔决定雪原；沙漠 profile 再叠加沙丘起伏。
## 材质：量化 16 层 + 独立山峰层可突破上限，生态顶层可替换为沙地或雪地。

const TILE_W := 32  ## 菱形宽（像素）
const TILE_H := 16  ## 菱形高（像素）
const LEVEL_H := 10  ## 方块侧壁高度：与 32x32 等距地块的侧壁高度一致

const ColumnBatchScript = preload("res://scripts/isometric_column_batch.gd")
const WanderingAnimalScript = preload("res://scripts/wandering_animal.gd")
const IsometricDepthSort = preload("res://scripts/isometric_depth_sort.gd")
const IsometricViewScript = preload("res://scripts/isometric_view.gd")
const WeatherSystemScript = preload("res://scripts/weather_system.gd")
const DayNightSystemScript = preload("res://scripts/day_night_system.gd")
const WorldAudioSystemScript = preload("res://scripts/world_audio_system.gd")
const DepthOfFieldSystemScript = preload("res://scripts/depth_of_field_system.gd")
const GameHudScript = preload("res://scripts/game_hud.gd")
const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const WorldMapOverlayScript = preload("res://scripts/world_map_overlay.gd")
const UnderwaterAnimalShader = preload("res://shaders/underwater_animal.gdshader")
const DeterministicRngScript = preload("res://scripts/world/deterministic_rng.gd")
const CellContextScript = preload("res://scripts/world/cell_context.gd")
const CellStateScript = preload("res://scripts/world/cell_state.gd")
const TerrainSamplerScript = preload("res://scripts/world/terrain_sampler.gd")
const TerrainMaterialRegistryScript = preload(
	"res://scripts/world/terrain_material_registry.gd"
)
const EcologyRegistryScript = preload("res://scripts/ecology/ecology_registry.gd")
const AmbientRegistryScript = preload("res://scripts/ecology/ambient_registry.gd")
const CommunityRuntimeScript = preload("res://scripts/ecology/community_runtime.gd")
const CommunitySpawnerScript = preload("res://scripts/ecology/community_spawner.gd")
const CommunityStateStoreScript = preload(
	"res://scripts/ecology/community_state_store.gd"
)
const AnimalBehaviorRegistryScript = preload(
	"res://scripts/animals/animal_behavior_registry.gd"
)
const ECOLOGY_MANIFEST_PATH := "res://config/ecology/manifest.json"
const ECOSYSTEM_CONFIG_PATH := "res://config/ecosystems.json"
const FLORA_LAYER_IDS := ["tree", "ground_cover", "decoration"]
const SORT_DEPTH_SCALE := 16.0  ## 默认角度下与旧版每格 128 的合成深度间距一致
const SORT_REBASE_DISTANCE := 4096

const ANIMAL_SORT_BIAS := WanderingAnimalScript.SORT_BIAS
const PLAYER_SORT_BIAS := 0.5
const PLAYER_OCCLUSION_SORT_EPSILON := 0.01
## block 本身还有半个贴图宽度；0.75 格的命中边距最终呈现约 3x3 的可见窗口。
const PLAYER_OCCLUSION_SCREEN_MARGIN := Vector2(TILE_W * 0.75, TILE_H * 0.75)
## 每个遮挡块保持固定的强透明度；不能按命中块总数继续拆分，否则高山会近乎消失。
const PLAYER_OCCLUSION_BLOCK_ALPHA := 0.20
const ANIMAL_WAIT_MIN := 0.6
const ANIMAL_WAIT_SPAN := 2.0
const ANIMAL_FLEE_RADIUS := 6
const ANIMAL_FLEE_SPEED := 2.0
const ANIMAL_FLEE_WAIT := 0.08
const ANIMAL_BLOCKED_RETRY := 0.25
const ANIMAL_FLEE_DISTANCE_WEIGHT := 1000.0
const ANIMAL_LEAVE_WATER_BONUS := 10000.0
const ANIMAL_GROUP_COHESION_WEIGHT := 6.0
const ANIMAL_DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

## 只使用像素安全的缩放倍率，避免任意比例造成像素抖动和采样缝隙。
const ZOOM_LEVELS: Array[float] = [0.5, 1.0, 2.0, 3.0, 4.0]
const DEFAULT_ZOOM_INDEX := 2
const PINCH_THRESHOLD := 1.12

const LEVELS := 16   ## 噪声量化层数
const WATER_MAX := 5  ## 层号 <= 此值为水面
const WATER_SURFACE_LEVEL := WATER_MAX + 1  ## 水体位于湖床上方，水面和首层陆地 q=6 齐平

## 连续透明水面 + 只在岸线暴露的体积侧壁。内部水面/侧壁不重复绘制，因此不会叠出网格。
const WATER_COLOR := Color(0.070, 0.320, 0.520, 1.0)
const WATER_DEPTH_COLOR := Color(0.035, 0.180, 0.270, 1.0)
const WATER_SURFACE_ALPHA := 0.38
const WATER_SIDE_ALPHA := 0.50
const WATER_SURFACE_VISUAL_OFFSET := Vector2(0.0, -2.0)

## 群系
enum { BIOME_PLAINS, BIOME_DESERT, BIOME_SNOW, BIOME_DESERT_TRANSITION }
enum DesertSurface { NONE, SAND, ROCK, TRANSITION_PARCHED, TRANSITION_SPARSE_GRASS }

## 地貌模块：offset 基准高度 / amp 起伏强度 / ridge 山脊化 / steep 水下坡度 / peak 高峰权重
## terrace 梯田化强度：>0 时地形向固定周期的台阶吸附，相邻格一次跳 2~3 层（丘陵/山区的陡峭感）
enum Landform { OCEAN, PLAINS, HILLS, MOUNTAIN, SWAMP }
const LANDFORM_ID_TO_TYPE := {
	"ocean": Landform.OCEAN,
	"plains": Landform.PLAINS,
	"hills": Landform.HILLS,
	"mountain": Landform.MOUNTAIN,
	"swamp": Landform.SWAMP,
}

@export var seed := 0  ## 0 表示每次随机
## 层号 >= 此值时陆地用石头表现山体
var rock_level := 12
## 独立山峰的额外层数上限（叠加在正常 16 层之上，比普通的山更高、更陡；按模块 peak 权重缩放）
var peak_max := 10
## 逻辑 x/y 方形窗口的半径；经过等距投影后，画面边界自然成为完整菱形。
@export var stream_extent := 32
## 小地图视野（探索）半径（格）
@export var sight_radius := 12
## 移动一格所需时间（秒）
@export var move_time := 0.15
## 按住 Shift 时的移动速度倍率
@export var fast_multiplier := 3.0
## 帧率无关的渐近跟随速度；逻辑位置保留小数，渲染位置仍按缩放倍率像素对齐。
@export_range(1.0, 20.0, 0.5) var camera_smoothing_speed := 8.0

const MINIMAP_SIZE := 129  ## 小地图边长（1 像素 = 1 格，奇数使角色居中）
const WORLD_MAP_RANGE_MULTIPLIER := 8

var _ecosystem_config := {}
var _ecology_registry
var _community_runtime
var _terrain_sampler
var _terrain_materials
var _noise_fields := {}
var _plant_species := {}
var _animal_species := {}
var _animal_behavior_stacks := {}
var _animal_behavior_tag_scan_radius := 1
var _animal_behavior_registry = AnimalBehaviorRegistryScript.new()
var _ambient_species := {}
var _spatial_flora_sources: Array[Dictionary] = []
var _spatial_flora_plan_cache := {}
var _ecosystems_by_id := {}
var _ecosystem_order: Array[Dictionary] = []
var _default_ecosystem_id := ""
var _landform_configs: Array[Dictionary] = []
var _landform_ids: Array[String] = []
var _landform_names: Array[String] = []
var _landform_order: Array[int] = []
var _landform_total_weight := 100.0
var _noise_type := FastNoiseLite.TYPE_PERLIN
var _fractal_type := FastNoiseLite.FRACTAL_FBM
var _noise_octaves := 4
var _flora_layer_configs := {}
var _flora_conflict_seed := 640
var _region_cell_size := 128.0
var _region_jitter := 0.9
var _region_blend_width := 14.0
var _sea_threshold := 6.0 / LEVELS
var _mountain_threshold := 0.65
var _terrace_period := 0.3
var _snow_base_level := 14
var _snow_temperature_level_scale := 3.0
var _dominant_species_chance := 0.8

var _tree_placement := FastNoiseLite.new()  ## 低频树木群落：沿用旧植被 seed
var _ground_cover_placement := FastNoiseLite.new()  ## 高频草丛/花草斑块
var _decoration_placement := FastNoiseLite.new()  ## 中尺度自然装饰斑块
var _water_tex: ImageTexture  ## 只含顶面菱形的透明水面 mask
var _water_left_tex: ImageTexture  ## 单层左侧水墙 mask
var _water_right_tex: ImageTexture  ## 单层右侧水墙 mask
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
var _cells := {}     ## Vector2i -> IsometricColumnBatch，每格一个批绘制节点
var _cell_states := {}  ## Vector2i -> CellState；生态、占用与导航的唯一逻辑来源
var _water_cells := {}  ## 当前流式窗口内的水格索引，供天气落点 O(1) 命中
var _animals := {}   ## 出生格 -> WanderingAnimal；出生格保持确定性生成身份
var _animal_frames_cache := {}  ## animal species id -> SpriteFrames
var _underwater_animal_material_cache := {}  ## water depth -> shared foreground-water material
var _animal_groups = CommunityStateStoreScript.new(2048)
var _animal_behavior_distance_cache := {}
var _ecology_near_tag_cache := {}
var _explored := {}  ## Vector2i -> Color；探索时缓存基础色，地图打开时不再采样地形
var _cam: Camera2D
var _hud
var _world_map
var _weather
var _day_night
var _ambient_registry
## 兼容现有调试/契约读取；实际实例由 AmbientRegistry 按配置创建。
var _fireflies
var _audio
var _depth_of_field
var _current_seed := 0
var _world_rng = DeterministicRngScript.new(0)
var _sort_origin := Vector2i.ZERO
var _has_sort_origin := false
var _iso_view = IsometricViewScript.new(TILE_W, TILE_H, LEVEL_H)
var _view_dragging := false
var _view_drag_last_x := 0.0
var _zoom_index := DEFAULT_ZOOM_INDEX
var _pinch_factor := 1.0
var _camera_smooth_position := Vector2.ZERO

# ---- B1 就地战斗模式字段（_battle_active=false 时全部不影响原行为）----
var _battle_active := false            # 战斗模式开关（照搬 is_world_map_open 范式）
var _battle_system: Node2D = null      # BattleSystem 实例（battle.gd 作为子节点）
var _battle_focus_world_pos := Vector2.ZERO  # 战斗时相机聚焦的世界坐标
# 战场相机操控：B1 下相机归 main.gd，战场中心 + offset 即相机位置。
var _battle_cam_offset := Vector2.ZERO   # 平移偏移（相对战场中心）
var _battle_pan_active := false          # 拖拽平移中（中键 / 空格+左键）
var _battle_pan_last := Vector2.ZERO     # 上次拖拽鼠标位置
# 进入战斗时备份的相机/玩家状态，退出时恢复
var _cam_pos_backup := Vector2.ZERO
var _zoom_index_backup := 0
var _player_visible_backup := true
# BattleSystem 脚本预加载
const _BattleScript := preload("res://scripts/scenes/battle.gd")

var _player: Sprite2D
var _player_cell := Vector2i.ZERO
var _move_from_cell := Vector2i.ZERO
var _move_from := Vector2.ZERO
var _move_to := Vector2.ZERO
var _move_sort_from := 0.0
var _move_sort_to := 0.0
var _move_level_from := 0.0
var _move_level_to := 0.0
var _player_visual_position := Vector2.ZERO
var _move_t := 1.0  ## >= 1 表示静止
var _player_occluder_cells := {}  ## cell -> 当前需要透明的 block indices
var _player_occlusion_fading_cells := {}  ## 包含正在恢复不透明度的格
var _player_occlusion_dirty := true
var _player_occlusion_last_visual_position := Vector2(1.0e20, 1.0e20)
var _player_occlusion_last_sort_y := 1.0e20
var _player_occlusion_last_stand_level := 1.0e20

var _minimap_img: Image
var _minimap_tex: ImageTexture


func _load_ecosystem_config() -> bool:
	_ecology_registry = EcologyRegistryScript.new()
	var loaded: bool
	if FileAccess.file_exists(ECOLOGY_MANIFEST_PATH):
		loaded = _ecology_registry.load_manifest(ECOLOGY_MANIFEST_PATH)
	else:
		# 迁移期间仍允许旧单文件启动；正式配置优先走模块 manifest。
		loaded = _ecology_registry.load_legacy(ECOSYSTEM_CONFIG_PATH)
	if not loaded:
		push_error("生态注册表加载失败:\n" + _ecology_registry.get_error_text())
		return false
	_ecosystem_config = _ecology_registry.to_legacy_config()
	if _ecosystem_config.is_empty():
		push_error("生态注册表未生成运行时配置")
		return false
	if not _compile_ecosystem_config():
		return false
	var catalog: Dictionary = _ecology_registry.get_catalog()
	_community_runtime = CommunityRuntimeScript.new()
	if not _community_runtime.configure(catalog):
		push_error("群落运行时配置失败: " + _community_runtime.last_error)
		return false
	_spatial_flora_sources = _community_runtime.spatial_flora_sources()
	_terrain_sampler = TerrainSamplerScript.new()
	if not _terrain_sampler.configure(
		catalog.get("world", {}),
		catalog.get("biomes", {}),
		0
	):
		push_error("地形采样器配置失败: " + _terrain_sampler.last_error)
		return false
	_terrain_materials = TerrainMaterialRegistryScript.new()
	var generation: Dictionary = _ecosystem_config.get("generation", {})
	if not _terrain_materials.load_from_generation(generation):
		push_error("地表材质配置失败: %s" % [_terrain_materials.get_errors()])
		return false
	if not _terrain_materials.load_biome_catalog(
		catalog.get("biomes", {}),
		catalog.get("biome_order", [])
	):
		push_error("Biome 地表材质扩展失败: %s" % [_terrain_materials.get_errors()])
		return false
	_terrain_materials.set_texture_processor(
		Callable(self, "_process_terrain_material_texture")
	)
	_sync_legacy_noise_handles()
	return true


func _compile_ecosystem_config() -> bool:
	if int(_ecosystem_config.get("version", 0)) != 1:
		push_error("不支持的生态配置版本: %s" % _ecosystem_config.get("version", null))
		return false
	var generation: Dictionary = _ecosystem_config.get("generation", {})
	var height: Dictionary = generation.get("height", {})
	rock_level = int(height.get("rock_level", rock_level))
	peak_max = int(height.get("peak_extra_levels", peak_max))
	_sea_threshold = float(height.get("sea_threshold", _sea_threshold))
	_mountain_threshold = float(height.get("mountain_threshold", _mountain_threshold))
	_terrace_period = float(height.get("terrace_period", _terrace_period))
	if (
		rock_level < 0
		or peak_max < 0
		or _sea_threshold <= 0.0
		or _sea_threshold >= 1.0
		or _mountain_threshold <= _sea_threshold
		or _mountain_threshold >= 1.0
		or _terrace_period <= 0.0
	):
		push_error("generation.height 的范围无效")
		return false

	var noise: Dictionary = generation.get("noise", {})
	var noise_type_name := String(noise.get("type", "perlin")).to_lower()
	if noise_type_name not in ["perlin", "simplex", "simplex_smooth", "value", "value_cubic"]:
		push_error("未知 noise type: " + noise_type_name)
		return false
	var fractal_type_name := String(noise.get("fractal", "fbm")).to_lower()
	if fractal_type_name not in ["fbm", "ridged", "ping_pong"]:
		push_error("未知 fractal type: " + fractal_type_name)
		return false
	_noise_type = _noise_type_from_name(noise_type_name)
	_fractal_type = _fractal_type_from_name(fractal_type_name)
	_noise_octaves = int(noise.get("octaves", _noise_octaves))
	if _noise_octaves <= 0:
		push_error("noise.octaves 必须大于 0")
		return false
	_noise_fields = noise.get("fields", {})
	for field_id in _noise_fields:
		var field: Dictionary = _noise_fields[field_id]
		if float(field.get("frequency", 0.0)) <= 0.0:
			push_error("noise field frequency 必须大于 0: " + field_id)
			return false
		if int(field.get("octaves", _noise_octaves)) <= 0:
			push_error("noise field octaves 必须大于 0: " + field_id)
			return false

	var flora_generation_value: Variant = generation.get("flora", {})
	if not flora_generation_value is Dictionary:
		push_error("generation.flora 必须是 Dictionary")
		return false
	var flora_generation: Dictionary = flora_generation_value
	_flora_conflict_seed = int(flora_generation.get("conflict_seed", _flora_conflict_seed))
	var flora_layers_value: Variant = flora_generation.get("layers", {})
	if not flora_layers_value is Dictionary:
		push_error("generation.flora.layers 必须是 Dictionary")
		return false
	_flora_layer_configs = flora_layers_value
	for configured_layer_id in _flora_layer_configs:
		if String(configured_layer_id) not in FLORA_LAYER_IDS:
			push_error("generation.flora.layers 包含未知层: " + String(configured_layer_id))
			return false
	for layer_id in FLORA_LAYER_IDS:
		if not _flora_layer_configs.has(layer_id):
			push_error("generation.flora.layers 缺少层: " + layer_id)
			return false
		var layer_value: Variant = _flora_layer_configs[layer_id]
		if not layer_value is Dictionary:
			push_error("flora layer 必须是 Dictionary: " + layer_id)
			return false
		var layer: Dictionary = layer_value
		var noise_field_id := String(layer.get("noise_field", ""))
		if (
			noise_field_id.is_empty()
			or not _noise_fields.has(noise_field_id)
		):
			push_error("flora layer 引用了未知 noise field [%s]: %s" % [layer_id, noise_field_id])
			return false
		var default_noise_above := float(layer.get("default_noise_above", 0.0))
		if default_noise_above < -1.0 or default_noise_above > 1.0:
			push_error("flora layer default_noise_above 必须在 -1..1: " + layer_id)
			return false
		var layer_dominant_chance := float(layer.get("dominant_chance", 0.8))
		if layer_dominant_chance < 0.0 or layer_dominant_chance > 1.0:
			push_error("flora layer dominant_chance 必须在 0..1: " + layer_id)
			return false

	var regions: Dictionary = generation.get("regions", {})
	_region_cell_size = float(regions.get("cell_size", _region_cell_size))
	_region_jitter = float(regions.get("jitter", _region_jitter))
	_region_blend_width = float(regions.get("blend_width", _region_blend_width))
	if _region_cell_size <= 0.0 or _region_blend_width <= 0.0 or _region_jitter < 0.0:
		push_error("generation.regions 的范围无效")
		return false
	_landform_configs.clear()
	_landform_configs.resize(LANDFORM_ID_TO_TYPE.size())
	_landform_ids.clear()
	_landform_ids.resize(LANDFORM_ID_TO_TYPE.size())
	_landform_names.clear()
	_landform_names.resize(LANDFORM_ID_TO_TYPE.size())
	for i in _landform_configs.size():
		_landform_configs[i] = {}
		_landform_ids[i] = ""
		_landform_names[i] = ""
	_landform_order.clear()
	_landform_total_weight = 0.0
	var seen_landforms := {}
	var landforms: Array = regions.get("landforms", [])
	for profile_value in landforms:
		var profile: Dictionary = profile_value
		var profile_id := String(profile.get("id", ""))
		if profile_id.is_empty():
			push_error("landform id 不能为空")
			return false
		if seen_landforms.has(profile_id):
			push_error("重复的 landform id: " + profile_id)
			return false
		seen_landforms[profile_id] = true
		var terrain: Dictionary = profile.get("terrain", {})
		var profile_weight := float(profile.get("weight", 0.0))
		if profile_weight <= 0.0:
			push_error("landform weight 必须大于 0: " + profile_id)
			return false
		var compiled := {
			"offset": float(terrain.get("offset", 0.0)),
			"amp": float(terrain.get("amplitude", 1.0)),
			"ridge": float(terrain.get("ridge", 0.0)),
			"steep": float(terrain.get("underwater_steepness", 1.0)),
			"peak": float(terrain.get("peak", 0.0)),
			"terrace": float(terrain.get("terrace", 0.0)),
			"weight": profile_weight,
		}
		_landform_total_weight += float(compiled["weight"])
		# 旧 enum 只作为现有规则/测试的适配边界；新 ID 完整保留在 TerrainSampler。
		if LANDFORM_ID_TO_TYPE.has(profile_id):
			var landform_type: int = LANDFORM_ID_TO_TYPE[profile_id]
			_landform_configs[landform_type] = compiled
			_landform_ids[landform_type] = profile_id
			_landform_names[landform_type] = String(profile.get("name_zh", profile_id))
			_landform_order.append(landform_type)
	for required_landform_id in LANDFORM_ID_TO_TYPE:
		if not seen_landforms.has(required_landform_id):
			push_error("生态配置缺少 legacy landform: " + String(required_landform_id))
			return false
	if _landform_total_weight <= 0.0:
		push_error("landform 总权重必须大于 0")
		return false

	var climate: Dictionary = generation.get("climate", {})
	var snow: Dictionary = climate.get("snow", {})
	_snow_base_level = int(snow.get("base_level", _snow_base_level))
	_snow_temperature_level_scale = float(snow.get("temperature_level_scale", _snow_temperature_level_scale))
	var species: Dictionary = _ecosystem_config.get("species", {})
	_plant_species = species.get("plants", {})
	_animal_species = species.get("animals", {})
	_ambient_species = species.get("ambient", {})
	if not _compile_animal_behavior_stacks():
		return false
	_ecosystems_by_id.clear()
	_ecosystem_order.clear()
	for ecosystem_value in _ecosystem_config.get("ecosystems", []):
		var ecosystem: Dictionary = ecosystem_value
		var ecosystem_id := String(ecosystem.get("id", ""))
		if ecosystem_id.is_empty() or _ecosystems_by_id.has(ecosystem_id):
			push_error("生态 id 为空或重复: " + ecosystem_id)
			return false
		_ecosystems_by_id[ecosystem_id] = ecosystem
		_ecosystem_order.append(ecosystem)
	if _ecosystem_order.is_empty():
		push_error("生态配置至少需要一个 ecosystem")
		return false
	_default_ecosystem_id = String(_ecosystem_config.get("default_ecosystem", ""))
	if _default_ecosystem_id.is_empty() or not _ecosystems_by_id.has(_default_ecosystem_id):
		push_error("default_ecosystem 必须引用已定义的生态: " + _default_ecosystem_id)
		return false
	_dominant_species_chance = float(
		(_ecosystem_config.get("pool_selection", {}) as Dictionary).get("dominant_chance", 0.8)
	)
	if _dominant_species_chance < 0.0 or _dominant_species_chance > 1.0:
		push_error("pool_selection.dominant_chance 必须在 0..1")
		return false
	return _validate_ecosystem_config()


func _compile_animal_behavior_stacks() -> bool:
	_animal_behavior_stacks.clear()
	_animal_behavior_tag_scan_radius = 1
	for animal_id_value in _animal_species:
		var animal_id := String(animal_id_value)
		var species: Dictionary = (_animal_species[animal_id_value] as Dictionary).duplicate(true)
		var movement_value: Variant = species.get("movement", {})
		var movement: Dictionary = (
			movement_value.duplicate(true) if movement_value is Dictionary else {}
		)
		if not species.has("allowed_surfaces") and not movement.has("allowed_surfaces"):
			movement["allowed_surfaces"] = ["land"]
		if not species.has("max_step_height") and not movement.has("max_step_height"):
			movement["max_step_height"] = 1
		species["movement"] = movement
		var stack: Array[Dictionary] = _animal_behavior_registry.behaviors_for_species(species)
		var has_flee := false
		for behavior in stack:
			var behavior_type := StringName(behavior.get("type", ""))
			if behavior_type == &"flee_player":
				has_flee = true
			elif behavior_type == &"near_tag":
				_animal_behavior_tag_scan_radius = maxi(
					_animal_behavior_tag_scan_radius,
					ceili(float(behavior.get(
						"query_radius",
						behavior.get("radius", behavior.get("max_distance", 1.0))
					)))
				)
			if not _animal_behavior_registry.has_scorer(behavior_type):
				push_error("动物引用了未注册行为 [%s]: %s" % [animal_id, behavior_type])
				return false
		if not has_flee:
			stack.append({
				"type": "flee_player",
				"radius": ANIMAL_FLEE_RADIUS,
				"speed_multiplier": ANIMAL_FLEE_SPEED,
				"weight": ANIMAL_FLEE_DISTANCE_WEIGHT,
			})
		_animal_behavior_stacks[animal_id] = stack
	return true


func _validate_ecosystem_config() -> bool:
	for plant_id in _plant_species:
		var plant: Dictionary = _plant_species[plant_id]
		var layer_id := String(plant.get("layer", ""))
		if layer_id not in FLORA_LAYER_IDS:
			push_error("植物缺少有效 layer [%s]: %s" % [plant_id, layer_id])
			return false
		var texture_path := String(plant.get("texture", ""))
		if texture_path.is_empty() or not ResourceLoader.exists(texture_path):
			push_error("植物资源不存在 [%s]: %s" % [plant_id, texture_path])
			return false
		var habitat_value: Variant = plant.get("habitat", {})
		if not habitat_value is Dictionary:
			push_error("植物 habitat 必须是 Dictionary [%s]" % plant_id)
			return false
		var habitat: Dictionary = habitat_value
		if not habitat.is_empty():
			var near_layer := String(habitat.get("near_flora_layer", ""))
			var radius := int(habitat.get("radius", 0))
			var fallback_species := String(habitat.get("fallback_species", ""))
			if near_layer not in FLORA_LAYER_IDS or radius < 1 or radius > 8:
				push_error("植物 habitat 邻近层或半径无效 [%s]" % plant_id)
				return false
			if not _plant_species.has(fallback_species):
				push_error("植物 habitat fallback 不存在 [%s]: %s" % [
					plant_id, fallback_species
				])
				return false
			var fallback: Dictionary = _plant_species[fallback_species]
			if String(fallback.get("layer", "")) != layer_id:
				push_error("植物 habitat fallback 必须与原物种同层 [%s]" % plant_id)
				return false
			if not (fallback.get("habitat", {}) as Dictionary).is_empty():
				push_error("植物 habitat fallback 不能继续声明 habitat [%s]" % plant_id)
				return false
	for animal_id in _animal_species:
		var animal: Dictionary = _animal_species[animal_id]
		var directory := String(animal.get("directory", ""))
		var actions: Dictionary = animal.get("actions", {})
		if actions.is_empty():
			push_error("动物缺少 actions: " + String(animal_id))
			return false
		for action_id in actions:
			var action: Dictionary = actions[action_id]
			var action_file := String(action.get("file", ""))
			var texture_path := directory.path_join(action_file)
			if directory.is_empty() or action_file.is_empty():
				push_error("动物动作缺少目录或文件 [%s/%s]" % [animal_id, action_id])
				return false
			if not ResourceLoader.exists(texture_path):
				push_error("动物动作资源不存在 [%s/%s]: %s" % [animal_id, action_id, texture_path])
				return false
			if float(action.get("fps", 1.0)) <= 0.0:
				push_error("动物动作 fps 必须大于 0 [%s/%s]" % [animal_id, action_id])
				return false
			if action.has("frame_size"):
				var frame_size_value: Variant = action["frame_size"]
				if (
					not frame_size_value is Array
					or frame_size_value.size() != 2
					or int(frame_size_value[0]) <= 0
					or int(frame_size_value[1]) <= 0
					or int(action.get("columns", 0)) <= 0
					or int(action.get("frames", 0)) <= 0
				):
					push_error("动物图集参数无效 [%s/%s]" % [animal_id, action_id])
					return false
				var frame_width := int(frame_size_value[0])
				var frame_height := int(frame_size_value[1])
				var columns := int(action["columns"])
				var frame_count := int(action["frames"])
				var rows := ceili(frame_count / float(columns))
				var texture: Texture2D = load(texture_path)
				if columns * frame_width > texture.get_width() or rows * frame_height > texture.get_height():
					push_error("动物图集范围超出图片 [%s/%s]" % [animal_id, action_id])
					return false
		var behavior := String(animal.get("behavior", "wander"))
		if (
			not animal.has("behaviors")
			and behavior not in ["wander", "near_water", "avoid_snow", "prefer_snow"]
		):
			push_error("未知动物行为 [%s]: %s" % [animal_id, behavior])
			return false
		var foot_offset_y := float(animal.get("foot_offset_y", 0.0))
		if foot_offset_y < 0.0 or foot_offset_y > 128.0:
			push_error("动物 foot_offset_y 必须在 0..128 [%s]" % animal_id)
			return false
		var movement: Dictionary = animal.get("movement", {})
		var idle_action := String(movement.get("idle_action", "idle"))
		var move_action := String(movement.get("move_action", idle_action))
		if not actions.has(idle_action) or not actions.has(move_action):
			push_error("动物 movement 引用了未知动作 [%s]: %s / %s" % [animal_id, idle_action, move_action])
			return false
		if float(movement.get("duration", 0.0)) <= 0.0:
			push_error("动物 movement.duration 必须大于 0 [%s]" % animal_id)
			return false
		if (
			movement.has("move_steps")
			and not _numeric_range_is_valid(movement["move_steps"], 1.0, true)
		):
			push_error("动物 move_steps 必须是递增正整数范围 [%s]" % animal_id)
			return false
		if (
			movement.has("step_pause_seconds")
			and not _numeric_range_is_valid(movement["step_pause_seconds"], 0.0, false)
		):
			push_error("动物 step_pause_seconds 必须是非负递增范围 [%s]" % animal_id)
			return false
		if movement.has("sort_switch_progress"):
			var switch_progress := float(movement["sort_switch_progress"])
			if switch_progress < 0.0 or switch_progress > 1.0:
				push_error("动物 sort_switch_progress 必须在 0..1 [%s]" % animal_id)
				return false
	for ambient_id in _ambient_species:
		var ambient: Dictionary = _ambient_species[ambient_id]
		var cluster_size: Variant = ambient.get("cluster_size", [1, 1])
		if (
			not cluster_size is Array
			or cluster_size.size() != 2
			or int(cluster_size[0]) <= 0
			or int(cluster_size[1]) < int(cluster_size[0])
		):
			push_error("环境生物 cluster_size 无效 [%s]" % ambient_id)
			return false
		if int(ambient.get("max_visible", 1)) <= 0:
			push_error("环境生物 max_visible 必须大于 0 [%s]" % ambient_id)
			return false
		if int(ambient.get("max_lights", 0)) < 0:
			push_error("环境生物 max_lights 不能小于 0 [%s]" % ambient_id)
			return false
	for ecosystem in _ecosystem_order:
		var ecosystem_id := String(ecosystem["id"])
		var match_value: Variant = ecosystem.get("match", {})
		if not match_value is Dictionary:
			push_error("生态 match 必须是 Dictionary [%s]" % ecosystem_id)
			return false
		if not _validate_ecosystem_match(match_value, ecosystem_id):
			return false
		var seen_flora_pool_ids := {}
		var seen_fauna_pool_ids := {}
		for rule_kind in ["flora", "fauna", "ambient"]:
			var rules_value: Variant = ecosystem.get(rule_kind, [])
			if not rules_value is Array:
				push_error("生态规则必须是数组 [%s/%s]" % [ecosystem_id, rule_kind])
				return false
			var catalog: Dictionary
			match rule_kind:
				"flora":
					catalog = _plant_species
				"fauna":
					catalog = _animal_species
				_:
					catalog = _ambient_species
			for rule_value in rules_value:
				if not rule_value is Dictionary:
					push_error("生态规则必须是 Dictionary [%s/%s]" % [ecosystem_id, rule_kind])
					return false
				var rule: Dictionary = rule_value
				if not _chance_value_is_valid(rule.get("chance", 0.0)):
					push_error("生态生成概率必须在 0..1 [%s/%s]" % [ecosystem_id, rule_kind])
					return false
				var pool_value: Variant = rule.get("species", [])
				if not pool_value is Array or pool_value.is_empty():
					push_error("生态物种池不能为空 [%s/%s]" % [ecosystem_id, rule_kind])
					return false
				for species_id_value in pool_value:
					var species_id := String(species_id_value)
					if not catalog.has(species_id):
						push_error("生态引用了未知物种 [%s/%s]: %s" % [ecosystem_id, rule_kind, species_id])
						return false
				if rule_kind == "flora":
					var layer_id := String(rule.get("layer", ""))
					if layer_id not in FLORA_LAYER_IDS:
						push_error("flora rule 缺少有效 layer [%s]: %s" % [ecosystem_id, layer_id])
						return false
					var pool_id := String(rule.get("pool_id", ""))
					if pool_id.is_empty() or seen_flora_pool_ids.has(pool_id):
						push_error("flora pool_id 为空或重复 [%s]: %s" % [ecosystem_id, pool_id])
						return false
					seen_flora_pool_ids[pool_id] = true
					for species_id_value in pool_value:
						var species_id := String(species_id_value)
						var plant: Dictionary = _plant_species[species_id]
						if String(plant.get("layer", "")) != layer_id:
							push_error(
								"flora rule 与物种 layer 不一致 [%s/%s]: %s"
								% [ecosystem_id, layer_id, species_id]
							)
							return false
					var layer: Dictionary = _flora_layer_configs[layer_id]
					var noise_above := float(
						rule.get("noise_above", layer.get("default_noise_above", 0.0))
					)
					if noise_above < -1.0 or noise_above > 1.0:
						push_error("flora noise_above 必须在 -1..1 [%s/%s]" % [ecosystem_id, pool_id])
						return false
					if float(rule.get("conflict_weight", 1.0)) <= 0.0:
						push_error("flora conflict_weight 必须大于 0 [%s/%s]" % [ecosystem_id, pool_id])
						return false
					var placement := String(rule.get("placement", "ground"))
					if placement not in ["ground", "lakebed", "water_surface"]:
						push_error("未知植物放置方式 [%s]: %s" % [ecosystem_id, placement])
						return false
				elif rule_kind == "fauna":
					var fauna_pool_id := String(rule.get("pool_id", ""))
					if fauna_pool_id.is_empty() or seen_fauna_pool_ids.has(fauna_pool_id):
						push_error("fauna pool_id 为空或重复 [%s]: %s" % [ecosystem_id, fauna_pool_id])
						return false
					seen_fauna_pool_ids[fauna_pool_id] = true
					if not _validate_fauna_distribution(rule, ecosystem_id, fauna_pool_id):
						return false
	for later_index in range(1, _ecosystem_order.size()):
		var later_ecosystem: Dictionary = _ecosystem_order[later_index]
		var later_match: Dictionary = later_ecosystem.get("match", {})
		for earlier_index in later_index:
			var earlier_ecosystem: Dictionary = _ecosystem_order[earlier_index]
			var earlier_match: Dictionary = earlier_ecosystem.get("match", {})
			if _ecosystem_match_subsumes(earlier_match, later_match):
				push_error(
					"生态 [%s] 被前面的规则 [%s] 完全遮蔽"
					% [String(later_ecosystem["id"]), String(earlier_ecosystem["id"])]
				)
				return false
	return true


func _validate_fauna_distribution(
	rule: Dictionary,
	ecosystem_id: String,
	pool_id: String
) -> bool:
	var distribution_value: Variant = rule.get("distribution", {})
	if not distribution_value is Dictionary:
		push_error("fauna distribution 必须是 Dictionary [%s/%s]" % [ecosystem_id, pool_id])
		return false
	var distribution: Dictionary = distribution_value
	if rule.has("only_if_flora_missed") and not rule["only_if_flora_missed"] is bool:
		push_error("fauna only_if_flora_missed 必须是 bool [%s/%s]" % [ecosystem_id, pool_id])
		return false
	if int(distribution.get("anchor_spacing", 0)) <= 0:
		push_error("fauna anchor_spacing 必须大于 0 [%s/%s]" % [ecosystem_id, pool_id])
		return false
	var anchor_jitter := float(distribution.get("anchor_jitter", 1.0))
	if anchor_jitter < 0.0 or anchor_jitter > 1.0:
		push_error("fauna anchor_jitter 必须在 0..1 [%s/%s]" % [ecosystem_id, pool_id])
		return false
	if not _numeric_range_is_valid(distribution.get("count", []), 1.0, true):
		push_error("fauna count 必须是递增正整数范围 [%s/%s]" % [ecosystem_id, pool_id])
		return false
	if int(distribution.get("radius", -1)) < 0:
		push_error("fauna radius 不能小于 0 [%s/%s]" % [ecosystem_id, pool_id])
		return false
	if float(distribution.get("social_radius", 0.0)) < 0.0:
		push_error("fauna social_radius 不能小于 0 [%s/%s]" % [ecosystem_id, pool_id])
		return false
	if int(distribution.get("requires_water_within", 0)) < 0:
		push_error("fauna requires_water_within 不能小于 0 [%s/%s]" % [ecosystem_id, pool_id])
		return false
	if distribution.has("same_ecosystem") and not distribution["same_ecosystem"] is bool:
		push_error("fauna same_ecosystem 必须是 bool [%s/%s]" % [ecosystem_id, pool_id])
		return false
	var substitution_value: Variant = distribution.get("substitution", {})
	if substitution_value is Dictionary and not substitution_value.is_empty():
		var substitution: Dictionary = substitution_value
		var substitute_species := String(substitution.get("species", ""))
		if not _animal_species.has(substitute_species):
			push_error("fauna substitution 引用了未知动物 [%s/%s]: %s" % [
				ecosystem_id, pool_id, substitute_species
			])
			return false
		if not _chance_value_is_valid(substitution.get("chance", -1.0)):
			push_error("fauna substitution chance 无效 [%s/%s]" % [ecosystem_id, pool_id])
			return false
		if int(substitution.get("max_count", 0)) <= 0:
			push_error("fauna substitution max_count 必须大于 0 [%s/%s]" % [ecosystem_id, pool_id])
			return false
	elif not substitution_value is Dictionary:
		push_error("fauna substitution 必须是 Dictionary [%s/%s]" % [ecosystem_id, pool_id])
		return false
	return true


func _validate_ecosystem_match(match_rule: Dictionary, ecosystem_id: String) -> bool:
	var allowed_keys := [
		"water",
		"shore",
		"biome",
		"landform",
		"minimum_level",
		"maximum_level",
	]
	for key_value in match_rule:
		var key := String(key_value)
		if key not in allowed_keys:
			push_error("生态 match 包含未知字段 [%s]: %s" % [ecosystem_id, key])
			return false
	for key in ["water", "shore"]:
		if match_rule.has(key) and not match_rule[key] is bool:
			push_error("生态 match.%s 必须是 bool [%s]" % [key, ecosystem_id])
			return false
	if match_rule.has("biome"):
		var biome_value: Variant = match_rule["biome"]
		var biome_ids: Array = biome_value if biome_value is Array else [biome_value]
		if biome_ids.is_empty():
			push_error("生态 match.biome 不能为空 [%s]" % ecosystem_id)
			return false
		for biome_id_value in biome_ids:
			if String(biome_id_value).is_empty():
				push_error("生态 match.biome 包含空 ID [%s]" % ecosystem_id)
				return false
	if match_rule.has("landform"):
		var landform_value: Variant = match_rule["landform"]
		var landform_ids: Array = landform_value if landform_value is Array else [landform_value]
		if landform_ids.is_empty():
			push_error("生态 match.landform 不能为空 [%s]" % ecosystem_id)
			return false
		for landform_id_value in landform_ids:
			if String(landform_id_value).is_empty():
				push_error("生态 match.landform 包含空 ID [%s]" % ecosystem_id)
				return false
	for key in ["minimum_level", "maximum_level"]:
		if match_rule.has(key) and not (match_rule[key] is int or match_rule[key] is float):
			push_error("生态 match.%s 必须是数字 [%s]" % [key, ecosystem_id])
			return false
	if (
		match_rule.has("minimum_level")
		and match_rule.has("maximum_level")
		and int(match_rule["minimum_level"]) > int(match_rule["maximum_level"])
	):
		push_error("生态 minimum_level 不能大于 maximum_level [%s]" % ecosystem_id)
		return false
	return true


## earlier 的匹配集合完全包含 later 时，later 永远不会被 first-match 选中。
func _ecosystem_match_subsumes(earlier: Dictionary, later: Dictionary) -> bool:
	for key in ["water", "shore", "biome"]:
		if earlier.has(key) and (not later.has(key) or earlier[key] != later[key]):
			return false
	if earlier.has("landform"):
		if not later.has("landform"):
			return false
		var earlier_value: Variant = earlier["landform"]
		var later_value: Variant = later["landform"]
		var earlier_ids: Array = earlier_value if earlier_value is Array else [earlier_value]
		var later_ids: Array = later_value if later_value is Array else [later_value]
		for landform_id in later_ids:
			if not earlier_ids.has(landform_id):
				return false
	if earlier.has("minimum_level"):
		if not later.has("minimum_level") or int(earlier["minimum_level"]) > int(later["minimum_level"]):
			return false
	if earlier.has("maximum_level"):
		if not later.has("maximum_level") or int(earlier["maximum_level"]) < int(later["maximum_level"]):
			return false
	return true


func _chance_value_is_valid(value: Variant) -> bool:
	if value is float or value is int:
		var chance := float(value)
		return chance >= 0.0 and chance <= 1.0
	if not value is Dictionary or value.is_empty():
		return false
	for chance_value in value.values():
		if not (chance_value is float or chance_value is int):
			return false
		var chance := float(chance_value)
		if chance < 0.0 or chance > 1.0:
			return false
	return true


func _numeric_range_is_valid(value: Variant, minimum: float, integers_only: bool) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for item in value:
		if not (item is float or item is int):
			return false
		var number := float(item)
		if number < minimum or (integers_only and not is_equal_approx(number, roundf(number))):
			return false
	return float(value[1]) >= float(value[0])


func _noise_type_from_name(value: String) -> int:
	match value.to_lower():
		"simplex":
			return FastNoiseLite.TYPE_SIMPLEX
		"simplex_smooth":
			return FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		"value":
			return FastNoiseLite.TYPE_VALUE
		"value_cubic":
			return FastNoiseLite.TYPE_VALUE_CUBIC
		_:
			return FastNoiseLite.TYPE_PERLIN


func _fractal_type_from_name(value: String) -> int:
	match value.to_lower():
		"ridged":
			return FastNoiseLite.FRACTAL_RIDGED
		"ping_pong":
			return FastNoiseLite.FRACTAL_PING_PONG
		_:
			return FastNoiseLite.FRACTAL_FBM


func _noise_instance_for_field(field_id: String) -> FastNoiseLite:
	if _terrain_sampler != null and _terrain_sampler.noise_registry != null:
		var registered: FastNoiseLite = _terrain_sampler.noise_registry.get_field(
			StringName(field_id)
		)
		if registered != null:
			return registered
	push_error("未知 noise field: " + field_id)
	return null


## 迁移期兼容旧契约/调试入口；这些引用和 TerrainSampler 共用同一批动态 noise 实例。
## 新 biome 的字段无需在此列出，它们直接通过 NoiseRegistry 按 ID 查询。
func _sync_legacy_noise_handles() -> void:
	_tree_placement = _terrain_sampler.noise_registry.get_field(&"tree_placement")
	_ground_cover_placement = _terrain_sampler.noise_registry.get_field(
		&"ground_cover_placement"
	)
	_decoration_placement = _terrain_sampler.noise_registry.get_field(
		&"decoration_placement"
	)


func _ready() -> void:
	if not _load_ecosystem_config():
		set_process(false)
		set_process_unhandled_input(false)
		return
	y_sort_enabled = true  # 每根地块柱用合成脚点深度排序；柱内内容由批绘制器固定顺序
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_water_tex = _make_water_face_texture(&"surface")
	_water_left_tex = _make_water_face_texture(&"left")
	_water_right_tex = _make_water_face_texture(&"right")
	_rock_tex = _terrain_materials.get_texture(&"rock")
	_rock_grass_tex = _terrain_materials.get_texture(&"rock_grass")
	_moss_tex = _terrain_materials.get_texture(&"mossy_rock")
	_soil_tex = _terrain_materials.get_texture(&"soil")
	_moist_tex = _terrain_materials.get_texture(&"moist_soil")
	_parched_tex = _terrain_materials.get_texture(&"parched_soil")
	_sand_tex = _terrain_materials.get_texture(&"sand")
	_underwater_texture_cache.clear()
	_grass_tex = _terrain_materials.get_texture(&"grass")
	_little_grass_tex = _terrain_materials.get_texture(&"sparse_grass")
	_snow_tex = _terrain_materials.get_texture(&"snow")
	_setup_player()
	_setup_camera()
	_setup_depth_of_field()
	_setup_day_night()
	_setup_audio()
	_setup_fireflies()
	_setup_weather()
	_setup_hud()
	_setup_minimap()
	_setup_world_map()
	var args := OS.get_cmdline_user_args()
	var si := args.find("--seed")
	if si != -1 and si + 1 < args.size():
		seed = int(args[si + 1])
	var shot_cell_arg := args.find("--shot-cell")
	if shot_cell_arg != -1 and shot_cell_arg + 2 < args.size():
		_player_cell = Vector2i(
			int(args[shot_cell_arg + 1]),
			int(args[shot_cell_arg + 2])
		)
	_regenerate(seed)
	if "--shot" in OS.get_cmdline_user_args():
		_shot_and_quit()


func _regenerate(new_seed: int) -> void:
	if _battle_active:
		return  # 战斗中禁止重生成（避免战场 cell 被 free）
	if _world_map != null:
		_world_map.close_map()
	_current_seed = new_seed if new_seed != 0 else (randi() & 0x7FFFFFFF)
	_world_rng.world_seed = _current_seed
	if _audio != null:
		_audio.reset_world(_current_seed)
	if _terrain_sampler != null:
		_terrain_sampler.reseed(_current_seed)
		_sync_legacy_noise_handles()
	_clear_animals()
	if _ambient_registry != null:
		_ambient_registry.clear_all()
	for cell in _cells.keys():
		_free_cell(cell)
	_player_occluder_cells.clear()
	_player_occlusion_fading_cells.clear()
	_player_occlusion_dirty = true
	_explored.clear()
	_sort_origin = _player_cell
	_has_sort_origin = true
	_stream_center = _player_cell
	_update_streaming()
	_move_from_cell = _player_cell
	_player_visual_position = _cell_feet_pos(_player_cell)
	_move_from = _player_visual_position
	_move_to = _player_visual_position
	_move_sort_from = _column_sort_y(_player_cell) + PLAYER_SORT_BIAS
	_move_sort_to = _move_sort_from
	_move_level_from = _stand_level(_quantize(_player_cell.x, _player_cell.y))
	_move_level_to = _move_level_from
	_set_player_render_position(_player_visual_position, _move_sort_to)
	_move_t = 1.0
	_update_player_occlusion(0.0)
	_snap_camera_position(_player_visual_position)
	_reveal()
	_update_minimap()
	var args := OS.get_cmdline_user_args()
	if "--stats" in args or "--dump" in args:
		_print_stats()
	_sync_weather_environment()
	if _weather != null:
		_weather.refresh_particle_field()


# ---------- 地形生成 ----------

func _sample_cell_context(cell: Vector2i):
	var context = _terrain_sampler.sample(cell)
	if _terrain_materials == null:
		return context
	var material: Dictionary = _terrain_materials.resolve(
		context.surface_id,
		context.biome_id
	)
	for tag_value in material.get("tags", []):
		context.add_tag(StringName(tag_value))
	return context

## 整数 hash（lowbias32），用于 Voronoi 种子点的确定性随机
func _hash_u32(v: int) -> int:
	return DeterministicRngScript.hash_u32(v)


func _cell_rand(gc: Vector2i, salt: int) -> float:
	# 保留 legacy salt 可确保现有固定种子世界逐格不变；新模块使用命名 stream。
	return _world_rng.cell_float(gc, &"legacy", salt)


## 每个 Voronoi 网格一个抖动的种子点
func _seed_point(gc: Vector2i) -> Vector2:
	return _terrain_sampler.seed_point(gc)


## 每个种子点按权重随机一种地貌
func _landform_type(gc: Vector2i) -> int:
	return _terrain_sampler.landform_index_for_region(gc)


## Voronoi 查询：返回 [最近地貌, 次近地貌, 次近权重 w2, 最近种子点网格]。
## w2 由 F2-F1 距离在过渡带内从 0 渐变到 0.5，参数按它混合 —— 这就是群落间的衔接算法
func _voronoi(x: int, y: int) -> Array:
	return _terrain_sampler.voronoi(Vector2i(x, y))


## 混合后的模块参数：[主地貌, offset, amp, ridge, steep, peak, terrace, 种子点网格]
func _modules(x: int, y: int) -> Array:
	var values: Array = _terrain_sampler.modules(Vector2i(x, y))
	var landform_id: StringName = _terrain_sampler.landform_id_for_index(
		int(values[0])
	)
	# 旧生态规则仍使用数值 enum；TerrainSampler/CellContext 内部只使用动态 ID。
	values[0] = int(LANDFORM_ID_TO_TYPE.get(String(landform_id), Landform.PLAINS))
	return values


## 量化：全局基线/细节噪声为底，当前位置的模块参数做增强/削弱/变体。
## 正常地形 [0, LEVELS)，独立山峰层按模块 peak 权重叠加、可突破 15 层上限
func _quantize(x: int, y: int) -> int:
	return _terrain_sampler.quantize(Vector2i(x, y))


## 群系判定：低频区域场先划出连续沙漠与泥土过渡带，其余区域再按海拔判定雪原。
func _biome(x: int, y: int, q: int) -> int:
	var biome_id: StringName = _terrain_sampler.biome_id(Vector2i(x, y), q)
	return _terrain_sampler.biome_index(biome_id)


func _print_stats() -> void:
	var hist := {}
	var bhist := {}
	var lhist := {}
	for cell in _cells:
		var q := _quantize(cell.x, cell.y)
		hist[q] = hist.get(q, 0) + 1
		var b := _biome(cell.x, cell.y, q)
		bhist[b] = bhist.get(b, 0) + 1
		var lf: int = _modules(cell.x, cell.y)[0]
		var landform_name := _landform_names[lf]
		lhist[landform_name] = lhist.get(landform_name, 0) + 1
	print(
		"层数分布(0-15+): ", hist,
		" 群系(0平原/1沙漠/2雪原/3沙漠过渡): ", bhist,
		" 地貌: ", lhist
	)
	if "--dump" in OS.get_cmdline_user_args():
		# 字符地图：~水 b泥滩 g平原 D沙漠 d沙漠过渡 S雪原
		var biome_chars := {
			BIOME_PLAINS: "g",
			BIOME_DESERT: "D",
			BIOME_SNOW: "S",
			BIOME_DESERT_TRANSITION: "d",
		}
		var lines := ""
		for y in range(_player_cell.y - stream_extent, _player_cell.y + stream_extent + 1):
			var row := ""
			for x in range(_player_cell.x - stream_extent, _player_cell.x + stream_extent + 1):
				var q := _quantize(x, y)
				if q <= WATER_MAX:
					row += "~"
				elif _is_beach(Vector2i(x, y), q):
					row += "b"
				else:
					row += String(biome_chars.get(_biome(x, y, q), "?"))
			lines += row + "\n"
		print(lines)


## 生成一格：湖底仍是实心柱；水体只保留一张连续顶面，岸线侧壁按深度逐层拼接。
## 相邻水格之间的内部侧面会被剔除，深水感由湖底细节衰减表达，不再堆透明完整方块。
func _spawn_cell(cell: Vector2i) -> void:
	var context = _sample_cell_context(cell)
	var q: int = context.height
	var state = CellStateScript.new(context)
	_cell_states[cell] = state
	var blocks: Array[Dictionary] = state.render_blocks
	var water_depth := WATER_SURFACE_LEVEL - q
	for level in q + 1:
		var solid_texture := _solid_tex(q, level, cell, context)
		if q <= WATER_MAX:
			solid_texture = _underwater_texture_for_context(context, water_depth)
		blocks.append(_render_block(solid_texture, level))
	if q <= WATER_MAX:
		_append_water_volume(cell, q, blocks)
	_spawn_flora(
		cell,
		q,
		int(LANDFORM_ID_TO_TYPE.get(
			String(context.landform_id),
			Landform.PLAINS
		)),
		context.region_anchor,
		state
	)
	for serial in blocks.size():
		blocks[serial]["serial"] = serial
	blocks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) < int(b["level"])
		if int(a["render_priority"]) != int(b["render_priority"]):
			return int(a["render_priority"]) < int(b["render_priority"])
		return int(a["serial"]) < int(b["serial"])
	)
	var view: Node2D = ColumnBatchScript.new()
	_cells[cell] = view
	if q <= WATER_MAX:
		_water_cells[cell] = true
	add_child(view)
	view.configure(cell, state.render_blocks, _grid_to_screen(cell), _column_sort_y(cell), LEVEL_H)
	_spawn_ambient_for_cell(
		cell,
		q,
		int(LANDFORM_ID_TO_TYPE.get(
			String(context.landform_id),
			Landform.PLAINS
		)),
		context.region_anchor,
		state,
		view
	)
	_player_occlusion_dirty = true


func _append_water_volume(cell: Vector2i, lakebed_level: int, blocks: Array) -> void:
	# +x 位于屏幕右下、+y 位于左下；只有朝向非水邻格的前侧面可能暴露。
	var expose_right := _quantize(cell.x + 1, cell.y) > WATER_MAX
	var expose_left := _quantize(cell.x, cell.y + 1) > WATER_MAX
	for level in range(lakebed_level + 1, WATER_SURFACE_LEVEL + 1):
		if expose_left:
			blocks.append(_water_block(_water_left_tex, level, WATER_SIDE_ALPHA, &"left_side"))
		if expose_right:
			blocks.append(_water_block(_water_right_tex, level, WATER_SIDE_ALPHA, &"right_side"))
	# 顶面只画一次，所有水格在同一个水位无缝拼接；透明像素不会重复覆盖。
	var surface_block := _water_block(
		_water_tex,
		WATER_SURFACE_LEVEL,
		WATER_SURFACE_ALPHA,
		&"surface"
	)
	var shore_edges := 0
	if _quantize(cell.x - 1, cell.y) > WATER_MAX:
		shore_edges |= 1
	if _quantize(cell.x, cell.y - 1) > WATER_MAX:
		shore_edges |= 2
	if expose_right:
		shore_edges |= 4
	if expose_left:
		shore_edges |= 8
	surface_block["shore_edges"] = shore_edges
	surface_block["shore_seed"] = _hash_u32(
		cell.x * 0x8da6b343 ^ cell.y * 0xd8163841 ^ _current_seed
	)
	blocks.append(surface_block)


func _water_block(texture: Texture2D, level: int, alpha: float, part: StringName) -> Dictionary:
	var block := _render_block(texture, level, Color(1.0, 1.0, 1.0, alpha), 1)
	block["water_part"] = part
	block["occluder_class"] = &"none"
	return block


func _render_block(
	tex: Texture2D,
	level: int,
	modulate := Color.WHITE,
	render_priority := 0,
	render_offset := Vector2.ZERO,
	occluder_class := &"terrain"
) -> Dictionary:
	return {
		"level": level,
		"texture": tex,
		"modulate": modulate,
		"render_priority": render_priority,
		"render_offset": render_offset,
		"occluder_class": occluder_class,
	}


func _free_cell(cell: Vector2i) -> void:
	_player_occluder_cells.erase(cell)
	_player_occlusion_fading_cells.erase(cell)
	_player_occlusion_dirty = true
	if _ambient_registry != null:
		_ambient_registry.remove_cell_all(cell)
	_cell_states.erase(cell)
	if not _cells.has(cell):
		return
	var view: Node2D = _cells[cell]
	_cells.erase(cell)
	_water_cells.erase(cell)
	if is_instance_valid(view):
		remove_child(view)
		view.queue_free()


## 逻辑坐标中的方形流式窗口，经标准等距投影后就是画面中的菱形视窗。
var _stream_center := Vector2i.ZERO


func _update_streaming() -> void:
	if _battle_active:
		return  # 战斗中冻结流式（战场 cell 不被释放/生成）
	# Habitat 邻近查询只在一次流式批次内复用，避免无限世界探索时缓存无界增长。
	_ecology_near_tag_cache.clear()
	_spatial_flora_plan_cache.clear()
	_raw_selected_flora_cache.clear()
	_ensure_sort_origin(_stream_center)
	for cell in _cells.keys():
		if not _in_stream(cell, _stream_center):
			_free_cell(cell)
	for y in range(_stream_center.y - stream_extent, _stream_center.y + stream_extent + 1):
		for x in range(_stream_center.x - stream_extent, _stream_center.x + stream_extent + 1):
			var cell := Vector2i(x, y)
			if not _cells.has(cell):
				_spawn_cell(cell)
	# 所有地块与静态生态对象完成后再生成动物群，避免群成员落在尚未加载的树木或装饰上。
	_spawn_fauna_for_stream()
	_cleanup_streamed_animals()
	if _ambient_registry != null:
		_ambient_registry.refresh_all()


func _in_stream(cell: Vector2i, center: Vector2i) -> bool:
	return absi(cell.x - center.x) <= stream_extent and absi(cell.y - center.y) <= stream_extent


func _grid_to_screen(cell: Vector2i, level := 0.0) -> Vector2:
	return _iso_view.grid_to_screen(cell, level)


func _column_sort_y(cell: Vector2i) -> float:
	var sort_cell := cell - _sort_origin
	# 投影 y 决定前后关系；量化后用投影 x 做稳定的同深度次序。
	# 排序键只用于合成，真实脚点仍由 _grid_to_screen 独立计算。
	var projected := _iso_view.grid_to_screen(sort_cell)
	var depth := snappedf(_iso_view.get_depth_key(sort_cell), 0.001)
	var tie_break := clampf(projected.x * 0.001, -0.25, 0.25)
	return depth * SORT_DEPTH_SCALE + tie_break


func _continuous_view_rotation() -> int:
	if _battle_active or is_world_map_open():
		return 0
	var counterclockwise := (
		Input.is_physical_key_pressed(KEY_Q)
		or Input.is_physical_key_pressed(KEY_LEFT)
	)
	var clockwise := (
		Input.is_physical_key_pressed(KEY_E)
		or Input.is_physical_key_pressed(KEY_RIGHT)
	)
	return int(clockwise) - int(counterclockwise)


## 角度变化只改变表现层坐标；地形采样、生态状态和确定性随机流保持不动。
func _refresh_view_projection() -> void:
	var previous_player_position := _player_visual_position
	for cell_value in _cells.keys():
		var cell: Vector2i = cell_value
		var view: Node2D = _cells[cell]
		view.update_sort_position(_grid_to_screen(cell), _column_sort_y(cell))
	if _player != null:
		if _move_t >= 1.0:
			_move_from_cell = _player_cell
			_move_level_from = _move_level_to
		_move_from = _grid_to_screen(_move_from_cell, _move_level_from)
		_move_to = _grid_to_screen(_player_cell, _move_level_to)
		_player_visual_position = _move_from.lerp(_move_to, clampf(_move_t, 0.0, 1.0))
		_move_sort_from = _column_sort_y(_move_from_cell) + PLAYER_SORT_BIAS
		_move_sort_to = _column_sort_y(_player_cell) + PLAYER_SORT_BIAS
		_set_player_render_position(_player_visual_position, _player_movement_sort_y())
	for animal_value in _animals.values():
		var animal: AnimatedSprite2D = animal_value
		if not is_instance_valid(animal):
			continue
		animal.reproject(
			_cell_feet_pos(animal.from_cell),
			_cell_feet_pos(animal.target_cell),
			_column_sort_y(animal.from_cell) + ANIMAL_SORT_BIAS,
			_column_sort_y(animal.target_cell) + ANIMAL_SORT_BIAS
		)
	_player_occlusion_dirty = true
	# 保留相机相对玩家的平移量，旋转不会把视野突然甩到世界原点。
	if _cam != null:
		var focus_delta := _player_visual_position - previous_player_position
		_camera_smooth_position += focus_delta
		_battle_focus_world_pos += focus_delta
		_set_camera_position(_camera_smooth_position)


func _ensure_sort_origin(near_cell: Vector2i) -> void:
	if not _has_sort_origin:
		_sort_origin = near_cell
		_has_sort_origin = true
		return
	var distance := near_cell - _sort_origin
	if absi(distance.x) < SORT_REBASE_DISTANCE and absi(distance.y) < SORT_REBASE_DISTANCE:
		return
	_sort_origin = near_cell
	for cell_value in _cells.keys():
		var cell: Vector2i = cell_value
		var view: Node2D = _cells[cell]
		view.update_sort_position(_grid_to_screen(cell), _column_sort_y(cell))
	_player_occlusion_dirty = true
	_move_sort_from = _column_sort_y(_move_from_cell) + PLAYER_SORT_BIAS
	_move_sort_to = _column_sort_y(_player_cell) + PLAYER_SORT_BIAS
	_set_player_render_position(
		_player_visual_position,
		_player_movement_sort_y()
	)
	for animal_value in _animals.values():
		var animal: AnimatedSprite2D = animal_value
		if not is_instance_valid(animal):
			continue
		animal.rebase_sort(
			_column_sort_y(animal.from_cell) + ANIMAL_SORT_BIAS,
			_column_sort_y(animal.target_cell) + ANIMAL_SORT_BIAS
		)


## 只有贴着水面的最低陆地才是泥滩（平坦平原不再整片变土色）
func _is_beach(cell: Vector2i, q: int) -> bool:
	return _terrain_sampler.is_shore(cell, q)


## 实心柱第 level 层的材质：q 为柱顶所在层号
func _solid_tex(
	q: int,
	level: int,
	cell: Vector2i,
	cell_context = null
) -> Texture2D:
	if q <= WATER_MAX:
		return _moist_tex  # 河底/湖底用湿土
	var context = cell_context if cell_context != null else _terrain_sampler.sample(cell)
	var surface_id: StringName = context.surface_id
	var biome_id: StringName = context.biome_id
	# 保留当前高山苔石的确定性整柱变体；它也是一个注册材质，不再是 preload 特例。
	if (
		surface_id == &"rock"
		and biome_id not in [&"desert", &"desert_transition"]
		and q >= 15
		and _cell_rand(cell, 77) < 0.4
	):
		return _terrain_materials.get_texture(&"mossy_rock", &"top", biome_id)
	# 当前温带柱壁曾有少量稀草纹理，继续保留该视觉随机流；其他（包括未来新增）
	# surface 直接使用自身声明的 top/column 材质，无需在这里增加 biome 分支。
	if level < q and surface_id in [&"grass", &"rock_grass", &"moist_soil"]:
		return _soil_or_little_grass(cell, level)
	var role := &"top" if level == q else &"column"
	var texture: Texture2D = _terrain_materials.get_texture(
		surface_id,
		role,
		biome_id
	)
	return texture if texture != null else _soil_tex


## 湖底来源由 surface material 决定；新 biome 只需覆盖 underwater_texture，
## 不再向 renderer 增加 desert/volcanic/ice 等名称分支。
func _underwater_texture_for_context(context, water_depth: int) -> Texture2D:
	var safe_depth := maxi(1, water_depth)
	var cache_key := "%s/%s/%d" % [
		context.surface_id,
		context.biome_id,
		safe_depth,
	]
	if _underwater_texture_cache.has(cache_key):
		return _underwater_texture_cache[cache_key]
	var base_texture: Texture2D = _terrain_materials.get_texture(
		context.surface_id,
		&"underwater",
		context.biome_id
	)
	if base_texture == null:
		base_texture = _moist_tex
	var texture := _make_underwater_ground_texture(safe_depth, base_texture)
	_underwater_texture_cache[cache_key] = texture
	return texture


func _desert_surface_kind(cell: Vector2i, q: int, biome: int) -> int:
	var biome_id := StringName(_biome_id(biome))
	var surface_id: StringName = _terrain_sampler.biome_registry.surface_kind(
		cell,
		q,
		biome_id
	)
	match surface_id:
		&"sand":
			return DesertSurface.SAND
		&"rock":
			return DesertSurface.ROCK
		&"transition_parched", &"parched_soil":
			return DesertSurface.TRANSITION_PARCHED
		&"transition_sparse_grass", &"sparse_grass":
			return DesertSurface.TRANSITION_SPARSE_GRASS
	return DesertSurface.NONE


## 泥土里按 8% 混入稀草泥土（按格+层确定性随机）
func _soil_or_little_grass(cell: Vector2i, level: int) -> Texture2D:
	return _little_grass_tex if _cell_rand(cell, 88 + level) < 0.08 else _soil_tex


# ---------- 植被 / 动物 ----------

var _flora_cache := {}
var _raw_selected_flora_cache := {}


func _plant_tex(species_id: String) -> Texture2D:
	if not _flora_cache.has(species_id):
		if not _plant_species.has(species_id):
			push_error("生态配置引用了未知植物: " + species_id)
			return null
		var species: Dictionary = _plant_species[species_id]
		_flora_cache[species_id] = load(String(species.get("texture", "")))
	return _flora_cache[species_id]


## 每个群落按 selection_seed_key 确定优势种；配置里的物种顺序与重复项都代表权重。
func _pick_species(rule: Dictionary, gc: Vector2i, cell: Vector2i) -> String:
	var pool: Array = rule.get("species", [])
	if pool.is_empty():
		return ""
	var seed_key := String(rule.get("selection_seed_key", rule.get("pool_id", "species")))
	var salt := seed_key.hash()
	var dominant: int = int(_cell_rand(gc, salt + 50) * pool.size()) % pool.size()
	var dominant_chance := _dominant_species_chance
	var layer_id := String(rule.get("layer", ""))
	if _flora_layer_configs.has(layer_id):
		var layer: Dictionary = _flora_layer_configs[layer_id]
		dominant_chance = float(layer.get("dominant_chance", dominant_chance))
	if _cell_rand(cell, salt + 100) < dominant_chance:
		return String(pool[dominant])
	var total := 0.0
	for i in pool.size():
		if i != dominant:
			total += _cell_rand(gc, salt + i)
	var rr := _cell_rand(cell, salt + 101) * total
	for i in pool.size():
		if i != dominant:
			rr -= _cell_rand(gc, salt + i)
			if rr <= 0.0:
				return String(pool[i])
	return String(pool[dominant])


func _ecosystem_id_for_cell(q: int, biome: int, beach: bool, lf: int) -> String:
	if _community_runtime != null and _community_runtime.is_configured():
		return _community_runtime.legacy_ecosystem_id(
			_legacy_cell_context(q, biome, beach, lf)
		)
	for ecosystem in _ecosystem_order:
		var match_rule: Dictionary = ecosystem.get("match", {})
		if _ecosystem_matches(match_rule, q, biome, beach, lf):
			return String(ecosystem["id"])
	return _default_ecosystem_id


## 旧测试与存档仍使用整数 biome/landform；在边界处转换成统一 CellContext。
## 新生态链始终直接消费 TerrainSampler 产生的动态 ID。
func _legacy_cell_context(q: int, biome: int, beach: bool, lf: int):
	var landform_id := ""
	if lf >= 0 and lf < _landform_ids.size():
		landform_id = _landform_ids[lf]
	return CellContextScript.new(
		Vector2i.ZERO,
		q,
		StringName(_biome_id(biome)),
		biome,
		StringName(landform_id),
		lf,
		maxi(0, WATER_SURFACE_LEVEL - q),
		q <= WATER_MAX,
		beach,
		&"water" if q <= WATER_MAX else &"",
		Vector2i.ZERO
	)


func _ecosystem_matches(match_rule: Dictionary, q: int, biome: int, beach: bool, lf: int) -> bool:
	if match_rule.has("water") and bool(match_rule["water"]) != (q <= WATER_MAX):
		return false
	if match_rule.has("shore") and bool(match_rule["shore"]) != beach:
		return false
	if match_rule.has("biome") and String(match_rule["biome"]) != _biome_id(biome):
		return false
	if match_rule.has("landform"):
		var configured_landform: Variant = match_rule["landform"]
		if configured_landform is Array:
			if not configured_landform.has(_landform_ids[lf]):
				return false
		elif String(configured_landform) != _landform_ids[lf]:
			return false
	if match_rule.has("minimum_level") and q < int(match_rule["minimum_level"]):
		return false
	if match_rule.has("maximum_level") and q > int(match_rule["maximum_level"]):
		return false
	return true


func _biome_id(biome: int) -> String:
	return String(_terrain_sampler.biome_id_for_index(biome))


func _ecology_chance(chance_value: Variant, lf: int, q: int) -> float:
	if chance_value is float or chance_value is int:
		return float(chance_value)
	if not chance_value is Dictionary:
		return 0.0
	var chances: Dictionary = chance_value
	if lf == Landform.MOUNTAIN or q >= rock_level:
		return float(chances.get("mountain_or_rock", chances.get("default", 0.0)))
	if lf == Landform.SWAMP:
		return float(chances.get("swamp", chances.get("default", 0.0)))
	if lf == Landform.HILLS:
		return float(chances.get("hills", chances.get("default", 0.0)))
	return float(chances.get("default", 0.0))


## 三个静态生态层分别使用独立噪声。所有命中的规则只先产生候选，同格最终只绘制一个。
func _raw_flora_candidates_for_rules(
	cell: Vector2i,
	q: int,
	lf: int,
	gc: Vector2i,
	rules: Array
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var water_depth := WATER_SURFACE_LEVEL - q
	for rule_value in rules:
		var rule: Dictionary = rule_value
		var layer_id := String(rule.get("layer", ""))
		var layer: Dictionary = _flora_layer_configs[layer_id]
		var noise_field_id := String(layer.get("noise_field", ""))
		var layer_noise := _noise_instance_for_field(noise_field_id).get_noise_2d(cell.x, cell.y)
		var noise_above := float(
			rule.get("noise_above", layer.get("default_noise_above", 0.0))
		)
		if layer_noise < noise_above:
			continue
		if rule.has("max_water_depth") and water_depth > int(rule["max_water_depth"]):
			continue
		var placement_seed := int(rule.get("placement_seed", 0))
		var chance := _ecology_chance(rule.get("chance", 0.0), lf, q)
		if _cell_rand(cell, placement_seed) >= chance:
			continue
		var plant_id := _pick_species(rule, gc, cell)
		if plant_id.is_empty():
			continue
		var placement := String(rule.get("placement", "ground"))
		candidates.append({
			"sort_key": "%s/%s/%s" % [layer_id, String(rule.get("pool_id", "")), plant_id],
			"species_id": plant_id,
			"layer": layer_id,
			"placement": placement,
			"level": WATER_SURFACE_LEVEL if placement == "water_surface" else q,
			"render_priority": int(rule.get("render_priority", 8)),
			"modulate": (
				_underwater_flora_modulate(water_depth)
				if placement == "lakebed"
				else Color.WHITE
			),
			"conflict_weight": float(rule.get("conflict_weight", 1.0)),
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["sort_key"]) < String(b["sort_key"])
	)
	return candidates


## 旧契约的兼容入口；正式生成链由 CommunityRuntime 提供加法合并后的 rules。
func _raw_flora_candidates_for_cell(
	cell: Vector2i,
	q: int,
	lf: int,
	gc: Vector2i,
	ecosystem: Dictionary
) -> Array[Dictionary]:
	return _raw_flora_candidates_for_rules(
		cell, q, lf, gc, ecosystem.get("flora", [])
	)


## 带 habitat 的物种只改变候选最终显示的品种，不删除候选或改变冲突权重。
## 因此空旷处的蘑菇会被同层草丛接替，但已经调好的地被总密度保持不变。
func _flora_candidates_for_cell(
	cell: Vector2i,
	q: int,
	lf: int,
	gc: Vector2i,
	ecosystem: Dictionary
) -> Array[Dictionary]:
	return _flora_candidates_for_rules(
		cell, q, lf, gc, ecosystem.get("flora", [])
	)


func _flora_candidates_for_rules(
	cell: Vector2i,
	q: int,
	lf: int,
	gc: Vector2i,
	rules: Array
) -> Array[Dictionary]:
	var candidates := _raw_flora_candidates_for_rules(cell, q, lf, gc, rules)
	for index in candidates.size():
		var candidate: Dictionary = candidates[index]
		candidate["species_id"] = _resolve_flora_habitat_species(
			cell,
			String(candidate["species_id"])
		)
		candidates[index] = candidate
	return candidates


func _resolve_flora_habitat_species(cell: Vector2i, species_id: String) -> String:
	var species: Dictionary = _plant_species.get(species_id, {})
	var habitat: Dictionary = species.get("habitat", {})
	if habitat.is_empty():
		return species_id
	var near_layer := String(habitat.get("near_flora_layer", ""))
	var radius := int(habitat.get("radius", 0))
	if _has_raw_selected_flora_layer_within(cell, near_layer, radius):
		return species_id
	return String(habitat.get("fallback_species", species_id))


## 邻近查询必须基于未应用 habitat 的确定性最终候选，不能读取流式 `_cells`。
## 这样结果不依赖格子的生成先后，也不会在蘑菇查询树木时递归调用自身。
func _raw_selected_flora_for_cell(cell: Vector2i) -> Dictionary:
	if _raw_selected_flora_cache.has(cell):
		return _raw_selected_flora_cache[cell]
	var context = _cell_context_for_query(cell)
	var rules: Array = _community_runtime.cell_flora_rules_for_cell(
		context,
		Callable(self, "_ecology_near_tag")
	)
	var candidates := _raw_flora_candidates_for_rules(
		cell,
		context.height,
		int(LANDFORM_ID_TO_TYPE.get(String(context.landform_id), Landform.PLAINS)),
		context.region_anchor,
		rules
	)
	candidates.append_array(_spatial_flora_candidates_for_cell(context))
	var selected := _select_flora_candidate(cell, candidates)
	_raw_selected_flora_cache[cell] = selected
	return selected


func _has_raw_selected_flora_layer_within(
	cell: Vector2i,
	layer_id: String,
	radius: int
) -> bool:
	for offset_y in range(-radius, radius + 1):
		for offset_x in range(-radius, radius + 1):
			if offset_x == 0 and offset_y == 0:
				continue
			var selected := _raw_selected_flora_for_cell(
				cell + Vector2i(offset_x, offset_y)
			)
			if String(selected.get("layer", "")) == layer_id:
				return true
	return false


func _select_flora_candidate(cell: Vector2i, candidates: Array[Dictionary]) -> Dictionary:
	if candidates.is_empty():
		return {}
	var total_weight := 0.0
	for candidate in candidates:
		total_weight += float(candidate.get("conflict_weight", 1.0))
	var cursor := _cell_rand(cell, _flora_conflict_seed) * total_weight
	for candidate in candidates:
		cursor -= float(candidate.get("conflict_weight", 1.0))
		if cursor <= 0.0:
			return candidate
	return candidates.back()


## 动植物定义由 ecology manifest 与 CommunityRuntime 驱动；这里只保留候选冲突与放置机制。
func _spawn_flora(
	cell: Vector2i,
	q: int,
	lf: int,
	gc: Vector2i,
	state
) -> void:
	var rules: Array = _community_runtime.cell_flora_rules_for_cell(
		state.context,
		Callable(self, "_ecology_near_tag")
	)
	var selected := _select_flora_candidate(
		cell,
		_flora_candidates_with_spatial(cell, q, lf, gc, rules, state.context)
	)
	if not selected.is_empty():
		_place_flora(
			String(selected["species_id"]),
			String(selected["layer"]),
			String(selected["placement"]),
			int(selected["level"]),
			state,
			int(selected["render_priority"]),
			selected.get("modulate", Color.WHITE)
		)


func _flora_candidates_with_spatial(
	cell: Vector2i,
	q: int,
	lf: int,
	gc: Vector2i,
	rules: Array,
	context
) -> Array[Dictionary]:
	var candidates := _flora_candidates_for_rules(cell, q, lf, gc, rules)
	for candidate_value in _spatial_flora_candidates_for_cell(context):
		var candidate: Dictionary = candidate_value
		candidate["species_id"] = _resolve_flora_habitat_species(
			cell,
			String(candidate.get("species_id", ""))
		)
		candidates.append(candidate)
	return candidates


func _spatial_flora_candidates_for_cell(context) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if context == null:
		return candidates
	var cell: Vector2i = context.cell
	for source in _spatial_flora_sources:
		var definition: Dictionary = source.get("definition", {})
		var distribution: Dictionary = definition.get("distribution", {})
		var spacing := maxi(1, int(distribution.get("anchor_spacing", 1)))
		var radius := maxi(0, int(distribution.get("radius", 0)))
		var minimum_bucket := CommunitySpawnerScript.bucket_for_cell(
			cell - Vector2i(radius, radius), spacing
		)
		var maximum_bucket := CommunitySpawnerScript.bucket_for_cell(
			cell + Vector2i(radius, radius), spacing
		)
		for bucket_y in range(minimum_bucket.y, maximum_bucket.y + 1):
			for bucket_x in range(minimum_bucket.x, maximum_bucket.x + 1):
				var plan := _spatial_flora_plan(
					source,
					Vector2i(bucket_x, bucket_y)
				)
				if not bool(plan.get("complete", false)):
					continue
				for member_value in plan.get("members", []):
					var member: Dictionary = member_value
					if member.get("cell", Vector2i.ZERO) != cell:
						continue
					var candidate := _spatial_flora_candidate(
						definition,
						member,
						context
					)
					if not candidate.is_empty():
						candidates.append(candidate)
	return candidates


func _spatial_flora_plan(source: Dictionary, bucket: Vector2i) -> Dictionary:
	var cache_key := "%s/%s/%d/%d" % [
		String(source.get("source_biome_id", "")),
		String(source.get("community_id", "")),
		bucket.x,
		bucket.y,
	]
	if _spatial_flora_plan_cache.has(cache_key):
		return _spatial_flora_plan_cache[cache_key]
	var habitat_valid: Callable = func(candidate: Vector2i) -> bool:
		return _community_runtime.flora_source_matches_context(
			source,
			_cell_context_for_query(candidate),
			Callable(self, "_ecology_near_tag")
		)
	var plan: Dictionary = CommunitySpawnerScript.plan_community(
		source.get("definition", {}),
		bucket,
		Callable(self, "_community_rand01"),
		habitat_valid,
		habitat_valid
	)
	_spatial_flora_plan_cache[cache_key] = plan
	return plan


func _spatial_flora_candidate(
	definition: Dictionary,
	member: Dictionary,
	context
) -> Dictionary:
	var species_id := String(member.get("species", member.get("species_id", "")))
	var species: Dictionary = _plant_species.get(species_id, {})
	var layer_id := String(species.get("layer", ""))
	if species_id.is_empty() or layer_id.is_empty():
		return {}
	var habitat_value: Variant = definition.get("habitat", {})
	var habitat: Dictionary = habitat_value if habitat_value is Dictionary else {}
	var placement := String(habitat.get("placement", "ground"))
	for spec_value in definition.get("members", []):
		if not spec_value is Dictionary:
			continue
		var spec: Dictionary = spec_value
		if String(spec.get("species_id", spec.get("species", ""))) == species_id:
			placement = String(spec.get("placement", placement))
			break
	var render_priority := int(definition.get(
		"render_priority",
		12 if placement == "water_surface" else 0 if placement == "lakebed" else 8
	))
	return {
		"sort_key": "%s/%s/%s" % [
			layer_id,
			String(definition.get("id", "community")),
			species_id,
		],
		"species_id": species_id,
		"layer": layer_id,
		"placement": placement,
		"level": WATER_SURFACE_LEVEL if placement == "water_surface" else context.height,
		"render_priority": render_priority,
		"modulate": (
			_underwater_flora_modulate(context.water_depth)
			if placement == "lakebed"
			else Color.WHITE
		),
		"conflict_weight": float(definition.get("conflict_weight", 1.0)),
	}


## 静态生态对象和所属地块柱一起绘制；地被不参与玩家遮挡，树木与装饰物仍可遮挡。
func _place_flora(
	species_id: String,
	layer_id: String,
	placement: String,
	level: int,
	state,
	z_bias := 8,
	modulate := Color.WHITE
) -> bool:
	var tex := _plant_tex(species_id)
	if tex == null:
		return false
	var occluder_class := (
		&"prop"
		if placement == "ground" and layer_id in ["tree", "decoration"]
		else &"none"
	)
	var block := _render_block(
		tex,
		level,
		modulate,
		z_bias,
		Vector2(0, -tex.get_height() / 2.0),
		occluder_class
	)
	block["flora_species_id"] = species_id
	block["flora_layer"] = layer_id
	block["flora_placement"] = placement
	state.add_render_block(block)
	var species: Dictionary = _plant_species.get(species_id, {})
	var traits_value: Variant = species.get("traits", {})
	var traits: Dictionary = traits_value if traits_value is Dictionary else {}
	var blocks_movement_default := (
		placement == "ground" and layer_id in ["tree", "decoration"]
	)
	state.add_static_object({
		"id": species_id,
		"category": "flora",
		"layer": layer_id,
		"placement": placement,
		"blocks_movement": bool(
			traits.get("blocks_movement", blocks_movement_default)
		),
		"blocks_fauna_spawn": bool(traits.get("blocks_fauna_spawn", false)),
		"tags": species.get("tags", []),
	})
	return true


## Ambient 是纯表现插件，不占动物格，也不参与移动或地图生成。
## 候选格与物种完全由生态规则决定；主场景不认识 firefly/butterfly 等具体类型。
func _spawn_ambient_for_cell(
	cell: Vector2i,
	q: int,
	lf: int,
	gc: Vector2i,
	state,
	host: Node2D
) -> void:
	if _ambient_registry == null:
		return
	var rules: Array = _community_runtime.ambient_rules_for_cell(
		state.context,
		Callable(self, "_ecology_near_tag")
	)
	var has_ground_flora := false
	for object_value in state.static_objects:
		var object_data: Dictionary = object_value
		if (
			String(object_data.get("placement", "")) == "ground"
			and String(object_data.get("layer", "")) in ["tree", "ground_cover"]
		):
			has_ground_flora = true
			break
	for rule_value in rules:
		var rule: Dictionary = rule_value
		if bool(rule.get("requires_ground_flora", false)) and not has_ground_flora:
			continue
		var placement_seed := int(rule.get("placement_seed", 0))
		var chance := _ecology_chance(rule.get("chance", 0.0), lf, q)
		if _cell_rand(cell, placement_seed) >= chance:
			continue
		var ambient_id := _pick_species(rule, gc, cell)
		if (
			not _ambient_species.has(ambient_id)
			or not _ambient_registry.has_species(StringName(ambient_id))
		):
			continue
		var ambient: Dictionary = _ambient_species[ambient_id]
		var cluster_range: Array = ambient.get("cluster_size", [2, 3])
		var cluster_min := int(cluster_range[0])
		var cluster_max := int(cluster_range[1])
		var count_span := cluster_max - cluster_min + 1
		var count := clampi(
			cluster_min + int(_cell_rand(cell, placement_seed + 1) * count_span),
			cluster_min,
			cluster_max
		)
		var deterministic_seed := _hash_u32(
			cell.x * 0x8da6b343
			^ cell.y * 0xd8163841
			^ (_current_seed + placement_seed)
		)
		var local_surface_position := _grid_to_screen(cell, q) - host.position
		_ambient_registry.add_cluster(
			StringName(ambient_id),
			cell,
			host,
			local_surface_position,
			count,
			deterministic_seed
		)
		break


# ---------- 动物群落 / 移动物体 ----------

## fauna 的 chance 是“每个稀疏领地是否存在一个社会单元”，不再逐地块掷概率。
## 这样既能降低全局密度，也能把狼、猪和青蛙组织成真正的群体。
func _spawn_fauna_for_stream() -> void:
	for source_value in _community_runtime.fauna_sources():
		var source: Dictionary = source_value
		var ecosystem_id := String(source.get("source_biome_id", ""))
		var rule: Dictionary = source.get("rule", {})
		if ecosystem_id.is_empty() or rule.is_empty():
			continue
		var distribution: Dictionary = rule.get("distribution", {})
		var spacing := maxi(1, int(distribution.get("anchor_spacing", 1)))
		var radius := maxi(0, int(distribution.get("radius", 0)))
		var minimum_bucket := Vector2i(
			floori(float(_stream_center.x - stream_extent - radius) / spacing),
			floori(float(_stream_center.y - stream_extent - radius) / spacing)
		)
		var maximum_bucket := Vector2i(
			floori(float(_stream_center.x + stream_extent + radius) / spacing),
			floori(float(_stream_center.y + stream_extent + radius) / spacing)
		)
		for bucket_y in range(minimum_bucket.y, maximum_bucket.y + 1):
			for bucket_x in range(minimum_bucket.x, maximum_bucket.x + 1):
				var bucket := Vector2i(bucket_x, bucket_y)
				var generic_spawner := _fauna_source_uses_generic_spawner(source)
				var anchor := (
					_community_anchor_for_source(source, bucket)
					if generic_spawner
					else _fauna_anchor_for_bucket(rule, bucket)
				)
				var group_id := _animal_group_id(ecosystem_id, rule, bucket)
				if _animal_groups.has(group_id):
					_restore_animal_group(group_id)
					continue
				# 首次发现必须等完整出生半径进入视窗，避免从不同方向接近时
				# 因边缘裁切得到不同的群成员位置或把 8 只狼永久截成 7 只。
				var anchor_search_radius := int(distribution.get("anchor_search_radius", 0))
				if (
					not _fauna_anchor_fully_loaded(anchor, radius + anchor_search_radius)
					or not _cells.has(anchor)
				):
					continue
				if generic_spawner:
					_create_first_class_animal_group(group_id, source, bucket)
					continue
				var anchor_context = _cell_context_for_query(anchor)
				var anchor_q: int = anchor_context.height
				var anchor_landform := int(LANDFORM_ID_TO_TYPE.get(
					String(anchor_context.landform_id),
					Landform.PLAINS
				))
				if not _community_runtime.fauna_source_matches_context(
					source,
					anchor_context,
					Callable(self, "_ecology_near_tag")
				):
					continue
				var placement_seed := int(rule.get("placement_seed", 0))
				var chance := _ecology_chance(
					rule.get("chance", 0.0), anchor_landform, anchor_q
				)
				if _cell_rand(bucket, placement_seed + 3) >= chance:
					continue
				var water_radius := int(distribution.get("requires_water_within", 0))
				if water_radius > 0 and not _has_water_within(anchor, water_radius):
					continue
				_create_animal_group(
					group_id,
					ecosystem_id,
					rule,
					distribution,
					bucket,
					anchor,
					anchor_q,
					source
				)


func _fauna_anchor_fully_loaded(anchor: Vector2i, radius: int) -> bool:
	var safe_extent := stream_extent - maxi(0, radius)
	return (
		safe_extent >= 0
		and absi(anchor.x - _stream_center.x) <= safe_extent
		and absi(anchor.y - _stream_center.y) <= safe_extent
	)


func _fauna_anchor_for_bucket(rule: Dictionary, bucket: Vector2i) -> Vector2i:
	var distribution: Dictionary = rule.get("distribution", {})
	var spacing := maxi(1, int(distribution.get("anchor_spacing", 1)))
	var jitter := clampf(float(distribution.get("anchor_jitter", 1.0)), 0.0, 1.0)
	var inset := floori(spacing * (1.0 - jitter) * 0.5)
	var usable := maxi(1, spacing - inset * 2)
	var placement_seed := int(rule.get("placement_seed", 0))
	var offset_x := inset + mini(
		usable - 1,
		int(_cell_rand(bucket, placement_seed + 1) * usable)
	)
	var offset_y := inset + mini(
		usable - 1,
		int(_cell_rand(bucket, placement_seed + 2) * usable)
	)
	return bucket * spacing + Vector2i(offset_x, offset_y)


func _animal_group_id(ecosystem_id: String, rule: Dictionary, bucket: Vector2i) -> String:
	return "%s/%s/%d/%d" % [
		ecosystem_id,
		String(rule.get("pool_id", "fauna")),
		bucket.x,
		bucket.y,
	]


func _community_rand01(position: Vector2i, stream_key: String) -> float:
	return _world_rng.cell_float(position, StringName(stream_key))


## 已迁移的内置群落继续走 legacy salt 适配器，确保现有世界与调好的密度不漂移；
## 没有 legacy seed 的新定义自动使用通用 CommunitySpawner。
func _fauna_source_uses_generic_spawner(source: Dictionary) -> bool:
	if not bool(source.get("first_class", false)):
		return false
	var definition: Dictionary = source.get("definition", {})
	var metadata_value: Variant = definition.get("metadata", {})
	var metadata: Dictionary = metadata_value if metadata_value is Dictionary else {}
	return not metadata.has("legacy_placement_seed")


func _community_anchor_for_source(source: Dictionary, bucket: Vector2i) -> Vector2i:
	var definition: Dictionary = source.get("definition", {})
	var distribution: Dictionary = definition.get("distribution", {})
	var spacing := maxi(1, int(distribution.get("anchor_spacing", 1)))
	var jitter := clampf(
		float(distribution.get("anchor_jitter", distribution.get("jitter", 1.0))),
		0.0,
		1.0
	)
	var stream_prefix := String(
		definition.get("stream_key", definition.get("id", "community"))
	)
	return CommunitySpawnerScript.anchor_for_bucket(
		bucket,
		spacing,
		jitter,
		Callable(self, "_community_rand01"),
		stream_prefix + "/anchor"
	)


func _create_first_class_animal_group(
	group_id: String,
	source: Dictionary,
	bucket: Vector2i
) -> void:
	var definition: Dictionary = source.get("definition", {})
	if definition.is_empty():
		return
	var rule: Dictionary = source.get("rule", {})
	var distribution: Dictionary = definition.get("distribution", {})
	var same_ecosystem := bool(distribution.get(
		"same_ecosystem",
		distribution.get(
			"same_biome",
			(definition.get("habitat", {}) as Dictionary).get("same_biome", true)
		)
	))
	var only_if_flora_missed := bool(rule.get("only_if_flora_missed", true))
	var habitat: Dictionary = definition.get("habitat", {})
	var required_tags: Array = habitat.get("required_tags", [])
	var allow_water := bool(
		(definition.get("metadata", {}) as Dictionary).get(
			"allow_water",
			"water" in required_tags and "land" not in required_tags
		)
	)
	var habitat_valid: Callable = func(candidate: Vector2i) -> bool:
		var candidate_context = _cell_context_for_query(candidate)
		return _community_runtime.fauna_source_matches_context(
			source,
			candidate_context,
			Callable(self, "_ecology_near_tag")
		) and _community_water_clearance_valid(definition, candidate_context)
	var anchor_result := CommunitySpawnerScript.resolve_anchor(
		definition,
		bucket,
		Callable(self, "_community_rand01"),
		habitat_valid
	)
	if not bool(anchor_result.get("valid", false)):
		_cache_inactive_animal_group(group_id, source, anchor_result["anchor"], "invalid_habitat")
		return
	var anchor: Vector2i = anchor_result["anchor"]
	var anchor_context = _cell_context_for_query(anchor)
	var anchor_q: int = anchor_context.height
	var cell_valid: Callable = func(candidate: Vector2i) -> bool:
		if not _cells.has(candidate) or not _cell_states.has(candidate):
			return false
		var candidate_context = _cell_context_for_query(candidate)
		if absi(_stand_level(candidate_context.height) - _stand_level(anchor_q)) > 1:
			return false
		if same_ecosystem and not _community_runtime.fauna_source_matches_context(
			source,
			candidate_context,
			Callable(self, "_ecology_near_tag")
		):
			return false
		if not _community_water_clearance_valid(definition, candidate_context):
			return false
		return _cell_states[candidate].can_spawn_fauna(
			allow_water,
			only_if_flora_missed
		)
	var plan: Dictionary = CommunitySpawnerScript.plan_community(
		definition,
		bucket,
		Callable(self, "_community_rand01"),
		habitat_valid,
		cell_valid
	)
	if not bool(plan.get("complete", false)):
		_cache_inactive_animal_group(
			group_id,
			source,
			anchor,
			String(plan.get("reason", "incomplete_plan"))
		)
		return
	var members: Array[Dictionary] = []
	for member_value in plan.get("members", []):
		var member: Dictionary = member_value
		members.append({
			"origin": member.get("cell", Vector2i.ZERO),
			"species": String(member.get("species", member.get("species_id", ""))),
			"role": String(member.get("role", "")),
		})
	if members.is_empty():
		_cache_inactive_animal_group(group_id, source, anchor, "empty_members")
		return
	_animal_groups.set_or_put(group_id, {
		"anchor": anchor,
		"ecosystem_id": String(source.get("source_biome_id", "")),
		"community_id": String(source.get("community_id", "")),
		"social_radius": float(distribution.get("social_radius", distribution.get("radius", 0.0))),
		"members": members,
	}, true)
	_restore_animal_group(group_id)
	_animal_groups.unpin(group_id)


func _cache_inactive_animal_group(
	group_id: String,
	source: Dictionary,
	anchor: Vector2i,
	reason: String
) -> void:
	# Fully loaded group territories are deterministic. Caching an empty result
	# prevents every one-cell streaming update from repeating habitat searches
	# for the same dry/invalid bucket. CommunityStateStore keeps this negative
	# cache bounded and evicts it before active groups.
	_animal_groups.set_or_put(group_id, {
		"anchor": anchor,
		"ecosystem_id": String(source.get("source_biome_id", "")),
		"community_id": String(source.get("community_id", "")),
		"social_radius": 0.0,
		"members": [],
		"inactive_reason": reason,
	})


func _create_animal_group(
	group_id: String,
	ecosystem_id: String,
	rule: Dictionary,
	distribution: Dictionary,
	bucket: Vector2i,
	anchor: Vector2i,
	anchor_q: int,
	source: Dictionary = {}
) -> void:
	var count_range: Array = distribution.get("count", [1, 1])
	var minimum_count := int(count_range[0])
	var maximum_count := int(count_range[1])
	var count_span := maximum_count - minimum_count + 1
	var placement_seed := int(rule.get("placement_seed", 0))
	var desired_count := minimum_count + int(
		_cell_rand(bucket, placement_seed + 4) * count_span
	) % count_span
	var spawn_cells := _animal_group_spawn_cells(
		anchor,
		anchor_q,
		ecosystem_id,
		distribution,
		desired_count,
		placement_seed,
		bool(rule.get("only_if_flora_missed", true)),
		source
	)
	if spawn_cells.size() < minimum_count:
		return
	var primary_species := _pick_species(rule, bucket, anchor)
	if primary_species.is_empty():
		return
	var members: Array[Dictionary] = []
	for spawn_cell in spawn_cells:
		members.append({"origin": spawn_cell, "species": primary_species})

	# substitution 替换群内成员而不是额外添加，狼群总数始终保持 7–8。
	var substitution: Dictionary = distribution.get("substitution", {})
	if not substitution.is_empty():
		var substitute_chance := float(substitution.get("chance", 0.0))
		if _cell_rand(bucket, placement_seed + 5) < substitute_chance:
			var substitute_count := mini(
				int(substitution.get("max_count", 1)),
				members.size()
			)
			var start_index := int(
				_cell_rand(bucket, placement_seed + 6) * members.size()
			) % members.size()
			for offset in substitute_count:
				var member_index := (start_index + offset) % members.size()
				members[member_index]["species"] = String(substitution.get("species", ""))

	_animal_groups.set_or_put(group_id, {
		"anchor": anchor,
		"ecosystem_id": ecosystem_id,
		"social_radius": float(distribution.get("social_radius", 0.0)),
		"members": members,
	}, true)
	_restore_animal_group(group_id)
	_animal_groups.unpin(group_id)


func _animal_group_spawn_cells(
	anchor: Vector2i,
	anchor_q: int,
	ecosystem_id: String,
	distribution: Dictionary,
	desired_count: int,
	placement_seed: int,
	only_if_flora_missed := true,
	source: Dictionary = {}
) -> Array[Vector2i]:
	var candidates: Array[Dictionary] = []
	var radius := maxi(0, int(distribution.get("radius", 0)))
	var same_ecosystem := bool(distribution.get("same_ecosystem", true))
	for offset_y in range(-radius, radius + 1):
		var row_radius := radius - absi(offset_y)
		for offset_x in range(-row_radius, row_radius + 1):
			var cell := anchor + Vector2i(offset_x, offset_y)
			if not _animal_group_cell_is_valid(
				cell,
				anchor_q,
				ecosystem_id,
				same_ecosystem,
				only_if_flora_missed,
				source
			):
				continue
			candidates.append({
				"cell": cell,
				"anchor_first": 0 if cell == anchor else 1,
				"rank": _cell_rand(cell, placement_seed + 101),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["anchor_first"]) != int(b["anchor_first"]):
			return int(a["anchor_first"]) < int(b["anchor_first"])
		if not is_equal_approx(float(a["rank"]), float(b["rank"])):
			return float(a["rank"]) < float(b["rank"])
		var a_cell: Vector2i = a["cell"]
		var b_cell: Vector2i = b["cell"]
		return a_cell.y < b_cell.y or (a_cell.y == b_cell.y and a_cell.x < b_cell.x)
	)
	var result: Array[Vector2i] = []
	for candidate in candidates:
		if result.size() >= desired_count:
			break
		result.append(candidate["cell"])
	return result


func _animal_group_cell_is_valid(
	cell: Vector2i,
	anchor_q: int,
	ecosystem_id: String,
	same_ecosystem: bool,
	only_if_flora_missed := true,
	source: Dictionary = {}
) -> bool:
	if (
		not _in_stream(cell, _stream_center)
		or not _cells.has(cell)
		or not _cell_states.has(cell)
	):
		return false
	var q := _quantize(cell.x, cell.y)
	if q <= WATER_MAX or absi(_stand_level(q) - _stand_level(anchor_q)) > 1:
		return false
	if same_ecosystem:
		var context = _cell_context_for_query(cell)
		if not source.is_empty():
			if not _community_runtime.fauna_source_matches_context(
				source,
				context,
				Callable(self, "_ecology_near_tag")
			):
				return false
		elif _community_runtime.legacy_ecosystem_id(context) != ecosystem_id:
			return false
	var state = _cell_states[cell]
	return state.can_spawn_fauna(false, only_if_flora_missed)


func _has_water_within(center: Vector2i, radius: int) -> bool:
	for offset_y in range(-radius, radius + 1):
		var row_radius := radius - absi(offset_y)
		for offset_x in range(-row_radius, row_radius + 1):
			if _quantize(center.x + offset_x, center.y + offset_y) <= WATER_MAX:
				return true
	return false


func _restore_animal_group(group_id: String) -> void:
	if not _animal_groups.has(group_id):
		return
	var group: Dictionary = _animal_groups[group_id]
	var members: Array = group.get("members", [])
	var social_group_id := group_id if members.size() > 1 else ""
	for member_value in members:
		var member: Dictionary = member_value
		var origin: Vector2i = member["origin"]
		if _animals.has(origin) or not _in_stream(origin, _stream_center):
			continue
		if (
			origin == _player_cell
			or not _cells.has(origin)
			or _animal_cell_reserved(origin)
		):
			continue
		var animal := _spawn_animal(
			String(member["species"]),
			origin,
			_quantize(origin.x, origin.y)
		)
		if animal == null:
			continue
		animal.community_group_id = group_id
		animal.social_group_id = social_group_id
		animal.social_radius = float(group.get("social_radius", 0.0))
	_animal_groups.set_active_member_count(
		group_id,
		_active_animal_count_for_group(group_id)
	)


func _active_animal_count_for_group(group_id: String) -> int:
	var count := 0
	for animal_value in _animals.values():
		var animal: AnimatedSprite2D = animal_value
		if (
			is_instance_valid(animal)
			and String(animal.community_group_id) == group_id
		):
			count += 1
	return count


func _release_animal_group_member(animal: AnimatedSprite2D) -> void:
	var group_id := String(animal.community_group_id)
	if group_id.is_empty() or not _animal_groups.has(group_id):
		return
	_animal_groups.decrement_active_members(group_id)


func _spawn_animal(species_id: String, cell: Vector2i, _level: int) -> AnimatedSprite2D:
	if _animals.has(cell) or _animal_cell_reserved(cell):
		return null
	if not _animal_species.has(species_id):
		push_error("生态配置引用了未知动物: " + species_id)
		return null
	var species: Dictionary = _animal_species[species_id]
	var terrain_level := _quantize(cell.x, cell.y)
	var surface_id := &"water" if terrain_level <= WATER_MAX else &"land"
	if not _animal_species_allows_surface(species, surface_id):
		return null
	var spawn_stack_value: Variant = _animal_behavior_stacks.get(species_id, [])
	var spawn_stack: Array[Dictionary] = []
	if spawn_stack_value is Array:
		for behavior_value in spawn_stack_value:
			if behavior_value is Dictionary:
				spawn_stack.append((behavior_value as Dictionary).duplicate(true))
	var spawn_cell_data := _animal_behavior_cell_data(cell)
	var spawn_decision := _animal_behavior_registry.evaluate_stack(
		spawn_stack,
		spawn_cell_data,
		{
			"current": spawn_cell_data,
			"player_cell": _player_cell,
			"distance_to_tag": Callable(self, "_animal_behavior_distance_to_tag"),
		}
	)
	if not bool(spawn_decision.get("allowed", false)):
		return null
	var animal: AnimatedSprite2D = WanderingAnimalScript.new()
	_animals[cell] = animal
	add_child(animal)
	animal.configure(
		species_id,
		cell,
		_animal_frames_for(species_id),
		_cell_feet_pos(cell),
		_column_sort_y(cell) + ANIMAL_SORT_BIAS,
		_animal_wait(cell, 0),
		StringName(species.get("behavior", &"wander")),
		species.get("movement", {}),
		float(species.get("foot_offset_y", 0.0))
	)
	var metadata: Dictionary = species.get("metadata", {})
	if bool(metadata.get("aquatic", false)):
		# 地块批绘制器会把湖底和水面合为一个 CanvasItem，移动鱼无法真正插入
		# 两次 draw call 之间；水下材质在鱼身上重建前景水层，形成被透明水体
		# 遮住的感觉，同时不额外创建成千上万个水面节点。
		animal.material = _underwater_animal_material_for_depth(
			WATER_SURFACE_LEVEL - terrain_level
		)
	return animal


func _underwater_animal_material_for_depth(water_depth: int) -> ShaderMaterial:
	var depth_key := clampi(water_depth, 1, WATER_SURFACE_LEVEL)
	if _underwater_animal_material_cache.has(depth_key):
		return _underwater_animal_material_cache[depth_key]
	var material := ShaderMaterial.new()
	material.shader = UnderwaterAnimalShader
	material.set_shader_parameter("water_colour", WATER_COLOR)
	material.set_shader_parameter("fin_coverage", 0.08)
	material.set_shader_parameter(
		"body_coverage",
		clampf(0.58 + float(depth_key - 1) * 0.05, 0.58, 0.74)
	)
	material.set_shader_parameter("waterline", 0.29)
	material.set_shader_parameter(
		"visibility",
		clampf(0.80 - float(depth_key - 1) * 0.05, 0.62, 0.80)
	)
	_underwater_animal_material_cache[depth_key] = material
	return material


func _animal_species_allows_surface(
	species: Dictionary,
	surface_id: StringName
) -> bool:
	var movement_value: Variant = species.get("movement", {})
	var movement: Dictionary = movement_value if movement_value is Dictionary else {}
	var surfaces_value: Variant = species.get(
		"allowed_surfaces",
		movement.get("allowed_surfaces", ["land"])
	)
	if not surfaces_value is Array:
		return false
	for allowed_surface in surfaces_value:
		if StringName(allowed_surface) == surface_id:
			return true
	return false


func _animal_frames_for(species_id: String) -> SpriteFrames:
	if _animal_frames_cache.has(species_id):
		return _animal_frames_cache[species_id]
	var species: Dictionary = _animal_species[species_id]
	var directory := String(species.get("directory", ""))
	var actions: Dictionary = species.get("actions", {})
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	for action_id in actions:
		var action: Dictionary = actions[action_id]
		var animation_name := StringName(action_id)
		var texture: Texture2D = load(directory.path_join(String(action.get("file", ""))))
		if action.has("frame_size"):
			var frame_size_value: Array = action["frame_size"]
			_add_sheet_animation(
				frames,
				animation_name,
				texture,
				Vector2i(int(frame_size_value[0]), int(frame_size_value[1])),
				int(action.get("columns", 1)),
				int(action.get("frames", 1)),
				float(action.get("fps", 1.0)),
				bool(action.get("loop", true))
			)
		else:
			frames.add_animation(animation_name)
			frames.set_animation_speed(animation_name, float(action.get("fps", 1.0)))
			frames.set_animation_loop(animation_name, bool(action.get("loop", true)))
			frames.add_frame(animation_name, texture)
	_animal_frames_cache[species_id] = frames
	return frames


func _add_sheet_animation(
	frames: SpriteFrames,
	animation_name: StringName,
	sheet: Texture2D,
	frame_size: Vector2i,
	columns: int,
	frame_count: int,
	fps: float,
	loop: bool
) -> void:
	frames.add_animation(animation_name)
	frames.set_animation_speed(animation_name, fps)
	frames.set_animation_loop(animation_name, loop)
	for i in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(
			(i % columns) * frame_size.x,
			(i / columns) * frame_size.y,
			frame_size.x,
			frame_size.y
		)
		frames.add_frame(animation_name, atlas)


func _clear_animals() -> void:
	for animal_value in _animals.values():
		var animal: Node = animal_value
		if is_instance_valid(animal):
			remove_child(animal)
			animal.queue_free()
	_animals.clear()
	_animal_groups.clear()


func _cleanup_streamed_animals() -> void:
	for origin_value in _animals.keys():
		var origin: Vector2i = origin_value
		var animal: AnimatedSprite2D = _animals[origin]
		if not is_instance_valid(animal):
			_animals.erase(origin)
			continue
		var active := _animal_in_active_stream(animal)
		animal.visible = active
		var retained := (
			_in_stream(origin, _stream_center)
			or active
		)
		if retained:
			continue
		_release_animal_group_member(animal)
		_animals.erase(origin)
		remove_child(animal)
		animal.queue_free()


func _update_animals(delta: float) -> void:
	for animal_value in _animals.values():
		var animal: AnimatedSprite2D = animal_value
		if not is_instance_valid(animal):
			continue
		var active := _animal_in_active_stream(animal)
		animal.visible = active
		if not active:
			continue
		# 玩家进入警戒范围时打断静止等待；已经起步的动作完成后再重新选逃跑方向。
		var should_flee := _animal_should_flee(animal)
		if not animal.moving and should_flee and not animal.fleeing:
			animal.wait_remaining = 0.0
		animal.fleeing = should_flee
		if animal.tick(delta):
			animal.consume_move_bout_step()
			animal.fleeing = _animal_should_flee(animal)
			var continue_bout: bool = (
				animal.move_action_loops()
				and (animal.fleeing or animal.move_steps_remaining > 0)
			)
			if continue_bout:
				animal.wait_remaining = (
					ANIMAL_FLEE_WAIT
					if animal.fleeing
					else _animal_step_pause(animal)
				)
			else:
				animal.finish_move_bout()
				animal.wait_remaining = (
					ANIMAL_FLEE_WAIT
					if animal.fleeing
					else _animal_wait(animal.origin_cell, animal.step_index)
				)
		elif animal.ready_to_move():
			_begin_animal_move(animal)


func _animal_in_active_stream(animal: AnimatedSprite2D) -> bool:
	return (
		_in_stream(animal.grid_cell, _stream_center)
		or (animal.moving and _in_stream(animal.target_cell, _stream_center))
	)


func _begin_animal_move(animal: AnimatedSprite2D) -> void:
	var current_cell: Vector2i = animal.grid_cell
	var fleeing := _animal_should_flee(animal)
	_animal_behavior_distance_cache.clear()
	if not animal.move_bout_active:
		animal.start_move_bout(_animal_bout_steps(animal))
	var direction_offset := int(_cell_rand(
		animal.origin_cell,
		9000 + animal.step_index * 97
	) * ANIMAL_DIRECTIONS.size()) % ANIMAL_DIRECTIONS.size()
	animal.step_index += 1
	var best_target := current_cell
	var best_score := _animal_move_score(animal, current_cell, current_cell)
	for i in ANIMAL_DIRECTIONS.size():
		var target: Vector2i = current_cell + ANIMAL_DIRECTIONS[(direction_offset + i) % ANIMAL_DIRECTIONS.size()]
		if not _can_animal_enter(animal, target):
			continue
		var score := _animal_move_score(animal, target, current_cell)
		# 平分时保留由 deterministic direction_offset 决定的第一个方向。
		if score > best_score:
			best_score = score
			best_target = target
	if best_target == current_cell:
		animal.finish_move_bout()
		animal.wait_remaining = (
			ANIMAL_BLOCKED_RETRY
			if fleeing
			else _animal_wait(animal.origin_cell, animal.step_index)
		)
		return
	var movement_decision := _animal_behavior_decision(animal, best_target, current_cell)
	var movement_speed := maxf(0.01, float(movement_decision.get("speed_multiplier", 1.0)))
	animal.begin_move(
		best_target,
		_cell_feet_pos(current_cell),
		_cell_feet_pos(best_target),
		_column_sort_y(current_cell) + ANIMAL_SORT_BIAS,
		_column_sort_y(best_target) + ANIMAL_SORT_BIAS,
		animal.move_duration / movement_speed,
		movement_speed,
		_stand_level(_quantize(current_cell.x, current_cell.y)),
		_stand_level(_quantize(best_target.x, best_target.y))
	)


func _can_animal_enter(animal: AnimatedSprite2D, target: Vector2i) -> bool:
	if not _in_stream(target, _stream_center):
		return false
	var current_cell: Vector2i = animal.grid_cell
	var decision := _animal_behavior_decision(animal, target, current_cell)
	if not bool(decision.get("allowed", false)):
		return false
	if target == _player_cell:
		return false
	if _cell_states.has(target) and _cell_states[target].blocks_movement():
		return false
	if _animal_cell_reserved(target, animal):
		return false
	return true


func _animal_cell_reserved(cell: Vector2i, except_animal: AnimatedSprite2D = null) -> bool:
	for other_value in _animals.values():
		var other: AnimatedSprite2D = other_value
		if other == except_animal or not is_instance_valid(other):
			continue
		if other.grid_cell == cell or (other.moving and other.target_cell == cell):
			return true
	return false


func _animal_should_flee(animal: AnimatedSprite2D) -> bool:
	var current_decision := _animal_behavior_decision(
		animal,
		animal.grid_cell,
		animal.grid_cell
	)
	if bool((current_decision.get("state", {}) as Dictionary).get("fleeing", false)):
		return true
	if animal.moving:
		var target_decision := _animal_behavior_decision(
			animal,
			animal.target_cell,
			animal.grid_cell
		)
		return bool((target_decision.get("state", {}) as Dictionary).get("fleeing", false))
	return false


func _animal_move_score(
	animal: AnimatedSprite2D,
	candidate: Vector2i,
	current_cell: Vector2i
) -> float:
	var score := 1.0 if candidate != current_cell else 0.0
	# 兼容热更新前已经误入水中的单位：水格仍不可作为新目标，但相邻陆格
	# 获得最高优先级，使遗留单位能够自行回到岸上而不是困在原地。
	if (
		_quantize(current_cell.x, current_cell.y) <= WATER_MAX
		and _quantize(candidate.x, candidate.y) > WATER_MAX
	):
		score += ANIMAL_LEAVE_WATER_BONUS
	var decision := _animal_behavior_decision(animal, candidate, current_cell)
	if not bool(decision.get("allowed", false)):
		return -INF
	return (
		score
		+ float(decision.get("score", 0.0))
		+ animal.direction_persistence_score(candidate, current_cell)
	)


func _animal_behavior_decision(
	animal: AnimatedSprite2D,
	candidate: Vector2i,
	current_cell: Vector2i
) -> Dictionary:
	var stack_value: Variant = _animal_behavior_stacks.get(animal.species_id, [])
	var stack: Array[Dictionary] = []
	if stack_value is Array:
		for behavior_value in stack_value:
			if behavior_value is Dictionary:
				stack.append((behavior_value as Dictionary).duplicate(true))
	if not String(animal.social_group_id).is_empty():
		stack.append({
			"type": "pack_cohesion",
			"radius": float(animal.social_radius),
			"weight": ANIMAL_GROUP_COHESION_WEIGHT,
		})
	var current := _animal_behavior_cell_data(current_cell)
	var candidate_data := _animal_behavior_cell_data(candidate)
	return _animal_behavior_registry.evaluate_stack(stack, candidate_data, {
		"current": current,
		"player_cell": _player_cell,
		"pack_center": (
			_animal_social_center(animal)
			if not String(animal.social_group_id).is_empty()
			else null
		),
		"distance_to_tag": Callable(self, "_animal_behavior_distance_to_tag"),
	})


func _animal_behavior_cell_data(cell: Vector2i) -> Dictionary:
	var context = _cell_context_for_query(cell)
	return {
		"cell": cell,
		"height": _stand_level(context.height),
		"water_depth": context.water_depth,
		"water_clearance": _water_clearance(cell, 1),
		# 通行约束使用 surface class；材质与 biome 细节都保留在 tags 中。
		"surface_id": &"water" if context.is_water else &"land",
		"surface_kind": context.surface_id,
		"tags": context.tag_list(),
	}


func _cell_context_for_query(cell: Vector2i):
	if _cell_states.has(cell):
		return _cell_states[cell].context
	return _sample_cell_context(cell)


## 水中格到最近陆地的曼哈顿安全层数。clearance=1 表示四个正交邻格
## 也全部是水，因此鱼的 32px 动画不会贴着岸线或半个身体压到泥地上。
func _water_clearance(cell: Vector2i, maximum_radius: int) -> int:
	var center_context = _cell_context_for_query(cell)
	if center_context == null or not center_context.is_water:
		return 0
	var scan_radius := maxi(0, maximum_radius)
	for distance in range(1, scan_radius + 1):
		for offset_y in range(-distance, distance + 1):
			var offset_x_abs := distance - absi(offset_y)
			var x_offsets := (
				[0]
				if offset_x_abs == 0
				else [-offset_x_abs, offset_x_abs]
			)
			for offset_x in x_offsets:
				var nearby = _cell_context_for_query(
					cell + Vector2i(offset_x, offset_y)
				)
				if nearby == null or not nearby.is_water:
					return distance - 1
	return scan_radius


func _community_water_clearance_valid(
	definition: Dictionary,
	context
) -> bool:
	var habitat_value: Variant = definition.get("habitat", {})
	if not habitat_value is Dictionary:
		return true
	var habitat: Dictionary = habitat_value
	var required_clearance := maxi(
		0,
		int(habitat.get("minimum_water_clearance", 0))
	)
	return (
		required_clearance <= 0
		or _water_clearance(context.cell, required_clearance) >= required_clearance
	)


## Community habitat 的统一空间查询。它只读取 CellContext，不依赖已生成节点，
## 因而结果与流式生成顺序无关，火山/冰原等新模块也能直接查询自己的 tag。
func _ecology_near_tag(context, tag: StringName, radius: float) -> bool:
	if context == null:
		return false
	var center: Vector2i = context.cell
	var scan_radius := maxi(0, ceili(radius))
	var cache_key := "%d/%d/%s/%d" % [
		center.x,
		center.y,
		tag,
		scan_radius,
	]
	if _ecology_near_tag_cache.has(cache_key):
		return bool(_ecology_near_tag_cache[cache_key])
	for offset_y in range(-scan_radius, scan_radius + 1):
		var row_radius := scan_radius - absi(offset_y)
		for offset_x in range(-row_radius, row_radius + 1):
			var nearby = _cell_context_for_query(
				center + Vector2i(offset_x, offset_y)
			)
			if nearby.has_tag(tag):
				_ecology_near_tag_cache[cache_key] = true
				return true
	_ecology_near_tag_cache[cache_key] = false
	return false


func _animal_behavior_distance_to_tag(
	candidate: Dictionary,
	tag: StringName
) -> float:
	var center: Vector2i = candidate.get("cell", Vector2i.ZERO)
	var cache_key := "%d/%d/%s" % [center.x, center.y, tag]
	if _animal_behavior_distance_cache.has(cache_key):
		return float(_animal_behavior_distance_cache[cache_key])
	var nearest := INF
	var scan_radius := _animal_behavior_tag_scan_radius
	for offset_y in range(-scan_radius, scan_radius + 1):
		var row_radius := scan_radius - absi(offset_y)
		for offset_x in range(-row_radius, row_radius + 1):
			var distance := absi(offset_x) + absi(offset_y)
			if float(distance) >= nearest:
				continue
			var context = _cell_context_for_query(
				center + Vector2i(offset_x, offset_y)
			)
			if context.has_tag(tag):
				nearest = float(distance)
	_animal_behavior_distance_cache[cache_key] = nearest
	return nearest


func _animal_social_center(animal: AnimatedSprite2D) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for other_value in _animals.values():
		var other: AnimatedSprite2D = other_value
		if (
			not is_instance_valid(other)
			or not other.visible
			or other.social_group_id != animal.social_group_id
		):
			continue
		total += Vector2(other.grid_cell)
		count += 1
	return total / count if count > 0 else Vector2(animal.grid_cell)


func _animal_wait(origin: Vector2i, step_index: int) -> float:
	return ANIMAL_WAIT_MIN + _cell_rand(origin, 8200 + step_index * 53) * ANIMAL_WAIT_SPAN


func _animal_bout_steps(animal: AnimatedSprite2D) -> int:
	var step_count: int = int(animal.move_steps_max) - int(animal.move_steps_min) + 1
	if step_count <= 1:
		return int(animal.move_steps_min)
	return int(animal.move_steps_min) + int(
		_cell_rand(animal.origin_cell, 8300 + animal.bout_index * 67) * step_count
	) % step_count


func _animal_step_pause(animal: AnimatedSprite2D) -> float:
	return lerpf(
		animal.step_pause_min,
		animal.step_pause_max,
		_cell_rand(animal.origin_cell, 8400 + animal.step_index * 71)
	)


## 生成互不重叠的水面/侧壁 mask。顶面在所有水格只绘制一次；侧壁只用于岸线外轮廓。
func _make_water_face_texture(face: StringName) -> ImageTexture:
	var img := Image.create(TILE_W, TILE_W, false, Image.FORMAT_RGBA8)
	for y in TILE_W:
		for x in TILE_W:
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			var dx := absf(px - TILE_W * 0.5)
			var top_y := 6.0 + dx * 0.5
			var seam_y := 22.0 - dx * 0.5
			var inside_top := py >= top_y and py < seam_y
			var inside_left := px < TILE_W * 0.5 and py >= seam_y and py < 24.0 + px * 0.5
			var inside_right := px >= TILE_W * 0.5 and py >= seam_y and py < 32.0 - (px - 16.0) * 0.5
			var inside := (
				(face == &"surface" and inside_top)
				or (face == &"left" and inside_left)
				or (face == &"right" and inside_right)
			)
			if inside:
				img.set_pixel(x, y, WATER_COLOR)
	return ImageTexture.create_from_image(img)


## 湖底从所属生态的基础方块取色，但随水深向统一深蓝收敛：浅水保留细节，深水不露网格。
func _make_underwater_ground_texture(
	water_depth: int,
	base_texture: Texture2D
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
				WATER_DEPTH_COLOR,
				depth_blend
			)
			underwater_pixel.a = pixel.a
			image.set_pixel(x, y, underwater_pixel)
	return ImageTexture.create_from_image(image)


func _underwater_flora_modulate(water_depth: int) -> Color:
	var visibility := 0.78 if water_depth <= 1 else 0.48
	return Color(0.72, 0.88, 0.94, visibility)


## 把非 32x32 的方块贴图底部对齐补到 32x32（顶面菱形中心与其他 tile 一致）
func _process_terrain_material_texture(
	texture: Texture2D,
	_texture_path: String
) -> Texture2D:
	return _pad_texture_to_32(texture)


func _pad_texture_to_32(tex: Texture2D) -> ImageTexture:
	var src := tex.get_image()
	if src.get_width() == TILE_W and src.get_height() == TILE_W:
		return ImageTexture.create_from_image(src)
	var img := Image.create(TILE_W, TILE_W, false, Image.FORMAT_RGBA8)
	img.blit_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i(0, TILE_W - src.get_height()))
	return ImageTexture.create_from_image(img)


# ---------- 角色 ----------

func _setup_player() -> void:
	_player = Sprite2D.new()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			var border := x == 0 or y == 0 or x == 7 or y == 7
			img.set_pixel(x, y, Color(0.5, 0.08, 0.1) if border else Color(0.95, 0.35, 0.3))
	_player.texture = ImageTexture.create_from_image(img)
	_player.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_player)


## 玩家节点也使用脚点排序代理；offset 只负责把像素补偿回真实脚点，镜头不再跟随代理坐标。
func _set_player_render_position(visual_position: Vector2, sort_y: float) -> void:
	_player.position = Vector2(visual_position.x, sort_y)
	_player.offset = Vector2(
		0,
		visual_position.y - sort_y - _player.texture.get_height() / 2.0
	)


func _player_movement_sort_y() -> float:
	# 玩家和动物共用支撑面排序规则，避免红点移动时也被共面地板切开。
	return IsometricDepthSort.moving_support_sort_y(
		_move_sort_from,
		_move_sort_to,
		_move_level_from,
		_move_level_to,
		_move_t,
		PLAYER_SORT_BIAS
	)


func _player_occlusion_sort_y() -> float:
	# 移动中的渲染代理会暂时取两个支撑面的前侧排序键，防止共面地板
	# 切开人物；落地后遮挡检测必须改用目标格的标准键，不能依赖进入方向。
	if _move_t >= 1.0:
		return _move_sort_to
	return _player.position.y


func _player_world_rect() -> Rect2:
	var texture_size := _player.texture.get_size()
	return Rect2(
		_player_visual_position - Vector2(texture_size.x * 0.5, texture_size.y),
		texture_size
	).grow(1.0)


func _player_current_stand_level() -> float:
	return lerpf(
		_move_level_from,
		_move_level_to,
		clampf(_move_t, 0.0, 1.0)
	)


func _column_draws_after_player(view: Node2D) -> bool:
	if view.z_index != _player.z_index:
		return view.z_index > _player.z_index
	return (
		view.position.y
		> _player_occlusion_sort_y() + PLAYER_OCCLUSION_SORT_EPSILON
	)


func _player_occlusion_screen_rect(core_rect: Rect2) -> Rect2:
	return Rect2(
		core_rect.position - PLAYER_OCCLUSION_SCREEN_MARGIN,
		core_rect.size + PLAYER_OCCLUSION_SCREEN_MARGIN * 2.0
	)


## 完全按最终屏幕投影收集遮挡 block。高山柱即使逻辑锚点离玩家很远，
## 只要投影落到人物身上，仍会成为 core seed；halo 只负责形成连贯的视觉窗口。
func _collect_player_occlusion_state() -> Dictionary:
	var empty_state := {"blocks": {}, "core_block_count": 0}
	if _player == null or _player.texture == null:
		return empty_state
	var core_rect := _player_world_rect()
	var screen_rect := _player_occlusion_screen_rect(core_rect)
	var player_stand_level := _player_current_stand_level()
	var core_cells := {}
	var halo_blocks := {}
	var core_block_count := 0
	for cell_value in _cells.keys():
		var cell: Vector2i = cell_value
		var view: Node2D = _cells[cell]
		if not is_instance_valid(view) or not _column_draws_after_player(view):
			continue
		var screen_indices: Array[int] = view.player_occluding_block_indices(
			screen_rect,
			player_stand_level
		)
		if screen_indices.is_empty():
			continue
		halo_blocks[cell] = screen_indices
		var core_indices: Array[int] = view.player_occluding_block_indices(
			core_rect,
			player_stand_level
		)
		if not core_indices.is_empty():
			core_cells[cell] = true
			core_block_count += core_indices.size()
	if core_cells.is_empty():
		return empty_state

	# 只沿画面 halo 内的相邻地形扩展；所有真正覆盖人物的 seed 都无条件保留。
	var selected_blocks := {}
	var pending: Array[Vector2i] = []
	for cell_value in core_cells.keys():
		pending.append(cell_value)
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		if selected_blocks.has(cell) or not halo_blocks.has(cell):
			continue
		selected_blocks[cell] = halo_blocks[cell]
		for direction_value in ANIMAL_DIRECTIONS:
			var direction: Vector2i = direction_value
			var neighbor: Vector2i = cell + direction
			if halo_blocks.has(neighbor) and not selected_blocks.has(neighbor):
				pending.append(neighbor)
	return {
		"blocks": selected_blocks,
		"core_block_count": core_block_count,
	}


func _collect_player_occluder_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var state: Dictionary = _collect_player_occlusion_state()
	for cell_value in (state["blocks"] as Dictionary).keys():
		result.append(cell_value)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return result


func _player_occlusion_target_alpha(core_block_count: int) -> float:
	if core_block_count <= 0:
		return 1.0
	return PLAYER_OCCLUSION_BLOCK_ALPHA


func _player_occlusion_needs_rebuild() -> bool:
	var stand_level := _player_current_stand_level()
	var sort_y := _player_occlusion_sort_y()
	return (
		_player_occlusion_dirty
		or not _player_occlusion_last_visual_position.is_equal_approx(_player_visual_position)
		or not is_equal_approx(_player_occlusion_last_sort_y, sort_y)
		or not is_equal_approx(_player_occlusion_last_stand_level, stand_level)
	)


func _update_player_occlusion(delta: float) -> void:
	if _player_occlusion_needs_rebuild():
		var state := _collect_player_occlusion_state()
		var next_cells: Dictionary = state["blocks"]
		var target_alpha := _player_occlusion_target_alpha(int(state["core_block_count"]))
		for cell_value in _player_occluder_cells.keys():
			var cell: Vector2i = cell_value
			if next_cells.has(cell) or not _cells.has(cell):
				continue
			_cells[cell].set_player_occlusion_blocks([], 1.0)
			_player_occlusion_fading_cells[cell] = true
		for cell_value in next_cells.keys():
			var cell: Vector2i = cell_value
			if not _cells.has(cell):
				continue
			_cells[cell].set_player_occlusion_blocks(next_cells[cell], target_alpha)
			_player_occlusion_fading_cells[cell] = true
		_player_occluder_cells = next_cells
		_player_occlusion_dirty = false
		_player_occlusion_last_visual_position = _player_visual_position
		_player_occlusion_last_sort_y = _player_occlusion_sort_y()
		_player_occlusion_last_stand_level = _player_current_stand_level()

	for cell_value in _player_occlusion_fading_cells.keys():
		var cell: Vector2i = cell_value
		if not _cells.has(cell):
			_player_occlusion_fading_cells.erase(cell)
			continue
		var view: Node2D = _cells[cell]
		var settled: bool = view.advance_player_occlusion(delta)
		if settled:
			_player_occlusion_fading_cells.erase(cell)


func get_player_occluder_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell_value in _player_occluder_cells.keys():
		result.append(cell_value)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return result


## 角色站立的层号：陆地为柱顶，水面为水位线
func _stand_level(q: int) -> int:
	return maxi(q, WATER_SURFACE_LEVEL)


func _cell_feet_pos(cell: Vector2i) -> Vector2:
	var q := _quantize(cell.x, cell.y)
	return _grid_to_screen(cell, _stand_level(q))


## WASD 与上下方向键移动；左右方向键保留给视角连续旋转。
func _input_dir() -> Vector2i:
	if is_world_map_open():
		return Vector2i.ZERO
	if Input.is_action_pressed("ui_up") or Input.is_physical_key_pressed(KEY_W):
		return Vector2i(0, -1)
	if Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_S):
		return Vector2i(0, 1)
	if Input.is_physical_key_pressed(KEY_A):
		return Vector2i(-1, 0)
	if Input.is_physical_key_pressed(KEY_D):
		return Vector2i(1, 0)
	return Vector2i.ZERO


func _try_move(d: Vector2i) -> void:
	if is_world_map_open():
		return
	_move_from_cell = _player_cell
	_move_level_from = _stand_level(_quantize(_player_cell.x, _player_cell.y))
	_player_cell += d
	_move_level_to = _stand_level(_quantize(_player_cell.x, _player_cell.y))
	_sync_weather_environment()
	_move_from = _player_visual_position
	_move_to = _cell_feet_pos(_player_cell)
	_move_sort_from = _column_sort_y(_move_from_cell) + PLAYER_SORT_BIAS
	_move_sort_to = _column_sort_y(_player_cell) + PLAYER_SORT_BIAS
	_move_t = 0.0
	_set_player_render_position(_player_visual_position, _player_movement_sort_y())
	_stream_center = _player_cell
	_update_streaming()
	_reveal()
	_update_minimap()


func _process(delta: float) -> void:
	if _iso_view.advance(delta, _continuous_view_rotation()):
		_refresh_view_projection()
	if _move_t < 1.0:
		var speed := fast_multiplier if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
		_move_t = minf(1.0, _move_t + delta / move_time * speed)
		_player_visual_position = _move_from.lerp(_move_to, _move_t)
		_set_player_render_position(
			_player_visual_position,
			_player_movement_sort_y()
		)
	else:
		if not is_world_map_open():
			var d := _input_dir()
			if d != Vector2i.ZERO:
				_try_move(d)
	_update_player_occlusion(delta)
	_update_animals(delta)
	if _audio != null:
		_audio.update_animal_sounds(_animals.values(), _player_cell, delta)
	# 战斗模式：相机聚焦战场（中心 + 平移偏移），跳过跟随玩家的 lerp
	if _battle_active:
		_update_battle_edge_pan(delta)  # 边缘滚屏：鼠标在视口边缘时累加偏移
		_set_camera_position(_battle_focus_world_pos + _battle_cam_offset)
	else:
		# 逻辑状态不做像素取整，避免从已量化的 Camera2D.position 反复积分
		# 而丢失亚像素进度；仅最终渲染位置按当前 zoom 对齐像素网格。
		var camera_blend := 1.0 - exp(
			-camera_smoothing_speed * maxf(delta, 0.0)
		)
		_camera_smooth_position = _camera_smooth_position.lerp(
			_player_visual_position,
			camera_blend
		)
		_set_camera_position(_camera_smooth_position)
	_sync_depth_of_field_focus()
	if _ambient_registry != null:
		var viewport_size := get_viewport_rect().size
		_ambient_registry.update_observer_all(
			{
				"player_cell": _player_cell,
				"player_world_position": _player_visual_position,
				"player_screen_position": viewport_size * 0.5 + (
					_player_visual_position - _cam.position
				) * _cam.zoom,
				"camera_world_position": _cam.position,
				"viewport_size": viewport_size,
				"canvas_transform": get_viewport().get_canvas_transform(),
				"zoom": _cam.zoom,
				"world_seed": _current_seed,
				"map_open": is_world_map_open(),
				"allow_flyovers": not is_world_map_open(),
			},
			delta
		)


# ---------- 小地图 ----------

func _setup_minimap() -> void:
	_minimap_img = Image.create(MINIMAP_SIZE, MINIMAP_SIZE, false, Image.FORMAT_RGBA8)
	_minimap_img.fill(Color.BLACK)
	_minimap_tex = ImageTexture.create_from_image(_minimap_img)
	var layer := CanvasLayer.new()
	layer.layer = 100
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1, 0.9)
	bg.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bg.offset_left = -MINIMAP_SIZE - 12
	bg.offset_top = 8
	bg.offset_right = -8
	bg.offset_bottom = MINIMAP_SIZE + 12
	var rect := TextureRect.new()
	rect.texture = _minimap_tex
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.position = Vector2(2, 2)
	bg.add_child(rect)
	layer.add_child(bg)
	add_child(layer)


## 角色周围 sight_radius 范围变为已探索（永久保留）
func _reveal() -> void:
	for dy in range(-sight_radius, sight_radius + 1):
		for dx in range(-sight_radius, sight_radius + 1):
			var cell := _player_cell + Vector2i(dx, dy)
			if not _explored.has(cell):
				var context = _sample_cell_context(cell)
				_explored[cell] = _map_color_for_context(context)


func _update_minimap() -> void:
	var half := MINIMAP_SIZE / 2
	for py in MINIMAP_SIZE:
		for px in MINIMAP_SIZE:
			var cell := _player_cell + Vector2i(px - half, py - half)
			var c: Color = _explored.get(cell, Color.BLACK)
			_minimap_img.set_pixel(px, py, c)
	_minimap_img.set_pixel(half, half, Color(1.0, 0.2, 0.2))  # 角色标记
	_minimap_tex.update(_minimap_img)


func _minimap_color(_q: int, _biome: int, cell: Vector2i) -> Color:
	var context = _sample_cell_context(cell)
	return _map_color_for_context(context)


func _map_color_for_context(context, sampler = null) -> Color:
	var color_sampler = sampler if sampler != null else _terrain_sampler
	if int(context.height) <= WATER_MAX:
		return Color(0.08, 0.2, 0.5).lerp(
			Color(0.3, 0.6, 0.95),
			float(context.height) / float(WATER_MAX)
		)
	if context.is_shore or context.surface_id in [&"rock", &"mossy_rock"]:
		return _terrain_materials.get_minimap_color(
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
	return _terrain_materials.get_minimap_color(
		context.surface_id,
		context.biome_id
	)


# ---------- 相机 / HUD / 输入 ----------

func _setup_camera() -> void:
	_cam = Camera2D.new()
	_cam.enabled = true
	# 内建 smoothing 会让实际 canvas 中心落在亚像素上；本项目需要保持
	# nearest 像素安全，因此在 _process() 中保存独立浮点状态后再量化输出。
	_cam.position_smoothing_enabled = false
	_cam.rotation_smoothing_enabled = false
	add_child(_cam)
	_apply_zoom()


func _setup_hud() -> void:
	_hud = GameHudScript.new()
	_hud.name = "GameHUD"
	_hud.battlefield_picked.connect(_on_battlefield_picked)
	_hud.editor_requested.connect(_open_map_editor)
	add_child(_hud)


func _setup_world_map() -> void:
	_world_map = WorldMapOverlayScript.new()
	_world_map.name = "WorldMapOverlay"
	add_child(_world_map)


func is_world_map_open() -> bool:
	return _world_map != null and _world_map.is_open()


func _toggle_world_map() -> void:
	if _world_map == null:
		return
	if _world_map.is_open():
		_world_map.close_map()
	else:
		var snapshot := _world_map_snapshot()
		_world_map.open_map(
			snapshot["colors"],
			snapshot["marker_cell"],
			snapshot["bounds"]
		)


func _world_map_snapshot() -> Dictionary:
	var radius := sight_radius * WORLD_MAP_RANGE_MULTIPLIER
	var world_span := radius * 2 + 1
	return {
		"colors": _explored,
		"marker_cell": _player_cell,
		"bounds": Rect2i(
			_player_cell - Vector2i.ONE * radius,
			Vector2i.ONE * world_span
		),
	}


func _handle_world_map_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_M or event.keycode == KEY_M:
			_toggle_world_map()
			return true
		if is_world_map_open():
			if event.keycode == KEY_ESCAPE:
				_world_map.close_map()
			return true
	return is_world_map_open()


func _unhandled_input(event: InputEvent) -> void:
	# B1 就地战斗模式：先处理拖拽平移（中键/空格+左键），再走整体短路
	if _battle_active:
		if _handle_battle_camera_input(event):
			get_viewport().set_input_as_handled()
			return
	# B1 就地战斗模式：整体短路，事件转发给 BattleSystem（照搬 world_map 模态范式）
	if _battle_active and _handle_battle_input(event):
		get_viewport().set_input_as_handled()
		return
	if _handle_world_map_input(event):
		# 地图是模态 UI；鼠标缩放、触控手势和背景快捷键都不应穿透。
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_view_dragging = event.pressed
		if event.pressed:
			_view_drag_last_x = event.position.x
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _view_dragging:
		var drag_dx: float = event.position.x - _view_drag_last_x
		_view_drag_last_x = event.position.x
		_iso_view.drag_by(drag_dx)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_step(1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_step(-1)
			get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		_pinch_factor *= event.factor
		if _pinch_factor >= PINCH_THRESHOLD:
			_zoom_step(1)
			_pinch_factor = 1.0
		elif _pinch_factor <= 1.0 / PINCH_THRESHOLD:
			_zoom_step(-1)
			_pinch_factor = 1.0
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R and event.ctrl_pressed:
			_regenerate(0)
		elif event.physical_keycode == KEY_R:
			_iso_view.reset_rotation()
		elif event.physical_keycode == KEY_Z:
			_iso_view.rotate_step(-1)
		elif event.physical_keycode == KEY_X:
			_iso_view.rotate_step(1)
		elif event.physical_keycode == KEY_T and _weather != null:
			if event.shift_pressed:
				_weather.set_auto_mode()
			else:
				_weather.cycle_manual_weather()
		elif event.physical_keycode == KEY_N and _day_night != null:
			if event.shift_pressed:
				_day_night.set_auto_mode()
			else:
				_day_night.toggle_manual_night()
		elif event.physical_keycode == KEY_B and _depth_of_field != null:
			_depth_of_field.toggle()
		elif event.physical_keycode == KEY_P or event.keycode == KEY_P:
			# 进入战棋（融合进 pixel_world 的战术 RPG 系统）
			# P = Play battle；physical_keycode 和 keycode 都匹配，确保注入输入也能触发
			_enter_battle()
		elif (event.physical_keycode == KEY_O or event.keycode == KEY_O) and not _battle_active:
			# 打开/关闭 JSON 战场加载列表（调试入口，与 P 的随机遭遇战互补）。
			# B1 就地战斗进行中不开（_battle_active 时输入已被战斗层接管）。
			if _hud != null:
				_hud.toggle_battlefield_panel()
		elif (
			(event.physical_keycode == KEY_E or event.keycode == KEY_E)
			and event.ctrl_pressed
			and not _battle_active
		):
			# Ctrl+E 打开地图编辑器；单独 E 用于连续顺时针旋转。
			if not is_world_map_open():
				_open_map_editor()
		elif event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			_zoom_step(1)
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			_zoom_step(-1)
		elif event.keycode == KEY_F:
			_zoom_index = DEFAULT_ZOOM_INDEX
			_apply_zoom()


func _setup_day_night() -> void:
	_day_night = DayNightSystemScript.new()
	_day_night.name = "DayNightSystem"
	add_child(_day_night)
	var args := OS.get_cmdline_user_args()
	var time_arg := args.find("--time")
	if time_arg == -1 or time_arg + 1 >= args.size():
		return
	var requested := String(args[time_arg + 1]).to_lower()
	match requested:
		"day":
			_day_night.set_manual_night(false)
		"night":
			_day_night.set_manual_night(true)
		"auto":
			_day_night.set_auto_mode()
		_:
			push_warning("--time 只接受 day / night / auto")
			return
	_day_night.snap_transition()


func _setup_depth_of_field() -> void:
	_depth_of_field = DepthOfFieldSystemScript.new()
	_depth_of_field.name = "DepthOfFieldSystem"
	add_child(_depth_of_field)
	var args := OS.get_cmdline_user_args()
	var depth_arg := args.find("--dof")
	if depth_arg == -1 or depth_arg + 1 >= args.size():
		return
	var requested := String(args[depth_arg + 1]).to_lower()
	if requested in ["on", "true", "1"]:
		_depth_of_field.set_enabled(true)
	elif requested in ["off", "false", "0"]:
		_depth_of_field.set_enabled(false)
	else:
		push_warning("--dof 只接受 on / off")


func _sync_depth_of_field_focus() -> void:
	if _depth_of_field == null or _cam == null:
		return
	var viewport_size := get_viewport_rect().size
	var player_screen_position := (
		viewport_size * 0.5
		+ (_player_visual_position - _cam.position) * _cam.zoom
	)
	_depth_of_field.set_focus_screen_position(player_screen_position, viewport_size)


func _setup_audio() -> void:
	_audio = WorldAudioSystemScript.new()
	_audio.name = "WorldAudioSystem"
	var audible_species: Array = []
	for species_id_value in _animal_species:
		var species: Dictionary = _animal_species[species_id_value]
		var metadata: Dictionary = species.get("metadata", {})
		if not bool(metadata.get("silent", false)):
			audible_species.append(String(species_id_value))
	_audio.configure_animal_species(audible_species)
	add_child(_audio)
	if not _audio.is_config_valid():
		push_warning("世界音频未启用：配置或资源无效")
		return
	if _day_night != null:
		_day_night.night_amount_changed.connect(_audio.set_night_amount)
		_audio.set_night_amount(_day_night.get_night_amount(), true)


func _setup_fireflies() -> void:
	_ambient_registry = AmbientRegistryScript.new()
	_ambient_registry.name = "AmbientRegistry"
	add_child(_ambient_registry)
	if not _ambient_registry.register_species_catalog(_ambient_species):
		push_error("Ambient registry 配置无效: %s" % [_ambient_registry.get_errors()])
	_fireflies = _ambient_registry.get_renderer(&"firefly")
	if _day_night != null:
		_day_night.night_amount_changed.connect(
			_ambient_registry.set_all_environment_amount
		)
		_ambient_registry.set_all_environment_amount(
			_day_night.get_night_amount()
		)


func _setup_weather() -> void:
	_weather = WeatherSystemScript.new()
	_weather.name = "WeatherSystem"
	add_child(_weather)
	_weather.water_impact_requested.connect(_on_weather_water_impact)
	_weather.status_changed.connect(_sync_weather_audio)
	var args := OS.get_cmdline_user_args()
	var weather_arg := args.find("--weather")
	if weather_arg != -1 and weather_arg + 1 < args.size():
		var requested := StringName(args[weather_arg + 1].to_lower())
		if requested == &"auto":
			_weather.set_auto_mode()
		elif not _weather.set_manual_weather(requested):
			push_warning("--weather 只接受 clear / rain / snow / auto")
		else:
			_weather.snap_transition()
	_sync_weather_audio(true)


func _sync_weather_audio(snap := false) -> void:
	if _weather == null or _audio == null or not _audio.is_config_valid():
		return
	_audio.set_rain_amount(
		1.0 if _weather.get_effective_weather() == &"rain" else 0.0,
		snap
	)


func _sync_weather_environment() -> void:
	if _weather == null:
		return
	var context = _sample_cell_context(_player_cell)
	var weather_tags: Array[StringName] = _terrain_sampler.biome_registry.weather_tags(
		_player_cell,
		context.height,
		context.biome_id
	)
	_weather.set_environment(
		context.height,
		&"snow_capable" in weather_tags,
		_snow_base_level
	)


## 世界空间粒子负责雨雪；这里只把少量代表性落点反投影到真实水格。
## 涟漪交给该水柱批绘制，因而位于水面之上、荷叶之下，并继续服从地图 Y-sort。
func _on_weather_water_impact(
	viewport_position: Vector2,
	kind: StringName,
	strength: float
) -> void:
	var canvas_inverse := get_viewport().get_canvas_transform().affine_inverse()
	var global_world := canvas_inverse * viewport_position
	var world_position := to_local(global_world)
	var grid_position := _iso_view.screen_to_grid(
		world_position - WATER_SURFACE_VISUAL_OFFSET,
		WATER_SURFACE_LEVEL
	)
	var cell := Vector2i(roundi(grid_position.x), roundi(grid_position.y))
	if not _water_cells.has(cell):
		return
	var surface_center := (
		_grid_to_screen(cell, WATER_SURFACE_LEVEL)
		+ WATER_SURFACE_VISUAL_OFFSET
	)
	var local_offset := world_position - surface_center
	var grid_offset := _iso_view.screen_to_grid(local_offset)
	var edge_ratio := absf(grid_offset.x) + absf(grid_offset.y)
	if edge_ratio > 0.94:
		return
	var edge_clearance := 1.0 - edge_ratio
	var maximum_radius := clampf(3.0 + edge_clearance * 10.0, 3.0, 10.5)
	var column = _cells[cell]
	column.spawn_water_ripple(local_offset, kind, strength, maximum_radius)


func _zoom_step(delta: int) -> void:
	var next_index := clampi(_zoom_index + delta, 0, ZOOM_LEVELS.size() - 1)
	if next_index == _zoom_index:
		return
	_zoom_index = next_index
	_apply_zoom()


func _apply_zoom() -> void:
	var value := ZOOM_LEVELS[_zoom_index]
	_cam.zoom = Vector2(value, value)
	_set_camera_position(_camera_smooth_position)
	_sync_depth_of_field_focus()
	if _weather != null:
		_weather.refresh_particle_field()
	if _ambient_registry != null:
		# Camera2D 的 canvas transform 在本帧末尾生效；延后一帧重新分配
		# 有限表现槽位，保证缩放后仍优先服务当前视口内的 ambient。
		_ambient_registry.call_deferred("refresh_all")


func _set_camera_position(world_position: Vector2) -> void:
	var snap_step := Vector2.ONE / _cam.zoom.x
	_cam.position = world_position.snapped(snap_step)


## 首次生成、换种子和自动截图属于瞬移，不应把旧视角缓慢拖进新位置。
func _snap_camera_position(world_position: Vector2) -> void:
	_camera_smooth_position = world_position
	_set_camera_position(world_position)
	_cam.force_update_scroll()


## 命令行带 `-- --shot` 时：渲染后截图到 /tmp/pixel_world_shot.png 并退出（自动验证用）
## 附加 `--walk` 会先向屏幕上方走 20 格再截图（回归测试：曾在此方向出现流式断层）
## 附加 `--shot-zoom 0.5|1|2|3|4` 可验证各个像素安全倍率。
## 附加 `--shot-delay 秒数` 可等待动画进入稳定帧，用于雨雪与水面涟漪回归。
## 附加 `--shot-map` 会打开基础色世界地图，用于模态 UI 视觉回归。
## 附加 `--shot-cell X Y` 可在固定逻辑格生成视窗，复现生态与群落实机截图。
## 附加 `--shot-output 路径` 可覆盖默认的 /tmp 输出位置。
func _shot_and_quit() -> void:
	var args := OS.get_cmdline_user_args()
	if "--walk" in args:
		for i in 20:
			_try_move(Vector2i(-1, -1))
			_player_visual_position = _move_to
			_move_t = 1.0
			_set_player_render_position(_player_visual_position, _move_sort_to)
	_zoom_index = 0  # 默认 0.5x 总览能看到逻辑方形投影后的完整菱形边界
	var zoom_arg := args.find("--shot-zoom")
	if zoom_arg != -1 and zoom_arg + 1 < args.size():
		var requested_zoom := float(args[zoom_arg + 1])
		var requested_index := ZOOM_LEVELS.find(requested_zoom)
		if requested_index != -1:
			_zoom_index = requested_index
		else:
			push_warning("--shot-zoom 只接受 0.5 / 1 / 2 / 3 / 4")
	_apply_zoom()
	# 最终缩放倍率确定后再同步屏幕中心，确保自动截图不带缓动残差。
	_snap_camera_position(_player_visual_position)
	if "--shot-map" in args:
		_toggle_world_map()
	var delay_arg := args.find("--shot-delay")
	if delay_arg != -1 and delay_arg + 1 < args.size():
		var delay_seconds := maxf(0.0, float(args[delay_arg + 1]))
		if delay_seconds > 0.0:
			await get_tree().create_timer(delay_seconds).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var output_path := "/tmp/pixel_world_shot.png"
	var output_arg := args.find("--shot-output")
	if output_arg != -1 and output_arg + 1 < args.size():
		output_path = String(args[output_arg + 1])
	if output_path.begins_with("res://") or output_path.begins_with("user://"):
		output_path = ProjectSettings.globalize_path(output_path)
	var output_dir := output_path.get_base_dir()
	if not output_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(output_dir)
	var save_error := img.save_png(output_path)
	if save_error != OK:
		push_error("自动截图保存失败: %s (%d)" % [output_path, save_error])
	get_tree().quit()


# ============================================================
# 战棋入口（融合自 phaserjs 战术 RPG）
# ============================================================
## 按 P 键进入战棋：从玩家周围真实地形采样 21×21 战场，切到 Battle.tscn。
## SceneArgs 是 autoload 单例（见 project.godot [autoload]），负责跨场景传参。
func _enter_battle() -> void:
	# L1 埋点：战棋入口被触发（按 AGENTS.md 调试埋点强制原则）
	print("[world] 进入战棋（按 P）→ 中心=%s 模式=%s" % [
		str(_player_cell), "就地" if Settings.battle_inline_mode else "独立场景"])
	var chapter := WorldToChapter.world_to_chapter(_terrain_sampler, _player_cell, 10, _current_seed)
	if Settings.battle_inline_mode:
		# B1 就地模式：不切场景，在 main.gd 下挂战斗层
		_enter_battle_inline(chapter)
		return
	# B2 独立场景模式：切到 Battle.tscn
	SceneArgs.battle_args = {
		"chapter": chapter,
		"return_to": "res://main.tscn",
		"hosting": false,
	}
	get_tree().change_scene_to_file("res://scenes/Battle.tscn")


## 从 JSON 战场文件进入战棋（HUD 战场列表点选触发）。
## JSON 声明的战场与真实世界地形无关（无 world_origin），固定走 B2 独立场景模式，
## 不受 Settings.battle_inline_mode 影响。
func _enter_battlefield(path: String) -> void:
	var result: Dictionary = BattlefieldLoaderScript.load_battlefield(path)
	if not bool(result.get("ok", false)):
		var msg := String(result.get("error", "未知错误"))
		push_error("[world] 战场加载失败: %s → %s" % [path, msg])
		if _hud != null:
			_hud.show_battlefield_error(msg)
		return
	var chapter: Dictionary = result["chapter"]
	var info: Dictionary = result["info"]
	# L1 埋点：JSON 战场入口（按 AGENTS.md 调试埋点强制原则）
	print("[world] 加载 JSON 战场: %s（%dx%d, 我方%d/敌方%d, hosting=%s）→ 独立场景模式" % [
		info.get("name", path), chapter.width, chapter.height,
		(chapter.playerUnits as Array).size(), (chapter.enemyUnits as Array).size(),
		str(info.get("hosting", false)),
	])
	SceneArgs.battle_args = {
		"chapter": chapter,
		"return_to": "res://main.tscn",
		"hosting": bool(info.get("hosting", false)),
	}
	get_tree().change_scene_to_file("res://scenes/Battle.tscn")


func _on_battlefield_picked(path: String) -> void:
	_enter_battlefield(path)


## 打开战场地图编辑器（E 键 / 战场面板「🛠 打开地图编辑器」按钮触发）。
## 编辑器保存的 JSON 落在 data/battlefields（或 user://battlefields），
## 返回后在战场列表（O 键）中即可开战。
func _open_map_editor() -> void:
	print("[world] 打开战场地图编辑器 → res://scenes/MapEditor.tscn")  # L1 埋点
	get_tree().change_scene_to_file("res://scenes/MapEditor.tscn")


# ============================================================
# B1 就地战斗模式（与 B2 切场景模式并存，由 Settings.battle_inline_mode 切换）
# ============================================================

## 进入就地战斗：备份相机/玩家状态 → 实例化 BattleSystem → 聚焦战场
func _enter_battle_inline(chapter: Dictionary) -> void:
	# 1. 备份世界探索状态
	_cam_pos_backup = _camera_smooth_position
	_zoom_index_backup = _zoom_index
	_player_visible_backup = _player.visible
	# 复位战场相机偏移（防止上次战斗残留）
	_battle_cam_offset = Vector2.ZERO
	_battle_pan_active = false
	# 2. 隐藏世界玩家红点（用战棋 UnitSprite 替代）
	_player.visible = false
	# 3. 相机聚焦战场中心（玩家位置 ≈ 战场中心），固定 zoom=2.0x
	_zoom_index = DEFAULT_ZOOM_INDEX  # 2 → 2.0x
	_apply_zoom()
	var center_world_cell := _player_cell
	_battle_focus_world_pos = _grid_to_screen(center_world_cell, _stand_level(_quantize(center_world_cell.x, center_world_cell.y)))
	_snap_camera_position(_battle_focus_world_pos)
	# 4. 实例化 BattleSystem 并注入 main.gd 引用
	SceneArgs.battle_args = {
		"chapter": chapter,
		"world": self,                  # B1 标记：main.gd 引用
		"hosting": false,
	}
	_battle_system = _BattleScript.new()
	_battle_system.name = "BattleSystem"
	_battle_system.battle_finished.connect(_exit_battle)
	add_child(_battle_system)
	# 5. 开启战斗模式（最后一步，避免 _ready 期间触发拦截）
	_battle_active = true


## 退出就地战斗：恢复世界探索状态
func _exit_battle(result: StringName) -> void:
	print("[world] 战斗结束（%s）→ 恢复世界探索" % String(result))
	_battle_active = false
	if _battle_system != null and is_instance_valid(_battle_system):
		_battle_system.queue_free()
	_battle_system = null
	# 复位战场相机偏移/平移状态
	_battle_cam_offset = Vector2.ZERO
	_battle_pan_active = false
	# 恢复相机/玩家
	_player.visible = _player_visible_backup
	_zoom_index = _zoom_index_backup
	_apply_zoom()
	_camera_smooth_position = _cam_pos_backup
	_set_camera_position(_cam_pos_backup)


## 战斗输入分发：把世界探索的输入事件转发给 BattleSystem。
## 返回 true = 消费事件（不让世界探索处理）；false = 放行给世界。
func _handle_battle_input(event: InputEvent) -> bool:
	if not _battle_active or _battle_system == null or not is_instance_valid(_battle_system):
		return false
	# 战斗期间禁用 P 键（避免重复触发）
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_P or event.keycode == KEY_P:
			return true  # 吞掉，不转发
	return false


## B1 战场拖拽平移：中键 / 空格+左键 拖拽时累加 _battle_cam_offset。
## 在 _unhandled_input 的 B1 分支调用（缩放键已由 _handle_battle_input 放行）。
func _handle_battle_camera_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# 中键拖拽；或按住空格时左键拖拽（与编辑器平移范式一致）
		var is_pan_button := mb.button_index == MOUSE_BUTTON_MIDDLE \
				or (mb.button_index == MOUSE_BUTTON_LEFT \
					and (Input.is_physical_key_pressed(KEY_SPACE) or _battle_pan_active))
		if not is_pan_button:
			return false
		if mb.pressed:
			# 起手若在 UI 上则不平移（避免误触按钮）
			if _is_battle_mouse_over_ui(mb.position):
				return false
			_battle_pan_active = true
			_battle_pan_last = mb.position
		else:
			_battle_pan_active = false
		return true
	elif event is InputEventMouseMotion and _battle_pan_active:
		var mm := event as InputEventMouseMotion
		var zoom := _cam.zoom.x if _cam != null else 1.0
		# 屏幕拖拽反方向施加到相机（与 iso_board.pan 语义一致）
		_battle_cam_offset -= (mm.position - _battle_pan_last) / zoom
		_battle_pan_last = mm.position
		_clamp_battle_cam_offset()
		return true
	return false


## B1 战场边缘滚屏：鼠标距视口边缘 < 阈值时按方向累加 _battle_cam_offset。
## 拖拽中 / 鼠标在 UI 上时不触发。在 _process 的 B1 分支调用。
const _BATTLE_EDGE_PAN_MARGIN := 24.0   # 触发边缘滚屏的边距（像素）
const _BATTLE_EDGE_PAN_SPEED := 420.0   # 边缘滚屏速度（屏幕像素/秒 → 除以 zoom 转世界）
func _update_battle_edge_pan(delta: float) -> void:
	if _battle_pan_active or _cam == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var mouse := vp.get_mouse_position()
	var size := vp.get_visible_rect().size
	# 鼠标在窗口外 / 在 UI 上 → 不滚屏
	if mouse.x < 0 or mouse.y < 0 or mouse.x > size.x or mouse.y > size.y:
		return
	if _is_battle_mouse_over_ui(mouse):
		return
	var dir := Vector2.ZERO
	if mouse.x < _BATTLE_EDGE_PAN_MARGIN:
		dir.x -= 1.0
	elif mouse.x > size.x - _BATTLE_EDGE_PAN_MARGIN:
		dir.x += 1.0
	if mouse.y < _BATTLE_EDGE_PAN_MARGIN:
		dir.y -= 1.0
	elif mouse.y > size.y - _BATTLE_EDGE_PAN_MARGIN:
		dir.y += 1.0
	if dir == Vector2.ZERO:
		return
	var zoom := _cam.zoom.x
	# 边缘滚屏 = 相机往鼠标指向方向走（同向）：鼠标在右边缘 → 相机右移 → 看到右侧内容。
	# （与拖拽平移相反：拖拽是抓地图反方向拖，用 -=）
	_battle_cam_offset += dir * (_BATTLE_EDGE_PAN_SPEED / zoom) * delta
	_clamp_battle_cam_offset()


## 把 _battle_cam_offset 钳制在战场范围内（中心 ± radius 格的屏幕距离），
## 防止平移到未流式加载的空洞区域。radius=10 → 21×21 战场，留 1 格边距。
func _clamp_battle_cam_offset() -> void:
	const _BATTLE_RADIUS := 10
	# 战场对角方向的屏幕半径（x+y 方向最远）：radius 格 × (TILE_W/2) 的等距投影
	var max_dx := float(_BATTLE_RADIUS) * TILE_W * 0.5
	var max_dy := float(_BATTLE_RADIUS) * TILE_H * 0.5
	# 偏移允许范围放宽到对角（等距下 x、y 偏移耦合），用各自菱形半径的 1.5 倍作软上限
	_battle_cam_offset.x = clampf(_battle_cam_offset.x, -max_dx * 1.5, max_dx * 1.5)
	_battle_cam_offset.y = clampf(_battle_cam_offset.y, -max_dy * 1.5, max_dy * 1.5)


## 鼠标位置是否落在战场 UI（按钮/菜单）上。battle_ui 可能为空（B2 或未建好）。
func _is_battle_mouse_over_ui(screen_pos: Vector2) -> bool:
	if _battle_system == null or not is_instance_valid(_battle_system):
		return false
	var ui = _battle_system.get("battle_ui")
	if ui == null:
		return false
	return ui.is_over_ui(screen_pos)





## 公开查询：世界 cell → 站立层号（供战棋 UnitSprite 算高度）
func cell_stand_level(cell: Vector2i) -> int:
	return _stand_level(_quantize(cell.x, cell.y))


## 公开查询：屏幕坐标 → 世界 cell（供战棋 cell 拾取用）
func screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var world_pos := _screen_to_world_pos(screen_pos)
	var initial_grid := _iso_view.screen_to_grid(world_pos)
	var best_cell := Vector2i(roundi(initial_grid.x), roundi(initial_grid.y))
	var best_score := INF
	var seen := {}
	for guess_level in range(WATER_SURFACE_LEVEL, LEVELS * 3):
		var base_grid := _iso_view.screen_to_grid(world_pos, float(guess_level))
		var base := Vector2i(roundi(base_grid.x), roundi(base_grid.y))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var cell := base + Vector2i(dx, dy)
				if seen.has(cell):
					continue
				seen[cell] = true
				var lvl := _stand_level(_quantize(cell.x, cell.y))
				var local := world_pos - _grid_to_screen(cell, float(lvl))
				var grid_offset := _iso_view.screen_to_grid(local)
				var score := absf(grid_offset.x) + absf(grid_offset.y)
				if score < best_score:
					best_score = score
					best_cell = cell
	return best_cell


func screen_to_cell_in_rect(screen_pos: Vector2, origin: Vector2i, size: Vector2i) -> Vector2i:
	var world_pos := _screen_to_world_pos(screen_pos)
	var best_cell := origin
	var best_score := INF
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			var cell := Vector2i(x, y)
			var lvl := _stand_level(_quantize(cell.x, cell.y))
			var local := world_pos - _grid_to_screen(cell, float(lvl))
			var grid_offset := _iso_view.screen_to_grid(local)
			var score := absf(grid_offset.x) + absf(grid_offset.y)
			if score < best_score:
				best_score = score
				best_cell = cell
	return best_cell


func _screen_to_world_pos(screen_pos: Vector2) -> Vector2:
	var zoom := _cam.zoom.x if _cam != null else 1.0
	var cam_pos := _cam.position if _cam != null else Vector2.ZERO
	var viewport_center := get_viewport_rect().size * 0.5
	return (screen_pos - viewport_center) / zoom + cam_pos
