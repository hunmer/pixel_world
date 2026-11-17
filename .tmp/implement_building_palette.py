from pathlib import Path
root = Path('E:/pixel_world')
def change(name, old, new):
 p=root/name
 s=p.read_text(encoding='utf-8')
 assert old in s, (name,old[:90])
 p.write_text(s.replace(old,new,1),encoding='utf-8')
change('scripts/scenes/map_editor.gd','var _building_rotation := 0','''var _building_rotation := 0
var _building_place_mode := false
var _building_grid: GridContainer
var _building_buttons: Dictionary = {}
var _builtin_building_id := ""''')
change('scripts/scenes/map_editor.gd','\t_asset_adapter = UserAssetVisualAdapterScript.new()','''\tvar builtins: Dictionary = preload("res://scripts/assets/builtin_building_assets.gd").ensure(_asset_service)
\t_builtin_building_id = String(builtins.get("asset_id", ""))
\tif not bool(builtins.get("ok", false)):
\t\tpush_warning("内置建筑加载失败：%s" % String(builtins.get("error", "未知错误")))
\t_asset_adapter = UserAssetVisualAdapterScript.new()''')
change('scripts/scenes/map_editor.gd','func _cancel_place_mode() -> void:\n\tMapEditorPresetsScript.cancel_place_mode(self)','''func _cancel_place_mode() -> void:
\tMapEditorPresetsScript.cancel_place_mode(self)
\tif _building_place_mode:
\t\t_clear_asset_selection()''')
change('scripts/editor/map_editor_assets.gd','const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")','''const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")
const BuildingPaletteScript = preload("res://scripts/editor/map_editor_buildings.gd")''')
change('scripts/editor/map_editor_assets.gd','\ted._selected_asset = descriptor','''\tif ed._building_place_mode:
\t\ted._building_place_mode = false
\t\ted._canvas.clear_paste_preview()
\ted._selected_asset = descriptor
\tBuildingPaletteScript.sync_selection(ed)''')
change('scripts/editor/map_editor_assets.gd','\ted._selected_asset = {}\n\tif String(ed._block_fg','''\tvar was_building_place: bool = ed._building_place_mode
\ted._building_place_mode = false
\ted._selected_asset = {}
\tif was_building_place and ed._canvas != null:
\t\ted._canvas.clear_paste_preview()
\tBuildingPaletteScript.sync_selection(ed)
\tif String(ed._block_fg''')
change('scripts/editor/map_editor_assets.gd','static func on_asset_library_changed(ed) -> void:\n\trebuild_block_asset_grid(ed)','''static func on_asset_library_changed(ed) -> void:
\trebuild_block_asset_grid(ed)
\tBuildingPaletteScript.rebuild(ed)''')
change('scripts/editor/map_editor_assets.gd','\t\ted._selected_asset = {}\n\t\tif ed._asset_panel != null:', '\t\tclear_asset_selection(ed)\n\t\tif ed._asset_panel != null:')
change('scripts/editor/map_editor_assets.gd','\trebuild_block_asset_grid(ed)\n\n\n## 选地形', '\trebuild_block_asset_grid(ed)\n\tBuildingPaletteScript.rebuild(ed)\n\n\n## 选地形')
# Append explicit placement controller; retain legacy asset tool behavior for the asset library.
p=root/'scripts/editor/map_editor_assets.gd'
s=p.read_text(encoding='utf-8')
s+='''

## 地形页建筑分组：选择即进入连续单击放置，与区域预设/粘贴/移动互斥。
static func on_building_selected(ed, asset_id: String) -> void:
\tif ed._building_place_mode and String(ed._selected_asset.get("id", "")) == asset_id:
\t\tclear_asset_selection(ed)
\t\ted._status("已退出建筑放置")
\t\treturn
\tvar descriptor: Variant = ed._asset_service.find_by_id(asset_id)
\tif not descriptor is Dictionary or String(descriptor.get("kind", "")) != "building":
\t\treturn
\ted._seal_pending()
\ted._cancel_place_mode()
\ted._cancel_paste()
\tif ed._move_tool_active:
\t\ted._set_move_tool(false)
\tclear_asset_selection(ed)
\tclear_block_asset_selection(ed)
\ted._selected_asset = descriptor.duplicate(true)
\ted._building_place_mode = true
\ted.current_prop = ""
\tif ed._terrain_group != null:
\t\tfor button: BaseButton in ed._terrain_group.get_buttons():
\t\t\tbutton.set_pressed_no_signal(false)
\tBuildingPaletteScript.sync_selection(ed)
\tupdate_asset_preview(ed)
\ted._status("建筑放置：移动鼠标实时预览，单击连续放置；T 换朝向，Esc 退出")


## 提交前在副本校验，失败不入历史；点击已有建筑不删除，拖动不提交。
static func commit_building_placement(ed, cell: Vector2i) -> void:
\tvar asset_id := String(ed._selected_asset.get("id", ""))
\tif asset_id.is_empty():
\t\treturn
\tvar snapshot: Dictionary = preload("res://scripts/editor/map_editor_model_ops.gd").building_assets_snapshot(ed, asset_id)
\tvar candidate: Dictionary = ed.model.duplicate(true)
\tvar result: Dictionary = BattlefieldDocScript.add_building(candidate, asset_id, cell, int(ed._building_rotation), snapshot)
\tif not bool(result.get("ok", false)):
\t\ted._status("放置失败：%s" % String(result.get("error", "建筑位置无效")), true)
\t\tMapEditorCellToolsScript.update_building_preview(ed, cell)
\t\treturn
\ted._push_undo("放置建筑")
\ted.model = candidate
\ted._refresh_canvas()
\ted._seal_pending()
\tMapEditorCellToolsScript.update_building_preview(ed, cell)
\ted._status("已放置建筑 → (%d,%d)，可继续放置；Esc 退出" % [cell.x, cell.y])
\tprint("[editor] 建筑连续放置 asset=%s cell=%s" % [asset_id, str(cell)])
'''
p.write_text(s,encoding='utf-8')
change('scripts/editor/map_editor_cell_tools.gd','\tif ed._place_mode:\n\t\ted._commit_place_preset(cell)', '''\tif ed.get("_building_place_mode") == true:
\t\tpreload("res://scripts/editor/map_editor_assets.gd").commit_building_placement(ed, cell)
\t\treturn
\tif ed._place_mode:
\t\ted._commit_place_preset(cell)''')
change('scripts/editor/map_editor_cell_tools.gd','static func on_cell_dragged(ed, cell: Vector2i) -> void:\n', '''static func on_cell_dragged(ed, cell: Vector2i) -> void:
\tif ed.get("_building_place_mode") == true or ed._place_mode or ed._paste_mode:
\t\treturn  # 连续放置仅单击提交；拖动只更新悬停预览。
''')
change('scripts/editor/map_editor_cell_tools.gd','\tvar d: Dictionary = ed._active_asset()\n\tvar asset_id := String(d.get("id", ""))\n\tvar is_building:', '''\tif ed._place_mode or ed._paste_mode or ed._move_tool_active:
\t\tclear_building_preview(ed)
\t\treturn
\tvar palette_mode: bool = ed.get("_building_place_mode") == true
\tif palette_mode and not ed._place_preview_enabled:
\t\tclear_building_preview(ed)
\t\ted._canvas.clear_paste_preview()
\t\treturn
\tvar d: Dictionary = ed._active_asset()
\tvar asset_id := String(d.get("id", ""))
\tvar is_building:''')
change('scripts/editor/map_editor_cell_tools.gd','\tif not is_building or not in_bounds:\n\t\tclear_building_preview(ed)\n\t\treturn','''\tif not is_building or not in_bounds:
\t\tclear_building_preview(ed)
\t\tif palette_mode:
\t\t\ted._canvas.clear_paste_preview()
\t\treturn''')
change('scripts/editor/map_editor_cell_tools.gd','\tif not err.is_empty():\n\t\tclear_building_preview(ed)\n\t\treturn\n\ted._canvas.set_building_preview', '''\tif palette_mode:
\t\tvar assets: Dictionary = ed.model.get("user_assets", {}).duplicate(true)
\t\tassets.merge(snapshot, true)
\t\tvar footprint: Vector2i = BattlefieldDocScript.BuildingLayoutScript.footprint_size(
\t\t\t{"asset_id": asset_id, "rotation": int(ed._building_rotation)}, assets)
\t\ted._canvas.set_paste_preview(cell, cell + footprint - Vector2i.ONE, err.is_empty())
\tif not err.is_empty():
\t\tclear_building_preview(ed)
\t\treturn
\ted._canvas.set_building_preview''')
change('scripts/editor/map_editor_shortcuts.gd','\t\t\tif ed._place_mode:', '\t\t\tif ed._place_mode or ed._building_place_mode:')
change('scripts/editor/map_editor_generate.gd','\tif ed._place_mode:\n\t\ted._cancel_place_mode()', '\tif ed._place_mode or (ed._building_place_mode and not ed._alt_pick_active):\n\t\ted._cancel_place_mode()')
change('scripts/editor/map_editor_presets.gd','\t\ted._cancel_paste()  # 与粘贴模式互斥','''\t\tif ed._building_place_mode:
\t\t\ted._clear_asset_selection()
\t\ted._cancel_paste()  # 与粘贴模式互斥''')
change('scripts/editor/map_editor_presets.gd','\ted._place_preview_enabled = on\n', '''\ted._place_preview_enabled = on
\tif ed._building_place_mode:
\t\ted._update_building_preview(ed._canvas.hover_cell)
\t\treturn
''')
