@tool
class_name PixelNameplate
extends PixelNinePatchFrame

## pixel_nameplate.gd — 像素名牌组件：assets/ui/nameplates/ 三张名牌底板。
## 绘制与分段逻辑在基类 PixelNinePatchFrame：左侧徽章与两端翼饰为固定保护区，
## 拉伸量由板体弹性段承担；高度锁定为素材名义高度 × 缩放，整图随高度等比缩放，
## 宽度由内容驱动自动拉宽（文本不变形）。内容槽从右侧装饰之后开始。

const NAMEPLATE_TEXTURES: Dictionary = {
	"silver": preload("res://assets/ui/nameplates/nameplates_r1c1.png"),
	"crimson": preload("res://assets/ui/nameplates/nameplates_r2c1.png"),
	"gold": preload("res://assets/ui/nameplates/nameplates_r3c1.png"),
}

const NAMEPLATE_LABELS: Dictionary = {
	"silver": "银辉",
	"crimson": "猩红",
	"gold": "鎏金",
}

## 顶部横向固定保护区 [起点, 终点)（源像素坐标）：左徽章区 / 右端饰。
## 依据列 alpha 剖面抽查校准（装饰/板体过渡跳变点）。
const NAMEPLATE_FIXED_BANDS: Dictionary = {
	"silver": [[0, 286], [1096, 1257]],
	"crimson": [[0, 322], [1088, 1286]],
	"gold": [[0, 332], [1354, 1516]],
}

## 名义显示缩放：素材按此比例估算最小尺寸与内容边距（高度锁定用）。
const NOMINAL_SCALE: float = 0.4
## 文本与徽章/端饰装饰区的额外间距。
const DECO_GAP: float = 14.0

func _get_texture_map() -> Dictionary:
	return NAMEPLATE_TEXTURES

func _get_band_map() -> Dictionary:
	return NAMEPLATE_FIXED_BANDS

func _get_label_map() -> Dictionary:
	return NAMEPLATE_LABELS

func _nominal_scale() -> float:
	return NOMINAL_SCALE

func _stretch_vertically() -> bool:
	return false

func _content_insets(key: String, scale: float) -> Vector4:
	var bands: Array = NAMEPLATE_FIXED_BANDS.get(key, [])
	var left_band: float = bands[0][1] * scale if bands.size() > 0 else 0.0
	var right_band: float = (bands[-1][1] - bands[-1][0]) * scale if bands.size() > 0 else 0.0
	return Vector4(left_band + DECO_GAP, 0.0, right_band + DECO_GAP, 0.0)
