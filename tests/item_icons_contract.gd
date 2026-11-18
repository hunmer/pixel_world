## tests/item_icons_contract.gd — 物品图标目录、绑定与战斗菜单接线契约
## 覆盖：①目录形状（"01".."08" 数字字符串稳定 ID、显式 ID→路径映射、非法输入拒绝）
## ②绑定完整性（items.json 8 物品 iconId 与约定绑定表一致、互异；旧定义缺 iconId 时
##   _normalize 容忍并落 &""，不回填默认，契约可判绑定缺失）
## ③纹理性（8 个文件全部存在，每个 ID 加载到本 ID 真实路径的 64x64 纹理，不得以兜底
##   通过；get_texture 缓存同实例；未知 iconId 回退默认图标同实例）
## ④应急缝隔离（_load_hook 模拟全目录加载失败：默认图也坏时非 null 应急纹理同实例，
##   item_icon 链路仍非 null；缝复位后真实纹理恢复，禁止删除/改名正式资源）
## ⑤item_icon 链路（每物品非 null 且等于其 iconId 纹理；未知物品回退默认图标（与技能
##   链路的 null 语义相反）；旧 {id,uses} 背包条目经 usable/equipable 仍可解析）
## ⑥战斗数值不动（iconId 为纯新增字段，锁定 8 物品关键结算数值基线）
## ⑦真实菜单接线（复用 battle_ui_components 契约的真实 setup+settle 模式：全背包
##   8 物品 + 耗尽 + 装备禁用 + 未知物品默认图逐按钮断言；NEAREST 与 token 图标尺寸、
##   禁用原因文案、打开前后战斗状态与背包零变化）
## 运行：godot --headless --path . --script res://tests/item_icons_contract.gd
extends SceneTree

const UnitScript = preload("res://scripts/core/unit.gd")
const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")

## 物品 id → iconId 的稳定绑定表，防止既有绑定漂移。
const EXPECTED_BINDINGS := {
	&"hpPotion": &"01",
	&"mpPotion": &"02",
	&"antidote": &"03",
	&"shuriken": &"04",
	&"bomb": &"05",
	&"armorRing": &"06",
	&"powerRing": &"07",
	&"mightPotion": &"08",
}

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)


func _settle() -> void:
	for i in range(5):
		await process_frame


func _buttons(node: Node) -> Array[Button]:
	var found: Array[Button] = []
	if node is Button:
		found.append(node)
	for child in node.get_children():
		found.append_array(_buttons(child))
	return found


func _run() -> void:
	_run_catalog_shape()
	_run_binding_integrity()
	_run_textures()
	_run_emergency_seam()
	_run_item_icon_chain()
	_run_battle_values_untouched()
	await _run_menu_wiring()
	if failures == 0:
		print("ITEM_ICONS_CONTRACT_OK")
	else:
		printerr("ITEM_ICONS_CONTRACT_FAILED: %d 处失败" % failures)
	quit(0 if failures == 0 else 1)


## ①目录形状：8 个数字字符串 ID、逐条路径显式映射、非法 ID 拒绝。
func _run_catalog_shape() -> void:
	var paths: Dictionary = ItemIcons.ICON_PATHS
	var ids: Array = ItemIcons.ICON_LIST
	_expect(paths.size() == 8, "图标目录应为 8 项，实际 %d" % paths.size())
	_expect(ids.size() == 8, "ICON_LIST 应为 8 项，实际 %d" % ids.size())
	# 数字字符串 ID 完整集合："01".."08"，两位零填充，显式路径不得拼接
	for n in range(1, 9):
		var iid := StringName("%02d" % n)
		_expect(paths.has(iid), "目录缺少稳定 ID %s" % String(iid))
		_expect(ids.has(iid), "ICON_LIST 缺少 %s" % String(iid))
		if paths.has(iid):
			_expect(String(paths[iid]) == "res://assets/ui/items/%02d.png" % n,
				"%s 应显式指向 items/%02d.png，实际 %s" % [String(iid), n, String(paths[iid])])
	# 非法 ID 拒绝
	for bad in [&"item_01", &"1", &"9", &"09", &"00", &"junk", &""]:
		_expect(not ItemIcons.has_icon(bad), "非法 ID %s 不应在目录内" % String(bad))
		_expect(ItemIcons.icon_path(bad) == "", "非法 ID %s 路径应为空串" % String(bad))
	_expect(ItemIcons.DEFAULT_ICON_ID == &"01", "默认兜底图标应为 01")
	_expect(ItemIcons.has_icon(ItemIcons.DEFAULT_ICON_ID), "默认兜底图标必须在目录内")


## ②绑定完整性：8 物品 iconId 与约定表逐项一致且互异；旧定义缺 iconId 容忍。
func _run_binding_integrity() -> void:
	var seen: Dictionary = {}
	var items: Array = ItemData.ITEM_LIST
	_expect(items.size() == EXPECTED_BINDINGS.size(),
		"物品数应为 %d，实际 %d" % [EXPECTED_BINDINGS.size(), items.size()])
	for raw in items:
		var it: Dictionary = raw
		var iid: StringName = it[&"id"]
		var icon_id: StringName = it.get(&"iconId", &"")
		_expect(EXPECTED_BINDINGS.has(iid), "出现约定外物品 %s" % String(iid))
		_expect(icon_id == EXPECTED_BINDINGS.get(iid, &"<none>"),
			"%s 的 iconId 应为 %s，实际 %s" % [String(iid), String(EXPECTED_BINDINGS.get(iid, &"")), String(icon_id)])
		_expect(icon_id != &"" and ItemIcons.has_icon(icon_id),
			"%s 的 iconId %s 不在图标目录内" % [String(iid), String(icon_id)])
		_expect(not seen.has(icon_id), "iconId %s 被 %s 与 %s 重复绑定" % [
			String(icon_id), String(seen.get(icon_id, &"")), String(iid)])
		seen[icon_id] = iid
	# 旧定义缺 iconId：normalize 容忍且落 &""（不回填默认，保契约可判 JSON 绑定缺失）
	var legacy: Dictionary = ItemData._normalize({
		id = &"legacyItem", name = "旧物品", desc = "无图标字段", type = &"consumable",
		target = &"self", effect = &"heal_hp", power = 5, range = [0, 0], uses = 1,
	})
	_expect(String(legacy.get(&"iconId", &"<missing>")) == "",
		"旧定义缺 iconId 应 normalize 为空 StringName，实际 %s" % String(legacy.get(&"iconId", &"<missing>")))
	# 有 iconId 时透传为 StringName
	var with_icon: Dictionary = ItemData._normalize({id = &"x1", iconId = "07"})
	_expect(with_icon[&"iconId"] == &"07", "iconId 应透传为 StringName 07，实际 %s" % String(with_icon[&"iconId"]))


## ③纹理性：8 个文件全部存在；每个 ID 取到本 ID 真实路径的 64x64 纹理（不得以兜底通过）。
func _run_textures() -> void:
	for iid in ItemIcons.ICON_LIST:
		var path: String = ItemIcons.ICON_PATHS[iid]
		_expect(FileAccess.file_exists(path), "图标文件缺失: %s" % path)
		_expect(ResourceLoader.exists(path), "图标未导入不可加载: %s" % path)
		var tex: Texture2D = ItemIcons.get_texture(iid)
		_expect(tex != null, "%s 纹理为 null（不得以兜底通过）" % String(iid))
		if tex == null:
			continue
		# 必须来自本 ID 的真实路径（同路径 load 同实例），而非兜底纹理
		var direct: Texture2D = load(path) as Texture2D
		_expect(tex == direct, "%s 应加载自真实路径 %s，而非兜底纹理" % [String(iid), path])
		_expect(tex.get_size() == Vector2(64, 64),
			"%s 纹理应为 64x64，实际 %s" % [String(iid), tex.get_size()])
	# 缓存：同一 ID 返回同一实例（战斗菜单用 == 比较图标）
	var a: Texture2D = ItemIcons.get_texture(&"01")
	var b: Texture2D = ItemIcons.get_texture(&"01")
	_expect(a != null and a == b, "get_texture 同一 ID 应返回同一实例")
	# 未知 iconId：明确兜底（非 null、等于默认图标纹理）
	var fb: Texture2D = ItemIcons.get_texture(&"not_an_icon")
	_expect(fb != null and fb == ItemIcons.get_texture(ItemIcons.DEFAULT_ICON_ID),
		"未知 iconId 应回退默认图标（非 null 且同实例）")


## ④应急缝：最小隔离 _load_hook 模拟全目录加载失败；复位后真实纹理必须恢复。
func _run_emergency_seam() -> void:
	var saved_hook: Callable = ItemIcons._load_hook
	var saved_cache: Dictionary = ItemIcons._cache.duplicate()
	var saved_emergency: Texture2D = ItemIcons._emergency_tex
	ItemIcons._load_hook = func(_path: String) -> Texture2D: return null
	ItemIcons._cache.clear()
	ItemIcons._emergency_tex = null
	var e_default: Texture2D = ItemIcons.get_texture(ItemIcons.DEFAULT_ICON_ID)
	_expect(e_default != null, "默认图标加载失败必须给非 null 应急纹理，绝不返回 null")
	if e_default != null:
		_expect(e_default.get_size() == Vector2(ItemIcons.EMERGENCY_SIZE, ItemIcons.EMERGENCY_SIZE),
			"应急纹理应为 %dx%dx，实际 %s" % [ItemIcons.EMERGENCY_SIZE, ItemIcons.EMERGENCY_SIZE, e_default.get_size()])
		var e_other: Texture2D = ItemIcons.get_texture(&"05")
		_expect(e_other != null and e_other == e_default,
			"非默认图标加载失败应回退默认；默认也坏时给同一应急实例")
		var e_chain: Texture2D = ItemData.item_icon(&"hpPotion")
		_expect(e_chain != null and e_chain == e_default,
			"应急态下 item_icon 链路仍非 null（物品菜单兜底语义）")
	# 复位（即使上面有失败也必须复位，不触碰正式资源）
	ItemIcons._load_hook = saved_hook
	ItemIcons._cache = saved_cache
	ItemIcons._emergency_tex = saved_emergency
	# 复位后恢复真实纹理
	var real: Texture2D = ItemIcons.get_texture(&"05")
	var real_direct: Texture2D = load(ItemIcons.icon_path(&"05")) as Texture2D
	_expect(real != null and real == real_direct, "测试缝复位后应恢复本 ID 真实路径纹理")


## ⑤item_icon 链路：每物品可取图标且等于其 iconId 纹理；未知物品回退默认（非 null）。
func _run_item_icon_chain() -> void:
	for raw in ItemData.ITEM_LIST:
		var it: Dictionary = raw
		var iid: StringName = it[&"id"]
		var tex: Texture2D = ItemData.item_icon(iid)
		_expect(tex != null, "item_icon(%s) 不应为 null" % String(iid))
		var expect_id: StringName = it.get(&"iconId", &"")
		if expect_id != &"":
			_expect(tex == ItemIcons.get_texture(expect_id),
				"item_icon(%s) 应等于其 iconId 纹理" % String(iid))
	# 未知物品：回退默认图标且非 null —— 与技能链路（未知技能必须 null）相反，
	# 物品菜单兜底不返回 null，且 ItemIcons 应急纹理保证最终也非 null。
	var unknown: Texture2D = ItemData.item_icon(&"__no_such_item__")
	_expect(unknown != null and unknown == ItemIcons.get_texture(ItemIcons.DEFAULT_ICON_ID),
		"未知物品 item_icon 应回退默认物品图标（非 null 且同实例）")
	# 旧 {id, uses} 背包条目（库存储格式不变）仍可解析出定义
	var unit := {id = &"u_legacy", items = [{id = &"hpPotion", uses = 2}, {id = &"armorRing", uses = 1}]}
	var usable: Array = ItemData.usable_items(unit)
	_expect(usable.size() == 1 and usable[0][&"def"][&"id"] == &"hpPotion",
		"旧 {id,uses} 背包经 usable_items 应解析出消耗品（数量 %d）" % usable.size())
	var equips: Array = ItemData.equipable_items(unit)
	_expect(equips.size() == 1 and equips[0][&"def"][&"id"] == &"armorRing",
		"旧 {id,uses} 背包经 equipable_items 应解析出装备（数量 %d）" % equips.size())


## ⑥战斗数值不动：iconId 为纯新增字段，锁定 8 物品关键结算数值基线。
func _run_battle_values_untouched() -> void:
	var baseline := {
		&"hpPotion": {type = &"consumable", target = &"ally", effect = &"heal_hp", power = 20, range = [0, 1], uses = 3},
		&"mpPotion": {type = &"consumable", target = &"ally", effect = &"heal_mp", power = 10, range = [0, 1], uses = 2},
		&"antidote": {type = &"consumable", target = &"self", effect = &"cleanse", power = 0, range = [0, 0], uses = 2},
		&"shuriken": {type = &"throwable", target = &"enemy", effect = &"damage", power = 8, range = [1, 3], uses = 4},
		&"bomb": {type = &"throwable", target = &"aoe_enemy", effect = &"damage", power = 10, range = [1, 2], uses = 2},
		&"armorRing": {type = &"equip", target = &"self", effect = &"equip", equipStat = &"def", equipValue = 4, uses = 1},
		&"powerRing": {type = &"equip", target = &"self", effect = &"equip", equipStat = &"str", equipValue = 3, uses = 1},
		&"mightPotion": {type = &"buff", target = &"self", effect = &"buff", stat = &"str", buffValue = 5, buffTurns = 3, power = 0, range = [0, 0], uses = 2},
	}
	for raw in ItemData.ITEM_LIST:
		var it: Dictionary = raw
		var iid: StringName = it[&"id"]
		var want: Dictionary = baseline.get(iid, {})
		for key in want:
			_expect(it.get(key, null) == want[key],
				"%s.%s 战斗数值被改动：期望 %s 实际 %s" % [String(iid), String(key), str(want[key]), str(it.get(key, null))])
	_expect(ItemData.ITEM_LIST.size() == baseline.size(), "物品数量不应变化（应仍为 8）")


## ⑦真实菜单接线：复用 battle_ui_components 契约的真实 setup+settle 模式。
func _run_menu_wiring() -> void:
	var battle_ui_script: GDScript = load("res://scripts/battle/battle_ui.gd")
	var player: Dictionary = UnitScript.create_random_unit(&"item_icon_player", "物品图标我方", &"player", 3, Vector2i(1, 1))
	var enemy: Dictionary = UnitScript.create_random_unit(&"item_icon_enemy", "物品图标敌方", &"enemy", 3, Vector2i(2, 1))
	# 全 8 物品 + 耗尽 + 未知条目（旧 {id,uses} 库存储格式）
	player.items = [
		{id = &"hpPotion", uses = 2}, {id = &"mpPotion", uses = 1}, {id = &"antidote", uses = 2},
		{id = &"shuriken", uses = 4}, {id = &"bomb", uses = 1},
		{id = &"armorRing", uses = 1}, {id = &"powerRing", uses = 1}, {id = &"mightPotion", uses = 2},
		{id = &"hpPotion", uses = 0},
		{id = &"ghostItem", uses = 2},
	]
	var grid := GridSystem.new(4, 4, [[&"plain", &"plain", &"plain", &"plain"], [&"plain", &"plain", &"plain", &"plain"], [&"plain", &"plain", &"plain", &"plain"], [&"plain", &"plain", &"plain", &"plain"]])
	grid.units = {player.id: player, enemy.id: enemy}
	var turn := TurnManager.new([player, enemy])
	root.add_child(turn)
	var ui: Node = battle_ui_script.new()
	ui.setup(null, grid, {}, turn)
	ui.chapter = {victory = {type = &"defend_turns", turns = 5}}
	ui.on_set_mode = func(_mode): pass
	ui.on_clear_pending_move_undo = func(): pass
	root.add_child(ui)
	ui.build(func(): pass, func(): pass, func(): pass)
	await _settle()
	# 打开前快照：战斗状态与背包（uses 不因打开菜单而变化）
	var hp_before: int = player.hp
	var mp_before: int = player.mp
	var acted_before: bool = bool(player.get(&"hasActed", false))
	var items_before: Array = []
	for entry in player.items:
		items_before.append({id = entry.get(&"id", &""), uses = int(entry.get(&"uses", 0))})
	ui._menu._open_item_picker(player)
	await _settle()
	var buttons: Array[Button] = _buttons(ui.menu_container)
	_expect(buttons.size() == player.items.size(),
		"背包菜单应逐条目显示按钮（期望 %d），实际 %d" % [player.items.size(), buttons.size()])
	if buttons.size() == player.items.size():
		var icon_size_want = ComponentThemeScript.SPACE_LG + ComponentThemeScript.SPACE_SM
		for index in buttons.size():
			var button: Button = buttons[index]
			var entry: Dictionary = player.items[index]
			var bind_id: StringName = EXPECTED_BINDINGS.get(entry.get(&"id", &""), &"")
			# 未知物品条目：get_item 回退默认物品定义 → 默认图标
			var want_icon: Texture2D = ItemIcons.get_texture(bind_id if bind_id != &"" else ItemIcons.DEFAULT_ICON_ID)
			_expect(button.icon != null and button.icon == want_icon,
				"条目 %d（%s）应显示对应图标（未知物品回退默认），实际 %s" % [index, String(entry.get(&"id", &"")), str(button.icon)])
			_expect(button.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
				"条目 %d 物品图标应保持最近邻采样" % index)
			_expect(button.expand_icon, "条目 %d 应展开图标" % index)
			_expect(button.get("icon_size") == icon_size_want and icon_size_want == 32,
				"条目 %d 图标尺寸应为 token SPACE_LG+SPACE_SM=32，实际 %s" % [index, str(button.get("icon_size"))])
			var uses: int = int(entry.get(&"uses", 0))
			var is_equip: bool = bind_id == &"06" or bind_id == &"07"
			if uses <= 0:
				_expect(button.disabled, "耗尽条目（%s）必须禁用" % String(entry.get(&"id", &"")))
				_expect(button.text.contains("已耗尽"), "耗尽条目禁用原因应显示已耗尽，实际 %s" % button.text)
			elif is_equip:
				_expect(button.disabled, "装备条目（%s）必须禁用" % String(entry.get(&"id", &"")))
				_expect(button.text.contains("装备 · 不可在战斗中使用"), "装备条目禁用原因文案，实际 %s" % button.text)
			else:
				_expect(not button.disabled, "可用条目（%s）不应禁用：%s" % [String(entry.get(&"id", &"")), button.text])
		# 未知物品默认图（最后一个条目 ghostItem）
		_expect(buttons[buttons.size() - 1].icon == ItemIcons.get_texture(ItemIcons.DEFAULT_ICON_ID),
			"未知物品条目应显示默认物品图标")
	# 打开菜单零副作用：战斗状态与背包不变
	_expect(player.hp == hp_before and player.mp == mp_before and bool(player.get(&"hasActed", false)) == acted_before,
		"打开物品菜单不得改动战斗数值/行动标记")
	var items_after: Array = []
	for entry in player.items:
		items_after.append({id = entry.get(&"id", &""), uses = int(entry.get(&"uses", 0))})
	_expect(items_after == items_before, "打开物品菜单不得改动背包条目")
	ui.close_menu()
	ui.queue_free()
	turn.queue_free()
	await process_frame
