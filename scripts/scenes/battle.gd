## scenes/battle.gd — 核心战场（场景编排器）
##
## 完整回合制循环：选单位→蓝格移动/红格攻击→移动→菜单(攻击/技能/物品/等待)→战斗演出→敌方AI回合→胜负。
## 2D 等距（pixel_world 融合版）：IsoBoard(Node2D) + UnitSprite3D(Node2D)；UI 用 CanvasLayer。
##
## 本文件只保留场景编排核心：生命周期/状态机/输入/选择/移动/战斗演出调度/胜负。
## 已按职责拆出的助手模块（scripts/battle/，均通过 setup()+Callable 注入，不持有本场景引用）：
##   - RangeOverlay (Node2D)      地形回退铺底 + 移动/攻击范围菱形描边 + 光标金色呼吸框
##   - TurnDirector (Node)        敌方 AI 回合 + 玩家方托管编排 + 偏好数据
##   - BattleUI    (CanvasLayer)  屏幕空间 UI 装配层（信号/注入面/共用容器/预览面板/演出包装；
##     HUD/单位菜单/单位详情/结果横幅再拆为 battle_ui_{hud,unit_menu,unit_detail,banner}.gd 子模块）
##   - BattleFx    (Node)         伤害数字/血条受击/飘字/抖动 + PixelFx 预热
##   - BattleSfx   (Node)         出手/受击/结算演出音效（含程序化回退波形）
##   - BattleResultStage (Node)   结算演出视觉（欢呼/倒地/死亡淡出 + 姿态捕获恢复）
##   - BattlePrefPanel (Node)     托管偏好面板（优先目标 + 策略）
##   - BattleSave (RefCounted)    战旗持久化（完整行动边界提交）
##   - BattleCameraKick (Node)    行动演出镜头踢击（strike/return 相位附加位移）
## 契约测试兼容面：_presentation_audio/_presentation_sound_cache/_result_visual_states 为
## 模块实例/字典的别名变量；_on_presentation_*/_restore_result_visuals/_on_impact_presented/
## _open_pref_panel/_commit_snapshot 为薄委托（tests/ 直戳这些成员）。

extends Node2D

const BattlefieldRendererScript = preload("res://scripts/iso/battlefield_renderer.gd")
const UserAssetVisualAdapterScript = preload("res://scripts/assets/user_asset_visual_adapter.gd")
const AIDifficulty = preload("res://scripts/systems/ai_difficulty.gd")
const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
const SunlightSystemScript = preload("res://scripts/sunlight_system.gd")
const EncounterTransitionScript = preload("res://scripts/battle/encounter_transition.gd")
const BattlePresentationScript = preload("res://scripts/battle/battle_presentation.gd")
const ActionAnimScript = preload("res://scripts/battle/action_anim.gd")
const ImmersiveCameraScript = preload("res://scripts/battle/immersive_camera.gd")
const BattleActionResolver = preload("res://scripts/battle/battle_action_resolver.gd")
const BattleFxScript = preload("res://scripts/battle/battle_fx.gd")
const BattleSfxScript = preload("res://scripts/battle/battle_sfx.gd")
const BattleResultStageScript = preload("res://scripts/battle/battle_result_stage.gd")
const BattlePrefPanelScript = preload("res://scripts/battle/battle_pref_panel.gd")
const BattleSaveScript = preload("res://scripts/battle/battle_save.gd")
const BattleCameraKickScript = preload("res://scripts/battle/battle_camera_kick.gd")
const LevelUpPresentationScript = preload("res://scripts/battle/level_up_presentation.gd")
const CampaignBattleBridgeScript = preload("res://scripts/battle/campaign_battle_bridge.gd")

var action_anim: Node = null
var _immersive_camera: Node = null
# 演出助手模块（职责见各模块头注释；battle.gd 只保留编排与契约兼容委托）
var _fx: BattleFx = null
var _sfx: BattleSfx = null
var _result_stage: BattleResultStage = null
var _pref_panel: BattlePrefPanel = null
var _save: BattleSave = null
var _camera_kick: BattleCameraKick = null
# 契约测试别名（指向模块实例/模块内部字典，勿重赋值）
var _presentation_audio: AudioStreamPlayer = null
var _presentation_sound_cache: Dictionary = {}
var _result_visual_states: Dictionary = {}

var grid: GridSystem
var turn: TurnManager
var chapter: Dictionary
var return_to_scene: String = "res://main.tscn"
## 战斗是否已结束（胜利/败北）。置位后不再推进回合，防止 turn_director 循环空转。
var _battle_ended: bool = false
var block_titles: Array = []

## B1 就地模式字段（B2 时 _world=null, _b1_mode=false）
var _b1_mode: bool = false
var _world: Node2D = null              # main.gd 引用（B1 注入）
var _world_origin: Vector2i = Vector2i.ZERO  # 战场 (0,0) 对应的世界 cell

## B1 模式战斗结束信号（main.gd 监听后 _exit_battle）；B2 走 change_scene
signal battle_finished(result: StringName)
## 统一开场链：EncounterStart → 转场/对峙 anim → BattleReady → 首个玩家回合。
signal encounter_started(mode: StringName)
signal battle_ready

var _encounter_transition: CanvasLayer = null
var _battle_presentation: Node = null

var board: IsoBoard
## B2 等距方块地形层（复用世界渲染管线：ColumnBatch + TerrainMaterialRegistry）
var renderer: Node2D = null
## 仅独立 B2 创建静态白昼；B1 复用主世界的昼夜太阳。
var _sunlight: Node3D = null
var _unit_sprites: Dictionary = {}  # unitId -> UnitSprite3D
# 范围/光标可视化层（地形回退铺底 + 移动/攻击范围菱形墙 + 光标金色呼吸墙）
var range_overlay: RangeOverlay = null
# 屏幕空间 UI（HUD + 菜单/面板/预览/横幅）
var battle_ui: BattleUI = null
# 场内升级薄演出弹窗（挂 battle_ui 顶层；只消费 resolver.gain_exp 的 levels）
# 类型用 preload 常量注解：新 class_name 未入 .godot 全局类缓存前 headless 也能解析。
var _level_up: LevelUpPresentationScript = null

# 状态机
enum Mode { IDLE, UNIT_SELECTED, MOVING, MENU, ENEMY_TURN, ANIMATING }
var mode: int = Mode.IDLE
var selected_unit: Dictionary = {}
var current_move_range: Dictionary = {}   # { "x,y" -> cost }
var current_attack_tiles: Dictionary = {} # { "x,y" -> true }
var cursor_pos: Vector2i = Vector2i.ZERO
var cursor_visible := false
# 可撤销移动：移动完成后弹出菜单期间记录「移动前位置」，按 ESC 取消移动时把单位送回。
# { unit: Dictionary, from: Vector2i } —— 菜单确认（攻击/等待）后清空。
var _pending_move_undo: Dictionary = {}

# 托管（autoplay）编排器：敌方回合 + 玩家方托管 + 偏好数据。
# hosting_active=true 时玩家回合自动跑，手动输入路径被锁。
# 仅本场战斗有效，偏好存 turn_director 内（key=unitId → {priorityTargetId, strategy}）。
var turn_director: TurnDirector = null

# ---- 战旗持久化（GameSession 自动存档；逻辑在 BattleSave 模块）----
# _save.identity 非空 → 本场战斗在完整行动边界自动提交；pending_state 非空 → 恢复进度。
# SceneArgs 读出的记录参数暂存为成员，供 _ready 拆分件之间传递（原 _ready 局部变量）。
var _save_identity := ""
var _save_state: Dictionary = {}
var _save_notice := ""
var _campaign_token := ""
var _campaign_result: StringName = &""
var _campaign_receipt: Dictionary = {}
# 击杀掉落（W4）：独立 RNG + pending 数组（挂 chapter.pending_loot，胜利结算随收据入账；
# 失败/撤退不入账——新一次出征构建新 chapter，pending 自然清空）。
var _drop_rng: RandomNumberGenerator = null
var _drop_ctx: Dictionary = {}


## _ready 装配序列（各拆分件内部顺序与拆分前逐句一致，勿调整调用顺序）：
## ① SceneArgs 参数 → ② 核心（网格/回合/编排器/存档/托管）→ ③ 渲染层+音效/结算
## → ④ UI 层+单位 sprite → ⑤ 演出模块 → 帧边界 → ⑥ 回合信号 → 开场 → ⑦ 首回合。
func _ready() -> void:
	_configure_scene_args()
	_configure_battle_core()
	_configure_render_layer()
	_configure_ui_layer()
	_configure_action_modules()
	await get_tree().process_frame
	_debug_print_unit_alignment()
	_configure_turn_signals()
	# 开场期间锁住所有输入；演出完成前不启动首个玩家回合。
	mode = Mode.ANIMATING
	set_process_input(false)
	set_process_unhandled_input(false)
	await _play_encounter_opening()
	if not is_inside_tree() or _battle_ended:
		return
	range_overlay.create_cursor_particles()
	set_process_input(true)
	set_process_unhandled_input(true)
	print("[Battle] BattleReady units=%d" % _unit_sprites.size())
	_start_first_turn_or_resume()


## _ready 拆分件①：从 SceneArgs 读战斗参数（由 main.gd._enter_battle 设置）。
func _configure_scene_args() -> void:
	if SceneArgs.battle_args.has("chapter"):
		chapter = SceneArgs.battle_args["chapter"]
		return_to_scene = SceneArgs.battle_args.get("return_to", "res://main.tscn")
		block_titles = chapter.get("blockTitles", [])
	# B1 就地模式：main.gd 通过 SceneArgs.battle_args["world"] 注入自身引用
	_world = SceneArgs.battle_args.get("world", null)
	_b1_mode = _world != null
	if _b1_mode:
		_world_origin = chapter.get("world_origin", Vector2i.ZERO)
	# 战旗记录参数：save_identity 非空开启自动存档；save_state 非空表示恢复进度
	_save_identity = String(SceneArgs.battle_args.get("save_identity", ""))
	_save_state = SceneArgs.battle_args.get("save_state", {})
	_save_notice = String(SceneArgs.battle_args.get("save_notice", ""))
	_campaign_token = String(SceneArgs.battle_args.get("campaign_token", ""))
	if not _campaign_token.is_empty():
		_save_identity = ""
		_save_state = {}
	# 击杀掉落上下文（W4）：种子 = 战场 id + campaign token 的哈希 —— 独立随机流，
	# 不消耗全局 randf（结算/经验契约不变），同一场战斗重放/保存重试掷出相同掉落；
	# 无 drop_table 的敌人零随机消费。pending_loot 每次 进 战 斗 重 置（chapter 每次新建，
	# 此处显式赋空防实例复用污染）。
	_drop_rng = RandomNumberGenerator.new()
	_drop_rng.seed = hash("%s|%s" % [String(chapter.get("id", "")), _campaign_token])
	chapter["pending_loot"] = []
	_drop_ctx = { "rng": _drop_rng, "loot": chapter["pending_loot"], "rolled": {} }


## _ready 拆分件②：网格 + 单位 + 回合 + 回合编排器 + 战旗持久化 + 托管接管。
func _configure_battle_core() -> void:
	# 1. 网格 + 单位 + 回合（与模式无关）；死亡单位只在恢复局出现——不放入 grid
	grid = GridSystem.new(chapter.width, chapter.height, chapter.map)
	# 1a. 建筑占用（B1 就地战斗无 buildings，快照缺失时为空表，安全跳过）
	grid.apply_buildings(chapter.get("buildings", []), chapter.get("user_assets", {}))
	for u in chapter.playerUnits + chapter.enemyUnits:
		if not u.isDead:
			grid.place_unit(u, u.position.x, u.position.y)
	turn = TurnManager.new(chapter.playerUnits + chapter.enemyUnits)
	turn.victory = chapter.get("victory", { &"type": &"rout" })
	add_child(turn)
	# 1b. 回合编排器（敌方 AI + 玩家方托管）
	turn_director = TurnDirector.new()
	turn_director.setup(grid, turn, chapter, _unit_sprites)
	# AI 难度档从全局设置注入（非法/缺失由 normalize 回 normal）
	turn_director.enemy_difficulty = AIDifficulty.normalize(Settings.enemy_ai_difficulty)
	turn_director.host_difficulty = AIDifficulty.normalize(Settings.host_ai_difficulty)
	# 1a. 战旗持久化模块（完整行动边界提交；toast 经 battle_ui 回交，调用时才求值）
	_save = BattleSaveScript.new()
	_save.setup(
		_save_identity,
		_save_state,
		turn,
		turn_director,
		func(msg: String) -> void: battle_ui.show_toast(msg)
	)
	_inject_turn_director_callables()
	add_child(turn_director)
	if SceneArgs.battle_args.get("hosting", false):
		turn_director.set_hosting(true)


## _ready 拆分件③：渲染层（B1/B2 分支）+ 演出音效/结算视觉模块（别名同步）。
func _configure_render_layer() -> void:
	# 2. 渲染层（B1/B2 分支）
	if _b1_mode:
		_setup_b1_render()
	else:
		_setup_b2_render()
	# 2b. 演出音效/结算视觉模块（_build_ui 的信号连接走 battle 侧委托，先建实例与别名）
	_sfx = BattleSfxScript.new()
	_sfx.name = "BattleSfx"
	add_child(_sfx)
	_sfx.setup(grid)
	_presentation_audio = _sfx.audio_player
	_presentation_sound_cache = _sfx.sound_cache
	_result_stage = BattleResultStageScript.new()
	_result_stage.name = "BattleResultStage"
	add_child(_result_stage)
	_result_stage.setup(_unit_sprites)
	_result_visual_states = _result_stage.states


## _ready 拆分件④：UI 层 + 托管偏好面板 + 退出按钮/续玩提示 + 单位 sprite。
func _configure_ui_layer() -> void:
	# 3. UI 层（屏幕空间，两种模式共用）
	_build_ui()
	# 托管偏好面板模块（容器由 battle_ui 提供；数据面读写走 turn_director）
	_pref_panel = BattlePrefPanelScript.new()
	_pref_panel.name = "BattlePrefPanel"
	add_child(_pref_panel)
	_pref_panel.setup(grid, turn_director, battle_ui.get_pref_panel_container())
	turn_director.update_host_btn_text()
	# 有存档身份的 B2 战斗提供「退出战斗」按钮（B1 由 main.gd 自己接管）
	if (not _save_identity.is_empty() or not _campaign_token.is_empty()) and not _b1_mode:
		battle_ui.set_exit_callback(_on_exit_to_list)
	if _save_notice != "":
		battle_ui.show_toast(_save_notice)
	# 4. 单位
	for u in grid.units.values():
		_spawn_unit_sprite(u)


## _ready 拆分件⑤：沉浸相机 + 演出特效/镜头踢击/行动演出模块。
func _configure_action_modules() -> void:
	# 沉浸演出相机（先建：特效预热的 LoadingScreen 遮罩门控用它）
	_immersive_camera = ImmersiveCameraScript.new()
	_immersive_camera.name = "ImmersiveCamera"
	add_child(_immersive_camera)
	_immersive_camera.setup(_world._cam if _b1_mode else board.camera)
	_immersive_camera.set_enabled(Settings.battle_immersive_presentation)
	battle_ui.immersive_presentation_changed.connect(_immersive_camera.set_enabled)
	# 沉浸遮挡：B1 用世界柱地形，B2 用战场柱地形（同一 IsometricTerrain3D 接口）。
	# B2 headless 无相机时 renderer._terrain_3d 为 null，遮挡自然停用。
	_immersive_camera.setup_occlusion(_world._terrain if _b1_mode else renderer._terrain_3d)
	# 演出特效模块（飘字/伤害数字/血条受击/抖动/预热；坐标与相机经适配方法注入）
	_fx = BattleFxScript.new()
	_fx.name = "BattleFx"
	add_child(_fx)
	_fx.setup(
		grid,
		_unit_sprites,
		_immersive_camera,
		Callable(self, "_float_cell_to_screen"),
		Callable(self, "_damage_camera"),
		Callable(battle_ui, "get_float_text_container")
	)
	# 行动演出镜头踢击（strike/return 相位附加位移；strike 出手音经 BattleSfx 回调）
	_camera_kick = BattleCameraKickScript.new()
	_camera_kick.name = "BattleCameraKick"
	add_child(_camera_kick)
	_camera_kick.setup(
		_unit_sprites,
		_immersive_camera,
		_world if _b1_mode else null,
		Callable(self, "_b2_camera"),
		Callable(_sfx, "play_strike")
	)
	action_anim = ActionAnimScript.new()
	action_anim.name = "ActionAnim"
	add_child(action_anim)
	action_anim.setup(
		_unit_sprites,
		_world._cam if _b1_mode else board.camera,
		Callable(_fx, "spawn_action_float_text")
	)
	action_anim.phase_started.connect(_camera_kick.on_phase_started)
	action_anim.finished.connect(_on_action_anim_finished)
	action_anim.finished.connect(_camera_kick.on_anim_finished)
	# 受伤特效：impacts 带 hp_before/hp_after，比 float_text 回调信息全。
	action_anim.impact_presented.connect(_on_impact_presented)


## _ready 拆分件⑥：回合信号 + viewport resize（仅 B2 需要重居中）。
func _configure_turn_signals() -> void:
	# 5. 输入 + 回合
	turn.phase_player.connect(_on_player_phase)
	turn.phase_enemy.connect(_on_enemy_phase)
	if not _b1_mode:
		# B2 才需要 viewport resize 重居中（B1 由 main.gd 管相机）
		get_viewport().size_changed.connect(_on_viewport_resized)


## _ready 拆分件⑦：恢复进度或启动首个玩家回合，最后发出 battle_ready
## （battle_ready 语义 = 完全就绪，含首回合复位/冷却/buff tick）。
func _start_first_turn_or_resume() -> void:
	var resume_state := _save.consume_pending_state()
	if not resume_state.is_empty():
		# 恢复进度：不复位列标志/不重跑开局 tick，直接进保存时的阶段
		_apply_resume_state(resume_state)
	else:
		# 首个玩家回合必须在 battle_ready 之前启动：
		# 监听方恢复后会立即行动结算，若 start_player_phase 仍在其后执行，
		# 复位 hasActed 会覆盖已落地的结算置位。
		turn.start_player_phase()
	battle_ready.emit()


func _play_encounter_opening() -> void:
	var transition_mode: StringName = &"b1" if _b1_mode else &"b2_reveal"
	battle_ui.set_phase_text("遭遇战", Color(0.95, 0.78, 0.32))
	encounter_started.emit(transition_mode)
	print("[Battle] EncounterStart mode=%s" % String(transition_mode))
	_encounter_transition = EncounterTransitionScript.new()
	add_child(_encounter_transition)
	await _encounter_transition.play(transition_mode)
	if not is_inside_tree() or _battle_ended:
		return
	_battle_presentation = BattlePresentationScript.new()
	add_child(_battle_presentation)
	var presentation_camera: Camera3D = _world._cam if _b1_mode else board.camera
	await _battle_presentation.play_standoff(
		_unit_sprites, presentation_camera, not _b1_mode
	)
	if not is_inside_tree() or _battle_ended:
		return
	var opening_units: Array = grid.units.values()
	var boss: Dictionary = chapter.get("boss", {})
	await battle_ui.play_opening(opening_units, boss)


## 演出结束（含跳过/中断）立即按当前 HP 恢复常驻血条。
## 镜头踢击清零由 BattleCameraKick.on_anim_finished（并列订阅）负责。
func _on_action_anim_finished(_event: Dictionary, _skipped: bool) -> void:
	_set_unit_bars_visible(true)


## B2 切场景模式渲染初始化：等距方块地形（像素版 Minecraft 风格，复用世界渲染管线）
func _setup_b2_render() -> void:
	# 独立场景没有 main.gd 的昼夜系统，固定为可读的正午真实日照。
	_sunlight = SunlightSystemScript.new()
	_sunlight.name = "BattleSunlight"
	add_child(_sunlight)
	_sunlight.apply_time(0.5, 0.0)
	board = IsoBoard.new()
	board.name = "Board"
	add_child(board)
	# 地形柱层（ColumnBatch 逐柱渲染，y_sort 处理柱间遮挡）
	renderer = BattlefieldRendererScript.new()
	board.add_child(renderer)
	# JSON 战场植物层（chapter.props，编辑器放置的具体树/植物）——setup 前注入生效
	renderer.set_custom_props(chapter.get("props", []))
	# 用户素材视觉层（props 的 asset_id + tile_overrides；离线读 user://custom_assets 库+blob，
	# 缺图返回占位 visual，引用不丢失）——setup 前注入生效
	var visual_adapter: RefCounted = UserAssetVisualAdapterScript.new()
	renderer.set_custom_assets(
		visual_adapter.visual_for_entries(
			chapter.get("props", []), chapter.get("tile_overrides", {})
		)
	)
	renderer.set_building_visuals(visual_adapter.visual_for_buildings(
		chapter.get("buildings", []), chapter.get("user_assets", {})), false)
	renderer.set_block_layout(chapter.get("block_layout", {}))
	renderer.setup(grid)
	_sync_building_view()
	# 范围/光标标记走注入模式：坐标/排序/高度由 renderer 提供（同 B1 的注入方式）
	range_overlay = RangeOverlay.new()
	add_child(range_overlay)
	range_overlay.setup_world(
		board, grid, block_titles,
		Callable(self, "_b2_cell_to_screen"),
		Callable(renderer, "sort_for"),
		Callable(renderer, "visual_top_level")
	)
	board.center_on_map(chapter.width, chapter.height)
	# B2 相机按侧栏宽度预留右侧取景（与 B1 世界相机的预留对齐；battle_ui 侧栏同宽覆盖）。
	# 预留换算用名义 size（isometric_camera_3d._reserved_lateral_world），不受 ActionAnim
	# 推近影响，strike 相位相机位移仍只来自 presentation_offset（演出契约保持）。
	if board.camera != null:
		board.camera.reserved_right_px = BattleUI.SIDEBAR_WIDTH


## B1 就地模式渲染初始化：不创建 IsoBoard，单位/范围层挂 main.gd 下
func _setup_b1_render() -> void:
	print("[battle] B1 就地模式：world_origin=%s" % str(_world_origin))
	range_overlay = RangeOverlay.new()
	_world.add_child(range_overlay)  # 挂 main.gd 下参与 y_sort
	# 注入坐标/sort 转换函数（闭包捕获 _world / _world_origin）
	var coord_fn := Callable(self, "_b1_cell_to_screen")
	var sort_fn := Callable(self, "_b1_cell_to_sort_y")
	var level_fn := Callable(self, "_b1_cell_level")
	range_overlay.setup_world(_world, grid, block_titles, coord_fn, sort_fn, level_fn)
	# B1 不画 terrain fallback（main.gd 已有真实地形）


func _b2_cell_to_screen(x: int, y: int, level := -1.0) -> Vector2:
	# 范围/路径默认贴可见顶面；显式 level 的菜单定位仍沿用单位站立层。
	if level < 0.0:
		return renderer.top_center_for(x, y)
	return board.cell_to_screen(x, y, level)


## B1 坐标转换：战场局部 cell (x,y) → 屏幕坐标（供 range_overlay 用）
func _b1_cell_to_screen(x: int, y: int, level := -1.0) -> Vector2:
	var world_cell: Vector2i = _world_origin + Vector2i(x, y)
	var lvl: float = float(_world.cell_stand_level(world_cell)) if level < 0.0 else level
	return _world._grid_to_screen(world_cell, lvl)


## B1 sort_y 转换：战场局部 cell (x,y) → sort_y（供 range_overlay 用）
func _b1_cell_to_sort_y(x: int, y: int) -> float:
	var world_cell: Vector2i = _world_origin + Vector2i(x, y)
	return _world._column_sort_y(world_cell)


func _b1_cell_level(x: int, y: int) -> int:
	var world_cell: Vector2i = _world_origin + Vector2i(x, y)
	return _world.cell_stand_level(world_cell)


## 飘字/特效脚点坐标（默认站立/可见顶面层；BattleFx 经 cell_screen_fn 注入使用，
## 与拆分前 _spawn_float_text 的 B1/B2 分支逐行等价）。
func _float_cell_to_screen(x: int, y: int) -> Vector2:
	if _b1_mode:
		return _b1_cell_to_screen(x, y)
	var lvl: int = renderer.visual_top_level(x, y) if renderer != null else 0
	return board.cell_to_screen(x, y, float(lvl))


## 当前取景相机（BattleFx 伤害特效 unproject 用；B1 世界相机 / B2 战场相机）。
func _damage_camera() -> Camera3D:
	if _b1_mode and is_instance_valid(_world):
		return _world._cam
	if is_instance_valid(board):
		return board.camera
	return null


## B2 演出相机（BattleCameraKick 的 presentation_offset 通道）。
func _b2_camera() -> Camera3D:
	if is_instance_valid(board):
		return board.camera
	return null


## 屏幕坐标 → 战场 cell（仅 B2 调用；B1 走 _screen_to_battle_cell* 系列）。
## renderer.pick_cell 逐层尝试柱顶投影，支持高低起伏地形。
func _pick_battle_cell(screen_pos: Vector2) -> Vector2i:
	return renderer.pick_cell(screen_pos, get_viewport().get_visible_rect().size)


## 把 battle.gd 自己的方法注入 turn_director（让它能回交战斗演出 / 胜负 / 状态机修改，
## 而无需持有父场景引用）。
func _inject_turn_director_callables() -> void:
	turn_director.on_resolve_combat = _resolve_combat
	turn_director.on_resolve_skill = _resolve_skill
	turn_director.on_resolve_item = _resolve_item
	# 普攻统一在 ActionAnim 完成后再刷新死亡/经验；敌方与托管也走同一入口。
	turn_director.on_resolve_combat_async = _resolve_combat_async
	turn_director.on_check_battle_end = _check_battle_end
	# 完整回合结束（敌方相位末尾）走带 end_of_round 语境的判定：defend_turns/seize 生效点
	turn_director.on_round_end_check = _check_battle_end.bind(true)
	turn_director.on_clear_range_highlight = _clear_range_highlight
	turn_director.on_clear_selection = _clear_selection
	turn_director.on_set_mode = _set_mode_from_director
	# 敌方/托管每个单位行动完成后提交一次完整快照
	turn_director.on_action_committed = _commit_snapshot


func _clear_selection() -> void:
	selected_unit = {}


func _set_mode_from_director(m: int) -> void:
	mode = m


func _on_viewport_resized() -> void:
	if is_instance_valid(board) and not chapter.is_empty():
		board.center_on_map(chapter.width, chapter.height)


# ============================================================
# UI（屏幕空间）—— 委托给 BattleUI
# ============================================================
func _build_ui() -> void:
	battle_ui = BattleUI.new()
	battle_ui.setup(board, grid, _unit_sprites, turn)
	# B1 没有 IsoBoard；菜单定位与范围层共用同一套真实顶面投影。
	battle_ui.cell_screen_fn = Callable(self, "_b1_cell_to_screen" if _b1_mode else "_b2_cell_to_screen")
	battle_ui.level_fn = Callable(self, "_b1_cell_level") if _b1_mode else Callable(renderer, "visual_top_level")
	add_child(battle_ui)
	battle_ui.cheer_requested.connect(_on_presentation_cheer)
	battle_ui.collapse_requested.connect(_on_presentation_collapse)
	battle_ui.presentation_sound_requested.connect(_on_presentation_sound)
	_inject_battle_ui_callables()
	battle_ui.build(_on_end_turn, _toggle_hosting, _open_pref_panel)
	# 升级薄演出：挂 battle_ui 顶层（build 后加入 → 绘制序在菜单/预览/结算演出之上），
	# 音效信号复用结算演出的真实素材链（_on_presentation_sound → BattleSfx）。
	_level_up = LevelUpPresentationScript.new()
	_level_up.name = "LevelUpPresentation"
	battle_ui.add_child(_level_up)
	_level_up.sound_requested.connect(_on_presentation_sound)


## 把 battle.gd 的方法注入 battle_ui（让它能回交战斗演出 / 状态机修改 / 胜负判定，
## 而无需持有父场景引用）。
func _inject_battle_ui_callables() -> void:
	battle_ui.on_resolve_combat = _resolve_combat
	battle_ui.on_resolve_skill = _resolve_skill
	battle_ui.on_resolve_item = _resolve_item
	battle_ui.on_finish_player_action = _finish_player_action
	battle_ui.on_clear_selection = _clear_selection
	battle_ui.on_clear_pending_move_undo = _clear_pending_move_undo
	battle_ui.on_cancel_move = _cancel_move
	battle_ui.on_select_unit = _select_unit
	battle_ui.on_set_mode = _set_mode_from_director
	battle_ui.on_check_battle_end = _check_battle_end
	battle_ui.on_should_end_turn_after_action = _should_end_turn_after_action
	# host_btn 由 battle_ui.build 内部创建，通过回调交给 turn_director
	battle_ui.set_host_btn_callback(func(btn: Button): turn_director.set_host_btn(btn))
	# close_menu 复位 mode（仅当当前是 MENU 态）
	battle_ui.set_menu_closed_callback(_on_menu_closed)


func _clear_pending_move_undo() -> void:
	_pending_move_undo.clear()


## close_menu 回调：仅当当前是 MENU 态时回到 IDLE（复刻原 _close_menu 的 if mode==MENU 判断）。
func _on_menu_closed() -> void:
	if mode == Mode.MENU:
		mode = Mode.IDLE


func _should_end_turn_after_action() -> bool:
	return turn.phase == &"player" and turn.all_player_acted()


func _on_player_phase(turn_num: int) -> void:
	if _battle_ended:
		return  # 战斗已分胜负，丢弃后续回合信号
	# L1 埋点：回合切换（按 AGENTS.md 调试埋点强制原则）
	print("[turn] === 玩家回合 #%d 开始 ===" % turn_num)
	Sfx.play(&"turn_player")
	mode = Mode.IDLE
	battle_ui.set_phase_text("第 %d 轮 · 我方行动" % turn_num, Color(0.29, 0.87, 0.50))
	_refresh_all_units()
	_commit_snapshot()
	# 托管模式下不需要手动选中（托管自己驱动），跳过 debug_auto_select 避免范围墙未入树报错
	if SceneArgs.battle_args.get("debug_auto_select_first_player", false) and not turn_director.is_hosting():
		SceneArgs.battle_args.erase("debug_auto_select_first_player")
		for u in grid.units.values():
			if u.faction == &"player" and not u.hasActed and not u.isDead:
				_select_unit(u)
				break
	# 托管：玩家回合自动跑移动+攻击
	if turn_director.is_hosting():
		turn_director.start_player_auto_phase()


func _on_enemy_phase(turn_num: int) -> void:
	if _battle_ended:
		return  # 战斗已分胜负，丢弃后续回合信号
	# L1 埋点：回合切换
	print("[turn] === 敌方回合 #%d 开始 ===" % turn_num)
	Sfx.play(&"turn_enemy")
	battle_ui.set_phase_text("第 %d 轮 · 敌方行动" % turn_num, Color(0.97, 0.44, 0.44))
	mode = Mode.ENEMY_TURN
	_clear_range_highlight()
	# TurnManager 已在信号前复位敌方行动状态；立即恢复存活单位亮度与顶部状态。
	_refresh_all_units()
	_commit_snapshot()

	# 增援：敌方回合开始时刷入到点波次（先于 AI，使新单位本回合即可行动）
	_spawn_due_reinforcements(turn_num)

	turn_director.start_enemy_phase()


## 刷入到点增援并补齐 sprite/快照。恢复局敌方回合重入时同样走这里。
func _spawn_due_reinforcements(turn_num: int) -> void:
	var spawned: Array = ReinforcementSpawner.spawn_due(chapter, grid, turn, turn_num)
	if spawned.is_empty():
		return
	for u in spawned:
		_spawn_unit_sprite(u)
		var us: UnitSprite3D = _unit_sprites[u.id]
		us.update_state()
	print("[reinforcement] 第 %d 轮敌方回合刷入 %d 个增援" % [turn_num, spawned.size()])
	_commit_snapshot()


# ============================================================
# 战旗持久化（BattleSave 模块；battle.gd 保留委托以维持注入面）
# ============================================================
## 在完整行动边界提交（回合开始 / 行动收尾 / 终局）。result 非空表示终局记录。
## 逻辑在 BattleSave.commit；turn_director.on_action_committed 与终局路径都调本委托。
func _commit_snapshot(result: StringName = &"") -> void:
	if _save != null:
		_save.commit(chapter, result)


## 恢复进度：不复位行动标志、不重跑开局 tick（冷却/buff 由存档单位数据承载）。
## 保存时若已分胜负则直接重演结算画面。
func _apply_resume_state(state: Dictionary) -> void:
	var phase: StringName = state.get("phase", &"player")
	turn.restore_state(phase, int(state.get("turn_number", 1)))
	turn_director.restore_prefs(state.get("prefs", {}))
	turn_director.set_hosting(bool(state.get("hosting", false)))
	var result: StringName = state.get("result", &"")
	print("[battle] Resume turn=%d phase=%s hosting=%s result=%s" % [
		turn.turn_number, String(phase), str(turn_director.is_hosting()), String(result)])
	if result == &"win" or result == &"lose":
		_battle_ended = true
		mode = Mode.ANIMATING
		_restore_result_visuals()
		_present_result(result)
		return
	if phase == &"player":
		_on_player_phase(turn.turn_number)
	else:
		battle_ui.set_phase_text("第 %d 轮 · 敌方行动" % turn.turn_number, Color(0.97, 0.44, 0.44))
		mode = Mode.ENEMY_TURN
		_clear_range_highlight()
		_refresh_all_units()
		_spawn_due_reinforcements(turn.turn_number)
		turn_director.start_enemy_phase()


## 「退出战斗」按钮：回到 return_to_scene；落盘由 _exit_tree 的 flush 兜底。
func _on_exit_to_list() -> void:
	if mode == Mode.ANIMATING and not _battle_ended:
		return  # 行动演出中不允许退出（防半行动快照）
	if mode == Mode.ENEMY_TURN:
		return  # 敌方回合推进中不允许退出
	if not _campaign_token.is_empty():
		var result: StringName = _campaign_result if _battle_ended else &"abandon"
		if not _settle_campaign(result):
			return
	battle_ui.close_menu()
	var tree := get_tree()
	if tree != null:
		if not _campaign_token.is_empty():
			SceneArgs.battle_args = {}
		tree.change_scene_to_file(return_to_scene)


# ============================================================
# 单位 sprite
# ============================================================
func _spawn_unit_sprite(u: Dictionary) -> void:
	var us := UnitSprite3D.new()
	if _b1_mode:
		# B1 就地模式：挂 main.gd 下，用 setup_world 注入世界引用 + stand_level
		var world_cell: Vector2i = _world_origin + u.position
		var stand_level: int = _world.cell_stand_level(world_cell)
		_world.add_child(us)
		us.setup_world(u, _world, stand_level, _world_origin)
	else:
		# B2 切场景模式：挂 board 下，注入 renderer.visual_top_level 站上可视柱顶
		board.add_child(us)
		us.setup(u, board, Callable(renderer, "visual_top_level"))
	_unit_sprites[u.id] = us


## 常驻血条显隐：仅在攻击/技能/物品等演出期间隐藏（受击特效在同一锚点演出），
## 演出结束/中断/退出按各 sprite 当前 hp 与原有可见性规则恢复。
func _set_unit_bars_visible(visible_: bool) -> void:
	for us in _unit_sprites.values():
		if is_instance_valid(us):
			(us as UnitSprite3D).set_persistent_bar_visible(visible_)


func _debug_print_unit_alignment() -> void:
	# 2D 版简化：只打印 cell 与单位屏幕坐标
	for u in grid.units.values():
		var us: UnitSprite3D = _unit_sprites.get(u.id)
		if us == null:
			continue
		var pos: Vector2i = u.position
		# B2 等距渲染下单位站在可视柱顶（renderer.visual_top_level）；B1 就地模式无 renderer，退回 0 层
		var lvl := 0
		if renderer != null:
			lvl = renderer.visual_top_level(pos.x, pos.y)
		var projection_pos := pos
		var projection_camera: Camera3D = null
		if _b1_mode:
			projection_pos += _world_origin
			projection_camera = _world._cam
			lvl = _world.cell_stand_level(projection_pos)
		elif board != null:
			projection_camera = board.camera
		if projection_camera == null:
			continue
		var screen := IsoProjection.world_to_screen(projection_camera, IsoProjection.grid_to_world(projection_pos, float(lvl)))
		print("[DEBUG-unit-align] id=%s name=%s cell=%s screen=%s actual=%s" % [
			str(u.id), str(u.name), str(pos), str(screen), str(us.global_position)
		])


func _refresh_all_units() -> void:
	for us in _unit_sprites.values():
		us.update_state()


# ============================================================
# 输入
# ============================================================
var _panning := false
var _pan_last := Vector2.ZERO
var _dragged := false
## hover 路径重算节流：上次重算时间（毫秒），避免鼠标快速移动时高频跑 find_path + 重建箭头。
var _last_path_update_msec := 0
## 临时平移（按住空格）：松开恢复普通点击/拖拽语义。
var _space_pan_active := false


func _is_presentation_skip_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo and key.keycode in [
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE
		]
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		return mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
	return false


func _skip_action_presentation() -> void:
	# 进入期 ActionAnim 尚未 play：先记录跳过并平滑反向，随后 play 同步完成。
	if is_instance_valid(_immersive_camera) and _immersive_camera.get_state() == ImmersiveCameraScript.State.ENTERING:
		_immersive_camera.request_skip()
	if action_anim != null and action_anim.is_playing():
		action_anim.skip()


## 手势 / 空格 / 滚轮：用 _input（GUI 处理前）确保一定能收到。
## 战场 UI（结束回合按钮 / 菜单面板）命中时让出缩放手势，避免误触。
## B1 就地模式下相机由 main.gd 管，这里全部跳过（避免 board 为 null 崩溃）。
func _input(event: InputEvent) -> void:
	# B2 遭遇转场期间锁死平移、缩放与旋转。
	if mode == Mode.ANIMATING:
		if battle_ui != null and battle_ui.is_presentation_active() and _is_presentation_skip_event(event):
			battle_ui.skip_presentation()
		elif _is_presentation_skip_event(event):
			_skip_action_presentation()
		get_viewport().set_input_as_handled()
		return
	if _b1_mode:
		return  # B1：相机/拾取由 main.gd._handle_battle_input 接管
	# 按住空格 = 临时平移模式（左键拖地图），松开恢复（与编辑器一致）
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_SPACE and not k.echo:
			if k.pressed:
				_space_pan_active = true
			elif _space_pan_active:
				_space_pan_active = false
			get_viewport().set_input_as_handled()
			return
	# 捏合/滚动手势分支必须与上面的 Key 分支平级——
	# 曾误写成 elif 挂在 `if event is InputEventKey` 内，手势事件永远不可能是 Key，整段成为死代码。
	if event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		if battle_ui.is_over_ui(g.position):
			return
		var factor := clampf(1.0 / g.factor, 0.5, 2.0)
		board.zoom_by(factor, g.position, get_viewport().get_visible_rect().size)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventPanGesture:
		var g := event as InputEventPanGesture
		if battle_ui.is_over_ui(g.position):
			return
		if absf(g.delta.y) > absf(g.delta.x):
			var factor := clampf(1.0 + g.delta.y * 0.08, 0.75, 1.25)
			board.zoom_by(factor, g.position, get_viewport().get_visible_rect().size)
			get_viewport().set_input_as_handled()
		return


# ============================================================
# 输入路由（演出期拦截 / 键盘路由表 / 鼠标分发；B1 也由 main.gd 直接调用）
# ============================================================
## 键盘路由表（keycode → handler Callable；Q/X/R 的 B1 guard 在 handler 内）。
## 惰性构建：首次按键时填充一次。
var _key_handlers: Dictionary = {}


func _unhandled_input(event: InputEvent) -> void:
	# 遭遇演出期间禁用移动/菜单等全部战斗输入（B1 也由 main.gd 直接调用此函数）。
	if mode == Mode.ANIMATING:
		_handle_input_while_animating(event)
		return
	if event is InputEventKey:
		_handle_key_input(event as InputEventKey)
	elif event is InputEventMouseButton:
		_handle_mouse_button_input(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion_input(event as InputEventMouseMotion)


## 演出期间只保留「跳过」语义，其余输入一律吞掉。
func _handle_input_while_animating(event: InputEvent) -> void:
	if battle_ui != null and battle_ui.is_presentation_active() and _is_presentation_skip_event(event):
		battle_ui.skip_presentation()
	elif _is_presentation_skip_event(event):
		_skip_action_presentation()
	get_viewport().set_input_as_handled()


func _handle_key_input(k: InputEventKey) -> void:
	if not k.pressed:
		return
	var handler: Callable = _key_route().get(k.keycode)
	if handler.is_valid():
		handler.call()


func _key_route() -> Dictionary:
	if _key_handlers.is_empty():
		_key_handlers = {
			KEY_ESCAPE: Callable(self, "_on_cancel"),
			KEY_ENTER: Callable(self, "_on_confirm"),
			KEY_Z: Callable(self, "_on_confirm"),
			KEY_E: Callable(self, "_on_end_turn"),
			KEY_Q: Callable(self, "_rotate_camera").bind(-1),
			KEY_X: Callable(self, "_rotate_camera").bind(1),
			KEY_R: Callable(self, "_reset_camera_rotation"),
			KEY_UP: Callable(self, "_move_cursor").bind(0, -1),
			KEY_DOWN: Callable(self, "_move_cursor").bind(0, 1),
			KEY_LEFT: Callable(self, "_move_cursor").bind(-1, 0),
			KEY_RIGHT: Callable(self, "_move_cursor").bind(1, 0),
		}
	return _key_handlers


## B2 专属视角操作（B1 就地模式下视角归世界相机管，不响应）。
func _rotate_camera(step: int) -> void:
	if not _b1_mode:
		board.camera.rotate_step(step)
		_sync_building_view()


func _reset_camera_rotation() -> void:
	if not _b1_mode:
		board.camera.reset_rotation()
		_sync_building_view()


## 建筑前背图按目标四向视角切换；地形几何与站立高度保持原有契约。
func _sync_building_view() -> void:
	if renderer == null or board == null or board.camera == null:
		return
	var quadrant := roundi((float(board.camera.target_yaw_radians) - PI * 0.25) / (PI * 0.5))
	renderer.set_camera_quadrant(posmod(quadrant, 4))


func _handle_mouse_button_input(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_handle_wheel_zoom(mb, 0.9)
		MOUSE_BUTTON_WHEEL_DOWN:
			_handle_wheel_zoom(mb, 1.1)
		MOUSE_BUTTON_LEFT:
			_handle_left_click(mb)
		MOUSE_BUTTON_RIGHT:
			_handle_right_click(mb)
		MOUSE_BUTTON_MIDDLE:
			_handle_middle_click(mb)


func _handle_wheel_zoom(mb: InputEventMouseButton, factor: float) -> void:
	if mb.pressed and not _b1_mode:
		board.zoom_by(factor, mb.position, get_viewport().get_visible_rect().size)


## 左键：按下（B2）进入平移；释放时非空格平移/非拖拽视为选格点击。
func _handle_left_click(mb: InputEventMouseButton) -> void:
	if mb.pressed:
		if not _b1_mode:
			_panning = true
			_pan_last = mb.position
	else:
		# 左键释放：非平移、非拖拽时视为选格点击
		if not _space_pan_active and not _dragged:
			_on_tile_click_at_screen(mb.position)
		_panning = false
		_dragged = false


## 右键：查看单位详情面板（任意阵营，不干扰左键的选中/攻击）。
func _handle_right_click(mb: InputEventMouseButton) -> void:
	if not mb.pressed:
		return
	if battle_ui.is_over_ui(mb.position):
		return
	var detail_cell: Vector2i
	if _b1_mode:
		detail_cell = _screen_to_battle_cell(mb.position)
	else:
		detail_cell = _pick_battle_cell(mb.position)
	if detail_cell.x >= 0 and detail_cell.x < grid.width \
			and detail_cell.y >= 0 and detail_cell.y < grid.height:
		var du := grid.unit_at(detail_cell.x, detail_cell.y)
		if not du.is_empty():
			battle_ui.open_unit_detail(du)


## 中键：B2 平移拖拽（按下/释放）。
func _handle_middle_click(mb: InputEventMouseButton) -> void:
	if _b1_mode:
		return
	if mb.pressed:
		_panning = true
		_pan_last = mb.position
	else:
		_panning = false


func _handle_mouse_motion_input(mm: InputEventMouseMotion) -> void:
	if _panning and not _b1_mode:
		_handle_pan_motion(mm)
	elif not _panning:
		_handle_hover_motion(mm)


## 平移拖拽：Ctrl 只水平转视角，否则平移棋盘；位移超阈值记为拖拽（抑制释放点击）。
func _handle_pan_motion(mm: InputEventMouseMotion) -> void:
	if mm.ctrl_pressed:
		board.camera.drag_by(Vector2(mm.position.x - _pan_last.x, 0.0))
	else:
		board.pan(mm.position.x - _pan_last.x, mm.position.y - _pan_last.y)
	_pan_last = mm.position
	if mm.relative.length() > 3:
		_dragged = true


## hover 移动光标（B1 用 main.gd.screen_to_cell，B2 用 board.pick_cell）。
func _handle_hover_motion(mm: InputEventMouseMotion) -> void:
	if turn_director.is_hosting() or mode == Mode.ENEMY_TURN or mode == Mode.ANIMATING \
			or battle_ui.has_open_menu() or battle_ui.is_over_ui(mm.position):
		return
	var hover_cell: Vector2i
	if _b1_mode:
		hover_cell = _screen_to_battle_cell_unbounded(mm.position)
	else:
		hover_cell = _pick_battle_cell(mm.position)
	if hover_cell != cursor_pos:
		cursor_pos = hover_cell
		cursor_visible = true
		range_overlay.update_cursor_particles(hover_cell.x, hover_cell.y, true)
		if grid.in_bounds(hover_cell.x, hover_cell.y):
			battle_ui.show_info_at(hover_cell.x, hover_cell.y)
			_update_hover_path(hover_cell)


## B1 模式：屏幕坐标 → 战场局部 cell（经 main.gd.screen_to_cell 拿世界 cell，再减 origin）
func _screen_to_battle_cell_unbounded(screen_pos: Vector2) -> Vector2i:
	var world_cell: Vector2i = _world.screen_to_cell(screen_pos)
	return world_cell - _world_origin


func _screen_to_battle_cell(screen_pos: Vector2) -> Vector2i:
	var world_cell: Vector2i = _world.screen_to_cell_in_rect(
		screen_pos,
		_world_origin,
		Vector2i(grid.width, grid.height)
	)
	return world_cell - _world_origin


## B1 模式：屏幕坐标 → 战场局部 cell（_on_tile_click_at_screen 用）
## 重写 _on_tile_click_at_screen 让它兼容两种模式
func _on_tile_click_at_screen(screen_pos: Vector2) -> void:
	if turn_director.is_hosting():
		return
	if mode == Mode.ENEMY_TURN or mode == Mode.ANIMATING:
		return
	if battle_ui.has_open_menu():
		return
	# 详情面板打开时，左键先关闭它（详情是临时查看，不与操作混用）
	if battle_ui.is_unit_detail_open():
		battle_ui.close_unit_detail()
		return
	var cell: Vector2i
	if _b1_mode:
		cell = _screen_to_battle_cell(screen_pos)
	else:
		cell = _pick_battle_cell(screen_pos)
	if cell.x < 0 or cell.x >= grid.width or cell.y < 0 or cell.y >= grid.height:
		return
	cursor_pos = cell
	cursor_visible = true
	range_overlay.update_cursor_particles(cell.x, cell.y, true)
	_on_tile_click(cell.x, cell.y)


func _move_cursor(dx: int, dy: int) -> void:
	if turn_director.is_hosting():
		return
	if mode == Mode.ENEMY_TURN or mode == Mode.ANIMATING:
		return
	if battle_ui.has_open_menu():
		return
	cursor_pos = Vector2i(clampi(cursor_pos.x + dx, 0, grid.width - 1), clampi(cursor_pos.y + dy, 0, grid.height - 1))
	cursor_visible = true
	range_overlay.update_cursor_particles(cursor_pos.x, cursor_pos.y, true)
	battle_ui.show_info_at(cursor_pos.x, cursor_pos.y)
	_update_hover_path(cursor_pos)


func _on_confirm() -> void:
	if turn_director.is_hosting():
		return
	if not grid.in_bounds(cursor_pos.x, cursor_pos.y):
		return
	_on_tile_click(cursor_pos.x, cursor_pos.y)


func _on_cancel() -> void:
	if turn_director.is_hosting():
		return
	# 详情面板打开时，ESC 优先关闭它
	if battle_ui.is_unit_detail_open():
		battle_ui.close_unit_detail()
		return
	if battle_ui.has_open_menu():
		# 移动完成后的菜单：ESC = 取消移动，把单位送回原位并重新选中。
		_cancel_move()
		return
	if mode == Mode.UNIT_SELECTED:
		_clear_range_highlight()
		selected_unit = {}

		mode = Mode.IDLE


func _on_end_turn() -> void:
	if turn_director.is_hosting():
		return
	if mode == Mode.IDLE or mode == Mode.UNIT_SELECTED:
		_clear_range_highlight()
		selected_unit = {}
		
		mode = Mode.IDLE
		turn.end_turn()


# ============================================================
# 点击逻辑（与 TS 版一致）
# ============================================================
func _on_tile_click(x: int, y: int) -> void:
	if turn_director.is_hosting():
		return
	if mode == Mode.ENEMY_TURN or mode == Mode.ANIMATING:
		return
	if battle_ui.has_open_menu():
		return
	battle_ui.show_info_at(x, y)
	var u := grid.unit_at(x, y)
	if mode == Mode.IDLE:
		if not u.is_empty() and u.faction == &"player" and not u.hasActed:
			_select_unit(u)
	elif mode == Mode.UNIT_SELECTED and not selected_unit.is_empty():
		var key := "%d,%d" % [x, y]
		if current_move_range.has(key) and u.is_empty():
			_perform_move(selected_unit, Vector2i(x, y))
		elif current_attack_tiles.has(key) and not u.is_empty() and u.faction != &"player":
			_perform_attack_from_current(selected_unit, u)
		elif not u.is_empty() and u.faction == &"player" and not u.hasActed:
			_clear_range_highlight()
			_select_unit(u)
		else:
			_on_cancel()


# ============================================================
# 选中 & 范围高亮
# ============================================================
func _select_unit(u: Dictionary) -> void:
	selected_unit = u
	mode = Mode.UNIT_SELECTED
	var res := grid.compute_attack_range(u.position.x, u.position.y, u)
	current_move_range = res.moveRange
	current_attack_tiles = res.attackTiles
	range_overlay.highlight_range(current_move_range, current_attack_tiles, selected_unit)
	range_overlay.update_cursor_particles(u.position.x, u.position.y, true)


func _clear_range_highlight() -> void:
	range_overlay.clear_range_highlight()
	current_move_range.clear()
	current_attack_tiles.clear()


## hover 路径指示：选中单位时，按 hover 格类型画路径——
## - hover 移动范围内的空格 → 蓝色路径（移动路径，单位走过去）
## - hover 攻击范围内的敌方单位 → 红色路径（攻击路径）：找一个「相邻于敌人、在移动范围内、空」
##   的攻击站位，画从单位→站位的红色路径（单位走到站位就能打到目标）。
##   要求该站位在移动范围内（单位可达）——否则不显示（单位打不到该目标）。
## 否则清路径。
func _update_hover_path(hover_cell: Vector2i) -> void:
	# 节流：至少 50ms 才重算一次路径（find_path + 重建箭头较重，防鼠标快速移动卡顿）
	var now_msec := Time.get_ticks_msec()
	if now_msec - _last_path_update_msec < 50:
		return
	_last_path_update_msec = now_msec
	if selected_unit.is_empty() or mode != Mode.UNIT_SELECTED:
		range_overlay.clear_path()
		range_overlay.clear_threat_arrows()
		return
	var key := "%d,%d" % [hover_cell.x, hover_cell.y]
	var hover_unit := grid.unit_at(hover_cell.x, hover_cell.y)
	if not hover_unit.is_empty() and hover_unit.faction != &"player":
		var stand := _find_attack_stand(hover_cell)
		if stand.x >= 0:
			var atk_path := grid.find_path(selected_unit.position, stand, selected_unit.moveType, selected_unit.stats.mov)
			if not atk_path.is_empty() and atk_path.size() >= 2:
				range_overlay.show_path(atk_path, Color(1.0, 0.25, 0.25))
				range_overlay.clear_threat_arrows()
				return
		range_overlay.clear_path()
		range_overlay.clear_threat_arrows()
		return
	# 移动路径：hover 移动范围内的空格 → 蓝色路径 + 所有威胁该落点的敌人抛物线。
	if current_move_range.has(key):
		_update_threat_arrows(hover_cell)
		var path := grid.find_path(selected_unit.position, hover_cell, selected_unit.moveType, selected_unit.stats.mov)
		if not path.is_empty() and path.size() >= 2:
			range_overlay.show_path(path, Color(0.25, 0.55, 1.0))   # 蓝
			return
	range_overlay.clear_path()
	range_overlay.clear_threat_arrows()


## 候选落点沿用现有攻击距离规则；每个能攻击该格的存活敌人各产生一条箭头。
func _update_threat_arrows(target: Vector2i) -> void:
	var sources: Array[Vector2i] = []
	for unit in grid.units.values():
		if unit.get(&"isDead", false) or unit.get(&"faction", &"") == &"player":
			continue
		var attack_range: Array = ProfessionData.unit_attack_range(unit)
		var dist := absi(unit.position.x - target.x) + absi(unit.position.y - target.y)
		if dist >= int(attack_range[0]) and dist <= int(attack_range[1]):
			sources.append(unit.position)
	range_overlay.show_threat_arrows(sources, target)


## 找一个攻击站位：在移动范围内、该格可停、且所选单位从该格能打到 target_cell。
## 返回站位 Vector2i；找不到返回 Vector2i(-1,-1)。
func _find_attack_stand(target_cell: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_len := 9999
	var attack_range: Array = ProfessionData.unit_attack_range(selected_unit)
	var min_range: int = int(attack_range[0])
	var max_range: int = int(attack_range[1])
	for move_key in current_move_range.keys():
		var p := (move_key as String).split(",")
		var stand := Vector2i(p[0].to_int(), p[1].to_int())
		if stand != selected_unit.position and not grid.unit_at(stand.x, stand.y).is_empty():
			continue
		var attack_dist := absi(stand.x - target_cell.x) + absi(stand.y - target_cell.y)
		if attack_dist < min_range or attack_dist > max_range:
			continue
		var path := grid.find_path(selected_unit.position, stand, selected_unit.moveType, selected_unit.stats.mov)
		if not path.is_empty() and path.size() < best_len:
			best_len = path.size()
			best = stand
	return best


# ============================================================
# 移动
# ============================================================
func _perform_move(u: Dictionary, target: Vector2i) -> void:
	mode = Mode.ANIMATING
	_clear_range_highlight()
	# 记录出发点：菜单期间按 ESC 取消移动时把单位送回这里。
	var from_pos: Vector2i = u.position
	# _pending_move_undo 由 battle.gd 维护（菜单确认/取消时读它），弹出菜单前先设置。
	_pending_move_undo = { &"unit": u, &"from": from_pos }
	var path := grid.find_path(u.position, target, u.moveType, u.stats.mov)
	if path.is_empty() or path.size() <= 1:
		battle_ui.open_unit_menu(u, target, from_pos)
		return
	var us: UnitSprite3D = _unit_sprites[u.id]
	Sfx.play_step(StringName(grid.tile_at(target.x, target.y).get(&"type", &"plain")))
	us.move_along_path(path.slice(1), func():
		grid.place_unit(u, target.x, target.y)
		u.hasMoved = true
		us.update_state()
		battle_ui.open_unit_menu(u, target, from_pos)
	)


func _perform_attack_from_current(u: Dictionary, target: Dictionary) -> void:
	_clear_range_highlight()
	
	_resolve_combat(u, target, func():
		selected_unit = {}

		mode = Mode.IDLE
		_commit_snapshot()
		_check_battle_end()
	)


# ============================================================
# 战斗演出
# ============================================================
func _resolve_combat(attacker: Dictionary, defender: Dictionary, on_done: Callable) -> void:
	await _resolve_combat_async(attacker, defender)
	if is_inside_tree() and on_done.is_valid():
		on_done.call()


## 唯一普攻结算入口：先落地 CombatSystem，再完整播放事件，最后统一刷新死亡/经验。
## TurnDirector 敌方/托管直接 await 本函数；手动路径经上方回调包装保持原状态机。
func _resolve_combat_async(attacker: Dictionary, defender: Dictionary) -> void:
	mode = Mode.ANIMATING
	print("[combat] %s → %s atk_hp=%d def_hp=%d" % [
		attacker.name, defender.name, attacker.hp, defender.hp])
	var atk_us: UnitSprite3D = _unit_sprites[attacker.id]
	var def_us: UnitSprite3D = _unit_sprites[defender.id]
	# 结算（execute+死亡标志+hasActed+经验）走共享 resolver；演出在结算后播放。
	var outcome := BattleActionResolver.resolve_attack(attacker, defender, grid, _drop_ctx)
	var result: Dictionary = outcome[&"combat"]
	var event: Dictionary = result.get(&"attack_event", {})
	var options := turn_director.get_action_anim_options(attacker.id)
	print("[combat-event] impacts=%d anim_speed=%.2f skip=%s" % [
		(event.get(&"impacts", []) as Array).size(),
		float(options.get(&"anim_speed", 1.0)),
		str(options.get(&"skip", false)),
	])
	if action_anim != null and not event.is_empty():
		var animation_speed := float(options.get(&"anim_speed", 1.0))
		var skipped := bool(options.get(&"skip", false))
		if not await _fx.prewarm_action_fx(event, event.get(&"impacts", []), skipped):
			return
		_set_unit_bars_visible(false)
		await _immersive_camera.begin(event, _unit_sprites, animation_speed, skipped)
		if not is_inside_tree():
			return
		await action_anim.play(
			event,
			animation_speed,
			skipped or _immersive_camera.consume_skip_request()
		)
		await _immersive_camera.end()
		if not is_inside_tree():
			return
	atk_us.update_state()
	def_us.update_state()
	# 死亡收尾（isDead 已由 resolver 置位，这里补 grid 移除 + 演出）
	for victim in outcome[&"deaths"]:
		_on_unit_death(victim)
	atk_us.update_state()
	# 升级薄演出：结算/死亡收尾后、on_done 返还控制与终局判定前，按 exp.levels 播放。
	await _present_level_up(attacker, outcome.get(&"exp", {}))


# ============================================================
# 战斗音效 / 演出特效（BattleSfx / BattleFx 模块；battle.gd 只留 impact 委托）
# ============================================================
## impact 呈现回调：受击音（BattleSfx.play_impact）+ 伤害数字/血条受击（BattleFx.spawn_damage_from_impact）。
func _on_impact_presented(impact: Dictionary) -> void:
	_sfx.play_impact(impact)
	_fx.spawn_damage_from_impact(impact)


# ============================================================
# 技能 / 物品 演出（统一 ActionAnim；物品保留自身短动画）
# ============================================================
## 技能先落地 SkillSystem，再播放其 attack_event；返回 true 告知 TurnDirector 已自行 await。
func _resolve_skill(caster: Dictionary, targets: Array, skill_id: StringName) -> bool:
	if targets.is_empty():
		caster.hasActed = true
		return true
	mode = Mode.ANIMATING
	var atk_us: UnitSprite3D = _unit_sprites.get(caster.id)
	# 结算（execute+死亡标志+hasActed+经验）走共享 resolver；演出在结算后播放。
	var outcome := BattleActionResolver.resolve_skill(caster, targets, skill_id, _drop_ctx)
	var result: Dictionary = outcome[&"skill"]
	var event: Dictionary = result.get(&"attack_event", {})
	var options := turn_director.get_action_anim_options(caster.id)
	print("[skill-event] skill=%s impacts=%d skip=%s" % [
		String(skill_id),
		(event.get(&"impacts", []) as Array).size(),
		str(options.get(&"skip", false)),
	])
	if action_anim != null and not event.is_empty():
		var animation_speed := float(options.get(&"anim_speed", 1.0))
		var skipped := bool(options.get(&"skip", false))
		if not await _fx.prewarm_action_fx(event, event.get(&"impacts", []), skipped):
			return true
		_set_unit_bars_visible(false)
		await _immersive_camera.begin(event, _unit_sprites, animation_speed, skipped)
		if not is_inside_tree():
			return true
		await action_anim.play(
			event,
			animation_speed,
			skipped or _immersive_camera.consume_skip_request()
		)
		await _immersive_camera.end()
		if not is_inside_tree():
			return true
	# 统一刷新施法者与全部目标（命中、未命中、治疗、buff 均由事件负责表现）。
	if atk_us != null:
		atk_us.update_state()
	for target_value in targets:
		var target: Dictionary = target_value
		var target_sprite: UnitSprite3D = _unit_sprites.get(target.id)
		if target_sprite != null:
			target_sprite.update_state()
	# 死亡收尾（isDead 已由 resolver 置位，这里补 grid 移除 + 演出）
	for victim in outcome[&"deaths"]:
		_on_unit_death(victim)
	# 升级薄演出：死亡收尾后、返还控制与终局判定前，按 exp.levels 播放。
	await _present_level_up(caster, outcome.get(&"exp", {}))
	mode = Mode.IDLE
	_check_battle_end()
	return true


## 物品演出。item_entry 为 {id, uses}。内部调 ItemSystem.execute。
func _resolve_item(user: Dictionary, targets: Array, item_entry: Dictionary) -> bool:
	if targets.is_empty() or item_entry.is_empty():
		user.hasActed = true
		return true
	mode = Mode.ANIMATING
	_set_unit_bars_visible(false)
	var us: UnitSprite3D = _unit_sprites.get(user.id)
	# 结算先行（execute+死亡标志+hasActed）走共享 resolver：伤害数值确定后才能预热对应 FX 变体。
	var outcome := BattleActionResolver.resolve_item(user, targets, item_entry, _drop_ctx)
	var result: Dictionary = outcome[&"item"]
	# 预热在抬升动画窗口内完成，投掷命中瞬间零冷启动。
	_fx.prewarm_item_damage_fx(result)
	# 简短使用动画：沿真实世界 Y 轴上抬 6 个美术像素。
	if us != null:
		var start: Vector3 = us.global_position
		var tween := create_tween()
		tween.tween_property(us, "global_position", start + Vector3(0, 6.0 / 32.0, 0), 0.12)
		tween.tween_property(us, "global_position", start, 0.12)
		await tween.finished
	# HP 变化飘字（治疗绿 / 伤害红）
	for h in result.get(&"hp_deltas", []):
		var t: Dictionary = h[&"unit"]
		var delta: int = int(h[&"delta"])
		if delta > 0:
			_fx.spawn_float_text(t, "+%d" % delta, Color(0.29, 0.87, 0.50))
		elif delta < 0:
			var hp_after := int(t.get(&"hp", 0))
			_fx.spawn_damage_fx(t, -delta, hp_after - delta, hp_after)
			if _unit_sprites.get(t.id) != null:
				_fx.shake_sprite(_unit_sprites[t.id])
	# MP 恢复飘字（蓝）
	for h in result.get(&"mp_deltas", []):
		var t: Dictionary = h[&"unit"]
		_fx.spawn_float_text(t, "+%d MP" % int(h[&"delta"]), Color(0.35, 0.6, 1.0))
	# buff 飘字
	for b in result.get(&"buffed", []):
		var t: Dictionary = b[&"unit"]
		_fx.spawn_float_text(t, String(b[&"desc"]), Color(0.98, 0.84, 0.30))
	# 刷新 sprite
	for h in result.get(&"hp_deltas", []):
		var t: Dictionary = h[&"unit"]
		if _unit_sprites.get(t.id) != null:
			(_unit_sprites[t.id] as UnitSprite3D).update_state()
	await get_tree().create_timer(0.4).timeout
	# 结算（execute+死亡标志+hasActed）走共享 resolver；投掷致死在演出后收尾。
	for victim in outcome[&"deaths"]:
		_on_unit_death(victim)
	# 物品演出结束：按当前 HP 恢复常驻血条。
	_set_unit_bars_visible(true)
	mode = Mode.IDLE
	_check_battle_end()
	return true


func _on_unit_death(u: Dictionary) -> void:
	var us: UnitSprite3D = _unit_sprites.get(u.id)
	grid.remove_unit(u)
	if us != null:
		_result_stage.play_death_fade(StringName(u[&"id"]), us)


# ============================================================
# 经验/升级
# ============================================================
## 经验/升级结算已迁入 BattleActionResolver.gain_exp（与 headless automation 共享单一事实源）。
## 这里保留薄包装：刷新立绘状态，供残留的动态调用兼容。
func _gain_exp(u: Dictionary, amount: int) -> Dictionary:
	var info: Dictionary = BattleActionResolver.gain_exp(u, amount)
	# gain_exp 顶层返回 {amount,gained,levels}；levels 在顶层而非 exp 子字典。
	if not (info.get(&"levels", []) as Array).is_empty():
		Sfx.play(&"ui_levelup")
	if _unit_sprites.has(u.id):
		(_unit_sprites[u.id] as UnitSprite3D).update_state()
	return info


## 升级薄演出入口（普攻/技能结算后统一走这里）：exp_info 为 resolver 返回的
## 顶层 exp 字典 {amount,gained,levels}；空 levels 不展示，options.skip（敌方/
## 托管跳过演出）只发音效不弹窗。await 到弹窗收尾，保证回合状态机不被卡死。
func _present_level_up(u: Dictionary, exp_info: Dictionary) -> void:
	if exp_info.is_empty():
		return
	var levels: Array = exp_info.get(&"levels", [])
	if levels.is_empty() or _level_up == null or not is_inside_tree():
		return
	var options := turn_director.get_action_anim_options(u.id)
	print("[levelup] unit=%s levels=%d skip=%s" % [
		String(u.get(&"name", u.id)), levels.size(), str(bool(options.get(&"skip", false)))])
	await _level_up.play(u, levels, options)


# ============================================================
# 玩家行动收尾（菜单UI在 battle_ui；这里只保留状态机收尾）
# ============================================================
## 玩家手动行动（攻击/技能/物品）结束后的统一收尾。
func _finish_player_action(_u: Dictionary) -> void:
	selected_unit = {}
	mode = Mode.IDLE
	_commit_snapshot()
	_check_battle_end()
	if turn.all_player_acted():
		await get_tree().create_timer(0.3).timeout
		turn.end_turn()


## 取消移动（移动完成后弹出菜单、按 ESC 时调用）：
## 关菜单 → 单位送回出发点 → 复位 hasMoved → 重新进入 UNIT_SELECTED 并重算移动/攻击范围。
## 对「没真正移动」（from == 当前位置）的情况只关菜单、回到选中态即可。
func _cancel_move() -> void:
	battle_ui.close_menu()
	if _pending_move_undo.is_empty():
		return
	var u: Dictionary = _pending_move_undo[&"unit"]
	var from: Vector2i = _pending_move_undo[&"from"]
	_pending_move_undo.clear()
	if u.is_empty():
		return
	# 仅当确实发生了位移时才回送；原地（path 为空）直接回到选中态。
	if u.position != from:
		grid.place_unit(u, from.x, from.y)
		u.hasMoved = false
		if _unit_sprites.has(u.id):
			(_unit_sprites[u.id] as UnitSprite3D).update_state()
	# 重新选中：重算移动/攻击范围、高亮、光标归位。
	_select_unit(u)


# ============================================================
# 托管开关（薄封装：实际状态/编排在 turn_director）
# ============================================================
## host_btn 按下：交给 turn_director.toggle_hosting。can_start_now 由当前状态判断。
func _toggle_hosting() -> void:
	turn_director.toggle_hosting(turn.phase == &"player" and mode == Mode.IDLE)


# ============================================================
# 托管偏好面板（BattlePrefPanel 模块；battle.gd 只留委托）
# ============================================================
## host_btn 旁的偏好按钮入口：面板构建/事件读写在 BattlePrefPanel.open。
func _open_pref_panel() -> void:
	_pref_panel.open()


# ============================================================
# 胜负
# ============================================================
func _check_battle_end(p_end_of_round: bool = false) -> void:
	if _battle_ended:
		return  # 已结束，避免重复结算演出
	# 敌存活集合 = chapter.enemyUnits（含已刷入增援）+ 未到点波次（防提前判胜）
	var enemies: Array = (chapter.enemyUnits as Array).duplicate()
	enemies.append_array(ReinforcementSpawner.pending_units(chapter))
	var ctx := {}
	if p_end_of_round:
		# 完整回合结束：defend_turns / seize 在此判定（rout 随时判定，兼容旧调用）
		ctx["end_of_round"] = true
		ctx["turns_survived"] = turn.turn_number
		ctx["seize_held"] = _seize_cell_held()
	var result := turn.check_victory(enemies, ctx)
	if result != &"win" and result != &"lose":
		return
	if result == &"win":
		print("[battle] 胜利！回合数=%d 存活玩家=%d" % [turn.turn_number, _alive_count(&"player")])
	else:
		print("[battle] 败北 回合数=%d 存活敌方=%d" % [turn.turn_number, _alive_count(&"enemy")])

	# 置位结束标志，阻止 turn_director 继续推进回合；先演算，后退出。
	_battle_ended = true
	mode = Mode.ANIMATING
	_restore_result_visuals()
	_commit_snapshot(result)  # 终局记录先行落盘：结算演出中断也不丢胜负
	_present_result(result)


## seize 条件：目标格当前是否有存活玩家单位（回合结束时由 _check_battle_end 查询）。
func _seize_cell_held() -> bool:
	var v: Dictionary = turn.victory
	if String(v.get(&"type", &"rout")) != "seize":
		return false
	var cell: Vector2i = v.get(&"cell", Vector2i(-1, -1))
	for u in grid.units.values():
		if u.faction == &"player" and not u.isDead and u.position == cell:
			return true
	return false


## 结算演出（_check_battle_end 与恢复局共用）。
func _present_result(result: StringName) -> void:
	_campaign_result = result
	if not _campaign_token.is_empty():
		_settle_campaign(result)
	var data := {
		# campaign 模式严格只信 receipt（战场掉落字段名固定为 loot，固定通关
		# 奖励 items/items_awarded 由 Hub 收据展示，两处分行不合并）；W2 落地
		# 前 receipt 无 loot 键 → 空数组 → 演出省略掉落行，不虚构奖励。
		# 非 campaign（世界战斗）保持 chapter 顶层 loot 原数据来源不变。
		"loot": (
			_campaign_receipt.get("loot", [])
			if not _campaign_token.is_empty()
			else chapter.get("loot", [])
		),
		"exp": int(chapter.get("exp", 0)),
		"gold": int(_campaign_receipt.get("gold", chapter.get("gold", 0))),
		"chapter_end": bool(chapter.get("chapterEnd", false)),
		"chapter_title": String(chapter.get("title", "")),
		"return_hint": "返回营地" if not _campaign_token.is_empty() else "返回世界",
		# 升级差分随成功 receipt 发布；非 campaign receipt 为空 → 空数组，
		# 演出层按空省略成长分节，不虚构成长。
		"level_ups": _campaign_receipt.get("level_ups", []),
	}
	var survivors: Array = _units_by_life(
		&"player" if result == &"win" else &"enemy", true
	)
	var defeated: Array = _units_by_life(
		&"enemy" if result == &"win" else &"player", false
	)
	battle_ui.result_finished.connect(_on_result_presentation_finished, CONNECT_ONE_SHOT)
	battle_ui.play_result(result, data, survivors, defeated)


func _units_by_life(faction: StringName, alive: bool) -> Array:
	var units: Array = []
	# 死亡单位已从 grid.units 移除；结果名单必须遍历 chapter 的权威单位数组。
	for unit in chapter.playerUnits + chapter.enemyUnits:
		if unit.faction == faction and (not unit.isDead) == alive:
			units.append(unit)
	return units


# ============================================================
# 结算演出视觉 / 演出音（BattleResultStage / BattleSfx 模块；battle.gd 只留委托）
# ============================================================
func _on_presentation_cheer(unit: Dictionary) -> void:
	_result_stage.cheer(unit)


func _on_presentation_collapse(unit: Dictionary) -> void:
	_result_stage.collapse(unit)


## 跳过/退出只结束显示时间轴；恢复姿态与透明度，绝不写 HP、isDead 或逻辑格。
func _restore_result_visuals() -> void:
	_result_stage.restore()


func _on_presentation_sound(cue: StringName) -> void:
	# 探针观测点（纯 meta，不影响真实播放链）：按 cue 计数 + 记录最近 cue。
	var counts: Dictionary = get_meta(&"presentation_sfx_counts", {})
	counts[cue] = int(counts.get(cue, 0)) + 1
	set_meta(&"presentation_sfx_counts", counts)
	set_meta(&"presentation_sfx_last", cue)
	_sfx.on_presentation_sound(cue)


func _settle_campaign(result: StringName) -> bool:
	if not _campaign_receipt.is_empty():
		return true
	var receipt: Dictionary = CampaignBattleBridgeScript.settle(
		get_tree(), _campaign_token, result, chapter)
	if not bool(receipt.get("ok", false)):
		battle_ui.show_toast("冒险保存失败：%s。请点击退出战斗重试。" % String(receipt.get("error", "")))
		return false
	_campaign_receipt = receipt
	print("[campaign] settled result=%s token=%s" % [String(result), _campaign_token])
	return true


func _on_result_presentation_finished(result: StringName, skipped: bool) -> void:
	_restore_result_visuals()
	if not _campaign_token.is_empty():
		if not _settle_campaign(result):
			return
		SceneArgs.battle_args = {}
	print("[battle] ResultFinished result=%s skipped=%s" % [String(result), str(skipped)])
	if _b1_mode:
		# B1 就地模式：发信号让 main.gd 接管 _exit_battle（不切场景）
		battle_finished.emit(result)
	else:
		# B2 切场景模式：结算演出完成后才切回 return_to_scene
		var tree := get_tree()
		if tree != null:
			tree.change_scene_to_file(return_to_scene)


## 统计存活单位数（按 faction）。L1 埋点辅助用。
func _alive_count(faction: StringName) -> int:
	var n := 0
	for u in grid.units.values():
		if not u.isDead and u.faction == faction:
			n += 1
	return n


# ============================================================
# 切换场景入口
# ============================================================
func _exit_tree() -> void:
	if is_instance_valid(_immersive_camera):
		_immersive_camera.cancel()
	# 升级薄演出：作废在途弹窗时间轴，避免退出战斗后残留 finished/协程。
	if is_instance_valid(_level_up):
		_level_up.cancel()
	# 防御：加载遮罩只在战斗演出预热窗口内使用，任何退出路径（胜/负/切场景/异常）都不残留。
	LoadingScreen.hide_loading()
	# 防御：退出战斗（含 B1 就地模式）时恢复全部常驻血条。
	_set_unit_bars_visible(true)
	_restore_result_visuals()
	if _save != null:
		_save.flush()  # 防半途退出：用最近一次完整快照补落盘（幂等）
	if _presentation_audio != null:
		_presentation_audio.stop()
	# 镜头踢击复位由 BattleCameraKick._exit_tree 自理（children 先于父退出）。


func setup_battle(p_chapter: Dictionary, p_return_to: String = "res://main.tscn") -> void:
	chapter = p_chapter
	return_to_scene = p_return_to
	block_titles = p_chapter.get("blockTitles", [])
