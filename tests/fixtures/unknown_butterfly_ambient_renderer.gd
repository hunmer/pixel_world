extends Node

## A renderer type unknown to AmbientRegistry, used to prove plugin loading.

var configured_profile: Dictionary = {}
var configure_count := 0
var clusters: Dictionary = {}
var removed_cells: Array[Vector2i] = []
var clear_count := 0
var refresh_count := 0
var environment_amount := 0.0
var environment_update_count := 0


func configure(profile: Dictionary = {}) -> void:
	configured_profile = profile.duplicate(true)
	configure_count += 1


func add_cluster(
	cell: Vector2i,
	host: Node2D,
	local_surface_position: Vector2,
	count: int,
	deterministic_seed: int
) -> void:
	clusters[cell] = {
		"host": host,
		"position": local_surface_position,
		"count": count,
		"seed": deterministic_seed,
	}


func remove_cell(cell: Vector2i) -> void:
	clusters.erase(cell)
	removed_cells.append(cell)


func clear() -> void:
	clusters.clear()
	clear_count += 1


func refresh_field() -> void:
	refresh_count += 1


func set_environment_amount(amount: float) -> void:
	environment_amount = amount
	environment_update_count += 1
