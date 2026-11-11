## editor/tile_preview.gd — 地形调色板的等距方块缩略图（纯贴图，无文字）
##
## 用 BattlefieldRenderer.preview_blocks 生成的单柱 blocks 自绘迷你方块柱，
## 与战场/画布内观感一致。只做展示；鼠标事件透传（IGNORE），不挡按钮点击。

class_name TilePreview
extends Control

const BattlefieldRendererScript = preload("res://scripts/iso/battlefield_renderer.gd")

const GROUND_MARGIN := 10.0
const DEFAULT_SIZE := Vector2(40.0, 88.0)

var terrain: StringName = &"plain":
	set(v):
		terrain = v
		_blocks = BattlefieldRendererScript.preview_blocks(terrain)
		queue_redraw()

var _blocks: Array = []


func _init(p_terrain: StringName = &"plain") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = DEFAULT_SIZE
	terrain = p_terrain


func _draw() -> void:
	var ground := size.y - GROUND_MARGIN
	for b in _blocks:
		var tex: Texture2D = b.get("texture", null)
		if tex == null:
			continue
		var lvl := int(b.get("level", 0))
		var off: Vector2 = b.get("render_offset", Vector2.ZERO)
		var ts: Vector2 = tex.get_size()
		var mod: Color = b.get("modulate", Color.WHITE)
		var center := Vector2(size.x * 0.5 + off.x, ground - lvl * IsoCoords.LEVEL_H + off.y)
		draw_texture_rect(tex, Rect2(center - ts * 0.5, ts), false, mod)
