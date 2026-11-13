## game_entry.gd — 新默认入口场景 Game.tscn
## 职责：
##   - 冷启动（进程首次打开）：按 GameSession 决策自动续玩最近战旗，直接进战斗
##   - 从战斗/编辑器返回（in_session=true）：显示战场列表（继续/进入/重置）+ 附属入口
## 不做任何世界生态生成 —— 任务要求进入游戏默认打开的是战旗，不是随机地图。

extends Control

const GAME_SCENE := "res://scenes/Game.tscn"
const BATTLE_SCENE := "res://scenes/Battle.tscn"
const EDITOR_SCENE := "res://scenes/MapEditor.tscn"
const WORLD_SCENE := "res://main.tscn"

var _notice_label: Label
var _list: VBoxContainer


func _ready() -> void:
	# 场景树仍在装配 _ready 链，change_scene 必须推迟到帧末，否则引擎报
	# "Parent node is busy adding/removing children"。
	call_deferred("_start")


func _start() -> void:
	if not GameSession.in_session:
		var entry: Dictionary = GameSession.prepare_entry()
		if String(entry.get("mode", "list")) != "list":
			_enter_battle(entry)
			return
		_build_list(String(entry.get("notice", "")))
	else:
		_build_list("")


# ============================================================
# 进入战斗
# ============================================================

## 用 GameSession 的决策结果切换到 Battle 场景（resume 带 save_state）。
func _enter_battle(entry: Dictionary) -> void:
	var chapter: Dictionary = entry.get("chapter", {})
	if chapter.is_empty():
		return
	GameSession.open_battle(
		String(entry.get("identity", "")), String(entry.get("kind", "")),
		String(entry.get("source", "")),
		entry.get("initial", chapter))
	var args := {
		"chapter": chapter,
		"return_to": GAME_SCENE,
		"hosting": bool(entry.get("hosting", false)),
		"save_identity": String(entry.get("identity", "")),
	}
	var state: Dictionary = entry.get("state", {})
	if not state.is_empty():
		args["save_state"] = state
	var notice := String(entry.get("notice", ""))
	if notice != "":
		args["save_notice"] = notice
	SceneArgs.battle_args = args
	get_tree().change_scene_to_file(BATTLE_SCENE)


# ============================================================
# 列表 UI
# ============================================================

func _build_list(notice: String) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "战旗 · 选择战场"
	title.add_theme_font_size_override("font_size", 26)
	title.position = Vector2(24, 16)
	add_child(title)

	if notice != "":
		_notice_label = Label.new()
		_notice_label.text = notice.strip_edges()
		_notice_label.add_theme_font_size_override("font_size", 13)
		_notice_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
		_notice_label.position = Vector2(24, 58)
		_notice_label.size = Vector2(760, 44)
		_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_notice_label)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(24, 108)
	scroll.size = Vector2(560, 470)
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	for item in GameSession.list_battlefields_checked():
		_add_row(item)

	_add_side_buttons()


func _add_row(item: Dictionary) -> void:
	var info: Dictionary = item["info"]
	var save: Dictionary = item["save"]
	var row := PanelContainer.new()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)

	var name := Label.new()
	name.text = String(info.get("name", info.get("file", "?")))
	name.custom_minimum_size = Vector2(170, 0)
	hb.add_child(name)

	var st := Label.new()
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.text = _save_summary(save)
	st.add_theme_font_size_override("font_size", 12)
	st.add_theme_color_override("font_color", Color(0.6, 0.75, 0.6))
	hb.add_child(st)

	var enter := Button.new()
	enter.text = "进入"
	enter.pressed.connect(_on_enter.bind(item))
	hb.add_child(enter)

	if bool(save.get("exists", false)):
		var reset := Button.new()
		reset.text = "重置"
		reset.pressed.connect(_on_reset.bind(item))
		hb.add_child(reset)

	row.add_child(hb)
	_list.add_child(row)


func _save_summary(save: Dictionary) -> String:
	if not bool(save.get("exists", false)):
		return "无记录"
	if bool(save.get("unknown_version", false)):
		return "新版本存档"
	var result := String(save.get("result", ""))
	if result == "win":
		return "已通关（胜利）"
	if result == "lose":
		return "已失败"
	var phase := "敌方回合" if String(save.get("phase", "player")) == "enemy" else "玩家回合"
	return "第 %d 轮 · %s" % [int(save.get("turn_number", 1)), phase]


func _add_side_buttons() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(620, 108)
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var latest := Button.new()
	latest.text = "↻ 继续最近战旗"
	latest.pressed.connect(_on_continue_latest)
	box.add_child(latest)

	var editor := Button.new()
	editor.text = "🗺 战场编辑器"
	editor.pressed.connect(_on_open_editor)
	box.add_child(editor)

	var world := Button.new()
	world.text = "🌍 生态世界"
	world.pressed.connect(_on_open_world)
	box.add_child(world)


# ============================================================
# 按钮
# ============================================================

func _on_enter(item: Dictionary) -> void:
	var entry: Dictionary = GameSession.prepare_entry_for(String(item["identity"]))
	if String(entry.get("mode", "list")) == "list":
		_refresh(String(entry.get("notice", "")))
		return
	_enter_battle(entry)


func _on_continue_latest() -> void:
	var entry: Dictionary = GameSession.prepare_entry()
	if String(entry.get("mode", "list")) == "list":
		_refresh(String(entry.get("notice", "")))
		return
	_enter_battle(entry)


func _on_reset(item: Dictionary) -> void:
	var res: Dictionary = GameSession.reset_battlefield(String(item["identity"]))
	var notice := ""
	if res.get("ok", false):
		notice = "已重置《%s》。" % String(item["info"].get("name", ""))
	else:
		notice = "重置失败：%s" % String(res.get("error", ""))
	_refresh(notice)


func _on_open_editor() -> void:
	SceneArgs.map_editor_return_to = GAME_SCENE
	get_tree().change_scene_to_file(EDITOR_SCENE)


func _on_open_world() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


func _refresh(notice: String) -> void:
	for c in get_children():
		c.queue_free()
	_build_list(notice)
