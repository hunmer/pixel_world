## building_occlusion_controller.gd — 建筑 billboard 遮挡单位时淡化，离开后恢复。
extends RefCounted

const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
const OCCLUDED_ALPHA := 0.20
const DEPTH_MARGIN := 0.01
var _occluded: Dictionary = {}
var _images: Dictionary = {}


func update(delta: float, terrain: Node3D, camera: Camera3D, targets: Array[Sprite3D]) -> void:
	var current: Dictionary = {}
	if is_instance_valid(camera):
		var viewport_height: float = camera.get_viewport().get_visible_rect().size.y
		var pixels_per_world: float = viewport_height / maxf(camera.size, 0.0001)
		for cell: Vector2i in terrain.get_prop_cells():
			for entry: Dictionary in terrain.get_prop_block_occlusion_data(cell):
				if not bool(entry.get("building", false)):
					continue
				for target: Sprite3D in targets:
					if covers_unit(entry, target, camera, pixels_per_world):
						current[cell] = true
						break
				if current.has(cell):
					break
	for cell: Vector2i in _occluded:
		if not current.has(cell):
			terrain.set_prop_fade_target(cell, 1.0)
	# 重放目标，兼容地图重建清掉原淡化代理的情况；特写锁定仍由 terrain 优先处理。
	for cell: Vector2i in current:
		terrain.set_prop_fade_target(cell, OCCLUDED_ALPHA)
	if current != _occluded:
		print_verbose("[building-occlusion] occluded=%d" % current.size())
	_occluded = current
	terrain.advance_prop_fades(delta)


func covers_unit(entry: Dictionary, target: Sprite3D, camera: Camera3D, pixels_per_world: float) -> bool:
	if not is_instance_valid(target) or not target.is_visible_in_tree() or target.texture == null or target.modulate.a <= 0.01:
		return false
	# 建筑为了防止底座穿地，已沿视线前移；深度必须使用实际绘制平面，不能用地基锚点。
	var back: Vector3 = camera.global_transform.basis.z
	if back.dot(entry["center"] - target.global_position) <= DEPTH_MARGIN:
		return false
	var target_image: Image = _image(target.texture)
	if target_image == null:
		return false
	var used: Rect2i = target_image.get_used_rect()
	if used.size == Vector2i.ZERO:
		return false
	var target_size: Vector2 = target.texture.get_size()
	var local_rect := Rect2(Vector2(used.position), Vector2(used.size))
	if target.flip_h:
		local_rect.position.x = target_size.x - local_rect.end.x
	if target.flip_v:
		local_rect.position.y = target_size.y - local_rect.end.y
	var source_origin: Vector2 = target_size * 0.5 if target.centered else Vector2.ZERO
	var unit_rect := Rect2(
		camera.unproject_position(target.global_position) + (local_rect.position - source_origin + Vector2(target.offset.x, -target.offset.y)) * target.pixel_size * pixels_per_world,
		local_rect.size * target.pixel_size * pixels_per_world)
	var display_scale: float = float(entry.get("display_scale", 1.0))
	var size: Vector2 = entry["size_px"] * display_scale / IsoProjection.TILE_PIXELS * pixels_per_world
	var rect := Rect2(camera.unproject_position(entry["center"]) - size * 0.5, size)
	var overlap: Rect2 = rect.intersection(unit_rect)
	if not overlap.has_area():
		return false
	var image: Image = _image(entry["texture"])
	if image == null:
		return true
	# 只在实际相交区域采样 alpha；整张方帧的透明角不触发淡化。
	var source_size: Vector2 = entry["size_px"]
	var origin: Vector2 = entry.get("origin_px", Vector2.ZERO)
	var from_px: Vector2i = Vector2i((overlap.position - rect.position) / rect.size * source_size + origin)
	var to_px: Vector2i = Vector2i(((overlap.end - rect.position) / rect.size * source_size + origin).ceil())
	for y: int in range(maxi(0, from_px.y), mini(image.get_height(), to_px.y)):
		for x: int in range(maxi(0, from_px.x), mini(image.get_width(), to_px.x)):
			if image.get_pixel(x, y).a > 0.01:
				return true
	return false


func _image(texture: Texture2D) -> Image:
	# 使用纹理对象作键，限制缓存规模，避免销毁后的实例 ID 复用。
	var key: Texture2D = texture
	if not _images.has(key):
		if _images.size() >= 64:
			_images.clear()
		_images[key] = texture.get_image()
	return _images[key]
