## map_editor_shortcuts.gd — 地图编辑器全局快捷键与临时吸管状态机
##
## _unhandled_input 全键盘路由（撤销/重做、区域剪贴板、方块槽交换、
## 方向键平移、Esc 级联退出、视角旋转）+ Alt 临时吸管 + 输入框焦点判定。
## 全部 static，ed=map_editor 实例；状态留在门面（_alt_key_down 等），
## 逻辑与原 map_editor.gd 内联实现逐行一致。

class_name MapEditorShortcuts
extends RefCounted


static func text_input_has_focus(ed) -> bool:
	if ed.get_viewport() == null:
		return false
	var focus: Control = ed.get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


static func begin_alt_pick(ed) -> void:
	if ed._alt_pick_active or ed.current_tool == ed.Tool.PICK or not ed._tool_buttons.has(ed.Tool.PICK):
		return
	ed._alt_pick_return_tool = ed.current_tool
	ed._alt_pick_active = true
	ed._tool_buttons[ed.Tool.PICK].button_pressed = true
	print("MapEditor: Alt 临时吸管 -> 松开恢复工具 %d" % ed._alt_pick_return_tool)


static func end_alt_pick(ed) -> void:
	if not ed._alt_pick_active:
		return
	var return_tool: int = ed._alt_pick_return_tool
	ed._alt_pick_active = false
	ed._alt_pick_return_tool = -1
	if return_tool >= 0 and ed._tool_buttons.has(return_tool):
		ed._tool_buttons[return_tool].button_pressed = true
		print("MapEditor: Alt 松开 -> 恢复工具 %d" % return_tool)


static func unhandled_input(ed, event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		var alt_key := event as InputEventKey
		if alt_key.keycode == KEY_ALT or alt_key.physical_keycode == KEY_ALT:
			if alt_key.pressed:
				if alt_key.ctrl_pressed or alt_key.meta_pressed or text_input_has_focus(ed):
					return
				ed._alt_key_down = true
				begin_alt_pick(ed)
			else:
				ed._alt_key_down = false
				end_alt_pick(ed)
			if ed.get_viewport() != null:
				ed.get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		var ctrl := key.ctrl_pressed or key.meta_pressed
		if ctrl and (key.keycode == KEY_Z or key.physical_keycode == KEY_Z):
			if ed.get_viewport() != null:
				ed.get_viewport().set_input_as_handled()
			# Ctrl+Z 撤销；Ctrl+Shift+Z / Ctrl+Y 重做（通用习惯）
			if key.shift_pressed:
				ed._redo()
			else:
				ed._undo()
		elif ctrl and (key.keycode == KEY_Y or key.physical_keycode == KEY_Y):
			if ed.get_viewport() != null:
				ed.get_viewport().set_input_as_handled()
			ed._redo()
		elif ctrl and (key.keycode == KEY_C or key.physical_keycode == KEY_C):
			if ed.get_viewport() != null:
				ed.get_viewport().set_input_as_handled()
			ed._on_region_copy_pressed()
		elif ctrl and (key.keycode == KEY_X or key.physical_keycode == KEY_X):
			if ed.get_viewport() != null:
				ed.get_viewport().set_input_as_handled()
			ed._on_region_cut_pressed()
		elif ctrl and (key.keycode == KEY_V or key.physical_keycode == KEY_V):
			if ed.get_viewport() != null:
				ed.get_viewport().set_input_as_handled()
			ed._on_region_paste_pressed()
		elif not ctrl and key.shift_pressed and (key.keycode == KEY_X or key.physical_keycode == KEY_X):
			# Shift+X 交换前景/背景；必须先于下方 X 右转分支拦截。
			if ed.get_viewport() != null:
				ed.get_viewport().set_input_as_handled()
			ed._swap_block_slots()
		elif ed._move_tool_active and (key.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
				or key.physical_keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]):
			# 移动工具开启：方向键逐格平移选区（上/下/左/右 = y-/y+/x-/x+），
			# 每键恰好一步历史、选区跟随；无完整选区仅中文提示
			if ed.get_viewport() != null:
				ed.get_viewport().set_input_as_handled()
			var kc: Key = key.keycode
			if not (kc in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]):
				kc = key.physical_keycode
			match kc:
				KEY_UP: ed._nudge_region(Vector2i(0, -1))
				KEY_DOWN: ed._nudge_region(Vector2i(0, 1))
				KEY_LEFT: ed._nudge_region(Vector2i(-1, 0))
				KEY_RIGHT: ed._nudge_region(Vector2i(1, 0))
		elif key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE:
			# 操作提示最优先：只关弹窗，不取消地图模式、更不返回世界。
			if ed._shortcut_hints_dialog != null and ed._shortcut_hints_dialog.visible:
				ed._shortcut_hints_dialog.close()
				if ed.get_viewport() != null:
					ed.get_viewport().set_input_as_handled()
				return
			# 方块选择器优先于 ReplacePopup/地图模式：取消只关选择器且不回填。
			if ed._replace_picker_dialog != null and ed._replace_picker_dialog.visible:
				ed._replace_picker_dialog.cancel()
				if ed.get_viewport() != null:
					ed.get_viewport().set_input_as_handled()
				return
			# 放置模式激活时：Esc 先退出放置（清预览），不碰菜单也不返回世界
			if ed._place_mode:
				ed._cancel_place_mode()
				if ed.get_viewport() != null:
					ed.get_viewport().set_input_as_handled()
				return
			# 粘贴/移动预览激活时：Esc 先取消预览，不关菜单也不返回世界
			if ed._paste_mode or ed._move_armed:
				ed._cancel_paste()
				if ed.get_viewport() != null:
					ed.get_viewport().set_input_as_handled()
				return
			# 移动工具开启时：Esc 先关掉移动工具（同步工具栏开关），不关菜单也不返回世界
			if ed._move_tool_active:
				ed._set_move_tool(false)
				if ed.get_viewport() != null:
					ed.get_viewport().set_input_as_handled()
				return
			# 条件替换弹窗打开时：Esc 只收起弹窗，不返回世界。
			if ed._replace_popup != null and ed._replace_popup.visible:
				ed._replace_popup.hide()
				if ed.get_viewport() != null:
					ed.get_viewport().set_input_as_handled()
				return
			# 选择模式菜单打开时：Esc 先关菜单，不碰素材弹窗也不返回世界
			if ed._selection_popup != null and ed._selection_popup.visible:
				ed._close_selection_popup()
				if ed.get_viewport() != null:
					ed.get_viewport().set_input_as_handled()
				return
			# 素材面板弹窗（导入文件选择/隐藏确认）打开时：Esc 先关弹窗，不返回世界
			if ed._asset_panel != null and ed._asset_panel.is_dialog_open():
				ed._asset_panel.close_dialogs()
				if ed.get_viewport() != null:
					ed.get_viewport().set_input_as_handled()
				return
			# 先标记已处理再切场景：change_scene 后本节点被释放，get_viewport() 会变 null
			if ed.get_viewport() != null:
				ed.get_viewport().set_input_as_handled()
			ed._back_to_world()
		elif not ctrl and (key.keycode == KEY_Q or key.keycode == KEY_Z):
			# 视角旋转 ±90°（Q/Z 左转；E/X 右转；R 复位）——与世界/战棋肌肉记忆一致
			if ed.get_viewport() != null:
				ed.get_viewport().set_input_as_handled()
			ed._canvas.rotate_view(-1)
		elif not ctrl and (key.keycode == KEY_E or key.keycode == KEY_X):
			if ed.get_viewport() != null:
				ed.get_viewport().set_input_as_handled()
			ed._canvas.rotate_view(1)
		elif not ctrl and key.keycode == KEY_R:
			if ed.get_viewport() != null:
				ed.get_viewport().set_input_as_handled()
			ed._canvas.reset_view()
