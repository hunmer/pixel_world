extends SceneTree

## Pure TerrainSampler contract for future landforms. This test deliberately
## does not instantiate main.tscn: renderer/legacy enums must not be part of the
## extension boundary for volcanic plateaus, ice sheets, or later terrain.

const TerrainSamplerScript = preload("res://scripts/world/terrain_sampler.gd")

const CONFIG_PATH := "res://config/ecosystems.json"
const TEMPERATE_SCRIPT := "res://scripts/world/biomes/temperate_biome.gd"
const FUTURE_LANDFORM_ID := &"volcanic_plateau"
const TEST_SEED := 24681357

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _load_generation() -> Dictionary:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		failures.append("cannot read ecosystems.json")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		failures.append("ecosystems.json is not a Dictionary")
		return {}
	var generation_value: Variant = (parsed as Dictionary).get("generation", {})
	if not generation_value is Dictionary:
		failures.append("ecosystems.json generation is not a Dictionary")
		return {}
	return (generation_value as Dictionary).duplicate(true)


func _future_generation() -> Dictionary:
	var generation := _load_generation()
	if generation.is_empty():
		return {}
	# This fixture has one fallback biome, so its compatibility index order is
	# intentionally independent of the production biome catalog.
	generation["biome_index_order"] = ["plains"]
	var regions: Dictionary = generation.get("regions", {})
	var landforms: Array = regions.get("landforms", [])
	landforms.append({
		"id": FUTURE_LANDFORM_ID,
		"name": "Volcanic Plateau",
		# Make the new entry dominant so a small deterministic region scan always
		# exercises it while all existing configured landforms still coexist.
		"weight": 1000000.0,
		"terrain": {
			"offset": 0.42,
			"amplitude": 2.25,
			"ridge": 0.9,
			"underwater_steepness": 2.8,
			"peak": 1.3,
			"terrace": 0.65,
		},
	})
	regions["landforms"] = landforms
	generation["regions"] = regions
	return generation


func _biome_definitions() -> Array:
	return [{
		"id": "temperate_fixture",
		"script": TEMPERATE_SCRIPT,
		"priority": -1000,
		"classification_id": "plains",
		"aliases": ["plains"],
		"tags": ["temperate", "mild"],
	}]


func _find_region(sampler: RefCounted, landform_id: StringName) -> Variant:
	for y in range(-8, 9):
		for x in range(-8, 9):
			var region := Vector2i(x, y)
			if sampler.landform_id_for_region(region) == landform_id:
				return region
	return null


func _snapshot(sampler: RefCounted) -> String:
	var values := PackedStringArray()
	for y in range(-5, 6):
		for x in range(-5, 6):
			var region := Vector2i(x, y)
			var anchor := Vector2i(sampler.seed_point(region).round())
			var context = sampler.sample(anchor)
			values.append(
				"%d,%d:%s:%d:%s"
				% [
					region.x,
					region.y,
					sampler.landform_id_for_region(region),
					context.height,
					context.surface_id,
				]
			)
	return "|".join(values).sha256_text()


func _run() -> void:
	var generation := _future_generation()
	if generation.is_empty():
		_finish()
		return
	var configured_landform_count := (
		(generation["regions"] as Dictionary).get("landforms", []) as Array
	).size()
	var future_index := configured_landform_count - 1
	var sampler_a = TerrainSamplerScript.new()
	var sampler_b = TerrainSamplerScript.new()
	_expect(
		sampler_a.configure(generation, _biome_definitions(), TEST_SEED),
		"sampler rejected an unknown configured landform id: %s" % sampler_a.last_error
	)
	_expect(
		sampler_b.configure(generation, _biome_definitions(), TEST_SEED),
		"second sampler rejected future landform config: %s" % sampler_b.last_error
	)
	if not sampler_a.configured or not sampler_b.configured:
		_finish()
		return

	_expect(
		sampler_a.landform_id_for_index(future_index) == FUTURE_LANDFORM_ID,
		"future landform did not keep its dynamic config-order index"
	)
	_expect(
		sampler_a.landform_id_for_index(configured_landform_count).is_empty(),
		"out-of-range dynamic landform lookup should be empty"
	)

	var future_region: Variant = _find_region(sampler_a, FUTURE_LANDFORM_ID)
	_expect(future_region != null, "deterministic region scan did not select future landform")
	if future_region != null:
		var region: Vector2i = future_region
		var sample_cell := Vector2i(sampler_a.seed_point(region).round())
		var context = sampler_a.sample(sample_cell)
		var legacy_values: Array = sampler_a.modules(sample_cell)
		_expect(
			context.landform_id == FUTURE_LANDFORM_ID,
			"CellContext lost the future landform id"
		)
		_expect(
			context.landform_index == future_index,
			"CellContext did not expose the dynamic config-order index"
		)
		_expect(
			context.has_tag(&"volcanic_plateau")
			and context.has_tag(&"landform:volcanic_plateau"),
			"CellContext did not publish future landform habitat tags"
		)
		_expect(
			int(legacy_values[0]) == future_index,
			"modules() adapter replaced the dynamic index with a fixed enum"
		)

	var first_snapshot := _snapshot(sampler_a)
	_expect(
		first_snapshot == _snapshot(sampler_b),
		"same config and seed produced different dynamic-landform samples"
	)
	sampler_a.reseed(TEST_SEED)
	_expect(
		first_snapshot == _snapshot(sampler_a),
		"reseed with the same seed did not restore dynamic-landform samples"
	)

	_finish()


func _finish() -> void:
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("DYNAMIC_LANDFORM_CONTRACT_OK")
	quit(0)
