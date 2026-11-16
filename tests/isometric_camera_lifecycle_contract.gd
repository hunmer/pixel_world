## isometric_camera_lifecycle_contract.gd — 相机退树、延迟 resize 与重新入树回归。
extends SceneTree

const IsoCamera = preload("res://scripts/iso/isometric_camera_3d.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var camera: Camera3D = IsoCamera.new()
	camera.name = "LifecycleCamera"
	# 未入树的延迟回调同样必须安全。
	camera._on_viewport_size_changed()
	for cycle: int in range(3):
		root.add_child(camera)
		_expect(root.size_changed.is_connected(camera._on_viewport_size_changed),
			"入树必须订阅视口 resize（含重新入树）")
		camera.set_viewport_size(Vector2(640.0, 480.0))
		root.size_changed.emit()
		_expect(camera.get("_viewport_size") == root.get_visible_rect().size,
			"在树相机必须响应 resize")
		var bridge: Node = root.get_node("BreakpointRuntimeBridge")
		var result: Dictionary = bridge.call("_dispatch", "runtime.assert_node_state", {
			"path": str(camera.get_path()), "expect": {"projection": Camera3D.PROJECTION_ORTHOGONAL}
		})
		_expect(bool(result.get("ok", false)) and bool(result.get("result", {}).get("ok", false)),
			"runtime_assert_node_state 验证相机正交投影")
		root.remove_child(camera)
		_expect(not root.size_changed.is_connected(camera._on_viewport_size_changed),
			"退树必须立即断开 resize，不能等对象释放")
		camera.set_viewport_size(Vector2(320.0, 240.0))
		root.size_changed.emit()
		camera._on_viewport_size_changed()
		_expect(camera.get("_viewport_size") == Vector2(320.0, 240.0),
			"退树后信号和延迟回调不得更新投影或访问视口")
	camera.free()
	if failures.is_empty():
		print("ISOMETRIC_CAMERA_LIFECYCLE_CONTRACT_OK cycles=3")
	quit(0 if failures.is_empty() else 1)
