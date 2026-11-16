extends RefCounted
## game_hud_battlefield_panel.gd — 战场选择面板（JSON 战场加载列表，调试入口）。
## 从 game_hud.gd 拆出的装配模块：hud 注入式静态构建（同 map_editor_overlays 模式），
## 节点挂到 hud.HUDRoot；面板状态仍存 hud._battlefield_panel / _battlefield_error_label，
## 对外行为（信号 battlefield_picked / editor_requested、ESC 关闭）与拆分前一致。


const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")

## 配色常量统一取自 ui_theme.gd（本文件别名）。
const TEXT_SECONDARY := UIThemeScript.TEXT_SECONDARY
const ACCENT := UIThemeScript.ACCENT
const ERROR_COLOR := UIThemeScript.ERROR


## 打开/关闭战场面板（O 键 / ⚔ 按钮共用；hud.toggle_battlefield_panel 委托至此）
static func toggle(hud: CanvasLayer) -> void:
	if hud._battlefield_panel != null and is_instance_valid(hud._battlefield_panel):
		close(hud)
	else:
		open(hud)


static func close(hud: CanvasLayer) -> void:
	if hud._battlefield_panel != null and is_instance_valid(hud._battlefield_panel):
		hud._battlefield_panel.queue_free()
	hud._battlefield_panel = null
	hud._battlefield_error_label = null


## 加载失败时在面板上回显错误（hud.show_battlefield_error 委托至此）
static func show_error(hud: CanvasLayer, message: String) -> void:
	if hud._battlefield_error_label == null or not is_instance_valid(hud._battlefield_error_label):
		return
	hud._battlefield_error_label.text = "加载失败：" + message
	hud._battlefield_error_label.visible = true


static func open(hud: CanvasLayer) -> void:
	close(hud)
	var vp := hud.get_viewport().get_visible_rect().size
	var panel := PanelContainer.new()
	panel.name = "BattlefieldPanel"
	panel.custom_minimum_size = Vector2(500.0, 0.0)
	panel.position = Vector2((vp.x - 500.0) / 2.0, 90.0)
	panel.add_theme_stylebox_override("panel", UIThemeScript.float_panel_style())
	hud.get_node("HUDRoot").add_child(panel)
	hud._battlefield_panel = panel

	var vbox := VBoxContainer.new()
	vbox.name = "BattlefieldVBox"
	vbox.offset_left = 14.0
	vbox.offset_top = 10.0
	vbox.offset_right = -14.0
	vbox.offset_bottom = -10.0
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# 标题行：标题 + 关闭按钮
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vbox.add_child(head)
	var title := UIFactoryScript.shadow_label("加载战场（JSON）", 14, ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := UIFactoryScript.button("✕ 关闭", func(): close(hud))
	head.add_child(close_btn)

	var subtitle := UIFactoryScript.shadow_label("data/battlefields/*.json · 独立场景模式 · O/ESC 关闭", 10, TEXT_SECONDARY)
	vbox.add_child(subtitle)

	# 可滚动列表
	var scroll := ScrollContainer.new()
	scroll.name = "BattlefieldScroll"
	scroll.custom_minimum_size = Vector2(0.0, 300.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "BattlefieldList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	# 错误提示行（加载失败时由 main.gd 回填）
	hud._battlefield_error_label = UIFactoryScript.shadow_label("", 11, ERROR_COLOR)
	hud._battlefield_error_label.visible = false
	vbox.add_child(hud._battlefield_error_label)

	# 编辑器入口：打开战场地图编辑器（种子生成地形 / 涂地形 / 放阵营角色，保存即出现在本列表）
	var editor_btn := UIFactoryScript.button("🛠 打开地图编辑器",
		func(): hud.editor_requested.emit())
	editor_btn.name = "OpenEditorBtn"
	vbox.add_child(editor_btn)

	# 填充列表（L1 埋点：面板打开时打印条目数，方便确认扫描正常）
	var battlefields: Array = BattlefieldLoaderScript.list_battlefields()
	print("[hud] 战场列表打开：data/battlefields/ 共 %d 个" % battlefields.size())
	if battlefields.is_empty():
		list.add_child(UIFactoryScript.shadow_label("（data/battlefields/ 下没有 *.json）", 11, TEXT_SECONDARY))
		return
	for entry in battlefields:
		list.add_child(_make_entry(hud, entry))


## 单个战场条目：按钮（名称 + 规模）+ 描述行；解析失败的条目置灰
static func _make_entry(hud: CanvasLayer, entry: Dictionary) -> Control:
	var item := VBoxContainer.new()
	item.add_theme_constant_override("separation", 1)

	var btn := UIFactoryScript.button()
	btn.text = "%s   （%d×%d · 我方%d/敌方%d）" % [
		entry.get("name", ""), entry.get("width", 0), entry.get("height", 0),
		entry.get("players", 0), entry.get("enemies", 0),
	]
	btn.add_theme_font_size_override("font_size", 13)
	var err := String(entry.get("error", ""))
	var path := String(entry.get("path", ""))
	if not err.is_empty():
		btn.disabled = true
	else:
		btn.pressed.connect(func():
			# 不主动关面板：成功时切场景整个 HUD 会被释放，失败时留面板显示错误
			hud.battlefield_picked.emit(path)
		)
	item.add_child(btn)

	var desc := String(entry.get("description", ""))
	if not err.is_empty():
		desc = "⚠ " + err
	if not desc.is_empty():
		item.add_child(UIFactoryScript.shadow_label("    " + desc, 10, ERROR_COLOR if not err.is_empty() else TEXT_SECONDARY))
	return item
