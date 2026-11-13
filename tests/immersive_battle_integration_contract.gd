## tests/immersive_battle_integration_contract.gd — 真实 Battle/SkillSystem/ActionAnim 的沉浸镜头边界。
## 通过 runtime_read_state("immersive_integration") 读取断言；SceneArgs 使用真实 JSON 战场且不写战旗存档。
extends Node2D

const BattleScene = preload("res://scenes/Battle.tscn")
const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")

var _result: Dictionary = {"finished": false, "passed": false, "checks": []}


func _ready() -> void:
	Engine.set_meta("breakpoint_state", {"immersive_integration": func(_args: Array = []): return _result})
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	_result["checks"].append({"label": label, "passed": condition})


func _wait_state(rig, wanted: int) -> void:
	# headless 可能一秒跑数千帧；超时必须按 wall clock，不能用帧数代替。
	var started := Time.get_ticks_msec()
	while rig.get_state() != wanted and Time.get_ticks_msec() - started < 15000:
		await rig.state_changed


func _run() -> void:
	var loaded: Dictionary = BattlefieldLoaderScript.load_battlefield("res://data/battlefields/arena_1v1.json")
	_check(bool(loaded.get("ok", false)), "真实 JSON 战场加载")
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	var old_setting: bool = Settings.battle_immersive_presentation
	Settings.set_battle_immersive_presentation(false)
	SceneArgs.battle_args = {
		"chapter": loaded["chapter"],
		"return_to": "res://main.tscn",
		"hosting": false,
		"save_identity": "",
	}
	var battle = BattleScene.instantiate()
	add_child(battle)
	await battle.battle_ready
	var rig = battle.get_node("ImmersiveCamera")
	var camera: Camera3D = battle.board.camera
	var caster: Dictionary = battle.chapter.playerUnits[0]
	_check(not rig.enabled and not battle.battle_ui.immersive_toggle.button_pressed, "真实战斗默认关闭沉浸")
	var original: Dictionary = rig._capture_camera()
	await battle._resolve_skill(caster, [caster], &"guard")
	_assert_restored(rig, camera, original, "默认关闭的真实技能保持原相机")
	_check(battle.action_anim._camera_state.is_empty(), "默认 ActionAnim 相机快照正常清理")
	battle.battle_ui.immersive_toggle.button_pressed = true
	_check(rig.enabled and Settings.battle_immersive_presentation, "战斗中通过真实开关开启沉浸")

	# ACTIVE 关闭：当前 SkillSystem→ActionAnim 完整收尾后，才由 end() 恢复战术快照。
	battle._resolve_skill(caster, [caster], &"guard")
	await _wait_state(rig, 2)
	_check(rig.get_state() == 2, "真实技能进入 ACTIVE")
	battle.battle_ui.immersive_toggle.button_pressed = false
	_check(rig.get_state() == 2, "ACTIVE 关闭不与 ActionAnim size 快照竞争")
	await _wait_state(rig, 0)
	_assert_restored(rig, camera, original, "真实技能 ACTIVE 关闭")
	_check(battle.action_anim._camera_state.is_empty(), "ActionAnim 相机快照已清理")

	# ENTERING skip：真实 Battle 输入路径先跳过镜头，再把同一跳过传给 ActionAnim.play。
	battle.battle_ui.immersive_toggle.button_pressed = true
	battle._resolve_skill(caster, [caster], &"guard")
	await _wait_state(rig, 1)
	_check(rig.get_state() == 1, "真实技能进入 ENTERING")
	battle._skip_action_presentation()
	await _wait_state(rig, 0)
	_assert_restored(rig, camera, original, "真实进入期跳过")
	_check(battle.action_anim._skipped, "进入期跳过同步跳过真实 ActionAnim")

	# ENTERING 关闭：begin 等恢复结束才启动普通 ActionAnim，最终不得留下中间 size。
	battle.battle_ui.immersive_toggle.button_pressed = true
	battle._resolve_skill(caster, [caster], &"guard")
	await _wait_state(rig, 1)
	battle.battle_ui.immersive_toggle.button_pressed = false
	await _wait_state(rig, 0)
	_assert_restored(rig, camera, original, "真实进入期关闭")
	_check(not battle.action_anim._skipped, "进入期关闭只恢复镜头，不错误跳过动作")

	Settings.set_battle_immersive_presentation(old_setting)
	SceneArgs.battle_args = {}
	battle.queue_free()
	_finish()


func _assert_restored(rig, camera: Camera3D, original: Dictionary, label: String) -> void:
	_check(rig.get_state() == 0, label + "：INACTIVE")
	_check(is_equal_approx(camera.size, float(original["size"])), label + "：size")
	_check(camera.global_transform.is_equal_approx(original["transform"]), label + "：position/rotation")
	_check(is_equal_approx(camera.elevation_radians, float(original["elevation"])), label + "：elevation")
	_check(is_equal_approx(camera.yaw_radians, float(original["yaw"])), label + "：yaw")
	_check(is_equal_approx(camera.presentation_distance, float(original["distance"])), label + "：distance")
	_check(camera.presentation_offset.is_equal_approx(original["presentation"]), label + "：presentation_offset")


func _finish() -> void:
	var passed := true
	for check in _result["checks"]:
		passed = passed and bool(check["passed"])
	_result["passed"] = passed
	_result["finished"] = true
	print("IMMERSIVE_INTEGRATION ", "PASS" if passed else "FAIL", " checks=", _result["checks"].size())
