## battle/result_presentation.gd — 开战名牌、Boss 横幅与胜负/章节末结算演出
##
## 纯表现层：只展示调用方传入的单位、loot/exp/gold，不生成或发放奖励。
## 所有时间轴均可通过 Space/Enter/Escape/点击或 skip() 跳过；每次播放只发一次完成信号。
class_name BattleResultPresentation
extends Control

signal nameplate_shown(unit: Dictionary, index: int)
signal boss_banner_shown(unit: Dictionary)
signal loot_shown(entry: Dictionary, index: int)
signal cheer_requested(unit: Dictionary)
signal collapse_requested(unit: Dictionary)
signal sound_requested(cue: StringName)
signal opening_finished(skipped: bool)
signal result_finished(result: StringName, skipped: bool)

const NAMEPLATE_INTERVAL := 0.15
const NAMEPLATE_FADE_DURATION := 0.12
const BOSS_HOLD_DURATION := 0.65
const OPENING_HOLD_DURATION := 0.25
const LOOT_INTERVAL := 0.20
const ROLL_DURATION := 0.65
const CHAPTER_HOLD_DURATION := 0.35
const DEFEAT_FADE_DURATION := 0.55

const RESULT_WIN := &"win"
const RESULT_LOSE := &"lose"

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")

const _DEFEAT_SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float fade_amount = 0.0;
void fragment() {
	vec4 source = texture(screen_texture, SCREEN_UV);
	float grey = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	vec3 faded = mix(source.rgb, vec3(grey) * 0.55, fade_amount);
	COLOR = vec4(faded, fade_amount);
}
"""

var _generation := 0
var _active_kind: StringName = &""
var _stage: Control
var _skip_button: Button
var _tweens: Array[Tween] = []

var _opening_root: Control
var _opening_units: Array = []
var _boss: Dictionary = {}
var _nameplate_rows: Array[PanelContainer] = []
var _nameplate_sent: Array[bool] = []
var _boss_panel: PanelContainer
var _boss_sent := false

var _result_root: Control
var _result_data: Dictionary = {}
var _survivors: Array = []
var _defeated: Array = []
var _cheer_sent: Array[bool] = []
var _collapse_sent: Array[bool] = []
var _loot_entries: Array[Dictionary] = []
var _loot_rows: Array[PanelContainer] = []
var _loot_sent: Array[bool] = []
var _exp_value: Label
var _gold_value: Label
var _chapter_card: PanelContainer
var _fade_material: ShaderMaterial


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_widgets()


func _ensure_widgets() -> void:
	if is_instance_valid(_stage):
		return
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_skip_button = UIFactoryScript.button("跳过演出 (Space)", skip)
	_skip_button.name = "SkipButton"
	_skip_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_button.offset_left = -186.0
	_skip_button.offset_top = -58.0
	_skip_button.offset_right = -18.0
	_skip_button.offset_bottom = -18.0
	add_child(_skip_button)
	_skip_button.hide()


func is_playing() -> bool:
	return _active_kind != &""


func _input(event: InputEvent) -> void:
	if not is_playing():
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			get_viewport().set_input_as_handled()
			skip()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			skip()


## 按传入顺序逐个亮出名牌；boss 非空时追加黑底金字横幅。
func play_opening(units: Array, boss: Dictionary = {}) -> void:
	_ensure_widgets()
	_opening_units = units.duplicate()
	_boss = boss.duplicate(true)
	var run_id := _begin(&"opening")
	_build_opening()
	print("[result_presentation] opening units=%d boss=%s" % [_opening_units.size(), "none" if _boss.is_empty() else _unit_name(_boss)])
	for index in range(_opening_units.size()):
		if not _is_current(run_id):
			return
		_reveal_nameplate(index, true)
		if index < _opening_units.size() - 1 or not _boss.is_empty():
			await get_tree().create_timer(NAMEPLATE_INTERVAL).timeout
	if not _is_current(run_id):
		return
	if not _boss.is_empty():
		_show_boss(true)
		await get_tree().create_timer(BOSS_HOLD_DURATION).timeout
	else:
		await get_tree().create_timer(OPENING_HOLD_DURATION).timeout
	if _is_current(run_id):
		_finish(run_id, false)


## result 接受现有战斗的 win/lose（也兼容 victory/defeat）。
## data: { loot:Array, exp:int, gold:int, chapter_end:bool, chapter_title:String,
##         title:String, return_hint:String }；仅读取，不改写逻辑数据。
func play_result(result: StringName, data: Dictionary = {}, survivors: Array = [], defeated: Array = []) -> void:
	_ensure_widgets()
	var normalized := _normalize_result(result)
	_result_data = data.duplicate(true)
	_survivors = survivors.duplicate()
	_defeated = defeated.duplicate()
	var run_id := _begin(normalized)
	_build_result(normalized)
	print("[result_presentation] result=%s exp=%d gold=%d chapter=%s" % [normalized, int(_result_data.get(&"exp", 0)), int(_result_data.get(&"gold", 0)), str(bool(_result_data.get(&"chapter_end", false)))])
	if normalized == RESULT_LOSE:
		await _play_defeat(run_id)
	else:
		await _play_victory(run_id)


## 章节末是胜利结算的附加标题卡，不另造一套奖励流程。
func play_chapter_result(data: Dictionary = {}, survivors: Array = []) -> void:
	var chapter_data := data.duplicate(true)
	chapter_data[&"chapter_end"] = true
	await play_result(RESULT_WIN, chapter_data, survivors)


## 立即落到当前演出的最终状态并发出唯一完成信号；重复调用安全。
func skip() -> void:
	if not is_playing():
		return
	_finish(_generation, true)


func _normalize_result(result: StringName) -> StringName:
	if result in [&"win", &"victory"]:
		return RESULT_WIN
	if result in [&"lose", &"defeat"]:
		return RESULT_LOSE
	push_warning("未知战斗结果 '%s'，按 lose 演出处理" % result)
	return RESULT_LOSE


func _begin(kind: StringName) -> int:
	if is_playing():
		skip()
	_generation += 1
	_active_kind = kind
	_clear_stage()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_skip_button.show()
	return _generation


func _is_current(run_id: int) -> bool:
	return is_playing() and run_id == _generation


func _finish(run_id: int, skipped: bool) -> void:
	if not _is_current(run_id):
		return
	var finished_kind := _active_kind
	_active_kind = &""
	_generation += 1
	_kill_tweens()
	_skip_button.hide()
	print("[result_presentation] finished kind=%s skipped=%s" % [finished_kind, str(skipped)])
	if finished_kind == &"opening":
		_finalize_opening()
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		opening_finished.emit(skipped)
	else:
		_finalize_result(finished_kind)
		# 结果面板保留到场景退出；屏蔽棋盘点击，但不再响应跳过键。
		mouse_filter = Control.MOUSE_FILTER_STOP
		result_finished.emit(finished_kind, skipped)


func _clear_stage() -> void:
	for child in _stage.get_children():
		(child as Control).hide()
		# 立即脱离当前舞台，避免新演出同帧找到/显示上一轮的节点。
		_stage.remove_child(child)
		child.queue_free()


func _track(tween: Tween) -> void:
	_tweens.append(tween)


func _kill_tweens() -> void:
	for tween in _tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_tweens.clear()


# ============================================================
# 开战名牌 / Boss 横幅
# ============================================================
func _build_opening() -> void:
	_nameplate_rows.clear()
	_nameplate_sent.clear()
	_boss_sent = false
	_opening_root = Control.new()
	_opening_root.name = "Opening"
	_opening_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_opening_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_opening_root)

	var plates := PanelContainer.new()
	plates.name = "Nameplates"
	plates.custom_minimum_size = Vector2(280, 0)
	plates.position = Vector2(42, 84)
	plates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plates.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.035, 0.06, 0.90), Color(0.55, 0.68, 0.86)))
	_opening_root.add_child(plates)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 7)
	plates.add_child(list)
	for index in range(_opening_units.size()):
		var unit: Dictionary = _opening_units[index]
		var row := PanelContainer.new()
		row.name = "Nameplate%d" % index
		row.visible = false
		row.modulate.a = 0.0
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.08, 0.12, 0.94), _faction_color(unit)))
		list.add_child(row)
		var label := UIFactoryScript.label(
			_nameplate_text(unit), 18, _faction_color(unit))
		row.add_child(label)
		_nameplate_rows.append(row)
		_nameplate_sent.append(false)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_opening_root.add_child(center)
	_boss_panel = PanelContainer.new()
	_boss_panel.name = "BossBanner"
	_boss_panel.custom_minimum_size = Vector2(480, 112)
	_boss_panel.visible = false
	_boss_panel.modulate.a = 0.0
	_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.add_theme_stylebox_override("panel", _panel_style(Color.BLACK, Color(0.95, 0.75, 0.25), 18))
	center.add_child(_boss_panel)
	var boss_box := VBoxContainer.new()
	_boss_panel.add_child(boss_box)
	var boss_title := UIFactoryScript.label(
		"BOSS · %s" % String(_boss.get(&"title", "强敌")), 16, Color(0.95, 0.75, 0.25))
	boss_title.name = "BossTitle"
	boss_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_title)
	var boss_name := UIFactoryScript.label(_unit_name(_boss), 36, Color(1.0, 0.88, 0.52))
	boss_name.name = "BossName"
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_name)


func _reveal_nameplate(index: int, with_sound: bool) -> void:
	if index < 0 or index >= _nameplate_rows.size():
		return
	var row := _nameplate_rows[index]
	if _nameplate_sent[index]:
		if not with_sound:
			row.show()
			row.modulate.a = 1.0
		return
	_nameplate_sent[index] = true
	row.visible = true
	if with_sound:
		row.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(row, "modulate:a", 1.0, NAMEPLATE_FADE_DURATION)
		_track(tween)
	else:
		row.modulate.a = 1.0
	var unit: Dictionary = _opening_units[index]
	var run_id := _generation
	nameplate_shown.emit(unit, index)
	if with_sound and _is_current(run_id):
		sound_requested.emit(&"nameplate")


func _show_boss(with_sound: bool) -> void:
	if _boss.is_empty():
		return
	if _boss_sent:
		if not with_sound:
			_boss_panel.show()
			_boss_panel.modulate.a = 1.0
		return
	_boss_sent = true
	_boss_panel.visible = true
	if with_sound:
		_boss_panel.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_boss_panel, "modulate:a", 1.0, NAMEPLATE_FADE_DURATION)
		_track(tween)
	else:
		_boss_panel.modulate.a = 1.0
	var run_id := _generation
	boss_banner_shown.emit(_boss)
	if with_sound and _is_current(run_id):
		sound_requested.emit(&"boss")


func _finalize_opening() -> void:
	for index in range(_nameplate_rows.size()):
		_reveal_nameplate(index, false)
	_show_boss(false)
	if is_instance_valid(_opening_root):
		_opening_root.hide()


# ============================================================
# 胜利 / 失败 / 章节末
# ============================================================
func _build_result(kind: StringName) -> void:
	_loot_entries.clear()
	_loot_rows.clear()
	_loot_sent.clear()
	_cheer_sent.clear()
	_collapse_sent.clear()
	_exp_value = null
	_gold_value = null
	_chapter_card = null
	_fade_material = null
	for _unit in _survivors:
		_cheer_sent.append(false)
	for _unit in _defeated:
		_collapse_sent.append(false)

	_result_root = Control.new()
	_result_root.name = "Result"
	_result_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_result_root)

	var fade := ColorRect.new()
	fade.name = "DefeatFade" if kind == RESULT_LOSE else "VictoryDim"
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_root.add_child(fade)
	if kind == RESULT_LOSE:
		var back_buffer := BackBufferCopy.new()
		back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		_result_root.add_child(back_buffer)
		_result_root.move_child(back_buffer, 0)
		var shader := Shader.new()
		shader.code = _DEFEAT_SHADER_CODE
		_fade_material = ShaderMaterial.new()
		_fade_material.shader = shader
		_fade_material.set_shader_parameter("fade_amount", 0.0)
		fade.material = _fade_material
	else:
		fade.color = Color(0.015, 0.02, 0.035, 0.64)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_root.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "ResultPanel"
	panel.custom_minimum_size = Vector2(470, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.03, 0.05, 0.95), Color(0.82, 0.70, 0.40), 20))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := UIFactoryScript.label(
		String(_result_data.get(&"title", "胜利！" if kind == RESULT_WIN else "败北…")), 42,
		Color(0.55, 0.95, 0.66) if kind == RESULT_WIN else Color(0.95, 0.48, 0.48))
	title.name = "ResultTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	if kind == RESULT_WIN:
		_build_victory_widgets(box)
	else:
		var hint := UIFactoryScript.label(
			String(_result_data.get(&"return_hint", "战斗结束 · 返回战场…")), 18, Color.WHITE)
		hint.name = "ReturnHint"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(hint)


func _build_victory_widgets(box: VBoxContainer) -> void:
	var loot_title := UIFactoryScript.label("战利品", 17, Color(0.95, 0.80, 0.43))
	box.add_child(loot_title)
	var loot_list := VBoxContainer.new()
	loot_list.name = "LootList"
	box.add_child(loot_list)
	_loot_entries = _normalized_loot()
	for index in range(_loot_entries.size()):
		var row := PanelContainer.new()
		row.name = "Loot%d" % index
		row.visible = false
		row.modulate.a = 0.0
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.09, 0.12, 0.96), Color(0.35, 0.40, 0.50), 7))
		loot_list.add_child(row)
		var label := UIFactoryScript.label(_loot_text(_loot_entries[index]), 18, UIThemeScript.TEXT_MAIN)
		row.add_child(label)
		_loot_rows.append(row)
		_loot_sent.append(false)
	if _loot_entries.is_empty():
		var empty := UIFactoryScript.label("（无）", 16, UIThemeScript.TEXT_MAIN)
		loot_list.add_child(empty)

	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 24)
	box.add_child(stats)
	_exp_value = _add_reward_counter(stats, "EXP", "ExpValue")
	_gold_value = _add_reward_counter(stats, "金币", "GoldValue")
	_exp_value.text = "0"
	_gold_value.text = "0"

	_chapter_card = PanelContainer.new()
	_chapter_card.name = "ChapterCard"
	_chapter_card.visible = false
	_chapter_card.add_theme_stylebox_override("panel", _panel_style(Color(0.10, 0.075, 0.025, 0.96), Color(0.95, 0.75, 0.25), 12))
	box.add_child(_chapter_card)
	var chapter_box := VBoxContainer.new()
	_chapter_card.add_child(chapter_box)
	var chapter_title := UIFactoryScript.label("章节完成", 24, Color(1.0, 0.86, 0.48))
	chapter_title.name = "ChapterTitle"
	chapter_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chapter_box.add_child(chapter_title)
	var chapter_name := UIFactoryScript.label(
		String(_result_data.get(&"chapter_title", "")), 16, Color.WHITE)
	chapter_name.name = "ChapterName"
	chapter_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chapter_box.add_child(chapter_name)


func _add_reward_counter(parent: HBoxContainer, caption: String, value_name: String) -> Label:
	var pair := HBoxContainer.new()
	parent.add_child(pair)
	var caption_label := UIFactoryScript.label(caption, 18, UIThemeScript.TEXT_MAIN)
	pair.add_child(caption_label)
	var value := UIFactoryScript.label("", 24, Color(1.0, 0.90, 0.55))
	value.name = value_name
	value.custom_minimum_size = Vector2(76, 0)
	pair.add_child(value)
	return value


func _play_victory(run_id: int) -> void:
	sound_requested.emit(&"victory")
	if not _is_current(run_id):
		return
	for index in range(_survivors.size()):
		if not _is_current(run_id):
			return
		_emit_cheer(index)
	for index in range(_loot_rows.size()):
		if not _is_current(run_id):
			return
		_reveal_loot(index, true)
		await get_tree().create_timer(LOOT_INTERVAL).timeout
	if not _is_current(run_id):
		return
	_roll_rewards()
	await get_tree().create_timer(ROLL_DURATION).timeout
	if not _is_current(run_id):
		return
	_set_reward_values_final()
	if bool(_result_data.get(&"chapter_end", false)):
		_chapter_card.show()
		sound_requested.emit(&"chapter_end")
		await get_tree().create_timer(CHAPTER_HOLD_DURATION).timeout
	if _is_current(run_id):
		_finish(run_id, false)


func _play_defeat(run_id: int) -> void:
	sound_requested.emit(&"defeat")
	if not _is_current(run_id):
		return
	for index in range(_defeated.size()):
		if not _is_current(run_id):
			return
		_emit_collapse(index)
	var tween := create_tween()
	tween.tween_method(_set_defeat_fade, 0.0, 1.0, DEFEAT_FADE_DURATION)
	_track(tween)
	await get_tree().create_timer(DEFEAT_FADE_DURATION).timeout
	if _is_current(run_id):
		_set_defeat_fade(1.0)
		_finish(run_id, false)


func _emit_cheer(index: int) -> void:
	if index < 0 or index >= _survivors.size() or _cheer_sent[index]:
		return
	_cheer_sent[index] = true
	var unit: Dictionary = _survivors[index]
	cheer_requested.emit(unit)


func _emit_collapse(index: int) -> void:
	if index < 0 or index >= _defeated.size() or _collapse_sent[index]:
		return
	_collapse_sent[index] = true
	var unit: Dictionary = _defeated[index]
	collapse_requested.emit(unit)


func _reveal_loot(index: int, with_sound: bool) -> void:
	if index < 0 or index >= _loot_rows.size():
		return
	var row := _loot_rows[index]
	if _loot_sent[index]:
		if not with_sound:
			row.show()
			row.modulate.a = 1.0
			row.scale = Vector2.ONE
		return
	_loot_sent[index] = true
	row.show()
	if with_sound:
		row.modulate.a = 0.0
		row.scale = Vector2(0.96, 0.96)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(row, "modulate:a", 1.0, NAMEPLATE_FADE_DURATION)
		tween.tween_property(row, "scale", Vector2.ONE, NAMEPLATE_FADE_DURATION)
		_track(tween)
	else:
		row.modulate.a = 1.0
		row.scale = Vector2.ONE
	var run_id := _generation
	loot_shown.emit(_loot_entries[index], index)
	if with_sound and _is_current(run_id):
		sound_requested.emit(&"loot")


func _roll_rewards() -> void:
	_exp_value.text = "0"
	_gold_value.text = "0"
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_method(_set_exp_display, 0.0, float(int(_result_data.get(&"exp", 0))), ROLL_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_gold_display, 0.0, float(int(_result_data.get(&"gold", 0))), ROLL_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_track(tween)


func _set_exp_display(value: float) -> void:
	if is_instance_valid(_exp_value):
		_exp_value.text = str(int(round(value)))


func _set_gold_display(value: float) -> void:
	if is_instance_valid(_gold_value):
		_gold_value.text = str(int(round(value)))


func _set_reward_values_final() -> void:
	if is_instance_valid(_exp_value):
		_exp_value.text = str(int(_result_data.get(&"exp", 0)))
	if is_instance_valid(_gold_value):
		_gold_value.text = str(int(_result_data.get(&"gold", 0)))


func _set_defeat_fade(value: float) -> void:
	if _fade_material != null:
		_fade_material.set_shader_parameter("fade_amount", clampf(value, 0.0, 1.0))


func _finalize_result(kind: StringName) -> void:
	if kind == RESULT_LOSE:
		for index in range(_defeated.size()):
			_emit_collapse(index)
		_set_defeat_fade(1.0)
		return
	for index in range(_survivors.size()):
		_emit_cheer(index)
	for index in range(_loot_rows.size()):
		_reveal_loot(index, false)
	_set_reward_values_final()
	if bool(_result_data.get(&"chapter_end", false)) and is_instance_valid(_chapter_card):
		_chapter_card.show()


func _normalized_loot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_loot: Variant = _result_data.get(&"loot", [])
	if not raw_loot is Array:
		return result
	for raw in raw_loot:
		if raw is Dictionary:
			result.append((raw as Dictionary).duplicate(true))
		else:
			result.append({&"name": String(raw), &"count": 1})
	return result


func _loot_text(entry: Dictionary) -> String:
	var item_name := String(entry.get(&"name", entry.get(&"item_name", entry.get(&"id", entry.get(&"item_id", "战利品")))))
	var count := int(entry.get(&"count", entry.get(&"quantity", entry.get(&"amount", 1))))
	return "%s ×%d" % [item_name, count]


func _nameplate_text(unit: Dictionary) -> String:
	var faction := StringName(unit.get(&"faction", &""))
	var faction_name: String = {
		&"player": "我方",
		&"enemy": "敌方",
		&"ally": "友军",
	}.get(faction, "中立")
	var level := int(unit.get(&"level", 1))
	var profession_name := String(unit.get(&"class_name", unit.get(&"classId", "")))
	var detail := "%s · Lv.%d" % [faction_name, level]
	if not profession_name.is_empty():
		detail += " · " + profession_name
	return "%s\n%s" % [_unit_name(unit), detail]


func _unit_name(unit: Dictionary) -> String:
	return String(unit.get(&"name", unit.get(&"display_name", unit.get(&"id", "未知单位"))))


func _faction_color(unit: Dictionary) -> Color:
	var colors := {
		&"player": Color(0.376, 0.647, 0.980),
		&"enemy": Color(0.973, 0.443, 0.443),
		&"ally": Color(0.290, 0.867, 0.502),
	}
	return colors.get(StringName(unit.get(&"faction", &"")), Color(0.984, 0.749, 0.141))


func _panel_style(background: Color, border: Color, margin: int = 10) -> StyleBoxFlat:
	# 卡片配色随演出内容变化，结构统一走 ui_theme.flat_style（1px 边 / 圆角 5）
	return UIThemeScript.flat_style(background, border, 1, 5, float(margin))
