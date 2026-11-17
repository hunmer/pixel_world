## scripts/scenes/ui_component_gallery.gd — UI 组件库演示画廊（精简版）
##
## 只展示真实组件、短名称、必要操作标签与真实值；API、继承、资源路径与用法
## 说明全部放 ui/README.md，界面不写教学文字、帮助页、描述段落或说明 tooltip。
##
## 页签：按钮 / 卡片 / 输入 / 数值 / 媒体 / 菜单 / 布局 / 鼠标 / 边框 / 名牌。PixelButton、PixelTabs、PixelPanel、
## 六类输入数值组件与图片 / 图标 / 多行文本 / 动作菜单 / 弹层 / 音频 / 视频容器
## 在同一画廊真实交互；布局页真实摆出六个 Pixel 布局容器（HBox/VBox/Grid/Margin/Center/Scroll）；
## 鼠标页展示 GameCursor 指针库全部素材，悬停即预览，并可切换箭头三色风格；
## 边框页展示 PixelFrame 装饰框（frames 九宫格素材），内容驱动框体自动拉宽拉长；
## 名牌页展示 PixelNameplate 名牌底板（nameplates 素材），高度锁定、宽度随内容自动拉宽。
## 头像页展示 PixelAvatarFrame 头像边框（timeline_frames 素材），整框等比缩放、四档尺寸演示。
## 战棋页还原 story/10_ui_ux.md 的战棋界面（顶部 HUD / 行动菜单 / 技能面板 / 战斗预测 / 单位详情 /
## 战前整备 / 胜负结算 / 设置 / 背包容器），story 专属色板以 UITheme 常量近似，不引入新颜色。
## F6 独立运行，不依赖战斗参数，不修改默认启动；ESC 退出。
extends Control

const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const PixelButtonScript = preload("res://ui/components/pixel_button.gd")
const PixelTabsScript = preload("res://ui/components/pixel_tabs.gd")
const PixelPanelScene = preload("res://ui/components/pixel_panel.tscn")
const PixelLineEditScript = preload("res://ui/components/pixel_line_edit.gd")
const PixelOptionButtonScript = preload("res://ui/components/pixel_option_button.gd")
const PixelCheckButtonScript = preload("res://ui/components/pixel_check_button.gd")
const PixelSliderScript = preload("res://ui/components/pixel_slider.gd")
const PixelSpinBoxScript = preload("res://ui/components/pixel_spin_box.gd")
const PixelProgressBarScript = preload("res://ui/components/pixel_progress_bar.gd")
const PixelImageScript = preload("res://ui/components/pixel_image.gd")
const PixelIconScript = preload("res://ui/components/pixel_icon.gd")
const PixelTextAreaScript = preload("res://ui/components/pixel_text_area.gd")
const PixelDropdownScript = preload("res://ui/components/pixel_dropdown.gd")
const PixelPopupScript = preload("res://ui/components/pixel_popup.gd")
const PixelAudioPlayerScript = preload("res://ui/components/pixel_audio_player.gd")
const PixelVideoPlayerScript = preload("res://ui/components/pixel_video_player.gd")
const PixelVBoxScript = preload("res://ui/components/pixel_v_box.gd")
const PixelHBoxScript = preload("res://ui/components/pixel_h_box.gd")
const PixelGridScript = preload("res://ui/components/pixel_grid.gd")
const PixelMarginScript = preload("res://ui/components/pixel_margin.gd")
const PixelCenterScript = preload("res://ui/components/pixel_center.gd")
const PixelScrollScript = preload("res://ui/components/pixel_scroll.gd")
const PixelFrameScript = preload("res://ui/components/pixel_frame.gd")
const PixelNameplateScript = preload("res://ui/components/pixel_nameplate.gd")
const PixelAvatarScript = preload("res://ui/components/pixel_avatar_frame.gd")

## 反馈面板最多保留的历史条数（超出丢弃最早一条，避免长时间点击后无限增长）。
const FEEDBACK_MAX_LINES := 60
## 右侧反馈卡片的窄窗口最小宽度。
const SIDE_MIN_WIDTH := 360
## 页签标题：只保留短组件类别。
const DEMO_TAB_TITLES: Array[String] = ["按钮", "卡片", "输入", "数值", "媒体", "菜单", "布局", "鼠标", "边框", "名牌", "头像", "战棋"]
## 数值页滑块 / 数值框 / 进度条的共用范围。
const DEMO_VALUE_MAX: float = 100.0
## 头像页尺寸演示的四档边长（px）。
const AVATAR_SIZES: Array[int] = [80, 105, 128, 160]
## 战棋页背包容器演示的格子容量（含空格）。
const BATTLE_BAG_CAPACITY: int = 6

var _tabs: TabContainer
var _feedback_log: RichTextLabel
var _status_label: Label
var _feedback_lines: PackedStringArray = PackedStringArray()

var _primary_button: Button
var _secondary_button: Button
var _danger_button: Button
var _icon_button: Button
var _disabled_button: Button
var _toggle_button: Button
var _reset_button: Button
var _demo_sfx_switch: CheckButton

var _demo_edit: LineEdit
var _demo_option: OptionButton
var _demo_switch: CheckButton
var _preview_label: Label

var _demo_slider: HSlider
var _demo_spin: SpinBox
var _demo_progress: ProgressBar

var _demo_image: Control
var _demo_icon: TextureRect
var _demo_extra_icon: TextureRect
var _demo_audio: Control
var _demo_video: Control
var _demo_text_area: TextEdit
var _demo_dropdown: MenuButton
var _demo_popup: PopupPanel
var _open_popup_button: Button
var _arrow_style_buttons: Dictionary = {}

## GameCursor autoload 的运行时引用：契约用 --script(SceneTree) 模式运行时注册单例，
## 但编译期不注册单例标识符，直接写 GameCursor.xxx 会让画廊在该模式下无法编译。
## 一律经 _gc() 运行时解析，并用 call/get 做动态访问（静态类型 Node 上无这些成员）。
var _game_cursor: Node = null


func _gc() -> Node:
	if _game_cursor == null:
		_game_cursor = get_tree().root.get_node_or_null("GameCursor")
	return _game_cursor

## 边框页演示状态：当前素材 key 序号 / 已追加行数 / 演示框与内部文本引用。
var _frame_demo_frame: PanelContainer
var _frame_demo_text: Label
var _frame_demo_status_label: Label
var _frame_demo_key_index: int = 0
var _frame_demo_added_lines: int = 0

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

## 战棋页演示状态：设置控件 / 编队勾选，供重置复位。
var _battle_master_slider: HSlider
var _battle_music_slider: HSlider
var _battle_sfx_slider: HSlider
var _battle_size_option: OptionButton
var _battle_colorblind_option: OptionButton
var _battle_autosave_option: OptionButton
var _battle_auto_battle_switch: CheckButton
var _battle_deploy_checks: Array[CheckButton] = []
var _battle_deploy_counter: Label
## 战棋页背包容器演示状态：条目（空字典=空格）/ 格子按钮 / 选中格序号 / 详情与容量控件。
var _battle_bag_items: Array[Dictionary] = []
var _battle_bag_buttons: Array[Button] = []
var _battle_bag_selected: int = 0
var _battle_bag_detail: Label
var _battle_bag_counter: Label
var _battle_bag_action: Button


func _ready() -> void:
	_build_ui()
	_connect_signals()
	_status_label.text = "就绪"
	_primary_button.grab_focus()


## 全屏锚点 + MarginContainer + VBox + HSplitContainer：标题行固定，主体两列可拖拽。
func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = UIThemeScript.BG
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sides: Array[String] = ["left", "right", "top", "bottom"]
	for side: String in sides:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 12)
	margin.add_child(root_box)

	root_box.add_child(_build_header())

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 680
	root_box.add_child(split)

	_tabs = PixelTabsScript.new() as TabContainer
	_tabs.name = "ComponentTabs"
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(_tabs)

	_build_button_page()
	_build_panel_page()
	_build_input_page()
	_build_value_page()
	_build_media_page()
	_build_menu_page()
	_build_layout_page()
	_build_cursor_page()
	_build_frame_page()
	_build_nameplate_page()
	_build_avatar_page()
	_build_battle_page()

	var feedback_card := _make_card("反馈", "")
	feedback_card.custom_minimum_size = Vector2(SIDE_MIN_WIDTH, 0)
	feedback_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feedback_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(feedback_card)
	_build_feedback_body(_card_slot(feedback_card))


## 标题行：短标题 + 重置按钮。
func _build_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var title := UIFactoryScript.outline_label("UI 组件库", ComponentThemeScript.FONT_DISPLAY, Color.WHITE, 6)
	row.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_reset_button = UIFactoryScript.button("重置", _reset_demo)
	_reset_button.name = "ResetButton"
	_reset_button.custom_minimum_size = Vector2(96, 36)
	row.add_child(_reset_button)
	return row


## 第 1 页：三种按钮语义、图标/禁用/切换原生状态、按钮音效开关。
func _build_button_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[0]) as VBoxContainer
	page.add_theme_constant_override("separation", 12)

	var card := _make_card("按钮", "")
	_card_slot(card).add_child(_build_semantic_row())
	page.add_child(card)

	var state_card := _make_card("状态", "")
	_card_slot(state_card).add_child(_build_native_row())
	page.add_child(state_card)

	var sfx_card := _make_card("音效", "")
	_demo_sfx_switch = UIFactoryScript.check_button("音效", "")
	_demo_sfx_switch.name = "DemoSfxSwitch"
	_demo_sfx_switch.button_pressed = true
	_card_slot(sfx_card).add_child(_demo_sfx_switch)
	page.add_child(sfx_card)


func _build_semantic_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_primary_button = _make_pixel_button("主操作", 0, "play")
	_primary_button.name = "PrimaryButton"
	_secondary_button = _make_pixel_button("次操作", 1, "cog")
	_secondary_button.name = "SecondaryButton"
	_danger_button = _make_pixel_button("危险", 2, "skull")
	_danger_button.name = "DangerButton"
	var buttons: Array[Button] = [_primary_button, _secondary_button, _danger_button]
	for btn: Button in buttons:
		btn.custom_minimum_size = Vector2(0, 40)
		row.add_child(btn)
	return row


func _build_native_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_icon_button = _make_pixel_button("图标 32", 0, "star", 32)
	_icon_button.name = "IconButton"
	_icon_button.custom_minimum_size = Vector2(0, 44)
	row.add_child(_icon_button)

	_disabled_button = _make_pixel_button("禁用", 1, "info")
	_disabled_button.name = "DisabledButton"
	_disabled_button.disabled = true
	_disabled_button.custom_minimum_size = Vector2(0, 40)
	row.add_child(_disabled_button)

	_toggle_button = _make_pixel_button("切换", 1, "target")
	_toggle_button.name = "ToggleButton"
	_toggle_button.toggle_mode = true
	_toggle_button.custom_minimum_size = Vector2(0, 40)
	row.add_child(_toggle_button)
	return row


## 第 2 页：PixelPanel 卡片（有头部 / 空头部）。
func _build_panel_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[1]) as VBoxContainer
	page.add_theme_constant_override("separation", 12)

	var card := _make_card("卡片", "")
	var action := _make_pixel_button("卡片操作", 1, "target")
	action.custom_minimum_size = Vector2(0, 36)
	action.pressed.connect(_on_card_action_pressed)
	_card_slot(card).add_child(action)
	page.add_child(card)

	var bare_card := _make_card("", "")
	var bare_action := _make_pixel_button("空头部", 1, "info")
	bare_action.custom_minimum_size = Vector2(0, 36)
	_card_slot(bare_card).add_child(bare_action)
	page.add_child(bare_card)


## 第 3 页：PixelLineEdit / PixelOptionButton / PixelCheckButton + 当前值。
func _build_input_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[2]) as VBoxContainer
	page.add_theme_constant_override("separation", 12)

	var card := _make_card("输入", "")
	var slot := _card_slot(card)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)

	grid.add_child(UIFactoryScript.label("文本", 12, UIThemeScript.TEXT_MAIN))
	_demo_edit = PixelLineEditScript.new() as LineEdit
	_demo_edit.name = "DemoLineEdit"
	_demo_edit.placeholder_text = "输入"
	_demo_edit.custom_minimum_size = Vector2(260, 0)
	_demo_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_demo_edit)

	grid.add_child(UIFactoryScript.label("选项", 12, UIThemeScript.TEXT_MAIN))
	_demo_option = PixelOptionButtonScript.new() as OptionButton
	_demo_option.name = "DemoOption"
	_demo_option.add_item("A")
	_demo_option.add_item("B")
	_demo_option.add_item("C")
	_demo_option.select(0)
	grid.add_child(_demo_option)

	grid.add_child(UIFactoryScript.label("开关", 12, UIThemeScript.TEXT_MAIN))
	_demo_switch = PixelCheckButtonScript.new() as CheckButton
	_demo_switch.name = "DemoSwitch"
	_demo_switch.text = "禁用危险按钮"
	grid.add_child(_demo_switch)

	slot.add_child(grid)

	_preview_label = UIFactoryScript.label("值：—", 13, UIThemeScript.TEXT_MAIN)
	_preview_label.name = "PreviewLabel"
	slot.add_child(_preview_label)
	page.add_child(card)


## 第 4 页：PixelSlider / PixelProgressBar / PixelSpinBox，滑块与数值框联动进度。
func _build_value_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[3]) as VBoxContainer
	page.add_theme_constant_override("separation", 12)

	var card := _make_card("数值", "")
	var slot := _card_slot(card)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)

	grid.add_child(UIFactoryScript.label("滑块", 12, UIThemeScript.TEXT_MAIN))
	_demo_slider = PixelSliderScript.new() as HSlider
	_demo_slider.name = "DemoSlider"
	_demo_slider.min_value = 0.0
	_demo_slider.max_value = DEMO_VALUE_MAX
	_demo_slider.step = 1.0
	_demo_slider.value = 0.0
	_demo_slider.custom_minimum_size = Vector2(260, 0)
	_demo_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_demo_slider)

	grid.add_child(UIFactoryScript.label("进度", 12, UIThemeScript.TEXT_MAIN))
	_demo_progress = PixelProgressBarScript.new() as ProgressBar
	_demo_progress.name = "DemoProgress"
	_demo_progress.min_value = 0.0
	_demo_progress.max_value = DEMO_VALUE_MAX
	_demo_progress.value = 0.0
	_demo_progress.custom_minimum_size = Vector2(260, 0)
	_demo_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_demo_progress)

	grid.add_child(UIFactoryScript.label("数值", 12, UIThemeScript.TEXT_MAIN))
	_demo_spin = PixelSpinBoxScript.new() as SpinBox
	_demo_spin.name = "DemoSpinBox"
	_demo_spin.min_value = 0.0
	_demo_spin.max_value = DEMO_VALUE_MAX
	_demo_spin.step = 1.0
	_demo_spin.value = 0.0
	grid.add_child(_demo_spin)

	slot.add_child(grid)
	page.add_child(card)


## 第 5 页：图片 / 图标 / 音频 / 视频容器（全部用项目内真实素材）。
func _build_media_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[4]) as VBoxContainer
	page.add_theme_constant_override("separation", 12)

	var image_card := _make_card("图片", "")
	_demo_image = PixelImageScript.new() as Control
	_demo_image.name = "DemoImage"
	_demo_image.set("texture", load("res://assets/markers/tile_box.png"))
	_demo_image.set("image_size", Vector2i(240, 135))
	_demo_image.set("stretch_mode", TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	_card_slot(image_card).add_child(_demo_image)
	page.add_child(image_card)

	var icon_card := _make_card("图标", "")
	var icon_row := HBoxContainer.new()
	icon_row.add_theme_constant_override("separation", 16)
	_demo_icon = PixelIconScript.new() as TextureRect
	_demo_icon.name = "DemoIcon"
	_demo_icon.texture = UIThemeScript.icon("star")
	_demo_icon.set("icon_size", 48)
	icon_row.add_child(_demo_icon)
	_demo_extra_icon = PixelIconScript.new() as TextureRect
	_demo_extra_icon.name = "DemoExtraIcon"
	_demo_extra_icon.texture = UIThemeScript.icon("play")
	_demo_extra_icon.set("icon_size", 28)
	_demo_extra_icon.set("icon_color", UIThemeScript.ACCENT)
	icon_row.add_child(_demo_extra_icon)
	_card_slot(icon_card).add_child(icon_row)
	page.add_child(icon_card)

	var audio_card := _make_card("音频", "")
	_demo_audio = PixelAudioPlayerScript.new() as Control
	_demo_audio.name = "DemoAudioPlayer"
	_demo_audio.set("stream", load("res://assets/audio/sfx/ui/sfx_ui_confirm.mp3"))
	_demo_audio.set("volume_db", -2.0)
	_card_slot(audio_card).add_child(_demo_audio)
	page.add_child(audio_card)

	var video_card := _make_card("视频", "")
	_demo_video = PixelVideoPlayerScript.new() as Control
	_demo_video.name = "DemoVideoPlayer"
	_demo_video.set("stream", load("res://assets/video/ui/ui_demo.ogv"))
	_demo_video.set("video_size", Vector2i(320, 180))
	_card_slot(video_card).add_child(_demo_video)
	page.add_child(video_card)


## 第 6 页：多行文本 / 动作菜单 / 弹层。
func _build_menu_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[5]) as VBoxContainer
	page.add_theme_constant_override("separation", 12)

	var text_card := _make_card("多行文本", "")
	_demo_text_area = PixelTextAreaScript.new() as TextEdit
	_demo_text_area.name = "DemoTextArea"
	_demo_text_area.placeholder = "多行文本"
	_demo_text_area.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_demo_text_area.custom_minimum_size = Vector2(0, 120)
	_card_slot(text_card).add_child(_demo_text_area)
	page.add_child(text_card)

	var menu_card := _make_card("菜单", "")
	var menu_row := HBoxContainer.new()
	menu_row.add_theme_constant_override("separation", 12)
	_demo_dropdown = PixelDropdownScript.new() as MenuButton
	_demo_dropdown.name = "DemoDropdown"
	_demo_dropdown.text = "动作"
	_demo_dropdown.set("items", PackedStringArray(["打开", "复制", "删除"]))
	menu_row.add_child(_demo_dropdown)
	_card_slot(menu_card).add_child(menu_row)
	page.add_child(menu_card)

	var popup_card := _make_card("弹层", "")
	_open_popup_button = _make_pixel_button("打开", 1, "info")
	_open_popup_button.name = "OpenPopupButton"
	_card_slot(popup_card).add_child(_open_popup_button)
	page.add_child(popup_card)

	_demo_popup = PixelPopupScript.new() as PopupPanel
	_demo_popup.name = "DemoPopup"
	var popup_box := VBoxContainer.new()
	popup_box.custom_minimum_size = Vector2(240, 120)
	popup_box.add_theme_constant_override("separation", 8)
	popup_box.add_child(UIFactoryScript.label("弹层", 13, UIThemeScript.TEXT_MAIN))
	var popup_close := _make_pixel_button("关闭", 1, "")
	popup_close.name = "PopupCloseButton"
	popup_close.pressed.connect(_on_popup_close_pressed)
	popup_box.add_child(popup_close)
	_demo_popup.add_child(popup_box)
	add_child(_demo_popup)


## 第 7 页：六个布局容器的真实摆位（HBox/VBox/Grid/Margin/Center/Scroll）。
func _build_layout_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[6]) as VBoxContainer
	page.add_theme_constant_override("separation", 12)

	# PixelHBox：横向排布，子项间距走 gap（默认 16）。
	var hbox_card := _make_card("横排", "")
	var hbox := PixelHBoxScript.new() as HBoxContainer
	hbox.name = "LayoutHBox"
	hbox.add_child(_make_layout_chip("甲"))
	hbox.add_child(_make_layout_chip("乙"))
	hbox.add_child(_make_layout_chip("丙"))
	_card_slot(hbox_card).add_child(hbox)
	page.add_child(hbox_card)

	# PixelVBox：纵向排布，子项间距走 gap（默认 16）。
	var vbox_card := _make_card("竖排", "")
	var vbox := PixelVBoxScript.new() as VBoxContainer
	vbox.name = "LayoutVBox"
	vbox.add_child(_make_layout_chip("丁"))
	vbox.add_child(_make_layout_chip("戊"))
	_card_slot(vbox_card).add_child(vbox)
	page.add_child(vbox_card)

	# PixelGrid：两列网格，横纵间距走 h_gap / v_gap（默认 16）。
	var grid_card := _make_card("网格", "")
	var grid := PixelGridScript.new() as GridContainer
	grid.name = "LayoutGrid"
	grid.columns = 2
	for chip_name: String in ["己", "庚", "辛", "壬"]:
		grid.add_child(_make_layout_chip(chip_name))
	_card_slot(grid_card).add_child(grid)
	page.add_child(grid_card)

	# PixelMargin：内容边距走 margin（默认 24），子项整体内缩。
	var margin_card := _make_card("边距", "")
	var margin_box := PixelMarginScript.new() as MarginContainer
	margin_box.name = "LayoutMargin"
	var margin_label := UIFactoryScript.label("边距 24", 12, UIThemeScript.TEXT_MAIN)
	margin_label.name = "LayoutMarginChild"
	margin_box.add_child(margin_label)
	_card_slot(margin_card).add_child(margin_box)
	page.add_child(margin_card)

	# PixelCenter：子项在剩余空间内水平垂直居中。
	var center_card := _make_card("居中", "")
	var center_box := PixelCenterScript.new() as CenterContainer
	center_box.name = "LayoutCenter"
	center_box.custom_minimum_size = Vector2(0, 64)
	var center_child := _make_pixel_button("居中", 1, "")
	center_child.name = "LayoutCenterChild"
	center_box.add_child(center_child)
	_card_slot(center_card).add_child(center_box)
	page.add_child(center_card)

	# PixelScroll：默认仅纵向滚动、双向 Expand Fill；内容高于可视区时出纵滚动条。
	var scroll_card := _make_card("滚动", "")
	var scroll := PixelScrollScript.new() as ScrollContainer
	scroll.name = "LayoutScroll"
	scroll.custom_minimum_size = Vector2(0, 140)
	var scroll_content := PixelVBoxScript.new() as VBoxContainer
	scroll_content.name = "LayoutScrollContent"
	for i: int in range(6):
		var row := UIFactoryScript.label("滚动内容 %d" % (i + 1), 12, UIThemeScript.TEXT_MAIN)
		row.custom_minimum_size = Vector2(200, 40)
		scroll_content.add_child(row)
	scroll.add_child(scroll_content)
	_card_slot(scroll_card).add_child(scroll)
	page.add_child(scroll_card)


## 布局页演示用小块：固定最小尺寸的短文本标签，保证间距断言可计算。
func _make_layout_chip(chip_text: String) -> Label:
	var chip := UIFactoryScript.label(chip_text, 12, UIThemeScript.TEXT_MAIN)
	chip.custom_minimum_size = Vector2(40, 20)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return chip


## 第 8 页：GameCursor 指针库全部素材（悬停预览）+ 箭头三色风格切换。
func _build_cursor_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[7]) as VBoxContainer
	page.add_theme_constant_override("separation", 12)

	var cursor_card := _make_card("指针", "")
	var grid := PixelGridScript.new() as GridContainer
	grid.name = "CursorGrid"
	grid.columns = 5
	var cursor_library: Array = _gc().get("CURSOR_LIBRARY") if _gc() != null else []
	for item: Dictionary in cursor_library:
		grid.add_child(_make_cursor_cell(item))
	_card_slot(cursor_card).add_child(grid)
	page.add_child(cursor_card)

	var style_card := _make_card("箭头风格", "")
	var style_row := HBoxContainer.new()
	style_row.add_theme_constant_override("separation", 10)
	var active_style: String = _gc().call("get_arrow_style") if _gc() != null else "white"
	for style_name: String in ["white", "blue", "gold"]:
		var btn := _make_pixel_button(_arrow_style_label(style_name), 1, "")
		btn.name = "ArrowStyle_" + style_name
		btn.toggle_mode = true
		btn.set_pressed_no_signal(style_name == active_style)
		# 按钮引用与回调在构建时绑定（同一批生成，无需进 _connect_signals）。
		_arrow_style_buttons[style_name] = btn
		btn.toggled.connect(_on_arrow_style_toggled.bind(style_name))
		style_row.add_child(btn)
	_card_slot(style_card).add_child(style_row)
	page.add_child(style_card)


## 单个指针格：PixelImage 原尺寸展示 + 短标签；悬停即预览该指针，移出恢复。
func _make_cursor_cell(item: Dictionary) -> Control:
	var cell := PanelContainer.new()
	cell.name = "CursorCell"
	cell.custom_minimum_size = Vector2(84, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var icon := PixelImageScript.new() as Control
	icon.name = "CursorIcon"
	icon.set("texture", item["texture"])
	icon.set("image_size", Vector2i(32, 32))
	box.add_child(icon)
	var caption := UIFactoryScript.label(item["label"], 11, UIThemeScript.TEXT_MAIN)
	caption.name = "CursorLabel"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)
	cell.add_child(box)
	cell.mouse_entered.connect(_on_cursor_cell_entered.bind(item))
	cell.mouse_exited.connect(_on_cursor_cell_exited)
	return cell


func _arrow_style_label(style_name: String) -> String:
	return {"white": "白", "blue": "蓝", "gold": "金"}.get(style_name, style_name)


func _on_cursor_cell_entered(item: Dictionary) -> void:
	if _gc() != null:
		_gc().call("preview_cursor", item["texture"], item["hotspot"])
	_status_label.text = "指针：%s" % item["label"]


func _on_cursor_cell_exited() -> void:
	if _gc() != null:
		_gc().call("restore_cursor")


func _on_arrow_style_toggled(toggled_on: bool, style_name: String) -> void:
	if _gc() == null:
		return
	if not toggled_on:
		# 当前激活风格不允许点击取消，保持按下。
		if style_name == _gc().call("get_arrow_style"):
			(_arrow_style_buttons[style_name] as Button).set_pressed_no_signal(true)
		return
	_gc().call("set_arrow_style", style_name)
	for other: String in _arrow_style_buttons:
		(_arrow_style_buttons[other] as Button).set_pressed_no_signal(other == style_name)
	_status_label.text = "箭头：%s" % _arrow_style_label(style_name)
	_log_feedback("箭头风格 → %s" % _arrow_style_label(style_name))


## 第 9 页：PixelFrame 装饰框（frames 九宫格素材）+ 内容驱动自适应演示。
func _build_frame_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[8]) as VBoxContainer
	page.add_theme_constant_override("separation", 12)

	var demo_card := _make_card("自适应演示", "")
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
	_card_slot(demo_card).add_child(demo_row)
	page.add_child(demo_card)

	var gallery_card := _make_card("素材图鉴", "")
	var gallery := VBoxContainer.new()
	gallery.name = "FrameGallery"
	gallery.add_theme_constant_override("separation", 10)
	for key: String in PixelFrameScript.FRAME_TEXTURES.keys():
		gallery.add_child(_make_frame_gallery_row(key))
	_card_slot(gallery_card).add_child(gallery)
	page.add_child(gallery_card)


## 演示框右侧控制列：切换素材 / 追加一行 / 清空 + 状态行。
func _build_frame_demo_controls() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "FrameDemoControls"
	box.add_theme_constant_override("separation", 8)
	var next_btn := _make_pixel_button("切换素材", 1, "cog")
	next_btn.name = "FrameStyleNextButton"
	next_btn.pressed.connect(_on_frame_style_next)
	box.add_child(next_btn)
	var add_btn := _make_pixel_button("追加一行", 0, "play")
	add_btn.name = "FrameLineAddButton"
	add_btn.pressed.connect(_on_frame_line_add)
	box.add_child(add_btn)
	var clear_btn := _make_pixel_button("清空", 2, "skull")
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


func _frame_demo_status() -> String:
	var key: String = PixelFrameScript.FRAME_TEXTURES.keys()[_frame_demo_key_index]
	return "%s · 追加 %d 行" % [PixelFrameScript.FRAME_LABELS[key], _frame_demo_added_lines]


func _on_frame_style_next() -> void:
	_frame_demo_key_index = (_frame_demo_key_index + 1) % PixelFrameScript.FRAME_TEXTURES.size()
	var key: String = PixelFrameScript.FRAME_TEXTURES.keys()[_frame_demo_key_index]
	_frame_demo_frame.set("frame_key", key)
	_frame_demo_status_label.text = _frame_demo_status()
	_log_feedback("框体 → %s" % PixelFrameScript.FRAME_LABELS[key])


func _on_frame_line_add() -> void:
	_frame_demo_added_lines += 1
	_frame_demo_text.text += "\n追加第 %d 行：框随内容自动拉长。" % _frame_demo_added_lines
	_frame_demo_status_label.text = _frame_demo_status()


func _on_frame_line_clear() -> void:
	_frame_demo_added_lines = 0
	_frame_demo_text.text = "内容决定框体：点右侧「追加一行」，框随内容自动拉长。"
	_frame_demo_status_label.text = _frame_demo_status()


## 第 10 页：PixelNameplate 名牌底板（nameplates 素材）+ 高度锁定、宽度随内容演示。
func _build_nameplate_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[9]) as VBoxContainer
	page.add_theme_constant_override("separation", 12)

	var demo_card := _make_card("自适应演示", "")
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
	_card_slot(demo_card).add_child(demo_row)
	page.add_child(demo_card)

	var gallery_card := _make_card("素材图鉴", "")
	var gallery := VBoxContainer.new()
	gallery.name = "NameplateGallery"
	gallery.add_theme_constant_override("separation", 10)
	for key: String in PixelNameplateScript.NAMEPLATE_TEXTURES.keys():
		gallery.add_child(_make_nameplate_gallery_row(key))
	_card_slot(gallery_card).add_child(gallery)
	page.add_child(gallery_card)


## 演示名牌右侧控制列：切换素材 / 追加称号 / 清空 + 状态行。
func _build_nameplate_demo_controls() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "NameplateDemoControls"
	box.add_theme_constant_override("separation", 8)
	var next_btn := _make_pixel_button("切换素材", 1, "cog")
	next_btn.name = "NameplateStyleNextButton"
	next_btn.pressed.connect(_on_nameplate_style_next)
	box.add_child(next_btn)
	var add_btn := _make_pixel_button("追加称号", 0, "play")
	add_btn.name = "NameplateCharAddButton"
	add_btn.pressed.connect(_on_nameplate_char_add)
	box.add_child(add_btn)
	var clear_btn := _make_pixel_button("清空", 2, "skull")
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


func _nameplate_demo_status() -> String:
	var key: String = PixelNameplateScript.NAMEPLATE_TEXTURES.keys()[_nameplate_demo_key_index]
	return "%s · 称号 %d" % [PixelNameplateScript.NAMEPLATE_LABELS[key], _nameplate_demo_exclaims]


func _on_nameplate_style_next() -> void:
	_nameplate_demo_key_index = (_nameplate_demo_key_index + 1) % PixelNameplateScript.NAMEPLATE_TEXTURES.size()
	var key: String = PixelNameplateScript.NAMEPLATE_TEXTURES.keys()[_nameplate_demo_key_index]
	_nameplate_demo_plate.set("frame_key", key)
	_nameplate_demo_status_label.text = _nameplate_demo_status()
	_log_feedback("名牌 → %s" % PixelNameplateScript.NAMEPLATE_LABELS[key])


func _on_nameplate_char_add() -> void:
	_nameplate_demo_exclaims += 1
	_nameplate_demo_label.text += "!"
	_nameplate_demo_status_label.text = _nameplate_demo_status()


func _on_nameplate_char_clear() -> void:
	_nameplate_demo_exclaims = 0
	_nameplate_demo_label.text = "勇者 · Lv.12"
	_nameplate_demo_status_label.text = _nameplate_demo_status()


## 第 11 页：PixelAvatarFrame 头像边框（timeline_frames 素材）+ 四档尺寸等比演示。
func _build_avatar_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[10]) as VBoxContainer
	page.add_theme_constant_override("separation", 12)

	var demo_card := _make_card("尺寸演示", "")
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
	_card_slot(demo_card).add_child(demo_row)
	page.add_child(demo_card)

	var gallery_card := _make_card("素材图鉴", "")
	var gallery := VBoxContainer.new()
	gallery.name = "AvatarGallery"
	gallery.add_theme_constant_override("separation", 10)
	for key: String in PixelAvatarScript.AVATAR_TEXTURES.keys():
		gallery.add_child(_make_avatar_gallery_row(key))
	_card_slot(gallery_card).add_child(gallery)
	page.add_child(gallery_card)


## 尺寸演示右侧控制列：切换素材 / 放大 / 缩小 + 状态行。
func _build_avatar_demo_controls() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "AvatarDemoControls"
	box.add_theme_constant_override("separation", 8)
	var next_btn := _make_pixel_button("切换素材", 1, "cog")
	next_btn.name = "AvatarStyleNextButton"
	next_btn.pressed.connect(_on_avatar_style_next)
	box.add_child(next_btn)
	var up_btn := _make_pixel_button("放大", 0, "star")
	up_btn.name = "AvatarSizeUpButton"
	up_btn.pressed.connect(_on_avatar_size_up)
	box.add_child(up_btn)
	var down_btn := _make_pixel_button("缩小", 1, "target")
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


func _avatar_demo_status() -> String:
	var key: String = PixelAvatarScript.AVATAR_TEXTURES.keys()[_avatar_demo_key_index]
	return "%s · %dpx" % [PixelAvatarScript.AVATAR_LABELS[key], AVATAR_SIZES[_avatar_demo_size_index]]


func _apply_avatar_size() -> void:
	var px: int = AVATAR_SIZES[_avatar_demo_size_index]
	_avatar_demo_frame.custom_minimum_size = Vector2(px, px)


func _on_avatar_style_next() -> void:
	_avatar_demo_key_index = (_avatar_demo_key_index + 1) % PixelAvatarScript.AVATAR_TEXTURES.size()
	var key: String = PixelAvatarScript.AVATAR_TEXTURES.keys()[_avatar_demo_key_index]
	_avatar_demo_frame.set("frame_key", key)
	_avatar_demo_status_label.text = _avatar_demo_status()
	_log_feedback("头像框 → %s" % PixelAvatarScript.AVATAR_LABELS[key])


func _on_avatar_size_up() -> void:
	_avatar_demo_size_index = mini(_avatar_demo_size_index + 1, AVATAR_SIZES.size() - 1)
	_apply_avatar_size()
	_avatar_demo_status_label.text = _avatar_demo_status()
	_log_feedback("头像框尺寸 → %dpx" % AVATAR_SIZES[_avatar_demo_size_index])


func _on_avatar_size_down() -> void:
	_avatar_demo_size_index = maxi(_avatar_demo_size_index - 1, 0)
	_apply_avatar_size()
	_avatar_demo_status_label.text = _avatar_demo_status()
	_log_feedback("头像框尺寸 → %dpx" % AVATAR_SIZES[_avatar_demo_size_index])


## 右侧反馈卡片内容：状态行 + 富文本历史。
func _build_feedback_body(slot: Container) -> void:
	_status_label = UIFactoryScript.label("就绪", 13, UIThemeScript.TEXT_MAIN)
	_status_label.name = "StatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot.add_child(_status_label)

	_feedback_log = RichTextLabel.new()
	_feedback_log.name = "FeedbackLog"
	_feedback_log.bbcode_enabled = true
	_feedback_log.scroll_following = true
	_feedback_log.selection_enabled = true
	_feedback_log.focus_mode = Control.FOCUS_CLICK
	_feedback_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback_log.custom_minimum_size = Vector2(0, 220)
	_feedback_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_feedback_log.add_theme_font_size_override("normal_font_size", ComponentThemeScript.FONT_CAPTION)
	_feedback_log.add_theme_color_override("default_color", Color(0.85, 0.9, 0.9))
	slot.add_child(_feedback_log)


## 统一接线：演示控件只在这里挂信号，回调只更新反馈/状态与联动，不改业务状态。
func _connect_signals() -> void:
	_primary_button.pressed.connect(_on_semantic_pressed.bind("主操作"))
	_secondary_button.pressed.connect(_on_semantic_pressed.bind("次操作"))
	_danger_button.pressed.connect(_on_semantic_pressed.bind("危险"))
	_icon_button.pressed.connect(_on_semantic_pressed.bind("图标"))
	_toggle_button.toggled.connect(_on_toggle_toggled)
	# _reset_button 的回调已由 UIFactory.button() 构造时绑定，这里不重复 connect。
	_demo_edit.text_changed.connect(_on_text_changed)
	_demo_edit.text_submitted.connect(_on_text_submitted)
	_demo_option.item_selected.connect(_on_option_selected)
	_demo_switch.toggled.connect(_on_switch_toggled)
	_demo_sfx_switch.toggled.connect(_on_sfx_toggled)
	_demo_slider.value_changed.connect(_on_slider_changed)
	_demo_spin.value_changed.connect(_on_spin_changed)
	_tabs.tab_changed.connect(_on_tab_changed)
	_demo_dropdown.get_popup().id_pressed.connect(_on_dropdown_id_pressed)
	_demo_text_area.text_changed.connect(_on_text_area_changed)
	_open_popup_button.pressed.connect(_on_open_popup_pressed)
	_demo_audio.connect("playback_started", _on_audio_state_changed.bind("播放"))
	_demo_audio.connect("playback_paused", _on_audio_state_changed.bind("暂停"))
	_demo_audio.connect("playback_stopped", _on_audio_state_changed.bind("停止"))
	_demo_video.connect("playback_started", _on_video_state_changed.bind("播放"))
	_demo_video.connect("playback_paused", _on_video_state_changed.bind("暂停"))
	_demo_video.connect("playback_stopped", _on_video_state_changed.bind("停止"))


## 生成一个 PixelButton（不依赖全局类名，统一走 preload 脚本 + 动态属性）。
func _make_pixel_button(
	label_text: String, semantic: int, icon_name: String = "", icon_size: int = 0
) -> Button:
	var btn: Button = PixelButtonScript.new()
	btn.text = label_text
	btn.set("semantic", semantic)
	if not icon_name.is_empty():
		btn.icon = UIThemeScript.icon(icon_name)
	if icon_size > 0:
		btn.set("icon_size", icon_size)
	return btn


## 实例化卡片 PackedScene 并写入短标题；内容由调用方通过 _card_slot 注入。
func _make_card(title_text: String, description_text: String) -> PanelContainer:
	var panel: PanelContainer = PixelPanelScene.instantiate() as PanelContainer
	panel.set("title", title_text)
	panel.set("description", description_text)
	return panel


func _card_slot(card: PanelContainer) -> Container:
	return card.call("get_content_slot") as Container


func _log_feedback(message: String) -> void:
	var stamp := Time.get_time_string_from_system()
	_feedback_lines.append(
		"[color=#%s]%s[/color] %s" % [UIThemeScript.ACCENT.to_html(false), stamp, message]
	)
	if _feedback_lines.size() > FEEDBACK_MAX_LINES:
		_feedback_lines.remove_at(0)
	_feedback_log.text = "\n".join(_feedback_lines)
	_feedback_log.scroll_to_line(_feedback_log.get_line_count() - 1)


func _on_semantic_pressed(which: String) -> void:
	_status_label.text = "按下「%s」" % which
	_log_feedback("按钮「%s」" % which)


func _on_toggle_toggled(toggled_on: bool) -> void:
	_status_label.text = "切换：%s" % ("开" if toggled_on else "关")
	_log_feedback("切换 → %s" % ("开" if toggled_on else "关"))


func _on_card_action_pressed() -> void:
	_status_label.text = "卡片操作"
	_log_feedback("卡片操作")


func _on_text_changed(new_text: String) -> void:
	var preview := new_text
	if preview.length() > 40:
		preview = preview.substr(0, 40) + "…"
	_preview_label.text = "值：%s" % (preview if not preview.is_empty() else "—")
	_status_label.text = "文本长度：%d" % new_text.length()


func _on_text_submitted(new_text: String) -> void:
	_status_label.text = "文本已提交"
	_log_feedback("文本提交「%s」" % new_text)


func _on_option_selected(index: int) -> void:
	var item_text := _demo_option.get_item_text(index)
	_status_label.text = "选项：%s" % item_text
	_log_feedback("选项 → %s" % item_text)


func _on_switch_toggled(toggled_on: bool) -> void:
	_danger_button.disabled = toggled_on
	_status_label.text = "危险按钮%s" % ("禁用" if toggled_on else "启用")
	_log_feedback("开关 → %s" % ("开" if toggled_on else "关"))


func _on_slider_changed(value: float) -> void:
	_demo_progress.value = value
	_demo_spin.set_value_no_signal(value)
	_status_label.text = "滑块：%d" % int(value)
	_log_feedback("滑块 → %d" % int(value))


func _on_spin_changed(value: float) -> void:
	_demo_slider.set_value_no_signal(value)
	_demo_progress.value = value
	_status_label.text = "数值：%d" % int(value)
	_log_feedback("数值 → %d" % int(value))


func _on_tab_changed(tab: int) -> void:
	var tab_title := _tabs.get_tab_title(tab)
	_status_label.text = "页签：%s" % tab_title
	_log_feedback("页签 → %s" % tab_title)


func _on_dropdown_id_pressed(id: int) -> void:
	var popup: PopupMenu = _demo_dropdown.get_popup()
	var item_text := popup.get_item_text(id) if id >= 0 and id < popup.item_count else str(id)
	_status_label.text = "动作：%s" % item_text
	_log_feedback("动作 → %s" % item_text)


func _on_text_area_changed() -> void:
	var line_count := _demo_text_area.get_line_count()
	_status_label.text = "多行文本：%d 行" % line_count
	_log_feedback("文本域 → %d 行" % line_count)


func _on_open_popup_pressed() -> void:
	_demo_popup.call("open_for", _open_popup_button)
	_status_label.text = "弹层打开"
	_log_feedback("弹层 → 打开")


func _on_popup_close_pressed() -> void:
	_demo_popup.hide()
	_status_label.text = "弹层关闭"
	_log_feedback("弹层 → 关闭")


func _on_audio_state_changed(state: String) -> void:
	_status_label.text = "音频：%s" % state
	_log_feedback("音频 → %s" % state)


func _on_video_state_changed(state: String) -> void:
	_status_label.text = "视频：%s" % state
	_log_feedback("视频 → %s" % state)


## 第 12 页：战棋界面（story/10_ui_ux.md 布局还原；骨架 PixelMargin→PixelVBox→PixelHBox，
## 溢出滚动由 add_tab 统一的「战棋Scroll」外壳承担，页内不再套第二层滚动容器）。
func _build_battle_page() -> void:
	var page: VBoxContainer = _tabs.call("add_pixel_tab", DEMO_TAB_TITLES[11]) as VBoxContainer

	var margin := PixelMarginScript.new() as MarginContainer
	margin.name = "BattleMargin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(margin)

	var column := PixelVBoxScript.new() as VBoxContainer
	column.name = "BattleColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_MD)
	margin.add_child(column)

	column.add_child(_battle_row([
		_build_battle_hud_card(), _build_battle_menu_card(), _build_battle_skill_card(),
	]))
	column.add_child(_battle_row([_build_battle_preview_card(), _build_battle_detail_card()]))
	column.add_child(_battle_row([_build_battle_prep_card(), _build_battle_victory_card()]))
	column.add_child(_battle_row([_build_battle_defeat_card(), _build_battle_settings_card()]))
	column.add_child(_battle_row([_build_battle_bag_card()]))


## 战棋页一行卡片：PixelHBox + 卡片均分，竖向收缩避免行内拉高。
func _battle_row(cards: Array) -> HBoxContainer:
	var row := PixelHBoxScript.new() as HBoxContainer
	row.name = "BattleRow"
	row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_MD)
	for card: PanelContainer in cards:
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(card)
	return row


## 顶部 HUD：回合阶段 + 友军/敌军存活计数 + 任务目标。
func _build_battle_hud_card() -> PanelContainer:
	var card := _make_card("顶部 HUD", "")
	card.name = "BattleHudCard"
	var slot := _card_slot(card)
	var row := HBoxContainer.new()
	row.name = "BattleHudRow"
	row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var phase := UIFactoryScript.label("回合 #3 · 玩家阶段", ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN)
	phase.name = "BattleHudPhase"
	row.add_child(phase)
	row.add_child(_battle_force_counter("友军", 6, 8))
	row.add_child(_battle_force_counter("敌军", 4, 7))
	var objective := UIFactoryScript.label("▶ 解救村民(0/2)", ComponentThemeScript.FONT_BODY, UIThemeScript.ACCENT)
	objective.name = "BattleHudObjective"
	row.add_child(objective)
	slot.add_child(row)
	return card


## 友军/敌军计数：短标签 + PixelProgressBar 存活比例。
func _battle_force_counter(force_name: String, alive: int, total: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = force_name + "Counter"
	box.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	box.add_child(
		UIFactoryScript.label("%s %d/%d" % [force_name, alive, total], ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM)
	)
	var bar := PixelProgressBarScript.new() as ProgressBar
	bar.max_value = total
	bar.value = alive
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(64, 8)
	box.add_child(bar)
	return box


## 行动菜单：推荐项置顶（主操作），其余次操作，Esc 撤销收尾。
func _build_battle_menu_card() -> PanelContainer:
	var card := _make_card("行动菜单", "")
	card.name = "BattleMenuCard"
	var slot := _card_slot(card)
	var menu := VBoxContainer.new()
	menu.name = "BattleMenuList"
	menu.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	var entries: Array[Array] = [
		["BattleMenuAttack", "★ 攻击（3 目标）", 0],
		["BattleMenuSkill", "技能（2 可用）", 1],
		["BattleMenuItem", "物品（1 可用）", 1],
		["BattleMenuWait", "等待", 1],
		["BattleMenuUndo", "✕ 撤销移动（Esc）", 1],
	]
	for entry: Array in entries:
		var btn := _make_pixel_button(entry[1], entry[2], "")
		btn.name = entry[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_battle_menu_pressed.bind(entry[1]))
		menu.add_child(btn)
	slot.add_child(menu)
	return card


## 技能面板：标题含 MP 余量；可用技能主/次操作，无目标与 MP 不足的项灰显。
func _build_battle_skill_card() -> PanelContainer:
	var card := _make_card("技能面板", "")
	card.name = "BattleSkillCard"
	var slot := _card_slot(card)
	var column := VBoxContainer.new()
	column.name = "BattleSkillColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	column.add_child(
		UIFactoryScript.label("技能 · 莉雅　MP 12/20", ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN)
	)
	var entries: Array[Array] = [
		["BattleSkillFire", "★ 火球术　MP 6 · 射程 1-3 · 预伤 18-24", 0, false],
		["BattleSkillFrost", "寒霜之触　MP 4 · 射程 1-2 · 预伤 10-14", 1, false],
		["BattleSkillShield", "魔法护盾　MP 3（无目标）", 1, true],
		["BattleSkillBlizzard", "暴风雪　MP 15（MP 不足）", 1, true],
	]
	for entry: Array in entries:
		var btn := _make_pixel_button(entry[1], entry[2], "")
		btn.name = entry[0]
		btn.disabled = entry[3]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not btn.disabled:
			btn.pressed.connect(_on_battle_menu_pressed.bind(entry[1]))
		column.add_child(btn)
	slot.add_child(column)
	return card


## 战斗预测：攻/守双列（HP 条 + 命中/伤害/必杀）+  weapon 克制与风险三色提示。
func _build_battle_preview_card() -> PanelContainer:
	var card := _make_card("战斗预测", "")
	card.name = "BattlePreviewCard"
	var slot := _card_slot(card)
	var column := VBoxContainer.new()
	column.name = "BattlePreviewColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)
	var grid := PixelGridScript.new() as GridContainer
	grid.name = "BattlePreviewGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", ComponentThemeScript.SPACE_MD)
	grid.add_theme_constant_override("v_separation", ComponentThemeScript.SPACE_XS)
	grid.add_child(_battle_combatant_column(
		"BattlePreviewAttacker", "⚔ 凯尔 [剑士]", 22, 24, ["命中 92%", "伤害 12 ×2双击", "必杀 7%"]
	))
	grid.add_child(_battle_combatant_column(
		"BattlePreviewDefender", "🛡 敌兵 [枪兵]", 9, 18, ["反击命中 41%", "反击伤害 4"]
	))
	column.add_child(grid)
	var tips := VBoxContainer.new()
	tips.name = "BattlePreviewTips"
	tips.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	tips.add_child(UIFactoryScript.label(
		"▲ 剑 克 枪（+15% 命中 +3 伤害）", ComponentThemeScript.FONT_CAPTION, UIThemeScript.ACCENT
	))
	tips.add_child(UIFactoryScript.label(
		"⚠ 敌人 HP 降至 0 → 可击杀", ComponentThemeScript.FONT_CAPTION, UIThemeScript.ERROR
	))
	tips.add_child(UIFactoryScript.label(
		"⚠ 敌人射程 1，你移入后将受反击", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TOAST_COLOR
	))
	column.add_child(tips)
	slot.add_child(column)
	return card


## 攻方/守方一列：名字 + HP 条 + 数值行。
func _battle_combatant_column(
	node_name: String, header: String, cur: float, maxv: float, lines: Array
) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = node_name
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	column.add_child(UIFactoryScript.label(header, ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN))
	var bar := PixelProgressBarScript.new() as ProgressBar
	bar.name = node_name + "Hp"
	bar.max_value = maxv
	bar.value = cur
	bar.show_percentage = false
	column.add_child(bar)
	column.add_child(
		UIFactoryScript.label("HP %d/%d" % [int(cur), int(maxv)], ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM)
	)
	for line_text: String in lines:
		column.add_child(UIFactoryScript.label(line_text, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN))
	return column


## 单位详情：名字 + 主角标签 / HP MP EXP 三条 / 属性四列网格 / 装备技能背包状态地形。
func _build_battle_detail_card() -> PanelContainer:
	var card := _make_card("单位详情", "")
	card.name = "BattleDetailCard"
	var slot := _card_slot(card)
	var column := VBoxContainer.new()
	column.name = "BattleDetailColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	header.add_child(
		UIFactoryScript.label("凯尔 [剑士·Lv5]", ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN)
	)
	header.add_child(UIFactoryScript.label("主角", ComponentThemeScript.FONT_CAPTION, UIThemeScript.ACCENT))
	column.add_child(header)
	column.add_child(_battle_bar_row("BattleDetailHp", "HP", 22, 24))
	column.add_child(_battle_bar_row("BattleDetailMp", "MP", 0, 0))
	column.add_child(_battle_bar_row("BattleDetailExp", "EXP", 74, 100))
	var stats := PixelGridScript.new() as GridContainer
	stats.name = "BattleDetailStats"
	stats.columns = 4
	stats.add_theme_constant_override("h_separation", ComponentThemeScript.SPACE_XS)
	stats.add_theme_constant_override("v_separation", ComponentThemeScript.SPACE_XS)
	for stat_pair: Array in [
		["力", 9], ["速", 8], ["技", 7], ["运", 6], ["防", 5], ["魔防", 2], ["移动", 5], ["射程", 1],
	]:
		stats.add_child(_battle_stat_cell(stat_pair[0], stat_pair[1]))
	column.add_child(stats)
	for line_text: String in [
		"装备：铁剑（攻击+5）· 皮甲（防御+2）",
		"技能：火球术（冷却 0）· 连击",
		"背包：生命药剂 ×2",
		"状态：力 +3（2 回合）",
		"地形：森林 防御+2 回避+15",
	]:
		column.add_child(UIFactoryScript.label(line_text, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN))
	slot.add_child(column)
	return card


## HP/MP/EXP 行：短标签 + PixelProgressBar（拉伸）+ 当前/上限文本；maxv<=0 时按空条处理。
func _battle_bar_row(node_name: String, stat_name: String, cur: float, maxv: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	row.add_child(
		UIFactoryScript.label(stat_name, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM)
	)
	var bar := PixelProgressBarScript.new() as ProgressBar
	bar.name = node_name
	bar.max_value = maxv if maxv > 0.0 else 1.0
	bar.value = cur if maxv > 0.0 else 0.0
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	row.add_child(
		UIFactoryScript.label(
			"%d/%d" % [int(cur), int(maxv)], ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN
		)
	)
	return row


## 单个属性格：居中短标签，最小宽度对齐四列网格。
func _battle_stat_cell(stat_name: String, stat_value: int) -> Label:
	var cell := UIFactoryScript.label(
		"%s %d" % [stat_name, stat_value], ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN
	)
	cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.custom_minimum_size = Vector2(56, 0)
	return cell


## 背包容器：持有者与容量计数 + PixelGrid 六格容量网格（图标 + 剩余次数，装备格主操作高亮，
## 空格灰显）+ 选中详情行 + 使用/装备操作；消耗到 0 格子空出，装备可切换。
func _build_battle_bag_card() -> PanelContainer:
	var card := _make_card("背包", "")
	card.name = "BattleBagCard"
	var slot := _card_slot(card)
	var column := VBoxContainer.new()
	column.name = "BattleBagColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)

	_battle_bag_items = _battle_bag_default_items()
	_battle_bag_selected = 0

	var header := HBoxContainer.new()
	header.name = "BattleBagHeader"
	header.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	header.add_child(
		UIFactoryScript.label("凯尔的随身背包", ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN)
	)
	_battle_bag_counter = UIFactoryScript.label("", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM)
	header.add_child(_battle_bag_counter)
	column.add_child(header)

	var grid := PixelGridScript.new() as GridContainer
	grid.name = "BattleBagGrid"
	grid.columns = BATTLE_BAG_CAPACITY
	grid.add_theme_constant_override("h_separation", ComponentThemeScript.SPACE_XS)
	grid.add_theme_constant_override("v_separation", ComponentThemeScript.SPACE_XS)
	_battle_bag_buttons.clear()
	for i: int in BATTLE_BAG_CAPACITY:
		var btn := _make_pixel_button("", 1, "")
		btn.name = "BattleBagSlot%d" % i
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_battle_bag_slot_pressed.bind(i))
		_battle_bag_buttons.append(btn)
		grid.add_child(btn)
	column.add_child(grid)

	var footer := HBoxContainer.new()
	footer.name = "BattleBagFooter"
	footer.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	_battle_bag_detail = UIFactoryScript.label("", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN)
	_battle_bag_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_battle_bag_detail)
	_battle_bag_action = _make_pixel_button("使用", 0, "")
	_battle_bag_action.name = "BattleBagAction"
	_battle_bag_action.pressed.connect(_on_battle_bag_action_pressed)
	footer.add_child(_battle_bag_action)
	column.add_child(footer)

	slot.add_child(column)
	_refresh_battle_bag()
	return card


## 背包演示初始条目（名称/效果/次数/射程取自 data/items.json 真实物品字段）。
func _battle_bag_default_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = [
		{
			"name": "生命药剂", "icon": "heart", "kind": "消耗",
			"detail": "恢复 20 HP · 射程 0-1", "uses": 2, "max_uses": 3,
		},
		{
			"name": "手里剑", "icon": "dagger", "kind": "投掷",
			"detail": "固定伤害 8 · 射程 1-3", "uses": 4, "max_uses": 4,
		},
		{
			"name": "守护之戒", "icon": "shield", "kind": "装备",
			"detail": "防御 +4", "equipped": true,
		},
		{
			"name": "炸弹", "icon": "bomb", "kind": "投掷",
			"detail": "范围伤害 10 · 射程 1-2", "uses": 1, "max_uses": 2,
		},
	]
	while items.size() < BATTLE_BAG_CAPACITY:
		items.append({})
	return items


## 背包格子文案：装备格带装备态注记，其余按剩余次数显示。
func _battle_bag_slot_text(item: Dictionary) -> String:
	if String(item.get("kind", "")) == "装备":
		return "%s%s" % [String(item.name), "（已装备）" if item.get("equipped", false) else ""]
	return "%s ×%d" % [String(item.name), int(item.uses)]


## 刷新背包全部格子、容量计数与详情/操作行；空字典条目显示为灰显空格。
func _refresh_battle_bag() -> void:
	var filled := 0
	for i: int in BATTLE_BAG_CAPACITY:
		var btn := _battle_bag_buttons[i]
		var item: Dictionary = _battle_bag_items[i]
		if item.is_empty():
			btn.set("semantic", 1)
			btn.text = "空"
			btn.icon = null
			btn.disabled = true
			continue
		filled += 1
		var equipped: bool = String(item.get("kind", "")) == "装备" and item.get("equipped", false)
		btn.set("semantic", 0 if equipped else 1)
		btn.text = _battle_bag_slot_text(item)
		btn.icon = UIThemeScript.icon(String(item.icon))
		btn.disabled = false
	_battle_bag_counter.text = "%d/%d" % [filled, BATTLE_BAG_CAPACITY]
	_refresh_battle_bag_detail()


## 当前选中格的条目；越界或空格返回空字典。
func _battle_bag_selected_item() -> Dictionary:
	if _battle_bag_selected < 0 or _battle_bag_selected >= _battle_bag_items.size():
		return {}
	return _battle_bag_items[_battle_bag_selected]


## 刷新详情行与操作按钮：空格禁用操作；装备格切换「装备/卸下」，其余为「使用」。
func _refresh_battle_bag_detail() -> void:
	var item := _battle_bag_selected_item()
	if item.is_empty():
		_battle_bag_detail.text = "选中：空格"
		_battle_bag_action.disabled = true
		_battle_bag_action.text = "使用"
		return
	var line := "选中：%s · %s · %s" % [String(item.name), String(item.kind), String(item.detail)]
	if String(item.get("kind", "")) != "装备":
		line += " · 剩 %d/%d" % [int(item.uses), int(item.max_uses)]
	_battle_bag_detail.text = line
	_battle_bag_action.disabled = false
	if String(item.get("kind", "")) == "装备":
		_battle_bag_action.text = "卸下" if item.get("equipped", false) else "装备"
	else:
		_battle_bag_action.text = "使用"


func _on_battle_bag_slot_pressed(index: int) -> void:
	_battle_bag_selected = index
	_refresh_battle_bag_detail()
	var item := _battle_bag_selected_item()
	if item.is_empty():
		return
	_status_label.text = "背包：%s" % String(item.name)
	_log_feedback("背包选中 → %s" % String(item.name))


## 背包操作：装备格切换装备态；消耗/投掷格扣 1 次，次数归零格子空出并取消选中。
func _on_battle_bag_action_pressed() -> void:
	var item := _battle_bag_selected_item()
	if item.is_empty():
		return
	if String(item.get("kind", "")) == "装备":
		var now_equipped: bool = not item.get("equipped", false)
		item["equipped"] = now_equipped
		_status_label.text = "背包：%s %s" % [String(item.name), "已装备" if now_equipped else "已卸下"]
		_log_feedback("背包 %s → %s" % [String(item.name), "装备" if now_equipped else "卸下"])
	else:
		var uses_left := int(item.uses) - 1
		if uses_left <= 0:
			var consumed := String(item.name)
			_battle_bag_items[_battle_bag_selected] = {}
			_battle_bag_selected = -1
			_status_label.text = "背包：%s 已用尽" % consumed
			_log_feedback("背包 %s 用尽 → 格子空出" % consumed)
		else:
			item["uses"] = uses_left
			_status_label.text = "背包：使用 %s" % String(item.name)
			_log_feedback("背包使用 → %s（剩 %d）" % [String(item.name), uses_left])
	_refresh_battle_bag()


## 战前整备：左栏编队勾选（联动上场计数）/ 中栏五个 Tab / 右栏选中单位详情。
func _build_battle_prep_card() -> PanelContainer:
	var card := _make_card("战前整备", "")
	card.name = "BattlePrepCard"
	var slot := _card_slot(card)
	var row := HBoxContainer.new()
	row.name = "BattlePrepRow"
	row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)

	var roster := VBoxContainer.new()
	roster.name = "BattlePrepRoster"
	roster.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	_battle_deploy_checks.clear()
	var names := ["凯尔", "莉雅", "希尔德", "艾尔文", "瑟兰"]
	for i: int in names.size():
		var check := PixelCheckButtonScript.new() as CheckButton
		check.text = names[i]
		check.set_pressed_no_signal(i < 3)
		check.toggled.connect(_on_battle_deploy_toggled)
		_battle_deploy_checks.append(check)
		roster.add_child(check)
	_battle_deploy_counter = UIFactoryScript.label("上场 3/6", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN)
	roster.add_child(_battle_deploy_counter)
	row.add_child(roster)

	var prep_tabs := PixelTabsScript.new() as TabContainer
	prep_tabs.name = "BattlePrepTabs"
	prep_tabs.custom_minimum_size = Vector2(150, 0)
	for tab_title: String in ["编队", "装备", "技能", "转职", "物品"]:
		var tab_page: VBoxContainer = prep_tabs.call("add_pixel_tab", tab_title) as VBoxContainer
		tab_page.add_child(
			UIFactoryScript.label("%s · 凯尔" % tab_title, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM)
		)
	row.add_child(prep_tabs)

	var detail := VBoxContainer.new()
	detail.name = "BattlePrepDetail"
	detail.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	for line_text: String in ["选中：凯尔 [剑士]", "Lv 5 · HP 22/24", "MP 0/0 · 移动 5", "装备：铁剑"]:
		detail.add_child(UIFactoryScript.label(line_text, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN))
	row.add_child(detail)
	slot.add_child(row)
	return card


## 胜利结算：标题大字 + 三条经验（进度条 + 升级注记）+ 掉落/存活/下一关 + 三个去向按钮。
func _build_battle_victory_card() -> PanelContainer:
	var card := _make_card("胜利结算", "")
	card.name = "BattleVictoryCard"
	var slot := _card_slot(card)
	var column := VBoxContainer.new()
	column.name = "BattleVictoryColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)
	var title := UIFactoryScript.outline_label("胜 利", ComponentThemeScript.FONT_TITLE, UIThemeScript.TOAST_COLOR, 4)
	title.name = "BattleVictoryTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(_battle_exp_row("BattleVictoryExpKai", "凯尔", 48, "Lv5→6！（力+1 速+1）", 48))
	column.add_child(_battle_exp_row("BattleVictoryExpLia", "莉雅", 32, "Lv4→5", 32))
	column.add_child(_battle_exp_row("BattleVictoryExpHild", "希尔德", 30, "经验 +30", 30))
	column.add_child(
		UIFactoryScript.label("掉落：铁枪 ×1 · 源脉药剂 ×1 · 100 金币", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN)
	)
	column.add_child(
		UIFactoryScript.label("队员：✓ 全员存活", ComponentThemeScript.FONT_CAPTION, UIThemeScript.ACCENT)
	)
	column.add_child(
		UIFactoryScript.label("下一关：第 2 章 · 雾岭哨站", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM)
	)
	var buttons := HBoxContainer.new()
	buttons.name = "BattleVictoryButtons"
	buttons.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	var primary := _make_pixel_button("继续剧情", 0, "")
	primary.name = "BattleVictoryPrimary"
	buttons.add_child(primary)
	var to_prep := _make_pixel_button("回整备", 1, "")
	to_prep.name = "BattleVictoryToPrep"
	buttons.add_child(to_prep)
	var save := _make_pixel_button("存档", 1, "")
	save.name = "BattleVictorySave"
	buttons.add_child(save)
	for child: Button in buttons.get_children():
		child.pressed.connect(_on_battle_result_pressed.bind(child.text))
	column.add_child(buttons)
	slot.add_child(column)
	return card


## 单条经验行：名字 + PixelProgressBar + 增量与升级注记。
func _battle_exp_row(
	node_name: String, who: String, gain: int, note: String, fill: float
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	var name_label := UIFactoryScript.label(who, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN)
	name_label.custom_minimum_size = Vector2(56, 0)
	row.add_child(name_label)
	var bar := PixelProgressBarScript.new() as ProgressBar
	bar.name = node_name
	bar.max_value = 100.0
	bar.value = fill
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	row.add_child(
		UIFactoryScript.label("+%d %s" % [gain, note], ComponentThemeScript.FONT_CAPTION, UIThemeScript.ACCENT)
	)
	return row


## 失败：血红大字 + 败因 + 三个去向按钮 + 自动存档提示。
func _build_battle_defeat_card() -> PanelContainer:
	var card := _make_card("失败", "")
	card.name = "BattleDefeatCard"
	var slot := _card_slot(card)
	var column := VBoxContainer.new()
	column.name = "BattleDefeatColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)
	var title := UIFactoryScript.outline_label("全军覆没", ComponentThemeScript.FONT_TITLE, UIThemeScript.ERROR, 4)
	title.name = "BattleDefeatTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(
		UIFactoryScript.label("主角凯尔已倒下，战局无可挽回。", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM)
	)
	var buttons := HBoxContainer.new()
	buttons.name = "BattleDefeatButtons"
	buttons.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	var retry := _make_pixel_button("重试本关", 0, "")
	retry.name = "BattleDefeatRetry"
	buttons.add_child(retry)
	var load := _make_pixel_button("读档", 1, "")
	load.name = "BattleDefeatLoad"
	buttons.add_child(load)
	var to_title := _make_pixel_button("回主菜单", 1, "")
	to_title.name = "BattleDefeatToTitle"
	buttons.add_child(to_title)
	for child: Button in buttons.get_children():
		child.pressed.connect(_on_battle_result_pressed.bind(child.text))
	column.add_child(buttons)
	column.add_child(
		UIFactoryScript.label("💡 上次自动存档：回合 #4（2 分钟前）", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TOAST_COLOR)
	)
	slot.add_child(column)
	return card


## 设置：三个下拉 + 托管开关 + 三条音量滑块。
func _build_battle_settings_card() -> PanelContainer:
	var card := _make_card("设置", "")
	card.name = "BattleSettingsCard"
	var slot := _card_slot(card)
	var column := VBoxContainer.new()
	column.name = "BattleSettingsColumn"
	column.add_theme_constant_override("separation", ComponentThemeScript.SPACE_SM)

	_battle_size_option = _battle_option_row(column, "BattleSettingsSize", "文字大小", ["标准", "大", "特大"])
	_battle_colorblind_option = _battle_option_row(
		column, "BattleSettingsColorblind", "色盲模式", ["关闭", "红绿", "蓝黄"]
	)
	_battle_autosave_option = _battle_option_row(column, "BattleSettingsAutosave", "自动存档", ["每回合", "每章", "关闭"])

	var auto_row := HBoxContainer.new()
	auto_row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	auto_row.add_child(UIFactoryScript.label("托管默认", ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_row.add_child(spacer)
	_battle_auto_battle_switch = PixelCheckButtonScript.new() as CheckButton
	_battle_auto_battle_switch.name = "BattleSettingsAutoBattle"
	_battle_auto_battle_switch.toggled.connect(_on_battle_auto_battle_toggled)
	auto_row.add_child(_battle_auto_battle_switch)
	column.add_child(auto_row)

	_battle_master_slider = _battle_volume_row(column, "BattleSettingsMaster", "主音量", 80.0)
	_battle_music_slider = _battle_volume_row(column, "BattleSettingsMusic", "音乐", 60.0)
	_battle_sfx_slider = _battle_volume_row(column, "BattleSettingsSfx", "音效", 70.0)

	slot.add_child(column)
	return card


## 设置页一行下拉：标签 + 弹簧 + PixelOptionButton，选择写入反馈。
func _battle_option_row(
	parent: Container, node_name: String, row_label: String, items: Array
) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	row.add_child(UIFactoryScript.label(row_label, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var option := PixelOptionButtonScript.new() as OptionButton
	option.name = node_name
	for item_text: String in items:
		option.add_item(item_text)
	option.item_selected.connect(_on_battle_option_selected.bind(row_label))
	row.add_child(option)
	parent.add_child(row)
	return option


## 设置页一行滑块：标签 + PixelSlider（拉伸），改动写入状态行。
func _battle_volume_row(parent: Container, node_name: String, bus_label: String, initial: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ComponentThemeScript.SPACE_XS)
	row.add_child(UIFactoryScript.label(bus_label, ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_MAIN))
	var slider := PixelSliderScript.new() as HSlider
	slider.name = node_name
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_battle_volume_changed.bind(bus_label))
	row.add_child(slider)
	parent.add_child(row)
	return slider


func _on_battle_menu_pressed(which: String) -> void:
	_status_label.text = "战棋菜单：%s" % which
	_log_feedback("战棋菜单 → %s" % which)


func _on_battle_result_pressed(which: String) -> void:
	_status_label.text = "结算：%s" % which
	_log_feedback("结算 → %s" % which)


## 编队勾选联动「上场 n/6」计数。
func _on_battle_deploy_toggled(_toggled_on: bool) -> void:
	var count := 0
	for check: CheckButton in _battle_deploy_checks:
		if check.button_pressed:
			count += 1
	_battle_deploy_counter.text = "上场 %d/6" % count
	_status_label.text = "编队：上场 %d/6" % count


func _on_battle_option_selected(which: String, index: int) -> void:
	_status_label.text = "设置：%s → 第 %d 项" % [which, index + 1]
	_log_feedback("设置 %s → 第 %d 项" % [which, index + 1])


func _on_battle_auto_battle_toggled(toggled_on: bool) -> void:
	_status_label.text = "托管默认：%s" % ("开" if toggled_on else "关")
	_log_feedback("托管默认 → %s" % ("开" if toggled_on else "关"))


func _on_battle_volume_changed(bus_name: String, value: float) -> void:
	_status_label.text = "%s：%d" % [bus_name, roundi(value)]


## 统一开关所有演示用 PixelButton 的悬停/点击音效（按脚本识别，不动其他按钮）。
func _apply_sfx_enabled(enabled: bool) -> void:
	for btn: Button in find_children("*", "Button", true, false):
		if btn.get_script() != PixelButtonScript:
			continue
		btn.set("hover_sfx_enabled", enabled)
		btn.set("click_sfx_enabled", enabled)


func _on_sfx_toggled(enabled: bool) -> void:
	_apply_sfx_enabled(enabled)
	_status_label.text = "音效：%s" % ("开" if enabled else "关")
	_log_feedback("音效 → %s" % ("开" if enabled else "关"))


## 重置所有演示状态：清空反馈、复位控件与联动值，并把焦点还给第一个按钮。
func _reset_demo() -> void:
	_feedback_lines.clear()
	_feedback_log.text = ""
	_demo_edit.text = ""
	_demo_option.select(0)
	_demo_switch.set_pressed_no_signal(false)
	_demo_sfx_switch.set_pressed_no_signal(true)
	_apply_sfx_enabled(true)
	_danger_button.disabled = false
	_toggle_button.set_pressed_no_signal(false)
	_demo_slider.set_value_no_signal(0.0)
	_demo_spin.set_value_no_signal(0.0)
	_demo_progress.value = 0.0
	_preview_label.text = "值：—"
	_demo_text_area.text = ""
	_demo_popup.hide()
	_demo_audio.call("stop_sound")
	_demo_video.call("stop_video")
	if _gc() != null:
		_gc().call("set_arrow_style", _gc().get("DEFAULT_ARROW_STYLE"))
		_gc().call("restore_cursor")
		for style_name: String in _arrow_style_buttons:
			(_arrow_style_buttons[style_name] as Button).set_pressed_no_signal(
				style_name == _gc().call("get_arrow_style")
			)
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
	_battle_master_slider.set_value_no_signal(80.0)
	_battle_music_slider.set_value_no_signal(60.0)
	_battle_sfx_slider.set_value_no_signal(70.0)
	_battle_size_option.select(0)
	_battle_colorblind_option.select(0)
	_battle_autosave_option.select(0)
	_battle_auto_battle_switch.set_pressed_no_signal(false)
	for i: int in _battle_deploy_checks.size():
		_battle_deploy_checks[i].set_pressed_no_signal(i < 3)
	_battle_deploy_counter.text = "上场 3/6"
	_battle_bag_items = _battle_bag_default_items()
	_battle_bag_selected = 0
	_refresh_battle_bag()
	_tabs.current_tab = 0
	_status_label.text = "已重置"
	_log_feedback("重置")
	_primary_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
