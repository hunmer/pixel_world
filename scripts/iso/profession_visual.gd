## iso/profession_visual.gd — 职业立绘/动画加载（对应 src/editor/ProfessionVisualAdapter.ts）
##
## 立绘：res://assets/ui/portraits/class-<id>.png
## 动画：knight 有 8 帧 48×48 idle（res://assets/units/class-knight-idle.png）
## 在 3D 下立绘用 Sprite3D，动画用 AnimatedSprite3D（需要 SpriteFrames 资源）。

class_name ProfessionVisual
extends RefCounted


## 立绘纹理路径（class-<id>.png）
static func portrait_path(class_id: StringName) -> String:
	return "res://assets/ui/portraits/class-%s.png" % String(class_id)


## 立绘纹理是否已存在（避免缺图崩溃）
static func portrait_exists(class_id: StringName) -> bool:
	return ResourceLoader.exists(portrait_path(class_id))


## knight idle 动画表路径
static func anim_path(class_id: StringName, anim_name: StringName) -> String:
	# 目前只有 knight 有 idle
	if class_id == &"knight" and anim_name == &"idle":
		return "res://assets/units/class-knight-idle.png"
	return ""


## 构建 SpriteFrames（用于 AnimatedSprite3D）。
## 把横向 sprite sheet 切成 N 帧。
static func build_idle_frames(_class_id: StringName, path: String, frame_w: int, frame_h: int, frame_count: int) -> SpriteFrames:
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var sf := SpriteFrames.new()
	sf.add_animation(&"idle")
	var cols := int(tex.get_width() / float(frame_w))
	for i in range(frame_count):
		var col := i % cols
		var row := int(i / float(cols))
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
		sf.add_frame(&"idle", atlas)
	sf.set_animation_speed(&"idle", 8)
	sf.set_animation_loop(&"idle", true)
	return sf
