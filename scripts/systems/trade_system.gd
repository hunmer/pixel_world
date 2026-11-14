## systems/trade_system.gd — 相邻友军物品交换（FE 式 trade，全静态）
##
## 契约（docs/gameplay_gap.md C1）：
##   - 单向转移一件物品（来回点两次 = 交换）
##   - 仅相邻 1 格（曼哈顿距离 1）同阵营存活友军之间
##   - uses 原样保留；条目整体搬移（含装备类）
##   - 交换是自由动作：不置 hasActed，由 UI 层负责
##
## 公开 API：
##   can_trade(from, to) -> { ok: bool, reason: StringName }
##   adjacent_trade_targets(unit, grid) -> Array   # 带物品的相邻友军
##   execute_trade(from, to, item_entry) -> Dictionary

class_name TradeSystem
extends RefCounted


## 合法性检查：同阵营、双方存活、非自身、曼哈顿距离恰为 1。
## 返回 { ok: bool, reason: StringName }（ok=false 时 reason ∈
## self/dead/faction/distance）。
static func can_trade(from: Dictionary, to: Dictionary) -> Dictionary:
	if from.is_empty() or to.is_empty():
		return { ok = false, reason = &"empty" }
	if StringName(from.get(&"id", &"")) == StringName(to.get(&"id", &"")) \
			and StringName(from.get(&"id", &"")) != &"":
		return { ok = false, reason = &"self" }
	if bool(to.get(&"isDead", false)) or bool(from.get(&"isDead", false)):
		return { ok = false, reason = &"dead" }
	if StringName(to.get(&"faction", &"")) != StringName(from.get(&"faction", &"")):
		return { ok = false, reason = &"faction" }
	var fp: Vector2i = from.get(&"position", Vector2i.ZERO)
	var tp: Vector2i = to.get(&"position", Vector2i.ZERO)
	var dist := absi(tp.x - fp.x) + absi(tp.y - fp.y)
	if dist != 1:
		return { ok = false, reason = &"distance" }
	return { ok = true, reason = &"" }


## 列出与 unit 相邻 1 格、同阵营、存活且带物品的友军（供行动菜单「交换」项）。
## grid 为 null（headless 契约测试）时返回空。
static func adjacent_trade_targets(unit: Dictionary, grid) -> Array:
	if grid == null:
		return []
	var out: Array = []
	var up: Vector2i = unit.get(&"position", Vector2i.ZERO)
	for other in grid.units.values():
		if bool(other.get(&"isDead", false)):
			continue
		if StringName(other.get(&"faction", &"")) != StringName(unit.get(&"faction", &"")):
			continue
		var op: Vector2i = other.get(&"position", Vector2i.ZERO)
		var dist := absi(op.x - up.x) + absi(op.y - up.y)
		if dist != 1:
			continue
		if (other.get(&"items", []) as Array).is_empty():
			continue
		out.append(other)
	return out


## 执行单向转移：把 from 背包中的 item_entry（{id, uses} 引用）搬给 to。
## 校验：can_trade 通过、entry 确实在 from.items 中。
## 成功：from 删该条目、to 追加同 id 同 uses 的新条目；返回 { ok = true, entry }。
## 失败：返回 { ok = false, reason }，不改动任何一方。
static func execute_trade(from: Dictionary, to: Dictionary, item_entry: Dictionary) -> Dictionary:
	var gate := can_trade(from, to)
	if not gate[&"ok"]:
		return { ok = false, reason = gate[&"reason"] }
	var from_items: Array = from.get(&"items", [])
	if not from_items.has(item_entry):
		return { ok = false, reason = &"not_owned" }
	# 复制成新条目再追加，避免双方背包共享同一 Dictionary 引用。
	var moved := {
		id = item_entry.get(&"id", &""),
		uses = int(item_entry.get(&"uses", 0)),
	}
	from_items.erase(item_entry)
	if not to.has(&"items"):
		to[&"items"] = []
	(to[&"items"] as Array).append(moved)
	return { ok = true, reason = &"", entry = moved }
