## battle/immersive_stage_layout.gd — 沉浸舞台的纯布局/重建逻辑（无节点、无副作用）。
##
## 职责：
##   - participants_for：事件参战者收集（出手者 + 主目标 + 每个 impact 的 source/target 去重），
##     含真实夹击追击友军与反击方；顺序 = 出手者、主目标、impact 顺序。
##   - build_slots：阵营对角站位 —— 我方/友军站屏幕左下角、敌方站右上角（按 faction 固定，
##     不因敌方先手换侧；治疗/自buff 同阵营不造敌方站位）。阵营内出手者与主目标站前排中央。
##   - initial_hp_map：代理初态重建 —— 每个参与者取其作为目标的第一个 impact 的 hp_before；
##     从未成为目标者沿用真实当前 HP（演出绝不回写真实数据）。
##   - strike_anim_for / strike_label：逐 impact 出手模板（按实际 source 武器）与可辨识标签。
##
## 屏幕方向推导（IsoProjection yaw=45°，推导自 grid_to_world 与相机正交基）：
##   grid +x → 屏幕(右 0.5, 下 0.25)；grid +y → 屏幕(左 0.5, 下 0.25)。
##   故 ±y 轴即屏幕对角：+y=左下（我方侧），−y=右上（敌方侧）；(±1,∓1) 为屏幕水平行。
class_name ImmersiveStageLayout
extends RefCounted

const AttackEventScript = preload("res://scripts/systems/attack_event.gd")
const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")

const SIDE_ALLY := &"ally"
const SIDE_ENEMY := &"enemy"
## player/ally → 我方侧；enemy/other → 敌方侧（中立可被攻击，与敌方同侧）。
const ENEMY_FACTIONS: Array = [&"enemy", &"other"]
## 阵营锚点离舞台中心的格距（沿 ±y 对角）；两锚点屏幕间距 = (水平 5, 垂直 2.5) 世界单位。
const ANCHOR_STEPS := 5
## 排深：后排沿本阵营对角外方向再退的格距。
const ROW_DEPTH_STEPS := 2
## 每排槽位数（中/左/右），前排中央留给出手者/主目标。
const ROW_SLOTS := 3


static func side_of(unit: Dictionary) -> StringName:
	var faction := StringName(unit.get(&"faction", &"other"))
	return SIDE_ENEMY if ENEMY_FACTIONS.has(faction) else SIDE_ALLY


## 参战者（真实单位引用，按事件顺序）；units 为真实 grid.units 的引用字典。
static func participants_for(event: Dictionary, units: Dictionary) -> Array:
	var ids: Array = [
		StringName(event.get(&"attacker_id", &"")),
		StringName(event.get(&"primary_target_id", AttackEventScript.primary_target_id(event))),
	]
	for raw_impact in event.get(&"impacts", []):
		var impact: Dictionary = raw_impact
		ids.append(StringName(impact.get(&"source_id", &"")))
		ids.append(StringName(impact.get(&"target_id", &"")))
	var out: Array = []
	var seen := {}
	for raw_id in ids:
		var unit_id := StringName(raw_id)
		if unit_id == &"" or seen.has(unit_id) or not units.has(unit_id):
			continue
		seen[unit_id] = true
		out.append(units[unit_id])
	return out


## 对角站位：{ unitId -> { cell: Vector2i, side: StringName, facing: Vector3 } }。
## facing 为世界空间水平朝向（面向对侧阵营锚点）。
static func build_slots(event: Dictionary, participants: Array) -> Dictionary:
	var attacker_id := StringName(event.get(&"attacker_id", &""))
	var primary_id := AttackEventScript.primary_target_id(event)
	var ally_order: Array = []
	var enemy_order: Array = []
	for raw_unit in participants:
		var unit: Dictionary = raw_unit
		if side_of(unit) == SIDE_ENEMY:
			enemy_order.append(unit)
		else:
			ally_order.append(unit)
	_prioritize(ally_order, attacker_id, primary_id)
	_prioritize(enemy_order, attacker_id, primary_id)
	var slots := {}
	_assign_camp(slots, ally_order, SIDE_ALLY)
	_assign_camp(slots, enemy_order, SIDE_ENEMY)
	return slots


## 阵营内排序：出手者最前、主目标次之，其余保持参与者顺序。
## Godot sort_custom 使用不稳定排序（pdqsort），相同 rank 必须用原始参加下标显式决胜，
## 否则同阵营多名普通参战者的站位顺序不可复现。
static func _prioritize(order: Array, attacker_id: StringName, primary_id: StringName) -> void:
	var indexed: Array = []
	for i in range(order.size()):
		indexed.append({
			"rank": _rank(order[i], attacker_id, primary_id),
			"i": i,
			"unit": order[i],
		})
	indexed.sort_custom(func(a, b) -> bool:
		if int(a["rank"]) != int(b["rank"]):
			return int(a["rank"]) < int(b["rank"])
		return int(a["i"]) < int(b["i"]))
	for i in range(indexed.size()):
		order[i] = indexed[i]["unit"]


static func _rank(unit: Dictionary, attacker_id: StringName, primary_id: StringName) -> int:
	var unit_id := StringName(unit.get(&"id", &""))
	if unit_id == attacker_id:
		return 0
	if unit_id == primary_id:
		return 1
	return 2


## 单侧阵营布阵：前排中央起，前左/前右，再退一排；后排沿对角外方向（更深的角落）。
static func _assign_camp(slots: Dictionary, order: Array, side: StringName) -> void:
	if order.is_empty():
		return
	var anchor := _anchor_for(side)
	var outward := _outward_for(side)
	for i in range(order.size()):
		var unit: Dictionary = order[i]
		var row := i / ROW_SLOTS
		var col := i % ROW_SLOTS
		var lateral := Vector2i.ZERO
		match col:
			1:
				lateral = Vector2i(-1, 1)
			2:
				lateral = Vector2i(1, -1)
		var cell := anchor + lateral + outward * (row * ROW_DEPTH_STEPS)
		slots[unit[&"id"]] = {
			&"cell": cell,
			&"side": side,
			&"facing": facing_world(cell, _anchor_for(_opposite(side))),
		}


static func _anchor_for(side: StringName) -> Vector2i:
	return Vector2i(0, -ANCHOR_STEPS) if side == SIDE_ENEMY else Vector2i(0, ANCHOR_STEPS)


## 本阵营"更深处"方向：我方继续往左下，敌方继续往右上。
static func _outward_for(side: StringName) -> Vector2i:
	return Vector2i(0, -1) if side == SIDE_ENEMY else Vector2i(0, 1)


static func _opposite(side: StringName) -> StringName:
	return SIDE_ALLY if side == SIDE_ENEMY else SIDE_ENEMY


## 格位 → 世界水平朝向（面向对侧锚点）；零向量兜底朝向敌方侧。
static func facing_world(cell: Vector2i, toward_cell: Vector2i) -> Vector3:
	var dir := IsoProjection.grid_to_world(toward_cell, 0.0) - IsoProjection.grid_to_world(cell, 0.0)
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0).normalized()
	return dir.normalized()


## 代理初态：{ unitId -> { hp: int（首个作为目标的 impact 的 hp_before；否则真实当前 HP）, dies: bool } }。
## participants_units 为 { unitId -> 真实单位 dict }（仅参战者）。
static func initial_hp_map(event: Dictionary, participants_units: Dictionary) -> Dictionary:
	var out := {}
	for raw_impact in event.get(&"impacts", []):
		var impact: Dictionary = raw_impact
		var target_id := StringName(impact.get(&"target_id", &""))
		if target_id == &"" or not participants_units.has(target_id):
			continue
		if not out.has(target_id):
			out[target_id] = {
				&"hp": int(impact.get(&"hp_before", 0)),
				&"dies": bool(impact.get(&"died", false)),
			}
		elif bool(impact.get(&"died", false)):
			out[target_id][&"dies"] = true
	for unit_id in participants_units.keys():
		if out.has(unit_id):
			continue
		var unit: Dictionary = participants_units[unit_id]
		out[unit_id] = { &"hp": int(unit.get(&"hp", 0)), &"dies": false }
	return out


## 逐 impact 出手模板：技能沿用事件 anim；普攻按实际 source 武器（与
## AttackEvent.from_combat 同映射），反击/追击因此拿到正确的出手视觉与音效。
static func strike_anim_for(event: Dictionary, unit: Dictionary) -> StringName:
	if StringName(event.get(&"kind", &"normal")) == &"skill":
		return StringName(event.get(&"anim", &"slash"))
	var weapon_type := StringName(unit.get(&"weapon", {}).get(&"type", &"sword"))
	match weapon_type:
		&"bow":
			return &"projectile:arrow"
		&"anima":
			return &"projectile:fire"
		&"dark":
			return &"projectile:dark"
		&"staff":
			return &"burst:holy"
		_:
			return &"slash"


## 出手可辨识标签：反击 = 非事件出手者的出手；连击 = 普攻事件 double_attack 的第二段。
## 追击（夹击）已有金色菱形高亮 + 伤害「追击」前缀，这里返回空串避免重复。
static func strike_label(event: Dictionary, index: int, impact: Dictionary) -> String:
	if bool(impact.get(&"pincer", false)):
		return ""
	var attacker_id := StringName(event.get(&"attacker_id", &""))
	var source_id := StringName(impact.get(&"source_id", &""))
	if source_id != attacker_id:
		return "反击"
	if StringName(event.get(&"kind", &"normal")) != &"skill" and index > 0 and bool(event.get(&"double_attack", false)):
		return "连击"
	return ""
