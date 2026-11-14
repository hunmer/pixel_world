## editor/tile_preview.gd — 调色板的等距方块缩略图（真实 ColumnBatch 渲染，无文字）
##
## 直接实例化游戏同款 ColumnBatch 渲染 preview_blocks 生成的单柱 blocks，
## 与战场/画布内观感像素一致（同一绘制代码/同一贴图/同一 NEAREST 过滤）。
## 每个缩略图就是一个 tile：地形=纯方块柱（不叠装饰物）；
## plant=true 时为植物 tile（树/灌木贴图单独成块，不插在方块柱上）。
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

## true=植物 tile：装饰物贴图单独成块（树就是树，不叠在方块柱上）
var plant := false:
	set(v):
		plant = v
		_refresh_column()

## 具体植物贴图路径（非空时优先于 plant/terrain：调色板枚举全部植物素材用）
var prop_path := "":
	set(v):
		prop_path = v
		_refresh_column()

## 用户素材 visual（UserAssetVisualAdapter 产出；非空时优先于 plant/terrain，
## 与 prop_path 互斥：素材缩略图用，渲染走 preview_visual_block，所见即所得）
var asset_visual: Dictionary = {}:
	set(v):
		asset_visual = v
		_refresh_column()

var _column: Node2D = null


func _init(p_terrain: StringName = &"plain", p_plant := false, p_prop_path := "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = PREVIEW_SIZE
	size = PREVIEW_SIZE  # Button 不是 Container：必须显式给尺寸
	prop_path = p_prop_path
	plant = p_plant
	terrain = p_terrain


func _ready() -> void:
	_refresh_column()


## 用真实 ColumnBatch 重建柱：绘制路径与游戏内完全一致。
## 地形 = 单块 tile（preview_blocks(single=true)，不再叠成高塔）；
## prop_path 优先；其次 asset_visual（用户素材）；再 plant（地形默认装饰独立成块）；
## 都无则纯地形单块。
func _refresh_column() -> void:
	if not is_inside_tree():
		return  # _ready 会再触发一次
	if _column == null:
		_column = ColumnBatchScript.new()
		add_child(_column)
	var raw: Array = []
	if not prop_path.is_empty():
		var pb: Dictionary = BattlefieldRendererScript.preview_path_block(prop_path)
		if not pb.is_empty():
			raw.append(pb)
	elif not asset_visual.is_empty():
		var ab: Dictionary = BattlefieldRendererScript.preview_visual_block(asset_visual)
		if not ab.is_empty():
			raw.append(ab)
	if raw.is_empty() and plant:
		var prop: Dictionary = BattlefieldRendererScript.preview_prop_block(terrain)
		if not prop.is_empty():
			raw.append(prop)
	if raw.is_empty():
		raw = BattlefieldRendererScript.preview_blocks(terrain, false, true)
	var blocks: Array[Dictionary] = []
	for b in raw:
		blocks.append(b)
	# 自适应缩放：量出最大块贴图，超出缩略图时整柱等比缩小（樱花树等大素材不越界）
	var ground_y := size.y - GROUND_MARGIN
	var max_w := 0.0
	var max_h := 0.0
	for b in blocks:
		var tex: Texture2D = b.get("texture")
		if tex == null:
			continue
		var ts := tex.get_size()
		var off := b.get("render_offset", Vector2.ZERO) as Vector2
		max_w = maxf(max_w, ts.x)
		max_h = maxf(max_h, ts.y + absf(off.y))
	var avail_w := size.x - 4.0
	var avail_h := size.y - 4.0
	var fit := 1.0
	if max_w > 0.0 and max_h > 0.0:
		fit = minf(1.0, minf(avail_w / max_w, avail_h / max_h))
	_column.scale = Vector2(fit, fit)
	_column.configure(
		Vector2i.ZERO,
		blocks,
		Vector2(0.0, ground_y / fit),  # 缩放后地面锚点保持在原位：local/scale
		0.0,
		IsoCoords.LEVEL_H
	)
	_column.position = Vector2(size.x * 0.5, 0.0)
