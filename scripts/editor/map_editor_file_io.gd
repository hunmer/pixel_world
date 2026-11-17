## map_editor_file_io.gd — 战场 JSON 读取候选/存档素材快照/读取列表
##
## 存取档中不触碰 UI 的纯内核：战场文件打开与解析校验（load_candidate）、
## 保存前被引用素材描述符快照（sync_user_assets）、战场文件列表（refresh_load_box）。
## 全部 static；UI 回显与历史（undo/状态条/模式清理）留在 map_editor.gd 门面。

class_name MapEditorFileIo
extends RefCounted

const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const ProfessionDataScript = preload("res://scripts/core/professions.gd")


## 打开并解析战场 JSON（rows / map 两种写法都支持），通过方块布局校验后返回
## {ok: true, model: candidate}；失败返回 {ok: false, error}（error 为
## "无法打开文件" / "JSON 解析失败" / 布局校验错误文案），不改动任何状态。
static func load_candidate(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return { "ok": false, "error": "无法打开文件" }
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return { "ok": false, "error": "JSON 解析失败" }
	var candidate := BattlefieldDocScript.from_json_dict(json.data)
	var layout_error := BattlefieldDocScript.validate_block_layout(candidate)
	if not layout_error.is_empty():
		return { "ok": false, "error": layout_error }
	var buildings_error := BattlefieldDocScript.validate_buildings(candidate)
	if not buildings_error.is_empty():
		return { "ok": false, "error": buildings_error }
	return { "ok": true, "model": candidate }


## 保存前从素材库拷贝被引用素材的描述符快照进 model.user_assets：
## B2 渲染离线读档自包含（user_assets 缺失时按 id 回退库+占位）；
## 库中已隐藏/删除的素材保留模型里的旧快照，保证存档与历史引用不丢。
## 建筑素材连带 render.back_asset_id 背面依赖一并快照（front_back 模式离线可渲染）。
static func sync_user_assets(model: Dictionary, service) -> void:
	var referenced := {}
	for p in model.get("props", []):
		var aid := String((p as Dictionary).get("asset_id", ""))
		if not aid.is_empty():
			referenced[aid] = true
	for key: String in model.get("tile_overrides", {}):
		var tval: Variant = model.tile_overrides[key]
		# 运行期/JSON 形状均为 {"x,y": {"asset_id": ...}}
		var tid := String((tval as Dictionary).get("asset_id", "") if tval is Dictionary else tval)
		if not tid.is_empty():
			referenced[tid] = true
	var lib: Dictionary = model.get("user_assets", {})
	for b in model.get("buildings", []):
		var baid := String((b as Dictionary).get("asset_id", ""))
		if baid.is_empty():
			continue
		referenced[baid] = true
		# 背面依赖：优先库中最新 descriptor，库无则模型旧快照（back 素材被隐藏时不丢引用）
		var render: Variant = null
		var in_lib: Variant = service.find_by_id(baid)
		if in_lib is Dictionary:
			render = (in_lib as Dictionary).get("render", null)
		elif lib.has(baid):
			render = (lib[baid] as Dictionary).get("render", null)
		if render is Dictionary:
			var back_id := String((render as Dictionary).get("back_asset_id", ""))
			if not back_id.is_empty():
				referenced[back_id] = true
	for aid: String in referenced:
		var d: Variant = service.find_by_id(aid)
		if d is Dictionary:
			lib[aid] = (d as Dictionary).duplicate(true)
	if lib.is_empty():
		model.erase("user_assets")
	else:
		model["user_assets"] = lib


## 读取下拉框数据源：user://battlefields/ 下全部战场（出错条目跳过）
static func refresh_load_box(ed) -> void:
	if ed._load_box == null:
		return
	ed._load_box.clear()
	for entry in BattlefieldLoaderScript.list_battlefields():
		if String(entry.get("error", "")) != "":
			continue
		ed._load_box.add_item("%s · %s" % [entry.get("name", ""), entry.get("file", "")])
		ed._load_box.set_item_metadata(ed._load_box.item_count - 1, entry.get("path", ""))


## 从战场 JSON 读入编辑器（rows / map 两种写法都支持）。
## 解析内核在 load_candidate；此处含历史入栈、面板回显、模式清理与状态栏。
static func apply_load(ed, path: String) -> Dictionary:
	var res: Dictionary = load_candidate(path)
	if not bool(res.get("ok", false)):
		var err: String = String(res.get("error", ""))
		if err == "无法打开文件":
			ed._status("无法打开 %s" % path, true)
		elif err == "JSON 解析失败":
			ed._status("JSON 解析失败：%s" % path, true)
		else:
			ed._status("读取失败：%s" % err, true)
		return { "ok": false, "error": err }
	var candidate: Dictionary = res.get("model", {})
	ed._push_undo("读取")
	ed.model = candidate
	ed._canvas.selected_cell = Vector2i(-1, -1)
	# 补 tag（画布职业缩写）
	for u in ed.model.units:
		if String(u.get("tag", "")).is_empty():
			u["tag"] = ProfessionDataScript.profession_name(StringName(String(u.get("class", "swordsman")))).substr(0, 1)
	ed._id_edit.text = String(ed.model.id)
	ed._name_edit.text = String(ed.model.name)
	ed._hosting_check.button_pressed = bool(ed.model.hosting)
	ed._syncing_boxes = true
	ed._width_box.value = ed.model.width
	ed._height_box.value = ed.model.height
	ed._syncing_boxes = false
	ed._refresh_canvas()
	ed._clear_building_preview()  # 跨模型建筑预览不成立
	ed._clipboard.clear()  # 跨模型粘贴语义不成立：读取即清剪贴板/取消预览
	ed._cancel_paste()
	ed._cancel_place_mode()  # 跨模型粘贴语义不成立：读取退出放置
	if ed._move_tool_active:
		ed._set_move_tool(false)  # 新模型旧选区不成立：收起移动工具
	ed._status("已读取 %s（%d×%d · 我方%d/敌方%d）" % [
		path.get_file(), ed.model.width, ed.model.height,
		(ed.model.units as Array).filter(func(u): return u.faction != "enemy").size(),
		(ed.model.units as Array).filter(func(u): return u.faction == "enemy").size()])
	print("[editor] 读取战场: %s" % path)  # L1 埋点
	return { "ok": true }


## 保存当前模型：面板输入回写 model、被引用素材快照入档、save_model 落盘。
static func apply_save(ed) -> Dictionary:
	ed.model.id = ed._id_edit.text
	ed.model.name = ed._name_edit.text if not ed._name_edit.text.strip_edges().is_empty() else "自定义战场"
	ed.model.hosting = ed._hosting_check.button_pressed
	sync_user_assets(ed.model, ed._asset_service)  # 被引用素材描述符快照入档（B2 渲染离线自包含）
	var result: Dictionary = BattlefieldDocScript.save_model(ed.model)
	if bool(result.get("ok", false)):
		print("[editor] 保存战场: %s" % result.get("path", ""))  # L1 埋点
	else:
		print("[editor] 保存失败: %s" % result.get("error", ""))
	return result
