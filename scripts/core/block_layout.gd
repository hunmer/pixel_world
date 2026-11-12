## core/block_layout.gd — 显式单块战场布局的统一 schema、校验与访问
##
## block_layout = {version:1, default_z:0, cells:[{x,y,z}]}。
## cells 允许省略格子（读取时采用 default_z）；规范化后按 row-major 枚举全部格子。
## 旧 JSON 没有 block_layout，调用方不得擅自注入，以保留旧柱体渲染契约。

class_name BattlefieldBlockLayout
extends RefCounted

const VERSION := 1
const DEFAULT_Z := 0
const MIN_Z := 0
const MAX_Z := 16


static func create(width: int, height: int, default_z: int = DEFAULT_Z) -> Dictionary:
	var cells: Array = []
	for y in range(height):
		for x in range(width):
			cells.append({"x": x, "y": y, "z": default_z})
	return {"version": VERSION, "default_z": default_z, "cells": cells}


static func normalize(raw: Variant, width: int, height: int) -> Dictionary:
	if not (raw is Dictionary):
		return {"ok": false, "error": "block_layout 必须是对象"}
	var layout: Dictionary = raw
	if not _is_integer(layout.get("version", null)) or int(layout["version"]) != VERSION:
		return {"ok": false, "error": "block_layout.version 必须为 1"}
	var default_z: Variant = layout.get("default_z", DEFAULT_Z)
	if not _is_integer(default_z) or not _z_valid(int(default_z)):
		return {"ok": false, "error": "block_layout.default_z 必须在 %d..%d" % [MIN_Z, MAX_Z]}
	var raw_cells: Variant = layout.get("cells", null)
	if not (raw_cells is Array):
		return {"ok": false, "error": "block_layout.cells 必须是数组"}
	var out := create(width, height, int(default_z))
	var seen := {}
	for entry_value in raw_cells:
		if not (entry_value is Dictionary):
			return {"ok": false, "error": "block_layout.cells 条目必须是对象"}
		var entry: Dictionary = entry_value
		var x_value: Variant = entry.get("x", null)
		var y_value: Variant = entry.get("y", null)
		var z_value: Variant = entry.get("z", DEFAULT_Z)
		if not _is_integer(x_value) or not _is_integer(y_value) or not _is_integer(z_value):
			return {"ok": false, "error": "block_layout 格子的 x/y/z 必须是整数"}
		var cell := Vector2i(int(x_value), int(y_value))
		var z := int(z_value)
		if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
			return {"ok": false, "error": "block_layout 格子越界: (%d,%d)" % [cell.x, cell.y]}
		if not _z_valid(z):
			return {"ok": false, "error": "block_layout.z 必须在 %d..%d" % [MIN_Z, MAX_Z]}
		if seen.has(cell):
			return {"ok": false, "error": "block_layout 格子重复: (%d,%d)" % [cell.x, cell.y]}
		seen[cell] = true
		out["cells"][cell.y * width + cell.x] = {"x": cell.x, "y": cell.y, "z": z}
	return {"ok": true, "layout": out}


static func validate(raw: Variant, width: int, height: int) -> String:
	var result := normalize(raw, width, height)
	return "" if bool(result.get("ok", false)) else String(result.get("error", ""))


static func z_at(layout: Dictionary, cell: Vector2i) -> int:
	var default_z := int(layout.get("default_z", DEFAULT_Z))
	var cells: Array = layout.get("cells", [])
	var index := cell.y * maxi(1, int(layout.get("width", 0))) + cell.x
	if index >= 0 and index < cells.size():
		var indexed: Variant = cells[index]
		if indexed is Dictionary and int(indexed.get("x", -1)) == cell.x and int(indexed.get("y", -1)) == cell.y:
			return int(indexed.get("z", default_z))
	for entry_value in cells:
		if entry_value is Dictionary and int(entry_value.get("x", -1)) == cell.x and int(entry_value.get("y", -1)) == cell.y:
			return int(entry_value.get("z", default_z))
	return default_z


static func set_z(layout: Dictionary, cell: Vector2i, z: int) -> bool:
	if not _z_valid(z):
		return false
	var cells: Array = layout.get("cells", [])
	for entry_value in cells:
		if entry_value is Dictionary and int(entry_value.get("x", -1)) == cell.x and int(entry_value.get("y", -1)) == cell.y:
			if int(entry_value.get("z", DEFAULT_Z)) == z:
				return false
			entry_value["z"] = z
			return true
	cells.append({"x": cell.x, "y": cell.y, "z": z})
	return true


static func _z_valid(z: int) -> bool:
	return z >= MIN_Z and z <= MAX_Z


static func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(float(value)) and float(value) == floorf(float(value))
