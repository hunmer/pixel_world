extends RefCounted
## game_hud_settings_panel.gd — 世界 HUD 设置面板（战斗模式 / AI 难度）。
## 从 game_hud.gd 拆出的装配模块：hud 注入式静态构建（同 map_editor_overlays 模式），
## 节点挂到 hud.HUDRoot；对 Settings autoload 的 /root 动态解析约定原样保留（见 open）。


const AIDifficultyScript = preload("res://scripts/systems/ai_difficulty.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")

## 配色常量统一取自 ui_theme.gd（本文件别名）。
const TEXT_SECONDARY := UIThemeScript.TEXT_SECONDARY
const ACCENT := UIThemeScript.ACCENT


## 设置面板：战斗模式切换（就地/独立场景）。hud._open_settings 委托至此。
static func open(hud: CanvasLayer) -> void:
	# Settings 走 /root 动态解析：契约测试用 --script 模式跑，不加载 autoload，
	# 编译期直接引用 Settings 标识符会 Compile Error（game_hud_contract.gd）。
	# 游戏内 /root/Settings 即 Settings autoload 本体，行为不变。
	var settings := hud.get_node_or_null("/root/Settings")
	if settings == null:
		push_error("[hud] Settings autoload 未加载，设置面板不可用")
		return
	# 如果已打开，先移除
	var old := hud.get_node_or_null("HUDRoot/SettingsPanel")
	if old != null:
		old.queue_free()
		return
	var vp := hud.get_viewport().get_visible_rect().size
	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.custom_minimum_size = Vector2(280, 200)
	panel.position = (vp - panel.custom_minimum_size) / 2.0
	panel.add_theme_stylebox_override("panel", UIThemeScript.float_panel_style())
	hud.get_node("HUDRoot").add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.offset_left = 12; vbox.offset_top = 8
	vbox.offset_right = -12; vbox.offset_bottom = -8
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	# 标题
	var title := UIFactoryScript.shadow_label("设置", 14, ACCENT)
	vbox.add_child(title)
	# 战斗模式选项
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	var lbl := UIFactoryScript.shadow_label("战斗模式", 12, TEXT_SECONDARY)
	row.add_child(lbl)
	var opt := UIFactoryScript.option_button()
	opt.add_item("就地（B1）", 0)
	opt.add_item("独立场景（B2）", 1)
	opt.select(0 if settings.battle_inline_mode else 1)
	opt.custom_minimum_size = Vector2(140, 0)
	opt.item_selected.connect(func(idx: int):
		settings.set_battle_inline_mode(idx == 0)
	)
	row.add_child(opt)
	# 敌方 AI 难度 / 托管 AI 难度（四档；缺省 normal，非法存档值已由 Settings 归一）
	vbox.add_child(_difficulty_row(hud, "敌方 AI 难度", settings.enemy_ai_difficulty, "enemy"))
	vbox.add_child(_difficulty_row(hud, "托管 AI 难度", settings.host_ai_difficulty, "host"))
	# 关闭按钮
	var close_btn := UIFactoryScript.button("关闭", func():
		var p := hud.get_node_or_null("HUDRoot/SettingsPanel")
		if p != null: p.queue_free()
	)
	vbox.add_child(close_btn)


## 构造一行「AI 难度」选项（label + OptionButton 四档）。kind: "enemy"/"host"。
## settings 传入 open 解析出的 /root/Settings，避免编译期引用 autoload 标识符。
static func _difficulty_row(hud: CanvasLayer, label_text: String, current: String, kind: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := UIFactoryScript.shadow_label(label_text, 12, TEXT_SECONDARY)
	row.add_child(lbl)
	var opt := UIFactoryScript.option_button()
	var cur_idx := 0
	for i in AIDifficultyScript.OPTIONS.size():
		var entry: Dictionary = AIDifficultyScript.OPTIONS[i]
		opt.add_item(String(entry.get("label", entry.get("id", "?"))), i)
		if String(entry.get("id", "")) == current:
			cur_idx = i
	opt.select(cur_idx)
	opt.custom_minimum_size = Vector2(140, 0)
	opt.item_selected.connect(func(idx: int):
		var chosen: Dictionary = AIDifficultyScript.OPTIONS[idx]
		var settings := hud.get_node_or_null("/root/Settings")
		if settings != null:
			settings.set_ai_difficulty(kind, String(chosen.get("id", "normal")))
	)
	row.add_child(opt)
	return row
