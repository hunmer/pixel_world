## dialogue_demo.gd — 独立对话演示场景：上方左右立绘+名称牌，下方台词逐字
##
## 与世界 / 战棋完全解耦，直接运行 res://scenes/DialogueDemo.tscn 即可。
## 数据：res://data/dialogue/demo_intro.json（speakers 表 + lines 序列，立绘路径可替换）。
## 交互：鼠标点击 / 触摸 / ui_accept（空格、回车）。
##   打字中 → 补全本句；句毕 → 推进下一句；结束 → 明确提示 + 重播按钮。
## 布局：PortraitRow（标题栏下、DialoguePanel 上）承载左右立绘列与名称牌；
##   名称牌常驻两侧，发言侧用角色色高亮、非发言侧压暗。
## 样式：只读复用 scripts/ui/ui_factory.gd 与 scripts/ui/ui_theme.gd，不改动共享 UI 底层。
extends Control

const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const DATA_PATH := "res://data/dialogue/demo_intro.json"
const TYPE_SPEED := 26.0                      # 逐字速度（字/秒）
const DIM_MODULATE := Color(1, 1, 1, 0.32)    # 非发言者立绘压暗
const FULL_MODULATE := Color(1, 1, 1, 1)
const END_MODULATE := Color(1, 1, 1, 0.7)

enum State { TYPING, WAITING, ENDED }

var _speakers: Dictionary = {}
var _lines: Array = []
var _dialogue_title := ""
var _line_index := -1
var _state: int = State.ENDED
var _typed_chars := 0.0

var _text_label: Label
var _hint_label: Label
var _name_left: Label
var _name_right: Label
var _portrait_left: PanelContainer
var _portrait_right: PanelContainer
var _end_overlay: Control
var _speaker_name := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_data()
	_build_ui()
	_start_dialogue()


## 逐字推进；打满整句自动转入 WAITING。
func _process(delta: float) -> void:
	if _state != State.TYPING:
		return
	var full_len := _text_label.text.length()
	_typed_chars = minf(_typed_chars + delta * TYPE_SPEED, float(full_len))
	_text_label.visible_characters = int(_typed_chars)
	if _typed_chars >= float(full_len):
		_enter_waiting()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	var confirm := false
	if event.is_action_pressed("ui_accept"):
		confirm = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		confirm = true
	elif event is InputEventScreenTouch and event.pressed:
		confirm = true
	if not confirm:
		return
	if _state == State.TYPING:
		_complete_line()
	elif _state == State.WAITING:
		_advance()
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 数据

func _load_data() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("dialogue_demo: 无法打开对话数据 " + DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("dialogue_demo: 对话数据不是合法 JSON 对象")
		return
	_dialogue_title = String(parsed.get("title", "对话演示"))
	_speakers = parsed.get("speakers", {})
	_lines = parsed.get("lines", [])


# ---------------------------------------------------------------- UI 搭建

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.045, 0.065, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var top := UIFactoryScript.label(_dialogue_title, 15, UIThemeScript.TEXT_DIM)
	top.name = "TitleBar"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 12
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(top)

	_portrait_left = _build_portrait_column("PortraitLeft", "hero", true)
	_portrait_right = _build_portrait_column("PortraitRight", "elf", false)

	var panel := PanelContainer.new()
	panel.name = "DialoguePanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 40
	panel.offset_right = -40
	panel.offset_top = -286
	panel.offset_bottom = -24
	panel.add_theme_stylebox_override("panel", UIThemeScript.flat_style(
		UIThemeScript.BG, UIThemeScript.PANEL_BORDER, 2, 10, 18))
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "DialogueBox"
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_text_label = UIFactoryScript.label("", 22, UIThemeScript.TEXT_MAIN)
	_text_label.name = "TextLabel"
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.clip_text = true
	vbox.add_child(_text_label)

	_hint_label = UIFactoryScript.label("", 14, UIThemeScript.TEXT_DIM)
	_hint_label.name = "HintLabel"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(_hint_label)

	_end_overlay = _build_end_overlay()
	add_child(_end_overlay)


## 上方立绘行：标题栏之下、DialoguePanel 之上，满宽自适应高度。
## 每列 = 名称牌 + 称号 + 立绘（立绘可压缩），列间弹性间隔保证窄窗不重叠。
func _build_portrait_column(node_name: String, speaker_id: String, is_left: bool) -> PanelContainer:
	var row := get_node_or_null("PortraitRow") as HBoxContainer
	if row == null:
		row = HBoxContainer.new()
		row.name = "PortraitRow"
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 48
		row.offset_top = 56
		row.offset_right = -48
		row.offset_bottom = -302
		row.add_theme_constant_override("separation", 24)
		add_child(row)

	var column := VBoxContainer.new()
	column.name = node_name + "Column"
	column.custom_minimum_size = Vector2(180, 0)
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if is_left else Control.SIZE_SHRINK_END
	row.add_child(column)
	if not is_left:
		# 右列需要先加入弹性垫片才能靠右
		var spacer := Control.new()
		spacer.name = "MiddleSpacer"
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.move_child(spacer, row.get_child_count() - 2)

	var speaker: Dictionary = _speakers.get(speaker_id, {})
	var name_l := UIFactoryScript.label(String(speaker.get("name", "???")), 22,
		Color(String(speaker.get("color", "#FFFFFF"))))
	name_l.name = "NameLabel"
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_l)
	if is_left:
		_name_left = name_l
	else:
		_name_right = name_l

	var title_l := UIFactoryScript.label(String(speaker.get("title", "")), 13, UIThemeScript.TEXT_DIM)
	title_l.name = "SpeakerTitleLabel"
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title_l)

	var wrap := PanelContainer.new()
	wrap.name = node_name
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_theme_stylebox_override("panel", UIThemeScript.flat_style(
		Color(0.07, 0.10, 0.14, 0.92), UIThemeScript.PANEL_BORDER, 2, 10, 8))

	var tex := TextureRect.new()
	tex.name = "PortraitTexture"
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var portrait_path := String(speaker.get("portrait", ""))
	if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
		tex.texture = load(portrait_path)
	wrap.add_child(tex)
	column.add_child(wrap)
	return wrap


func _build_end_overlay() -> Control:
	var center := CenterContainer.new()
	center.name = "EndOverlay"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.visible = false

	var box := VBoxContainer.new()
	box.name = "EndBox"
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	var end_label := UIFactoryScript.outline_label("—— 对话结束 ——", 34, Color.WHITE, 5)
	end_label.name = "EndLabel"
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(end_label)

	var tip := UIFactoryScript.label("感谢观看这段演示。点击重播可再看一遍。", 16, UIThemeScript.TEXT_DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tip)

	var replay := UIFactoryScript.button("重播对话", _on_replay)
	replay.name = "ReplayButton"
	replay.custom_minimum_size = Vector2(240, 56)
	replay.add_theme_font_size_override("font_size", 22)
	replay.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(replay)

	return center


# ---------------------------------------------------------------- 对话状态机

func _start_dialogue() -> void:
	_line_index = -1
	_end_overlay.hide()
	_advance()


## 推进到下一句（句毕时调用）；越过末句进入结束态。
func _advance() -> void:
	_line_index += 1
	if _line_index >= _lines.size():
		_finish_dialogue()
		return
	var line: Dictionary = _lines[_line_index]
	var speaker_id := String(line.get("speaker", ""))
	var speaker: Dictionary = _speakers.get(speaker_id, {})
	_speaker_name = String(speaker.get("name", "???"))
	_apply_speaker_highlight(speaker_id)
	_typed_chars = 0.0
	_text_label.text = String(line.get("text", ""))
	_text_label.visible_characters = 0
	_apply_speaker_highlight(speaker_id)
	_state = State.TYPING
	_hint_label.text = "点击 / 空格：补全本句"


## 打字中确认：一次性补全本句（不会顺带推进下一句）。
func _complete_line() -> void:
	_typed_chars = float(_text_label.text.length())
	_text_label.visible_characters = -1
	_enter_waiting()


func _enter_waiting() -> void:
	_state = State.WAITING
	_hint_label.text = "点击 / 空格：继续 ▼"


func _finish_dialogue() -> void:
	_state = State.ENDED
	_hint_label.text = ""
	_speaker_name = ""
	_text_label.text = ""
	_portrait_left.modulate = END_MODULATE
	_portrait_right.modulate = END_MODULATE
	_name_left.add_theme_color_override("font_color", UIThemeScript.TEXT_DIM)
	_name_right.add_theme_color_override("font_color", UIThemeScript.TEXT_DIM)
	_end_overlay.show()
	(_end_overlay.get_node("EndBox/ReplayButton") as Button).grab_focus()


func _on_replay() -> void:
	_start_dialogue()


## 发言者一侧立绘全亮 + 名称牌用角色色，另一侧立绘压暗 + 名称灰显。
func _apply_speaker_highlight(speaker_id: String) -> void:
	var speaker: Dictionary = _speakers.get(speaker_id, {})
	var color := Color(String(speaker.get("color", "#FFFFFF")))
	var left_speaking := String(speaker.get("side", "")) == "left"
	_portrait_left.modulate = FULL_MODULATE if left_speaking else DIM_MODULATE
	_portrait_right.modulate = FULL_MODULATE if not left_speaking else DIM_MODULATE
	_name_left.add_theme_color_override("font_color", color if left_speaking else UIThemeScript.TEXT_DIM)
	_name_right.add_theme_color_override("font_color", UIThemeScript.TEXT_DIM if left_speaking else color)


# ---------------------------------------------------------------- 调试钩子（仅供 MCP 运行态验证）

func debug_set_window_size(width: int, height: int) -> void:
	get_window().size = Vector2i(width, height)


func debug_state() -> Dictionary:
	return {
		"state": _state,
		"line_index": _line_index,
		"typed_chars": _typed_chars,
		"full_len": _text_label.text.length(),
		"name": _speaker_name,
	}
