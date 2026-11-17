@tool
class_name PixelNinePatchFrame
extends PanelContainer

## pixel_ninepatch_frame.gd — 通用「分段九宫格」面板底基类：自绘绘制，
## 固定段（角饰/徽章/端饰）永不变形，拉伸量由弹性段按同一倍率分担。
## 垂直策略分两种（子类覆盖 _stretch_vertically）：中带拉伸（面板框）或整高锁定（名牌）。
## 子类需提供素材表 / 固定段表 / 标签表，并可选覆盖缩放与内边距策略。

## 垂直中带拉伸模式下的上下固定条高度。
const V_BAND: float = 50.0
## 面板框模式的内容内边距。
const CONTENT_PADDING: float = 48.0

@export var frame_key: String = "":
	set(value):
		var next_key: String = _resolve_key(value)
		if next_key == frame_key and is_inside_tree():
			return
		frame_key = next_key
		_refresh()

var _style_placeholder: StyleBoxEmpty

func _init() -> void:
	_style_placeholder = StyleBoxEmpty.new()
	add_theme_stylebox_override("panel", _style_placeholder)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_content_margins()

func _ready() -> void:
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)
	_refresh()

## 素材表：key -> Texture2D（子类覆盖）。
func _get_texture_map() -> Dictionary:
	return {}

## 顶部横向固定保护区表：key -> Array[[起点, 终点], ...]（源像素坐标，子类覆盖）。
func _get_band_map() -> Dictionary:
	return {}

## 中文标签表：key -> String（子类覆盖）。
func _get_label_map() -> Dictionary:
	return {}

## 名义显示缩放（用于最小尺寸与内容内边距估算；子类覆盖）。
func _nominal_scale() -> float:
	return 1.0

## 垂直策略：true = 上条/中带拉伸/下条（面板框）；false = 整高锁定随高度等比缩放（名牌）。
func _stretch_vertically() -> bool:
	return true

## 中带拉伸模式的上下固定条高（子类可覆盖）。
func _vertical_band() -> float:
	return V_BAND

## 内容内边距 (左, 上, 右, 下)（子类可覆盖）。
func _content_insets(_key: String, _scale: float) -> Vector4:
	return Vector4(CONTENT_PADDING, CONTENT_PADDING, CONTENT_PADDING, CONTENT_PADDING)

func _resolve_key(value: String = "") -> String:
	var keys := _get_texture_map().keys()
	if value != "" and _get_texture_map().has(value):
		return value
	return String(keys[0]) if keys.size() > 0 else ""

func get_content_slot() -> PanelContainer:
	return self

func get_frame_label() -> String:
	return String(_get_label_map().get(_resolve_key(frame_key), frame_key))

func _refresh() -> void:
	_apply_content_margins()
	custom_minimum_size = _compute_min_size()
	queue_redraw()

func _apply_content_margins() -> void:
	var insets := _content_insets(_resolve_key(frame_key), _nominal_scale())
	_style_placeholder.content_margin_left = insets.x
	_style_placeholder.content_margin_top = insets.y
	_style_placeholder.content_margin_right = insets.z
	_style_placeholder.content_margin_bottom = insets.w

func _compute_min_size() -> Vector2:
	var key := _resolve_key(frame_key)
	var tex: Texture2D = _get_texture_map().get(key)
	if tex == null:
		return Vector2.ZERO
	var src_size := tex.get_size()
	var fixed_width: float = 0.0
	for band in _get_band_map().get(key, []):
		fixed_width += band[1] - band[0]
	var scale := _nominal_scale()
	var insets := _content_insets(key, scale)
	var base_height: float = _vertical_band() * 2.0 if _stretch_vertically() else src_size.y * scale
	return Vector2(fixed_width * scale + insets.x + insets.z, base_height + insets.y + insets.w)

func _draw() -> void:
	var key := _resolve_key(frame_key)
	var tex: Texture2D = _get_texture_map().get(key)
	if tex == null:
		return
	var src_size := tex.get_size()
	var bands: Array = _get_band_map().get(key, _get_band_map().values()[0] if _get_band_map().size() > 0 else [])
	var hscale: float = 1.0 if _stretch_vertically() else size.y / maxf(src_size.y, 1.0)
	var col_src: Array[float] = []
	var col_dst: Array[float] = []
	_build_axis(bands, src_size.x, size.x / hscale, col_src, col_dst)
	var rows_src: Array[float] = []
	var rows_dst: Array[float] = []
	if _stretch_vertically():
		var band := _vertical_band()
		rows_src.assign([0.0, band, src_size.y - band, src_size.y])
		rows_dst.assign([0.0, band, size.y - band, size.y])
	else:
		rows_src.assign([0.0, src_size.y])
		rows_dst.assign([0.0, src_size.y * hscale])
	for col in col_src.size() - 1:
		var sw: float = col_src[col + 1] - col_src[col]
		var dw: float = (col_dst[col + 1] - col_dst[col]) * hscale
		if sw <= 0.0 or dw <= 0.0:
			continue
		for row in rows_src.size() - 1:
			var sh: float = rows_src[row + 1] - rows_src[row]
			var dh: float = rows_dst[row + 1] - rows_dst[row]
			if sh <= 0.0 or dh <= 0.0:
				continue
			draw_texture_rect_region(
				tex,
				Rect2(col_dst[col] * hscale, rows_dst[row], dw, dh),
				Rect2(col_src[col], rows_src[row], sw, sh)
			)

## 按固定段列表构建一条轴的源/目标边界（源坐标系）：固定段原宽，弹性段等比分担拉伸量。
func _build_axis(bands: Array, src_len: float, dst_len: float, col_src: Array[float], col_dst: Array[float]) -> void:
	var fixed_total: float = 0.0
	for band in bands:
		fixed_total += band[1] - band[0]
	var gap_total: float = maxf(src_len - fixed_total, 0.0)
	var stretch_total: float = maxf(dst_len - fixed_total, 0.0)
	var ratio: float = stretch_total / gap_total if gap_total > 0.0 else 1.0
	var cursor_src: float = 0.0
	var cursor_dst: float = 0.0
	col_src.append(0.0)
	col_dst.append(0.0)
	for band in bands:
		var band_left: float = clampf(band[0], 0.0, src_len)
		var band_right: float = clampf(band[1], 0.0, src_len)
		var gap_src: float = band_left - cursor_src
		if gap_src > 0.5:
			cursor_dst += gap_src * ratio
			cursor_src = band_left
			col_src.append(cursor_src)
			col_dst.append(cursor_dst)
		var band_width: float = band_right - band_left
		if band_width > 0.5:
			cursor_dst += band_width
			cursor_src = band_right
			col_src.append(cursor_src)
			col_dst.append(cursor_dst)
	if src_len - cursor_src > 0.5:
		col_src.append(src_len)
		col_dst.append(cursor_dst + (src_len - cursor_src) * ratio)
