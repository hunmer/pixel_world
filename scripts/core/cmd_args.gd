## core/cmd_args.gd — 启动命令行参数解析（纯静态工具类，零依赖）
##
## 让场景能从启动命令行接收参数，不完全依赖硬编码。
## 用法示例（命令行）：
##   godot -d --path <project> res://scenes/BattleTest.tscn -- --no-hosting
##   godot -d --path <project> res://scenes/BattleTest.tscn --hosting=false
## 脚本里读取：
##   CmdArgs.get_bool("hosting", true)   # 默认 true，可用 --no-hosting / --hosting=false 关闭
##
## 解析规则：
##   --name            布尔标志 → true
##   --no-name         布尔标志 → false（等价 --name=false）
##   --name=value      键值对（value 为 true/false 时按布尔解释）
##   -d / 单短横项      忽略（如 Godot 的 -d）
##   已知 Godot 参数    忽略（--path / --scene / --main-pack / --rendering-method 等）
##
## 数据源：优先 OS.get_cmdline_user_args()（Godot 4 推荐，即 `--` 分隔后的用户参数），
## 兜底扫 OS.get_cmdline_args()，这样 CLI 加不加 `--` 都能用。

class_name CmdArgs
extends RefCounted

# Godot 自身会消费的参数，避免误读（值参数连同其值一起跳过）。
const _ENGINE_VALUE_ARGS: PackedStringArray = [
	"--path", "--scene", "--main-pack", "--rendering-method",
	"--rendering-driver", "--audio-driver", "--editor", "--import",
]

# 解析结果：name(String) -> { value: Variant, explicit: bool }
# - 布尔标志：value 为 bool
# - 键值对：  value 为 bool（true/false 字面量）或 String
# - explicit=true 表示该 name 在命令行里出现过
static var _args: Dictionary = {}
static var _parsed: bool = false


static func _parse_once() -> void:
	if _parsed:
		return
	_parsed = true

	# OS.get_cmdline_user_args() = `--` 之后的用户参数；OS.get_cmdline_args() 兜底。
	var raw := []
	raw.append_array(OS.get_cmdline_user_args())
	raw.append_array(OS.get_cmdline_args())

	var skip_next := false
	for i in raw.size():
		if skip_next:
			skip_next = false
			continue
		var tok: String = raw[i]
		if tok.begins_with("--"):
			# 引擎值参数：连同下一个 token（它的值）一起跳过
			if _ENGINE_VALUE_ARGS.has(tok):
				skip_next = true
				continue
			var name := ""
			var value: Variant = true  # 裸 --name 默认 true
			var eq := tok.find("=")
			if eq >= 0:
				name = tok.substr(2, eq - 2)
				var v := tok.substr(eq + 1)
				value = _coerce(v)
			else:
				name = tok.substr(2)
			# --no-xxx → 等价 xxx=false
			if name.begins_with("no-"):
				name = name.substr(3)
				value = false
			_args[name] = { "value": value, "explicit": true }
		# 单短横（-d 等）和非 -- 开头的裸 token（场景路径等）忽略


# 把字符串值解释成合适类型：仅 true/false 走布尔，其余保持字符串。
static func _coerce(v: String) -> Variant:
	match v.to_lower():
		"true", "1", "yes", "on":
			return true
		"false", "0", "no", "off":
			return false
		_:
			return v


## 该 name 是否在命令行里出现过（无论带不带值）。
static func has_flag(name: String) -> bool:
	_parse_once()
	return _args.has(name)


## 读取布尔参数。优先级：
##   --name=false / --no-name  → false
##   --name / --name=true      → true
##   未提供                     → default
static func get_bool(name: String, default: bool) -> bool:
	_parse_once()
	if not _args.has(name):
		return default
	var v: Variant = _args[name]["value"]
	if v is bool:
		return v
	# --name=字符串 的兜底：非空非 false 字面量视为 true
	if v is String:
		return _coerce(v) == true
	return default


## 读取字符串参数。未提供或为布尔标志时返回 default。
static func get_string(name: String, default: String) -> String:
	_parse_once()
	if not _args.has(name):
		return default
	var v: Variant = _args[name]["value"]
	if v is String:
		return v
	return default
