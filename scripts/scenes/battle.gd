## scenes/battle.gd — 核心战场（场景编排器）
##
## 完整回合制循环：选单位→蓝格移动/红格攻击→移动→菜单(攻击/技能/物品/等待)→战斗演出→敌方AI回合→胜负。
## 2D 等距（pixel_world 融合版）：IsoBoard(Node2D) + UnitSprite3D(Node2D)；UI 用 CanvasLayer。
##
## 本文件只保留场景编排核心：生命周期/状态机/输入/选择/移动/战斗演出(伤害/死亡/经验)/胜负。
## 已按职责拆出三个助手模块（scripts/battle/，均通过 setup()+Callable 注入，不持有本场景引用）：
##   - RangeOverlay (Node2D)    地形回退铺底 + 移动/攻击范围菱形描边 + 光标金色呼吸框
##   - TurnDirector (Node)      敌方 AI 回合 + 玩家方托管编排 + 偏好数据
##   - BattleUI    (CanvasLayer) HUD + 单位菜单/选择器/预览面板/结果横幅

extends Node2D

const BattlefieldRendererScript = preload("res://scripts/iso/battlefield_renderer.gd")
const AIDifficulty = preload("res://scripts/systems/ai_difficulty.gd")
const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
const SunlightSystemScript = preload("res://scripts/sunlight_system.gd")
const EncounterTransitionScript = preload("res://scripts/battle/encounter_transition.gd")
const BattlePresentationScript = preload("res://scripts/battle/battle_presentation.gd")
const ActionAnimScript = preload("res://scripts/battle/action_anim.gd")
const BattleActionResolver = preload("res://scripts/battle/battle_action_resolver.gd")

var action_anim: Node = null
var _action_camera_kick_tween: Tween = null
var _action_camera_kick_offset := Vector3.ZERO
var _action_camera_kick_active := false
var _result_visual_states: Dictionary = {}
var _unit_visual_tweens: Dictionary = {}
var _presentation_audio: AudioStreamPlayer = null
var _presentation_sound_cache: Dictionary = {}

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
# 偏好配置面板（默认 hidden，_open_pref_panel 动态填充；数据在 turn_director）
var pref_panel: Control = null

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

# ---- 战旗持久化（GameSession 自动存档）----
# save_identity 非空 → 本场战斗在完整行动边界自动提交；save_state 非空 → 恢复进度。
# _last_committed 缓存最近一次完整快照：演出中途退出时用它补落盘（防半行动丢失）。
var _save_identity: String = ""
var _save_state: Dictionary = {}
var _last_committed: Dictionary = {}


func _ready() -> void:
	# 从 SceneArgs 读战斗参数（由 main.gd._enter_battle 设置）
	if SceneArgs.battle_args.has("chapter"):
		chapter = SceneArgs.battle_args["chapter"]
		return_to_scene = SceneArgs.battle_args.get("return_to", "res://main.tscn")
		block_titles = chapter.get("blockTitles", [])
	# B1 就地模式：main.gd 通过 SceneArgs.battle_args["world"] 注入自身引用
	_world = SceneArgs.battle_args.get("world", null)
	_b1_mode = _world != null
	# 战旗记录参数：save_identity 非空开启自动存档；save_state 非空表示恢复进度
	_save_identity = String(SceneArgs.battle_args.get("save_identity", ""))
	_save_state = SceneArgs.battle_args.get("save_state", {})
	var _save_notice := String(SceneArgs.battle_args.get("save_notice", ""))
	if _b1_mode:
		_world_origin = chapter.get("world_origin", Vector2i.ZERO)
	# 1. 网格 + 单位 + 回合（与模式无关）；死亡单位只在恢复局出现——不放入 grid
	grid = GridSystem.new(chapter.width, chapter.height, chapter.map)
	for u in chapter.playerUnits + chapter.enemyUnits:
		if not u.isDead:
			grid.place_unit(u, u.position.x, u.position.y)
	turn = TurnManager.new(chapter.playerUnits + chapter.enemyUnits)
	add_child(turn)
	# 1b. 回合编排器（敌方 AI + 玩家方托管）
	turn_director = TurnDirector.new()
	turn_director.setup(grid, turn, chapter, _unit_sprites)
	# AI 难度档从全局设置注入（非法/缺失由 normalize 回 normal）
	turn_director.enemy_difficulty = AIDifficulty.normalize(Settings.enemy_ai_difficulty)
	turn_director.host_difficulty = AIDifficulty.normalize(Settings.host_ai_difficulty)
	_inject_turn_director_callables()
	add_child(turn_director)
	if SceneArgs.battle_args.get("hosting", false):
		turn_director.set_hosting(true)
	# 2. 渲染层（B1/B2 分支）
	if _b1_mode:
		_setup_b1_render()
	else:
		_setup_b2_render()
	# 3. UI 层（屏幕空间，两种模式共用）
	_build_ui()
	turn_director.update_host_btn_text()
	# 有存档身份的 B2 战斗提供「退出战斗」按钮（B1 由 main.gd 自己接管）
	if not _save_identity.is_empty() and not _b1_mode:
		battle_ui.set_exit_callback(_on_exit_to_list)
	if _save_notice != "":
		battle_ui.show_toast(_save_notice)
	# 4. 单位
	for u in grid.units.values():
		_spawn_unit_sprite(u)
	action_anim = ActionAnimScript.new()
	action_anim.name = "ActionAnim"
	add_child(action_anim)
	action_anim.setup(
		_unit_sprites,
		_world._cam if _b1_mode else board.camera,
		_spawn_action_float_text
	)
	action_anim.phase_started.connect(_on_action_phase_started)
	action_anim.finished.connect(_on_action_anim_finished)
	await get_tree().process_frame
	_debug_print_unit_alignment()
	# 5. 输入 + 回合
	turn.phase_player.connect(_on_player_phase)
	turn.phase_enemy.connect(_on_enemy_phase)
	if not _b1_mode:
		# B2 才需要 viewport resize 重居中（B1 由 main.gd 管相机）
		get_viewport().size_changed.connect(_on_viewport_resized)

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
	if not _save_state.is_empty():
		# 恢复进度：不复位列标志/不重跑开局 tick，直接进保存时的阶段
		var resume: Dictionary = _save_state
		_save_state = {}
		_apply_resume_state(resume)
	else:
		# 首个玩家回合必须在 battle_ready 之前启动：battle_ready 语义 = 完全就绪
		# （含首回合复位/冷却/buff tick）。监听方恢复后会立即行动结算，
		# 若 start_player_phase 仍在其后执行，复位 hasActed 会覆盖已落地的结算置位。
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


## ActionAnim 仍负责缩放；位置推近走 main/IsoCamera 认可的附加位移，避免被每帧取景覆盖。
func _process(_delta: float) -> void:
	if _action_camera_kick_active:
		_apply_action_camera_kick()


func _on_action_phase_started(phase: StringName, event: Dictionary) -> void:
	if phase != &"strike" and phase != &"return":
		return
	var target_offset := Vector3.ZERO
	if phase == &"strike":
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return
		var attacker_id := StringName(event.get(&"attacker_id", &""))
		var target_id := StringName(event.get(&"target_id", &""))
		var impacts: Array = event.get(&"impacts", [])
		if target_id == &"" and not impacts.is_empty():
			target_id = StringName((impacts[0] as Dictionary).get(&"target_id", &""))
		var attacker: UnitSprite3D = _unit_sprites.get(attacker_id)
		var target: UnitSprite3D = _unit_sprites.get(target_id)
		var focus := Vector3.ZERO
		if attacker != null and target != null:
			focus = (attacker.global_position + target.global_position) * 0.5
		elif attacker != null:
			focus = attacker.global_position
		elif target != null:
			focus = target.global_position
		else:
			return
		target_offset = (focus - camera.global_position) * 0.08
	if _action_camera_kick_tween != null and _action_camera_kick_tween.is_valid():
		_action_camera_kick_tween.kill()
	_action_camera_kick_active = true
	_action_camera_kick_tween = create_tween()
	_action_camera_kick_tween.tween_property(
		self, "_action_camera_kick_offset", target_offset, 0.16 if phase == &"strike" else 0.14
	)


func _on_action_anim_finished(_event: Dictionary, _skipped: bool) -> void:
	if _action_camera_kick_tween != null and _action_camera_kick_tween.is_valid():
		_action_camera_kick_tween.kill()
	_action_camera_kick_offset = Vector3.ZERO
	_apply_action_camera_kick()
	_action_camera_kick_active = false


func _apply_action_camera_kick() -> void:
	if _b1_mode and is_instance_valid(_world):
		_world.set_battle_camera_kick(_action_camera_kick_offset)
	elif is_instance_valid(board) and board.camera != null:
		board.camera.presentation_offset = _action_camera_kick_offset


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
	renderer.set_block_layout(chapter.get("block_layout", {}))
	renderer.setup(grid)
	# 范围/光标标记走注入模式：坐标/排序/高度由 renderer 提供（同 B1 的注入方式）
	range_overlay = RangeOverlay.new()
	add_child(range_overlay)
	range_overlay.setup_world(
		board, grid, block_titles,
		Callable(self, "_b2_cell_to_screen"),
		Callable(renderer, "sort_for"),
		Callable(renderer, "stand_level")
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
	battle_ui.level_fn = Callable(self, "_b1_cell_level") if _b1_mode else Callable(renderer, "stand_level")
	add_child(battle_ui)
	_presentation_audio = AudioStreamPlayer.new()
	_presentation_audio.name = "PresentationAudio"
	add_child(_presentation_audio)
	battle_ui.cheer_requested.connect(_on_presentation_cheer)
	battle_ui.collapse_requested.connect(_on_presentation_collapse)
	battle_ui.presentation_sound_requested.connect(_on_presentation_sound)
	_inject_battle_ui_callables()
	battle_ui.build(_on_end_turn, _toggle_hosting, _open_pref_panel)
	# 偏好面板容器（数据在 turn_director，所以面板由 battle.gd 持有）
	pref_panel = battle_ui.get_pref_panel_container()


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
	battle_ui.set_phase_text("第 %d 轮 · 敌方行动" % turn_num, Color(0.97, 0.44, 0.44))
	mode = Mode.ENEMY_TURN
	_clear_range_highlight()
	# TurnManager 已在信号前复位敌方行动状态；立即恢复存活单位亮度与顶部状态。
	_refresh_all_units()
	_commit_snapshot()

	turn_director.start_enemy_phase()


# ============================================================
# 战旗持久化（完整行动边界提交；演出中退出回退上一完整快照）
# ============================================================
## 收集恢复所需的运行态（回合/阶段/托管/偏好/胜负）。
func _capture_battle_state(result: StringName = &"") -> Dictionary:
	return {
		"turn_number": int(turn.turn_number),
		"phase": turn.phase,
		"hosting": turn_director.is_hosting(),
		"prefs": turn_director.get_prefs().duplicate(true),
		"result": result,
	}


## 在完整行动边界提交（回合开始 / 行动收尾 / 终局）。result 非空表示终局记录。
func _commit_snapshot(result: StringName = &"") -> void:
	if _save_identity.is_empty():
		return
	_last_committed = {
		"chapter": chapter.duplicate(true),
		"state": _capture_battle_state(result),
	}
	_flush_save()


## 落盘最近一次完整快照（幂等；_exit_tree 用它补防半途退出）。
func _flush_save() -> void:
	if _save_identity.is_empty() or _last_committed.is_empty():
		return
	var res: Dictionary = GameSession.commit(_last_committed["chapter"], _last_committed["state"])
	if not res.get("ok", false):
		battle_ui.show_toast("保存失败：%s" % String(res.get("error", "")))


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
		turn_director.start_enemy_phase()


## 「退出战斗」按钮：回到 return_to_scene；落盘由 _exit_tree 的 flush 兜底。
func _on_exit_to_list() -> void:
	if mode == Mode.ANIMATING and not _battle_ended:
		return  # 行动演出中不允许退出（防半行动快照）
	if mode == Mode.ENEMY_TURN:
		return  # 敌方回合推进中不允许退出
	battle_ui.close_menu()
	var tree := get_tree()
	if tree != null:
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
		# B2 切场景模式：挂 board 下，注入 renderer.stand_level 支持柱顶站立
		board.add_child(us)
		us.setup(u, board, Callable(renderer, "stand_level"))
	_unit_sprites[u.id] = us


func _debug_print_unit_alignment() -> void:
	# 2D 版简化：只打印 cell 与单位屏幕坐标
	for u in grid.units.values():
		var us: UnitSprite3D = _unit_sprites.get(u.id)
		if us == null:
			continue
		var pos: Vector2i = u.position
		# B2 等距渲染下单位站在地形高度上（renderer.stand_level）；B1 就地模式无 renderer，退回 0 层
		var lvl := 0
		if renderer != null:
			lvl = renderer.stand_level(pos.x, pos.y)
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


## 手势 / 空格 / 滚轮：用 _input（GUI 处理前）确保一定能收到。
## 战场 UI（结束回合按钮 / 菜单面板）命中时让出缩放手势，避免误触。
## B1 就地模式下相机由 main.gd 管，这里全部跳过（避免 board 为 null 崩溃）。
func _input(event: InputEvent) -> void:
	# B2 遭遇转场期间锁死平移、缩放与旋转。
	if mode == Mode.ANIMATING:
		if battle_ui != null and battle_ui.is_presentation_active() and _is_presentation_skip_event(event):
			battle_ui.skip_presentation()
		elif action_anim != null and action_anim.is_playing() and _is_presentation_skip_event(event):
			action_anim.skip()
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
		elif event is InputEventMagnifyGesture:
			var g := event as InputEventMagnifyGesture
			if battle_ui.is_over_ui(g.position):
				return
			var factor := clampf(1.0 / g.factor, 0.5, 2.0)
			board.zoom_by(factor, g.position, get_viewport().get_visible_rect().size)
			get_viewport().set_input_as_handled()
			return
		elif event is InputEventPanGesture:
			var g := event as InputEventPanGesture
			if battle_ui.is_over_ui(g.position):
				return
			if absf(g.delta.y) > absf(g.delta.x):
				var factor := clampf(1.0 + g.delta.y * 0.08, 0.75, 1.25)
				board.zoom_by(factor, g.position, get_viewport().get_visible_rect().size)
				get_viewport().set_input_as_handled()
			return


func _unhandled_input(event: InputEvent) -> void:
	# 遭遇演出期间禁用移动/菜单等全部战斗输入（B1 也由 main.gd 直接调用此函数）。
	if mode == Mode.ANIMATING:
		if battle_ui != null and battle_ui.is_presentation_active() and _is_presentation_skip_event(event):
			battle_ui.skip_presentation()
		elif action_anim != null and action_anim.is_playing() and _is_presentation_skip_event(event):
			action_anim.skip()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed:
			match k.keycode:
				KEY_ESCAPE: _on_cancel()
				KEY_ENTER, KEY_Z: _on_confirm()
				KEY_E: _on_end_turn()
				KEY_Q:
					if not _b1_mode:
						board.camera.rotate_step(-1)
				KEY_X:
					if not _b1_mode:
						board.camera.rotate_step(1)
				KEY_R:
					if not _b1_mode:
						board.camera.reset_rotation()
				KEY_UP: _move_cursor(0, -1)
				KEY_DOWN: _move_cursor(0, 1)
				KEY_LEFT: _move_cursor(-1, 0)
				KEY_RIGHT: _move_cursor(1, 0)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed and not _b1_mode:
			board.zoom_by(0.9, mb.position, get_viewport().get_visible_rect().size)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed and not _b1_mode:
			board.zoom_by(1.1, mb.position, get_viewport().get_visible_rect().size)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
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
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# 右键：查看单位详情面板（任意阵营，不干扰左键的选中/攻击）
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

		elif mb.button_index == MOUSE_BUTTON_MIDDLE and not _b1_mode:
			if mb.pressed:
				_panning = true
				_pan_last = mb.position
			else:
				_panning = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning and not _b1_mode:
			if mm.ctrl_pressed:
				board.camera.drag_by(Vector2(mm.position.x - _pan_last.x, 0.0))
			else:
				board.pan(mm.position.x - _pan_last.x, mm.position.y - _pan_last.y)
			_pan_last = mm.position
			if mm.relative.length() > 3:
				_dragged = true
		elif not _panning:
			# hover 移动光标（B1 用 main.gd.screen_to_cell，B2 用 board.pick_cell）
			if not turn_director.is_hosting() and mode != Mode.ENEMY_TURN and mode != Mode.ANIMATING \
					and not battle_ui.has_open_menu() and not battle_ui.is_over_ui(mm.position):
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
	var outcome := BattleActionResolver.resolve_attack(attacker, defender, grid)
	var result: Dictionary = outcome[&"combat"]
	var event: Dictionary = result.get(&"attack_event", {})
	var options := turn_director.get_action_anim_options(attacker.id)
	print("[combat-event] impacts=%d anim_speed=%.2f skip=%s" % [
		(event.get(&"impacts", []) as Array).size(),
		float(options.get(&"anim_speed", 1.0)),
		str(options.get(&"skip", false)),
	])
	if action_anim != null and not event.is_empty():
		await action_anim.play(
			event,
			float(options.get(&"anim_speed", 1.0)),
			bool(options.get(&"skip", false))
		)
	atk_us.update_state()
	def_us.update_state()
	# 死亡收尾（isDead 已由 resolver 置位，这里补 grid 移除 + 演出）
	for victim in outcome[&"deaths"]:
		_on_unit_death(victim)
	atk_us.update_state()


## ActionAnim 每个 impact 只回调一次，按权威单位 id 取当前格位，避免重复订阅飘字信号。
func _spawn_action_float_text(unit_id: StringName, text: String, color: Color, font_size: int) -> void:
	var unit: Dictionary = grid.units.get(unit_id, {})
	if unit.is_empty():
		return
	_spawn_float_text(unit, text, color, font_size)


## 通用飘字（ActionAnim/物品用：治疗绿、伤害红、buff 黄、回 MP 蓝）。
func _spawn_float_text(u: Dictionary, text: String, color: Color, font_size: int = 18) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	# 单位脚点由当前 Camera3D 投影到屏幕，再抬升 50px。
	var screen: Vector2
	if _b1_mode:
		var world_cell: Vector2i = _world_origin + u.position
		var lvl: int = _world.cell_stand_level(world_cell)
		screen = _world._grid_to_screen(world_cell, float(lvl))
	else:
		var lvl: int = renderer.stand_level(u.position.x, u.position.y) if renderer != null else 0
		screen = board.cell_to_screen(u.position.x, u.position.y, float(lvl))
	lbl.position = screen + Vector2(0, -50) - Vector2(20, 30)
	battle_ui.get_float_text_container().add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 30, 0.7)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.7)
	tw.tween_callback(lbl.queue_free)


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
	var outcome := BattleActionResolver.resolve_skill(caster, targets, skill_id)
	var result: Dictionary = outcome[&"skill"]
	var event: Dictionary = result.get(&"attack_event", {})
	var options := turn_director.get_action_anim_options(caster.id)
	print("[skill-event] skill=%s impacts=%d skip=%s" % [
		String(skill_id),
		(event.get(&"impacts", []) as Array).size(),
		str(options.get(&"skip", false)),
	])
	if action_anim != null and not event.is_empty():
		await action_anim.play(
			event,
			float(options.get(&"anim_speed", 1.0)),
			bool(options.get(&"skip", false))
		)
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
	mode = Mode.IDLE
	_check_battle_end()
	return true


## 物品演出。item_entry 为 {id, uses}。内部调 ItemSystem.execute。
func _resolve_item(user: Dictionary, targets: Array, item_entry: Dictionary) -> bool:
	if targets.is_empty() or item_entry.is_empty():
		user.hasActed = true
		return true
	mode = Mode.ANIMATING
	var us: UnitSprite3D = _unit_sprites.get(user.id)
	# 简短使用动画：沿真实世界 Y 轴上抬 6 个美术像素。
	if us != null:
		var start: Vector3 = us.global_position
		var tween := create_tween()
		tween.tween_property(us, "global_position", start + Vector3(0, 6.0 / 32.0, 0), 0.12)
		tween.tween_property(us, "global_position", start, 0.12)
		await tween.finished
	# 结算（execute+死亡标志+hasActed）走共享 resolver。
	var outcome := BattleActionResolver.resolve_item(user, targets, item_entry)
	var result: Dictionary = outcome[&"item"]
	# HP 变化飘字（治疗绿 / 伤害红）
	for h in result.get(&"hp_deltas", []):
		var t: Dictionary = h[&"unit"]
		var delta: int = int(h[&"delta"])
		if delta > 0:
			_spawn_float_text(t, "+%d" % delta, Color(0.29, 0.87, 0.50))
		elif delta < 0:
			_spawn_float_text(t, "%d" % delta, Color(0.97, 0.44, 0.44))
			if _unit_sprites.get(t.id) != null:
				_shake(_unit_sprites[t.id])
	# MP 恢复飘字（蓝）
	for h in result.get(&"mp_deltas", []):
		var t: Dictionary = h[&"unit"]
		_spawn_float_text(t, "+%d MP" % int(h[&"delta"]), Color(0.35, 0.6, 1.0))
	# buff 飘字
	for b in result.get(&"buffed", []):
		var t: Dictionary = b[&"unit"]
		_spawn_float_text(t, String(b[&"desc"]), Color(0.98, 0.84, 0.30))
	# 刷新 sprite
	for h in result.get(&"hp_deltas", []):
		var t: Dictionary = h[&"unit"]
		if _unit_sprites.get(t.id) != null:
			(_unit_sprites[t.id] as UnitSprite3D).update_state()
	await get_tree().create_timer(0.4).timeout
	# 结算（execute+死亡标志+hasActed）走共享 resolver；投掷致死在演出后收尾。
	for victim in outcome[&"deaths"]:
		_on_unit_death(victim)
	mode = Mode.IDLE
	_check_battle_end()
	return true


func _shake(us: Node3D) -> void:
	# 在相机右方向水平抖动 4 个美术像素。
	var orig: Vector3 = us.global_position
	var camera := get_viewport().get_camera_3d()
	var right := camera.global_basis.x if camera != null else Vector3.RIGHT
	var tw := create_tween()
	for i in range(4):
		tw.tween_property(us, "global_position", orig + right * (4.0 / 32.0) * (1.0 if i % 2 == 0 else -1.0), 0.04)
	tw.tween_property(us, "global_position", orig, 0.04)


func _on_unit_death(u: Dictionary) -> void:
	var us: UnitSprite3D = _unit_sprites.get(u.id)
	grid.remove_unit(u)
	if us != null:
		var tw := create_tween()
		_track_unit_visual_tween(StringName(u[&"id"]), tw)
		# UnitSprite3D 是 Node2D（2D 版），用 fade_alpha 驱动子 CanvasItem alpha 淡出
		tw.tween_method(us.fade_alpha, 1.0, 0.0, 0.4)
		tw.parallel().tween_property(us, "scale", us.scale * 1.5, 0.4)
		tw.tween_callback(func(): us.visible = false)


# ============================================================
# 经验/升级
# ============================================================
## 经验/升级结算已迁入 BattleActionResolver.gain_exp（与 headless automation 共享单一事实源）。
## 这里保留薄包装：刷新立绘状态，供残留的动态调用兼容。
func _gain_exp(u: Dictionary, amount: int) -> Dictionary:
	var info: Dictionary = BattleActionResolver.gain_exp(u, amount)
	if _unit_sprites.has(u.id):
		(_unit_sprites[u.id] as UnitSprite3D).update_state()
	return info


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


func _make_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.88)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(4)
	return sb


# ============================================================
# 托管开关（薄封装：实际状态/编排在 turn_director）
# ============================================================
## host_btn 按下：交给 turn_director.toggle_hosting。can_start_now 由当前状态判断。
func _toggle_hosting() -> void:
	turn_director.toggle_hosting(turn.phase == &"player" and mode == Mode.IDLE)


# ============================================================
# 托管偏好面板（每单位配：优先目标 + 策略）
# ============================================================
## 打开偏好面板：动态拉取当前存活敌方单位填充优先目标下拉，列出所有 player 单位。
func _open_pref_panel() -> void:
	# 清旧内容
	for c in pref_panel.get_children():
		c.queue_free()
	await get_tree().process_frame

	# 收集 player 单位（含 name/class）和存活敌方单位（优先目标候选）
	var player_units: Array = []
	var enemy_units: Array = []
	for u in grid.units.values():
		if u.isDead:
			continue
		if u.faction == &"player":
			player_units.append(u)
		else:
			enemy_units.append(u)

	# 居中面板
	var viewport_size := get_viewport().get_visible_rect().size
	var panel := Panel.new()
	panel.size = Vector2(440, 60 + player_units.size() * 34)
	panel.position = (viewport_size - panel.size) / 2.0
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	pref_panel.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 10; vbox.offset_top = 8; vbox.offset_right = -10; vbox.offset_bottom = -8
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "托管偏好（仅本场战斗有效）"
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 0)
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	# 策略下拉选项
	var strat_ids: Array = []
	var strat_labels: Array = []
	for opt in PlayerAI.STRATEGY_OPTIONS:
		strat_ids.append(opt[&"id"])
		strat_labels.append(String(opt[&"label"]))

	for u in player_units:
		var row := HBoxContainer.new()
		list.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = "%s [%s]" % [String(u.name), String(ProfessionData.profession_name(u.classId))]
		name_lbl.custom_minimum_size = Vector2(150, 0)
		row.add_child(name_lbl)

		# 优先目标下拉
		var target_opt := OptionButton.new()
		target_opt.add_item("（无，按策略）", 0)
		var cur_pref: Dictionary = turn_director.get_pref(u.id)
		var cur_priority = cur_pref.get(&"priorityTargetId", "")
		var sel_idx := 0
		for i in range(enemy_units.size()):
			var e: Dictionary = enemy_units[i]
			target_opt.add_item("%s [%s]" % [String(e.name), String(ProfessionData.profession_name(e.classId))], i + 1)
			if cur_priority != "" and cur_priority == e.id:
				sel_idx = i + 1
		target_opt.select(sel_idx)
		target_opt.custom_minimum_size = Vector2(150, 0)
		target_opt.item_selected.connect(_on_pref_target_changed.bind(u.id, target_opt, enemy_units))
		row.add_child(target_opt)

		# 策略下拉
		var strat_opt := OptionButton.new()
		for i in range(strat_ids.size()):
			strat_opt.add_item(strat_labels[i], i)
		var cur_strat = cur_pref.get(&"strategy", PlayerAI.STRATEGY_AUTO)
		var strat_sel := 0
		for i in range(strat_ids.size()):
			if strat_ids[i] == cur_strat:
				strat_sel = i
				break
		strat_opt.select(strat_sel)
		strat_opt.custom_minimum_size = Vector2(120, 0)
		strat_opt.item_selected.connect(_on_pref_strategy_changed.bind(u.id, strat_opt, strat_ids))
		row.add_child(strat_opt)

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(_close_pref_panel)
	vbox.add_child(close_btn)

	pref_panel.visible = true


func _on_pref_target_changed(unit_id, opt: OptionButton, enemy_units: Array) -> void:
	var idx := opt.get_selected_id()
	var priority_id = ""
	if idx >= 1 and idx <= enemy_units.size():
		priority_id = enemy_units[idx - 1].id
	turn_director.set_pref(unit_id, &"priorityTargetId", priority_id)


func _on_pref_strategy_changed(unit_id, opt: OptionButton, strat_ids: Array) -> void:
	var idx := opt.get_selected_id()
	turn_director.set_pref(unit_id, &"strategy", strat_ids[idx])


func _close_pref_panel() -> void:
	pref_panel.visible = false
	for c in pref_panel.get_children():
		c.queue_free()


# ============================================================
# 胜负
# ============================================================
func _check_battle_end() -> void:
	if _battle_ended:
		return  # 已结束，避免重复结算演出
	var enemies: Array = chapter.enemyUnits
	var result := turn.check_victory(enemies)
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


## 结算演出（_check_battle_end 与恢复局共用）。
func _present_result(result: StringName) -> void:
	var data := {
		"loot": chapter.get("loot", []),
		"exp": int(chapter.get("exp", 0)),
		"gold": int(chapter.get("gold", 0)),
		"chapter_end": bool(chapter.get("chapterEnd", false)),
		"chapter_title": String(chapter.get("title", "")),
		"return_hint": "返回世界",
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


func _capture_result_visual(sprite: UnitSprite3D) -> void:
	var unit_id := StringName(sprite.unit.get(&"id", &""))
	if _result_visual_states.has(unit_id):
		return
	var visual: Node3D = sprite.portrait if sprite.portrait != null else sprite
	var children: Array[Dictionary] = []
	for child in sprite.get_children():
		if child is Sprite3D or child is Label3D:
			children.append({"node": child, "modulate": child.modulate})
	var state := {
		"sprite": sprite,
		"position": sprite.global_position,
		"scale": sprite.scale,
		"visible": sprite.visible,
		"visual": visual,
		"visual_rotation": visual.rotation,
		"children": children,
	}
	if visual is Sprite3D:
		state["visual_modulate"] = (visual as Sprite3D).modulate
	_result_visual_states[unit_id] = state


func _track_unit_visual_tween(unit_id: StringName, tween: Tween) -> void:
	var previous: Tween = _unit_visual_tweens.get(unit_id)
	if previous != null and previous.is_valid():
		previous.kill()
	_unit_visual_tweens[unit_id] = tween


func _on_presentation_cheer(unit: Dictionary) -> void:
	var sprite: UnitSprite3D = _unit_sprites.get(unit.get(&"id", &""))
	if sprite == null:
		return
	_capture_result_visual(sprite)
	var unit_id := StringName(unit[&"id"])
	var base: Vector3 = _result_visual_states[unit_id]["position"]
	sprite.global_position = base
	sprite.visible = true
	sprite.fade_alpha(1.0)
	var tween := create_tween()
	_track_unit_visual_tween(unit_id, tween)
	tween.tween_property(sprite, "global_position", base + Vector3.UP * 0.45, 0.12)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "global_position", base, 0.18)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _on_presentation_collapse(unit: Dictionary) -> void:
	var sprite: UnitSprite3D = _unit_sprites.get(unit.get(&"id", &""))
	if sprite == null:
		return
	_capture_result_visual(sprite)
	var unit_id := StringName(unit[&"id"])
	var state: Dictionary = _result_visual_states[unit_id]
	var visual := state["visual"] as Node3D
	sprite.global_position = state["position"]
	sprite.visible = true
	sprite.fade_alpha(1.0)
	var tween := create_tween()
	_track_unit_visual_tween(unit_id, tween)
	tween.tween_property(visual, "rotation:z", -PI * 0.5, 0.26)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if visual is Sprite3D:
		tween.parallel().tween_property(visual, "modulate:a", 0.55, 0.26)


## 跳过/退出只结束显示时间轴；恢复姿态与透明度，绝不写 HP、isDead 或逻辑格。
func _restore_result_visuals() -> void:
	for raw_tween in _unit_visual_tweens.values():
		var tween := raw_tween as Tween
		if tween != null and tween.is_valid():
			tween.kill()
	_unit_visual_tweens.clear()
	for raw_state in _result_visual_states.values():
		var state := raw_state as Dictionary
		var sprite := state.get("sprite") as UnitSprite3D
		if not is_instance_valid(sprite) or not sprite.is_inside_tree():
			continue
		sprite.global_position = state["position"]
		sprite.scale = state["scale"]
		sprite.visible = state["visible"]
		var visual := state.get("visual") as Node3D
		if is_instance_valid(visual):
			visual.rotation = state["visual_rotation"]
			if visual is Sprite3D and state.has("visual_modulate"):
				(visual as Sprite3D).modulate = state["visual_modulate"]
		for entry_value in state["children"]:
			var entry := entry_value as Dictionary
			var child := entry.get("node") as Node
			if is_instance_valid(child):
				child.set("modulate", entry["modulate"])
	_result_visual_states.clear()


func _on_presentation_sound(cue: StringName) -> void:
	if _presentation_audio == null:
		return
	if not _presentation_sound_cache.has(cue):
		_presentation_sound_cache[cue] = _make_presentation_sound(cue)
	_presentation_audio.stop()
	_presentation_audio.stream = _presentation_sound_cache[cue]
	_presentation_audio.play()
	print("[Battle] PresentationSound cue=%s" % String(cue))


## 固定波形，无 RNG、无外部资产依赖；各 cue 以音高/时长区分。
func _make_presentation_sound(cue: StringName) -> AudioStreamWAV:
	const SAMPLE_RATE := 22050
	var pitches := {
		&"nameplate": 660.0,
		&"boss": 180.0,
		&"victory": 880.0,
		&"chapter_end": 740.0,
		&"defeat": 130.0,
		&"loot": 980.0,
	}
	var duration := 0.30 if cue == &"boss" or cue == &"defeat" else 0.16
	var sample_count := int(SAMPLE_RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var pitch := float(pitches.get(cue, 440.0))
	for index in range(sample_count):
		var t := float(index) / float(SAMPLE_RATE)
		var progress := t / duration
		var frequency := pitch
		if cue == &"victory" or cue == &"chapter_end":
			frequency *= 1.0 + 0.25 * floorf(progress * 3.0)
		elif cue == &"defeat":
			frequency *= 1.0 - 0.35 * progress
		var envelope := minf(1.0, t / 0.01) * pow(1.0 - progress, 2.0)
		var wave := sin(TAU * frequency * t) + 0.25 * sin(TAU * frequency * 2.0 * t)
		bytes.encode_s16(index * 2, int(clampf(wave * envelope * 10500.0, -32768.0, 32767.0)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


func _on_result_presentation_finished(result: StringName, skipped: bool) -> void:
	_restore_result_visuals()
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
	_restore_result_visuals()
	_flush_save()  # 防半途退出：用最近一次完整快照补落盘（幂等）
	if _presentation_audio != null:
		_presentation_audio.stop()
	if _action_camera_kick_tween != null and _action_camera_kick_tween.is_valid():
		_action_camera_kick_tween.kill()
	_action_camera_kick_offset = Vector3.ZERO
	_apply_action_camera_kick()
	_action_camera_kick_active = false


func setup_battle(p_chapter: Dictionary, p_return_to: String = "res://main.tscn") -> void:
	chapter = p_chapter
	return_to_scene = p_return_to
	block_titles = p_chapter.get("blockTitles", [])
