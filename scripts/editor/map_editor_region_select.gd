## map_editor_region_select.gd — 地图编辑器区域选择与区域填充入口
##
## 选择模式弹窗开关、单格/区域模式切换、pos1/pos2 端点点击语义、画布虚线框
## （同高=平面 / 异高=立体选择体）与坐标 SpinBox 双向同步、完整区域 2D 角点、
## 区域填充/清除按钮门禁。全部 static，ed=map_editor 实例；
## 逻辑与原 map_editor.gd 内联实现逐行一致。

class_name MapEditorRegionSelect
extends RefCounted

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")


static func open_selection_popup(ed) -> void:
	if ed._selection_popup == null:
		return
	ed._selection_popup.visible = true
	if ed._fill_selector != null:
		ed._fill_selector.refresh_assets()
	sync_region_boxes(ed)


static func close_selection_popup(ed) -> void:
	if ed._selection_popup != null:
		ed._selection_popup.visible = false


static func on_selection_mode_item(ed, idx: int) -> void:
	ed._selection_mode = &"region" if idx == 1 else &"single"
	if ed._selection_mode == &"single":
		# 回单格：清区域端点与虚线框（单格选择行为与既有契约完全一致）
		ed._selection_range.clear()
		ed._region_pos2_set = false
		ed._sync_region_marker()
	ed._status("选择模式：%s" % ("区域（两次点击设 pos1/pos2，拖动无效）" if idx == 1 else "单格"))


## 区域模式点击：第一次=pos1（取所在格 z），第二次=pos2，第三次重新从 pos1 开始
static func apply_region_click(ed, cell: Vector2i) -> void:
	var p := Vector3i(cell.x, cell.y, BattlefieldDocScript.cell_z(ed.model, cell))
	if not ed._selection_range.is_active() or ed._region_pos2_set:
		ed._selection_range.begin(p)
		ed._region_pos2_set = false
	else:
		ed._selection_range.update_focus(p)
		ed._region_pos2_set = true
	ed._sync_region_marker()
	var mn: Vector3i = ed._selection_range.min_corner()
	var mx: Vector3i = ed._selection_range.max_corner()
	ed._status("区域 pos1=(%d,%d,%d) pos2=(%d,%d,%d) · %d 格" % [
		mn.x, mn.y, mn.z, mx.x, mx.y, mx.z, ed._selection_range.cell_count(),
	])
	print("[editor] 区域端点 pos1=%s pos2=%s" % [str(mn), str(mx)])  # L1 埋点


## range.changed（端点变化 / clamp_to 缩框）→ 画布虚线框 + 坐标 SpinBox 回显
static func on_selection_range_changed(ed) -> void:
	ed._sync_region_marker()
	ed._refresh_replace_scope()


static func sync_region_marker(ed) -> void:
	if ed._canvas == null:
		return
	if ed._selection_range.is_active():
		var mn: Vector3i = ed._selection_range.min_corner()
		var mx: Vector3i = ed._selection_range.max_corner()
		# 两端点同高度 → 固定高度平面四边形（旧行为）；异高度 → 立体选择体
		# （z_min 底面 + z_max 顶面 + 四角立边），不再退化为单平面/跟随地形
		if mn.z == mx.z:
			ed._canvas.set_selection_region(Vector2i(mn.x, mn.y), Vector2i(mx.x, mx.y), mn.z)
		else:
			ed._canvas.set_selection_region(Vector2i(mn.x, mn.y), Vector2i(mx.x, mx.y),
				mini(mn.z, mx.z), maxi(mn.z, mx.z))
	else:
		ed._canvas.clear_selection_region()
	sync_region_boxes(ed)


## 坐标 SpinBox 回显原始端点（anchor=pos1 / focus=pos2，与手改一一对应）：
## 未激活时禁用编辑，max 跟随模型尺寸
static func sync_region_boxes(ed) -> void:
	if ed._pos1_boxes.is_empty() or ed._pos2_boxes.is_empty():
		return
	ed._syncing_region_boxes = true
	var active: bool = ed._selection_range.is_active()
	for pair in [[ed._pos1_boxes, ed._selection_range.anchor], [ed._pos2_boxes, ed._selection_range.focus]]:
		var boxes: Dictionary = pair[0]
		var p: Vector3i = pair[1]
		boxes.x.max_value = float(maxi(0, int(ed.model.width) - 1))
		boxes.y.max_value = float(maxi(0, int(ed.model.height) - 1))
		boxes.x.editable = active
		boxes.y.editable = active
		boxes.z.editable = active
		if active:
			boxes.x.value = p.x
			boxes.y.value = p.y
			boxes.z.value = p.z
	ed._syncing_region_boxes = false


## SpinBox 手改坐标：直接改原始端点（anchor=pos1 / focus=pos2，回显与输入
## 一一对应；归一化只影响虚线框与填充遍历）；夹进模型边界
static func on_region_box_changed(ed, value: float, which: String, axis: StringName) -> void:
	if ed._syncing_region_boxes or not ed._selection_range.is_active():
		return
	var v := int(value)
	if axis == &"x":
		v = clampi(v, 0, int(ed.model.width) - 1)
	elif axis == &"y":
		v = clampi(v, 0, int(ed.model.height) - 1)
	else:
		v = clampi(v, BattlefieldDocScript.BLOCK_MIN_Z, BattlefieldDocScript.BLOCK_MAX_Z)
	if which == "pos1":
		var p: Vector3i = ed._selection_range.anchor
		p[String(axis)] = v
		var f: Vector3i = ed._selection_range.focus
		ed._selection_range.begin(p)
		ed._selection_range.update_focus(f)
	else:
		var p: Vector3i = ed._selection_range.focus
		p[String(axis)] = v
		ed._selection_range.update_focus(p)
	ed._sync_region_marker()


static func on_region_fill_pressed(ed) -> void:
	if ed._selection_mode != &"region" or not ed._region_pos2_set or not ed._selection_range.is_active():
		ed._status("区域未完整（需两次点击画布设置 pos1/pos2）", true)
		return
	ed._push_undo("区域填充")  # 按钮路径自行入栈；画布 FILL 路径由 _apply_tool 统一入栈
	ed._fill_region()


static func on_region_clear_pressed(ed) -> void:
	ed._selection_range.clear()
	ed._region_pos2_set = false
	ed._sync_region_marker()
	ed._status("已清除区域选择")


## 当前完整区域的 2D 角点 [min, max]；区域不完整（未两次点击/未激活）返回 []
static func region_2d_bounds(ed) -> Array:
	if ed._selection_mode != &"region" or not ed._region_pos2_set or not ed._selection_range.is_active():
		return []
	var mn: Vector3i = ed._selection_range.min_corner()
	var mx: Vector3i = ed._selection_range.max_corner()
	return [Vector2i(mini(mn.x, mx.x), mini(mn.y, mx.y)),
		Vector2i(maxi(mn.x, mx.x), maxi(mn.y, mx.y))]


## 移动工具专用角点 [min, max]（与 current_tool/_selection_mode 解耦）：
## 只要求区域完整（两击设好 pos1/pos2 且选区激活）
static func move_tool_bounds(ed) -> Array:
	if not ed._region_pos2_set or not ed._selection_range.is_active():
		return []
	var mn: Vector3i = ed._selection_range.min_corner()
	var mx: Vector3i = ed._selection_range.max_corner()
	return [Vector2i(mini(mn.x, mx.x), mini(mn.y, mx.y)),
		Vector2i(maxi(mn.x, mx.x), maxi(mn.y, mx.y))]
