## battle_key_input_contract.gd — 战斗按键路由的缺失键、有效键与松键回归。
extends SceneTree

var failures: Array[String] = []
var routed_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _on_routed() -> void:
	routed_count += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var battle_script: GDScript = load("res://scripts/scenes/battle.gd") as GDScript
	if battle_script == null or not battle_script.can_instantiate():
		push_error("战斗脚本无法实例化，终止按键契约")
		quit(1)
		return
	var battle: Node = battle_script.new()
	var event: InputEventKey = InputEventKey.new()
	event.pressed = true
	# 使用真实路由表验证缺失键，不启动战斗场景及演出。
	var route: Dictionary = battle._key_route()
	var missing_handler: Callable = route.get(KEY_A, Callable())
	_expect(not missing_handler.is_valid(), "未绑定键应返回空 Callable")
	battle._handle_key_input(event)
	event.keycode = KEY_A
	battle._handle_key_input(event)
	_expect(routed_count == 0, "空键码与未绑定键应安全忽略")
	battle.set("_key_handlers", {KEY_Z: Callable(self, "_on_routed")})
	event.keycode = KEY_Z
	battle._handle_key_input(event)
	_expect(routed_count == 1, "已绑定键按下应调用一次处理器")
	event.pressed = false
	battle._handle_key_input(event)
	_expect(routed_count == 1, "松键不应调用处理器")
	event.pressed = true
	event.keycode = KEY_A
	battle._handle_key_input(event)
	_expect(routed_count == 1, "路由表已缓存时未绑定键仍应安全忽略")
	battle.free()
	if failures.is_empty():
		print("BATTLE_KEY_INPUT_CONTRACT_OK checks=5")
	quit(0 if failures.is_empty() else 1)
