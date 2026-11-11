## flat_rotation_probe.gd — 临时平底旋转渲染隔离探针，验收后删除
extends Node2D

const ColumnBatchScript = preload("res://scripts/isometric_column_batch.gd")
const IsometricView = preload("res://scripts/isometric_view.gd")

func _ready() -> void:
	var source: Image = load("res://meowa_tiles/terrain/soil_with_grass.png").get_image()
	var padded := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	padded.fill(Color(0, 0, 0, 0))
	padded.blit_rect(source, Rect2i(0, 0, 32, 26), Vector2i(0, 6))
	var texture := ImageTexture.create_from_image(padded)
	var view := IsometricView.new()
	view.set_view_angle(-45)
	for y in range(-8, 9):
		for x in range(-8, 9):
			var cell := Vector2i(x, y)
			var blocks: Array[Dictionary] = []
			for level in 8:
				blocks.append({
					"level": level,
					"texture": texture,
					"modulate": Color.WHITE,
					"render_offset": Vector2.ZERO,
				})
			var column := ColumnBatchScript.new()
			add_child(column)
			column.configure(
				cell, blocks, view.grid_to_screen(cell),
				view.get_depth_key(cell) * 16.0, 10.0,
				view._basis_x, view._basis_y,
				func(_neighbor: Vector2i) -> int: return 7
			)
	var camera := Camera2D.new()
	add_child(camera)
	camera.make_current()
