extends Node3D
## isometric_terrain_3d.gd — 消费既有 render_blocks，按 chunk/图集合批真实 3D 柱地形。

const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")
const CHUNK_SIZE := 2
const MAX_WATER_RIPPLES := 48
const MAX_CELL_WATER_RIPPLES := 4
const RIPPLE_SEGMENTS := 18
const RIPPLE_REDRAW_INTERVAL := 1.0 / 30.0
const TOP_UV := [Vector2(16, 6), Vector2(32, 14), Vector2(16, 22), Vector2(0, 14)]
const RIGHT_SIDE_UV := [Vector2(32, 14), Vector2(16, 22), Vector2(16, 32), Vector2(32, 24)]
const LEFT_SIDE_UV := [Vector2(0, 14), Vector2(16, 22), Vector2(16, 32), Vector2(0, 24)]

var _cells: Dictionary = {}
var _chunks: Dictionary = {}
var _dirty_chunks: Dictionary = {}
var _materials: Dictionary = {}
var _last_build_ms := 0.0
var _water_ripples: Array[Dictionary] = []
var _ripple_redraw_elapsed := 0.0
var _ripple_instance: MultiMeshInstance3D


func set_cell(cell: Vector2i, blocks: Array, stand_level: float = 0.0) -> void:
	_cells[cell] = {
		"blocks": blocks.duplicate(true),
		"stand_level": stand_level,
	}
	_mark_chunk_dirty(cell)


func remove_cell(cell: Vector2i) -> void:
	if not _cells.has(cell):
		return
	_cells.erase(cell)
	_remove_ripples_for_cell(cell)
	_mark_chunk_dirty(cell)


func clear() -> void:
	_cells.clear()
	_dirty_chunks.clear()
	_water_ripples.clear()
	_refresh_ripple_multimesh()
	for chunk_value in _chunks.values():
		var chunk: Node3D = chunk_value
		if is_instance_valid(chunk):
			chunk.free()
	_chunks.clear()


func has_cell(cell: Vector2i) -> bool:
	return _cells.has(cell)


func cell_count() -> int:
	return _cells.size()


func chunk_count() -> int:
	return _chunks.size()


func mesh_instance_count() -> int:
	var count := 0
	for chunk_value in _chunks.values():
		var chunk: Node3D = chunk_value
		for child in chunk.get_children():
			if child is MeshInstance3D or child is MultiMeshInstance3D:
				count += 1
	return count


func stand_level(cell: Vector2i) -> float:
	return float((_cells.get(cell, {}) as Dictionary).get("stand_level", 0.0))


func flush() -> int:
	if _dirty_chunks.is_empty():
		return 0
	var started := Time.get_ticks_usec()
	var chunks_to_build := _dirty_chunks.keys()
	_dirty_chunks.clear()
	for chunk_value in chunks_to_build:
		_rebuild_chunk(chunk_value as Vector2i)
	_last_build_ms = float(Time.get_ticks_usec() - started) / 1000.0
	return chunks_to_build.size()


func _process(delta: float) -> void:
	# 兼容直接调用 set_cell 的编辑器/契约；主世界会在一批流式操作后显式 flush。
	flush()
	_advance_water_ripples(delta)


## 天气水波使用一个全局 MultiMesh（双环），不创建逐格节点，也不重建地形。
func spawn_water_ripple(
	cell: Vector2i,
	local_offset: Vector2,
	kind: StringName,
	strength: float,
	maximum_radius: float
) -> void:
	if not _cells.has(cell):
		return
	var same_cell_count := 0
	var oldest_same_cell := -1
	for index in _water_ripples.size():
		if _water_ripples[index]["cell"] == cell:
			if oldest_same_cell < 0:
				oldest_same_cell = index
			same_cell_count += 1
	if same_cell_count >= MAX_CELL_WATER_RIPPLES and oldest_same_cell >= 0:
		_water_ripples.remove_at(oldest_same_cell)
	if _water_ripples.size() >= MAX_WATER_RIPPLES:
		_water_ripples.pop_front()
	var surface_level := stand_level(cell)
	var center := IsoProjection.visual_to_world(
		Vector2(cell) + local_offset, surface_level
	) + Vector3.UP * 0.004
	_water_ripples.append({
		"cell": cell,
		"age": 0.0,
		"lifetime": 0.72 if kind == &"rain" else 1.05,
		"kind": kind,
		"position": center,
		"strength": clampf(strength, 0.0, 1.0),
		"maximum_radius": maximum_radius,
	})
	_ensure_ripple_renderer()
	_refresh_ripple_multimesh()


func active_water_ripple_count() -> int:
	return _water_ripples.size()


func _advance_water_ripples(delta: float) -> void:
	if _water_ripples.is_empty():
		_ripple_redraw_elapsed = 0.0
		return
	var changed := false
	for index in range(_water_ripples.size() - 1, -1, -1):
		_water_ripples[index]["age"] = float(_water_ripples[index]["age"]) + delta
		if float(_water_ripples[index]["age"]) >= float(_water_ripples[index]["lifetime"]):
			_water_ripples.remove_at(index)
			changed = true
	_ripple_redraw_elapsed += delta
	if changed or _ripple_redraw_elapsed >= RIPPLE_REDRAW_INTERVAL:
		_ripple_redraw_elapsed = fmod(_ripple_redraw_elapsed, RIPPLE_REDRAW_INTERVAL)
		_refresh_ripple_multimesh()


func _remove_ripples_for_cell(cell: Vector2i) -> void:
	for index in range(_water_ripples.size() - 1, -1, -1):
		if _water_ripples[index]["cell"] == cell:
			_water_ripples.remove_at(index)
	_refresh_ripple_multimesh()


func _ensure_ripple_renderer() -> void:
	if is_instance_valid(_ripple_instance):
		return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for segment in RIPPLE_SEGMENTS:
		var a0 := TAU * float(segment) / RIPPLE_SEGMENTS
		var a1 := TAU * float(segment + 1) / RIPPLE_SEGMENTS
		var inner0 := Vector3(cos(a0) * 0.86, 0.0, sin(a0) * 0.86)
		var outer0 := Vector3(cos(a0), 0.0, sin(a0))
		var inner1 := Vector3(cos(a1) * 0.86, 0.0, sin(a1) * 0.86)
		var outer1 := Vector3(cos(a1), 0.0, sin(a1))
		for point in [inner0, outer0, outer1, inner0, outer1, inner1]:
			vertices.append(point)
			normals.append(Vector3.UP)
			colors.append(Color.WHITE)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var ring := ArrayMesh.new()
	ring.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	ring.surface_set_material(0, material)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = ring
	multimesh.instance_count = MAX_WATER_RIPPLES * 2
	multimesh.visible_instance_count = 0
	_ripple_instance = MultiMeshInstance3D.new()
	_ripple_instance.name = "WaterRipples"
	_ripple_instance.multimesh = multimesh
	_ripple_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ripple_instance.visible = false
	add_child(_ripple_instance)


func _refresh_ripple_multimesh() -> void:
	if not is_instance_valid(_ripple_instance):
		return
	var multimesh := _ripple_instance.multimesh
	multimesh.visible_instance_count = _water_ripples.size() * 2
	_ripple_instance.visible = not _water_ripples.is_empty()
	for index in _water_ripples.size():
		var ripple: Dictionary = _water_ripples[index]
		var progress := clampf(float(ripple["age"]) / float(ripple["lifetime"]), 0.0, 1.0)
		var expansion := 1.0 - pow(1.0 - progress, 2.0)
		var fade := pow(1.0 - progress, 1.7) * float(ripple["strength"])
		var radius_px := lerpf(1.2, float(ripple["maximum_radius"]), expansion)
		var radius := radius_px / IsoProjection.TILE_PIXELS * IsoProjection.GRID_STEP
		var color := Color(0.72, 0.91, 1.0, fade * 0.68)
		if ripple["kind"] == &"snow":
			color = Color(0.91, 0.97, 1.0, fade * 0.36)
		multimesh.set_instance_transform(index * 2, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), ripple["position"]))
		multimesh.set_instance_color(index * 2, color)
		var tail_progress := maxf(0.0, (progress - 0.18) / 0.82)
		var tail_expansion := 1.0 - pow(1.0 - tail_progress, 2.0)
		var tail_radius := lerpf(0.8, float(ripple["maximum_radius"]) * 0.72, tail_expansion) / IsoProjection.TILE_PIXELS * IsoProjection.GRID_STEP
		var tail_color := color
		tail_color.a *= (1.0 - tail_progress) * 0.52 if progress > 0.18 else 0.0
		multimesh.set_instance_transform(index * 2 + 1, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * tail_radius), ripple["position"] + Vector3.UP * 0.001))
		multimesh.set_instance_color(index * 2 + 1, tail_color)


func _mark_chunk_dirty(cell: Vector2i) -> void:
	var chunk := Vector2i(
		floori(float(cell.x) / CHUNK_SIZE),
		floori(float(cell.y) / CHUNK_SIZE)
	)
	_dirty_chunks[chunk] = true


func _rebuild_chunk(chunk_coord: Vector2i) -> void:
	if _chunks.has(chunk_coord):
		var previous: Node3D = _chunks[chunk_coord]
		_chunks.erase(chunk_coord)
		previous.free()
	var chunk := Node3D.new()
	chunk.name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	add_child(chunk)
	_chunks[chunk_coord] = chunk
	var groups: Dictionary = {}
	var props: Dictionary = {}
	var min_cell := chunk_coord * CHUNK_SIZE
	for y in range(min_cell.y, min_cell.y + CHUNK_SIZE):
		for x in range(min_cell.x, min_cell.x + CHUNK_SIZE):
			var cell := Vector2i(x, y)
			if not _cells.has(cell):
				continue
			var blocks: Array = _cells[cell]["blocks"]
			for block_value in blocks:
				var block: Dictionary = block_value
				if block.has("flora_species_id") or StringName(block.get("occluder_class", &"")) == &"prop":
					_append_prop(props, cell, block)
				else:
					_append_block(groups, cell, block)
	for group_value in groups.values():
		_commit_mesh_group(chunk, group_value)
	for prop_value in props.values():
		_commit_prop_group(chunk, prop_value)


func _append_block(groups: Dictionary, cell: Vector2i, block: Dictionary) -> void:
	var texture: Texture2D = block.get("texture")
	if texture == null:
		return
	var tint: Color = block.get("modulate", Color.WHITE)
	var water_part := StringName(block.get("water_part", &""))
	var transparent := water_part != &"" or tint.a < 0.999
	var atlas := _atlas_texture(texture)
	if atlas == null:
		return
	var key := "%d:%d" % [atlas.get_instance_id(), int(transparent)]
	if not groups.has(key):
		groups[key] = {
			"vertices": [],
			"normals": [],
			"uvs": [],
			"colors": [],
			"transparent": transparent,
			"material": _mesh_material(atlas, transparent),
		}
	var group: Dictionary = groups[key]
	var level := float(block.get("level", 0))
	var center := IsoProjection.grid_to_world(cell, level) + _screen_offset_world(
		block.get("render_offset", Vector2.ZERO)
	)
	var half := IsoProjection.GRID_STEP * 0.5
	var top := [
		center + Vector3(-half, 0, -half),
		center + Vector3(half, 0, -half),
		center + Vector3(half, 0, half),
		center + Vector3(-half, 0, half),
	]
	var down := Vector3(0, -IsoProjection.LEVEL_HEIGHT, 0)
	if water_part == &"surface":
		_add_quad(group, top, TOP_UV, texture, tint)
		return
	if water_part != &"":
		match water_part:
			&"right_side":
				_add_quad(group, [top[1], top[2], top[2] + down, top[1] + down], RIGHT_SIDE_UV, texture, tint)
			&"right_side_opposite":
				_add_quad(group, [top[3], top[0], top[0] + down, top[3] + down], LEFT_SIDE_UV, texture, tint)
			&"left_side":
				_add_quad(group, [top[2], top[3], top[3] + down, top[2] + down], RIGHT_SIDE_UV, texture, tint)
			&"left_side_opposite":
				_add_quad(group, [top[0], top[1], top[1] + down, top[0] + down], LEFT_SIDE_UV, texture, tint)
		return
	# 实心柱四个侧面都是真实几何；旋转相机不会触发任何顶点重建。
	_add_quad(group, top, TOP_UV, texture, tint)
	_add_quad(group, [top[1], top[2], top[2] + down, top[1] + down], RIGHT_SIDE_UV, texture, tint)
	_add_quad(group, [top[3], top[0], top[0] + down, top[3] + down], LEFT_SIDE_UV, texture, tint)
	_add_quad(group, [top[0], top[1], top[1] + down, top[0] + down], LEFT_SIDE_UV, texture, tint)
	_add_quad(group, [top[2], top[3], top[3] + down, top[2] + down], RIGHT_SIDE_UV, texture, tint)


func _append_prop(props: Dictionary, cell: Vector2i, block: Dictionary) -> void:
	var texture: Texture2D = block.get("texture")
	if texture == null:
		return
	var atlas := _atlas_texture(texture)
	if atlas == null:
		return
	var region := _texture_region(texture)
	var tint: Color = block.get("modulate", Color.WHITE)
	var key := "%d:%s" % [atlas.get_instance_id(), str(region)]
	if not props.has(key):
		props[key] = {
			"atlas": atlas,
			"region": region,
			"transforms": [],
			"colors": [],
		}
	var center := IsoProjection.grid_to_world(cell, float(block.get("level", 0)))
	center += _screen_offset_world(block.get("render_offset", Vector2.ZERO))
	(props[key]["transforms"] as Array).append(Transform3D(Basis.IDENTITY, center))
	(props[key]["colors"] as Array).append(tint)


func _commit_mesh_group(chunk: Node3D, group: Dictionary) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(group["vertices"])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(group["normals"])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(group["uvs"])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(group["colors"])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, group["material"])
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if bool(group["transparent"])
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	)
	chunk.add_child(instance)


func _commit_prop_group(chunk: Node3D, group: Dictionary) -> void:
	var transforms: Array = group["transforms"]
	if transforms.is_empty():
		return
	var quad := QuadMesh.new()
	quad.size = (group["region"] as Rect2).size / IsoProjection.TILE_PIXELS
	var material := _prop_material(group["atlas"], group["region"])
	quad.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
		multimesh.set_instance_color(index, group["colors"][index])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(instance)


func _add_quad(
	group: Dictionary,
	points: Array,
	uvs: Array,
	texture: Texture2D,
	tint: Color
) -> void:
	# Godot 正面采用顺时针 winding；交叉积取反才是柱体朝外的光照法线。
	var normal := ((points[2] as Vector3) - (points[0] as Vector3)).cross(
		(points[1] as Vector3) - (points[0] as Vector3)
	).normalized()
	for index in [0, 1, 2, 0, 2, 3]:
		(group["vertices"] as Array).append(points[index])
		(group["normals"] as Array).append(normal)
		(group["uvs"] as Array).append(_atlas_uv(texture, uvs[index]))
		(group["colors"] as Array).append(tint)


func _atlas_texture(texture: Texture2D) -> Texture2D:
	if texture is AtlasTexture:
		return (texture as AtlasTexture).atlas
	return texture


func _texture_region(texture: Texture2D) -> Rect2:
	if texture is AtlasTexture:
		return (texture as AtlasTexture).region
	return Rect2(Vector2.ZERO, texture.get_size())


func _atlas_uv(texture: Texture2D, uv: Vector2) -> Vector2:
	var atlas := _atlas_texture(texture)
	if atlas == null or atlas.get_width() <= 0 or atlas.get_height() <= 0:
		return Vector2.ZERO
	if texture is AtlasTexture:
		var region := (texture as AtlasTexture).region
		return (region.position + uv / 32.0 * region.size) / atlas.get_size()
	return uv / atlas.get_size()


func _screen_offset_world(offset_value: Variant) -> Vector3:
	var offset: Vector2 = offset_value if offset_value is Vector2 else Vector2.ZERO
	var right := Vector3(IsoProjection.GRID_STEP, 0, -IsoProjection.GRID_STEP)
	return right * (offset.x / IsoProjection.TILE_PIXELS) + Vector3.UP * (
		-offset.y / (IsoProjection.TILE_PIXELS * cos(IsoProjection.CAMERA_ELEVATION))
	)


func _mesh_material(atlas: Texture2D, transparent: bool) -> StandardMaterial3D:
	var key := "mesh:%d:%d" % [atlas.get_instance_id(), int(transparent)]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = atlas
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# 只有不透明实心柱参与真实日照；水面继续无光照，避免透明叠面出现黑斑。
	material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
		if transparent
		else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	)
	material.metallic_specular = 0.0
	material.roughness = 1.0
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.1
	_materials[key] = material
	return material


func _prop_material(atlas: Texture2D, region: Rect2) -> StandardMaterial3D:
	var key := "prop:%d:%s" % [atlas.get_instance_id(), str(region)]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = atlas
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.1
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.uv1_offset = Vector3(region.position.x / atlas.get_width(), region.position.y / atlas.get_height(), 0.0)
	material.uv1_scale = Vector3(region.size.x / atlas.get_width(), region.size.y / atlas.get_height(), 1.0)
	_materials[key] = material
	return material
