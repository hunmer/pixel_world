## editor/battlefield_doc.gd — 战场编辑器文档模型：种子地形生成 + JSON 序列化/解析/保存
##
## 编辑器模型（Dictionary）：
##   { id:String, name:String, description:String, hosting:bool,
##     width:int, height:int, rows:Array[String]（图例行，与 BattlefieldLoader.DEFAULT_LEGEND 一致）,
##     units:Array[{ class:String, name:String, level:int, x:int, y:int, faction:"player"|"enemy" }] }
##
## 与 scripts/core/battlefield_loader.gd 的 JSON schema 互转；保存前用 loader 做权威校验。
## 全部纯静态，可 headless 契约测试（tests/map_editor_contract.gd）。

class_name BattlefieldDoc
extends RefCounted

const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const BlockLayoutScript = preload("res://scripts/core/block_layout.gd")

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
		"block_layout": BlockLayoutScript.create(w, h),
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
	var out: Dictionary = model.duplicate(true)
	out.width = w
	out.height = h
	out.rows = rows
	out.units = units
	out.props = props
	var old_layout: Dictionary = model.get("block_layout", {})
	var default_z := int(old_layout.get("default_z", BlockLayoutScript.DEFAULT_Z))
	out["block_layout"] = BlockLayoutScript.create(w, h, clampi(default_z, BLOCK_MIN_Z, BLOCK_MAX_Z))
	if not old_layout.is_empty():
		for y in range(mini(int(model.height), h)):
			for x in range(mini(int(model.width), w)):
				set_cell_z(out, Vector2i(x, y), cell_z(model, Vector2i(x, y)))
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
			return String(p.texture)
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
	# 植物层（可选字段：空则不写，保持旧 JSON 兼容）
	var props: Array = model.get("props", [])
	if not props.is_empty():
		var jprops: Array = []
		for p in props:
			jprops.append({
				"x": int(p.x), "y": int(p.y), "texture": String(p.texture),
			})
		out["props"] = jprops
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
	# 植物层（可选；宽松解析：非法条目跳过）
	var props: Array = []
	for p in d.get("props", []):
		if not (p is Dictionary):
			continue
		var tex := String(p.get("texture", ""))
		if tex.is_empty():
			continue
		props.append({
			"x": int(p.get("x", 0)),
			"y": int(p.get("y", 0)),
			"texture": tex,
		})
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
	return ""


## id 规范化：小写字母/数字/下划线，非法字符替换为 _，为空时给默认名
static func sanitize_id(id: String) -> String:
	var out := ""
	for c in id.to_lower():
		out += c if (c.is_valid_identifier() or c == "_" or c.is_valid_int()) else "_"
	return out if not out.is_empty() else "custom_map"


## 保存：优先 res://data/battlefields/<id>.json（开发运行），失败落 user://battlefields/。
## 写入后立刻用 BattlefieldLoader.load_battlefield 回读校验；校验失败删除文件并返回错误。
static func save_model(model: Dictionary) -> Dictionary:
	var id := sanitize_id(String(model.get("id", "")))
	var err := quick_validate(model)
	if not err.is_empty():
		return { "ok": false, "error": "校验失败：%s" % err }
	var doc := to_json_dict(model)
	doc["id"] = id
	var pretty := JSON.stringify(doc, "\t")

	var path := "res://data/battlefields/%s.json" % id
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		path = "user://battlefields/%s.json" % id
		DirAccess.make_dir_recursive_absolute("user://battlefields")
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return { "ok": false, "error": "无法写入文件（res:// 与 user:// 均失败）" }
	f.store_string(pretty)
	f.close()

	# 权威校验：loader 回读（含单位站合法性 / 职业存在性等完整规则）
	var back := BattlefieldLoaderScript.load_battlefield(path)
	if not bool(back.get("ok", false)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return { "ok": false, "error": String(back.get("error", "回读校验失败")) }
	return { "ok": true, "path": path }
