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

var board: IsoBoard
## B2 等距方块地形层（复用世界渲染管线：ColumnBatch + TerrainMaterialRegistry）
var renderer: Node2D = null
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


func _ready() -> void:
	# 从 SceneArgs 读战斗参数（由 main.gd._enter_battle 设置）
	if SceneArgs.battle_args.has("chapter"):
		chapter = SceneArgs.battle_args["chapter"]
		return_to_scene = SceneArgs.battle_args.get("return_to", "res://main.tscn")
		block_titles = chapter.get("blockTitles", [])
	# B1 就地模式：main.gd 通过 SceneArgs.battle_args["world"] 注入自身引用
	_world = SceneArgs.battle_args.get("world", null)
	_b1_mode = _world != null
	if _b1_mode:
		_world_origin = chapter.get("world_origin", Vector2i.ZERO)
	# 1. 网格 + 单位 + 回合（与模式无关）
	grid = GridSystem.new(chapter.width, chapter.height, chapter.map)
	for u in chapter.playerUnits + chapter.enemyUnits:
		grid.place_unit(u, u.position.x, u.position.y)
	turn = TurnManager.new(chapter.playerUnits + chapter.enemyUnits)
	add_child(turn)
	# 1b. 回合编排器（敌方 AI + 玩家方托管）
	turn_director = TurnDirector.new()
	turn_director.setup(grid, turn, chapter, _unit_sprites)
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
	# 4. 单位
	for u in grid.units.values():
		_spawn_unit_sprite(u)
	await get_tree().process_frame
	_debug_print_unit_alignment()
	# 5. 输入 + 回合
	set_process_unhandled_input(true)
	turn.phase_player.connect(_on_player_phase)
	turn.phase_enemy.connect(_on_enemy_phase)
	if not _b1_mode:
		# B2 才需要 viewport resize 重居中（B1 由 main.gd 管相机）
		get_viewport().size_changed.connect(_on_viewport_resized)
	await get_tree().create_timer(0.3).timeout
	range_overlay.create_cursor_particles()
	turn.start_player_phase()


## B2 切场景模式渲染初始化：等距方块地形（像素版 Minecraft 风格，复用世界渲染管线）
func _setup_b2_render() -> void:
	board = IsoBoard.new()
	board.name = "Board"
	add_child(board)
	# 地形柱层（ColumnBatch 逐柱渲染，y_sort 处理柱间遮挡）
	renderer = BattlefieldRendererScript.new()
	board.add_child(renderer)
	renderer.setup(grid)
	# 范围/光标标记走注入模式：坐标/排序/高度由 renderer 提供（同 B1 的注入方式）
	range_overlay = RangeOverlay.new()
	add_child(range_overlay)
	range_overlay.setup_world(
		board, grid, block_titles,
		Callable(renderer, "coord_for"),
		Callable(renderer, "sort_for"),
		Callable(renderer, "stand_level")
	)
	board.center_on_map(chapter.width, chapter.height)


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


## B1 坐标转换：战场局部 cell (x,y) → 屏幕坐标（供 range_overlay 用）
func _b1_cell_to_screen(x: int, y: int) -> Vector2:
	var world_cell: Vector2i = _world_origin + Vector2i(x, y)
	var lvl: int = _world.cell_stand_level(world_cell)
	return _world._grid_to_screen(world_cell, float(lvl))


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
	turn_director.on_resolve_combat_sync = _resolve_combat_sync
	turn_director.on_check_battle_end = _check_battle_end
	turn_director.on_clear_range_highlight = _clear_range_highlight
	turn_director.on_clear_selection = _clear_selection
	turn_director.on_set_mode = _set_mode_from_director


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
	if renderer != null:
		# B2 等距方块模式：菜单/浮字定位带柱顶高度
		battle_ui.level_fn = Callable(renderer, "stand_level")
	add_child(battle_ui)
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
	battle_ui.set_phase_text("玩家回合 #%d" % turn_num, Color(0.29, 0.87, 0.50))
	_refresh_all_units()
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
	battle_ui.set_phase_text("敌方回合 #%d" % turn_num, Color(0.97, 0.44, 0.44))
	mode = Mode.ENEMY_TURN
	_clear_range_highlight()

	turn_director.start_enemy_phase()


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
		var screen := IsoCoords.to_screen(pos.x, pos.y, lvl)
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


## 手势 / 空格 / 滚轮：用 _input（GUI 处理前）确保一定能收到。
## 战场 UI（结束回合按钮 / 菜单面板）命中时让出缩放手势，避免误触。
## B1 就地模式下相机由 main.gd 管，这里全部跳过（避免 board 为 null 崩溃）。
func _input(event: InputEvent) -> void:
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
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed:
			match k.keycode:
				KEY_ESCAPE: _on_cancel()
				KEY_ENTER, KEY_Z: _on_confirm()
				KEY_E: _on_end_turn()
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
		return
	var key := "%d,%d" % [hover_cell.x, hover_cell.y]
	var hover_unit := grid.unit_at(hover_cell.x, hover_cell.y)
	if not hover_unit.is_empty() and hover_unit.faction != &"player":
		var stand := _find_attack_stand(hover_cell)
		if stand.x >= 0:
			var atk_path := grid.find_path(selected_unit.position, stand, selected_unit.moveType, selected_unit.stats.mov)
			if not atk_path.is_empty() and atk_path.size() >= 2:
				range_overlay.show_path(atk_path, Color(1.0, 0.25, 0.25))
				return
		range_overlay.clear_path()
		return
	# 移动路径：hover 移动范围内的空格 → 蓝色路径
	if current_move_range.has(key):
		var path := grid.find_path(selected_unit.position, hover_cell, selected_unit.moveType, selected_unit.stats.mov)
		if not path.is_empty() and path.size() >= 2:
			range_overlay.show_path(path, Color(0.25, 0.55, 1.0))   # 蓝
			return
	range_overlay.clear_path()


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
		_check_battle_end()
	)


# ============================================================
# 战斗演出
# ============================================================
func _resolve_combat(attacker: Dictionary, defender: Dictionary, on_done: Callable) -> void:
	mode = Mode.ANIMATING
	# L1 埋点：战斗结算入口（按 AGENTS.md 调试埋点强制原则）
	print("[combat] %s → %s atk_hp=%d def_hp=%d" % [
		attacker.name, defender.name, attacker.hp, defender.hp])
	var atk_us: UnitSprite3D = _unit_sprites[attacker.id]
	var def_us: UnitSprite3D = _unit_sprites[defender.id]
	# 2D 版：向目标冲一步（保留完整 2D 方向，原版 dir.y=0 是为了清除 3D 高度偏移）
	var start: Vector2 = atk_us.global_position
	var dir := (def_us.global_position - start).normalized() * 12.0   # 像素幅度
	var tween := create_tween()
	tween.tween_property(atk_us, "global_position", start + dir, 0.12)
	tween.tween_property(atk_us, "global_position", start, 0.12)
	await tween.finished
	var def_tile := grid.tile_at(defender.position.x, defender.position.y)
	var result := CombatSystem.execute(attacker, defender, def_tile.avoid_bonus, def_tile.def_bonus)
	if result.attackerHits:
		_spawn_damage_text(defender, result.attackerDamage, result.isCrit, "")
		_shake(def_us)
	else:
		_spawn_damage_text(defender, 0, false, "MISS")
	atk_us.update_state()
	def_us.update_state()
	await get_tree().create_timer(0.45).timeout
	if result.defenderDied:
		_on_unit_death(defender)
	if result.attackerDied:
		_on_unit_death(attacker)
	attacker.hasActed = true
	if attacker.faction == &"enemy":
		attacker.hasMoved = true
	atk_us.update_state()
	if attacker.faction == &"player" and result.defenderDied:
		_gain_exp(attacker, WeaponData.exp_for_kill(defender.level))
	elif attacker.faction == &"player" and result.attackerHits:
		_gain_exp(attacker, WeaponData.exp_for_hit(defender.level, attacker.level))
	on_done.call()


func _spawn_damage_text(u: Dictionary, dmg: int, is_crit: bool, label: String) -> void:
	var txt := label if not label.is_empty() else ("-%d" % dmg)
	var color := Color(0.98, 0.74, 0.14) if not label.is_empty() else (Color(0.97,0.44,0.44) if is_crit else Color.WHITE)
	_spawn_float_text(u, txt, color, 24 if is_crit else 18)


## 通用飘字（技能/物品用：治疗绿、伤害红、buff 黄、回 MP 蓝）。
func _spawn_float_text(u: Dictionary, text: String, color: Color, font_size: int = 18) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	# 定位到单位屏幕坐标（cell 世界坐标 → canvas 投影 → 屏幕坐标）
	# B1：用 main.gd 的世界坐标（含 origin + stand_level）；B2：用 IsoCoords 局部坐标
	var world_pos: Vector2
	if _b1_mode:
		var world_cell: Vector2i = _world_origin + u.position
		var lvl: int = _world.cell_stand_level(world_cell)
		world_pos = _world._grid_to_screen(world_cell, float(lvl)) + Vector2(0, -50)
	else:
		world_pos = IsoCoords.to_screen(u.position.x, u.position.y) + Vector2(0, -50)
	# canvas 投影：B1 用 main.gd 的 viewport/transform；B2 用 board 的
	var canvas: Transform2D
	var node_transform: Transform2D
	if _b1_mode:
		canvas = _world.get_viewport().get_canvas_transform()
		node_transform = _world.get_global_transform()
	else:
		canvas = board.get_viewport().get_canvas_transform()
		node_transform = board.get_global_transform()
	var screen := canvas * (node_transform * world_pos)
	lbl.position = screen - Vector2(20, 30)
	battle_ui.get_float_text_container().add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 30, 0.7)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.7)
	tw.tween_callback(lbl.queue_free)


# ============================================================
# 技能 / 物品 演出（复用 _resolve_combat 的冲撞/飘字/死亡/经验/hasActed 结构）
# ============================================================
## 技能演出。targets 为 SkillSystem.targets_for 的结果。
## 内部调 SkillSystem.execute（不被反击），演出施法者冲撞 + 各目标飘字 + 死亡 + 经验。
func _resolve_skill(caster: Dictionary, targets: Array, skill_id: StringName) -> void:
	if targets.is_empty():
		caster.hasActed = true
		return
	mode = Mode.ANIMATING
	var atk_us: UnitSprite3D = _unit_sprites.get(caster.id)
	# 施法者朝第一个目标冲一步（演出）
	if atk_us != null and not targets.is_empty():
		var first_us: UnitSprite3D = _unit_sprites.get(targets[0].id)
		if first_us != null:
			var start: Vector2 = atk_us.global_position
			var dir := (first_us.global_position - start).normalized() * 12.0
			var tween := create_tween()
			tween.tween_property(atk_us, "global_position", start + dir, 0.12)
			tween.tween_property(atk_us, "global_position", start, 0.12)
			await tween.finished
	# 落地结算
	var result := SkillSystem.execute(caster, targets, skill_id)
	# 伤害飘字
	for h in result[&"hits"]:
		var t: Dictionary = h[&"unit"]
		if _unit_sprites.get(t.id) != null:
			_spawn_damage_text(t, int(h[&"dmg"]), false, "")
			_shake(_unit_sprites[t.id])
	for m in result[&"missed"]:
		var t: Dictionary = m[&"unit"]
		_spawn_float_text(t, "MISS", Color(0.98, 0.74, 0.14))
	# 治疗飘字（绿）
	for h in result[&"healed"]:
		var t: Dictionary = h[&"unit"]
		_spawn_float_text(t, "+%d" % int(h[&"hp_delta"]), Color(0.29, 0.87, 0.50))
	# buff 飘字（黄）
	for b in result[&"buffed"]:
		var t: Dictionary = b[&"unit"]
		_spawn_float_text(t, String(b[&"desc"]), Color(0.98, 0.84, 0.30))
	# 刷新所有涉及的 sprite
	if atk_us != null:
		atk_us.update_state()
	for h in result[&"hits"] + result[&"healed"]:
		var t: Dictionary = h[&"unit"]
		if _unit_sprites.get(t.id) != null:
			(_unit_sprites[t.id] as UnitSprite3D).update_state()
	await get_tree().create_timer(0.45).timeout
	# 死亡处理 + 经验（玩家方施法击杀得经验）
	var killed := 0
	for h in result[&"hits"]:
		if bool(h.get(&"died", false)):
			_on_unit_death(h[&"unit"])
			killed += 1
	caster.hasActed = true
	if caster.faction == &"enemy":
		caster.hasMoved = true
	if caster.faction == &"player" and killed > 0:
		_gain_exp(caster, WeaponData.exp_for_kill(int(targets[0][&"level"])) * killed)
	elif caster.faction == &"player" and not result[&"hits"].is_empty():
		_gain_exp(caster, WeaponData.exp_for_hit(int(targets[0][&"level"]), int(caster[&"level"])))
	mode = Mode.IDLE
	_check_battle_end()


## 物品演出。item_entry 为 {id, uses}。内部调 ItemSystem.execute。
func _resolve_item(user: Dictionary, targets: Array, item_entry: Dictionary) -> void:
	if targets.is_empty() or item_entry.is_empty():
		user.hasActed = true
		return
	mode = Mode.ANIMATING
	var us: UnitSprite3D = _unit_sprites.get(user.id)
	# 简短使用动画（轻微上抬；2D 版用像素幅度 6px 代替原世界单位 0.15）
	if us != null:
		var start: Vector2 = us.global_position
		var tween := create_tween()
		tween.tween_property(us, "global_position", start + Vector2(0, -6), 0.12)
		tween.tween_property(us, "global_position", start, 0.12)
		await tween.finished
	var result := ItemSystem.execute(user, targets, item_entry)
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
	# 投掷物致死处理
	for h in result.get(&"hp_deltas", []):
		if bool(h.get(&"died", false)):
			_on_unit_death(h[&"unit"])
	user.hasActed = true
	if user.faction == &"enemy":
		user.hasMoved = true
	mode = Mode.IDLE
	_check_battle_end()


func _shake(us: Node2D) -> void:
	# 2D 版抖动：原版 Vector3(0.1,0,0) → 2D 用 4px 水平抖
	var orig: Vector2 = us.global_position
	var tw := create_tween()
	for i in range(4):
		tw.tween_property(us, "global_position", orig + Vector2(4, 0) * (1.0 if i % 2 == 0 else -1.0), 0.04)
	tw.tween_property(us, "global_position", orig, 0.04)


func _on_unit_death(u: Dictionary) -> void:
	var us: UnitSprite3D = _unit_sprites.get(u.id)
	grid.remove_unit(u)
	if us != null:
		var tw := create_tween()
		# UnitSprite3D 是 Node2D（2D 版），用 fade_alpha 驱动子 CanvasItem alpha 淡出
		tw.tween_method(us.fade_alpha, 1.0, 0.0, 0.4)
		tw.parallel().tween_property(us, "scale", us.scale * 1.5, 0.4)
		tw.tween_callback(func(): us.visible = false)


# ============================================================
# 经验/升级
# ============================================================
func _gain_exp(u: Dictionary, amount: int) -> void:
	if u.isDead:
		return
	u.exp += amount
	while u.exp >= WeaponData.exp_to_next(u.level) and u.level < 20:
		u.exp -= WeaponData.exp_to_next(u.level)
		u.level += 1
		# 升级随机成长：每属性按 growths% 概率 +1
		var g: Dictionary = u.growths
		var s: Dictionary = u.stats
		for k in g.keys():
			if randf() * 100.0 < g[k]:
				s[k] = int(s[k]) + 1
		u.hp = int(u.stats.hp)  # 升 hp 上限后回满
	if _unit_sprites.has(u.id):
		(_unit_sprites[u.id] as UnitSprite3D).update_state()


# ============================================================
# 玩家行动收尾（菜单UI在 battle_ui；这里只保留状态机收尾）
# ============================================================
## 玩家手动行动（攻击/技能/物品）结束后的统一收尾。
func _finish_player_action(_u: Dictionary) -> void:
	selected_unit = {}
	mode = Mode.IDLE
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


# 同步版战斗演出（敌方回合用，不含 await 链）
func _resolve_combat_sync(attacker: Dictionary, defender: Dictionary) -> void:
	mode = Mode.ANIMATING
	var atk_us: UnitSprite3D = _unit_sprites[attacker.id]
	var def_us: UnitSprite3D = _unit_sprites[defender.id]
	var def_tile := grid.tile_at(defender.position.x, defender.position.y)
	var result := CombatSystem.execute(attacker, defender, def_tile.avoid_bonus, def_tile.def_bonus)
	if result.attackerHits:
		_spawn_damage_text(defender, result.attackerDamage, result.isCrit, "")
		_shake(def_us)
	else:
		_spawn_damage_text(defender, 0, false, "MISS")
	atk_us.update_state()
	def_us.update_state()
	# 延迟处理死亡（给飘字时间）
	get_tree().create_timer(0.45).timeout.connect(func():
		if result.defenderDied:
			_on_unit_death(defender)
		if result.attackerDied:
			_on_unit_death(attacker)
		attacker.hasActed = true
		attacker.hasMoved = true
		if attacker.faction == &"player" and result.defenderDied:
			_gain_exp(attacker, WeaponData.exp_for_kill(defender.level))
		if mode == Mode.ANIMATING:
			mode = Mode.ENEMY_TURN
	)



# ============================================================
# 胜负
# ============================================================
func _check_battle_end() -> void:
	if _battle_ended:
		return  # 已结束，避免重复 banner / 重复挂 timer
	var enemies: Array = chapter.enemyUnits
	var result := turn.check_victory(enemies)
	var ended := false
	if result == &"win":
		# L1 埋点：胜负判定生效（按 AGENTS.md 调试埋点强制原则）
		print("[battle] 胜利！回合数=%d 存活玩家=%d" % [turn.turn_number, _alive_count(&"player")])
		battle_ui.show_result_banner("胜利！", Color(0.29, 0.87, 0.50))
		ended = true
	elif result == &"lose":
		print("[battle] 败北 回合数=%d 存活敌方=%d" % [turn.turn_number, _alive_count(&"enemy")])
		battle_ui.show_result_banner("败北...", Color(0.97, 0.44, 0.44))
		ended = true
	if ended:
		# 置位结束标志，阻止 turn_director 继续推进回合
		_battle_ended = true
		mode = Mode.ANIMATING
		if _b1_mode:
			# B1 就地模式：发信号让 main.gd 接管 _exit_battle（不切场景）
			get_tree().create_timer(3.0).timeout.connect(func():
				if is_instance_valid(self):
					battle_finished.emit(result)
			)
		else:
			# B2 切场景模式：3 秒后切回 return_to_scene
			get_tree().create_timer(3.0).timeout.connect(func():
				if not is_instance_valid(self):
					return
				var tree := get_tree()
				if tree != null:
					tree.change_scene_to_file(return_to_scene)
			)


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
func setup_battle(p_chapter: Dictionary, p_return_to: String = "res://main.tscn") -> void:
	chapter = p_chapter
	return_to_scene = p_return_to
	block_titles = p_chapter.get("blockTitles", [])
