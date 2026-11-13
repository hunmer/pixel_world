## home_entry.gd — 游戏入场页（全屏奇幻背景 + 屏幕中央纵向占位菜单）
##
## 职责：
##   - assets/bg/home-background.png 全屏等比居中（不裁剪、不拉伸；图外暗色兜底）
##   - 背景图顶部已含金色「奇幻大陆」标题，本脚本不叠加任何标题文字
##   - 屏幕中央（背景山谷留白区）放纵向按钮列表，按钮功能仅占位：
##     点击/键盘确认后仅弹出轻量 Toast 提示，不跳转、不读档、不真退出
##   - 默认焦点落在首个按钮，支持键盘/手柄上下导航与 hover/pressed/focus 三态区分
##   - 全部用锚点 + 容器布局，窗口尺寸变化时保持居中、不溢出
##
## 打开方式：编辑器按 F6 运行当前场景，或
##   dbg_launch({"scene":"res://scenes/HomeEntry.tscn"})。
## 注意：不改动 project.godot 默认主场景（当前为 scenes/Game.tscn）。

extends Control

const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")

const BG_PATH := "res://assets/bg/home-background.png"
## 按钮列整体下移比例（占视口高）：背景顶部 ~19% 是标题，中央山谷留白在 0.55 高度附近，
## 菜单列中心压到约 0.60 处，既不遮挡标题也避开两侧角色。
const VALLEY_BIAS := 0.20
const TOAST_SECONDS := 1.8

var _buttons: Array[Button] = []
var _toast: Label
var _toast_seq := 0


func _ready() -> void:
	_build_background()
	_build_menu()
	_build_toast()
	_update_valley_bias()
	resized.connect(_update_valley_bias)
	# 场景树装配完成后聚焦首个按钮（call_deferred 避免 ready 链中抢焦点失败）
	call_deferred("_focus_first")


# ============================================================
# 背景
# ============================================================

func _build_background() -> void:
	# 图外区域（窄屏/竖屏时）用接近原画夜色的暗色兜底，不出现裸边
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.02, 0.03, 0.06)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var bg := TextureRect.new()
	bg.name = "Background"
	if ResourceLoader.exists(BG_PATH):
		bg.texture = load(BG_PATH)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 等比居中：完整显示整张图（含顶部标题），不裁剪不拉伸；比例不同时两侧留边由暗色兜底
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


# ============================================================
# 中央纵向菜单
# ============================================================

func _build_menu() -> void:
	var center := CenterContainer.new()
	center.name = "MenuCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var list := VBoxContainer.new()
	list.name = "MenuList"
	list.alignment = BoxContainer.ALIGNMENT_CENTER
	list.add_theme_constant_override("separation", 18)
	center.add_child(list)

	# 顺序即键盘/手柄上下导航顺序；功能全部占位
	var items: Array = [
		["开始游戏", "BtnStart"],
		["继续游戏", "BtnContinue"],
		["设置", "BtnSettings"],
		["退出", "BtnQuit"],
	]
	for item in items:
		var caption: String = item[0]
		var btn := UIFactoryScript.button(caption, _on_placeholder.bind(caption))
		btn.name = item[1]
		btn.custom_minimum_size = Vector2(280, 56)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.add_theme_font_size_override("font_size", 20)
		btn.focus_mode = Control.FOCUS_ALL
		list.add_child(btn)
		_buttons.append(btn)


## 菜单列整体下移到山谷留白区；锚点全铺 + 顶部 offset，水平始终居中。
func _update_valley_bias() -> void:
	var center := get_node_or_null("MenuCenter") as CenterContainer
	if center != null:
		center.offset_top = size.y * VALLEY_BIAS


func _focus_first() -> void:
	if not _buttons.is_empty() and is_instance_valid(_buttons[0]):
		_buttons[0].grab_focus()


# ============================================================
# 占位反馈（Toast）
# ============================================================

func _build_toast() -> void:
	_toast = UIFactoryScript.outline_label("", 15, UIThemeScript.TOAST_COLOR, 4)
	_toast.name = "Toast"
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_top = -72.0
	_toast.offset_bottom = -32.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	add_child(_toast)


## 轻量占位反馈：底部淡显提示，TOAST_SECONDS 秒后自动消失；重复点击重置计时。
func _show_toast(text: String) -> void:
	_toast_seq += 1
	var seq := _toast_seq
	_toast.text = text
	_toast.visible = true
	await get_tree().create_timer(TOAST_SECONDS).timeout
	if seq == _toast_seq and is_instance_valid(_toast):
		_toast.visible = false


# ============================================================
# 按钮占位处理
# ============================================================

func _on_placeholder(caption: String) -> void:
	_show_toast("「%s」功能为占位，暂未实现" % caption)
