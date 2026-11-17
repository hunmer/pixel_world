## battle/level_up_presentation.gd — 场内升级薄演出（升级弹窗）
##
## 纯表现层：只消费调用方传入的 unit 与 levels（BattleActionResolver.gain_exp
## 顶层的 [{level:int, gains:{statKey:{from,to}}}] 列表），展示单位名 / 等级跨度 /
## 中文九属性 from → to 成长行；绝不重算经验、不改写结算结果或 RNG。
## 音效不直连 Sfx：发出 sound_requested(&"ui_levelup")，由宿主（battle.gd
## _on_presentation_sound → BattleSfx.on_presentation_sound）走真实素材链播放。
##
## 生命周期：play() 为协程，直到弹窗收尾才返回（调用方 await 即得"演出结束"）。
## 收尾路径任意一条即结束且只发一次 finished 信号（幂等）：
##   - Space / Enter / KpEnter / Escape / 左键（_input，与 ResultPresentation 同款）
##   - "继续" 按钮
##   - AUTO_CLOSE_DURATION 超时兜底（防卡回合状态机）
##   - options.skip（敌方/托管跳过演出）：只发音效不弹窗，立即返回
##   - cancel()：宿主退出（_exit_tree）时的静默清理
## 空 levels 不展示（play 立即返回，不发信号）。
##
## 公开 API（battle.gd 装配层调用）：
##   play(unit, levels, options) -> void   # 协程；options 同 turn_director
##                                          # get_action_anim_options 的 {skip:bool}
##   skip() / cancel() / is_playing() -> bool
##   signal finished(skipped: bool)        # 每次实际展示的弹窗恰好一次
##   signal sound_requested(cue: StringName)
## 静态纯函数（契约测试直测文本）：stat_label / level_range_text / gain_lines。
class_name BattleLevelUpPresentation
extends Control

signal finished(skipped: bool)
signal sound_requested(cue: StringName)
## 内部收尾信号：play 协程挂起点；带 skipped 语义（超时=自然收尾 false）。
signal _session_closed(skipped: bool)

## 超时兜底：任何路径下弹窗至多停留此时长，保证回合状态机不被卡死。
const AUTO_CLOSE_DURATION := 2.5

## 属性键 → 中文短名（与 scripts/scenes/campaign_format.gd STAT_LABELS 同源一致）。
const STAT_LABELS := {
	&"hp": "HP", &"mp": "MP", &"str": "力", &"mag": "魔", &"skl": "技",
	&"spd": "速", &"luk": "运", &"def": "防", &"res": "魔防",
}
## 成长行固定展示顺序（九键；未知键按插入序追加，键名原样显示）。
const _STAT_ORDER: Array[StringName] = [
	&"hp", &"mp", &"str", &"mag", &"skl", &"spd", &"luk", &"def", &"res",
]

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")

## 弹窗最小宽度：300 = SPACE_LG*12 + SPACE_XS*3（DESIGN 禁裸数字，token 显式换算）。
const _PANEL_MIN_WIDTH: int = ComponentThemeScript.SPACE_LG * 12 + ComponentThemeScript.SPACE_XS * 3
## 标题字号 18 = FONT_BODY(16) + SPACE_XS/2（正文上沿，中间档 token 换算）。
const _TITLE_FONT_SIZE: int = ComponentThemeScript.FONT_BODY + ComponentThemeScript.SPACE_XS / 2
## 正文字号 14 = FONT_CAPTION(12) + SPACE_XS/2（辅助上沿，中间档 token 换算）。
const _BODY_FONT_SIZE: int = ComponentThemeScript.FONT_CAPTION + ComponentThemeScript.SPACE_XS / 2

var _generation := 0
var _active := false
var _center: CenterContainer = null
var _title_label: Label = null
var _level_label: Label = null
var _gains_label: Label = null
var _gains_scroll: ScrollContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_playing() -> bool:
	return _active


## 升级弹窗协程：levels 为 resolver.gain_exp 顶层 levels 列表。
## options.skip=true（敌方/托管跳过演出）时只发音效、不弹窗、立即返回。
func play(unit: Dictionary, levels: Array, options: Dictionary = {}) -> void:
	if _active:
		skip()  # 串场防御：先收尾上一场，保证 finished/协程各自恰一次
	_generation += 1
	var gen := _generation
	if levels.is_empty():
		return
	sound_requested.emit(&"ui_levelup")
	if bool(options.get(&"skip", false)) or not is_inside_tree():
		return
	_show(unit, levels)
	var closed_info: Array = []
	var handler := func(did_skip: bool) -> void:
		if closed_info.is_empty():
			closed_info.append(did_skip)
	_session_closed.connect(handler)
	# 超时兜底：无论输入路径如何，AUTO_CLOSE_DURATION 后强制自然收尾。
	var timer := get_tree().create_timer(AUTO_CLOSE_DURATION)
	timer.timeout.connect(func() -> void:
		if _generation == gen:
			_finish(false))
	while closed_info.is_empty() and _generation == gen:
		await _session_closed
	_session_closed.disconnect(handler)


func skip() -> void:
	_finish(true)


## 宿主退出（battle.gd _exit_tree）静默清理：作废在途时间轴并收尾一次。
func cancel() -> void:
	_generation += 1
	_finish(true)


func _finish(skipped: bool) -> void:
	if not _active:
		return  # 幂等：skip/超时/按钮多路径只收尾一次
	_active = false
	if _center != null and is_instance_valid(_center):
		_center.visible = false
	finished.emit(skipped)
	_session_closed.emit(skipped)


## 与 ResultPresentation 同款跳过输入：演出期 Space/Enter/KpEnter/Esc/左键。
## set_input_as_handled 阻断事件继续传给宿主输入路由。
func _input(event: InputEvent) -> void:
	if not is_playing():
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			get_viewport().set_input_as_handled()
			skip()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			skip()


func _ensure_widgets() -> void:
	if is_instance_valid(_center):
		return
	_center = PixelCenter.new()
	_center.name = "Center"
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	var panel := PanelContainer.new()
	panel.name = "LevelUpPanel"
	panel.add_theme_stylebox_override("panel", UIThemeScript.menu_panel_style())
	panel.custom_minimum_size = Vector2(float(_PANEL_MIN_WIDTH), 0.0)
	_center.add_child(panel)
	var vbox := PixelVBox.new()
	vbox.name = "LevelUpVBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.gap = ComponentThemeScript.SPACE_SM  # 原 6 收敛到最近间距 token
	panel.add_child(vbox)
	_title_label = UIFactoryScript.outline_label("", _TITLE_FONT_SIZE, UIThemeScript.ACCENT)
	_title_label.name = "LevelTitle"
	# 长中文名在面板宽度内任意断行（CJK 无空格，WORD_SMART 不生效）。
	_title_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	vbox.add_child(_title_label)
	_level_label = UIFactoryScript.outline_label("", _BODY_FONT_SIZE, UIThemeScript.TEXT_MAIN)
	_level_label.name = "LevelRange"
	vbox.add_child(_level_label)
	# 成长行超出高度上限时纵向滚动（PixelScroll 横向禁用，按钮始终可见）。
	_gains_scroll = PixelScroll.new()
	_gains_scroll.name = "GainsScroll"
	_gains_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_gains_scroll)
	# 组件库惯例（campaign_hub / campaign_levels / save_select 等 5 处）：
	# ScrollContainer 子级必须是 PixelVBox 容器承载内容，不用裸 Label 直挂
	# （实测裸 Label 直挂时区域渲染为空——修复 1024x640 黑屏）。
	var gains_list := PixelVBox.new()
	gains_list.name = "GainsList"
	gains_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gains_scroll.add_child(gains_list)
	_gains_label = UIFactoryScript.outline_label("", _BODY_FONT_SIZE, UIThemeScript.TEXT_MAIN)
	_gains_label.name = "GainsText"
	gains_list.add_child(_gains_label)
	var continue_btn := UIFactoryScript.button("继续 (Space)", skip)
	continue_btn.name = "ContinueButton"
	vbox.add_child(continue_btn)
	_center.visible = false


func _show(unit: Dictionary, levels: Array) -> void:
	_ensure_widgets()
	var display_name := String(unit.get(&"name", unit.get(&"id", "未知单位")))
	_title_label.text = "%s 升级！" % display_name
	_level_label.text = level_range_text(levels)
	_gains_label.text = "\n".join(gain_lines(levels))
	# 高度上限随视口自适应（1024x640~1920x1080 预留标题/按钮/边距），
	# 内容不足上限时贴合内容，超出则纵向滚动。
	var needed: int = int(_gains_label.get_combined_minimum_size().y)
	var viewport_h := int(get_viewport_rect().size.y)
	var cap: int = maxi(
		viewport_h - ComponentThemeScript.SPACE_LG * 4,
		ComponentThemeScript.FONT_TITLE)
	var want: int = mini(needed + ComponentThemeScript.SPACE_XS, cap)
	# 4.7 实测：custom_maximum_size 的 0 分量会被当作真实上限把宽度钳成 0
	# （运行态 dump 实证 scroll size.x=0 → 内容全裁 → 黑屏）。横向须显式 INF。
	_gains_scroll.custom_minimum_size = Vector2(0.0, float(want))
	_gains_scroll.custom_maximum_size = Vector2(INF, float(cap))
	_center.visible = true
	_active = true


# ---------- 静态纯函数（文本组装，契约测试直测） ----------

## 属性键 → 中文短名；未知键原样返回键名字符串。
static func stat_label(stat) -> String:
	var key := String(stat)
	return String(STAT_LABELS.get(key, key))


## 等级跨度行：levels 为空返回空串；多级连升合成 "Lv.a → Lv.b"。
## 起始等级 = 首条 level - 1（resolver 连续升级每条严格 +1），下限 1。
static func level_range_text(levels: Array) -> String:
	if levels.is_empty():
		return ""
	var first := int((levels[0] as Dictionary).get(&"level", 1))
	var last := int((levels[levels.size() - 1] as Dictionary).get(&"level", first))
	var from := maxi(1, first - 1)
	return "Lv.%d → Lv.%d" % [from, last]


## 成长文本行：每条 level 一段；单级直列 "力 4 → 5"，多级加 "▶ Lv.n" 段头；
## 零成长条目显示"没有属性成长"。九键固定序，未知键按插入序追加。
static func gain_lines(levels: Array) -> Array[String]:
	var lines: Array[String] = []
	var multi := levels.size() > 1
	for entry_value in levels:
		var entry := entry_value as Dictionary
		if entry == null:
			continue
		if multi:
			lines.append("▶ Lv.%d" % int(entry.get(&"level", 0)))
		var gains: Dictionary = entry.get(&"gains", {})
		var stat_lines: Array[String] = []
		for stat in _STAT_ORDER:
			if gains.has(stat):
				var change: Dictionary = gains[stat]
				stat_lines.append("%s %d → %d" % [
					stat_label(stat),
					int(change.get(&"from", 0)), int(change.get(&"to", 0))])
		for key in gains.keys():
			if not _STAT_ORDER.has(key):
				var change: Dictionary = gains[key]
				stat_lines.append("%s %d → %d" % [
					stat_label(key),
					int(change.get(&"from", 0)), int(change.get(&"to", 0))])
		if stat_lines.is_empty():
			lines.append("没有属性成长")
		else:
			lines.append_array(stat_lines)
	return lines
