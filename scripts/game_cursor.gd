## game_cursor.gd — 全局游戏鼠标指针（autoload 单例）
##
## 基于 assets/ui/gen/split_anime 像素指针集（32×32）注册系统光标形状，
## 维护可切换的箭头三色风格，并向画廊等展示层提供指针库与预览接口；
## 未覆盖的形状（等待 / 忙碌等）保留系统默认。

extends Node

## 指针素材最长边（像素）；超过的素材按此边长等比缩放。
const _CURSOR_MAX_EDGE: int = 32

## 箭头风格表：风格名 → 素材（split_anime 三色箭头）。
const ARROW_STYLES: Dictionary = {
	"white": preload("res://assets/ui/gen/split_anime/cursor_arrow_white.png"),
	"blue": preload("res://assets/ui/gen/split_anime/cursor_arrow_blue.png"),
	"gold": preload("res://assets/ui/gen/split_anime/cursor_arrow_gold.png"),
}


## 各箭头风格的热点（箭头尖位置，随配色尖端像素微调）。
const _ARROW_HOTSPOTS: Dictionary = {
	"white": Vector2(3, 1),
	"blue": Vector2(3, 1),
	"gold": Vector2(2, 1),
}

## 启动时使用的默认箭头风格。
const DEFAULT_ARROW_STYLE: String = "white"

## 系统形状注册表：Godot CursorShape → {texture, hotspot}，语义按素材文件名对齐。
const _CURSORS: Dictionary = {
	Input.CURSOR_IBEAM: {
		"texture": preload("res://assets/ui/gen/split_anime/cursor_beam.png"),
		"hotspot": Vector2(15, 16),
	},
	Input.CURSOR_POINTING_HAND: {
		"texture": preload("res://assets/ui/gen/split_anime/cursor_hand_white.png"),
		"hotspot": Vector2(9, 2),
	},
	Input.CURSOR_CROSS: {
		"texture": preload("res://assets/ui/gen/split_anime/cursor_crosshair_white.png"),
		"hotspot": Vector2(15, 16),
	},
	Input.CURSOR_DRAG: {
		"texture": preload("res://assets/ui/gen/split_anime/cursor_grab_white.png"),
		"hotspot": Vector2(19, 15),
	},
	Input.CURSOR_MOVE: {
		"texture": preload("res://assets/ui/gen/split_anime/cursor_move.png"),
		"hotspot": Vector2(15, 15),
	},
	Input.CURSOR_FORBIDDEN: {
		"texture": preload("res://assets/ui/gen/split_anime/cursor_banned.png"),
		"hotspot": Vector2(16, 16),
	},
	Input.CURSOR_HELP: {
		"texture": preload("res://assets/ui/gen/split_anime/cursor_help.png"),
		"hotspot": Vector2(16, 16),
	},
	Input.CURSOR_HSIZE: {
		"texture": preload("res://assets/ui/gen/split_anime/cursor_resize_h.png"),
		"hotspot": Vector2(15, 15),
	},
	Input.CURSOR_VSIZE: {
		"texture": preload("res://assets/ui/gen/split_anime/cursor_resize_v.png"),
		"hotspot": Vector2(15, 16),
	},
	Input.CURSOR_FDIAGSIZE: {
		"texture": preload("res://assets/ui/gen/split_anime/cursor_resize_diag.png"),
		"hotspot": Vector2(16, 16),
	},
	Input.CURSOR_BDIAGSIZE: {
		"texture": preload("res://assets/ui/gen/split_anime/cursor_resize_diag.png"),
		"hotspot": Vector2(16, 16),
	},
}

## 指针展示库：split_anime 全部素材的标签 / 纹理 / 热点 / 关联系统形状。
## shape = -1 表示纯展示素材（剑 / 对话 / 链接 / 画笔 / 目标 / 红准星），
## 未绑定系统形状，供游戏内战斗 / 交互等场景按需取用。
const CURSOR_LIBRARY: Array[Dictionary] = [
	{"label": "箭头·白", "texture": preload("res://assets/ui/gen/split_anime/cursor_arrow_white.png"), "hotspot": Vector2(3, 1), "shape": Input.CURSOR_ARROW},
	{"label": "箭头·蓝", "texture": preload("res://assets/ui/gen/split_anime/cursor_arrow_blue.png"), "hotspot": Vector2(3, 1), "shape": Input.CURSOR_ARROW},
	{"label": "箭头·金", "texture": preload("res://assets/ui/gen/split_anime/cursor_arrow_gold.png"), "hotspot": Vector2(2, 1), "shape": Input.CURSOR_ARROW},
	{"label": "文本", "texture": preload("res://assets/ui/gen/split_anime/cursor_beam.png"), "hotspot": Vector2(15, 16), "shape": Input.CURSOR_IBEAM},
	{"label": "指向", "texture": preload("res://assets/ui/gen/split_anime/cursor_hand_white.png"), "hotspot": Vector2(9, 2), "shape": Input.CURSOR_POINTING_HAND},
	{"label": "准星·白", "texture": preload("res://assets/ui/gen/split_anime/cursor_crosshair_white.png"), "hotspot": Vector2(15, 16), "shape": Input.CURSOR_CROSS},
	{"label": "准星·红", "texture": preload("res://assets/ui/gen/split_anime/cursor_crosshair_red.png"), "hotspot": Vector2(15, 15), "shape": -1},
	{"label": "目标", "texture": preload("res://assets/ui/gen/split_anime/cursor_target.png"), "hotspot": Vector2(16, 16), "shape": -1},
	{"label": "抓取", "texture": preload("res://assets/ui/gen/split_anime/cursor_grab_white.png"), "hotspot": Vector2(19, 15), "shape": Input.CURSOR_DRAG},
	{"label": "移动", "texture": preload("res://assets/ui/gen/split_anime/cursor_move.png"), "hotspot": Vector2(15, 15), "shape": Input.CURSOR_MOVE},
	{"label": "禁止", "texture": preload("res://assets/ui/gen/split_anime/cursor_banned.png"), "hotspot": Vector2(16, 16), "shape": Input.CURSOR_FORBIDDEN},
	{"label": "帮助", "texture": preload("res://assets/ui/gen/split_anime/cursor_help.png"), "hotspot": Vector2(16, 16), "shape": Input.CURSOR_HELP},
	{"label": "链接", "texture": preload("res://assets/ui/gen/split_anime/cursor_link.png"), "hotspot": Vector2(2, 1), "shape": -1},
	{"label": "对话", "texture": preload("res://assets/ui/gen/split_anime/cursor_talk.png"), "hotspot": Vector2(16, 14), "shape": -1},
	{"label": "剑", "texture": preload("res://assets/ui/gen/split_anime/cursor_sword.png"), "hotspot": Vector2(5, 16), "shape": -1},
	{"label": "画笔", "texture": preload("res://assets/ui/gen/split_anime/cursor_paint.png"), "hotspot": Vector2(9, 28), "shape": -1},
	{"label": "横向", "texture": preload("res://assets/ui/gen/split_anime/cursor_resize_h.png"), "hotspot": Vector2(15, 15), "shape": Input.CURSOR_HSIZE},
	{"label": "纵向", "texture": preload("res://assets/ui/gen/split_anime/cursor_resize_v.png"), "hotspot": Vector2(15, 16), "shape": Input.CURSOR_VSIZE},
	{"label": "对角", "texture": preload("res://assets/ui/gen/split_anime/cursor_resize_diag.png"), "hotspot": Vector2(16, 16), "shape": Input.CURSOR_FDIAGSIZE},
]

## 已注册形状 → {texture, hotspot}（含预览覆盖后的 ARROW），供恢复 / 断言用。
var _registered_cursors: Dictionary = {}

## 当前箭头风格名（ARROW_STYLES 的键之一）。
var _arrow_style: String = DEFAULT_ARROW_STYLE


func _ready() -> void:
	_apply_arrow_style(DEFAULT_ARROW_STYLE)
	for shape: int in _CURSORS:
		var definition: Dictionary = _CURSORS[shape]
		_register_shape(shape, definition["texture"], definition["hotspot"])


## 按最长边等比缩放素材并以 NEAREST 注册到系统形状，热点同步缩放。
func _register_shape(shape: int, source_texture: Texture2D, source_hotspot: Vector2) -> void:
	var image: Image = source_texture.get_image()
	var scale_factor: float = float(_CURSOR_MAX_EDGE) / maxi(image.get_width(), image.get_height())
	var scaled_size := Vector2i(
		maxi(1, roundi(image.get_width() * scale_factor)),
		maxi(1, roundi(image.get_height() * scale_factor))
	)
	image.resize(scaled_size.x, scaled_size.y, Image.INTERPOLATE_NEAREST)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	var hotspot: Vector2 = (source_hotspot * scale_factor).round()
	_registered_cursors[shape] = {"texture": texture, "hotspot": hotspot}
	Input.set_custom_mouse_cursor(texture, shape, hotspot)


func get_arrow_style() -> String:
	return _arrow_style


## 切换箭头风格并即时生效；未知风格或重复设置时忽略。
func set_arrow_style(style_name: String) -> void:
	if not ARROW_STYLES.has(style_name) or style_name == _arrow_style:
		return
	_apply_arrow_style(style_name)


## 应用箭头风格：记录风格名并注册到 CURSOR_ARROW。
func _apply_arrow_style(style_name: String) -> void:
	_arrow_style = style_name
	_register_shape(
		Input.CURSOR_ARROW, ARROW_STYLES[style_name], _ARROW_HOTSPOTS[style_name]
	)


## 临时把任意指针挂到 ARROW 形状上预览（画廊 hover 用）；配 restore_cursor 恢复。
func preview_cursor(texture: Texture2D, hotspot: Vector2) -> void:
	_register_shape(Input.CURSOR_ARROW, texture, hotspot)


## 恢复当前箭头风格的指针（结束预览）。
func restore_cursor() -> void:
	_apply_arrow_style(_arrow_style)
