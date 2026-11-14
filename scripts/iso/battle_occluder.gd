class_name BattleOccluder
extends RefCounted
## battle_occluder.gd — 沉浸式战斗遮挡判定（纯几何，无场景树依赖，可 headless 单测）。
##
## 输入：相机世界坐标、参战单位中心点数组、候选格查询回调。
## 回调签名：query(bounds_min: Vector2i, bounds_max: Vector2i) -> Array[Dictionary]，
## 每项 {cell: Vector2i, center: Vector3, top: float, prop: bool}；调用方负责按 bounds
## 枚举候选（有界区域，不遍历无限世界），center 为柱轴/植物 billboard 中心，
## top 为其最高点世界 Y。
## 输出：{columns: Array[Vector2i], props: Array[Vector2i]} —— 挡在"相机→单位"视线
## 之间、且高度足以遮住单位中心的柱/植物格。只判视线之间的物体，背后的不选。
##
## 几何：柱/植物都是竖直物体，判定在地面投影上进行——视线的地面轨迹是
## cam.xz→unit.xz 的直线段，柱心到该线段的水平距小于捕获半径即视为挡线；
## 柱顶高于该处视线高度（相机→单位线性插值）才真的遮得住单位中心。

const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")

## 单位脚下豁免半径：参战单位周围此水平半径内的柱视为脚下支撑，不隐藏。
const FOOT_RADIUS := IsoProjection.GRID_STEP * 0.5
## 挡线捕获半径：柱心到视线地面轨迹的水平距小于此值即视为挡线（略大于柱半宽 0.354）。
const CAPTURE_RADIUS := IsoProjection.GRID_STEP * 0.55
## 端点余量：水平参数落在捕获半径内（相机脚下）或超过 len-余量（单位身上）不判。
const ENDPOINT_MARGIN := 0.05
## 顶部容差：柱顶低于视线高度超过此值才算不挡（略宽容，避免浮点边缘漏判）。
const TOP_MARGIN := 0.05
## 候选格范围每轴硬上限：相机→单位距离有界，超限向中点收缩，防御病态输入。
const MAX_SPAN := 64


static func compute(camera_position: Vector3, participants: Array, query: Callable) -> Dictionary:
	var columns := {}
	var props := {}
	for participant_value in participants:
		var participant: Vector3 = participant_value
		var ground := Vector2(participant.x - camera_position.x, participant.z - camera_position.z)
		var ground_length := ground.length()
		if ground_length < 0.01:
			continue
		var direction := ground / ground_length
		var bounds := _segment_bounds(camera_position, participant)
		for item_value in query.call(bounds[0], bounds[1]):
			var item: Dictionary = item_value
			var center: Vector3 = item["center"]
			var relative := Vector2(center.x - camera_position.x, center.z - camera_position.z)
			var along := relative.dot(direction)
			if along <= CAPTURE_RADIUS or along >= ground_length - ENDPOINT_MARGIN:
				continue
			var closest := direction * along
			if (relative - closest).length() > CAPTURE_RADIUS:
				continue
			# 单位脚下的柱不隐藏（水平距小于豁免半径；最近邻柱心距 0.707 不受影响）。
			if Vector2(center.x - participant.x, center.z - participant.z).length() <= FOOT_RADIUS:
				continue
			var ray_height := lerpf(camera_position.y, participant.y, along / ground_length)
			if float(item.get("top", 0.0)) < ray_height - TOP_MARGIN:
				continue
			var cell: Vector2i = item["cell"]
			if bool(item.get("prop", false)):
				props[cell] = true
			else:
				columns[cell] = true
	return {"columns": columns.keys(), "props": props.keys()}


## 视线段的格坐标包围盒（两端各外扩 1 格），每轴超过 MAX_SPAN 时向中点收缩。
static func _segment_bounds(from: Vector3, to: Vector3) -> Array:
	var a := IsoProjection.world_to_grid_position(from)
	var b := IsoProjection.world_to_grid_position(to)
	var bounds_min := Vector2i(
		mini(floori(a.x), floori(b.x)) - 1,
		mini(floori(a.y), floori(b.y)) - 1
	)
	var bounds_max := Vector2i(
		maxi(ceili(a.x), ceili(b.x)) + 1,
		maxi(ceili(a.y), ceili(b.y)) + 1
	)
	var span := bounds_max - bounds_min
	var center := (bounds_min + bounds_max) / 2
	if span.x > MAX_SPAN:
		bounds_min.x = center.x - MAX_SPAN / 2
		bounds_max.x = center.x + MAX_SPAN / 2
	if span.y > MAX_SPAN:
		bounds_min.y = center.y - MAX_SPAN / 2
		bounds_max.y = center.y + MAX_SPAN / 2
	return [bounds_min, bounds_max]
