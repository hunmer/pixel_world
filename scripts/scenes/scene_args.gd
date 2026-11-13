## scenes/scene_args.gd — 场景间传参（autoload 单例）
## Godot change_scene 不带参，用一个全局单例暂存待传递的数据。

extends Node

## 战斗参数：{ chapter, return_to }
var battle_args: Dictionary = {}
## 关卡选择传给 LevelPreload 的 levelId
var pending_level_id: String = ""

## LevelSelect 用：编辑器传回的来源场景
var level_select_return_to: String = "res://scenes/Title.tscn"

## MapEditor 用：返回的来源场景（Game 入口设为 Game.tscn；世界 E 键保持默认回世界）
var map_editor_return_to: String = "res://main.tscn"
