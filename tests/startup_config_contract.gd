## startup_config_contract.gd — 启动配置的读写、校验与手动修改保护契约。
extends SceneTree

const StartupConfigScript = preload("res://scripts/scenes/startup_config.gd")
const TEST_PATH := "user://startup_config_contract.cfg"
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var entry_script: Script = load("res://scripts/scenes/game_entry.gd")
	_check(entry_script != null and entry_script.can_instantiate(), "入口脚本应编译通过")
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	var config := StartupConfigScript.new(TEST_PATH)
	_check(config.launch_scene() == config.BATTLE_SCENE, "缺省保持最近战斗入口")
	config.record_scene("res://scenes/MapEditor.tscn")
	var loaded := StartupConfigScript.new(TEST_PATH)
	_check(loaded.launch_scene() == "res://scenes/MapEditor.tscn", "最近场景应跨实例恢复")
	var before: String = FileAccess.get_file_as_string(TEST_PATH)
	config.record_scene("res://scenes/SkillTest.tscn")
	_check(FileAccess.get_file_as_string(TEST_PATH) == before, "默认过滤场景不得写入配置")
	_check(config.last_scene == "res://scenes/MapEditor.tscn", "过滤场景应保留最近入口")
	var filters := ConfigFile.new()
	filters.load(TEST_PATH)
	filters.set_value("startup", "excluded_scenes", ["res://main.tscn"])
	filters.save(TEST_PATH)
	config.record_scene("res://main.tscn")
	_check(config.last_scene == "res://scenes/MapEditor.tscn", "应立即使用手动修改的过滤列表")
	filters.set_value("startup", "excluded_scenes", [])
	filters.save(TEST_PATH)
	config.record_scene("res://scenes/SkillTest.tscn")
	_check(config.last_scene == "res://scenes/SkillTest.tscn", "空列表允许记录全部场景")

	var manual := ConfigFile.new()
	_check(manual.load(TEST_PATH) == OK, "记录应生成可编辑配置")
	manual.set_value("startup", "auto_open_last_scene", false)
	manual.set_value("custom", "keep", 42)
	_check(manual.save(TEST_PATH) == OK, "模拟手动修改配置")
	config.record_scene("res://main.tscn")
	loaded.reload()
	_check(not loaded.auto_open_last_scene, "自动记录不得覆盖手动修改的开关")
	_check(loaded.last_scene == "res://main.tscn", "关闭自动打开仍记录最近场景")
	_check(loaded.launch_scene() == config.GAME_SCENE, "关闭自动打开应停在列表")
	manual.load(TEST_PATH)
	_check(manual.get_value("custom", "keep") == 42, "保存应保留无关字段")

	loaded.auto_open_last_scene = true
	loaded.last_scene = "res://scenes/not_a_real_scene.tscn"
	_check(loaded.launch_scene() == config.GAME_SCENE, "不存在的场景回退列表")
	loaded.last_scene = "user://arbitrary.tscn"
	_check(loaded.launch_scene() == config.GAME_SCENE, "拒绝项目外路径")
	loaded.last_scene = config.GAME_SCENE
	_check(loaded.launch_scene() == config.GAME_SCENE, "列表路径不应自动进入战斗")

	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("[broken")
	file.close()
	config.record_scene("res://main.tscn")
	_check(FileAccess.get_file_as_string(TEST_PATH) == "[broken", "损坏配置不得被自动覆盖")
	DirAccess.remove_absolute(TEST_PATH)
	print("[startup_config_contract] 失败数：%d" % _failures)
	quit(0 if _failures == 0 else 1)
