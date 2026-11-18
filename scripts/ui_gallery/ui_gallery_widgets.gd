## ui_gallery/ui_gallery_widgets.gd — 画廊共享构建工具（从 ui_component_gallery.gd 拆出）
##
## 职责：无状态静态工具——生成 PixelButton、实例化 PixelPanel 卡片、取卡片内容槽。
## 画廊宿主（scripts/scenes/ui_component_gallery.gd）与 scripts/ui_gallery/ 各页签模块共用；
## 不持有任何节点或演示状态，全部输入走参数、输出走返回值。
class_name UiGalleryWidgets
extends RefCounted

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const PixelButtonScript = preload("res://ui/components/pixel_button.gd")
const PixelPanelScene = preload("res://ui/components/pixel_panel.tscn")


## 生成一个 PixelButton（不依赖全局类名，统一走 preload 脚本 + 动态属性）。
static func make_pixel_button(
	label_text: String, semantic: int, icon_name: String = "", icon_size: int = 0
) -> Button:
	var btn: Button = PixelButtonScript.new()
	btn.text = label_text
	btn.set("semantic", semantic)
	if not icon_name.is_empty():
		btn.icon = UIThemeScript.icon(icon_name)
	if icon_size > 0:
		btn.set("icon_size", icon_size)
	return btn


## 实例化卡片 PackedScene 并写入短标题；内容由调用方通过 card_slot 注入。
static func make_card(title_text: String, description_text: String) -> PanelContainer:
	var panel: PanelContainer = PixelPanelScene.instantiate() as PanelContainer
	panel.set("title", title_text)
	panel.set("description", description_text)
	return panel


static func card_slot(card: PanelContainer) -> Container:
	return card.call("get_content_slot") as Container
