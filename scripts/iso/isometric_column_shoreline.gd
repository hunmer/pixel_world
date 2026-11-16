extends RefCounted

## isometric_column_shoreline.gd — 岸线白浪与水面涟漪的 CanvasItem 绘制命令层。
##
## 纯静态、无状态：所有几何/相位常量在这里集中，绘制函数接收 canvas（柱体节点）
## 与主文件算好的顶面角点，逐条生成 draw_multiline / draw_arc 命令。
## 潮汐相位、确定性 _rand(seed, salt) 与分段曲线形状是像素契约，改动即回归。

const SHORELINE_FRAME_COUNT := 4
const SHORELINE_FRAME_SECONDS := 0.34
const SHORELINE_COLOR := Color(0.94, 0.98, 1.0, 0.96)
const SHORELINE_LINE_WIDTH := 0.50
const SHORELINE_EDGE_COVERAGE := 0.50
const SHORELINE_HALF_LENGTH_MIN := 3.4
const SHORELINE_HALF_LENGTH_MAX := 5.3
const SHORELINE_TIDE_PHASES := [0.08, 0.54, 1.0, 0.38]
const SHORELINE_TIDE_ALPHA_PHASES := [0.96, 1.0, 1.0, 0.98]
const SHORELINE_EVEN_ALPHA_PHASES := [1.0, 0.68, 0.05, 0.68]
const SHORELINE_ODD_ALPHA_PHASES := [0.05, 0.68, 1.0, 0.68]
const SHORELINE_SEGMENT_COUNT_MIN := 5
const SHORELINE_SEGMENT_COUNT_MAX := 6
const RIPPLE_SEGMENTS := 18


## 岸线循环由 RenderingServer 的 animation slice 驱动，不让每个岸线格都进入
## _process()；每帧一个切片，相位按相邻格交错。
static func draw_foam(
	canvas: CanvasItem,
	surface_center: Vector2,
	edge_mask: int,
	seed: int,
	corners: PackedVector2Array
) -> void:
	if edge_mask == 0:
		return
	var cycle_seconds := SHORELINE_FRAME_COUNT * SHORELINE_FRAME_SECONDS
	# 相邻格仅分成两个交错相位，再叠加极小时间偏移。比每格完全随机闪烁
	# 更像沿岸传播的潮汐，同时不会让整条岸线同步亮灭。
	var phase_step := 0 if rand(seed, 211) < 0.5 else 2
	var phase_offset := (
		float(phase_step) * SHORELINE_FRAME_SECONDS
		+ rand(seed, 213) * SHORELINE_FRAME_SECONDS * 0.08
	)
	for frame in SHORELINE_FRAME_COUNT:
		canvas.draw_animation_slice(
			cycle_seconds,
			float(frame) * SHORELINE_FRAME_SECONDS,
			float(frame + 1) * SHORELINE_FRAME_SECONDS,
			phase_offset
		)
		_draw_frame(canvas, surface_center, edge_mask, seed, frame, corners)
	# 后续雨滴水波必须恢复普通绘制，否则也会被最后一个动画切片过滤。
	canvas.draw_end_animation()


static func _draw_frame(
	canvas: CanvasItem,
	surface_center: Vector2,
	edge_mask: int,
	seed: int,
	animation_step: int,
	corners: PackedVector2Array
) -> void:
	var vertices := [
		corners[3],
		corners[0],
		corners[1],
		corners[2],
	]
	var edges := [
		[vertices[0], vertices[1]],
		[vertices[1], vertices[2]],
		[vertices[2], vertices[3]],
		[vertices[3], vertices[0]],
	]
	for edge_index in _active_edges(seed, edge_mask):
		_draw_edge_foam(canvas, surface_center, edges[edge_index], edge_index, seed, animation_step)


## 仅约半数接岸边生成浪花，静态缺口会打破连续描边感；拐角通常只保留一小段，
## 避免两条边叠成醒目的白色 V，少量拐角保留第二段让长岸线仍有自然局部变化。
static func _active_edges(seed: int, edge_mask: int) -> Array[int]:
	var active_edges: Array[int] = []
	for edge_index in 4:
		if (edge_mask & (1 << edge_index)) == 0:
			continue
		if rand(seed, edge_index * 41 + 3) > SHORELINE_EDGE_COVERAGE:
			continue
		active_edges.append(edge_index)
	if active_edges.size() > 1:
		var first_index := mini(
			int(rand(seed, 223) * float(active_edges.size())),
			active_edges.size() - 1
		)
		var selected_edges: Array[int] = [active_edges[first_index]]
		if rand(seed, 227) > 0.82:
			selected_edges.append(active_edges[(first_index + 1) % active_edges.size()])
		active_edges = selected_edges
	return active_edges


## 波纹中心保持稳定，只沿岸线伸展、向水内涨起后退回；这样更像一次小潮汐
## 呼吸，而不是短线沿菱形边机械滑动。
static func _draw_edge_foam(
	canvas: CanvasItem,
	surface_center: Vector2,
	edge: Array,
	edge_index: int,
	seed: int,
	animation_step: int
) -> void:
	var start: Vector2 = surface_center + Vector2(edge[0])
	var finish: Vector2 = surface_center + Vector2(edge[1])
	var tangent: Vector2 = (finish - start).normalized()
	var inward: Vector2 = (surface_center - (start + finish) * 0.5).normalized()
	var salt: int = edge_index * 97
	var center_t: float = 0.28 + rand(seed, salt + 13) * 0.44
	var center: Vector2 = start.lerp(finish, center_t)
	var phase: int = posmod(animation_step, SHORELINE_FRAME_COUNT)
	var tide: float = float(SHORELINE_TIDE_PHASES[phase])
	var fade: float = float(SHORELINE_TIDE_ALPHA_PHASES[phase])
	var half_length: float = lerpf(
		SHORELINE_HALF_LENGTH_MIN,
		SHORELINE_HALF_LENGTH_MAX,
		rand(seed, salt + 17)
	) * lerpf(0.68, 1.0, tide)
	var inset: float = 0.34 + tide * 1.72
	var bend: float = lerpf(0.42, 0.88, rand(seed, salt + 23)) * lerpf(0.42, 1.0, tide)
	var shape_variant := mini(int(rand(seed, salt + 29) * 3.0), 2)
	var shape_mirrored := rand(seed, salt + 31) < 0.5
	var segment_count := mini(
		SHORELINE_SEGMENT_COUNT_MIN
		+ int(
			rand(seed, salt + 37)
			* float(SHORELINE_SEGMENT_COUNT_MAX - SHORELINE_SEGMENT_COUNT_MIN + 1)
		),
		SHORELINE_SEGMENT_COUNT_MAX
	)
	var segments := _edge_segments(
		center,
		tangent,
		inward,
		half_length,
		inset,
		bend,
		shape_variant,
		shape_mirrored,
		seed,
		salt,
		segment_count,
		tide
	)
	var even_color := SHORELINE_COLOR
	even_color.a *= fade * float(SHORELINE_EVEN_ALPHA_PHASES[phase])
	var odd_color := SHORELINE_COLOR
	odd_color.a *= fade * float(SHORELINE_ODD_ALPHA_PHASES[phase])
	# A/B 两组分别批绘。它们沿曲线天然错开一个槽位：A 退暗时 B 变亮，
	# 位置会移动；绘制调用仍固定为每帧最多两次。
	if not (segments["even"] as PackedVector2Array).is_empty():
		canvas.draw_multiline(
			segments["even"],
			even_color,
			SHORELINE_LINE_WIDTH,
			true
		)
	if not (segments["odd"] as PackedVector2Array).is_empty():
		canvas.draw_multiline(
			segments["odd"],
			odd_color,
			SHORELINE_LINE_WIDTH,
			true
		)


static func _edge_segments(
	center: Vector2,
	tangent: Vector2,
	inward: Vector2,
	half_length: float,
	inset: float,
	bend: float,
	shape_variant: int,
	shape_mirrored: bool,
	seed: int,
	salt: int,
	segment_count: int,
	tide: float
) -> Dictionary:
	var even_segments := PackedVector2Array()
	var odd_segments := PackedVector2Array()
	var slot_width := 2.0 / float(segment_count)
	for segment_index in segment_count:
		var segment_salt := salt + 101 + segment_index * 17
		var center_u := (
			-1.0
			+ (float(segment_index) + 0.5) * slot_width
			+ lerpf(
				-slot_width * 0.055,
				slot_width * 0.055,
				rand(seed, segment_salt)
			)
		)
		var half_segment_u := slot_width * lerpf(
			0.34,
			0.43,
			rand(seed, segment_salt + 3)
		)
		var group_inset := (
			0.0
			if segment_index % 2 == 0
			else lerpf(0.22, 0.68, tide)
		)
		var point_a := curve_point(
			center,
			tangent,
			inward,
			half_length,
			clampf(center_u - half_segment_u, -1.0, 1.0),
			inset + group_inset,
			bend,
			shape_variant,
			shape_mirrored
		)
		var point_b := curve_point(
			center,
			tangent,
			inward,
			half_length,
			clampf(center_u + half_segment_u, -1.0, 1.0),
			inset + group_inset,
			bend,
			shape_variant,
			shape_mirrored
		)
		if segment_index % 2 == 0:
			even_segments.append(point_a)
			even_segments.append(point_b)
		else:
			odd_segments.append(point_a)
			odd_segments.append(point_b)
	return {"even": even_segments, "odd": odd_segments}


static func curve_point(
	center: Vector2,
	tangent: Vector2,
	inward: Vector2,
	half_length: float,
	normalized_position: float,
	inset: float,
	bend: float,
	shape_variant: int,
	mirrored: bool
) -> Vector2:
	var u := clampf(normalized_position, -1.0, 1.0)
	var base_curve := maxf(0.0, 1.0 - u * u)
	var curve_amount: float
	match shape_variant:
		1:
			var direction := -u if mirrored else u
			curve_amount = base_curve * (0.72 + direction * 0.28)
		2:
			# 宽而平缓的弧，与普通抛物线形成明显轮廓差异。
			curve_amount = pow(base_curve, 0.56) * 0.88
		_:
			curve_amount = base_curve
	return (
		center
		+ tangent * (half_length * u)
		+ inward * (inset + bend * curve_amount)
	)


static func rand(seed: int, salt: int) -> float:
	var mixed := int(hash(Vector3i(seed, salt, seed ^ (salt * 31))))
	return float(mixed & 0xFFFF) / 65535.0


## 涟漪属于当前水柱，并在水面贴图之后、同格水面植物之前绘制。
## 这样无需额外节点，也不会破坏外层地块/动物的 Y-sort 遮挡关系。
static func draw_water_ripples(
	canvas: CanvasItem,
	water_ripples: Array[Dictionary],
	surface_center: Vector2
) -> void:
	for ripple in water_ripples:
		var lifetime: float = ripple["lifetime"]
		var progress := clampf(float(ripple["age"]) / lifetime, 0.0, 1.0)
		var expansion := 1.0 - pow(1.0 - progress, 2.0)
		var fade := pow(1.0 - progress, 1.7) * float(ripple["strength"])
		var maximum_radius: float = ripple["maximum_radius"]
		var radius_x := lerpf(1.2, maximum_radius, expansion)
		var radius_y := radius_x * 0.46
		var center := surface_center + Vector2(ripple["offset"])
		var color := Color(0.72, 0.91, 1.0, fade * 0.68)
		if ripple["kind"] == &"snow":
			color = Color(0.91, 0.97, 1.0, fade * 0.36)
		_draw_ellipse(canvas, center, radius_x, radius_y, color, 0.72)

		# 第二道较淡的尾环让雨点命中不只是一个机械扩张圆。
		if progress > 0.18:
			var tail_progress := (progress - 0.18) / 0.82
			var tail_expansion := 1.0 - pow(1.0 - tail_progress, 2.0)
			var tail_radius_x := lerpf(0.8, maximum_radius * 0.72, tail_expansion)
			var tail_color := color
			tail_color.a *= (1.0 - tail_progress) * 0.52
			_draw_ellipse(
				canvas,
				center,
				tail_radius_x,
				tail_radius_x * 0.46,
				tail_color,
				0.58
			)

		if ripple["kind"] == &"rain" and progress < 0.12:
			var splash_height := (1.0 - progress / 0.12) * 3.5
			canvas.draw_line(
				center - Vector2(0.0, splash_height),
				center + Vector2(0.0, 0.4),
				Color(0.78, 0.94, 1.0, fade * 0.72),
				0.72,
				true
			)


static func _draw_ellipse(
	canvas: CanvasItem,
	center: Vector2,
	radius_x: float,
	radius_y: float,
	color: Color,
	width: float
) -> void:
	if radius_x <= 0.0 or radius_y <= 0.0:
		return
	# 使用 Canvas 变换把单个 draw_arc 压成椭圆，避免每圈、每帧分配
	# PackedVector2Array 并在 GDScript 中重复计算 sin/cos。
	canvas.draw_set_transform(center, 0.0, Vector2(1.0, radius_y / radius_x))
	canvas.draw_arc(Vector2.ZERO, radius_x, 0.0, TAU, RIPPLE_SEGMENTS, color, width, true)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
