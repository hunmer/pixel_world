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
## 植物遮挡淡出的指数缓动速率（每秒）：淡出更快，恢复稍慢，避免抖动。
const PROP_FADE_OUT_RATE := 14.0
const PROP_FADE_IN_RATE := 7.0
const PROP_FADE_SETTLE := 0.001

var _cells: Dictionary = {}
var _chunks: Dictionary = {}
var _dirty_chunks: Dictionary = {}
var _materials: Dictionary = {}
var _last_build_ms := 0.0
var _water_ripples: Array[Dictionary] = []
var _ripple_redraw_elapsed := 0.0
var _ripple_instance: MultiMeshInstance3D
## 植物 prop 实例注册表：cell -> 条目数组（multimesh/index/贴图/尺寸/中心/锚点/色调）。
## 由 chunk 提交时登记，chunk 重建、remove_cell、clear 时清理；玩家遮挡淡化按格查询。
var _prop_instances: Dictionary = {}
## 正在淡化（或待恢复）的植物格：cell -> {target, current, entries, sprites}。
## 淡化期间原 multimesh 实例颜色置全透明（scissor 丢弃），用逐节点代理 Sprite3D
## 呈现残余透明度，避免改动共享 prop 材质影响其他植物。
var _prop_fades: Dictionary = {}
var _fade_layer: Node3D = null
## 战斗沉浸遮挡：临时隐藏的柱格集合。chunk 重建时整格跳过（含植物），
## 恢复隐藏后按 _cells 原样重建回来；流式重建/编辑器重建同样尊重本集合。
var _hidden_columns: Dictionary = {}
## 植物透明度外部锁定（战斗沉浸遮挡）：锁定期间 set_prop_fade_target 对该格无效，
## 防止 main.gd 玩家遮挡的 0.5s 周期重建把战斗淡出的植物拉回可见；
## chunk 重建会清掉淡化状态，重建末尾按本表重放锁定。
var _prop_fade_holds: Dictionary = {}


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
	_clear_prop_cell(cell)
	_mark_chunk_dirty(cell)


func clear() -> void:
	_cells.clear()
	_dirty_chunks.clear()
	_water_ripples.clear()
	_refresh_ripple_multimesh()
	_hidden_columns.clear()
	_prop_fade_holds.clear()
	for chunk_value in _chunks.values():
		var chunk: Node3D = chunk_value
		if is_instance_valid(chunk):
			chunk.free()
	_chunks.clear()
	_clear_all_prop_cells()


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


## 有植物 prop 实例的格子（遮挡淡化的候选集合）。
func get_prop_cells() -> Array:
	return _prop_instances.keys()


## 指定格的植物 prop 实例数据（中心世界坐标、地面锚点、贴图与像素尺寸）。
func get_prop_block_occlusion_data(cell: Vector2i) -> Array:
	return _prop_instances.get(cell, [])


## 指定格当前的淡化透明度（无淡化状态视为 1.0）。
func get_prop_fade_alpha(cell: Vector2i) -> float:
	var state: Dictionary = _prop_fades.get(cell, {})
	return float(state.get("current", 1.0))


## 有活动淡化状态的格子（main.gd 用来镜像调试状态）。
func get_active_prop_fade_cells() -> Array:
	return _prop_fades.keys()


## 设定某格植物的目标透明度：<1 时隐藏原 multimesh 实例（共享材质不受影响），
## 改为逐节点代理呈现；=1 时恢复到原实例。逐帧调用 advance_prop_fades 驱动缓动。
## 被 set_prop_fade_hold 锁定的格忽略本写入（main.gd 玩家遮挡周期重建不会顶掉战斗锁定）。
func set_prop_fade_target(cell: Vector2i, alpha: float) -> void:
	if _prop_fade_holds.has(cell):
		return
	_apply_prop_fade_target(cell, alpha)


## 透明度锁定：锁定期间 set_prop_fade_target 对该格无效；chunk 重建后自动重放锁定。
## clear 时目标回到 1.0（交还 main.gd，其 0.5s 周期重建会按需重新淡化）。
func set_prop_fade_hold(cell: Vector2i, alpha: float) -> void:
	_prop_fade_holds[cell] = clampf(alpha, 0.0, 1.0)
	_apply_prop_fade_target(cell, float(_prop_fade_holds[cell]))


func clear_prop_fade_hold(cell: Vector2i) -> void:
	if not _prop_fade_holds.has(cell):
		return
	_prop_fade_holds.erase(cell)
	_apply_prop_fade_target(cell, 1.0)


func has_prop_fade_hold(cell: Vector2i) -> bool:
	return _prop_fade_holds.has(cell)


## 战斗沉浸遮挡：临时隐藏整柱（幂等，flush 后生效）。柱体与格上植物一并消失。
func set_column_hidden(cell: Vector2i, hidden: bool) -> void:
	if _hidden_columns.has(cell) == hidden:
		return
	if hidden:
		_hidden_columns[cell] = true
	else:
		_hidden_columns.erase(cell)
	_mark_chunk_dirty(cell)


func is_column_hidden(cell: Vector2i) -> bool:
	return _hidden_columns.has(cell)


func get_hidden_columns() -> Array:
	return _hidden_columns.keys()


## 战斗沉浸遮挡查询：bounds 内的柱数据 [{cell, center, top}]，center 为柱顶面中心，
## top 为柱顶世界 Y（取 blocks 最大 level）。调用方按有界 bounds 查询，不遍历无限世界。
func get_column_occlusion_data(bounds_min: Vector2i, bounds_max: Vector2i) -> Array:
	var result: Array = []
	for cell_value in _cells.keys():
		var cell: Vector2i = cell_value
		if cell.x < bounds_min.x or cell.x > bounds_max.x:
			continue
		if cell.y < bounds_min.y or cell.y > bounds_max.y:
			continue
		var top := 0.0
		for block_value in (_cells[cell]["blocks"] as Array):
			top = maxf(top, float((block_value as Dictionary).get("level", 0)) * IsoProjection.LEVEL_HEIGHT)
		result.append({"cell": cell, "center": IsoProjection.grid_to_world(cell, top), "top": top})
	return result


func _apply_prop_fade_target(cell: Vector2i, alpha: float) -> void:
	var clamped := clampf(alpha, 0.0, 1.0)
	var state: Dictionary = _prop_fades.get(cell, {})
	if state.is_empty():
		if clamped >= 1.0 - PROP_FADE_SETTLE:
			return
		var entries: Array = _prop_instances.get(cell, [])
		if entries.is_empty():
			return
		state = {"target": clamped, "current": 1.0, "entries": entries, "sprites": []}
		var layer := _ensure_fade_layer()
		for entry_value in entries:
			var entry: Dictionary = entry_value
			_hide_prop_instance(entry)
			var sprite := _make_prop_proxy(entry)
			layer.add_child(sprite)
			(state["sprites"] as Array).append(sprite)
		_prop_fades[cell] = state
	else:
		state["target"] = clamped


## 推进所有活动植物格淡化的指数缓动；返回 true 表示全部收敛。
func advance_prop_fades(delta: float) -> bool:
	var settled := true
	var finished: Array = []
	for cell_value in _prop_fades.keys():
		var cell: Vector2i = cell_value
		var state: Dictionary = _prop_fades[cell]
		var target := float(state["target"])
		var current := float(state["current"])
		var rate := PROP_FADE_OUT_RATE if target < current else PROP_FADE_IN_RATE
		current = lerpf(current, target, 1.0 - exp(-rate * maxf(delta, 0.0)))
		if absf(current - target) <= PROP_FADE_SETTLE:
			current = target
		else:
			settled = false
		state["current"] = current
		var entries: Array = state["entries"]
		var sprites: Array = state["sprites"]
		for index in sprites.size():
			var tint: Color = (entries[index] as Dictionary)["tint"]
			(sprites[index] as Sprite3D).modulate = Color(tint.r, tint.g, tint.b, tint.a * current)
		if current >= 1.0 - PROP_FADE_SETTLE:
			finished.append(cell)
	for cell_value in finished:
		_restore_prop_cell(cell_value as Vector2i)
	return settled


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
			# chunk 重建会替换该格全部 prop 实例，旧注册与代理同步清理。
			_clear_prop_cell(cell)
			if _hidden_columns.has(cell):
				continue
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
	# 透明度锁定重放：_clear_prop_cell 已清掉本 chunk 全部淡化状态，
	# 被外部（战斗沉浸遮挡）锁定的格需要按锁定表重新隐藏。
	for y in range(min_cell.y, min_cell.y + CHUNK_SIZE):
		for x in range(min_cell.x, min_cell.x + CHUNK_SIZE):
			var held := Vector2i(x, y)
			if _prop_fade_holds.has(held):
				_apply_prop_fade_target(held, float(_prop_fade_holds[held]))


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
			"cells": [],
			"metas": [],
		}
	var anchor := IsoProjection.grid_to_world(cell, float(block.get("level", 0)))
	var center := anchor + _screen_offset_world(block.get("render_offset", Vector2.ZERO))
	(props[key]["transforms"] as Array).append(Transform3D(Basis.IDENTITY, center))
	(props[key]["colors"] as Array).append(tint)
	(props[key]["cells"] as Array).append(cell)
	(props[key]["metas"] as Array).append({
		"texture": texture,
		"origin_px": region.position,
		"size_px": region.size,
		"center": center,
		"anchor": anchor,
		"tint": tint,
	})


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
	var cells: Array = group["cells"]
	var metas: Array = group["metas"]
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
		multimesh.set_instance_color(index, group["colors"][index])
		# 遮挡淡化注册：按格隐藏单个实例颜色，共享材质与其他植物不受影响。
		var meta: Dictionary = metas[index]
		var entry := {
			"multimesh": multimesh,
			"index": index,
			"texture": meta["texture"],
			"origin_px": meta["origin_px"],
			"size_px": meta["size_px"],
			"center": meta["center"],
			"anchor": meta["anchor"],
			"tint": meta["tint"],
			"hidden": false,
		}
		var cell: Vector2i = cells[index]
		if not _prop_instances.has(cell):
			_prop_instances[cell] = []
		(_prop_instances[cell] as Array).append(entry)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(instance)


func _ensure_fade_layer() -> Node3D:
	if not is_instance_valid(_fade_layer):
		_fade_layer = Node3D.new()
		_fade_layer.name = "PropFadeLayer"
		add_child(_fade_layer)
	return _fade_layer


func _make_prop_proxy(entry: Dictionary) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = entry["texture"]
	sprite.pixel_size = 1.0 / IsoProjection.TILE_PIXELS
	sprite.position = entry["center"]
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.shaded = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.modulate = entry["tint"]
	return sprite


func _hide_prop_instance(entry: Dictionary) -> void:
	var multimesh: MultiMesh = entry["multimesh"]
	if is_instance_valid(multimesh):
		multimesh.set_instance_color(int(entry["index"]), Color(0.0, 0.0, 0.0, 0.0))
	entry["hidden"] = true


func _restore_prop_cell(cell: Vector2i) -> void:
	var state: Dictionary = _prop_fades.get(cell, {})
	if state.is_empty():
		return
	for sprite_value in state["sprites"]:
		var sprite: Sprite3D = sprite_value
		if is_instance_valid(sprite):
			sprite.queue_free()
	for entry_value in state["entries"]:
		var entry: Dictionary = entry_value
		var multimesh: MultiMesh = entry["multimesh"]
		if is_instance_valid(multimesh):
			multimesh.set_instance_color(int(entry["index"]), entry["tint"])
		entry["hidden"] = false
	_prop_fades.erase(cell)


func _clear_prop_cell(cell: Vector2i) -> void:
	if _prop_fades.has(cell):
		var state: Dictionary = _prop_fades[cell]
		for sprite_value in state["sprites"]:
			var sprite: Sprite3D = sprite_value
			if is_instance_valid(sprite):
				sprite.queue_free()
		_prop_fades.erase(cell)
	_prop_instances.erase(cell)


func _clear_all_prop_cells() -> void:
	for cell_value in _prop_fades.keys():
		var state: Dictionary = _prop_fades[cell_value]
		for sprite_value in state["sprites"]:
			var sprite: Sprite3D = sprite_value
			if is_instance_valid(sprite):
				sprite.queue_free()
	_prop_fades.clear()
	_prop_instances.clear()


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
