## world_key_input_contract.gd — 未绑定按键、逻辑键回退和物理键优先级回归。
extends SceneTree

var failures: Array[String] = []
var routed: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _physical(_event: InputEventKey) -> void:
	routed.append("physical")


func _logical(_event: InputEventKey) -> void:
	routed.append("logical")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var world: Node = load("res://main.gd").new()
	var event := InputEventKey.new()
	event.pressed = true
	# 使用真实路由表覆盖两条缺失键路径，不启动世界生成。
	event.physical_keycode = KEY_A
	event.keycode = KEY_A
	world._handle_key_input(event)
	event.keycode = KEY_D
	world._handle_key_input(event)
	_expect(routed.is_empty(), "未绑定按键应安全忽略")

	world.set("_key_handlers", {KEY_E: Callable(self, "_physical")})
	world.set("_entry_key_handlers", {KEY_F: Callable(self, "_logical")})
	event.physical_keycode = KEY_E
	event.keycode = KEY_F
	world._handle_key_input(event)
	_expect(routed == ["physical"], "已绑定物理键优先且只触发一次")
	event.physical_keycode = KEY_NONE
	world._handle_key_input(event)
	_expect(routed == ["physical", "logical"], "物理键未绑定时保留逻辑键回退")
	event.keycode = KEY_D
	world._handle_key_input(event)
	_expect(routed.size() == 2, "两张表均未命中时不调用处理器")
	world.free()
	if failures.is_empty():
		print("WORLD_KEY_INPUT_CONTRACT_OK checks=4")
	quit(0 if failures.is_empty() else 1)
