extends SceneTree

const EXPECTED_SEED_42_HASH := "0c3f713bb202119938a5b7745e310f2e3800869b11acf13b93fb88b339abfc2f"
const SAMPLE_RADIUS := 256
const SAMPLE_STEP := 4


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	world.seed = 42
	root.add_child(world)
	await process_frame
	world.set_process(false)

	var samples := PackedStringArray()
	for y in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, SAMPLE_STEP):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, SAMPLE_STEP):
			var cell := Vector2i(x, y)
			var q: int = world._quantize(x, y)
			var biome: int = world._biome(x, y, q)
			var beach: bool = world._is_beach(cell, q)
			var landform: int = world._modules(x, y)[0]
			var desert_surface: int = world._desert_surface_kind(cell, q, biome)
			samples.append(
				"%d,%d,%d,%d,%d"
				% [q, biome, int(beach), landform, desert_surface]
			)
	var snapshot_hash := "|".join(samples).sha256_text()
	print("TERRAIN_SEED_42_HASH ", snapshot_hash, " samples=", samples.size())
	if not EXPECTED_SEED_42_HASH.is_empty() and snapshot_hash != EXPECTED_SEED_42_HASH:
		push_error(
			"地形生成发生回归: %s != %s"
			% [snapshot_hash, EXPECTED_SEED_42_HASH]
		)
		quit(1)
		return
	print("TERRAIN_GENERATION_CONTRACT_OK")
	quit(0)
