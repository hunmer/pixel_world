## battle/battle_settings_tab.gd — 右侧【战场设置】页的独立内容构造器。
##
## 只负责控件与回调注入；偏好持久化由 Settings、真实镜头生命周期由 Battle 负责。
extends RefCounted

const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")


## 返回开关供集成层/自动断言读取；on_changed 只接收用户切换后的 bool。
static func populate(
	tab: VBoxContainer,
	immersive_enabled: bool,
	on_changed: Callable
) -> CheckButton:
	var title := UIFactoryScript.shadow_label("交战镜头", 14, UIThemeScript.TEXT_MAIN)
	tab.add_child(title)
	var toggle := UIFactoryScript.check_button(
		"沉浸式演出",
		"攻击/技能交战时平滑降到参战角色附近，以近平视视角演出；完整演出后恢复战术相机。"
	)
	toggle.name = "ImmersivePresentationToggle"
	toggle.button_pressed = immersive_enabled
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.tooltip_text = "默认关闭。战斗中可随时切换；关闭会在当前完整动作结束后恢复战术镜头。"
	tab.add_child(toggle)
	var description := UIFactoryScript.label(
		"开启后，攻击与技能使用近平视交战镜头；反击、多段与范围目标完整演出后恢复原视角。",
		10,
		UIThemeScript.TEXT_DIM
	)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(description)
	if on_changed.is_valid():
		toggle.toggled.connect(on_changed)
	return toggle
