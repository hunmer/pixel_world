## map_editor_file_io.gd — 战场 JSON 读取候选/存档素材快照/读取列表
##
## 存取档中不触碰 UI 的纯内核：战场文件打开与解析校验（load_candidate）、
## 保存前被引用素材描述符快照（sync_user_assets）、战场文件列表（refresh_load_box）。
## 全部 static；UI 回显与历史（undo/状态条/模式清理）留在 map_editor.gd 门面。

class_name MapEditorFileIo
extends RefCounted

const BattlefieldLoaderScript = preload("res://scripts/core/battlefield_loader.gd")
const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")


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
	return { "ok": true, "model": candidate }


## 保存前从素材库拷贝被引用素材的描述符快照进 model.user_assets：
## B2 渲染离线读档自包含（user_assets 缺失时按 id 回退库+占位）；
## 库中已隐藏/删除的素材保留模型里的旧快照，保证存档与历史引用不丢
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
