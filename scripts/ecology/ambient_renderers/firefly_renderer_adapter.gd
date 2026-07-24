extends Node

## Adapts the existing FireflyField to AmbientRegistry's renderer contract.
## No firefly-specific branch is needed in the registry or caller.

const FireflyFieldScript = preload("res://scripts/firefly_field.gd")

var _field: Node


func _ready() -> void:
	_ensure_field()


func configure(profile: Dictionary = {}) -> void:
	_ensure_field().configure(
		int(profile.get("max_visible", 72)),
		int(profile.get("max_lights", 12))
	)


func add_cluster(
	cell: Vector2i,
	host: Node2D,
	local_surface_position: Vector2,
	count: int,
	deterministic_seed: int
) -> void:
	_ensure_field().add_cluster(
		cell,
		host,
		local_surface_position,
		count,
		deterministic_seed
	)


func remove_cell(cell: Vector2i) -> void:
	_ensure_field().remove_cell(cell)


func clear() -> void:
	_ensure_field().clear()


func refresh_field() -> void:
	_ensure_field().refresh_field()


func set_environment_amount(amount: float) -> void:
	_ensure_field().set_night_amount(amount)


func get_registered_count() -> int:
	return _ensure_field().get_registered_count()


func get_active_count() -> int:
	return _ensure_field().get_active_count()


func get_active_light_count() -> int:
	return _ensure_field().get_active_light_count()


func _ensure_field() -> Node:
	if is_instance_valid(_field):
		return _field
	_field = FireflyFieldScript.new()
	_field.name = "FireflyField"
	add_child(_field)
	return _field
