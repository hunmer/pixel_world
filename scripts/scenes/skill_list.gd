## scenes/skill_list.gd — 技能图鉴：从技能配置生成列表，选择后查看图标与战斗信息。
## 可独立运行 SkillList.tscn；返回按钮与 ESC 回到标题菜单。
extends Control

const Tokens = preload("res://ui/theme/component_theme.gd")
const Palette = preload("res://scripts/ui/ui_theme.gd")
const PixelButtonScript = preload("res://ui/components/pixel_button.gd")
const PixelVBoxScript = preload("res://ui/components/pixel_v_box.gd")
const PixelHBoxScript = preload("res://ui/components/pixel_h_box.gd")
const PixelGridScript = preload("res://ui/components/pixel_grid.gd")
const PixelMarginScript = preload("res://ui/components/pixel_margin.gd")
const PixelScrollScript = preload("res://ui/components/pixel_scroll.gd")
const PixelIconScript = preload("res://ui/components/pixel_icon.gd")
const PanelScene = preload("res://ui/components/pixel_panel.tscn")

const TYPE_NAMES: Dictionary = {&"damage": "单体伤害", &"aoe": "范围伤害", &"heal": "治疗", &"buff": "增益", &"debuff": "减益"}
const ELEMENT_NAMES: Dictionary = {&"physical": "物理", &"fire": "火", &"ice": "冰", &"holy": "神圣", &"dark": "暗", &"wind": "风"}
const TARGET_NAMES: Dictionary = {&"self": "自身", &"enemy": "单个敌人", &"ally": "单个友方（不含自身）", &"aoe_enemy": "射程内所有敌人", &"aoe_ally": "射程内所有友方"}
const STAT_NAMES: Dictionary = {&"str": "力量", &"mag": "魔力", &"def": "防御", &"res": "魔抗", &"spd": "速度", &"skl": "技巧", &"luk": "幸运"}

var selected_skill_id: StringName = &""
var _buttons: Dictionary = {}
var _group: ButtonGroup = ButtonGroup.new()
var _detail_icon: TextureRect
var _detail_title: Label
var _detail_type: Label
var _description: Label
var _fields: GridContainer
var _effect: Label
var _detail_scroll: ScrollContainer


func _ready() -> void:
	theme = Tokens.create()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_ui()
	if not SkillData.SKILL_LIST.is_empty():
		var first: StringName = SkillData.SKILL_LIST[0][&"id"]
		select_skill(first)
		(_buttons[first] as Button).grab_focus()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Palette.BG
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := PixelMarginScript.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var page := PixelVBoxScript.new()
	margin.add_child(page)
	var header := PixelHBoxScript.new()
	page.add_child(header)
	var title := _label("技能图鉴", Tokens.FONT_DISPLAY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := PixelButtonScript.new()
	back.name = "BackButton"
	back.text = "返回菜单"
	back.semantic = 1
	back.pressed.connect(_go_back)
	header.add_child(back)
	page.add_child(_label("全部技能 · %d" % SkillData.SKILL_LIST.size(), Tokens.FONT_BODY, Palette.TEXT_DIM))
	var body := PixelHBoxScript.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	var list_scroll := PixelScrollScript.new()
	list_scroll.name = "SkillScroll"
	# 左栏宽度取正文 token 的 20 倍，剩余空间交给详情卡片。
	list_scroll.custom_minimum_size.x = Tokens.FONT_BODY * 20
	list_scroll.size_flags_horizontal = Control.SIZE_FILL
	body.add_child(list_scroll)
	var list := PixelVBoxScript.new()
	list.name = "SkillButtons"
	list.gap = Tokens.SPACE_SM
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(list)
	for skill: Dictionary in SkillData.SKILL_LIST:
		var sid: StringName = skill[&"id"]
		var button := PixelButtonScript.new()
		button.name = String(sid)
		button.text = String(skill[&"name"])
		button.icon = SkillData.skill_icon(sid)
		button.expand_icon = true
		button.icon_size = Tokens.SPACE_LG + Tokens.SPACE_SM
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = _group
		button.semantic = 1
		button.pressed.connect(select_skill.bind(sid))
		button.focus_entered.connect(select_skill.bind(sid))
		list.add_child(button)
		_buttons[sid] = button
	var panel := PanelScene.instantiate() as PanelContainer
	panel.name = "SkillDetail"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	_detail_scroll = PixelScrollScript.new()
	_detail_scroll.name = "DetailScroll"
	panel.call("get_content_slot").add_child(_detail_scroll)
	var detail := PixelVBoxScript.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.add_child(detail)
	var detail_header := PixelHBoxScript.new()
	detail.add_child(detail_header)
	_detail_icon = PixelIconScript.new()
	_detail_icon.name = "SkillIcon"
	_detail_icon.set("icon_size", Tokens.SPACE_MD * 4)
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_header.add_child(_detail_icon)
	var names := PixelVBoxScript.new()
	names.gap = Tokens.SPACE_XS
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_header.add_child(names)
	_detail_title = _label("", Tokens.FONT_TITLE)
	_detail_title.name = "SkillName"
	names.add_child(_detail_title)
	_detail_type = _label("", Tokens.FONT_BODY, Palette.ACCENT)
	names.add_child(_detail_type)
	_description = _label("")
	_description.name = "SkillDescription"
	detail.add_child(_description)
	_fields = PixelGridScript.new()
	_fields.name = "Stats"
	_fields.columns = 2
	detail.add_child(_fields)
	_effect = _label("")
	_effect.name = "Effect"
	detail.add_child(_effect)


## 无效 ID 不采用 SkillData 的默认技能回退，保留当前选择。
func select_skill(skill_id: StringName) -> bool:
	if not _buttons.has(skill_id):
		return false
	selected_skill_id = skill_id
	var skill: Dictionary = SkillData.get_skill(skill_id)
	(_buttons[skill_id] as Button).set_pressed_no_signal(true)
	_detail_icon.texture = SkillData.skill_icon(skill_id)
	_detail_title.text = String(skill[&"name"])
	_detail_type.text = "%s · %s" % [TYPE_NAMES.get(skill[&"type"], skill[&"type"]), ELEMENT_NAMES.get(skill[&"element"], skill[&"element"])]
	_description.text = String(skill[&"desc"])
	for child: Node in _fields.get_children():
		_fields.remove_child(child)
		child.queue_free()
	_add_field("MP 消耗", "%d MP" % int(skill[&"mpCost"]))
	_add_field("冷却", "%d 回合" % int(skill[&"cooldown"]) if int(skill[&"cooldown"]) > 0 else "无冷却")
	var reach: Array = skill[&"range"]
	_add_field("射程", "%d–%d 格" % [int(reach[0]), int(reach[1])])
	_add_field("目标", String(TARGET_NAMES.get(skill[&"targetType"], skill[&"targetType"])))
	match skill[&"type"]:
		&"buff", &"debuff":
			_effect.text = "%s %+d，持续 %d 回合。" % [STAT_NAMES.get(skill[&"stat"], skill[&"stat"]), int(skill[&"buffValue"]), int(skill[&"buffTurns"])]
		&"heal":
			_add_field("基础治疗", str(int(skill[&"power"])))
			_effect.text = "实际恢复量受施法者魔力加成，且不会超过目标生命上限。"
		_:
			_add_field("技能威力", str(int(skill[&"power"])))
			_add_field("基础命中", "%d%%" % int(skill[&"hitBonus"]))
			_effect.text = "实际伤害与命中率受施法者和目标属性影响。"
	_detail_scroll.scroll_vertical = 0
	return true


func _add_field(caption: String, value: String) -> void:
	_fields.add_child(_label(caption, Tokens.FONT_BODY, Palette.TEXT_DIM))
	_fields.add_child(_label(value))


func _label(text: String, font_size: int = Tokens.FONT_BODY, color: Color = Palette.TEXT_MAIN) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


func _go_back() -> void:
	get_tree().change_scene_to_file("res://scenes/Title.tscn")
