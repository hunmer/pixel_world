## map_editor_buildings.gd — 地形页建筑素材分组、缩略图与选中回显
##
## 全部 static，ed=map_editor 实例。列表与缩略图共用场景持有的素材服务/适配器；
## 背面依赖只作为正面建筑的渲染资源，不作为独立可放置素材重复列出。

class_name MapEditorBuildings
extends RefCounted

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const PixelGridScript = preload("res://ui/components/pixel_grid.gd")

const GRID_COLUMNS: int = 3
const THUMB_SIZE: Vector2i = Vector2i(
	ComponentThemeScript.DEFAULT_ICON_SIZE * 4,
	ComponentThemeScript.DEFAULT_ICON_SIZE * 4
)


## 地形组之后、植物组之前插入；列表内容由 rebuild 统一填充。
static func build(ed, tab: VBoxContainer) -> void:
	tab.add_child(UIFactoryScript.label(
		"建筑（整栋放置，T 换朝向）",
		ComponentThemeScript.FONT_CAPTION,
		UIThemeScript.TEXT_DIM
	))
	var grid := PixelGridScript.new()
	grid.name = "BuildingGrid"
	grid.columns = GRID_COLUMNS
	grid.h_gap = ComponentThemeScript.SPACE_XS
	grid.v_gap = ComponentThemeScript.SPACE_XS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ed._building_grid = grid
	ed._building_buttons = {}
	tab.add_child(grid)
	rebuild(ed)


## 全量重建建筑按钮；一次 resolve_many 批量解析缩略图，避免逐素材重读素材库。
static func rebuild(ed) -> void:
	if ed._building_grid == null or ed._asset_service == null or ed._asset_adapter == null:
		return
	for child: Node in ed._building_grid.get_children():
		ed._building_grid.remove_child(child)
		child.queue_free()
	ed._building_buttons.clear()

	var assets: Array = ed._asset_service.list_assets()
	var back_asset_ids: Dictionary = {}
	for raw in assets:
		if not raw is Dictionary:
			continue
		var descriptor: Dictionary = raw
		if String(descriptor.get("kind", "")) != "building":
			continue
		var back_id := String(descriptor.get("render", {}).get("back_asset_id", ""))
		if not back_id.is_empty():
			back_asset_ids[back_id] = true

	var buildings: Array[Dictionary] = []
	for raw in assets:
		if not raw is Dictionary:
			continue
		var descriptor: Dictionary = raw
		var asset_id := String(descriptor.get("id", ""))
		if String(descriptor.get("kind", "")) != "building" or asset_id.is_empty():
			continue
		if back_asset_ids.has(asset_id):
			continue
		buildings.append(descriptor)
	var builtin_id := String(ed._builtin_building_id)
	buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_id := String(a.get("id", ""))
		var b_id := String(b.get("id", ""))
		if a_id == builtin_id and b_id != builtin_id:
			return true
		if b_id == builtin_id and a_id != builtin_id:
			return false
		return a_id < b_id)

	var ids: Array = []
	for descriptor: Dictionary in buildings:
		ids.append(String(descriptor.get("id", "")))
	var visuals: Dictionary = ed._asset_adapter.resolve_many(ids, false)
	for descriptor: Dictionary in buildings:
		var asset_id := String(descriptor.get("id", ""))
		var visual: Dictionary = visuals.get(asset_id, {})
		var button := _building_button(ed, descriptor, visual)
		ed._building_grid.add_child(button)
		ed._building_buttons[asset_id] = button
	sync_selection(ed)


static func _building_button(ed, descriptor: Dictionary, visual: Dictionary) -> Button:
	var asset_id := String(descriptor.get("id", ""))
	var display_name := String(descriptor.get("name", asset_id))
	if asset_id == String(ed._builtin_building_id):
		display_name = "石墙"
	var button: Button = UIFactoryScript.button("", Callable(), "", false)
	button.toggle_mode = true
	if ed._terrain_group != null:
		button.button_group = ed._terrain_group
	button.custom_minimum_size = Vector2(THUMB_SIZE) + Vector2(ComponentThemeScript.SPACE_MD, 0)
	button.text = display_name
	button.clip_text = true
	button.tooltip_text = "%s（%s）" % [display_name, asset_id]
	button.set_meta("kind", "building")
	button.set_meta("asset_id", asset_id)
	var texture: Variant = visual.get("texture")
	if texture is Texture2D:
		button.icon = texture
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", THUMB_SIZE.x)
	button.pressed.connect(func() -> void:
		ed._on_building_selected(asset_id))
	return button


## 素材页与地形页共用 _selected_asset；仅回显，不触发选择回调。
static func sync_selection(ed) -> void:
	var selected_id := String(ed._selected_asset.get("id", ""))
	for raw_id in ed._building_buttons:
		var button: Button = ed._building_buttons[raw_id]
		if is_instance_valid(button):
			button.set_pressed_no_signal(String(raw_id) == selected_id)
