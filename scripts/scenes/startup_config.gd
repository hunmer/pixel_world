## startup_config.gd — 可编辑的调试启动配置与最近场景记录。
extends RefCounted

const PROJECT_PATH := "res://config/startup.cfg"
const USER_PATH := "user://startup.cfg"
const GAME_SCENE := "res://scenes/Game.tscn"
const BATTLE_SCENE := "res://scenes/Battle.tscn"
const SECTION := "startup"

var path: String
var auto_open_last_scene: bool = true
var last_scene: String = BATTLE_SCENE
var excluded_scenes: Array[String] = ["res://scenes/SkillTest.tscn"]
var _config: ConfigFile = ConfigFile.new()
var _writable: bool = true


func _init(config_path: String = "") -> void:
	path = config_path if not config_path.is_empty() else (
		PROJECT_PATH if OS.has_feature("editor") else USER_PATH)
	reload()


func reload() -> void:
	_config = ConfigFile.new()
	var err: Error = _config.load(path)
	_writable = err == OK or err == ERR_FILE_NOT_FOUND
	if not _writable:
		push_warning("[StartupConfig] 配置无法读取，停在入口列表：%s (%d)" % [path, err])
		auto_open_last_scene = false
		return
	auto_open_last_scene = _config.get_value(SECTION, "auto_open_last_scene", true) == true
	var value: Variant = _config.get_value(SECTION, "last_scene", BATTLE_SCENE)
	last_scene = String(value).strip_edges() if value is String else ""
	excluded_scenes = ["res://scenes/SkillTest.tscn"]
	var excluded: Variant = _config.get_value(SECTION, "excluded_scenes", excluded_scenes)
	if excluded is Array or excluded is PackedStringArray:
		excluded_scenes = []
		for item: Variant in excluded:
			if item is String:
				excluded_scenes.append(String(item).strip_edges())


## 文件缺失或路径错误时安全回到入口列表。
func launch_scene() -> String:
	if not auto_open_last_scene or last_scene == GAME_SCENE:
		return GAME_SCENE
	if not last_scene.begins_with("res://") or not last_scene.ends_with(".tscn"):
		push_warning("[StartupConfig] last_scene 不是项目场景：%s" % last_scene)
		return GAME_SCENE
	if not ResourceLoader.exists(last_scene, "PackedScene"):
		push_warning("[StartupConfig] 场景不存在：%s" % last_scene)
		return GAME_SCENE
	return last_scene


## 保存时重新读取，保留用户在运行中修改的开关和额外配置项。
func record_scene(scene_path: String) -> void:
	reload()
	if not _writable or scene_path.is_empty() or excluded_scenes.has(scene_path):
		return
	if last_scene == scene_path and FileAccess.file_exists(path):
		return
	_config.set_value(SECTION, "auto_open_last_scene", auto_open_last_scene)
	_config.set_value(SECTION, "last_scene", scene_path)
	_config.set_value(SECTION, "excluded_scenes", excluded_scenes)
	var err: Error = _config.save(path)
	if err != OK:
		push_warning("[StartupConfig] 最近场景保存失败：%s (%d)" % [path, err])
		return
	last_scene = scene_path
	print("[StartupConfig] 最近场景 → %s" % last_scene)
