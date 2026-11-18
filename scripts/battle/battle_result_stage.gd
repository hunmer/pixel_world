## battle/battle_result_stage.gd — 结算演出视觉（欢呼/倒地/死亡淡出 + 姿态捕获与恢复）
##
## 职责：
##   - 胜利欢呼：存活单位跳一下（global_position 上抛回落）
##   - 败北倒地：立绘 rotation:z 倒下 + 半透明
##   - 死亡淡出：fade_alpha 1→0 + 放大 1.5x + 隐藏
##   - 姿态捕获/恢复：演出前记录 sprite 姿态（位置/缩放/可见性/立绘角度/子节点 modulate），
##     跳过/退出/重演时恢复，绝不写 HP、isDead 或逻辑格
##
## 设计：从 scenes/battle.gd 抽出的 Node（create_tween 需要）。自有 states/tweens 两个字典；
## battle.gd 以别名变量 _result_visual_states 引用同一 Dictionary（契约测试内省面，
## 本模块只 clear() 绝不整体重赋值）。unit_sprites 由 battle.gd 在 setup() 注入。
##
## 公开 API（battle.gd 调用）：
##   setup(unit_sprites)
##   cheer(unit)                 # battle_ui.cheer_requested → battle.gd 委托
##   collapse(unit)              # battle_ui.collapse_requested → battle.gd 委托
##   play_death_fade(unit_id, us)  # battle.gd _on_unit_death 的视觉半段
##   restore()                   # battle.gd _restore_result_visuals 委托（_exit_tree/重演用）

class_name BattleResultStage
extends Node

var unit_sprites: Dictionary
## unit_id -> 演出前姿态快照（battle.gd 以 _result_visual_states 别名引用；只 clear 不重赋值）。
var states: Dictionary = {}
## unit_id -> 进行中的演出 Tween（新演出先 kill 旧的）。
var tweens: Dictionary = {}


func setup(p_unit_sprites: Dictionary) -> void:
	unit_sprites = p_unit_sprites


func _capture_visual(sprite: UnitSprite3D) -> void:
	var unit_id := StringName(sprite.unit.get(&"id", &""))
	if states.has(unit_id):
		return
	var visual: Node3D = sprite.portrait if sprite.portrait != null else sprite
	var children: Array[Dictionary] = []
	# 状态图标与回合数字位于独立子模块内，递归捕获以便跳过/重演恢复透明度。
	for child in sprite.find_children("*", "", true, false):
		if child is Sprite3D or child is Label3D:
			children.append({"node": child, "modulate": child.modulate})
	var state := {
		"sprite": sprite,
		"position": sprite.global_position,
		"scale": sprite.scale,
		"visible": sprite.visible,
		"visual": visual,
		"visual_rotation": visual.rotation,
		"children": children,
		"status_alpha": sprite._status_badges._alpha if sprite._status_badges != null else 1.0,
	}
	if visual is Sprite3D:
		state["visual_modulate"] = (visual as Sprite3D).modulate
	states[unit_id] = state


func _track_tween(unit_id: StringName, tween: Tween) -> void:
	var previous: Tween = tweens.get(unit_id)
	if previous != null and previous.is_valid():
		previous.kill()
	tweens[unit_id] = tween


func cheer(unit: Dictionary) -> void:
	var sprite: UnitSprite3D = unit_sprites.get(unit.get(&"id", &""))
	if sprite == null:
		return
	_capture_visual(sprite)
	var unit_id := StringName(unit[&"id"])
	var base: Vector3 = states[unit_id]["position"]
	sprite.global_position = base
	sprite.visible = true
	sprite.fade_alpha(1.0)
	var tween := create_tween()
	_track_tween(unit_id, tween)
	tween.tween_property(sprite, "global_position", base + Vector3.UP * 0.45, 0.12)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "global_position", base, 0.18)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func collapse(unit: Dictionary) -> void:
	var sprite: UnitSprite3D = unit_sprites.get(unit.get(&"id", &""))
	if sprite == null:
		return
	_capture_visual(sprite)
	var unit_id := StringName(unit[&"id"])
	var state: Dictionary = states[unit_id]
	var visual := state["visual"] as Node3D
	sprite.global_position = state["position"]
	sprite.visible = true
	sprite.fade_alpha(1.0)
	var tween := create_tween()
	_track_tween(unit_id, tween)
	tween.tween_property(visual, "rotation:z", -PI * 0.5, 0.26)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if visual is Sprite3D:
		tween.parallel().tween_property(visual, "modulate:a", 0.55, 0.26)


## 死亡淡出（battle.gd _on_unit_death 的视觉半段；grid.remove_unit 由 battle.gd 负责）。
func play_death_fade(unit_id: StringName, us: UnitSprite3D) -> void:
	var tw := create_tween()
	_track_tween(unit_id, tw)
	# 通过 UnitSprite3D.fade_alpha 统一淡出立绘与头顶状态图标、回合数字。
	tw.tween_method(us.fade_alpha, 1.0, 0.0, 0.4)
	tw.parallel().tween_property(us, "scale", us.scale * 1.5, 0.4)
	tw.tween_callback(func(): us.visible = false)


## 跳过/退出只结束显示时间轴；恢复姿态与透明度，绝不写 HP、isDead 或逻辑格。
func restore() -> void:
	for raw_tween in tweens.values():
		var tween := raw_tween as Tween
		if tween != null and tween.is_valid():
			tween.kill()
	tweens.clear()
	for raw_state in states.values():
		var state := raw_state as Dictionary
		var sprite := state.get("sprite") as UnitSprite3D
		if not is_instance_valid(sprite) or not sprite.is_inside_tree():
			continue
		sprite.global_position = state["position"]
		sprite.scale = state["scale"]
		sprite.visible = state["visible"]
		var visual := state.get("visual") as Node3D
		if is_instance_valid(visual):
			visual.rotation = state["visual_rotation"]
			if visual is Sprite3D and state.has("visual_modulate"):
				(visual as Sprite3D).modulate = state["visual_modulate"]
		if sprite._status_badges != null:
			sprite._status_badges.set_alpha(float(state.get("status_alpha", 1.0)))
		for entry_value in state["children"]:
			var entry := entry_value as Dictionary
			var child := entry.get("node") as Node
			if is_instance_valid(child):
				child.set("modulate", entry["modulate"])
	states.clear()
