## scripts/scenes/campaign_save_select.gd — 冒险存档选择屏
##
## 多档命名列表（新建/加载/重命名/确认删除），摘要显示金币/通关数/时间；
## 最近档以 list_profiles 的 is_recent 标记显示「最近游玩」并默认聚焦其
## 「加载」（无该字段时回落 saved_at 排序首卡）；notice 非空即警示（含
## 可加载的备份恢复档），加载成功的 notice 弹「存档提示」给玩家确认。
## 数据全部经 CampaignSession 读取，changed 信号触发刷新（事件驱动，不轮询）。
extends Control

const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const PixelPanelScene = preload("res://ui/components/pixel_panel.tscn")
const PixelMarginScript = preload("res://ui/components/pixel_margin.gd")
const PixelVBoxScript = preload("res://ui/components/pixel_v_box.gd")
const PixelHBoxScript = preload("res://ui/components/pixel_h_box.gd")
const PixelScrollScript = preload("res://ui/components/pixel_scroll.gd")
const CampaignFormatScript = preload("res://scripts/scenes/campaign_format.gd")
const AIDifficultyScript = preload("res://scripts/systems/ai_difficulty.gd")

const DEV_ENTRY_SCENE := "res://scenes/Game.tscn"

var _main: Control
var _save_list: VBoxContainer
var _empty_card: PanelContainer
var _notice: Label
var _new_btn: Button
var _refresh_btn: Button
var _dev_btn: Button
var _first_load_btn: Button
var _recent_idx: int = -1
var _profiles: Array = []


func setup(main_ref: Control) -> void:
	_main = main_ref


func _ready() -> void:
	_build()
	visible = false


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var page := PixelMarginScript.new()
	page.name = "PageMargin"
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)

	var box := PixelVBoxScript.new()
	box.name = "PageBox"
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(box)

	var title: Label = UIFactoryScript.label(
		"冒险存档", ComponentThemeScript.FONT_TITLE, UIThemeScript.TEXT_MAIN
	)
	title.name = "PageTitle"
	box.add_child(title)

	var caption: Label = UIFactoryScript.label(
		"每段存档是一次独立冒险：金币、物品、角色与关卡进度互相隔离。",
		ComponentThemeScript.FONT_CAPTION, UIThemeScript.TEXT_DIM
	)
	caption.name = "PageCaption"
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(caption)

	_notice = UIFactoryScript.label(
		"", ComponentThemeScript.FONT_BODY, UIThemeScript.ERROR
	)
	_notice.name = "SessionNotice"
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.visible = false
	box.add_child(_notice)

	var scroll := PixelScrollScript.new()
	scroll.name = "ListScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)

	_save_list = PixelVBoxScript.new()
	_save_list.name = "SaveList"
	scroll.add_child(_save_list)

	_empty_card = PixelPanelScene.instantiate() as PanelContainer
	_empty_card.name = "EmptyCard"
	_empty_card.set("title", "还没有冒险存档")
	_empty_card.set("description", "点击下方「新建冒险」开始第一段旅程。")
	_empty_card.visible = false
	box.add_child(_empty_card)

	var footer := PixelHBoxScript.new()
	footer.name = "FooterRow"
	box.add_child(footer)

	_new_btn = _make_action_button("新建冒险", 0, _on_new)
	_new_btn.name = "NewBtn"
	footer.add_child(_new_btn)

	_refresh_btn = _make_action_button("刷新", 1, _on_refresh)
	_refresh_btn.name = "RefreshBtn"
	footer.add_child(_refresh_btn)

	_dev_btn = _make_action_button("开发入口 · Game.tscn", 1, _on_dev_entry)
	_dev_btn.name = "DevEntryBtn"
	footer.add_child(_dev_btn)


## 语义按钮统一入口：styled=false 走 PixelButton 组件变体（视觉一致）。
func _make_action_button(text: String, semantic: int, handler: Callable) -> Button:
	var button: Button = UIFactoryScript.button(text, Callable(), "", false)
	button.set("semantic", clampi(semantic, 0, 2))
	button.pressed.connect(handler)
	return button


func on_shown() -> void:
	refresh()
	if not bool(_main.call("modal_open")):
		if CampaignFormatScript.can_grab_focus(_first_load_btn):
			_first_load_btn.grab_focus()
		elif CampaignFormatScript.can_grab_focus(_new_btn):
			_new_btn.grab_focus()


func on_data_changed() -> void:
	if visible:
		refresh()


func refresh() -> void:
	var session: Node = _main.call("session")
	if session == null:
		_notice.text = "CampaignSession 未注册：冒险存档不可用；开发入口仍可跳转 Game.tscn。"
		_notice.visible = true
		_new_btn.disabled = true
		_refresh_btn.disabled = true
	else:
		_notice.visible = false
		_new_btn.disabled = false
		_refresh_btn.disabled = false
	_profiles = CampaignFormatScript.call_array(session, "list_profiles")
	_profiles.sort_custom(Callable(CampaignFormatScript, "saved_later_than"))
	_rebuild_list()


func _rebuild_list() -> void:
	_first_load_btn = null
	_recent_idx = _find_recent_index()
	CampaignFormatScript.detach_children(_save_list)
	var index := 0
	for entry: Variant in _profiles:
		var profile: Dictionary = entry
		_save_list.add_child(_make_save_card(profile, index))
		index += 1
	_empty_card.visible = _profiles.is_empty()


## 最近档索引：优先取 list_profiles 的 is_recent 标记（加载/创建时由
## CampaignSession 持久化）；无该字段时回落「按 saved_at 排序的首个可加载
## 档」即旧口径（首卡）。字段存在但全 false → -1 不显示。
func _find_recent_index() -> int:
	var has_field := false
	var index := 0
	for entry: Variant in _profiles:
		if entry is Dictionary:
			var profile: Dictionary = entry
			if profile.has("is_recent"):
				has_field = true
				if bool(profile.get("is_recent", false)):
					return index
		index += 1
	if has_field:
		return -1
	return 0 if not _profiles.is_empty() else -1


func _make_save_card(profile: Dictionary, index: int) -> PanelContainer:
	var session: Node = _main.call("session")
	var id := String(profile.get("id", ""))
	var loadable := bool(profile.get("loadable", true))
	var card: PanelContainer = PixelPanelScene.instantiate() as PanelContainer
	card.name = "SaveCard_%d" % index
	card.set("title", CampaignFormatScript.profile_name(profile))
	card.set(
		"description",
		"难度 %s · 金币 %d · 已通关 %d 关 · %s"
		% [
			CampaignFormatScript.difficulty_label(
				String(profile.get("difficulty", String(AIDifficultyScript.DEFAULT)))
			),
			CampaignFormatScript.as_int(profile.get("gold", 0), 0),
			CampaignFormatScript.as_int(profile.get("completed_count", 0), 0),
			CampaignFormatScript.format_saved_at(profile.get("saved_at", null)),
		]
	)

	var slot: Container = card.call("get_content_slot") as Container
	var body := PixelVBoxScript.new()
	slot.add_child(body)

	if index == _recent_idx and loadable:
		var latest: Label = UIFactoryScript.label(
			"最近游玩", ComponentThemeScript.FONT_CAPTION, UIThemeScript.ACCENT
		)
		latest.name = "LatestChip"
		body.add_child(latest)

	# notice 非空即提示（备份恢复等 loadable 档也会带提示）；不可加载档
	# 无 notice 时用兜底文案。
	var notice_text := CampaignFormatScript.as_text(profile.get("notice", ""), "")
	if not loadable or notice_text != "":
		var warn: Label = UIFactoryScript.label(
			"⚠ %s"
			% (notice_text if notice_text != "" else "该存档暂时无法加载"),
			ComponentThemeScript.FONT_CAPTION, UIThemeScript.ERROR
		)
		warn.name = "LoadWarn"
		body.add_child(warn)

	var row := PixelHBoxScript.new()
	body.add_child(row)

	var load_btn := _make_action_button("加载", 0, _on_load.bind(id))
	load_btn.name = "LoadBtn_%d" % index
	load_btn.disabled = not loadable
	if not load_btn.disabled:
		if index == _recent_idx:
			_first_load_btn = load_btn
		elif _first_load_btn == null:
			_first_load_btn = load_btn
	row.add_child(load_btn)

	var rename_btn := _make_action_button(
		"重命名", 1, _on_rename.bind(id, CampaignFormatScript.profile_name(profile))
	)
	rename_btn.name = "RenameBtn_%d" % index
	row.add_child(rename_btn)

	var delete_btn := _make_action_button(
		"删除", 2, _on_delete.bind(id, CampaignFormatScript.profile_name(profile))
	)
	delete_btn.name = "DeleteBtn_%d" % index
	row.add_child(delete_btn)
	return card


func _on_new() -> void:
	var modal: Control = _main.call(
		"open_modal",
		"新建冒险",
		"为新存档起一个名字，并选择冒险难度：",
		[
			{"text": "创建", "semantic": 0, "id": "confirm", "focus": true},
			{"text": "取消", "semantic": 1, "id": "cancel"},
		],
		true,
		"冒险名称",
		"",
		true,
		AIDifficultyScript.OPTIONS.duplicate(),
		String(AIDifficultyScript.DEFAULT)
	)
	modal.connect("chosen", Callable(self, "_on_new_chosen").bind(modal))


func _on_new_chosen(action_id: String, modal: Control) -> void:
	if action_id != "confirm":
		return
	var session: Node = _main.call("session")
	var profile_name := String(modal.call("get_input_text"))
	if profile_name == "":
		_main.call("open_error", "名字不能为空", "请输入至少一个字符的冒险名称。")
		return
	# 难度来自弹层互斥选择组；未选中（异常）回 normal 缺省。
	var difficulty := String(modal.call("get_selected_difficulty"))
	if difficulty == "":
		difficulty = String(AIDifficultyScript.DEFAULT)
	var created: Dictionary = CampaignFormatScript.call_dict(
		session, "create_profile", [profile_name, difficulty]
	)
	if not bool(created.get("ok", false)):
		_main.call(
			"open_error",
			"创建失败",
			"%s\n可稍后重试；问题持续请检查 CampaignSession 日志。" % CampaignFormatScript.as_text(created.get("error", ""), "未知错误")
		)
		return
	var new_id := String(created.get("id", ""))
	if new_id != "":
		var loaded: Dictionary = CampaignFormatScript.call_dict(session, "load_profile", [new_id])
		if not bool(loaded.get("ok", false)):
			_main.call(
				"open_error",
				"自动加载失败",
				"%s\n存档已创建，请从列表手动加载。" % CampaignFormatScript.as_text(loaded.get("error", ""), "未知错误")
			)
			refresh()
			return
	else:
		var current: Dictionary = CampaignFormatScript.call_raw_dict(session, "get_profile")
		if current.is_empty():
			_main.call(
				"open_error",
				"创建成功但未能进入",
				"会话未返回新档 id 且未自动加载；请刷新列表后手动加载。"
			)
			refresh()
			return
	_main.call("go_hub")


func _on_load(id: String) -> void:
	var session: Node = _main.call("session")
	var result: Dictionary = CampaignFormatScript.call_dict(session, "load_profile", [id])
	if not bool(result.get("ok", false)):
		_main.call(
			"open_error",
			"加载失败",
			"%s\n可点「刷新」重试，或加载其他存档继续冒险。" % CampaignFormatScript.as_text(result.get("error", ""), "未知错误")
		)
		return
	var notice := _collect_load_notice(id, result)
	if notice != "":
		var modal: Control = _main.call(
			"open_modal",
			"存档提示",
			notice,
			[{"text": "继续", "semantic": 0, "id": "continue", "focus": true}]
		)
		modal.connect("chosen", Callable(self, "_on_load_notice_chosen"))
		return
	_main.call("go_hub")


func _on_load_notice_chosen(_action_id: String) -> void:
	_main.call("go_hub")


## 加载成功后的玩家可见提示：合并加载结果、列表条目、当前档三处 notice
## （中断恢复/备份恢复等），去重、按出现顺序拼接。
func _collect_load_notice(id: String, result: Dictionary) -> String:
	var parts: Array[String] = []
	var candidates: Array = [
		result.get("notice", ""),
		_entry_notice(id),
		CampaignFormatScript.call_raw_dict(_main.call("session"), "get_profile").get("notice", ""),
	]
	for source: Variant in candidates:
		var text := CampaignFormatScript.as_text(source, "")
		if text != "" and not parts.has(text):
			parts.append(text)
	return "\n".join(parts)


func _entry_notice(id: String) -> String:
	for entry: Variant in _profiles:
		if entry is Dictionary and String((entry as Dictionary).get("id", "")) == id:
			return CampaignFormatScript.as_text((entry as Dictionary).get("notice", ""), "")
	return ""


func _on_rename(id: String, current_name: String) -> void:
	var modal: Control = _main.call(
		"open_modal",
		"重命名存档",
		"修改「%s」的名称：" % current_name,
		[
			{"text": "保存", "semantic": 0, "id": "confirm", "focus": true},
			{"text": "取消", "semantic": 1, "id": "cancel"},
		],
		true,
		"冒险名称",
		current_name
	)
	modal.connect("chosen", Callable(self, "_on_rename_chosen").bind(id, modal))


func _on_rename_chosen(action_id: String, id: String, modal: Control) -> void:
	if action_id != "confirm":
		return
	var session: Node = _main.call("session")
	var new_name := String(modal.call("get_input_text"))
	if new_name == "":
		_main.call("open_error", "名字不能为空", "请输入至少一个字符的名称。")
		return
	var result: Dictionary = CampaignFormatScript.call_dict(session, "rename_profile", [id, new_name])
	if not bool(result.get("ok", false)):
		_main.call(
			"open_error",
			"重命名失败",
			"%s\n列表将保持原样，可重试。" % CampaignFormatScript.as_text(result.get("error", ""), "未知错误")
		)
		return
	refresh()


func _on_delete(id: String, profile_name: String) -> void:
	var modal: Control = _main.call(
		"open_modal",
		"确认删除",
		"将删除存档「%s」。\n删除后无法恢复，确定吗？" % profile_name,
		[
			{"text": "确认删除", "semantic": 2, "id": "confirm", "focus": true},
			{"text": "取消", "semantic": 1, "id": "cancel"},
		]
	)
	modal.connect("chosen", Callable(self, "_on_delete_chosen").bind(id))


func _on_delete_chosen(action_id: String, id: String) -> void:
	if action_id != "confirm":
		return
	var session: Node = _main.call("session")
	var result: Dictionary = CampaignFormatScript.call_dict(session, "delete_profile", [id])
	if not bool(result.get("ok", false)):
		_main.call(
			"open_error",
			"删除失败",
			"%s\n存档未受影响，可重试。" % CampaignFormatScript.as_text(result.get("error", ""), "未知错误")
		)
		return
	refresh()


func _on_refresh() -> void:
	refresh()


func _on_dev_entry() -> void:
	# 旧开发入口：先消费启动配置，避免 startup.cfg 把 Game.tscn 再度重定向。
	var args: Node = get_tree().root.get_node_or_null("SceneArgs")
	if args != null:
		args.set("startup_consumed", true)
	get_tree().change_scene_to_file(DEV_ENTRY_SCENE)
