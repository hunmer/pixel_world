extends SceneTree

## tests/battle_save_contract.gd — 战旗存档编解码 + 落盘契约测试
## 运行：godot --headless --path . --script res://tests/battle_save_contract.gd
## 覆盖：真实战场的 chapter 快照往返 / 完整状态(state)往返 / JSON 磁盘序列化 /
##       原子写与损坏回退 / 版本拒绝 / 最近索引 / 删除。

const Codec := preload("res://scripts/core/battle_save_codec.gd")
const Store := preload("res://scripts/core/battle_save_store.gd")
const Loader := preload("res://scripts/core/battlefield_loader.gd")

const TMP_DIR := "user://battle_save_contract_tmp"
const SRC := "res://data/battlefields/plains_skirmish.json"

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = Loader.load_battlefield(SRC)
	_expect(bool(loaded.get("ok", false)), "plains_skirmish 加载失败: %s" % String(loaded.get("error", "")))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	var chapter: Dictionary = loaded["chapter"]
	var info: Dictionary = loaded["info"]

	_test_validate_and_roundtrip(chapter, info)
	_test_state_roundtrip(chapter)
	_test_json_disk_roundtrip(chapter, info)
	_test_corruption_and_version(chapter, info)
	_test_latest_index_and_delete(chapter, info)

	# 清理临时目录
	var dir := DirAccess.open(TMP_DIR)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
		dir.change_dir("..")
		dir.remove(TMP_DIR.get_file())
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("BATTLE_SAVE_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error("[battle_save_contract] %s" % failure)
		quit(1)


# ------------------------------------------------------------------
# 真实战场校验 + chapter 快照往返
# ------------------------------------------------------------------
func _test_validate_and_roundtrip(chapter: Dictionary, info: Dictionary) -> void:
	_expect(Codec.validate_chapter(chapter) == "",
		"真实战场 chapter 应通过校验，实际: %s" % Codec.validate_chapter(chapter))
	var identity := "bf:res/%s" % String(info.get("id", "plains_skirmish"))
	var cap: Dictionary = Codec.capture(identity, "battlefield", SRC,
		chapter, chapter, _sample_state(), "sig-1")
	_expect(bool(cap.get("ok", false)), "capture 失败: %s" % String(cap.get("error", "")))
	if not bool(cap.get("ok", false)):
		return
	var rr: Dictionary = Codec.restore(cap["record"])
	_expect(bool(rr.get("ok", false)), "restore 失败: %s" % String(rr.get("error", "")))
	if not bool(rr.get("ok", false)):
		return
	# 全部单位（含蓄意标记的死亡单位）都要还原
	var n_units: int = (chapter["playerUnits"] as Array).size() + (chapter["enemyUnits"] as Array).size()
	var n_restored: int = (rr["chapter"]["playerUnits"] as Array).size() + (rr["chapter"]["enemyUnits"] as Array).size()
	_expect(n_restored == n_units, "单位数往返不一致 %d != %d" % [n_restored, n_units])
	# 逐字段抽查第一个单位
	var a0: Dictionary = (chapter["playerUnits"] as Array)[0]
	var b0: Dictionary = (rr["chapter"]["playerUnits"] as Array)[0]
	for field in ["id", "name", "faction", "level", "exp", "hp", "mp", "moveType"]:
		_expect(str(a0[field]) == str(b0[field]),
			"单位字段 %s 往返不一致 %s != %s" % [field, str(a0[field]), str(b0[field])])
	_expect(a0["position"] == b0["position"], "position 往返不一致")
	# 地图尺寸/网格
	_expect(int(rr["chapter"]["width"]) == int(chapter["width"]), "width 往返不一致")
	_expect(int(rr["chapter"]["height"]) == int(chapter["height"]), "height 往返不一致")
	# 身份元数据
	_expect(String(rr["identity"]) == identity, "identity 往返不一致")
	_expect(String(rr["source"]) == SRC, "source 往返不一致")
	_expect(String(rr.get("signature", "")) == "sig-1", "initial_signature 往返不一致")


func _sample_state() -> Dictionary:
	return {
		"turn_number": 3,
		"phase": &"enemy",
		"hosting": true,
		"prefs": {"ally_1": {"strategy": "aggressive", "priorityTargetId": "enemy_2"}},
		"result": &"",
	}


# ------------------------------------------------------------------
# 完整状态往返（含 StringName / 冷却 / 胜负）
# ------------------------------------------------------------------
func _test_state_roundtrip(chapter: Dictionary) -> void:
	# 修改出有意义的进度：掉血 / 行动标志 / 死亡 / 冷却 / buff / 物品次数
	var ch: Dictionary = chapter.duplicate(true)
	var p0: Dictionary = (ch["playerUnits"] as Array)[0]
	var e0: Dictionary = (ch["enemyUnits"] as Array)[0]
	var e1: Dictionary = (ch["enemyUnits"] as Array)[1] if (ch["enemyUnits"] as Array).size() > 1 else e0
	p0["hp"] = int(p0["hp"]) - 3
	p0["hasActed"] = true
	p0["hasMoved"] = true
	p0["skillCooldowns"] = {&"skill_fire": 2}
	e1["isDead"] = true
	e0["buffs"] = [{"stat": &"def", "value": 2, "turns": 1, "label": "护体"}]
	var items: Array = p0.get("items", [])
	if not items.is_empty():
		items[0]["uses"] = int(items[0]["uses"]) - 1
	# 死亡单位与活人不许重叠（校验应只对活人算重叠）
	var state := _sample_state()
	var cap: Dictionary = Codec.capture("bf:res/x", "battlefield", SRC, chapter, ch, state, "")
	_expect(bool(cap.get("ok", false)), "进度 capture 失败: %s" % String(cap.get("error", "")))
	if not bool(cap.get("ok", false)):
		return
	var rr: Dictionary = Codec.restore(cap["record"])
	_expect(bool(rr.get("ok", false)), "进度 restore 失败: %s" % String(rr.get("error", "")))
	if not bool(rr.get("ok", false)):
		return
	var r_p0: Dictionary = (rr["chapter"]["playerUnits"] as Array)[0]
	_expect(int(r_p0["hp"]) == int(p0["hp"]), "hp 进度往返不一致")
	_expect(bool(r_p0["hasActed"]) == true, "hasActed 往返不一致")
	var cd: Dictionary = r_p0.get("skillCooldowns", {})
	_expect(int(cd.get("skill_fire", -1)) == 2, "冷却往返不一致: %s" % str(cd))
	var r_e1: Dictionary = (rr["chapter"]["enemyUnits"] as Array)[1] if (rr["chapter"]["enemyUnits"] as Array).size() > 1 else (rr["chapter"]["enemyUnits"] as Array)[0]
	_expect(bool(r_e1["isDead"]) == true, "死亡标志往返不一致")
	var buffs: Array = (rr["chapter"]["enemyUnits"] as Array)[0].get("buffs", [])
	_expect(buffs.size() == 1 and int(buffs[0]["turns"]) == 1 and buffs[0]["stat"] == &"def",
		"buff 往返不一致: %s" % str(buffs))
	var rs: Dictionary = rr["state"]
	_expect(int(rs["turn_number"]) == 3, "turn_number 往返不一致")
	_expect(StringName(rs["phase"]) == &"enemy", "phase 往返不一致")
	_expect(bool(rs["hosting"]) == true, "hosting 往返不一致")
	var prefs: Dictionary = rs["prefs"]
	_expect(prefs.has("ally_1") and prefs["ally_1"]["strategy"] == "aggressive",
		"托管偏好往返不一致: %s" % str(prefs))
	# 终局状态
	state["result"] = &"win"
	var cap2: Dictionary = Codec.capture("bf:res/x", "battlefield", SRC, chapter, ch, state, "")
	var rr2: Dictionary = Codec.restore(cap2["record"])
	_expect(bool(rr2.get("ok", false)) and StringName(rr2["state"]["result"]) == &"win",
		"result=win 往返不一致")


# ------------------------------------------------------------------
# 磁盘 JSON 往返 + store 原子写
# ------------------------------------------------------------------
func _test_json_disk_roundtrip(chapter: Dictionary, info: Dictionary) -> void:
	var store: Store = Store.new()
	store.base_dir = TMP_DIR
	var identity := "bf:res/%s" % String(info.get("id", "plains_skirmish"))
	var cap: Dictionary = Codec.capture(identity, "battlefield", SRC,
		chapter, chapter, _sample_state(), "sig-disk")
	_expect(bool(cap.get("ok", false)), "disk capture 失败")
	var sv: Dictionary = store.save_record(identity, cap["record"])
	_expect(bool(sv.get("ok", false)), "save_record 失败: %s" % str(sv))
	var ld: Dictionary = store.load_record(identity)
	_expect(bool(ld.get("ok", false)), "load_record 失败: %s" % str(ld))
	if bool(ld.get("ok", false)):
		var rr: Dictionary = Codec.restore(ld["record"])
		_expect(bool(rr.get("ok", false)), "磁盘往返 restore 失败: %s" % String(rr.get("error", "")))
	# peek 摘要
	var pk: Dictionary = store.peek(identity)
	_expect(bool(pk.get("exists", false)), "peek 应找到记录")
	_expect(int(pk.get("turn_number", -1)) == 3, "peek turn_number 不一致")
	_expect(String(pk.get("phase", "")) == "enemy", "peek phase 不一致")


# ------------------------------------------------------------------
# 主档损坏回退 .bak / 新版本拒绝 / 损坏提示
# ------------------------------------------------------------------
func _test_corruption_and_version(chapter: Dictionary, info: Dictionary) -> void:
	var store: Store = Store.new()
	store.base_dir = TMP_DIR
	var identity := "bf:res/corrupt-case"
	var cap: Dictionary = Codec.capture(identity, "battlefield", SRC, chapter, chapter, _sample_state(), "")
	store.save_record(identity, cap["record"])
	# 再写一次 → 产生 .bak；然后把主档写坏
	store.save_record(identity, cap["record"])
	var path: String = store._file_path(identity)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ not json !!!")
	f.close()
	var ld: Dictionary = store.load_record(identity)
	_expect(bool(ld.get("ok", false)) and bool(ld.get("from_bak", false)),
		"主档损坏应回退 .bak: %s" % str(ld))
	# 新版本记录：拒绝且不覆盖
	var newer: Dictionary = (cap["record"] as Dictionary).duplicate(true)
	newer["version"] = 99
	store.save_record(identity, newer)
	var ld2: Dictionary = store.load_record(identity)
	var rr: Dictionary = Codec.restore(ld2["record"])
	_expect(not bool(rr.get("ok", false)) and bool(rr.get("newer", false)),
		"version=99 应判定为 newer 且拒绝恢复")
	# 缺字段
	var broken: Dictionary = {"version": 1}
	var rr2: Dictionary = Codec.restore(broken)
	_expect(not bool(rr2.get("ok", false)), "缺字段记录应恢复失败")


# ------------------------------------------------------------------
# 最近索引 / 删除
# ------------------------------------------------------------------
func _test_latest_index_and_delete(chapter: Dictionary, info: Dictionary) -> void:
	var store: Store = Store.new()
	store.base_dir = TMP_DIR
	_expect(store.load_latest() == "" or not store.load_latest().is_empty(),
		"load_latest 不应崩溃")
	var ida := "bf:res/latest-a"
	var idb := "bf:res/latest-b"
	var cap: Dictionary = Codec.capture(ida, "battlefield", SRC, chapter, chapter, _sample_state(), "")
	store.save_record(ida, cap["record"])
	store.set_latest(ida)
	_expect(store.load_latest() == ida, "索引应指向 latest-a")
	var capb: Dictionary = Codec.capture(idb, "battlefield", SRC, chapter, chapter, _sample_state(), "")
	store.save_record(idb, capb["record"])
	store.set_latest(idb)
	_expect(store.load_latest() == idb, "索引应指向 latest-b")
	# 删除 latest 指向的记录 → 索引清空；有其他档案时回退到剩余最近者
	var del: Dictionary = store.delete_record(idb)
	_expect(bool(del.get("ok", false)), "delete_record 失败: %s" % str(del))
	_expect(store.load_latest() != idb, "删除后最近索引不应再指向已删档案")
	var gone: Dictionary = store.load_record(idb)
	_expect(bool(gone.get("missing", false)), "删除后应 missing")
	var still: Dictionary = store.load_record(ida)
	_expect(bool(still.get("ok", false)), "其他档案不应被删除")
	# 全空目录：最近索引应为空串
	var empty_store: Store = Store.new()
	empty_store.base_dir = TMP_DIR + "_empty"
	var idc := "bf:res/latest-c"
	var capc: Dictionary = Codec.capture(idc, "battlefield", SRC, chapter, chapter, _sample_state(), "")
	empty_store.save_record(idc, capc["record"])
	empty_store.set_latest(idc)
	empty_store.delete_record(idc)
	_expect(empty_store.load_latest() == "", "空目录最近索引应为空串，实际 %s" % empty_store.load_latest())
	var edir := DirAccess.open(TMP_DIR + "_empty")
	if edir != null:
		for f in edir.get_files():
			edir.remove(f)
		edir.change_dir("..")
		edir.remove((TMP_DIR + "_empty").get_file())
