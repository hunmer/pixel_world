## settings.gd — 全局用户偏好（autoload 单例）
##
## 用 ConfigFile 持久化到 user://settings.cfg，下次启动自动加载。
## 目前只存「战斗模式」开关：就地（B1）/ 独立场景（B2）。

extends Node

const PATH := "user://settings.cfg"
const SECTION_BATTLE := "battle"
const KEY_INLINE_MODE := "inline_mode"

## 战斗模式：true=就地（B1，单位挂世界场景）/ false=独立场景（B2，切 Battle.tscn）
var battle_inline_mode: bool = true


func _ready() -> void:
	_load()


func _load() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(PATH)
	if err != OK:
		return  # 文件不存在或解析失败，用默认值
	battle_inline_mode = cfg.get_value(SECTION_BATTLE, KEY_INLINE_MODE, true)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_BATTLE, KEY_INLINE_MODE, battle_inline_mode)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("[Settings] 保存失败: %s (%d)" % [PATH, err])


## 设置战斗模式并持久化。true=就地, false=独立场景。
func set_battle_inline_mode(value: bool) -> void:
	if battle_inline_mode == value:
		return
	battle_inline_mode = value
	save()
	print("[Settings] 战斗模式 → %s" % ("就地" if value else "独立场景"))
