## tests/immersive_battle_camera_contract.gd — 沉浸镜头生命周期与真实右侧 Tab 的可执行合约。
## 由 runtime_spawn_peers(headless) 运行；结果通过 breakpoint_state 读取，不靠肉眼 print。
extends Node

const CameraScript = preload("res://scripts/iso/isometric_camera_3d.gd")
const IsoProjectionScript = preload("res://scripts/iso/iso_projection_3d.gd")
const ImmersiveCameraScript = preload("res://scripts/battle/immersive_camera.gd")
const SettingsTabScript = preload("res://scripts/battle/battle_settings_tab.gd")
const BattleUIScript = preload("res://scripts/battle/battle_ui.gd")

var _result: Dictionary = {"finished": false, "passed": false, "checks": []}


func _ready() -> void:
	var readers: Dictionary = Engine.get_meta("breakpoint_state", {})
	readers["immersive_contract"] = func(): return _result
	Engine.set_meta("breakpoint_state", readers)
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	_result["checks"].append({"label": label, "passed": condition})
	if not condition:
		_result["passed"] = false


func _run() -> void:
	await get_tree().process_frame
	var stage := Node3D.new()
	add_child(stage)
	var camera = CameraScript.new()
	stage.add_child(camera)
	camera.current = true
	camera.focus_position = Vector3(2.0, 0.7, -3.0)
	camera.size = 18.0
	camera.yaw_radians = IsoProjectionScript.CAMERA_YAW
	camera.target_yaw_radians = IsoProjectionScript.CAMERA_YAW
	camera.elevation_radians = IsoProjectionScript.CAMERA_ELEVATION
	camera.target_elevation_radians = IsoProjectionScript.CAMERA_ELEVATION
	_check(is_equal_approx(camera.presentation_distance, CameraScript.CAMERA_DISTANCE), "默认 presentation_distance 保持原 64")
	camera.presentation_distance = 6.0
	_check(is_equal_approx(camera.global_position.distance_to(camera.focus_position), 6.0), "演出距离真实改变 Camera3D 位置")
	camera.presentation_distance = CameraScript.CAMERA_DISTANCE
	camera.reserved_right_px = 360.0

	var sprites: Dictionary = {}
	for unit_id in [&"hero", &"enemy", &"aoe"]:
		var sprite := Node3D.new()
		stage.add_child(sprite)
		sprites[unit_id] = sprite
	sprites[&"hero"].position = Vector3.ZERO
	sprites[&"enemy"].position = Vector3(IsoProjectionScript.GRID_STEP, 0.0, 0.0)
	sprites[&"aoe"].position = Vector3(IsoProjectionScript.GRID_STEP * 3.0, 0.0, 0.0)
	var event: Dictionary = {
		&"attacker_id": &"hero",
		&"primary_target_id": &"enemy",
		&"impacts": [
			{&"source_id": &"hero", &"target_id": &"enemy"},
			{&"source_id": &"enemy", &"target_id": &"hero"},
			{&"source_id": &"hero", &"target_id": &"aoe"},
		],
	}
	var rig = ImmersiveCameraScript.new()
	add_child(rig)
	rig.setup(camera)
	var original: Dictionary = rig._capture_camera()
	await rig.begin(event, sprites, 4.0, false)
	_check(rig.get_state() == ImmersiveCameraScript.State.ACTIVE, "演出前 begin 可等待并进入 ACTIVE")
	_check(is_equal_approx(camera.elevation_radians, ImmersiveCameraScript.IMMERSIVE_ELEVATION), "进入 10° 近平视")
	var quarters := roundi((camera.yaw_radians - IsoProjectionScript.CAMERA_YAW) / (PI * 0.5))
	_check(quarters >= 0 and quarters <= 3, "yaw 仍是素材支持的四正交方向")
	_check(camera.size < float(original["size"]), "交战构图确实推近")
	_check(camera.presentation_distance < float(original["distance"]), "近平视同时缩短相机距离避免地形遮挡")
	var shot: Dictionary = rig._to
	var shot_focus: Vector3 = shot["focus"]
	_check(is_equal_approx(shot_focus.x, IsoProjectionScript.GRID_STEP * 1.5), "镜头焦点覆盖全部 impacts/AoE，而非只覆盖首要目标")

	# 模拟 ActionAnim 在原相机上的普通推近与恢复；沉浸恢复必须还原最初的战术快照。
	var engaged_size: float = camera.size
	camera.size /= 1.12
	camera.size = engaged_size
	await rig.end()
	_assert_restored(rig, camera, original, "完整演出 end")

	rig.begin(event, sprites, 1.0, false)
	await get_tree().process_frame
	_check(rig.get_state() == ImmersiveCameraScript.State.ENTERING, "进入期可接收跳过")
	rig.request_skip()
	_check(rig.consume_skip_request(), "进入期跳过传递给随后的 ActionAnim.play")
	_check(rig.get_state() == ImmersiveCameraScript.State.RESTORING, "进入期跳过平滑反向恢复")
	await rig.end()
	_assert_restored(rig, camera, original, "进入期跳过")

	await rig.begin(event, sprites, 4.0, false)
	engaged_size = camera.size
	camera.size /= 1.12
	rig.set_enabled(false)
	_check(rig.get_state() == ImmersiveCameraScript.State.ACTIVE, "ACTIVE 关闭等待当前完整动作边界，避免 size tween 竞争")
	camera.size = engaged_size # ActionAnim.return/_restore_camera_immediate 先写回交战快照。
	await rig.end()
	_assert_restored(rig, camera, original, "ACTIVE 关闭后的完整动作收尾")

	rig.set_enabled(true)
	rig.begin(event, sprites, 1.0, false)
	await get_tree().process_frame
	_check(rig.get_state() == ImmersiveCameraScript.State.ENTERING, "进入期关闭可从 ENTERING 反向")
	rig.set_enabled(false)
	_check(rig.get_state() == ImmersiveCameraScript.State.RESTORING, "进入期关闭立即开始恢复")
	while rig.get_state() == ImmersiveCameraScript.State.RESTORING:
		await rig.state_changed
	_assert_restored(rig, camera, original, "进入期关闭后、普通动作启动前")

	rig.set_enabled(true)
	await rig.begin(event, sprites, 4.0, false)
	rig.cancel()
	_assert_restored(rig, camera, original, "退出/取消立即清理")
	await rig.begin(event, sprites, 4.0, true)
	_check(not rig.is_engaged(), "预先跳过的托管事件不做双向转场")

	var tab := VBoxContainer.new()
	add_child(tab)
	var received: Array[bool] = []
	var toggle: CheckButton = SettingsTabScript.populate(tab, false, func(value: bool): received.append(value))
	_check(toggle.name == &"ImmersivePresentationToggle", "设置页暴露可断言开关")
	_check(toggle.text == "沉浸式演出" and not toggle.button_pressed, "沉浸式演出文案与默认关闭")
	toggle.button_pressed = true
	_check(received == [true], "开关切换发出真实回调")
	tab.queue_free()

	var ui = BattleUIScript.new()
	add_child(ui)
	ui.build(Callable(), Callable(), Callable())
	var tabs: TabContainer = ui.find_child("InfoTabs", true, false) as TabContainer
	_check(tabs != null and tabs.get_tab_count() == 5, "右侧现有 tabs 新增为五页")
	if tabs != null and tabs.get_tab_count() == 5:
		_check(tabs.get_tab_title(3) == "战场设置", "战场设置位于右侧 TabContainer")
	_check(ui.get("immersive_toggle") != null, "BattleUI 保留真实开关引用")

	var checks: Array = _result["checks"]
	var passed := true
	for check in checks:
		passed = passed and bool(check["passed"])
	_result["passed"] = passed
	_result["finished"] = true
	print("IMMERSIVE_CONTRACT ", "PASS" if passed else "FAIL", " checks=", checks.size())


func _assert_restored(rig, camera, original: Dictionary, label: String) -> void:
	_check(rig.get_state() == ImmersiveCameraScript.State.INACTIVE, label + "：INACTIVE")
	_check(camera.global_transform.is_equal_approx(original["transform"]), label + "：position/rotation 快照恢复")
	_check(is_equal_approx(camera.size, float(original["size"])), label + "：size 恢复")
	_check(is_equal_approx(camera.yaw_radians, float(original["yaw"])), label + "：yaw 恢复")
	_check(is_equal_approx(camera.target_yaw_radians, float(original["target_yaw"])), label + "：target yaw 恢复")
	_check(is_equal_approx(camera.elevation_radians, float(original["elevation"])), label + "：elevation 恢复")
	_check(camera.projection == int(original["projection"]), label + "：projection 恢复")
	_check(camera.presentation_offset.is_equal_approx(original["presentation"]), label + "：presentation_offset 恢复")
	_check(is_equal_approx(camera.presentation_distance, float(original["distance"])), label + "：distance 恢复")
