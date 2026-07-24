class_name CellState
extends RefCounted

const CellContextType = preload("res://scripts/world/cell_context.gd")

## Logical occupancy tags. Rendering may consume these facts, but gameplay must
## never infer them back from render priority, texture, or a Node's private data.
const OCCUPANCY_BLOCKS_MOVEMENT: StringName = &"blocks_movement"
const OCCUPANCY_STATIC_FLORA: StringName = &"static_flora"
const OCCUPANCY_BLOCKS_FAUNA_SPAWN: StringName = &"blocks_fauna_spawn"

var context: CellContextType
var render_blocks: Array[Dictionary] = []
var static_objects: Array[Dictionary] = []
var occupancy_tags: Dictionary[StringName, bool] = {}


func _init(initial_context: CellContextType = null) -> void:
	context = initial_context


func add_occupancy_tag(tag: StringName) -> void:
	if not tag.is_empty():
		occupancy_tags[tag] = true


func remove_occupancy_tag(tag: StringName) -> void:
	occupancy_tags.erase(tag)


func has_occupancy_tag(tag: StringName) -> bool:
	return occupancy_tags.has(tag)


func add_static_object(object_data: Dictionary) -> void:
	var stored_object := object_data.duplicate(true)
	static_objects.append(stored_object)
	var category := StringName(stored_object.get("category", &""))
	if category == &"flora":
		add_occupancy_tag(OCCUPANCY_STATIC_FLORA)
	if bool(stored_object.get("blocks_movement", false)):
		add_occupancy_tag(OCCUPANCY_BLOCKS_MOVEMENT)
	if bool(stored_object.get("blocks_fauna_spawn", false)):
		add_occupancy_tag(OCCUPANCY_BLOCKS_FAUNA_SPAWN)
	for tag_value in stored_object.get("occupancy_tags", []):
		add_occupancy_tag(StringName(tag_value))


func add_render_block(block_data: Dictionary) -> void:
	render_blocks.append(block_data.duplicate(true))


func blocks_movement() -> bool:
	return has_occupancy_tag(OCCUPANCY_BLOCKS_MOVEMENT)


func has_static_flora() -> bool:
	return has_occupancy_tag(OCCUPANCY_STATIC_FLORA)


## The default models current land-fauna behavior. Future aquatic species can
## explicitly opt into water without teaching CellState about species IDs.
func can_spawn_fauna(
	allow_water: bool = false,
	require_flora_miss: bool = true
) -> bool:
	if context == null:
		return false
	if context.is_water and not allow_water:
		return false
	return (
		not blocks_movement()
		and (not require_flora_miss or not has_static_flora())
		and not has_occupancy_tag(OCCUPANCY_BLOCKS_FAUNA_SPAWN)
	)
