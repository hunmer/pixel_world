@tool
class_name PixelFrame
extends PixelNinePatchFrame

## pixel_frame.gd — 像素边框组件：assets/ui/frames/ 六张边框素材。
## 绘制与分段逻辑在基类 PixelNinePatchFrame：水平「固定段 + 弹性段」——
## 角饰、顶部中央徽章翼展、垂旗为固定保护区，拉伸量由其左右弹性段等比分担；
## 垂直为上条固定 / 中区拉伸 / 下条固定。内容尺寸决定框体尺寸（智能拉宽拉长）。

const FRAME_TEXTURES: Dictionary = {
	"panel": preload("res://assets/ui/frames/frame-panel.png"),
	"dialogue": preload("res://assets/ui/frames/frame-dialogue.png"),
	"info": preload("res://assets/ui/frames/frame-info.png"),
	"map_info": preload("res://assets/ui/frames/frame-map-info.png"),
	"character_status": preload("res://assets/ui/frames/frame-character-status.png"),
	"skill_description": preload("res://assets/ui/frames/frame-skill-description.png"),
}

const FRAME_LABELS: Dictionary = {
	"panel": "面板",
	"dialogue": "对话",
	"info": "信息",
	"map_info": "地图信息",
	"character_status": "角色状态",
	"skill_description": "技能描述",
}

## 顶部横向固定保护区 [起点, 终点)（源像素坐标）：角饰 / 徽章翼展 / 垂旗。
## 依据 RGBA 顶部凸出探针 + 翼展 ASCII 实测：徽章核 ±24px 包住斜翼。
const FRAME_FIXED_BANDS: Dictionary = {
	"panel": [[0, 41], [201, 303], [455, 496]],
	"dialogue": [[0, 39], [168, 263], [384, 428]],
	"info": [[0, 41], [127, 293], [371, 412]],
	"map_info": [[0, 43], [191, 289], [435, 478]],
	"character_status": [[0, 64], [440, 504]],
	"skill_description": [[0, 40], [137, 245], [341, 381]],
}

func _get_texture_map() -> Dictionary:
	return FRAME_TEXTURES

func _get_band_map() -> Dictionary:
	return FRAME_FIXED_BANDS

func _get_label_map() -> Dictionary:
	return FRAME_LABELS
