## editor/battlefield_doc.gd — 战场编辑器文档模型：种子地形生成 + JSON 序列化/解析/保存
##
## 编辑器模型（Dictionary）：
##   { id:String, name:String, description:String, hosting:bool,
##     width:int, height:int, rows:Array[String]（图例行，与 BattlefieldLoader.DEFAULT_LEGEND 一致）,
##     units:Array[{ class:String, name:String, level:int, x:int, y:int, faction:"player"|"enemy" }],
##     buildings:Array[{ instance_id:String, asset_id:String, x:int, y:int, rotation:int }]（建筑层，整栋条目） }
##
## 与 scripts/core/battlefield_loader.gd 的 JSON schema 互转；保存前用 loader 做权威校验。
## 全部纯静态，可 headless 契约测试（tests/map_editor_contract.gd）。

class_name BattlefieldDoc
extends RefCounted

const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const BlockLayoutScript = preload("res://scripts/core/block_layout.gd")
const BuildingLayoutScript = preload("res://scripts/core/building_layout.gd")

## 建筑类用户素材 kind（与素材契约一致；字符串字面量避免与素材目录常量的编译时序耦合）
const ASSET_KIND_BUILDING := "building"

const MIN_SIZE := 4
const MAX_SIZE := 40
const DEFAULT_WIDTH := 12
const DEFAULT_HEIGHT := 9
const BLOCK_MIN_Z := BlockLayoutScript.MIN_Z
const BLOCK_MAX_Z := BlockLayoutScript.MAX_Z

## 地形 -> 图例（DEFAULT_LEGEND 的逆映射，取每种地形的主图例字符）
const TERRAIN_GLYPH := {
	&"plain": ".",
	&"forest": "f",
	&"mountain": "m",
	&"water": "w",
	&"fort": "F",
	&"village": "v",
	&"wall": "#",
	&"sand": "s",
	&"snow": "S",
	&"grass": "g",
	&"rocky": "r",
}

## 地形中文名（编辑器侧栏 / 状态文案用）
const TERRAIN_CN := {
	&"plain": "平原",
	&"forest": "森林",
	&"mountain": "山地",
	&"water": "水域",
	&"fort": "要塞",
	&"village": "村庄",
	&"wall": "城墙",
	&"sand": "沙地",
	&"snow": "雪地",
	&"grass": "草地",
	&"rocky": "岩坡",
}

## 图例 -> 地形（懒缓存 DEFAULT_LEGEND 拷贝）
static var _glyph_to_terrain: Dictionary = {}

## 植物类地形（地面上的树/灌木）：调色板里与纯地形分开成组、各自单独成一个 tile，
## 不再把树插在方块柱上组合展示。数据模型不变（仍是 11 种地形图例）。
const PLANT_TERRAINS: Array[StringName] = [&"forest"]

## 植物素材目录（调色板「植物」组按此枚举全部贴图，每张贴图一个 tile）
const PLANT_DIRS := {
	"树木": "res://meowa_tiles/trees",
	"植物": "res://meowa_tiles/plants",
	"装饰": "res://meowa_tiles/decorations",
}


## 是否植物类地形（调色板分组用）
static func is_plant(t: StringName) -> bool:
	return PLANT_TERRAINS.has(t)


static func _static_init() -> void:
	_glyph_to_terrain = BattlefieldLoaderScript.DEFAULT_LEGEND.duplicate()


## 新建空模型（全平原）
static func create_empty(w: int = DEFAULT_WIDTH, h: int = DEFAULT_HEIGHT) -> Dictionary:
	w = clampi(w, MIN_SIZE, MAX_SIZE)
	h = clampi(h, MIN_SIZE, MAX_SIZE)
	var rows: Array[String] = []
	for y in range(h):
		rows.append(".".repeat(w))
	return {
		"id": "",
		"name": "",
		"description": "",
		"hosting": false,
		"width": w,
		"height": h,
		"rows": rows,
		"units": [],
		"props": [],  # 植物层 [{x,y,texture}]，与地形解耦（一格至多一株）
		"buildings": [],  # 建筑层 [{instance_id,asset_id,x,y,rotation}]（整栋条目，占用由 footprint 派生）
		"block_layout": BlockLayoutScript.create(w, h),
		"tile_overrides": {},  # 地块视觉覆盖层 {"x,y": {asset_id}}——逻辑地形不变
		"user_assets": {},     # 引用的用户素材描述符快照 {asset_id: descriptor}（保存时从素材库拷贝）
	}


static func cell_z(model: Dictionary, cell: Vector2i) -> int:
	return BlockLayoutScript.z_at(model.get("block_layout", {}), cell)


static func set_cell_z(model: Dictionary, cell: Vector2i, z: int) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(model.width) or cell.y >= int(model.height):
		return false
	if not model.has("block_layout"):
		model["block_layout"] = BlockLayoutScript.create(int(model.width), int(model.height))
	return BlockLayoutScript.set_z(model["block_layout"], cell, z)


## 调整尺寸：保留左上交集，扩出区域补平原/默认高度，越界实体与高度条目剔除
static func resize(model: Dictionary, w: int, h: int) -> Dictionary:
	w = clampi(w, MIN_SIZE, MAX_SIZE)
	h = clampi(h, MIN_SIZE, MAX_SIZE)
	var rows: Array[String] = []
	for y in range(h):
		if y < model.height:
			var src: String = model.rows[y]
			if src.length() >= w:
				rows.append(src.substr(0, w))
			else:
				rows.append(src + ".".repeat(w - src.length()))
		else:
			rows.append(".".repeat(w))
	var units: Array = (model.units as Array).filter(func(u): return u.x < w and u.y < h)
	var props: Array = (model.get("props", []) as Array).filter(
		func(p): return int(p.x) < w and int(p.y) < h)
	# 地块覆盖层：越界键剔除
	var overrides: Dictionary = {}
	for key in (model.get("tile_overrides", {}) as Dictionary).keys():
		var parts := String(key).split(",")
		if parts.size() == 2 and int(parts[0]) < w and int(parts[1]) < h:
			overrides[key] = (model["tile_overrides"] as Dictionary)[key]
	var out: Dictionary = model.duplicate(true)
	out.width = w
	out.height = h
	out.rows = rows
	out.units = units
	out.props = props
	out["tile_overrides"] = overrides
	var old_layout: Dictionary = model.get("block_layout", {})
	var default_z := int(old_layout.get("default_z", BlockLayoutScript.DEFAULT_Z))
	out["block_layout"] = BlockLayoutScript.create(w, h, clampi(default_z, BLOCK_MIN_Z, BLOCK_MAX_Z))
	if not old_layout.is_empty():
		for y in range(mini(int(model.height), h)):
			for x in range(mini(int(model.width), w)):
				set_cell_z(out, Vector2i(x, y), cell_z(model, Vector2i(x, y)))
	# 建筑整栋保留/剔除：占用格全部落在新界内才保留（不静默切碎）
	prune_buildings_outside(out, w, h)
	return out


## 种子地形生成：同 seed + 同尺寸 → 完全相同的地图（确定性）。
## 布局策略：平原基底 + 2~3 片水域 blob + 2~3 条山脊 + 若干森林簇 + 零星村庄/要塞。
static func generate(seed: String, w: int = DEFAULT_WIDTH, h: int = DEFAULT_HEIGHT) -> Dictionary:
	w = clampi(w, MIN_SIZE, MAX_SIZE)
	h = clampi(h, MIN_SIZE, MAX_SIZE)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed) if not seed.is_empty() else 0
	var grid: Array = []
	for y in range(h):
		var row: Array = []
		row.resize(w)
		row.fill(&"plain")
		grid.append(row)

	# 水域 blob：中心 + 随机游走扩张
	var water_blobs := rng.randi_range(2, 3)
	for _i in range(water_blobs):
		var cx := rng.randi_range(1, w - 2)
		var cy := rng.randi_range(1, h - 2)
		for _j in range(rng.randi_range(4, 8)):
			if _inb(cx, cy, w, h):
				grid[cy][cx] = &"water"
			cx = clampi(cx + rng.randi_range(-1, 1), 0, w - 1)
			cy = clampi(cy + rng.randi_range(-1, 1), 0, h - 1)
		if _inb(cx, cy, w, h):
			grid[cy][cx] = &"water"

	# 山脊：随机方向短线段
	var ridges := rng.randi_range(2, 3)
	for _i in range(ridges):
		var x := rng.randi_range(0, w - 1)
		var y := rng.randi_range(0, h - 1)
		var len := rng.randi_range(3, 6)
		var dx := rng.randi_range(-1, 1)
		var dy := 0 if dx != 0 else (1 if rng.randf() > 0.5 else -1)
		for _j in range(len):
			if _inb(x, y, w, h):
				grid[y][x] = &"mountain"
			x += dx
			y += dy
			if dx == 0 and dy == 0:
				break

	# 森林簇
	var forests := rng.randi_range(3, 5)
	for _i in range(forests):
		var fx := rng.randi_range(0, w - 1)
		var fy := rng.randi_range(0, h - 1)
		for _j in range(rng.randi_range(2, 5)):
			if _inb(fx, fy, w, h) and grid[fy][fx] == &"plain":
				grid[fy][fx] = &"forest"
			fx = clampi(fx + rng.randi_range(-1, 1), 0, w - 1)
			fy = clampi(fy + rng.randi_range(-1, 1), 0, h - 1)

	# 零星村庄 / 要塞（只落在平原上）
	for _i in range(rng.randi_range(1, 2)):
		var vx := rng.randi_range(0, w - 1)
		var vy := rng.randi_range(0, h - 1)
		if grid[vy][vx] == &"plain":
			grid[vy][vx] = &"village"
	for _i in range(rng.randi_range(0, 2)):
		var fx2 := rng.randi_range(0, w - 1)
		var fy2 := rng.randi_range(0, h - 1)
		if grid[fy2][fx2] == &"plain":
			grid[fy2][fx2] = &"fort"

	var rows: Array[String] = []
	for y in range(h):
		var s := ""
		for x in range(w):
			s += TERRAIN_GLYPH.get(grid[y][x], ".")
		rows.append(s)
	var out := create_empty(w, h)
	out.rows = rows
	return out


static func _inb(x: int, y: int, w: int, h: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


## 图例字符 -> 地形（不在图例中返回 &"plain"）
static func glyph_to_terrain(g: String) -> StringName:
	return _glyph_to_terrain.get(g, &"plain")


## ---- 植物层（props）----------------------------------------------------

## 取某格的植物贴图路径（无则 ""）
static func prop_at(model: Dictionary, cell: Vector2i) -> String:
	for p in model.get("props", []):
		if int(p.x) == cell.x and int(p.y) == cell.y:
			return String(p.get("texture", ""))  # asset 通道条目无 texture 键
	return ""


## 在某格放置/替换植物（texture=res:// 贴图路径）；返回是否改动了模型
static func set_prop(model: Dictionary, cell: Vector2i, texture: String) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(model.width) or cell.y >= int(model.height):
		return false
	remove_prop(model, cell)
	(model.props as Array).append({ "x": cell.x, "y": cell.y, "texture": texture })
	return true


## 移除某格植物；返回是否删到
static func remove_prop(model: Dictionary, cell: Vector2i) -> bool:
	var props: Array = model.get("props", [])
	for i in range(props.size()):
		var p: Dictionary = props[i]
		if int(p.x) == cell.x and int(p.y) == cell.y:
			props.remove_at(i)
			return true
	return false


## 取某格植物的用户素材 ID（无则 ""；与 texture 通道互斥：一格至多一株）
static func prop_asset_at(model: Dictionary, cell: Vector2i) -> String:
	for p in model.get("props", []):
		if int(p.x) == cell.x and int(p.y) == cell.y:
			return String(p.get("asset_id", ""))
	return ""


## 在某格放置/替换用户素材植物（asset_id 引用素材库；同格旧 texture 条目一并替换）。
## asset_id 为空时等价 remove_prop。返回是否改动了模型。
static func set_prop_asset(model: Dictionary, cell: Vector2i, asset_id: String) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(model.width) or cell.y >= int(model.height):
		return false
	if asset_id.is_empty():
		return remove_prop(model, cell)
	remove_prop(model, cell)
	(model.get("props", []) as Array).append({ "x": cell.x, "y": cell.y, "asset_id": asset_id })
	return true


## ---- 地块视觉覆盖层（tile_overrides）------------------------------------
## 逻辑地形（rows/高度/拾取）不变，仅替换该格的地块视觉为用户素材整图。

static func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


## 取某格的地块覆盖素材 ID（无则 ""）
static func tile_override_at(model: Dictionary, cell: Vector2i) -> String:
	var entry: Dictionary = model.get("tile_overrides", {}).get(_cell_key(cell), {})
	return String(entry.get("asset_id", ""))


## 设置/清除（asset_id 空）某格的地块视觉覆盖；返回是否改动了模型
static func set_tile_override(model: Dictionary, cell: Vector2i, asset_id: String) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(model.width) or cell.y >= int(model.height):
		return false
	if not model.has("tile_overrides"):
		model["tile_overrides"] = {}
	var overrides: Dictionary = model["tile_overrides"]
	var key := _cell_key(cell)
	if asset_id.is_empty():
		if overrides.has(key):
			overrides.erase(key)
			return true
		return false
	overrides[key] = { "asset_id": asset_id }
	return true


## ---- 建筑层（buildings）--------------------------------------------------
## 建筑是跨格整体条目 [{instance_id,asset_id,x,y,rotation}]：占用格由素材
## descriptor.render.footprint 派生（BuildingLayout），底面必须等高、不与
## 单位/其他建筑重叠。编辑永远整栋进行（放置/删除/旋转/区域操作不切碎）。

## 建筑条目列表（模型缺 buildings 键时返回空数组，不写回模型）
static func building_entries(model: Dictionary) -> Array:
	return model.get("buildings", []) as Array


## 占用映射 {"x,y" -> instance_id}（占用格由素材快照 footprint 派生）
static func building_occupancy(model: Dictionary) -> Dictionary:
	return BuildingLayoutScript.occupancy(building_entries(model), model.get("user_assets", {}) as Dictionary)


## 命中格所在建筑条目（无则 {}）
static func building_at(model: Dictionary, cell: Vector2i) -> Dictionary:
	for e in building_entries(model):
		for c in BuildingLayoutScript.occupied_cells(e, model.get("user_assets", {}) as Dictionary):
			if c == cell:
				return e
	return {}


## 合并素材快照：模型已有快照 + 待放置素材（预览/首放时 user_assets 可能还没有该素材）
static func _merged_assets(model: Dictionary, assets_snapshot: Dictionary) -> Dictionary:
	var merged: Dictionary = (model.get("user_assets", {}) as Dictionary).duplicate(true)
	for aid in assets_snapshot.keys():
		merged[String(aid)] = (assets_snapshot[aid] as Dictionary).duplicate(true)
	return merged


## 单位占用映射 {"x,y" -> true}（建筑不得压单位）
static func _unit_occupancy(model: Dictionary) -> Dictionary:
	var occupied: Dictionary = {}
	for u in model.get("units", []) as Array:
		occupied[BuildingLayoutScript.cell_key(int(u.x), int(u.y))] = true
	return occupied


## 校验放置：返回错误文案（"" = 可放）。
## assets_snapshot 非空时参与占用派生（含待放素材，含 render.back_asset_id 依赖）。
static func can_place_building(
	model: Dictionary, asset_id: String, origin: Vector2i, rotation: int, assets_snapshot: Dictionary = {}
) -> String:
	if asset_id.is_empty():
		return "缺少建筑素材"
	if rotation < 0 or rotation > 3:
		return "建筑 rotation 越界: %d（0..3）" % rotation
	var entry := {
		"instance_id": "?", "asset_id": asset_id,
		"x": origin.x, "y": origin.y, "rotation": rotation,
	}
	var assets := _merged_assets(model, assets_snapshot)
	var cells := BuildingLayoutScript.occupied_cells(entry, assets)
	var w := int(model.width)
	var h := int(model.height)
	# 界内
	for cell in cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= w or cell.y >= h:
			return "建筑占用 (%d,%d) 越界（地图 %d×%d）" % [cell.x, cell.y, w, h]
	# 底面等高（不支持登楼，建筑整体坐在同一高度平面）
	var z_base := cell_z(model, cells[0])
	for cell in cells:
		if cell_z(model, cell) != z_base:
			return "建筑底面不等高（%d,%d z=%d ≠ %d,%d z=%d）" % [
				cells[0].x, cells[0].y, z_base, cell.x, cell.y, cell_z(model, cell)]
	# 建筑间不重叠（与新楼同一份 merged 解释：库 footprint 变更后不出现新旧混用）
	var occupied_buildings := BuildingLayoutScript.occupancy(
		building_entries(model), assets)
	for cell in cells:
		var k := BuildingLayoutScript.cell_key(cell.x, cell.y)
		if occupied_buildings.has(k):
			return "建筑占用 (%d,%d) 与 %s 重叠" % [cell.x, cell.y, String(occupied_buildings[k])]
	# 不压单位
	var units := _unit_occupancy(model)
	for cell in cells:
		if units.has(BuildingLayoutScript.cell_key(cell.x, cell.y)):
			return "建筑占用 (%d,%d) 与单位冲突" % [cell.x, cell.y]
	return ""


## 生成下一个不冲突的 instance_id（b001 递增，跳过已用）
static func _next_building_id(model: Dictionary) -> String:
	var used: Dictionary = {}
	for e in building_entries(model):
		used[String(e.get("instance_id", ""))] = true
	var n := 1
	while used.has("b%03d" % n):
		n += 1
	return "b%03d" % n


## 放置建筑：校验通过后追加条目，并把 assets_snapshot（主素材+背面依赖）
## 深拷入 user_assets。返回 {ok:true, entry} 或 {ok:false, error}。
static func add_building(
	model: Dictionary, asset_id: String, origin: Vector2i, rotation: int, assets_snapshot: Dictionary
) -> Dictionary:
	var err := can_place_building(model, asset_id, origin, rotation, assets_snapshot)
	if not err.is_empty():
		return { "ok": false, "error": err }
	var entry := {
		"instance_id": _next_building_id(model),
		"asset_id": asset_id,
		"x": origin.x, "y": origin.y,
		"rotation": rotation,
	}
	# 快照提交前模拟：既有楼按新 footprint 重解释后仍需全体合法（界内/等高/重叠/压单位），
	# 失败则拒绝放置且不改动模型（防止"放置成功、保存才拒"的编辑态漂移）。
	if not assets_snapshot.is_empty():
		var merged := _merged_assets(model, assets_snapshot)
		var sim: Dictionary = model.duplicate(true)
		if not sim.has("buildings"):
			sim["buildings"] = []
		(sim["buildings"] as Array).append(entry.duplicate())
		sim["user_assets"] = merged.duplicate(true)
		var sim_err := validate_buildings(sim)
		if not sim_err.is_empty():
			return { "ok": false, "error": "素材占地已变化，落快照会使既有建筑非法：%s" % sim_err }
		model["user_assets"] = merged
	if not model.has("buildings"):
		model["buildings"] = []
	(model["buildings"] as Array).append(entry)
	return { "ok": true, "entry": entry.duplicate() }


## 按 instance_id 删除整栋建筑；返回是否删到
static func remove_building(model: Dictionary, instance_id: String) -> bool:
	var entries := building_entries(model)
	for i in range(entries.size()):
		if String((entries[i] as Dictionary).get("instance_id", "")) == instance_id:
			entries.remove_at(i)
			return true
	return false


## 删除命中格所在建筑（整栋）；返回是否删到
static func remove_building_at(model: Dictionary, cell: Vector2i) -> bool:
	var entry := building_at(model, cell)
	if entry.is_empty():
		return false
	return remove_building(model, String(entry["instance_id"]))


## 旋转命中格所在建筑 90°（rotation+1 回环），目标位置非法时拒绝；
## 返回错误文案（"" = 成功）。旋转可能改变占用格，全部规则重校验。
static func rotate_building(model: Dictionary, cell: Vector2i) -> String:
	var entry := building_at(model, cell)
	if entry.is_empty():
		return "(%d,%d) 没有建筑" % [cell.x, cell.y]
	var instance_id := String(entry["instance_id"])
	var new_entry := (entry as Dictionary).duplicate(true)
	new_entry["rotation"] = (int(entry.get("rotation", 0)) + 1) % 4
	# 先摘除自己再校验（避免自重叠误报）
	remove_building(model, instance_id)
	var err := can_place_building(
		model, String(new_entry["asset_id"]),
		Vector2i(int(new_entry["x"]), int(new_entry["y"])), int(new_entry["rotation"]))
	if not err.is_empty():
		(model["buildings"] as Array).append(entry)  # 恢复原朝向
		return "旋转失败：%s" % err
	(model["buildings"] as Array).append(new_entry)
	return ""


## 完全落在闭区间矩形 [min_cell, max_cell]（含边界）内的建筑条目列表。
## 区域复制/剪切/移动只作用于整栋：跨界（部分占用在矩形外）的建筑不算在内。
static func buildings_fully_within(model: Dictionary, min_cell: Vector2i, max_cell: Vector2i) -> Array:
	var result: Array = []
	for e in building_entries(model):
		var inside := true
		for c in BuildingLayoutScript.occupied_cells(e, model.get("user_assets", {}) as Dictionary):
			if c.x < min_cell.x or c.y < min_cell.y or c.x > max_cell.x or c.y > max_cell.y:
				inside = false
				break
		if inside:
			result.append((e as Dictionary).duplicate(true))
	return result


## 建筑整栋剔除：占用格全部落在 w×h 界内才保留（resize 用）。
## 返回删除的栋数；不静默切碎——任何一格出界整栋删。
static func prune_buildings_outside(model: Dictionary, w: int, h: int) -> int:
	var kept: Array = []
	var removed := 0
	for e in building_entries(model):
		var inside := true
		for c in BuildingLayoutScript.occupied_cells(e, model.get("user_assets", {}) as Dictionary):
			if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
				inside = false
				break
		if inside:
			kept.append(e)
		else:
			removed += 1
	if model.has("buildings") or removed > 0:
		model["buildings"] = kept
	return removed


## 建筑层校验（保存前本地反馈；权威校验是 loader 回读）。
## BuildingLayout.validate_entries：id 唯一/界内/不重叠/不压单位；
## 追加底面等高：占用格 block_layout z 必须全等（放置时已保证，
## 旧档手工改高/库 footprint 变更后可能破坏）。
static func validate_buildings(model: Dictionary) -> String:
	var entries := building_entries(model)
	var base_err := BuildingLayoutScript.validate_entries(
		entries, int(model.width), int(model.height),
		model.get("user_assets", {}) as Dictionary, _unit_occupancy(model))
	if not base_err.is_empty():
		return base_err
	for e in entries:
		var z_ref := -1
		for c: Vector2i in BuildingLayoutScript.occupied_cells(e, model.get("user_assets", {}) as Dictionary):
			var z := cell_z(model, c)
			if z_ref < 0:
				z_ref = z
			elif z != z_ref:
				return "建筑 %s 底面不等高（z=%d 与 z=%d）" % [String(e.get("instance_id", "?")), z_ref, z]
	return ""


## 模型 -> 战场 JSON dict（loader schema：rows + 显式 legend + 双阵营单位）
static func to_json_dict(model: Dictionary) -> Dictionary:
	var players: Array = []
	var enemies: Array = []
	for u in model.units:
		var d := {
			"class": String(u.get("class", "swordsman")),
			"level": int(u.get("level", 1)),
			"x": int(u.get("x", 0)),
			"y": int(u.get("y", 0)),
		}
		var uname := String(u.get("name", ""))
		if not uname.is_empty():
			d["name"] = uname
		if String(u.get("faction", "player")) == "enemy":
			enemies.append(d)
		else:
			players.append(d)
	var legend: Dictionary = {}
	for g in BattlefieldLoaderScript.DEFAULT_LEGEND:
		legend[g] = String(BattlefieldLoaderScript.DEFAULT_LEGEND[g])
	# loader schema：rows / legend / playerUnits / enemyUnits 均为顶层字段
	var out := {
		"id": String(model.get("id", "")),
		"name": String(model.get("name", "")),
		"description": String(model.get("description", "")),
		"hosting": bool(model.get("hosting", false)),
		"rows": (model.rows as Array).duplicate(),
		"legend": legend,
		"playerUnits": players,
		"enemyUnits": enemies,
	}
	# 植物层（可选字段：空则不写，保持旧 JSON 兼容；asset_id 条目与 texture 条目并存）
	var props: Array = model.get("props", [])
	if not props.is_empty():
		var jprops: Array = []
		for p in props:
			var entry := { "x": int(p.x), "y": int(p.y) }
			var aid := String(p.get("asset_id", ""))
			if not aid.is_empty():
				entry["asset_id"] = aid
			else:
				entry["texture"] = String(p.get("texture", ""))
			jprops.append(entry)
		out["props"] = jprops
	# 地块视觉覆盖层（可选字段：空则不写）
	var overrides: Dictionary = model.get("tile_overrides", {})
	if not overrides.is_empty():
		var joverrides: Dictionary = {}
		for key in overrides.keys():
			var e: Dictionary = overrides[key]
			var aid := String(e.get("asset_id", ""))
			if not aid.is_empty():
				joverrides[key] = { "asset_id": aid }
		out["tile_overrides"] = joverrides
	# 建筑层（可选字段：空则不写，保持旧 JSON 兼容）
	var buildings: Array = model.get("buildings", [])
	if not buildings.is_empty():
		var jbuildings: Array = []
		for b in buildings:
			jbuildings.append({
				"instance_id": String(b.get("instance_id", "")),
				"asset_id": String(b.get("asset_id", "")),
				"x": int(b.get("x", 0)),
				"y": int(b.get("y", 0)),
				"rotation": int(b.get("rotation", 0)),
			})
		out["buildings"] = jbuildings
	# 引用素材描述符快照（可选字段：空则不写；运行时纹理不序列化，只存纯 JSON 描述）
	var user_assets: Dictionary = model.get("user_assets", {})
	if not user_assets.is_empty():
		out["user_assets"] = user_assets.duplicate(true)
	if model.has("block_layout"):
		out["block_layout"] = (model["block_layout"] as Dictionary).duplicate(true)
	return out


## 战场 JSON dict -> 编辑器模型（顶层 "rows" 字符画与 "map" 全名矩阵两种写法都支持）
static func from_json_dict(d: Dictionary) -> Dictionary:
	var rows: Array[String] = []
	if d.has("rows"):
		for r in d["rows"]:
			rows.append(String(r))
	elif d.has("map"):
		for r in d["map"]:
			var row := ""
			if r is Array:
				for t in r:
					row += TERRAIN_GLYPH.get(StringName(String(t)), ".")
			else:
				for t in String(r).split(" ", false):
					row += TERRAIN_GLYPH.get(StringName(t), ".")
			rows.append(row)
	var w: int = (rows.map(func(r): return r.length()).max() if not rows.is_empty() else 0) as int
	var h := rows.size()
	# 补齐锯齿行（ Defensive：loader 会拒收 ragged，这里先补齐便于编辑）
	for i in range(rows.size()):
		if rows[i].length() < w:
			rows[i] = rows[i] + ".".repeat(w - rows[i].length())

	var units: Array = []
	for key in ["playerUnits", "enemyUnits"]:
		var faction := "player" if key == "playerUnits" else "enemy"
		for u in d.get(key, []):
			units.append({
				"class": String(u.get("class", "swordsman")),
				"name": String(u.get("name", "")),
				"level": int(u.get("level", 1)),
				"x": int(u.get("x", 0)),
				"y": int(u.get("y", 0)),
				"faction": faction,
			})
	# 植物层（可选；宽松解析：非法条目跳过；texture 与 asset_id 至少其一）
	var props: Array = []
	for p in d.get("props", []):
		if not (p is Dictionary):
			continue
		var tex := String(p.get("texture", ""))
		var aid := String(p.get("asset_id", ""))
		if tex.is_empty() and aid.is_empty():
			continue
		var entry := { "x": int(p.get("x", 0)), "y": int(p.get("y", 0)) }
		if not aid.is_empty():
			entry["asset_id"] = aid
		else:
			entry["texture"] = tex
		props.append(entry)
	# 地块视觉覆盖层（可选；宽松解析：坐标非法/asset_id 空的条目跳过）
	var overrides: Dictionary = {}
	for key in (d.get("tile_overrides", {}) as Dictionary).keys():
		var e: Dictionary = d["tile_overrides"][key] if d["tile_overrides"][key] is Dictionary else {}
		var aid := String(e.get("asset_id", ""))
		if aid.is_empty():
			continue
		var parts := String(key).split(",")
		if parts.size() != 2:
			continue
		if int(parts[0]) < 0 or int(parts[1]) < 0:
			continue
		overrides[key] = { "asset_id": aid }
	# 建筑层（可选；宽松解析：非 Dict/缺 id/缺 asset 跳过，rotation 折叠到 0..3
	# （posmod 4：wrapi(x,0,3) 是半开区间会把合法 3 折成 0）；
	# 越界条目保留，由 validate_buildings/loader 报错，不静默丢弃）
	var buildings: Array = []
	for b in d.get("buildings", []):
		if not (b is Dictionary):
			continue
		var bid := String(b.get("instance_id", ""))
		var baid := String(b.get("asset_id", ""))
		if bid.is_empty() or baid.is_empty():
			continue
		buildings.append({
			"instance_id": bid,
			"asset_id": baid,
			"x": int(b.get("x", 0)),
			"y": int(b.get("y", 0)),
			"rotation": posmod(int(b.get("rotation", 0)), 4),
		})
	# 引用素材描述符快照（可选；形状宽松：只要键是 asset_id 的 Dictionary 就收）
	var user_assets: Dictionary = {}
	var raw_assets: Variant = d.get("user_assets", {})
	if raw_assets is Dictionary:
		for aid in (raw_assets as Dictionary).keys():
			var desc: Variant = (raw_assets as Dictionary)[aid]
			if desc is Dictionary and not String(aid).is_empty():
				user_assets[String(aid)] = (desc as Dictionary).duplicate(true)
	var out := {
		"id": String(d.get("id", "")),
		"name": String(d.get("name", "")),
		"description": String(d.get("description", "")),
		"hosting": bool(d.get("hosting", false)),
		"width": w,
		"height": h,
		"rows": rows,
		"units": units,
		"props": props,
		"buildings": buildings,
		"tile_overrides": overrides,
		"user_assets": user_assets,
	}
	# 旧 JSON 进入编辑器后统一成为 z=0 的显式单块平面；仅磁盘中途加载器保留旧柱路径。
	if d.has("block_layout"):
		out["block_layout"] = (d["block_layout"] as Dictionary).duplicate(true) if d["block_layout"] is Dictionary else d["block_layout"]
	else:
		out["block_layout"] = BlockLayoutScript.create(w, h)
	return out


## 本地快速校验（保存前的即时反馈；权威校验是保存后的 loader 回读）
## 返回 "" 表示通过，否则为中文错误描述
static func validate_block_layout(model: Dictionary) -> String:
	if not model.has("block_layout"):
		return ""
	return BlockLayoutScript.validate(model["block_layout"], int(model.width), int(model.height))


static func quick_validate(model: Dictionary) -> String:
	var w: int = model.width
	var h: int = model.height
	var rows: Array = model.rows
	if rows.size() != h:
		return "行数 %d 与高度 %d 不符" % [rows.size(), h]
	for r in rows:
		if String(r).length() != w:
			return "存在锯齿行（长度 != %d）" % w
		for g in String(r):
			if not _glyph_to_terrain.has(g):
				return "未知图例字符 '%s'" % g
	var seen := {}
	var players := 0
	var enemies := 0
	for u in model.units:
		var key := Vector2i(int(u.x), int(u.y))
		if seen.has(key):
			return "单位重叠于 (%d,%d)" % [key.x, key.y]
		seen[key] = true
		if u.faction == "enemy":
			enemies += 1
		else:
			players += 1
	if players < 1 or enemies < 1:
		return "双方各需至少 1 个单位（当前 我方%d/敌方%d）" % [players, enemies]
	if model.has("block_layout"):
		var layout_error := validate_block_layout(model)
		if not layout_error.is_empty():
			return layout_error
	var buildings_error := validate_buildings(model)
	if not buildings_error.is_empty():
		return buildings_error
	return ""


## id 规范化：小写字母/数字/下划线，非法字符替换为 _，为空时给默认名
static func sanitize_id(id: String) -> String:
	var out := ""
	for c in id.to_lower():
		out += c if (c.is_valid_identifier() or c == "_" or c.is_valid_int()) else "_"
	return out if not out.is_empty() else "custom_map"


## 保存：优先 res://data/battlefields/<id>.json（开发运行），失败落 user://battlefields/。
## 原子写流程（不毁旧图）：
##   1. quick_validate + load_battlefield_inline 权威预校验（不动磁盘）
##   2. 写 <path>.tmp → 回读 tmp 校验
##   3. 旧文件 rename 为 <path>.bak（先删旧 bak）→ rename tmp → 正式路径
##   4. 任一步失败：删 tmp / 回滚 bak，原文件保持原样
static func save_model(model: Dictionary) -> Dictionary:
	var id := sanitize_id(String(model.get("id", "")))
	var err := quick_validate(model)
	if not err.is_empty():
		return { "ok": false, "error": "校验失败：%s" % err }
	var doc := to_json_dict(model)
	doc["id"] = id
	# 权威预校验：走 loader 完整规则（单位职业/站住合法性等），磁盘零改动
	var pre := BattlefieldLoaderScript.load_battlefield_inline(doc, id)
	if not bool(pre.get("ok", false)):
		return { "ok": false, "error": "预校验失败：%s" % String(pre.get("error", "")) }
	var pretty := JSON.stringify(doc, "\t")

	var path := "res://data/battlefields/%s.json" % id
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		# res:// 不可写（导出版）→ 落 user://
		path = "user://battlefields/%s.json" % id
		DirAccess.make_dir_recursive_absolute("user://battlefields")
		f = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return { "ok": false, "error": "无法写入临时文件（res:// 与 user:// 均失败）" }
	var tmp := path + ".tmp"
	var bak := path + ".bak"
	f.store_string(pretty)
	f.close()

	# 回读 tmp 校验；失败删 tmp，原文件未动
	var back := BattlefieldLoaderScript.load_battlefield(tmp)
	if not bool(back.get("ok", false)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return { "ok": false, "error": String(back.get("error", "回读校验失败")) }

	# 旧文件 → .bak（Windows rename 需先清目标），tmp → 正式路径；失败回滚
	if FileAccess.file_exists(path):
		var gpath := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(bak))
		var ren_old := DirAccess.rename_absolute(gpath, ProjectSettings.globalize_path(bak))
		if ren_old != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
			return { "ok": false, "error": "备份旧文件失败（原文件未动）" }
		var ren_new := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), gpath)
		if ren_new != OK:
			# 回滚：bak 恢复为正式文件
			DirAccess.rename_absolute(ProjectSettings.globalize_path(bak), gpath)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
			return { "ok": false, "error": "落盘失败（已回滚为原文件）" }
	else:
		var ren := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
		if ren != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
			return { "ok": false, "error": "落盘失败: %s" % path }
	return { "ok": true, "path": path }
