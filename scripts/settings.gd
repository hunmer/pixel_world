## settings.gd — 全局用户偏好（autoload 单例）
##
## 用 ConfigFile 持久化到 user://settings.cfg，下次启动自动加载。
## 存「战斗模式」开关（B1/B2）与 AI 难度档（敌方/玩家托管）。
## 难度校验用内联名单而非 preload AIDifficulty：autoload 尽量少依赖，且
## 非法值统一宽容回 "normal"。

extends Node

const PATH := "user://settings.cfg"
const SECTION_BATTLE := "battle"
const KEY_INLINE_MODE := "inline_mode"
const KEY_ENEMY_AI_DIFFICULTY := "enemy_ai_difficulty"
const KEY_HOST_AI_DIFFICULTY := "host_ai_difficulty"
const KEY_IMMERSIVE_PRESENTATION := "immersive_presentation"

## 合法难度名单（与 scripts/systems/ai_difficulty.gd 的 VALID 保持一致）
const AI_DIFFICULTY_VALID: Array = ["novice", "normal", "hard", "nightmare"]

## 战斗模式：true=就地（B1，单位挂世界场景）/ false=独立场景（B2，切 Battle.tscn）
var battle_inline_mode: bool = true

## 敌方 AI 难度档（novice/normal/hard/nightmare，缺省 normal=历史行为）
var enemy_ai_difficulty: String = "normal"
## 玩家托管 AI 难度档（同上）
var host_ai_difficulty: String = "normal"
## 沉浸式交战镜头：默认关闭，保留原战术推近；战斗中也可切换。
var battle_immersive_presentation: bool = false


func _ready() -> void:
	_load()


func _load() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(PATH)
	if err != OK:
		return  # 文件不存在或解析失败，用默认值
	battle_inline_mode = cfg.get_value(SECTION_BATTLE, KEY_INLINE_MODE, true)
	enemy_ai_difficulty = _clamp_difficulty(cfg.get_value(SECTION_BATTLE, KEY_ENEMY_AI_DIFFICULTY, "normal"))
	host_ai_difficulty = _clamp_difficulty(cfg.get_value(SECTION_BATTLE, KEY_HOST_AI_DIFFICULTY, "normal"))
	battle_immersive_presentation = bool(cfg.get_value(SECTION_BATTLE, KEY_IMMERSIVE_PRESENTATION, false))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_BATTLE, KEY_INLINE_MODE, battle_inline_mode)
	cfg.set_value(SECTION_BATTLE, KEY_ENEMY_AI_DIFFICULTY, enemy_ai_difficulty)
	cfg.set_value(SECTION_BATTLE, KEY_HOST_AI_DIFFICULTY, host_ai_difficulty)
	cfg.set_value(SECTION_BATTLE, KEY_IMMERSIVE_PRESENTATION, battle_immersive_presentation)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("[Settings] 保存失败: %s (%d)" % [PATH, err])


## 非法/缺失/非字符串难度回 "normal"（运行时宽容；声明式 CLI 侧由 loader 严格报错）。
## ConfigFile 可能存出任意类型（数字/bool/数组），先 typeof 防御再转字符串。
func _clamp_difficulty(value) -> String:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return "normal"
	var s := String(value)
	return s if AI_DIFFICULTY_VALID.has(s) else "normal"


## 设置战斗模式并持久化。true=就地, false=独立场景。
func set_battle_inline_mode(value: bool) -> void:
	if battle_inline_mode == value:
		return
	battle_inline_mode = value
	save()
	print("[Settings] 战斗模式 → %s" % ("就地" if value else "独立场景"))


## 设置 AI 难度档并持久化。kind: "enemy"/"host"；非法难度忽略（不改配置）。
func set_ai_difficulty(kind: String, difficulty: String) -> void:
	if not AI_DIFFICULTY_VALID.has(difficulty):
		return
	match kind:
		"enemy":
			if enemy_ai_difficulty == difficulty:
				return
			enemy_ai_difficulty = difficulty
		"host":
			if host_ai_difficulty == difficulty:
				return
			host_ai_difficulty = difficulty
		_:
			return
	save()
	print("[Settings] AI 难度（%s）→ %s" % [kind, difficulty])


## 设置沉浸式交战镜头并持久化；false 会请求正在演出的镜头恢复战术视角。
func set_battle_immersive_presentation(value: bool) -> void:
	if battle_immersive_presentation == value:
		return
	battle_immersive_presentation = value
	save()
	print("[Settings] 沉浸式演出 → %s" % ("开启" if value else "关闭"))
