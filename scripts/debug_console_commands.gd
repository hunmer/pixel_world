## debug_console_commands.gd — PankuConsole 调试命令集（控制台里以 dbg.* 调用）
##
## 挂在主场景根下（main.tscn 的 DebugConsoleCommands 节点），_ready 时把自身
## 注册进 Panku 表达式环境（Panku.gd_exprenv.register_env("dbg", self)）。
## 游戏内按 `~` 呼出控制台后可直接执行 dbg.list_battlefields()、dbg.battlefield("arena_1v1") 等。
## 本脚本只做入口转发与只读查询，不含业务逻辑；Panku 未启用（如 release 导出）时静默跳过。

extends Node

const BattlefieldLoaderScript := preload("res://scripts/core/battlefield_loader.gd")

const _HELP_help := "列出 dbg 的全部调试命令。"
const _HELP_list_battlefields := "扫描并返回全部 JSON 战场条目（res://data/battlefields + user://battlefields）。"
const _HELP_battlefield := "按 id 或路径进入 JSON 战场（独立场景模式）。例：dbg.battlefield(\"arena_1v1\")。"
const _HELP_editor := "打开战场地图编辑器（等价主界面按 E）。"
const _HELP_enter_battle := "就地进入战旗战斗（等价按 P，需在世界中）。"
const _HELP_battle_mode := "无参查询战斗模式；传 \"inline\"（B1 就地）或 \"scene\"（B2 独立场景）切换并持久化。"
const _HELP_player := "返回玩家世界格坐标与当前世界种子（只读）。"
const _HELP_time_scale := "无参查询 Engine.time_scale；传正数设置（1=正常速度）。"


func _ready() -> void:
	var panku := get_node_or_null("/root/Panku")
	if panku == null:
		print("[dbg] Panku 控制台未启用，调试命令不注册")
		return
	var env: Object = panku.get("gd_exprenv")
	if env == null:
		push_warning("[dbg] Panku.gd_exprenv 不可用，调试命令不注册")
		return
	env.call("register_env", "dbg", self)
	print("[dbg] 调试命令已注册：控制台按 ~ 呼出，dbg.help() 查看命令")


## 场景根（Main）。节点保存在 main.tscn 里，实例化后 owner 即场景根。
func _main() -> Node:
	var m := owner as Node
	if m == null:
		push_warning("[dbg] owner 不是主场景根（main.tscn 未实例化完整？）")
	return m


func help() -> Array:
	return [
		"dbg.help() — 本列表",
		"dbg.list_battlefields() — JSON 战场列表",
		'dbg.battlefield("arena_1v1") — 进入 JSON 战场（B2）',
		"dbg.editor() — 打开地图编辑器",
		"dbg.enter_battle() — 就地战旗（B1，等价按 P）",
		'dbg.battle_mode() / dbg.battle_mode("inline"|"scene") — 查询/切换战斗模式',
		"dbg.player() — 玩家格坐标 + 世界种子",
		"dbg.time_scale() / dbg.time_scale(2.0) — 查询/设置游戏速度",
	]


func list_battlefields() -> Array:
	var out: Array = []
	for e in BattlefieldLoaderScript.list_battlefields():
		var entry: Dictionary = e
		if String(entry.get("error", "")) != "":
			out.append("%s  ✗ %s" % [entry["file"], entry["error"]])
		else:
			out.append("%s  %s  %dx%d 玩家%d/敌%d" % [
				entry["name"], entry["path"], entry["width"], entry["height"],
				entry["players"], entry["enemies"],
			])
	return out


func battlefield(id_or_path: String) -> String:
	var target := ""
	if id_or_path.is_absolute_path() or FileAccess.file_exists(id_or_path):
		target = id_or_path
	else:
		for e in BattlefieldLoaderScript.list_battlefields():
			var entry: Dictionary = e
			if String(entry.get("id", "")) == id_or_path \
					or String(entry["file"]).get_basename() == id_or_path:
				target = String(entry["path"])
				break
	if target.is_empty():
		return "[dbg] 找不到战场：%s（用 dbg.list_battlefields() 查看可用项）" % id_or_path
	var m := _main()
	if m == null or not m.has_method("_enter_battlefield"):
		return "[dbg] 主场景未就绪，无法进入战场"
	m.call("_enter_battlefield", target)
	return "[dbg] 进入战场：%s" % target


func editor() -> String:
	var m := _main()
	if m == null or not m.has_method("_open_map_editor"):
		return "[dbg] 主场景未就绪，无法打开编辑器"
	m.call("_open_map_editor")
	return "[dbg] 打开地图编辑器"


func enter_battle() -> String:
	var m := _main()
	if m == null or not m.has_method("_enter_battle"):
		return "[dbg] 主场景未就绪，无法进入战斗"
	m.call("_enter_battle")
	return "[dbg] 就地进入战斗（B1）"


func battle_mode(mode := "") -> String:
	match mode:
		"inline", "b1":
			Settings.set_battle_inline_mode(true)
		"scene", "b2":
			Settings.set_battle_inline_mode(false)
		"":
			pass
		_:
			return '[dbg] 未知模式 "%s"，可用：inline/b1、scene/b2 或留空查询' % mode
	return "[dbg] 战斗模式 = %s（%s）" % [
		"inline" if Settings.battle_inline_mode else "scene",
		"就地 B1" if Settings.battle_inline_mode else "独立场景 B2",
	]


func player() -> Dictionary:
	var m := _main()
	if m == null:
		return {}
	return {
		"cell": m.get("_player_cell"),
		"seed": m.get("_current_seed"),
	}


func time_scale(s := -1.0) -> float:
	if s > 0.0:
		Engine.time_scale = s
	return Engine.time_scale
