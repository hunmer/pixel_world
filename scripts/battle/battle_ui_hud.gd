## battle/battle_ui_hud.gd — 战场 HUD 侧栏（从 battle_ui.gd 拆出）
##
## 职责：
##   - 右侧固定宽多 Tab 侧边栏（map_editor 布局范式）：标题行 + TabContainer + 底部提示行
##     —— Tab = 回合（阶段标签/阵营状态/结束回合）· 情报（悬停信息）· 托管（托管/偏好）
##     · 战场设置（沉浸演出开关）· 日志（接管 Panku native_logger，浮层不再挂页面左侧）
##   - 阵营状态行：按签名检测增量刷新（战斗/技能/物品/AI 改 HP 都会被下一帧捕捉）
##   - 悬停单位/地形情报文本（show_info_at 的内容主体）
##   - process_tick()：由 battle_ui._process 每帧驱动（状态刷新 + 挂起日志落盘）
##
## 设计：RefCounted 能力模块（battle_ui 拆分件）。不持有 battle.gd 引用；
## 宿主 BattleUI（CanvasLayer）经 setup() 注入为 _ui：控件挂载（_ui.add_child）、
## Panku 接入（_ui.get_node_or_null）与数据引用（_ui.grid / _ui.turn）都经宿主
## duck-typed 动态访问（与拆分前 battle_ui 访问 self 等价；refs 在 battle_ui.setup 后不变）。
## 本模块持有的控件实例（phase_label / end_turn_btn / info_label / immersive_toggle /
## turn_status_labels / host_tab）同时以别名变量暴露在 battle_ui 上 —— 契约测试
## 直戳 battle_ui.phase_label / _turn_status_labels 等，两者必须始终是同一实例。
##
## 公开 API（battle_ui 装配层调用）：
##   setup(ui)
##   build(end_turn_cb, toggle_hosting_cb, open_pref_cb, host_btn_cb, immersive_toggled_cb)
##   refresh_turn_status()
##   show_info_at(x, y)
##   process_tick()
class_name BattleUiHud
extends RefCounted

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const BattleSettingsTabScript = preload("res://scripts/battle/battle_settings_tab.gd")

## 宿主 BattleUI（CanvasLayer；duck-typed 动态访问 add_child/get_node_or_null/grid/turn）
var _ui = null

# ---- 本模块持有的控件（battle_ui 侧别名的本体） ----
var sidebar: PanelContainer = null
## 【托管】Tab 内容盒（battle_ui.set_exit_callback 按需往里追加「退出战斗」按钮）
var host_tab: VBoxContainer = null
var phase_label: Label = null
var end_turn_btn: Button = null
var info_label: Label = null
var immersive_toggle: CheckButton = null
## 阵营 → 状态行 Label（battle_ui._turn_status_labels 别名指向同一 Dictionary 实例）
var turn_status_labels: Dictionary = {}
var _turn_status_signature := ""
# ---- 【日志】Tab ----
var log_label: RichTextLabel = null
var _pending_log_bbcode := ""
var _log_update_pending := false
## PankuModuleNativeLogger 实例（duck-typed；Panku 不在时保持 null）
var _logger_module = null

# ---- 配色常量（统一取自 ui_theme.gd，与 battle_ui 原侧栏样式一致） ----
const TEXT_MAIN := UIThemeScript.TEXT_MAIN
const TEXT_DIM := UIThemeScript.TEXT_DIM
const ACCENT := UIThemeScript.ACCENT
# 阵营 → 显示名 / 颜色（与 unit_sprite.gd 保持一致；状态行配色用）
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


## 右侧固定宽多 Tab 侧边栏（标题行 + TabContainer + 底部提示行）。
## host_btn_cb / immersive_toggled_cb 由 battle_ui 在 build 时传入当前回调
## （battle.gd 的 set_host_btn_callback / battle_ui 自身的沉浸开关处理）。
func build(end_turn_cb: Callable, toggle_hosting_cb: Callable, open_pref_cb: Callable,
		host_btn_cb: Callable, immersive_toggled_cb: Callable) -> void:
	sidebar = PanelContainer.new()
	sidebar.name = "BattleSidePanel"
	sidebar.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	sidebar.offset_left = -_ui.SIDEBAR_WIDTH
	sidebar.mouse_filter = Control.MOUSE_FILTER_STOP
	sidebar.add_theme_stylebox_override("panel", UIThemeScript.dock_panel_style())
	_ui.add_child(sidebar)

	var sv := VBoxContainer.new()
	sv.name = "SideVBox"
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", 6)
	sidebar.add_child(sv)

	# 标题行：双剑图标 + 文字（图标缺失只显示文字）
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	var swords: Texture2D = UIThemeScript.icon("swords")
	if swords != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = swords
		icon_rect.custom_minimum_size = Vector2(18, 18)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_row.add_child(icon_rect)
	title_row.add_child(UIFactoryScript.label("战场情报", 16, ACCENT))
	sv.add_child(title_row)

	# Tab 样式统一走 ui_factory.tab_container（含页签三态与面板底）
	var tabs := UIFactoryScript.tab_container("InfoTabs")
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(tabs)

	# ---- Tab【回合】：阶段 / 阵营状态 / 结束回合 ----
	var turn_tab := UIFactoryScript.add_tab(tabs, "回合", "swords")
	phase_label = UIFactoryScript.label("第 1 轮 · 我方行动", 18, TEXT_MAIN)
	turn_tab.add_child(phase_label)
	_add_turn_status_rows(turn_tab)
	end_turn_btn = UIFactoryScript.button()
	end_turn_btn.text = "结束回合 (E)"
	end_turn_btn.pressed.connect(end_turn_cb)
	turn_tab.add_child(end_turn_btn)
	turn_tab.add_child(UIFactoryScript.label("存活单位实时 HP 与行动状态；全部行动后自动结束回合。", 10, TEXT_DIM))

	# ---- Tab【情报】：悬停单位 / 地形详情（show_info_at 更新） ----
	var info_tab := UIFactoryScript.add_tab(tabs, "情报", "info")
	info_label = UIFactoryScript.label("（鼠标悬停单位或地形查看详情）", 13, TEXT_DIM)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_tab.add_child(info_label)
	info_tab.add_child(UIFactoryScript.label("右键单位打开完整详情；方向键移动光标同样刷新。", 10, TEXT_DIM))

	# ---- Tab【托管】：托管 / 偏好 /（按需）退出战斗 ----
	host_tab = UIFactoryScript.add_tab(tabs, "托管", "gears")
	var host_btn := UIFactoryScript.button()
	host_btn.pressed.connect(toggle_hosting_cb)
	host_tab.add_child(host_btn)
	# 把 host_btn 引用交给 turn_director（它负责更新按钮文字）—— 通过注入回调
	if host_btn_cb.is_valid():
		host_btn_cb.call(host_btn)
	var pref_btn := UIFactoryScript.button()
	pref_btn.text = "托管偏好"
	pref_btn.pressed.connect(open_pref_cb)
	host_tab.add_child(pref_btn)
	host_tab.add_child(UIFactoryScript.label("托管 = 本场战斗自动代打（敌方回合本就自动）；偏好按单位配置目标与策略。", 10, TEXT_DIM))

	# ---- Tab【战场设置】：真实交战镜头偏好；切换立即作用于当前/下一次演出 ----
	var settings_tab := UIFactoryScript.add_tab(tabs, "战场设置", "settings")
	immersive_toggle = BattleSettingsTabScript.populate(
		settings_tab,
		Settings.battle_immersive_presentation,
		immersive_toggled_cb
	)

	# ---- Tab【日志】：引擎/战斗日志（接管 Panku native_logger，浮层不再挂左侧） ----
	var log_tab := UIFactoryScript.add_tab(tabs, "日志", "file_terminal")
	var log_toolbar := HBoxContainer.new()
	log_toolbar.add_theme_constant_override("separation", 8)
	log_tab.add_child(log_toolbar)
	var clear_btn := UIFactoryScript.button()
	clear_btn.text = "清空"
	clear_btn.tooltip_text = "清空日志（同步清空 Panku native_logger 缓冲）"
	clear_btn.pressed.connect(_clear_log)
	log_toolbar.add_child(clear_btn)
	var log_source := UIFactoryScript.label("引擎日志 · info/warning/error", 10, TEXT_DIM)
	log_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_source.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	log_toolbar.add_child(log_source)
	log_label = UIFactoryScript.log_label()
	log_label.scroll_active = true
	log_label.context_menu_enabled = true
	log_label.shortcut_keys_enabled = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_tab.add_child(log_label)
	_attach_panku_logger()

	# 底部提示行（贴面板底部，自动换行）
	var hint := UIFactoryScript.label("Q/Z·E/X 旋转视角 · R 复位 · 中键拖拽平移 · ESC 取消", 10, TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(hint)


## battle_ui._process 每帧驱动：状态刷新 + 挂起日志落盘（顺序与拆分前一致）。
func process_tick() -> void:
	# 战斗、技能、物品和AI都可能改HP/行动状态；以签名检测统一刷新，避免遗漏调用链。
	refresh_turn_status()
	# 日志镜像：拖选期间挂起，选区清除后再落盘（同 side_panel.gd）。
	if _log_update_pending and not _log_selection_active():
		if is_instance_valid(log_label):
			log_label.text = _pending_log_bbcode
		_log_update_pending = false


## 阵营状态行（挂侧栏【回合】Tab）：按阵营存在性建「我方/敌方」两行 Label。
## turn 未注入（headless 契约测试直接 build）时不建行，refresh_turn_status 自然跳过。
func _add_turn_status_rows(parent: VBoxContainer) -> void:
	if _ui.turn == null:
		return
	for faction: StringName in [&"player", &"enemy"]:
		var has_faction := false
		for u: Dictionary in _ui.turn.units:
			if StringName(u.get(&"faction", &"")) == faction:
				has_faction = true
				break
		if not has_faction:
			continue
		var label := Label.new()
		label.name = "PlayerStatus" if faction == &"player" else "EnemyStatus"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", FACTION_COLOR[faction])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(label)
		turn_status_labels[faction] = label
	refresh_turn_status()


## 顶部精简状态：阵营、存活角色、行动状态与实时HP；死亡角色不再占行。
func refresh_turn_status() -> void:
	if _ui.turn == null or turn_status_labels.is_empty():
		return
	var signature := "%d:%s" % [_ui.turn.turn_number, String(_ui.turn.phase)]
	for u: Dictionary in _ui.turn.units:
		signature += "|%s:%s:%s:%d:%d:%s:%s" % [
			String(u.get(&"id", &"")), String(u.get(&"name", "")),
			String(u.get(&"faction", &"")), int(u.get(&"hp", 0)),
			int((u.get(&"stats", {}) as Dictionary).get(&"hp", 0)),
			str(bool(u.get(&"hasActed", false))), str(bool(u.get(&"isDead", false)))
		]
	if signature == _turn_status_signature:
		return
	_turn_status_signature = signature
	for faction: StringName in turn_status_labels:
		var parts := PackedStringArray()
		for u: Dictionary in _ui.turn.units:
			if StringName(u.get(&"faction", &"")) != faction or bool(u.get(&"isDead", false)):
				continue
			var stats: Dictionary = u.get(&"stats", {})
			parts.append("%s %s HP%d/%d" % [
				String(u.get(&"name", "")), "已行动" if bool(u.get(&"hasActed", false)) else "未行动",
				int(u.get(&"hp", 0)), int(stats.get(&"hp", 0))
			])
		var label: Label = turn_status_labels[faction]
		label.text = "%s｜%s" % [FACTION_NAME[faction], "；".join(parts)]
		label.visible = not parts.is_empty()


## 悬停单位/地形情报文本（写入【情报】Tab 的 info_label）。
func show_info_at(x: int, y: int) -> void:
	var u = _ui.grid.unit_at(x, y)
	if u.is_empty():
		var t = _ui.grid.tile_at(x, y)
		if not t.is_empty():
			info_label.text = "(%d,%d) %s\n防御+%d 回避+%d" % [x, y, String(t.type), t.def_bonus, t.avoid_bonus]
		else:
			info_label.text = "(%d,%d)" % [x, y]
	else:
		var s: Dictionary = u.stats
		var lines := PackedStringArray()
		lines.append("%s [%s] Lv%d" % [u.name, ProfessionData.profession_name(u.classId), u.level])
		lines.append("HP %d/%d  MP %d/%d" % [u.hp, s.hp, int(u.get(&"mp", 0)), int(s.get(&"mp", 0))])
		lines.append("力%d 速%d 防%d 魔防%d 射程%s" % [
			s.get(&"str", 0) + s.get(&"mag", 0), s.spd, s.def, s.res,
			str(ProfessionData.unit_attack_range(u)),
		])
		# 技能列表（含冷却）
		var skill_parts: Array = []
		var cd: Dictionary = u.get(&"skillCooldowns", {})
		for sid in u.get(&"skills", []):
			var sn := SkillData.skill_name(sid)
			var c: int = int(cd.get(sid, 0))
			if c > 0:
				skill_parts.append("%s(冷却%d)" % [sn, c])
			else:
				skill_parts.append(sn)
		if not skill_parts.is_empty():
			lines.append("技能: " + ", ".join(skill_parts))
		# 背包（含 uses）
		var item_parts: Array = []
		for ie in u.get(&"items", []):
			var iname := ItemData.item_name(ie.get(&"id", &""))
			item_parts.append("%s×%d" % [iname, int(ie.get(&"uses", 0))])
		if not item_parts.is_empty():
			lines.append("背包: " + ", ".join(item_parts))
		# buff 状态
		var buff_parts: Array = []
		for b in u.get(&"buffs", []):
			buff_parts.append("%s%+d(%d回合)" % [String(b.get(&"stat", &"")), int(b.get(&"value", 0)), int(b.get(&"turns", 0))])
		if not buff_parts.is_empty():
			lines.append("状态: " + ", ".join(buff_parts))
		info_label.text = "\n".join(lines)


## 接管 Panku native_logger（照搬 side_panel.gd._attach_panku）：
## 把原生屏幕浮层切成 NeverShow（B2 从 Game.tscn 进来没人关它，会挂在页面左侧），
## 并镜像 logger_view 的完整 bbcode 到【日志】Tab。B1 下世界 side_panel 可能已接管过，
## 再切一次幂等；content_updated 多消费者并存，各自维护自己的文本。
func _attach_panku_logger() -> void:
	var panku = _ui.get_node_or_null("/root/Panku")
	if panku == null:
		if is_instance_valid(log_label):
			log_label.text = "（Panku 未加载，无日志源）"
		return
	var module_manager = panku.get("module_manager")
	if module_manager == null or not module_manager.has_method("get_module"):
		return
	if not module_manager.has_module("native_logger"):
		return
	_logger_module = module_manager.get_module("native_logger")
	# 1) 屏幕浮层关闭（仅本会话；不写回 panku 持久化配置）
	_logger_module.set_overlay_display_mode(
		PankuModuleNativeLogger.ScreenOverlayDisplayMode.NeverShow
	)
	# 2) 镜像 logger_view 的完整 bbcode（自带去重 / 条数上限 / 时间戳着色）
	var logger_ui: Node = _logger_module.logger_ui
	logger_ui.content_updated.connect(_on_log_content_updated)


func _log_selection_active() -> bool:
	if not is_instance_valid(log_label):
		return false
	return not log_label.get_selected_text().is_empty() \
		or (log_label.has_focus() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))


func _on_log_content_updated(bbcode: String) -> void:
	if _log_selection_active():
		_pending_log_bbcode = bbcode
		_log_update_pending = true
		return
	if is_instance_valid(log_label):
		log_label.text = bbcode


func _clear_log() -> void:
	if not is_instance_valid(log_label):
		return
	log_label.deselect()
	if _logger_module != null and is_instance_valid(_logger_module):
		# content_updated 会回传空文本并同步本面板
		_logger_module.logger_ui.clear_all()
	else:
		log_label.text = ""
