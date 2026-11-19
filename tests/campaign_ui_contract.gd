## tests/campaign_ui_contract.gd — 冒险 UI（Campaign.tscn 四屏）契约测试
##
## 只写不跑（由 lead 统一执行）：`godot --headless --path . --script res://tests/campaign_ui_contract.gd`
## 用桩 CampaignSession（同名 autoload 形态挂在 root 下）验证：
## ①源码静态规范（UIFactory 按钮 / 无直建控件 / 无绝对定位 / tscn 绑脚本）
## ②存档列表（排序/最近标记/不可加载警告/默认焦点）③模态焦点陷阱与还原
## ④重命名 ⑤新建→自动进基地 ⑥基地四数据+进度条 ⑦手动保存 ⑧胜利结算弹窗
## ⑨单位装备弹层（四槽装卸/拒绝明示/焦点还原）+物品详情 ⑩关卡列表/出征确认/battle_requested+桥接缺失兜底
## ⑪ESC 屏级返回 ⑫删除存档 ⑬切换存档 ⑭三档分辨率布局 ⑮无会话降级
## ⑳营地商店（入口/列表/限购/余额禁用/确认防重/changed 刷新/售罄/失败明示/
## ESC 返回/焦点还原）。ESC 用直接调 _unhandled_input(构造 InputEventAction)
## 保证确定性。
extends SceneTree

const CampaignScene = preload("res://scenes/Campaign.tscn")

const UI_FILES: Array[String] = [
	"res://scripts/scenes/campaign_main.gd",
	"res://scripts/scenes/campaign_hub.gd",
	"res://scripts/scenes/campaign_levels.gd",
	"res://scripts/scenes/campaign_shop.gd",
	"res://scripts/scenes/campaign_modal.gd",
	"res://scripts/scenes/campaign_equipment.gd",
	"res://scripts/scenes/campaign_save_select.gd",
]
## 这些文件必须含 UIFactory 按钮调用（main 只装配无按钮）。
const BUTTON_FILES: Array[String] = [
	"res://scripts/scenes/campaign_hub.gd",
	"res://scripts/scenes/campaign_levels.gd",
	"res://scripts/scenes/campaign_shop.gd",
	"res://scripts/scenes/campaign_modal.gd",
	"res://scripts/scenes/campaign_equipment.gd",
	"res://scripts/scenes/campaign_save_select.gd",
]
const FORBIDDEN_PATTERNS: Array[String] = [
	"Button.new(",
	"CheckButton.new(",
	"OptionButton.new(",
	"add_theme_stylebox_override(",
	".position = Vector2(",
	"components/pixel_button",
]

var fails: Array[String] = []
var battle_requests: Array = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if condition:
		print("  [pass] %s" % message)
	else:
		fails.append(message)
		printerr("  [FAIL] %s" % message)


func _fail(error: String) -> void:
	fails.append(error)
	printerr("  [FAIL] %s" % error)


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 800)

	# ① 源码静态规范。
	_static_source_checks()

	# 桩会话 + 场景实例。先摘除项目真实 autoload CampaignSession（--script
	# 模式 autoload 仍会启动；不摘会被自动改名导致 UI 取到真实服务）。
	# 测试进程即退，无需恢复。
	var existing_session := root.get_node_or_null("CampaignSession")
	if existing_session != null:
		root.remove_child(existing_session)
		existing_session.free()
	# 隔离全局按钮音效：断开 Sfx 的 SceneTree.node_added 自动挂接（保留
	# Sfx 本体，已挂 lambda 不失效）。headless 无音频输出，按钮密集 emit
	# 只会令 AudioStreamPlayback/AudioStreamMP3 在退出时泄漏（曾漏
	# 10 playback + sfx_ui_confirm.mp3）。收尾对称重连，避免 game_sfx
	# _exit_tree 的 disconnect 二次报错。
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null and node_added.is_connected(Callable(sfx, "_on_node_added")):
		node_added.disconnect(Callable(sfx, "_on_node_added"))
	var stub := StubSession.new()
	stub.name = "CampaignSession"
	root.add_child(stub)
	var campaign: Control = CampaignScene.instantiate() as Control
	root.add_child(campaign)
	campaign.battle_requested.connect(_on_battle_requested)
	await process_frame
	await process_frame

	# ② 存档列表：排序 B,A,C / 最近标记 / 警告 / 禁用 / 默认焦点。
	check(campaign.find_child("SaveSelect", true, false) != null, "02 进入选档屏")
	check(
		campaign.find_child("Hub", true, false) != null
			and campaign.find_child("Levels", true, false) != null,
		"02 三屏已装配"
	)
	var card_b: Control = campaign.find_child("SaveCard_0", true, false)
	var card_a: Control = campaign.find_child("SaveCard_1", true, false)
	var card_c: Control = campaign.find_child("SaveCard_2", true, false)
	check(card_b != null and card_a != null and card_c != null, "02 三张存档卡")
	check(
		String(card_b.get("title")).find("最近的档") >= 0
			and String(card_a.get("title")).find("旧档冒险") >= 0,
		"02 排序：saved_at 新→旧（B,A,C）"
	)
	check(card_b.find_child("LatestChip", true, false) != null, "02 is_recent 档带「最近游玩」")
	check(
		card_a.find_child("LatestChip", true, false) == null,
		"02 非最近档无「最近游玩」标记"
	)
	check(card_c.find_child("LoadWarn", true, false) != null, "02 不可加载卡带警告")
	var warn_a: Label = card_a.find_child("LoadWarn", true, false) as Label
	check(
		warn_a != null and warn_a.text.find("备份恢复") >= 0,
		"02 可加载档 notice 非空也警示（备份恢复）"
	)
	var load_c: Button = campaign.find_child("LoadBtn_2", true, false) as Button
	check(load_c != null and load_c.disabled, "02 损坏档「加载」禁用")
	var focus_owner: Control = root.gui_get_focus_owner()
	check(
		focus_owner != null and focus_owner.name == "LoadBtn_0",
		"02 默认焦点=最近可加载档的「加载」"
	)

	# ③ 模态焦点陷阱 + 关闭还原。
	var rename_btn: Button = campaign.find_child("RenameBtn_0", true, false) as Button
	rename_btn.pressed.emit()
	await process_frame
	var modal: Control = campaign.find_child("CampaignModal", true, false)
	check(modal != null, "03 重命名弹层打开")
	var load_b: Button = campaign.find_child("LoadBtn_0", true, false) as Button
	check(load_b.focus_mode == Control.FOCUS_NONE, "03 背景按钮焦点被禁用（陷阱）")
	focus_owner = root.gui_get_focus_owner()
	check(
		focus_owner != null and focus_owner.name == "ModalInput",
		"03 弹层默认焦点=输入框"
	)
	(modal.find_child("Action_cancel", true, false) as Button).pressed.emit()
	await process_frame
	check(load_b.focus_mode == Control.FOCUS_ALL, "03 关闭后背景焦点恢复")
	focus_owner = root.gui_get_focus_owner()
	check(
		focus_owner != null and focus_owner.name == "LoadBtn_0",
		"03 关闭后焦点还原到原控件"
	)

	# ③b 弹层存活期间释放被禁焦控件 → close 恢复循环必须判活跳过。
	# 回归：freed 对象连 `as Control` 都会报错（运行态实测
	# campaign_modal.gd close "Trying to cast a freed object"）。
	rename_btn.pressed.emit()
	await process_frame
	modal = campaign.find_child("CampaignModal", true, false)
	var victim: Button = campaign.find_child("LoadBtn_1", true, false) as Button
	check(
		victim != null and victim.focus_mode == Control.FOCUS_NONE,
		"03 弹层存活期背景控件处于陷阱中"
	)
	# free() 自动从父节点摘除；不再先 root.remove_child（victim 的父是
	# SaveCard_1 而非 root，父不匹配会打引擎 ERROR remove_child 断言）。
	victim.free()
	(modal.find_child("Action_cancel", true, false) as Button).pressed.emit()
	await process_frame
	check(
		campaign.find_child("CampaignModal", true, false) == null,
		"03 含已释放控件的陷阱关闭不崩且弹层移除"
	)
	check(load_b.focus_mode == Control.FOCUS_ALL, "03 其余背景控件焦点仍恢复")

	# ③c 原焦点已释放：必须能进入共享判活函数并完成 close/chosen。
	var previous_focus := Control.new()
	previous_focus.focus_mode = Control.FOCUS_ALL
	root.add_child(previous_focus)
	previous_focus.grab_focus()
	rename_btn.pressed.emit()
	await process_frame
	modal = campaign.find_child("CampaignModal", true, false)
	check(modal.get("_previous_focus") == previous_focus, "03 弹窗记录打开前焦点")
	previous_focus.free()
	(modal.find_child("Action_cancel", true, false) as Button).pressed.emit()
	await process_frame
	check(campaign.find_child("CampaignModal", true, false) == null, "03 原焦点已释放仍完成弹窗关闭")
	check(not bool(campaign.call("modal_open")), "03 原焦点已释放仍清除模态状态")

	# ④ 重命名流程。
	rename_btn.pressed.emit()
	await process_frame
	modal = campaign.find_child("CampaignModal", true, false)
	var input: LineEdit = modal.find_child("ModalInput", true, false) as LineEdit
	input.text = "新档名"
	(modal.find_child("Action_confirm", true, false) as Button).pressed.emit()
	await process_frame
	check(stub.profiles["b"]["name"] == "新档名", "04 rename_profile 已调用")
	card_b = campaign.find_child("SaveCard_0", true, false)
	check(String(card_b.get("title")).find("新档名") >= 0, "04 列表标题已刷新")

	# ⑤ 新建存档 → 自动加载 → 进基地。
	(campaign.find_child("NewBtn", true, false) as Button).pressed.emit()
	await process_frame
	modal = campaign.find_child("CampaignModal", true, false)
	# ⑤a 新建弹层难度组：四档齐全、默认 normal 选中、ButtonGroup 互斥切换。
	var diff_ids := ["novice", "normal", "hard", "nightmare"]
	for did in diff_ids:
		check(
			modal.find_child("Difficulty_%s" % did, true, false) != null,
			"05 新建弹层含难度档按钮 %s" % did
		)
	var diff_normal: Button = modal.find_child("Difficulty_normal", true, false) as Button
	check(diff_normal.button_pressed, "05 难度默认选中 normal")
	var diff_hard: Button = modal.find_child("Difficulty_hard", true, false) as Button
	diff_hard.button_pressed = true
	check(diff_hard.button_pressed and not diff_normal.button_pressed, "05 难度组互斥切换到 hard")
	input = modal.find_child("ModalInput", true, false) as LineEdit
	input.text = "测试新档"
	(modal.find_child("Action_confirm", true, false) as Button).pressed.emit()
	await process_frame
	check(stub.current.length() > 0, "05 新档已加载为当前档")
	check(stub.last_created_difficulty == "hard", "05 新建传值 difficulty=hard")
	var hub: Control = campaign.find_child("Hub", true, false)
	check(hub.visible, "05 新建后进入基地")
	var gold_label: Label = campaign.find_child("GoldLabel", true, false) as Label
	check(gold_label.text.contains("困难"), "05 基地头部显示所选难度（困难）")
	var profile_title: Label = campaign.find_child("ProfileTitle", true, false) as Label
	check(profile_title.text == "测试新档", "05 基地标题=新档名")
	check(campaign.find_child("RosterEmpty", true, false) != null, "05 空队伍有占位提示")

	# ⑥/⑬ 切换存档 → 加载 B（04 已把 B 改名「新档名」）→ 四数据。
	(campaign.find_child("SwitchProfileBtn", true, false) as Button).pressed.emit()
	await process_frame
	check(campaign.find_child("SaveSelect", true, false).visible, "13 切换存档回到列表")
	# 新建 p0 后排序漂移：按卡 title 定位 B 的加载按钮，禁止依赖固定下标。
	var load_b_by_title: Button = _card_button_by_title(campaign, "新档名", "LoadBtn_%d")
	check(load_b_by_title != null and not load_b_by_title.disabled, "06 按标题定位 B 加载按钮")
	load_b_by_title.pressed.emit()
	await process_frame
	check(hub.visible, "06 加载 B 进入基地")
	var gold_value: Label = campaign.find_child("GoldValue", true, false) as Label
	check(gold_value.text == "220", "06 金币=220")
	# B 为手造旧档（无 difficulty 键）→ 头部回退显示默认普通。
	gold_label = campaign.find_child("GoldLabel", true, false) as Label
	check(gold_label.text.contains("普通"), "06 旧档无难度键回退普通")
	var progress_label: Label = campaign.find_child("ProgressLabel", true, false) as Label
	check(progress_label.text == "已通关 2 / 6", "06 进度文本 2 / 6")
	var progress_fill: Range = campaign.find_child("ProgressFill", true, false) as Range
	check(
		is_equal_approx(float(progress_fill.value), 2.0)
			and is_equal_approx(float(progress_fill.max_value), 6.0),
		"06 进度条 value=2 max=6"
	)
	check(campaign.find_child("UnitRow_0", true, false) != null, "06 队伍行 0")
	check(campaign.find_child("UnitRow_1", true, false) != null, "06 队伍行 1")
	var unit_row_0: Button = campaign.find_child("UnitRow_0", true, false) as Button
	check(unit_row_0.text.contains("EXP 40/140"), "06 队伍行显示 EXP 当前/阈值（40/140）")
	var unit_row_1: Button = campaign.find_child("UnitRow_1", true, false) as Button
	check(not unit_row_1.text.contains("EXP"), "06 无 exp 旧形状单位不显示 EXP（向后兼容）")
	check(campaign.find_child("ItemRow_0", true, false) != null, "06 物品行 0")
	check(campaign.find_child("RosterEmpty", true, false) == null, "06 非空队伍无占位提示")
	var gold_caption: Label = campaign.find_child("GoldCaption", true, false) as Label
	check(gold_caption.text == "首胜 200 · 重复通关 50", "06 金币说明=按关卡数据计算")

	# ⑦ 手动保存。
	(campaign.find_child("SaveNowBtn", true, false) as Button).pressed.emit()
	await process_frame
	check(stub.saved_count == 1, "07 save_current 已调用")
	modal = campaign.find_child("CampaignModal", true, false)
	check(
		modal != null and String(modal.find_child("ModalPanel", true, false).get("title")) == "已保存",
		"07 保存成功弹层"
	)
	(modal.find_child("Action_close", true, false) as Button).pressed.emit()
	await process_frame

	# ⑧ 结算：win 重复通关路径（B 已通关 level_0 → +50）。
	var settled: Dictionary = stub.settle_battle("tok_win", &"win", {})
	check(bool(settled.get("ok", false)), "08 settle ok")
	campaign.call("go_hub")
	await process_frame
	modal = campaign.find_child("CampaignModal", true, false)
	check(
		modal != null and String(modal.find_child("ModalPanel", true, false).get("title")) == "胜利！",
		"08 胜利结算弹层"
	)
	var message: Label = modal.find_child("ModalMessage", true, false) as Label
	check(message.text.find("获得金币：50") >= 0, "08 重复胜利金币=50")
	check(message.text.find("首次通关") < 0, "08 非首胜不显示首通标记")
	check(message.text.find("获得物品") < 0, "08 重复胜利物品空整行省略（不显示占位）")
	check(message.text.find("升级：剑士队长 2→3") >= 0, "08 胜利弹层含升级行")
	check(
		message.text.find("力+1 速+1") >= 0,
		"08 升级行按固定属性序输出（反序输入仍力→速）"
	)
	(modal.find_child("Action_continue", true, false) as Button).pressed.emit()
	await process_frame
	check(stub.get_last_result().is_empty(), "08 结算展示后已 clear")
	gold_value = campaign.find_child("GoldValue", true, false) as Label
	check(gold_value.text == "270", "08 金币入账 220+50")

	# ⑨ 单位装备弹层（四槽装卸/拒绝明示/焦点还原）+ 物品详情弹窗。
	(campaign.find_child("UnitRow_0", true, false) as Button).pressed.emit()
	await process_frame
	var equip_panel: Control = campaign.find_child("CampaignEquipment", true, false)
	check(equip_panel != null, "09 角色行打开装备弹层")
	check(
		String(equip_panel.find_child("EquipPanel", true, false).get("title")).find("剑士队长") >= 0,
		"09 弹层标题含单位名"
	)
	check(
		(equip_panel.find_child("EquipSummary", true, false) as Label).text.find("剑士") >= 0,
		"09 概要行含职业名（swordsman→剑士）"
	)
	for slot_label: String in ["武器", "盾牌", "法杖", "秘宝"]:
		check(_panel_has_text(equip_panel, slot_label), "09 四槽标签含 %s" % slot_label)
	var shield_row: Label = equip_panel.find_child("SlotTitle_shield", true, false) as Label
	check(shield_row.text.find("（空）") >= 0, "09 初始盾槽为空")
	# 装上皮盾（通用盾）：changed 驱动重建 → 槽行/加成/条目状态全量更新。
	(equip_panel.find_child("Equip_leatherShield", true, false) as Button).pressed.emit()
	await process_frame
	shield_row = equip_panel.find_child("SlotTitle_shield", true, false) as Label
	check(shield_row.text.find("皮盾") >= 0 and shield_row.text.find("防+1") >= 0, "09 装备后槽行显示皮盾（防+1）")
	check(_panel_has_text(equip_panel, "装备加成："), "09 加成行存在")
	var equipped_btn: Button = equip_panel.find_child("Equip_leatherShield", true, false) as Button
	check(equipped_btn.disabled and equipped_btn.text == "已装备", "09 已装备条目置灰「已装备」")
	check((equip_panel.find_child("EquipError", true, false) as Label).visible == false, "09 成功后无错误")
	# 卸下：槽行回空、加成清零，焦点按约定回到该件的「装备」键。
	(equip_panel.find_child("Unequip_shield", true, false) as Button).pressed.emit()
	await process_frame
	shield_row = equip_panel.find_child("SlotTitle_shield", true, false) as Label
	check(shield_row.text.find("（空）") >= 0, "09 卸下后槽行回空")
	check(_panel_has_text(equip_panel, "装备加成：无"), "09 卸下后加成为无")
	check(
		root.gui_get_focus_owner() != null
			and root.gui_get_focus_owner().name == "Equip_leatherShield",
		"09 卸下后焦点回该件装备键"
	)
	# 拒绝路径（会话级）：出征挂起时 session 拒绝装卸 → 内联错误、数据不变。
	# （职业不符条目不进 catalog_for 清单——可装性过滤在 UI 列表层已生效，
	# 见 equipment_integration_contract 的核心判定断言。）
	stub.attempt = "battle_1"
	(equip_panel.find_child("Equip_leatherShield", true, false) as Button).pressed.emit()
	await process_frame
	var equip_error: Label = equip_panel.find_child("EquipError", true, false) as Label
	check(equip_error.visible, "09 拒绝时错误行可见")
	check(equip_error.text.find("战斗进行中") >= 0, "09 拒绝信息透传会话原文")
	check(
		(equip_panel.find_child("SlotTitle_shield", true, false) as Label).text.find("（空）") >= 0,
		"09 拒绝后槽位不变"
	)
	stub.attempt = ""
	# 焦点陷阱：焦点只能落在弹层内部控件。
	var trapped: Control = root.gui_get_focus_owner()
	check(trapped != null and equip_panel.is_ancestor_of(trapped), "09 焦点被困弹层内")
	# 关闭（点关闭键）：弹层移除、焦点还原 Hub 保存按钮。
	(equip_panel.find_child("EquipCloseBtn", true, false) as Button).pressed.emit()
	await process_frame
	check(campaign.find_child("CampaignEquipment", true, false) == null, "09 关闭后弹层移除")
	var equip_restored: Control = root.gui_get_focus_owner()
	check(equip_restored != null and equip_restored.name == "SaveNowBtn", "09 关闭后焦点还原 Hub")
	# 真实角色行持有焦点后打开弹层；背景刷新释放原行，复现关闭时报 freed 类型错误。
	var previous_unit_row: Button = campaign.find_child("UnitRow_0", true, false) as Button
	previous_unit_row.grab_focus()
	previous_unit_row.pressed.emit()
	await process_frame
	equip_panel = campaign.find_child("CampaignEquipment", true, false)
	check(equip_panel.get("_previous_focus") == previous_unit_row, "09 装备弹层记录角色行焦点")
	hub.call("refresh")
	await process_frame
	await process_frame
	check(not is_instance_valid(previous_unit_row), "09 背景刷新已释放原焦点角色行")
	(equip_panel.find_child("EquipCloseBtn", true, false) as Button).pressed.emit()
	await process_frame
	check(campaign.find_child("CampaignEquipment", true, false) == null, "09 原焦点已释放仍完成装备弹层关闭")
	check(not bool(campaign.call("modal_open")), "09 原焦点已释放仍清除装备模态状态")
	(campaign.find_child("ItemRow_0", true, false) as Button).pressed.emit()
	await process_frame
	modal = campaign.find_child("CampaignModal", true, false)
	message = modal.find_child("ModalMessage", true, false) as Label
	check(message.text.find("治疗药水") >= 0, "09 物品详情含名称")
	(modal.find_child("Action_close", true, false) as Button).pressed.emit()
	await process_frame

	# ⑳ 营地商店：入口/列表/限购/余额禁用/确认防重/购买刷新/售罄/失败明示/
	# ESC 返回。预备金 400 覆盖余额不足（500>400）、限购递减（2→1→0）与
	# 不限购路径；金币状态为测试预备值，不影响后续组断言。
	stub.profiles["b"]["gold"] = 400
	(campaign.find_child("ShopBtn", true, false) as Button).pressed.emit()
	await process_frame
	var shop_screen: Control = campaign.find_child("Shop", true, false)
	check(shop_screen != null and shop_screen.visible, "20 Hub ShopBtn 进入营地商店")
	check(campaign.find_child("Levels", true, false).visible == false, "20 进入商店后地图屏隐藏")
	var shop_gold: Label = shop_screen.find_child("GoldLabel", true, false) as Label
	check(shop_gold.text == "金币 400", "20 商店金币=400")
	for i: int in 3:
		check(shop_screen.find_child("ItemRow_%d" % i, true, false) != null, "20 商品行 %d" % i)
	var meta_0: Label = shop_screen.find_child("ItemMeta_0", true, false) as Label
	check(
		meta_0.text.find("80 金币") >= 0 and meta_0.text.find("不限购") >= 0,
		"20 不限购商品文案（价格+不限购）"
	)
	var meta_1: Label = shop_screen.find_child("ItemMeta_1", true, false) as Label
	check(
		meta_1.text.find("120 金币") >= 0 and meta_1.text.find("本周期剩 2") >= 0,
		"20 限购商品文案（价格+剩余额度）"
	)
	var buy_0: Button = shop_screen.find_child("BuyBtn_0", true, false) as Button
	var buy_1: Button = shop_screen.find_child("BuyBtn_1", true, false) as Button
	var buy_2: Button = shop_screen.find_child("BuyBtn_2", true, false) as Button
	check(buy_0 != null and not buy_0.disabled, "20 不限购商品可买")
	check(buy_1 != null and not buy_1.disabled, "20 限购余量内可买")
	check(buy_2 != null and buy_2.disabled, "20 余额不足商品禁用")
	var shop_focus: Control = root.gui_get_focus_owner()
	check(shop_focus != null and shop_focus.name == "BuyBtn_0", "20 默认焦点=首个可购买按钮")
	# 确认弹窗（单层）+ 防重：弹窗开着再点其他入口不叠加弹层。
	buy_1.pressed.emit()
	await process_frame
	modal = campaign.find_child("CampaignModal", true, false)
	check(
		modal != null
			and String(modal.find_child("ModalPanel", true, false).get("title")) == "购买确认",
		"20 购买确认弹层（单层）"
	)
	var buy_message: Label = modal.find_child("ModalMessage", true, false) as Label
	check(
		buy_message.text.find("法力药水 ×1") >= 0 and buy_message.text.find("120 金币") >= 0,
		"20 确认文案含商品与价格（买 1）"
	)
	buy_0.pressed.emit()
	await process_frame
	check(
		campaign.find_children("CampaignModal", "", true, false).size() == 1,
		"20 确认期间防重（不叠加弹层）"
	)
	(modal.find_child("Action_confirm", true, false) as Button).pressed.emit()
	await process_frame
	check(stub.buy_calls.size() == 1, "20 buy_item 恰好调用一次")
	check(int(stub.profiles["b"]["gold"]) == 280, "20 购买入账 400-120")
	check(shop_gold.text == "金币 280", "20 金币标签随 changed 刷新")
	var meta_1_after: Label = shop_screen.find_child("ItemMeta_1", true, false) as Label
	check(meta_1_after.text.find("本周期剩 1") >= 0, "20 限购额度递减 2→1")
	var restored: Control = root.gui_get_focus_owner()
	check(
		restored != null and restored.name == "BuyBtn_1",
		"20 购买后焦点恢复到刚购商品行（refresh 重建不悬空）"
	)
	# 限购售罄：mpPotion 剩 1 → 买 1 → 剩 0 禁用。
	(shop_screen.find_child("BuyBtn_1", true, false) as Button).pressed.emit()
	await process_frame
	modal = campaign.find_child("CampaignModal", true, false)
	(modal.find_child("Action_confirm", true, false) as Button).pressed.emit()
	await process_frame
	check(int(stub.profiles["b"]["gold"]) == 160, "20 第二次购买入账 280-120")
	var buy_1_after: Button = shop_screen.find_child("BuyBtn_1", true, false) as Button
	check(buy_1_after != null and buy_1_after.disabled, "20 售罄后按钮禁用")
	# 不限购购买 + 库存入账。
	(shop_screen.find_child("BuyBtn_0", true, false) as Button).pressed.emit()
	await process_frame
	modal = campaign.find_child("CampaignModal", true, false)
	(modal.find_child("Action_confirm", true, false) as Button).pressed.emit()
	await process_frame
	check(int(stub.profiles["b"]["gold"]) == 80, "20 不限购入账 160-80")
	var inventory: Array = stub.profiles["b"]["inventory"]
	check(
		inventory.size() == 5
			and String((inventory[2] as Dictionary).get("id", "")) == "mpPotion"
			and String((inventory[4] as Dictionary).get("id", "")) == "hpPotion",
		"20 三次购买各入库存一条（末条=hpPotion）"
	)
	check(stub.buy_calls.size() == 3, "20 buy_calls 累计 3 次")
	# 失败明示：确认回调直调模拟余额拒绝（售罄/余额不足按钮已禁用，无法自然触发）。
	shop_screen._on_buy_chosen("confirm", "shuriken")
	await process_frame
	var shop_notice: Label = shop_screen.find_child("ShopNotice", true, false) as Label
	check(
		shop_notice != null and shop_notice.visible and shop_notice.text.find("金币不足") >= 0,
		"20 购买失败在页面明示"
	)
	check(stub.buy_calls.size() == 4, "20 失败路径同样记录 buy 调用")
	check(int(stub.profiles["b"]["gold"]) == 80, "20 失败不入账")
	# ESC：商店→基地（屏级返回链新增 shop→hub 分支）。
	var shop_cancel := InputEventAction.new()
	shop_cancel.action = "ui_cancel"
	shop_cancel.pressed = true
	campaign._unhandled_input(shop_cancel)
	await process_frame
	check(campaign.find_child("Hub", true, false).visible, "20 ESC：商店→基地")

	# ⑩ 关卡列表 + 出征确认 + 桥接。
	(campaign.find_child("MapBtn", true, false) as Button).pressed.emit()
	await process_frame
	check(campaign.find_child("Levels", true, false).visible, "10 进入世界地图")
	for i: int in 6:
		check(campaign.find_child("LevelCard_%d" % i, true, false) != null, "10 关卡卡 %d" % i)
	var status_0: Label = campaign.find_child("StatusLabel_0", true, false) as Label
	check(status_0.text.find("已通关") >= 0, "10 level_0 状态=已通关")
	var status_2: Label = campaign.find_child("StatusLabel_2", true, false) as Label
	check(status_2.text == "可挑战", "10 level_2 状态=可挑战")
	var status_3: Label = campaign.find_child("StatusLabel_3", true, false) as Label
	check(status_3.text.find("未解锁") >= 0, "10 level_3 状态=未解锁")
	# 奖励前置展示实际数值：已通关卡只展示重复奖励；未通关卡展示首胜+重复。
	var reward_0: Label = campaign.find_child("RewardLabel_0", true, false) as Label
	check(reward_0.text == "奖励：50 金币 · 无", "10 已通关卡奖励=重复胜 50/无物品")
	check(campaign.find_child("RepeatLabel_0", true, false) == null, "10 已通关卡无重复提示行")
	var reward_2: Label = campaign.find_child("RewardLabel_2", true, false) as Label
	check(
		reward_2.text.find("首胜") >= 0 and reward_2.text.find("200") >= 0,
		"10 未通关卡奖励=首胜 200+道具"
	)
	var repeat_2: Label = campaign.find_child("RepeatLabel_2", true, false) as Label
	check(
		repeat_2 != null and repeat_2.text.find("重复通关：50") >= 0,
		"10 未通关卡附重复通关行"
	)
	for i: int in [0, 1, 2]:
		var enabled_btn: Button = campaign.find_child("ChallengeBtn_%d" % i, true, false) as Button
		check(enabled_btn != null and not enabled_btn.disabled, "10 ChallengeBtn_%d 可用" % i)
	for i: int in [3, 4, 5]:
		var locked_btn: Button = campaign.find_child("ChallengeBtn_%d" % i, true, false) as Button
		check(locked_btn != null and locked_btn.disabled, "10 ChallengeBtn_%d 锁定" % i)
	(campaign.find_child("ChallengeBtn_2", true, false) as Button).pressed.emit()
	await process_frame
	modal = campaign.find_child("CampaignModal", true, false)
	check(modal != null, "10 出征确认弹层")
	var confirm_message: Label = modal.find_child("ModalMessage", true, false) as Label
	check(
		confirm_message.text.find("首胜奖励：200 金币") >= 0
			and confirm_message.text.find("重复通关：50 金币") >= 0,
		"10 确认弹窗前置展示两套实际奖励"
	)
	(modal.find_child("Action_go", true, false) as Button).pressed.emit()
	await process_frame
	await process_frame
	check(battle_requests.size() == 1, "10 battle_requested 恰好一次")
	# 桩 prepare_battle 返回失败：桥接应把具体失败带回并弹「进入战斗失败」。
	# 确认弹层在 close() 的 chosen 处理器内同步开新弹层，旧弹层同帧才
	# queue_free——find_child 可能命中残留确认弹层。这里按面板标题精确定位。
	var error_modal := _modal_by_title(campaign, "进入战斗失败")
	check(error_modal != null, "10 出征失败兜底弹层")
	if error_modal != null:
		check(stub.prepare_calls.size() == 1, "10 enter_battle 已尝试 prepare")
		(error_modal.find_child("Action_close", true, false) as Button).pressed.emit()
		await process_frame
	# 桥接失败路径可能对桩 settle(abandon) 写入 last_result：清掉避免污染 ESC 断言。
	stub.clear_last_result()
	# ESC 前保证弹层清空（关闭是 queue_free，需等帧；残留会令 ESC 直接 return）。
	for leftover: Node in campaign.find_children("CampaignModal", "", true, false):
		leftover.queue_free()
	await process_frame

	# ⑪ ESC 屏级返回（直接调 _unhandled_input，输入事件确定）。
	var cancel_event := InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	campaign._unhandled_input(cancel_event)
	await process_frame
	check(hub.visible, "11 ESC：世界地图→基地")
	campaign._unhandled_input(cancel_event)
	await process_frame
	check(campaign.find_child("SaveSelect", true, false).visible, "11 ESC：基地→存档列表")
	check(stub.current == "", "11 ESC 回列表=退出当前档")

	# ⑯ 加载成功 notice（备份恢复档 a）：弹「存档提示」→ 继续 → 基地。
	# 按卡 title 定位（新建 p0 后排序已漂移，固定下标不可靠）。
	var load_a: Button = _card_button_by_title(campaign, "旧档冒险", "LoadBtn_%d")
	check(load_a != null and not load_a.disabled, "16 备份恢复档可加载")
	load_a.pressed.emit()
	await process_frame
	modal = campaign.find_child("CampaignModal", true, false)
	check(modal != null, "16 加载成功弹「存档提示」")
	var notice_message: Label = modal.find_child("ModalMessage", true, false) as Label
	check(
		notice_message != null and notice_message.text.find("备份恢复") >= 0,
		"16 提示内容含备份恢复文案"
	)
	check(
		String(modal.find_child("ModalPanel", true, false).get("title")) == "存档提示",
		"16 弹层标题=存档提示"
	)
	check(not campaign.find_child("Hub", true, false).visible, "16 确认前不进基地")
	(modal.find_child("Action_continue", true, false) as Button).pressed.emit()
	await process_frame
	check(hub.visible, "16 继续后进入基地")
	var profile_title_a: Label = campaign.find_child("ProfileTitle", true, false) as Label
	check(profile_title_a.text == "旧档冒险", "16 已加载旧档冒险")

	# ⑰ 删除旧档 a（按卡 title 定位删除按钮；删除后列表仅剩 p0/B/C）。
	campaign.call("go_save_select")
	await process_frame
	var delete_a: Button = _card_button_by_title(campaign, "旧档冒险", "DeleteBtn_%d")
	check(delete_a != null, "17 按标题定位旧档删除按钮")
	delete_a.pressed.emit()
	await process_frame
	modal = campaign.find_child("CampaignModal", true, false)
	check(modal != null, "17 删除确认弹层")
	(modal.find_child("Action_confirm", true, false) as Button).pressed.emit()
	await process_frame
	check(not stub.profiles.has("a"), "17 delete_profile 已执行")
	check(
		_card_button_by_title(campaign, "旧档冒险", "LoadBtn_%d") == null,
		"17 旧档卡已从列表消失"
	)

	# ⑱ 重载 B（新档名）→ 三档分辨率布局（标题/进度条/列布局不塌陷）。
	var reload_b: Button = _card_button_by_title(campaign, "新档名", "LoadBtn_%d")
	check(reload_b != null and not reload_b.disabled, "18 按标题定位 B 加载按钮")
	reload_b.pressed.emit()
	await process_frame
	check(hub.visible, "18 重载 B 进入基地")
	var sizes: Array = [[1024, 640], [1280, 800], [1920, 1080]]
	for size_cfg: Variant in sizes:
		var w := int(size_cfg[0])
		var h := int(size_cfg[1])
		root.size = Vector2i(w, h)
		await process_frame
		await process_frame
		check(
			absf(campaign.size.x - float(w)) <= 1.0 and absf(campaign.size.y - float(h)) <= 1.0,
			"18 %dx%d 根尺寸=视口" % [w, h]
		)
		var progress_panel: Control = campaign.find_child("ProgressPanel", true, false)
		var panel_rect := progress_panel.get_global_rect()
		check(
			panel_rect.end.x <= float(w) + 1.0 and panel_rect.size.x > 0.0,
			"18 %dx%d 进度卡不越界" % [w, h]
		)
		var gold_panel: Control = campaign.find_child("GoldPanel", true, false)
		check(gold_panel.get_global_rect().end.x <= float(w) + 1.0, "18 %dx%d 金币卡不越界" % [w, h])
	# 存档列表横向滚动禁用（PixelScroll 约束）。
	campaign.call("go_save_select")
	await process_frame
	var list_scroll: ScrollContainer = campaign.find_child("ListScroll", true, false) as ScrollContainer
	check(not list_scroll.get_h_scroll_bar().visible, "18 存档列表无横向滚动条")

	# ⑲ 零高度回归：三分辨率逐层断言（根=视口、Screens=根、每屏= Screens、
	# PageMargin=屏——隐藏屏锚点布局同样成立），各列表 viewport 正高度；
	# Levels 首卡无需滚动可见、滚至底部末卡进入视口（六关实际可访问）。
	var screens: Control = campaign.find_child("Screens", true, false)
	var screen_names: Array = ["SaveSelect", "Hub", "Levels", "Shop"]
	for size_cfg: Variant in sizes:
		var w := int(size_cfg[0])
		var h := int(size_cfg[1])
		root.size = Vector2i(w, h)
		await process_frame
		await process_frame
		check(
			absf(campaign.size.x - float(w)) <= 1.0 and absf(campaign.size.y - float(h)) <= 1.0,
			"19 %dx%d 根尺寸=视口" % [w, h]
		)
		check(
			screens != null
				and absf(screens.size.x - campaign.size.x) <= 1.0
				and absf(screens.size.y - campaign.size.y) <= 1.0,
			"19 %dx%d Screens 铺满根" % [w, h]
		)
		for screen_name: String in screen_names:
			var screen: Control = campaign.find_child(screen_name, true, false)
			check(
				screen != null
					and absf(screen.size.x - screens.size.x) <= 1.0
					and absf(screen.size.y - screens.size.y) <= 1.0,
				"19 %dx%d %s 铺满 Screens" % [w, h, screen_name]
			)
			var page_margin: Control = (
				screen.find_child("PageMargin", true, false) if screen != null else null
			)
			check(
				page_margin != null
					and absf(page_margin.size.x - screen.size.x) <= 1.0
					and absf(page_margin.size.y - screen.size.y) <= 1.0,
				"19 %dx%d %s PageMargin 铺满屏" % [w, h, screen_name]
			)
		check(list_scroll != null and list_scroll.size.y > 0.0, "19 %dx%d 存档列表高度>0" % [w, h])
		campaign.call("go_hub")
		await process_frame
		for scroll_name: String in ["RosterScroll", "InventoryScroll"]:
			var panel_scroll: ScrollContainer = (
				campaign.find_child(scroll_name, true, false) as ScrollContainer
			)
			check(
				panel_scroll != null and panel_scroll.size.y > 0.0,
				"19 %dx%d Hub %s 高度>0" % [w, h, scroll_name]
			)
		campaign.call("go_levels")
		await process_frame
		var level_scroll: ScrollContainer = campaign.find_child("LevelScroll", true, false) as ScrollContainer
		check(level_scroll != null and level_scroll.size.y > 0.0, "19 %dx%d 关卡滚动区高度>0" % [w, h])
		# on_shown 抓焦会让 follow_focus 滚到首个可挑战卡；显式归零后断言
		# 顶部状态，避免依赖焦点时序。
		level_scroll.scroll_vertical = 0.0
		await process_frame
		var first_card: Control = campaign.find_child("LevelCard_0", true, false)
		check(
			first_card != null and _v_overlaps(first_card, level_scroll),
			"19 %dx%d 首卡无需滚动即可见" % [w, h]
		)
		level_scroll.scroll_vertical = level_scroll.get_v_scroll_bar().max_value
		await process_frame
		var last_card: Control = campaign.find_child("LevelCard_5", true, false)
		check(
			last_card != null and _v_overlaps(last_card, level_scroll),
			"19 %dx%d 滚动后末卡进入视口" % [w, h]
		)
		campaign.call("go_shop")
		await process_frame
		var shop_scroll_19: ScrollContainer = (
			campaign.find_child("ShopScroll", true, false) as ScrollContainer
		)
		check(
			shop_scroll_19 != null and shop_scroll_19.size.y > 0.0,
			"19 %dx%d 商店滚动区高度>0" % [w, h]
		)
	# 还原到与旧流程一致的屏态，再进入无会话降级检查。
	campaign.call("go_save_select")
	await process_frame

	# ⑮ 无会话降级（二次实例化）。
	campaign.queue_free()
	stub.queue_free()
	await process_frame
	await process_frame
	var campaign2: Control = CampaignScene.instantiate() as Control
	root.add_child(campaign2)
	await process_frame
	await process_frame
	var notice: Label = campaign2.find_child("SessionNotice", true, false) as Label
	check(notice != null and notice.visible, "15 无会话：SessionNotice 可见")
	var new_btn2: Button = campaign2.find_child("NewBtn", true, false) as Button
	check(new_btn2 != null and new_btn2.disabled, "15 无会话：新建禁用")
	var dev_btn2: Button = campaign2.find_child("DevEntryBtn", true, false) as Button
	check(dev_btn2 != null and not dev_btn2.disabled, "15 无会话：开发入口仍可用")
	check(campaign2.has_signal("battle_requested"), "15 battle_requested 信号存在")
	campaign2.queue_free()
	# quit 前让 queue_free 的延迟删除真正执行，否则 ObjectDB 报泄漏。
	await process_frame
	await process_frame
	# 与开头的断开对称：恢复 Sfx 挂接（此后无节点入树，不会发声；
	# game_sfx._exit_tree 的 disconnect 由此保持有效连接可拆）。
	if sfx != null and not node_added.is_connected(Callable(sfx, "_on_node_added")):
		node_added.connect(Callable(sfx, "_on_node_added"))

	if fails.is_empty():
		print("campaign_ui_contract: ALL PASS")
		quit(0)
	else:
		printerr("campaign_ui_contract: %d FAIL" % fails.size())
		quit(1)


func _on_battle_requested(level_id: String) -> void:
	battle_requests.append(level_id)


## 按存档卡 PixelPanel title 子串定位卡内按钮（列表排序会因新建/重命名/
## 删除漂移，测试禁止依赖固定下标）。button_pattern 形如 "LoadBtn_%d"。
func _card_button_by_title(campaign: Control, title_sub: String, button_pattern: String) -> Button:
	for i: int in 12:
		var card: Control = campaign.find_child("SaveCard_%d" % i, true, false)
		if card == null:
			continue
		if String(card.get("title")).find(title_sub) < 0:
			continue
		return card.find_child(button_pattern % i, true, false) as Button
	return null


## 按弹层面板标题精确定位 CampaignModal（链式弹层时同帧内可能同时存在
## 「旧弹层（已 queue_free 未删除）+ 新弹层」，按名字 find 会命中旧的）。
func _modal_by_title(campaign: Control, title: String) -> Control:
	for node: Node in campaign.find_children("CampaignModal", "", true, false):
		var panel: Control = node.find_child("ModalPanel", true, false)
		if panel != null and String(panel.get("title")) == title:
			return node as Control
	return null


## control 的全局矩形在 viewport（滚动区）纵向可视范围内（重叠超过 1px，
## 避开 Rect2.intersects 的贴边歧义）。
func _v_overlaps(control: Control, viewport: Control) -> bool:
	if control == null or viewport == null:
		return false
	var a := control.get_global_rect()
	var b := viewport.get_global_rect()
	return a.position.y < b.end.y - 1.0 and a.end.y > b.position.y + 1.0


## 弹层内任意 Label 是否含指定文案（槽行/加成行等多标签聚合断言用）。
func _panel_has_text(panel: Control, needle: String) -> bool:
	for node: Variant in panel.find_children("*", "Label", true, false):
		if (node as Label).text.find(needle) >= 0:
			return true
	return false


func _static_source_checks() -> void:
	for path: String in UI_FILES:
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			_fail("S1 读取失败：%s" % path)
			continue
		for pattern: String in FORBIDDEN_PATTERNS:
			if text.find(pattern) >= 0:
				_fail("S1 %s 含禁用模式 %s" % [path, pattern])
		if path in BUTTON_FILES and text.find("UIFactoryScript.button(") < 0:
			_fail("S1 %s 未走 UIFactory.button" % path)
	var tscn := FileAccess.get_file_as_string("res://scenes/Campaign.tscn")
	check(
		tscn.find("campaign_main.gd") >= 0 and tscn.find("type=\"Control\"") >= 0,
		"S1 Campaign.tscn 绑定 campaign_main.gd"
	)
	check(fails.is_empty(), "S1 静态扫描通过")


## 桩会话：按契约（memory contract/campaign-api）实现全部方法。
class StubSession extends Node:
	signal changed(reason: String)

	## 装备装卸直用真实 EquipmentData 核心（拒绝/幂等/prev 形状与正式会话一致）。
	const EquipmentDataScript = preload("res://scripts/core/equipment.gd")

	const LEVEL_IDS: Array[String] = [
		"plains_skirmish", "river_crossing", "ambush_reinforce",
		"mountain_pass", "last_stand", "arena_1v1",
	]
	const LEVEL_NAMES: Array[String] = [
		"平原前哨战", "渡河攻坚战", "峡谷伏击·增援",
		"山口要塞", "桥头守卫战", "竞技场单挑",
	]

	var profiles := {}
	var current := ""
	var last_result := {}
	var prepare_calls: Array = []
	var saved_count := 0
	var next_id := 0
	## 最近一次 create_profile 收到的难度参（供新建弹层传值断言）。
	var last_created_difficulty := ""
	var settled_tokens := {}
	## 非空模拟出征挂起：装卸一律拒绝「战斗进行中，不能更换装备」。
	var attempt := ""
	## 购买调用流水（无论成败都记录）——供防重/失败路径断言。
	var buy_calls: Array = []
	## 商店货架（实例字段而非 const：remaining 随购买递减需可变）。
	var shop_stock: Array = []

	func _init() -> void:
		shop_stock = [
			{"id": "hpPotion", "name": "治疗药水", "price": 80, "remaining": -1, "max_buyable": -1},
			{"id": "mpPotion", "name": "法力药水", "price": 120, "remaining": 2, "max_buyable": 2},
			{"id": "shuriken", "name": "手里剑", "price": 500, "remaining": -1, "max_buyable": -1},
		]
		profiles["a"] = _make_profile("a", "旧档冒险", 120, ["plains_skirmish"], 100, [], [])
		# a 可加载但带 notice：备份恢复档也必须在列表上警示玩家。
		profiles["a"]["notice"] = "备份恢复：部分回合数据来自自动备份"
		profiles["b"] = _make_profile(
			"b", "最近的档", 220, ["plains_skirmish", "river_crossing"], 900,
			[
				{"id": "hero", "name": "剑士队长", "level": 3, "exp": 40, "hp": 30, "max_hp": 30, "mp": 10, "max_mp": 10, "classId": "swordsman"},
				{"id": "mage", "name": "见习法师", "level": 2, "hp": 18, "max_hp": 20, "mp": 14, "max_mp": 16},
			],
			[
				{"id": "hpPotion", "name": "治疗药水", "uses": 3},
				{"id": "mpPotion", "name": "法力药水", "count": 2},
			]
		)
		# is_recent 由 CampaignSession 持久化（加载/创建即置位）：UI 以此
		# 显示「最近游玩」并默认聚焦，不依赖 saved_at 排序首位。
		profiles["b"]["is_recent"] = true
		profiles["c"] = _make_profile("c", "损坏档", 0, [], 50, [], [])
		profiles["c"]["loadable"] = false
		profiles["c"]["notice"] = "版本过旧，需要迁移后才能加载"

	static func _make_profile(
		id: String, profile_name: String, gold: int,
		completed: Array, saved_at: int, roster: Array, inventory: Array
	) -> Dictionary:
		return {
			"id": id,
			"name": profile_name,
			"gold": gold,
			"completed_levels": completed.duplicate(),
			"saved_at": saved_at,
			"roster": roster,
			"inventory": inventory,
		}

	func _emit(reason := "") -> void:
		changed.emit(reason)

	func get_profile() -> Dictionary:
		if current == "" or not profiles.has(current):
			return {}
		return (profiles[current] as Dictionary).duplicate(true)

	func list_profiles() -> Array:
		var result: Array = []
		for key: Variant in profiles.keys():
			var profile: Dictionary = profiles[key]
			result.append({
				"id": profile.get("id"),
				"name": profile.get("name"),
				"gold": profile.get("gold"),
				"completed_count": (profile.get("completed_levels") as Array).size(),
				"saved_at": profile.get("saved_at"),
				"loadable": profile.get("loadable", true),
				"notice": profile.get("notice", ""),
				"is_recent": profile.get("is_recent", false),
			})
		return result

	func create_profile(profile_name: String, difficulty: Variant = &"normal") -> Dictionary:
		var id := "p%d" % next_id
		next_id += 1
		profiles[id] = _make_profile(id, profile_name, 0, [], 990 + next_id, [], [])
		(profiles[id] as Dictionary)["difficulty"] = String(difficulty)
		last_created_difficulty = String(difficulty)
		_emit()
		return {"ok": true, "id": id}

	func load_profile(id: String) -> Dictionary:
		if not profiles.has(id):
			return {"ok": false, "error": "存档不存在"}
		var profile: Dictionary = profiles[id]
		if not bool(profile.get("loadable", true)):
			return {"ok": false, "error": String(profile.get("notice", ""))}
		current = id
		_emit()
		return {"ok": true}

	func rename_profile(id: String, profile_name: String) -> Dictionary:
		if not profiles.has(id):
			return {"ok": false, "error": "存档不存在"}
		profiles[id]["name"] = profile_name
		_emit()
		return {"ok": true}

	func delete_profile(id: String) -> Dictionary:
		if not profiles.has(id):
			return {"ok": false, "error": "存档不存在"}
		profiles.erase(id)
		if current == id:
			current = ""
		_emit()
		return {"ok": true}

	func save_current() -> Dictionary:
		if current == "" or not profiles.has(current):
			return {"ok": false, "error": "没有已加载的存档"}
		saved_count += 1
		profiles[current]["saved_at"] = 995
		_emit()
		return {"ok": true}

	func leave_profile() -> void:
		current = ""

	func list_levels() -> Array:
		var completed: Array = []
		if profiles.has(current):
			completed = profiles[current].get("completed_levels", [])
		var result: Array = []
		for i: int in LEVEL_IDS.size():
			var unlocked := i == 0 or completed.has(LEVEL_IDS[i - 1])
			result.append({
				"id": LEVEL_IDS[i],
				"name": LEVEL_NAMES[i],
				"source": "res://data/battlefields/%s.json" % LEVEL_IDS[i],
				"unlocked": unlocked,
				"completed": completed.has(LEVEL_IDS[i]),
				"reward_gold": 200,
				"reward_items": [{"id": "hpPotion", "name": "治疗药水", "count": 1}],
				"reward_gold_repeat": 50,
				"reward_items_repeat": [],
			})
		return result

	func prepare_battle(level_id: String) -> Dictionary:
		prepare_calls.append(level_id)
		# 测试默认阻止真实出征（避免 change_scene 破坏测试树）。
		return {"ok": false, "error": "测试桩：阻止真实进入战斗"}

	func list_shop() -> Dictionary:
		if current == "" or not profiles.has(current):
			return {"ok": false, "error": "没有已加载的存档"}
		var profile: Dictionary = profiles[current]
		var clear_index := (profile.get("completed_levels", []) as Array).size()
		var stock: Array = []
		for entry: Variant in shop_stock:
			var item: Dictionary = (entry as Dictionary).duplicate()
			if int(item["remaining"]) >= 0:
				item["max_buyable"] = int(item["remaining"])
			stock.append(item)
		return {
			"ok": true, "error": "",
			"gold": int(profile.get("gold", 0)),
			"clear_index": clear_index,
			"stock": stock,
		}

	func buy_item(id: String, count: int = 1) -> Dictionary:
		buy_calls.append({"id": id, "count": count})
		if current == "" or not profiles.has(current):
			return {"ok": false, "error": "没有已加载的存档"}
		var profile: Dictionary = profiles[current]
		for entry: Variant in shop_stock:
			var item: Dictionary = entry as Dictionary
			if String(item["id"]) != id:
				continue
			var price := int(item["price"])
			var remaining := int(item.get("remaining", -1))
			if remaining == 0:
				return {"ok": false, "error": "%s 本周期限购已用完" % String(item["name"])}
			if int(profile["gold"]) < price * count:
				return {
					"ok": false,
					"error": "金币不足：%s 需 %d，当前 %d" % [
						String(item["name"]), price * count, int(profile["gold"]),
					],
				}
			profile["gold"] = int(profile["gold"]) - price * count
			var inventory: Array = profile["inventory"]
			inventory.append({"id": id, "name": String(item["name"]), "uses": 3})
			if remaining > 0:
				item["remaining"] = remaining - count
			# 失败不 emit：UI 失败路径保持页面不动，仅成功后 changed 刷新。
			_emit()
			return {"ok": true}
		return {"ok": false, "error": "未知商品：%s" % id}

	## 装备装卸（契约 scripts/campaign/campaign_session.gd equip_item/unequip_item）：
	## 核心判定走真实 EquipmentData（职业授权/同槽替换/幂等/prev 形状与正式
	## 会话一致），桩只负责 roster 定位、原地修改与 changed 通知。
	func equip_item(roster_id: String, entry_id: String) -> Dictionary:
		if attempt != "":
			return {"ok": false, "error": "战斗进行中，不能更换装备"}
		var unit := _find_roster_unit(roster_id)
		if unit.is_empty():
			return {"ok": false, "error": "队伍中找不到该单位"}
		var result: Dictionary = EquipmentDataScript.equip(unit, StringName(entry_id))
		if bool(result.get("ok", false)) and bool(result.get("changed", false)):
			_emit("equipped")
		return result

	func unequip_item(roster_id: String, slot: String) -> Dictionary:
		if attempt != "":
			return {"ok": false, "error": "战斗进行中，不能更换装备"}
		var unit := _find_roster_unit(roster_id)
		if unit.is_empty():
			return {"ok": false, "error": "队伍中找不到该单位"}
		var result: Dictionary = EquipmentDataScript.unequip(unit, StringName(slot))
		if bool(result.get("ok", false)) and bool(result.get("changed", false)):
			_emit("unequipped")
		return result

	func _find_roster_unit(roster_id: String) -> Dictionary:
		if current == "" or not profiles.has(current):
			return {}
		for entry: Variant in profiles[current].get("roster", []):
			if entry is Dictionary and String((entry as Dictionary).get("id", "")) == roster_id:
				return entry
		return {}

	func settle_battle(token: String, result: StringName, chapter: Variant) -> Dictionary:
		if settled_tokens.has(token):
			return {"ok": true, "duplicate": true}
		settled_tokens[token] = true
		if current == "" or not profiles.has(current):
			return {"ok": false, "error": "没有已加载的存档"}
		var profile: Dictionary = profiles[current]
		var completed: Array = profile["completed_levels"]
		# settle 作用于第一关（与 list_levels 的 LEVEL_IDS 同源，勿用 "level_0"
		# 这类下标假 ID——曾因两套 ID 不一致导致关卡卡状态全错）。
		var level_id := LEVEL_IDS[0]
		var first_clear := not completed.has(level_id)
		var gold := 50
		var items: Array = []
		if result == &"win":
			gold = 200 if first_clear else 50
			items = [{"id": "hpPotion", "name": "治疗药水", "count": 1}] if first_clear else []
			profile["gold"] = int(profile["gold"]) + gold
			if first_clear:
				completed.append(level_id)
			last_result = {
				"result": "win",
				"level_name": "平原前哨战",
				"gold": gold,
				"items": items,
				"first_clear": first_clear,
				"level_ups": [
					{
						"id": "hero",
						"name": "剑士队长",
						"from_level": 2,
						"to_level": 3,
						# 故意反序插入（spd 在 str 前）：验证升级行按固定属性序输出。
						"stat_deltas": {"spd": 1, "str": 1},
					},
				],
			}
			_emit()
			return {"ok": true}
		last_result = {"result": String(result), "level_name": "平原前哨战"}
		return {"ok": true}

	func get_last_result() -> Dictionary:
		return last_result.duplicate(true)

	func clear_last_result() -> void:
		last_result = {}
