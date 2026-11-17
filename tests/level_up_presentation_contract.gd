## tests/level_up_presentation_contract.gd — 场内升级薄演出（弹窗）契约
## 运行：godot --headless --path . --script res://tests/level_up_presentation_contract.gd
## 覆盖：静态文本组装（九属性/多级/零成长）、自然超时收尾、键盘与左键跳过、
##       幂等 finished、空 levels 不展示、options.skip 只发音效、cancel 与重入不串场。
extends SceneTree

const PresentationScript = preload("res://scripts/battle/level_up_presentation.gd")
const PixelCenterScript = preload("res://ui/components/pixel_center.gd")
const PixelVBoxScript = preload("res://ui/components/pixel_v_box.gd")
const PixelScrollScript = preload("res://ui/components/pixel_scroll.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _label(presentation: Node, node_name: String) -> Label:
	return presentation.find_child(node_name, true, false) as Label


func _flush_frames() -> void:
	await process_frame
	await process_frame


func _unit() -> Dictionary:
	return {&"id": &"p1", &"name": "艾琳", &"faction": &"player", &"level": 2}


func _one_level() -> Array:
	return [{&"level": 2, &"gains": {&"str": {&"from": 4, &"to": 5}, &"luk": {&"from": 3, &"to": 4}}}]


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var presentation := PresentationScript.new()
	_expect(presentation != null, "LevelUpPresentation 可实例化")
	if presentation == null:
		_finish(presentation)
		return
	root.add_child(presentation)
	await _flush_frames()
	_expect(not presentation.is_playing(), "初始无活动演出")

	_test_statics()
	await _test_natural(presentation)
	await _test_key_skip(presentation)
	await _test_mouse_skip(presentation)
	await _test_empty_levels(presentation)
	await _test_zero_gains(presentation)
	await _test_multi_level(presentation)
	await _test_option_skip(presentation)
	await _test_cancel(presentation)
	await _test_reentrancy(presentation)

	_finish(presentation)


## 静态纯函数：文本组装不依赖节点/场景。
func _test_statics() -> void:
	_expect(PresentationScript.stat_label(&"str") == "力"
		and PresentationScript.stat_label(&"res") == "魔防"
		and PresentationScript.stat_label(&"luk") == "运"
		and PresentationScript.stat_label(&"hp") == "HP"
		and PresentationScript.stat_label(&"mp") == "MP", "九属性中文短名映射正确")
	_expect(PresentationScript.stat_label(&"crit") == "crit", "未知属性键原样显示")
	_expect(PresentationScript.level_range_text([]) == "", "空 levels 无跨度文本")
	_expect(PresentationScript.level_range_text(_one_level()) == "Lv.1 → Lv.2", "单级跨度 Lv.1 → Lv.2")
	_expect(PresentationScript.level_range_text([
		{&"level": 2, &"gains": {}}, {&"level": 3, &"gains": {}}]) == "Lv.1 → Lv.3", "多级连升跨度合成")
	_expect(PresentationScript.level_range_text([
		{&"level": 4, &"gains": {}}, {&"level": 5, &"gains": {}}]) == "Lv.3 → Lv.5",
		"非 Lv.1 起始的两级连升跨度从 first-1 起算（实际 %s）" % PresentationScript.level_range_text([
			{&"level": 4, &"gains": {}}, {&"level": 5, &"gains": {}}]))
	_expect(PresentationScript.level_range_text([
		{&"level": 20, &"gains": {}}]) == "Lv.19 → Lv.20", "封顶单级跨度 Lv.19 → Lv.20")
	var lines := PresentationScript.gain_lines(_one_level())
	_expect(lines == ["力 4 → 5", "运 3 → 4"], "单级成长行按九键序 from → to（实际 %s）" % ", ".join(lines))
	_expect(PresentationScript.gain_lines([{&"level": 2, &"gains": {}}]) == ["没有属性成长"], "零成长条目显示占位行")
	var multi := PresentationScript.gain_lines([
		{&"level": 2, &"gains": {&"hp": {&"from": 18, &"to": 19}}},
		{&"level": 3, &"gains": {&"spd": {&"from": 5, &"to": 6}}},])
	_expect(multi == ["▶ Lv.2", "HP 18 → 19", "▶ Lv.3", "速 5 → 6"], "多级分段带 Lv 段头（实际 %s）" % ", ".join(multi))
	var unknown := PresentationScript.gain_lines([
		{&"level": 2, &"gains": {&"str": {&"from": 4, &"to": 5}, &"crit": {&"from": 0, &"to": 1}}}],)
	_expect(unknown == ["力 4 → 5", "crit 0 → 1"], "未知键按插入序追加在九键之后")


func _test_natural(presentation: PresentationScript) -> void:
	var sounds: Array[StringName] = []
	var finished: Array[bool] = []
	presentation.sound_requested.connect(func(cue: StringName): sounds.append(cue))
	presentation.finished.connect(func(skipped: bool): finished.append(skipped))
	presentation.play(_unit(), _one_level())
	_expect(presentation.is_playing(), "播放中进入活动态")
	_expect(presentation.find_child("Center", true, false) is PixelCenterScript, "居中使用 PixelCenter 组件")
	_expect(presentation.find_child("LevelUpVBox", true, false) is PixelVBoxScript, "纵向布局使用 PixelVBox 组件")
	var scroll = presentation.find_child("GainsScroll", true, false)
	_expect(scroll is PixelScrollScript, "成长行容器使用 PixelScroll 组件")
	if scroll is PixelScrollScript:
		_expect(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
			and scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO,
			"PixelScroll 横向禁用纵向自动（禁横向滚动规范）")
	# 惯例：ScrollContainer 子级必须是容器承载（裸 Label 直挂实测渲染为空）。
	var gains_list = presentation.find_child("GainsList", true, false)
	_expect(gains_list is PixelVBoxScript, "GainsScroll 内容由 PixelVBox 容器承载")
	_expect(gains_list is Control and (gains_list as Control).is_ancestor_of(
		presentation.find_child("GainsText", true, false)),
		"GainsText 位于 GainsList 内")
	_expect(sounds == [&"ui_levelup"], "弹窗展示即发 ui_levelup 音效钩子（实际 %s）" % str(sounds))
	_expect(_label(presentation, "LevelTitle").text == "艾琳 升级！", "标题使用单位名")
	_expect(_label(presentation, "LevelRange").text == "Lv.1 → Lv.2", "跨度行 Lv.1 → Lv.2")
	_expect(_label(presentation, "GainsText").text == "力 4 → 5\n运 3 → 4", "成长行与 levels[].gains 一致（实际 %s）" % _label(presentation, "GainsText").text)
	await create_timer(PresentationScript.AUTO_CLOSE_DURATION + 0.5).timeout
	_expect(finished == [false], "超时自然收尾恰好一次且 skipped=false（实际 %s）" % str(finished))
	_expect(not presentation.is_playing(), "自然收尾后无活动演出")
	_expect(not presentation.find_child("Center", true, false).visible, "收尾后隐藏弹窗")
	for connection in presentation.sound_requested.get_connections():
		presentation.sound_requested.disconnect(connection.callable)
	for connection in presentation.finished.get_connections():
		presentation.finished.disconnect(connection.callable)
	await _flush_frames()


func _test_key_skip(presentation: PresentationScript) -> void:
	var finished: Array[bool] = []
	presentation.finished.connect(func(skipped: bool): finished.append(skipped))
	presentation.play(_unit(), _one_level())
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = true
	presentation._input(event)
	_expect(finished == [true], "Space 跳过收尾一次且 skipped=true")
	_expect(not presentation.is_playing(), "键盘跳过后无活动演出")
	presentation.skip()
	await create_timer(0.30).timeout
	_expect(finished.size() == 1, "重复 skip 不重复收尾（实际 %d 次）" % finished.size())
	for connection in presentation.finished.get_connections():
		presentation.finished.disconnect(connection.callable)
	await _flush_frames()


func _test_mouse_skip(presentation: PresentationScript) -> void:
	var finished: Array[bool] = []
	presentation.finished.connect(func(skipped: bool): finished.append(skipped))
	presentation.play(_unit(), _one_level())
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	presentation._input(event)
	_expect(finished == [true], "左键跳过收尾一次且 skipped=true")
	_expect(not presentation.is_playing(), "左键跳过后无活动演出")
	for connection in presentation.finished.get_connections():
		presentation.finished.disconnect(connection.callable)
	await _flush_frames()


func _test_empty_levels(presentation: PresentationScript) -> void:
	var sounds: Array[StringName] = []
	var finished: Array[bool] = []
	presentation.sound_requested.connect(func(cue: StringName): sounds.append(cue))
	presentation.finished.connect(func(skipped: bool): finished.append(skipped))
	presentation.play(_unit(), [])
	await _flush_frames()
	_expect(not presentation.is_playing(), "空 levels 不展示弹窗")
	_expect(sounds.is_empty() and finished.is_empty(), "空 levels 不发音效不发完成信号")
	for connection in presentation.sound_requested.get_connections():
		presentation.sound_requested.disconnect(connection.callable)
	for connection in presentation.finished.get_connections():
		presentation.finished.disconnect(connection.callable)


func _test_zero_gains(presentation: PresentationScript) -> void:
	var finished: Array[bool] = []
	presentation.finished.connect(func(skipped: bool): finished.append(skipped))
	presentation.play(_unit(), [{&"level": 3, &"gains": {}}])
	_expect(presentation.is_playing(), "零成长条目仍可展示")
	_expect(_label(presentation, "GainsText").text == "没有属性成长", "零成长显示占位行")
	presentation.skip()
	_expect(finished == [true], "零成长弹窗可跳过收尾")
	for connection in presentation.finished.get_connections():
		presentation.finished.disconnect(connection.callable)
	await _flush_frames()


func _test_multi_level(presentation: PresentationScript) -> void:
	presentation.play(_unit(), [
		{&"level": 2, &"gains": {&"hp": {&"from": 18, &"to": 19}, &"str": {&"from": 4, &"to": 5}}},
		{&"level": 3, &"gains": {&"spd": {&"from": 5, &"to": 6}}},])
	_expect(_label(presentation, "LevelRange").text == "Lv.1 → Lv.3", "两级连升跨度 Lv.1 → Lv.3")
	_expect(_label(presentation, "GainsText").text == "▶ Lv.2\nHP 18 → 19\n力 4 → 5\n▶ Lv.3\n速 5 → 6",
		"多级成长按段头分组（实际 %s）" % _label(presentation, "GainsText").text)
	presentation.skip()
	_expect(not presentation.is_playing(), "多级弹窗可跳过收尾")
	await _flush_frames()


func _test_option_skip(presentation: PresentationScript) -> void:
	var sounds: Array[StringName] = []
	var finished: Array[bool] = []
	presentation.sound_requested.connect(func(cue: StringName): sounds.append(cue))
	presentation.finished.connect(func(skipped: bool): finished.append(skipped))
	presentation.play(_unit(), _one_level(), {&"skip": true})
	await _flush_frames()
	_expect(sounds == [&"ui_levelup"], "托管/敌方 skip 选项仍发升级音效钩子")
	_expect(not presentation.is_playing(), "skip 选项不弹窗立即返回")
	_expect(finished.is_empty(), "skip 选项未展示过弹窗不发 finished")
	for connection in presentation.sound_requested.get_connections():
		presentation.sound_requested.disconnect(connection.callable)
	for connection in presentation.finished.get_connections():
		presentation.finished.disconnect(connection.callable)


func _test_cancel(presentation: PresentationScript) -> void:
	var finished: Array[bool] = []
	presentation.finished.connect(func(skipped: bool): finished.append(skipped))
	presentation.play(_unit(), _one_level())
	_expect(presentation.is_playing(), "cancel 前处于活动态")
	presentation.cancel()
	_expect(finished == [true], "cancel 静默收尾一次")
	_expect(not presentation.is_playing(), "cancel 后无活动演出")
	presentation.cancel()
	await create_timer(0.20).timeout
	_expect(finished.size() == 1, "重复 cancel 幂等")
	for connection in presentation.finished.get_connections():
		presentation.finished.disconnect(connection.callable)
	await _flush_frames()


func _test_reentrancy(presentation: PresentationScript) -> void:
	var finished: Array[bool] = []
	presentation.finished.connect(func(skipped: bool): finished.append(skipped))
	presentation.play(_unit(), _one_level())
	presentation.play({&"id": &"p2", &"name": "罗兰", &"level": 5},
		[{&"level": 6, &"gains": {&"mag": {&"from": 7, &"to": 8}}}])
	_expect(finished == [true], "重入先收尾上一场恰好一次")
	_expect(presentation.is_playing(), "重入后新一场处于活动态")
	_expect(_label(presentation, "LevelTitle").text == "罗兰 升级！", "重入展示新一场内容（实际 %s）" % _label(presentation, "LevelTitle").text)
	presentation.skip()
	_expect(finished.size() == 2 and finished[1] == true, "新一场跳过收尾（实际 %s）" % str(finished))
	_expect(not presentation.is_playing(), "重入串场后无残留活动态")
	for connection in presentation.finished.get_connections():
		presentation.finished.disconnect(connection.callable)
	await _flush_frames()


func _finish(presentation: Node) -> void:
	if is_instance_valid(presentation):
		presentation.queue_free()
		await process_frame
	if failures.is_empty():
		print("LEVEL_UP_PRESENTATION_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
