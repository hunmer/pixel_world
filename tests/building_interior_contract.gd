## building_interior_contract.gd — 室内schema、旋转、阻挡、寻路、编辑与快照往返。
extends SceneTree
const Interior = preload("res://scripts/core/building_interior.gd")
const Layout = preload("res://scripts/core/building_layout.gd")
const Catalog = preload("res://scripts/assets/user_asset_catalog.gd")
const Doc = preload("res://scripts/editor/battlefield_doc.gd")
const Loader = preload("res://scripts/core/battlefield_loader.gd")
const Grid = preload("res://scripts/systems/grid_system.gd")
const ModelOps = preload("res://scripts/editor/map_editor_model_ops.gd")
class FakeCanvas:
	extends RefCounted
	func _refresh_cell(_cell: Vector2i) -> void:
		pass

class FakeEditor:
	extends RefCounted
	var model: Dictionary
	var _canvas := FakeCanvas.new()
	func _init(source: Dictionary) -> void:
		model = source.duplicate(true)
	func _status(_text: String, _error: bool = false) -> void:
		pass
	func _remove_unit_at(cell: Vector2i) -> void:
		for index: int in range(model.units.size() - 1, -1, -1):
			if Vector2i(int(model.units[index].x), int(model.units[index].y)) == cell:
				model.units.remove_at(index)

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("INTERIOR_FAIL: " + message)

func house() -> Dictionary:
	var render: Dictionary = Catalog.default_render()
	render["direction_mode"] = "four_directions"
	render["footprint"] = {"w": 6, "h": 6}
	render["interior"] = {"enabled": true, "rows": ["######", "#....#", "#.F..#", "#....#", "#....#", "##D###"], "reveal_zoom": 1.8, "hide_zoom": 1.5}
	return Catalog.make_descriptor("house", "building", "房屋", [], "sheet.png", "a".repeat(64), 100, 2048, 512, render)

func _run() -> void:
	var descriptor: Dictionary = house()
	var interior: Dictionary = descriptor["render"]["interior"]
	expect(Catalog.validate_descriptor(descriptor, "house").is_empty(), "合法房屋描述符")
	for kind: String in ["rows_missing", "row_count", "row_width", "character", "open_edge", "door_missing", "inner_door", "corner_door", "disconnected", "nan", "inverted", "enabled_type"]:
		var bad: Dictionary = interior.duplicate(true)
		match kind:
			"rows_missing": bad.erase("rows")
			"row_count": bad["rows"].pop_back()
			"row_width": bad["rows"][1] = "#...#"
			"character": bad["rows"][1] = "#..X.#"
			"open_edge": bad["rows"][0] = "##.###"
			"door_missing": bad["rows"][5] = "######"
			"inner_door": bad["rows"][1] = "#D...#"
			"corner_door": bad["rows"][0] = "D#####"
			"disconnected": bad["rows"][4] = "######"
			"nan": bad["reveal_zoom"] = NAN
			"inverted": bad["hide_zoom"] = 2.0
			"enabled_type": bad["enabled"] = "yes"
		expect(not Interior.validate(bad, {"w": 6, "h": 6}).is_empty(), "拒绝非法室内 " + kind)
	var assets: Dictionary = {"house": descriptor}
	for rotation: int in 4:
		var entry: Dictionary = {"instance_id": "house1", "asset_id": "house", "x": 2, "y": 2, "rotation": rotation}
		expect(Layout.occupied_cells(entry, assets).size() == 36, "四向保持完整36格占地")
		var blocks: Array[Vector2i] = Layout.blocking_cells(entry, assets)
		expect(blocks.size() == 20, "四向仅19墙+1家具阻挡")
		var door: Vector2i = Interior.cell_at(entry, Vector2i(2, 5), Vector2i(6, 6))
		var floor: Vector2i = Interior.cell_at(entry, Vector2i(2, 4), Vector2i(6, 6))
		var furniture: Vector2i = Interior.cell_at(entry, Vector2i(2, 2), Vector2i(6, 6))
		expect(not blocks.has(door) and not blocks.has(floor) and blocks.has(furniture), "门地板可走家具阻挡")
		var expected_doors: Array[Vector2i] = [Vector2i(4, 7), Vector2i(2, 4), Vector2i(5, 2), Vector2i(7, 5)]
		expect(door == expected_doors[rotation], "门按顺时针旋转映射")
		var model: Dictionary = Doc.create_empty(12, 12)
		model["user_assets"] = assets.duplicate(true)
		model["units"] = [{"class": "swordsman", "faction": "player", "x": floor.x, "y": floor.y, "level": 1},
			{"class": "berserker", "faction": "enemy", "x": 11, "y": 11, "level": 1}]
		expect(Doc.can_place_building(model, "house", Vector2i(2, 2), rotation).is_empty(), "可围绕已有室内角色放房屋")
		var added: Dictionary = Doc.add_building(model, "house", Vector2i(2, 2), rotation, assets)
		expect(added.get("ok", false), "可进入房屋放置")
		expect(not Doc.building_blocks_cell(model, floor) and Doc.building_blocks_cell(model, furniture), "编辑器阻挡API")
		expect(not Doc.building_at(model, floor).is_empty(), "室内地板仍可命中整栋选择")
		expect(not Doc.can_place_building(model, "house", Vector2i(3, 3), 0).is_empty(), "全占地建筑重叠仍拒绝")
		var json: Dictionary = Doc.to_json_dict(model)
		var loaded: Dictionary = Loader.load_battlefield_inline(json, "interior_test")
		expect(loaded.get("ok", false), "含室内角色地图可加载: %s" % loaded.get("error", ""))
		var roundtrip: Dictionary = Doc.from_json_dict(JSON.parse_string(JSON.stringify(json)))
		expect(roundtrip["user_assets"]["house"]["render"]["interior"] == interior, "室内元数据JSON往返保留")
		var map: Array = []
		for y: int in 12:
			var row: Array = []
			for x: int in 12:
				row.append(&"plain")
			map.append(row)
		var grid := Grid.new(12, 12, map)
		grid.apply_buildings(model["buildings"], assets)
		var outside: Vector2i = door + (door - floor)
		var path: Array = grid.find_path(outside, floor, &"foot", 30)
		expect(not path.is_empty(), "角色经门进入室内寻路")
		expect(grid.find_path(outside, furniture, &"foot", 30).is_empty(), "家具不可成为寻路终点")
		var editor := FakeEditor.new(model)
		expect(ModelOps.place_unit(editor, floor, "player", "swordsman", 1), "编辑器实际角色工具允许放置室内地板")
		expect(not ModelOps.place_unit(editor, furniture, "player", "swordsman", 1), "编辑器实际角色工具拒绝家具")
		var changed_json: Dictionary = json.duplicate(true)
		changed_json["user_assets"]["house"]["render"]["interior"]["rows"][0] = "......"
		expect(not Loader.load_battlefield_inline(changed_json, "invalid_interior").get("ok", true), "地图加载严格拒绝非法室内快照")
		var water_model: Dictionary = model.duplicate(true)
		var water_row: String = water_model.rows[floor.y]
		water_model.rows[floor.y] = water_row.substr(0, floor.x) + "w" + water_row.substr(floor.x + 1)
		expect(not ModelOps.place_unit(FakeEditor.new(water_model), floor, "player", "swordsman", 1), "室内地板不会覆盖水域不可站立属性")
		var nonflat: Dictionary = model.duplicate(true)
		nonflat.erase("block_layout")
		var first_row: String = nonflat.rows[2]
		nonflat.rows[2] = first_row.substr(0, 2) + "m" + first_row.substr(3)
		expect(not Doc.validate_buildings(nonflat).is_empty(), "无显式高度时检测实际地形站立高度不平")
		model["units"][0]["x"] = furniture.x
		model["units"][0]["y"] = furniture.y
		expect(not Doc.validate_buildings(model).is_empty(), "保存拒绝角色压家具")
		model["units"] = []
		var uneven: Vector2i = Vector2i(2, 2)
		Doc.set_cell_z(model, uneven, 1)
		expect(not Doc.validate_buildings(model).is_empty(), "可进入房屋拒绝不平底面")
	var old: Dictionary = descriptor.duplicate(true)
	old["render"].erase("interior")
	var entry: Dictionary = {"instance_id": "old", "asset_id": "old", "x": 0, "y": 0, "rotation": 0}
	expect(Layout.blocking_cells(entry, {"old": old}).size() == 36, "旧建筑保持全占地阻挡")
	var disabled: Dictionary = descriptor.duplicate(true)
	disabled["render"]["interior"] = {"enabled": false}
	expect(Layout.blocking_cells(entry, {"old": disabled}).size() == 36, "关闭入内恢复旧行为")
	print("BUILDING_INTERIOR_CONTRACT %s checks=%d" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
