## editor_region_preset_store_contract.gd — 区域预设存储的纯数据持久化契约

extends SceneTree

const PresetStoreScript = preload("res://scripts/editor/region_preset_store.gd")
const RegionClipboardScript = preload("res://scripts/editor/region_clipboard.gd")
const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const TEST_ROOT := "user://test_editor_presets"

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_tree(TEST_ROOT)
	var store = PresetStoreScript.new(TEST_ROOT)
	_check(store.list().is_empty(), "空目录 list 应为空")
	_check(store.count() == 0, "空目录 count 应为 0")
	_check(not store.has("preset_1"), "空目录不应含预设")
	_check(store.load("preset_1").is_empty(), "缺失预设 load 应为空")
	_check(not FileAccess.file_exists(TEST_ROOT.path_join("presets.json")), "读取空目录不应落盘")

	var payload := _make_payload()
	_check(not payload.is_empty(), "测试 payload 应可提取")
	_check(RegionClipboardScript.validate(payload).is_empty(), "测试 payload 应合法")
	var first: Dictionary = store.save("  同名区域  ", payload)
	_check(bool(first.get("ok", false)), "首次 save 应成功：%s" % String(first.get("error", "")))
	var first_id := String(first.get("id", ""))
	_check(not first_id.is_empty(), "首次 save 应返回 id")
	_check(String(first.get("error", "x")).is_empty(), "成功 save 的 error 应为空")
	_check(store.count() == 1, "首次 save 后 count 应为 1")
	_check(store.has(first_id), "首次 save 后 has 应为 true")
	_check(FileAccess.file_exists(store.path), "save 应真实创建 presets.json")
	_check(not FileAccess.file_exists(store.path + ".tmp"), "成功后不应残留 tmp")
	_check(not FileAccess.file_exists(store.path + ".bak"), "成功后不应残留 bak")

	var entries: Array[Dictionary] = store.list()
	_check(entries.size() == 1, "save 后 list 应有一项")
	if entries.size() == 1:
		var meta := entries[0]
		_check(String(meta.get("id", "")) == first_id, "list 应返回相同 id")
		_check(String(meta.get("name", "")) == "同名区域", "name 应去首尾空白")
		_check(int(meta.get("saved_at", 0)) > 0, "list 应包含 saved_at")
		_check(int(meta.get("w", 0)) == 4 and int(meta.get("h", 0)) == 4, "list 应返回 payload 尺寸")
		_check(int(meta.get("units", -1)) == 1, "list 应统计 units")
		_check(int(meta.get("props", -1)) == 2, "list 应统计 props")
		_check(int(meta.get("overrides", -1)) == 1, "list 应统计 tile_overrides")

	var reopened = PresetStoreScript.new(TEST_ROOT)
	_check(reopened.count() == 1, "新实例应读回持久化数据")
	_check(reopened.has(first_id), "新实例应识别既有 id")
	var loaded: Dictionary = reopened.load(first_id)
	_check(loaded == payload, "payload 整体 round-trip 应相等")
	for key in ["version", "w", "h", "rows", "block_z", "tile_overrides", "props", "units"]:
		_check(loaded.get(key, null) == payload.get(key, null), "payload 键 %s 应逐值相等" % key)
	_check(reopened.load("missing").is_empty(), "未知 id load 应为空")

	var second: Dictionary = reopened.save("同名区域", payload)
	_check(bool(second.get("ok", false)), "同名第二次 save 应成功")
	var second_id := String(second.get("id", ""))
	_check(not second_id.is_empty() and second_id != first_id, "同名 save 必须生成不同 id")
	_check(reopened.count() == 2, "同名 save 不应覆盖旧预设")
	_check(reopened.load(first_id) == payload, "同名 save 后旧 payload 应保持")
	var ordered: Array[Dictionary] = reopened.list()
	_check(ordered.size() == 2, "同名 save 后 list 应为两项")
	if ordered.size() == 2:
		_check(String(ordered[0].id) == first_id and String(ordered[1].id) == second_id,
			"同 saved_at 时也应按 id 保存顺序列出")
		_check(int(ordered[0].saved_at) <= int(ordered[1].saved_at), "list 应按 saved_at 升序")

	_check(reopened.rename(second_id, "  改名区域  "), "rename 既有 id 应成功")
	_check(not reopened.rename(second_id, " \t "), "空白 rename 应拒绝")
	_check(not reopened.rename("missing", "名字"), "未知 id rename 应失败")
	_check(reopened.count() == 2, "rename 不应改变数量")
	_check(reopened.load(second_id) == payload, "rename 不应改变 payload")
	var renamed := _find_entry(reopened.list(), second_id)
	_check(String(renamed.get("name", "")) == "改名区域", "rename 应作用于同一 id 并去空白")
	_check(String(renamed.get("id", "")) == second_id, "rename 后 id 不应变化")

	var bytes_before_blank := _read_text(store.path)
	var blank: Dictionary = reopened.save(" \t\n ", payload)
	_check(not bool(blank.get("ok", true)), "空白名称 save 应失败")
	_check(String(blank.get("id", "x")).is_empty(), "空白名称 save 不应返回 id")
	_check(not String(blank.get("error", "")).is_empty(), "空白名称 save 应返回中文错误")
	_check(reopened.count() == 2, "空白名称 save 不应增加数量")
	_check(_read_text(store.path) == bytes_before_blank, "空白名称 save 不应改写文件")

	_check(reopened.delete(first_id), "delete 既有 id 应成功")
	_check(not reopened.has(first_id), "delete 后 has 应为 false")
	_check(reopened.load(first_id).is_empty(), "delete 后 load 应为空")
	_check(reopened.count() == 1, "delete 后 count 应减一")
	_check(not reopened.delete(first_id), "重复 delete 应失败")
	_check(reopened.has(second_id), "delete 不应影响其它预设")

	_write_text(store.path, "{broken json")
	var corrupt = PresetStoreScript.new(TEST_ROOT)
	_check(corrupt.list().is_empty(), "损坏 JSON 的 list 应为空")
	_check(corrupt.count() == 0, "损坏 JSON 的 count 应为 0")
	_check(corrupt.load(second_id).is_empty(), "损坏 JSON 不应返回半份 payload")
	_check(not corrupt.has(second_id), "损坏 JSON 的 has 应为 false")
	var recovered: Dictionary = corrupt.save("损坏后恢复", payload)
	_check(bool(recovered.get("ok", false)), "损坏 JSON 后 save 应重建文件：%s" % String(recovered.get("error", "")))
	var recovered_id := String(recovered.get("id", ""))
	_check(corrupt.count() == 1, "损坏 JSON 重建后应只有新预设")
	_check(corrupt.load(recovered_id) == payload, "损坏 JSON 重建后 payload 应可读回")

	_write_text(store.path, '{"version":1,"presets":[]}')
	var missing_fields = PresetStoreScript.new(TEST_ROOT)
	_check(missing_fields.list().is_empty(), "必要字段缺失时 list 应为空")
	var rebuilt: Dictionary = missing_fields.save("缺字段后恢复", payload)
	_check(bool(rebuilt.get("ok", false)), "必要字段缺失后 save 应重建文件")
	_check(missing_fields.load(String(rebuilt.get("id", ""))) == payload, "缺字段重建后应可 round-trip")
	_check(not FileAccess.file_exists(store.path + ".tmp"), "全部写操作后不应残留 tmp")
	_check(not FileAccess.file_exists(store.path + ".bak"), "全部写操作后不应残留 bak")

	_remove_tree(TEST_ROOT)
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(TEST_ROOT)), "测试结束应递归清理测试目录")
	if _failures == 0:
		print("EDITOR_REGION_PRESET_STORE_CONTRACT_OK: %d assertions" % _checks)
	else:
		printerr("EDITOR_REGION_PRESET_STORE_CONTRACT_FAIL: %d of %d assertions failed" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


func _make_payload() -> Dictionary:
	var model := BattlefieldDocScript.create_empty(4, 4)
	BattlefieldDocScript.set_cell_z(model, Vector2i(1, 1), 3)
	BattlefieldDocScript.set_tile_override(model, Vector2i(2, 2), "test/tile_override")
	BattlefieldDocScript.set_prop(model, Vector2i(0, 1), "res://test_prop.png")
	BattlefieldDocScript.set_prop_asset(model, Vector2i(1, 2), "test/plant_asset")
	model.units.append({
		"class": "hero", "name": "测试单位", "level": 2,
		"x": 3, "y": 3, "faction": "player", "tag": "round_trip",
	})
	return RegionClipboardScript.extract(model, Vector2i.ZERO, Vector2i(3, 3))


func _find_entry(entries: Array[Dictionary], id: String) -> Dictionary:
	for entry in entries:
		if String(entry.get("id", "")) == id:
			return entry
	return {}


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if dir.current_is_dir():
				_remove_tree(child)
			else:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
