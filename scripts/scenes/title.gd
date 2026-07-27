## scenes/title.gd — 标题界面（对应 src/scenes/TitleScene.ts）

extends Control

var start_btn: Button


func _ready() -> void:
	# 背景（contain 缩放）
	var bg := TextureRect.new()
	bg.texture = load("res://assets/bg/home-background.png") if ResourceLoader.exists("res://assets/bg/home-background.png") else null
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	add_child(bg)
	# 标题
	var title := Label.new()
	title.text = "TACTICS RPG\n战旗 · 觉醒之章"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.offset_top = -150
	add_child(title)
	# 按钮
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	vbox.position = Vector2(get_viewport_rect().size.x / 2 - 130, get_viewport_rect().size.y / 2 + 20)
	add_child(vbox)
	start_btn = Button.new()
	start_btn.text = "进入世界"
	start_btn.custom_minimum_size = Vector2(260, 60)
	start_btn.add_theme_font_size_override("font_size", 24)
	start_btn.pressed.connect(_on_start)
	vbox.add_child(start_btn)
	# 底部版权
	var foot := Label.new()
	foot.text = "pixel_world × 战旗融合 · Godot 4.7"
	foot.add_theme_font_size_override("font_size", 11)
	foot.add_theme_color_override("font_color", Color(0.8, 0.83, 0.88))
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.position.y = -28
	add_child(foot)


func _on_start() -> void:
	# 进入 pixel_world 生态世界（在世界里按 P 进战棋）
	get_tree().change_scene_to_file("res://main.tscn")
