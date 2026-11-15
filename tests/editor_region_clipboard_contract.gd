## tests/editor_region_clipboard_contract.gd — 区域五层复制/粘贴/清空/移动契约（headless）
##
## 跑法：godot --headless --path . --script res://tests/editor_region_clipboard_contract.gd

extends SceneTree

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const ClipboardScript = preload("res://scripts/editor/region_clipboard.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		push_error("[editor_region_clipboard_contract] FAIL: %s" % msg)
		print("EDITOR_REGION_CLIPBOARD_FAIL: %s" % msg)


func _run() -> void:
	_test_extract_five_layers()
	_test_paste_replace_and_drop()
	_test_clear_default_z()
	_test_rejections_are_atomic()
	_test_move_and_noop()
	if _failures > 0:
		print("EDITOR_REGION_CLIPBOARD_CONTRACT_FAIL: %d/%d 项未过" % [_failures, _checks])
		quit(1)
		return
	print("EDITOR_REGION_CLIPBOARD_CONTRACT_OK: %d assertions" % _checks)
	quit(0)


func _test_extract_five_layers() -> void:
	var model := _five_layer_model()
	var before := _snapshot(model)
	var payload := ClipboardScript.extract(model, Vector2i(1, 1), Vector2i(3, 2))
	_expect(_snapshot(model) == before, "A1 extract 不修改源模型")
	_expect(ClipboardScript.validate(payload).is_empty(), "A2 extract 产物通过 validate")
	_expect(ClipboardScript.payload_size(payload) == Vector2i(3, 2), "A3 payload_size=3×2")
	_expect(payload.get("version") == 1 and payload.get("w") == 3 and payload.get("h") == 2, "A4 version/w/h")
	_expect(payload.get("rows") == ["fmw", ".Fg"], "A5 地形层按相对行提取")
	_expect(payload.get("block_z") == [1, 2, 3, 4, 5, 6], "A6 高度层 row-major")
	var overrides: Dictionary = payload.get("tile_overrides", {})
	_expect(overrides.size() == 1 and String(overrides.get("2,0", {}).get("asset_id", "")) == "tile_a", "A7 覆盖层相对化且排除区域外")
	var props: Array = payload.get("props", [])
	_expect(props.size() == 2, "A8 只提取区域内两株植物")
	if props.size() == 2:
		_expect(props[0].get("dx") == 0 and props[0].get("dy") == 1 and props[0].get("texture") == "res://tree.png", "A9 texture prop 相对化")
		_expect(props[1].get("dx") == 2 and props[1].get("dy") == 1 and props[1].get("asset_id") == "plant_a", "A10 asset prop 相对化")
	var units: Array = payload.get("units", [])
	_expect(units.size() == 1, "A11 只提取区域内单位")
	if units.size() == 1:
		var unit: Dictionary = units[0]
		_expect(unit.get("dx") == 1 and unit.get("dy") == 1, "A12 单位坐标相对化")
		_expect(unit.get("class") == "swordsman" and unit.get("name") == "区域卫兵" and unit.get("level") == 3, "A13 class/name/level 保留")
		_expect(unit.get("faction") == "player" and unit.get("tag") == "卫", "A14 faction/tag 保留")
	var description := ClipboardScript.describe(payload)
	_expect(description.contains("3×2") and description.contains("单位 1") and description.contains("植物 2"), "A15 describe 摘要")
	_expect(ClipboardScript.payload_size({}) == Vector2i.ZERO, "A16 空 payload 尺寸为 0")


func _test_paste_replace_and_drop() -> void:
	var source := _five_layer_model()
	var payload := ClipboardScript.extract(source, Vector2i(1, 1), Vector2i(3, 2))
	var source_before := _snapshot(source)
	var target := BattlefieldDocScript.create_empty(6, 5)
	var origin := Vector2i(2, 0)
	for dy in range(2):
		for dx in range(3):
			var cell := origin + Vector2i(dx, dy)
			_set_glyph(target, cell, "S")
			BattlefieldDocScript.set_cell_z(target, cell, 9)
	BattlefieldDocScript.set_tile_override(target, Vector2i(2, 0), "old_tile")
	BattlefieldDocScript.set_prop(target, Vector2i(2, 0), "res://old.png")
	_put_unit(target, Vector2i(3, 0), "enemy", "旧目标兵")
	_put_unit(target, Vector2i(0, 4), "enemy", "界外保留兵")
	BattlefieldDocScript.set_prop(target, Vector2i(5, 4), "res://outside.png")

	var result := ClipboardScript.paste(target, payload, origin)
	_expect(bool(result.get("ok", false)) and String(result.get("error", "")).is_empty(), "B1 paste 成功")
	_expect(int(result.get("dropped_units", -1)) == 0 and not bool(result.get("no_op", true)), "B2 paste 无丢弃且非 no-op")
	_expect(_snapshot(source) == source_before, "B3 复制粘贴不改源模型")
	for dy in range(2):
		for dx in range(3):
			var cell := origin + Vector2i(dx, dy)
			_expect(_glyph(target, cell) == String(payload.rows[dy]).substr(dx, 1), "B4 地形整体写入 (%d,%d)" % [dx, dy])
			_expect(BattlefieldDocScript.cell_z(target, cell) == int(payload.block_z[dy * 3 + dx]), "B5 高度整体写入 (%d,%d)" % [dx, dy])
			var expected_override := String(payload.tile_overrides.get("%d,%d" % [dx, dy], {}).get("asset_id", ""))
			_expect(BattlefieldDocScript.tile_override_at(target, cell) == expected_override, "B6 覆盖整体替换 (%d,%d)" % [dx, dy])
	_expect(BattlefieldDocScript.prop_at(target, Vector2i(2, 1)) == "res://tree.png", "B7 texture prop 写入目标")
	_expect(BattlefieldDocScript.prop_asset_at(target, Vector2i(4, 1)) == "plant_a", "B8 asset prop 写入目标")
	_expect(BattlefieldDocScript.prop_at(target, Vector2i(2, 0)).is_empty(), "B9 目标矩形旧 prop 删除")
	_expect(_unit_at(target, Vector2i(3, 0)).is_empty(), "B10 目标矩形旧 unit 删除")
	var moved_unit := _unit_at(target, Vector2i(3, 1))
	_expect(String(moved_unit.get("name", "")) == "区域卫兵" and int(moved_unit.get("level", 0)) == 3, "B11 单位完整写入")
	_expect(String(_unit_at(target, Vector2i(0, 4)).get("name", "")) == "界外保留兵", "B12 目标矩形外 unit 保留")
	_expect(BattlefieldDocScript.prop_at(target, Vector2i(5, 4)) == "res://outside.png", "B13 目标矩形外 prop 保留")

	var wet := BattlefieldDocScript.create_empty(4, 4)
	_set_glyph(wet, Vector2i(1, 1), "w")
	_put_unit(wet, Vector2i(1, 1), "player", "水上兵")
	var wet_payload := ClipboardScript.extract(wet, Vector2i(1, 1), Vector2i(1, 1))
	var dropped := ClipboardScript.write(wet, wet_payload, Vector2i(2, 2))
	_expect(bool(dropped.get("ok", false)) and int(dropped.get("dropped_units", 0)) == 1, "B14 不可站人单位丢弃并计数")
	_expect(_unit_at(wet, Vector2i(2, 2)).is_empty(), "B15 丢弃单位不写入目标")
	_expect(_glyph(wet, Vector2i(2, 2)) == "w", "B16 丢弃单位不影响地形写入")
	_expect(String(_unit_at(wet, Vector2i(1, 1)).get("name", "")) == "水上兵", "B17 paste/write 的源单位仍保留")


func _test_clear_default_z() -> void:
	var model := BattlefieldDocScript.create_empty(5, 4)
	model.block_layout.default_z = 3
	for y in range(1, 3):
		for x in range(1, 3):
			var cell := Vector2i(x, y)
			_set_glyph(model, cell, "f")
			BattlefieldDocScript.set_cell_z(model, cell, 7)
			BattlefieldDocScript.set_tile_override(model, cell, "old_tile")
			BattlefieldDocScript.set_prop(model, cell, "res://old.png")
			_put_unit(model, cell, "player", "待清兵")
	_put_unit(model, Vector2i(0, 0), "enemy", "清空界外兵")
	BattlefieldDocScript.set_prop(model, Vector2i(0, 0), "res://outside.png")
	var result := ClipboardScript.clear_rect(model, Vector2i(1, 1), Vector2i(2, 2))
	_expect(bool(result.get("ok", false)), "C1 clear_rect 成功")
	for y in range(1, 3):
		for x in range(1, 3):
			var cell := Vector2i(x, y)
			_expect(_glyph(model, cell) == ".", "C2 地形回平原 (%d,%d)" % [x, y])
			_expect(BattlefieldDocScript.cell_z(model, cell) == 3, "C3 高度回 default_z=3 (%d,%d)" % [x, y])
			_expect(BattlefieldDocScript.tile_override_at(model, cell).is_empty(), "C4 覆盖清除 (%d,%d)" % [x, y])
			_expect(BattlefieldDocScript.prop_at(model, cell).is_empty() and _unit_at(model, cell).is_empty(), "C5 prop/unit 删除 (%d,%d)" % [x, y])
	_expect(String(_unit_at(model, Vector2i(0, 0)).get("name", "")) == "清空界外兵", "C6 清空界外 unit 保留")
	_expect(BattlefieldDocScript.prop_at(model, Vector2i(0, 0)) == "res://outside.png", "C7 清空界外 prop 保留")


func _test_rejections_are_atomic() -> void:
	var model := _five_layer_model()
	_expect(ClipboardScript.bounds_error(model, Vector2i(1, 1), Vector2i(3, 2)).is_empty(), "D1 合法 bounds")
	_expect(not ClipboardScript.bounds_error(model, Vector2i(3, 1), Vector2i(1, 2)).is_empty(), "D2 反向矩形拒绝")
	_expect(not ClipboardScript.bounds_error(model, Vector2i(-1, 0), Vector2i(1, 1)).is_empty(), "D3 负坐标拒绝")
	_expect(not ClipboardScript.bounds_error(model, Vector2i(0, 0), Vector2i(6, 1)).is_empty(), "D4 越出地图拒绝")
	_expect(not ClipboardScript.validate({}).is_empty(), "D5 空 payload 拒绝")

	var before := _snapshot(model)
	_expect(ClipboardScript.extract(model, Vector2i(-1, 0), Vector2i(1, 1)).is_empty(), "D6 非法 extract 返回空")
	_expect(_snapshot(model) == before, "D7 非法 extract 模型不变")
	var cleared := ClipboardScript.clear_rect(model, Vector2i(0, 0), Vector2i(9, 9))
	_expect(not bool(cleared.get("ok", true)) and not String(cleared.get("error", "")).is_empty(), "D8 非法 clear 返回中文错误")
	_expect(_snapshot(model) == before, "D9 非法 clear 模型不变")

	var payload := ClipboardScript.extract(model, Vector2i(1, 1), Vector2i(3, 2))
	var bad_version: Dictionary = payload.duplicate(true)
	bad_version["version"] = 2
	var rejected_version := ClipboardScript.paste(model, bad_version, Vector2i(0, 0))
	_expect(not bool(rejected_version.get("ok", true)) and not String(rejected_version.get("error", "")).is_empty(), "D10 非法 version 拒绝")
	_expect(_snapshot(model) == before, "D11 非法 version 模型不变")
	var bad_z: Dictionary = payload.duplicate(true)
	bad_z.block_z[0] = 99
	var rejected_z := ClipboardScript.write(model, bad_z, Vector2i(0, 0))
	_expect(not bool(rejected_z.get("ok", true)), "D12 非法高度拒绝")
	_expect(_snapshot(model) == before, "D13 非法高度模型不变")
	var rejected_bounds := ClipboardScript.paste(model, payload, Vector2i(4, 4))
	_expect(not bool(rejected_bounds.get("ok", true)), "D14 paste 目标越界拒绝")
	_expect(_snapshot(model) == before, "D15 paste 目标越界模型不变")
	var rejected_move := ClipboardScript.move(model, Vector2i(1, 1), Vector2i(3, 2), Vector2i(3, 0))
	_expect(not bool(rejected_move.get("ok", true)), "D16 move 目标越界拒绝")
	_expect(_snapshot(model) == before, "D17 move 失败不留半成品")


func _test_move_and_noop() -> void:
	var model := BattlefieldDocScript.create_empty(6, 5)
	model.block_layout.default_z = 2
	_set_glyph(model, Vector2i(1, 1), "f")
	_set_glyph(model, Vector2i(2, 1), "m")
	_set_glyph(model, Vector2i(1, 2), ".")
	_set_glyph(model, Vector2i(2, 2), "F")
	for i in range(4):
		var cell := Vector2i(1 + i % 2, 1 + i / 2)
		BattlefieldDocScript.set_cell_z(model, cell, 4 + i)
	BattlefieldDocScript.set_tile_override(model, Vector2i(1, 1), "move_tile")
	BattlefieldDocScript.set_prop(model, Vector2i(1, 1), "res://move.png")
	BattlefieldDocScript.set_prop_asset(model, Vector2i(2, 2), "move_plant")
	_put_unit(model, Vector2i(1, 1), "player", "移动兵")
	_put_unit(model, Vector2i(4, 3), "enemy", "目标旧兵")
	BattlefieldDocScript.set_prop(model, Vector2i(4, 3), "res://target_old.png")
	_put_unit(model, Vector2i(0, 0), "enemy", "移动界外兵")
	var payload := ClipboardScript.extract(model, Vector2i(1, 1), Vector2i(2, 2))

	var result := ClipboardScript.move(model, Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 1))
	_expect(bool(result.get("ok", false)) and int(result.get("dropped_units", -1)) == 0, "E1 move 成功且无丢弃")
	_expect(not bool(result.get("no_op", true)), "E2 非零 delta 不是 no-op")
	for y in range(1, 3):
		for x in range(1, 3):
			var cell := Vector2i(x, y)
			_expect(_glyph(model, cell) == "." and BattlefieldDocScript.cell_z(model, cell) == 2, "E3 源区清空 (%d,%d)" % [x, y])
			_expect(BattlefieldDocScript.tile_override_at(model, cell).is_empty(), "E4 源覆盖清除 (%d,%d)" % [x, y])
			_expect(BattlefieldDocScript.prop_at(model, cell).is_empty() and BattlefieldDocScript.prop_asset_at(model, cell).is_empty(), "E5 源植物清除 (%d,%d)" % [x, y])
	var origin := Vector2i(4, 2)
	for dy in range(2):
		for dx in range(2):
			var cell := origin + Vector2i(dx, dy)
			_expect(_glyph(model, cell) == String(payload.rows[dy]).substr(dx, 1), "E6 目标地形 (%d,%d)" % [dx, dy])
			_expect(BattlefieldDocScript.cell_z(model, cell) == int(payload.block_z[dy * 2 + dx]), "E7 目标高度 (%d,%d)" % [dx, dy])
	_expect(BattlefieldDocScript.tile_override_at(model, Vector2i(4, 2)) == "move_tile", "E8 目标覆盖")
	_expect(BattlefieldDocScript.prop_at(model, Vector2i(4, 2)) == "res://move.png", "E9 目标 texture prop")
	_expect(BattlefieldDocScript.prop_asset_at(model, Vector2i(5, 3)) == "move_plant", "E10 目标 asset prop 替换旧 prop")
	_expect(String(_unit_at(model, Vector2i(4, 2)).get("name", "")) == "移动兵", "E11 单位移动")
	_expect(_unit_at(model, Vector2i(4, 3)).is_empty(), "E12 目标矩形旧单位删除")
	_expect(_unit_at(model, Vector2i(1, 1)).is_empty(), "E13 源单位删除")
	_expect(String(_unit_at(model, Vector2i(0, 0)).get("name", "")) == "移动界外兵", "E14 界外单位保留")

	var before := _snapshot(model)
	var noop := ClipboardScript.move(model, origin, origin + Vector2i(1, 1), Vector2i.ZERO)
	_expect(bool(noop.get("ok", false)) and bool(noop.get("no_op", false)), "E15 delta=(0,0) 返回 no-op")
	_expect(int(noop.get("dropped_units", -1)) == 0, "E16 no-op 无丢弃")
	_expect(_snapshot(model) == before, "E17 no-op 模型逐字节不变")


func _five_layer_model() -> Dictionary:
	var model := BattlefieldDocScript.create_empty(6, 5)
	var glyphs := ["fmw", ".Fg"]
	for dy in range(2):
		for dx in range(3):
			var cell := Vector2i(1 + dx, 1 + dy)
			_set_glyph(model, cell, String(glyphs[dy]).substr(dx, 1))
			BattlefieldDocScript.set_cell_z(model, cell, dy * 3 + dx + 1)
	BattlefieldDocScript.set_tile_override(model, Vector2i(3, 1), "tile_a")
	BattlefieldDocScript.set_tile_override(model, Vector2i(0, 0), "outside_tile")
	BattlefieldDocScript.set_prop(model, Vector2i(1, 2), "res://tree.png")
	BattlefieldDocScript.set_prop_asset(model, Vector2i(3, 2), "plant_a")
	BattlefieldDocScript.set_prop(model, Vector2i(0, 0), "res://outside.png")
	var unit := _put_unit(model, Vector2i(2, 2), "player", "区域卫兵")
	unit["level"] = 3
	unit["tag"] = "卫"
	_put_unit(model, Vector2i(0, 0), "enemy", "区域外兵")
	return model


func _set_glyph(model: Dictionary, cell: Vector2i, glyph: String) -> void:
	var row := String(model.rows[cell.y])
	model.rows[cell.y] = row.substr(0, cell.x) + glyph + row.substr(cell.x + 1)


func _glyph(model: Dictionary, cell: Vector2i) -> String:
	return String(model.rows[cell.y]).substr(cell.x, 1)


func _put_unit(model: Dictionary, cell: Vector2i, faction: String, uname: String) -> Dictionary:
	var unit := {
		"class": "swordsman",
		"name": uname,
		"level": 1,
		"x": cell.x,
		"y": cell.y,
		"faction": faction,
		"tag": "剑",
	}
	(model.units as Array).append(unit)
	return unit


func _unit_at(model: Dictionary, cell: Vector2i) -> Dictionary:
	for unit_value in model.get("units", []):
		var unit: Dictionary = unit_value
		if int(unit.get("x", -1)) == cell.x and int(unit.get("y", -1)) == cell.y:
			return unit
	return {}


func _snapshot(model: Dictionary) -> String:
	return JSON.stringify(model)
