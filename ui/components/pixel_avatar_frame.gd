@tool
class_name PixelAvatarFrame
extends PixelNinePatchFrame

## pixel_avatar_frame.gd — 头像边框（timeline_frames 素材）：方形装饰框整图等比缩放。
## 四边中点饰物 / 角爪 / 皇冠不允许任何轴向变形，因此不复用面板框的弹性拉伸，
## 而是锁定纵横比整体缩放：全宽单固定段 + 整高锁定在基类绘制里天然退化为等比缩放。

const AVATAR_TEXTURES: Dictionary = {
	"gold": preload("res://assets/ui/timeline_frames/timeline_frames_r1c1.png"),
	"crimson": preload("res://assets/ui/timeline_frames/timeline_frames_r2c1.png"),
	"violet": preload("res://assets/ui/timeline_frames/timeline_frames_r3c1.png"),
}

const AVATAR_LABELS: Dictionary = {
	"gold": "鎏金",
	"crimson": "猩红",
	"violet": "紫曜",
}

## 全宽单固定段：整图皆为保护区，无弹性段 → 绘制整图原样等比缩放。
const AVATAR_FIXED_BANDS: Dictionary = {
	"gold": [[0, 422]],
	"crimson": [[0, 427]],
	"violet": [[0, 428]],
}

## 名义显示缩放：428×415 的素材以约 1/4 尺寸展示（约 107px 方框）。
const NOMINAL_SCALE: float = 0.25
## 框内内容与饰物的额外留缝。
const DECO_GAP: float = 6.0
## 统一保守内容缩进（源像素；三张素材多点扫描取各边最深值：左角饰 139 / 顶饰 140 / 右 90 / 底 90）。
const CONTENT_INSET_SRC := Vector4(139.0, 140.0, 90.0, 90.0)


func _get_texture_map() -> Dictionary:
	return AVATAR_TEXTURES


func _get_band_map() -> Dictionary:
	return AVATAR_FIXED_BANDS


func _get_label_map() -> Dictionary:
	return AVATAR_LABELS


func _nominal_scale() -> float:
	return NOMINAL_SCALE


func _stretch_vertically() -> bool:
	return false


func _content_insets(_key: String, scale: float) -> Vector4:
	return Vector4(
		CONTENT_INSET_SRC.x * scale + DECO_GAP,
		CONTENT_INSET_SRC.y * scale + DECO_GAP,
		CONTENT_INSET_SRC.z * scale + DECO_GAP,
		CONTENT_INSET_SRC.w * scale + DECO_GAP
	)


## 覆盖基类 min 公式：内容 insets 是框内缩进、不占外形尺寸，最小尺寸即整图 × scale。
## 尺寸与高度同源，保证任意容器分配下绘制都保持素材纵横比（hscale 由 size.y 推导）。
func _compute_min_size() -> Vector2:
	var tex: Texture2D = _get_texture_map().get(_resolve_key(frame_key))
	if tex == null:
		return Vector2.ZERO
	return tex.get_size() * _nominal_scale()
