## scripts/scenes/campaign_modal.gd — 冒险 UI 模态弹层（确认/输入/通知）
##
## PixelPanel + PixelCenter 组合。打开时对背景层做确定性焦点陷阱：
## 收集并临时禁用背景层全部可聚焦控件（不依赖引擎版本的递归焦点开关），
## 关闭时恢复并把焦点还给打开前的焦点控件；ESC 等价「取消」。
## 按钮一律 UIFactory（禁直预加载 pixel_button，全局 Sfx 发声）。
extends Control

signal chosen(action_id: String)

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const CampaignFormatScript = preload("res://scripts/scenes/campaign_format.gd")
const PixelPanelScene = preload("res://ui/components/pixel_panel.tscn")
const PixelCenterScript = preload("res://ui/components/pixel_center.gd")
const PixelVBoxScript = preload("res://ui/components/pixel_v_box.gd")
const PixelHBoxScript = preload("res://ui/components/pixel_h_box.gd")

var _input_edit: LineEdit
var _scope: Control
var _cancelable := true
var _default_focus: Control
var _first_button: Button
var _previous_focus: Control
var _focus_disabled: Array = []
var _closing := false


## 构建弹层视觉树（加入场景树前调用）。
## actions: [{text:String, semantic:int(0/1/2), id:String, focus:bool}]；
## want_input 时提供输入框并默认聚焦输入框；scope_focus 为要屏蔽焦点的背景层。
func build(
	title: String,
	message: String,
	actions: Array,
	scope_focus: Control,
	want_input: bool = false,
	input_placeholder: String = "",
	input_default: String = "",
	cancelable: bool = true
) -> void:
	_scope = scope_focus
	_cancelable = cancelable
	name = "CampaignModal"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 整层拦截鼠标，屏蔽下方屏幕的点击（子内容在其上正常接收）。
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 遮罩：色板取 UITheme.BG，不新增硬编码颜色。
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = UIThemeScript.BG
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var center := PixelCenterScript.new()
	center.name = "ModalCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel: PanelContainer = PixelPanelScene.instantiate() as PanelContainer
	panel.name = "ModalPanel"
	panel.set("title", title)
	# 弹层最小宽 360 = SPACE_LG(24) * 15（token 换算，DESIGN.md §7）。
	panel.custom_minimum_size = Vector2(ComponentThemeScript.SPACE_LG * 15, 0.0)
	center.add_child(panel)

	var slot: Container = panel.call("get_content_slot") as Container
	var body := PixelVBoxScript.new()
	slot.add_child(body)

	if message != "":
		var message_label: Label = UIFactoryScript.label(
			message, ComponentThemeScript.FONT_BODY, UIThemeScript.TEXT_MAIN
		)
		message_label.name = "ModalMessage"
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(message_label)

	if want_input:
		_input_edit = UIFactoryScript.line_edit(input_placeholder)
		_input_edit.name = "ModalInput"
		_input_edit.text = input_default
		body.add_child(_input_edit)

	var row := PixelHBoxScript.new()
	row.name = "ModalActions"
	row.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(row)

	for action: Variant in actions:
		var spec: Dictionary = action
		var action_id := String(spec.get("id", "ok"))
		var button: Button = UIFactoryScript.button(
			String(spec.get("text", "确定")), Callable(), "", false
		)
		# styled=false 走 PixelButton 组件语义变体（Primary/Secondary/Danger）。
		button.set("semantic", clampi(int(spec.get("semantic", 1)), 0, 2))
		button.name = "Action_%s" % action_id
		if _first_button == null:
			_first_button = button
		if bool(spec.get("focus", false)):
			_default_focus = button
		button.pressed.connect(_on_action.bind(action_id))
		row.add_child(button)


## 进入场景树后调用：启用焦点陷阱并抓默认焦点。
func open() -> void:
	_previous_focus = get_viewport().gui_get_focus_owner()
	_focus_disabled.clear()
	if _scope != null:
		for node: Variant in _scope.find_children("*", "Control", true, false):
			var control := node as Control
			if control != null and control.focus_mode != Control.FOCUS_NONE:
				_focus_disabled.append([control, control.focus_mode])
				control.focus_mode = Control.FOCUS_NONE
	# 默认焦点：带输入框时输入框优先（caret 到末尾），否则取 spec 标记的
	# focus 按钮或首按钮。spec.focus 只在不带输入框的弹窗生效。
	if _input_edit != null:
		_default_focus = _input_edit
	elif _default_focus == null:
		_default_focus = _first_button
	if CampaignFormatScript.can_grab_focus(_default_focus):
		_default_focus.grab_focus()
		if _input_edit != null and _default_focus == _input_edit:
			_input_edit.caret_column = _input_edit.text.length()


func get_input_text() -> String:
	if _input_edit == null:
		return ""
	return _input_edit.text.strip_edges()


func close(action_id: String) -> void:
	if _closing:
		return
	_closing = true
	# 先恢复背景焦点与原焦点，再发 chosen：处理器里若开新弹窗（如空名→错误
	# 提示），新弹窗的焦点陷阱才能建立在已恢复的干净状态上。
	for pair: Variant in _focus_disabled:
		var control := pair[0] as Control
		if control != null and is_instance_valid(control):
			control.focus_mode = pair[1]
	_focus_disabled.clear()
	if CampaignFormatScript.can_grab_focus(_previous_focus):
		_previous_focus.grab_focus()
	# 先脱离父节点再发 chosen：chosen 处理器内同步开的新弹层才能拿到干净的
	# "CampaignModal" 节点名——否则旧弹层同名未删，Godot 会把新弹层自动改名
	# （@CampaignModal@…），按名定位（测试断言/清场）全部失准。此时不 free：
	# 信号源按钮仍在 pressed 发射栈上（曾因同步 free 报 freed-while-emitted），
	# 由末尾 queue_free 延迟释放。
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)
	chosen.emit(action_id)
	queue_free()


func _on_action(action_id: String) -> void:
	close(action_id)


func _unhandled_input(event: InputEvent) -> void:
	if _cancelable and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close("cancel")
