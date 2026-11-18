## tests/skill_list_contract.gd — 技能图鉴真实场景的数据、选择、焦点与三档布局契约。
extends SceneTree

const SkillListScene = preload("res://scenes/SkillList.tscn")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _settle() -> void:
	for frame: int in range(8):
		await process_frame


func _run() -> void:
	# 导航测试不写入开发者的最近启动场景；其余场景及界面逻辑照常运行。
	var recorder := Callable(root.get_node("SceneArgs"), "_record_current_scene")
	var restore_recorder: bool = scene_changed.is_connected(recorder)
	if restore_recorder:
		scene_changed.disconnect(recorder)
	for dimensions: Vector2i in [Vector2i(1024, 640), Vector2i(1280, 800), Vector2i(1920, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		root.add_child(viewport)
		var page := SkillListScene.instantiate() as Control
		viewport.add_child(page)
		await _settle()
		_expect(page.size.is_equal_approx(Vector2(dimensions)), "场景铺满视口 %s" % dimensions)
		var buttons := page.find_child("SkillButtons", true, false) as Container
		_expect(buttons.get_child_count() == SkillData.SKILL_LIST.size(), "全部技能均入列")
		_expect(viewport.gui_get_focus_owner() is Button, "打开图鉴有初始按钮焦点")
		_expect(page.get("selected_skill_id") == SkillData.SKILL_LIST[0][&"id"], "默认展示首个技能")
		var detail := page.find_child("SkillDetail", true, false) as Control
		var icon := page.find_child("SkillIcon", true, false) as TextureRect
		var title := page.find_child("SkillName", true, false) as Label
		var description := page.find_child("SkillDescription", true, false) as Label
		var effect := page.find_child("Effect", true, false) as Label
		var fields := page.find_child("Stats", true, false) as Container
		for skill: Dictionary in SkillData.SKILL_LIST:
			var sid: StringName = skill[&"id"]
			var button := buttons.get_node(String(sid)) as Button
			# 真实 pressed 接线，以及键盘焦点切换路径。
			button.grab_focus()
			button.pressed.emit()
			await _settle()
			_expect(page.get("selected_skill_id") == sid, "%s 点击更新选中技能" % sid)
			_expect(button.button_pressed, "%s 有选中态" % sid)
			_expect(title.text == skill[&"name"] and description.text == skill[&"desc"], "%s 标题和说明来自配置" % sid)
			_expect(icon.texture == SkillData.skill_icon(sid) and button.icon == icon.texture, "%s 列表与详情绑定同一图标" % sid)
			_expect((fields.get_child(1) as Label).text == "%d MP" % int(skill[&"mpCost"]), "%s MP 正确" % sid)
			var expected_cd: String = "%d 回合" % int(skill[&"cooldown"]) if int(skill[&"cooldown"]) > 0 else "无冷却"
			_expect((fields.get_child(3) as Label).text == expected_cd, "%s 冷却正确" % sid)
			var reach: Array = skill[&"range"]
			_expect((fields.get_child(5) as Label).text == "%d–%d 格" % [int(reach[0]), int(reach[1])], "%s 射程正确" % sid)
			if skill[&"type"] in [&"buff", &"debuff"]:
				_expect(fields.get_child_count() == 8, "%s 不残留伤害字段" % sid)
				_expect(effect.text.contains("%+d" % int(skill[&"buffValue"])) and effect.text.contains("%d 回合" % int(skill[&"buffTurns"])), "%s 属性增减与持续时间正确" % sid)
			elif skill[&"type"] == &"heal":
				_expect(fields.get_child_count() == 10 and (fields.get_child(9) as Label).text == str(int(skill[&"power"])), "治疗展示基础治疗量，无伤害命中字段")
			else:
				_expect(fields.get_child_count() == 12 and (fields.get_child(11) as Label).text == "%d%%" % int(skill[&"hitBonus"]), "%s 基础命中正确" % sid)
			_expect(detail.size.x > 0 and detail.size.y > 0, "详情卡片有效尺寸")
			_expect(detail.get_global_rect().end.x <= dimensions.x + 1 and detail.get_global_rect().end.y <= dimensions.y + 1, "详情无视口溢出 %s" % dimensions)
			_expect(fields.size.x <= detail.size.x and fields.size.y > 0, "属性表有布局且无横向溢出")
			for field: Node in fields.get_children():
				_expect((field as Control).size.x > 0 and (field as Control).size.y > 0, "字段尺寸有效")
		var first_button := buttons.get_child(0) as Button
		first_button.grab_focus()
		await _settle()
		_expect(page.get("selected_skill_id") == SkillData.SKILL_LIST[0][&"id"], "键盘焦点同步选择")
		_expect(not bool(page.call("select_skill", &"missing_skill")), "拒绝未知技能")
		_expect(page.get("selected_skill_id") == SkillData.SKILL_LIST[0][&"id"], "未知技能不改变当前详情")
		for scroll: Node in page.find_children("*", "ScrollContainer", true, false):
			_expect((scroll as ScrollContainer).horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "禁止横向滚动")
		viewport.queue_free()
		await process_frame
	# 同时加载标题场景，确认新增入口的真实按钮与接线。
	var menu := load("res://scenes/Title.tscn").instantiate() as Control
	root.add_child(menu)
	await _settle()
	var entry := menu.find_child("SkillListButton", true, false) as Button
	_expect(entry != null and entry.pressed.is_connected(Callable(menu, "_on_skills")), "标题菜单已连接技能图鉴入口")
	current_scene = menu
	if entry != null:
		entry.pressed.emit()
		await _settle()
		_expect(current_scene != null and current_scene.scene_file_path == "res://scenes/SkillList.tscn", "菜单进入技能图鉴")
		if current_scene != null and current_scene.scene_file_path == "res://scenes/SkillList.tscn":
			var back := current_scene.find_child("BackButton", true, false) as Button
			back.pressed.emit()
			await _settle()
			_expect(current_scene.scene_file_path == "res://scenes/Title.tscn", "返回按钮回到菜单")
			var reopen := current_scene.find_child("SkillListButton", true, false) as Button
			reopen.pressed.emit()
			await _settle()
			var cancel := InputEventAction.new()
			cancel.action = &"ui_cancel"
			cancel.pressed = true
			current_scene.call("_unhandled_input", cancel)
			await _settle()
			_expect(current_scene.scene_file_path == "res://scenes/Title.tscn", "ESC 操作回到菜单")
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if restore_recorder:
		scene_changed.connect(recorder)
	if failures.is_empty():
		print("SKILL_LIST_CONTRACT_OK")
	else:
		printerr("SKILL_LIST_CONTRACT_FAILED: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)
