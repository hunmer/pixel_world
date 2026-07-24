extends RefCounted

## 移动物体横跨两个地块时，不能在线性插值两个离散的地块排序键。
## 物体的脚点同时占据起点/终点支撑面：屏幕前方且不高于脚点的地板必须先画；
## 只有屏幕前方、确实高于当前脚点的地形才允许后画并形成遮挡。

const HEIGHT_EPSILON := 0.0001


static func moving_support_sort_y(
	from_anchor_sort_y: float,
	target_anchor_sort_y: float,
	from_stand_level: float,
	target_stand_level: float,
	progress: float,
	sort_bias: float,
	switch_progress: float = -1.0
) -> float:
	var t := clampf(progress, 0.0, 1.0)
	var preferred_sort := lerpf(from_anchor_sort_y, target_anchor_sort_y, t)
	if switch_progress >= 0.0:
		preferred_sort = (
			from_anchor_sort_y
			if t < switch_progress
			else target_anchor_sort_y
		)

	var target_is_front := target_anchor_sort_y > from_anchor_sort_y
	var front_anchor_sort := (
		target_anchor_sort_y if target_is_front else from_anchor_sort_y
	)
	var front_level := target_stand_level if target_is_front else from_stand_level
	var current_stand_level := lerpf(from_stand_level, target_stand_level, t)

	# 同高或更低的前方支撑面永远位于物体下面。平地移动因此始终等价于
	# max(from_anchor_sort_y, target_anchor_sort_y)，不会再有目标/起点地板穿模。
	if front_level <= current_stand_level + HEIGHT_EPSILON:
		return front_anchor_sort

	# 前方地形仍高于脚点时，让它稳定地位于物体之后。两倍 bias 分别跨过
	# 地板排序线和物体排序线，避免浮点相等时的绘制顺序不确定。
	var before_front_floor := front_anchor_sort - maxf(sort_bias * 2.0, 0.002)
	return minf(preferred_sort, before_front_floor)
