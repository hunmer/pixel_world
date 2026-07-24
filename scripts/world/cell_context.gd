class_name CellContext
extends RefCounted

## Immutable-by-convention terrain/ecology facts for one logical world cell.
## Renderer payload and scene nodes deliberately do not live here.

var cell: Vector2i
var height: int
var biome_id: StringName
var biome_index: int
var landform_id: StringName
var landform_index: int
var water_depth: int
var is_water: bool
var is_shore: bool
var surface_id: StringName
var tags: Dictionary[StringName, bool] = {}
var region_anchor: Vector2i
var _ecology_signature_cache := ""


func _init(
	initial_cell: Vector2i = Vector2i.ZERO,
	initial_height: int = 0,
	initial_biome_id: StringName = &"",
	initial_biome_index: int = -1,
	initial_landform_id: StringName = &"",
	initial_landform_index: int = -1,
	initial_water_depth: int = 0,
	initial_is_water: bool = false,
	initial_is_shore: bool = false,
	initial_surface_id: StringName = &"",
	initial_region_anchor: Vector2i = Vector2i.ZERO,
	initial_tags: Array[StringName] = []
) -> void:
	cell = initial_cell
	height = initial_height
	biome_id = initial_biome_id
	biome_index = initial_biome_index
	landform_id = initial_landform_id
	landform_index = initial_landform_index
	water_depth = maxi(0, initial_water_depth)
	is_water = initial_is_water
	is_shore = initial_is_shore
	surface_id = initial_surface_id
	region_anchor = initial_region_anchor
	for tag in initial_tags:
		tags[tag] = true


func add_tag(tag: StringName) -> void:
	if not tag.is_empty():
		tags[tag] = true
		_ecology_signature_cache = ""


func remove_tag(tag: StringName) -> void:
	tags.erase(tag)
	_ecology_signature_cache = ""


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func has_all_tags(required_tags: Array[StringName]) -> bool:
	for tag in required_tags:
		if not tags.has(tag):
			return false
	return true


func has_any_tag(candidate_tags: Array[StringName]) -> bool:
	for tag in candidate_tags:
		if tags.has(tag):
			return true
	return false


func tag_list() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(tags.keys())
	result.sort()
	return result


## Stable cache identity for habitat rules. It deliberately excludes the cell
## coordinate: placement randomness remains per-cell, while rule applicability
## depends only on these immutable ecological facts.
func ecology_signature() -> String:
	if _ecology_signature_cache.is_empty():
		_ecology_signature_cache = "%s|%s|%s|%d|%d|%d|%d|%s" % [
			biome_id,
			landform_id,
			surface_id,
			height,
			water_depth,
			1 if is_water else 0,
			1 if is_shore else 0,
			",".join(tag_list()),
		]
	return _ecology_signature_cache
