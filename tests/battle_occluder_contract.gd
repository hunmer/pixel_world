extends SceneTree

## tests/battle_occluder_contract.gd — 沉浸战斗遮挡契约（BattleOccluder 几何 + IsometricTerrain3D 柱隐藏/淡化锁定）
## 运行：D:/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/battle_occluder_contract.gd
## 覆盖：前方柱选中 / 背后与两端豁免 / 侧偏不选 / 顶部低于视线不选 / prop 分流 / 单位脚下豁免与
##       距离变化 / 空 participants / 相机≈单位 / 相机移动集合变化 / MAX_SPAN 收缩 /
##       terrain 数据→compute 集成 / 柱隐藏→恢复幂等 / 淡化锁定存在性幂等 / clear 重置。
## 不依赖 autoload 与渲染（不调 flush/_rebuild_chunk）；渲染层（chunk 跳过重建、fade 代理节点、
## main.gd 0.5s 写竞争实测）由真实启动 + "[ImmersiveCamera] Occlusion" 日志验证覆盖。

const BattleOccluderScript = preload("res://scripts/iso/battle_occluder.gd")
const Terrain3DScript = preload("res://scripts/iso/isometric_terrain_3d.gd")
const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")

## 几何标定：CAM→UNIT 是沿 +Z 的水平视线，长 12；格 (0,g) 柱心 world=(0, top, g*GRID_STEP)。
## 格心 z 与 along（离相机的水平距）对照：g=-7→z=-4.9497→along=1.0503；g=-8→along=0.3431；
## g=-2→along=4.5858；g=-3→along=3.8787；g=-4→along=3.1716；g=8→along=11.6569；g=9→along=12.3640。
const CAM := Vector3(0.0, 3.0, -6.0)
const UNIT := Vector3(0.0, 1.0, 6.0)

var failures: Array[String] = []
var checks := 0
var _query_calls := 0
var _last_bounds: Array = []


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


## 构造柱候选（center.y 即柱顶世界高度；BattleOccluder 只用 center.x/z 与 top）。
func _col(cell: Vector2i, top: float) -> Dictionary:
	return {
		"cell": cell,
		"center": Vector3(cell.x * IsoProjection.GRID_STEP, top, cell.y * IsoProjection.GRID_STEP),
		"top": top,
		"prop": false,
	}


func _prop(cell: Vector2i, top: float) -> Dictionary:
	var item := _col(cell, top)
	item["prop"] = true
	return item


## 模拟 immersive_camera._query_occlusion_candidates 的有界枚举，并记录调用与 bounds。
func _make_query(candidates: Array) -> Callable:
	return func(bounds_min: Vector2i, bounds_max: Vector2i) -> Array:
		_query_calls += 1
		_last_bounds = [bounds_min, bounds_max]
		var out: Array = []
		for item_value in candidates:
			var item: Dictionary = item_value
			var cell: Vector2i = item["cell"]
			if cell.x >= bounds_min.x and cell.x <= bounds_max.x and cell.y >= bounds_min.y and cell.y <= bounds_max.y:
				out.append(item)
		return out


func _has_cell(cells: Array, cell: Vector2i) -> bool:
	for cell_value in cells:
		if (cell_value as Vector2i) == cell:
			return true
	return false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_front_column_selected()
	_test_behind_and_endpoints_excluded()
	_test_lateral_offset_excluded()
	_test_low_top_excluded()
	_test_prop_routing()
	_test_foot_radius_exempt_and_distance_change()
	_test_empty_participants()
	_test_camera_equals_unit()
	_test_camera_move_changes_set()
	_test_max_span_clamped()
	_test_terrain_data_to_compute()
	_test_column_hidden_roundtrip()
	_test_prop_fade_hold()
	_test_clear_resets_hidden_and_holds()
	if failures.is_empty():
		print("BATTLE_OCCLUDER_CONTRACT PASS checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		print("BATTLE_OCCLUDER_CONTRACT FAIL checks=%d failures=%d" % [checks, failures.size()])
		quit(1)


## T1 前方高柱挡住视线：along=1.0503 在段内，垂距 0，ray 高度≈2.8249，top=3 遮得住 → 选中。
func _test_front_column_selected() -> void:
	var result: Dictionary = BattleOccluderScript.compute(
		CAM, [UNIT], _make_query([_col(Vector2i(0, -7), 3.0)])
	)
	_expect(result["columns"].size() == 1, "T1 前方柱应恰好选中 1 格")
	_expect(_has_cell(result["columns"], Vector2i(0, -7)), "T1 前方柱 (0,-7) 应在 columns")
	_expect(result["props"].is_empty(), "T1 无 prop 候选时 props 应为空")


## T2 背后与两端豁免：相机脚下(along<=CAPTURE)、单位身上/背后(along>=len-margin)都不选；
## 附带断言这些格都在 query 的 bounds 内——证明是几何排除而非枚举遗漏。
func _test_behind_and_endpoints_excluded() -> void:
	_query_calls = 0
	var result: Dictionary = BattleOccluderScript.compute(
		CAM,
		[UNIT],
		_make_query([
			_col(Vector2i(0, -8), 5.0),
			_col(Vector2i(0, 9), 5.0),
			_col(Vector2i(0, 10), 5.0),
		])
	)
	_expect(result["columns"].is_empty(), "T2 相机脚下 (0,-8)/单位身后 (0,9)(0,10) 均不应选中")
	_expect(_query_calls == 1, "T2 单位视线只应查询一次")
	_expect(_last_bounds.size() == 2, "T2 应记录 bounds")
	var bounds_min: Vector2i = _last_bounds[0]
	var bounds_max: Vector2i = _last_bounds[1]
	for excluded in [Vector2i(0, -8), Vector2i(0, 9), Vector2i(0, 10)]:
		var cell: Vector2i = excluded
		_expect(
			cell.x >= bounds_min.x and cell.x <= bounds_max.x and cell.y >= bounds_min.y and cell.y <= bounds_max.y,
			"T2 豁免格 %s 应在 query bounds 内（证明为几何排除）" % [cell]
		)


## T3 侧偏不选：柱心离视线水平距 1.4142 > CAPTURE_RADIUS(≈0.3889)。
func _test_lateral_offset_excluded() -> void:
	var result: Dictionary = BattleOccluderScript.compute(
		CAM, [UNIT], _make_query([_col(Vector2i(2, -2), 5.0)])
	)
	_expect(result["columns"].is_empty(), "T3 侧偏一格的柱不应选中")


## T4 顶部低于视线不选：along=4.5858 处视线高≈2.2357，top=1.5 遮不住单位中心。
func _test_low_top_excluded() -> void:
	var result: Dictionary = BattleOccluderScript.compute(
		CAM, [UNIT], _make_query([_col(Vector2i(0, -2), 1.5)])
	)
	_expect(result["columns"].is_empty(), "T4 低柱（top 低于视线）不应选中")


## T5 prop 分流：同高度的柱与植物，柱进 columns、植物进 props，互不混。
func _test_prop_routing() -> void:
	var result: Dictionary = BattleOccluderScript.compute(
		CAM,
		[UNIT],
		_make_query([_prop(Vector2i(0, -3), 2.5), _col(Vector2i(0, -4), 2.5)])
	)
	_expect(result["columns"].size() == 1 and _has_cell(result["columns"], Vector2i(0, -4)), "T5 柱 (0,-4) 应在 columns")
	_expect(result["props"].size() == 1 and _has_cell(result["props"], Vector2i(0, -3)), "T5 植物 (0,-3) 应在 props")


## T6 单位脚下豁免：距单位水平距 0.3431 <= FOOT_RADIUS(≈0.3536) 不隐藏；
## 单位移远后（距离 1.3431 > 豁免半径）同一格被选中——同时覆盖"距离变化集合变化"。
func _test_foot_radius_exempt_and_distance_change() -> void:
	var near_unit := Vector3(0.0, 1.0, 6.0)
	var result_near: Dictionary = BattleOccluderScript.compute(
		CAM, [near_unit], _make_query([_col(Vector2i(0, 8), 5.0)])
	)
	_expect(result_near["columns"].is_empty(), "T6 单位脚下柱 (0,8) 应豁免")

	var far_unit := Vector3(0.0, 1.0, 7.0)
	var result_far: Dictionary = BattleOccluderScript.compute(
		CAM, [far_unit], _make_query([_col(Vector2i(0, 8), 5.0)])
	)
	_expect(
		result_far["columns"].size() == 1 and _has_cell(result_far["columns"], Vector2i(0, 8)),
		"T6 单位移远后脚下柱 (0,8) 应回到选中集合"
	)


## T7 空 participants：不崩、空集合、不触发任何查询。
func _test_empty_participants() -> void:
	_query_calls = 0
	var result: Dictionary = BattleOccluderScript.compute(CAM, [], _make_query([_col(Vector2i(0, -7), 3.0)]))
	_expect(result["columns"].is_empty() and result["props"].is_empty(), "T7 空 participants 应返回空集合")
	_expect(_query_calls == 0, "T7 空 participants 不应触发 query")


## T8 相机≈单位：ground_length<0.01 直接跳过。
func _test_camera_equals_unit() -> void:
	_query_calls = 0
	var result: Dictionary = BattleOccluderScript.compute(CAM, [CAM], _make_query([_col(Vector2i(0, -7), 3.0)]))
	_expect(result["columns"].is_empty(), "T8 相机≈单位应返回空集合")
	_expect(_query_calls == 0, "T8 相机≈单位不应触发 query")


## T9 相机移动（等价于 yaw 变化）集合变化：视线从 +Z 转到左前对角，
## 原选中 (0,-7) 垂距 4.897 出局，新视线上 (4,0)（垂距 0.153）入选。
func _test_camera_move_changes_set() -> void:
	var candidates := [_col(Vector2i(0, -7), 3.0), _col(Vector2i(4, 0), 3.0)]
	var before: Dictionary = BattleOccluderScript.compute(CAM, [UNIT], _make_query(candidates))
	var after: Dictionary = BattleOccluderScript.compute(
		Vector3(6.0, 3.0, -6.0), [UNIT], _make_query(candidates)
	)
	_expect(
		before["columns"].size() == 1 and _has_cell(before["columns"], Vector2i(0, -7)),
		"T9 移动前应选中 (0,-7)"
	)
	_expect(
		after["columns"].size() == 1 and _has_cell(after["columns"], Vector2i(4, 0)),
		"T9 移动后应只选中新视线上 (4,0)"
	)
	_expect(not _has_cell(after["columns"], Vector2i(0, -7)), "T9 移动后 (0,-7) 不应残留")


## T10 MAX_SPAN 收缩：跨 100 世界单位的视线格跨度 144 > 64，向中点收缩到恰 64；
## 超界格 (0,60) 被 bounds 过滤（枚举有界的直接证据）。
func _test_max_span_clamped() -> void:
	_query_calls = 0
	var result: Dictionary = BattleOccluderScript.compute(
		Vector3(0.0, 3.0, -50.0),
		[Vector3(0.0, 1.0, 50.0)],
		_make_query([_col(Vector2i(0, 60), 3.0)])
	)
	_expect(result["columns"].is_empty(), "T10 超出收缩 bounds 的远格不应被枚举")
	_expect(_query_calls == 1 and _last_bounds.size() == 2, "T10 应记录一次 bounds 查询")
	if _last_bounds.size() == 2:
		var bounds_min: Vector2i = _last_bounds[0]
		var bounds_max: Vector2i = _last_bounds[1]
		_expect(bounds_max.y - bounds_min.y == BattleOccluderScript.MAX_SPAN, "T10 y 轴 span 应收缩到 MAX_SPAN")
		_expect(bounds_min.y == -BattleOccluderScript.MAX_SPAN / 2, "T10 收缩后 y 下界应为 -32")
		_expect(bounds_max.x - bounds_min.x <= BattleOccluderScript.MAX_SPAN, "T10 x 轴 span 不应超过 MAX_SPAN")


## T11 真实 IsometricTerrain3D 数据 → get_column_occlusion_data（作为 query）→ compute 全链：
## 3 格中只选中前方高柱；(0,-2) 因 level 太低、(2,-2) 因侧偏被几何层排除。
func _test_terrain_data_to_compute() -> void:
	var terrain: Node3D = Terrain3DScript.new()
	terrain.set_cell(Vector2i(0, -7), [{"level": 9}])
	terrain.set_cell(Vector2i(0, -2), [{"level": 1}])
	terrain.set_cell(Vector2i(2, -2), [{"level": 9}])
	var result: Dictionary = BattleOccluderScript.compute(
		CAM, [UNIT], Callable(terrain, "get_column_occlusion_data")
	)
	_expect(
		result["columns"].size() == 1 and _has_cell(result["columns"], Vector2i(0, -7)),
		"T11 terrain 全链应只选中 (0,-7)（低柱与侧偏被排除）"
	)
	var data: Array = terrain.get_column_occlusion_data(Vector2i(-1, -10), Vector2i(1, 10))
	_expect(data.size() == 2, "T11 bounds (-1..1, -10..10) 内应有 2 柱（(2,-2) 被矩形过滤）")
	for item_value in data:
		var item: Dictionary = item_value
		if (item["cell"] as Vector2i) == Vector2i(0, -7):
			_expect(
				is_equal_approx(float(item["top"]), 9.0 * IsoProjection.LEVEL_HEIGHT),
				"T11 (0,-7) top 应为 9*LEVEL_HEIGHT≈%.4f，实测 %.4f" % [9.0 * IsoProjection.LEVEL_HEIGHT, float(item["top"])]
			)
	terrain.free()


## T12 柱隐藏→恢复幂等（数据层）：重复 hide 不叠加、unhide 后零残留、cell 数据不受影响。
func _test_column_hidden_roundtrip() -> void:
	var terrain: Node3D = Terrain3DScript.new()
	terrain.set_cell(Vector2i(0, -7), [{"level": 9}])
	terrain.set_column_hidden(Vector2i(0, -7), true)
	_expect(terrain.is_column_hidden(Vector2i(0, -7)), "T12 hide 后 is_column_hidden 应为 true")
	_expect(_has_cell(terrain.get_hidden_columns(), Vector2i(0, -7)), "T12 get_hidden_columns 应含该格")
	terrain.set_column_hidden(Vector2i(0, -7), true)
	_expect(terrain.get_hidden_columns().size() == 1, "T12 重复 hide 应幂等（不重复记录）")
	terrain.set_column_hidden(Vector2i(0, -7), false)
	_expect(not terrain.is_column_hidden(Vector2i(0, -7)), "T12 unhide 后 is_column_hidden 应为 false")
	_expect(terrain.get_hidden_columns().is_empty(), "T12 unhide 后隐藏集合应清空")
	terrain.set_column_hidden(Vector2i(0, -7), false)
	_expect(terrain.get_hidden_columns().is_empty(), "T12 重复 unhide 应幂等")
	_expect(terrain.has_cell(Vector2i(0, -7)), "T12 隐藏/恢复不应破坏 cell 数据（重建依据）")
	terrain.free()


## T13 淡化锁定存在性/幂等：hold 期间 set_prop_fade_target 被挡（无 prop 实例时两者均 no-op，
## 可观察部分为 hold 表本身）；clear 后交还。
func _test_prop_fade_hold() -> void:
	var terrain: Node3D = Terrain3DScript.new()
	terrain.set_cell(Vector2i(0, -3), [{"level": 9}])
	terrain.set_prop_fade_hold(Vector2i(0, -3), 0.0)
	_expect(terrain.has_prop_fade_hold(Vector2i(0, -3)), "T13 hold 后 has_prop_fade_hold 应为 true")
	terrain.set_prop_fade_target(Vector2i(0, -3), 0.5)
	_expect(terrain.has_prop_fade_hold(Vector2i(0, -3)), "T13 hold 格被 set_prop_fade_target 写入后锁定应保持")
	terrain.set_prop_fade_hold(Vector2i(0, -3), 0.0)
	_expect(terrain.has_prop_fade_hold(Vector2i(0, -3)), "T13 重复 hold 应幂等")
	terrain.clear_prop_fade_hold(Vector2i(0, -3))
	_expect(not terrain.has_prop_fade_hold(Vector2i(0, -3)), "T13 clear 后锁定应解除")
	terrain.clear_prop_fade_hold(Vector2i(0, -3))
	_expect(not terrain.has_prop_fade_hold(Vector2i(0, -3)), "T13 重复 clear 应幂等")
	terrain.free()


## T14 clear() 重置隐藏与锁定表（换地形/整场重建的零残留基础）。
func _test_clear_resets_hidden_and_holds() -> void:
	var terrain: Node3D = Terrain3DScript.new()
	terrain.set_cell(Vector2i(0, -7), [{"level": 9}])
	terrain.set_column_hidden(Vector2i(0, -7), true)
	terrain.set_prop_fade_hold(Vector2i(0, -7), 0.0)
	terrain.clear()
	_expect(terrain.get_hidden_columns().is_empty(), "T14 clear 后隐藏表应清空")
	_expect(not terrain.has_prop_fade_hold(Vector2i(0, -7)), "T14 clear 后锁定表应清空")
	terrain.free()
