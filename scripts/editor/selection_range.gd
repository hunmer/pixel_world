## selection_range.gd — 可复用选择范围模型（框选/体选状态内核）
##
## 双端点 Vector3i（x/y 格坐标 + z 方块高度层），提供范围归一化、坐标校验
## （clamp 到文档模型边界）、尺寸更新与变更通知。纯 RefCounted、无 UI 依赖，
## headless 契约可测（tests/editor_selection_contract.gd）。
##
## 给「框选工具」的典型用法（map_editor 的 SELECT 后续可迁移到此模型）：
##   按下  range.begin_2i(cell)          # anchor = focus = (cell, 0)
##   拖动  range.update_focus(Vector3i(cell.x, cell.y, 0))
##   松手  range.normalized() / size()    # 读取闭合范围
##   模型 resize/重生成后 range.clamp_to(model)  # 收敛失效端点（尺寸更新）
## z 维度语义：anchor.z/focus.z 是方块高度层（BattlefieldDoc.BLOCK_MIN_Z..MAX_Z），
## 归一对三分量都生效；只做平面框选时两端点 z 恒 0（begin_2i 默认）。

class_name EditorSelectionRange
extends RefCounted

const BattlefieldDocScript := preload("res://scripts/editor/battlefield_doc.gd")

## 未激活时 anchor/focus 的哨兵值。
const INVALID := Vector3i(-1, -1, -1)

## 任何会改动端点的操作后发射（begin/update_focus/clear/clamp_to 实际变更时）。
signal changed()

var anchor: Vector3i = INVALID
var focus: Vector3i = INVALID


## 以 3D 端点开启选择（anchor = focus = cell）。
func begin(cell: Vector3i) -> void:
	anchor = cell
	focus = cell
	changed.emit()


## 以 2D 格坐标开启平面选择（z 固定 0，纯框选场景）。
func begin_2i(cell: Vector2i, z := 0) -> void:
	begin(Vector3i(cell.x, cell.y, z))


## 拖动中更新焦点端点；未激活时忽略。
func update_focus(cell: Vector3i) -> void:
	if not is_active():
		return
	if focus == cell:
		return
	focus = cell
	changed.emit()


## 清空选择（回到未激活态）。
func clear() -> void:
	if not is_active():
		return
	anchor = INVALID
	focus = INVALID
	changed.emit()


## 是否处于激活态（begin 过且未 clear）。
func is_active() -> bool:
	return anchor != INVALID and focus != INVALID


## 归一化后的最小角（未激活返回 INVALID）。
func min_corner() -> Vector3i:
	if not is_active():
		return INVALID
	return Vector3i(
		mini(anchor.x, focus.x),
		mini(anchor.y, focus.y),
		mini(anchor.z, focus.z)
	)


## 归一化后的最大角（含端点，闭区间；未激活返回 INVALID）。
func max_corner() -> Vector3i:
	if not is_active():
		return INVALID
	return Vector3i(
		maxi(anchor.x, focus.x),
		maxi(anchor.y, focus.y),
		maxi(anchor.z, focus.z)
	)


## 归一化范围字典 {"min": Vector3i, "max": Vector3i}；未激活返回 {}。
func normalized() -> Dictionary:
	if not is_active():
		return {}
	return {"min": min_corner(), "max": max_corner()}


## 范围尺寸（闭区间边长）；未激活返回 (0,0,0)。
func size() -> Vector3i:
	if not is_active():
		return Vector3i.ZERO
	return max_corner() - min_corner() + Vector3i.ONE


## 范围内格子总数（x*y*z 体积）；未激活返回 0。
func cell_count() -> int:
	if not is_active():
		return 0
	var s := size()
	return s.x * s.y * s.z


## z 层闭区间 [zmin, zmax]；未激活返回 (0,0)。
func z_span() -> Vector2i:
	if not is_active():
		return Vector2i.ZERO
	return Vector2i(mini(anchor.z, focus.z), maxi(anchor.z, focus.z))


## 3D 包含判断（闭区间）。
func contains(cell: Vector3i) -> bool:
	if not is_active():
		return false
	var lo := min_corner()
	var hi := max_corner()
	return (
		cell.x >= lo.x and cell.x <= hi.x
		and cell.y >= lo.y and cell.y <= hi.y
		and cell.z >= lo.z and cell.z <= hi.z
	)


## 2D 包含判断（忽略 z；供画布/面板按格查询）。
func contains_2i(cell: Vector2i) -> bool:
	return contains(Vector3i(cell.x, cell.y, 0))


## 范围覆盖的全部平面格（x×y 遍历，忽略 z 维）；未激活返回空数组。
func cells_2d() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not is_active():
		return out
	var lo := min_corner()
	var hi := max_corner()
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			out.append(Vector2i(x, y))
	return out


## 坐标校验 + 尺寸更新：把两端点独立夹进模型 [0,width)×[0,height)×
## [BLOCK_MIN_Z,BLOCK_MAX_Z]。模型 resize / 重生成后调用，让过期端点收敛到
## 最近的合法边界（拖出画布外的框选会退化为边缘区）。
## 返回 clamp 后是否仍激活（false = 原本就未激活或被清空）。
func clamp_to(model: Dictionary) -> bool:
	if not is_active():
		return false
	var w: int = model.get("width", 0)
	var h: int = model.get("height", 0)
	if w <= 0 or h <= 0:
		clear()
		return false
	var z_min: int = BattlefieldDocScript.BLOCK_MIN_Z
	var z_max: int = BattlefieldDocScript.BLOCK_MAX_Z
	var before_a := anchor
	var before_f := focus
	anchor = _clamp_cell(anchor, w, h, z_min, z_max)
	focus = _clamp_cell(focus, w, h, z_min, z_max)
	if anchor != before_a or focus != before_f:
		changed.emit()
	return true


static func _clamp_cell(cell: Vector3i, w: int, h: int, z_min: int, z_max: int) -> Vector3i:
	return Vector3i(
		clampi(cell.x, 0, w - 1),
		clampi(cell.y, 0, h - 1),
		clampi(cell.z, z_min, z_max)
	)
