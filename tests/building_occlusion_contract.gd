## building_occlusion_contract.gd — 真实建筑、单位组、renderer 常规帧驱动的遮挡与恢复。
extends SceneTree

const Renderer = preload("res://scripts/iso/battlefield_renderer.gd")
const Adapter = preload("res://scripts/assets/user_asset_visual_adapter.gd")
const Camera = preload("res://scripts/iso/isometric_camera_3d.gd")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _unit() -> UnitSprite3D:
	var unit := UnitSprite3D.new()
	unit.portrait = Sprite3D.new()
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	unit.portrait.texture = ImageTexture.create_from_image(image)
	unit.portrait.pixel_size = 1.0 / 32.0
	unit.portrait.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	unit.add_child(unit.portrait)
	root.add_child(unit)
	return unit

func _run() -> void:
	var camera := Camera.new()
	root.add_child(camera)
	await process_frame
	var renderer := Renderer.new()
	root.add_child(renderer)
	renderer.set_process(false)
	var adapter := Adapter.new("user://tmp/building_occlusion_empty")
	var demo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/battlefields/building_demo.json"))
	var descriptor: Dictionary = demo["user_assets"].values()[0]
	var id: String = descriptor["id"]
	var entries: Array = adapter.visual_for_buildings([{"asset_id": id, "x": 1, "y": 1, "rotation": 0}], {id: descriptor})
	renderer.set_building_visuals(entries, false)
	var map: Array = []
	for y: int in 6:
		var row: Array = []
		for x: int in 6:
			row.append(&"plain")
		map.append(row)
	renderer.setup(GridSystem.new(6, 6, map))
	var unit: UnitSprite3D = _unit()
	var other: UnitSprite3D = _unit()
	other.position = Vector3(100, 100, 100)
	var cell := Vector2i(1, 1)
	var terrain: Node3D = renderer._terrain_3d
	_expect(unit.is_in_group("building_occlusion_units"), "实际UnitSprite3D自动加入遮挡目标组")
	for quadrant: int in 4:
		camera.snap_to_angle(45.0 + 90.0 * quadrant)
		renderer.set_camera_quadrant(quadrant)
		var entry: Dictionary = terrain.get_prop_block_occlusion_data(cell)[0]
		var center: Vector3 = entry["center"]
		var back: Vector3 = camera.global_transform.basis.z
		unit.position = center - back * 0.5
		renderer._process(1.0)
		_expect(absf(terrain.get_prop_fade_alpha(cell) - 0.2) < 0.001, "象限%d建筑挡住角色实际淡化到20%%" % quadrant)
		var state: Dictionary = terrain._prop_fades[cell]
		var proxy: Sprite3D = state["sprites"][0]
		_expect(absf(proxy.modulate.a - 0.2) < 0.001 and bool(state["entries"][0]["hidden"]), "象限%d原实例隐藏且真实代理透明度20%%" % quadrant)
		# 建筑重建后，常规帧必须重放遮挡目标。
		renderer.refresh_cell(cell.x, cell.y)
		renderer._process(1.0)
		_expect(absf(terrain.get_prop_fade_alpha(cell) - 0.2) < 0.001, "象限%d重建后遮挡继续淡化" % quadrant)
		unit.position = center + back * 0.5
		renderer._process(1.0)
		_expect(is_equal_approx(terrain.get_prop_fade_alpha(cell), 1.0), "象限%d角色在建筑前面恢复不透明" % quadrant)
		unit.position = center - back * 0.5 + camera.global_transform.basis.x * 20.0
		renderer._process(1.0)
		_expect(is_equal_approx(terrain.get_prop_fade_alpha(cell), 1.0), "象限%d屏幕不相交不淡化" % quadrant)
		# 单位位于方帧透明的左上角，不能因整图包围盒相交而误触。
		var half: Vector2 = entry["size_px"] * float(entry["display_scale"]) / 64.0
		unit.position = center - camera.global_transform.basis.x * (half.x - 0.1) + camera.global_transform.basis.y * (half.y - 0.1) - back * 0.5
		renderer._process(1.0)
		_expect(is_equal_approx(terrain.get_prop_fade_alpha(cell), 1.0), "象限%d建筑方帧透明角不误触淡化" % quadrant)
		unit.position = center - back * 0.5
		other.position = unit.position
		unit.hide()
		renderer._process(1.0)
		_expect(absf(terrain.get_prop_fade_alpha(cell) - 0.2) < 0.001, "象限%d另一角色仍被遮挡时保持淡化" % quadrant)
		other.hide()
		renderer._process(1.0)
		_expect(is_equal_approx(terrain.get_prop_fade_alpha(cell), 1.0), "象限%d所有可见角色离开后恢复" % quadrant)
		unit.show()
		other.show()
		other.position = Vector3(100, 100, 100)
		terrain.set_prop_fade_hold(cell, 0.1)
		renderer._process(1.0)
		_expect(absf(terrain.get_prop_fade_alpha(cell) - 0.1) < 0.001, "象限%d特写遮挡锁优先于常规淡化" % quadrant)
		terrain.clear_prop_fade_hold(cell)
	unit.queue_free()
	other.queue_free()
	renderer.queue_free()
	camera.queue_free()
	await process_frame
	print("BUILDING_OCCLUSION_CONTRACT %s checks=%d" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
