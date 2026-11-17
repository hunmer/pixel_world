## building_interior_view.gd — 单层房屋剖面，真实格地板、低墙与桌子；不参与碰撞。
extends Node3D

const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
var _rooms: Dictionary = {}
var _materials: Dictionary = {}
var room_count: int = 0
var visible_room_count: int = 0


func rebuild(entries: Array, renderer) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_rooms.clear()
	room_count = 0
	visible_room_count = 0
	for raw in entries:
		var entry: Dictionary = raw
		var visual: Dictionary = entry.get("visual", {})
		var interior: Dictionary = visual.get("interior", {})
		if not bool(interior.get("enabled", false)):
			continue
		var rows: Array = interior.get("rows", [])
		if rows.is_empty():
			continue
		var room := Node3D.new()
		var id := String(entry.get("instance_id", ""))
		room.name = "Room_%s" % room_count
		room.set_meta("instance_id", id)
		add_child(room)
		_rooms[id] = room
		room.visible = false
		room_count += 1
		var origin: Vector2i = renderer._building_cell(entry)
		var rotation := posmod(int(entry.get("rotation", 0)), 4)
		var width := String(rows[0]).length()
		for y in rows.size():
			for x in width:
				var local := Vector2i(x, y)
				match rotation:
					1: local = Vector2i(rows.size() - 1 - y, x)
					2: local = Vector2i(width - 1 - x, rows.size() - 1 - y)
					3: local = Vector2i(y, width - 1 - x)
				var cell := origin + local
				var base: Vector3 = IsoProjection.grid_to_world(cell, renderer.visual_top_level(cell.x, cell.y))
				var symbol := String(rows[y]).substr(x, 1)
				_add_floor(room, cell, base, symbol == "D")
				if symbol == "#":
					_box(room, base + Vector3(0, 0.17, 0), Vector3(IsoProjection.GRID_STEP, 0.32, IsoProjection.GRID_STEP), Color("9c967e"), "Wall", cell)
					_box(room, base + Vector3(0, 0.34, 0), Vector3(IsoProjection.GRID_STEP, 0.035, IsoProjection.GRID_STEP), Color("c6b9a0"), "WallCap", cell)
				elif symbol == "F":
					_add_table(room, cell, base)


func set_revealed(states: Dictionary) -> void:
	visible_room_count = 0
	for id in _rooms:
		var room: Node3D = _rooms[id]
		room.visible = bool(states.get(id, false))
		if room.visible:
			visible_room_count += 1


func _add_floor(room: Node3D, cell: Vector2i, base: Vector3, door: bool) -> void:
	var floor_color := Color("b99b6f") if (cell.x + cell.y) % 2 == 0 else Color("ad8d60")
	if door:
		floor_color = Color("c9b68b")
	_box(room, base + Vector3(0, 0.006, 0), Vector3(IsoProjection.GRID_STEP, 0.01, IsoProjection.GRID_STEP), floor_color, "Door" if door else "Floor", cell)
	# 薄木条保留像素风的地板方向，不依赖外部贴图。
	for stripe in [-1, 1]:
		_box(room, base + Vector3(float(stripe) * IsoProjection.GRID_STEP / 6.0, 0.012, 0), Vector3(0.008, 0.002, IsoProjection.GRID_STEP), Color("806b4f"), "Plank", cell)


func _add_table(room: Node3D, cell: Vector2i, base: Vector3) -> void:
	_box(room, base + Vector3(0, 0.29, 0), Vector3(0.52, 0.07, 0.52), Color("775033"), "Furniture", cell)
	for dx in [-1, 1]:
		for dz in [-1, 1]:
			_box(room, base + Vector3(float(dx) * 0.19, 0.14, float(dz) * 0.19), Vector3(0.065, 0.28, 0.065), Color("513a29"), "TableLeg", cell)


func _box(parent: Node3D, center: Vector3, size: Vector3, color: Color, kind: String, cell: Vector2i) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = center
	instance.set_meta("kind", kind)
	instance.set_meta("cell", cell)
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 1.0
		_materials[key] = material
	instance.material_override = _materials[key]
	parent.add_child(instance)
