## region_preset_store.gd — 区域剪贴板 payload 的命名预设持久化内核
## 单文件保存全部预设；临时文件 + 备份 + rename 原子替换，损坏文件读取为空并可由 save 重建。

class_name EditorRegionPresetStore
extends RefCounted

const RegionClipboardScript = preload("res://scripts/editor/region_clipboard.gd")
const STORE_VERSION := 1
const DEFAULT_ROOT := "user://editor_presets"

var _root := DEFAULT_ROOT
var path := DEFAULT_ROOT.path_join("presets.json")


func _init(root: String = DEFAULT_ROOT) -> void:
	var clean_root := root.strip_edges()
	_root = clean_root if not clean_root.is_empty() else DEFAULT_ROOT
	path = _root.path_join("presets.json")


## 元数据按 saved_at 升序；同秒保存按递增 id 次序排列。
func list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var doc := _read_document()
	if doc.is_empty():
		return result
	for record_value in doc.presets:
		var record: Dictionary = record_value
		var payload: Dictionary = record.payload
		result.append({
			"id": String(record.id),
			"name": String(record.name),
			"saved_at": int(record.saved_at),
			"w": int(record.w),
			"h": int(record.h),
			"units": (payload.units as Array).size(),
			"props": (payload.props as Array).size(),
			"overrides": (payload.tile_overrides as Dictionary).size(),
		})
	result.sort_custom(_metadata_before)
	return result


## 同名也追加新 id；成功返回 {ok:true,id,error:""}。
func save(name: String, payload: Dictionary) -> Dictionary:
	var clean_name := name.strip_edges()
	if clean_name.is_empty():
		return {"ok": false, "id": "", "error": "预设名称不能为空"}
	var payload_error := RegionClipboardScript.validate(payload)
	if not payload_error.is_empty():
		return {"ok": false, "id": "", "error": "区域数据无效：%s" % payload_error}

	var doc := _read_document()
	if doc.is_empty():
		doc = _empty_document()
	var normalized := _normalize_payload(payload)
	var used_ids := {}
	for record_value in doc.presets:
		used_ids[String((record_value as Dictionary).get("id", ""))] = true
	var next_id := maxi(1, int(doc.get("next_id", 1)))
	var id := "preset_%d" % next_id
	while used_ids.has(id):
		next_id += 1
		id = "preset_%d" % next_id
	doc.next_id = next_id + 1
	doc.presets.append({
		"id": id,
		"name": clean_name,
		"saved_at": int(Time.get_unix_time_from_system()),
		"w": int(normalized.w),
		"h": int(normalized.h),
		"payload": normalized,
	})
	var write_result := _write_document(doc)
	if not bool(write_result.get("ok", false)):
		return {"ok": false, "id": "", "error": String(write_result.get("error", "预设保存失败"))}
	return {"ok": true, "id": id, "error": ""}


func load(id: String) -> Dictionary:
	var doc := _read_document()
	if doc.is_empty():
		return {}
	for record_value in doc.presets:
		var record: Dictionary = record_value
		if String(record.id) == id:
			return (record.payload as Dictionary).duplicate(true)
	return {}


func rename(id: String, name: String) -> bool:
	var clean_name := name.strip_edges()
	if clean_name.is_empty():
		return false
	var doc := _read_document()
	if doc.is_empty():
		return false
	for record_value in doc.presets:
		var record: Dictionary = record_value
		if String(record.id) == id:
			record.name = clean_name
			return bool(_write_document(doc).get("ok", false))
	return false


func delete(id: String) -> bool:
	var doc := _read_document()
	if doc.is_empty():
		return false
	for i in range(doc.presets.size()):
		if String(doc.presets[i].id) == id:
			doc.presets.remove_at(i)
			return bool(_write_document(doc).get("ok", false))
	return false


func has(id: String) -> bool:
	var doc := _read_document()
	if doc.is_empty():
		return false
	for record_value in doc.presets:
		if String((record_value as Dictionary).get("id", "")) == id:
			return true
	return false


func count() -> int:
	var doc := _read_document()
	return 0 if doc.is_empty() else (doc.presets as Array).size()


func _empty_document() -> Dictionary:
	return {"version": STORE_VERSION, "next_id": 1, "presets": []}


func _read_document() -> Dictionary:
	if not FileAccess.file_exists(path):
		return _empty_document()
	return _read_document_at(path)


## 任一必要字段损坏都视为整份存储无效；调用方不得把半份数据当成有效预设。
func _read_document_at(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {}
	var raw: Dictionary = json.data
	if not _is_integer(raw.get("version", null)) or int(raw.version) != STORE_VERSION:
		return {}
	if not _is_integer(raw.get("next_id", null)) or int(raw.next_id) < 1:
		return {}
	if not (raw.get("presets", null) is Array):
		return {}

	var presets: Array = []
	var seen_ids := {}
	for record_value in raw.presets:
		if not (record_value is Dictionary):
			return {}
		var record: Dictionary = record_value
		var id := String(record.get("id", ""))
		var name := String(record.get("name", ""))
		if id.is_empty() or name.strip_edges().is_empty() or seen_ids.has(id):
			return {}
		if not _is_integer(record.get("saved_at", null)):
			return {}
		if not _is_integer(record.get("w", null)) or not _is_integer(record.get("h", null)):
			return {}
		if not (record.get("payload", null) is Dictionary):
			return {}
		var payload: Dictionary = record.payload
		if not RegionClipboardScript.validate(payload).is_empty():
			return {}
		if int(record.w) != int(payload.w) or int(record.h) != int(payload.h):
			return {}
		seen_ids[id] = true
		presets.append({
			"id": id,
			"name": name,
			"saved_at": int(record.saved_at),
			"w": int(payload.w),
			"h": int(payload.h),
			"payload": _normalize_payload(payload),
		})
	return {"version": STORE_VERSION, "next_id": int(raw.next_id), "presets": presets}


func _write_document(doc: Dictionary) -> Dictionary:
	var make_dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_root))
	if make_dir_error != OK and make_dir_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": "无法创建预设目录（错误 %d）" % make_dir_error}
	var tmp := path + ".tmp"
	var bak := path + ".bak"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "无法写入预设临时文件"}
	file.store_string(JSON.stringify(doc, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_remove_file(tmp)
		return {"ok": false, "error": "预设临时文件写入失败（错误 %d）" % write_error}
	if _read_document_at(tmp).is_empty():
		_remove_file(tmp)
		return {"ok": false, "error": "预设临时文件回读校验失败"}

	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(bak))
			if remove_error != OK:
				_remove_file(tmp)
				return {"ok": false, "error": "无法清理旧预设备份（错误 %d）" % remove_error}
		var backup_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(bak))
		if backup_error != OK:
			_remove_file(tmp)
			return {"ok": false, "error": "备份旧预设失败，原文件未动（错误 %d）" % backup_error}
		var replace_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
		if replace_error != OK:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(bak), ProjectSettings.globalize_path(path))
			_remove_file(tmp)
			return {"ok": false, "error": "预设落盘失败，已回滚（错误 %d）" % replace_error}
		_remove_file(bak)
	else:
		var rename_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
		if rename_error != OK:
			_remove_file(tmp)
			return {"ok": false, "error": "预设落盘失败（错误 %d）" % rename_error}
	return {"ok": true, "error": ""}


func _normalize_payload(payload: Dictionary) -> Dictionary:
	var normalized := payload.duplicate(true)
	normalized.version = int(payload.version)
	normalized.w = int(payload.w)
	normalized.h = int(payload.h)
	var rows: Array[String] = []
	for row in payload.rows:
		rows.append(String(row))
	normalized.rows = rows
	var heights: Array[int] = []
	for height in payload.block_z:
		heights.append(int(height))
	normalized.block_z = heights
	for prop_value in normalized.props:
		var prop: Dictionary = prop_value
		prop.dx = int(prop.dx)
		prop.dy = int(prop.dy)
	for unit_value in normalized.units:
		var unit: Dictionary = unit_value
		unit.dx = int(unit.dx)
		unit.dy = int(unit.dy)
		unit.level = int(unit.level)
	return normalized


func _metadata_before(a: Dictionary, b: Dictionary) -> bool:
	var a_time := int(a.saved_at)
	var b_time := int(b.saved_at)
	if a_time != b_time:
		return a_time < b_time
	var a_id := String(a.id)
	var b_id := String(b.id)
	var a_sequence := a_id.trim_prefix("preset_").to_int()
	var b_sequence := b_id.trim_prefix("preset_").to_int()
	return a_id < b_id if a_sequence == b_sequence else a_sequence < b_sequence


func _is_integer(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_finite(value) and floor(value) == value


func _remove_file(file_path: String) -> void:
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
