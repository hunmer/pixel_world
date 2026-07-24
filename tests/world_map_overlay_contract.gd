extends SceneTree

const MainScript = preload("res://main.gd")
const MapSnapshotRendererScript = preload(
	"res://scripts/world/map_snapshot_renderer.gd"
)
const WorldMapOverlayScript = preload("res://scripts/world_map_overlay.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var host := Node.new()
	root.add_child(host)
	var overlay = WorldMapOverlayScript.new()
	host.add_child(overlay)
	await process_frame

	_expect(not overlay.is_open(), "世界地图默认不应打开")
	_expect(overlay.layer > 100, "世界地图没有覆盖 HUD 和右上小地图")
	var map_root := overlay.get_node("WorldMapRoot") as Control
	var map_texture := overlay.get_node(
		"WorldMapRoot/Center/MapPanel/Content/MapFrame/MapTexture"
	) as TextureRect
	var player_marker := overlay.get_node(
		"WorldMapRoot/Center/MapPanel/Content/MapFrame/MapTexture/PlayerMarker"
	) as PanelContainer
	_expect(map_root.mouse_filter == Control.MOUSE_FILTER_STOP, "地图没有阻止背景鼠标输入")
	_expect(map_texture.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "地图颜色被平滑采样")

	var explored := {}
	for y in range(-4, 5):
		for x in range(-6, 7):
			explored[Vector2i(x, y)] = (
				Color(0.10, 0.32, 0.56)
				if y < 0
				else Color(0.32, 0.58, 0.20)
			)
	overlay.open_map(explored, Vector2i(2, 1))
	_expect(overlay.is_open(), "open_map 没有显示地图")
	_expect(map_root.visible, "地图根控件仍然隐藏")
	_expect(overlay.get_rendered_cell_count() == explored.size(), "地图遗漏已探索格")
	var image: Image = overlay.get_map_image()
	_expect(image != null, "地图没有生成 Image")
	if image != null:
		_expect(
			image.get_width() <= MapSnapshotRendererScript.DEFAULT_MAX_EDGE
			and image.get_height() <= MapSnapshotRendererScript.DEFAULT_MAX_EDGE,
			"地图位图突破尺寸上限"
		)
		_expect(
			player_marker.size == WorldMapOverlayScript.PLAYER_MARKER_SIZE,
			"玩家标记没有保持固定屏幕尺寸"
		)
	_expect(_count_type(map_root, "Sprite2D") == 0, "地图为探索格创建了 Sprite2D")
	_expect(_count_type(map_root, "TextureRect") == 1, "地图没有保持单 TextureRect 渲染")

	var huge_map := {
		Vector2i(-2000, -1000): Color.BLUE,
		Vector2i(2000, 1000): Color.GREEN,
	}
	overlay.open_map(huge_map, Vector2i.ZERO)
	image = overlay.get_map_image()
	_expect(
		image.get_width() <= MapSnapshotRendererScript.DEFAULT_MAX_EDGE
		and image.get_height() <= MapSnapshotRendererScript.DEFAULT_MAX_EDGE,
		"超大探索范围没有下采样"
	)

	var world = MainScript.new()
	world.set("_world_map", overlay)
	var map_key := InputEventKey.new()
	map_key.physical_keycode = KEY_M
	map_key.pressed = true
	overlay.close_map()
	_expect(world.call("_handle_world_map_input", map_key), "M 键没有被地图输入处理")
	_expect(overlay.is_open(), "M 键没有打开地图")
	_expect(world.call("_handle_world_map_input", map_key), "第二次 M 键没有被处理")
	_expect(not overlay.is_open(), "第二次 M 键没有关闭地图")
	overlay.open_map(explored, Vector2i(2, 1))
	var escape_key := InputEventKey.new()
	escape_key.keycode = KEY_ESCAPE
	escape_key.pressed = true
	_expect(world.call("_handle_world_map_input", escape_key), "ESC 没有被地图输入处理")
	_expect(not overlay.is_open(), "ESC 没有关闭地图")
	overlay.open_map(explored, Vector2i(2, 1))
	Input.action_press("ui_right")
	_expect(world.call("_input_dir") == Vector2i.ZERO, "地图打开时仍接受玩家移动")
	overlay.close_map()
	_expect(not overlay.is_open(), "close_map 没有关闭地图")
	_expect(world.call("_input_dir") == Vector2i.RIGHT, "关闭地图后玩家移动没有恢复")
	Input.action_release("ui_right")

	world.free()
	host.free()
	await _test_live_movement_lock()
	if failures.is_empty():
		print("WORLD_MAP_OVERLAY_CONTRACT_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _test_live_movement_lock() -> void:
	var live_world = load("res://main.tscn").instantiate()
	live_world.seed = 42
	root.add_child(live_world)
	await process_frame
	var start_cell: Vector2i = live_world.get("_player_cell")
	var terrain_cache_before: Dictionary = live_world.get("_terrain_sampler").cache_sizes()
	var open_started_ms := Time.get_ticks_msec()
	live_world.call("_toggle_world_map")
	var open_elapsed_ms := Time.get_ticks_msec() - open_started_ms
	print("WORLD_MAP_OPEN_MS ", open_elapsed_ms)
	_expect(
		live_world.get("_terrain_sampler").cache_sizes() == terrain_cache_before,
		"打开大地图提前采样了未探索地形"
	)
	_expect(live_world.call("is_world_map_open"), "真实场景没有打开地图")
	var expected_span: int = (
		int(live_world.sight_radius) * 2 * int(live_world.WORLD_MAP_RANGE_MULTIPLIER) + 1
	)
	_expect(
		live_world.get("_world_map").get_render_bounds().size
		== Vector2i.ONE * expected_span,
		"大地图覆盖范围没有按线性 8 倍扩展"
	)
	_expect(
		live_world.get("_world_map").get_rendered_cell_count()
		== live_world.get("_explored").size(),
		"大地图绘制了未探索地形"
	)
	var live_map_image: Image = live_world.get("_world_map").get_map_image()
	_expect(
		live_map_image.get_pixel(0, 0).is_equal_approx(
			MapSnapshotRendererScript.UNKNOWN_COLOR
		),
		"大地图未探索区域不是黑色"
	)
	_expect(not paused, "地图错误暂停了整个 SceneTree")
	Input.action_press("ui_right")
	await process_frame
	await process_frame
	Input.action_release("ui_right")
	_expect(
		live_world.get("_player_cell") == start_cell,
		"真实场景在地图打开期间发生了玩家位移"
	)
	live_world.call("_toggle_world_map")
	Input.action_press("ui_right")
	await process_frame
	Input.action_release("ui_right")
	_expect(
		live_world.get("_player_cell") == start_cell + Vector2i.RIGHT,
		"真实场景关闭地图后没有恢复移动"
	)
	live_world.queue_free()
	await process_frame
	await process_frame


func _count_type(node: Node, type_name: String) -> int:
	var count := 1 if node.is_class(type_name) else 0
	for child in node.get_children():
		count += _count_type(child, type_name)
	return count
