## ui_gallery/ui_gallery_cursor_page.gd — 画廊鼠标页（从 ui_component_gallery.gd 拆出）
##
## 职责：第 8 页「鼠标」——GameCursor 指针库全部素材的悬停预览网格
## （五列 PixelGrid，悬停即 preview_cursor、移出 restore_cursor）
## + 箭头三色风格（白/蓝/金）切换按钮组（互斥按下态）。
##
## 设计：RefCounted 能力模块（ui_component_gallery 拆分件）。宿主经 setup() 注入 self，
## duck-typed 调用宿主公开面：add_gallery_tab / set_status / log_feedback / gc。
## GameCursor 自动加载可能缺席（_gc() 判空兜底，与拆分前一致）。
class_name UiGalleryCursorPage
extends RefCounted

const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const PixelGridScript = preload("res://ui/components/pixel_grid.gd")
const PixelImageScript = preload("res://ui/components/pixel_image.gd")

## 本模块负责的页签标题。
const TAB_TITLE: String = "鼠标"

## 宿主画廊（duck-typed 动态访问 add_gallery_tab / set_status / log_feedback / gc）。
var _host = null

## 箭头风格按钮组（style_name -> Button），reset 时同步按下态。
var _arrow_style_buttons: Dictionary = {}


func setup(p_host) -> void:
	_host = p_host


## 构建鼠标页：指针素材网格 + 箭头风格按钮行（按钮引用与回调在构建时绑定）。
func build() -> void:
	var page: VBoxContainer = _host.add_gallery_tab(TAB_TITLE)
	page.add_theme_constant_override("separation", 12)

	var cursor_card := UiGalleryWidgets.make_card("指针", "")
	var grid := PixelGridScript.new() as GridContainer
	grid.name = "CursorGrid"
	grid.columns = 5
	var cursor_library: Array = _host.gc().get("CURSOR_LIBRARY") if _host.gc() != null else []
	for item: Dictionary in cursor_library:
		grid.add_child(_make_cursor_cell(item))
	UiGalleryWidgets.card_slot(cursor_card).add_child(grid)
	page.add_child(cursor_card)

	var style_card := UiGalleryWidgets.make_card("箭头风格", "")
	var style_row := HBoxContainer.new()
	style_row.add_theme_constant_override("separation", 10)
	var active_style: String = _host.gc().call("get_arrow_style") if _host.gc() != null else "white"
	for style_name: String in ["white", "blue", "gold"]:
		var btn := UiGalleryWidgets.make_pixel_button(_arrow_style_label(style_name), 1, "")
		btn.name = "ArrowStyle_" + style_name
		btn.toggle_mode = true
		btn.set_pressed_no_signal(style_name == active_style)
		# 按钮引用与回调在构建时绑定（同一批生成，无需集中接线）。
		_arrow_style_buttons[style_name] = btn
		btn.toggled.connect(_on_arrow_style_toggled.bind(style_name))
		style_row.add_child(btn)
	UiGalleryWidgets.card_slot(style_card).add_child(style_row)
	page.add_child(style_card)


## 复位鼠标演示状态：箭头风格回默认、恢复指针、按钮组按下态与 GameCursor 同步。
func reset() -> void:
	if _host.gc() != null:
		_host.gc().call("set_arrow_style", _host.gc().get("DEFAULT_ARROW_STYLE"))
		_host.gc().call("restore_cursor")
		for style_name: String in _arrow_style_buttons:
			(_arrow_style_buttons[style_name] as Button).set_pressed_no_signal(
				style_name == _host.gc().call("get_arrow_style")
			)


## 单个指针格：PixelImage 原尺寸展示 + 短标签；悬停即预览该指针，移出恢复。
func _make_cursor_cell(item: Dictionary) -> Control:
	var cell := PanelContainer.new()
	cell.name = "CursorCell"
	cell.custom_minimum_size = Vector2(84, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var icon := PixelImageScript.new() as Control
	icon.name = "CursorIcon"
	icon.set("texture", item["texture"])
	icon.set("image_size", Vector2i(32, 32))
	box.add_child(icon)
	var caption := UIFactoryScript.label(item["label"], 11, UIThemeScript.TEXT_MAIN)
	caption.name = "CursorLabel"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)
	cell.add_child(box)
	cell.mouse_entered.connect(_on_cursor_cell_entered.bind(item))
	cell.mouse_exited.connect(_on_cursor_cell_exited)
	return cell


func _arrow_style_label(style_name: String) -> String:
	return {"white": "白", "blue": "蓝", "gold": "金"}.get(style_name, style_name)


func _on_cursor_cell_entered(item: Dictionary) -> void:
	if _host.gc() != null:
		_host.gc().call("preview_cursor", item["texture"], item["hotspot"])
	_host.set_status("指针：%s" % item["label"])


func _on_cursor_cell_exited() -> void:
	if _host.gc() != null:
		_host.gc().call("restore_cursor")


func _on_arrow_style_toggled(toggled_on: bool, style_name: String) -> void:
	if _host.gc() == null:
		return
	if not toggled_on:
		# 当前激活风格不允许点击取消，保持按下。
		if style_name == _host.gc().call("get_arrow_style"):
			(_arrow_style_buttons[style_name] as Button).set_pressed_no_signal(true)
		return
	_host.gc().call("set_arrow_style", style_name)
	for other: String in _arrow_style_buttons:
		(_arrow_style_buttons[other] as Button).set_pressed_no_signal(other == style_name)
	_host.set_status("箭头：%s" % _arrow_style_label(style_name))
	_host.log_feedback("箭头风格 → %s" % _arrow_style_label(style_name))
