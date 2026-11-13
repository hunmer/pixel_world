## battle_save_store.gd — 战棋存档的磁盘读写（user://battle_saves/）
## 职责：按稳定身份分文件持久化；tmp+bak 两段式原子写（先复核再轮换）；
## 主档损坏回退 .bak；索引损坏时扫描存档文件自恢复最近记录。
## 本类只做 IO 与 JSON 往返，不做业务校验（那是 BattleSaveCodec 的事）。

class_name BattleSaveStore
extends RefCounted

const INDEX_FILE := "index.json"

var base_dir := "user://battle_saves"


# ============================================================
# 记录读写
# ============================================================

## 原子写入一条存档记录。任何一步失败都不破坏上一次的有效存档。
func save_record(identity: String, record: Dictionary) -> Dictionary:
	var dir_err := _ensure_dir()
	if dir_err != "":
		return {"ok": false, "error": dir_err}
	return _write_json(_file_path(identity), record)


## 读取一条存档记录（原始字典，未经业务校验）。
## 返回 {ok, record, from_bak} / {ok:false, missing:true} / {ok:false, corrupt:true, error}。
func load_record(identity: String) -> Dictionary:
	var path := _file_path(identity)
	var main_res := _read_json(path)
	if main_res.ok:
		return {"ok": true, "record": main_res.data, "from_bak": false}
	var bak_res := _read_json(path + ".bak")
	if bak_res.ok:
		push_warning("[battle_save_store] 主档不可读，回退备份: %s" % path)
		return {"ok": true, "record": bak_res.data, "from_bak": true}
	if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak"):
		return {"ok": false, "corrupt": true, "error": "存档损坏且备份不可用: %s" % path}
	return {"ok": false, "missing": true}


## 轻量窥探：只取展示所需字段（不深校验），供战场列表显示进度。
func peek(identity: String) -> Dictionary:
	var res := _read_json(_file_path(identity))
	if not res.ok:
		res = _read_json(_file_path(identity) + ".bak")
		if not res.ok:
			return {"exists": false}
	var d: Dictionary = res.data
	if int(d.get("version", 0)) != 1:
		return {"exists": true, "unknown_version": true}
	var info := {"exists": true, "saved_at": float(d.get("saved_at", 0.0))}
	var state: Variant = d.get("state")
	if state is Dictionary:
		info["turn_number"] = int(state.get("turn_number", 1))
		info["phase"] = String(state.get("phase", "player"))
		info["result"] = String(state.get("result", ""))
	return info


## 删除一条记录（主档+备份+临时残留）。若最近索引指向它则清空索引。
func delete_record(identity: String) -> Dictionary:
	var path := _file_path(identity)
	var removed_any := false
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			var err := DirAccess.remove_absolute(p)
			if err != OK:
				return {"ok": false, "error": "删除失败 %s: %s" % [p, error_string(err)]}
			removed_any = true
	if load_latest() == identity:
		# 清空最近索引：连 .bak 一起删除（写空值会把旧值轮换进 .bak 继续生效）
		for idx_path in [base_dir.path_join(INDEX_FILE), base_dir.path_join(INDEX_FILE + ".bak")]:
			if FileAccess.file_exists(idx_path):
				var rm_err := DirAccess.remove_absolute(idx_path)
				if rm_err != OK:
					return {"ok": false, "error": "索引清理失败 %s: %s" % [idx_path, error_string(rm_err)]}
	return {"ok": true, "deleted": removed_any}


## 清空整个存档目录（仅测试用）。
func clear_all() -> void:
	var dir := DirAccess.open(base_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname != "." and fname != "..":
			dir.remove(fname)
		fname = dir.get_next()
	dir.list_dir_end()


# ============================================================
# 最近记录索引
# ============================================================

## 更新最近一次进入的战场身份。
func set_latest(identity: String) -> Dictionary:
	var dir_err := _ensure_dir()
	if dir_err != "":
		return {"ok": false, "error": dir_err}
	return _write_index(identity)


## 读取最近战场身份；索引损坏时扫描全部存档按 saved_at 恢复。空串表示无记录。
func load_latest() -> String:
	for suffix in ["", ".bak"]:
		var res := _read_json(base_dir.path_join(INDEX_FILE + suffix))
		if res.ok:
			var latest: Variant = res.data.get("latest")
			if latest is String and not String(latest).is_empty():
				return String(latest)
	return _scan_latest_identity()


## 列出目录内全部存档文件名（不含 index）。
func list_record_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(base_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json") and fname != INDEX_FILE:
			out.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return out


# ============================================================
# 内部：路径与原子写
# ============================================================

## 身份 -> 稳定文件名：可读前缀 + sha1 前 8 位防清洗碰撞。
func _file_path(identity: String) -> String:
	var safe := ""
	for i in identity.length():
		var c := identity[i]
		var ok_char := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
			or (c >= "0" and c <= "9") or c == "_" or c == "-"
		safe += c if ok_char else "_"
	var stem := safe + "_" + identity.sha1_text().substr(0, 8)
	return base_dir.path_join(stem + ".json")


func _ensure_dir() -> String:
	if DirAccess.dir_exists_absolute(base_dir):
		return ""
	var err := DirAccess.make_dir_recursive_absolute(base_dir)
	if err != OK:
		return "无法创建存档目录 %s: %s" % [base_dir, error_string(err)]
	return ""


func _write_index(latest: String) -> Dictionary:
	return _write_json(base_dir.path_join(INDEX_FILE), {
		"version": 1,
		"latest": latest,
		"updated_at": Time.get_unix_time_from_system(),
	})


## tmp+bak 两段式原子写：写 tmp -> 复核 -> main 轮换为 bak -> tmp 转正。
func _write_json(path: String, data: Dictionary) -> Dictionary:
	var tmp_path := path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "无法写入 %s（%s）" % [tmp_path, error_string(FileAccess.get_open_error())]}
	var txt := JSON.stringify(data)
	if txt.is_empty():
		f.close()
		return {"ok": false, "error": "序列化结果为空"}
	var stored := f.store_string(txt)
	f.close()
	if not stored:
		return {"ok": false, "error": "写入失败: %s" % tmp_path}
	var check := FileAccess.open(tmp_path, FileAccess.READ)
	if check == null:
		return {"ok": false, "error": "无法复核 %s" % tmp_path}
	var size := check.get_length()
	check.close()
	if size < txt.length():
		return {"ok": false, "error": "临时文件不完整: %s（%d/%d）" % [tmp_path, size, txt.length()]}
	# 轮换备份（Windows rename 不覆盖目标，先删旧 bak）
	if FileAccess.file_exists(path + ".bak"):
		var rm_err := DirAccess.remove_absolute(path + ".bak")
		if rm_err != OK:
			return {"ok": false, "error": "清理旧备份失败（原档未动）: %s" % error_string(rm_err)}
	if FileAccess.file_exists(path):
		var bak_err := DirAccess.rename_absolute(path, path + ".bak")
		if bak_err != OK:
			return {"ok": false, "error": "轮换备份失败（原档未动）: %s" % error_string(bak_err)}
	var ren_err := DirAccess.rename_absolute(tmp_path, path)
	if ren_err != OK:
		# 回滚：把 bak 放回 main，保证至少有一份有效档
		if FileAccess.file_exists(path + ".bak") and not FileAccess.file_exists(path):
			DirAccess.rename_absolute(path + ".bak", path)
		return {"ok": false, "error": "落盘失败: %s" % error_string(ren_err)}
	return {"ok": true}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "文件不存在: %s" % path}
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return {"ok": false, "error": "文件为空: %s" % path}
	var json := JSON.new()
	if json.parse(txt) != OK:
		return {"ok": false, "error": "JSON 解析失败 %s: %s" % [path, json.get_error_message()]}
	if not json.data is Dictionary:
		return {"ok": false, "error": "顶层不是对象: %s" % path}
	return {"ok": true, "data": json.data}


## 索引全损时的自恢复：扫全部存档取 saved_at 最大者的 identity。
func _scan_latest_identity() -> String:
	var best_id := ""
	var best_time := -1.0
	for fname in list_record_files():
		var res := _read_json(base_dir.path_join(fname))
		if not res.ok:
			continue
		var idv: Variant = res.data.get("identity")
		var ts: Variant = res.data.get("saved_at")
		if idv is String and (ts is float or ts is int) and float(ts) > best_time:
			best_time = float(ts)
			best_id = String(idv)
	return best_id
