extends RefCounted
## iso_projection_3d.gd — 主世界/战棋共享的 2:1 dimetric 3D 坐标与射线投影。

const TILE_PIXELS := 32.0
const TILE_HEIGHT_PIXELS := 16.0
const LEVEL_PIXELS := 10.0
const CAMERA_YAW := PI * 0.25
const CAMERA_ELEVATION := PI / 6.0
# 等宽 X/Z 方格在 yaw=45°、pitch=30° 下保持 32×16 像素菱形。
const GRID_STEP := 0.7071067811865476
const LEVEL_HEIGHT := 0.3608439182435161


static func grid_to_world(cell: Vector2i, level: float = 0.0) -> Vector3:
	return Vector3(
		float(cell.x) * GRID_STEP,
		level * LEVEL_HEIGHT,
		float(cell.y) * GRID_STEP
	)


static func visual_to_world(visual_position: Vector2, level: float = 0.0) -> Vector3:
	return Vector3(
		visual_position.x * GRID_STEP,
		level * LEVEL_HEIGHT,
		visual_position.y * GRID_STEP
	)


static func world_to_grid_position(point: Vector3) -> Vector2:
	return Vector2(point.x / GRID_STEP, point.z / GRID_STEP)


static func world_to_grid(point: Vector3) -> Vector2i:
	var continuous := world_to_grid_position(point)
	return Vector2i(roundi(continuous.x), roundi(continuous.y))


static func screen_to_world(
	camera: Camera3D,
	screen_position: Vector2,
	level: float = 0.0
) -> Variant:
	if camera == null or not camera.is_inside_tree():
		return null
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.00001:
		return null
	var distance := (level * LEVEL_HEIGHT - origin.y) / direction.y
	if distance < 0.0:
		return null
	return origin + direction * distance


static func screen_to_grid(
	camera: Camera3D,
	screen_position: Vector2,
	level: float = 0.0
) -> Variant:
	var point: Variant = screen_to_world(camera, screen_position, level)
	if point == null:
		return null
	return world_to_grid_position(point as Vector3)


## 用真实射线与各柱顶平面求交；命中方格顶面后取离相机最近的交点。
## level_for_cell 返回该格实际站立层；valid_cell 可选，用来限制战场/矩形边界。
static func pick_top_face(
	camera: Camera3D,
	screen_position: Vector2,
	min_level: int,
	max_level: int,
	level_for_cell: Callable,
	valid_cell: Callable = Callable()
) -> Dictionary:
	var empty: Dictionary = {}
	if camera == null or not camera.is_inside_tree() or not level_for_cell.is_valid():
		return empty
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.00001:
		return empty
	var best: Dictionary = {}
	var best_distance := INF
	for level in range(min_level, max_level + 1):
		var distance := (float(level) * LEVEL_HEIGHT - origin.y) / direction.y
		if distance < 0.0 or distance >= best_distance:
			continue
		var point := origin + direction * distance
		var continuous := world_to_grid_position(point)
		# 方格顶面以整数格为中心；显式取最近格，避免 Vector2i 隐式截断。
		var cell := Vector2i(floori(continuous.x + 0.5), floori(continuous.y + 0.5))
		if valid_cell.is_valid() and not bool(valid_cell.call(cell)):
			continue
		var actual_level := float(level_for_cell.call(cell))
		if not is_equal_approx(actual_level, float(level)):
			continue
		var center := grid_to_world(cell, actual_level)
		var half := GRID_STEP * 0.5 + 0.00001
		if absf(point.x - center.x) > half or absf(point.z - center.z) > half:
			continue
		best_distance = distance
		best = {
			"cell": cell,
			"world_position": point,
			"distance": distance,
			"level": level,
		}
	return best


static func world_to_screen(camera: Camera3D, point: Vector3) -> Vector2:
	if camera == null or not camera.is_inside_tree():
		return Vector2.ZERO
	return camera.unproject_position(point)


static func grid_to_screen(
	camera: Camera3D,
	cell: Vector2i,
	level: float = 0.0
) -> Vector2:
	return world_to_screen(camera, grid_to_world(cell, level))
