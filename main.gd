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
const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
const IsometricCamera3DScript = preload("res://scripts/iso/isometric_camera_3d.gd")
const WorldCameraNavigationScript = preload("res://scripts/iso/world_camera_navigation.gd")
const IsometricTerrain3DScript = preload("res://scripts/iso/isometric_terrain_3d.gd")
const IsometricDepthSort = preload("res://scripts/isometric_depth_sort.gd")
const WeatherSystemScript = preload("res://scripts/weather_system.gd")
const DayNightSystemScript = preload("res://scripts/day_night_system.gd")
const SunlightSystemScript = preload("res://scripts/sunlight_system.gd")
const WorldAudioSystemScript = preload("res://scripts/world_audio_system.gd")
const DepthOfFieldSystemScript = preload("res://scripts/depth_of_field_system.gd")
const GameHudScript = preload("res://scripts/game_hud.gd")
const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const WorldMapOverlayScript = preload("res://scripts/world_map_overlay.gd")
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
const EcologyConfigValidatorScript = preload(
	"res://scripts/world/ecology_config_validator.gd"
)
const EcologyConfigCompilerScript = preload(
	"res://scripts/world/ecology_config_compiler.gd"
)
const TerrainTextureCatalogScript = preload(
	"res://scripts/world/terrain_texture_catalog.gd"
)
const MinimapRendererScript = preload("res://scripts/world/minimap_renderer.gd")
const PlayerOcclusionControllerScript = preload(
	"res://scripts/world/player_occlusion_controller.gd"
)
const EcosystemMatchScript = preload("res://scripts/world/ecosystem_match.gd")
const PresentationStageScript = preload("res://scripts/world/presentation_stage.gd")
const FloraSpawnerScript = preload("res://scripts/world/flora_spawner.gd")
const WorldQueryServiceScript = preload("res://scripts/world/world_query_service.gd")
const FaunaStreamerScript = preload("res://scripts/world/fauna_streamer.gd")
const AnimalRuntimeScript = preload("res://scripts/world/animal_runtime.gd")


const ECOLOGY_MANIFEST_PATH := "res://config/ecology/manifest.json"
const ECOSYSTEM_CONFIG_PATH := "res://config/ecosystems.json"
const FLORA_LAYER_IDS := ["tree", "ground_cover", "decoration"]
const SORT_DEPTH_SCALE := 16.0  ## 默认角度下与旧版每格 128 的合成深度间距一致
const SORT_REBASE_DISTANCE := 4096
const WanderingAnimalScript = preload("res://scripts/wandering_animal.gd")

const ANIMAL_SORT_BIAS := WanderingAnimalScript.SORT_BIAS
const PLAYER_SORT_BIAS := 0.5
## 世界玩家使用的职业精灵图（data/professions.json 8 职业 id 之一；缺图回退占位红点）。
const PLAYER_SHEET_CLASS := &"swordsman"
const ANIMAL_FLEE_RADIUS := 6
const ANIMAL_FLEE_SPEED := 2.0
const ANIMAL_FLEE_DISTANCE_WEIGHT := 1000.0
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
const Landform = EcosystemMatchScript.Landform  ## 旧整数地物枚举（定义在 ecosystem_match.gd，值不变）
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
## 方块贴图目录：水面 mask、各地表补齐贴图与湖底弱化纹理（原 14 个散装贴图字段）
var _textures := TerrainTextureCatalogScript.new()
var _cells := {}     ## Vector2i -> bool；真实柱网格由 IsometricTerrain3D 按 chunk 合批
var _cell_states := {}  ## Vector2i -> CellState；生态、占用与导航的唯一逻辑来源
var _water_cells := {}  ## 当前流式窗口内的水格索引，供天气落点 O(1) 命中
var _animals := {}   ## 出生格 -> WanderingAnimal；出生格保持确定性生成身份
var _animal_groups = CommunityStateStoreScript.new(2048)
var _world_query := WorldQueryServiceScript.new()  ## 空间查询服务；near_tag 缓存随模块
var _explored := {}  ## Vector2i -> Color；探索时缓存基础色，地图打开时不再采样地形
var _cam: Camera3D
var _terrain: Node3D
var _hud
var _world_map
var _weather
var _day_night
var _sunlight
var _ambient_registry
## 兼容现有调试/契约读取；实际实例由 AmbientRegistry 按配置创建。
var _fireflies
var _audio
var _depth_of_field
var _current_seed := 0
var _world_rng = DeterministicRngScript.new(0)
var _sort_origin := Vector2i.ZERO
var _has_sort_origin := false
var _view_rotation_culling := false
var _view_dragging := false
var _view_drag_last_x := 0.0
var _zoom_index := DEFAULT_ZOOM_INDEX
var _pinch_factor := 1.0
var _camera_smooth_position := Vector2.ZERO
var _world_camera_navigation := WorldCameraNavigationScript.new()

# ---- B1 就地战斗模式字段（_battle_active=false 时全部不影响原行为）----
var _battle_active := false            # 战斗模式开关（照搬 is_world_map_open 范式）
var _battle_system: Node2D = null      # BattleSystem 实例（battle.gd 作为子节点）
var _battle_transition: CanvasLayer = null  # B2 切场景前的遭遇覆盖层（随 main 释放）
var _battle_transition_pending := false    # 覆盖播放期间吞输入并防止重复切场景
var _battle_focus_world_pos := Vector2.ZERO  # 战斗时相机聚焦的世界坐标
# 战场相机操控：B1 下相机归 main.gd，战场中心 + offset 即相机位置。
var _battle_cam_offset := Vector2.ZERO   # 平移偏移（实际屏幕像素，相对战场中心）
var _battle_pan_active := false          # 拖拽平移中（中键 / 空格+左键）
var _battle_pan_last := Vector2.ZERO     # 上次拖拽鼠标位置
# ActionAnim 的附加位移；焦点/角度/缩放仍由原相机管线管理。
var _battle_camera_kick_offset := Vector3.ZERO
# 进入战斗时备份的相机/玩家状态，退出时恢复
var _cam_pos_backup := Vector2.ZERO
var _zoom_index_backup := 0
var _player_visible_backup := true
# BattleSystem 脚本预加载
const _BattleScript := preload("res://scripts/scenes/battle.gd")
const _EncounterTransitionScript := preload("res://scripts/battle/encounter_transition.gd")

var _player: Sprite3D
var _player_facing := Vector3(0.0, 0.0, 1.0)
var _player_pose: StringName = CharacterSheet.POSE_IDLE
var _player_uses_sheet := false
var _player_last_yaw := 1.0e20
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
var _player_occlusion := PlayerOcclusionControllerScript.new()  ## 玩家植被遮挡控制器
var _minimap := MinimapRendererScript.new()  ## 小地图渲染器


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


## 生态配置编译已拆至 scripts/world/ecology_config_compiler.gd（按配置域拆分的
## 纯静态函数集）。这里保持原函数名与调用顺序：先编译 generation/species 域并
## 回填成员，再编译动物行为栈，最后编译 ecosystems/pool_selection 域并做整体校验。
func _compile_ecosystem_config() -> bool:
	var defaults := {
		"rock_level": rock_level,
		"peak_max": peak_max,
		"sea_threshold": _sea_threshold,
		"mountain_threshold": _mountain_threshold,
		"terrace_period": _terrace_period,
		"noise_octaves": _noise_octaves,
		"flora_conflict_seed": _flora_conflict_seed,
		"region_cell_size": _region_cell_size,
		"region_jitter": _region_jitter,
		"region_blend_width": _region_blend_width,
		"snow_base_level": _snow_base_level,
		"snow_temperature_level_scale": _snow_temperature_level_scale,
	}
	var generation_result: Dictionary = EcologyConfigCompilerScript.compile_generation(
		_ecosystem_config, defaults, FLORA_LAYER_IDS, LANDFORM_ID_TO_TYPE
	)
	if not generation_result.get("ok", false):
		push_error(String(generation_result.get("error", "")))
		return false
	_apply_generation_compiled(generation_result.get("values", {}))
	if not _compile_animal_behavior_stacks():
		return false
	var ecosystems_result: Dictionary = EcologyConfigCompilerScript.compile_ecosystems(
		_ecosystem_config
	)
	if not ecosystems_result.get("ok", false):
		push_error(String(ecosystems_result.get("error", "")))
		return false
	_apply_ecosystems_compiled(ecosystems_result.get("values", {}))
	return _validate_ecosystem_config()


## 回填 generation/species 域编译结果（赋值顺序与原内联实现一致；容器保持原引用）。
func _apply_generation_compiled(values: Dictionary) -> void:
	rock_level = int(values["rock_level"])
	peak_max = int(values["peak_max"])
	_sea_threshold = float(values["sea_threshold"])
	_mountain_threshold = float(values["mountain_threshold"])
	_terrace_period = float(values["terrace_period"])
	_noise_type = int(values["noise_type"])
	_fractal_type = int(values["fractal_type"])
	_noise_octaves = int(values["noise_octaves"])
	_noise_fields = values["noise_fields"]
	_flora_conflict_seed = int(values["flora_conflict_seed"])
	_flora_layer_configs = values["flora_layer_configs"]
	_region_cell_size = float(values["region_cell_size"])
	_region_jitter = float(values["region_jitter"])
	_region_blend_width = float(values["region_blend_width"])
	_landform_configs = values["landform_configs"]
	_landform_ids = values["landform_ids"]
	_landform_names = values["landform_names"]
	_landform_order = values["landform_order"]
	_landform_total_weight = float(values["landform_total_weight"])
	_snow_base_level = int(values["snow_base_level"])
	_snow_temperature_level_scale = float(values["snow_temperature_level_scale"])
	_plant_species = values["plant_species"]
	_animal_species = values["animal_species"]
	_ambient_species = values["ambient_species"]


## 回填 ecosystems/pool_selection 域编译结果。
func _apply_ecosystems_compiled(values: Dictionary) -> void:
	_ecosystems_by_id = values["ecosystems_by_id"]
	_ecosystem_order = values["ecosystem_order"]
	_default_ecosystem_id = String(values["default_ecosystem_id"])
	_dominant_species_chance = float(values["dominant_species_chance"])


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


## 生态配置结构校验已迁移至 scripts/world/ecology_config_validator.gd（纯静态函数集）。
func _validate_ecosystem_config() -> bool:
	return EcologyConfigValidatorScript.validate_ecosystem_config(
		_plant_species,
		_animal_species,
		_ambient_species,
		_ecosystem_order,
		_flora_layer_configs,
		FLORA_LAYER_IDS
	)


func _noise_type_from_name(value: String) -> int:
	return EcologyConfigValidatorScript.noise_type_from_name(value)


func _fractal_type_from_name(value: String) -> int:
	return EcologyConfigValidatorScript.fractal_type_from_name(value)





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
	_textures.setup(
		_terrain_materials,
		_terrain_sampler,
		Callable(self, "_cell_rand"),
		TILE_W,
		WATER_COLOR,
		WATER_DEPTH_COLOR,
		WATER_MAX
	)
	_setup_terrain()
	_setup_player()
	_setup_camera()
	_player_occlusion.configure(_player, _cam, _terrain, TILE_W, TILE_H)
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
	_configure_generation_services()
	_regenerate(seed)
	if "--shot" in OS.get_cmdline_user_args():
		_shot_and_quit()


## 生成服务接线：配置编译完成后一次性注入（字典按引用同步，无需重复调用）。
func _configure_generation_services() -> void:
	_world_query.configure(
		_cell_states,
		Callable(self, "_sample_cell_context")
	)
	_flora.configure(
		_plant_species,
		_ambient_species,
		_flora_layer_configs,
		_dominant_species_chance,
		_flora_conflict_seed,
		rock_level,
		WATER_SURFACE_LEVEL,
		LANDFORM_ID_TO_TYPE,
		_spatial_flora_sources,
		_community_runtime,
		_ambient_registry,
		_terrain_sampler,
		Callable(self, "_cell_rand"),
		Callable(self, "_cell_context_for_query"),
		Callable(self, "_ecology_near_tag"),
		Callable(self, "_community_rand01"),
		Callable(self, "_render_block")
	)
	_fauna.configure(
		_community_runtime,
		_animal_groups,
		_cells,
		_cell_states,
		_animals,
		WATER_MAX,
		WATER_SURFACE_LEVEL,
		LANDFORM_ID_TO_TYPE,
		Callable(self, "_cell_rand"),
		Callable(self, "_community_rand01"),
		Callable(self, "_ecology_near_tag"),
		Callable(self, "_ecology_chance"),
		Callable(self, "_pick_species"),
		Callable(self, "_quantize"),
		Callable(self, "_cell_context_for_query"),
		Callable(self, "_community_water_clearance_valid"),
		Callable(self, "_spawn_animal"),
		Callable(self, "_animal_cell_reserved")
	)
	_animal_runtime.configure(
		self,
		_animals,
		_cell_states,
		_animal_species,
		_animal_behavior_stacks,
		_animal_behavior_registry,
		_animal_groups,
		WATER_MAX,
		WATER_SURFACE_LEVEL,
		WATER_COLOR,
		ANIMAL_SORT_BIAS,
		ANIMAL_DIRECTIONS,
		Callable(self, "_cell_rand"),
		Callable(self, "_quantize"),
		Callable(self, "_cell_context_for_query"),
		Callable(self, "_water_clearance"),
		Callable(self, "_column_sort_y"),
		Callable(self, "_cell_feet_pos"),
		Callable(self, "_grid_to_screen")
	)


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
	_player_occlusion.clear_recorded()
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
	_move_t = 1.0
	_set_player_render_position(_player_visual_position, _move_sort_to)
	_update_player_occlusion(0.0)
	_world_camera_navigation.reset()
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
		var solid_texture := _textures.solid_tex(q, level, cell, context)
		if q <= WATER_MAX:
			solid_texture = _textures.underwater_texture_for_context(context, water_depth)
		blocks.append(_render_block(solid_texture, level))
	if q <= WATER_MAX:
		_append_water_volume(cell, q, blocks)
	_flora.spawn_flora(
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
	_terrain.set_cell(cell, state.render_blocks, cell_stand_level(cell))
	_cells[cell] = true
	if q <= WATER_MAX:
		_water_cells[cell] = true
	_flora.spawn_ambient_for_cell(
		cell,
		q,
		int(LANDFORM_ID_TO_TYPE.get(
			String(context.landform_id),
			Landform.PLAINS
		)),
		context.region_anchor,
		state,
		self,
		_current_seed
	)
	_player_occlusion.mark_dirty()


func _append_water_volume(cell: Vector2i, lakebed_level: int, blocks: Array) -> void:
	# 四个水平方向都保留独立的岸线侧壁；绘制时按当前视角选取朝前两侧。
	var expose_right := _quantize(cell.x + 1, cell.y) > WATER_MAX
	var expose_left := _quantize(cell.x, cell.y + 1) > WATER_MAX
	var expose_back_right := _quantize(cell.x - 1, cell.y) > WATER_MAX
	var expose_back_left := _quantize(cell.x, cell.y - 1) > WATER_MAX
	for level in range(lakebed_level + 1, WATER_SURFACE_LEVEL + 1):
		if expose_left:
			blocks.append(_water_block(_textures.water_left_tex, level, WATER_SIDE_ALPHA, &"left_side"))
		if expose_right:
			blocks.append(_water_block(_textures.water_right_tex, level, WATER_SIDE_ALPHA, &"right_side"))
		if expose_back_left:
			blocks.append(_water_block(_textures.water_left_tex, level, WATER_SIDE_ALPHA, &"left_side_opposite"))
		if expose_back_right:
			blocks.append(_water_block(_textures.water_right_tex, level, WATER_SIDE_ALPHA, &"right_side_opposite"))
	# 顶面只画一次，所有水格在同一个水位无缝拼接；透明像素不会重复覆盖。
	var surface_block := _water_block(
		_textures.water_tex,
		WATER_SURFACE_LEVEL,
		WATER_SURFACE_ALPHA,
		&"surface"
	)
	var shore_edges := 0
	if expose_back_right:
		shore_edges |= 1
	if expose_back_left:
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
	_player_occlusion.on_cell_freed(cell)
	if _ambient_registry != null:
		_ambient_registry.remove_cell_all(cell)
	_cell_states.erase(cell)
	if not _cells.has(cell):
		return
	_cells.erase(cell)
	_water_cells.erase(cell)
	if is_instance_valid(_terrain):
		_terrain.remove_cell(cell)


## 逻辑坐标中的方形流式窗口，经标准等距投影后就是画面中的菱形视窗。
var _stream_center := Vector2i.ZERO


func _update_streaming() -> void:
	if _battle_active:
		return  # 战斗中冻结流式（战场 cell 不被释放/生成）
	# Habitat 邻近查询只在一次流式批次内复用，避免无限世界探索时缓存无界增长。
	_world_query.clear_caches()
	_flora.clear_caches()
	_ensure_sort_origin(_stream_center)
	for cell in _cells.keys():
		if not _in_stream(cell, _stream_center):
			_free_cell(cell)
	for y in range(_stream_center.y - stream_extent, _stream_center.y + stream_extent + 1):
		for x in range(_stream_center.x - stream_extent, _stream_center.x + stream_extent + 1):
			var cell := Vector2i(x, y)
			if not _cells.has(cell):
				_spawn_cell(cell)
	# 每个流式批次只重建受影响的 chunk，而非每格一个 Node。
	if is_instance_valid(_terrain):
		if _terrain.flush() > 0:
			# chunk 重建会清掉植物淡化状态（注册表重建），需要重算遮挡集合，
			# 否则已记录的遮挡格会带着"已处理"标记而永远不再淡化。
			_player_occlusion.mark_dirty()
	# 所有地块与静态生态对象完成后再生成动物群，避免群成员落在尚未加载的树木或装饰上。
	_spawn_fauna_for_stream()
	_cleanup_streamed_animals()
	if _ambient_registry != null:
		_ambient_registry.refresh_all()


func _in_stream(cell: Vector2i, center: Vector2i) -> bool:
	return absi(cell.x - center.x) <= stream_extent and absi(cell.y - center.y) <= stream_extent


func _grid_to_world(cell: Vector2i, level := 0.0) -> Vector3:
	return IsoProjection.grid_to_world(cell, level)


func _grid_to_screen(cell: Vector2i, level := 0.0) -> Vector2:
	var world_position := IsoProjection.grid_to_world(cell, level)
	if is_instance_valid(_cam):
		return _cam.unproject_position(world_position)
	return Vector2(
		float(cell.x - cell.y) * TILE_W * 0.5,
		float(cell.x + cell.y) * TILE_H * 0.5 - level * LEVEL_H
	)


func _column_sort_y(cell: Vector2i) -> float:
	var sort_cell := cell - _sort_origin
	# 逻辑排序只服务兼容接口；真实遮挡由 Camera3D 深度完成，旋转不重写排序状态。
	var projected := Vector2(
		float(sort_cell.x - sort_cell.y) * TILE_W * 0.5,
		float(sort_cell.x + sort_cell.y) * TILE_H * 0.5
	)
	var depth := snappedf(projected.y, 0.001)
	var tie_break := clampf(projected.x * 0.001, -0.25, 0.25)
	return depth * SORT_DEPTH_SCALE + tie_break


## 角度变化只旋转 Camera3D；地形、生态状态和连续网格坐标全部保持不变。
func _refresh_view_projection() -> void:
	_view_rotation_culling = false
	_player_occlusion.mark_dirty()


func _restore_view_draw_culling() -> void:
	_view_rotation_culling = false


func _ensure_sort_origin(near_cell: Vector2i) -> void:
	if not _has_sort_origin:
		_sort_origin = near_cell
		_has_sort_origin = true
		return
	var distance := near_cell - _sort_origin
	if absi(distance.x) < SORT_REBASE_DISTANCE and absi(distance.y) < SORT_REBASE_DISTANCE:
		return
	_sort_origin = near_cell
	_player_occlusion.mark_dirty()
	_move_sort_from = _column_sort_y(_move_from_cell) + PLAYER_SORT_BIAS
	_move_sort_to = _column_sort_y(_player_cell) + PLAYER_SORT_BIAS
	_set_player_render_position(
		_player_visual_position,
		_player_movement_sort_y()
	)
	for animal_value in _animals.values():
		var animal: AnimatedSprite3D = animal_value
		if not is_instance_valid(animal):
			continue
		animal.rebase_sort(
			_column_sort_y(animal.from_cell) + ANIMAL_SORT_BIAS,
			_column_sort_y(animal.target_cell) + ANIMAL_SORT_BIAS
		)


## 只有贴着水面的最低陆地才是泥滩（平坦平原不再整片变土色）
func _is_beach(cell: Vector2i, q: int) -> bool:
	return _terrain_sampler.is_shore(cell, q)


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


# ---------- 植被 / 动物 ----------

var _flora := FloraSpawnerScript.new()
var _fauna := FaunaStreamerScript.new()
var _animal_runtime := AnimalRuntimeScript.new()


func _ecosystem_id_for_cell(q: int, biome: int, beach: bool, lf: int) -> String:
	return EcosystemMatchScript.ecosystem_id_for_cell(
		_community_runtime,
		_ecosystem_order,
		_default_ecosystem_id,
		_landform_ids,
		_terrain_sampler,
		WATER_SURFACE_LEVEL,
		WATER_MAX,
		q,
		biome,
		beach,
		lf
	)


## 旧测试与存档仍使用整数 biome/landform；在边界处转换成统一 CellContext。
## 新生态链始终直接消费 TerrainSampler 产生的动态 ID。
func _legacy_cell_context(q: int, biome: int, beach: bool, lf: int):
	return EcosystemMatchScript.legacy_cell_context(
		_landform_ids,
		_terrain_sampler,
		WATER_SURFACE_LEVEL,
		WATER_MAX,
		q,
		biome,
		beach,
		lf
	)


func _ecosystem_matches(
	match_rule: Dictionary,
	q: int,
	biome: int,
	beach: bool,
	lf: int
) -> bool:
	return EcosystemMatchScript.ecosystem_matches(
		match_rule,
		_landform_ids,
		_terrain_sampler,
		WATER_MAX,
		q,
		biome,
		beach,
		lf
	)


func _biome_id(biome: int) -> String:
	return EcosystemMatchScript.biome_id(_terrain_sampler, biome)


func _ecology_chance(chance_value: Variant, lf: int, q: int) -> float:
	return EcosystemMatchScript.ecology_chance(chance_value, rock_level, lf, q)



func _pick_species(rule: Dictionary, gc: Vector2i, cell: Vector2i) -> String:
	return _flora.pick_species(rule, gc, cell)


func _flora_candidates_for_cell(
	cell: Vector2i,
	q: int,
	lf: int,
	gc: Vector2i,
	ecosystem: Dictionary
) -> Array[Dictionary]:
	return _flora.flora_candidates_for_cell(cell, q, lf, gc, ecosystem)


func _has_raw_selected_flora_layer_within(
	cell: Vector2i,
	layer_id: String,
	radius: int
) -> bool:
	return _flora.has_raw_selected_flora_layer_within(cell, layer_id, radius)


func _select_flora_candidate(cell: Vector2i, candidates: Array[Dictionary]) -> Dictionary:
	return _flora.select_flora_candidate(cell, candidates)



# ---------- 动物群落 / 移动物体 ----------
## 动物群落生成主体已迁移至 scripts/world/fauna_streamer.gd（行为不变，确定性盐保留）。
func _spawn_fauna_for_stream() -> void:
	_fauna.spawn_fauna_for_stream(_stream_center, stream_extent, _player_cell)


func _fauna_anchor_fully_loaded(anchor: Vector2i, radius: int) -> bool:
	_fauna.sync_stream_frame(_stream_center, stream_extent, _player_cell)
	return _fauna.fauna_anchor_fully_loaded(anchor, radius)


func _fauna_anchor_for_bucket(rule: Dictionary, bucket: Vector2i) -> Vector2i:
	return _fauna.fauna_anchor_for_bucket(rule, bucket)


## 确定性契约核心：stream_key 流（勿改语义；flora/fauna 模块经 Callable 注入引用本函数）。
func _community_rand01(position: Vector2i, stream_key: String) -> float:
	return _world_rng.cell_float(position, StringName(stream_key))


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
	_fauna.sync_stream_frame(_stream_center, stream_extent, _player_cell)
	_fauna.create_animal_group(
		group_id,
		ecosystem_id,
		rule,
		distribution,
		bucket,
		anchor,
		anchor_q,
		source
	)


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
	_fauna.sync_stream_frame(_stream_center, stream_extent, _player_cell)
	return _fauna.animal_group_spawn_cells(
		anchor,
		anchor_q,
		ecosystem_id,
		distribution,
		desired_count,
		placement_seed,
		only_if_flora_missed,
		source
	)


func _has_water_within(center: Vector2i, radius: int) -> bool:
	return _fauna.has_water_within(center, radius)


func _restore_animal_group(group_id: String) -> void:
	_fauna.sync_stream_frame(_stream_center, stream_extent, _player_cell)
	_fauna.restore_animal_group(group_id)


func _active_animal_count_for_group(group_id: String) -> int:
	return _fauna.active_animal_count_for_group(group_id)


func _release_animal_group_member(animal: AnimatedSprite3D) -> void:
	_fauna.release_animal_group_member(animal)



## 动物个体运行时（簇9）已迁 scripts/world/animal_runtime.gd；以下为兼容委托。
func _sync_animal_frame() -> void:
	_animal_runtime.sync_frame(
		_stream_center, stream_extent, _player_cell, _animal_behavior_tag_scan_radius
	)


func _spawn_animal(
	species_id: String, cell: Vector2i, _level: int
) -> AnimatedSprite3D:
	_sync_animal_frame()
	return _animal_runtime.spawn_animal(species_id, cell, _level)


func _underwater_animal_material_for_depth(water_depth: int) -> ShaderMaterial:
	return _animal_runtime.underwater_animal_material_for_depth(water_depth)


func _animal_species_allows_surface(
	species: Dictionary,
	surface_id: StringName
) -> bool:
	return _animal_runtime.animal_species_allows_surface(species, surface_id)


func _clear_animals() -> void:
	_animal_runtime.clear_animals()


func _cleanup_streamed_animals() -> void:
	_sync_animal_frame()
	_animal_runtime.cleanup_streamed_animals()


func _update_animals(delta: float) -> void:
	_sync_animal_frame()
	_animal_runtime.update_animals(delta)


func _begin_animal_move(animal: AnimatedSprite3D) -> void:
	_sync_animal_frame()
	_animal_runtime.begin_animal_move(animal)


func _can_animal_enter(animal: AnimatedSprite3D, target: Vector2i) -> bool:
	_sync_animal_frame()
	return _animal_runtime.can_animal_enter(animal, target)


func _animal_cell_reserved(
	cell: Vector2i, except_animal: AnimatedSprite3D = null
) -> bool:
	return _animal_runtime.animal_cell_reserved(cell, except_animal)



func _cell_context_for_query(cell: Vector2i):
	return _world_query.cell_context_for_query(cell)


func _water_clearance(cell: Vector2i, maximum_radius: int) -> int:
	return _world_query.water_clearance(cell, maximum_radius)


func _community_water_clearance_valid(
	definition: Dictionary,
	context
) -> bool:
	return _world_query.community_water_clearance_valid(definition, context)


## Community habitat 的统一空间查询（缓存随模块，_update_streaming 批次内清空）。
func _ecology_near_tag(context, tag: StringName, radius: float) -> bool:
	return _world_query.ecology_near_tag(context, tag, radius)



func _process_terrain_material_texture(
	texture: Texture2D,
	_texture_path: String
) -> Texture2D:
	return TerrainTextureCatalogScript.pad_texture_to_32(texture)



func _setup_terrain() -> void:
	_terrain = IsometricTerrain3DScript.new()
	_terrain.name = "IsometricTerrain3D"
	add_child(_terrain)


func _setup_player() -> void:
	_player = Sprite3D.new()
	if CharacterSheet.sheet_exists(PLAYER_SHEET_CLASS):
		_player.texture = CharacterSheet.frame_texture(PLAYER_SHEET_CLASS, CharacterSheet.FRAME_FRONT)
		_player.pixel_size = CharacterSheet.pixel_size()
		_player_uses_sheet = true
	else:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		for y in 8:
			for x in 8:
				var border := x == 0 or y == 0 or x == 7 or y == 7
				img.set_pixel(x, y, Color(0.5, 0.08, 0.1) if border else Color(0.95, 0.35, 0.3))
		_player.texture = ImageTexture.create_from_image(img)
		_player.pixel_size = 1.0 / 32.0
	_player.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_player.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_player.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_player.shaded = false
	add_child(_player)


## 玩家使用真实 3D 脚点；sort_y 仅保留给旧调试接口，不再参与 Canvas 排序。
func _set_player_render_position(visual_position: Vector2, _sort_y: float) -> void:
	_player.position = IsoProjection.visual_to_world(visual_position, _player_current_stand_level())
	# 精灵图锚点 bottom-center：格中心在脚底上方 140px，offset 上抬对齐脚点。
	if _player_uses_sheet:
		_player.offset = Vector2(0, -CharacterSheet.FEET_FROM_CENTER_PX)
	else:
		_player.offset = Vector2(0, -_player.texture.get_height() / 2.0)


## 玩家姿态 API：idle 按相机朝向解析 front/back/side 三视图；run 在朝向/远离
## 相机轴用 front/back 帧、横切轴用单帧 run+镜像（CharacterSheet.resolve_pose）。
func _set_player_pose(pose: StringName) -> void:
	_player_pose = pose
	_refresh_player_visual()


## 相机旋转后同一世界朝向的屏幕解析会变：yaw 变化时重算 idle 帧。
func _track_player_camera_yaw() -> void:
	if not _player_uses_sheet or _player_pose != CharacterSheet.POSE_IDLE or not is_instance_valid(_cam):
		return
	var yaw: float = _cam.yaw_radians
	if absf(yaw - _player_last_yaw) < 0.001:
		return
	_player_last_yaw = yaw
	_refresh_player_visual()


func _refresh_player_visual() -> void:
	if not _player_uses_sheet or _player == null:
		return
	var delta := Vector2.ZERO
	if is_instance_valid(_cam):
		delta = CharacterSheet.facing_screen_delta(_cam, _player.global_position, _player_facing)
	var resolved := CharacterSheet.resolve_pose(_player_pose, delta)
	_player.texture = CharacterSheet.frame_texture(PLAYER_SHEET_CLASS, resolved[&"frame"])
	_player.flip_h = resolved[&"flip"]


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


func _player_current_stand_level() -> float:
	return lerpf(
		_move_level_from,
		_move_level_to,
		clampf(_move_t, 0.0, 1.0)
	)


func _update_player_occlusion(delta: float) -> void:
	_player_occlusion.update(
		delta,
		get_viewport_rect().size.y,
		_player_visual_position,
		_player_current_stand_level(),
		_player_uses_sheet
	)


func get_player_occluder_cells() -> Array[Vector2i]:
	return _player_occlusion.get_occluder_cells()



## 角色站立的层号：陆地为柱顶，水面为水位线
func _stand_level(q: int) -> int:
	return maxi(q, WATER_SURFACE_LEVEL)


func _cell_feet_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell)


## WASD 与上下方向键移动；左右方向键用于离散视角切换。
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
	# 树木/装饰类植物按地面占位阻挡移动（与动物 _can_animal_enter 同一占用事实）。
	var target_cell := _player_cell + d
	if _cell_states.has(target_cell) and _cell_states[target_cell].blocks_movement():
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
	# 脚步声：按目标格 CellContext 的水域/群系/地貌选素材（Sfx 内部带节流）。
	var _step_state = _cell_states.get(_player_cell)
	Sfx.play_world_step(_step_state.context if _step_state != null else null)
	_player_facing = Vector3(float(d.x), 0.0, float(d.y))
	_set_player_pose(CharacterSheet.POSE_RUN)
	_set_player_render_position(_player_visual_position, _player_movement_sort_y())
	_stream_center = _player_cell
	_update_streaming()
	_reveal()
	_update_minimap()


func _process(delta: float) -> void:
	if is_instance_valid(_cam):
		_cam.advance(delta)
		_track_player_camera_yaw()
	if _move_t < 1.0:
		var speed := fast_multiplier if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
		_move_t = minf(1.0, _move_t + delta / move_time * speed)
		_player_visual_position = _move_from.lerp(_move_to, _move_t)
		_set_player_render_position(
			_player_visual_position,
			_player_movement_sort_y()
		)
		if _move_t >= 1.0:
			_set_player_pose(CharacterSheet.POSE_IDLE)
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
		_set_camera_position(_battle_camera_focus())
	else:
		# 连续网格状态不做像素取整；Camera3D 只消费平滑后的焦点。
		var camera_blend := 1.0 - exp(
			-camera_smoothing_speed * maxf(delta, 0.0)
		)
		_camera_smooth_position = _camera_smooth_position.lerp(
			_player_visual_position,
			camera_blend
		)
		_set_camera_position(_camera_smooth_position + _world_camera_navigation.offset)
	_sync_depth_of_field_focus()
	if _ambient_registry != null:
		var viewport_size := get_viewport_rect().size
		var camera_focus_grid := IsoProjection.world_to_grid(_cam.focus_position)
		_ambient_registry.update_observer_all(
			{
				"player_cell": _player_cell,
				"player_world_position": _player_visual_position,
				"player_world_3d": _player.global_position,
				"player_screen_position": _cam.unproject_position(_player.global_position),
				"camera_world_position": Vector2(camera_focus_grid),
				"camera_3d": _cam,
				"viewport_size": viewport_size,
				"canvas_transform": get_viewport().get_canvas_transform(),
				"zoom": Vector2.ONE * _cam.zoom,
				"world_seed": _current_seed,
				"map_open": is_world_map_open(),
				"allow_flyovers": not is_world_map_open(),
			},
			delta
		)


# ---------- 小地图 ----------

func _setup_minimap() -> void:
	_minimap.configure(_terrain_materials, _terrain_sampler, WATER_MAX)
	_minimap.setup_ui(self, GameHudScript.SIDE_PANEL_WIDTH)


## 角色周围 sight_radius 范围变为已探索（永久保留）
func _reveal() -> void:
	_minimap.reveal(
		_player_cell,
		sight_radius,
		_explored,
		Callable(self, "_sample_cell_context")
	)


func _update_minimap() -> void:
	_minimap.update(_player_cell, _explored)


func _minimap_color(_q: int, _biome: int, cell: Vector2i) -> Color:
	var context = _sample_cell_context(cell)
	return _minimap.map_color_for_context(context)



# ---------- 相机 / HUD / 输入 ----------

func _setup_camera() -> void:
	_cam = IsometricCamera3DScript.new()
	_cam.name = "IsometricCamera3D"
	# Camera3D 没有 Camera2D 的 position/rotation smoothing 属性；逻辑跟随由 main.gd 插值。
	add_child(_cam)
	_cam.current = true
	_apply_zoom()


func _setup_hud() -> void:
	_hud = GameHudScript.new()
	_hud.name = "GameHUD"
	_hud.battlefield_picked.connect(_on_battlefield_picked)
	_hud.editor_requested.connect(_open_map_editor)
	add_child(_hud)
	# 侧栏独占窗口右侧一列：3D 视锥让出该宽度，舞台不延伸到面板下方。
	_cam.reserved_right_px = GameHudScript.SIDE_PANEL_WIDTH
	_cam.reserved_left_px = GameHudScript.LEFT_RAIL_WIDTH


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


# ============================================================
# 世界输入：模态守卫 → 视图拖拽 → 缩放手势 → 键位路由表
# ============================================================
## 键位路由表（physical_keycode → handler(event)），惰性构建。
## 覆盖原 elif 链里按 physical 匹配的键（R/Z/Q/←/X/→/T/N/B/P/O/E）。
var _key_handlers: Dictionary = {}
## 入口/缩放键的 keycode 兜底路由（P/O/E 双匹配注入输入；=、+、-、F 原链只看 keycode）。
## 物理键优先、keycode 兜底：与原 elif 链在真实键盘与契约注入下逐键等价。
var _entry_key_handlers: Dictionary = {}


func _unhandled_input(event: InputEvent) -> void:
	# B2 遭遇覆盖期间阻止 P/O/E 等入口重入；false 时保持原世界输入路径。
	if _battle_transition_pending:
		get_viewport().set_input_as_handled()
		return
	if _handle_b1_battle_input(event):
		get_viewport().set_input_as_handled()
		return
	if _handle_world_map_input(event):
		# 地图是模态 UI；鼠标缩放、触控手势和背景快捷键都不应穿透。
		get_viewport().set_input_as_handled()
		return
	if not _battle_active and _world_camera_navigation.handle_input(event, _cam):
		get_viewport().set_input_as_handled()
		return
	if _handle_view_drag_input(event):
		get_viewport().set_input_as_handled()
		return
	if _handle_zoom_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key_input(event)


## B1 就地战斗模式三段守卫（ANIMATING 直通 → 相机拖拽 → 战斗层接管）。
## 返回 true = 事件已被战斗侧消费，调用方需标记 handled。
func _handle_b1_battle_input(event: InputEvent) -> bool:
	if not _battle_active:
		return false
	if _battle_system != null and _battle_system.mode == _battle_system.Mode.ANIMATING:
		_battle_system._unhandled_input(event)
		return true
	return _handle_battle_camera_input(event) or _handle_battle_input(event)


## 中键按住水平拖转视角（按下记录基准 x；运动按 dx 连续旋转）。
func _handle_view_drag_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_view_dragging = event.pressed
		if event.pressed:
			_view_drag_last_x = event.position.x
		return true
	if event is InputEventMouseMotion and _view_dragging:
		var drag_dx: float = event.position.x - _view_drag_last_x
		_view_drag_last_x = event.position.x
		_cam.drag_by(Vector2(drag_dx, 0.0))
		return true
	return false


## 滚轮缩放（带锚点）与触控板捏合（累积越过阈值才触发一档）。
func _handle_zoom_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_step(1, event.position)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_step(-1, event.position)
			return true
		return false
	if event is InputEventMagnifyGesture:
		_pinch_factor *= event.factor
		if _pinch_factor >= PINCH_THRESHOLD:
			_zoom_step(1)
			_pinch_factor = 1.0
		elif _pinch_factor <= 1.0 / PINCH_THRESHOLD:
			_zoom_step(-1)
			_pinch_factor = 1.0
		return true
	return false


func _handle_key_input(event: InputEventKey) -> void:
	var handler: Callable = _key_route().get(event.physical_keycode, Callable())
	if not handler.is_valid() and event.keycode != event.physical_keycode:
		handler = _entry_key_route().get(event.keycode, Callable())
	if handler.is_valid():
		handler.call(event)


func _key_route() -> Dictionary:
	if _key_handlers.is_empty():
		_key_handlers = {
			KEY_R: Callable(self, "_key_reset_or_regenerate"),
			KEY_Z: Callable(self, "_key_rotate_ccw"),
			KEY_Q: Callable(self, "_key_rotate_ccw"),
			KEY_LEFT: Callable(self, "_key_rotate_ccw"),
			KEY_X: Callable(self, "_key_rotate_cw"),
			KEY_RIGHT: Callable(self, "_key_rotate_cw"),
			KEY_T: Callable(self, "_key_weather"),
			KEY_N: Callable(self, "_key_day_night"),
			KEY_B: Callable(self, "_key_depth_of_field"),
			KEY_P: Callable(self, "_key_enter_battle"),
			KEY_O: Callable(self, "_key_battlefield_panel"),
			KEY_E: Callable(self, "_key_editor_or_rotate"),
		}
	return _key_handlers


func _entry_key_route() -> Dictionary:
	if _entry_key_handlers.is_empty():
		_entry_key_handlers = {
			KEY_P: Callable(self, "_key_enter_battle"),
			KEY_O: Callable(self, "_key_battlefield_panel"),
			KEY_E: Callable(self, "_key_editor_or_rotate"),
			KEY_EQUAL: Callable(self, "_key_zoom_in"),
			KEY_KP_ADD: Callable(self, "_key_zoom_in"),
			KEY_MINUS: Callable(self, "_key_zoom_out"),
			KEY_KP_SUBTRACT: Callable(self, "_key_zoom_out"),
			KEY_F: Callable(self, "_key_zoom_reset"),
		}
	return _entry_key_handlers


## Ctrl+R 重生成世界；单独 R 复位视角。
func _key_reset_or_regenerate(event: InputEventKey) -> void:
	if event.ctrl_pressed:
		_regenerate(0)
	else:
		_cam.reset_rotation()


## Z/Q/← 逆时针；X/→/E 顺时针（E 见 _key_editor_or_rotate）。
func _key_rotate_ccw(_event: InputEventKey) -> void:
	_cam.rotate_step(-1)


func _key_rotate_cw(_event: InputEventKey) -> void:
	_cam.rotate_step(1)


## Shift+T 自动天气；单独 T 手动轮换。天气模块缺席时静默忽略。
func _key_weather(event: InputEventKey) -> void:
	if _weather == null:
		return
	if event.shift_pressed:
		_weather.set_auto_mode()
	else:
		_weather.cycle_manual_weather()


## Shift+N 自动昼夜；单独 N 手动切夜。昼夜模块缺席时静默忽略。
func _key_day_night(event: InputEventKey) -> void:
	if _day_night == null:
		return
	if event.shift_pressed:
		_day_night.set_auto_mode()
	else:
		_day_night.toggle_manual_night()


## B 切换景深。模块缺席时静默忽略。
func _key_depth_of_field(_event: InputEventKey) -> void:
	if _depth_of_field != null:
		_depth_of_field.toggle()


## P = Play battle：进入战棋（融合进 pixel_world 的战术 RPG 系统）。
## physical/keycode 双匹配，确保注入输入也能触发；无前置 guard（与原链一致）。
func _key_enter_battle(_event: InputEventKey) -> void:
	_enter_battle()


## O 打开/关闭 JSON 战场加载列表（调试入口，与 P 的随机遭遇战互补）。
## B1 就地战斗进行中不开（_battle_active 时输入已被战斗层接管）。
func _key_battlefield_panel(_event: InputEventKey) -> void:
	if not _battle_active and _hud != null:
		_hud.toggle_battlefield_panel()


## Ctrl+E 打开地图编辑器；单独 E 用于离散顺时针步进。
## 原 elif 链里 Ctrl+E 命中后即使内部 guard 拦下也整体短路（不落到旋转），
## 仅 B1 进行中不满足前置（not _battle_active）才落到 plain-E 旋转——此处保持一致。
func _key_editor_or_rotate(event: InputEventKey) -> void:
	if event.ctrl_pressed and not _battle_active:
		if not is_world_map_open():
			_open_map_editor()
		return
	if event.physical_keycode == KEY_E:
		_cam.rotate_step(1)


func _key_zoom_in(_event: InputEventKey) -> void:
	_zoom_step(1)


func _key_zoom_out(_event: InputEventKey) -> void:
	_zoom_step(-1)


## F 复位到默认缩放档。
func _key_zoom_reset(_event: InputEventKey) -> void:
	_zoom_index = DEFAULT_ZOOM_INDEX
	_apply_zoom()


func _setup_day_night() -> void:
	var built := PresentationStageScript.build_day_night(self)
	_day_night = built["day_night"]
	_sunlight = built["sunlight"]


func _setup_depth_of_field() -> void:
	_depth_of_field = PresentationStageScript.build_depth_of_field(self)



func _sync_depth_of_field_focus() -> void:
	if _depth_of_field == null or _cam == null:
		return
	var viewport_size := get_viewport_rect().size
	var player_screen_position := _cam.unproject_position(_player.global_position)
	_depth_of_field.set_focus_screen_position(player_screen_position, viewport_size)


func _setup_audio() -> void:
	_audio = PresentationStageScript.build_world_audio(self, _animal_species, _day_night)


func _setup_fireflies() -> void:
	var built := PresentationStageScript.build_ambient_registry(
		self, _ambient_species, _day_night
	)
	_ambient_registry = built["registry"]
	_fireflies = built["fireflies"]


func _setup_weather() -> void:
	_weather = PresentationStageScript.build_weather(
		self,
		Callable(self, "_on_weather_water_impact"),
		Callable(self, "_sync_weather_audio")
	)
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


## 世界空间粒子负责雨雪；少量落点通过真实射线命中水面并交给 3D 水波池。
func _on_weather_water_impact(
	viewport_position: Vector2,
	kind: StringName,
	strength: float
) -> void:
	var picked: Variant = IsoProjection.screen_to_grid(
		_cam,
		viewport_position,
		WATER_SURFACE_LEVEL
	)
	if picked == null:
		return
	var continuous := picked as Vector2
	var cell := Vector2i(floori(continuous.x + 0.5), floori(continuous.y + 0.5))
	if not _water_cells.has(cell):
		return
	var offset_cells := continuous - Vector2(cell)
	var edge_ratio := absf(offset_cells.x) + absf(offset_cells.y)
	if edge_ratio > 0.94:
		return
	var maximum_radius := clampf(3.0 + (1.0 - edge_ratio) * 10.0, 3.0, 10.5)
	if is_instance_valid(_terrain) and _terrain.has_method(&"spawn_water_ripple"):
		_terrain.spawn_water_ripple(cell, offset_cells, kind, strength, maximum_radius)


func _zoom_step(delta: int, anchor_screen: Vector2 = Vector2.INF) -> void:
	var next_index := clampi(_zoom_index + delta, 0, ZOOM_LEVELS.size() - 1)
	if next_index == _zoom_index:
		return
	var anchor_before: Variant = null
	var anchor_level: float = 0.0
	if anchor_screen.is_finite():
		anchor_level = float(cell_stand_level(screen_to_cell(anchor_screen)))
		anchor_before = IsoProjection.screen_to_world(_cam, anchor_screen, anchor_level)
	_zoom_index = next_index
	_apply_zoom()
	if anchor_before == null:
		return
	var anchor_after: Variant = IsoProjection.screen_to_world(_cam, anchor_screen, anchor_level)
	if anchor_after == null:
		return
	var displacement: Vector2 = IsoProjection.world_to_grid_position(
		(anchor_before as Vector3) - (anchor_after as Vector3)
	)
	if _battle_active:
		_battle_focus_world_pos += displacement
		_set_camera_position(_battle_camera_focus())
	else:
		_world_camera_navigation.offset += displacement
		_set_camera_position(_camera_smooth_position + _world_camera_navigation.offset)
	_sync_depth_of_field_focus()


func _apply_zoom() -> void:
	var value := ZOOM_LEVELS[_zoom_index]
	_cam.zoom = value
	_set_camera_position(
		_battle_camera_focus() if _battle_active
		else _camera_smooth_position + _world_camera_navigation.offset
	)
	_sync_depth_of_field_focus()
	if _weather != null:
		_weather.refresh_particle_field()
	if _ambient_registry != null:
		# Camera3D 投影在本帧更新；延后一帧重新分配有限表现槽位。
		# 有限表现槽位，保证缩放后仍优先服务当前视口内的 ambient。
		_ambient_registry.call_deferred("refresh_all")


func _set_camera_position(world_position: Vector2) -> void:
	if not is_instance_valid(_cam):
		return
	_cam.focus_position = IsoProjection.visual_to_world(
		world_position,
		_player_current_stand_level()
	)
	if _battle_active and not _battle_camera_kick_offset.is_zero_approx():
		_cam.global_position += _battle_camera_kick_offset


## B1 攻击演出只叠加世界位移；原焦点、四正交角度和缩放逻辑不变。
func set_battle_camera_kick(offset: Vector3) -> void:
	_battle_camera_kick_offset = offset
	if _battle_active:
		_set_camera_position(_battle_camera_focus())


## 首次生成、换种子和自动截图属于瞬移，不应把旧视角缓慢拖进新位置。
func _snap_camera_position(world_position: Vector2) -> void:
	_camera_smooth_position = world_position
	_set_camera_position(world_position)


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
	if _battle_transition_pending:
		return
	# L1 埋点：战棋入口被触发（按 AGENTS.md 调试埋点强制原则）
	print("[world] 进入战棋（按 P）→ 中心=%s 模式=%s" % [
		str(_player_cell), "就地" if Settings.battle_inline_mode else "独立场景"])
	var chapter := WorldToChapter.world_to_chapter(_terrain_sampler, _player_cell, 10, _current_seed)
	# 战旗记录：世界就地战旗身份 = 种子 + 战场起点（同一世界同一位置 = 同一战旗）。
	# 同身份已有记录 → 从记录恢复进度（任务：退出后再进入自动恢复状态）。
	var save_identity := GameSession.identity_for_world_chapter(
		_current_seed, chapter.get("world_origin", Vector2i.ZERO))
	var decision := GameSession.prepare_world_entry(save_identity, chapter)
	chapter = decision.get("chapter", chapter)
	var save_state: Dictionary = decision.get("state", {})
	# 登记 initial 快照（commit 组装记录要用；恢复时沿用档案里的开局快照）
	GameSession.open_battle(save_identity, "world", "world",
		decision.get("initial", chapter))
	if Settings.battle_inline_mode:
		# B1 就地模式：不切场景，在 main.gd 下挂战斗层
		_enter_battle_inline(chapter, save_identity, save_state)
		return
	# B2 独立场景模式：切到 Battle.tscn
	SceneArgs.battle_args = {
		"chapter": chapter,
		"return_to": "res://main.tscn",
		"hosting": false,
		"save_identity": save_identity,
	}
	if not save_state.is_empty():
		SceneArgs.battle_args["save_state"] = save_state
	_change_to_battle_scene()


## B2 统一遭遇覆盖：先暗化当前世界，再切 Battle.tscn；新场景负责揭开。
func _change_to_battle_scene() -> void:
	if _battle_transition_pending:
		return
	_battle_transition_pending = true
	_battle_transition = _EncounterTransitionScript.new()
	add_child(_battle_transition)
	await _battle_transition.cover_for_scene_change()
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		_battle_transition_pending = false
		return
	tree.change_scene_to_file("res://scenes/Battle.tscn")


## 从 JSON 战场文件进入战棋（HUD 战场列表点选触发）。
## JSON 声明的战场与真实世界地形无关（无 world_origin），固定走 B2 独立场景模式，
## 不受 Settings.battle_inline_mode 影响。
func _enter_battlefield(path: String) -> void:
	if _battle_transition_pending:
		return
	var result: Dictionary = BattlefieldLoaderScript.load_battlefield(path)
	if not bool(result.get("ok", false)):
		var msg := String(result.get("error", "未知错误"))
		push_error("[world] 战场加载失败: %s → %s" % [path, msg])
		if _hud != null:
			_hud.show_battlefield_error(msg)
		return
	var chapter: Dictionary = result["chapter"]
	var info: Dictionary = result["info"]
	# 战旗记录：JSON 战场按「命名空间/id」登记；同战场已有档案 → 恢复进度
	var identity := GameSession.identity_for_battlefield(info)
	var decision := GameSession.prepare_entry_for(identity)
	if String(decision.get("mode", "")) == "list":
		# 档案版本更新等无法恢复 → 不开新局覆盖，提示后留在世界
		if _hud != null:
			_hud.show_battlefield_error(String(decision.get("notice", "存档无法恢复")))
		return
	chapter = decision.get("chapter", chapter)
	var save_state: Dictionary = decision.get("state", {})
	# L1 埋点：JSON 战场入口（按 AGENTS.md 调试埋点强制原则）
	print("[world] 加载 JSON 战场: %s（%dx%d, 我方%d/敌方%d, hosting=%s, %s）→ 独立场景模式" % [
		info.get("name", path), chapter.width, chapter.height,
		(chapter.playerUnits as Array).size(), (chapter.enemyUnits as Array).size(),
		str(decision.get("hosting", info.get("hosting", false))),
		"恢复进度" if not save_state.is_empty() else "新开局",
	])
	SceneArgs.battle_args = {
		"chapter": chapter,
		"return_to": "res://main.tscn",
		"hosting": bool(decision.get("hosting", info.get("hosting", false))),
		"save_identity": identity,
	}
	if not save_state.is_empty():
		SceneArgs.battle_args["save_state"] = save_state
	var notice := String(decision.get("notice", ""))
	if notice != "":
		SceneArgs.battle_args["save_notice"] = notice
	# 登记 initial 快照（commit 组装记录要用；恢复时沿用档案里的开局快照）
	GameSession.open_battle(identity, "battlefield", String(path),
		decision.get("initial", chapter))
	_change_to_battle_scene()


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
func _enter_battle_inline(chapter: Dictionary, save_identity: String = "", save_state: Dictionary = {}) -> void:
	_world_camera_navigation.cancel_drag()
	# 1. 备份世界探索状态
	_cam_pos_backup = _camera_smooth_position
	_zoom_index_backup = _zoom_index
	_player_visible_backup = _player.visible
	# 复位战场相机偏移（防止上次战斗残留）
	_battle_cam_offset = Vector2.ZERO
	_battle_pan_active = false
	_battle_camera_kick_offset = Vector3.ZERO
	# 2. 隐藏世界玩家红点（用战棋 UnitSprite 替代）
	_player.visible = false
	# 3. 相机聚焦战场中心（玩家位置 ≈ 战场中心），固定 zoom=2.0x
	_zoom_index = DEFAULT_ZOOM_INDEX  # 2 → 2.0x
	_apply_zoom()
	var center_world_cell := _player_cell
	_battle_focus_world_pos = Vector2(center_world_cell)
	_snap_camera_position(_battle_focus_world_pos)
	# 4. 实例化 BattleSystem 并注入 main.gd 引用
	SceneArgs.battle_args = {
		"chapter": chapter,
		"world": self,                  # B1 标记：main.gd 引用
		"hosting": false,
		"save_identity": save_identity, # 战旗记录身份（空 = 调试直启，不存档）
	}
	if not save_state.is_empty():
		SceneArgs.battle_args["save_state"] = save_state # 同身份档案恢复进度
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
	_battle_camera_kick_offset = Vector3.ZERO
	# 恢复相机/玩家
	_player.visible = _player_visible_backup
	_zoom_index = _zoom_index_backup
	_apply_zoom()
	_camera_smooth_position = _cam_pos_backup
	_set_camera_position(_cam_pos_backup + _world_camera_navigation.offset)


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


## B1 平移仍以屏幕像素累积，最终通过同一 Camera3D 射线换算为连续网格偏移。
func _battle_camera_focus() -> Vector2:
	if _battle_cam_offset.is_zero_approx() or not is_instance_valid(_cam):
		return _battle_focus_world_pos
	# 3D 舞台夹在左竖栏与右侧栏之间；B1 视觉中心 = 舞台中心，不是窗口中心。
	var viewport_size := get_viewport_rect().size
	var viewport_center := Vector2(
		(GameHudScript.LEFT_RAIL_WIDTH
			+ viewport_size.x - GameHudScript.SIDE_PANEL_WIDTH) * 0.5,
		viewport_size.y * 0.5
	)
	var level := _player_current_stand_level()
	var from: Variant = IsoProjection.screen_to_world(_cam, viewport_center, level)
	var to: Variant = IsoProjection.screen_to_world(_cam, viewport_center + _battle_cam_offset, level)
	if from == null or to == null:
		return _battle_focus_world_pos
	var delta := (to as Vector3) - (from as Vector3)
	return _battle_focus_world_pos + Vector2(
		delta.x / IsoProjection.GRID_STEP,
		delta.z / IsoProjection.GRID_STEP
	)


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
		if mm.ctrl_pressed:
			_cam.drag_by(Vector2(mm.position.x - _battle_pan_last.x, 0.0))
		else:
			# offset 始终是实际屏幕像素；射线反投影只在焦点换算时处理 zoom。
			_battle_cam_offset -= mm.position - _battle_pan_last
			_clamp_battle_cam_offset()
		_battle_pan_last = mm.position
		return true
	return false


## B1 战场边缘滚屏：鼠标距视口边缘 < 阈值时按方向累加 _battle_cam_offset。
## 拖拽中 / 鼠标在 UI 上时不触发。在 _process 的 B1 分支调用。
const _BATTLE_EDGE_PAN_MARGIN := 24.0   # 触发边缘滚屏的边距（像素）
const _BATTLE_EDGE_PAN_SPEED := 420.0   # 边缘滚屏速度（实际屏幕像素/秒）
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
	# 鼠标悬在右侧侧栏列上（HUD 面板，不属于 battle_ui）→ 不滚屏。
	if mouse.x > size.x - GameHudScript.SIDE_PANEL_WIDTH:
		return
	# 鼠标在左侧竖栏上 → 同样不滚屏。
	if mouse.x < GameHudScript.LEFT_RAIL_WIDTH:
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
	# 边缘滚屏 = 相机往鼠标指向方向走（同向）；offset 不预除 zoom。
	# （与拖拽平移相反：拖拽是抓地图反方向拖，用 -=）
	_battle_cam_offset += dir * _BATTLE_EDGE_PAN_SPEED * delta
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


## 公开查询：屏幕坐标 → 世界 cell。真实射线与方格柱顶求交，最近顶面优先。
func screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var hit := IsoProjection.pick_top_face(
		_cam, screen_pos, 0, LEVELS * 3 - 1, Callable(self, "cell_stand_level")
	)
	return hit.get("cell", _player_cell) as Vector2i


func screen_to_cell_in_rect(screen_pos: Vector2, origin: Vector2i, size: Vector2i) -> Vector2i:
	var valid_cell := func(cell: Vector2i) -> bool:
		return cell.x >= origin.x and cell.y >= origin.y \
			and cell.x < origin.x + size.x and cell.y < origin.y + size.y
	var hit := IsoProjection.pick_top_face(
		_cam, screen_pos, 0, LEVELS * 3 - 1,
		Callable(self, "cell_stand_level"), valid_cell
	)
	return hit.get("cell", origin) as Vector2i


func _screen_to_world_pos(screen_pos: Vector2, level: float = 0.0) -> Variant:
	return IsoProjection.screen_to_world(_cam, screen_pos, level)
