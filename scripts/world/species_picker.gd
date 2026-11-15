## species_picker.gd — 物种池确定性选择：优势种 + 加权轮盘。
##
## 从 main.gd 簇7 的 _pick_species 迁出（结构性拆分，行为不变）。
## 确定性契约：selection_seed_key/pool_id 的 hash 作为 salt，salt+50/100/101
## 与逐项 salt+i 的取数顺序逐字保留。
class_name SpeciesPicker
extends RefCounted


## 每个群落按 selection_seed_key 确定优势种；配置里的物种顺序与重复项都代表权重。
static func pick_species(
	rule: Dictionary,
	gc: Vector2i,
	cell: Vector2i,
	cell_rand: Callable,
	dominant_species_chance: float,
	flora_layer_configs: Dictionary
) -> String:
	var pool: Array = rule.get("species", [])
	if pool.is_empty():
		return ""
	var seed_key := String(rule.get("selection_seed_key", rule.get("pool_id", "species")))
	var salt := seed_key.hash()
	var dominant: int = int(cell_rand.call(gc, salt + 50) * pool.size()) % pool.size()
	var layer_id := String(rule.get("layer", ""))
	if flora_layer_configs.has(layer_id):
		var layer: Dictionary = flora_layer_configs[layer_id]
		dominant_species_chance = float(
			layer.get("dominant_chance", dominant_species_chance)
		)
	if cell_rand.call(cell, salt + 100) < dominant_species_chance:
		return String(pool[dominant])
	var total := 0.0
	for i in pool.size():
		if i != dominant:
			total += cell_rand.call(gc, salt + i)
	var rr: float = cell_rand.call(cell, salt + 101) * total
	for i in pool.size():
		if i != dominant:
			rr -= cell_rand.call(gc, salt + i)
			if rr <= 0.0:
				return String(pool[i])
	return String(pool[dominant])
