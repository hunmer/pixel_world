## core/item_icons.gd — 物品图标目录（稳定 ID → 纹理；不复制物品战斗定义）
##
## 只负责「图标资源目录」：稳定 iconId（数字字符串 "01".."08"）到纹理路径的
## 显式映射、缓存与兜底。物品 ↔ 图标的绑定关系在 data/items.json 的 iconId
## 字段，经 ItemData 规范化；战斗定义（伤害/射程/uses 等）仍以物品 JSON 配置
## 为唯一来源，本文件不涉及。
##
## 路径约定（显式列出，不按编号拼接）：
##   "01".."08" → assets/ui/items/01.png … 08.png（64x64，S1 LibTV 切片入库）
## 稳定 ID 契约：ID 与文件的绑定关系永不因语义更名重排；新增图标只允许续在尾部。
## 未知 iconId / 纹理缺失时回退 DEFAULT_ICON_ID 并 push_warning（每 ID 一次）。
## 与 SkillIcons 不同：默认图标也加载失败时返回非 null 应急纹理（品红占位，
## 缺资源经典标记），绝不返回 null —— 战斗菜单 b.icon 直接赋值，null 只会
## 静默退化成无图标；应急纹理让「连兜底都坏」保持可见。

class_name ItemIcons
extends RefCounted

## 兜底图标。未知 iconId / 加载失败统一回退到这里。
const DEFAULT_ICON_ID: StringName = &"01"

## 稳定 ID → 纹理路径（8 项，显式列出；新增图标只允许续在尾部）。
const ICON_PATHS := {
	&"01": "res://assets/ui/items/01.png",
	&"02": "res://assets/ui/items/02.png",
	&"03": "res://assets/ui/items/03.png",
	&"04": "res://assets/ui/items/04.png",
	&"05": "res://assets/ui/items/05.png",
	&"06": "res://assets/ui/items/06.png",
	&"07": "res://assets/ui/items/07.png",
	&"08": "res://assets/ui/items/08.png",
}

## 应急纹理参数：8x8 品红（缺资源经典标记，非 UI 色板值，纯可见性信号）。
const EMERGENCY_SIZE := 8
const EMERGENCY_COLOR := Color(1.0, 0.0, 1.0)

static var _cache: Dictionary = {}       # { icon_id -> Texture2D }
static var _warned: Dictionary = {}      # { icon_id -> true } 兜底告警去重
static var _emergency_tex: Texture2D = null

## 测试缝（最小隔离加载缝）：置为有效 Callable(path) -> Texture2D 时替代
## ResourceLoader 探测+加载，供契约模拟「图标文件缺失」分支；用完必须复位。
static var _load_hook: Callable = Callable()


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
## 未知 ID 或纹理加载失败 → 回退 DEFAULT_ICON_ID 纹理并 push_warning（每 ID 一次）；
## 默认图标也加载失败 → 非 null 应急纹理（同实例），绝不返回 null。
static func get_texture(icon_id: StringName) -> Texture2D:
	var key := icon_id if has_icon(icon_id) else DEFAULT_ICON_ID
	if not has_icon(icon_id):
		_warn_fallback(icon_id, "未知物品图标 ID")
	if _cache.has(key):
		return _cache[key]
	var tex := _load_texture(icon_path(key))
	if tex == null:
		_warn_fallback(icon_id, "图标纹理加载失败: %s" % icon_path(key))
		if key != DEFAULT_ICON_ID:
			return get_texture(DEFAULT_ICON_ID)
		return _emergency_texture()
	_cache[key] = tex
	return tex


## 单点加载（测试缝入口）：默认走 ResourceLoader 探测 + load。
static func _load_texture(path: String) -> Texture2D:
	if _load_hook.is_valid():
		return _load_hook.call(path) as Texture2D
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## 默认图标也坏时的应急纹理：8x8 品红 ImageTexture，非 null 且同实例。
static func _emergency_texture() -> Texture2D:
	if _emergency_tex == null:
		var img := Image.create(EMERGENCY_SIZE, EMERGENCY_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(EMERGENCY_COLOR)
		_emergency_tex = ImageTexture.create_from_image(img)
	return _emergency_tex


static func _warn_fallback(icon_id: StringName, reason: String) -> void:
	if _warned.has(icon_id):
		return
	_warned[icon_id] = true
	push_warning("ItemIcons: %s（%s），回退默认图标 %s" % [reason, String(icon_id), String(DEFAULT_ICON_ID)])
