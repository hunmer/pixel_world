## battle/battle_sfx.gd — 战斗音效（出手/受击 + 结算演出 cue + 程序化回退波形）
##
## 职责：
##   - 出手音：按事件动画/武器类型选拨剑/挥斧/突刺/放箭
##   - 受击/闪避/治疗/死亡/暴击/低血量警报音
##   - 结算演出 cue（胜利/失败/拾取/名牌/Boss 横幅）：优先真实素材（Sfx autoload），
##     缺失时回退程序化波形（22050Hz 固定波形，无 RNG、无外部资产依赖）
##
## 设计：从 scenes/battle.gd 抽出的 Node。自有 AudioStreamPlayer("PresentationAudio") 与
## 波形缓存 sound_cache；battle.gd 以别名变量 _presentation_audio/_presentation_sound_cache
## 引用同一实例（契约测试内省面）。grid 由 battle.gd 在 setup() 注入；不持有父场景引用。
##
## 公开 API（battle.gd 调用）：
##   setup(grid)
##   play_strike(event)          # ActionAnim strike 相位出手音（BattleCameraKick 经回调触发）
##   play_impact(impact)         # impact 受击音（battle.gd _on_impact_presented 委托）
##   on_presentation_sound(cue)  # 结算演出 cue（battle.gd _on_presentation_sound 委托）

class_name BattleSfx
extends Node

var grid: GridSystem
var audio_player: AudioStreamPlayer = null
var sound_cache: Dictionary = {}


func setup(p_grid: GridSystem) -> void:
	grid = p_grid
	audio_player = AudioStreamPlayer.new()
	audio_player.name = "PresentationAudio"
	add_child(audio_player)


## 出手音：按事件动画/武器类型选拨剑/挥斧/突刺/放箭；法系由受击音覆盖。
func play_strike(event: Dictionary) -> void:
	var anim := String(event.get(&"anim", &"slash"))
	var cue := StringName()
	if anim == "projectile:arrow":
		cue = &"bow_release"
	elif anim == "slash":
		var attacker: Dictionary = grid.units.get(StringName(event.get(&"attacker_id", &"")), {})
		var weapon_type := StringName(WeaponData.unit_weapon(attacker).get(&"type", &"sword"))
		match weapon_type:
			&"axe":
				cue = &"swing_axe"
			&"lance":
				cue = &"swing_lance"
			_:
				cue = &"swing_sword"
	if cue != StringName():
		Sfx.play(cue)


## 受击/闪避/治疗/死亡/暴击/低血量警报音；素材缺失时 Sfx 内部静默。
func play_impact(impact: Dictionary) -> void:
	if int(impact.get(&"healing", 0)) > 0:
		Sfx.play(&"heal")
		return
	if not bool(impact.get(&"hit", false)):
		Sfx.play(&"miss")
		return
	if bool(impact.get(&"died", false)):
		Sfx.play(&"unit_death")
		return
	if bool(impact.get(&"critical", false)):
		Sfx.play(&"crit")
		return
	var element := StringName(impact.get(&"element", &"physical"))
	if element == &"physical":
		var source: Dictionary = grid.units.get(StringName(impact.get(&"source_id", &"")), {})
		var weapon_type := StringName(WeaponData.unit_weapon(source).get(&"type", &"sword"))
		match weapon_type:
			&"axe":
				Sfx.play(&"hit_blunt")
			&"lance", &"bow":
				Sfx.play(&"hit_pierce")
			_:
				Sfx.play(&"hit_blade")
	else:
		Sfx.play(StringName("skill_" + String(element)))
	# 低血量警报：我方单位 HP ≤ 25%（Sfx 内部带 6s 冷却）
	var hp_after := int(impact.get(&"hp_after", 0))
	if hp_after > 0:
		var u: Dictionary = grid.units.get(StringName(impact.get(&"target_id", &"")), {})
		if not u.is_empty() and u.get(&"faction", &"") == &"player":
			var max_hp := int(u.get(&"stats", {}).get(&"hp", 0))
			if max_hp > 0 and hp_after * 4 <= max_hp:
				Sfx.play_low_hp()


func on_presentation_sound(cue: StringName) -> void:
	# 优先播放真实素材（assets/audio/sfx，经 Sfx autoload）；缺失时回退程序化波形。
	if Sfx.play(_cue_to_sfx(cue)):
		print("[Battle] PresentationSound cue=%s (sfx)" % String(cue))
		return
	if audio_player == null:
		return
	if not sound_cache.has(cue):
		sound_cache[cue] = _make_sound(cue)
	audio_player.stop()
	audio_player.stream = sound_cache[cue]
	audio_player.play()
	print("[Battle] PresentationSound cue=%s" % String(cue))


## 演出 cue → Sfx cue 映射（胜利/失败/拾取/名牌/Boss 横幅）。
func _cue_to_sfx(cue: StringName) -> StringName:
	match cue:
		&"victory", &"chapter_end":
			return &"victory"
		&"defeat":
			return &"defeat"
		&"loot":
			return &"ui_equip"
		&"nameplate":
			return &"ui_select"
		&"boss":
			return &"skill_dark"
	return cue


## 固定波形，无 RNG、无外部资产依赖；各 cue 以音高/时长区分。
func _make_sound(cue: StringName) -> AudioStreamWAV:
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
