## region_clipboard.gd — 区域复制/剪切/粘贴/移动的五层数据内核
##
## 五层：地形 rows、块高 block_z、地块覆盖 tile_overrides、植物 props、单位 units。
## 所有坐标在 payload 内均相对区域左上角；只操作 Dictionary 模型，不依赖 UI/场景。

class_name EditorRegionClipboard
extends RefCounted

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const BlockLayoutScript = preload("res://scripts/core/block_layout.gd")

const PAYLOAD_VERSION := 1


## 校验闭区间 min_cell..max_cell 是否完整落在模型内；"" 表示合法。
static func bounds_error(model: Dictionary, min_cell: Vector2i, max_cell: Vector2i) -> String:
	var w := int(model.get("width", 0))
	var h := int(model.get("height", 0))
	if w <= 0 or h <= 0:
		return "模型尺寸无效"
	if min_cell.x > max_cell.x or min_cell.y > max_cell.y:
		return "区域左上角不能超过右下角"
	if min_cell.x < 0 or min_cell.y < 0 or max_cell.x >= w or max_cell.y >= h:
		return "区域越界：(%d,%d)..(%d,%d)，地图尺寸为 %d×%d" % [
			min_cell.x, min_cell.y, max_cell.x, max_cell.y, w, h]
	var rows_value: Variant = model.get("rows", null)
	if not (rows_value is Array) or (rows_value as Array).size() != h:
		return "模型地形行数与高度不符"
	for y in range(h):
		if String((rows_value as Array)[y]).length() != w:
			return "模型地形行宽与地图宽度不符"
	return ""


## 校验 payload 的五层 schema；"" 表示合法。
static func validate(payload: Dictionary) -> String:
	if not _is_integer(payload.get("version", null)) or int(payload.get("version", 0)) != PAYLOAD_VERSION:
		return "区域数据 version 必须为 1"
	var w_value: Variant = payload.get("w", null)
	var h_value: Variant = payload.get("h", null)
	if not _is_integer(w_value) or not _is_integer(h_value):
		return "区域数据 w/h 必须是整数"
	var w := int(w_value)
	var h := int(h_value)
	if w <= 0 or h <= 0:
		return "区域数据 w/h 必须大于 0"

	var rows_value: Variant = payload.get("rows", null)
	if not (rows_value is Array):
		return "区域数据 rows 必须是数组"
	var rows: Array = rows_value
	if rows.size() != h:
		return "区域数据 rows 行数必须等于 h"
	for y in range(h):
		if not (rows[y] is String):
			return "区域数据 rows 第 %d 行必须是字符串" % y
		var row := String(rows[y])
		if row.length() != w:
			return "区域数据 rows 第 %d 行长度必须等于 w" % y
		for glyph in row:
			if not BattlefieldDocScript.TERRAIN_GLYPH.values().has(glyph):
				return "区域数据含未知地形字符 '%s'" % glyph

	var heights_value: Variant = payload.get("block_z", null)
	if not (heights_value is Array):
		return "区域数据 block_z 必须是数组"
	var heights: Array = heights_value
	if heights.size() != w * h:
		return "区域数据 block_z 长度必须等于 w×h"
	for i in range(heights.size()):
		if not _is_integer(heights[i]):
			return "区域数据 block_z 第 %d 项必须是整数" % i
		var z := int(heights[i])
		if z < BlockLayoutScript.MIN_Z or z > BlockLayoutScript.MAX_Z:
			return "区域数据 block_z 第 %d 项超出 %d..%d" % [i, BlockLayoutScript.MIN_Z, BlockLayoutScript.MAX_Z]

	var overrides_value: Variant = payload.get("tile_overrides", null)
	if not (overrides_value is Dictionary):
		return "区域数据 tile_overrides 必须是对象"
	for key in (overrides_value as Dictionary).keys():
		var parsed := _parse_delta_key(String(key), w, h)
		if not bool(parsed.get("ok", false)):
			return String(parsed.get("error", "地块覆盖坐标无效"))
		var entry_value: Variant = (overrides_value as Dictionary)[key]
		if not (entry_value is Dictionary) or String((entry_value as Dictionary).get("asset_id", "")).is_empty():
			return "地块覆盖 %s 缺少 asset_id" % String(key)

	var props_value: Variant = payload.get("props", null)
	if not (props_value is Array):
		return "区域数据 props 必须是数组"
	var seen_props := {}
	for i in range((props_value as Array).size()):
		var entry_value: Variant = (props_value as Array)[i]
		if not (entry_value is Dictionary):
			return "区域数据 props 第 %d 项必须是对象" % i
		var entry: Dictionary = entry_value
		var cell_error := _delta_error(entry, w, h, "props 第 %d 项" % i)
		if not cell_error.is_empty():
			return cell_error
		var cell := Vector2i(int(entry.get("dx")), int(entry.get("dy")))
		if seen_props.has(cell):
			return "区域数据 props 在 (%d,%d) 重复" % [cell.x, cell.y]
		seen_props[cell] = true
		var texture := String(entry.get("texture", ""))
		var asset_id := String(entry.get("asset_id", ""))
		if texture.is_empty() and asset_id.is_empty():
			return "区域数据 props 第 %d 项缺少 texture/asset_id" % i
		if not texture.is_empty() and not asset_id.is_empty():
			return "区域数据 props 第 %d 项的 texture/asset_id 不能同时存在" % i

	var units_value: Variant = payload.get("units", null)
	if not (units_value is Array):
		return "区域数据 units 必须是数组"
	var seen_units := {}
	for i in range((units_value as Array).size()):
		var entry_value: Variant = (units_value as Array)[i]
		if not (entry_value is Dictionary):
			return "区域数据 units 第 %d 项必须是对象" % i
		var entry: Dictionary = entry_value
		var cell_error := _delta_error(entry, w, h, "units 第 %d 项" % i)
		if not cell_error.is_empty():
			return cell_error
		var cell := Vector2i(int(entry.get("dx")), int(entry.get("dy")))
		if seen_units.has(cell):
			return "区域数据 units 在 (%d,%d) 重叠" % [cell.x, cell.y]
		seen_units[cell] = true
		if String(entry.get("class", "")).is_empty():
			return "区域数据 units 第 %d 项缺少 class" % i
		if not _is_integer(entry.get("level", null)) or int(entry.get("level", 0)) < 1:
			return "区域数据 units 第 %d 项 level 必须是正整数" % i
		var faction := String(entry.get("faction", ""))
		if faction != "player" and faction != "enemy":
			return "区域数据 units 第 %d 项 faction 必须是 player/enemy" % i
		for field in ["name", "tag"]:
			if entry.has(field) and not (entry[field] is String):
				return "区域数据 units 第 %d 项 %s 必须是字符串" % [i, field]
	return ""


## 提取闭区间区域；坐标全部相对 min_cell。边界非法时返回 {}。
static func extract(model: Dictionary, min_cell: Vector2i, max_cell: Vector2i) -> Dictionary:
	if not bounds_error(model, min_cell, max_cell).is_empty():
		return {}
	var w := max_cell.x - min_cell.x + 1
	var h := max_cell.y - min_cell.y + 1
	var rows: Array[String] = []
	var block_z: Array[int] = []
	var tile_overrides := {}
	for dy in range(h):
		var row := ""
		for dx in range(w):
			var source := min_cell + Vector2i(dx, dy)
			row += String(model.rows[source.y]).substr(source.x, 1)
			block_z.append(BattlefieldDocScript.cell_z(model, source))
			var asset_id := BattlefieldDocScript.tile_override_at(model, source)
			if not asset_id.is_empty():
				tile_overrides["%d,%d" % [dx, dy]] = {"asset_id": asset_id}
		rows.append(row)

	var props: Array = []
	for prop_value in model.get("props", []):
		if not (prop_value is Dictionary):
			continue
		var prop: Dictionary = prop_value
		var cell := Vector2i(int(prop.get("x", -1)), int(prop.get("y", -1)))
		if not _in_rect(cell, min_cell, max_cell):
			continue
		var entry := {"dx": cell.x - min_cell.x, "dy": cell.y - min_cell.y}
		var asset_id := String(prop.get("asset_id", ""))
		var texture := String(prop.get("texture", ""))
		if not asset_id.is_empty():
			entry["asset_id"] = asset_id
		elif not texture.is_empty():
			entry["texture"] = texture
		else:
			continue
		props.append(entry)

	var units: Array = []
	for unit_value in model.get("units", []):
		if not (unit_value is Dictionary):
			continue
		var unit: Dictionary = unit_value
		var cell := Vector2i(int(unit.get("x", -1)), int(unit.get("y", -1)))
		if not _in_rect(cell, min_cell, max_cell):
			continue
		units.append({
			"dx": cell.x - min_cell.x,
			"dy": cell.y - min_cell.y,
			"class": String(unit.get("class", "")),
			"name": String(unit.get("name", "")),
			"level": int(unit.get("level", 1)),
			"faction": String(unit.get("faction", "player")),
			"tag": String(unit.get("tag", "")),
		})
	return {
		"version": PAYLOAD_VERSION,
		"w": w,
		"h": h,
		"rows": rows,
		"block_z": block_z,
		"tile_overrides": tile_overrides,
		"props": props,
		"units": units,
	}


## 将 payload 整体写入 origin 为左上角的矩形；目标矩形内旧 props/units 被替换。
## 返回 {ok,error,dropped_units,no_op}；不可站人地形上的单位丢弃并计数。
static func write(model: Dictionary, payload: Dictionary, origin: Vector2i) -> Dictionary:
	var payload_error := validate(payload)
	if not payload_error.is_empty():
		return _failure(payload_error)
	var size := payload_size(payload)
	var max_cell := origin + size - Vector2i.ONE
	var boundary_error := bounds_error(model, origin, max_cell)
	if not boundary_error.is_empty():
		return _failure(boundary_error)

	_remove_entities(model, origin, max_cell)
	var rows: Array = model.rows
	for dy in range(size.y):
		for dx in range(size.x):
			var target := origin + Vector2i(dx, dy)
			var glyph := String(payload.rows[dy]).substr(dx, 1)
			var row := String(rows[target.y])
			rows[target.y] = row.substr(0, target.x) + glyph + row.substr(target.x + 1)
			BattlefieldDocScript.set_cell_z(model, target, int(payload.block_z[dy * size.x + dx]))
			var override_entry: Dictionary = payload.tile_overrides.get("%d,%d" % [dx, dy], {})
			BattlefieldDocScript.set_tile_override(model, target, String(override_entry.get("asset_id", "")))

	for prop_value in payload.props:
		var prop: Dictionary = prop_value
		var target := origin + Vector2i(int(prop.dx), int(prop.dy))
		var asset_id := String(prop.get("asset_id", ""))
		if not asset_id.is_empty():
			BattlefieldDocScript.set_prop_asset(model, target, asset_id)
		else:
			BattlefieldDocScript.set_prop(model, target, String(prop.get("texture", "")))

	var dropped_units := 0
	for unit_value in payload.units:
		var unit: Dictionary = unit_value
		var target := origin + Vector2i(int(unit.dx), int(unit.dy))
		var glyph := String(model.rows[target.y]).substr(target.x, 1)
		var terrain := BattlefieldDocScript.glyph_to_terrain(glyph)
		if not BattlefieldLoaderScript._is_standable(terrain):
			dropped_units += 1
			continue
		(model.units as Array).append({
			"class": String(unit.get("class", "")),
			"name": String(unit.get("name", "")),
			"level": int(unit.get("level", 1)),
			"x": target.x,
			"y": target.y,
			"faction": String(unit.get("faction", "player")),
			"tag": String(unit.get("tag", "")),
		})
	return _ok(dropped_units)


## 清空区域：地形回平原、高度回模型 default_z、清除覆盖并删除 props/units。
static func clear_rect(model: Dictionary, min_cell: Vector2i, max_cell: Vector2i) -> Dictionary:
	var boundary_error := bounds_error(model, min_cell, max_cell)
	if not boundary_error.is_empty():
		return _failure(boundary_error)
	var layout: Dictionary = model.get("block_layout", {})
	var default_z := int(layout.get("default_z", BlockLayoutScript.DEFAULT_Z))
	_remove_entities(model, min_cell, max_cell)
	var rows: Array = model.rows
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			var target := Vector2i(x, y)
			var row := String(rows[y])
			rows[y] = row.substr(0, x) + "." + row.substr(x + 1)
			BattlefieldDocScript.set_cell_z(model, target, default_z)
			BattlefieldDocScript.set_tile_override(model, target, "")
	return _ok()


## 粘贴等价于一次带完整预校验的整体 write。
static func paste(model: Dictionary, payload: Dictionary, origin: Vector2i) -> Dictionary:
	return write(model, payload, origin)


## 移动闭区间源区域到 src_min+delta；源/目标全部预检后才改动模型。
static func move(model: Dictionary, src_min: Vector2i, src_max: Vector2i, delta: Vector2i) -> Dictionary:
	var boundary_error := bounds_error(model, src_min, src_max)
	if not boundary_error.is_empty():
		return _failure(boundary_error)
	var payload := extract(model, src_min, src_max)
	var payload_error := validate(payload)
	if not payload_error.is_empty():
		return _failure(payload_error)
	var destination := src_min + delta
	var destination_max := src_max + delta
	boundary_error = bounds_error(model, destination, destination_max)
	if not boundary_error.is_empty():
		return _failure(boundary_error)
	if delta == Vector2i.ZERO:
		return _ok(0, true)
	var cleared := clear_rect(model, src_min, src_max)
	if not bool(cleared.get("ok", false)):
		return cleared
	return write(model, payload, destination)


static func payload_size(payload: Dictionary) -> Vector2i:
	return Vector2i(int(payload.get("w", 0)), int(payload.get("h", 0)))


static func describe(payload: Dictionary) -> String:
	var size := payload_size(payload)
	var units: Array = payload.get("units", []) if payload.get("units", []) is Array else []
	var props: Array = payload.get("props", []) if payload.get("props", []) is Array else []
	var overrides: Dictionary = payload.get("tile_overrides", {}) if payload.get("tile_overrides", {}) is Dictionary else {}
	return "%d×%d 区域 · 单位 %d · 植物 %d · 地块覆盖 %d" % [
		size.x, size.y, units.size(), props.size(), overrides.size()]


static func _remove_entities(model: Dictionary, min_cell: Vector2i, max_cell: Vector2i) -> void:
	var units: Array = model.get("units", [])
	for i in range(units.size() - 1, -1, -1):
		var unit: Dictionary = units[i]
		if _in_rect(Vector2i(int(unit.get("x", -1)), int(unit.get("y", -1))), min_cell, max_cell):
			units.remove_at(i)
	var props: Array = model.get("props", [])
	for i in range(props.size() - 1, -1, -1):
		var prop: Dictionary = props[i]
		if _in_rect(Vector2i(int(prop.get("x", -1)), int(prop.get("y", -1))), min_cell, max_cell):
			props.remove_at(i)


static func _in_rect(cell: Vector2i, min_cell: Vector2i, max_cell: Vector2i) -> bool:
	return cell.x >= min_cell.x and cell.y >= min_cell.y and cell.x <= max_cell.x and cell.y <= max_cell.y


static func _delta_error(entry: Dictionary, w: int, h: int, label: String) -> String:
	if not _is_integer(entry.get("dx", null)) or not _is_integer(entry.get("dy", null)):
		return "区域数据 %s 的 dx/dy 必须是整数" % label
	var dx := int(entry.get("dx"))
	var dy := int(entry.get("dy"))
	if dx < 0 or dy < 0 or dx >= w or dy >= h:
		return "区域数据 %s 坐标越界: (%d,%d)" % [label, dx, dy]
	return ""


static func _parse_delta_key(key: String, w: int, h: int) -> Dictionary:
	var parts := key.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return {"ok": false, "error": "地块覆盖键必须是 \"dx,dy\": %s" % key}
	var cell := Vector2i(int(parts[0]), int(parts[1]))
	if cell.x < 0 or cell.y < 0 or cell.x >= w or cell.y >= h:
		return {"ok": false, "error": "地块覆盖坐标越界: %s" % key}
	return {"ok": true, "cell": cell}


static func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(float(value)) and float(value) == floorf(float(value))


static func _ok(dropped_units: int = 0, no_op: bool = false) -> Dictionary:
	return {"ok": true, "error": "", "dropped_units": dropped_units, "no_op": no_op}


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "dropped_units": 0, "no_op": false}
