## map_editor_generate.gd — 地图编辑器种子生成 / 调尺寸 / 工具切换
##
## 种子生成（保留 id/name/hosting，替换地形并清空单位与剪贴板/粘贴/放置/
## 移动状态）、尺寸调整（同样的模式作废清理）、整图刷新、工具切换时的
## 放置退出与替换弹窗可见性。全部 static，ed=map_editor 实例；
## 逻辑与原 map_editor.gd 内联实现逐行一致。

class_name MapEditorGenerate
extends RefCounted

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")


## 种子生成（保留 id/name/hosting，替换地形并清空单位）
static func apply_generate(ed, seed: String, w: int, h: int) -> void:
	ed._push_undo("生成")
	var meta := {
		"id": ed._id_edit.text if ed._id_edit != null else String(ed.model.id),
		"name": ed._name_edit.text if ed._name_edit != null else String(ed.model.name),
		"hosting": ed._hosting_check.button_pressed if ed._hosting_check != null else false,
	}
	ed.model = BattlefieldDocScript.generate(seed, w, h)
	ed.model.merge(meta, true)  # overwrite=true：generate 的空 id/name 需被当前输入覆盖
	ed._canvas.selected_cell = Vector2i(-1, -1)
	ed._syncing_boxes = true
	ed._width_box.value = w
	ed._height_box.value = h
	ed._syncing_boxes = false
	refresh_canvas(ed)
	ed._clipboard.clear()  # 跨模型粘贴语义不成立：生成即清剪贴板/取消预览
	ed._cancel_paste()
	ed._cancel_place_mode()  # 旧预设引用同样作废：退出放置
	if ed._move_tool_active:
		ed._set_move_tool(false)  # 新模型旧选区不成立：收起移动工具
	ed._status("已生成 %d×%d · 种子「%s」（单位已清空）" % [w, h, seed])
	print("[editor] 生成地形 seed=%s size=%dx%d" % [seed, w, h])  # L1 埋点


static func generate(ed) -> void:
	ed.apply_generate(ed._seed_edit.text, int(ed._width_box.value), int(ed._height_box.value))


static func on_resize(ed) -> void:
	if ed._canvas == null or ed._syncing_boxes:
		return
	var w := int(ed._width_box.value)
	var h := int(ed._height_box.value)
	if w == ed.model.width and h == ed.model.height:
		return
	ed._push_undo("调整尺寸")
	ed.model = BattlefieldDocScript.resize(ed.model, w, h)
	refresh_canvas(ed)
	ed._clipboard.clear()  # 尺寸变化后旧区域可能越界：清剪贴板/取消预览
	ed._cancel_paste()
	ed._cancel_place_mode()  # 尺寸变化后放置同样作废：退出
	if ed._move_tool_active:
		ed._set_move_tool(false)  # 尺寸变化后旧选区可能越界：收起移动工具


static func refresh_canvas(ed) -> void:
	if ed._canvas == null:
		return
	ed._selection_range.clamp_to(ed.model)  # resize/生成后区域端点夹进新边界（无交集=清空）
	ed._canvas.model = ed.model
	ed._canvas.queue_redraw()
	ed._sync_selection_after_model_change()
	ed._refresh_replace_scope()


static func on_tool_changed(ed) -> void:
	if ed._place_mode or (ed._building_place_mode and not ed._alt_pick_active):
		ed._cancel_place_mode()  # 切工具退出放置模式
	if ed.current_tool != ed.Tool.REPLACE and ed._replace_picker_dialog != null:
		ed._replace_picker_dialog.cancel()
	if ed._replace_popup != null:
		ed._replace_popup.visible = ed.current_tool == ed.Tool.REPLACE
		if ed._replace_popup.visible:
			ed._reset_replace_popup()
	# 选择菜单只属于选择/填充工具：切到其他工具自动收起（与替换弹窗互斥不叠加；
	# 打开仍由工具条回调 _open_selection_popup 负责，保留刷新素材/回显语义）
	if ed._selection_popup != null and ed.current_tool != ed.Tool.SELECT \
			and ed.current_tool != ed.Tool.FILL:
		ed._close_selection_popup()
	var names := {
		ed.Tool.SELECT: "选择", ed.Tool.PAINT: "画笔", ed.Tool.FILL: "填充", ed.Tool.ERASE: "橡皮",
		ed.Tool.UNIT: "角色", ed.Tool.HEIGHT_UP: "地形上升", ed.Tool.HEIGHT_DOWN: "地形下降",
		ed.Tool.REPLACE: "替换方块", ed.Tool.PICK: "吸管",
	}
	ed._status("工具：%s" % names[ed.current_tool])
