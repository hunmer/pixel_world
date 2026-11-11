## scenes/map_editor.gd — 战场地图编辑器（JSON 战场调试工具）
##
## 三大能力（用户需求）：
##   1. 更换地图种子：seed 输入 + 🌱 生成 → BattlefieldDoc.generate 确定性地形
##   2. 添加地图实体：地形调色板（平原/森林/山地/水域/要塞/村庄/城墙）+ 画笔/填充/橡皮
##   3. 添加阵营角色：阵营（我方/敌方）+ 职业 + 等级 + 姓名放置，左键放置/再点删除
## 保存为 res://data/battlefields/<id>.json（loader schema，保存即回读校验），
## 战场列表（O 键 / ⚔ 按钮）立即可见可开战。
##
## 入口：世界内 E 键 / 战场面板「🛠 打开编辑器」按钮；返回 → res://main.tscn。

extends Control

const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const EditorCanvasScript = preload("res://scripts/editor/editor_canvas.gd")
const ProfessionDataScript = preload("res://scripts/core/professions.gd")

const Tool = { PAINT = 0, FILL = 1, ERASE = 2, UNIT = 3 }

const BG := Color(0.05, 0.07, 0.10, 0.97)
const PANEL_BORDER := Color(0.25, 0.37, 0.43, 0.9)
const TEXT_MAIN := Color(0.88, 0.93, 0.95)
const TEXT_DIM := Color(0.56, 0.68, 0.71)
const ACCENT := Color(0.40, 0.86, 0.76)
const ERR := Color(1.0, 0.45, 0.42)

const CLASS_IDS: Array[String] = [
	"swordsman", "knight", "archer", "mage", "berserker", "assassin", "lancer", "priest",
]

var model: Dictionary = {}
var current_tool: int = Tool.PAINT
var current_terrain: StringName = &"mountain"
var selected_class: String = "swordsman"
var selected_faction: String = "player"

var _canvas: EditorCanvasScript
var _status_label: Label
var _id_edit: LineEdit
var _name_edit: LineEdit
var _seed_edit: LineEdit
var _width_box: SpinBox
var _height_box: SpinBox
var _hosting_check: CheckButton
var _class_box: OptionButton
var _faction_box: OptionButton
var _level_box: SpinBox
var _unit_name_edit: LineEdit
var _load_box: OptionButton
var _tool_buttons: Dictionary = {}   # Tool -> Button
var _terrain_buttons: Dictionary = {}  # StringName(terrain) -> Button
## 程序化同步 SpinBox 时挂起 _on_resize（避免读到另一半的旧值触发错误 resize）
var _syncing_boxes := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	model = BattlefieldDocScript.create_empty()
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
			# 先标记已处理再切场景：change_scene 后本节点被释放，get_viewport() 会变 null
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			_back_to_world()


# ============================================================
# UI 构建（代码建 UI，项目风格与 game_hud.gd / title.gd 一致）
# ============================================================

func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size

	# ---- 顶栏 1：标题 / id / 名称 / hosting / 读取 / 保存 / 返回 ----
	var bar1 := HBoxContainer.new()
	bar1.position = Vector2(8, 6)
	bar1.add_theme_constant_override("separation", 6)
	add_child(bar1)
	var title := _label("🛠 战场编辑器", 16, ACCENT)
	bar1.add_child(title)
	bar1.add_child(_label("id:", 11, TEXT_DIM))
	_id_edit = LineEdit.new()
	_id_edit.text = "custom_map"
	_id_edit.custom_minimum_size = Vector2(110, 28)
	_id_edit.placeholder_text = "snake_case"
	bar1.add_child(_id_edit)
	bar1.add_child(_label("名称:", 11, TEXT_DIM))
	_name_edit = LineEdit.new()
	_name_edit.text = "自定义战场"
	_name_edit.custom_minimum_size = Vector2(130, 28)
	bar1.add_child(_name_edit)
	_hosting_check = CheckButton.new()
	_hosting_check.text = "托管"
	_hosting_check.tooltip_text = "开启后战斗自动托管运行（AI 对 AI），调试观察用"
	bar1.add_child(_hosting_check)
	_load_box = OptionButton.new()
	_load_box.custom_minimum_size = Vector2(170, 28)
	_refresh_load_box()
	bar1.add_child(_load_box)
	var load_btn := _action_btn("📂 读取", _load_selected)
	bar1.add_child(load_btn)
	var save_btn := _action_btn("💾 保存", _save)
	save_btn.custom_minimum_size = Vector2(96, 30)
	bar1.add_child(save_btn)
	var back_btn := _action_btn("✕ 返回(Esc)", _back_to_world)
	bar1.add_child(back_btn)

	# ---- 顶栏 2：种子 / 尺寸 / 生成 / 清空 ----
	var bar2 := HBoxContainer.new()
	bar2.position = Vector2(8, 42)
	bar2.add_theme_constant_override("separation", 6)
	add_child(bar2)
	bar2.add_child(_label("种子:", 11, TEXT_DIM))
	_seed_edit = LineEdit.new()
	_seed_edit.text = "demo"
	_seed_edit.custom_minimum_size = Vector2(130, 28)
	_seed_edit.placeholder_text = "任意文本，同种子同地图"
	bar2.add_child(_seed_edit)
	var dice_btn := _action_btn("🎲", func():
		_seed_edit.text = str(Time.get_unix_time_from_system()).sha1_text().substr(0, 8)
		_generate())
	bar2.add_child(dice_btn)
	bar2.add_child(_label("宽:", 11, TEXT_DIM))
	_width_box = SpinBox.new()
	_width_box.min_value = BattlefieldDocScript.MIN_SIZE
	_width_box.max_value = BattlefieldDocScript.MAX_SIZE
	_width_box.value = model.width
	_width_box.value_changed.connect(func(_v: float): _on_resize())
	bar2.add_child(_width_box)
	bar2.add_child(_label("高:", 11, TEXT_DIM))
	_height_box = SpinBox.new()
	_height_box.min_value = BattlefieldDocScript.MIN_SIZE
	_height_box.max_value = BattlefieldDocScript.MAX_SIZE
	_height_box.value = model.height
	_height_box.value_changed.connect(func(_v: float): _on_resize())
	bar2.add_child(_height_box)
	var gen_btn := _action_btn("🌱 生成", _generate)
	gen_btn.custom_minimum_size = Vector2(90, 30)
	bar2.add_child(gen_btn)
	var clear_btn := _action_btn("🧹 清空地形", func():
		model.rows = BattlefieldDocScript.create_empty(model.width, model.height).rows
		_refresh_canvas()
		_status("地形已清空（单位保留）"))
	bar2.add_child(clear_btn)

	# ---- 左侧栏 ----
	var side := PanelContainer.new()
	side.position = Vector2(8, 80)
	side.size = Vector2(218, vp.y - 116)
	side.add_theme_stylebox_override("panel", _panel_style())
	add_child(side)
	var sv := VBoxContainer.new()
	sv.offset_left = 10; sv.offset_top = 8
	sv.offset_right = -10; sv.offset_bottom = -8
	sv.add_theme_constant_override("separation", 6)
	side.add_child(sv)

	sv.add_child(_label("工具", 12, ACCENT))
	var tool_group := ButtonGroup.new()
	tool_group.pressed.connect(func(btn: Button):
		current_tool = btn.get_meta("tool")
		_on_tool_changed())
	_add_tool_btn(sv, tool_group, Tool.PAINT, "🖌 画笔")
	_add_tool_btn(sv, tool_group, Tool.FILL, "🪣 填充")
	_add_tool_btn(sv, tool_group, Tool.ERASE, "🧽 橡皮")
	_add_tool_btn(sv, tool_group, Tool.UNIT, "👤 角色")
	_tool_buttons[Tool.PAINT].button_pressed = true

	sv.add_child(HSeparator.new())
	sv.add_child(_label("地形（画笔/填充）", 12, ACCENT))
	var terrain_group := ButtonGroup.new()
	terrain_group.pressed.connect(func(btn: Button):
		current_terrain = btn.get_meta("terrain"))
	var tgrid := GridContainer.new()
	tgrid.columns = 2
	tgrid.add_theme_constant_override("h_separation", 4)
	tgrid.add_theme_constant_override("v_separation", 4)
	sv.add_child(tgrid)
	for t in [&"plain", &"forest", &"mountain", &"water", &"fort", &"village", &"wall"]:
		var tb := Button.new()
		tb.toggle_mode = true
		tb.button_group = terrain_group
		tb.custom_minimum_size = Vector2(96, 30)
		tb.text = BattlefieldDocScript.TERRAIN_CN[t]
		tb.set_meta("terrain", t)
		tgrid.add_child(tb)
		_terrain_buttons[t] = tb
	_terrain_buttons[current_terrain].button_pressed = true

	sv.add_child(HSeparator.new())
	sv.add_child(_label("角色放置（角色工具）", 12, ACCENT))
	_faction_box = OptionButton.new()
	_faction_box.add_item("🔵 我方 player")
	_faction_box.add_item("🔴 敌方 enemy")
	_faction_box.item_selected.connect(func(idx: int):
		selected_faction = "player" if idx == 0 else "enemy")
	sv.add_child(_faction_box)
	_class_box = OptionButton.new()
	for cid in CLASS_IDS:
		_class_box.add_item("%s %s" % [ProfessionDataScript.profession_name(StringName(cid)), cid])
	_class_box.item_selected.connect(func(idx: int):
		selected_class = CLASS_IDS[idx])
	sv.add_child(_class_box)
	var lv_row := HBoxContainer.new()
	lv_row.add_child(_label("等级:", 11, TEXT_DIM))
	_level_box = SpinBox.new()
	_level_box.min_value = 1
	_level_box.max_value = 9
	_level_box.value = 3
	lv_row.add_child(_level_box)
	lv_row.add_child(_label("姓名:", 11, TEXT_DIM))
	_unit_name_edit = LineEdit.new()
	_unit_name_edit.custom_minimum_size = Vector2(80, 26)
	_unit_name_edit.placeholder_text = "自动"
	lv_row.add_child(_unit_name_edit)
	sv.add_child(lv_row)

	# ---- 画布 ----
	var scroll := ScrollContainer.new()
	scroll.name = "EditorScroll"
	scroll.position = Vector2(236, 80)
	scroll.size = Vector2(vp.x - 244, vp.y - 118)
	add_child(scroll)
	_canvas = EditorCanvasScript.new()
	_canvas.name = "EditorCanvas"
	_canvas.cell_pressed.connect(_on_cell_pressed)
	_canvas.cell_dragged.connect(_on_cell_dragged)
	scroll.add_child(_canvas)
	_refresh_canvas()

	# ---- 状态栏 ----
	_status_label = _label("就绪 — 左键操作画布；同种子+同尺寸生成结果确定", 11, TEXT_DIM)
	_status_label.name = "StatusLabel"
	_status_label.position = Vector2(236, vp.y - 34)
	add_child(_status_label)


func _add_tool_btn(parent: Node, group: ButtonGroup, tool: int, text: String) -> void:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.text = text
	b.set_meta("tool", tool)
	parent.add_child(b)
	_tool_buttons[tool] = b


func _action_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	return b


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


# ============================================================
# 编辑操作（canvas 信号 + 可测方法）
# ============================================================

func _on_cell_pressed(cell: Vector2i) -> void:
	_apply_tool(cell)


func _on_cell_dragged(cell: Vector2i) -> void:
	# 拖动仅对画笔/橡皮有意义（填充/角色不响应拖动）
	if current_tool == Tool.PAINT:
		_set_glyph(cell, BattlefieldDocScript.TERRAIN_GLYPH[current_terrain])
	elif current_tool == Tool.ERASE:
		_set_glyph(cell, ".")


func _apply_tool(cell: Vector2i) -> void:
	match current_tool:
		Tool.PAINT:
			_set_glyph(cell, BattlefieldDocScript.TERRAIN_GLYPH[current_terrain])
		Tool.FILL:
			fill_cell(cell, current_terrain)
		Tool.ERASE:
			if _remove_unit_at(cell):
				pass  # 单位优先删除
			else:
				_set_glyph(cell, ".")
		Tool.UNIT:
			if not _remove_unit_at(cell):
				place_unit(cell, selected_faction, selected_class, int(_level_box.value), _unit_name_edit.text)


## 设置地形图例字符（含画笔/橡皮/拖动路径）
func _set_glyph(cell: Vector2i, glyph: String) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= model.width or cell.y >= model.height:
		return
	var rows: Array = model.rows
	var row: String = rows[cell.y]
	if row.substr(cell.x, 1) == glyph:
		return
	rows[cell.y] = row.substr(0, cell.x) + glyph + row.substr(cell.x + 1)
	_canvas.queue_redraw()


## 洪水填充：同图例连通区域 → 目标地形
func fill_cell(cell: Vector2i, terrain: StringName) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= model.width or cell.y >= model.height:
		return
	var rows: Array = model.rows
	var from: String = (rows[cell.y] as String).substr(cell.x, 1)
	var to: String = String(BattlefieldDocScript.TERRAIN_GLYPH.get(terrain, "."))
	if from == to:
		return
	var stack: Array[Vector2i] = [cell]
	var seen := { cell: true }
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		rows[c.y] = (rows[c.y] as String).substr(0, c.x) + to + (rows[c.y] as String).substr(c.x + 1)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= model.width or n.y >= model.height or seen.has(n):
				continue
			if (rows[n.y] as String).substr(n.x, 1) == from:
				seen[n] = true
				stack.append(n)
	_canvas.queue_redraw()
	_status("填充 %s ×%d 格" % [BattlefieldDocScript.TERRAIN_CN[terrain], seen.size()])


## 放置阵营角色：站不住的地形拒绝；同格已有单位则先移除
func place_unit(cell: Vector2i, faction: String, class_id: String, level: int, uname: String = "") -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= model.width or cell.y >= model.height:
		_status("越界：(%d,%d)" % [cell.x, cell.y], true)
		return false
	var terrain := BattlefieldDocScript.glyph_to_terrain((model.rows[cell.y] as String).substr(cell.x, 1))
	if not BattlefieldLoaderScript._is_standable(terrain):
		_status("%s 不可站人（%s）" % [BattlefieldDocScript.TERRAIN_CN[terrain], str(cell)], true)
		return false
	_remove_unit_at(cell)
	var cn := ProfessionDataScript.profession_name(StringName(class_id))
	var seq := 1
	for u in model.units:
		if String(u.get("class", "")) == class_id and String(u.get("faction", "")) == faction:
			seq += 1
	var unit := {
		"class": class_id,
		"name": uname.strip_edges() if not uname.strip_edges().is_empty() else "%s%d" % [cn, seq],
		"level": clampi(level, 1, 9),
		"x": cell.x,
		"y": cell.y,
		"faction": faction,
		"tag": cn.substr(0, 1),
	}
	(model.units as Array).append(unit)
	_canvas.queue_redraw()
	_status("放置 %s·%s Lv%d @(%d,%d)" % [cn, unit.name, unit.level, cell.x, cell.y])
	return true


## 删除 (cell) 处单位；返回是否删到
func _remove_unit_at(cell: Vector2i) -> bool:
	for i in range((model.units as Array).size()):
		var u: Dictionary = model.units[i]
		if int(u.x) == cell.x and int(u.y) == cell.y:
			model.units.remove_at(i)
			_canvas.queue_redraw()
			_status("移除 %s @(%d,%d)" % [u.name, cell.x, cell.y])
			return true
	return false


## 种子生成（保留 id/name/hosting，替换地形并清空单位）
func apply_generate(seed: String, w: int, h: int) -> void:
	var meta := {
		"id": _id_edit.text if _id_edit != null else String(model.id),
		"name": _name_edit.text if _name_edit != null else String(model.name),
		"hosting": _hosting_check.button_pressed if _hosting_check != null else false,
	}
	model = BattlefieldDocScript.generate(seed, w, h)
	model.merge(meta, true)  # overwrite=true：generate 的空 id/name 需被当前输入覆盖
	_syncing_boxes = true
	_width_box.value = w
	_height_box.value = h
	_syncing_boxes = false
	_refresh_canvas()
	_status("已生成 %d×%d · 种子「%s」（单位已清空）" % [w, h, seed])
	print("[editor] 生成地形 seed=%s size=%dx%d" % [seed, w, h])  # L1 埋点


func _generate() -> void:
	apply_generate(_seed_edit.text, int(_width_box.value), int(_height_box.value))


func _on_resize() -> void:
	if _canvas == null or _syncing_boxes:
		return
	var w := int(_width_box.value)
	var h := int(_height_box.value)
	if w == model.width and h == model.height:
		return
	model = BattlefieldDocScript.resize(model, w, h)
	_refresh_canvas()


func _refresh_canvas() -> void:
	if _canvas == null:
		return
	_canvas.model = model
	_canvas.queue_redraw()


func _on_tool_changed() -> void:
	var names := { Tool.PAINT: "画笔", Tool.FILL: "填充", Tool.ERASE: "橡皮", Tool.UNIT: "角色" }
	_status("工具：%s" % names[current_tool])


# ============================================================
# 读取 / 保存 / 返回
# ============================================================

func _refresh_load_box() -> void:
	if _load_box == null:
		return
	_load_box.clear()
	for entry in BattlefieldLoaderScript.list_battlefields():
		if String(entry.get("error", "")) != "":
			continue
		_load_box.add_item("%s · %s" % [entry.get("name", ""), entry.get("file", "")])
		_load_box.set_item_metadata(_load_box.item_count - 1, entry.get("path", ""))


func _load_selected() -> void:
	if _load_box.selected < 0:
		_status("先在下拉框选择要读取的战场", true)
		return
	load_path(String(_load_box.get_item_metadata(_load_box.selected)))


## 从战场 JSON 读入编辑器（rows / map 两种写法都支持）
func load_path(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_status("无法打开 %s" % path, true)
		return { "ok": false, "error": "无法打开文件" }
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		_status("JSON 解析失败：%s" % path, true)
		return { "ok": false, "error": "JSON 解析失败" }
	model = BattlefieldDocScript.from_json_dict(json.data)
	# 补 tag（画布职业缩写）
	for u in model.units:
		if String(u.get("tag", "")).is_empty():
			u["tag"] = ProfessionDataScript.profession_name(StringName(String(u.get("class", "swordsman")))).substr(0, 1)
	_id_edit.text = String(model.id)
	_name_edit.text = String(model.name)
	_hosting_check.button_pressed = bool(model.hosting)
	_syncing_boxes = true
	_width_box.value = model.width
	_height_box.value = model.height
	_syncing_boxes = false
	_refresh_canvas()
	_status("已读取 %s（%d×%d · 我方%d/敌方%d）" % [
		path.get_file(), model.width, model.height,
		(model.units as Array).filter(func(u): return u.faction != "enemy").size(),
		(model.units as Array).filter(func(u): return u.faction == "enemy").size()])
	print("[editor] 读取战场: %s" % path)  # L1 埋点
	return { "ok": true }


## 保存当前模型（UI 入口；返回 save_model 结果）
func _save() -> void:
	var result := save_current()
	if bool(result.get("ok", false)):
		_status("已保存 → %s（战场列表立即可用）" % result.get("path", ""))
		_refresh_load_box()
	else:
		_status("保存失败：%s" % result.get("error", ""), true)


func save_current() -> Dictionary:
	model.id = _id_edit.text
	model.name = _name_edit.text if not _name_edit.text.strip_edges().is_empty() else "自定义战场"
	model.hosting = _hosting_check.button_pressed
	var result: Dictionary = BattlefieldDocScript.save_model(model)
	if bool(result.get("ok", false)):
		print("[editor] 保存战场: %s" % result.get("path", ""))  # L1 埋点
	else:
		print("[editor] 保存失败: %s" % result.get("error", ""))  # L1 埋点
	return result


func _back_to_world() -> void:
	get_tree().change_scene_to_file("res://main.tscn")


func _status(text: String, is_error: bool = false) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", ERR if is_error else TEXT_DIM)
