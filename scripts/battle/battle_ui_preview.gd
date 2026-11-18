## battle/battle_ui_preview.gd — 使用组件库呈现真实攻守双方与技能预测。
extends RefCounted

const Tokens = preload("res://ui/theme/component_theme.gd")
const Palette = preload("res://scripts/ui/ui_theme.gd")
const Factory = preload("res://scripts/ui/ui_factory.gd")
const FacingRules = preload("res://scripts/systems/facing_rules.gd")
const Card = preload("res://ui/components/pixel_panel.tscn")
const VBox = preload("res://ui/components/pixel_v_box.gd")
const HBox = preload("res://ui/components/pixel_h_box.gd")
const Margin = preload("res://ui/components/pixel_margin.gd")
const Bar = preload("res://ui/components/pixel_progress_bar.gd")

var _ui: CanvasLayer

func setup(ui: CanvasLayer) -> void:
	_ui = ui

func show_combat(attacker: Dictionary, defender: Dictionary, prev: Dictionary) -> void:
	var slot: Container = _shell("战斗预测", "BattlePreviewCard")
	var row: HBoxContainer = HBox.new()
	row.name = "BattlePreviewGrid"
	slot.add_child(row)
	var attack_column: VBoxContainer = _combatant(attacker, "攻方", "BattlePreviewAttacker")
	row.add_child(attack_column)
	_line(attack_column, "命中 %d%%" % int(prev.atkHit))
	_line(attack_column, "伤害 %d%s" % [int(prev.atkDmg), " ×2" if prev.doubleAttack else ""])
	if bool(prev.get(&"atkBackstab", false)):
		_line(attack_column, "背击 · 伤害 ×%s" % String.num(FacingRules.BACKSTAB_DAMAGE_MULTIPLIER, 2), Palette.ACCENT)
	_line(attack_column, "必杀 %d%%" % int(prev.atkCrit))
	var defend_column: VBoxContainer = _combatant(defender, "守方", "BattlePreviewDefender")
	row.add_child(defend_column)
	# 使用结算内核同一射程判定；法杖不造成反击伤害。
	var can_counter: bool = CombatSystem._in_range(attacker, defender) and defender.weapon.type != &"staff"
	if can_counter:
		_line(defend_column, "反击命中 %d%%" % int(prev.defHit))
		_line(defend_column, "反击伤害 %d" % int(prev.defDmg))
	else:
		_line(defend_column, "无法反击", Palette.TEXT_DIM)
	var triangle: Dictionary = WeaponData.triangle_modifier(attacker.weapon.type, defender.weapon.type)
	if int(triangle.get(&"hit", 0)) != 0 or int(triangle.get(&"damage", 0)) != 0:
		_line(slot, "武器克制 · 命中 %+d%% / 伤害 %+d" % [int(triangle.hit), int(triangle.damage)], Palette.ACCENT)
	if int(prev.atkDmg) >= int(defender.hp):
		_line(slot, "命中可击倒目标", Palette.ACCENT)
	elif bool(prev.doubleAttack) and int(prev.atkDmg) * 2 >= int(defender.hp):
		_line(slot, "两次命中可击倒目标", Palette.ACCENT)
	if can_counter and int(prev.defDmg) >= int(attacker.hp):
		_line(slot, "⚠ 反击命中可能使攻方倒下", Palette.ERROR)

func show_skill(caster: Dictionary, target: Dictionary, skill_id: StringName) -> void:
	var skill: Dictionary = SkillData.get_skill(skill_id)
	var preview: Dictionary = SkillSystem.preview(caster, target, skill_id)
	var slot: Container = _shell("技能预测", "BattleSkillPreviewCard")
	_line(slot, "%s → %s" % [String(caster.name), String(target.name)])
	_line(slot, "%s · MP %d" % [String(skill.get(&"name", skill_id)), int(skill.get(&"mpCost", 0))], Palette.ACCENT)
	var row: HBoxContainer = HBox.new()
	slot.add_child(row)
	row.add_child(_combatant(caster, "施放者", "SkillPreviewCaster"))
	row.add_child(_combatant(target, "目标", "SkillPreviewTarget"))
	if preview.has(&"desc"):
		_line(slot, String(preview[&"desc"]))
	if preview.has(&"hit"):
		_line(slot, "命中 %d%%" % int(preview[&"hit"]))

func _shell(title: String, node_name: String) -> Container:
	_ui.close_preview()
	var margin: MarginContainer = Margin.new()
	margin.name = "BattlePreviewLayout"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.call("set_margin_all", Tokens.SPACE_MD)
	margin.set("margin_right_v", int(_ui.SIDEBAR_WIDTH) + Tokens.SPACE_MD)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.preview_container.add_child(margin)
	var row: HBoxContainer = HBox.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var card: PanelContainer = Card.instantiate()
	card.name = node_name
	card.set("title", title)
	card.custom_minimum_size.x = Tokens.SPACE_MD * 20
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(card)
	return card.call("get_content_slot") as Container

func _combatant(unit: Dictionary, role: String, node_name: String) -> VBoxContainer:
	var column: VBoxContainer = VBox.new()
	column.name = node_name
	column.set("gap", Tokens.SPACE_XS)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.custom_minimum_size.x = Tokens.SPACE_MD * 8
	_line(column, role, Palette.TEXT_DIM)
	_line(column, String(unit.name))
	var bar: ProgressBar = Bar.new()
	bar.name = node_name + "Hp"
	bar.max_value = maxi(1, int(unit.stats.hp))
	bar.value = int(unit.hp)
	bar.show_percentage = false
	column.add_child(bar)
	_line(column, "HP %d/%d" % [int(unit.hp), int(unit.stats.hp)])
	_line(column, String(unit.weapon.get(&"name", "")), Palette.TEXT_DIM)
	return column

func _line(parent: Node, text: String, color: Color = Palette.TEXT_MAIN) -> Label:
	var label: Label = Factory.label(text, Tokens.FONT_BODY, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label
