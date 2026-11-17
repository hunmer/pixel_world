## building_interior.gd — 单层建筑室内 schema 与局部格旋转（纯逻辑）。
class_name BuildingInterior
extends RefCounted

const ALLOWED := ".#DF"

static func enabled(descriptor: Dictionary) -> bool:
	var interior: Variant = descriptor.get("render", {}).get("interior", null)
	return interior is Dictionary and interior.get("enabled", false) == true


static func validate(raw: Variant, footprint: Dictionary) -> String:
	if not raw is Dictionary:
		return "render.interior 必须是对象"
	var interior: Dictionary = raw
	if typeof(interior.get("enabled", null)) != TYPE_BOOL:
		return "interior.enabled 必须是布尔值"
	if not bool(interior["enabled"]):
		return ""
	for key: String in ["w", "h"]:
		var value: Variant = footprint.get(key, null)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floorf(float(value)) or float(value) < 3 or float(value) > 8:
			return "interior footprint必须为3..8整数尺寸"
	var w: int = int(footprint.get("w", 0))
	var h: int = int(footprint.get("h", 0))
	var rows_value: Variant = interior.get("rows", null)
	if not rows_value is Array or rows_value.size() != h or w < 3 or h < 3:
		return "interior.rows 必须与 footprint 尺寸一致，且至少3x3"
	var rows: Array = rows_value
	var doors: Array[Vector2i] = []
	var walkable: Dictionary = {}
	for y: int in h:
		if not rows[y] is String or rows[y].length() != w:
			return "interior.rows 每行必须是与 footprint 宽度一致的字符串"
		for x: int in w:
			var glyph: String = rows[y].substr(x, 1)
			if not ALLOWED.contains(glyph):
				return "interior.rows 只允许 . # D F"
			var edge: bool = x == 0 or y == 0 or x == w - 1 or y == h - 1
			if edge and glyph not in ["#", "D"]:
				return "interior 边界必须为墙或门"
			if glyph == "D":
				if not edge or ((x == 0 or x == w - 1) and (y == 0 or y == h - 1)):
					return "interior 门必须位于非角落边界"
				doors.append(Vector2i(x, y))
			if glyph in [".", "D"]:
				walkable[Vector2i(x, y)] = true
	if doors.is_empty():
		return "interior 至少需要一个边界门"
	var visited: Dictionary = {doors[0]: true}
	var queue: Array[Vector2i] = [doors[0]]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + offset
			if walkable.has(next) and not visited.has(next):
				visited[next] = true
				queue.append(next)
	if visited.size() != walkable.size() or walkable.size() <= doors.size():
		return "interior 所有室内通路必须连通到门且有室内地板"
	for key: String in ["reveal_zoom", "hide_zoom"]:
		var value: Variant = interior.get(key, null)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.5 or float(value) > 4.0:
			return "interior.%s 必须是0.5..4.0的有限数字" % key
	if float(interior["hide_zoom"]) >= float(interior["reveal_zoom"]):
		return "interior.hide_zoom 必须小于 reveal_zoom"
	return ""


## entry x/y 为旋转后矩形左上角；局部原点为未旋转布局左上角。
static func cell_at(entry: Dictionary, local: Vector2i, size: Vector2i) -> Vector2i:
	var rotated: Vector2i = local
	match posmod(int(entry.get("rotation", 0)), 4):
		1: rotated = Vector2i(size.y - 1 - local.y, local.x)
		2: rotated = Vector2i(size.x - 1 - local.x, size.y - 1 - local.y)
		3: rotated = Vector2i(local.y, size.x - 1 - local.x)
	return Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0))) + rotated


static func blocking_cells(entry: Dictionary, descriptor: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var render: Dictionary = descriptor.get("render", {})
	var footprint: Dictionary = render.get("footprint", {})
	var interior: Dictionary = render.get("interior", {})
	if not enabled(descriptor) or not validate(interior, footprint).is_empty():
		return result
	var size := Vector2i(int(footprint["w"]), int(footprint["h"]))
	var rows: Array = interior["rows"]
	for y: int in size.y:
		for x: int in size.x:
			if rows[y].substr(x, 1) in ["#", "F"]:
				result.append(cell_at(entry, Vector2i(x, y), size))
	return result
