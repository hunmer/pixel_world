## battle/battle_ui_unit_detail.gd — 真实单位的只读属性、技能与背包卡片。
class_name BattleUiUnitDetail
extends RefCounted

const Widgets = preload("res://scripts/battle/battle_ui_status_widgets.gd")
const Tokens = preload("res://ui/theme/component_theme.gd")
const Palette = preload("res://scripts/ui/ui_theme.gd")

var _ui = null
var _panel: Control = null
const FACTION_NAME := {player = "我方", enemy = "敌方", ally = "友军", other = "中立"}

func setup(p_ui) -> void:
	_ui = p_ui

## 详情的宽高由视口锚点限定，内容只纵向滚动，关闭按钮固定在滚动区之外。
func open_unit_detail(u: Dictionary) -> void:
	close_unit_detail()
	var frame := Widgets.Margin.new()
	frame.name = "UnitDetailPanel"
	frame.theme = Tokens.create()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.preview_container.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 中间半幅作为详情舞台：1024 档可容纳属性网格，1920 档随视口扩展。
	frame.anchor_left = 0.25
	frame.anchor_right = 0.75
	frame.anchor_top = 0.08
	frame.anchor_bottom = 0.92
	var shell: PanelContainer = Widgets.Card.instantiate()
	shell.name = "UnitDetailCard"
	shell.custom_minimum_size = Vector2.ZERO
	shell.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.add_child(shell)
	var body: VBoxContainer = shell.call("get_content_slot")
	body.add_theme_constant_override("separation", Tokens.SPACE_SM)
	var heading := Widgets.label("%s · %s" % [String(FACTION_NAME.get(u.get(&"faction", &""), "单位")), String(u.get(&"name", ""))])
	heading.name = "UnitDetailTitle"
	heading.add_theme_font_size_override("font_size", Tokens.FONT_TITLE)
	body.add_child(heading)
	body.add_child(Widgets.label("%s · Lv.%d · %s" % [ProfessionData.profession_name(u.get(&"classId", &"")), int(u.get(&"level", 1)), "已行动" if bool(u.get(&"hasActed", false)) else "未行动"], true, Palette.TEXT_DIM))
	var scroll := Widgets.Scroll.new()
	scroll.name = "UnitDetailScroll"
	body.add_child(scroll)
	var column := Widgets.Column.new()
	column.name = "UnitDetailContent"
	column.gap = Tokens.SPACE_SM
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var stats: Dictionary = u.get(&"stats", {})
	var resources := Widgets.card(column, "状态", "UnitResourcesCard")
	Widgets.bar(resources, "UnitDetailHp", "HP", float(u.get(&"hp", 0)), float(stats.get(&"hp", 0)))
	Widgets.bar(resources, "UnitDetailMp", "MP", float(u.get(&"mp", 0)), float(stats.get(&"mp", 0)))
	Widgets.bar(resources, "UnitDetailExp", "EXP", float(u.get(&"exp", 0)), float(WeaponData.exp_to_next(int(u.get(&"level", 1)))))
	var grid := Widgets.Grid.new()
	grid.name = "UnitDetailStats"
	grid.columns = 3
	grid.h_gap = Tokens.SPACE_SM
	grid.v_gap = Tokens.SPACE_SM
	resources.add_child(grid)
	for pair: Array in [["力", &"str"], ["魔", &"mag"], ["技", &"skl"], ["速", &"spd"], ["防", &"def"], ["魔防", &"res"], ["运", &"luk"], ["移动", &"mov"]]:
		grid.add_child(Widgets.label("%s %d" % [pair[0], int(stats.get(pair[1], 0))], true))
	resources.add_child(Widgets.label("攻击射程 %s" % str(ProfessionData.unit_attack_range(u)), true))
	var weapon = WeaponData.unit_weapon(u)
	if weapon is Dictionary and not weapon.is_empty():
		resources.add_child(Widgets.label("武器 · %s" % String(weapon.get(&"name", weapon.get(&"id", ""))), true, Palette.ACCENT))
	for item_id in u.get(&"equipped", []):
		var definition: Dictionary = ItemData.get_item(StringName(item_id))
		resources.add_child(Widgets.label("已装备 · %s · %s" % [ItemData.item_name(StringName(item_id)), String(definition.get(&"desc", ""))], true, Palette.ACCENT))
	_build_skills(column, u)
	_build_bag(column, u)
	_build_status(column, u)
	body.add_child(Widgets.button("关闭 (ESC)", close_unit_detail))
	_panel = frame

func _build_skills(parent: Node, u: Dictionary) -> void:
	var skills: Array = u.get(&"skills", [])
	var slot := Widgets.card(parent, "技能 · %d" % skills.size(), "UnitSkillsCard")
	if skills.is_empty():
		slot.add_child(Widgets.label("未习得技能", true, Palette.TEXT_DIM))
		return
	var cooldowns: Dictionary = u.get(&"skillCooldowns", {})
	for sid in skills:
		var definition: Dictionary = SkillData.get_skill(StringName(sid))
		var skill := Widgets.card(slot, SkillData.skill_name(StringName(sid)), "Skill_" + String(sid), SkillData.skill_icon(StringName(sid)))
		var remaining := int(cooldowns.get(sid, 0))
		var cost := int(definition.get(&"mpCost", 0))
		var availability := "冷却 %d 回合" % remaining if remaining > 0 else "MP 不足" if int(u.get(&"mp", 0)) < cost else "就绪"
		skill.add_child(Widgets.label("MP %d · 射程 %s · %s" % [cost, str(definition.get(&"range", [])), availability], true, Palette.TEXT_DIM))
		skill.add_child(Widgets.label(String(definition.get(&"desc", "")), true))

## 背包只展示运行时条目，不补画廊演示空槽，也不提供绕过行动流程的使用按钮。
func _build_bag(parent: Node, u: Dictionary) -> void:
	var items: Array = u.get(&"items", [])
	var bag := Widgets.card(parent, "背包 · %d 件" % items.size(), "BattleBagCard")
	if items.is_empty():
		bag.add_child(Widgets.label("背包为空", true, Palette.TEXT_DIM))
		return
	for index in items.size():
		var entry: Dictionary = items[index]
		var item_id := StringName(entry.get(&"id", &""))
		var definition: Dictionary = ItemData.get_item(item_id)
		var item := Widgets.card(bag, ItemData.item_name(item_id), "BattleBagSlot%d" % index)
		item.add_child(Widgets.label("剩余 %d/%d" % [int(entry.get(&"uses", 0)), int(definition.get(&"uses", 0))], true, Palette.TEXT_DIM))
		item.add_child(Widgets.label(String(definition.get(&"desc", "")), true))
		if definition.has(&"range"):
			item.add_child(Widgets.label("射程 %s" % str(definition[&"range"]), true, Palette.TEXT_DIM))

func _build_status(parent: Node, u: Dictionary) -> void:
	var buffs: Array = u.get(&"buffs", [])
	if not buffs.is_empty():
		var slot := Widgets.card(parent, "临时状态", "UnitBuffsCard")
		for buff: Dictionary in buffs:
			slot.add_child(Widgets.label("%s %+d · 剩余 %d 回合" % [String(buff.get(&"label", buff.get(&"stat", ""))), int(buff.get(&"value", 0)), int(buff.get(&"turns", 0))], true))
	if _ui.grid != null:
		var cell: Vector2i = u.get(&"position", Vector2i.ZERO)
		var tile: Dictionary = _ui.grid.tile_at(cell.x, cell.y)
		if not tile.is_empty():
			var terrain := Widgets.card(parent, "地形", "UnitTerrainCard")
			terrain.add_child(Widgets.label("%s · 防御 +%d · 回避 +%d" % [String(tile.get("type", "")), int(tile.get("def_bonus", 0)), int(tile.get("avoid_bonus", 0))], true))

func close_unit_detail() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

func is_unit_detail_open() -> bool:
	return is_instance_valid(_panel)
