## scripts/scenes/campaign_levels.gd — 关卡列表屏（世界地图 · 顺序挑战）
##
## data/campaign.json 的关卡按顺序线性解锁、可重复挑战。每张关卡卡展示
## 状态（未解锁/可挑战/已通关）与奖励预览；「挑战」先经确认弹窗再向
## campaign_main 发 request_battle。
extends Control

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const PixelPanelScene = preload("res://ui/components/pixel_panel.tscn")
const PixelMarginScript = preload("res://ui/components/pixel_margin.gd")
const PixelVBoxScript = preload("res://ui/components/pixel_v_box.gd")
const PixelHBoxScript = preload("res://ui/components/pixel_h_box.gd")
const PixelScrollScript = preload("res://ui/components/pixel_scroll.gd")
const PixelGridScript = preload("res://ui/components/pixel_grid.gd")
const CampaignFormatScript = preload("res://scripts/scenes/campaign_format.gd")

var _main: Control
var _notice: Label
var _grid: GridContainer
var _back_btn: Button
var _levels: Array = []
var _first_open_btn: Button


func setup(main_ref: Control) -> void:
	_main = main_ref


func _ready() -> void:
	_build()
	visible = false


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var page := PixelMarginScript.new()
	page.name = "PageMargin"
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)

	var box := PixelVBoxScript.new()
	box.name = "PageBox"
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(box)

	var header := PixelHBoxScript.new()
	header.name = "HeaderRow"
	box.add_child(header)

	_back_btn = _make_action_button("← 返回基地", 1, _on_back)
	_back_btn.name = "BackBtn"
	header.add_child(_back_btn)

	var title: Label = UIFactoryScript.label(
		"世界地图 · 顺序挑战", ComponentThemeScript.FONT_TITLE, UIThemeScript.TEXT_MAIN
	)
	title.name = "PageTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(title)

	var caption: Label = UIFactoryScript.label(
		"按顺序解锁：通关前一关即开放下一关，已通关的关卡可重复挑战获取重复奖励。",
		ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM
	)
	caption.name = "PageCaption"
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(caption)

	_notice = UIFactoryScript.label(
		"", ComponentThemeScript.FONT_BODY, UIThemeScript.ERROR
	)
	_notice.name = "SessionNotice"
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.visible = false
	box.add_child(_notice)

	var scroll := PixelScrollScript.new()
	scroll.name = "LevelScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)

	_grid = PixelGridScript.new()
	_grid.name = "LevelGrid"
	_grid.columns = 2
	scroll.add_child(_grid)


func _make_action_button(text: String, semantic: int, handler: Callable) -> Button:
	var button: Button = UIFactoryScript.button(text, Callable(), "", false)
	button.set("semantic", clampi(semantic, 0, 2))
	button.pressed.connect(handler)
	return button


func on_shown() -> void:
	refresh()
	if not bool(_main.call("modal_open")):
		if CampaignFormatScript.can_grab_focus(_first_open_btn):
			_first_open_btn.grab_focus()
		elif CampaignFormatScript.can_grab_focus(_back_btn):
			_back_btn.grab_focus()


func on_data_changed() -> void:
	if visible:
		refresh()


func refresh() -> void:
	var session: Node = _main.call("session")
	if session == null:
		_notice.text = "CampaignSession 未注册：无法读取关卡列表。"
		_notice.visible = true
	else:
		_notice.visible = false
	_levels = CampaignFormatScript.call_array(session, "list_levels")
	_rebuild_grid()


func _rebuild_grid() -> void:
	_first_open_btn = null
	CampaignFormatScript.detach_children(_grid)
	var index := 0
	for entry: Variant in _levels:
		var level: Dictionary = entry if entry is Dictionary else {}
		_grid.add_child(_make_level_card(level, index))
		index += 1


func _make_level_card(level: Dictionary, index: int) -> PanelContainer:
	var id := CampaignFormatScript.as_text(level.get("id", ""), "level_%d" % index)
	var display_name := CampaignFormatScript.as_text(level.get("name", ""), id)
	var unlocked := bool(level.get("unlocked", false))
	var completed := bool(level.get("completed", false))
	var reward_gold := CampaignFormatScript.as_int(level.get("reward_gold", 0), 0)
	var reward_items_line := CampaignFormatScript.items_line(level.get("reward_items", []))
	var repeat_gold := CampaignFormatScript.as_int(level.get("reward_gold_repeat", 0), 0)
	var repeat_items_line := CampaignFormatScript.items_line(level.get("reward_items_repeat", []))

	var card: PanelContainer = PixelPanelScene.instantiate() as PanelContainer
	card.name = "LevelCard_%d" % index
	card.set("title", "%d. %s" % [index + 1, display_name])

	var slot: Container = card.call("get_content_slot") as Container
	var body := PixelVBoxScript.new()
	slot.add_child(body)

	var status: Label
	if not unlocked:
		status = UIFactoryScript.label(
			"未解锁 · 先通关前一关", ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_DIM
		)
	elif completed:
		status = UIFactoryScript.label(
			"已通关 · 可重复挑战", ComponentThemeScript.FONT_BODY, UIThemeScript.ACCENT
		)
	else:
		status = UIFactoryScript.label(
			"可挑战", ComponentThemeScript.FONT_BODY, UIThemeScript.ACCENT
		)
	status.name = "StatusLabel_%d" % index
	body.add_child(status)

	# 奖励前置展示实际数值：已通关只看重复奖励；未通关展示首胜+重复两套。
	var reward: Label
	if completed:
		reward = UIFactoryScript.label(
			"奖励：%d 金币 · %s" % [repeat_gold, repeat_items_line],
			ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM
		)
	else:
		reward = UIFactoryScript.label(
			"首胜：%d 金币 · %s" % [reward_gold, reward_items_line],
			ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM
		)
	reward.name = "RewardLabel_%d" % index
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(reward)

	if not completed:
		var repeat_hint: Label = UIFactoryScript.label(
			"重复通关：%d 金币 · %s" % [repeat_gold, repeat_items_line],
			ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM
		)
		repeat_hint.name = "RepeatLabel_%d" % index
		repeat_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(repeat_hint)

	var row := PixelHBoxScript.new()
	body.add_child(row)

	var challenge_btn := _make_action_button(
		"挑战", 0,
		_on_challenge.bind(id, display_name, completed, reward_gold, reward_items_line, repeat_gold, repeat_items_line)
	)
	challenge_btn.name = "ChallengeBtn_%d" % index
	challenge_btn.disabled = not unlocked
	if _first_open_btn == null and not challenge_btn.disabled:
		_first_open_btn = challenge_btn
	row.add_child(challenge_btn)
	return card


func _on_challenge(
	id: String,
	display_name: String,
	completed: bool,
	reward_gold: int,
	reward_items_line: String,
	repeat_gold: int,
	repeat_items_line: String
) -> void:
	var message := ""
	if completed:
		message = "关卡：%s\n本次为重复挑战：胜利得 %d 金币 · %s。" % [
			display_name, repeat_gold, repeat_items_line
		]
	else:
		message = (
			"关卡：%s\n首胜奖励：%d 金币 · %s\n重复通关：%d 金币 · %s"
			% [display_name, reward_gold, reward_items_line, repeat_gold, repeat_items_line]
		)
	var modal: Control = _main.call(
		"open_modal",
		"出征确认",
		message,
		[
			{"text": "出征", "semantic": 0, "id": "go", "focus": true},
			{"text": "取消", "semantic": 1, "id": "cancel"},
		]
	)
	modal.connect("chosen", Callable(self, "_on_challenge_chosen").bind(id))


func _on_challenge_chosen(action_id: String, id: String) -> void:
	if action_id != "go":
		return
	_main.call("request_battle", id)


func _on_back() -> void:
	_main.call("go_hub")
