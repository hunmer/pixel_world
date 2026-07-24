extends CanvasLayer

## 已探索世界总览。地图内容是一张基础色位图，UI 不参与世界暂停。

signal open_state_changed(is_open: bool)

const MapSnapshotRendererScript = preload(
	"res://scripts/world/map_snapshot_renderer.gd"
)
const MAP_LAYER := 200
const MAP_DISPLAY_SIZE := Vector2(540.0, 540.0)
const PLAYER_MARKER_SIZE := Vector2(10.0, 10.0)

var _snapshot_renderer = MapSnapshotRendererScript.new()
var _root: Control
var _texture_rect: TextureRect
var _player_marker: PanelContainer
var _status_label: Label
var _map_texture: ImageTexture
var _last_snapshot := {}
var _open := false


func _ready() -> void:
	layer = MAP_LAYER
	_build_ui()


func open_map(
	explored_colors: Dictionary,
	player_cell: Vector2i,
	display_bounds := Rect2i()
) -> void:
	_build_ui()
	_last_snapshot = _snapshot_renderer.render(
		explored_colors,
		player_cell,
		MapSnapshotRendererScript.DEFAULT_MAX_EDGE,
		display_bounds
	)
	var image: Image = _last_snapshot["image"]
	_map_texture = ImageTexture.create_from_image(image)
	_texture_rect.texture = _map_texture
	_position_player_marker(image)
	var bounds: Rect2i = _last_snapshot["bounds"]
	_status_label.text = (
		"已探索 %d 格  ·  覆盖 %d × %d 格  ·  黑色区域尚未探索"
		% [
			int(_last_snapshot["cell_count"]),
			bounds.size.x,
			bounds.size.y,
		]
	)
	_set_open(true)


func close_map() -> void:
	_set_open(false)


func is_open() -> bool:
	return _open


func blocks_world_input() -> bool:
	return _open


func get_map_image() -> Image:
	return _last_snapshot.get("image", null)


func get_render_bounds() -> Rect2i:
	return _last_snapshot.get("bounds", Rect2i())


func get_player_pixel() -> Vector2i:
	return _last_snapshot.get("player_pixel", Vector2i.ZERO)


func get_rendered_cell_count() -> int:
	return int(_last_snapshot.get("cell_count", 0))


func _set_open(value: bool) -> void:
	_build_ui()
	if _open == value:
		return
	_open = value
	_root.visible = value
	open_state_changed.emit(value)


func _build_ui() -> void:
	if _root != null:
		return
	layer = MAP_LAYER
	_root = Control.new()
	_root.name = "WorldMapRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.008, 0.014, 0.022, 0.86)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "MapPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(header)

	var title := _label("世界地图", 22, Color(0.88, 0.95, 0.96))
	title.name = "Title"
	header.add_child(title)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_hint := _label("M / ESC  关闭", 13, Color(1.0, 0.78, 0.34))
	close_hint.name = "CloseHint"
	header.add_child(close_hint)

	var map_frame := PanelContainer.new()
	map_frame.name = "MapFrame"
	map_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_frame.add_theme_stylebox_override("panel", _map_style())
	content.add_child(map_frame)

	_texture_rect = TextureRect.new()
	_texture_rect.name = "MapTexture"
	_texture_rect.custom_minimum_size = MAP_DISPLAY_SIZE
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map_frame.add_child(_texture_rect)
	_player_marker = PanelContainer.new()
	_player_marker.name = "PlayerMarker"
	_player_marker.custom_minimum_size = PLAYER_MARKER_SIZE
	_player_marker.size = PLAYER_MARKER_SIZE
	_player_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_marker.add_theme_stylebox_override("panel", _player_marker_style())
	_texture_rect.add_child(_player_marker)

	_status_label = _label("尚未探索地图", 13, Color(0.58, 0.72, 0.75))
	_status_label.name = "Status"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_status_label)


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override(
		"font_shadow_color",
		Color(0.0, 0.0, 0.0, 0.72)
	)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.075, 0.98)
	style.border_color = Color(0.30, 0.48, 0.54, 0.95)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 18.0
	style.content_margin_top = 14.0
	style.content_margin_right = 18.0
	style.content_margin_bottom = 14.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.68)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0.0, 5.0)
	return style


func _map_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = MapSnapshotRendererScript.UNKNOWN_COLOR
	style.border_color = Color(0.16, 0.25, 0.29, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 4.0
	style.content_margin_top = 4.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 4.0
	return style


func _player_marker_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = MapSnapshotRendererScript.PLAYER_COLOR
	style.border_color = Color(0.38, 0.05, 0.035, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	return style


func _position_player_marker(image: Image) -> void:
	var image_size := Vector2(image.get_width(), image.get_height())
	var scale := minf(
		MAP_DISPLAY_SIZE.x / maxf(1.0, image_size.x),
		MAP_DISPLAY_SIZE.y / maxf(1.0, image_size.y)
	)
	var displayed_size := image_size * scale
	var displayed_origin := (MAP_DISPLAY_SIZE - displayed_size) * 0.5
	var pixel_center := (
		Vector2(get_player_pixel()) + Vector2(0.5, 0.5)
	) * scale
	_player_marker.position = (
		displayed_origin + pixel_center - PLAYER_MARKER_SIZE * 0.5
	)
