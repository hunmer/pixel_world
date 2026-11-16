## campaign_profile_store.gd — 冒险档案磁盘存取（BattleSaveStore 包装）
##
## 职责：以 base_dir（默认 user://campaign_saves）隔离冒险存档目录，
## identity = "campaign:<profile_id>"，复用 BattleSaveStore 的原子写（tmp→bak→main）。
##
## 读取语义（read_layers，供上层做 codec 级回退）：主档与备份分层返回，JSON 解析
## 在本层，结构校验在上层（session+codec）——主档"合法 JSON 但结构损坏"时由上层
## 决定是否回退验证后的备份；未来版本主档由上层直接拒绝、绝不回退旧备份。
##
## 删除语义：支持彻底损坏档案的确认删除——按 identity 定位失败后按内容 id 扫描，
## 再按文件名兜底（列表对损坏档以文件名为 id）；只清理 base_dir 内该 stem 的
## 主档/.bak/.tmp，路径经安全净化，不可能越出目录。

class_name CampaignProfileStore
extends RefCounted

const BattleSaveStoreScript := preload("res://scripts/core/battle_save_store.gd")
const CodecScript := preload("res://scripts/campaign/campaign_profile_codec.gd")

var base_dir := "user://campaign_saves"

var _store: RefCounted


func _ensure() -> RefCounted:
	if _store == null:
		_store = BattleSaveStoreScript.new()
		_store.base_dir = base_dir
	return _store


## 档案 id -> 存档身份（文件名会被 BattleSaveStore 安净化）。
static func identity_for(profile_id: String) -> String:
	return "campaign:" + profile_id


## 落盘一条档案 record（须含 id）。注入 identity 供 BattleSaveStore.load_latest
## 的 saved_at 扫描识别（与 index.latest 同形状）。
## 写前两道保护：
## 1) 未来版本保护：主档或备份任一是未来版本（codec newer）时直接拒绝写入
##    （{ok:false,newer:true}）——旧 store 的轮换（删 bak→main→bak）会把未来
##    版本文件覆盖掉，这里在任何写入发生前拦截。
## 2) 备份保护自愈：主档损坏（JSON 坏/结构坏/缺失）且备份 codec 校验通过时，
##    先把备份原文复制回主档并通过校验，才进入旧 store 的轮换写；任何时刻
##    至少保留一份有效档。备份无效时无从保护，按普通写入处理。
func save_profile(record: Dictionary) -> Dictionary:
	var profile_id := str(record.get("id", ""))
	if profile_id == "":
		return {"ok": false, "error": "record 缺少 id，无法落盘"}
	var heal: Dictionary = _heal_main_from_bak(profile_id)
	if not heal.get("ok", false):
		return heal
	record["identity"] = identity_for(profile_id)
	return _ensure().save_record(identity_for(profile_id), record)


## JSON 层快速读取（主档坏 JSON 时回退备份）。{ok,record,from_bak} 或 {ok:false,...}。
func load_profile_record(profile_id: String) -> Dictionary:
	if profile_id == "":
		return {"ok": false, "missing": true, "error": "档案 id 为空"}
	return _ensure().load_record(identity_for(profile_id))


## 记录最近使用（最近加载/新建）的档案 id（索引失败由调用方静默容忍）。
func set_latest_profile(profile_id: String) -> void:
	if profile_id == "":
		return
	_ensure().set_latest(identity_for(profile_id))


## 最近使用档案 id（无索引/无档案时返回 ""，非法前缀返回 ""）。
func load_latest_profile() -> String:
	var identity := str(_ensure().load_latest())
	const PREFIX := "campaign:"
	if not identity.begins_with(PREFIX):
		return ""
	return identity.substr(PREFIX.length())


## 分层读取主档与备份（JSON 层解析，不做 codec 校验）。
## 返回 {missing:bool, main:{present,record?|broken?}, bak:{present,record?|broken?}}。
func read_layers(profile_id: String) -> Dictionary:
	if profile_id == "":
		return {"missing": true, "main": {}, "bak": {}}
	var paths := _paths_for(identity_for(profile_id))
	var main_layer := _read_layer(paths.main)
	var bak_layer := _read_layer(paths.bak)
	var missing: bool = not main_layer.get("present", false) and not bak_layer.get("present", false)
	return {"missing": missing, "main": main_layer, "bak": bak_layer}


## 删除档案（主档+备份+临时残留）。定位顺序：identity 路径 -> 内容 id 扫描 ->
## 文件名兜底（列表把损坏档的文件名当 id）。都不存在时报"档案不存在"。
## 只删除 base_dir 内匹配 stem 的 main/.bak/.tmp。
func delete_profile(profile_id: String) -> Dictionary:
	if profile_id == "":
		return {"ok": false, "error": "档案 id 为空"}
	var paths := _paths_for(identity_for(profile_id))
	var res := _remove_files([paths.main, paths.bak, paths.tmp, paths.heal_tmp])
	if not res.get("ok", false):
		return res
	if res.get("removed_any", false):
		_clear_latest_index_if(identity_for(profile_id))
		return {"ok": true, "error": "", "deleted": true}
	# 内容 id 扫描（主档名损坏但 record.id 仍可读）
	for entry: Variant in list_records():
		if entry is Dictionary and entry.get("record") is Dictionary:
			if str((entry.record as Dictionary).get("id", "")) == profile_id:
				var stem := _stem_of(str(entry.file))
				var ok_res := _remove_stem(stem)
				if ok_res.get("removed_any", false):
					_clear_latest_index_if(identity_for(profile_id))
					return {"ok": true, "error": "", "deleted": true}
	# 文件名兜底（彻底损坏档：列表以文件名为 id）
	for entry: Variant in list_records():
		if entry is Dictionary:
			var fname := str(entry.get("file", ""))
			if fname != "" and (fname == profile_id or fname == profile_id + ".json"):
				var stem := _stem_of(fname)
				var ok_res := _remove_stem(stem)
				if ok_res.get("removed_any", false):
					_clear_latest_index_if(identity_for(profile_id))
					return {"ok": true, "error": "", "deleted": true}
	return {"ok": false, "error": "档案不存在"}


## 列出目录内全部档案（含孤儿备份），按文件名排序（确定性）。
## 条目携带 main/bak 两层原始信息（供上层做 codec 级同口径选择），
## 同时保留 JSON 层首选的 record（主档优先，主档坏 JSON 回退备份时 from_bak=true）
## 与旧字段 file/error（delete 扫描与损坏档兜底 id 使用）。
func list_records() -> Array:
	var out: Array = []
	var dir := DirAccess.open(base_dir)
	if dir == null:
		return out
	var mains := {}
	var baks := {}
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json.bak"):
			if fname != "index.json.bak":
				baks[fname.substr(0, fname.length() - ".json.bak".length())] = fname
		elif fname.ends_with(".json") and fname != "index.json":
			mains[fname.substr(0, fname.length() - ".json".length())] = fname
		fname = dir.get_next()
	dir.list_dir_end()
	var stems: Array = []
	for stem in mains:
		stems.append(stem)
	for stem in baks:
		if not mains.has(stem):
			stems.append(stem)
	stems.sort()
	for stem in stems:
		var main_name: String = mains.get(stem, stem + ".json")
		var bak_name: String = baks.get(stem, "")
		var main_layer: Dictionary = _read_layer(base_dir.path_join(main_name))
		var bak_layer: Dictionary = {} if bak_name == "" else _read_layer(base_dir.path_join(bak_name))
		var entry: Dictionary = {
			"file": main_name,
			"stem": stem,
			"main": main_layer,
			"bak": bak_layer,
		}
		# JSON 层首选 record（主档优先，回退备份），供 delete 扫描与旧调用方使用
		var primary: Dictionary = {}
		var from_bak := false
		if main_layer.has("record"):
			primary = main_layer
		elif bak_layer.has("record"):
			primary = bak_layer
			from_bak = true
		if not primary.is_empty():
			entry["record"] = primary.record
			if from_bak:
				entry["from_bak"] = true
		else:
			entry["error"] = "解析失败"
		out.append(entry)
	return out


## 清空存档目录（仅测试用）。
func clear_all() -> void:
	_ensure().clear_all()


# ============================================================
# 内部：路径与受限删除
# ============================================================

## save_profile 的前置检查：未来版本守卫 + 备份保护自愈。
## 返回 {ok:true,healed:bool} 可继续写入；{ok:false,newer:true,error} 拒绝写入
## （主档或备份是未来版本——轮换会覆盖它们）；{ok:false,error} 自愈失败
## （备份未动，磁盘原状可重试）。
## 自愈流程全程不动备份：读备份原文 → 写 heal 临时文件 → 重新读取并 codec 校验 →
## 转正为主档 → 复核；任何一步失败即清理临时文件返回错误。
func _heal_main_from_bak(profile_id: String) -> Dictionary:
	var paths := _paths_for(identity_for(profile_id))
	var main_layer := _read_layer(paths.main)
	var main_restored: Dictionary = {}
	if main_layer.has("record"):
		main_restored = CodecScript.restore(main_layer.record)
		if main_restored.get("newer", false):
			return {"ok": false, "newer": true,
				"error": "主档为未来版本，已拒绝写入以避免覆盖"}
		if main_restored.get("ok", false):
			return {"ok": true, "healed": false}
	var bak_layer := _read_layer(paths.bak)
	if not bak_layer.has("record"):
		return {"ok": true, "healed": false}
	var bak_restored: Dictionary = CodecScript.restore(bak_layer.record)
	if bak_restored.get("newer", false):
		return {"ok": false, "newer": true,
			"error": "备份为未来版本，已拒绝写入以避免覆盖"}
	if not bak_restored.get("ok", false):
		return {"ok": true, "healed": false}
	var raw := FileAccess.get_file_as_string(paths.bak)
	if raw.is_empty():
		return {"ok": true, "healed": false}
	var heal_tmp: String = paths.heal_tmp
	var f := FileAccess.open(heal_tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "主档自愈写入失败（备份未动）: %s" % paths.main}
	f.store_string(raw)
	f.close()
	if not _verify_heal_file(heal_tmp):
		_try_remove(heal_tmp)
		return {"ok": false, "error": "主档自愈校验失败（备份未动）"}
	var rename_err := DirAccess.rename_absolute(heal_tmp, paths.main)
	if rename_err != OK:
		# 转正失败：清掉损坏主档后重试一次；仍失败则放弃（主档仍坏、备份未动）
		DirAccess.remove_absolute(paths.main)
		rename_err = DirAccess.rename_absolute(heal_tmp, paths.main)
		if rename_err != OK:
			_try_remove(heal_tmp)
			return {"ok": false, "error": "主档自愈转正失败（备份未动）: %s" % error_string(rename_err)}
	if not _verify_heal_file(paths.main):
		return {"ok": false, "error": "主档自愈后复核失败（备份未动）"}
	return {"ok": true, "healed": true}


## 文件可解析为 JSON Dictionary 且通过 codec 校验。
func _verify_heal_file(path: String) -> bool:
	var layer := _read_layer(path)
	if not layer.has("record"):
		return false
	return CodecScript.restore(layer.record).get("ok", false)


func _try_remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

## 索引指向刚删除的档案时清掉 index（index+index.bak，容错：清不掉不报错）。
func _clear_latest_index_if(identity: String) -> void:
	if str(_ensure().load_latest()) != identity:
		return
	_remove_files([
		base_dir.path_join("index.json"),
		base_dir.path_join("index.json.bak"),
	])

## 身份 -> 文件名 stem（与 BattleSaveStore._file_path 同规则：可读前缀+sha1 前 8 位）。
static func _safe_stem(identity: String) -> String:
	var safe := ""
	for i in identity.length():
		var c := identity[i]
		var ok_char := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
			or (c >= "0" and c <= "9") or c == "_" or c == "-"
		safe += c if ok_char else "_"
	return safe + "_" + identity.sha1_text().substr(0, 8)


func _paths_for(identity: String) -> Dictionary:
	var stem := _safe_stem(identity)
	return {
		"main": base_dir.path_join(stem + ".json"),
		"bak": base_dir.path_join(stem + ".json.bak"),
		"tmp": base_dir.path_join(stem + ".json.tmp"),
		"heal_tmp": base_dir.path_join(stem + ".json.heal.tmp"),
	}


## 文件名（含或不含 .json）-> stem；含路径分隔符或 ".." 时返回 ""（拒绝）。
static func _stem_of(fname: String) -> String:
	if fname == "" or fname.contains("/") or fname.contains("\\") or fname.contains(".."):
		return ""
	var stem := fname
	if stem.ends_with(".json"):
		stem = stem.substr(0, stem.length() - ".json".length())
	return stem


## 删除某 stem 的主档/.bak/.tmp/.heal.tmp（全部在 base_dir 内）。
func _remove_stem(stem: String) -> Dictionary:
	if stem == "":
		return {"ok": false, "error": "非法文件名"}
	return _remove_files([
		base_dir.path_join(stem + ".json"),
		base_dir.path_join(stem + ".json.bak"),
		base_dir.path_join(stem + ".json.tmp"),
		base_dir.path_join(stem + ".json.heal.tmp"),
	])


func _remove_files(paths: Array) -> Dictionary:
	var removed_any := false
	for raw_path: Variant in paths:
		var path := str(raw_path)
		if path == "" or not path.begins_with(base_dir):
			continue
		if FileAccess.file_exists(path):
			var err := DirAccess.remove_absolute(path)
			if err != OK:
				return {"ok": false, "error": "删除失败 %s: %s" % [path, error_string(err)]}
			removed_any = true
	return {"ok": true, "error": "", "removed_any": removed_any}


func _read_layer(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"present": false}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK or json.data is not Dictionary:
		return {"present": true, "broken": "JSON 解析失败"}
	return {"present": true, "record": json.data}
