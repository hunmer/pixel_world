## game_sfx.gd — 全局音效管理（autoload: Sfx）
## 统一播放 assets/audio/sfx 素材：UI 点击/Hover、战棋战斗、回合切换、
## 胜负、升级、地形脚步声。按钮声通过 SceneTree.node_added 自动挂接，
## 各场景无需逐个 connect。所有播放走固定播放器池，无每帧分配。

extends Node

const SFX_ROOT := "res://assets/audio/sfx"
const POOL_SIZE := 10
const UI_ATTACH_META := &"_sfx_ui_attached"

## cue -> [相对路径, 音量dB, 音高随机半音]
const CUES := {
	&"ui_confirm": ["ui/sfx_ui_confirm.mp3", -8.0, 0.4],
	&"ui_hover": ["ui/sfx_ui_cursor.mp3", -17.0, 0.3],
	&"ui_cancel": ["ui/sfx_ui_cancel.mp3", -10.0, 0.3],
	&"ui_select": ["ui/sfx_ui_select.mp3", -12.0, 0.3],
	&"ui_error": ["ui/sfx_ui_error.mp3", -8.0, 0.0],
	&"ui_menu_open": ["ui/sfx_ui_menu_open.mp3", -10.0, 0.3],
	&"ui_menu_close": ["ui/sfx_ui_menu_close.mp3", -10.0, 0.3],
	&"ui_equip": ["ui/sfx_ui_equip.wav", -8.0, 0.3],
	&"ui_levelup": ["ui/sfx_ui_levelup.wav", -6.0, 0.0],
	&"ui_turn_end": ["ui/sfx_ui_turn_end.mp3", -8.0, 0.0],
	&"turn_player": ["system/sfx_turn_start_player.mp3", -8.0, 0.0],
	&"turn_enemy": ["system/sfx_turn_start_enemy.mp3", -8.0, 0.0],
	&"victory": ["system/sfx_victory.wav", -4.0, 0.0],
	&"defeat": ["system/sfx_defeat.mp3", -6.0, 0.0],
	&"promote": ["system/sfx_promote.wav", -6.0, 0.0],
	&"save": ["system/sfx_save.mp3", -10.0, 0.0],
	&"low_hp": ["system/sfx_low_hp_alarm.mp3", -10.0, 0.0],
	&"swing_sword": ["combat/sfx_sword_swing.wav", -8.0, 0.6],
	&"swing_axe": ["combat/sfx_axe_swing.mp3", -8.0, 0.6],
	&"swing_lance": ["combat/sfx_lance_swing.mp3", -8.0, 0.6],
	&"bow_draw": ["combat/sfx_bow_draw.mp3", -14.0, 0.4],
	&"bow_release": ["combat/sfx_bow_release.mp3", -8.0, 0.4],
	&"counter": ["combat/sfx_counter.mp3", -8.0, 0.3],
	&"crit": ["combat/sfx_crit.wav", -4.0, 0.0],
	&"heal": ["combat/sfx_heal.mp3", -8.0, 0.3],
	&"hit_blade": ["combat/sfx_hit_blade.mp3", -6.0, 0.5],
	&"hit_blunt": ["combat/sfx_hit_blunt.mp3", -6.0, 0.5],
	&"hit_pierce": ["combat/sfx_hit_pierce.mp3", -6.0, 0.5],
	&"skill_fire": ["combat/sfx_skill_fire.mp3", -7.0, 0.3],
	&"skill_water": ["combat/sfx_skill_water.mp3", -7.0, 0.3],
	&"skill_wind": ["combat/sfx_skill_wind.wav", -7.0, 0.3],
	&"skill_earth": ["combat/sfx_skill_earth.mp3", -7.0, 0.3],
	&"skill_light": ["combat/sfx_skill_light.wav", -7.0, 0.3],
	&"skill_dark": ["combat/sfx_skill_dark.mp3", -7.0, 0.3],
	&"miss": ["combat/sfx_miss.mp3", -10.0, 0.4],
	&"unit_damaged": ["combat/sfx_unit_damaged.mp3", -8.0, 0.5],
	&"unit_death": ["combat/sfx_unit_death.mp3", -7.0, 0.2],
	&"step_plain": ["terrain/sfx_step_plain.mp3", -15.0, 1.5],
	&"step_forest": ["terrain/sfx_step_forest.mp3", -15.0, 1.5],
	&"step_snow": ["terrain/sfx_step_snow.mp3", -15.0, 1.5],
	&"step_water": ["terrain/sfx_step_water.mp3", -15.0, 1.5],
	&"step_mountain": ["terrain/sfx_step_mountain.mp3", -15.0, 1.5],
	&"step_fort": ["terrain/sfx_step_fort.mp3", -15.0, 1.5],
}

var _pool: Array[AudioStreamPlayer] = []
var _streams := {}
var _pool_cursor := 0
var _last_play_at := {}  # cue -> 时间戳（节流用）
var _low_hp_cooldown_until := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % index
		add_child(player)
		_pool.append(player)
	# 全局 UI 按钮声：任何 BaseButton 入树即挂接，无需各场景手动 connect。
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree() != null:
		get_tree().node_added.disconnect(_on_node_added)


## 播放一个 cue；素材缺失或被节流时返回 false（调用方可回退）。
func play(cue: StringName, throttle_seconds: float = 0.0) -> bool:
	var entry: Array = CUES.get(cue)
	if entry == null:
		return false
	var stream: AudioStream = _get_stream(String(entry[0]))
	if stream == null:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if throttle_seconds > 0.0 and _last_play_at.has(cue) \
			and now - float(_last_play_at[cue]) < throttle_seconds:
		return false
	_last_play_at[cue] = now
	var player := _pool[_pool_cursor]
	_pool_cursor = (_pool_cursor + 1) % _pool.size()
	player.stream = stream
	player.volume_db = float(entry[1])
	player.pitch_scale = 1.0 + randf_range(-float(entry[2]), float(entry[2])) / 12.0
	player.play()
	return true


## 战棋地形脚步：按 BattleGrid 地形类型映射到脚步素材。
func play_step(terrain_type: StringName) -> bool:
	var cue := StringName("step_" + String(_step_category(String(terrain_type))))
	return play(cue, 0.08)


## 世界模式脚步：按 CellContext 的水域/生物群系/地貌推断（接受 Dictionary 或 CellContext）。
func play_world_step(context) -> bool:
	var is_water := false
	var biome := ""
	var landform := ""
	if context is Dictionary:
		is_water = bool(context.get("is_water", false)) or int(context.get("water_depth", 0)) > 0
		biome = String(context.get("biome_id", ""))
		landform = String(context.get("landform_id", ""))
	elif context != null:
		is_water = bool(context.is_water) or int(context.water_depth) > 0
		biome = String(context.biome_id)
		landform = String(context.landform_id)
	if is_water:
		return play(&"step_water", 0.08)
	if biome.contains("snow") or biome.contains("frost"):
		return play(&"step_snow", 0.08)
	if landform.contains("forest") or biome.contains("forest"):
		return play(&"step_forest", 0.08)
	if landform.contains("mountain") or landform.contains("rock") or biome.contains("rock"):
		return play(&"step_mountain", 0.08)
	return play(&"step_plain", 0.08)


## 低血量警报（带冷却），供战棋受伤后调用。
func play_low_hp() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _low_hp_cooldown_until:
		return false
	_low_hp_cooldown_until = now + 6.0
	return play(&"low_hp")


func _step_category(terrain_type: String) -> String:
	match terrain_type:
		"forest":
			return "forest"
		"snow":
			return "snow"
		"water":
			return "water"
		"mountain", "rocky":
			return "mountain"
		"fort", "village", "wall":
			return "fort"
		_:
			return "plain"


func _get_stream(relative_path: String) -> AudioStream:
	if _streams.has(relative_path):
		return _streams[relative_path]
	var full_path := SFX_ROOT + "/" + relative_path
	if not ResourceLoader.exists(full_path):
		push_warning("[Sfx] 素材缺失: " + full_path)
		_streams[relative_path] = null
		return null
	var stream: AudioStream = load(full_path)
	_streams[relative_path] = stream
	return stream


func _on_node_added(node: Node) -> void:
	if not (node is BaseButton):
		return
	var button := node as BaseButton
	if button.has_meta(UI_ATTACH_META):
		return
	button.set_meta(UI_ATTACH_META, true)
	button.pressed.connect(func() -> void:
		if not button.disabled:
			play(&"ui_confirm"))
	button.mouse_entered.connect(func() -> void:
		if not button.disabled and button.is_visible_in_tree():
			play(&"ui_hover", 0.05))
	if button is OptionButton:
		(button as OptionButton).item_selected.connect(func(_index: int) -> void:
			play(&"ui_select"))
