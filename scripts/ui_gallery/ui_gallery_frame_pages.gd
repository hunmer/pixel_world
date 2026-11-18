## ui_gallery/ui_gallery_frame_pages.gd — 画廊框体系三页（从 ui_component_gallery.gd 拆出）
##
## 职责：第 9-11 页「边框 / 名牌 / 头像」——PixelFrame、PixelNameplate、PixelAvatarFrame
## 三个框体系组件的演示，三页同构：自适应/尺寸演示卡（切换素材 + 追加/清空或放大/缩小）
## + 素材图鉴卡（每种 key 一行，标注中文名与素材原始尺寸）。
##   - 边框页：内容驱动自适应（追加行拉长框体）；
##   - 名牌页：高度锁定、宽度随内容（称号追加 "!"）；
##   - 头像页：四档尺寸等比缩放（AVATAR_SIZES），首档经 call_deferred 延迟应用
##     （组件 _ready 的 _refresh 会重算 custom_minimum_size，提前设值会被覆盖）。
##
## 设计：RefCounted 能力模块（ui_component_gallery 拆分件）。宿主经 setup() 注入 self，
## duck-typed 调用宿主公开面 add_gallery_tab / log_feedback；卡片 / 按钮工具复用
## UiGalleryWidgets。三组演示状态互相独立，reset 按边框→名牌→头像原序复位。
class_name UiGalleryFramePages
extends RefCounted

const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const PixelFrameScript = preload("res://ui/components/pixel_frame.gd")
const PixelNameplateScript = preload("res://ui/components/pixel_nameplate.gd")
const PixelAvatarScript = preload("res://ui/components/pixel_avatar_frame.gd")

## 本模块负责的页签标题（顺序即构建顺序）。
const TAB_TITLES: Array[String] = ["边框", "名牌", "头像"]
## 头像页尺寸档（等比四档）。
const AVATAR_SIZES: Array[int] = [80, 105, 128, 160]

## 宿主画廊（duck-typed 动态访问 add_gallery_tab / log_feedback）。
var _host = null

## 边框页演示状态：当前素材 key 序号 / 已追加行数 / 演示框与内部文本引用。
var _frame_demo_frame: PanelContainer
var _frame_demo_text: Label
var _frame_demo_status_label: Label
var _frame_demo_key_index: int = 0
var _frame_demo_added_lines: int = 0

## 名牌页演示状态：当前素材 key 序号 / 已追加称号数 / 演示牌与内部文字引用。
var _nameplate_demo_plate: PanelContainer
var _nameplate_demo_label: Label
var _nameplate_demo_status_label: Label
var _nameplate_demo_key_index: int = 0
var _nameplate_demo_exclaims: int = 0

## 头像页演示状态：当前素材 key 序号 / 尺寸档序号 / 演示框与内部文字引用。
var _avatar_demo_frame: PanelContainer
var _avatar_demo_label: Label
var _avatar_demo_status_label: Label
var _avatar_demo_key_index: int = 0
var _avatar_demo_size_index: int = 2


func setup(p_host) -> void:
	_host = p_host


## 依次构建三个页签。
func build() -> void:
	_build_frame_page()
	_build_nameplate_page()
	_build_avatar_page()


## 复位三页演示状态（边框 → 名牌 → 头像，与拆分前 _reset_demo 对应段同序）。
func reset() -> void:
	_frame_demo_key_index = 0
	_frame_demo_frame.set("frame_key", "panel")
	_on_frame_line_clear()
	_nameplate_demo_key_index = 0
	_nameplate_demo_plate.set("frame_key", PixelNameplateScript.NAMEPLATE_TEXTURES.keys()[0])
	_on_nameplate_char_clear()
	_avatar_demo_key_index = 0
	_avatar_demo_size_index = 2
	_avatar_demo_frame.set("frame_key", PixelAvatarScript.AVATAR_TEXTURES.keys()[0])
	_apply_avatar_size()
	_avatar_demo_status_label.text = _avatar_demo_status()


## 第 9 页：PixelFrame 装饰框（frames 九宫格素材）+ 内容驱动自适应演示。
func _build_frame_page() -> void:
	var page: VBoxContainer = _host.add_gallery_tab(TAB_TITLES[0])
	page.add_theme_constant_override("separation", 12)

	var demo_card := UiGalleryWidgets.make_card("自适应演示", "")
	var demo_row := HBoxContainer.new()
	demo_row.name = "FrameDemoRow"
	demo_row.add_theme_constant_override("separation", 12)
	_frame_demo_frame = PixelFrameScript.new() as PanelContainer
	_frame_demo_frame.name = "FrameDemoFrame"
	_frame_demo_frame.set("frame_key", "panel")
	_frame_demo_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame_demo_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_frame_demo_text = UIFactoryScript.label("内容决定框体：点右侧「追加一行」，框随内容自动拉长。", 12, UIThemeScript.TEXT_MAIN)
	_frame_demo_text.name = "FrameDemoText"
	_frame_demo_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_frame_demo_text.custom_minimum_size = Vector2(160, 0)
	_frame_demo_frame.add_child(_frame_demo_text)
	demo_row.add_child(_frame_demo_frame)
	demo_row.add_child(_build_frame_demo_controls())
	UiGalleryWidgets.card_slot(demo_card).add_child(demo_row)
	page.add_child(demo_card)

	var gallery_card := UiGalleryWidgets.make_card("素材图鉴", "")
	var gallery := VBoxContainer.new()
	gallery.name = "FrameGallery"
	gallery.add_theme_constant_override("separation", 10)
	for key: String in PixelFrameScript.FRAME_TEXTURES.keys():
		gallery.add_child(_make_frame_gallery_row(key))
	UiGalleryWidgets.card_slot(gallery_card).add_child(gallery)
	page.add_child(gallery_card)


## 演示框右侧控制列：切换素材 / 追加一行 / 清空 + 状态行。
func _build_frame_demo_controls() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "FrameDemoControls"
	box.add_theme_constant_override("separation", 8)
	var next_btn := UiGalleryWidgets.make_pixel_button("切换素材", 1, "cog")
	next_btn.name = "FrameStyleNextButton"
	next_btn.pressed.connect(_on_frame_style_next)
	box.add_child(next_btn)
	var add_btn := UiGalleryWidgets.make_pixel_button("追加一行", 0, "play")
	add_btn.name = "FrameLineAddButton"
	add_btn.pressed.connect(_on_frame_line_add)
	box.add_child(add_btn)
	var clear_btn := UiGalleryWidgets.make_pixel_button("清空", 2, "skull")
	clear_btn.name = "FrameLineClearButton"
	clear_btn.pressed.connect(_on_frame_line_clear)
	box.add_child(clear_btn)
	_frame_demo_status_label = UIFactoryScript.label(_frame_demo_status(), 11, UIThemeScript.TEXT_DIM)
	_frame_demo_status_label.name = "FrameDemoStatus"
	box.add_child(_frame_demo_status_label)
	return box


## 素材图鉴行：整行一个 PixelFrame，框内短说明（key 中文名 + 素材原始尺寸）。
func _make_frame_gallery_row(key: String) -> Control:
	var frame := PixelFrameScript.new() as PanelContainer
	frame.name = "Frame_" + key
	frame.set("frame_key", key)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var tex: Texture2D = PixelFrameScript.FRAME_TEXTURES[key]
	var text := UIFactoryScript.label(
		"%s · %d×%d" % [PixelFrameScript.FRAME_LABELS[key], tex.get_width(), tex.get_height()],
		12, UIThemeScript.TEXT_MAIN
	)
	text.name = "FrameLabel"
	frame.add_child(text)
	return frame


## 第 10 页：PixelNameplate 名牌底板（nameplates 素材）+ 高度锁定、宽度随内容演示。
func _build_nameplate_page() -> void:
	var page: VBoxContainer = _host.add_gallery_tab(TAB_TITLES[1])
	page.add_theme_constant_override("separation", 12)

	var demo_card := UiGalleryWidgets.make_card("自适应演示", "")
	var demo_row := HBoxContainer.new()
	demo_row.name = "NameplateDemoRow"
	demo_row.add_theme_constant_override("separation", 12)
	_nameplate_demo_plate = PixelNameplateScript.new() as PanelContainer
	_nameplate_demo_plate.name = "NameplateDemoFrame"
	_nameplate_demo_plate.set("frame_key", PixelNameplateScript.NAMEPLATE_TEXTURES.keys()[0])
	_nameplate_demo_plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nameplate_demo_plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_nameplate_demo_label = UIFactoryScript.label("勇者 · Lv.12", 13, UIThemeScript.TEXT_MAIN)
	_nameplate_demo_label.name = "NameplateDemoLabel"
	_nameplate_demo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nameplate_demo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_nameplate_demo_plate.add_child(_nameplate_demo_label)
	demo_row.add_child(_nameplate_demo_plate)
	demo_row.add_child(_build_nameplate_demo_controls())
	UiGalleryWidgets.card_slot(demo_card).add_child(demo_row)
	page.add_child(demo_card)

	var gallery_card := UiGalleryWidgets.make_card("素材图鉴", "")
	var gallery := VBoxContainer.new()
	gallery.name = "NameplateGallery"
	gallery.add_theme_constant_override("separation", 10)
	for key: String in PixelNameplateScript.NAMEPLATE_TEXTURES.keys():
		gallery.add_child(_make_nameplate_gallery_row(key))
	UiGalleryWidgets.card_slot(gallery_card).add_child(gallery)
	page.add_child(gallery_card)


## 演示名牌右侧控制列：切换素材 / 追加称号 / 清空 + 状态行。
func _build_nameplate_demo_controls() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "NameplateDemoControls"
	box.add_theme_constant_override("separation", 8)
	var next_btn := UiGalleryWidgets.make_pixel_button("切换素材", 1, "cog")
	next_btn.name = "NameplateStyleNextButton"
	next_btn.pressed.connect(_on_nameplate_style_next)
	box.add_child(next_btn)
	var add_btn := UiGalleryWidgets.make_pixel_button("追加称号", 0, "play")
	add_btn.name = "NameplateCharAddButton"
	add_btn.pressed.connect(_on_nameplate_char_add)
	box.add_child(add_btn)
	var clear_btn := UiGalleryWidgets.make_pixel_button("清空", 2, "skull")
	clear_btn.name = "NameplateCharClearButton"
	clear_btn.pressed.connect(_on_nameplate_char_clear)
	box.add_child(clear_btn)
	_nameplate_demo_status_label = UIFactoryScript.label(_nameplate_demo_status(), 11, UIThemeScript.TEXT_DIM)
	_nameplate_demo_status_label.name = "NameplateDemoStatus"
	box.add_child(_nameplate_demo_status_label)
	return box


## 素材图鉴行：整行一个 PixelNameplate，框内示例名（key 中文名 + 素材原始尺寸）。
func _make_nameplate_gallery_row(key: String) -> Control:
	var plate := PixelNameplateScript.new() as PanelContainer
	plate.name = "Nameplate_" + key
	plate.set("frame_key", key)
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var tex: Texture2D = PixelNameplateScript.NAMEPLATE_TEXTURES[key]
	var text := UIFactoryScript.label(
		"%s · %d×%d · 剑士 Lv.24" % [PixelNameplateScript.NAMEPLATE_LABELS[key], tex.get_width(), tex.get_height()],
		12, UIThemeScript.TEXT_MAIN
	)
	text.name = "NameplateLabel"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_child(text)
	return plate


## 第 11 页：PixelAvatarFrame 头像边框（timeline_frames 素材）+ 四档尺寸等比演示。
func _build_avatar_page() -> void:
	var page: VBoxContainer = _host.add_gallery_tab(TAB_TITLES[2])
	page.add_theme_constant_override("separation", 12)

	var demo_card := UiGalleryWidgets.make_card("尺寸演示", "")
	var demo_row := HBoxContainer.new()
	demo_row.name = "AvatarDemoRow"
	demo_row.add_theme_constant_override("separation", 12)
	_avatar_demo_frame = PixelAvatarScript.new() as PanelContainer
	_avatar_demo_frame.name = "AvatarDemoFrame"
	_avatar_demo_frame.set("frame_key", PixelAvatarScript.AVATAR_TEXTURES.keys()[0])
	_avatar_demo_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_avatar_demo_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_avatar_demo_label = UIFactoryScript.label("头像", 13, UIThemeScript.TEXT_MAIN)
	_avatar_demo_label.name = "AvatarDemoLabel"
	_avatar_demo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar_demo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar_demo_frame.add_child(_avatar_demo_label)
	demo_row.add_child(_avatar_demo_frame)
	# 组件 _ready 的 _refresh 会重算 custom_minimum_size，且 _ready 要等整棵子树
	# 入树才触发，任何提前设值都会被覆盖回名义 min；首个尺寸档延迟到帧末设置。
	_apply_avatar_size.call_deferred()
	demo_row.add_child(_build_avatar_demo_controls())
	UiGalleryWidgets.card_slot(demo_card).add_child(demo_row)
	page.add_child(demo_card)

	var gallery_card := UiGalleryWidgets.make_card("素材图鉴", "")
	var gallery := VBoxContainer.new()
	gallery.name = "AvatarGallery"
	gallery.add_theme_constant_override("separation", 10)
	for key: String in PixelAvatarScript.AVATAR_TEXTURES.keys():
		gallery.add_child(_make_avatar_gallery_row(key))
	UiGalleryWidgets.card_slot(gallery_card).add_child(gallery)
	page.add_child(gallery_card)


## 尺寸演示右侧控制列：切换素材 / 放大 / 缩小 + 状态行。
func _build_avatar_demo_controls() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "AvatarDemoControls"
	box.add_theme_constant_override("separation", 8)
	var next_btn := UiGalleryWidgets.make_pixel_button("切换素材", 1, "cog")
	next_btn.name = "AvatarStyleNextButton"
	next_btn.pressed.connect(_on_avatar_style_next)
	box.add_child(next_btn)
	var up_btn := UiGalleryWidgets.make_pixel_button("放大", 0, "star")
	up_btn.name = "AvatarSizeUpButton"
	up_btn.pressed.connect(_on_avatar_size_up)
	box.add_child(up_btn)
	var down_btn := UiGalleryWidgets.make_pixel_button("缩小", 1, "target")
	down_btn.name = "AvatarSizeDownButton"
	down_btn.pressed.connect(_on_avatar_size_down)
	box.add_child(down_btn)
	_avatar_demo_status_label = UIFactoryScript.label(_avatar_demo_status(), 12, UIThemeScript.TEXT_DIM)
	_avatar_demo_status_label.name = "AvatarDemoStatus"
	box.add_child(_avatar_demo_status_label)
	return box


## 素材图鉴行：名义尺寸头像框 + key 中文名与素材原始尺寸。
func _make_avatar_gallery_row(key: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Avatar_" + key
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var frame := PixelAvatarScript.new() as PanelContainer
	frame.name = "AvatarFrame_" + key
	frame.set("frame_key", key)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var tex: Texture2D = PixelAvatarScript.AVATAR_TEXTURES[key]
	frame.custom_minimum_size = tex.get_size() * PixelAvatarScript.NOMINAL_SCALE
	var text := UIFactoryScript.label("头像", 13, UIThemeScript.TEXT_MAIN)
	text.name = "AvatarLabel"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	frame.add_child(text)
	row.add_child(frame)
	var desc := UIFactoryScript.label(
		"%s · %d×%d" % [PixelAvatarScript.AVATAR_LABELS[key], tex.get_width(), tex.get_height()],
		12, UIThemeScript.TEXT_MAIN
	)
	desc.name = "AvatarDesc"
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(desc)
	return row


func _frame_demo_status() -> String:
	var key: String = PixelFrameScript.FRAME_TEXTURES.keys()[_frame_demo_key_index]
	return "%s · 追加 %d 行" % [PixelFrameScript.FRAME_LABELS[key], _frame_demo_added_lines]


func _nameplate_demo_status() -> String:
	var key: String = PixelNameplateScript.NAMEPLATE_TEXTURES.keys()[_nameplate_demo_key_index]
	return "%s · 称号 %d" % [PixelNameplateScript.NAMEPLATE_LABELS[key], _nameplate_demo_exclaims]


func _avatar_demo_status() -> String:
	var key: String = PixelAvatarScript.AVATAR_TEXTURES.keys()[_avatar_demo_key_index]
	return "%s · %dpx" % [PixelAvatarScript.AVATAR_LABELS[key], AVATAR_SIZES[_avatar_demo_size_index]]


func _apply_avatar_size() -> void:
	var px: int = AVATAR_SIZES[_avatar_demo_size_index]
	_avatar_demo_frame.custom_minimum_size = Vector2(px, px)


func _on_frame_style_next() -> void:
	_frame_demo_key_index = (_frame_demo_key_index + 1) % PixelFrameScript.FRAME_TEXTURES.size()
	var key: String = PixelFrameScript.FRAME_TEXTURES.keys()[_frame_demo_key_index]
	_frame_demo_frame.set("frame_key", key)
	_frame_demo_status_label.text = _frame_demo_status()
	_host.log_feedback("框体 → %s" % PixelFrameScript.FRAME_LABELS[key])


func _on_frame_line_add() -> void:
	_frame_demo_added_lines += 1
	_frame_demo_text.text += "\n追加第 %d 行：框随内容自动拉长。" % _frame_demo_added_lines
	_frame_demo_status_label.text = _frame_demo_status()


func _on_frame_line_clear() -> void:
	_frame_demo_added_lines = 0
	_frame_demo_text.text = "内容决定框体：点右侧「追加一行」，框随内容自动拉长。"
	_frame_demo_status_label.text = _frame_demo_status()


func _on_nameplate_style_next() -> void:
	_nameplate_demo_key_index = (_nameplate_demo_key_index + 1) % PixelNameplateScript.NAMEPLATE_TEXTURES.size()
	var key: String = PixelNameplateScript.NAMEPLATE_TEXTURES.keys()[_nameplate_demo_key_index]
	_nameplate_demo_plate.set("frame_key", key)
	_nameplate_demo_status_label.text = _nameplate_demo_status()
	_host.log_feedback("名牌 → %s" % PixelNameplateScript.NAMEPLATE_LABELS[key])


func _on_nameplate_char_add() -> void:
	_nameplate_demo_exclaims += 1
	_nameplate_demo_label.text += "!"
	_nameplate_demo_status_label.text = _nameplate_demo_status()


func _on_nameplate_char_clear() -> void:
	_nameplate_demo_exclaims = 0
	_nameplate_demo_label.text = "勇者 · Lv.12"
	_nameplate_demo_status_label.text = _nameplate_demo_status()


func _on_avatar_style_next() -> void:
	_avatar_demo_key_index = (_avatar_demo_key_index + 1) % PixelAvatarScript.AVATAR_TEXTURES.size()
	var key: String = PixelAvatarScript.AVATAR_TEXTURES.keys()[_avatar_demo_key_index]
	_avatar_demo_frame.set("frame_key", key)
	_avatar_demo_status_label.text = _avatar_demo_status()
	_host.log_feedback("头像框 → %s" % PixelAvatarScript.AVATAR_LABELS[key])


func _on_avatar_size_up() -> void:
	_avatar_demo_size_index = mini(_avatar_demo_size_index + 1, AVATAR_SIZES.size() - 1)
	_apply_avatar_size()
	_avatar_demo_status_label.text = _avatar_demo_status()
	_host.log_feedback("头像框尺寸 → %dpx" % AVATAR_SIZES[_avatar_demo_size_index])


func _on_avatar_size_down() -> void:
	_avatar_demo_size_index = maxi(_avatar_demo_size_index - 1, 0)
	_apply_avatar_size()
	_avatar_demo_status_label.text = _avatar_demo_status()
	_host.log_feedback("头像框尺寸 → %dpx" % AVATAR_SIZES[_avatar_demo_size_index])
