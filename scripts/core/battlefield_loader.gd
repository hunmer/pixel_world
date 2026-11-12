## core/battlefield_loader.gd — JSON 战场声明 → 战棋 chapter 加载器（调试用）
##
## 职责：扫描 res://data/battlefields/*.json，把 JSON 声明的战场翻译成与
## world_to_chapter 输出同构的 chapter（id/name/map/width/height/playerUnits/enemyUnits），
## 供 battle.gd 直接消费。
##
## JSON 格式（两种地形写法二选一）：
##   {
##     "id": "plains_skirmish",            # 可选，缺省用文件名
##     "name": "平原前哨战",                 # 可选，缺省用文件名
##     "description": "……",                # 可选，UI 列表里展示
##     "hosting": false,                   # 可选，true=进战斗后玩家方托管自动打
##     "legend": { "f": "forest" },        # 可选，单字符 → 地形名，覆盖默认表
##     "rows": [                           # 写法一：字符画（每行等长，缺省图例见 DEFAULT_LEGEND）
##       "....f....",
##       "........"
##     ],
##     "map": [                            # 写法二：全名矩阵（或空格分隔的行字符串）
##       ["plain", "forest"],
##       ["water", "plain"]
##     ],
##     "playerUnits": [ { "class": "swordsman", "name": "罗兰", "level": 3, "x": 1, "y": 2 } ],
##     "enemyUnits":  [ { "class": "berserker", "level": 2, "x": 6, "y": 2 } ]
##   }
##
## 校验：地形名必须是 TerrainData 已注册类型；行宽一致；单位 class 必须存在；
## 坐标在界内；不与其他单位重叠；不站在不可通行地形（water/wall）上。
##
## 公开 API：
##   list_battlefields() -> Array  [{path,file,id,name,description,width,height,players,enemies,error}]
##   load_battlefield(path) -> Dictionary  { ok, chapter?, info?, error? }
##
## 注意：JSON 战场与真实世界地形无关，调用方应固定走 B2 独立场景模式（见 main.gd）。

class_name BattlefieldLoader
extends RefCounted

const BlockLayoutScript = preload("res://scripts/core/block_layout.gd")

## 战场 JSON 目录
const BATTLEFIELD_DIR := "res://data/battlefields"

## 用户战场目录（地图编辑器在 res:// 不可写时的落盘位置，导出版也可用）
const USER_BATTLEFIELD_DIR := "user://battlefields"

## 默认单字符地形图例（JSON "legend" 可覆盖/追加）
const DEFAULT_LEGEND := {
	".": &"plain",
	"p": &"plain",
	"f": &"forest",
	"m": &"mountain",
	"w": &"water",
	"~": &"water",
	"F": &"fort",
	"v": &"village",
	"#": &"wall",
	"s": &"sand",
	"S": &"snow",
	"g": &"grass",
	"r": &"rocky",
}


## 扫描战场目录，返回按文件名排序的条目列表。
## 同时扫描 res://data/battlefields 与 user://battlefields（编辑器保存的地图），
## res:// 条目在前；user:// 中与 res:// 同名的文件跳过。
## 解析失败的条目也保留（error 非空），UI 里置灰展示方便定位坏文件。
static func list_battlefields() -> Array:
	var out: Array = []
	var seen_files := {}
	_scan_dir_into(BATTLEFIELD_DIR, out, seen_files)
	_scan_dir_into(USER_BATTLEFIELD_DIR, out, seen_files)
	return out


static func _scan_dir_into(dir_path: String, out: Array, seen_files: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		if dir_path != USER_BATTLEFIELD_DIR:
			push_warning("[battlefield_loader] 战场目录不存在: %s" % dir_path)
		return  # user:// 目录不存在是正常情况（还没保存过编辑器地图）
	var files: Array[String] = []
	dir.list_dir_begin()
	var fn := dir.get_next()
	while not fn.is_empty():
		if fn.get_extension() == "json" and not dir.current_is_dir():
			files.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	files.sort()
	for f in files:
		if seen_files.has(f):
			continue
		seen_files[f] = true
		var path := dir_path + "/" + f
		var entry := { "path": path, "file": f }
		var res := load_battlefield(path)
		if bool(res.get("ok", false)):
			var info: Dictionary = res["info"]
			var ch: Dictionary = res["chapter"]
			entry.merge({
				"id": info["id"],
				"name": info["name"],
				"description": info["description"],
				"hosting": info["hosting"],
				"width": ch["width"],
				"height": ch["height"],
				"players": (ch["playerUnits"] as Array).size(),
				"enemies": (ch["enemyUnits"] as Array).size(),
				"error": "",
			})
		else:
			entry.merge({
				"name": f.get_basename(),
				"description": "",
				"error": String(res.get("error", "未知错误")),
			})
		out.append(entry)


## 加载单个战场 JSON → { ok, chapter, info } 或 { ok:false, error }。
## chapter 与 WorldToChapter.world_to_chapter 输出同构（无 world_origin，固定 B2 消费）。
static func load_battlefield(path: String) -> Dictionary:
	var res := _parse_json_file(path)
	if not bool(res.get("ok", false)):
		return { "ok": false, "error": res.get("error", "") }
	var d: Dictionary = res["data"]
	var file_id := path.get_file().get_basename()
	var info := {
		"id": String(d.get("id", file_id)),
		"name": String(d.get("name", file_id)),
		"description": String(d.get("description", "")),
		"hosting": bool(d.get("hosting", false)),
	}
	# 1) 地形矩阵
	var terr := _parse_terrain(d)
	if not bool(terr.get("ok", false)):
		return { "ok": false, "error": terr.get("error", "") }
	var map: Array = terr["map"]
	var height := map.size()
	var width := (map[0] as Array).size()
	if width == 0:
		return { "ok": false, "error": "地形为空（rows/map 首行没有格子）" }
	# 2) 地形合法性 + 行宽一致
	for y in range(height):
		var row: Array = map[y]
		if row.size() != width:
			return { "ok": false, "error": "地形第 %d 行宽度 %d 与首行 %d 不一致" % [y + 1, row.size(), width] }
		for x in range(width):
			var t: StringName = row[x]
			if not TerrainData.TERRAIN.has(t):
				return { "ok": false, "error": "未知地形 \"%s\"（第 %d 行第 %d 列）；可用: plain/forest/mountain/water/fort/village/wall/sand/snow/grass/rocky" % [String(t), y + 1, x + 1] }
	# 3) 单位（两阵营共享 occupied 做重叠检查）
	var occupied: Dictionary = {}
	var pu := _parse_units(d, "playerUnits", &"player", map, width, height, occupied, "u_p")
	if not bool(pu.get("ok", false)):
		return { "ok": false, "error": pu.get("error", "") }
	var eu := _parse_units(d, "enemyUnits", &"enemy", map, width, height, occupied, "u_e")
	if not bool(eu.get("ok", false)):
		return { "ok": false, "error": eu.get("error", "") }
	# 4) 植物层（可选 "props": [{x,y,texture}]；越界/贴图缺失的条目跳过不报错）
	var props: Array = _parse_props(d, width, height)
	# 5) 显式单块布局（可选）：缺省字段保留旧柱体路径，出现时严格校验并规范化。
	var block_layout: Dictionary = {}
	if d.has("block_layout"):
		var layout_result := BlockLayoutScript.normalize(d["block_layout"], width, height)
		if not bool(layout_result.get("ok", false)):
			return {"ok": false, "error": String(layout_result.get("error", "block_layout 非法"))}
		block_layout = layout_result["layout"]
	# 6) 组装 chapter（无 blockTitles → battle.gd 走 terrain fallback 渲染）
	var chapter := {
		"id": StringName(String(info["id"])),
		"name": String(info["name"]),
		"map": map,
		"width": width,
		"height": height,
		"playerUnits": pu["units"],
		"enemyUnits": eu["units"],
		"props": props,
	}
	if not block_layout.is_empty():
		chapter["block_layout"] = block_layout
	return { "ok": true, "chapter": chapter, "info": info }


## ---- 内部实现 ----------------------------------------------------------


## 植物层解析（宽松）：条目须为 {x,y,texture}；越界或贴图文件不存在的跳过
static func _parse_props(d: Dictionary, width: int, height: int) -> Array:
	var out: Array = []
	var raw = d.get("props", [])
	if not (raw is Array):
		return out
	for p in raw:
		if not (p is Dictionary):
			continue
		var x := int(p.get("x", -1))
		var y := int(p.get("y", -1))
		var tex := String(p.get("texture", ""))
		if tex.is_empty() or x < 0 or y < 0 or x >= width or y >= height:
			push_warning("[battlefield_loader] 跳过非法植物条目: %s" % str(p))
			continue
		if not FileAccess.file_exists(tex):
			push_warning("[battlefield_loader] 植物贴图不存在，跳过: %s" % tex)
			continue
		out.append({ "x": x, "y": y, "texture": tex })
	return out


static func _parse_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return { "ok": false, "error": "文件不存在: %s" % path }
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return { "ok": false, "error": "无法打开: %s" % path }
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return { "ok": false, "error": "JSON 解析失败: %s" % json.get_error_message() }
	if not (json.data is Dictionary):
		return { "ok": false, "error": "顶层必须是 JSON 对象" }
	return { "ok": true, "data": json.data }


## 地形声明解析：优先 "rows"（字符画 + 图例），其次 "map"（全名矩阵/行字符串）。
## 返回 { ok, map:[[StringName]] } 或 { ok:false, error }。
static func _parse_terrain(d: Dictionary) -> Dictionary:
	if d.has("rows"):
		return _parse_rows_terrain(d)
	if d.has("map"):
		return _parse_fullname_terrain(d)
	return { "ok": false, "error": "缺少地形声明：需要 \"rows\"（字符画）或 \"map\"（全名矩阵）" }


static func _parse_rows_terrain(d: Dictionary) -> Dictionary:
	# 图例 = 默认表 + JSON legend 覆盖
	var legend := DEFAULT_LEGEND.duplicate()
	var lg = d.get("legend", {})
	if not (lg is Dictionary):
		return { "ok": false, "error": "\"legend\" 必须是对象（单字符 → 地形名）" }
	for k in (lg as Dictionary).keys():
		var glyph := String(k)
		if glyph.length() != 1:
			return { "ok": false, "error": "legend 键必须是单字符: \"%s\"" % glyph }
		legend[glyph] = StringName(String((lg as Dictionary)[k]))
	var rows = d.get("rows", [])
	if not (rows is Array) or (rows as Array).is_empty():
		return { "ok": false, "error": "\"rows\" 必须是非空字符串数组" }
	var map: Array = []
	var width := -1
	for ri in range(rows.size()):
		var row := String(rows[ri])
		if width == -1:
			width = row.length()
		elif row.length() != width:
			return { "ok": false, "error": "rows 第 %d 行长度 %d 与首行 %d 不一致" % [ri + 1, row.length(), width] }
		var cells: Array = []
		cells.resize(row.length())
		for x in range(row.length()):
			var glyph := row[x]
			if not legend.has(glyph):
				return { "ok": false, "error": "rows 第 %d 行第 %d 列未知地形字符 '%s'（在 legend 里补映射）" % [ri + 1, x + 1, glyph] }
			cells[x] = legend[glyph]
		map.append(cells)
	return { "ok": true, "map": map }


static func _parse_fullname_terrain(d: Dictionary) -> Dictionary:
	var rows = d.get("map", [])
	if not (rows is Array) or (rows as Array).is_empty():
		return { "ok": false, "error": "\"map\" 必须是非空二维数组" }
	var map: Array = []
	for ri in range(rows.size()):
		var raw_row = rows[ri]
		var tokens: Array = []
		if raw_row is Array:
			tokens = raw_row
		elif raw_row is String:
			tokens = (raw_row as String).split(" ", false)
		else:
			return { "ok": false, "error": "map 第 %d 行必须是数组或空格分隔字符串" % (ri + 1) }
		if tokens.is_empty():
			return { "ok": false, "error": "map 第 %d 行没有格子" % (ri + 1) }
		var cells: Array = []
		cells.resize(tokens.size())
		for x in range(tokens.size()):
			cells[x] = StringName(String(tokens[x]))
		map.append(cells)
	return { "ok": true, "map": map }


## 单位列表解析：[{class/classId, name?, level?, x, y}] → UnitData 数组（UnitFactory 构建）。
## occupied 由两阵营共享，跨阵营也不允许重叠。
static func _parse_units(
		d: Dictionary, key: String, faction: StringName,
		map: Array, width: int, height: int,
		occupied: Dictionary, id_prefix: String
		) -> Dictionary:
	var raw_list = d.get(key, [])
	if not (raw_list is Array):
		return { "ok": false, "error": "\"%s\" 必须是数组" % key }
	if (raw_list as Array).is_empty():
		return { "ok": false, "error": "\"%s\" 为空（双方至少各 1 个单位）" % key }
	var units: Array = []
	for i in range(raw_list.size()):
		var raw = raw_list[i]
		if not (raw is Dictionary):
			return { "ok": false, "error": "%s 第 %d 项必须是对象" % [key, i + 1] }
		var rd: Dictionary = raw
		var class_str := String(rd.get("class", rd.get("classId", "")))
		var class_id := StringName(class_str)
		if class_str.is_empty() or not ProfessionData.has_profession(class_id):
			return { "ok": false, "error": "%s 第 %d 项职业不存在: \"%s\"" % [key, i + 1, class_str] }
		var level := int(rd.get("level", 1))
		if level < 1:
			level = 1
		var x := int(rd.get("x", -1))
		var y := int(rd.get("y", -1))
		if x < 0 or y < 0 or x >= width or y >= height:
			return { "ok": false, "error": "%s 第 %d 项（%s）坐标越界: (%d,%d)，地图 %dx%d" % [key, i + 1, class_str, x, y, width, height] }
		var terrain: StringName = map[y][x]
		if not _is_standable(terrain):
			return { "ok": false, "error": "%s 第 %d 项（%s）站在不可通行地形 %s 上: (%d,%d)" % [key, i + 1, class_str, String(terrain), x, y] }
		var pos := Vector2i(x, y)
		if occupied.has(pos):
			return { "ok": false, "error": "%s 第 %d 项与其他单位重叠在 (%d,%d)" % [key, i + 1, x, y] }
		occupied[pos] = true
		var uname := String(rd.get("name", ""))
		if uname.is_empty():
			uname = "%s%d" % [ProfessionData.profession_name(class_id), i + 1]
		var uid := StringName("%s_%d" % [id_prefix, i])
		units.append(UnitFactory.create_random_unit(
			uid, uname, faction, level, pos, ProfessionData.get_profession(class_id)))
	return { "ok": true, "units": units }


## terrain 是否可站立（与 world_to_chapter._is_standable 同一规则）
static func _is_standable(t: StringName) -> bool:
	var tile := TerrainData.get_tile(t)
	if not bool(tile.get(&"walkable", false)):
		return false
	return int(tile[&"move_cost"].get(&"foot", 99)) < 99
