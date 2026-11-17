## tests/level_up_visual_probe.gd — 升级弹窗可视验收探针（仅测试，MCP 留屏用）
## 入口：dbg_launch(scene="res://tests/level_up_visual_probe.tscn")（Headful）。
## 复用真实 BattleLevelUpPresentation（产品组件，零改动），固定真实格式 fixture：
## 九属性双级连升（Lv.1 → Lv.3，每属性每级 +1，与 resolver.gain_exp 输出同构）。
##
## MCP 可调用（runtime_call_method）：
##   resize_view(width, height)  设内部视口（content_scale 三件套，见函数注释）；
##                               随后调 show_level_up() 按新视口重算布局
##   show_level_up()             播放 fixture 弹窗（产品 AUTO_CLOSE 2.5s；可先
##                               runtime_time_scale(0) 冻结留屏再调用）
##   close()                     跳过/关闭当前弹窗
## MCP 可读（runtime_get_property / runtime_await_condition）：
##   panel_visible(bool) 弹窗当前是否展示 / finished(bool) 是否完成过一次收尾
##   passed(bool) 自检（文本/边界）/ last_result(String) 最近自检详情
##   fixture_levels(Array) fixture（可先 runtime_set_property 改长再 show 压纵滚）
## 行为：_ready 自动播放一次；场景保活 240s 后 quit(0)；点击/Space/Esc 亦可关弹窗。
extends Control

const LevelUpPresentationScript = preload("res://scripts/battle/level_up_presentation.gd")

const HOLD_SECONDS := 240

var fixture_levels: Array = _default_levels()
var passed: bool = true
var finished: bool = false
var last_result: String = "not checked"

var _presentation: LevelUpPresentationScript = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_presentation = LevelUpPresentationScript.new()
	_presentation.name = "LevelUpPresentation"
	_presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_presentation)
	_presentation.finished.connect(_on_finished)
	# 真实音效链（ui_levelup 已注册 wav）：可视验收时能听到即链路通。
	_presentation.sound_requested.connect(func(cue: StringName) -> void: Sfx.play(cue))
	print("[visual-probe] ready size=%s；fixture 九属性双级；hold %ds；"
		% [get_viewport_rect().size, HOLD_SECONDS]
		+ "MCP: resize_view/show_level_up/close；读 panel_visible/passed/last_result")
	show_level_up()
	_hold_then_quit()


## 固定真实格式 fixture：基础 stats 双级各 +1（键序无关，展示按九键序）。
func _default_levels() -> Array:
	var base := {
		&"hp": 24, &"mp": 10, &"str": 11, &"mag": 6, &"skl": 9,
		&"spd": 8, &"luk": 7, &"def": 8, &"res": 4,
	}
	var levels: Array = []
	for level in [2, 3]:
		var gains := {}
		var step: int = level - 2
		for stat in base:
			gains[stat] = {&"from": int(base[stat]) + step, &"to": int(base[stat]) + step + 1}
		levels.append({&"level": level, &"gains": gains})
	return levels


func _unit() -> Dictionary:
	return {&"name": "罗兰", &"level": 3}


# ---------- MCP 入口 ----------

## 窗口 embedded 不可物理 resize：用 root Window 的 content_scale 三件套指定内部
## 视口（mode=2 VIEWPORT / aspect=0 IGNORE / size=两档 1024x640、1920x1080）。
## 弹窗布局与 _check_panel 的视口矩形均按虚拟视口坐标计算，两档下自检同一套。
## 写入顺序必须 size → aspect → mode：mode=VIEWPORT 先写而 scale_size 仍是 (0,0)
## 的中间态会让视口缩放除零，根 Control size 变 NaN（运行态 dump 实证）；
## 若外部已直写过属性导致根布局 NaN，末尾的预设重挂可同步自愈（不依赖延迟重排，
## 冻结树下也生效）。弹窗自动收尾 2.5s：MCP 侧先 runtime_time_scale(0) 冻结再
## show_level_up() 可无限留屏（SceneTreeTimer 随 time_scale 缩放）；注意冻结期间
## _hold_then_quit 计时同样暂停，恢复 1 后 240s 保活继续。
func resize_view(width: int, height: int) -> void:
	var win := get_window()
	win.content_scale_size = Vector2i(width, height)
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE  # 0
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT  # 2
	_heal_layout()
	print("[visual-probe] content scale -> %dx%d root=%s" % [width, height, size])


## 根布局自愈：重挂全矩形预设（从当前父视口尺寸同步重算锚点偏移）。
## 可在 show_level_up 前 MCP 直调；size 含 NaN 亦可恢复。
func _heal_layout() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _presentation != null:
		_presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_level_up() -> void:
	finished = false
	_heal_layout()
	_presentation.play(_unit(), fixture_levels)
	_check_panel()


func close() -> void:
	_presentation.skip()


## 布局诊断（MCP runtime_call_method 可调）：打印并返回各关键节点实测矩形。
## 用于「节点有文本但像素不绘制」类布局问题定位（对照 1024x640 黑屏截图）：
## 重点看 label/list/scroll 三层 rect 是否全零/错位/在 clip 外。
func dump_rects() -> Dictionary:
	var out := {}
	out["window"] = {
		"size": get_window().size,
		"scale_size": get_window().content_scale_size,
		"mode": get_window().content_scale_mode,
	}
	var probe_nodes := [
		["root", self],
		["presentation", _presentation],
		["center", _presentation.find_child("Center", true, false)],
		["panel", _presentation.find_child("LevelUpPanel", true, false)],
		["vbox", _presentation.find_child("LevelUpVBox", true, false)],
		["scroll", _presentation.find_child("GainsScroll", true, false)],
		["list", _presentation.find_child("GainsList", true, false)],
		["label", _presentation.find_child("GainsText", true, false)],
	]
	for entry in probe_nodes:
		var key: String = entry[0]
		var node: Node = entry[1]
		if node is Control:
			var c := node as Control
			out[key] = {
				"rect": c.get_global_rect(),
				"min": c.get_minimum_size(),
				"vis": c.is_visible_in_tree(),
			}
		else:
			out[key] = "missing"
	if out.get("scroll") is Dictionary:
		var scroll := _presentation.find_child("GainsScroll", true, false) as ScrollContainer
		out["scroll_v_bar"] = scroll.get_v_scroll_bar().is_visible_in_tree()
	print("[visual-probe] dump_rects ", JSON.stringify(out))
	return out


# ---------- 观测 ----------

func panel_visible() -> bool:
	return _presentation != null and _presentation.is_playing()


func _on_finished(_skipped: bool) -> void:
	finished = true


## 展示后两帧自检：三 Label 文本非空、跨度文本=静态预期、面板矩形在视口内。
func _check_panel() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not _presentation.is_playing():
		last_result = "check skipped: panel already closed"
		return
	var center := _presentation.find_child("Center", true, false)
	if center == null or center.get_child_count() == 0:
		passed = false
		last_result = "FAIL: Center/PanelContainer 缺失"
		return
	var panel := center.get_child(0) as Control
	var panel_rect: Rect2 = panel.get_global_rect()
	var vp_rect := get_viewport_rect()
	var inside: bool = vp_rect.encloses(panel_rect)
	var gains := _presentation.find_child("GainsText", true, false) as Label
	var range_label := _presentation.find_child("LevelRange", true, false) as Label
	var title := _presentation.find_child("LevelTitle", true, false) as Label
	var range_ok := range_label != null \
		and range_label.text == LevelUpPresentationScript.level_range_text(fixture_levels)
	var text_ok := gains != null and not gains.text.is_empty() and title != null \
		and title.text == "%s 升级！" % String(_unit()[&"name"])
	# 几何自检：成长文本 rect 非零高且与视口相交（防“有文本无像素”黑屏回归）。
	var gains_geo: bool = gains != null \
		and gains.is_visible_in_tree() \
		and gains.get_global_rect().size.y > 0.0 \
		and vp_rect.intersects(gains.get_global_rect())
	last_result = "panel=%s vp=%s inside=%s range_ok=%s text_ok=%s gains_geo=%s" % [
		panel_rect, vp_rect, inside, range_ok, text_ok, gains_geo]
	if not (inside and range_ok and text_ok and gains_geo):
		passed = false


func _hold_then_quit() -> void:
	await get_tree().create_timer(HOLD_SECONDS).timeout
	print("[visual-probe] hold 结束 passed=%s last=%s" % [str(passed), last_result])
	get_tree().quit(0 if passed else 1)
