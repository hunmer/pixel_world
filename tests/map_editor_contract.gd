## tests/map_editor_contract.gd — 战场地图编辑器契约测试（headless）
##
## 跑法：godot --headless --path . --script res://tests/map_editor_contract.gd
## 覆盖：种子生成确定性 / resize / 模型↔JSON 互转 / 保存回读校验（含坏地图拒收）/
##       loader 双目录扫描合并（res:// + user://battlefields）/
##       新地形全链一致性（TerrainData ↔ DEFAULT_LEGEND ↔ TERRAIN_GLYPH/CN ↔ TERRAIN_STYLES）。

extends SceneTree

const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const RendererScript = preload("res://scripts/iso/battlefield_renderer.gd")

const TMP_RES_ID := "contract_tmp_map"
const TMP_USER_ID := "contract_tmp_user"


func _initialize() -> void:
	call_deferred("_run")


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		push_error("[map_editor_contract] FAIL: %s" % msg)
		print("MAP_EDITOR_CONTRACT_FAIL: %s" % msg)
		quit(1)


func _run() -> void:
	# ---- 1. 种子生成：确定性 + 差异性 + 尺寸 + 图例合法 ----
	var g1: Dictionary = BattlefieldDocScript.generate("abc", 10, 8)
	var g2: Dictionary = BattlefieldDocScript.generate("abc", 10, 8)
	var g3: Dictionary = BattlefieldDocScript.generate("abd", 10, 8)
	_expect(g1.width == 10 and g1.height == 8, "generate 尺寸 10x8")
	_expect("\n".join(g1.rows) == "\n".join(g2.rows), "同种子同尺寸 → 相同地形")
	_expect("\n".join(g1.rows) != "\n".join(g3.rows), "不同种子 → 不同地形")
	var legend_keys := {}
	for k in BattlefieldLoaderScript.DEFAULT_LEGEND:
		legend_keys[k] = true
	for r: String in g1.rows:
		_expect(r.length() == 10, "生成行宽 == 10")
		for ch in r:
			_expect(legend_keys.has(ch), "生成图例字符 '%s' 合法" % ch)

	# 尺寸钳制
	var tiny: Dictionary = BattlefieldDocScript.generate("x", 2, 2)
	_expect(tiny.width == BattlefieldDocScript.MIN_SIZE and tiny.height == BattlefieldDocScript.MIN_SIZE,
		"尺寸钳制到 MIN_SIZE=%d" % BattlefieldDocScript.MIN_SIZE)

	# ---- 2. resize：裁剪保留左上、扩出补平原、越界单位剔除 ----
	var m: Dictionary = BattlefieldDocScript.create_empty(6, 4)
	m.rows[1] = "##ffff"
	m.units = [
		{ "class": "swordsman", "name": "A", "level": 1, "x": 0, "y": 0, "faction": "player" },
		{ "class": "berserker", "name": "B", "level": 1, "x": 5, "y": 3, "faction": "enemy" },
	]
	var r2: Dictionary = BattlefieldDocScript.resize(m, 4, 8)
	_expect(r2.rows[1] == "##ff", "resize 裁剪行内容")
	_expect(r2.rows[4] == "....", "resize 扩出行为平原")
	_expect((r2.units as Array).size() == 1, "越界单位被剔除（保留 (0,0)）")

	# ---- 3. 模型 ↔ JSON 互转 round-trip ----
	var doc: Dictionary = BattlefieldDocScript.generate("rt", 8, 6)
	doc.id = "rt_map"
	doc.name = "回环测试"
	doc.description = "desc"
	doc.hosting = true
	var cells := _find_plain_cells(doc, 2)
	doc.units = [
		{ "class": "swordsman", "name": "罗兰", "level": 3, "x": cells[0].x, "y": cells[0].y, "faction": "player" },
		{ "class": "mage", "name": "暮语", "level": 2, "x": cells[1].x, "y": cells[1].y, "faction": "enemy" },
	]
	var j: Dictionary = BattlefieldDocScript.to_json_dict(doc)
	_expect(j.id == "rt_map" and j.name == "回环测试" and j.hosting == true, "to_json 元字段")
	_expect((j.rows as Array).size() == 6, "to_json rows 行数（顶层字段）")
	_expect((j.playerUnits as Array).size() == 1 and (j.enemyUnits as Array).size() == 1, "to_json 双阵营拆分")
	var back: Dictionary = BattlefieldDocScript.from_json_dict(j)
	_expect(back.id == "rt_map" and back.hosting == true, "from_json 元字段回读")
	_expect("\n".join(back.rows) == "\n".join(doc.rows), "from_json rows 回读一致")
	_expect((back.units as Array).size() == 2, "from_json 单位回读")
	var u0: Dictionary = back.units[0]
	_expect(u0.faction == "player" and u0.class == "swordsman" and u0.level == 3, "from_json 单位字段")

	# map 全名写法（顶层字段，与 loader schema 一致）→ 图例行
	var map_form := {
		"id": "mf", "name": "MF",
		"map": [["plain", "forest"], ["water", "wall"]],
		"playerUnits": [ { "class": "swordsman", "level": 1, "x": 0, "y": 0 } ],
		"enemyUnits": [ { "class": "berserker", "level": 1, "x": 1, "y": 1 } ],
	}
	var mf: Dictionary = BattlefieldDocScript.from_json_dict(map_form)
	_expect(mf.rows[0] == ".f" and mf.rows[1] == "w#", "map 全名写法转图例行")

	# ---- 4. quick_validate 错误分支 ----
	var bad: Dictionary = BattlefieldDocScript.create_empty(5, 5)
	bad.units = []
	_expect(BattlefieldDocScript.quick_validate(bad) != "", "缺单位被 quick_validate 拒绝")
	bad.rows[2] = "zzzzz"
	_expect(BattlefieldDocScript.quick_validate(bad) != "", "未知图例被 quick_validate 拒绝")

	# ---- 5. save_model：先清残留 → 保存 → loader 回读 → 删除 ----
	_cleanup_res_tmp()
	var sv: Dictionary = BattlefieldDocScript.create_empty(6, 5)
	sv.id = TMP_RES_ID
	sv.name = "契约临时图"
	sv.rows[2] = "..ww.."
	var pc := _find_plain_cells(sv, 3)
	sv.units = [
		{ "class": "swordsman", "name": "契约甲", "level": 2, "x": pc[0].x, "y": pc[0].y, "faction": "player" },
		{ "class": "berserker", "name": "契约乙", "level": 2, "x": pc[1].x, "y": pc[1].y, "faction": "enemy" },
	]
	var saved: Dictionary = BattlefieldDocScript.save_model(sv)
	_expect(bool(saved.get("ok", false)), "save_model 成功: %s" % saved.get("error", ""))
	var saved_path := String(saved.get("path", ""))
	_expect(saved_path.ends_with(TMP_RES_ID + ".json"), "保存路径含 id（%s）" % saved_path)
	var loaded := BattlefieldLoaderScript.load_battlefield(saved_path)
	_expect(bool(loaded.get("ok", false)), "保存后 loader 回读 ok: %s" % loaded.get("error", ""))
	if bool(loaded.get("ok", false)):
		var ch: Dictionary = loaded["chapter"]
		_expect(ch.width == 6 and ch.height == 5, "回读 chapter 尺寸")
		_expect((ch.playerUnits as Array).size() == 1, "回读 playerUnits")
	_cleanup_res_tmp()

	# 坏地图拒收：单位站在水上 → save 失败且不残留文件
	var wet: Dictionary = BattlefieldDocScript.create_empty(6, 5)
	wet.id = TMP_RES_ID
	wet.rows = [
		"wwwwww",
		"wwwwww",
		"......",
		"......",
		"......",
	]
	wet.units = [
		{ "class": "swordsman", "name": "A", "level": 1, "x": 0, "y": 0, "faction": "player" },
		{ "class": "berserker", "name": "B", "level": 1, "x": 0, "y": 2, "faction": "enemy" },
	]
	var wet_save: Dictionary = BattlefieldDocScript.save_model(wet)
	_expect(not bool(wet_save.get("ok", false)), "水上站单位被拒收")
	_expect(not FileAccess.file_exists("res://data/battlefields/%s.json" % TMP_RES_ID),
		"拒收后不残留文件")
	_cleanup_res_tmp()

	# ---- 6. loader 双目录合并：user://battlefields 条目并入列表 ----
	_cleanup_user_tmp()
	DirAccess.make_dir_recursive_absolute("user://battlefields")
	var sample: Dictionary = BattlefieldDocScript.create_empty(4, 4)
	sample.units = [
		{ "class": "knight", "name": "U1", "level": 1, "x": 1, "y": 1, "faction": "player" },
		{ "class": "archer", "name": "U2", "level": 1, "x": 2, "y": 2, "faction": "enemy" },
	]
	sample.id = TMP_USER_ID
	var juser: Dictionary = BattlefieldDocScript.to_json_dict(sample)
	juser.id = TMP_USER_ID
	juser.name = "用户临时图"
	var uf := FileAccess.open("user://battlefields/%s.json" % TMP_USER_ID, FileAccess.WRITE)
	uf.store_string(JSON.stringify(juser, "\t"))
	uf.close()

	var listing: Array = BattlefieldLoaderScript.list_battlefields()
	var found_user := false
	var res_count := 0
	for e in listing:
		if String(e.file) == TMP_USER_ID + ".json" and String(e.path).begins_with("user://"):
			found_user = String(e.get("error", "x")) == ""
		if String(e.path).begins_with("res://"):
			res_count += 1
	_expect(found_user, "user://battlefields 条目并入列表")
	_expect(res_count >= 4, "res:// 内置示例仍在列表（%d 个）" % res_count)
	_cleanup_user_tmp()
	var after: Array = BattlefieldLoaderScript.list_battlefields()
	var still := false
	for e in after:
		if String(e.file) == TMP_USER_ID + ".json":
			still = true
	_expect(not still, "清理后 user:// 临时条目消失")

	# ---- 7. 新地形全链一致性：TerrainData ↔ DEFAULT_LEGEND ↔ TERRAIN_GLYPH/CN ↔ TERRAIN_STYLES ----
	var new_terrains: Array = [&"sand", &"snow", &"grass", &"rocky"]
	for t in new_terrains:
		_expect(TerrainData.TERRAIN.has(t), "TerrainData 注册新地形 %s" % t)
		if TerrainData.TERRAIN.has(t):
			var tile: Dictionary = TerrainData.TERRAIN[t]
			_expect(bool(tile[&"walkable"]) and int(tile[&"move_cost"][&"foot"]) < 99,
				"新地形 %s 可站立（walkable 且 foot 可通行）" % t)
		var glyph: String = String(BattlefieldDocScript.TERRAIN_GLYPH.get(t, ""))
		_expect(glyph.length() == 1, "%s 有单字符主图例（实际 '%s'）" % [t, glyph])
		if glyph.length() == 1:
			_expect(BattlefieldLoaderScript.DEFAULT_LEGEND.get(glyph, &"") == t,
				"DEFAULT_LEGEND['%s'] == %s" % [glyph, t])
			_expect(BattlefieldDocScript.glyph_to_terrain(glyph) == t,
				"glyph_to_terrain('%s') == %s（图例往返一致）" % [glyph, t])
		_expect(String(BattlefieldDocScript.TERRAIN_CN.get(t, "")) != "", "%s 有中文名" % t)
		var style: Dictionary = RendererScript.TERRAIN_STYLES.get(t, {})
		_expect(not style.is_empty() and int(style.get("height", 0)) >= 1,
			"%s 有渲染样式且 height>=1" % t)
		var pblocks: Array = RendererScript.preview_blocks(t)
		var prev_all_tex := not pblocks.is_empty()
		for b in pblocks:
			if b.get("texture", null) == null:
				prev_all_tex = false
		_expect(prev_all_tex, "%s preview_blocks 非空且贴图全非空" % t)

	# 全链闭环：TerrainData 每种地形都必须有 图例/中文名/渲染样式（防以后加地形漏一环）
	for t in TerrainData.TERRAIN.keys():
		_expect(BattlefieldDocScript.TERRAIN_GLYPH.has(t), "全地形 %s 缺 TERRAIN_GLYPH" % t)
		_expect(BattlefieldDocScript.TERRAIN_CN.has(t), "全地形 %s 缺 TERRAIN_CN" % t)
		_expect(RendererScript.TERRAIN_STYLES.has(t), "全地形 %s 缺 TERRAIN_STYLES" % t)

	# 端到端：新图例字符画 → quick_validate → save_model → loader 回读出新地形名
	var nt: Dictionary = BattlefieldDocScript.create_empty(8, 4)
	nt.id = TMP_RES_ID
	nt.name = "新地形链"
	nt.rows[0] = "ssSSggrr"
	nt.rows[1] = "rSg.rsSg"
	nt.units = [
		{ "class": "swordsman", "name": "甲", "level": 1, "x": 4, "y": 1, "faction": "player" },
		{ "class": "berserker", "name": "乙", "level": 1, "x": 0, "y": 3, "faction": "enemy" },
	]
	_expect(BattlefieldDocScript.quick_validate(nt) == "", "新图例模型 quick_validate 通过")
	_cleanup_res_tmp()
	var nt_saved: Dictionary = BattlefieldDocScript.save_model(nt)
	_expect(bool(nt_saved.get("ok", false)), "新图例地图 save_model 成功: %s" % nt_saved.get("error", ""))
	if bool(nt_saved.get("ok", false)):
		var nt_loaded := BattlefieldLoaderScript.load_battlefield(String(nt_saved.get("path", "")))
		_expect(bool(nt_loaded.get("ok", false)), "新图例地图 loader 回读 ok: %s" % nt_loaded.get("error", ""))
		if bool(nt_loaded.get("ok", false)):
			var nch: Dictionary = nt_loaded["chapter"]
			_expect(nch["map"][0][0] == &"sand" and nch["map"][0][1] == &"sand", "回读沙地 s→sand")
			_expect(nch["map"][0][2] == &"snow" and nch["map"][0][3] == &"snow", "回读雪地 S→snow")
			_expect(nch["map"][0][4] == &"grass" and nch["map"][0][5] == &"grass", "回读草原 g→grass")
			_expect(nch["map"][0][6] == &"rocky" and nch["map"][0][7] == &"rocky", "回读碎石地 r→rocky")
			_expect(nch["map"][1][3] == &"plain", "新图例行中的 '.' 仍是 plain")
	_cleanup_res_tmp()

	print("MAP_EDITOR_CONTRACT_OK")
	quit(0)


func _find_plain_cells(m: Dictionary, count: int) -> Array:
	var out: Array = []
	for y in range(m.height):
		var row: String = m.rows[y]
		for x in range(m.width):
			if row.substr(x, 1) == ".":
				out.append(Vector2i(x, y))
				if out.size() >= count:
					return out
	return out


func _cleanup_res_tmp() -> void:
	var p := "res://data/battlefields/%s.json" % TMP_RES_ID
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _cleanup_user_tmp() -> void:
	var p := "user://battlefields/%s.json" % TMP_USER_ID
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
