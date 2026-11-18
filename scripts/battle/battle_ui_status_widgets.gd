## battle_ui_status_widgets.gd — 战斗 HUD 与单位详情共用的只读组件工厂。
extends RefCounted

const Tokens = preload("res://ui/theme/component_theme.gd")
const Palette = preload("res://scripts/ui/ui_theme.gd")
const Factory = preload("res://scripts/ui/ui_factory.gd")
const Column = preload("res://ui/components/pixel_v_box.gd")
const Row = preload("res://ui/components/pixel_h_box.gd")
const Grid = preload("res://ui/components/pixel_grid.gd")
const Margin = preload("res://ui/components/pixel_margin.gd")
const Scroll = preload("res://ui/components/pixel_scroll.gd")
const ButtonScript = preload("res://ui/components/pixel_button.gd")
const Bar = preload("res://ui/components/pixel_progress_bar.gd")
const Card = preload("res://ui/components/pixel_panel.tscn")

static func label(text: String, caption := false, color := Palette.TEXT_MAIN) -> Label:
	var result := Factory.label(text, Tokens.FONT_CAPTION if caption else Tokens.FONT_BODY, color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result

static func card(parent: Node, title: String, node_name: String) -> VBoxContainer:
	var panel: PanelContainer = Card.instantiate()
	panel.name = node_name
	panel.custom_minimum_size = Vector2.ZERO
	panel.set("title", title)
	var heading: Label = panel.get_node("VBox/Header/TitleBox/Title")
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var slot: VBoxContainer = panel.call("get_content_slot")
	slot.add_theme_constant_override("separation", Tokens.SPACE_SM)
	return slot

static func button(text: String, callback: Callable, primary := false) -> Button:
	var result: Button = ButtonScript.new()
	result.text = text
	result.set("semantic", 0 if primary else 1)
	# 战斗入口已通过 Sfx 自动挂载按钮音效，组件不重复播放。
	result.set("hover_sfx_enabled", false)
	result.set("click_sfx_enabled", false)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if callback.is_valid():
		result.pressed.connect(callback)
	return result

static func bar(parent: Node, node_name: String, stat: String, current: float, maximum: float) -> ProgressBar:
	var column := Column.new()
	column.gap = Tokens.SPACE_XS
	parent.add_child(column)
	column.add_child(label("%s %d/%d" % [stat, int(current), int(maximum)], true))
	var progress: ProgressBar = Bar.new()
	progress.name = node_name
	progress.max_value = maxf(maximum, 1.0)
	progress.value = clampf(current, 0.0, maximum) if maximum > 0.0 else 0.0
	progress.show_percentage = false
	progress.custom_minimum_size.y = Tokens.SPACE_SM
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(progress)
	return progress
