## tests/ui_components_contract.gd — ui/ 组件库与交互画廊的 headless 契约
## 跑法：godot --headless --path . --script res://tests/ui_components_contract.gd
##
## 覆盖：
## - ComponentTheme：按钮语义/页签/面板/输入类六变体基类与样式键、实例隔离；
## - PixelButton：默认语义、semantic/icon_size 刷新、原生 toggle/disabled、重复进树、焦点；
##   音效：默认资源/开关/音量/总线、悬停与点击各只播一次、关闭与 disabled 静默、
##   资源/音量可替换、无效总线回退、重复进树不重复节点/连接、源码级 @tool 静默；
## - PixelLineEdit / PixelOptionButton / PixelCheckButton / PixelSlider / PixelSpinBox /
##   PixelProgressBar：变体主题、原生信号/范围/禁用、实例隔离、重复进树；
## - PixelTabs：与 UIFactory.add_tab 结构兼容、页签信号、重复进树；
## - PixelPanel：头部可见性、标题/说明/图标刷新、内容槽、实例隔离；
## - 画廊：4 个短页签、按钮/页签/输入/下拉/开关/滑块/数值联动/重置、演示页无说明文本、
##   1024x640 / 1280x800 / 1920x1080 铺满与有效布局、焦点回归。
##
## 只做组件级断言，不启动游戏主场景、不依赖世界/战斗状态。
extends SceneTree

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const PixelButtonScript = preload("res://ui/components/pixel_button.gd")
const PixelTabsScript = preload("res://ui/components/pixel_tabs.gd")
const PixelPanelScene = preload("res://ui/components/pixel_panel.tscn")
const GalleryScene = preload("res://scenes/UIComponentGallery.tscn")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
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

## 画廊页签标题的期望值（与脚本内 DEMO_TAB_TITLES 保持一致，改名时必须同步）。
const EXPECTED_TAB_TITLES: Array[String] = ["按钮", "卡片", "输入", "数值", "媒体", "菜单"]

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_component_theme()
	_test_pixel_button()
	_test_pixel_button_sfx()
	_test_pixel_tabs()
	_test_pixel_panel()
	_test_pixel_controls()
	await _test_pixel_media_controls()
	await _test_gallery()
	_finish()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("[FAIL] " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("UI_COMPONENTS_CONTRACT_OK checks=%d" % _checks)
		quit(0)
	else:
		printerr("UI_COMPONENTS_CONTRACT_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		for failed_message: String in _failures:
			printerr("  - " + failed_message)
		quit(1)


# ---------------------------------------------------------------- ComponentTheme

func _test_component_theme() -> void:
	var theme_a: Theme = ComponentThemeScript.create()
	var theme_b: Theme = ComponentThemeScript.create()
	_expect(theme_a != null and theme_b != null, "ComponentTheme.create() 返回 Theme")
	_expect(theme_a != theme_b, "ComponentTheme.create() 每次返回独立实例")

	_expect(theme_a.get_type_variation_base(ComponentThemeScript.BUTTON_PRIMARY) == &"Button", "主操作变体基类为 Button")
	_expect(theme_a.get_type_variation_base(ComponentThemeScript.BUTTON_SECONDARY) == &"Button", "次操作变体基类为 Button")
	_expect(theme_a.get_type_variation_base(ComponentThemeScript.BUTTON_DANGER) == &"Button", "危险变体基类为 Button")
	_expect(theme_a.get_type_variation_base(ComponentThemeScript.TABS_VARIATION) == &"TabContainer", "页签变体基类为 TabContainer")
	_expect(theme_a.get_type_variation_base(ComponentThemeScript.PANEL_VARIATION) == &"PanelContainer", "面板变体基类为 PanelContainer")

	for variation: StringName in [
		ComponentThemeScript.BUTTON_PRIMARY,
		ComponentThemeScript.BUTTON_SECONDARY,
		ComponentThemeScript.BUTTON_DANGER,
	]:
		var label := String(variation)
		_expect(theme_a.has_stylebox("normal", variation), label + " 有 normal 样式")
		_expect(theme_a.has_stylebox("hover", variation), label + " 有 hover 样式")
		_expect(theme_a.has_stylebox("pressed", variation), label + " 有 pressed 样式")
		_expect(theme_a.has_stylebox("focus", variation), label + " 有 focus 样式")
		_expect(theme_a.has_stylebox("disabled", variation), label + " 有 disabled 样式")
		_expect(theme_a.get_constant("icon_max_width", variation) == 18, label + " 图标最大宽度默认 18")
		_expect(theme_a.get_font_size("font_size", variation) == 12, label + " 字号 12")

	_expect(theme_a.has_stylebox("panel", ComponentThemeScript.TABS_VARIATION), "页签变体有 panel 样式")
	_expect(theme_a.has_stylebox("panel", ComponentThemeScript.PANEL_VARIATION), "面板变体有 panel 样式")
	_expect(theme_a.get_font_size("font_size", ComponentThemeScript.TABS_VARIATION) == 13, "页签字号 13")

	# 语义必须真的不同：主操作 vs 危险按钮边框/字体色不同。
	_expect(
		theme_a.get_color("font_color", ComponentThemeScript.BUTTON_PRIMARY)
		!= theme_a.get_color("font_color", ComponentThemeScript.BUTTON_DANGER),
		"主操作与危险按钮字体色不同"
	)
	_expect(
		theme_a.get_stylebox("normal", ComponentThemeScript.BUTTON_DANGER) is StyleBoxFlat,
		"危险按钮 normal 为 StyleBoxFlat"
	)

	# 实例隔离：改 A 不影响 B。
	var before: Color = theme_b.get_color("font_color", ComponentThemeScript.BUTTON_PRIMARY)
	theme_a.set_color("font_color", ComponentThemeScript.BUTTON_PRIMARY, Color.MAGENTA)
	_expect(
		theme_b.get_color("font_color", ComponentThemeScript.BUTTON_PRIMARY) == before,
		"主题实例之间样式互不污染"
	)

	# 语义 → 变体映射。
	_expect(
		ComponentThemeScript.variation_for_semantic(ComponentThemeScript.ButtonSemantic.PRIMARY)
		== ComponentThemeScript.BUTTON_PRIMARY,
		"PRIMARY 映射主操作变体"
	)
	_expect(
		ComponentThemeScript.variation_for_semantic(ComponentThemeScript.ButtonSemantic.SECONDARY)
		== ComponentThemeScript.BUTTON_SECONDARY,
		"SECONDARY 映射次操作变体"
	)
	_expect(
		ComponentThemeScript.variation_for_semantic(ComponentThemeScript.ButtonSemantic.DANGER)
		== ComponentThemeScript.BUTTON_DANGER,
		"DANGER 映射危险变体"
	)


# ---------------------------------------------------------------- PixelButton

func _test_pixel_button() -> void:
	var button: Button = PixelButtonScript.new()
	_expect(button is Button, "PixelButton 继承 Button")
	_expect(button.theme != null, "PixelButton 默认创建主题")
	_expect(button.theme_type_variation == ComponentThemeScript.BUTTON_PRIMARY, "默认使用主操作变体")
	_expect(int(button.get("semantic")) == ComponentThemeScript.ButtonSemantic.PRIMARY, "默认 semantic = 0")

	button.set("semantic", ComponentThemeScript.ButtonSemantic.DANGER)
	_expect(button.theme_type_variation == ComponentThemeScript.BUTTON_DANGER, "semantic=2 切换危险变体")
	button.set("semantic", ComponentThemeScript.ButtonSemantic.SECONDARY)
	_expect(button.theme_type_variation == ComponentThemeScript.BUTTON_SECONDARY, "semantic=1 切换次操作变体")
	button.set("semantic", 99)
	_expect(int(button.get("semantic")) == ComponentThemeScript.ButtonSemantic.DANGER, "semantic 越界钳制到 2")

	button.set("icon_size", 32)
	_expect(button.get_theme_constant("icon_max_width") == 32, "icon_size=32 写入图标最大宽度")
	button.set("icon_size", 0)
	_expect(button.get_theme_constant("icon_max_width") == 18, "icon_size=0 回落主题默认 18")

	var theme_before: Theme = button.theme
	var other: Button = PixelButtonScript.new()
	_expect(other.theme != button.theme, "两个 PixelButton 不共享主题实例")
	other.set("semantic", ComponentThemeScript.ButtonSemantic.SECONDARY)
	_expect(button.theme_type_variation == ComponentThemeScript.BUTTON_DANGER, "改另一实例不影响本实例变体")

	# 原生 toggle 行为保留。
	button.toggle_mode = true
	var toggle_hits: Array[int] = [0]
	button.toggled.connect(func(_pressed: bool) -> void: toggle_hits[0] += 1)
	button.button_pressed = true
	_expect(toggle_hits[0] == 1, "toggle_mode 原生 toggled 触发一次")
	button.button_pressed = false
	_expect(toggle_hits[0] == 2, "toggle 再次切换计数递增")

	# 禁用态样式来自主题。
	button.disabled = true
	_expect(button.get_theme_stylebox("disabled") != null, "禁用态有 disabled 样式")
	button.disabled = false

	# 重复进树：不新增子节点、不重建主题、不重复接信号。
	root.add_child(button)
	_expect(button.is_inside_tree(), "PixelButton 可加入场景树")
	root.remove_child(button)
	root.add_child(button)
	_expect(
		button.get_child_count() == 2
		and button.get_node_or_null("HoverSfx") != null
		and button.get_node_or_null("ClickSfx") != null,
		"重复进树不新增子节点（仅两个常驻音效播放器）"
	)
	_expect(button.theme == theme_before, "重复进树不重建主题实例")
	button.button_pressed = true
	_expect(toggle_hits[0] == 3, "重复进树不重复连接 toggled 信号")
	root.remove_child(button)
	button.queue_free()

	# 焦点：可成为焦点所有者。
	var focus_button: Button = PixelButtonScript.new()
	root.add_child(focus_button)
	focus_button.grab_focus()
	_expect(root.gui_get_focus_owner() == focus_button, "PixelButton 可获得焦点")
	root.remove_child(focus_button)
	focus_button.queue_free()


# ---------------------------------------------------------------- PixelButton 音效

func _test_pixel_button_sfx() -> void:
	var button: Button = PixelButtonScript.new()
	_expect(button.get("hover_sfx") != null, "默认悬停音效资源非空")
	_expect(button.get("click_sfx") != null, "默认点击音效资源非空")
	_expect(bool(button.get("hover_sfx_enabled")), "默认悬停音效开启")
	_expect(bool(button.get("click_sfx_enabled")), "默认点击音效开启")
	_expect(is_equal_approx(float(button.get("hover_volume_db")), -8.0), "默认悬停音量 -8 dB")
	_expect(is_equal_approx(float(button.get("click_volume_db")), -3.0), "默认点击音量 -3 dB")
	_expect(StringName(button.get("sfx_bus")) == &"Master", "默认输出 Master 总线")

	var hover_player: AudioStreamPlayer = button.get_node_or_null("HoverSfx") as AudioStreamPlayer
	var click_player: AudioStreamPlayer = button.get_node_or_null("ClickSfx") as AudioStreamPlayer
	_expect(hover_player != null and click_player != null, "两个音效播放器节点常驻")
	if hover_player == null or click_player == null:
		button.queue_free()
		return
	_expect(hover_player.bus == &"Master" and click_player.bus == &"Master", "播放器输出 Master")
	_expect(is_equal_approx(hover_player.volume_db, -8.0), "悬停音量写入播放器")
	_expect(is_equal_approx(click_player.volume_db, -3.0), "点击音量写入播放器")
	_expect(hover_player.stream == button.get("hover_sfx"), "悬停资源写入播放器")
	_expect(hover_player.max_polyphony >= 2, "播放器限制复音数，避免叠成噪声墙")

	# AudioStreamPlayer 只有在场景树内才能播放；先把按钮入树再验证触发。
	root.add_child(button)
	_expect(button.is_inside_tree(), "音效测试按钮已加入场景树")

	# 原生 mouse_entered 每次进入只发一次；这里手动 emit 两次验证每次只播一次。
	button.emit_signal("mouse_entered")
	_expect(int(button.get("hover_play_count")) == 1, "鼠标进入边界播放一次悬停音效")
	button.emit_signal("mouse_entered")
	_expect(int(button.get("hover_play_count")) == 2, "每次进入边界只播一次")
	button.emit_signal("pressed")
	_expect(int(button.get("click_play_count")) == 1, "pressed 播放一次点击音效")

	button.set("hover_sfx_enabled", false)
	button.emit_signal("mouse_entered")
	_expect(int(button.get("hover_play_count")) == 2, "关闭悬停音效后不播放")
	button.set("hover_sfx_enabled", true)

	button.set("click_sfx_enabled", false)
	button.emit_signal("pressed")
	_expect(int(button.get("click_play_count")) == 1, "关闭点击音效后不播放")
	button.set("click_sfx_enabled", true)

	button.disabled = true
	button.emit_signal("mouse_entered")
	button.emit_signal("pressed")
	_expect(
		int(button.get("hover_play_count")) == 2 and int(button.get("click_play_count")) == 1,
		"disabled 时悬停与点击音效都静默"
	)
	button.disabled = false

	var custom_stream := AudioStreamWAV.new()
	button.set("hover_sfx", custom_stream)
	_expect(hover_player.stream == custom_stream, "可替换悬停 AudioStream")
	button.set("hover_volume_db", -20.0)
	_expect(is_equal_approx(hover_player.volume_db, -20.0), "可调节悬停音量")
	button.set("sfx_bus", &"NotARegisteredBus")
	_expect(
		hover_player.bus == &"Master" and click_player.bus == &"Master",
		"无效总线名安全回退 Master"
	)

	# 重复进树：播放器节点与信号连接都幂等。
	var theme_before: Theme = button.theme
	var children_before: int = button.get_child_count()
	root.remove_child(button)
	root.add_child(button)
	_expect(button.get_child_count() == children_before, "重复进树不新增音效播放器")
	_expect(button.theme == theme_before, "重复进树不重建主题")
	button.emit_signal("mouse_entered")
	_expect(int(button.get("hover_play_count")) == 3, "重复进树不重复连接悬停信号")
	button.emit_signal("pressed")
	_expect(int(button.get("click_play_count")) == 2, "重复进树不重复连接点击信号")
	root.remove_child(button)

	# --script 模式进不了编辑器：@tool 静默只能做源码级断言。
	_check_source(
		"res://ui/components/pixel_button.gd",
		["Engine.is_editor_hint()", "mouse_entered.connect", "pressed.connect"],
		[]
	)

	button.queue_free()


## 读源码做静态断言（用于 headless 无法直接覆盖的编辑器分支）。
func _check_source(path: String, must_have: Array[String], must_not_have: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	_expect(file != null, "源码可读：" + path)
	if file == null:
		return
	var source := file.get_as_text()
	file.close()
	for needle: String in must_have:
		_expect(source.contains(needle), "源码包含「%s」：%s" % [needle, path])
	for needle: String in must_not_have:
		_expect(not source.contains(needle), "源码不包含「%s」：%s" % [needle, path])


# ---------------------------------------------------------------- 六类输入/数值组件

func _test_pixel_controls() -> void:
	# 六类薄组件：只负责集中主题变体，原生范围/信号/禁用全部保留。
	var line_edit: LineEdit = PixelLineEditScript.new() as LineEdit
	var option: OptionButton = PixelOptionButtonScript.new() as OptionButton
	var check: CheckButton = PixelCheckButtonScript.new() as CheckButton
	var slider: HSlider = PixelSliderScript.new() as HSlider
	var spin: SpinBox = PixelSpinBoxScript.new() as SpinBox
	var progress: ProgressBar = PixelProgressBarScript.new() as ProgressBar
	_expect(line_edit is LineEdit, "PixelLineEdit 继承 LineEdit")
	_expect(option is OptionButton, "PixelOptionButton 继承 OptionButton")
	_expect(check is CheckButton, "PixelCheckButton 继承 CheckButton")
	_expect(slider is HSlider, "PixelSlider 继承 HSlider")
	_expect(spin is SpinBox, "PixelSpinBox 继承 SpinBox")
	_expect(progress is ProgressBar, "PixelProgressBar 继承 ProgressBar")
	if line_edit == null or option == null or check == null or slider == null or spin == null or progress == null:
		return

	# 变体与主题：每个组件实例化即带集中主题，多实例互不共享。
	_expect(line_edit.theme != null and line_edit.theme_type_variation == ComponentThemeScript.LINE_EDIT_VARIATION, "输入框使用 PixelLineEdit 变体")
	_expect(option.theme_type_variation == ComponentThemeScript.OPTION_BUTTON_VARIATION, "下拉使用 PixelOptionButton 变体")
	_expect(check.theme_type_variation == ComponentThemeScript.CHECK_BUTTON_VARIATION, "开关使用 PixelCheckButton 变体")
	_expect(slider.theme_type_variation == ComponentThemeScript.SLIDER_VARIATION, "滑块使用 PixelSlider 变体")
	_expect(spin.theme_type_variation == ComponentThemeScript.SPIN_BOX_VARIATION, "数值框使用 PixelSpinBox 变体")
	_expect(progress.theme_type_variation == ComponentThemeScript.PROGRESS_BAR_VARIATION, "进度条使用 PixelProgressBar 变体")
	_expect(line_edit.theme != option.theme, "不同组件实例不共享 Theme")

	var other_line_edit: LineEdit = PixelLineEditScript.new() as LineEdit
	_expect(other_line_edit.theme != line_edit.theme, "两个输入框实例主题互相独立")
	var before: Color = other_line_edit.theme.get_color("font_color", ComponentThemeScript.LINE_EDIT_VARIATION)
	line_edit.theme.set_color("font_color", ComponentThemeScript.LINE_EDIT_VARIATION, Color.MAGENTA)
	_expect(other_line_edit.theme.get_color("font_color", ComponentThemeScript.LINE_EDIT_VARIATION) == before, "输入框主题实例互不污染")

	# 原生行为：范围、步进、禁用、信号都还是 Godot 原生实现。
	# Range 的 value_changed 需要节点在树内才稳定投递，先挂到 root 再测。
	root.add_child(slider)
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	var slider_values: Array[float] = []
	slider.value_changed.connect(func(v: float) -> void: slider_values.append(v))
	slider.value = 64.0
	_expect(int(slider.value) == 64 and slider_values.size() == 1 and int(slider_values[0]) == 64, "滑块保留原生 value_changed 与范围")
	slider.editable = false
	_expect(not slider.editable, "滑块可禁用编辑")

	spin.min_value = 0.0
	spin.max_value = 100.0
	spin.step = 1.0
	spin.value = 25.0
	_expect(int(spin.value) == 25, "数值框保留原生范围与步进")
	spin.editable = false
	_expect(not spin.editable, "数值框可禁用编辑")

	check.button_pressed = true
	_expect(check.button_pressed, "开关保留原生 button_pressed")
	check.disabled = true
	_expect(check.disabled, "开关可禁用")

	line_edit.text = "abc"
	_expect(line_edit.text == "abc", "输入框保留原生文本属性")
	line_edit.editable = false
	_expect(not line_edit.editable, "输入框可禁用编辑")

	option.add_item("甲")
	option.add_item("乙")
	option.select(1)
	_expect(option.selected == 1 and option.get_item_text(1) == "乙", "下拉保留原生选项与选中")

	# 重复进树：不重复挂节点，主题实例保持可用。
	_expect(line_edit.get_child_count() == 0, "输入框无额外子节点")
	root.add_child(line_edit)
	root.remove_child(line_edit)
	root.add_child(line_edit)
	_expect(line_edit.theme != null, "输入框重复进树后仍带主题")
	root.remove_child(line_edit)
	line_edit.free()
	option.free()
	check.free()
	slider.free()
	spin.free()
	progress.free()
	other_line_edit.free()


# ---------------------------------------------------------------- 媒体与菜单组件

func _test_pixel_media_controls() -> void:
	var image: PanelContainer = PixelImageScript.new() as PanelContainer
	var icon: TextureRect = PixelIconScript.new() as TextureRect
	var text_area: TextEdit = PixelTextAreaScript.new() as TextEdit
	var dropdown: MenuButton = PixelDropdownScript.new() as MenuButton
	var popup: PopupPanel = PixelPopupScript.new() as PopupPanel
	var audio: PanelContainer = PixelAudioPlayerScript.new() as PanelContainer
	var video: PanelContainer = PixelVideoPlayerScript.new() as PanelContainer
	_expect(image is PanelContainer, "PixelImage 继承 PanelContainer")
	_expect(icon is TextureRect, "PixelIcon 继承 TextureRect")
	_expect(text_area is TextEdit, "PixelTextArea 继承 TextEdit")
	_expect(dropdown is MenuButton, "PixelDropdown 继承 MenuButton")
	_expect(popup is PopupPanel, "PixelPopup 继承 PopupPanel")
	_expect(audio is PanelContainer, "PixelAudioPlayer 是组合 PanelContainer")
	_expect(video is PanelContainer, "PixelVideoPlayer 是组合 PanelContainer")
	if image == null or icon == null or text_area == null or dropdown == null or popup == null:
		return
	if audio == null or video == null:
		return

	# 变体与实例隔离：每个组件实例化即带集中主题。
	_expect(image.theme != null and image.theme_type_variation == ComponentThemeScript.IMAGE_VARIATION, "图片容器使用 PixelImage 变体")
	_expect(text_area.theme != null and text_area.theme_type_variation == ComponentThemeScript.TEXT_AREA_VARIATION, "多行文本使用 PixelTextArea 变体")
	_expect(dropdown.theme_type_variation == ComponentThemeScript.DROPDOWN_VARIATION, "动作菜单使用 PixelDropdown 变体")
	_expect(popup.theme_type_variation == ComponentThemeScript.POPUP_VARIATION, "弹层使用 PixelPopup 变体")
	_expect(audio.theme_type_variation == ComponentThemeScript.PANEL_VARIATION, "音频容器复用卡片面变体")
	_expect(video.theme_type_variation == ComponentThemeScript.PANEL_VARIATION, "视频容器复用卡片面变体")
	_expect(image.theme != text_area.theme, "媒体组件之间不共享 Theme 实例")

	# PixelImage：纹理绑定、尺寸、适配方式、重复进树幂等。
	var image_texture: Texture2D = UIThemeScript.icon("star")
	image.set("texture", image_texture)
	image.set("image_size", Vector2i(160, 90))
	var image_child: TextureRect = image.get_node_or_null(
		NodePath(String(PixelImageScript.IMAGE_NODE_NAME))
	) as TextureRect
	_expect(image_child != null, "图片容器内部 Image 节点常驻")
	if image_child != null:
		_expect(image_child.texture == image_texture, "纹理绑定到内部 TextureRect")
		_expect(image_child.custom_minimum_size == Vector2(160, 90), "图片最小尺寸随导出值")
	image.set("stretch_mode", TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	if image_child != null:
		_expect(image_child.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED, "图片支持等比裁切")
	var image_children: int = image.get_child_count()
	root.add_child(image)
	root.remove_child(image)
	root.add_child(image)
	_expect(image.get_child_count() == image_children, "图片容器重复进树不增节点")
	root.remove_child(image)

	# PixelIcon：尺寸钳制与着色。
	icon.set("icon_size", 48)
	_expect(icon.custom_minimum_size == Vector2(48, 48), "图标尺寸写入最小尺寸")
	icon.set("icon_color", Color.RED)
	_expect(icon.modulate == Color.RED, "图标着色写入 modulate")
	icon.set("icon_size", 999)
	_expect(icon.custom_minimum_size == Vector2(128, 128), "图标尺寸上限钳制到 128")
	icon.free()

	# PixelTextArea：原生占位、多行、只读/可编辑。
	text_area.placeholder = "多行"
	_expect(text_area.placeholder_text == "多行", "多行文本占位符转发")
	root.add_child(text_area)
	text_area.text = "第一行\n第二行"
	_expect(text_area.get_line_count() == 2, "多行文本保留原生换行")
	text_area.editable = false
	_expect(not text_area.editable, "多行文本保留可编辑开关")
	_expect(text_area.has_theme_stylebox("read_only"), "多行文本主题含只读样式")
	root.remove_child(text_area)
	text_area.free()

	# PixelDropdown：条目、动作信号。
	dropdown.set("items", PackedStringArray(["打开", "复制"]))
	_expect(int(dropdown.call("get_choice_count")) == 2, "动作菜单按 items 建条目")
	_expect(dropdown.get_popup().get_item_text(0) == "打开", "动作菜单条目文本正确")
	dropdown.call("add_choice", "删除")
	_expect(int(dropdown.call("get_choice_count")) == 3, "add_choice 追加条目")
	var picked: Array[int] = []
	dropdown.get_popup().id_pressed.connect(func(id: int) -> void: picked.append(id))
	dropdown.get_popup().id_pressed.emit(1)
	_expect(picked == [1], "动作菜单保留原生 id_pressed 信号")
	dropdown.free()

	# PixelPopup：真实打开/关闭与焦点恢复。
	var opener := Button.new()
	opener.text = "打开"
	root.add_child(opener)
	opener.grab_focus()
	_expect(root.gui_get_focus_owner() == opener, "弹层 opener 获得焦点")
	popup.add_child(Label.new())
	root.add_child(popup)
	popup.call("open_for", opener)
	_expect(popup.visible, "open_for 后弹层可见")
	popup.hide()
	_expect(not popup.visible, "hide 后弹层关闭")
	_expect(root.gui_get_focus_owner() == opener, "弹层关闭后焦点恢复到 opener")
	root.remove_child(popup)
	root.add_child(popup)
	popup.call("open_for", opener)
	popup.hide()
	_expect(root.gui_get_focus_owner() == opener, "重复进树后关闭仍恢复焦点")
	root.remove_child(popup)
	popup.queue_free()
	root.remove_child(opener)
	opener.queue_free()

	# PixelAudioPlayer：真实播放/暂停/停止、音量、空流安全、重复进树幂等。
	audio.set("stream", load("res://assets/audio/sfx/ui/sfx_ui_confirm.mp3"))
	var audio_player: AudioStreamPlayer = audio.get_node_or_null("Player") as AudioStreamPlayer
	_expect(audio_player != null, "音频容器含 Player 节点")
	if audio_player != null:
		_expect(audio_player.stream != null, "音频流已绑定 Player")
	root.add_child(audio)
	audio.call("play_sound")
	if audio_player != null:
		_expect(audio_player.playing, "音频真实进入播放")
	audio.call("pause_sound")
	if audio_player != null:
		_expect(audio_player.stream_paused, "暂停写入 stream_paused")
	audio.call("play_sound")
	if audio_player != null:
		_expect(not audio_player.stream_paused, "音频从暂停恢复")
	audio.call("stop_sound")
	if audio_player != null:
		_expect(not audio_player.playing, "停止后退出播放")
	audio.set("volume_db", -6.0)
	if audio_player != null:
		_expect(is_equal_approx(audio_player.volume_db, -6.0), "音量导出写入播放器")
	var audio_children: int = audio.get_child_count()
	root.remove_child(audio)
	root.add_child(audio)
	_expect(audio.get_child_count() == audio_children, "音频容器重复进树不增节点")
	root.remove_child(audio)
	audio.queue_free()

	var empty_audio: PanelContainer = PixelAudioPlayerScript.new() as PanelContainer
	root.add_child(empty_audio)
	empty_audio.call("play_sound")
	var empty_audio_player: AudioStreamPlayer = empty_audio.get_node_or_null("Player") as AudioStreamPlayer
	_expect(empty_audio_player != null and not empty_audio_player.playing, "空流播放请求安全忽略")
	root.remove_child(empty_audio)
	empty_audio.queue_free()

	# PixelVideoPlayer：真实可播 ogv、播放/暂停/停止、空流安全、重复进树幂等。
	var video_stream: VideoStream = load("res://assets/video/ui/ui_demo.ogv") as VideoStream
	_expect(video_stream != null, "项目内 .ogv 视频样例可加载")
	if video_stream == null:
		video.queue_free()
		return
	video.set("stream", video_stream)
	var video_player: VideoStreamPlayer = video.get_node_or_null("Video") as VideoStreamPlayer
	_expect(video_player != null and video_player.stream == video_stream, "视频流已绑定 VideoStreamPlayer")
	root.add_child(video)
	video.call("play_video")
	await process_frame
	if video_player != null:
		_expect(video_player.is_playing(), "视频真实进入播放")
	video.call("pause_video")
	if video_player != null:
		_expect(video_player.paused, "视频暂停写入 paused")
	video.call("play_video")
	if video_player != null:
		_expect(not video_player.paused, "视频从暂停恢复")
	await process_frame
	await process_frame
	if video_player != null:
		_expect(video_player.stream_position >= 0.0, "视频位置可读")
	video.call("stop_video")
	if video_player != null:
		_expect(not video_player.is_playing(), "视频停止后退出播放")
	var video_children: int = video.get_child_count()
	root.remove_child(video)
	root.add_child(video)
	_expect(video.get_child_count() == video_children, "视频容器重复进树不增节点")
	root.remove_child(video)
	video.queue_free()

	var empty_video: PanelContainer = PixelVideoPlayerScript.new() as PanelContainer
	root.add_child(empty_video)
	empty_video.call("play_video")
	var empty_video_player: VideoStreamPlayer = empty_video.get_node_or_null("Video") as VideoStreamPlayer
	_expect(empty_video_player != null and not empty_video_player.is_playing(), "空流视频安全忽略")
	root.remove_child(empty_video)
	empty_video.queue_free()

	# @tool 静默：两个播放器都必须在源码里用 is_editor_hint 拦住编辑器播发。
	_check_source("res://ui/components/pixel_audio_player.gd", ["Engine.is_editor_hint()"], [])
	_check_source("res://ui/components/pixel_video_player.gd", ["Engine.is_editor_hint()"], [])


# ---------------------------------------------------------------- PixelTabs

func _test_pixel_tabs() -> void:
	var tabs: TabContainer = PixelTabsScript.new()
	_expect(tabs is TabContainer, "PixelTabs 继承 TabContainer")
	_expect(tabs.theme != null, "PixelTabs 默认创建主题")
	_expect(tabs.theme_type_variation == ComponentThemeScript.TABS_VARIATION, "使用页签变体")

	var page_one: VBoxContainer = tabs.call("add_pixel_tab", "页一", "star") as VBoxContainer
	_expect(page_one is VBoxContainer, "add_pixel_tab 返回 VBoxContainer")
	_expect(tabs.get_tab_count() == 1, "新增一个页签")
	_expect(tabs.get_tab_title(0) == "页一", "页签标题正确")
	_expect(tabs.has_node("页一Scroll/页一Tab"), "与 UIFactory.add_tab 的两级节点结构一致")
	_expect(page_one.get_theme_constant("separation") == 6, "页内容 VBox separation = 6")

	var page_two: VBoxContainer = tabs.call("add_pixel_tab", "页二") as VBoxContainer
	_expect(page_two is VBoxContainer, "无图标页签同样返回 VBoxContainer")
	_expect(tabs.get_tab_count() == 2, "新增第二个页签")

	root.add_child(tabs)
	var changed: Array[int] = []
	tabs.tab_changed.connect(func(tab_index: int) -> void: changed.append(tab_index))
	tabs.current_tab = 1
	_expect(changed.size() == 1 and changed[0] == 1, "切换页签触发一次 tab_changed")

	root.remove_child(tabs)
	root.add_child(tabs)
	_expect(tabs.get_tab_count() == 2, "重复进树页签数不变")
	_expect(changed.size() == 1, "重复进树不重复连接 tab_changed")
	root.remove_child(tabs)
	tabs.queue_free()


# ---------------------------------------------------------------- PixelPanel

func _test_pixel_panel() -> void:
	var panel: PanelContainer = PixelPanelScene.instantiate() as PanelContainer
	_expect(panel is PanelContainer, "PixelPanel 场景实例化为 PanelContainer")
	_expect(panel.theme != null, "PixelPanel 默认创建主题")
	_expect(panel.theme_type_variation == ComponentThemeScript.PANEL_VARIATION, "使用面板变体")

	var header: Control = panel.get_node_or_null("VBox/Header") as Control
	_expect(header != null, "固定 Header 节点存在")
	_expect(header != null and not header.visible, "空标题/空说明时头部隐藏")

	var slot: Container = panel.call("get_content_slot") as Container
	_expect(slot != null, "get_content_slot() 返回内容槽")
	_expect(slot == panel.get_node("VBox/ContentSlot"), "内容槽路径固定为 VBox/ContentSlot")

	var title_label: Label = panel.get_node("VBox/Header/TitleBox/Title") as Label
	var description_label: Label = panel.get_node("VBox/Header/TitleBox/Description") as Label
	var icon_rect: TextureRect = panel.get_node("VBox/Header/Icon") as TextureRect
	_expect(title_label != null and description_label != null and icon_rect != null, "标题/说明/图标节点存在")
	_expect(title_label != null and not title_label.visible, "空标题时标题标签隐藏")
	_expect(icon_rect != null and not icon_rect.visible, "空图标时图标隐藏")

	var vbox: Control = panel.get_node("VBox") as Control
	var children_before: int = vbox.get_child_count()
	panel.set("title", "契约标题")
	panel.set("description", "契约说明文字")
	panel.set("icon", UIThemeScript.icon("star"))
	_expect(title_label.text == "契约标题" and title_label.visible, "设置 title 后标题显示")
	_expect(description_label.text == "契约说明文字" and description_label.visible, "设置 description 后说明显示")
	_expect(icon_rect.texture != null and icon_rect.visible, "设置 icon 后图标显示")
	_expect(header.visible, "有标题/说明/图标后头部整体显示")

	# 重复刷新幂等：不增删节点。
	panel.set("title", "契约标题")
	panel.set("description", "契约说明文字")
	_expect(vbox.get_child_count() == children_before, "重复刷新不增删节点")

	# 实例隔离。
	var other_panel: PanelContainer = PixelPanelScene.instantiate() as PanelContainer
	other_panel.set("title", "另一张卡")
	_expect(title_label.text == "契约标题", "面板实例之间标题互不影响")
	_expect(other_panel.get_node("VBox/Header/TitleBox/Title").text == "另一张卡", "另一实例独立显示标题")

	# 内容槽可注入内容。
	slot.add_child(Label.new())
	_expect(slot.get_child_count() == 1, "内容槽可安全 add_child")

	# 重复进树不重建主题、结构不变。
	var theme_before: Theme = panel.theme
	root.add_child(panel)
	root.remove_child(panel)
	root.add_child(panel)
	_expect(panel.theme == theme_before, "重复进树不重建主题实例")
	_expect(vbox.get_child_count() == children_before, "重复进树结构不变")
	root.remove_child(panel)
	panel.queue_free()
	other_panel.free()


# ---------------------------------------------------------------- 画廊

func _test_gallery() -> void:
	# headless 下关闭内容缩放，让窗口像素尺寸 = 逻辑尺寸，三种尺寸才是真实布局宽度。
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 800)
	var gallery: Control = GalleryScene.instantiate() as Control
	_expect(gallery is Control, "画廊场景实例化为 Control")
	root.add_child(gallery)
	await process_frame
	await process_frame

	var tabs: TabContainer = gallery.find_child("ComponentTabs", true, false) as TabContainer
	_expect(tabs != null, "画廊包含 ComponentTabs")
	if tabs == null:
		return
	_expect(tabs.get_tab_count() == EXPECTED_TAB_TITLES.size(), "画廊页签数量与期望一致")
	for tab_index: int in range(mini(tabs.get_tab_count(), EXPECTED_TAB_TITLES.size())):
		_expect(
			tabs.get_tab_title(tab_index) == EXPECTED_TAB_TITLES[tab_index],
			"页签 %d 标题为「%s」（实际「%s」）"
			% [tab_index, EXPECTED_TAB_TITLES[tab_index], tabs.get_tab_title(tab_index)]
		)
	_expect(tabs.current_tab == 0, "默认停在第一个页签")
	_expect(tabs.has_node("按钮Scroll"), "第一页由 UIFactory.add_tab 生成滚动容器")

	var primary: Button = gallery.find_child("PrimaryButton", true, false) as Button
	var danger: Button = gallery.find_child("DangerButton", true, false) as Button
	var feedback: RichTextLabel = gallery.find_child("FeedbackLog", true, false) as RichTextLabel
	var status: Label = gallery.find_child("StatusLabel", true, false) as Label
	_expect(primary != null and danger != null and feedback != null and status != null, "画廊关键控件可按稳定 name 定位")
	if primary == null or danger == null or feedback == null or status == null:
		return

	_expect(root.gui_get_focus_owner() == primary, "初始焦点在主操作按钮")

	primary.pressed.emit()
	_expect(feedback.text.contains("主操作"), "主操作按钮点击写入反馈")
	_expect(status.text.contains("主操作"), "主操作按钮更新状态行")

	tabs.current_tab = 2
	_expect(feedback.text.contains("输入"), "页签切换写入反馈")

	# 输入页：文本、下拉、开关都使用新组件并真实驱动状态。
	var demo_edit: LineEdit = gallery.find_child("DemoLineEdit", true, false) as LineEdit
	var demo_option: OptionButton = gallery.find_child("DemoOption", true, false) as OptionButton
	var demo_switch: CheckButton = gallery.find_child("DemoSwitch", true, false) as CheckButton
	var preview: Label = gallery.find_child("PreviewLabel", true, false) as Label
	_expect(demo_edit != null and demo_option != null and demo_switch != null and preview != null, "输入页包含四个新组件")
	if demo_edit == null or demo_option == null or demo_switch == null or preview == null:
		return
	_expect(demo_edit.get_script() == PixelLineEditScript, "文本控件为 PixelLineEdit")
	_expect(demo_option.get_script() == PixelOptionButtonScript, "下拉控件为 PixelOptionButton")
	_expect(demo_switch.get_script() == PixelCheckButtonScript, "开关控件为 PixelCheckButton")

	demo_edit.text_changed.emit("契约测试")
	_expect(preview.text.contains("契约测试"), "输入框输入更新预览值")

	demo_option.select(1)
	demo_option.item_selected.emit(1)
	_expect(feedback.text.contains("选项 → B"), "下拉选择写入反馈")

	_expect(not danger.disabled, "危险按钮初始可用")
	demo_switch.button_pressed = true
	_expect(danger.disabled, "开关勾选后危险按钮禁用")
	demo_switch.button_pressed = false
	_expect(not danger.disabled, "开关取消后危险按钮恢复")

	# 数值页：滑块与数值框互相联动并驱动进度条。
	tabs.current_tab = 3
	await process_frame
	var demo_slider: HSlider = gallery.find_child("DemoSlider", true, false) as HSlider
	var demo_spin: SpinBox = gallery.find_child("DemoSpinBox", true, false) as SpinBox
	var demo_progress: ProgressBar = gallery.find_child("DemoProgress", true, false) as ProgressBar
	_expect(demo_slider != null and demo_spin != null and demo_progress != null, "数值页包含滑块/数值框/进度条")
	if demo_slider == null or demo_spin == null or demo_progress == null:
		return
	_expect(demo_slider.get_script() == PixelSliderScript, "滑块为 PixelSlider")
	_expect(demo_spin.get_script() == PixelSpinBoxScript, "数值框为 PixelSpinBox")
	_expect(demo_progress.get_script() == PixelProgressBarScript, "进度条为 PixelProgressBar")
	_expect(demo_slider.max_value == 100.0 and demo_progress.max_value == 100.0, "滑块与进度条共用 0..100 范围")

	demo_slider.value = 64.0
	await process_frame
	_expect(int(demo_progress.value) == 64, "滑块驱动进度条")
	_expect(int(demo_spin.value) == 64, "滑块联动数值框")

	demo_spin.value = 25.0
	await process_frame
	_expect(int(demo_slider.value) == 25, "数值框联动滑块")
	_expect(int(demo_progress.value) == 25, "数值框驱动进度条")

	# 媒体页：图片/图标/音频/视频容器挂载，播放控制真实驱动播放状态。
	tabs.current_tab = 4
	await process_frame
	await process_frame
	var demo_image: Control = gallery.find_child("DemoImage", true, false) as Control
	var demo_icon: Control = gallery.find_child("DemoIcon", true, false) as Control
	var demo_audio: Control = gallery.find_child("DemoAudioPlayer", true, false) as Control
	var demo_video: Control = gallery.find_child("DemoVideoPlayer", true, false) as Control
	_expect(
		demo_image != null and demo_icon != null and demo_audio != null and demo_video != null,
		"媒体页包含图片/图标/音频/视频容器"
	)
	if demo_image == null or demo_icon == null or demo_audio == null or demo_video == null:
		return
	_expect(demo_image.get_script() == PixelImageScript, "媒体页图片为 PixelImage")
	_expect(demo_icon.get_script() == PixelIconScript, "媒体页图标为 PixelIcon")
	_expect(demo_audio.get_script() == PixelAudioPlayerScript, "媒体页音频为 PixelAudioPlayer")
	_expect(demo_video.get_script() == PixelVideoPlayerScript, "媒体页视频为 PixelVideoPlayer")
	var media_image: TextureRect = demo_image.find_child("Image", true, false) as TextureRect
	var audio_player: AudioStreamPlayer = demo_audio.find_child("Player", true, false) as AudioStreamPlayer
	var video_player: VideoStreamPlayer = demo_video.find_child("Video", true, false) as VideoStreamPlayer
	_expect(media_image != null and media_image.texture != null, "媒体页图片绑定真实纹理")
	_expect(audio_player != null and audio_player.stream != null, "媒体页音频绑定真实 stream")
	_expect(video_player != null and video_player.stream != null, "媒体页视频绑定真实 stream")
	var play_audio: Button = demo_audio.find_child("PlayButton", true, false) as Button
	var pause_audio: Button = demo_audio.find_child("PauseButton", true, false) as Button
	var stop_audio: Button = demo_audio.find_child("StopButton", true, false) as Button
	_expect(play_audio != null and pause_audio != null and stop_audio != null, "音频容器含播放/暂停/停止按钮")
	if play_audio != null and pause_audio != null and stop_audio != null and audio_player != null:
		play_audio.pressed.emit()
		_expect(audio_player.playing, "媒体页音频播放按钮驱动播放")
		pause_audio.pressed.emit()
		_expect(audio_player.stream_paused, "媒体页音频暂停按钮生效")
		play_audio.pressed.emit()
		_expect(not audio_player.stream_paused, "媒体页音频从暂停恢复")
		stop_audio.pressed.emit()
		_expect(not audio_player.playing, "媒体页音频停止按钮生效")
	var play_video: Button = demo_video.find_child("PlayButton", true, false) as Button
	var pause_video: Button = demo_video.find_child("PauseButton", true, false) as Button
	var stop_video: Button = demo_video.find_child("StopButton", true, false) as Button
	_expect(play_video != null and pause_video != null and stop_video != null, "视频容器含播放/暂停/停止按钮")
	if play_video != null and pause_video != null and stop_video != null and video_player != null:
		play_video.pressed.emit()
		await process_frame
		_expect(video_player.is_playing(), "媒体页视频播放按钮驱动播放")
		pause_video.pressed.emit()
		_expect(video_player.paused, "媒体页视频暂停按钮生效")
		play_video.pressed.emit()
		_expect(not video_player.paused, "媒体页视频从暂停恢复")
		stop_video.pressed.emit()
		_expect(not video_player.is_playing(), "媒体页视频停止按钮生效")

	# 菜单页：多行文本、动作菜单、弹层开关与焦点恢复。
	tabs.current_tab = 5
	await process_frame
	await process_frame
	var demo_text_area: TextEdit = gallery.find_child("DemoTextArea", true, false) as TextEdit
	var demo_dropdown: MenuButton = gallery.find_child("DemoDropdown", true, false) as MenuButton
	var open_popup: Button = gallery.find_child("OpenPopupButton", true, false) as Button
	var demo_popup: PopupPanel = gallery.find_child("DemoPopup", true, false) as PopupPanel
	var close_popup: Button = gallery.find_child("PopupCloseButton", true, false) as Button
	_expect(
		demo_text_area != null and demo_dropdown != null and open_popup != null
		and demo_popup != null and close_popup != null,
		"菜单页包含多行文本/动作菜单/弹层与开关按钮"
	)
	if demo_text_area == null or demo_dropdown == null or open_popup == null:
		return
	if demo_popup == null or close_popup == null:
		return
	_expect(demo_text_area.get_script() == PixelTextAreaScript, "菜单页多行文本为 PixelTextArea")
	_expect(demo_dropdown.get_script() == PixelDropdownScript, "菜单页动作菜单为 PixelDropdown")
	_expect(demo_popup.get_script() == PixelPopupScript, "菜单页弹层为 PixelPopup")
	demo_text_area.text_changed.emit()
	_expect(feedback.text.contains("文本域"), "多行文本编辑写入反馈")
	demo_dropdown.get_popup().id_pressed.emit(0)
	_expect(feedback.text.contains("动作"), "动作菜单选择写入反馈")
	open_popup.grab_focus()
	open_popup.pressed.emit()
	_expect(demo_popup.visible, "打开按钮弹出弹层")
	close_popup.pressed.emit()
	_expect(not demo_popup.visible, "关闭按钮收起弹层")
	_expect(root.gui_get_focus_owner() == open_popup, "弹层关闭后焦点回到打开按钮")

	# 演示页无教学/说明性文本：标题、短标签与真实值之外不应出现说明文案或路径。
	var forbidden: Array[String] = ["说明", "用法", "API", "继承", "res://", "点击可", "示例"]
	for control: Node in gallery.find_children("*", "Label", true, false):
		var label_text: String = (control as Label).text
		for word: String in forbidden:
			_expect(not label_text.contains(word), "演示页标签不含说明性文本「%s」：%s" % [word, label_text])
	for button_node: Node in gallery.find_children("*", "Button", true, false):
		var button_text: String = (button_node as Button).text
		for word: String in forbidden:
			_expect(not button_text.contains(word), "演示页按钮不含说明性文本「%s」：%s" % [word, button_text])

	# 重置：页签回首页、危险按钮恢复、清空旧反馈、数值归零、焦点回归。
	var reset_button: Button = gallery.find_child("ResetButton", true, false) as Button
	_expect(reset_button != null, "标题栏包含重置按钮")
	if reset_button != null:
		reset_button.pressed.emit()
		_expect(tabs.current_tab == 0, "重置后页签回到第一个")
		_expect(not danger.disabled, "重置后危险按钮恢复可用")
		_expect(not feedback.text.contains("契约测试"), "重置清空旧反馈")
		_expect(feedback.text.contains("重置"), "重置写入反馈")
		_expect(int(demo_slider.value) == 0 and int(demo_progress.value) == 0, "重置后滑块与进度归零")
		_expect(preview.text.contains("—"), "重置后预览值复位")
		_expect(demo_text_area.text == "", "重置清空多行文本")
		_expect(not demo_popup.visible, "重置收起弹层")
		_expect(audio_player != null and not audio_player.playing, "重置停止音频")
		_expect(video_player != null and not video_player.is_playing(), "重置停止视频")
		_expect(root.gui_get_focus_owner() == primary, "重置后焦点回到主操作按钮")

	# 多尺寸：铺满窗口、页签/新组件有有效布局。
	var sizes: Array[Vector2i] = [Vector2i(1024, 640), Vector2i(1280, 800), Vector2i(1920, 1080)]
	for target: Vector2i in sizes:
		root.size = target
		await process_frame
		await process_frame
		_expect(
			gallery.size == Vector2(target),
			"画廊铺满 %dx%d（实际 %s）" % [target.x, target.y, str(gallery.size)]
		)
		_expect(tabs.size.x > 0.0 and tabs.size.y > 0.0, "页签在 %dx%d 有有效尺寸" % [target.x, target.y])
		_expect(
			primary.size.x > 0.0 and primary.size.y > 0.0,
			"主操作按钮在 %dx%d 有有效尺寸" % [target.x, target.y]
		)
		_expect(
			feedback.size.y > 0.0,
			"反馈面板在 %dx%d 有有效高度" % [target.x, target.y]
		)
		tabs.current_tab = 4
		await process_frame
		_expect(
			demo_image.size.x > 0.0 and demo_image.size.y > 0.0,
			"图片容器在 %dx%d 有有效尺寸" % [target.x, target.y]
		)
		tabs.current_tab = 5
		await process_frame
		_expect(
			demo_text_area.size.x > 0.0 and demo_text_area.size.y > 0.0,
			"多行文本在 %dx%d 有有效尺寸" % [target.x, target.y]
		)
		tabs.current_tab = 0
		await process_frame

	root.remove_child(gallery)
	gallery.queue_free()
