## core/status_icons.gd — 状态图标目录（buff → 稳定图标 ID → 纹理）
##
## 只负责「状态图标资源目录」与 buff → 图标 ID 的稳定推导，不复制战斗定义：
##   正面 str/def/spd → power_up / defense_up / speed_up
##   负面 def → defense_down；其余正/负面 → 通用 buff / debuff
## buff 数据结构（scripts/systems/buff_system.gd）{ stat, value, turns, label }，
## 图标由 stat+value 即时推导，不给 buff 增加冗余图标字段（结算/存档零改动）。
## value==0 或 turns<=0（到期/旧档残留）返回 &""，调用方应过滤不显示。
## 稳定 ID 契约：ID 与文件的绑定关系永不因语义更名重排。
## 素材缺失/未知 ID 时 get_texture 返回 null 并一次性告警，调用方隐藏该槽位，
## 不得以其它图标伪装成功。

class_name StatusIcons
extends RefCounted

## 稳定 ID → 纹理路径（显式列出，不拼接；新增图标只允许续在尾部）。
const ICON_PATHS := {
	&"power_up": "res://assets/ui/status/power_up.png",
	&"defense_up": "res://assets/ui/status/defense_up.png",
	&"speed_up": "res://assets/ui/status/speed_up.png",
	&"defense_down": "res://assets/ui/status/defense_down.png",
	&"buff": "res://assets/ui/status/buff.png",
	&"debuff": "res://assets/ui/status/debuff.png",
}

static var _cache: Dictionary = {}   # { icon_id -> Texture2D 或 null（已探测缺失） }
static var _warned: Dictionary = {}  # { icon_id -> true } 告警去重


## 全部稳定 iconId（保持目录声明顺序）。
static var ICON_LIST: Array:
	get:
		return ICON_PATHS.keys()


static func has_icon(icon_id: StringName) -> bool:
	return ICON_PATHS.has(icon_id)


## iconId → 纹理路径；未知 ID 返回 ""。
static func icon_path(icon_id: StringName) -> String:
	return String(ICON_PATHS.get(icon_id, ""))


## buff → 稳定图标 ID。零值 / 到期（turns<=0）/ 字段缺失的旧字典返回 &""（应过滤）。
## stat 兼容 String 与 StringName 键值（JSON 存档载入后为 String）。
static func icon_id_for_buff(buff: Dictionary) -> StringName:
	var turns := int(buff.get(&"turns", 0))
	if turns <= 0:
		return &""
	var value := int(buff.get(&"value", 0))
	if value == 0:
		return &""
	var stat := StringName(String(buff.get(&"stat", &"")))
	if value > 0:
		match stat:
			&"str":
				return &"power_up"
			&"def":
				return &"defense_up"
			&"spd":
				return &"speed_up"
			_:
				return &"buff"
	match stat:
		&"def":
			return &"defense_down"
		_:
			return &"debuff"


## 取图标纹理（带缓存；同一 ID 返回同一实例）。
## 未知 ID / 素材缺失 → 返回 null（并每 ID 告警一次）；null 也会被缓存，
## 避免素材未就绪期间重复探测。调用方（状态行）对 null 隐藏槽位。
static func get_texture(icon_id: StringName) -> Texture2D:
	if not has_icon(icon_id):
		_warn_once(icon_id, "未知状态图标 ID")
		return null
	if _cache.has(icon_id):
		return _cache[icon_id]
	var path := icon_path(icon_id)
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		_warn_once(icon_id, "状态图标素材缺失: %s" % path)
	_cache[icon_id] = tex
	return tex


## 供测试/工具重置缓存（运行期不需要）。
static func clear_cache() -> void:
	_cache.clear()
	_warned.clear()


static func _warn_once(icon_id: StringName, reason: String) -> void:
	if _warned.has(icon_id):
		return
	_warned[icon_id] = true
	push_warning("StatusIcons: %s（%s），该状态图标槽位将隐藏" % [reason, String(icon_id)])
