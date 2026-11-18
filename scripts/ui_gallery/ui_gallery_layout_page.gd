## ui_gallery/ui_gallery_layout_page.gd — 画廊布局页（从 ui_component_gallery.gd 拆出）
##
## 职责：第 7 页「布局」——六个布局容器的真实摆位（HBox/VBox/Grid/Margin/Center/Scroll）。
## 每个容器装进独立卡片，演示默认间距参数（PixelHBox/PixelVBox gap=16、PixelGrid
## h_gap/v_gap=16、PixelMargin margin=24）与滚动容器仅纵向滚动的默认行为。
##
## 设计：RefCounted 能力模块（ui_component_gallery 拆分件）。宿主经 setup() 注入 self，
## duck-typed 调用宿主公开面 add_gallery_tab；卡片 / 按钮工具复用 UiGalleryWidgets。
## 本页为纯静态演示，无状态、无回调，故不提供 reset。
class_name UiGalleryLayoutPage
extends RefCounted

const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const PixelHBoxScript = preload("res://ui/components/pixel_h_box.gd")
const PixelVBoxScript = preload("res://ui/components/pixel_v_box.gd")
const PixelGridScript = preload("res://ui/components/pixel_grid.gd")
const PixelMarginScript = preload("res://ui/components/pixel_margin.gd")
const PixelCenterScript = preload("res://ui/components/pixel_center.gd")
const PixelScrollScript = preload("res://ui/components/pixel_scroll.gd")

## 本模块负责的页签标题。
const TAB_TITLE: String = "布局"

## 宿主画廊（duck-typed 动态访问 add_gallery_tab）。
var _host = null


func setup(p_host) -> void:
	_host = p_host


## 构建布局页：六个容器卡片依次入页。
func build() -> void:
	var page: VBoxContainer = _host.add_gallery_tab(TAB_TITLE)
	page.add_theme_constant_override("separation", 12)

	# PixelHBox：横向排布，子项间距走 gap（默认 16）。
	var hbox_card := UiGalleryWidgets.make_card("横排", "")
	var hbox := PixelHBoxScript.new() as HBoxContainer
	hbox.name = "LayoutHBox"
	hbox.add_child(_make_layout_chip("甲"))
	hbox.add_child(_make_layout_chip("乙"))
	hbox.add_child(_make_layout_chip("丙"))
	UiGalleryWidgets.card_slot(hbox_card).add_child(hbox)
	page.add_child(hbox_card)

	# PixelVBox：纵向排布，子项间距走 gap（默认 16）。
	var vbox_card := UiGalleryWidgets.make_card("竖排", "")
	var vbox := PixelVBoxScript.new() as VBoxContainer
	vbox.name = "LayoutVBox"
	vbox.add_child(_make_layout_chip("丁"))
	vbox.add_child(_make_layout_chip("戊"))
	UiGalleryWidgets.card_slot(vbox_card).add_child(vbox)
	page.add_child(vbox_card)

	# PixelGrid：两列网格，横纵间距走 h_gap / v_gap（默认 16）。
	var grid_card := UiGalleryWidgets.make_card("网格", "")
	var grid := PixelGridScript.new() as GridContainer
	grid.name = "LayoutGrid"
	grid.columns = 2
	for chip_name: String in ["己", "庚", "辛", "壬"]:
		grid.add_child(_make_layout_chip(chip_name))
	UiGalleryWidgets.card_slot(grid_card).add_child(grid)
	page.add_child(grid_card)

	# PixelMargin：内容边距走 margin（默认 24），子项整体内缩。
	var margin_card := UiGalleryWidgets.make_card("边距", "")
	var margin_box := PixelMarginScript.new() as MarginContainer
	margin_box.name = "LayoutMargin"
	var margin_label := UIFactoryScript.label("边距 24", 12, UIThemeScript.TEXT_MAIN)
	margin_label.name = "LayoutMarginChild"
	margin_box.add_child(margin_label)
	UiGalleryWidgets.card_slot(margin_card).add_child(margin_box)
	page.add_child(margin_card)

	# PixelCenter：子项在剩余空间内水平垂直居中。
	var center_card := UiGalleryWidgets.make_card("居中", "")
	var center_box := PixelCenterScript.new() as CenterContainer
	center_box.name = "LayoutCenter"
	center_box.custom_minimum_size = Vector2(0, 64)
	var center_child := UiGalleryWidgets.make_pixel_button("居中", 1, "")
	center_child.name = "LayoutCenterChild"
	center_box.add_child(center_child)
	UiGalleryWidgets.card_slot(center_card).add_child(center_box)
	page.add_child(center_card)

	# PixelScroll：默认仅纵向滚动、双向 Expand Fill；内容高于可视区时出纵滚动条。
	var scroll_card := UiGalleryWidgets.make_card("滚动", "")
	var scroll := PixelScrollScript.new() as ScrollContainer
	scroll.name = "LayoutScroll"
	scroll.custom_minimum_size = Vector2(0, 140)
	var scroll_content := PixelVBoxScript.new() as VBoxContainer
	scroll_content.name = "LayoutScrollContent"
	for i: int in range(6):
		var row := UIFactoryScript.label("滚动内容 %d" % (i + 1), 12, UIThemeScript.TEXT_MAIN)
		row.custom_minimum_size = Vector2(200, 40)
		scroll_content.add_child(row)
	scroll.add_child(scroll_content)
	UiGalleryWidgets.card_slot(scroll_card).add_child(scroll)
	page.add_child(scroll_card)


## 布局页演示用小块：固定最小尺寸的短文本标签，保证间距断言可计算。
func _make_layout_chip(chip_text: String) -> Label:
	var chip := UIFactoryScript.label(chip_text, 12, UIThemeScript.TEXT_MAIN)
	chip.custom_minimum_size = Vector2(40, 20)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return chip
