extends SceneTree

const AnimalScript = preload("res://scripts/wandering_animal.gd")
const FISH_SPECIES := [
	"goldfish",
	"blue_goldfish",
	"calico_goldfish",
	"crucian_carp",
	"salmon",
]

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	# Seed 2 starts inside a broad temperate water body, so this contract verifies
	# both large-water density and actual camera visibility instead of merely
	# finding an off-screen group somewhere in the streaming square.
	world.seed = 2
	world._player_cell = Vector2i.ZERO
	root.add_child(world)
	await process_frame
	world.set_process(false)

	for species_id in FISH_SPECIES:
		_expect(world._animal_species.has(species_id), "缺少鱼类物种: " + species_id)
		if not world._animal_species.has(species_id):
			continue
		var species: Dictionary = world._animal_species[species_id]
		_expect(
			world._animal_species_allows_surface(species, &"water"),
			"鱼类没有允许水面: " + species_id
		)
		_expect(
			not world._animal_species_allows_surface(species, &"land"),
			"鱼类错误允许陆地: " + species_id
		)
		_expect(
			bool((species.get("metadata", {}) as Dictionary).get("silent", false)),
			"无声鱼类没有声明 silent: " + species_id
		)
		var movement: Dictionary = species.get("movement", {})
		var actions: Dictionary = species.get("actions", {})
		_expect(
			String(movement.get("idle_action", "")) == "swim"
			and String(movement.get("move_action", "")) == "swim",
			"鱼类停留或移动时没有统一使用 swim: " + species_id
		)
		_expect(
			bool(movement.get("source_faces_right", false)),
			"鱼素材默认朝右的配置缺失: " + species_id
		)
		var move_steps: Array = movement.get("move_steps", [])
		_expect(
			move_steps.size() == 2 and int(move_steps[0]) >= 7,
			"鱼的连续游动轨迹仍然过短: " + species_id
		)
		_expect(
			float(movement.get("direction_persistence", 0.0)) >= 6.0,
			"鱼没有足够的直线方向惯性: " + species_id
		)
		_expect(
			actions.size() == 1 and actions.has("swim"),
			"鱼类必须只有一个 swim 动作: " + species_id
		)
		if actions.has("swim"):
			_expect(
				bool((actions["swim"] as Dictionary).get("loop", false)),
				"鱼类 swim 动作没有循环: " + species_id
			)

	var natural_fish: Array = []
	var natural_groups := {}
	var visible_fish_count := 0
	var viewport_size: Vector2 = root.get_viewport().get_visible_rect().size
	for animal_value in world._animals.values():
		var animal = animal_value
		if String(animal.species_id) not in FISH_SPECIES:
			continue
		natural_fish.append(animal)
		var group_id := String(animal.social_group_id)
		if not natural_groups.has(group_id):
			natural_groups[group_id] = {}
		(natural_groups[group_id] as Dictionary)[String(animal.species_id)] = true
		_expect(
			world._quantize(animal.grid_cell.x, animal.grid_cell.y) <= world.WATER_MAX,
			"自然鱼群成员出生在陆地"
		)
		_expect(
			world._water_clearance(animal.grid_cell, 1) >= 1,
			"自然鱼群成员贴着岸线出生"
		)
		_expect(animal.material is ShaderMaterial, "自然鱼没有前景水层材质")
		_expect(animal.animation == &"swim", "自然鱼没有默认播放 swim")
		_expect(animal.is_playing(), "自然鱼的 swim 动画没有播放")
		_expect(
			animal.sprite_frames.get_animation_loop(&"swim"),
			"自然鱼的 swim 动画没有循环"
		)
		var fish_screen_position: Vector2 = world._cam.unproject_position(animal.global_position)
		if Rect2(Vector2.ZERO, viewport_size).grow(32.0).has_point(
			fish_screen_position
		):
			visible_fish_count += 1
	_expect(natural_fish.size() >= 2, "大面积温带水域完全没有生成鱼群")
	_expect(natural_groups.size() >= 1, "大面积水域没有生成稀疏鱼群领地")
	_expect(visible_fish_count >= 1, "鱼群虽已生成，但当前实际镜头仍看不到")
	for species_set_value in natural_groups.values():
		var species_set: Dictionary = species_set_value
		_expect(species_set.size() == 1, "同一鱼群混入了多个品种")

	var template: ShaderMaterial = world._underwater_animal_material_for_depth(3)
	var fish_a:AnimatedSprite3D=AnimalScript.new()
	var fish_b:AnimatedSprite3D=AnimalScript.new()
	root.add_child(fish_a)
	root.add_child(fish_b)
	var frames_a:=SpriteFrames.new()
	var frames_b:=SpriteFrames.new()
	var image_a:=Image.create(2,2,false,Image.FORMAT_RGBA8)
	image_a.fill(Color.RED)
	var image_b:=Image.create(2,2,false,Image.FORMAT_RGBA8)
	image_b.fill(Color.BLUE)
	var texture_a:=ImageTexture.create_from_image(image_a)
	var texture_b:=ImageTexture.create_from_image(image_b)
	for pair in [[frames_a,texture_a],[frames_b,texture_b]]:
		pair[0].add_animation("idle")
		pair[0].add_frame("idle",pair[1])
	fish_a.material=template
	fish_b.material=template
	fish_a.configure("a",Vector2i.ZERO,frames_a,Vector2.ZERO,0,0,&"wander",{},0,6)
	fish_b.configure("b",Vector2i.ONE,frames_b,Vector2.ONE,0,0,&"wander",{},0,6)
	_expect(fish_a.material!=fish_b.material,"fish materials must be independent")
	_expect(is_equal_approx(float(fish_a.material.get_shader_parameter("submerged_visibility")),0.7),"submerged visibility was not copied from the depth template")
	_expect(fish_a.material.get_shader_parameter("albedo_texture")==texture_a and fish_b.material.get_shader_parameter("albedo_texture")==texture_b,"fish frame textures leaked between instances")
	fish_a.queue_free()
	fish_b.queue_free()
	var shore_water := Vector2i(1000000, 1000000)
	var interior_water := Vector2i(1000000, 1000000)
	var nearby_land := Vector2i(1000000, 1000000)
	for cell_value in world._cell_states:
		var cell: Vector2i = cell_value
		var context = world._cell_states[cell].context
		if context.is_water and context.water_depth <= 2:
			if world._water_clearance(cell, 1) >= 1:
				interior_water = cell
			for direction in world.ANIMAL_DIRECTIONS:
				var neighbor: Vector2i = cell + direction
				if (
					world._cell_states.has(neighbor)
					and not world._cell_states[neighbor].context.is_water
				):
					shore_water = cell
					nearby_land = neighbor
					break
		if shore_water.x < 1000000 and interior_water.x < 1000000:
			break
	_expect(shore_water.x < 1000000, "测试视窗没有找到浅水岸线")
	_expect(interior_water.x < 1000000, "测试视窗没有找到离岸一格的浅水")
	if shore_water.x < 1000000:
		var shore_surface := _water_surface_block(world, shore_water)
		var expected_mask := _expected_shore_mask(world, shore_water)
		_expect(not shore_surface.is_empty(), "岸线水格缺少水面 render block")
		_expect(
			int(shore_surface.get("shore_edges", 0)) == expected_mask
			and expected_mask != 0,
			"岸线白浪边没有与四个陆地邻格一致"
		)
	if interior_water.x < 1000000:
		var interior_surface := _water_surface_block(world, interior_water)
		_expect(not interior_surface.is_empty(), "内部水格缺少水面 render block")
		_expect(
			int(interior_surface.get("shore_edges", -1)) == 0,
			"内部水格错误绘制了岸线白浪"
		)

	world._clear_animals()
	if shore_water.x < 1000000 and interior_water.x < 1000000:
		var fish = world._spawn_animal(
			"goldfish",
			interior_water,
			world._quantize(interior_water.x, interior_water.y)
		)
		_expect(fish != null, "金鱼无法出生在浅水格")
		if fish != null:
			_expect(fish.animation == &"swim", "金鱼出生后没有默认播放 swim")
			_expect(fish.is_playing(), "金鱼出生后 swim 动画没有播放")
			_expect(
				fish.sprite_frames.get_animation_loop(&"swim"),
				"金鱼 swim 动画没有循环"
			)
			fish.finish_move_bout()
			_expect(
				fish.animation == &"swim" and fish.is_playing(),
				"金鱼结束移动后切离了 swim"
			)
			_expect(
				fish.current_visual_position().is_equal_approx(
					world._cell_feet_pos(interior_water)
				),
				"鱼没有对齐统一水面高度"
			)
			_expect(fish.material is ShaderMaterial, "鱼没有被前景水层覆盖")
			if fish.material is ShaderMaterial:
				var water_material := fish.material as ShaderMaterial
				_expect(
					float(water_material.get_shader_parameter("body_coverage")) >= 0.58,
					"鱼的大部分身体没有被前景水层覆盖"
				)
			_expect(
				not world._can_animal_enter(fish, nearby_land),
				"鱼可以从水中游上陆地"
			)
			_expect(
				not world._can_animal_enter(fish, shore_water),
				"鱼可以游回紧贴岸边的水格"
			)
			world._animals.erase(interior_water)
			world.remove_child(fish)
			fish.free()
		var fish_on_shore = world._spawn_animal(
			"goldfish",
			shore_water,
			world._quantize(shore_water.x, shore_water.y)
		)
		_expect(fish_on_shore == null, "鱼可以直接出生在紧贴岸边的水格")
		var fish_on_land = world._spawn_animal(
			"blue_goldfish",
			nearby_land,
			world._quantize(nearby_land.x, nearby_land.y)
		)
		_expect(fish_on_land == null, "鱼可以直接出生在陆地")
		var dog_in_water = world._spawn_animal(
			"dog",
			interior_water,
			world._quantize(interior_water.x, interior_water.y)
		)
		_expect(dog_in_water == null, "陆生动物可以出生在水中")

	world.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("AQUATIC_FAUNA_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _water_surface_block(world, cell: Vector2i) -> Dictionary:
	if not world._cell_states.has(cell):
		return {}
	for block_value in world._cell_states[cell].render_blocks:
		var block: Dictionary = block_value
		if block.get("water_part", &"") == &"surface":
			return block
	return {}


func _expected_shore_mask(world, cell: Vector2i) -> int:
	var result := 0
	if world._quantize(cell.x - 1, cell.y) > world.WATER_MAX:
		result |= 1
	if world._quantize(cell.x, cell.y - 1) > world.WATER_MAX:
		result |= 2
	if world._quantize(cell.x + 1, cell.y) > world.WATER_MAX:
		result |= 4
	if world._quantize(cell.x, cell.y + 1) > world.WATER_MAX:
		result |= 8
	return result
