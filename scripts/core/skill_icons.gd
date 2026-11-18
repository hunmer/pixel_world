## core/skill_icons.gd — 技能图标目录（稳定 ID → 纹理；不复制技能战斗定义）
##
## 只负责「图标资源目录」：稳定 iconId（数字字符串 "01".."53"）到纹理路径的
## 显式映射、缓存与兜底。技能 ↔ 图标的绑定关系在 data/skills.json 的 iconId
## 字段，经 SkillData 规范化；战斗定义（伤害/MP/冷却等）仍以技能 JSON 配置为
## 唯一来源，本文件不涉及。
##
## 路径约定（显式列出，不按编号拼接）：
##   "01".."50" → assets/ui/skills/01.png … 50.png（既有切片，重切片文件名不变）
##   "51" → power_surge.png   "52" → guard.png   "53" → haste.png（新增语义命名）
## 稳定 ID 契约：ID 与文件的绑定关系永不因语义更名重排。
## 未知 iconId / 纹理缺失时回退 DEFAULT_ICON_ID 并 push_warning（明确兜底，不返回 null）。

class_name SkillIcons
extends RefCounted

## 兜底图标。未知 iconId / 加载失败统一回退到这里。
const DEFAULT_ICON_ID: StringName = &"01"

## 稳定 ID → 纹理路径（53 项，显式列出；新增图标只允许续在尾部）。
const ICON_PATHS := {
	&"01": "res://assets/ui/skills/01.png",
	&"02": "res://assets/ui/skills/02.png",
	&"03": "res://assets/ui/skills/03.png",
	&"04": "res://assets/ui/skills/04.png",
	&"05": "res://assets/ui/skills/05.png",
	&"06": "res://assets/ui/skills/06.png",
	&"07": "res://assets/ui/skills/07.png",
	&"08": "res://assets/ui/skills/08.png",
	&"09": "res://assets/ui/skills/09.png",
	&"10": "res://assets/ui/skills/10.png",
	&"11": "res://assets/ui/skills/11.png",
	&"12": "res://assets/ui/skills/12.png",
	&"13": "res://assets/ui/skills/13.png",
	&"14": "res://assets/ui/skills/14.png",
	&"15": "res://assets/ui/skills/15.png",
	&"16": "res://assets/ui/skills/16.png",
	&"17": "res://assets/ui/skills/17.png",
	&"18": "res://assets/ui/skills/18.png",
	&"19": "res://assets/ui/skills/19.png",
	&"20": "res://assets/ui/skills/20.png",
	&"21": "res://assets/ui/skills/21.png",
	&"22": "res://assets/ui/skills/22.png",
	&"23": "res://assets/ui/skills/23.png",
	&"24": "res://assets/ui/skills/24.png",
	&"25": "res://assets/ui/skills/25.png",
	&"26": "res://assets/ui/skills/26.png",
	&"27": "res://assets/ui/skills/27.png",
	&"28": "res://assets/ui/skills/28.png",
	&"29": "res://assets/ui/skills/29.png",
	&"30": "res://assets/ui/skills/30.png",
	&"31": "res://assets/ui/skills/31.png",
	&"32": "res://assets/ui/skills/32.png",
	&"33": "res://assets/ui/skills/33.png",
	&"34": "res://assets/ui/skills/34.png",
	&"35": "res://assets/ui/skills/35.png",
	&"36": "res://assets/ui/skills/36.png",
	&"37": "res://assets/ui/skills/37.png",
	&"38": "res://assets/ui/skills/38.png",
	&"39": "res://assets/ui/skills/39.png",
	&"40": "res://assets/ui/skills/40.png",
	&"41": "res://assets/ui/skills/41.png",
	&"42": "res://assets/ui/skills/42.png",
	&"43": "res://assets/ui/skills/43.png",
	&"44": "res://assets/ui/skills/44.png",
	&"45": "res://assets/ui/skills/45.png",
	&"46": "res://assets/ui/skills/46.png",
	&"47": "res://assets/ui/skills/47.png",
	&"48": "res://assets/ui/skills/48.png",
	&"49": "res://assets/ui/skills/49.png",
	&"50": "res://assets/ui/skills/50.png",
	&"51": "res://assets/ui/skills/power_surge.png",
	&"52": "res://assets/ui/skills/guard.png",
	&"53": "res://assets/ui/skills/haste.png",
}

static var _cache: Dictionary = {}   # { icon_id -> Texture2D }
static var _warned: Dictionary = {}  # { icon_id -> true } 兜底告警去重


## 全部稳定 iconId（保持目录声明顺序）。
static var ICON_LIST: Array:
	get:
		return ICON_PATHS.keys()


static func has_icon(icon_id: StringName) -> bool:
	return ICON_PATHS.has(icon_id)


## iconId → 纹理路径；未知 ID 返回 ""。
static func icon_path(icon_id: StringName) -> String:
	return String(ICON_PATHS.get(icon_id, ""))


## 取图标纹理（带缓存；同一 ID 返回同一实例，供 UI 直接比较/赋值）。
## 未知 ID 或纹理加载失败 → 回退 DEFAULT_ICON_ID 纹理并 push_warning（每 ID 一次）。
static func get_texture(icon_id: StringName) -> Texture2D:
	var key := icon_id if has_icon(icon_id) else DEFAULT_ICON_ID
	if not has_icon(icon_id):
		_warn_fallback(icon_id, "未知技能图标 ID")
	if _cache.has(key):
		return _cache[key]
	var path := icon_path(key)
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		_warn_fallback(icon_id, "图标纹理加载失败: %s" % path)
		if key != DEFAULT_ICON_ID:
			return get_texture(DEFAULT_ICON_ID)
		return null
	_cache[key] = tex
	return tex


static func _warn_fallback(icon_id: StringName, reason: String) -> void:
	if _warned.has(icon_id):
		return
	_warned[icon_id] = true
	push_warning("SkillIcons: %s（%s），回退默认图标 %s" % [reason, String(icon_id), String(DEFAULT_ICON_ID)])
