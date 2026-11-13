## battle/turn_director.gd — 敌方 AI 回合 + 玩家方托管的回合编排（从 scenes/battle.gd 抽出）
##
## 职责：
##   - 敌方回合串行驱动每个 enemy 单位（_run_enemy_phase / _enemy_act）
##   - 玩家方托管：整方统一开关，自动移动+攻击+技能+物品（_run_player_auto_phase / _player_auto_act）
##   - 托管偏好数据 hosting_active / _auto_prefs / _hosting_running
##   - 单位沿路径 tween 移动（_tween_move）
##
## 设计：从 battle.gd 抽出的 Node（仿 TurnManager 是 Node 的先例 —— async 编排器需要
## get_tree() / create_tween()，所以必须是 Node 而非 RefCounted）。不持有父场景引用；
## grid/turn/chapter/unit_sprites 由 battle.gd 在 setup() 注入；战斗演出 / 胜负 / mode
## 修改通过 Callable 回交 battle.gd（保持状态机核心不外移）。
##
## 公开 API（battle.gd 调用）：
##   setup(grid, turn, chapter, unit_sprites)
##   is_hosting() / set_hosting(active)
##   get_prefs() / get_pref(unit_id) / set_pref(unit_id, key, value)
##   get_action_anim_options(unit_id)  # -> { anim_speed:float, skip:bool }
##   set_enemy_animation(speed, skip) / set_hosting_animation(speed, skip)
##   start_enemy_phase()
##   start_player_auto_phase()
##   toggle_hosting(can_start_now: bool)   # can_start_now = (玩家回合 IDLE 态时)
##   update_host_btn_text()
##
## Callable 注入面（battle.gd _ready 时赋值）：
##   on_resolve_combat(attacker, defender, on_done_cb)
##   on_resolve_skill(caster, targets, skill_id)
##   on_resolve_item(user, targets, entry)
##   on_resolve_combat_sync(attacker, defender)  # 旧敌方同步回退
##   on_resolve_combat_async(attacker, defender) # 可选：结算+await ActionAnim 的新路径
##   on_resolve_skill/on_resolve_item 返回 true 表示已自行完成演出，不再追加旧固定等待。
##   on_check_battle_end()
##   on_clear_range_highlight()
##   on_clear_selection()           # 托管/切开关时清 selected_unit
##   on_set_mode(m: int)            # 设 battle.gd 的 mode
class_name TurnDirector
extends Node

# ---- 注入的只读引用（setup 时由 battle.gd 设置）----
var grid: GridSystem
var turn: TurnManager
var chapter: Dictionary
var unit_sprites: Dictionary   # { unitId -> UnitSprite3D }

# ---- Callable 注入面 ----
var on_resolve_combat: Callable
var on_resolve_skill: Callable
var on_resolve_item: Callable
var on_resolve_combat_sync: Callable
## 新演出路径由场景集成者注入；为空时继续使用旧 sync 回调与固定等待。
var on_resolve_combat_async: Callable
var on_check_battle_end: Callable
var on_clear_range_highlight: Callable
var on_clear_selection: Callable
var on_set_mode: Callable
## 敌方/托管每个单位完整行动后回调（battle.gd 用来提交战旗快照）。
var on_action_committed: Callable

# ---- 托管状态（原 battle.gd 的 hosting_active / _auto_prefs / _hosting_running）----
# hosting_active=true 时玩家回合自动跑 start_player_auto_phase，手动输入路径被锁。
# 仅本场战斗有效，偏好存 _auto_prefs（key=unitId → {priorityTargetId, strategy}）。
var hosting_active: bool = false
## 敌方与玩家托管的演出默认值；单位 pref 的 anim_speed 可覆盖速度，skip_anim 可强制跳过。
var enemy_anim_speed: float = 1.0
var skip_enemy_anim: bool = false
var hosting_anim_speed: float = 1.0
var skip_hosting_anim: bool = false
## 敌方 / 玩家托管 AI 难度档（StringName：novice/normal/hard/nightmare）。
## 缺省 normal；由 battle.gd setup 后从 Settings 注入（本类不直接依赖 autoload）。
var enemy_difficulty: StringName = &"normal"
var host_difficulty: StringName = &"normal"
var _auto_prefs: Dictionary = {}
var _hosting_running: bool = false  # 防止 start_player_auto_phase 重入

# battle.gd 的 Mode 枚举镜像（on_set_mode 传 int；这里只用作常量便于阅读）
# 注意：必须与 battle.gd 的 enum Mode 保持一致。
const MODE_IDLE := 0
const MODE_ENEMY_TURN := 4
const MODE_ANIMATING := 5


func setup(p_grid: GridSystem, p_turn: TurnManager, p_chapter: Dictionary, p_unit_sprites: Dictionary) -> void:
	grid = p_grid
	turn = p_turn
	chapter = p_chapter
	unit_sprites = p_unit_sprites


# ============================================================
# 托管开关 + 偏好访问
# ============================================================
func is_hosting() -> bool:
	return hosting_active


## SceneArgs.hosting=true 调试入口用：直接置位（不触发立即启动，由 _on_player_phase 驱动）。
func set_hosting(active: bool) -> void:
	hosting_active = active


func get_prefs() -> Dictionary:
	return _auto_prefs


func get_pref(unit_id) -> Dictionary:
	return _auto_prefs.get(unit_id, PlayerAI.default_pref())


func set_pref(unit_id, key: StringName, value) -> void:
	var p: Dictionary = _auto_prefs.get(unit_id, PlayerAI.default_pref())
	p[key] = value
	_auto_prefs[unit_id] = p


## 恢复托管偏好（GameSession 读档传入；键为单位 id 字符串）。
func restore_prefs(prefs: Dictionary) -> void:
	_auto_prefs.clear()
	for k in prefs.keys():
		var v: Variant = prefs[k]
		if v is Dictionary:
			_auto_prefs[StringName(k)] = (v as Dictionary).duplicate(true)


func set_enemy_animation(speed: float, skipped: bool) -> void:
	enemy_anim_speed = clampf(speed, 0.1, 8.0)
	skip_enemy_anim = skipped


func set_hosting_animation(speed: float, skipped: bool) -> void:
	hosting_anim_speed = clampf(speed, 0.1, 8.0)
	skip_hosting_anim = skipped


## 场景在 await ActionAnim.play 前读取；倍速只影响演出，不改变结算或 AI 决策。
func get_action_anim_options(unit_id: StringName) -> Dictionary:
	var unit: Dictionary = grid.units.get(unit_id, {}) if grid != null else {}
	var is_enemy := StringName(unit.get(&"faction", &"")) == &"enemy"
	var speed := enemy_anim_speed if is_enemy else 1.0
	var skipped := skip_enemy_anim if is_enemy else false
	if hosting_active and not is_enemy:
		speed = hosting_anim_speed
		skipped = skip_hosting_anim
	var pref := get_pref(unit_id)
	if pref.has(&"anim_speed"):
		speed = clampf(float(pref[&"anim_speed"]), 0.1, 8.0)
	if bool(pref.get(&"skip_anim", false)):
		skipped = true
	return { &"anim_speed": speed, &"skip": skipped }


func _action_delay(unit_id: StringName, seconds: float) -> void:
	var options := get_action_anim_options(unit_id)
	if bool(options[&"skip"]):
		return
	await get_tree().create_timer(seconds / float(options[&"anim_speed"])).timeout


## 切换托管开关。can_start_now 由 battle.gd 判断（玩家回合 + IDLE 态 + 未在跑）后传入；
## 切到 true 且 can_start_now 时立即启动自动回合。
func toggle_hosting(can_start_now: bool) -> void:
	hosting_active = not hosting_active
	update_host_btn_text()
	if hosting_active and not _hosting_running and turn.phase == &"player" and can_start_now:
		on_clear_range_highlight.call()
		on_clear_selection.call()
		start_player_auto_phase()


func update_host_btn_text() -> void:
	# host_btn 由 BattleUI 持有；battle.gd 在注入时会把这个 Callable 也接上，
	# 但为兼容「host_btn 还没建好」的早期调用，这里通过 on_update_host_btn 注入。
	# 简化：host_btn 引用由 battle.gd 在 setup 后用 set_host_btn 传入。
	if _host_btn != null:
		_host_btn.text = "关闭托管" if hosting_active else "开启托管"


var _host_btn: Button = null
func set_host_btn(btn: Button) -> void:
	_host_btn = btn


# ============================================================
# 玩家方托管（autoplay）—— 镜像敌方 AI 回合的结构
# ============================================================
## 玩家回合开始时（_on_player_phase）若 hosting_active 则调用：
## 串行 await 每个未行动的 player 单位自动移动+攻击，结束后检查胜负并结束回合。
func start_player_auto_phase() -> void:
	if _hosting_running:
		return
	_hosting_running = true
	var units: Array = []
	for u in grid.units.values():
		if u.faction == &"player" and not u.isDead:
			units.append(u)
	for u in units:
		if u.isDead or u.hasActed:
			continue
		await _player_auto_act(u)
		# 每次行动后查胜负，若已分胜负则停止托管循环
		var vr := turn.check_victory(chapter.enemyUnits)
		if vr == &"win" or vr == &"lose":
			on_check_battle_end.call()
			_hosting_running = false
			return
		# 单位完整行动完成 → 提交快照（battle.gd 注入；无身份时是空操作）
		if on_action_committed.is_valid():
			on_action_committed.call()
	await get_tree().create_timer(0.3).timeout
	_hosting_running = false
	if turn.phase == &"player":
		turn.end_turn()


## 单个玩家单位的自动行动（镜像 _enemy_act）。攻击走 on_resolve_combat（含经验结算）。
func _player_auto_act(u: Dictionary) -> void:
	var enemies: Array = []
	for e in grid.units.values():
		if e.faction != &"player" and not e.isDead:
			enemies.append(e)
	if enemies.is_empty():
		# 无敌人可打：标记已行动，跳过
		u.hasMoved = true
		u.hasActed = true
		return
	var pref: Dictionary = _auto_prefs.get(u.id, PlayerAI.default_pref()).duplicate()
	# 场级托管难度覆盖单位 pref 的 difficulty（未单独配置时无该键 → 用场级档）
	pref[&"difficulty"] = host_difficulty
	var decision := PlayerAI.decide(u, grid, enemies, pref)
	var us: UnitSprite3D = unit_sprites.get(u.id)
	if us == null:
		u.hasActed = true
		return
	var move_target = decision.moveTarget
	if move_target != null and (move_target as Vector2i) != u.position:
		var path := grid.find_path(u.position, move_target, u.moveType, u.stats.mov)
		if not path.is_empty():
			await _tween_move(us, path.slice(1))
			grid.place_unit(u, (move_target as Vector2i).x, (move_target as Vector2i).y)
			u.hasMoved = true
			us.update_state()
			await get_tree().create_timer(0.2).timeout
	# 按 action.type 分发：普攻 / 技能 / 物品
	var act: Dictionary = decision.get(&"action", { &"type": &"normal" })
	var act_type: StringName = act.get(&"type", &"normal")
	var tgts: Array = act.get(&"targets", [])
	var acted := false
	if act_type == &"skill" and act.has(&"skillId"):
		await on_resolve_skill.call(u, tgts, act[&"skillId"])
		acted = true
	elif act_type == &"item" and act.has(&"itemId"):
		await on_resolve_item.call(u, tgts, act.get(&"entry", {}))
		acted = true
	elif not decision.attackTarget.is_empty() and not decision.attackTarget.isDead:
		# 玩家方攻击走 async 版 on_resolve_combat（含经验 + hasActed 设置）
		await on_resolve_combat.call(u, decision.attackTarget, func():
			on_set_mode.call(MODE_IDLE)
			on_check_battle_end.call()
		)
		acted = true
	if not acted:
		# 没攻击/技能/物品：手动标记已行动（移动也算消耗本回合行动）
		u.hasActed = true


# ============================================================
# 敌方 AI 回合
# ============================================================
func start_enemy_phase() -> void:
	var enemies: Array = []
	for u in grid.units.values():
		if u.faction == &"enemy" and not u.isDead:
			enemies.append(u)
	for enemy in enemies:
		if enemy.isDead:
			continue
		if enemy.hasActed:
			continue  # 恢复进度：只推进本回合未行动的敌方单位
		await _enemy_act(enemy)
		# 没有可攻击目标也算完成行动；同步立绘与顶部状态，不能留到下一轮误显示。
		if not enemy.isDead:
			enemy.hasActed = true
			var us: UnitSprite3D = unit_sprites.get(enemy.id)
			if us != null:
				us.update_state()
		# 单位完整行动完成 → 提交快照（battle.gd 注入；无身份时是空操作）
		if on_action_committed.is_valid():
			on_action_committed.call()
	await get_tree().create_timer(0.4).timeout
	on_check_battle_end.call()
	if turn.phase == &"enemy":
		turn.end_turn()


func _enemy_act(enemy: Dictionary) -> void:
	var players: Array = []
	for u in grid.units.values():
		if u.faction == &"player" and not u.isDead:
			players.append(u)
	if players.is_empty():
		return
	var decision := EnemyAI.decide(enemy, grid, players, enemy_difficulty)
	var us: UnitSprite3D = unit_sprites[enemy.id]
	if us == null:
		return
	var move_target = decision.moveTarget
	if move_target != null and (move_target as Vector2i) != enemy.position:
		var path := grid.find_path(enemy.position, move_target, enemy.moveType, enemy.stats.mov)
		if not path.is_empty():
			await _tween_move(us, path.slice(1))
			grid.place_unit(enemy, (move_target as Vector2i).x, (move_target as Vector2i).y)
			us.update_state()
			await get_tree().create_timer(0.2).timeout
	# 按 action.type 分发：普攻 / 技能 / 物品
	var act: Dictionary = decision.get(&"action", { &"type": &"normal" })
	var act_type: StringName = act.get(&"type", &"normal")
	var tgts: Array = act.get(&"targets", [])
	if act_type == &"skill" and act.has(&"skillId"):
		# 新处理器返回 true 表示已 await ActionAnim；旧处理器保留按偏好缩放后的固定停顿。
		var handled: Variant = await on_resolve_skill.call(enemy, tgts, act[&"skillId"])
		if not bool(handled):
			await _action_delay(enemy.id, 0.9)
	elif act_type == &"item" and act.has(&"itemId"):
		var handled: Variant = await on_resolve_item.call(enemy, tgts, act.get(&"entry", {}))
		if not bool(handled):
			await _action_delay(enemy.id, 0.7)
	elif not decision.attackTarget.is_empty() and not decision.attackTarget.isDead:
		if on_resolve_combat_async.is_valid():
			await on_resolve_combat_async.call(enemy, decision.attackTarget)
		else:
			on_resolve_combat_sync.call(enemy, decision.attackTarget)
			await _action_delay(enemy.id, 0.9)


# ============================================================
# 单位沿路径 tween 移动（共享 Camera3D 世界坐标）
# ============================================================
## UnitSprite3D 继承 Node3D；B1/B2 都返回真实地形表面的 Vector3。
func _tween_move(us: UnitSprite3D, path: Array) -> void:
	for cell in path:
		var target := us._world_cell_world(cell) if us.is_world_mode() else us._b2_cell_world(cell)
		us.face_movement(target)
		var tw := create_tween()
		tw.tween_property(us, "global_position", target, 0.15)
		await tw.finished
