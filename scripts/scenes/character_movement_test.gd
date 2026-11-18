## character_movement_test.gd — 继承真实生态世界的独立人物网格移动与逐行动作测试
extends "res://main.gd"

const Sheet = preload("res://scripts/characters/free_character_sheet.gd")
const Animator = preload("res://scripts/characters/free_character_animator.gd")
const Terrain3DScript = preload("res://scripts/scenes/character_movement_terrain_3d.gd")
const PixelMarginScript = preload("res://ui/components/pixel_margin.gd")
const PixelVBoxScript = preload("res://ui/components/pixel_v_box.gd")
const PixelPanelScene = preload("res://ui/components/pixel_panel.tscn")

const ACTION_LEFT := &"character_test_left"
const ACTION_RIGHT := &"character_test_right"
const ACTION_UP := &"character_test_up"
const ACTION_DOWN := &"character_test_down"
const TEST_ACTIONS: Array[StringName] = [ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN]
const ACTION_KEYS := {
	ACTION_LEFT: [KEY_A, KEY_LEFT],
	ACTION_RIGHT: [KEY_D, KEY_RIGHT],
	ACTION_UP: [KEY_W, KEY_UP],
	ACTION_DOWN: [KEY_S, KEY_DOWN],
}
const INPUT_DEADZONE := 0.2
const DIGITAL_MOVE_THRESHOLD := 0.5

@export var initial_character: StringName = &"002"

var _animator := Animator.new()
var _preview_order: Array[StringName] = Sheet.preview_ids()
var _preview_index: int = 0
var _character_index: int = 0
var _preferred_axis: int = 1
var _window_focus_lost: bool = false
var _registered_actions: Array[StringName] = []
var _registered_events: Dictionary = {}
var _test_key_handlers: Dictionary = {}
var _test_entry_key_handlers: Dictionary = {}
var _status_label: Label
var _selection_label: Label
var _blocked_entry_attempts: int = 0
var _continue_run_pose: bool = false
var _has_stream_center: bool = false
var _last_stream_center: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_register_test_actions()
	_character_index = maxi(0, Sheet.character_ids().find(initial_character))
	_animator.set_character(initial_character)
	_animator.preview_finished.connect(_update_status)
	super._ready()
	var test_terrain := _terrain as Terrain3DScript
	if test_terrain != null:
		test_terrain.set_incremental_flush(true)
	_setup_test_ui()
	_refresh_player_visual()
	_update_status()


func _exit_tree() -> void:
	_release_test_actions()
	for action_name: StringName in _registered_events:
		for event: InputEvent in _registered_events[action_name]:
			InputMap.action_erase_event(action_name, event)
	for action_name: StringName in _registered_actions:
		InputMap.erase_action(action_name)
	_registered_events.clear()
	_registered_actions.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_window_focus_lost = true
		_release_test_actions()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_window_focus_lost = false
	elif what == NOTIFICATION_PAUSED:
		_release_test_actions()


func _register_test_actions() -> void:
	for action_name: StringName in TEST_ACTIONS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name, INPUT_DEADZONE)
			_registered_actions.append(action_name)
		var added_events: Array[InputEvent] = []
		for keycode: int in ACTION_KEYS[action_name]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			event.keycode = keycode
			if not InputMap.action_has_event(action_name, event):
				InputMap.action_add_event(action_name, event)
				added_events.append(event)
		if not added_events.is_empty():
			_registered_events[action_name] = added_events


func _release_test_actions() -> void:
	for action_name: StringName in _registered_events:
		Input.action_release(action_name)
	if _world_camera_navigation != null:
		_world_camera_navigation.cancel_drag()


func _setup_terrain() -> void:
	_terrain = Terrain3DScript.new()
	_terrain.name = "IsometricTerrain3D"
	add_child(_terrain)


func _regenerate(new_seed: int) -> void:
	_has_stream_center = false
	var test_terrain := _terrain as Terrain3DScript
	if test_terrain != null:
		test_terrain.set_incremental_flush(false)
	super._regenerate(new_seed)
	if test_terrain != null:
		test_terrain.set_incremental_flush(true)


## 单格行走只替换流式窗口的一条边；完整 65×65 扫描仍用于初次生成与跳转。
## 这与父流程生成同一 CellState/生态内容，只避免每格重复检查数千个未变化格。
func _update_streaming() -> void:
	var delta := _stream_center - _last_stream_center
	if not _has_stream_center or absi(delta.x) + absi(delta.y) != 1:
		super._update_streaming()
		_last_stream_center = _stream_center
		_has_stream_center = true
		return
	_world_query.clear_caches()
	_flora.clear_caches()
	if delta.x != 0:
		var leaving_x := _last_stream_center.x - delta.x * stream_extent
		for y in range(_last_stream_center.y - stream_extent, _last_stream_center.y + stream_extent + 1):
			var leaving := Vector2i(leaving_x, y)
			if _cells.has(leaving):
				_free_cell(leaving)
		var entering_x := _stream_center.x + delta.x * stream_extent
		for y in range(_stream_center.y - stream_extent, _stream_center.y + stream_extent + 1):
			var entering := Vector2i(entering_x, y)
			if not _cells.has(entering):
				_spawn_cell(entering)
	else:
		var leaving_y := _last_stream_center.y - delta.y * stream_extent
		for x in range(_last_stream_center.x - stream_extent, _last_stream_center.x + stream_extent + 1):
			var leaving := Vector2i(x, leaving_y)
			if _cells.has(leaving):
				_free_cell(leaving)
		var entering_y := _stream_center.y + delta.y * stream_extent
		for x in range(_stream_center.x - stream_extent, _stream_center.x + stream_extent + 1):
			var entering := Vector2i(x, entering_y)
			if not _cells.has(entering):
				_spawn_cell(entering)
	_terrain.flush()
	_spawn_fauna_for_stream()
	_cleanup_streamed_animals()
	_ambient_registry.refresh_all()
	_ensure_sort_origin(_player_cell)
	_last_stream_center = _stream_center


func _setup_player() -> void:
	super._setup_player()
	_apply_animator()


func _set_player_render_position(visual_position: Vector2, sort_y: float) -> void:
	super._set_player_render_position(visual_position, sort_y)
	if _player != null:
		_player.offset = Sheet.foot_offset()
		_player.pixel_size = Sheet.pixel_size()


func _set_player_pose(pose: StringName) -> void:
	# 父流程在每一格结束先报 idle、下一帧才读取持续输入；按住方向时跳过这个
	# 单帧 idle，保留 run 的相位。真正松键或撞墙仍走父 idle 语义。
	if pose == &"idle" and _continue_run_pose:
		return
	super._set_player_pose(pose)


func _try_move(direction: Vector2i) -> void:
	var previous_cell := _player_cell
	super._try_move(direction)
	if _player_cell == previous_cell and _continue_run_pose:
		_continue_run_pose = false
		super._set_player_pose(&"idle")


func _refresh_player_visual() -> void:
	if _player == null:
		return
	if _cam != null and not _animator.is_preview_active():
		var screen_delta := Sheet.facing_screen_delta(
			_cam, _player.global_position, _player_facing
		)
		_animator.set_locomotion(_move_t < 1.0, screen_delta)
	_apply_animator()


func _apply_animator() -> void:
	if _player == null:
		return
	# 完整图集 + Sprite3D 原生区域只保留一层帧坐标映射，避免区域纹理与帧状态叠加。
	_player.texture = Sheet.sheet_texture(_animator.character_id)
	_player.hframes = 1
	_player.vframes = 1
	_player.frame = 0
	_player.region_rect = Sheet.frame_region(_animator.current_row(), _animator.frame_index)
	_player.region_enabled = true
	_player.flip_h = _animator.current_flip_h()
	_player.pixel_size = Sheet.pixel_size()
	_player.offset = Sheet.foot_offset()


func _process(delta: float) -> void:
	_continue_run_pose = _input_dir() != Vector2i.ZERO
	var previous_mode := _animator.mode
	super._process(delta)
	if _player == null:
		return
	if _animator.advance(delta):
		_apply_animator()
	if previous_mode != _animator.mode:
		_update_status()


## 数字输入也经 Input.get_vector 统一归一；双轴同时按下时由最后按键轴决定单格方向。
func _input_dir() -> Vector2i:
	if not _movement_input_allowed():
		return Vector2i.ZERO
	var value := Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN, INPUT_DEADZONE)
	return resolve_grid_direction(value, _preferred_axis)


static func resolve_grid_direction(value: Vector2, preferred_axis: int = 1) -> Vector2i:
	if value.length() < DIGITAL_MOVE_THRESHOLD:
		return Vector2i.ZERO
	var x := signi(int(signf(value.x)))
	var y := signi(int(signf(value.y)))
	if x != 0 and y != 0:
		if preferred_axis == 0:
			y = 0
		else:
			x = 0
	return Vector2i(x, y)


func _movement_input_allowed() -> bool:
	return not _animator.is_preview_active() and _test_action_allowed()


func _test_action_allowed() -> bool:
	if _window_focus_lost:
		return false
	var tree := get_tree()
	if tree != null and tree.paused:
		return false
	if is_world_map_open():
		return false
	var viewport := get_viewport()
	if viewport == null:
		return true
	return viewport.gui_get_focus_owner() == null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		for action_name: StringName in TEST_ACTIONS:
			if event.is_action_pressed(action_name):
				_preferred_axis = 0 if action_name == ACTION_LEFT or action_name == ACTION_RIGHT else 1
				break
	super._unhandled_input(event)


func _key_route() -> Dictionary:
	if _test_key_handlers.is_empty():
		_test_key_handlers = super._key_route().duplicate()
		for keycode: int in [KEY_LEFT, KEY_RIGHT, KEY_P, KEY_O, KEY_E]:
			_test_key_handlers.erase(keycode)
		_test_key_handlers[KEY_J] = Callable(self, "_key_play_preview")
		_test_key_handlers[KEY_H] = Callable(self, "_key_reset_preview")
		_test_key_handlers[KEY_K] = Callable(self, "_key_previous_character")
		_test_key_handlers[KEY_L] = Callable(self, "_key_next_character")
		_test_key_handlers[KEY_U] = Callable(self, "_key_previous_preview")
		_test_key_handlers[KEY_I] = Callable(self, "_key_next_preview")
	return _test_key_handlers


func _entry_key_route() -> Dictionary:
	if _test_entry_key_handlers.is_empty():
		_test_entry_key_handlers = super._entry_key_route().duplicate()
		for keycode: int in [KEY_P, KEY_O, KEY_E]:
			_test_entry_key_handlers.erase(keycode)
		_test_entry_key_handlers[KEY_J] = Callable(self, "_key_play_preview")
		_test_entry_key_handlers[KEY_H] = Callable(self, "_key_reset_preview")
		_test_entry_key_handlers[KEY_K] = Callable(self, "_key_previous_character")
		_test_entry_key_handlers[KEY_L] = Callable(self, "_key_next_character")
		_test_entry_key_handlers[KEY_U] = Callable(self, "_key_previous_preview")
		_test_entry_key_handlers[KEY_I] = Callable(self, "_key_next_preview")
	return _test_entry_key_handlers




func _key_play_preview(_event: InputEvent) -> void:
	trigger_selected_preview()


func _key_reset_preview(_event: InputEvent) -> void:
	if _test_action_allowed():
		_animator.cancel_preview()
		_refresh_player_visual()
		_update_status()


func _key_previous_character(_event: InputEvent) -> void:
	cycle_character(-1)


func _key_next_character(_event: InputEvent) -> void:
	cycle_character(1)


func _key_previous_preview(_event: InputEvent) -> void:
	cycle_preview(-1)


func _key_next_preview(_event: InputEvent) -> void:
	cycle_preview(1)


func selected_preview() -> StringName:
	if _preview_order.is_empty():
		return &""
	return _preview_order[_preview_index]


func cycle_character(step: int) -> bool:
	if not _test_action_allowed():
		return false
	var ids := Sheet.character_ids()
	if ids.is_empty():
		return false
	_character_index = posmod(_character_index + step, ids.size())
	if not _animator.set_character(ids[_character_index]):
		return false
	_refresh_player_visual()
	_update_status()
	return true


func cycle_preview(step: int) -> bool:
	if not _test_action_allowed() or _preview_order.is_empty():
		return false
	_preview_index = posmod(_preview_index + step, _preview_order.size())
	_update_status()
	return true


func trigger_selected_preview() -> bool:
	if not _test_action_allowed() or _move_t < 1.0:
		return false
	if _input_dir() != Vector2i.ZERO:
		return false
	if not _animator.start_preview(selected_preview()):
		return false
	_refresh_player_visual()
	_update_status()
	return true


func _update_status() -> void:
	if _status_label == null or _selection_label == null:
		return
	var mode_text := "待机"
	if _animator.mode == &"run":
		mode_text = "移动"
	elif _animator.is_preview_active():
		mode_text = "播放中"
	_status_label.text = "角色 %s · %s · %s" % [
		_animator.character_id,
		_animator.direction,
		mode_text,
	]
	_selection_label.text = "动作选择 %s（仅图集预览，无战斗结算）" % selected_preview()


func _setup_test_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CharacterTestUI"
	layer.layer = 5
	add_child(layer)
	var root := Control.new()
	root.name = "Overlay"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var margin := PixelMarginScript.new()
	margin.name = "SafeMargin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(margin)
	var stack: VBoxContainer = PixelVBoxScript.new()
	stack.name = "TestStack"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(stack)
	var panel := PixelPanelScene.instantiate()
	panel.title = "人物移动测试"
	panel.description = "独立场景 · 原有生态与阻挡规则"
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(panel)
	var content := panel.get_content_slot() as VBoxContainer
	content.add_child(_make_label(
		"WASD / 方向键：单格移动　Q / X：旋转视角　Space：抓取平移\n"
		+ "K / L：切换角色　U / I：选择动作　J：播放　H：停止动作\n"
		+ "M：世界地图　P / O / E：战斗与编辑器入口已隔离"
	))
	_status_label = _make_label("")
	_selection_label = _make_label("")
	content.add_child(_status_label)
	content.add_child(_selection_label)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", UITheme.TEXT_MAIN)
	label.add_theme_font_size_override("font_size", ComponentTheme.FONT_CAPTION)
	return label


## 测试场景不提供战斗、JSON 战场或编辑器入口，HUD 与直接函数调用也同样隔离。
func _enter_battle() -> void:
	_blocked_entry_attempts += 1


func _enter_battlefield(_path: String) -> void:
	_blocked_entry_attempts += 1


func _on_battlefield_picked(path: String) -> void:
	_enter_battlefield(path)


func _open_map_editor() -> void:
	_blocked_entry_attempts += 1


func _key_enter_battle(_event: InputEventKey) -> void:
	pass


func _key_battlefield_panel(_event: InputEventKey) -> void:
	pass


func _key_editor_or_rotate(_event: InputEventKey) -> void:
	pass
