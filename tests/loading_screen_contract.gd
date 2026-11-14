## tests/loading_screen_contract.gd — 全局加载遮罩 LoadingScreen 与沉浸演出预热联动契约。
##
## 跑法：D:/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/loading_screen_contract.gd
## 覆盖：
##   1. autoload 注册（project.godot）+ 进程内实例唯一 + 启动默认隐藏（世界探索无遮罩）。
##   2. 场景结构：CanvasLayer 全屏遮罩；Label 右下角锚点（anchor 全 1 + offset 负值）；
##      全树 MOUSE_FILTER_IGNORE（不拦截输入）。
##   3. show/hide API：幂等、文字可设置/复位、展示态查询。
##   4. 时序：show → 至少一帧可见 → hide 跨帧（Engine.get_process_frames 断言）。
##   5. 取消路径：模拟 battle 预热协程中止后遮罩不残留。
##   6. 沉浸联动：ImmersiveBattleCamera.would_begin 门控（关闭/skip/空事件/无参战点）+
##      battle.gd / immersive_camera.gd 静态源检查（唯一接入点、不挪 prewarm）。
extends SceneTree

const ImmersiveCameraScript := preload("res://scripts/battle/immersive_camera.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _check_source(path: String, must_have: Array, must_not_have: Array) -> void:
	var src := FileAccess.open(path, FileAccess.READ)
	if src == null:
		_expect(false, "%s 可读" % path)
		return
	var text := src.get_as_text()
	src.close()
	for needle in must_have:
		_expect(text.contains(needle), "%s 应包含 %s" % [path, needle])
	for needle in must_not_have:
		_expect(not text.contains(needle), "%s 不应再包含 %s" % [path, needle])


func _assert_ignore_tree(node: Node) -> void:
	if node is Control:
		_expect(
			(node as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"遮罩拦截了输入: " + str(node.get_path())
		)
	for child in node.get_children():
		_assert_ignore_tree(child)


## 模拟 battle.gd::_prewarm_action_fx 的时序契约：遮罩先上屏再同步重活，最后隐藏。
func _simulate_prewarm_sequence(screen: CanvasLayer) -> void:
	screen.show_loading()
	await process_frame
	await process_frame
	# …同步预烘焙（此处省略实际烘焙）…
	screen.hide_loading()


func _run() -> void:
	# ---- 1. autoload 注册 / 唯一性 / 启动默认隐藏 ----
	var autoload_path := str(ProjectSettings.get_setting("autoload/LoadingScreen", ""))
	_expect(autoload_path.contains("LoadingScreen.tscn"),
		"autoload/LoadingScreen 指向 LoadingScreen.tscn（实际 %s）" % autoload_path)
	var autoload_count := 0
	var autoload_node: Node = null
	for child in root.get_children():
		if child.name == "LoadingScreen":
			autoload_count += 1
			autoload_node = child
	_expect(autoload_count == 1, "LoadingScreen 进程内实例唯一（实际 %d）" % autoload_count)
	if autoload_node != null:
		_expect(autoload_node is CanvasLayer, "autoload 节点是 CanvasLayer")
		_expect(not (autoload_node as CanvasLayer).visible,
			"进程启动时遮罩默认隐藏（世界探索/标题不留全屏遮罩）")

	# ---- 2. 场景结构 ----
	# 不用 preload：--script 模式下 preload 与 autoload 抢同一 tscn 路径会报 cyclic inclusion。
	var loading_screen_scene := load("res://scenes/LoadingScreen.tscn") as PackedScene
	_expect(loading_screen_scene != null, "LoadingScreen.tscn 可加载")
	var screen: CanvasLayer = loading_screen_scene.instantiate()
	root.add_child(screen)
	await process_frame  # 触发 _ready / @onready
	_expect(screen.layer == 100, "CanvasLayer.layer=100 盖住战斗/世界 UI（实际 %d）" % screen.layer)
	var backdrop := screen.get_node_or_null("Backdrop") as ColorRect
	var label := screen.get_node_or_null("LoadingLabel") as Label
	_expect(backdrop != null, "Backdrop(ColorRect) 存在")
	_expect(label != null, "LoadingLabel(Label) 存在")
	if backdrop != null:
		_expect(backdrop.anchor_right == 1.0 and backdrop.anchor_bottom == 1.0,
			"Backdrop 全屏锚点（anchor_right/bottom=1）")
	if label != null:
		_expect(label.anchor_left == 1.0 and label.anchor_top == 1.0
				and label.anchor_right == 1.0 and label.anchor_bottom == 1.0,
			"Label 四锚点=1（右下贴边，不依赖运行时读场景尺寸）")
		_expect(label.offset_left < 0.0 and label.offset_top < 0.0
				and label.offset_right < 0.0 and label.offset_bottom < 0.0,
			"Label offset 全负值（right/bottom margin）")
		_expect(label.text == "加载中…", "Label 默认文字「加载中…」（实际 %s）" % label.text)
	_assert_ignore_tree(screen)
	_expect(not screen.visible, "实例进场默认隐藏")

	# ---- 3. show/hide 幂等与文字 API ----
	screen.show_loading()
	_expect(screen.is_loading_shown(), "show 后处于展示态")
	screen.show_loading("烘焙特效…")
	screen.show_loading("烘焙特效…")
	_expect(screen.is_loading_shown(), "重复 show 幂等（仍展示）")
	if label != null:
		_expect(label.text == "烘焙特效…", "show 可设置文字（实际 %s）" % label.text)
	screen.set_loading_text("第二阶段")
	if label != null:
		_expect(label.text == "第二阶段", "set_loading_text 展示期改文字")
	screen.hide_loading()
	_expect(not screen.is_loading_shown(), "hide 后不再展示")
	_expect(not screen.visible, "hide 后 visible=false")
	if label != null:
		_expect(label.text == "加载中…", "hide 复位默认文字")
	screen.hide_loading()
	_expect(not screen.is_loading_shown(), "重复 hide 幂等（no-op）")

	# ---- 4. 时序：show→hide 跨至少一帧，展示期间持续可见 ----
	var frame_at_show := Engine.get_process_frames()
	screen.show_loading()
	await process_frame
	_expect(screen.is_loading_shown(), "展示期间第 1 帧后仍可见")
	await process_frame
	_expect(screen.is_loading_shown(), "展示期间第 2 帧后仍可见")
	screen.hide_loading()
	_expect(Engine.get_process_frames() > frame_at_show,
		"show→hide 跨至少一帧（%d → %d）" % [frame_at_show, Engine.get_process_frames()])

	# ---- 5. 取消/失败路径：预热协程中止后遮罩不残留 ----
	await _simulate_prewarm_sequence(screen)
	_expect(not screen.is_loading_shown(), "预热协程完成后遮罩隐藏")
	screen.show_loading()
	screen.hide_loading()
	_expect(not screen.is_loading_shown(), "手动取消（show 后立即 hide）不残留")

	# ---- 6. 沉浸联动：would_begin 门控 ----
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	var rig = ImmersiveCameraScript.new()
	root.add_child(rig)
	rig.setup(camera)
	var sprites: Dictionary = {}
	for unit_id in [&"hero", &"enemy"]:
		var sprite := Node3D.new()
		stage.add_child(sprite)
		sprites[unit_id] = sprite
	var event: Dictionary = {
		&"attacker_id": &"hero",
		&"primary_target_id": &"enemy",
		&"impacts": [{&"source_id": &"hero", &"target_id": &"enemy"}],
	}
	rig.set_enabled(false)
	_expect(not rig.would_begin(event, sprites, false),
		"沉浸演出关闭时 would_begin=false（不弹加载遮罩）")
	rig.set_enabled(true)
	_expect(rig.would_begin(event, sprites, false),
		"开启且有有效参战点 would_begin=true（弹加载遮罩）")
	_expect(not rig.would_begin(event, sprites, true),
		"预先 skip 时 would_begin=false")
	_expect(not rig.would_begin({}, sprites, false), "空事件 would_begin=false")
	_expect(not rig.would_begin(event, {}, false), "无有效参战点 would_begin=false")

	# ---- 7. 静态源检查：battle.gd 唯一接入点 + prewarm 不挪位 ----
	_check_source("res://scripts/scenes/battle.gd",
		["LoadingScreen.show_loading()", "LoadingScreen.hide_loading()",
			"would_begin(event, _unit_sprites, skipped)",
			"await get_tree().process_frame",
			"_prewarm_damage_fx_variants(impacts)",
			"func _prewarm_action_fx("],
		[])
	_check_source("res://scripts/battle/immersive_camera.gd",
		["func would_begin("], [])
	var battle_src := FileAccess.open("res://scripts/scenes/battle.gd", FileAccess.READ)
	if battle_src != null:
		var battle_text := battle_src.get_as_text()
		battle_src.close()
		_expect(battle_text.count("LoadingScreen.show_loading()") == 1,
			"battle.gd 只有一处 show_loading 调用（经 _prewarm_action_fx 复用）")

	screen.queue_free()
	rig.queue_free()
	stage.queue_free()
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("LOADING_SCREEN_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
