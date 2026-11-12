## game_cursor.gd — 全局游戏鼠标指针（autoload 单例）
##
## 为所有场景注册最长边 32px 的像素指针；文本输入与窗口缩放保留系统形状。

extends Node

const _CURSOR_MAX_EDGE: int = 32
const _CURSORS: Dictionary = {
	Input.CURSOR_ARROW: {
		"texture": preload("res://assets/ui/cursors/cursor-normal.png"),
		"hotspot": Vector2(9, 5),
	},
	Input.CURSOR_POINTING_HAND: {
		"texture": preload("res://assets/ui/cursors/cursor-attack.png"),
		"hotspot": Vector2(13, 7),
	},
	Input.CURSOR_CROSS: {
		"texture": preload("res://assets/ui/cursors/cursor-area-select.png"),
		"hotspot": Vector2(57, 54),
	},
	Input.CURSOR_DRAG: {
		"texture": preload("res://assets/ui/cursors/cursor-unavailable.png"),
		"hotspot": Vector2(48, 56),
	},
	Input.CURSOR_MOVE: {
		"texture": preload("res://assets/ui/cursors/cursor-move.png"),
		"hotspot": Vector2(55, 52),
	},
	Input.CURSOR_FORBIDDEN: {
		"texture": preload("res://assets/ui/cursors/cursor-interact.png"),
		"hotspot": Vector2(49, 49),
	},
}

var _registered_cursors: Dictionary = {}


func _ready() -> void:
	for shape: int in _CURSORS:
		var definition: Dictionary = _CURSORS[shape]
		var source_texture: Texture2D = definition["texture"]
		var image: Image = source_texture.get_image()
		var scale_factor: float = float(_CURSOR_MAX_EDGE) / maxi(image.get_width(), image.get_height())
		var scaled_size := Vector2i(
			maxi(1, roundi(image.get_width() * scale_factor)),
			maxi(1, roundi(image.get_height() * scale_factor))
		)
		image.resize(scaled_size.x, scaled_size.y, Image.INTERPOLATE_NEAREST)
		var texture: Texture2D = ImageTexture.create_from_image(image)
		var source_hotspot: Vector2 = definition["hotspot"]
		var hotspot: Vector2 = (source_hotspot * scale_factor).round()
		_registered_cursors[shape] = {"size": texture.get_size(), "hotspot": hotspot}
		Input.set_custom_mouse_cursor(texture, shape, hotspot)
