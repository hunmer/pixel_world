## battle/battle_ui_unit_detail.gd — 单位详情面板（从 battle_ui.gd 拆出）
##
## 职责：
##   - 右键查看任意阵营单位完整信息：居中弹出面板，展示阵营/等级/HP/MP/
##     全部属性/攻击射程/武器/技能（含冷却+描述）/背包（含 uses）/buff 状态
##   - 面板生命周期（open / close / is_open）—— 挂 battle_ui.preview_container
##     （与预览面板、飘字共用屏幕空间容器），与行动菜单 menu_container 独立、不改 mode
##
## 设计：RefCounted 能力模块（battle_ui 拆分件）。不持有 battle.gd 引用；
## 宿主 BattleUI（CanvasLayer）经 setup() 注入为 _ui：视口取尺寸（_ui.get_viewport）
## 与容器挂载（_ui.preview_container）经宿主 duck-typed 动态访问。
## 面板实例 _panel 由本模块持有；battle_ui.open_unit_detail / close_unit_detail /
## is_unit_detail_open 对外薄委托到这里。
##
## 公开 API（battle_ui 装配层调用）：
##   setup(ui)
##   open_unit_detail(u)
##   close_unit_detail()
##   is_unit_detail_open() -> bool
class_name BattleUiUnitDetail
extends RefCounted

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")

## 宿主 BattleUI（CanvasLayer；duck-typed 动态访问 get_viewport/preview_container）
var _ui = null

var _panel: Control = null

# 阵营 → 显示名 / 颜色（与 unit_sprite.gd 保持一致，详情面板标题用）
const FACTION_NAME := {
	player = "我方",
	enemy = "敌方",
	ally = "友军",
	other = "中立",
}
const FACTION_COLOR := {
	player = Color(0.376, 0.647, 0.980),
	enemy = Color(0.973, 0.443, 0.443),
	ally = Color(0.290, 0.867, 0.502),
	other = Color(0.984, 0.749, 0.141),
}


func setup(p_ui) -> void:
	_ui = p_ui


## 打开单位详情面板：居中弹出，展示阵营/等级/HP/MP/全部属性/技能/背包/buff/武器。
## 与行动菜单（menu_container）独立，不改变 mode；ESC 或关闭按钮关。
func open_unit_detail(u: Dictionary) -> void:
	close_unit_detail()
	var s: Dictionary = u.stats
	var viewport_size = _ui.get_viewport().get_visible_rect().size
	# 详情面板挂在 preview_container（屏幕空间，FULL_RECT）
	var panel := PanelContainer.new()
	panel.name = "UnitDetailPanel"
	panel.add_theme_stylebox_override("panel", UIThemeScript.menu_panel_style())
	panel.position = (viewport_size - Vector2(360, 420)) * 0.5
	panel.custom_minimum_size = Vector2(360, 0)
	panel.size = Vector2(360, 420)
	_ui.preview_container.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(340, 380)
	panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	var faction_text: String = FACTION_NAME.get(u.faction, "")
	# 标题：阵营色 + 名字 + 职业 + 等级
	var title := UIFactoryScript.outline_label(
		"%s · %s [%s] Lv.%d" % [faction_text, String(u.name),
			ProfessionData.profession_name(u.classId), int(u.level)],
		18, FACTION_COLOR.get(u.faction, Color.WHITE))
	vbox.add_child(title)

	# 状态行：HP/MP/经验
	vbox.add_child(UIFactoryScript.outline_label(
		"HP %d / %d    MP %d / %d    EXP %d" % [
			int(u.hp), int(s.hp), int(u.get(&"mp", 0)), int(s.get(&"mp", 0)),
			int(u.get(&"exp", 0))], 14, Color(0.92, 0.95, 0.98)))

	# 全部基础属性
	vbox.add_child(UIFactoryScript.outline_label(
		("力 %d   魔 %d   技 %d   速 %d\n" +
		 "防 %d   魔防 %d   运 %d   移动 %d") % [
			int(s.get(&"str", 0)), int(s.get(&"mag", 0)), int(s.get(&"skl", 0)), int(s.spd),
			int(s.def), int(s.res), int(s.get(&"luk", 0)), int(s.get(&"mov", 0))],
		14, Color(0.88, 0.93, 0.96)))

	# 攻击范围
	vbox.add_child(UIFactoryScript.outline_label(
		"攻击射程 %s" % str(ProfessionData.unit_attack_range(u)),
		14, Color(0.88, 0.93, 0.96)))

	# 武器
	var weapon = u.get(&"weapon", null)
	if weapon is Dictionary and not (weapon as Dictionary).is_empty():
		var wd: Dictionary = weapon
		vbox.add_child(UIFactoryScript.outline_label(
			"武器：%s" % String(wd.get(&"name", String(wd.get(&"id", &"")))),
			14, Color(0.96, 0.84, 0.40)))

	# 技能列表（含冷却 + 描述）
	var skills: Array = u.get(&"skills", [])
	if not skills.is_empty():
		var cd: Dictionary = u.get(&"skillCooldowns", {})
		var skill_lines: Array = []
		for sid in skills:
			var sn := SkillData.skill_name(sid)
			var c: int = int(cd.get(sid, 0))
			if c > 0:
				skill_lines.append("  • %s（冷却 %d）" % [sn, c])
			else:
				skill_lines.append("  • %s" % sn)
		vbox.add_child(UIFactoryScript.outline_label("技能：", 14, Color(0.75, 0.92, 0.78)))
		vbox.add_child(UIFactoryScript.outline_label("\n".join(skill_lines), 13, Color(0.82, 0.90, 0.84)))

	# 背包（含 uses）
	var items: Array = u.get(&"items", [])
	if not items.is_empty():
		var item_lines: Array = []
		for ie in items:
			var iname := ItemData.item_name(ie.get(&"id", &""))
			item_lines.append("  • %s ×%d" % [iname, int(ie.get(&"uses", 0))])
		vbox.add_child(UIFactoryScript.outline_label("背包：", 14, Color(0.74, 0.84, 0.96)))
		vbox.add_child(UIFactoryScript.outline_label("\n".join(item_lines), 13, Color(0.80, 0.88, 0.95)))

	# buff 状态
	var buffs: Array = u.get(&"buffs", [])
	if not buffs.is_empty():
		var buff_lines: Array = []
		for b in buffs:
			buff_lines.append("  • %s %+d（%d 回合）" % [
				String(b.get(&"stat", &"")), int(b.get(&"value", 0)), int(b.get(&"turns", 0))])
		vbox.add_child(UIFactoryScript.outline_label("状态：", 14, Color(0.98, 0.84, 0.30)))
		vbox.add_child(UIFactoryScript.outline_label("\n".join(buff_lines), 13, Color(0.95, 0.86, 0.50)))

	# 关闭按钮
	var close_btn := UIFactoryScript.button()
	close_btn.text = "关闭 (ESC)"
	close_btn.pressed.connect(close_unit_detail)
	vbox.add_child(close_btn)

	_panel = panel


func close_unit_detail() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null


func is_unit_detail_open() -> bool:
	return _panel != null and is_instance_valid(_panel)
