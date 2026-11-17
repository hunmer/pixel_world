## map_editor_building_palette_contract.gd — 建筑分组与连续实时放置契约（无截图）。
extends SceneTree

const AssetsScript = preload("res://scripts/editor/map_editor_assets.gd")
const CellToolsScript = preload("res://scripts/editor/map_editor_cell_tools.gd")
const PresetsScript = preload("res://scripts/editor/map_editor_presets.gd")
const ShortcutsScript = preload("res://scripts/editor/map_editor_shortcuts.gd")
const DocScript = preload("res://scripts/editor/battlefield_doc.gd")
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error("BUILDING_PALETTE_FAIL: " + message)

func _run() -> void:
	var packed := load("res://scenes/MapEditor.tscn") as PackedScene
	var ed = packed.instantiate()
	root.add_child(ed)
	await process_frame
	await process_frame
	ed.model = DocScript.create_empty(12, 10)
	ed._refresh_canvas()
	ed._init_history()
	for index in ed._tabs.get_tab_count():
		if ed._tabs.get_tab_title(index) == "地形":
			ed._tabs.current_tab = index
			break
	var asset_id := String(ed._builtin_building_id)
	_expect(not asset_id.is_empty() and ed._building_buttons.has(asset_id), "地形建筑分组自动提供四方向瞭望塔")
	var descriptor: Dictionary = ed._asset_service.find_by_id(asset_id)
	_expect(preload("res://scripts/assets/user_asset_catalog.gd").is_four_direction_building(descriptor), "内置建筑严格符合四帧契约")
	var button: Button = ed._building_buttons.get(asset_id)
	_expect(button != null and button.icon != null and button.text == String(descriptor.get("name", "")), "建筑按钮有单帧缩略图并保留素材名称")
	ed._canvas.hover_cell = Vector2i(1, 1)
	button.pressed.emit()
	_expect(ed._building_place_mode and button.button_pressed, "单击按钮进入建筑放置且同步选中态")
	_expect(DocScript.building_entries(ed.model).is_empty(), "预览不修改正式模型")
	_expect(not ed._canvas._building_preview.is_empty(), "真实建筑预览跟随鼠标")
	_expect(bool(ed._canvas._paste_region.get("valid", false)), "合法落点显示占地提示")
	var history_size: int = ed._history.size()
	ed._on_cell_pressed(Vector2i(1, 1))
	_expect(DocScript.building_entries(ed.model).size() == 1 and ed._building_place_mode, "单击放置一栋且保留连续模式")
	_expect(ed._history.size() == history_size + 1, "每次放置恰好一步历史")
	ed._on_cell_dragged(Vector2i(4, 1))
	_expect(DocScript.building_entries(ed.model).size() == 1, "拖动不刷建筑也不删除")
	ed._on_cell_pressed(Vector2i(1, 1))
	_expect(DocScript.building_entries(ed.model).size() == 1, "重复点已有建筑不删除")
	_expect(ed._history.size() == history_size + 1, "非法放置不进入历史")
	ed._canvas.hover_cell = Vector2i(4, 1)
	ed._on_hover_changed(Vector2i(4, 1))
	ed._rotate_building_intent()
	_expect(ed._building_rotation == 1 and int(ed._canvas._building_preview.get("rotation", -1)) == 1, "T旋转与预览一致")
	ed._on_cell_pressed(Vector2i(4, 1))
	_expect(DocScript.building_entries(ed.model).size() == 2, "另一个位置连续放置成功")
	ed._undo()
	_expect(DocScript.building_entries(ed.model).size() == 1, "撤销仅撤第二栋")
	ed._redo()
	_expect(DocScript.building_entries(ed.model).size() == 2, "重做恢复第二栋")
	ed._on_hover_changed(Vector2i(11, 9))
	_expect(ed._canvas._building_preview.is_empty() and not bool(ed._canvas._paste_region.get("valid", true)), "越界隐藏建筑并标红占地")
	PresetsScript.on_place_preview_toggled(ed, false)
	_expect(ed._canvas._paste_region.is_empty() and ed._canvas._building_preview.is_empty(), "预设实时预览开关同样控制建筑")
	ed._canvas.hover_cell = Vector2i(7, 1)
	PresetsScript.on_place_preview_toggled(ed, true)
	_expect(not ed._canvas._building_preview.is_empty(), "开启实时预览立即恢复")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	ShortcutsScript.unhandled_input(ed, escape)
	_expect(ed.is_inside_tree() and not ed._building_place_mode and ed._selected_asset.is_empty(), "Esc只退出建筑放置不离开编辑器")
	_expect(ed._canvas._building_preview.is_empty() and ed._canvas._paste_region.is_empty(), "退出清除全部建筑预览")
	AssetsScript.on_building_selected(ed, asset_id)
	AssetsScript.on_building_selected(ed, asset_id)
	_expect(not ed._building_place_mode, "再次点分组按钮取消放置")
	AssetsScript.on_building_selected(ed, asset_id)
	ed.current_tool = ed.Tool.HEIGHT_UP
	ed._on_tool_changed()
	_expect(not ed._building_place_mode and ed._selected_asset.is_empty(), "切工具退出建筑放置")
	AssetsScript.on_building_selected(ed, asset_id)
	ed.apply_generate("building_palette_contract", 12, 10)
	_expect(not ed._building_place_mode and ed._canvas._building_preview.is_empty(), "生成新地图退出并清预览")
	ed.queue_free()
	await process_frame
	await process_frame
	if not failed:
		print("MAP_EDITOR_BUILDING_PALETTE_OK")
	quit(1 if failed else 0)
