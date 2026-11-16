extends RefCounted

## isometric_column_texture_batch.gd — 柱体贴图通道的网格批绘（ProjectedTerrainBatch）。
##
## 把连续、同贴图且同色调的投影面合并为三角形网格，避免逐面 draw_polygon
## 在完整地图旋转时产生数万次 CanvasItem 绘制调用。本文件只负责顶点/UV/CUSTOM0
## 的累积、ArrayMesh 提交与按缓存键复用；调用方（isometric_column_batch.gd 装配层
## 与 isometric_column_terrain_draw.gd）负责决定哪些面进入批绘。

const TOP_UV := [
	Vector2(16.0, 6.0),
	Vector2(32.0, 14.0),
	Vector2(16.0, 22.0),
	Vector2(0.0, 14.0),
]
const RIGHT_SIDE_UV := [
	Vector2(32.0, 14.0),
	Vector2(16.0, 22.0),
	Vector2(16.0, 32.0),
	Vector2(32.0, 24.0),
]
const LEFT_SIDE_UV := [
	Vector2(0.0, 14.0),
	Vector2(16.0, 22.0),
	Vector2(16.0, 32.0),
	Vector2(0.0, 24.0),
]


class ProjectedTerrainBatch:
	var texture: Texture2D
	var water_part: StringName = &""
	var tint := Color.WHITE
	var start_index := -1
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var customs := PackedColorArray()
	var colors := PackedColorArray()

	func matches(next_texture: Texture2D, next_part: StringName, next_tint: Color) -> bool:
		return (
			start_index >= 0
			and texture == next_texture
			and water_part == next_part
			and tint.is_equal_approx(next_tint)
		)

	func begin(
		next_texture: Texture2D,
		next_part: StringName,
		next_tint: Color,
		block_index: int
	) -> void:
		texture = next_texture
		water_part = next_part
		tint = next_tint
		start_index = block_index

	func append_quad(points: PackedVector2Array, quad_uvs: Array, center: Vector2) -> void:
		for vertex_index in [0, 1, 2, 0, 2, 3]:
			vertices.append(points[vertex_index])
			uvs.append(quad_uvs[vertex_index])
			var vertical := maxf(float(quad_uvs[vertex_index].y) - 22.0, 0.0)
			customs.append(Color(center.x, center.y, 1.0, vertical))
			colors.append(tint)

	func append_side(
		corners: PackedVector2Array,
		axis: int,
		positive: bool,
		level_height: float,
		center: Vector2
	) -> void:
		var first := 0
		var second := 0
		var quad_uvs: Array = []
		if axis == 0:
			first = 1 if positive else 0
			second = 2 if positive else 3
			quad_uvs = RIGHT_SIDE_UV
		else:
			first = 3 if positive else 0
			second = 2 if positive else 1
			quad_uvs = LEFT_SIDE_UV
		var down := Vector2(0.0, level_height)
		append_quad(
			PackedVector2Array([
				corners[first],
				corners[second],
				corners[second] + down,
				corners[first] + down,
			]),
			quad_uvs,
			center
		)

	func commit(mesh_cache: Dictionary, sector: int, end_index: int) -> ArrayMesh:
		if start_index < 0 or vertices.is_empty():
			start_index = -1
			return null
		var cache_key := "%d:%d:%d:%d:%s" % [
			start_index,
			end_index,
			sector,
			texture.get_instance_id(),
			str(tint),
		]
		var mesh: ArrayMesh = mesh_cache.get(cache_key)
		if mesh == null:
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surface.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
			var texture_size := texture.get_size()
			for vertex_index in vertices.size():
				# draw_polygon 接受像素 UV，但 draw_mesh/ArrayMesh 必须使用归一化 UV。
				surface.set_uv(uvs[vertex_index] / texture_size)
				surface.set_color(colors[vertex_index])
				surface.set_custom(0, customs[vertex_index])
				var point := vertices[vertex_index]
				surface.add_vertex(Vector3(point.x, point.y, 0.0))
			mesh = surface.commit()
			mesh_cache[cache_key] = mesh
		start_index = -1
		vertices = PackedVector2Array()
		uvs = PackedVector2Array()
		customs = PackedColorArray()
		colors = PackedColorArray()
		return mesh

	func flush(
		canvas: CanvasItem,
		mesh_cache: Dictionary,
		sector: int,
		end_index: int,
		screen_y_offset: float
	) -> void:
		var mesh := commit(mesh_cache, sector, end_index)
		if mesh == null:
			return
		# draw_mesh 必须在 identity Canvas transform 下记录，否则 custom rect
		# 仍无法纠正 Y-sort 原点造成的视口剔除；Y 偏移只走显式 transform。
		canvas.draw_set_transform(Vector2.ZERO)
		canvas.draw_mesh(
			mesh,
			texture,
			Transform2D(0.0, Vector2(0.0, screen_y_offset))
		)
		canvas.draw_set_transform(Vector2(0.0, screen_y_offset))
