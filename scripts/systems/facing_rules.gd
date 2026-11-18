## systems/facing_rules.gd — 网格朝向与背击规则（全静态、零依赖）
##
## 逻辑朝向是 UnitData 上的运行时字段 unit.facing: Vector2i（网格空间，逐轴 sign 的
## 单位向量，不随相机旋转；与表现层 UnitSprite3D._facing_world 解耦）。
## 生命周期：
##   - 开场 initialize_facings：每个单位面向最近敌方（与表现层 _orient_units_toward_opponents 同语义）；
##   - 移动 face_move（由 GridSystem.place_unit 统一接线）：面向移动方向；
##   - Vector2i.ZERO = 「无朝向」（旧档/未初始化单位），永不判背击 —— 兼容旧存档与纯单测。
## 背击判定：受击者面朝方向与「指向攻击者方向」点积 < 0（背对攻击者）才触发；
## 正面 > 0 / 侧面 = 0 / 无朝向或同格均不触发。治疗/增益不走伤害公式，天然不受影响。
## 伤害增幅统一经 apply_backstab 施加于「本次总伤害」：普攻在 CombatSystem.preview /
## execute（三角修正合并后）、技能在 SkillSystem._skill_damage、投掷物在 ItemSystem ——
## 预览、真实结算、AI 评估、无头 runner 全部共用同一公式。
class_name FacingRules
extends RefCounted

## 背击伤害倍率（从背后命中时本次伤害 ×1.25；可调常量，无配置文件依赖）。
const BACKSTAB_DAMAGE_MULTIPLIER := 1.25

## 「无朝向」哨兵值：旧档单位缺 facing 字段时容错返回，背击规则对其关闭。
const NO_FACING := Vector2i.ZERO


## 读单位逻辑朝向（网格空间；缺省/类型异常一律回退 NO_FACING）。
static func get_facing(unit: Dictionary) -> Vector2i:
	var facing = unit.get(&"facing", NO_FACING)
	if facing is Vector2i:
		return facing
	return NO_FACING


## 是否背击：attacker_pos 对 defender 发起攻击，defender 背对攻击者时为 true。
## to_attacker = 受击者指向攻击者的单位向量；dot(facing, to_attacker) < 0 即攻击来自身后。
## Vector2i 无 dot()（仅 Vector2 有），用分量乘加实现点积。
static func is_backstab(attacker_pos: Vector2i, defender: Dictionary) -> bool:
	var facing := get_facing(defender)
	if facing == NO_FACING:
		return false
	var dp: Vector2i = defender.get(&"position", Vector2i.ZERO)
	var to_attacker := Vector2i(signi(attacker_pos.x - dp.x), signi(attacker_pos.y - dp.y))
	if to_attacker == Vector2i.ZERO:
		return false
	var dot := facing.x * to_attacker.x + facing.y * to_attacker.y
	return dot < 0


## 伤害背击增幅：背击时 ×BACKSTAB_DAMAGE_MULTIPLIER（roundi 四舍五入），
## 否则原值返回。0 伤害乘后仍为 0；暴击 ×3 在调用方（CombatSystem.execute）其后叠乘。
static func apply_backstab(attacker_pos: Vector2i, defender: Dictionary, base_damage: int) -> int:
	if base_damage <= 0 or not is_backstab(attacker_pos, defender):
		return base_damage
	return maxi(0, roundi(base_damage * BACKSTAB_DAMAGE_MULTIPLIER))


## 出手/瞄准：面向目标格（同格不变）。
static func face_toward(unit: Dictionary, target_pos: Vector2i) -> void:
	var mp: Vector2i = unit.get(&"position", Vector2i.ZERO)
	var dir := Vector2i(signi(target_pos.x - mp.x), signi(target_pos.y - mp.y))
	if dir != Vector2i.ZERO:
		unit[&"facing"] = dir


## 移动后朝向移动方向（from→to 的逐轴 sign；零位移不动朝向）。
static func face_move(unit: Dictionary, from: Vector2i, to: Vector2i) -> void:
	var delta := to - from
	if delta == Vector2i.ZERO:
		return
	unit[&"facing"] = Vector2i(signi(delta.x), signi(delta.y))


## 开场初始化：每个「尚无朝向」的在场单位面向最近敌方（曼哈顿距离；平手取先遍历者，确定性）。
## 已有朝向的单位（读档恢复 / 增援入场后再触发）保持原值 —— 逻辑朝向随存档持久化
## （battle_save_codec 全量编码 Vector2i），读档重入开场链路不会被重置。
## 无敌方时保持原朝向。units 传 grid.units.values() 或 playerUnits+enemyUnits。
static func initialize_facings(units: Array) -> void:
	for raw in units:
		var unit: Dictionary = raw
		if bool(unit.get(&"isDead", false)):
			continue
		if get_facing(unit) != NO_FACING:
			continue
		orient_toward_nearest_enemy(unit, units)


## 单个单位面向最近敌方（曼哈顿距离，平手取先遍历者）；无敌方时不动。
## 增援入场等「单位逐个进场」场景用这个，避免对全场重算。
static func orient_toward_nearest_enemy(unit: Dictionary, units: Array) -> void:
	var mp: Vector2i = unit.get(&"position", Vector2i.ZERO)
	var my_faction = unit.get(&"faction", &"")
	var nearest: Vector2i = Vector2i.ZERO
	var nearest_dist := -1
	for raw_other in units:
		var other: Dictionary = raw_other
		if bool(other.get(&"isDead", false)) or other.get(&"faction", &"") == my_faction:
			continue
		var op: Vector2i = other.get(&"position", Vector2i.ZERO)
		var dist := absi(op.x - mp.x) + absi(op.y - mp.y)
		if nearest_dist < 0 or dist < nearest_dist:
			nearest_dist = dist
			nearest = op
	if nearest_dist >= 0:
		face_toward(unit, nearest)
