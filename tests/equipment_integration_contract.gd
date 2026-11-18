## equipment_integration_contract.gd — 装备接线集成契约（Commit C）
##
## 覆盖：BattleSaveCodec 装备往返（chapter 快照 + JSON 磁盘序列化 + 坏装备拒绝）、
## CampaignSession 装卸 API（equip_item/unequip_item 原子性、职业授权、稳定 roster id、
## 出征挂起拒绝、结算后恢复、落盘往返、坏档 JSON 拒绝）。
## 临时目录：user://equipment_integration_tmp/<tag>（与其它契约互不污染）。
## 运行：godot --headless --path . --script res://tests/equipment_integration_contract.gd

extends SceneTree

const Codec := preload("res://scripts/core/battle_save_codec.gd")
const Loader := preload("res://scripts/core/battlefield_loader.gd")
const SessionScript := preload("res://scripts/campaign/campaign_session.gd")
const EquipmentDataScript := preload("res://scripts/core/equipment.gd")

const ROOT := "user://equipment_integration_tmp"
const SRC := "res://data/battlefields/plains_skirmish.json"
const L0 := "plains_skirmish"

var failures: Array[String] = []
var _sessions: Array = []
var _cur_dir := ""


func _sample_state() -> Dictionary:
	return {
		"turn_number": 3,
		"phase": &"enemy",
		"hosting": true,
		"prefs": {"ally_1": {"strategy": "aggressive", "priorityTargetId": "enemy_2"}},
		"result": &"",
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_battle_save_roundtrip()
	_test_session_equip_api()
	_test_session_attempt_rejection()
	_test_victory_preserves_camp_slots()
	_test_profile_json_equipment_rejected()
	_cleanup()
	_finish()


# ============================================================
# BattleSaveCodec：chapter 快照往返 + JSON 磁盘序列化 + 坏装备拒绝
# ============================================================
func _test_battle_save_roundtrip() -> void:
	var loaded: Dictionary = Loader.load_battlefield(SRC)
	if not bool(loaded.get("ok", false)):
		_expect(false, "plains_skirmish 加载失败: %s" % String(loaded.get("error", "")))
		return
	var chapter: Dictionary = loaded["chapter"]
	var info: Dictionary = loaded["info"]
	# 给第一个玩家单位装上通用盾 + 通用护甲（不依赖职业）
	var u0: Dictionary = (chapter["playerUnits"] as Array)[0]
	var eq_out: Dictionary = EquipmentDataScript.equip(u0, &"leatherShield")
	_expect(bool(eq_out.get("ok", false)), "装备 leatherShield 失败: %s" % String(str(eq_out.get("reason", ""))))
	eq_out = EquipmentDataScript.equip(u0, &"campaignCloak")
	_expect(bool(eq_out.get("ok", false)), "装备 campaignCloak 失败: %s" % String(str(eq_out.get("reason", ""))))
	if not u0.has(&"equipment"):
		_expect(false, "装备后单位应有 equipment 键")
		return

	var vErr := Codec.validate_chapter(chapter)
	_expect(vErr == "", "带装备 chapter 应通过校验，实际: %s" % vErr)

	var identity := "bf:res/%s" % String(info.get("id", "plains_skirmish"))
	var cap: Dictionary = Codec.capture(identity, "battlefield", SRC, chapter, chapter, _sample_state(), "sig-eq")
	_expect(bool(cap.get("ok", false)), "capture 失败: %s" % String(cap.get("error", "")))
	if not bool(cap.get("ok", false)):
		return
	var rr: Dictionary = Codec.restore(cap["record"])
	_expect(bool(rr.get("ok", false)), "restore 失败: %s" % String(rr.get("error", "")))
	if not bool(rr.get("ok", false)):
		return
	var b0: Dictionary = ((rr["chapter"]["playerUnits"] as Array)[0] as Dictionary).get(&"equipment", {})
	_expect(String(b0.get(&"shield", "")) == "leatherShield", "快照往返后 shield 槽丢失")
	_expect(String(b0.get(&"relic", "")) == "campaignCloak", "快照往返后 relic 槽丢失")
	_expect(b0.has(&"weapon") == false, "未装 weapon 槽不应存在")

	# JSON 磁盘序列化往返（String 键 → 解码归一 StringName）
	var as_json: String = JSON.stringify(Codec.encode(cap["record"]))
	var parsed: Variant = JSON.parse_string(as_json)
	if parsed is not Dictionary:
		_expect(false, "JSON 解析失败")
		return
	var jr: Dictionary = Codec.restore(Codec.decode(parsed))
	_expect(bool(jr.get("ok", false)), "JSON 往返 restore 失败: %s" % String(jr.get("error", "")))
	if not bool(jr.get("ok", false)):
		return
	var j0: Dictionary = ((jr["chapter"]["playerUnits"] as Array)[0] as Dictionary).get(&"equipment", {})
	_expect(String(j0.get(&"shield", "")) == "leatherShield", "JSON 往返后 shield 槽丢失")
	_expect(String(j0.get(&"relic", "")) == "campaignCloak", "JSON 往返后 relic 槽丢失")

	# 坏装备：未知条目必须被拒绝
	var bad_chapter: Dictionary = chapter.duplicate(true)
	(((bad_chapter["playerUnits"] as Array)[0] as Dictionary).get(&"equipment", {}) as Dictionary)[&"shield"] = &"not_exist"
	_expect(Codec.validate_chapter(bad_chapter) != "", "未知装备条目应被 chapter 校验拒绝")


# ============================================================
# CampaignSession.equip_item / unequip_item
# ============================================================
func _test_session_equip_api() -> void:
	_cur_dir = "%s/api" % ROOT
	var session := _mk_session()
	var created: Dictionary = session.create_profile("装备小队")
	_expect(bool(created.get("ok", false)), "建档失败: %s" % String(created.get("error", "")))
	if not bool(created.get("ok", false)):
		return
	var state: Dictionary = session.get_profile()
	var pid := String(state.get("id", ""))
	var roster: Array = state.get("roster", [])
	_expect(not roster.is_empty(), "档内 roster 不应为空")
	var rid := String((roster[0] as Dictionary).get("id", ""))
	var class_id := String((roster[0] as Dictionary).get("classId", ""))
	_expect(rid != "", "roster 单位应有稳定 id")

	# 未加载档拒绝
	var idle := SessionScript.new()
	var no_state: Dictionary = idle.equip_item("x", "leatherShield")
	_expect(not bool(no_state.get("ok", true)), "未加载档案应拒绝装备")

	# 未知单位拒绝（内存/磁盘无副作用）
	var bad_unit: Dictionary = session.equip_item("no_such_unit", "leatherShield")
	_expect(not bool(bad_unit.get("ok", true)), "未知单位应拒绝: %s" % String(bad_unit.get("error", "")))

	# 职业授权：mage 专属火魔法书对非 mage 拒绝；对 mage 成功
	var fire_entry := &"fire"
	var can := class_id == "mage"
	var fire_res: Dictionary = session.equip_item(rid, String(fire_entry))
	if can:
		_expect(bool(fire_res.get("ok", false)) and String(fire_res.get("slot", "")) == "weapon",
			"mage 应能装 fire: %s" % String(fire_res.get("error", "")))
	else:
		_expect(not bool(fire_res.get("ok", true)), "非 mage 装 fire 应被拒绝")
	# 未知条目拒绝
	var unknown: Dictionary = session.equip_item(rid, "not_exist")
	_expect(not bool(unknown.get("ok", true)), "未知装备条目应被拒绝")

	# 通用盾装上成功；武器槽按职业覆盖（mage 用 fire 后 weapon 槽已占用）
	var shield_res: Dictionary = session.equip_item(rid, "leatherShield")
	_expect(bool(shield_res.get("ok", false)), "通用皮盾应可装: %s" % String(shield_res.get("error", "")))
	_expect(String(shield_res.get("slot", "")) == "shield", "皮盾应落 shield 槽")
	# 装上不补满：hp 不因 campaignCloak 之外的新装变化（此处盾无 hp 加成，维持原值即可）
	var after: Dictionary = (session.get_profile()["roster"] as Array)[0]
	var hp_after_shield := int(after.get("hp", -1))

	# 再装鸢盾替换皮盾（同槽替换，prev 回传）
	var kite_res: Dictionary = session.equip_item(rid, "kiteShield")
	_expect(bool(kite_res.get("ok", false)), "鸢盾替换皮盾应成功: %s" % String(kite_res.get("error", "")))
	_expect(String(kite_res.get("prev", "")) == "leatherShield", "替换应回传 prev=leatherShield")

	# 落盘往返：全新会话加载同一档案，equipment 仍在
	var reloaded := SessionScript.new()
	reloaded.base_dir = _cur_dir
	var load_res: Dictionary = reloaded.load_profile(pid)
	_expect(bool(load_res.get("ok", false)), "重载档案失败: %s" % String(load_res.get("error", "")))
	if bool(load_res.get("ok", false)):
		var r0: Dictionary = (reloaded.get_profile()["roster"] as Array)[0]
		var req: Dictionary = r0.get(&"equipment", {})
		_expect(String(req.get(&"shield", "")) == "kiteShield", "重载后 shield 槽应保留 kiteShield")
		if can:
			_expect(String(req.get(&"weapon", "")) == "fire", "重载后 weapon 槽应保留 fire")
		_expect(int(r0.get("hp", -1)) == hp_after_shield, "装备不改变当前 HP")

	# 卸下：成功 + prev 正确 + 空槽拒绝
	var uneq: Dictionary = session.unequip_item(rid, "shield")
	_expect(bool(uneq.get("ok", false)), "卸下 shield 应成功: %s" % String(uneq.get("error", "")))
	_expect(String(uneq.get("prev", "")) == "kiteShield", "卸下应回传 prev=kiteShield")
	var uneq_again: Dictionary = session.unequip_item(rid, "shield")
	_expect(bool(uneq_again.get("ok", false)) and String(uneq_again.get("prev", "x")) == "",
		"空槽再卸应为幂等成功且 prev 为空")
	var uneq_bad_slot: Dictionary = session.unequip_item(rid, "helm")
	_expect(not bool(uneq_bad_slot.get("ok", true)), "未知槽位应被拒绝")


# ============================================================
# 出征挂起拒绝 + 结算后恢复
# ============================================================
func _test_session_attempt_rejection() -> void:
	_cur_dir = "%s/attempt" % ROOT
	var session := _mk_session()
	session.create_profile("出征队")
	var rid := String(((session.get_profile()["roster"] as Array)[0] as Dictionary).get("id", ""))
	var prepared: Dictionary = session.prepare_battle(L0)
	_expect(bool(prepared.get("ok", false)), "出征应成功: %s" % String(prepared.get("error", "")))
	if not bool(prepared.get("ok", false)):
		return
	var token := String(prepared.get("token", ""))
	var during: Dictionary = session.equip_item(rid, "leatherShield")
	_expect(not bool(during.get("ok", true)), "出征挂起时应拒绝装备: %s" % String(during.get("error", "")))
	var during2: Dictionary = session.unequip_item(rid, "shield")
	_expect(not bool(during2.get("ok", true)), "出征挂起时应拒绝卸下")
	var settled: Dictionary = session.settle_battle(token, "abandon")
	_expect(bool(settled.get("ok", false)), "弃战结算应成功: %s" % String(settled.get("error", "")))
	var after: Dictionary = session.equip_item(rid, "leatherShield")
	_expect(bool(after.get("ok", false)), "结算后应恢复装备能力: %s" % String(after.get("error", "")))


# ============================================================
# 胜利结算：营地档槽位权威，不从 battle snapshot 回写
# ============================================================
func _test_victory_preserves_camp_slots() -> void:
	_cur_dir = "%s/victory" % ROOT
	var session := _mk_session()
	session.create_profile("凯旋队")
	var profile: Dictionary = session.get_profile()
	var rid := String(((profile["roster"] as Array)[0] as Dictionary).get("id", ""))
	# 出征前在营地装好盾+秘宝（任意职业通用）
	_expect(bool(session.equip_item(rid, "leatherShield").get("ok", false)), "出征前装盾应成功")
	_expect(bool(session.equip_item(rid, "campaignCloak").get("ok", false)), "出征前装秘宝应成功")
	var prepped: Dictionary = session.prepare_battle(L0)
	_expect(bool(prepped.get("ok", false)), "出征应成功: %s" % String(prepped.get("error", "")))
	if not bool(prepped.get("ok", false)):
		return
	var token := String(prepped.get("token", ""))
	# 终局战场数据：同 id 单位但 equipment 被清空且 stats 有成长 —— 模拟
	# 战场快照（战内不发生装卸；即便快照缺字段/被污染，营地档也不回写吸收）。
	var final_unit: Dictionary = ((profile["roster"] as Array)[0] as Dictionary).duplicate(true)
	final_unit.erase(&"equipment")
	final_unit["exp"] = int(final_unit.get("exp", 0)) + 40
	var final_chapter := {"playerUnits": [final_unit], "enemyUnits": []}
	var settled: Dictionary = session.settle_battle(token, "win", final_chapter)
	_expect(bool(settled.get("ok", false)), "胜利结算应成功: %s" % String(settled.get("error", "")))
	if not bool(settled.get("ok", false)):
		return
	var after: Dictionary = ((session.get_profile()["roster"] as Array)[0] as Dictionary)
	var eq: Dictionary = after.get(&"equipment", {})
	_expect(String(eq.get(&"shield", "")) == "leatherShield", "回营后 shield 槽应保留营地档原值")
	_expect(String(eq.get(&"relic", "")) == "campaignCloak", "回营后 relic 槽应保留营地档原值")
	# 成长照常吸收：exp 增加（40 落进档内）
	_expect(int(after.get("exp", -1)) == int(final_unit["exp"]), "成长（exp）应照常吸收")


# ============================================================
# 坏装备 JSON：profile 校验拒绝
# ============================================================
func _test_profile_json_equipment_rejected() -> void:
	_cur_dir = "%s/badjson" % ROOT
	var session := _mk_session()
	var created: Dictionary = session.create_profile("坏档队")
	_expect(bool(created.get("ok", false)), "建档失败")
	if not bool(created.get("ok", false)):
		return
	var pid := String(session.get_profile().get("id", ""))
	var rid := String(((session.get_profile()["roster"] as Array)[0] as Dictionary).get("id", ""))
	_expect(session.equip_item(rid, "leatherShield").get("ok", false), "装盾应成功")
	# 直接改写磁盘 JSON：把 shield 槽值换成未知条目
	var files: Array = DirAccess.get_files_at(_cur_dir)
	var target := ""
	for f in files:
		var fname := String(f)
		if fname.begins_with("campaign_") and fname.ends_with(".json") and pid in fname:
			target = "%s/%s" % [_cur_dir, fname]
			break
	_expect(target != "", "应能找到档案 JSON 文件")
	if target == "":
		return
	var text := FileAccess.get_file_as_string(target)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		_expect(false, "档案 JSON 解析失败")
		return
	var record: Dictionary = parsed
	var roster_v: Variant = record.get("roster", [])
	if roster_v is not Array or (roster_v as Array).is_empty():
		_expect(false, "档案 record 缺 roster")
		return
	var eq_v: Variant = (roster_v as Array)[0].get("equipment", null)
	if eq_v is not Dictionary:
		_expect(false, "档案 roster[0] 缺 equipment（装备未落盘？）")
		return
	(eq_v as Dictionary)["shield"] = "not_exist"
	# 主档与备份都要污染：codec 层有「主档结构损坏回退备份」的自愈设计，
	# 只毒主档会被好备份救回（那是既有契约保护，不是本测试目标）。
	var poisoned_text := JSON.stringify(parsed)
	for suffix in ["", ".bak"]:
		var wf := FileAccess.open(target + suffix, FileAccess.WRITE)
		if wf != null:
			wf.store_string(poisoned_text)
			wf.close()
	var reloaded := SessionScript.new()
	reloaded.base_dir = _cur_dir
	var load_res: Dictionary = reloaded.load_profile(pid)
	_expect(not bool(load_res.get("ok", false)), "坏装备条目应被档案校验拒绝，实际加载成功")


# ============================================================
# helpers
# ============================================================
func _mk_session() -> SessionScript:
	var session := SessionScript.new()
	session.base_dir = _cur_dir
	_sessions.append(session)
	return session


func _cleanup() -> void:
	for s in _sessions:
		if is_instance_valid(s):
			s.queue_free()
	var dir := DirAccess.open(ROOT)
	if dir != null:
		for sub in dir.get_directories():
			var child := DirAccess.open("%s/%s" % [ROOT, sub])
			if child != null:
				for f in child.get_files():
					child.remove(f)
			dir.remove(sub)


func _finish() -> void:
	if failures.is_empty():
		print("EQUIPMENT_INTEGRATION_CONTRACT_OK")
		quit(0)
	else:
		push_error("EQUIPMENT_INTEGRATION_CONTRACT 失败 x%d" % failures.size())
		for m in failures:
			push_error("  - " + m)
		printerr("EQUIPMENT_INTEGRATION_CONTRACT_FAILED")
		quit(1)
