extends Node3D
## isometric_3d_test.gd — 最小真实柱网格与 90° Camera3D 旋转验证场景。

const CameraScript = preload("res://scripts/iso/isometric_camera_3d.gd")
const TerrainScript = preload("res://scripts/iso/isometric_terrain_3d.gd")

var camera: Camera3D
var terrain: Node3D


func _ready() -> void:
	camera = CameraScript.new()
	camera.zoom = 1.0
	camera.focus_position = Vector3(0.0, 0.3608439182435161, 0.0)
	add_child(camera)
	terrain = TerrainScript.new()
	add_child(terrain)
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.38, 0.72, 0.31, 1.0))
	var texture := ImageTexture.create_from_image(image)
	terrain.set_cell(Vector2i.ZERO, [{
		"level": 1,
		"texture": texture,
		"modulate": Color.WHITE,
		"occluder_class": &"terrain",
		"render_offset": Vector2.ZERO,
	}], 1.0)
	terrain.flush()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT:
			camera.rotate_step(-1)
		elif event.keycode == KEY_RIGHT:
			camera.rotate_step(1)
