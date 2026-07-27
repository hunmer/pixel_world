## core/world_to_chapter.gd — pixel_world 真实世界 cell → 战棋 chapter 适配层
##
## 职责：把玩家周围的真实地形（TerrainSampler 采样的 CellContext）翻译成战棋
## GridSystem 能消费的 StringName 二维矩阵，并随机布置玩家单位 + 敌兵。
##
## 设计：
##   - 纯静态函数，无副作用
##   - 战场坐标 (bx,by) ↔ 世界坐标 (origin.x + bx, origin.y + by)
##   - chapter 不含 blockTitles，强制 battle.gd 走 range_overlay.render_terrain_fallback
##   - cell_context_to_terrain 映射优先级：water > mountain > plain（forest/fort/village/wall
##     世界层无对应数据源，先退化到 plain/mountain，留给 B1 阶段扩展）
##   - 战场中心自动找陆地（玩家可能站在水面，搜索附近最近的非水 cell）
##   - 玩家/敌兵只放在 walkable 且 move_cost 可达的格子上（避免卡在水里）
##
## 公开 API：
##   cell_context_to_terrain(ctx) -> StringName
##   world_to_chapter(sampler, player_cell, radius, rng_seed) -> Dictionary

class_name WorldToChapter
extends RefCounted

## 水面高度阈值（与 main.gd 的 WATER_MAX 一致）
const _WATER_MAX := 5
## 山岩高度阈值（与 main.gd 的 _rock_level 默认值一致）
const _ROCK_LEVEL := 12


## 单个 CellContext → 战棋 terrain type。
## 优先级：water（含岸）→ mountain（高山/裸岩）→ plain（默认）。
static func cell_context_to_terrain(ctx) -> StringName:
	if ctx == null:
		return &"plain"
	# 1) 水：is_water 标志或高度低于水面
	if bool(ctx.is_water) or int(ctx.height) <= _WATER_MAX:
		return &"water"
	# 2) 山：landform_id 为 mountain，或高度超过 rock_level，或 surface 是裸岩
	var landform: StringName = ctx.landform_id
	var surface: StringName = ctx.surface_id
	if landform == &"mountain" \
			or int(ctx.height) >= _ROCK_LEVEL \
			or surface == &"rock" or surface == &"rock_with_moss" or surface == &"snow":
		return &"mountain"
	# 3) 兜底：平地（含草地/沙地/土壤/岸线）
	return &"plain"


## terrain type 是否可站立（foot 移动能进入）
static func _is_standable(t: StringName) -> bool:
	var tile := TerrainData.get_tile(t)
	if not bool(tile.get(&"walkable", false)):
		return false
	# water 虽然 walkable=true 但 foot move_cost=99（不可通行），过滤掉
	var cost: int = int(tile[&"move_cost"].get(&"foot", 99))
	return cost < 99


## 在世界 cell 周围 BFS 搜索最近的陆地（非水）cell。
## 防止玩家站在海里时战场全被采成水。
static func _find_nearest_land(sampler, start: Vector2i, max_radius: int = 30) -> Vector2i:
	if sampler == null or not sampler.configured:
		return start
	# 先看起点本身
	var ctx = sampler.sample(start)
	if ctx != null and not bool(ctx.is_water) and int(ctx.height) > _WATER_MAX:
		return start
	# 螺旋向外搜索（曼哈顿距离递增）
	for r in range(1, max_radius + 1):
		for dx in range(-r, r + 1):
			var dy := r - absi(dx)
			for sign_y in [-1, 1] if dy > 0 else [0]:
				var cand := start + Vector2i(dx, sign_y * dy)
				var c = sampler.sample(cand)
				if c != null and not bool(c.is_water) and int(c.height) > _WATER_MAX \
						and int(c.height) < _ROCK_LEVEL:
					return cand
	return start  # 实在找不到就回退


## 采样玩家周围 (2*radius+1)² 格，生成战棋 chapter。
static func world_to_chapter(
		sampler,
		player_cell: Vector2i,
		radius: int = 10,
		rng_seed: int = 0,
		enemy_count: int = 4
		) -> Dictionary:
	var size := radius * 2 + 1
	# 0) 先把战场中心对齐到玩家附近的陆地（玩家可能站在水面）
	var origin := _find_nearest_land(sampler, player_cell, 30)
	if origin != player_cell:
		print("[world_to_chapter] 玩家在水面，战场中心移至最近陆地 %s" % str(origin))
	# 1) 采样每格 terrain，生成 map 矩阵
	var terrain_map: Array = []
	terrain_map.resize(size)
	for by in range(size):
		var row: Array = []
		row.resize(size)
		for bx in range(size):
			var world_cell := Vector2i(origin.x - radius + bx, origin.y - radius + by)
			var ctx = null
			if sampler != null and sampler.configured:
				ctx = sampler.sample(world_cell)
			row[bx] = cell_context_to_terrain(ctx)
		terrain_map[by] = row
	# 2) 玩家单位：放在战场中心；若中心不可站立，搜索最近的 standable 格
	var center := Vector2i(radius, radius)
	center = _find_standable_near(terrain_map, center)
	var player_units: Array = [
		UnitFactory.create_random_unit(
			&"u_player", "玩家英雄", &"player", 3, center, {}),
	]
	# 3) 敌兵：随机放在远处（距中心 >= radius*0.5）的 standable 空地
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed if rng_seed != 0 else randi()
	var enemy_units: Array = []
	var occupied := { center: true }
	var attempts := 0
	var max_attempts := enemy_count * 50
	while enemy_units.size() < enemy_count and attempts < max_attempts:
		attempts += 1
		var ex := rng.randi_range(0, size - 1)
		var ey := rng.randi_range(0, size - 1)
		var epos := Vector2i(ex, ey)
		# 距离中心要够远（缩小到 radius*0.5，更易找到合法位）
		if epos.distance_to(center) < radius * 0.5:
			continue
		if occupied.has(epos):
			continue
		# 该格必须 standable
		if not _is_standable(terrain_map[ey][ex]):
			continue
		occupied[epos] = true
		var lvl := rng.randi_range(1, 3)
		var eid := StringName("u_enemy_%d" % enemy_units.size())
		enemy_units.append(UnitFactory.create_random_unit(
			eid, "敌兵%d" % (enemy_units.size() + 1), &"enemy", lvl, epos, {}))
	# 4) 组装 chapter（无 blockTitles → 强制 fallback）
	# world_origin：战场左上角 (0,0) 对应的世界 cell（B1 就地模式用于世界坐标转换）
	return {
		id = &"world_encounter",
		name = "野外遭遇战",
		map = terrain_map,
		width = size,
		height = size,
		world_origin = origin - Vector2i(radius, radius),
		playerUnits = player_units,
		enemyUnits = enemy_units,
	}


## 在 terrain_map 里找 start 附近最近的 standable 格（螺旋搜索）
static func _find_standable_near(terrain_map: Array, start: Vector2i) -> Vector2i:
	var size := terrain_map.size()
	if size == 0:
		return start
	if _is_standable(terrain_map[start.y][start.x]):
		return start
	for r in range(1, size):
		for dx in range(-r, r + 1):
			var dy := r - absi(dx)
			for sy in ([-1, 1] if dy > 0 else [0]):
				var c := start + Vector2i(dx, sy * dy)
				if c.x < 0 or c.y < 0 or c.x >= size or c.y >= size:
					continue
				if _is_standable(terrain_map[c.y][c.x]):
					return c
	return start
