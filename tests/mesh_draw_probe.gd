extends Node2D

## mesh_draw_probe.gd — 临时对比 CanvasItem draw_mesh 的像素/归一化 UV 与变换。

var mesh_pixel: ArrayMesh
var mesh_normalized: ArrayMesh


func _make_mesh(normalized: bool) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [Vector2.ZERO, Vector2(32, 0), Vector2(32, 32), Vector2(0, 32)]
	var uvs := [Vector2.ZERO, Vector2(32, 0), Vector2(32, 32), Vector2(0, 32)]
	for index in [0, 1, 2, 0, 2, 3]:
		surface.set_uv(uvs[index] / 32.0 if normalized else uvs[index])
		surface.add_vertex(Vector3(points[index].x, points[index].y, 0))
	return surface.commit()


func _ready() -> void:
	mesh_pixel = _make_mesh(false)
	mesh_normalized = _make_mesh(true)
	z_index = 10000


func _draw() -> void:
	var texture := load("res://meowa_tiles/terrain/soil_with_grass.png") as Texture2D
	draw_string(ThemeDB.fallback_font, Vector2(360, 190), "pixel UV")
	draw_string(ThemeDB.fallback_font, Vector2(500, 190), "normalized UV")
	draw_mesh(mesh_pixel, texture, Transform2D(0, Vector2(360, 200)))
	draw_mesh(mesh_normalized, texture, Transform2D(0, Vector2(500, 200)))
	draw_set_transform(Vector2(650, 200))
	draw_mesh(mesh_normalized, texture)
	draw_set_transform(Vector2.ZERO)
	draw_string(ThemeDB.fallback_font, Vector2(650, 190), "draw_set_transform")
