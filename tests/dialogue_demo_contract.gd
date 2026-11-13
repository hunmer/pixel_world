## dialogue_demo_contract.gd — DialogueDemo 场景运行态契约
##
## 验证：状态机（打字/补全/推进/结束/重播）、左右立绘与名称牌高亮切换、
## 名称/立绘在对话框上方且不重叠不裁切、逐字更新、连续输入不错句、
## 宽窄窗口自适应不溢出。
## 运行：godot --headless --path . --script res://tests/dialogue_demo_contract.gd
extends SceneTree

const STATE_TYPING := 0
const STATE_WAITING := 1
const STATE_ENDED := 2
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")

var _fail_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok - " + msg)
	else:
		_fail_count += 1
		push_error("CHECK_FAIL: " + msg)


func _confirm_key() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	return ev


func _confirm_click() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev


func _rect_inside_viewport(c: Control, bounds: Vector2) -> bool:
	var r := Rect2(c.global_position, c.size)
	return r.position.x >= -0.5 and r.position.y >= -0.5 \
		and r.position.x + r.size.x <= bounds.x + 0.5 \
		and r.position.y + r.size.y <= bounds.y + 0.5


func _run() -> void:
	var scene = load("res://scenes/DialogueDemo.tscn").instantiate()
	root.add_child(scene)

	var text_label: Label = scene.get_node("DialoguePanel/DialogueBox/TextLabel")
	var hint_label: Label = scene.get_node("DialoguePanel/DialogueBox/HintLabel")
	var panel: Control = scene.get_node("DialoguePanel")
	var plate_left: Control = scene.get_node("NamePlateLeft")
	var plate_right: Control = scene.get_node("NamePlateRight")
	var name_left: Label = scene.get_node("NamePlateLeft/PlateBox/NameLabel")
	var name_right: Label = scene.get_node("NamePlateRight/PlateBox/NameLabel")
	var left: Control = scene.get_node("PortraitLeft")
	var right: Control = scene.get_node("PortraitRight")
	var overlay: Control = scene.get_node("EndOverlay")

	var hero_color := Color(scene._speakers["hero"]["color"])
	var elf_color := Color(scene._speakers["elf"]["color"])

	# ---- 1. 结构与初始状态：主角左侧先发言，逐字进行中
	_check(scene.name == "DialogueDemo", "场景根节点名")
	_check(scene._state == STATE_TYPING, "初始 state=TYPING")
	_check(scene._line_index == 0, "初始 line_index=0")
	_check(name_left.text == "罗恩" and name_right.text == "莉娅",
		"上方名称牌：左=罗恩（主角）右=莉娅（配角）")
	_check(scene._speakers["hero"]["side"] == "left" and scene._speakers["elf"]["side"] == "right",
		"数据侧别：主角 left / 配角 right")
	_check(scene._lines.size() >= 6, "多轮台词数量 >= 6")
	_check(text_label.visible_characters == 0, "初始逐字可见 0")
	_check(name_left.get_theme_color("font_color") == hero_color,
		"主角发言时左名称牌用角色色")
	_check(name_right.get_theme_color("font_color") == UIThemeScript.TEXT_DIM,
		"非发言侧右名称牌灰显")
	await process_frame
	await process_frame

	# ---- 2. 逐字推进：帧推进后 typed_chars 增长但未打满
	for i in 6:
		await process_frame
	_check(scene._typed_chars > 0.0, "逐字推进 typed_chars>0")
	_check(scene._typed_chars < float(text_label.text.length()), "逐字未完成时 typed_chars<全长")
	_check(scene._state == STATE_TYPING, "逐字中 state=TYPING")

	# ---- 3. 打字中按确认 → 补全本句（不推进）
	scene._unhandled_input(_confirm_key())
	_check(scene._state == STATE_WAITING, "补全后 state=WAITING")
	_check(scene._typed_chars == float(text_label.text.length()), "补全后本句全显")
	_check(scene._line_index == 0, "补全不跳句 line_index 仍 0")
	_check(hint_label.text.contains("继续"), "提示语切换为继续")

	# ---- 4. 句毕再按 → 推进到配角第二句；名称牌高亮切到右侧
	scene._unhandled_input(_confirm_key())
	_check(scene._line_index == 1, "推进后 line_index=1")
	_check(scene._state == STATE_TYPING, "新句进入 TYPING")
	_check(name_right.get_theme_color("font_color") == elf_color,
		"配角发言时右名称牌用角色色")
	_check(name_left.get_theme_color("font_color") == UIThemeScript.TEXT_DIM,
		"配角发言时左名称牌灰显")

	# ---- 5. 左右高亮：配角发言时右侧亮、左侧压暗
	_check(right.modulate.a > 0.99, "发言侧（右）立绘全亮")
	_check(is_equal_approx(left.modulate.a, 0.32), "非发言侧（左）立绘压暗 a=0.32")

	# ---- 6. 连续输入（快速两次）：第一次补全、第二次推进，不可跳错句
	var full_second := text_label.text.length()
	for i in 3:
		await process_frame
	scene._unhandled_input(_confirm_click())
	scene._unhandled_input(_confirm_click())
	_check(scene._line_index == 2, "双击后 line_index=2（补全+推进各一次，未连跳）")
	_check(scene._state == STATE_TYPING, "双击后进入第三句 TYPING")
	_check(scene._typed_chars < float(text_label.text.length()), "第三句从头逐字")

	# ---- 7. 回车键也可推进（ui_accept）；第 4 句（index 3）为配角，右侧亮
	scene._unhandled_input(_confirm_key())
	scene._unhandled_input(_confirm_key())
	_check(scene._line_index == 3, "回车键推进 line_index=3")
	_check(right.modulate.a > 0.99 and is_equal_approx(left.modulate.a, 0.32),
		"配角发言时右侧亮左侧暗")
	_check(name_right.get_theme_color("font_color") == elf_color
		and name_left.get_theme_color("font_color") == UIThemeScript.TEXT_DIM,
		"配角发言时右名称牌亮左名称牌灰")

	# ---- 8. echo 事件被忽略
	var echo := _confirm_key()
	echo.echo = true
	var idx_before: int = scene._line_index
	scene._unhandled_input(echo)
	_check(scene._line_index == idx_before, "echo 事件不改变状态")

	# ---- 9. 跑到结束：明确提示 + 重播入口
	var guard := 0
	while scene._state != STATE_ENDED and guard < 200:
		if scene._state == STATE_TYPING:
			scene._complete_line()
		elif scene._state == STATE_WAITING:
			scene._advance()
		guard += 1
	_check(scene._state == STATE_ENDED, "末句后 state=ENDED")
	_check(overlay.visible, "结束提示层可见")
	_check(text_label.text == "", "结束后台词清空")
	_check(name_left.text == "罗恩" and name_right.text == "莉娅", "结束后名称牌保留")
	_check(overlay.get_node("EndBox/ReplayButton") != null, "重播按钮存在")
	# 结束态按确认不报错也不改状态
	scene._unhandled_input(_confirm_key())
	_check(scene._state == STATE_ENDED, "结束态忽略推进输入")

	# ---- 10. 重播：回到首句
	scene._on_replay()
	_check(scene._line_index == 0 and scene._state == STATE_TYPING, "重播回到首句 TYPING")
	_check(not overlay.visible, "重播后结束层隐藏")
	_check(name_left.get_theme_color("font_color") == hero_color, "重播后左名称牌恢复高亮")

	# ---- 11. 宽窗口布局（真实视口）：面板贴底宽=视口-80；立绘贴两侧边、
	#         底边在对话框上方；名称牌悬浮在对话框上边沿（tab 压边 <=12px）
	var vsize: Vector2 = scene.get_viewport_rect().size
	_check(is_equal_approx(panel.size.x, vsize.x - 80.0), "宽窗口面板宽度=视口-80")
	_check(panel.global_position.y + panel.size.y <= vsize.y + 0.5, "宽窗口面板不越出底边")
	_check(panel.global_position.x >= 0.0, "宽窗口面板左边不越界")
	_check(is_equal_approx(left.global_position.x, 48.0), "宽窗口左立绘贴左边距 48")
	_check(is_equal_approx(right.global_position.x + right.size.x, vsize.x - 48.0),
		"宽窗口右立绘贴右边距 48")
	_check(left.global_position.y + left.size.y <= panel.global_position.y + 0.5
		and right.global_position.y + right.size.y <= panel.global_position.y + 0.5,
		"宽窗口立绘底边在对话框上方（不重叠）")
	_check(_rect_inside_viewport(left, vsize) and _rect_inside_viewport(right, vsize),
		"宽窗口两侧立绘不被裁切")
	_check(_rect_inside_viewport(plate_left, vsize) and _rect_inside_viewport(plate_right, vsize),
		"宽窗口两侧名称牌不被裁切")
	_check(plate_left.global_position.y < panel.global_position.y
		and plate_right.global_position.y < panel.global_position.y,
		"宽窗口名称牌主体在对话框上方")
	_check(plate_left.global_position.y + plate_left.size.y <= panel.global_position.y + 12.5
		and plate_right.global_position.y + plate_right.size.y <= panel.global_position.y + 12.5,
		"宽窗口名称牌仅 tab 压边（<=12px）")

	# ---- 12. 窄窗口布局：挂进 620x420 模拟父容器，锚点自适应不越界
	var shell := Control.new()
	shell.name = "SimulatedNarrowViewport"
	root.remove_child(scene)
	shell.add_child(scene)
	root.add_child(shell)
	shell.size = Vector2(620, 420)
	await process_frame
	await process_frame
	vsize = scene.get_viewport_rect().size
	_check(is_equal_approx(panel.size.x, shell.size.x - 80.0), "窄窗口面板宽度=模拟视口-80")
	_check(is_finite(panel.size.x) and is_finite(panel.size.y), "窄窗口面板尺寸有限")
	_check(panel.size.x <= vsize.x + 0.5, "窄窗口面板宽 <= 视口宽")
	_check(panel.global_position.x >= 0.0 and panel.global_position.y >= 0.0, "窄窗口面板左上不越界")
	_check(panel.global_position.y + panel.size.y <= vsize.y + 0.5, "窄窗口面板底边不越界")
	var text_rect := Rect2(text_label.global_position, text_label.size)
	var panel_rect := Rect2(panel.global_position, panel.size)
	_check(panel_rect.encloses(text_rect), "窄窗口文本框包含在面板内")
	var left_rect := Rect2(left.global_position, left.size)
	var right_rect := Rect2(right.global_position, right.size)
	_check(not left_rect.intersects(right_rect), "窄窗口左右立绘不重叠")
	_check(is_equal_approx(right.global_position.x + right.size.x, shell.size.x - 48.0),
		"窄窗口右立绘仍贴右缘")
	_check(left.global_position.y + left.size.y <= panel.global_position.y + 0.5
		and right.global_position.y + right.size.y <= panel.global_position.y + 0.5,
		"窄窗口立绘底边在对话框上方（不重叠）")
	_check(plate_left.global_position.y + plate_left.size.y <= panel.global_position.y + 12.5
		and plate_right.global_position.y + plate_right.size.y <= panel.global_position.y + 12.5,
		"窄窗口名称牌仅 tab 压边（<=12px）")
	_check(_rect_inside_viewport(plate_left, shell.size) and _rect_inside_viewport(plate_right, shell.size),
		"窄窗口两侧名称牌不被裁切")

	# ---- 13. 窄窗口长句自动换行（第三句为 70+ 字长句）
	scene._line_index = 1
	scene._advance()
	await process_frame
	scene._complete_line()
	await process_frame
	_check(text_label.get_line_count() >= 3, "窄窗口长句自动换行 >=3 行")
	_check(panel_rect.encloses(Rect2(text_label.global_position, text_label.size)),
		"长句仍收于面板内")

	if _fail_count == 0:
		print("DIALOGUE_DEMO_CONTRACT_OK")
		quit(0)
	else:
		push_error("DIALOGUE_DEMO_CONTRACT_FAILED x%d" % _fail_count)
		quit(1)
