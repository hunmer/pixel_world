## tests/battlefield_render_contract.gd — 等距方块渲染器契约测试
##
## 跑法：godot --headless --path . --script res://tests/battlefield_render_contract.gd
## 覆盖：柱数/站立层/坐标投影/多高度拾取/水柱岸线位掩码/装饰物确定性/单格重建。

extends SceneTree

const RendererScript = preload("res://scripts/iso/battlefield_renderer.gd")
const IsoCoordsScript = preload("res://scripts/iso/iso_coords.gd")

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  ok: %s" % msg)
	else:
		failures += 1
		printerr("  FAIL: %s" % msg)


## 5×5 测试图：'. 'plain 'F'fort 'v'village 'm'mountain 'w'water '#'wall 'f'forest
func _make_grid() -> GridSystem:
	var terrain_names := {
		".": &"plain", "F": &"fort", "v": &"village", "m": &"mountain",
		"w": &"water", "#": &"wall", "f": &"forest",
	}
	var rows := [
		".....",
		".F..v",
		"..w..",
		"#..wm",
		"..f.w",
	]
	var map: Array = []
	for y in range(5):
		var line: Array = []
		var row: String = rows[y]
		for x in range(5):
			line.append(terrain_names[row.substr(x, 1)])
		map.append(line)
	return GridSystem.new(5, 5, map)


func _run() -> void:
	print("== battlefield_render_contract ==")
	var root := Node2D.new()
	var renderer: Node2D = RendererScript.new()
	root.add_child(renderer)
	var grid := _make_grid()
	renderer.setup(grid)

	# 1. 柱数 = 格子数
	_expect(renderer.column_count() == 25, "柱数=25（实际 %d）" % renderer.column_count())

	# 2. 站立层：plain2/forest2/fort3/wall4/mountain5/water1/village2
	_expect(renderer.stand_level(0, 0) == 2, "plain(0,0) 站立层=2")
	_expect(renderer.stand_level(2, 4) == 2, "forest(2,4) 站立层=2")
	_expect(renderer.stand_level(1, 1) == 3, "fort(1,1) 站立层=3")
	_expect(renderer.stand_level(0, 3) == 4, "wall(0,3) 站立层=4")
	_expect(renderer.stand_level(4, 3) == 5, "mountain(4,3) 站立层=5")
	_expect(renderer.stand_level(2, 2) == 1, "water(2,2) 站立层=1")
	_expect(renderer.stand_level(4, 1) == 2, "village(4,1) 站立层=2")
	_expect(renderer.stand_level(-1, 0) == 0, "越界站立层=0")

	# 3. coord_for == to_screen(x, y, stand_level)
	var ok := true
	for y in range(5):
		for x in range(5):
			var expect_pos: Vector2 = IsoCoordsScript.to_screen(x, y, renderer.stand_level(x, y))
			if renderer.coord_for(x, y) != expect_pos:
				ok = false
	_expect(ok, "coord_for 全图 == to_screen(x,y,stand_level)")

	# 4. sort_for 对角单调
	_expect(renderer.sort_for(0, 1) < renderer.sort_for(1, 0)
		and renderer.sort_for(1, 0) < renderer.sort_for(1, 1), "sort_for 对角单调")

	# 5. 多高度拾取（root/renderer 未进树 → global_transform=identity，直接用世界坐标）
	var hit: Vector2i = renderer.pick_world(IsoCoordsScript.to_screen(3, 2, 2))
	_expect(hit == Vector2i(3, 2), "平原柱顶点击命中 (3,2)（实际 %s）" % hit)
	var hit_m: Vector2i = renderer.pick_world(IsoCoordsScript.to_screen(4, 3, 5))
	_expect(hit_m == Vector2i(4, 3), "山顶点击命中 (4,3)（实际 %s）" % hit_m)
	var hit_w: Vector2i = renderer.pick_world(IsoCoordsScript.to_screen(4, 4, 1))
	_expect(hit_w == Vector2i(4, 4), "水面点击命中 (4,4)（实际 %s）" % hit_w)
	var hit_w2: Vector2i = renderer.pick_world(IsoCoordsScript.to_screen(2, 2, 1))
	_expect(hit_w2 == Vector2i(2, 2), "水面(2,2)点击命中（实际 %s）" % hit_w2)
	# 山体侧壁中段点击：算法只把「柱顶面」精确归属；侧壁点击落到图内其他格（可接受的退化）
	var mid: Vector2i = renderer.pick_world(IsoCoordsScript.to_screen(4, 3, 3))
	_expect(grid.in_bounds(mid.x, mid.y), "山体侧壁中段点击退化为图内有效格（实际 %s）" % mid)
	var oob: Vector2i = renderer.pick_world(IsoCoordsScript.to_screen(-3, -3, 2))
	_expect(oob == Vector2i(-1, -1), "图外拾取返回 (-1,-1)（实际 %s）" % oob)

	# 6. 水柱块结构：bed@0 + surface@1（带岸线位掩码）
	var col: Node = renderer._columns[Vector2i(2, 2)]
	var blocks: Array = col._blocks
	_expect(blocks.size() == 2, "浅水柱块数=2（bed+surface，实际 %d）" % blocks.size())
	var bed: Dictionary = blocks[0]
	var surf: Dictionary = blocks[blocks.size() - 1]
	_expect(int(bed["level"]) == 0, "湖床 level=0")
	_expect(surf.get("water_part", &"") == &"surface", "顶块 water_part=surface")
	_expect(int(surf["level"]) == 1, "水面 level=1")
	# (2,2) 四邻 (1,2)/(3,2)/(2,1)/(2,3) 全 plain → shore=1|2|4|8=15
	_expect(int(surf.get("shore_edges", -1)) == 15, "四邻全陆 → shore_edges=15（实际 %d）" % int(surf.get("shore_edges", -1)))
	# 角落水格 (4,4)：左(3,4)plain→位1、上(4,3)mountain→位2；右/下 OOB 不置位
	var corner: Array = (renderer._columns[Vector2i(4, 4)] as Node)._blocks
	var csurf: Dictionary = corner[corner.size() - 1]
	_expect(int(csurf.get("shore_edges", -1)) == 3, "角水格 shore_edges=3（左|上）（实际 %d）" % int(csurf.get("shore_edges", -1)))

	# 7. 装饰物确定性：forest 格含 prop block，occluder_class=prop，重建后贴图一致
	var forest_col: Node = renderer._columns[Vector2i(2, 4)]
	var prev_has_prop := false
	var prop_tex: Texture2D = null
	for b in (forest_col as Node)._blocks:
		if b.get("occluder_class", &"") == &"prop":
			prev_has_prop = true
			prop_tex = b["texture"]
	_expect(prev_has_prop, "森林格有装饰物 block")
	_expect(prop_tex != null and prop_tex.get_size().x > 0, "装饰物贴图有效（%s）" % str(prop_tex.get_size() if prop_tex else Vector2i.ZERO))
	var blocks_before: int = (forest_col as Node)._blocks.size()
	renderer.refresh_cell(2, 4)
	var forest_col2: Node = renderer._columns[Vector2i(2, 4)]
	var prop_tex2: Texture2D = null
	for b in (forest_col2 as Node)._blocks:
		if b.get("occluder_class", &"") == &"prop":
			prop_tex2 = b["texture"]
	_expect(prop_tex2 == prop_tex, "refresh_cell 后装饰物贴图确定性一致")
	_expect((forest_col2 as Node)._blocks.size() == blocks_before, "refresh_cell 块数不变")
	_expect(renderer.column_count() == 25, "refresh_cell 后柱数仍 25")

	# 8. 单格地形变更：water → mountain（stand_level 1→5）
	(grid.tiles[2][2] as Dictionary)["type"] = &"mountain"
	renderer.refresh_cell(2, 2)
	_expect(renderer.stand_level(2, 2) == 5, "水→山后站立层=5")
	var mhit: Vector2i = renderer.pick_world(IsoCoordsScript.to_screen(2, 2, 5))
	_expect(mhit == Vector2i(2, 2), "变更后山顶点击命中 (2,2)（实际 %s）" % mhit)
	var mblocks: Array = (renderer._columns[Vector2i(2, 2)] as Node)._blocks
	var no_water := true
	for b in mblocks:
		if b.has("water_part"):
			no_water = false
	_expect(no_water and mblocks.size() == 5, "水→山后无水块且块数=5（实际 %d）" % mblocks.size())

	# 9. setup(null) 安全（编辑器空模型路径）
	renderer.setup(null)
	_expect(renderer.column_count() == 0 and renderer.grid == null, "setup(null) 清空且不崩")

	# 10. 调色板预览 blocks（编辑器 tile_preview 用）
	var expect_counts := {&"plain": 2, &"forest": 3, &"mountain": 5, &"water": 2, &"fort": 4, &"village": 3, &"wall": 4}
	for t in expect_counts.keys():
		var pblocks: Array = RendererScript.preview_blocks(t)
		var prev_all_tex := true
		for b in pblocks:
			if b.get("texture", null) == null:
				prev_all_tex = false
		_expect(pblocks.size() == int(expect_counts[t]), "preview %s 块数=%d（期望 %d）" % [t, pblocks.size(), int(expect_counts[t])])
		_expect(prev_all_tex, "preview %s 贴图全非空" % t)
	var water_preview: Array = RendererScript.preview_blocks(&"water")
	_expect(abs(float(water_preview[1]["modulate"].a) - 0.38) < 0.001, "水面预览 alpha=0.38")
	var wall_preview: Array = RendererScript.preview_blocks(&"wall")
	_expect(abs(float(wall_preview[0]["modulate"].r) - 0.58) < 0.001, "墙体预览 tint r=0.58")
	var forest_preview: Array = RendererScript.preview_blocks(&"forest")
	var palette_has_prop := false
	for b in forest_preview:
		if b.get("occluder_class", &"") == &"prop":
			palette_has_prop = true
	_expect(palette_has_prop, "森林预览含装饰物")

	if failures == 0:
		print("BATTLEFIELD_RENDER_CONTRACT_OK")
		quit(0)
	else:
		printerr("BATTLEFIELD_RENDER_CONTRACT_FAILED: %d 处失败" % failures)
		quit(1)
