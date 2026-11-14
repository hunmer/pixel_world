## scenes/scene_args.gd — 场景间传参（autoload 单例）
## Godot change_scene 不带参，用一个全局单例暂存待传递的数据。

extends Node

const StartupConfigScript = preload("res://scripts/scenes/startup_config.gd")
var startup_config := StartupConfigScript.new()
var startup_consumed: bool = false


func _ready() -> void:
	get_tree().scene_changed.connect(_record_current_scene)
	# F6 直接运行场景也应记录；初始场景不一定触发 scene_changed。
	_record_current_scene.call_deferred()


func _record_current_scene() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null or scene.scene_file_path == StartupConfigScript.GAME_SCENE:
		return
	startup_consumed = true
	startup_config.record_scene(scene.scene_file_path)

## 战斗参数：{ chapter, return_to }
var battle_args: Dictionary = {}
## 关卡选择传给 LevelPreload 的 levelId
var pending_level_id: String = ""

## LevelSelect 用：编辑器传回的来源场景
var level_select_return_to: String = "res://scenes/Title.tscn"

## MapEditor 用：返回的来源场景（Game 入口设为 Game.tscn；世界 E 键保持默认回世界）
var map_editor_return_to: String = "res://main.tscn"
