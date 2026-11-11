## editor/tile_preview.gd — 地形调色板的等距方块缩略图（真实 ColumnBatch 渲染，无文字）
##
## 直接实例化游戏同款 ColumnBatch 渲染 preview_blocks 生成的单柱 blocks，
## 与战场/画布内观感像素一致（同一绘制代码/同一贴图/同一 NEAREST 过滤）。
## 只做展示；鼠标事件透传（IGNORE），不挡按钮点击。
## 注意：Button 不是 Container，不会给子 Control 应用 minimum size，
## 因此必须显式设置 size（旧版自绘 _draw 依赖 size 却从未被布局赋值，
## 导致柱体按 (0,0) 尺寸锚定而整体错位）。

class_name TilePreview
extends Control

const BattlefieldRendererScript = preload("res://scripts/iso/battlefield_renderer.gd")
const ColumnBatchScript = preload("res://scripts/isometric_column_batch.gd")

const GROUND_MARGIN := 16.0  # 底块贴图底缘 = 地面+16，取 16 让最高柱（山 5 层）恰好不越界
const PREVIEW_SIZE := Vector2(40.0, 88.0)

var terrain: StringName = &"plain":
	set(v):
		terrain = v
		_refresh_column()

var _column: Node2D = null


func _init(p_terrain: StringName = &"plain") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = PREVIEW_SIZE
	size = PREVIEW_SIZE  # Button 不是 Container：必须显式给尺寸
	terrain = p_terrain


func _ready() -> void:
	_refresh_column()


## 用真实 ColumnBatch 重建柱：绘制路径与游戏内完全一致。
func _refresh_column() -> void:
	if not is_inside_tree():
		return  # _ready 会再触发一次
	if _column == null:
		_column = ColumnBatchScript.new()
		add_child(_column)
	var raw: Array = BattlefieldRendererScript.preview_blocks(terrain)
	var blocks: Array[Dictionary] = []
	for b in raw:
		blocks.append(b)
	_column.configure(
		Vector2i.ZERO,
		blocks,
		Vector2(0.0, size.y - GROUND_MARGIN),
		0.0,
		IsoCoords.LEVEL_H
	)
	_column.position = Vector2(size.x * 0.5, 0.0)
