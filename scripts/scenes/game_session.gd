## game_session.gd — 战棋会话路由（autoload GameSession）
## 职责：
##   - 统一「进入游戏默认打开什么战旗」的决策：--battlefield 显式 > 最近记录 > 默认 plains_skirmish
##   - 分战场稳定身份（bf:res|user/id、world:seed/x/y），每个身份一份独立记录
##   - 一次性 --reset-battle 重置（只清目标档案，其余保留；命令行参数天然一次进程一次）
##   - 战斗进度提交（battle.gd → commit → codec 组装 → store 原子落盘 + 最近索引）
##   - 进程内路由：in_session 标记让 Game 入口在从战斗返回时停在列表，而不是循环自动续玩
## 依赖：BattleSaveCodec / BattleSaveStore / BattlefieldLoader / CmdArgs（全部零场景依赖）。

extends Node

const DEFAULT_BATTLEFIELD_ID := "plains_skirmish"
const GAME_SCENE := "res://scenes/Game.tscn"

const BattleSaveStoreScript := preload("res://scripts/core/battle_save_store.gd")
const BattleSaveCodecScript := preload("res://scripts/core/battle_save_codec.gd")

var store := BattleSaveStoreScript.new()

## 本进程内是否已开过战旗（Game 入口据此决定自动续玩还是显示列表）。
var in_session := false

## 当前打开的战斗上下文 {identity, kind, source, initial, initial_signature}。
## initial 是开局 chapter 的深拷贝（battle.gd 会原地改 chapter，不能存引用）。
var _current: Dictionary = {}

## --reset-battle 是否已在本进程消费过（见 _consume_reset_target）。
var _reset_target_consumed := false


# ============================================================
# 启动决策（Game 入口冷启动调用）
# ============================================================

## 决定启动目标并准备进入参数（冷启动入口）。返回：
##   {mode: "resume"|"fresh"|"list", identity, kind, source, chapter, state,
##    initial, initial_signature, hosting, notice}
## - resume：chapter/state 来自存档（保存时的权威快照）
## - fresh：chapter 来自战场 JSON；state 为空
## - list：无法决策出可玩战场（如存档版本更新），交回列表 UI
func prepare_entry() -> Dictionary:
	var reset_target := _consume_reset_target()
	return _decide_entry(_resolve_launch(), reset_target)


## 列表点选某个战场进入（reset=true 时先清档）。返回结构同 prepare_entry。
func prepare_entry_for(identity: String, reset: bool = false) -> Dictionary:
	for info in _battlefield_infos():
		if identity_for_battlefield(info) == identity:
			var fields := _fields_from_info(info)
			if fields["chapter"].is_empty():
				return {"mode": "list", "notice": String(fields.get("notice", ""))}
			return _decide_entry(fields, "*" if reset else "")
	return {"mode": "list", "notice": "战场不存在：%s\n" % identity}


func _decide_entry(fields: Dictionary, reset_target: String) -> Dictionary:
	var notice := String(fields.get("notice", ""))
	var identity: String = fields["identity"]
	var kind: String = fields["kind"]
	var source: String = fields["source"]
	var hosting: bool = fields["hosting"]
	var chapter: Dictionary = fields["chapter"]
	if chapter.is_empty():
		return {"mode": "list", "notice": notice}
	# 一次性重置：只清将要打开的目标档案
	if not reset_target.is_empty() and _reset_matches(reset_target, identity, source):
		var del: Dictionary = store.delete_record(identity)
		if del.get("ok", false):
			notice += "已按 --reset-battle 重置《%s》。\n" % String(fields["name"])
		else:
			notice += "重置失败：%s\n" % String(del.get("error", ""))
	# 有档案 → 尝试恢复
	var loaded: Dictionary = store.load_record(identity)
	if loaded.get("ok", false):
		var rr: Dictionary = BattleSaveCodecScript.restore(loaded["record"])
		if rr.get("ok", false):
			var sig_saved := String(rr.get("signature", ""))
			if sig_saved != "" and sig_saved != chapter_signature(chapter):
				notice += "战场内容已变更，继续将沿用进入时的快照。\n"
			return {
				"mode": "resume", "identity": identity, "kind": kind,
				"source": source, "chapter": rr["chapter"], "state": rr["state"],
				"initial": rr["initial"],
				"initial_signature": sig_saved,
				"hosting": bool(rr["state"].get("hosting", hosting)),
				"notice": notice,
			}
		# 版本更新：绝不覆盖（新开局提交会以旧版本号重写档案）
		if bool(rr.get("newer", false)):
			return {"mode": "list",
				"notice": notice + "存档来自更新的版本（%s），已停在列表。\n" % String(rr.get("error", ""))}
		notice += "存档无法恢复（%s），新开一局。\n" % String(rr.get("error", ""))
	elif not bool(loaded.get("missing", false)):
		notice += "存档损坏（%s）。\n" % String(loaded.get("error", ""))
	# 新开一局（世界就地战旗没有可重建的 JSON 源：重置后从开局快照重打）
	var fresh_chapter: Dictionary = chapter
	if kind == "world" and not fields.get("initial", {}).is_empty():
		fresh_chapter = fields["initial"]
	return {
		"mode": "fresh", "identity": identity, "kind": kind, "source": source,
		"chapter": fresh_chapter, "state": {}, "initial": fresh_chapter,
		"initial_signature": "", "hosting": hosting, "notice": notice,
	}


## 决策顺序：--battlefield 显式（id|路径|文件名）> 最近记录 > 默认 plains_skirmish。
func _resolve_launch() -> Dictionary:
	var infos := _battlefield_infos()
	var explicit := CmdArgs.get_string("battlefield", "")
	if explicit != "":
		var m := _match_battlefield(explicit, infos)
		if not m.is_empty():
			return _fields_from_info(m)
		return _default_fields(infos, "未找到 --battlefield=%s，回退默认。\n" % explicit)
	var latest := store.load_latest()
	if latest != "":
		var m2 := _find_by_identity(latest, infos)
		if not m2.is_empty():
			return _fields_from_info(m2)
		if latest.begins_with("world:"):
			# 最近进入的是世界就地战旗：没有 JSON 源，档案快照本身就是权威，
			# 直接按 B2 独立战斗从快照恢复（任务要求打开最后进入的战旗）。
			var wf := _fields_from_world_identity(latest)
			if not wf.is_empty():
				return wf
			return _default_fields(infos,
				"最近的世界战旗记录无法读取，已打开默认战旗。\n")
	return _default_fields(infos, "")


## 世界就地战旗没有战场 JSON：身份 → 档案快照。返回结构同 _fields_from_info
## （chapter/state/initial 都来自档案；记录缺失或无法恢复返回 {}）。
func _fields_from_world_identity(identity: String) -> Dictionary:
	var loaded: Dictionary = store.load_record(identity)
	if not loaded.get("ok", false):
		return {}
	var rr: Dictionary = BattleSaveCodecScript.restore(loaded["record"])
	if not rr.get("ok", false):
		return {}
	return {
		"identity": identity, "kind": "world", "source": "world",
		"name": "生态世界战旗",
		"hosting": bool(rr["state"].get("hosting", false)),
		"chapter": rr["chapter"], "state": rr["state"],
		"initial": rr["initial"],
		"initial_signature": String(rr.get("signature", "")),
	}


## 世界内按 P 再次进入同一处就地战旗（同身份）：有档案 → 从档案恢复，
## 无档案 → 用刚构建的 chapter 新开。返回结构同 prepare_entry（mode: resume|fresh）。
func prepare_world_entry(identity: String, chapter: Dictionary) -> Dictionary:
	return _decide_entry({
		"identity": identity, "kind": "world", "source": "world",
		"name": "生态世界战旗", "hosting": false, "chapter": chapter,
	}, "")


func _default_fields(infos: Array, notice: String) -> Dictionary:
	for info in infos:
		if String(info.get("id", "")) == DEFAULT_BATTLEFIELD_ID:
			var f := _fields_from_info(info)
			f["notice"] = String(f.get("notice", "")) + notice
			return f
	if not infos.is_empty():
		var f2 := _fields_from_info(infos[0])
		f2["notice"] = String(f2.get("notice", "")) + notice
		return f2
	return {"identity": "", "kind": "", "source": "", "chapter": {},
		"hosting": false, "name": "", "notice": notice + "没有任何可用战场。\n"}


func _fields_from_info(info: Dictionary) -> Dictionary:
	var loaded: Dictionary = BattlefieldLoader.load_battlefield(String(info["path"]))
	if not bool(loaded.get("ok", false)):
		return {"identity": "", "kind": "", "source": "", "chapter": {},
			"hosting": false, "name": String(info.get("name", "")),
			"notice": "战场加载失败 %s：%s\n" % [String(info.get("path", "")), String(loaded.get("error", ""))]}
	return {
		"identity": identity_for_battlefield(info),
		"kind": "battlefield",
		"source": String(info["path"]),
		"chapter": loaded["chapter"],
		"hosting": bool(info.get("hosting", false)),
		"name": String(info.get("name", "")),
		"notice": "",
	}


## 按 id / 路径 / 文件名 匹配战场。
func _match_battlefield(key: String, infos: Array) -> Dictionary:
	for info in infos:
		if String(info.get("id", "")) == key or String(info.get("path", "")) == key \
				or String(info.get("file", "")) == key:
			return info
	return {}


func _find_by_identity(identity: String, infos: Array) -> Dictionary:
	for info in infos:
		if identity_for_battlefield(info) == identity:
			return info
	return {}


func _battlefield_infos() -> Array:
	var out: Array = []
	for info in BattlefieldLoader.list_battlefields():
		if not String(info.get("error", "")).is_empty():
			continue
		out.append(info)
	return out


# ============================================================
# 稳定身份
# ============================================================

## JSON 战场身份：res/user 命名空间 + 内容 id；无 id 的旧文件用文件名兼容。
func identity_for_battlefield(info: Dictionary) -> String:
	var ns := "user" if String(info.get("path", "")).begins_with("user://") else "res"
	var key := String(info.get("id", ""))
	if key.is_empty():
		key = "<file>" + String(info.get("file", info.get("path", "")))
	return "bf:%s/%s" % [ns, key]


## 世界就地战旗身份：种子 + 起点（同一世界同一位置 = 同一战旗）。
func identity_for_world_chapter(seed: int, origin: Vector2i) -> String:
	return "world:%d/%d/%d" % [seed, origin.x, origin.y]


# ============================================================
# 战斗打开 / 提交
# ============================================================

## 任何入口（Game 自动续玩 / 生态世界 P / O 键）进入战斗前调用：
## 登记 _current 并置 in_session。initial_chapter 传「开局时的 chapter」。
func open_battle(identity: String, kind: String, source: String, initial_chapter: Dictionary) -> void:
	in_session = true
	_current = {
		"identity": identity,
		"kind": kind,
		"source": source,
		"initial": initial_chapter.duplicate(true),
		"initial_signature": chapter_signature(initial_chapter),
	}


## battle.gd 在完整行动边界调用：组装记录 + 原子落盘 + 刷新最近索引。
func commit(chapter: Dictionary, state: Dictionary) -> Dictionary:
	if _current.is_empty() or String(_current["identity"]).is_empty():
		return {"ok": false, "error": "no_active_battle"}
	var cap: Dictionary = BattleSaveCodecScript.capture(
		_current["identity"], _current["kind"], _current["source"],
		_current["initial"], chapter, state, _current["initial_signature"])
	if not cap.get("ok", false):
		return cap
	var sv: Dictionary = store.save_record(_current["identity"], cap["record"])
	if sv.get("ok", false):
		store.set_latest(_current["identity"])
	return sv


func current_identity() -> String:
	return String(_current.get("identity", ""))


## 列表 UI 的手动重置：只删这一份档案。
func reset_battlefield(identity: String) -> Dictionary:
	return store.delete_record(identity)


# ============================================================
# 列表 / 签名 / 重置参数
# ============================================================

## 战场列表 + 每项存档摘要，供 Game 入口列表 UI。
func list_battlefields_checked() -> Array:
	var out: Array = []
	for info in _battlefield_infos():
		var idn := identity_for_battlefield(info)
		out.append({"info": info, "identity": idn, "save": store.peek(idn)})
	return out


## 初始 chapter 的内容签名（检测「来源 JSON 已被编辑过」）。
func chapter_signature(chapter: Dictionary) -> String:
	var enc: Variant = BattleSaveCodecScript.encode(chapter)
	if enc == null:
		return ""
	return JSON.stringify(enc).sha1_text()


## --reset-battle[=id|路径]：裸标志返回 "*"（重置将要打开的那个）。
## 命令行参数只在本次进程出现 → 跨进程天然一次性；进程内必须再记一次
## 已消费标记 —— 否则「重置 → 战斗 → 退回列表 → 继续最近」会在同一进程里
## 第二次 prepare_entry 时把刚打出来的进度又重置掉。
func _consume_reset_target() -> String:
	if _reset_target_consumed:
		return ""
	if not CmdArgs.has_flag("reset-battle"):
		return ""
	_reset_target_consumed = true
	var v := CmdArgs.get_string("reset-battle", "")
	return "*" if v.is_empty() else v


func _reset_matches(target: String, identity: String, source: String) -> bool:
	if target == "*" or target == identity or target == source:
		return true
	# 允许只写 id 简写：bf:res/plains_skirmish 匹配 plains_skirmish
	return identity.ends_with("/" + target)
