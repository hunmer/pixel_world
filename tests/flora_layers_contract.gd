extends SceneTree

const SCAN_RADIUS := 256
const POOL_REACHABILITY_SAMPLES := 2048
const NEW_SPECIES := [
	"agave_small",
	"barrel_cactus",
	"dwarf_cactus",
	"prickly_pear_cactus",
	"dry_shrub_small",
	"twisted_dead_tree",
	"grass_clump_round",
	"grass_tuft_sparse",
	"grass_tuft_dense",
	"wildflower_pink",
	"wildflower_orange",
	"snowy_grass_clump_green",
	"snowy_grass_clump_round",
	"snowy_tree_stump",
	"snowy_tree_stump_tall",
	"autumn_maple_tree",
	"pine_tree_dense",
	"blue_spruce_tree_small",
	"pine_tree_tall",
	"palm_tree_small",
	"palm_tree_tall",
	"banyan_tree",
	"cherry_blossom_tree_small",
	"birch_tree_slender",
	"apple_tree",
	"dead_tree_bent",
	"dead_tree_tall",
	"snowy_pine_small",
	"snowy_pine_round",
	"snowy_pine_large",
	"dry_brush_patch",
	"grass_tuft_narrow",
	"grass_tuft_lush",
	"snowy_grass_tuft_silver",
	"snowy_grass_tuft_green",
	"wildflower_purple",
	"wildflower_blue",
	"wildflower_yellow",
	"mushroom_cluster_red",
	"mushroom_cluster_brown",
	"mushroom_cluster_red_large",
	"matsutake_mushroom",
	"flowering_prickly_pear_cactus",
	"saguaro_cactus",
	"flowering_barrel_cactus",
]

const EXPECTED_LAYER_COUNTS := {
	"tree": 1342,
	"ground_cover": 12218,
	"decoration": 1390,
}
const EXPECTED_TEMPERATE_LAYER_COUNTS := {
	"tree": 948,
	"ground_cover": 7404,
	"decoration": 351,
}
const EXPECTED_CONFLICT_CELLS := 489
const MUSHROOM_HABITAT_RADIUS := 4
const MIN_FINAL_MUSHROOMS := 250
const MIN_CLUSTER_VARIANT_COUNT := 40
const MUSHROOM_SPECIES := [
	"mushroom_cluster_red",
	"mushroom_cluster_brown",
	"mushroom_cluster_red_large",
	"matsutake_mushroom",
]

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _expect_only_ecosystems(
	species_ecosystems: Dictionary,
	species_id: String,
	allowed_ecosystems: Array[String]
) -> void:
	var actual: Array = species_ecosystems.get(species_id, {}).keys()
	actual.sort()
	var expected: Array = allowed_ecosystems.duplicate()
	expected.sort()
	_expect(
		actual == expected,
		"物种生态归属错误 [%s]: %s != %s" % [species_id, actual, expected]
	)


func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	world.seed = 42
	root.add_child(world)
	await process_frame
	world.set_process(false)

	_expect(world._tree_placement != world._ground_cover_placement, "树木和地被复用了同一噪声实例")
	_expect(world._tree_placement != world._decoration_placement, "树木和装饰复用了同一噪声实例")
	_expect(world._ground_cover_placement != world._decoration_placement, "地被和装饰复用了同一噪声实例")

	var referenced_species := {}
	var reachable_species := {}
	var species_ecosystems := {}
	var large_boulder_ecosystems := {}
	for ecosystem in world._ecosystem_order:
		var ecosystem_id := String(ecosystem["id"])
		for rule_value in ecosystem.get("flora", []):
			var rule: Dictionary = rule_value
			for sample_index in range(POOL_REACHABILITY_SAMPLES):
				var sample_cluster := Vector2i(sample_index % 64, sample_index / 64)
				var sample_cell := Vector2i(sample_index * 17, sample_index * 31)
				var reachable_id: String = world._pick_species(rule, sample_cluster, sample_cell)
				if not reachable_id.is_empty():
					reachable_species[reachable_id] = true
			for species_id_value in rule.get("species", []):
				var species_id := String(species_id_value)
				referenced_species[species_id] = true
				if not species_ecosystems.has(species_id):
					species_ecosystems[species_id] = {}
				species_ecosystems[species_id][ecosystem_id] = true
				if species_id == "mossy_boulder_large":
					large_boulder_ecosystems[ecosystem_id] = true
	_expect(
		large_boulder_ecosystems.size() == 2
		and large_boulder_ecosystems.has("desert")
		and large_boulder_ecosystems.has("desert_transition"),
		"黄色大苔石只能进入沙漠核心和过渡带: %s" % large_boulder_ecosystems
	)
	for species_id in NEW_SPECIES:
		_expect(world._plant_species.has(species_id), "配置缺少新增物种: " + species_id)
		_expect(referenced_species.has(species_id), "新增物种没有进入任何生态池: " + species_id)
		_expect(reachable_species.has(species_id), "新增物种无法被物种选择器抽中: " + species_id)
		if world._plant_species.has(species_id):
			var texture_path := String(world._plant_species[species_id].get("texture", ""))
			_expect(ResourceLoader.exists(texture_path), "新增物种资源不存在: " + texture_path)

	_expect_only_ecosystems(species_ecosystems, "palm_tree_small", ["desert_shore"])
	_expect_only_ecosystems(species_ecosystems, "palm_tree_tall", ["desert_shore"])
	_expect_only_ecosystems(species_ecosystems, "banyan_tree", ["shore"])
	for species_id in [
		"snowy_pine_small",
		"snowy_pine_round",
		"snowy_pine_large",
		"snowy_grass_tuft_silver",
		"snowy_grass_tuft_green",
	]:
		_expect_only_ecosystems(species_ecosystems, species_id, ["snow"])
	for species_id in MUSHROOM_SPECIES:
		_expect_only_ecosystems(species_ecosystems, species_id, ["temperate"])
		var habitat: Dictionary = world._plant_species[species_id].get("habitat", {})
		_expect(
			String(habitat.get("near_flora_layer", "")) == "tree"
			and int(habitat.get("radius", 0)) == MUSHROOM_HABITAT_RADIUS
			and String(habitat.get("fallback_species", "")) == "grass_clump_round",
			"蘑菇缺少树旁 habitat 配置: " + species_id
		)

	var selected_by_layer := {"tree": 0, "ground_cover": 0, "decoration": 0}
	var selected_by_species := {}
	var temperate_by_layer := {"tree": 0, "ground_cover": 0, "decoration": 0}
	var temperate_by_species := {}
	var example_by_layer := {}
	var conflict_cells := 0
	var deterministic_samples := 0
	var selected_mushrooms := 0
	var mushroom_habitat_replacements := 0
	for y in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
		for x in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
			var cell := Vector2i(x, y)
			var q: int = world._quantize(x, y)
			var biome: int = world._biome(x, y, q)
			var beach: bool = world._is_beach(cell, q)
			var modules: Array = world._modules(x, y)
			var ecosystem_id: String = world._ecosystem_id_for_cell(q, biome, beach, modules[0])
			var ecosystem: Dictionary = world._ecosystems_by_id[ecosystem_id]
			var candidates: Array[Dictionary] = world._flora_candidates_for_cell(
				cell,
				q,
				modules[0],
				modules[7],
				ecosystem
			)
			if candidates.size() > 1:
				conflict_cells += 1
			var selected: Dictionary = world._select_flora_candidate(cell, candidates)
			if selected.is_empty():
				continue
			var layer_id := String(selected["layer"])
			var species_id := String(selected["species_id"])
			var habitat_origin := ""
			var selected_sort_key := String(selected.get("sort_key", ""))
			for mushroom_id in MUSHROOM_SPECIES:
				if selected_sort_key.ends_with("/" + mushroom_id):
					habitat_origin = mushroom_id
					break
			if not habitat_origin.is_empty():
				var near_tree: bool = world._has_raw_selected_flora_layer_within(
					cell, "tree", MUSHROOM_HABITAT_RADIUS
				)
				if near_tree:
					selected_mushrooms += 1
					_expect(
						species_id == habitat_origin,
						"树旁蘑菇被错误替换 [%s]: %s" % [cell, species_id]
					)
				else:
					mushroom_habitat_replacements += 1
					_expect(
						species_id == "grass_clump_round",
						"空旷处蘑菇没有替换为草丛 [%s]: %s" % [cell, species_id]
					)
			selected_by_layer[layer_id] = int(selected_by_layer[layer_id]) + 1
			selected_by_species[species_id] = int(selected_by_species.get(species_id, 0)) + 1
			if ecosystem_id == "temperate":
				temperate_by_layer[layer_id] = int(temperate_by_layer[layer_id]) + 1
				temperate_by_species[species_id] = int(temperate_by_species.get(species_id, 0)) + 1
			if not example_by_layer.has(layer_id):
				example_by_layer[layer_id] = {"cell": cell, "species_id": species_id}
			if deterministic_samples < 512:
				var repeated: Dictionary = world._select_flora_candidate(cell, candidates)
				_expect(
					String(repeated.get("species_id", "")) == species_id,
					"同一种子重复选择结果不一致: %s" % cell
				)
				deterministic_samples += 1

	_expect(conflict_cells > 0, "扫描范围没有产生任何跨层冲突，无法验证同格随机")
	_expect(
		selected_by_layer == EXPECTED_LAYER_COUNTS,
		"新增品种改变了全局静态对象疏密度: %s" % selected_by_layer
	)
	_expect(
		temperate_by_layer == EXPECTED_TEMPERATE_LAYER_COUNTS,
		"新增品种改变了温带静态对象疏密度: %s" % temperate_by_layer
	)
	_expect(
		conflict_cells == EXPECTED_CONFLICT_CELLS,
		"新增品种改变了跨层候选密度: %d" % conflict_cells
	)
	_expect(
		selected_mushrooms >= MIN_FINAL_MUSHROOMS,
		"树旁蘑菇数量过少: %d" % selected_mushrooms
	)
	_expect(mushroom_habitat_replacements > 0, "扫描范围没有验证空旷蘑菇替换")
	for mushroom_id in [
		"mushroom_cluster_red",
		"mushroom_cluster_brown",
		"mushroom_cluster_red_large",
	]:
		_expect(
			int(selected_by_species.get(mushroom_id, 0)) >= MIN_CLUSTER_VARIANT_COUNT,
			"成簇蘑菇品种数量过少 [%s]: %d"
			% [mushroom_id, int(selected_by_species.get(mushroom_id, 0))]
		)
	_expect(
		int(selected_by_species.get("matsutake_mushroom", 0)) * 4
		< selected_mushrooms,
		"松茸在蘑菇池中的占比过高: %s" % selected_by_species
	)
	for layer_id in world.FLORA_LAYER_IDS:
		_expect(int(selected_by_layer[layer_id]) > 0, "没有自然生成层: " + layer_id)
		_expect(example_by_layer.has(layer_id), "缺少实际渲染样本层: " + layer_id)
	_expect(
		int(temperate_by_layer["ground_cover"]) > int(temperate_by_layer["tree"]) * 3,
		"温带地被没有显著多于树木: %s" % temperate_by_layer
	)
	_expect(
		int(temperate_by_layer["decoration"]) < int(temperate_by_layer["ground_cover"]),
		"温带装饰物不应多于地被: %s" % temperate_by_layer
	)
	var temperate_live_trees := 0
	for species_id in [
		"broadleaf_tree",
		"autumn_maple_tree",
		"apple_tree",
		"birch_tree",
		"birch_tree_slender",
		"cherry_blossom_tree",
		"cherry_blossom_tree_small",
		"pine_tree",
		"pine_tree_dense",
		"pine_tree_tall",
		"blue_spruce_tree",
		"blue_spruce_tree_small",
	]:
		temperate_live_trees += int(temperate_by_species.get(species_id, 0))
	var temperate_dead_trees := (
		int(temperate_by_species.get("dead_tree", 0))
		+ int(temperate_by_species.get("dead_tree_bent", 0))
		+ int(temperate_by_species.get("dead_tree_tall", 0))
	)
	_expect(
		temperate_dead_trees * 10 < temperate_live_trees,
		"普通温带枯树不应接近活树密度: %s" % temperate_by_species
	)
	var temperate_grass := (
		int(temperate_by_species.get("grass_tuft_sparse", 0))
		+ int(temperate_by_species.get("grass_tuft_dense", 0))
		+ int(temperate_by_species.get("grass_tuft_narrow", 0))
		+ int(temperate_by_species.get("grass_tuft_lush", 0))
		+ int(temperate_by_species.get("grass_clump_round", 0))
	)
	var temperate_flowers := (
		int(temperate_by_species.get("wildflower_pink", 0))
		+ int(temperate_by_species.get("wildflower_orange", 0))
		+ int(temperate_by_species.get("wildflower_purple", 0))
		+ int(temperate_by_species.get("wildflower_blue", 0))
		+ int(temperate_by_species.get("wildflower_yellow", 0))
	)
	_expect(
		temperate_flowers * 4 < temperate_grass,
		"温带野花应明显少于青草: %s" % temperate_by_species
	)
	var streamed_flora_max := 0
	for cell_value in world._cells:
		var flora_count := 0
		for block in world._cell_states[cell_value].render_blocks:
			if block.has("flora_species_id"):
				flora_count += 1
		streamed_flora_max = maxi(streamed_flora_max, flora_count)
		_expect(flora_count <= 1, "同格实际渲染了多个静态对象: %s" % cell_value)

	var rendered_examples := {}
	for layer_id in world.FLORA_LAYER_IDS:
		if not example_by_layer.has(layer_id):
			continue
		var example: Dictionary = example_by_layer[layer_id]
		var example_cell: Vector2i = example["cell"]
		var expected_species := String(example["species_id"])
		world._player_cell = example_cell
		world._regenerate(42)
		await process_frame
		var rendered_species := ""
		if world._cells.has(example_cell):
			for block in world._cell_states[example_cell].render_blocks:
				if block.has("flora_species_id"):
					rendered_species = String(block["flora_species_id"])
					break
		rendered_examples[layer_id] = rendered_species
		_expect(
			rendered_species == expected_species,
			"候选没有进入实际渲染 [%s]: %s != %s"
			% [layer_id, rendered_species, expected_species]
		)

	print(
		"FLORA_LAYER_METRICS selected_by_layer=", selected_by_layer,
		" temperate=", temperate_by_layer,
		" conflicts=", conflict_cells,
		" mushrooms=", selected_mushrooms,
		" mushroom_fallbacks=", mushroom_habitat_replacements,
		" streamed_max=", streamed_flora_max
	)
	print("NEW_SPECIES_METRICS ", selected_by_species)
	print("FLORA_RENDERED_EXAMPLES ", rendered_examples)
	if failures.is_empty():
		print("FLORA_LAYERS_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
