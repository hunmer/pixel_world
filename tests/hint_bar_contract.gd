## tests/hint_bar_contract.gd — 可复用操作提示条（hint_bar.gd）契约
##
## 跑法：godot --headless --path . --script res://tests/hint_bar_contract.gd
## 覆盖：
##   1. 组件本体：_init 自建 HelpFlow；set_title/add_hint 构建
##      HelpTitle + Hint%d(Keycap/Key/Action)；全树 MOUSE_FILTER_IGNORE。
##   2. map_editor 集成：CanvasHolder 内 EditorHintBar 存在、条目齐全、
##      横向让位左下 CellInfoPanel、完整在画布内，且不破坏原布局契约
##      （EditorRoot 恰 2 子 / 画布 index 0 / 工具条 index 1）。
##   3. game_hud 抽离干净（静态源检查——本机 --script 模式下 Settings
##      autoload 编不过 game_hud.gd，HUD 运行态断言由 Godot MCP
##      dbg_launch + runtime_assert_* 覆盖，见 AGENTS.md）。

extends SceneTree

const HintBarScript = preload("res://scripts/hint_bar.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _assert_ignore_tree(node: Node) -> void:
	if node is Control:
		_expect(
			(node as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"提示条拦截了输入: " + str(node.get_path())
		)
	for child in node.get_children():
		_assert_ignore_tree(child)


func _run() -> void:
	# ---- 1. 组件本体 ----
	var bar := HintBarScript.new()
	bar.name = "HelpPanel"
	root.add_child(bar)
	await process_frame
	var flow := bar.get_node_or_null("HelpFlow") as HFlowContainer
	_expect(flow != null, "组件内建 HelpFlow（HFlowContainer）")
	if flow != null:
		bar.set_title("操作")
		for i in 10:
			bar.add_hint("K%d" % i, "动作%d" % i)
		_expect(flow.get_child_count() == 11,
			"标题 + 10 条 = 11 个子节点（实际 %d）" % flow.get_child_count())
		var has_keycap := false
		for child in flow.get_children():
			var key_label := child.get_node_or_null("Keycap/Key")
			var action_label := child.get_node_or_null("Action")
			if key_label != null and action_label != null \
					and key_label.text == "K3" and action_label.text == "动作3":
				has_keycap = true
		_expect(has_keycap, "Keycap/Key/Action 节点结构保持（game_hud_contract 依赖）")
		_assert_ignore_tree(bar)
	bar.queue_free()
	await process_frame

	# ---- 2. map_editor 集成：右下键盘按钮 + 点击后的完整键帽弹窗 ----
	var editor = load("res://scenes/MapEditor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	root.size = Vector2i(1024, 640)
	await process_frame
	await process_frame
	var holder: Control = editor.get_node_or_null("EditorRoot/CanvasHolder")
	var hint_button: Button = editor.get_node_or_null("EditorRoot/CanvasHolder/EditorHintBar") as Button
	_expect(hint_button != null and hint_button.icon is Texture2D
		and hint_button.custom_minimum_size == Vector2(34, 30)
		and hint_button.mouse_filter == Control.MOUSE_FILTER_STOP
		and hint_button.tooltip_text == "操作提示"
		and hint_button.get_node_or_null("HelpFlow") == null,
		"EditorHintBar 是 34×30 键盘图标按钮，不再常驻文本提示")
	var dialog = holder.get_node_or_null("ShortcutHintsDialog") if holder != null else null
	_expect(dialog != null and not dialog.visible, "ShortcutHintsDialog 挂在 CanvasHolder 且默认隐藏")
	if hint_button != null and holder != null and dialog != null:
		var close_events: Array[bool] = []
		dialog.closed.connect(func(): close_events.append(true))
		hint_button.pressed.emit()
		await process_frame
		var shortcut_flow := dialog.get_node_or_null("ShortcutHintsPanel/ShortcutHintFlow") as HFlowContainer
		var hint_rows := 0
		if shortcut_flow != null:
			for child in shortcut_flow.get_children():
				if child.get_node_or_null("Keycap/Key") != null \
						and child.get_node_or_null("Action") != null:
					hint_rows += 1
		_expect(dialog.visible and shortcut_flow != null and hint_rows == editor.HINT_ITEMS.size()
			and hint_rows >= 6, "点击图标打开弹窗，ShortcutHintFlow 复用键帽行并展示全部 13 条提示")
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = true
		editor._unhandled_input(esc)
		_expect(not dialog.visible and close_events.size() == 1,
			"Esc 最优先只关闭操作提示弹窗并 emit closed")
		dialog.open(editor.HINT_ITEMS)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		var shade: Control = dialog.get_node_or_null("ShortcutHintsShade")
		if shade != null:
			shade.gui_input.emit(click)
		_expect(not dialog.visible and close_events.size() == 2, "点遮罩关闭并 emit closed")
		hint_button.pressed.emit()
		var close_btn: Button = dialog.get_node_or_null(
			"ShortcutHintsPanel/ShortcutHintFlow/ShortcutHintsCloseBtn") as Button
		if close_btn != null:
			close_btn.pressed.emit()
		_expect(not dialog.visible and close_events.size() == 3, "关闭按钮关闭并 emit closed")
		var info: Control = holder.get_node_or_null("CellInfoPanel")
		if info != null:
			_expect(hint_button.get_global_rect().position.x >= info.get_global_rect().end.x - 1.0,
				"键盘按钮横向让位 CellInfoPanel（bar %s vs info %s）" %
				[hint_button.get_global_rect(), info.get_global_rect()])
		var hr := hint_button.get_global_rect()
		var cr := holder.get_global_rect()
		_expect(hr.position.x >= cr.position.x - 1.0 and hr.position.y >= cr.position.y - 1.0
			and hr.end.x <= cr.end.x + 1.0 and hr.end.y <= cr.end.y + 1.0,
			"键盘按钮完整位于画布右下（%s ⊄ %s）" % [hr, cr])
	var eroot: Control = editor.get_node_or_null("EditorRoot")
	if eroot != null:
		_expect(eroot.get_child_count() == 2, "EditorRoot 仍恰好 2 子（按钮/弹窗挂在 CanvasHolder 内）")
	if holder != null:
		var canvas: Control = holder.get_node_or_null("EditorCanvas")
		var toolbar: Control = holder.get_node_or_null("ToolBar")
		_expect(canvas != null and toolbar != null
			and canvas.get_index() == 0 and toolbar.get_index() == 1,
			"画布 index 0 / 工具条 index 1 不变")
	editor.queue_free()
	await process_frame

	# ---- 3. game_hud 抽离干净（静态源检查；动态由 MCP runtime 断言覆盖） ----
	var src := FileAccess.open("res://scripts/game_hud.gd", FileAccess.READ)
	if src != null:
		var text := src.get_as_text()
		src.close()
		_expect(text.contains("res://scripts/hint_bar.gd"),
			"game_hud.gd 引用 hint_bar 组件（真复用非复制）")
		_expect(not text.contains("func _add_hint("),
			"game_hud.gd 不再自建 hint 节点（已抽离到组件）")
	else:
		_expect(false, "game_hud.gd 可读")

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("HINT_BAR_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
