## ui_gallery/ui_gallery_battle_page.gd — 画廊战棋页（从 ui_component_gallery.gd 拆出）
##
## 职责：第 12 页「战棋」——story/10_ui_ux.md 布局还原：顶部 HUD / 行动菜单 / 技能面板 /
## 战斗预测 / 单位详情 / 战前整备 / 胜负结算 / 设置 / 背包容器。story 专属色板以
## UITheme 常量近似，不引入新颜色。骨架 PixelMargin→PixelVBox→PixelHBox，
## 溢出滚动由 add_pixel_tab 统一的「战棋Scroll」外壳承担，页内不再套第二层滚动容器。
##
## 设计：RefCounted 能力模块（ui_component_gallery 拆分件）。宿主经 setup() 注入 self，
## duck-typed 调用宿主公开面 add_gallery_tab / set_status / log_feedback；
## 卡片 / 按钮工具复用 UiGalleryWidgets。设置控件与背包状态归本模块持有，reset 复位。
class_name UiGalleryBattlePage
extends RefCounted

const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const PixelVBoxScript = preload("res://ui/components/pixel_v_box.gd")
const PixelHBoxScript = preload("res://ui/components/pixel_h_box.gd")
const PixelGridScript = preload("res://ui/components/pixel_grid.gd")
const PixelMarginScript = preload("res://ui/components/pixel_margin.gd")
const PixelProgressBarScript = preload("res://ui/components/pixel_progress_bar.gd")
const PixelCheckButtonScript = preload("res://ui/components/pixel_check_button.gd")
const PixelOptionButtonScript = preload("res://ui/components/pixel_option_button.gd")
const PixelSliderScript = preload("res://ui/components/pixel_slider.gd")
const PixelTabsScript = preload("res://ui/components/pixel_tabs.gd")

## 本模块负责的页签标题。
const TAB_TITLE: String = "战棋"
## 背包容器格数（story 口径六格）。
const BATTLE_BAG_CAPACITY: int = 6

## 宿主画廊（duck-typed 动态访问 add_gallery_tab / set_status / log_feedback）。
var _host = null

## 战棋页演示状态：设置控件 / 编队勾选，供重置复位。
var _battle_master_slider: HSlider
var _battle_music_slider: HSlider
var _battle_sfx_slider: HSlider
var _battle_size_option: OptionButton
var _battle_colorblind_option: OptionButton
var _battle_autosave_option: OptionButton
var _battle_auto_battle_switch: CheckButton
var _battle_deploy_checks: Array[CheckButton] = []
var _battle_deploy_counter: Label
## 战棋页背包容器演示状态：条目（空字典=空格）/ 格子按钮 / 选中格序号 / 详情与容量控件。
var _battle_bag_items: Array[Dictionary] = []
var _battle_bag_buttons: Array[Button] = []
var _battle_bag_selected: int = 0
var _battle_bag_detail: Label
var _battle_bag_counter: Label
var _battle_bag_action: Button


func setup(p_host) -> void:
	_host = p_host


## 构建战棋页：五行卡片组（HUD+菜单+技能 / 预测+详情 / 整备+胜利 / 失败+设置 / 背包）。
func build() -> void:
	var page: VBoxContainer = _host.add_gallery_tab(TAB_TITLE)

	var margin := PixelMarginScript.new() as MarginContainer
	margin.name = "BattleMargin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(margin)

	var column := PixelVBoxScript.new() as VBoxContainer
	column.name = "BattleColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_MD)
	margin.add_child(column)

	column.add_child(_battle_row([
		_build_battle_hud_card(), _build_battle_menu_card(), _build_battle_skill_card(),
	]))
	column.add_child(_battle_row([_build_battle_preview_card(), _build_battle_detail_card()]))
	column.add_child(_battle_row([_build_battle_prep_card(), _build_battle_victory_card()]))
	column.add_child(_battle_row([_build_battle_defeat_card(), _build_battle_settings_card()]))
	column.add_child(_battle_row([_build_battle_bag_card()]))


## 复位战棋演示状态（设置滑块/下拉/托管/编队/背包，与拆分前 _reset_demo 对应段同序）。
func reset() -> void:
	_battle_master_slider.set_value_no_signal(80.0)
	_battle_music_slider.set_value_no_signal(60.0)
	_battle_sfx_slider.set_value_no_signal(70.0)
	_battle_size_option.select(0)
	_battle_colorblind_option.select(0)
	_battle_autosave_option.select(0)
	_battle_auto_battle_switch.set_pressed_no_signal(false)
	for i: int in _battle_deploy_checks.size():
		_battle_deploy_checks[i].set_pressed_no_signal(i < 3)
	_battle_deploy_counter.text = "上场 3/6"
	_battle_bag_items = _battle_bag_default_items()
	_battle_bag_selected = 0
	_refresh_battle_bag()


## 战棋页一行卡片：PixelHBox + 卡片均分，竖向收缩避免行内拉高。
func _battle_row(cards: Array) -> HBoxContainer:
	var row := PixelHBoxScript.new() as HBoxContainer
	row.name = "BattleRow"
	row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_MD)
	for card: PanelContainer in cards:
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(card)
	return row


## 顶部 HUD：回合阶段 + 友军/敌军存活计数 + 任务目标。
func _build_battle_hud_card() -> PanelContainer:
	var card := UiGalleryWidgets.make_card("顶部 HUD", "")
	card.name = "BattleHudCard"
	var slot := UiGalleryWidgets.card_slot(card)
	var row := HBoxContainer.new()
	row.name = "BattleHudRow"
	row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var phase := UIFactoryScript.label("回合 #3 · 玩家阶段", ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN)
	phase.name = "BattleHudPhase"
	row.add_child(phase)
	row.add_child(_battle_force_counter("友军", 6, 8))
	row.add_child(_battle_force_counter("敌军", 4, 7))
	var objective := UIFactoryScript.label("▶ 解救村民(0/2)", ComponentThemeScript.FONT_BODY, UIThemeScript.ACCENT)
	objective.name = "BattleHudObjective"
	row.add_child(objective)
	slot.add_child(row)
	return card


## 友军/敌军计数：短标签 + PixelProgressBar 存活比例。
func _battle_force_counter(force_name: String, alive: int, total: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = force_name + "Counter"
	box.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	box.add_child(
		UIFactoryScript.label("%s %d/%d" % [force_name, alive, total], ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM)
	)
	var bar := PixelProgressBarScript.new() as ProgressBar
	bar.max_value = total
	bar.value = alive
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(64, 8)
	box.add_child(bar)
	return box


## 行动菜单：推荐项置顶（主操作），其余次操作，Esc 撤销收尾。
func _build_battle_menu_card() -> PanelContainer:
	var card := UiGalleryWidgets.make_card("行动菜单", "")
	card.name = "BattleMenuCard"
	var slot := UiGalleryWidgets.card_slot(card)
	var menu := VBoxContainer.new()
	menu.name = "BattleMenuList"
	menu.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	var entries: Array[Array] = [
		["BattleMenuAttack", "★ 攻击（3 目标）", 0],
		["BattleMenuSkill", "技能（2 可用）", 1],
		["BattleMenuItem", "物品（1 可用）", 1],
		["BattleMenuWait", "等待", 1],
		["BattleMenuUndo", "✕ 撤销移动（Esc）", 1],
	]
	for entry: Array in entries:
		var btn := UiGalleryWidgets.make_pixel_button(entry[1], entry[2], "")
		btn.name = entry[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_battle_menu_pressed.bind(entry[1]))
		menu.add_child(btn)
	slot.add_child(menu)
	return card


## 技能面板：标题含 MP 余量；可用技能主/次操作，无目标与 MP 不足的项灰显。
func _build_battle_skill_card() -> PanelContainer:
	var card := UiGalleryWidgets.make_card("技能面板", "")
	card.name = "BattleSkillCard"
	var slot := UiGalleryWidgets.card_slot(card)
	var column := VBoxContainer.new()
	column.name = "BattleSkillColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	column.add_child(
		UIFactoryScript.label("技能 · 莉雅　MP 12/20", ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN)
	)
	var entries: Array[Array] = [
		["BattleSkillFire", "★ 火球术　MP 6 · 射程 1-3 · 预伤 18-24", 0, false],
		["BattleSkillFrost", "寒霜之触　MP 4 · 射程 1-2 · 预伤 10-14", 1, false],
		["BattleSkillShield", "魔法护盾　MP 3（无目标）", 1, true],
		["BattleSkillBlizzard", "暴风雪　MP 15（MP 不足）", 1, true],
	]
	for entry: Array in entries:
		var btn := UiGalleryWidgets.make_pixel_button(entry[1], entry[2], "")
		btn.name = entry[0]
		btn.disabled = entry[3]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not btn.disabled:
			btn.pressed.connect(_on_battle_menu_pressed.bind(entry[1]))
		column.add_child(btn)
	slot.add_child(column)
	return card


## 战斗预测：攻/守双列（HP 条 + 命中/伤害/必杀）+  weapon 克制与风险三色提示。
func _build_battle_preview_card() -> PanelContainer:
	var card := UiGalleryWidgets.make_card("战斗预测", "")
	card.name = "BattlePreviewCard"
	var slot := UiGalleryWidgets.card_slot(card)
	var column := VBoxContainer.new()
	column.name = "BattlePreviewColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)
	var grid := PixelGridScript.new() as GridContainer
	grid.name = "BattlePreviewGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", ComponentThemeScript.SPACE_MD)
	grid.add_theme_constant_override("v_separation", ComponentThemeScript.SPACE_XS)
	grid.add_child(_battle_combatant_column(
		"BattlePreviewAttacker", "⚔ 凯尔 [剑士]", 22, 24, ["命中 92%", "伤害 12 ×2双击", "必杀 7%"]
	))
	grid.add_child(_battle_combatant_column(
		"BattlePreviewDefender", "🛡 敌兵 [枪兵]", 9, 18, ["反击命中 41%", "反击伤害 4"]
	))
	column.add_child(grid)
	var tips := VBoxContainer.new()
	tips.name = "BattlePreviewTips"
	tips.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	tips.add_child(UIFactoryScript.label(
		"▲ 剑 克 枪（+15% 命中 +3 伤害）", ComponentThemeScript.FONT_CAPTION, UIThemeScript.ACCENT
	))
	tips.add_child(UIFactoryScript.label(
		"⚠ 敌人 HP 降至 0 → 可击杀", ComponentThemeScript.FONT_CAPTION, UIThemeScript.ERROR
	))
	tips.add_child(UIFactoryScript.label(
		"⚠ 敌人射程 1，你移入后将受反击", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TOAST_COLOR
	))
	column.add_child(tips)
	slot.add_child(column)
	return card


## 攻方/守方一列：名字 + HP 条 + 数值行。
func _battle_combatant_column(
	node_name: String, header: String, cur: float, maxv: float, lines: Array
) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = node_name
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	column.add_child(UIFactoryScript.label(header, ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN))
	var bar := PixelProgressBarScript.new() as ProgressBar
	bar.name = node_name + "Hp"
	bar.max_value = maxv
	bar.value = cur
	bar.show_percentage = false
	column.add_child(bar)
	column.add_child(
		UIFactoryScript.label("HP %d/%d" % [int(cur), int(maxv)], ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM)
	)
	for line_text: String in lines:
		column.add_child(UIFactoryScript.label(line_text, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN))
	return column


## 单位详情：名字 + 主角标签 / HP MP EXP 三条 / 属性四列网格 / 装备技能背包状态地形。
func _build_battle_detail_card() -> PanelContainer:
	var card := UiGalleryWidgets.make_card("单位详情", "")
	card.name = "BattleDetailCard"
	var slot := UiGalleryWidgets.card_slot(card)
	var column := VBoxContainer.new()
	column.name = "BattleDetailColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	header.add_child(
		UIFactoryScript.label("凯尔 [剑士·Lv5]", ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN)
	)
	header.add_child(UIFactoryScript.label("主角", ComponentThemeScript.FONT_CAPTION, UIThemeScript.ACCENT))
	column.add_child(header)
	column.add_child(_battle_bar_row("BattleDetailHp", "HP", 22, 24))
	column.add_child(_battle_bar_row("BattleDetailMp", "MP", 0, 0))
	column.add_child(_battle_bar_row("BattleDetailExp", "EXP", 74, 100))
	var stats := PixelGridScript.new() as GridContainer
	stats.name = "BattleDetailStats"
	stats.columns = 4
	stats.add_theme_constant_override("h_separation", ComponentThemeScript.SPACE_XS)
	stats.add_theme_constant_override("v_separation", ComponentThemeScript.SPACE_XS)
	for stat_pair: Array in [
		["力", 9], ["速", 8], ["技", 7], ["运", 6], ["防", 5], ["魔防", 2], ["移动", 5], ["射程", 1],
	]:
		stats.add_child(_battle_stat_cell(stat_pair[0], stat_pair[1]))
	column.add_child(stats)
	for line_text: String in [
		"装备：铁剑（攻击+5）· 皮甲（防御+2）",
		"技能：火球术（冷却 0）· 连击",
		"背包：生命药剂 ×2",
		"状态：力 +3（2 回合）",
		"地形：森林 防御+2 回避+15",
	]:
		column.add_child(UIFactoryScript.label(line_text, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN))
	slot.add_child(column)
	return card


## HP/MP/EXP 行：短标签 + PixelProgressBar（拉伸）+ 当前/上限文本；maxv<=0 时按空条处理。
func _battle_bar_row(node_name: String, stat_name: String, cur: float, maxv: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	row.add_child(
		UIFactoryScript.label(stat_name, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM)
	)
	var bar := PixelProgressBarScript.new() as ProgressBar
	bar.name = node_name
	bar.max_value = maxv if maxv > 0.0 else 1.0
	bar.value = cur if maxv > 0.0 else 0.0
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	row.add_child(
		UIFactoryScript.label(
			"%d/%d" % [int(cur), int(maxv)], ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN
		)
	)
	return row


## 单个属性格：居中短标签，最小宽度对齐四列网格。
func _battle_stat_cell(stat_name: String, stat_value: int) -> Label:
	var cell := UIFactoryScript.label(
		"%s %d" % [stat_name, stat_value], ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN
	)
	cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.custom_minimum_size = Vector2(56, 0)
	return cell


## 背包容器：持有者与容量计数 + PixelGrid 六格容量网格（图标 + 剩余次数，装备格主操作高亮，
## 空格灰显）+ 选中详情行 + 使用/装备操作；消耗到 0 格子空出，装备可切换。
func _build_battle_bag_card() -> PanelContainer:
	var card := UiGalleryWidgets.make_card("背包", "")
	card.name = "BattleBagCard"
	var slot := UiGalleryWidgets.card_slot(card)
	var column := VBoxContainer.new()
	column.name = "BattleBagColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)

	_battle_bag_items = _battle_bag_default_items()
	_battle_bag_selected = 0

	var header := HBoxContainer.new()
	header.name = "BattleBagHeader"
	header.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	header.add_child(
		UIFactoryScript.label("凯尔的随身背包", ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN)
	)
	_battle_bag_counter = UIFactoryScript.label("", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM)
	header.add_child(_battle_bag_counter)
	column.add_child(header)

	var grid := PixelGridScript.new() as GridContainer
	grid.name = "BattleBagGrid"
	grid.columns = BATTLE_BAG_CAPACITY
	grid.add_theme_constant_override("h_separation", ComponentThemeScript.SPACE_XS)
	grid.add_theme_constant_override("v_separation", ComponentThemeScript.SPACE_XS)
	_battle_bag_buttons.clear()
	for i: int in BATTLE_BAG_CAPACITY:
		var btn := UiGalleryWidgets.make_pixel_button("", 1, "")
		btn.name = "BattleBagSlot%d" % i
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_battle_bag_slot_pressed.bind(i))
		_battle_bag_buttons.append(btn)
		grid.add_child(btn)
	column.add_child(grid)

	var footer := HBoxContainer.new()
	footer.name = "BattleBagFooter"
	footer.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	_battle_bag_detail = UIFactoryScript.label("", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN)
	_battle_bag_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_battle_bag_detail)
	_battle_bag_action = UiGalleryWidgets.make_pixel_button("使用", 0, "")
	_battle_bag_action.name = "BattleBagAction"
	_battle_bag_action.pressed.connect(_on_battle_bag_action_pressed)
	footer.add_child(_battle_bag_action)
	column.add_child(footer)

	slot.add_child(column)
	_refresh_battle_bag()
	return card


## 背包演示初始条目（名称/效果/次数/射程取自 data/items.json 真实物品字段）。
func _battle_bag_default_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = [
		{
			"name": "生命药剂", "icon": "heart", "kind": "消耗",
			"detail": "恢复 20 HP · 射程 0-1", "uses": 2, "max_uses": 3,
		},
		{
			"name": "手里剑", "icon": "dagger", "kind": "投掷",
			"detail": "固定伤害 8 · 射程 1-3", "uses": 4, "max_uses": 4,
		},
		{
			"name": "守护之戒", "icon": "shield", "kind": "装备",
			"detail": "防御 +4", "equipped": true,
		},
		{
			"name": "炸弹", "icon": "bomb", "kind": "投掷",
			"detail": "范围伤害 10 · 射程 1-2", "uses": 1, "max_uses": 2,
		},
	]
	while items.size() < BATTLE_BAG_CAPACITY:
		items.append({})
	return items


## 背包格子文案：装备格带装备态注记，其余按剩余次数显示。
func _battle_bag_slot_text(item: Dictionary) -> String:
	if String(item.get("kind", "")) == "装备":
		return "%s%s" % [String(item.name), "（已装备）" if item.get("equipped", false) else ""]
	return "%s ×%d" % [String(item.name), int(item.uses)]


## 刷新背包全部格子、容量计数与详情/操作行；空字典条目显示为灰显空格。
func _refresh_battle_bag() -> void:
	var filled := 0
	for i: int in BATTLE_BAG_CAPACITY:
		var btn := _battle_bag_buttons[i]
		var item: Dictionary = _battle_bag_items[i]
		if item.is_empty():
			btn.set("semantic", 1)
			btn.text = "空"
			btn.icon = null
			btn.disabled = true
			continue
		filled += 1
		var equipped: bool = String(item.get("kind", "")) == "装备" and item.get("equipped", false)
		btn.set("semantic", 0 if equipped else 1)
		btn.text = _battle_bag_slot_text(item)
		btn.icon = UIThemeScript.icon(String(item.icon))
		btn.disabled = false
	_battle_bag_counter.text = "%d/%d" % [filled, BATTLE_BAG_CAPACITY]
	_refresh_battle_bag_detail()


## 当前选中格的条目；越界或空格返回空字典。
func _battle_bag_selected_item() -> Dictionary:
	if _battle_bag_selected < 0 or _battle_bag_selected >= _battle_bag_items.size():
		return {}
	return _battle_bag_items[_battle_bag_selected]


## 刷新详情行与操作按钮：空格禁用操作；装备格切换「装备/卸下」，其余为「使用」。
func _refresh_battle_bag_detail() -> void:
	var item := _battle_bag_selected_item()
	if item.is_empty():
		_battle_bag_detail.text = "选中：空格"
		_battle_bag_action.disabled = true
		_battle_bag_action.text = "使用"
		return
	var line := "选中：%s · %s · %s" % [String(item.name), String(item.kind), String(item.detail)]
	if String(item.get("kind", "")) != "装备":
		line += " · 剩 %d/%d" % [int(item.uses), int(item.max_uses)]
	_battle_bag_detail.text = line
	_battle_bag_action.disabled = false
	if String(item.get("kind", "")) == "装备":
		_battle_bag_action.text = "卸下" if item.get("equipped", false) else "装备"
	else:
		_battle_bag_action.text = "使用"


func _on_battle_bag_slot_pressed(index: int) -> void:
	_battle_bag_selected = index
	_refresh_battle_bag_detail()
	var item := _battle_bag_selected_item()
	if item.is_empty():
		return
	_host.set_status("背包：%s" % String(item.name))
	_host.log_feedback("背包选中 → %s" % String(item.name))


## 背包操作：装备格切换装备态；消耗/投掷格扣 1 次，次数归零格子空出并取消选中。
func _on_battle_bag_action_pressed() -> void:
	var item := _battle_bag_selected_item()
	if item.is_empty():
		return
	if String(item.get("kind", "")) == "装备":
		var now_equipped: bool = not item.get("equipped", false)
		item["equipped"] = now_equipped
		_host.set_status("背包：%s %s" % [String(item.name), "已装备" if now_equipped else "已卸下"])
		_host.log_feedback("背包 %s → %s" % [String(item.name), "装备" if now_equipped else "卸下"])
	else:
		var uses_left := int(item.uses) - 1
		if uses_left <= 0:
			var consumed := String(item.name)
			_battle_bag_items[_battle_bag_selected] = {}
			_battle_bag_selected = -1
			_host.set_status("背包：%s 已用尽" % consumed)
			_host.log_feedback("背包 %s 用尽 → 格子空出" % consumed)
		else:
			item["uses"] = uses_left
			_host.set_status("背包：使用 %s" % String(item.name))
			_host.log_feedback("背包使用 → %s（剩 %d）" % [String(item.name), uses_left])
	_refresh_battle_bag()


## 战前整备：左栏编队勾选（联动上场计数）/ 中栏五个 Tab / 右栏选中单位详情。
func _build_battle_prep_card() -> PanelContainer:
	var card := UiGalleryWidgets.make_card("战前整备", "")
	card.name = "BattlePrepCard"
	var slot := UiGalleryWidgets.card_slot(card)
	var row := HBoxContainer.new()
	row.name = "BattlePrepRow"
	row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)

	var roster := VBoxContainer.new()
	roster.name = "BattlePrepRoster"
	roster.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	_battle_deploy_checks.clear()
	var names := ["凯尔", "莉雅", "希尔德", "艾尔文", "瑟兰"]
	for i: int in names.size():
		var check := PixelCheckButtonScript.new() as CheckButton
		check.text = names[i]
		check.set_pressed_no_signal(i < 3)
		check.toggled.connect(_on_battle_deploy_toggled)
		_battle_deploy_checks.append(check)
		roster.add_child(check)
	_battle_deploy_counter = UIFactoryScript.label("上场 3/6", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN)
	roster.add_child(_battle_deploy_counter)
	row.add_child(roster)

	var prep_tabs := PixelTabsScript.new() as TabContainer
	prep_tabs.name = "BattlePrepTabs"
	prep_tabs.custom_minimum_size = Vector2(150, 0)
	for tab_title: String in ["编队", "装备", "技能", "转职", "物品"]:
		var tab_page: VBoxContainer = prep_tabs.call("add_pixel_tab", tab_title) as VBoxContainer
		tab_page.add_child(
			UIFactoryScript.label("%s · 凯尔" % tab_title, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM)
		)
	row.add_child(prep_tabs)

	var detail := VBoxContainer.new()
	detail.name = "BattlePrepDetail"
	detail.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	for line_text: String in ["选中：凯尔 [剑士]", "Lv 5 · HP 22/24", "MP 0/0 · 移动 5", "装备：铁剑"]:
		detail.add_child(UIFactoryScript.label(line_text, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN))
	row.add_child(detail)
	slot.add_child(row)
	return card


## 胜利结算：标题大字 + 三条经验（进度条 + 升级注记）+ 掉落/存活/下一关 + 三个去向按钮。
func _build_battle_victory_card() -> PanelContainer:
	var card := UiGalleryWidgets.make_card("胜利结算", "")
	card.name = "BattleVictoryCard"
	var slot := UiGalleryWidgets.card_slot(card)
	var column := VBoxContainer.new()
	column.name = "BattleVictoryColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)
	var title := UIFactoryScript.outline_label("胜 利", ComponentThemeScript.FONT_TITLE, UIThemeScript.TOAST_COLOR, 4)
	title.name = "BattleVictoryTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(_battle_exp_row("BattleVictoryExpKai", "凯尔", 48, "Lv5→6！（力+1 速+1）", 48))
	column.add_child(_battle_exp_row("BattleVictoryExpLia", "莉雅", 32, "Lv4→5", 32))
	column.add_child(_battle_exp_row("BattleVictoryExpHild", "希尔德", 30, "经验 +30", 30))
	column.add_child(
		UIFactoryScript.label("掉落：铁枪 ×1 · 源脉药剂 ×1 · 100 金币", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN)
	)
	column.add_child(
		UIFactoryScript.label("队员：✓ 全员存活", ComponentThemeScript.FONT_CAPTION, UIThemeScript.ACCENT)
	)
	column.add_child(
		UIFactoryScript.label("下一关：第 2 章 · 雾岭哨站", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM)
	)
	var buttons := HBoxContainer.new()
	buttons.name = "BattleVictoryButtons"
	buttons.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	var primary := UiGalleryWidgets.make_pixel_button("继续剧情", 0, "")
	primary.name = "BattleVictoryPrimary"
	buttons.add_child(primary)
	var to_prep := UiGalleryWidgets.make_pixel_button("回整备", 1, "")
	to_prep.name = "BattleVictoryToPrep"
	buttons.add_child(to_prep)
	var save := UiGalleryWidgets.make_pixel_button("存档", 1, "")
	save.name = "BattleVictorySave"
	buttons.add_child(save)
	for child: Button in buttons.get_children():
		child.pressed.connect(_on_battle_result_pressed.bind(child.text))
	column.add_child(buttons)
	slot.add_child(column)
	return card


## 单条经验行：名字 + PixelProgressBar + 增量与升级注记。
func _battle_exp_row(
	node_name: String, who: String, gain: int, note: String, fill: float
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	var name_label := UIFactoryScript.label(who, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN)
	name_label.custom_minimum_size = Vector2(56, 0)
	row.add_child(name_label)
	var bar := PixelProgressBarScript.new() as ProgressBar
	bar.name = node_name
	bar.max_value = 100.0
	bar.value = fill
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	row.add_child(
		UIFactoryScript.label("+%d %s" % [gain, note], ComponentThemeScript.FONT_CAPTION, UIThemeScript.ACCENT)
	)
	return row


## 失败：血红大字 + 败因 + 三个去向按钮 + 自动存档提示。
func _build_battle_defeat_card() -> PanelContainer:
	var card := UiGalleryWidgets.make_card("失败", "")
	card.name = "BattleDefeatCard"
	var slot := UiGalleryWidgets.card_slot(card)
	var column := VBoxContainer.new()
	column.name = "BattleDefeatColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)
	var title := UIFactoryScript.outline_label("全军覆没", ComponentThemeScript.FONT_TITLE, UIThemeScript.ERROR, 4)
	title.name = "BattleDefeatTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(
		UIFactoryScript.label("主角凯尔已倒下，战局无可挽回。", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM)
	)
	var buttons := HBoxContainer.new()
	buttons.name = "BattleDefeatButtons"
	buttons.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	var retry := UiGalleryWidgets.make_pixel_button("重试本关", 0, "")
	retry.name = "BattleDefeatRetry"
	buttons.add_child(retry)
	var load := UiGalleryWidgets.make_pixel_button("读档", 1, "")
	load.name = "BattleDefeatLoad"
	buttons.add_child(load)
	var to_title := UiGalleryWidgets.make_pixel_button("回主菜单", 1, "")
	to_title.name = "BattleDefeatToTitle"
	buttons.add_child(to_title)
	for child: Button in buttons.get_children():
		child.pressed.connect(_on_battle_result_pressed.bind(child.text))
	column.add_child(buttons)
	column.add_child(
		UIFactoryScript.label("💡 上次自动存档：回合 #4（2 分钟前）", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TOAST_COLOR)
	)
	slot.add_child(column)
	return card


## 设置：三个下拉 + 托管开关 + 三条音量滑块。
func _build_battle_settings_card() -> PanelContainer:
	var card := UiGalleryWidgets.make_card("设置", "")
	card.name = "BattleSettingsCard"
	var slot := UiGalleryWidgets.card_slot(card)
	var column := VBoxContainer.new()
	column.name = "BattleSettingsColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)

	_battle_size_option = _battle_option_row(column, "BattleSettingsSize", "文字大小", ["标准", "大", "特大"])
	_battle_colorblind_option = _battle_option_row(
		column, "BattleSettingsColorblind", "色盲模式", ["关闭", "红绿", "蓝黄"]
	)
	_battle_autosave_option = _battle_option_row(column, "BattleSettingsAutosave", "自动存档", ["每回合", "每章", "关闭"])

	var auto_row := HBoxContainer.new()
	auto_row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	auto_row.add_child(UIFactoryScript.label("托管默认", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_row.add_child(spacer)
	_battle_auto_battle_switch = PixelCheckButtonScript.new() as CheckButton
	_battle_auto_battle_switch.name = "BattleSettingsAutoBattle"
	_battle_auto_battle_switch.toggled.connect(_on_battle_auto_battle_toggled)
	auto_row.add_child(_battle_auto_battle_switch)
	column.add_child(auto_row)

	_battle_master_slider = _battle_volume_row(column, "BattleSettingsMaster", "主音量", 80.0)
	_battle_music_slider = _battle_volume_row(column, "BattleSettingsMusic", "音乐", 60.0)
	_battle_sfx_slider = _battle_volume_row(column, "BattleSettingsSfx", "音效", 70.0)

	slot.add_child(column)
	return card


## 设置页一行下拉：标签 + 弹簧 + PixelOptionButton，选择写入反馈。
func _battle_option_row(
	parent: Container, node_name: String, row_label: String, items: Array
) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	row.add_child(UIFactoryScript.label(row_label, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var option := PixelOptionButtonScript.new() as OptionButton
	option.name = node_name
	for item_text: String in items:
		option.add_item(item_text)
	option.item_selected.connect(_on_battle_option_selected.bind(row_label))
	row.add_child(option)
	parent.add_child(row)
	return option


## 设置页一行滑块：标签 + PixelSlider（拉伸），改动写入状态行。
func _battle_volume_row(parent: Container, node_name: String, bus_label: String, initial: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	row.add_child(UIFactoryScript.label(bus_label, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN))
	var slider := PixelSliderScript.new() as HSlider
	slider.name = node_name
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_battle_volume_changed.bind(bus_label))
	row.add_child(slider)
	parent.add_child(row)
	return slider


func _on_battle_menu_pressed(which: String) -> void:
	_host.set_status("战棋菜单：%s" % which)
	_host.log_feedback("战棋菜单 → %s" % which)


func _on_battle_result_pressed(which: String) -> void:
	_host.set_status("结算：%s" % which)
	_host.log_feedback("结算 → %s" % which)


## 编队勾选联动「上场 n/6」计数。
func _on_battle_deploy_toggled(_toggled_on: bool) -> void:
	var count := 0
	for check: CheckButton in _battle_deploy_checks:
		if check.button_pressed:
			count += 1
	_battle_deploy_counter.text = "上场 %d/6" % count
	_host.set_status("编队：上场 %d/6" % count)


func _on_battle_option_selected(which: String, index: int) -> void:
	_host.set_status("设置：%s → 第 %d 项" % [which, index + 1])
	_host.log_feedback("设置 %s → 第 %d 项" % [which, index + 1])


func _on_battle_auto_battle_toggled(toggled_on: bool) -> void:
	_host.set_status("托管默认：%s" % ("开" if toggled_on else "关"))
	_host.log_feedback("托管默认 → %s" % ("开" if toggled_on else "关"))


func _on_battle_volume_changed(bus_name: String, value: float) -> void:
	_host.set_status("%s：%d" % [bus_name, roundi(value)])
