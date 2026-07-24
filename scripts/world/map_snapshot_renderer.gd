extends RefCounted

## 将无限世界的已探索颜色缓存压缩为一张有限位图。
## 每次打开地图只生成一个 Image/ImageTexture，不创建任何地块或 Sprite 节点。

const DEFAULT_MAX_EDGE := 512
const UNKNOWN_COLOR := Color.BLACK
const PLAYER_COLOR := Color(1.0, 0.25, 0.18, 1.0)


func render(
	explored_colors: Dictionary,
	player_cell: Vector2i,
	max_edge := DEFAULT_MAX_EDGE,
	display_bounds := Rect2i()
) -> Dictionary:
	var cells: Array[Vector2i] = []
	for cell_value in explored_colors.keys():
		if (
			cell_value is Vector2i
			and (not display_bounds.has_area() or display_bounds.has_point(cell_value))
		):
			cells.append(cell_value)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)

	var min_cell := player_cell
	var span := Vector2i.ONE
	if display_bounds.has_area():
		min_cell = display_bounds.position
		span = display_bounds.size
	else:
		var max_cell := player_cell
		for cell in cells:
			min_cell.x = mini(min_cell.x, cell.x)
			min_cell.y = mini(min_cell.y, cell.y)
			max_cell.x = maxi(max_cell.x, cell.x)
			max_cell.y = maxi(max_cell.y, cell.y)
		span = max_cell - min_cell + Vector2i.ONE
	var safe_max_edge := maxi(1, int(max_edge))
	var scale := minf(
		1.0,
		float(safe_max_edge) / float(maxi(span.x, span.y))
	)
	var image_size := Vector2i(
		maxi(1, ceili(float(span.x) * scale)),
		maxi(1, ceili(float(span.y) * scale))
	)
	var image := Image.create(
		image_size.x,
		image_size.y,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(UNKNOWN_COLOR)

	# 大范围下采样时多个格可能落到同一像素；取平均色，且先排序保证稳定。
	var color_sums := {}
	var color_counts := {}
	for cell in cells:
		var pixel := _cell_to_pixel(cell, min_cell, span, image_size)
		var pixel_index := pixel.y * image_size.x + pixel.x
		var current_sum: Color = color_sums.get(
			pixel_index,
			Color(0.0, 0.0, 0.0, 0.0)
		)
		color_sums[pixel_index] = current_sum + _color_value(
			explored_colors[cell]
		)
		color_counts[pixel_index] = int(color_counts.get(pixel_index, 0)) + 1
	for pixel_index_value in color_sums.keys():
		var pixel_index := int(pixel_index_value)
		var count := maxi(1, int(color_counts[pixel_index]))
		var sum: Color = color_sums[pixel_index]
		var color := Color(
			sum.r / count,
			sum.g / count,
			sum.b / count,
			1.0
		)
		image.set_pixel(
			pixel_index % image_size.x,
			floori(float(pixel_index) / float(image_size.x)),
			color
		)

	var player_pixel := _cell_to_pixel(player_cell, min_cell, span, image_size)
	var raster_bounds := Rect2i(min_cell, span)
	return {
		"image": image,
		"bounds": raster_bounds,
		"raster_bounds": raster_bounds,
		"player_pixel": player_pixel,
		"cell_count": cells.size(),
	}


func _cell_to_pixel(
	cell: Vector2i,
	min_cell: Vector2i,
	span: Vector2i,
	image_size: Vector2i
) -> Vector2i:
	var px := 0
	var py := 0
	if span.x > 1 and image_size.x > 1:
		px = roundi(
			float(cell.x - min_cell.x) / float(span.x - 1) * float(image_size.x - 1)
		)
	if span.y > 1 and image_size.y > 1:
		py = roundi(
			float(cell.y - min_cell.y) / float(span.y - 1) * float(image_size.y - 1)
		)
	return Vector2i(
		clampi(px, 0, image_size.x - 1),
		clampi(py, 0, image_size.y - 1)
	)


func _color_value(value: Variant) -> Color:
	if value is Color:
		var color: Color = value
		color.a = 1.0
		return color
	if value is Dictionary and value.get("color", null) is Color:
		var dictionary_color: Color = value["color"]
		dictionary_color.a = 1.0
		return dictionary_color
	return UNKNOWN_COLOR
