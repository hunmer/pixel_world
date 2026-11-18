## campaign_session.gd — 冒险模式会话服务（autoload CampaignSession）
##
## 职责：多档案管理（创建/加载/重命名/删除/列表）、公共库存、线性关卡解锁、
## 出征部署（prepare_battle，防重复出征）与战后结算（settle_battle，win/lose/abandon；
## 胜利 receipt 附 level_ups 升级差分，按 id 对位出征前快照，等级提升才列）、
## 商店购买（list_shop/buy_item，限购周期 = completed_levels.size()，先落盘后切内存）。
##
## 磁盘契约（user://campaign_saves/，经 CampaignProfileStore 原子写）：
## 磁盘永远是"安全态"——出征挂起时落盘的是出征前快照 + attempt 标记；胜利结算
## 先落盘新态、成功才提交内存（失败可重试、不重复发奖）；失败/放弃回滚内存后
## 重新落盘（标记自愈）。重新载入带 attempt 标记的档案 = 恢复出征前状态。
##
## 集成约定：settle_battle 对终局 chapter 只读（battle 演出层结算后还要用）；
## prepare_battle 返回的 chapter 是深拷贝；测试用 configure_store_dir 隔离目录。

extends Node

signal changed(reason: String)

const DEFAULT_STORE_DIR := "user://campaign_saves"

const CampaignConfigScript := preload("res://scripts/campaign/campaign_config.gd")
const Codec := preload("res://scripts/campaign/campaign_profile_codec.gd")
const Roster := preload("res://scripts/campaign/campaign_roster.gd")
const StoreScript := preload("res://scripts/campaign/campaign_profile_store.gd")
const BattlefieldLoaderScript := preload("res://scripts/core/battlefield_loader.gd")
const ItemDataScript := preload("res://scripts/core/items.gd")
const ShopCatalogScript := preload("res://scripts/campaign/shop_catalog.gd")
const AIDifficultyScript := preload("res://scripts/systems/ai_difficulty.gd")
const EquipmentDataScript := preload("res://scripts/core/equipment.gd")

## 存档根目录（测试可改；改动在下次访问 store 时生效）。
var base_dir: String = DEFAULT_STORE_DIR

var _store: StoreScript
var _state: Dictionary = {}
var _attempt: Dictionary = {}
var _last_result: Dictionary = {}
var _last_settled_token := ""


# ============================================================
# 目录与查询
# ============================================================

## 切换存档根目录（测试隔离用）。清空内存会话态（等价 leave_profile）后切换，
## 保证返回后新目录干净隔离；restore 时传回 DEFAULT_STORE_DIR 即可。
func configure_store_dir(path: String) -> void:
	_reset_memory()
	base_dir = path
	_store = null


## 当前档案概览；未加载返回 {}。
func get_profile() -> Dictionary:
	if _state.is_empty():
		return {}
	return {
		"id": str(_state.id),
		"name": str(_state.name),
		"gold": int(_state.gold),
		"roster": _state.roster.duplicate(true),
		"inventory": _state.inventory.duplicate(true),
		"completed_levels": _state.completed_levels.duplicate(true),
		"saved_at": float(_state.saved_at),
		"last_opened_level": str(_state.get("last_opened_level", "")),
		"difficulty": StringName(str(_state.get("difficulty", AIDifficultyScript.DEFAULT))),
	}


## 上次成功出征的关卡。未出征、关卡已不存在或当前未解锁时返回 {}。
## 否则返回 {id, name, unlocked, completed}，供基地「继续上次战斗」直接开战。
func get_last_opened_level() -> Dictionary:
	if _state.is_empty():
		return {}
	var level_id := str(_state.get("last_opened_level", "")).strip_edges()
	if level_id == "":
		return {}
	var level: Dictionary = CampaignConfigScript.get_level(level_id)
	if level.is_empty():
		return {}
	var completed: Array = _state.completed_levels if _state.completed_levels is Array else []
	if not _level_unlocked(int(level.index), completed):
		return {}
	return {
		"id": str(level.id),
		"name": str(level.get("name", level_id)),
		"unlocked": true,
		"completed": completed.has(str(level.id)),
	}


## 全部档案摘要（saved_at 降序）。与 load_profile 同口径做 codec 级主/备选择：
## 结构坏主档+合法备份 → loadable=true + 备份恢复 notice；新版本/双损坏 →
## loadable=false + notice。保证列表与实际加载结果一致。
func list_profiles() -> Array:
	var entries: Array = _ensure_store().list_records()
	var out: Array = []
	for entry: Variant in entries:
		if entry is Dictionary:
			out.append(_summarize_entry(entry))
	out.sort_custom(func(a, b): return float(a.saved_at) > float(b.saved_at))
	# 最近使用标记（UI 聚焦用）：优先磁盘索引记录的最近加载/新建档；
	# 索引缺失/失配时回退最新保存的可读档案。
	var recent_id := _ensure_store().load_latest_profile()
	var stamped := false
	for s: Variant in out:
		s["is_recent"] = false
	if recent_id != "":
		for s: Variant in out:
			if str(s.get("id", "")) == recent_id:
				s["is_recent"] = true
				stamped = true
				break
	if not stamped:
		for s: Variant in out:
			if bool(s.get("loadable", false)):
				s["is_recent"] = true
				break
	return out


## 单条档案列表摘要：与 load_profile 完全同口径（_resolve_codec_layers），
## 避免"列表判定不可加载、实际加载却成功（或反之）"的不一致。
func _summarize_entry(entry: Dictionary) -> Dictionary:
	var raw: Dictionary = {}
	var raw_value: Variant = entry.get("record")
	if raw_value is Dictionary:
		raw = raw_value
	var fallback_id := str(entry.get("file", ""))
	var resolved: Dictionary = _resolve_codec_layers(entry.get("main", {}), entry.get("bak", {}))
	if str(resolved.get("status", "")) == "ok":
		var state: Dictionary = resolved.state
		var hints: Array = []
		if bool(resolved.get("from_bak", false)):
			hints.append("主档损坏，已从备份恢复")
		if state.get("attempt", null) != null:
			hints.append("上次战斗中断")
		return {
			"id": str(state.id),
			"name": str(state.name),
			"gold": int(state.gold),
			"completed_count": int(state.completed_levels.size()),
			"saved_at": float(state.saved_at),
			"difficulty": str(state.get("difficulty", AIDifficultyScript.DEFAULT)),
			"loadable": true,
			"notice": "；".join(hints),
		}
	var notice := str(resolved.get("error", "档案无法读取"))
	var broken_id := fallback_id
	var broken_name := "（损坏档案）"
	var broken_saved_at := 0.0
	if not raw.is_empty():
		broken_id = str(raw.get("id", fallback_id))
		broken_name = str(raw.get("name", "（未知档案）"))
		broken_saved_at = float(raw.get("saved_at", 0.0))
	return {
		"id": broken_id,
		"name": broken_name,
		"gold": 0,
		"completed_count": 0,
		"saved_at": broken_saved_at,
		"loadable": false,
		"notice": notice,
	}


## codec 级分层解析（list 与 load 共用同一业务口径）：
## 主档 restore 成功 → 用主档；newer → 直接拒绝（绝不回退旧版本备份）；
## 主档"合法 JSON 但结构损坏" → 尝试验证后的备份（from_bak=true）；
## 全部不可用 → broken（错误信息与 load_profile 历史文案一致）。
func _resolve_codec_layers(main_layer: Dictionary, bak_layer: Dictionary) -> Dictionary:
	if main_layer.has("record"):
		var main_restored: Dictionary = Codec.restore(main_layer.record)
		if main_restored.get("ok", false):
			return {"status": "ok", "state": main_restored.state, "from_bak": false}
		if main_restored.get("newer", false):
			return {"status": "newer", "error": str(main_restored.error)}
	if bak_layer.has("record"):
		var bak_restored: Dictionary = Codec.restore(bak_layer.record)
		if bak_restored.get("ok", false):
			return {"status": "ok", "state": bak_restored.state, "from_bak": true}
		if bak_restored.get("newer", false):
			return {"status": "newer", "error": str(bak_restored.error)}
		var detail := str(bak_restored.error)
		if main_layer.has("record"):
			return {"status": "broken", "error": "主档结构损坏且备份校验失败：%s" % detail}
		return {"status": "broken", "error": "备份校验失败：%s" % detail}
	if main_layer.has("broken") or bak_layer.has("broken"):
		return {"status": "broken", "error": "主档损坏且无可用备份"}
	return {"status": "broken", "error": "主档结构校验失败且无可用备份"}


## 关卡列表（含解锁/通关/奖励信息）。配置无效时返回 []。
func list_levels() -> Array:
	var levels: Array = CampaignConfigScript.levels()
	if levels.is_empty():
		return []
	var completed: Array = [] if _state.is_empty() else _state.completed_levels
	var out: Array = []
	for level: Variant in levels:
		var level_id := str(level.id)
		var first_rewards: Dictionary = CampaignConfigScript.rewards_for(level_id, true)
		var repeat_rewards: Dictionary = CampaignConfigScript.rewards_for(level_id, false)
		var reward_items: Array = []
		for raw_item: Variant in first_rewards.items:
			reward_items.append({
				"id": str(raw_item.id),
				"name": str(raw_item.name),
				"count": int(raw_item.count),
			})
		var reward_items_repeat: Array = []
		for raw_item: Variant in repeat_rewards.items:
			reward_items_repeat.append({
				"id": str(raw_item.id),
				"name": str(raw_item.name),
				"count": int(raw_item.count),
			})
		out.append({
			"id": level_id,
			"name": str(level.name),
			"source": str(level.source),
			"unlocked": _level_unlocked(int(level.index), completed),
			"completed": completed.has(level_id),
			"reward_gold": int(first_rewards.gold),
			"reward_items": reward_items,
			"reward_gold_repeat": int(repeat_rewards.gold),
			"reward_items_repeat": reward_items_repeat,
			"index": int(level.index),
		})
	return out


## 最近一次结算结果（或 {}）。
func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)


func clear_last_result() -> void:
	_last_result = {}


# ============================================================
# 档案管理
# ============================================================

## 创建新档案。difficulty 为 AI 难度档名（AIDifficulty 四档之一，缺省 normal），
## 随档持久化并在出征时注入战斗；创建后即成为当前档案。
func create_profile(profile_name: String, difficulty: Variant = AIDifficultyScript.DEFAULT) -> Dictionary:
	var name_check := _validate_name(profile_name)
	if not name_check.get("ok", false):
		return {"ok": false, "error": str(name_check.error)}
	if not AIDifficultyScript.validate(difficulty):
		return {"ok": false, "error": "未知难度档：%s" % str(difficulty)}
	var first_level := CampaignConfigScript.first_level_id()
	if first_level == "":
		return {"ok": false, "error": "冒险配置无效，无法创建档案"}
	var built: Dictionary = Roster.build_initial(first_level)
	if not built.get("ok", false):
		return {"ok": false, "error": "初始队伍构建失败：%s" % str(built.error)}
	var now := Time.get_unix_time_from_system()
	var state := {
		"id": _gen_profile_id(),
		"name": str(name_check.name),
		"gold": 0,
		"roster": built.roster,
		"inventory": built.inventory,
		"completed_levels": [],
		"carry_templates": built.templates,
		"shop_purchases": {"clear_index": 0, "counts": {}},
		"created_at": now,
		"saved_at": now,
		"last_opened_level": "",
		"difficulty": str(difficulty),
	}
	var persisted := _persist(state)
	if not persisted.get("ok", false):
		return {"ok": false, "error": "创建档案失败（未落盘）：%s" % str(persisted.error)}
	_state = state
	_attempt = {}
	_last_result = {}
	_last_settled_token = ""
	_mark_latest(str(state.id))
	_emit_changed("created")
	return {"ok": true, "error": "", "profile_id": str(state.id)}


func load_profile(profile_id: String) -> Dictionary:
	if profile_id.strip_edges() == "":
		return {"ok": false, "error": "档案 id 为空"}
	var layers: Dictionary = _ensure_store().read_layers(profile_id)
	if layers.get("missing", false):
		return {"ok": false, "error": "档案不存在"}
	# codec 级分层回退（与 list_profiles 共用 _resolve_codec_layers，口径一致）：
	# 主档"合法 JSON 但结构损坏"时尝试验证后的备份；
	# 未来版本（newer）主档直接拒绝，绝不回退旧版本备份。
	var resolved: Dictionary = _resolve_codec_layers(layers.get("main", {}), layers.get("bak", {}))
	var status := str(resolved.get("status", ""))
	if status == "newer":
		return {"ok": false, "error": str(resolved.error), "newer": true}
	if status != "ok":
		return {"ok": false, "error": str(resolved.error)}
	var from_bak: bool = bool(resolved.get("from_bak", false))
	var state: Dictionary = resolved.state
	var notice := ""
	var interrupted_level := ""
	if from_bak:
		notice = "主档损坏，已从备份恢复"
	if state.get("attempt", null) != null:
		interrupted_level = str(state.attempt.get("level_id", ""))
		notice = (notice + "；" if notice != "" else "") + "上次战斗中断，已恢复到出征前状态"
	# 旧档没有 last_opened_level：中断关卡就是上次打开的关卡。
	if str(state.get("last_opened_level", "")).strip_edges() == "" and interrupted_level != "":
		state["last_opened_level"] = interrupted_level
	state.erase("attempt")
	_state = state
	_attempt = {}
	_last_result = {}
	_last_settled_token = ""
	_mark_latest(str(state.id))
	_emit_changed("loaded")
	var result := {"ok": true, "error": "", "notice": notice}
	if interrupted_level != "":
		result["interrupted_level_id"] = interrupted_level
	return result


func rename_profile(profile_id: String, new_name: String) -> Dictionary:
	var name_check := _validate_name(new_name)
	if not name_check.get("ok", false):
		return {"ok": false, "error": str(name_check.error)}
	var is_current: bool = not _state.is_empty() and str(_state.id) == profile_id
	if is_current:
		var persisted := _persist_safe(str(name_check.name))
		if not persisted.get("ok", false):
			return {"ok": false, "error": "重命名落盘失败：%s" % str(persisted.error)}
		_state["name"] = str(name_check.name)
		_emit_changed("renamed")
		return {"ok": true, "error": ""}
	# 他档路径：与 load 同口径的 codec 级校验（未来版本拒绝重命名，保护其不被
	# 覆写；主档结构坏时用验证后的备份内容），校验通过才允许改名落盘。
	var layers: Dictionary = _ensure_store().read_layers(profile_id)
	if layers.get("missing", false):
		return {"ok": false, "error": "档案不存在或读取失败"}
	var resolved: Dictionary = _resolve_codec_layers(layers.get("main", {}), layers.get("bak", {}))
	if str(resolved.get("status", "")) == "newer":
		return {"ok": false, "newer": true, "error": "档案为未来版本，已拒绝重命名"}
	if str(resolved.get("status", "")) != "ok":
		return {"ok": false, "error": "档案结构校验失败，已拒绝重命名：%s" % str(resolved.get("error", ""))}
	var st: Dictionary = resolved.state
	st["name"] = str(name_check.name)
	var persisted: Dictionary = _persist(st)
	if not persisted.get("ok", false):
		return {"ok": false, "error": "重命名落盘失败：%s" % str(persisted.error)}
	return {"ok": true, "error": ""}


func delete_profile(profile_id: String) -> Dictionary:
	if profile_id == "":
		return {"ok": false, "error": "档案 id 为空"}
	var res: Dictionary = _ensure_store().delete_profile(profile_id)
	if not res.get("ok", false):
		return {"ok": false, "error": str(res.error)}
	if not _state.is_empty() and str(_state.id) == profile_id:
		_reset_memory()
	_emit_changed("deleted")
	return {"ok": true, "error": ""}


## Hub 手动保存。战斗进行中（出征挂起）禁止。
func save_current() -> Dictionary:
	if _state.is_empty():
		return {"ok": false, "error": "尚未加载冒险档案"}
	if not _attempt.is_empty():
		return {"ok": false, "error": "战斗进行中，不能手动保存"}
	var persisted := _persist_safe()
	if not persisted.get("ok", false):
		return {"ok": false, "error": "保存失败：%s" % str(persisted.error)}
	_emit_changed("saved")
	return {"ok": true, "error": "", "saved_at": float(_state.saved_at)}


## 退出当前档案（只清内存，不删盘）。
func leave_profile() -> void:
	if _state.is_empty() and _attempt.is_empty():
		return
	_reset_memory()
	_emit_changed("left")


# ============================================================
# 商店（购买原子性：先落盘成功才切内存态；失败完整回滚无副作用）
# ============================================================

## 货架视图（只读，不落盘）。返回 {ok, gold, clear_index, stock:[...]}；
## stock 条目 {id, name, price, limit_per_clear, remaining, affordable_count, max_buyable}：
## - remaining：本限购周期剩余可购数，-1 = 不限购（limit_per_clear == 0）。
## - affordable_count：仅金币维度最多可购数（gold / price），-1 = 免费不限。
## - max_buyable：综合限购与金币后的「本次最多还能买几件」，-1 = 双双不限。
## 限购周期唯一基准 = completed_levels.size()：周期推进（新关首通）后旧计数
## 自动视作清零，repeat 通关 / 保存重载都不刷新额度。
func list_shop() -> Dictionary:
	if _state.is_empty():
		return {"ok": false, "error": "尚未加载冒险档案"}
	var loaded: Dictionary = ShopCatalogScript.load_catalog()
	if not loaded.get("ok", false):
		return {"ok": false, "error": str(loaded.error)}
	var clear_index := int(_state.completed_levels.size())
	var counts: Dictionary = _current_purchase_counts()
	var stock: Array = []
	for entry: Variant in loaded.catalog.stock:
		var item_id := StringName(String(entry.id))
		var price := int(entry.price)
		var limit := int(entry.limit_per_clear)
		var bought := int(counts.get(String(item_id), 0))
		var remaining := -1 if limit <= 0 else maxi(0, limit - bought)
		var affordable := -1 if price <= 0 else int(int(_state.gold) / price)
		var max_buyable := _cap_buyable(affordable, remaining)
		stock.append({
			"id": String(item_id),
			"name": str(ItemDataScript.item_name(item_id)),
			"price": price,
			"limit_per_clear": limit,
			"remaining": remaining,
			"affordable_count": affordable,
			"max_buyable": max_buyable,
		})
	return {"ok": true, "error": "", "gold": int(_state.gold), "clear_index": clear_index, "stock": stock}


## 购买：严格原子——所有校验通过后组装完整新态，_persist 成功才提交内存并
## 发 changed；任何失败（未知物/售罄/金币不足/无档/出征挂起/落盘失败）返回
## {ok:false, error}，内存与磁盘完整无副作用（可安全重试，不重复扣费）。
## 买入每件实例满 uses 直接入公共库存；若该物品未被任何携带方案行覆盖，
## 则给队长（roster 首名）行追加 {id, count:1}（已覆盖不重复追加）——下次出征
## 自动带上；FIFO 补给拿不完的留在库存。
## count 取 Variant 并在函数内严格校验（bool/float/字符串一律拒绝）：
## int 形参会在调用点被隐式截断（1.5→1、true→1）或直接抛原生类型错误炸掉
## 调用方（String 经 Variant 通道，2026-11-18 实测），无法返回友好 error。
func buy_item(item_id: String, count: Variant = 1) -> Dictionary:
	if _state.is_empty():
		return {"ok": false, "error": "尚未加载冒险档案"}
	if not _attempt.is_empty():
		return {"ok": false, "error": "战斗进行中，不能购买"}
	if count is not int or int(count) < 1:
		return {"ok": false, "error": "购买数量必须是正整数（收到 %s）" % str(count)}
	var wanted := StringName(String(item_id))
	var loaded: Dictionary = ShopCatalogScript.load_catalog()
	if not loaded.get("ok", false):
		return {"ok": false, "error": str(loaded.error)}
	var entry := ShopCatalogScript.entry_for(String(wanted))
	if entry.is_empty():
		return {"ok": false, "error": "商店不出售：%s" % String(wanted)}
	var price := int(entry.price)
	var limit := int(entry.limit_per_clear)
	var clear_index := int(_state.completed_levels.size())
	var counts: Dictionary = _current_purchase_counts()
	var bought := int(counts.get(String(wanted), 0))
	if limit > 0 and bought + count > limit:
		var remaining := maxi(0, limit - bought)
		return {
			"ok": false,
			"error": "限购：本周期（已通关 %d 关）最多还能购买 %d 件 %s" % [clear_index, remaining, String(wanted)],
		}
	var cost := price * int(count)
	if cost > int(_state.gold):
		return {"ok": false, "error": "金币不足（需要 %d，持有 %d）" % [cost, int(_state.gold)]}
	var max_uses := maxi(1, int(ItemDataScript.get_item(wanted).get("uses", 0)))
	var inventory_new: Array = _state.inventory.duplicate(true)
	for _c in count:
		inventory_new.append({"id": wanted, "uses": max_uses})
	var counts_new: Dictionary = counts.duplicate(true)
	counts_new[String(wanted)] = bought + count
	var templates_new: Array = _state.carry_templates.duplicate(true)
	if not _templates_cover(templates_new, wanted) and not templates_new.is_empty():
		(templates_new[0] as Array).append({"id": wanted, "count": 1})
	var staged := {
		"id": _state.id,
		"name": _state.name,
		"gold": int(_state.gold) - cost,
		"roster": _state.roster,
		"inventory": inventory_new,
		"completed_levels": _state.completed_levels,
		"carry_templates": templates_new,
		"shop_purchases": {"clear_index": clear_index, "counts": counts_new},
		"created_at": _state.created_at,
		"saved_at": Time.get_unix_time_from_system(),
		"last_opened_level": str(_state.get("last_opened_level", "")),
	}
	var persisted := _persist(staged)
	if not persisted.get("ok", false):
		return {"ok": false, "error": "购买落盘失败，未扣费（可重试）：%s" % str(persisted.error)}
	_state = staged
	_emit_changed("purchased")
	var remaining_after := -1 if limit <= 0 else maxi(0, limit - (bought + count))
	return {
		"ok": true,
		"error": "",
		"id": String(wanted),
		"count": count,
		"total_cost": cost,
		"gold": int(_state.gold),
		"remaining": remaining_after,
	}


## 给档内单位装备一件（roster_id = 单位稳定 id）。原子语义与 buy_item 一致：
## 校验 → 深拷贝全量 state、只改副本上目标单位的 equipment 槽 → _persist 成功
## 才提交内存并发 changed；任何失败无副作用。出征挂起（_attempt 非空）时拒绝。
## equip/unequip 本身不动 HP/MP：装上不补满；卸下仅在超容量时钳制（由
## EquipmentData.unequip 完成）。返回 {ok, error, slot, prev, entry}。
func equip_item(roster_id: String, entry_id: String) -> Dictionary:
	if _state.is_empty():
		return {"ok": false, "error": "尚未加载冒险档案"}
	if not _attempt.is_empty():
		return {"ok": false, "error": "战斗进行中，不能更换装备"}
	var staged: Dictionary = _state.duplicate(true)
	var unit := _find_roster_unit(staged, roster_id)
	if unit.is_empty():
		return {"ok": false, "error": "档内单位不存在：%s" % str(roster_id)}
	var outcome: Dictionary = EquipmentDataScript.equip(unit, StringName(String(entry_id)))
	if not bool(outcome.get("ok", false)):
		return {"ok": false, "error": str(outcome.get("reason", "装备失败"))}
	var persisted := _persist(staged)
	if not persisted.get("ok", false):
		return {"ok": false, "error": "装备落盘失败，未生效（可重试）：%s" % str(persisted.error)}
	_state = staged
	_emit_changed("equipped")
	return {
		"ok": true, "error": "",
		"slot": String(outcome.get("slot", "")),
		"prev": String(outcome.get("prev", "")),
		"entry": String(entry_id),
	}


## 卸下档内单位某槽装备（slot ∈ weapon/shield/armor/accessory）。原子语义同
## equip_item；卸下后若 HP/MP 超过新容量则就地钳制（营地单位通常已满，正常
## 情况无变化）。返回 {ok, error, prev, hp_clamped, mp_clamped}。
func unequip_item(roster_id: String, slot: String) -> Dictionary:
	if _state.is_empty():
		return {"ok": false, "error": "尚未加载冒险档案"}
	if not _attempt.is_empty():
		return {"ok": false, "error": "战斗进行中，不能更换装备"}
	var staged: Dictionary = _state.duplicate(true)
	var unit := _find_roster_unit(staged, roster_id)
	if unit.is_empty():
		return {"ok": false, "error": "档内单位不存在：%s" % str(roster_id)}
	var outcome: Dictionary = EquipmentDataScript.unequip(unit, StringName(String(slot)))
	if not bool(outcome.get("ok", false)):
		return {"ok": false, "error": str(outcome.get("reason", "卸下失败"))}
	var persisted := _persist(staged)
	if not persisted.get("ok", false):
		return {"ok": false, "error": "卸下落盘失败，未生效（可重试）：%s" % str(persisted.error)}
	_state = staged
	_emit_changed("unequipped")
	return {
		"ok": true, "error": "",
		"slot": String(slot),
		"prev": String(outcome.get("prev", "")),
		"hp_clamped": bool(outcome.get("hp_clamped", false)),
		"mp_clamped": bool(outcome.get("mp_clamped", false)),
	}


## 在 state 副本里按稳定 id 找档内单位（找不到返回空字典；不修改 state）。
func _find_roster_unit(state: Dictionary, roster_id: String) -> Dictionary:
	var roster: Variant = state.get("roster", [])
	if roster is not Array:
		return {}
	for u: Variant in roster:
		if u is Dictionary and String((u as Dictionary).get("id", "")) == String(roster_id):
			return u
	return {}


## 当前限购周期内的已购计数（周期推进则旧计数视作清零；不修改 _state）。
func _current_purchase_counts() -> Dictionary:
	var purchases: Variant = _state.get("shop_purchases", null)
	if purchases is not Dictionary:
		return {}
	var record: Dictionary = purchases
	if int(record.get("clear_index", -1)) != int(_state.completed_levels.size()):
		return {}
	var raw_counts: Variant = record.get("counts", {})
	return raw_counts if raw_counts is Dictionary else {}


## 综合可购上限：-1 视为不限，双双不限返回 -1。
func _cap_buyable(gold_cap: int, limit_cap: int) -> int:
	if gold_cap < 0 and limit_cap < 0:
		return -1
	if gold_cap < 0:
		return limit_cap
	if limit_cap < 0:
		return gold_cap
	return mini(gold_cap, limit_cap)


## 物品是否已被任意携带方案行覆盖（购买补模板的判据）。
func _templates_cover(templates: Array, item_id: StringName) -> bool:
	for row: Variant in templates:
		if row is not Array:
			continue
		for entry: Variant in row:
			if entry is Dictionary and StringName(String((entry as Dictionary).get("id", ""))) == item_id:
				return true
	return false



# ============================================================
# 出征与结算
# ============================================================

## 出征：校验解锁与无挂起战斗 -> 部署档内队伍到战场（全员出征，自动补给）->
## 落盘出征前快照 + attempt 标记（失败则回滚并取消出征）。返回 {ok, chapter,
## token, level_id, deployed_count, extra_ids, sit_out_ids(恒空), difficulty
## (档案难度档，出征注入战斗)}。chapter 为深拷贝，可直传战斗。
func prepare_battle(level_id: String) -> Dictionary:
	if _state.is_empty():
		return {"ok": false, "error": "尚未加载冒险档案"}
	if not _attempt.is_empty():
		return {"ok": false, "error": "已有出征中的战斗（%s），请先完成或退出" % str(_attempt.level_id)}
	var level: Dictionary = CampaignConfigScript.get_level(level_id)
	if level.is_empty():
		return {"ok": false, "error": "未知关卡：%s" % level_id}
	if not _level_unlocked(int(level.index), _state.completed_levels):
		return {"ok": false, "error": "关卡未解锁：%s" % str(level.name)}
	var probe: Dictionary = BattlefieldLoaderScript.load_battlefield(str(level.source))
	if not probe.get("ok", false):
		return {"ok": false, "error": "战场装载失败：%s" % str(probe.error)}
	var snapshot := {
		"gold": int(_state.gold),
		"roster": _state.roster.duplicate(true),
		"inventory": _state.inventory.duplicate(true),
		"completed": _state.completed_levels.duplicate(true),
	}
	var deployment: Dictionary = Roster.deploy(probe.chapter, _state.roster, _state.inventory, _state.carry_templates)
	if not deployment.get("ok", false):
		_state["inventory"] = snapshot.inventory
		return {"ok": false, "error": "队伍部署失败：%s" % str(deployment.error)}
	var token := _gen_token()
	var previous_opened := str(_state.get("last_opened_level", ""))
	_state["last_opened_level"] = str(level.id)
	_attempt = {
		"token": token,
		"level_id": str(level.id),
		"prepared_at": Time.get_unix_time_from_system(),
		"snapshot": snapshot,
		"loot_seed": randi(),
	}
	# 出征前快照必须落盘成功：失败则回滚出征扣减与挂起态，阻止进入战斗
	# （没有安全快照不允许出征，绝不静默继续）。
	var persisted := _persist_safe()
	if not persisted.get("ok", false):
		_state["inventory"] = snapshot.inventory
		_state["last_opened_level"] = previous_opened
		_attempt = {}
		return {"ok": false, "error": "出征前存档写入失败，已取消出征（可重试）：%s" % str(persisted.error)}
	var out := {
		"ok": true,
		"error": "",
		"chapter": deployment.chapter,
		"token": token,
		"level_id": str(level.id),
		"deployed_count": int(deployment.deployed_count),
		"extra_ids": deployment.extra_ids,
		"sit_out_ids": deployment.sit_out_ids,
		"difficulty": str(_state.get("difficulty", AIDifficultyScript.DEFAULT)),
	}
	_emit_changed("prepared")
	return out


## 结算（幂等）：result 兼容 String/StringName 的 "win"/"lose"/"abandon"。
## - win：从终局 chapter（只读）吸收成长 -> 组装新态 -> 落盘成功才提交内存并清
##   attempt；落盘失败返回 {ok:false, retryable:true}，内存不动，可同 token 重试。
##   成功 receipt 附 level_ups（_diff_level_ups 差分，失败/撤退不产生）。
## - lose/abandon：回滚出征前快照，重新落盘（标记自愈）。
## 同 token 重复结算返回缓存结果 + already_settled=true。
func settle_battle(token: String, result: Variant, chapter: Dictionary = {}) -> Dictionary:
	var result_str := _normalize_result(result)
	if result_str == "":
		return {"ok": false, "error": "未知战斗结果：%s（期望 win/lose/abandon）" % str(result)}
	if token == "":
		return {"ok": false, "error": "出征令牌为空"}
	if _last_settled_token == token and not _last_result.is_empty():
		var cached: Dictionary = _last_result.duplicate(true)
		cached["already_settled"] = true
		return cached
	if _attempt.is_empty():
		return {"ok": false, "error": "当前没有出征中的战斗"}
	if str(_attempt.token) != token:
		return {"ok": false, "error": "出征令牌不匹配"}
	var level_id := str(_attempt.level_id)
	var level: Dictionary = CampaignConfigScript.get_level(level_id)
	var level_name := str(level.get("name", level_id))
	if result_str == "win":
		return _settle_win(token, level_id, level_name, chapter)
	return _settle_restore(token, result_str, level_id, level_name)


# ============================================================
# 内部：结算实现
# ============================================================

func _settle_win(token: String, level_id: String, level_name: String, chapter: Dictionary) -> Dictionary:
	var units: Variant = chapter.get("playerUnits", [])
	if units is not Array or units.is_empty():
		return {"ok": false, "error": "胜利结算缺少终局战场数据（playerUnits）"}
	var imported: Dictionary = Roster.import_victory(chapter, _state.roster)
	if not imported.get("ok", false):
		return {"ok": false, "error": str(imported.error)}
	# 升级差分只在这里做（按 id 对位出征前快照 vs 吸收后队伍，不重放 RNG，
	# 不侵入 Roster 吸收逻辑）；落盘失败路径不携带 level_ups —— 差分随成功
	# payload 一起发布。
	var level_ups: Array = _diff_level_ups(_attempt.snapshot.roster, imported.roster_new)
	var first_clear: bool = not _state.completed_levels.has(level_id)
	var rewards: Dictionary = CampaignConfigScript.rewards_for(level_id, first_clear)
	var gold_before := int(_state.gold)
	var inventory_new: Array = _state.inventory.duplicate(true)
	for inst: Variant in imported.recovered:
		if inst is Dictionary:
			inventory_new.append((inst as Dictionary).duplicate(true))
	var items_awarded: Array = []
	for reward_item: Variant in rewards.items:
		var iid := StringName(String(reward_item.get("id", "")))
		if iid == &"":
			continue
		var max_uses := maxi(1, int(ItemDataScript.get_item(iid).get("uses", 0)))
		var count := maxi(0, int(reward_item.get("count", 0)))
		for c in count:
			inventory_new.append({"id": iid, "uses": max_uses})
		items_awarded.append({
			"id": String(iid),
			"name": str(reward_item.get("name", String(iid))),
			"uses": max_uses,
			"count": count,
		})
	# 掉落（关卡 loot_table 掷骰 + 战斗层击杀积累 pending_loot）只入胜利账：
	# 失败/撤退路径不经过这里，inventory 由快照恢复出征前精确值。
	var loot_award: Array = _victory_loot(rewards, chapter)
	for loot_entry: Variant in loot_award:
		var loot_id := StringName(String(loot_entry.get("id", "")))
		var loot_uses := maxi(1, int(loot_entry.get("uses", 1)))
		for c in int(loot_entry.get("count", 0)):
			inventory_new.append({"id": loot_id, "uses": loot_uses})
	var completed_new: Array = _state.completed_levels.duplicate(true)
	if first_clear:
		completed_new.append(level_id)
	var staged := {
		"id": _state.id,
		"name": _state.name,
		"gold": gold_before + int(rewards.gold),
		"roster": imported.roster_new,
		"inventory": inventory_new,
		"completed_levels": completed_new,
		"carry_templates": _state.carry_templates,
		"shop_purchases": _state.shop_purchases,
		"created_at": _state.created_at,
		"saved_at": Time.get_unix_time_from_system(),
		"last_opened_level": str(_state.get("last_opened_level", "")),
	}
	var persisted := _persist(staged)
	if not persisted.get("ok", false):
		return {
			"ok": false,
			"error": "胜利结算落盘失败，可重试（奖励未入账）：%s" % str(persisted.error),
			"retryable": true,
			"level_id": level_id,
			"level_name": level_name,
		}
	var gold_awarded := int(rewards.gold)
	var payload := {
		"ok": true,
		"error": "",
		"result": "win",
		"level_id": level_id,
		"level_name": level_name,
		"first_clear": first_clear,
		"gold": gold_awarded,
		"gold_awarded": gold_awarded,
		"items": items_awarded,
		"items_awarded": items_awarded,
		"loot": loot_award,
		"gold_before": gold_before,
		"gold_after": int(staged.gold),
		"items_recovered": int(imported.recovered.size()),
		"level_ups": level_ups,
		"persisted": true,
	}
	_state = staged
	_attempt = {}
	_last_settled_token = token
	_last_result = payload
	_emit_changed("settled")
	return payload


func _settle_restore(token: String, result_str: String, level_id: String, level_name: String) -> Dictionary:
	var snapshot: Dictionary = _attempt.snapshot
	_state["gold"] = int(snapshot.gold)
	_state["roster"] = snapshot.roster
	_state["inventory"] = snapshot.inventory
	_state["completed_levels"] = snapshot.completed
	_attempt = {}
	var payload := {
		"ok": true,
		"error": "",
		"result": result_str,
		"level_id": level_id,
		"level_name": level_name,
		"restored": true,
		"persisted": true,
	}
	var persisted := _persist_safe()
	if not persisted.get("ok", false):
		payload["persisted"] = false
		payload["persist_warning"] = "回Hub存档写入失败（%s）：下次保存将自动重试" % str(persisted.error)
	_last_settled_token = token
	_last_result = payload
	_emit_changed("settled")
	return payload


## 胜利结算的升级差分：按 id 对位出征前快照 roster 与吸收后 roster_new，
## 只有等级提升的单位才列入（exp 变化未升级不列）。stat_deltas 取 stats
## 上限差（新-旧，只含双方都有且非零的键）。宽松形状：非 Dictionary 单位、
## 缺 id/level、对位缺失一律跳过，绝不抛错。
func _diff_level_ups(before_roster: Array, after_roster: Array) -> Array:
	var before_by_id := {}
	for unit: Variant in before_roster:
		if unit is Dictionary and (unit as Dictionary).has("id"):
			before_by_id[String((unit as Dictionary).id)] = unit
	var level_ups: Array = []
	for unit: Variant in after_roster:
		if unit is not Dictionary or not (unit as Dictionary).has("id"):
			continue
		var after_unit: Dictionary = unit
		var before_unit: Variant = before_by_id.get(String(after_unit.id))
		if before_unit is not Dictionary:
			continue
		var from_level := maxi(1, int((before_unit as Dictionary).get("level", 1)))
		var to_level := maxi(1, int(after_unit.get("level", 1)))
		if to_level <= from_level:
			continue
		var stat_deltas := {}
		var before_stats: Dictionary = (before_unit as Dictionary).get("stats", {})
		var after_stats: Dictionary = after_unit.get("stats", {})
		for stat_key: Variant in after_stats.keys():
			if not before_stats.has(stat_key):
				continue
			var delta := int(after_stats[stat_key]) - int(before_stats[stat_key])
			if delta != 0:
				stat_deltas[String(stat_key)] = delta
		level_ups.append({
			"id": String(after_unit.id),
			"name": str(after_unit.get("name", (before_unit as Dictionary).get("name", after_unit.id))),
			"from_level": from_level,
			"to_level": to_level,
			"stat_deltas": stat_deltas,
		})
	return level_ups


## 胜利掉落：关卡 loot_table 掷骰（独立 RandomNumberGenerator，种子为出征时
## 生成的 _attempt.loot_seed（int，非 RNG 对象，不落盘），绝不触碰战斗全局随机流）
## 合并战斗层积累的 chapter.pending_loot[{id,count}]（对 chapter 只读，未知物品
## 条目跳过），同 id 合并计数、按首次出现序输出
## [{id:StringName, name:String, count:int, uses:int}]（uses = 掉落统一满充）。
## 掷出结果缓存于内存 _attempt.loot_rolled：落盘失败重试直接复用绝不重掷
## （「保存失败重试不重掷」）；进程重启后 attempt 标记恢复为出征前态，缓存自然
## 失效则重掷——上一次结果从未入账，无重复风险。
func _victory_loot(rewards: Dictionary, chapter: Dictionary) -> Array:
	if _attempt.has("loot_rolled"):
		return (_attempt.loot_rolled as Array).duplicate(true)
	var merged := {}
	var order: Array = []
	var loot_table: Array = rewards.get("loot_table", [])
	var loot_rolls := int(rewards.get("loot_rolls", 0))
	if not loot_table.is_empty() and loot_rolls > 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(_attempt.get("loot_seed", randi()))
		for rolled: Variant in CampaignConfigScript.roll_loot(loot_table, loot_rolls, rng):
			if rolled is not Dictionary:
				continue
			var rolled_id := StringName(String((rolled as Dictionary).get("id", "")))
			if rolled_id == &"":
				continue
			_merge_loot_entry(merged, order, rolled_id, maxi(0, int((rolled as Dictionary).get("count", 0))))
	var pending: Variant = chapter.get("pending_loot", [])
	if pending is Array:
		for raw: Variant in pending:
			if raw is not Dictionary:
				continue
			var pending_id := StringName(String((raw as Dictionary).get("id", "")))
			if pending_id == &"" or ItemDataScript.get_item(pending_id).get("id", &"") != pending_id:
				continue
			_merge_loot_entry(merged, order, pending_id, maxi(1, int((raw as Dictionary).get("count", 1))))
	var out: Array = []
	for key: Variant in order:
		var entry: Dictionary = merged[key]
		out.append({
			"id": entry.id,
			"name": str(entry.name),
			"count": int(entry.count),
			"uses": maxi(1, int(ItemDataScript.get_item(entry.id).get("uses", 0))),
		})
	_attempt["loot_rolled"] = out.duplicate(true)
	return out


func _merge_loot_entry(merged: Dictionary, order: Array, item_id: StringName, count: int) -> void:
	if count <= 0:
		return
	var key := String(item_id)
	if merged.has(key):
		(merged[key] as Dictionary)["count"] = int((merged[key] as Dictionary).count) + count
	else:
		merged[key] = {
			"id": item_id,
			"name": str(ItemDataScript.item_name(item_id)),
			"count": count,
		}
		order.append(key)


# ============================================================
# 内部：持久化与工具
# ============================================================

func _ensure_store() -> StoreScript:
	if _store == null or _store.base_dir != base_dir:
		_store = StoreScript.new()
		_store.base_dir = base_dir
	return _store


## 落盘一个完整 state（capture -> store.save_profile）。
func _persist(state: Dictionary) -> Dictionary:
	var captured := Codec.capture(state)
	if not captured.get("ok", false):
		return {"ok": false, "error": str(captured.error)}
	return _ensure_store().save_profile(captured.record)


## 落盘"安全态"：出征挂起时用出征前快照 + attempt 标记；否则当前态。
## override_name 非空时用新名落盘（重命名场景）。成功后同步内存 saved_at/名字。
func _persist_safe(override_name := "") -> Dictionary:
	var now := Time.get_unix_time_from_system()
	var st: Dictionary
	if not _attempt.is_empty():
		var snapshot: Dictionary = _attempt.snapshot
		st = {
			"id": _state.id,
			"name": _state.name if override_name == "" else override_name,
			"gold": int(snapshot.gold),
			"roster": snapshot.roster,
			"inventory": snapshot.inventory,
			"completed_levels": snapshot.completed,
			"carry_templates": _state.carry_templates,
			"shop_purchases": _state.shop_purchases,
			"created_at": _state.created_at,
			"saved_at": now,
			"last_opened_level": str(_state.get("last_opened_level", "")),
			"attempt": {
				"level_id": str(_attempt.level_id),
				"prepared_at": float(_attempt.prepared_at),
			},
		}
	else:
		st = _state.duplicate(true)
		st["saved_at"] = now
		if override_name != "":
			st["name"] = override_name
	var persisted := _persist(st)
	if persisted.get("ok", false):
		_state["saved_at"] = now
		if override_name != "":
			_state["name"] = override_name
	return persisted


func _level_unlocked(index: int, completed: Array) -> bool:
	if index <= 0:
		return true
	var levels: Array = CampaignConfigScript.levels()
	if completed.has(str(levels[index].id)):
		return true
	if index <= levels.size():
		return completed.has(str(levels[index - 1].id))
	return false


## 记录最近使用档案（索引写失败静默容忍，不影响加载/创建）。
func _mark_latest(profile_id: String) -> void:
	if profile_id == "":
		return
	_ensure_store().set_latest_profile(profile_id)


func _validate_name(profile_name: String) -> Dictionary:
	var stripped := profile_name.strip_edges()
	if stripped == "":
		return {"ok": false, "error": "档案名不能为空"}
	if stripped.length() > 32:
		return {"ok": false, "error": "档案名过长（最多 32 字符）"}
	return {"ok": true, "error": "", "name": stripped}


func _normalize_result(result: Variant) -> String:
	var s := str(result)
	if s == "win" or s == "lose" or s == "abandon":
		return s
	return ""


func _reset_memory() -> void:
	_state = {}
	_attempt = {}
	_last_result = {}
	_last_settled_token = ""


func _gen_profile_id() -> String:
	var existing := {}
	for entry: Variant in _ensure_store().list_records():
		if entry is Dictionary and entry.get("record") is Dictionary:
			existing[str((entry.record as Dictionary).get("id", ""))] = true
	var stamp := int(Time.get_unix_time_from_system())
	for i in 16:
		var candidate := "p_%x_%06x" % [stamp, randi() & 0xFFFFFF]
		if not existing.has(candidate):
			return candidate
	return "p_%x_%x" % [stamp, randi()]


func _gen_token() -> String:
	return "t_%x_%06x" % [int(Time.get_unix_time_from_system()), randi() & 0xFFFFFF]


func _emit_changed(reason: String) -> void:
	changed.emit(reason)
