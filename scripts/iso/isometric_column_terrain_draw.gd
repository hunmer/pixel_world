extends RefCounted

## isometric_column_terrain_draw.gd — 柱体普通块与投影地形的绘制决策层。
##
## 静态函数集合：负责 _draw 的三条路径——构建/回放缓存绘制计划（无动态遮挡）、
## 逐块即时绘制（含遮挡透明与剖面加深），以及把面交给 ProjectedTerrainBatch。
## 全部状态（块列表、遮挡透明度、缓存）由 isometric_column_batch.gd 装配层持有，
## 经 ctx 字典与参数传入；ctx 键见 _draw_context() 的文档。

const TextureBatch = preload("res://scripts/iso/isometric_column_texture_batch.gd")

const ProjectedTerrainBatch = TextureBatch.ProjectedTerrainBatch


## ctx 约定（由装配层 _draw_context() 构造）：
##   level_height: float          每层像素高度
##   screen_y_offset: float       Y-sort 原点补偿
##   terrain_top_level: int       柱体最高地形层（可见顶面判定）
##   x_positive / y_positive: bool  当前视角基向量 y 分量符号
##   default_projection: bool     是否默认（未旋转）投影
##   top_center_offset: Vector2   顶面中心相对块中心的偏移
##   default_basis_x / default_basis_y: Vector2  默认投影基向量
##   side_exposed: Callable(axis,positive,level)->bool
##   top_corners: Callable(center)->PackedVector2Array  当前投影顶面角点
##   water_effects: Callable(center,block)->void       岸线+水波绘制回调
##   texture_mask: Callable(texture)->Texture2D        剖面用 alpha 蒙版
##   cutaway_shade_color: Color                        剖面深灰基色

static func is_projected_terrain(block: Dictionary) -> bool:
	return (
		block.get("occluder_class", &"") == &"terrain"
		or block.get("water_part", &"") != &""
	)


## 柱内较低方块的顶面被同柱上层占据，不属于可见表面。
## 水面是独立透明表层；湖床顶面仍保留以透过水体显示。
static func is_visible_top(
	water_part: StringName,
	level: int,
	terrain_top_level: int
) -> bool:
	if water_part == &"surface":
		return true
	return water_part == &"" and level == terrain_top_level


static func draw_textured_quad(
	canvas: CanvasItem,
	points: PackedVector2Array,
	uvs: Array,
	texture: Texture2D,
	tint: Color
) -> void:
	canvas.draw_polygon(
		points,
		PackedColorArray([tint, tint, tint, tint]),
		PackedVector2Array(uvs),
		texture
	)


static func draw_terrain_side(
	canvas: CanvasItem,
	texture: Texture2D,
	corners: PackedVector2Array,
	axis: int,
	positive: bool,
	tint: Color,
	level_height: float
) -> void:
	var first := 0
	var second := 0
	var uvs: Array = []
	if axis == 0:
		first = 1 if positive else 0
		second = 2 if positive else 3
		uvs = TextureBatch.RIGHT_SIDE_UV
	else:
		first = 3 if positive else 0
		second = 2 if positive else 1
		uvs = TextureBatch.LEFT_SIDE_UV
	var down := Vector2(0.0, level_height)
	draw_textured_quad(
		canvas,
		PackedVector2Array([
			corners[first],
			corners[second],
			corners[second] + down,
			corners[first] + down,
		]),
		uvs,
		texture,
		tint
	)


## 实心地形的源贴图只带默认视角的两侧；转到背面时复用对应材质，
## 但按当前视角只画朝向镜头的两侧。平地内部侧面由前排顶面覆盖。
static func draw_projected_terrain(
	canvas: CanvasItem,
	texture: Texture2D,
	center: Vector2,
	tint: Color,
	water_part: StringName,
	level: int,
	corners: PackedVector2Array,
	ctx: Dictionary
) -> void:
	if water_part != &"surface":
		if water_part == &"":
			draw_terrain_side(
				canvas, texture, corners, 0, bool(ctx["x_positive"]), tint, ctx["level_height"]
			)
			draw_terrain_side(
				canvas, texture, corners, 1, bool(ctx["y_positive"]), tint, ctx["level_height"]
			)
		elif water_part == &"right_side" and bool(ctx["x_positive"]):
			draw_terrain_side(canvas, texture, corners, 0, true, tint, ctx["level_height"])
		elif water_part == &"right_side_opposite" and not bool(ctx["x_positive"]):
			draw_terrain_side(canvas, texture, corners, 0, false, tint, ctx["level_height"])
		elif water_part == &"left_side" and bool(ctx["y_positive"]):
			draw_terrain_side(canvas, texture, corners, 1, true, tint, ctx["level_height"])
		elif water_part == &"left_side_opposite" and not bool(ctx["y_positive"]):
			draw_terrain_side(canvas, texture, corners, 1, false, tint, ctx["level_height"])
	if is_visible_top(water_part, level, int(ctx["terrain_top_level"])):
		draw_textured_quad(canvas, corners, TextureBatch.TOP_UV, texture, tint)


static func append_batch_terrain(
	batch: ProjectedTerrainBatch,
	corners: PackedVector2Array,
	water_part: StringName,
	center: Vector2,
	level: int,
	ctx: Dictionary
) -> void:
	var side_exposed: Callable = ctx["side_exposed"]
	if water_part != &"surface":
		if water_part == &"":
			var x_positive: bool = ctx["x_positive"]
			var y_positive: bool = ctx["y_positive"]
			if bool(side_exposed.call(0, x_positive, level)):
				batch.append_side(corners, 0, x_positive, ctx["level_height"], center)
			if bool(side_exposed.call(1, y_positive, level)):
				batch.append_side(corners, 1, y_positive, ctx["level_height"], center)
		elif (
			water_part == &"right_side" and bool(ctx["x_positive"])
			and bool(side_exposed.call(0, true, level))
		):
			batch.append_side(corners, 0, true, ctx["level_height"], center)
		elif (
			water_part == &"right_side_opposite" and not bool(ctx["x_positive"])
			and bool(side_exposed.call(0, false, level))
		):
			batch.append_side(corners, 0, false, ctx["level_height"], center)
		elif (
			water_part == &"left_side" and bool(ctx["y_positive"])
			and bool(side_exposed.call(1, true, level))
		):
			batch.append_side(corners, 1, true, ctx["level_height"], center)
		elif (
			water_part == &"left_side_opposite" and not bool(ctx["y_positive"])
			and bool(side_exposed.call(1, false, level))
		):
			batch.append_side(corners, 1, false, ctx["level_height"], center)
	if is_visible_top(water_part, level, int(ctx["terrain_top_level"])):
		batch.append_quad(corners, TextureBatch.TOP_UV, center)


static func _commit_batch(
	batch: ProjectedTerrainBatch,
	plan: Array,
	mesh_cache: Dictionary,
	sector: int,
	end_index: int
) -> void:
	var mesh: ArrayMesh = batch.commit(mesh_cache, sector, end_index)
	if mesh != null:
		plan.append({"kind": &"mesh", "mesh": mesh, "texture": batch.texture})


## top_center 已含 TOP_CENTER_OFFSET（与原内联实现一致；CUSTOM0 中心同样带偏移）。
static func _default_corners(top_center: Vector2, ctx: Dictionary) -> PackedVector2Array:
	var half_x: Vector2 = ctx["default_basis_x"] * 0.5
	var half_y: Vector2 = ctx["default_basis_y"] * 0.5
	return PackedVector2Array([
		top_center - half_x - half_y,
		top_center + half_x - half_y,
		top_center + half_x + half_y,
		top_center - half_x + half_y,
	])


## 普通柱没有动态遮挡时，把每帧绘制退化为遍历已缓存命令。网格顶点、UV、
## CUSTOM0 与色调只在首次遇到某个朝向扇区时生成，连续旋转不再逐顶点重建。
static func build_draw_plan(
	blocks: Array[Dictionary],
	sector: int,
	mesh_cache: Dictionary,
	ctx: Dictionary
) -> Array:
	var plan: Array = []
	var batch := ProjectedTerrainBatch.new()
	for index in blocks.size():
		var block: Dictionary = blocks[index]
		var level := int(block["level"])
		var texture: Texture2D = block["texture"]
		var water_part: StringName = block.get("water_part", &"")
		var draw_modulate: Color = block["modulate"]
		var projected := is_projected_terrain(block) and (
			not bool(ctx["default_projection"])
			or (water_part != &"" and water_part != &"surface")
		)
		if projected:
			if not batch.matches(texture, water_part, draw_modulate):
				_commit_batch(batch, plan, mesh_cache, sector, index - 1)
				batch.begin(texture, water_part, draw_modulate, index)
			var center: Vector2 = (
				Vector2(0.0, -level * ctx["level_height"])
				+ Vector2(block["render_offset"])
				+ ctx["top_center_offset"]
			)
			append_batch_terrain(
				batch,
				_default_corners(center, ctx),
				water_part,
				center,
				level,
				ctx
			)
		else:
			_commit_batch(batch, plan, mesh_cache, sector, index - 1)
			plan.append({"kind": &"texture", "index": index})
		if water_part == &"surface":
			_commit_batch(batch, plan, mesh_cache, sector, index)
			plan.append({"kind": &"water_effects", "index": index})
	_commit_batch(batch, plan, mesh_cache, sector, blocks.size() - 1)
	return plan


static func draw_cached_plan(
	canvas: CanvasItem,
	plan: Array,
	blocks: Array[Dictionary],
	ctx: Dictionary
) -> void:
	canvas.draw_set_transform(Vector2(0, ctx["screen_y_offset"]))
	for item_value in plan:
		var item: Dictionary = item_value
		var kind: StringName = item["kind"]
		if kind == &"mesh":
			# 与动态遮挡路径一致：mesh 记录时保持 identity，避免绕过 custom rect。
			canvas.draw_set_transform(Vector2.ZERO)
			canvas.draw_mesh(
				item["mesh"],
				item["texture"],
				Transform2D(0.0, Vector2(0.0, ctx["screen_y_offset"]))
			)
			canvas.draw_set_transform(Vector2(0, ctx["screen_y_offset"]))
			continue
		var block: Dictionary = blocks[int(item["index"])]
		var center := Vector2(
			0.0,
			-int(block["level"]) * ctx["level_height"]
		) + Vector2(block["render_offset"])
		if kind == &"texture":
			var texture: Texture2D = block["texture"]
			var display_size := texture.get_size() * float(block.get("display_scale", 1.0))
			canvas.draw_texture_rect(texture, Rect2(center - display_size * 0.5, display_size), false, block["modulate"])
		else:
			ctx["water_effects"].call(center, block)
	canvas.draw_set_transform(Vector2.ZERO)


## 含动态遮挡透明/剖面加深的逐块即时路径；绘制命令顺序与无遮挡路径一致。
static func draw_dynamic_column(
	canvas: CanvasItem,
	blocks: Array[Dictionary],
	sector: int,
	mesh_cache: Dictionary,
	occlusion_alphas: Dictionary,
	cutaway_shades: Dictionary,
	ctx: Dictionary
) -> void:
	var top_corners: Callable = ctx["top_corners"]
	var texture_mask: Callable = ctx["texture_mask"]
	var water_effects: Callable = ctx["water_effects"]
	var screen_y_offset: float = ctx["screen_y_offset"]
	canvas.draw_set_transform(Vector2(0, screen_y_offset))
	var projected_batch := ProjectedTerrainBatch.new()
	for index in blocks.size():
		var block: Dictionary = blocks[index]
		var level: int = block["level"]
		var texture: Texture2D = block["texture"]
		var center := Vector2(
			0.0,
			-level * ctx["level_height"]
		) + Vector2(block["render_offset"])
		var draw_modulate: Color = block["modulate"]
		draw_modulate.a *= float(occlusion_alphas.get(index, 1.0))
		var display_size := texture.get_size() * float(block.get("display_scale", 1.0))
		var draw_position := center - display_size * 0.5
		var water_part: StringName = block.get("water_part", &"")
		var cutaway_shade := float(cutaway_shades.get(index, 0.0))
		var projected_terrain := is_projected_terrain(block) and (
			not bool(ctx["default_projection"])
			or (water_part != &"" and water_part != &"surface")
		)
		var can_batch := (
			projected_terrain
			and cutaway_shade <= 0.0
			and draw_modulate.a >= 0.999
		)
		if can_batch:
			if not projected_batch.matches(texture, water_part, draw_modulate):
				projected_batch.flush(
					canvas, mesh_cache, sector, index - 1, screen_y_offset
				)
				projected_batch.begin(texture, water_part, draw_modulate, index)
			var batch_center: Vector2 = (
				Vector2(0.0, -level * ctx["level_height"])
				+ Vector2(block["render_offset"])
				+ ctx["top_center_offset"]
			)
			append_batch_terrain(
				projected_batch,
				_default_corners(batch_center, ctx),
				water_part,
				batch_center,
				level,
				ctx
			)
		else:
			projected_batch.flush(canvas, mesh_cache, sector, index - 1, screen_y_offset)
			if projected_terrain:
				draw_projected_terrain(
					canvas,
					texture,
					center,
					draw_modulate,
					water_part,
					level,
					top_corners.call(center),
					ctx
				)
			else:
				canvas.draw_texture_rect(texture, Rect2(draw_position, display_size), false, draw_modulate)
		if cutaway_shade > 0.0:
			# 白色 alpha mask 让深灰以真实颜色覆盖，而不是简单乘暗后仍偏绿/偏棕。
			# 保留一部分原贴图，形成可辨认材质的深灰不可通行剖面。
			var shade_color: Color = ctx["cutaway_shade_color"]
			shade_color.a = cutaway_shade * draw_modulate.a
			if projected_terrain:
				draw_projected_terrain(
					canvas,
					texture_mask.call(texture),
					center,
					shade_color,
					water_part,
					level,
					top_corners.call(center),
					ctx
				)
			else:
				canvas.draw_texture_rect(
					texture_mask.call(texture), Rect2(draw_position, display_size), false, shade_color
				)
		if water_part == &"surface":
			projected_batch.flush(canvas, mesh_cache, sector, index, screen_y_offset)
			water_effects.call(center, block)
	projected_batch.flush(canvas, mesh_cache, sector, blocks.size() - 1, screen_y_offset)
	canvas.draw_set_transform(Vector2.ZERO)
