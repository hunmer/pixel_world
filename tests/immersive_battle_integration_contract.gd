## tests/immersive_battle_integration_contract.gd — 真实 Battle 的独立沉浸舞台边界。
## 通过 runtime_read_state("immersive_integration") 读取断言；SceneArgs 使用真实 JSON 战场且不写战旗存档。
## 2026-11-19 起沉浸演出改为独立舞台（ImmersiveStage）：旧 ImmersiveBattleCamera rig 保留接线但
## 不再被战斗链驱动，本契约断言舞台路径与传统链路的边界与相机密闭性。
## 运行环境注意：--script 模式下 autoload 标识符不可用（编译期报 Identifier not found），
## 一律 root.get_node(...)；场景也用运行时 load()，避免主脚本编译期预载 battle.gd 链。
extends SceneTree

const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")

const ARENA := "res://data/battlefields/arena_1v1.json"

var _result: Dictionary = {"finished": false, "passed": false, "checks": []}


func _initialize() -> void:
	Engine.set_meta("breakpoint_state", {"immersive_integration": func(_args: Array = []): return _result})
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	_result["checks"].append({"label": label, "passed": condition})


func _snapshot(camera: Camera3D) -> Dictionary:
	return {
		"size": camera.size,
		"transform": camera.global_transform,
		"elevation": camera.elevation_radians,
		"yaw": camera.yaw_radians,
		"distance": camera.presentation_distance,
		"presentation": camera.presentation_offset,
	}


func _assert_camera_untouched(camera: Camera3D, original: Dictionary, label: String) -> void:
	_check(is_equal_approx(camera.size, float(original["size"])), label + "：size 零写入")
	_check(camera.global_transform.is_equal_approx(original["transform"]), label + "：position/rotation 零写入")
	_check(is_equal_approx(camera.elevation_radians, float(original["elevation"])), label + "：elevation 零写入")
	_check(is_equal_approx(camera.yaw_radians, float(original["yaw"])), label + "：yaw 零写入")
	_check(is_equal_approx(camera.presentation_distance, float(original["distance"])), label + "：distance 零写入")
	_check(camera.presentation_offset.is_equal_approx(original["presentation"]), label + "：presentation_offset 零写入")


func _reset_unit(unit: Dictionary, hp: int) -> void:
	unit[&"hp"] = hp
	unit[&"maxHp"] = maxi(hp, int(unit.get(&"maxHp", hp)))
	unit[&"hasActed"] = false
	unit[&"hasMoved"] = false
	unit[&"isDead"] = false


func _run() -> void:
	var loaded: Dictionary = BattlefieldLoaderScript.load_battlefield(ARENA)
	_check(bool(loaded.get("ok", false)), "真实 JSON 战场加载")
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	var settings: Node = root.get_node("Settings")
	var scene_args: Node = root.get_node("SceneArgs")
	var old_setting: bool = bool(settings.get("battle_immersive_presentation"))
	settings.call("set_battle_immersive_presentation", false)
	scene_args.set("battle_args", {
		"chapter": loaded["chapter"],
		"return_to": "res://main.tscn",
		"hosting": false,
		"save_identity": "",
	})
	var battle = load("res://scenes/Battle.tscn").instantiate()
	if battle.get_script() == null:
		_check(false, "battle.gd 编译失败，测试不能作为通过依据")
		_finish()
		return
	root.add_child(battle)
	await battle.battle_ready
	var stage = battle._immersive_stage
	var camera: Camera3D = battle.board.camera
	var caster: Dictionary = battle.chapter.playerUnits[0]
	battle.turn_director.set_pref(caster.id, "anim_speed", 8.0)
	_check(stage != null and not stage.is_enabled(), "真实战斗默认关闭沉浸舞台")
	_check(not battle.battle_ui.immersive_toggle.button_pressed, "默认开关未按下")
	var original: Dictionary = _snapshot(camera)
	var real_finished: Array = []
	battle.action_anim.finished.connect(func(_event, _skipped): real_finished.append(true))
	var started: Array = []
	var finished: Array = []
	stage.presentation_started.connect(func(_event): started.append(true))
	stage.presentation_finished.connect(func(_event, skipped): finished.append(skipped))

	# ① 默认关闭：自技能走传统链路，舞台零启动，真实相机只被传统链路使用后复原。
	await battle._resolve_skill(caster, [caster], &"guard")
	_check(started.is_empty(), "默认关闭不进沉浸舞台")
	_check(real_finished.size() == 1, "默认关闭走真实 ActionAnim 恰一次")
	_assert_camera_untouched(camera, original, "默认关闭的真实技能保持原相机")
	_check(battle.action_anim._camera_state.is_empty(), "默认 ActionAnim 相机快照正常清理")

	# ② 战斗中通过真实开关开启：UI 按钮 → 舞台启用；自技能整场进舞台，真实链路不被驱动。
	battle.battle_ui.immersive_toggle.button_pressed = true
	_check(stage.is_enabled() and bool(settings.get("battle_immersive_presentation")), "战斗中通过真实开关开启沉浸舞台")
	await battle._resolve_skill(caster, [caster], &"guard")
	_check(started.size() == 1, "开启后自技能进沉浸舞台")
	_check(finished.size() == 1 and not bool(finished[0]), "开启后舞台 finished 恰一次且非跳过")
	_check(real_finished.size() == 1, "舞台路径不驱动真实 ActionAnim")
	_assert_camera_untouched(camera, original, "舞台演出真实相机零写入")
	_check(not battle._immersive_camera.is_engaged(), "旧沉浸相机保持待命不被驱动")

	# ③ 演出中关闭开关：立即 request_skip 收尾，finished.skipped=true，状态不残留。
	var disable_state := {"fired": false}
	var skip_finished: Array = []
	stage.presentation_started.connect(func(_event):
		disable_state["fired"] = true
		battle.battle_ui.immersive_toggle.button_pressed = false)
	stage.presentation_finished.connect(func(_event, skipped): skip_finished.append(skipped))
	var attacker: Dictionary = caster
	var defender: Dictionary = {}
	for unit_value in battle.grid.units.values():
		var unit: Dictionary = unit_value
		if unit.get(&"faction", &"") == &"enemy" and not bool(unit.get(&"isDead", false)):
			defender = unit
			break
	_check(not defender.is_empty(), "存在敌方单位")
	_reset_unit(attacker, 999)
	_reset_unit(defender, 999)
	await battle._resolve_combat(attacker, defender, func() -> void: pass)
	_check(bool(disable_state["fired"]), "演出中关闭发生在舞台演出期间")
	_check(skip_finished.size() == 1 and bool(skip_finished[0]), "演出中关闭立即跳过收尾")
	_check(not stage.is_presenting(), "跳过收尾后舞台复位")
	_assert_camera_untouched(camera, original, "演出中关闭真实相机零写入")

	settings.call("set_battle_immersive_presentation", old_setting)
	scene_args.set("battle_args", {})
	battle.queue_free()
	await process_frame
	await process_frame
	_finish()


func _finish() -> void:
	var passed := true
	for check in _result["checks"]:
		passed = passed and bool(check["passed"])
		if not bool(check["passed"]):
			push_error("IMMERSIVE_INTEGRATION_FAIL: " + str(check["label"]))
	_result["passed"] = passed
	_result["finished"] = true
	print("IMMERSIVE_INTEGRATION ", "PASS" if passed else "FAIL", " checks=", _result["checks"].size())
	# breakpoint_state 持有捕获 self 的 Callable：引擎关机时 runtime bridge 若仍可见该 meta，
	# 会以 recursive_mutex abort 结束进程（2026-11-19 实测）。退出前必须摘除。
	Engine.remove_meta("breakpoint_state")
	await create_timer(0.1).timeout
	quit(0 if passed else 1)
