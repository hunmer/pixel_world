## core/building_layout.gd — 建筑占用派生与文档校验（纯逻辑，编辑器保存与战场加载共用）
##
## 建筑在文档中是单实例条目 buildings=[{instance_id,asset_id,x,y,rotation}]，
## 占用格由素材 descriptor.render.footprint{w,h} 派生（不逐格复制贴图）：
##   - entry.x/y 即「旋转后包围矩形」的左上格（编辑器放置时即按此语义落点）
##   - rotation 为 0..3（90°步），奇数时占用矩形交换 w/h
##   - footprint 缺失/非法时回退 1x1 并 push_warning（引用不丢失，加载不中断）
## 校验规则（编辑器保存与 loader 共用）：
##   instance_id 非空且唯一 / asset_id 非空 / rotation 整数 0..3 /
##   旋转后矩形全格界内 / 建筑间不允许重叠 / 不与既有占用（单位、增援落点）冲突。

class_name BuildingLayout
extends RefCounted

## 占用矩形边长上限（与素材契约 render.footprint 1..8 一致）
const MAX_FOOTPRINT: int = 8
const Interior = preload("res://scripts/core/building_interior.gd")


## 归一化占用 key："x,y"（与 GridSystem._key 一致；occupied 可传 Vector2i 或 String key）
static func cell_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


## JSON 整值转换：int 或整值 float → int；其他（1.5/字符串/null…）返回 null。
## JSON.parse_string 把磁盘数字统一解析为 float，入口须接受 1.0、拒绝 1.5。
static func as_json_int(v: Variant) -> Variant:
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT and is_finite(v) and float(int(v)) == v:
		return int(v)
	return null


## 读取 entry 的旋转后占用矩形尺寸；rotation 奇数时交换 w/h。
## footprint 缺失/非法回退 (1,1) 并 push_warning（素材快照不完整时保证可用）。
static func footprint_size(entry: Dictionary, assets: Dictionary) -> Vector2i:
	var size := Vector2i(1, 1)
	var asset_id := String(entry.get("asset_id", ""))
	if assets.has(asset_id):
		var descriptor: Dictionary = assets[asset_id]
		var render: Dictionary = descriptor.get("render", {})
		var footprint: Dictionary = render.get("footprint", {})
		var w_value: Variant = as_json_int(footprint.get("w", 1))
		var h_value: Variant = as_json_int(footprint.get("h", 1))
		if w_value == null or h_value == null:
			push_warning("[building_layout] 素材 %s footprint 非整数(%s,%s)，回退 1x1" % [
				asset_id, str(footprint.get("w", 1)), str(footprint.get("h", 1))])
		else:
			var w := int(w_value)
			var h := int(h_value)
			if w < 1 or h < 1 or w > MAX_FOOTPRINT or h > MAX_FOOTPRINT:
				push_warning("[building_layout] 素材 %s footprint 非法(%d,%d)，回退 1x1" % [asset_id, w, h])
			else:
				size = Vector2i(w, h)
	else:
		push_warning("[building_layout] 素材 %s 不在快照中，占用回退 1x1" % asset_id)
	var rotation_value: Variant = as_json_int(entry.get("rotation", 0))
	var rotation := 0 if rotation_value == null else int(rotation_value)
	rotation = rotation & 3
	if rotation == 1 or rotation == 3:
		return Vector2i(size.y, size.x)
	return size


## 单个建筑占用的全部格子：以 entry.x/y 为旋转后矩形左上格，展开 w×h。
## 纯派生：不裁界（越界由 validate_entries 拒绝）、不查重叠。
static func occupied_cells(entry: Dictionary, assets: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var size := footprint_size(entry, assets)
	var x := int(entry.get("x", 0))
	var y := int(entry.get("y", 0))
	for dy in range(size.y):
		for dx in range(size.x):
			cells.append(Vector2i(x + dx, y + dy))
	return cells


## 批量占用映射：{"x,y" -> instance_id}。
## 同格被多建筑覆盖时保留先到者（重叠属非法，应由 validate_entries 拒绝；此处不抛错）。
static func occupancy(entries: Array, assets: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for e in entries:
		var entry: Dictionary = e
		var instance_id := String(entry.get("instance_id", ""))
		for cell in occupied_cells(entry, assets):
			var k := cell_key(cell.x, cell.y)
			if not result.has(k):
				result[k] = instance_id
	return result


## 与 footprint 占地分离：旧建筑全阻挡，可进入建筑仅墙/家具阻挡。
static func blocking_cells(entry: Dictionary, assets: Dictionary) -> Array[Vector2i]:
	var descriptor: Dictionary = assets.get(String(entry.get("asset_id", "")), {})
	if Interior.enabled(descriptor):
		var render: Dictionary = descriptor.get("render", {})
		if Interior.validate(render.get("interior"), render.get("footprint", {})).is_empty():
			return Interior.blocking_cells(entry, descriptor)
	return occupied_cells(entry, assets)


static func blocking_occupancy(entries: Array, assets: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in entries:
		for cell: Vector2i in blocking_cells(entry, assets):
			result[cell_key(cell.x, cell.y)] = String(entry.get("instance_id", ""))
	return result


## 归一化既有占用集合的 key（接受 Vector2i key 或 "x,y" 字符串 key 的 Dictionary）。
static func _occupied_has(occupied: Dictionary, cell: Vector2i) -> bool:
	var k := cell_key(cell.x, cell.y)
	if occupied.has(k):
		return true
	return occupied.has(cell)


## 校验建筑条目列表。返回错误消息（空串 = 合法）。
## width/height 为战场尺寸；occupied 为既有占用（单位位置、增援落点等），
## key 为 Vector2i 或 "x,y" 字符串。
static func validate_entries(
	entries: Array, width: int, height: int, assets: Dictionary, occupied: Dictionary
) -> String:
	var seen_ids: Dictionary = {}
	var seen_cells: Dictionary = {}
	var index := 0
	for e in entries:
		var entry: Dictionary = e
		var label := String(entry.get("instance_id", ""))
		if label.is_empty():
			label = "#%d" % index
		# instance_id 非空且唯一
		var instance_id := String(entry.get("instance_id", ""))
		if instance_id.is_empty():
			return "建筑 %s 缺 instance_id" % label
		if seen_ids.has(instance_id):
			return "建筑 instance_id 重复: %s" % instance_id
		seen_ids[instance_id] = true
		# asset_id 非空
		var asset_id := String(entry.get("asset_id", ""))
		if asset_id.is_empty():
			return "建筑 %s 缺 asset_id" % instance_id
		var descriptor: Dictionary = assets.get(asset_id, {})
		var render: Dictionary = descriptor.get("render", {})
		if render.has("interior"):
			var interior_error: String = Interior.validate(render["interior"], render.get("footprint", {}))
			if not interior_error.is_empty():
				return "建筑 %s %s" % [instance_id, interior_error]
		# rotation 整数 0..3（接受 JSON 整值 float：1.0 合法、1.5 拒绝）
		var rotation_value: Variant = as_json_int(entry.get("rotation", 0))
		if rotation_value == null:
			return "建筑 %s rotation 必须是整数" % instance_id
		var rotation := int(rotation_value)
		if rotation < 0 or rotation > 3:
			return "建筑 %s rotation 越界: %d（0..3）" % [instance_id, rotation]
		# x/y 整数（同上接受整值 float）
		var x_value: Variant = as_json_int(entry.get("x", null))
		var y_value: Variant = as_json_int(entry.get("y", null))
		if x_value == null or y_value == null:
			return "建筑 %s x/y 必须是整数" % instance_id
		# 旋转后矩形全格界内 + 不重叠 + 不与既有占用冲突
		var blocked: Array[Vector2i] = blocking_cells(entry, assets)
		var cells := occupied_cells(entry, assets)
		for cell in cells:
			if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
				return "建筑 %s 占用越界 (%d,%d) 界外于 %dx%d" % [
					instance_id, cell.x, cell.y, width, height
				]
			var k := cell_key(cell.x, cell.y)
			if seen_cells.has(k):
				return "建筑 %s 与 %s 占用重叠于 (%d,%d)" % [
					instance_id, String(seen_cells[k]), cell.x, cell.y
				]
			if blocked.has(cell) and _occupied_has(occupied, cell):
				return "建筑 %s 占用 (%d,%d) 与单位/增援冲突" % [instance_id, cell.x, cell.y]
			seen_cells[k] = instance_id
		index += 1
	return ""


## 进入式房屋必须整体位于同一实际站立高度；不替换底层地形通行属性。
static func validate_interior_ground(entries: Array, assets: Dictionary, level_for_cell: Callable) -> String:
	for entry: Dictionary in entries:
		if not Interior.enabled(assets.get(String(entry.get("asset_id", "")), {})):
			continue
		var first: Variant = null
		for cell: Vector2i in occupied_cells(entry, assets):
			var level: int = int(level_for_cell.call(cell))
			if first == null:
				first = level
			elif int(first) != level:
				return "可进入建筑 %s 底面站立高度不等" % String(entry.get("instance_id", "?"))
	return ""
