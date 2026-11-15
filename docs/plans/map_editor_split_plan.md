# map_editor.gd 结构化拆分方案（P3-13 编辑器部分）

> 任务：task_mwhsl7fi1c3inom ｜ 成员：editor-split ｜ 日期：2026-11-15
> 目标：`scripts/scenes/map_editor.gd`（3285 行 / 150 函数）按函数簇抽取到 `scripts/editor/` 模块，**行为 100% 不变**。本文件是执行批次（后续任务）的唯一依据。

## 0. 硬约束回顾（来自任务简报）

1. 纯结构性重构：只移动代码，不改逻辑/数值/快捷键行为/保存校验语义。
2. 3 处直建控件 `Button.new()` / `CheckButton.new()` / `OptionButton.new()` 不修（P0-3 另行处理）；`ui_contract` / `map_editor_ui_contract` 移动后仍红，失败主题须与改前一致（行号/文件名变化算正常）。
3. 优先归拢 `scripts/editor/` 既有模块；风格：tab 缩进、snake_case.gd、顶部 `## file.gd — 职责`。
4. 不碰 main.gd / ui/ 组件库本体 / DESIGN.md / tests/ 断言；不执行 git commit/branch/reset。
5. 契约按批跑，不跑全量；4 个历史挂起契约（action_anim / immersive_battle_camera / world_map_overlay / user_asset_source_live）不跑。

## 1. 改前基线（2026-11-15 实测，本机 /Applications/Godot = 4.7.1.stable）

> 完整日志：`/tmp/editor_split_baseline/*_before.log`（每批执行后与之对照）。
> ⚠️ headless 契约在本 DSH 沙箱内会段错误（空项目也崩，`--version` 正常）；须以全权限运行（本会话已获 danger-full-access）。

| 契约 | 改前退出码 | 结论 |
| --- | --- | --- |
| editor_selection / editor_block_picker / editor_region_clipboard / editor_region_preset_store / map_editor_region_ops / hint_bar / ui_components | 0 | 绿，必须保持 |
| map_editor_ui | 1 | 红（对照），6 条失败主题见下 |
| ui | 1 | 红（对照），3 条失败主题见下 |

map_editor_ui 失败主题（6 条，改后必须逐条仍在）：
1. `ERROR: (1024, 640)：侧栏保持 320px`
2. `ERROR: (1280, 800)：侧栏保持 320px`
3. `ERROR: 改 z 后实际重建的单块 level=6`
4. `ERROR: 10 选择模式菜单存在且默认隐藏`
5. `ERROR: 10 素材区域填充恰好一步历史`
6. `ERROR: 10 体积填充恰好一步历史`

ui 失败主题（3 条）：
1. `ERROR: res://scripts/scenes/map_editor.gd 不应再包含 Button.new(`
2. `ERROR: res://scripts/scenes/map_editor.gd 不应再包含 CheckButton.new(`
3. `ERROR: res://scripts/scenes/map_editor.gd 不应再包含 OptionButton.new(`

## 2. 架构决策（两条红线）

### 2.1 契约钉死成员名 → 门面（facade）模式

实测三个绿契约**直接实例化 MapEditor 场景并按名访问私有成员**：

- `map_editor_region_ops`：`Tool/_active_tool/_alt_key_down/_alt_pick_active/_alt_pick_return_tool/_apply_region_click/_asset_adapter/_block_bg/_block_fg/_cancel_paste/_canvas/_clipboard/_history/_history_cursor/_on_cell_dragged/_on_cell_pressed/_on_cell_released/_on_delete_preset_pressed/_on_fill_preset_pressed/_on_hover_changed/_on_recent_pick_pressed/_on_region_clear_pressed/_on_region_copy_pressed/_on_region_cut_pressed/_on_region_paste_pressed/_on_save_preset_pressed/_on_selection_mode_item/_on_tool_changed/_paste_mode/_place_mode/_place_preset_btn/_place_preview_enabled/_place_preview_toggle/_preset_list/_preset_name_edit/_preset_store/_push_undo/_recent_picks/_recent_picks_info/_refresh_preset_list/_refresh_recent_picks/_region_pos2_set/_replace_dest_code/_replace_items/_replace_picker_dialog/_replace_source_code/_seal_pending/_select_replace_option/_selection_range/_set_block_slot/_set_glyph/_status_label/_tool_buttons/_undo/_unhandled_input/apply_generate/current_tool/model/region_clipboard_info`
- `hint_bar`：`HINT_ITEMS/_unhandled_input`（+ 树上找 EditorHintBar / ShortcutHintsDialog 键帽结构）
- `user_asset_editor`：`Tool/_active_tool/_apply_tool/_asset_adapter/_asset_panel/_asset_service/_block_asset_buttons/_canvas/_clear_asset_selection/_id_edit/_on_asset_selected/_on_block_asset_btn_pressed/_rebuild_block_asset_grid/_redo/_selected_asset/_selected_block_asset/_terrain_buttons/_tool_buttons/_undo/current_terrain/current_tool/fill_cell/model/place_unit/save_current`

⇒ **所有被钉死的函数名/变量名必须留在 map_editor.gd**。做法：函数体中的纯逻辑抽到模块静态函数，原函数名保留为 1–3 行薄门面（或整体不动）；未被钉死的小函数可整段删除改为直调模块。`Tool` 枚举、`HINT_ITEMS`、`CLASS_IDS`、`SIDEBAR_WIDTH`、`TAB_BLOCK`、`UNDO_LIMIT` 与全部颜色别名**留在 map_editor.gd**（契约按实例访问 `ed.Tool`/`ed.HINT_ITEMS`）。

### 2.2 3 处直建控件：留在 map_editor.gd（关键决策，需 Lead 确认）

`ui_contract.gd:180` 对 **固定路径** `res://scripts/scenes/map_editor.gd` 做源码扫描（`_check_source` 列表是写死的文件清单，`scripts/editor/` 下只有 `asset_library_panel.gd` 在列，见 tests/ui_contract.gd:180-228）。

- 若把 3 处 `.new()` 随簇移入新模块：map_editor.gd 扫描通过、新模块不在扫描清单 → `ui_contract` 由红转绿且 3 条失败主题消失，**违反简报「移动后仍会红、失败主题一致」**。
- 因此方案：`Button.new()`（_build_hint_bar 内）→ **_build_hint_bar 整函数原地保留**；`CheckButton.new()`/`OptionButton.new()` → **`CheckButton.new()`/`OptionButton.new()` 这一行留在 map_editor.gd 的薄门面里**（先构造、再把控件作为参数传给模块构建器，模块在原逻辑位置完成命名/接线/加树）。仅裸构造时机提前，属性设置与加树顺序不变，节点树与行为逐字节等价，3 条失败主题逐字不变。
- 备选（若 Lead 要求 3 处必须物理移动）：需同时把新模块路径加进 tests/ui_contract.gd 的 `_check_source` 清单 —— 这触碰「不改 tests/」边界，**须 Lead 拍板后才做**；默认不采用。

### 2.3 不搬的簇（有意保留，非遗漏）

- **素材簇胶水**（_on_asset_selected / _rebuild_block_asset_grid / _on_block_asset_btn_pressed / _clear_*_selection / _active_asset / _on_block_asset_ready / _flush_asset_thumbs / _on_asset_library_changed / _update_asset_preview）：几乎全被 user_asset_editor 契约按名钉死，且重活已在 asset_library_panel.gd / editor_block_list.gd / user_asset_service.gd 模块内。保留。
- **画布事件三联**（_on_cell_pressed/_dragged/_released）+ _apply_tool/_active_tool/_apply_height_brush：状态机核心，被钉死且与 _canvas/_move_* 状态深度耦合。保留。
- **区域/预设处理器胶水**（_on_region_*、_on_*_preset_*、_commit_*、_cancel_*）：内核已走 region_clipboard.gd/region_preset_store.gd 纯函数；剩余是门禁+历史+状态栏，被钉死。保留（本拆分继续把其中的纯逻辑下沉）。
- **_set_glyph / fill_cell 等模型手术的调用面**：fill_cell 是公共契约 API，保留门面。

## 3. 目标模块

### 新建（5 个，均在 scripts/editor/）

| 模块 | class_name | 形态 | 职责 | 批次 |
| --- | --- | --- | --- | --- |
| map_editor_history.gd | MapEditorHistory | RefCounted + static | 历史快照/比较/恢复/封存纯逻辑（snapshot/state_equal/restore_into/seal 游标数学） | A |
| map_editor_paint_ops.gd | MapEditorPaintOps | RefCounted + static | 纯模型笔刷内核：地形洪水填充/素材洪水填充/区域（体积）填充/条件替换/code_at | B |
| map_editor_panel_tabs.gd | MapEditorPanelTabs | RefCounted + static | 右侧 8 个 Tab 构建器（文件/生成/地形/方块/角色/历史/素材/预设）+ 地形/植物/阵营/职业按钮工厂 + scan_prop_paths | C |
| map_editor_block_palette.gd | MapEditorBlockPalette | RefCounted + static | 方块槽位/最近选择辅助（label/refresh_slot_ui/remember_pick/short_label/texture/refresh_recent_picks） | C |
| map_editor_overlays.gd | MapEditorOverlays | RefCounted + static | 画布悬浮层构建器：工具栏+add_tool_btn、格子信息栏、最近选择条、替换弹窗+选项装配、选区弹窗+端点行 | D |
| map_editor_file_io.gd | MapEditorFileIo | RefCounted + static | 读档候选解析（FileAccess+JSON+from_json_dict+校验）/战场列表刷新/保存前素材快照 sync_user_assets | E |

### 归拢既有（1 处）

- `region_clipboard.gd`（EditorRegionClipboard）新增 static `ghost_at(model, payload, anchor) Vector2i 锚点幽灵展开` ← 吸收 `_ghost_payload_at`（纯 payload→cells 计算，与该模块五层语义同域）。

### 不新建不归拢

- `editor_block_list.gd` / `editor_block_picker_dialog.gd` / `shortcut_hints_dialog.gd` / `block_selector.gd` / `selection_range.gd`：无同类可归逻辑（编辑器侧只剩被钉死的接线胶水）。

## 4. 150 函数完整映射表

标记：**MOVE**=整函数搬走（编辑器删或留 1 行直调）；**FACE**=函数名保留为薄门面，函数体主体进模块；**KEEP**=原地不动；**SITE**=直建控件行所在函数，特殊处理（见 §2.2）。批 = 执行批次。

### 簇：生命周期/输入路由（6）
| 函数 | 行 | 决策 | 批 |
| --- | --- | --- | --- |
| _ready | 230 | KEEP | – |
| _init_asset_service | 242 | KEEP | – |
| _text_input_has_focus | 251 | KEEP | – |
| _begin_alt_pick | 258 | KEEP | – |
| _end_alt_pick | 267 | KEEP | – |
| _unhandled_input | 278 | KEEP（钉死；ESC 级联顺序不动） | – |

### 簇：UI 构建（_build_ui 总装 + 8 Tab + 悬浮层，25）
| 函数 | 行 | 决策 | 去向/批 |
| --- | --- | --- | --- |
| _build_ui | 412 | KEEP（总装顺序不变，逐项改为调用构建器） | – |
| _build_file_tab | 522 | FACE → PanelTabs.build_file_tab | C |
| _build_generate_tab | 571 | FACE → PanelTabs.build_generate_tab | C |
| _build_tool_bar | 628 | FACE → Overlays.build_tool_bar | D |
| _build_replace_popup | 693 | FACE → Overlays.build_replace_popup | D |
| _build_recent_picks_bar | 745 | FACE → Overlays.build_recent_picks_bar | D |
| _populate_replace_options | 783 | MOVE → Overlays.replace_populate_options | D |
| _replace_item_for_code | 809 | MOVE → Overlays.replace_item_for_code | D |
| _build_cell_info | 924 | FACE → Overlays.build_cell_info | D |
| _build_hint_bar | 942 | **SITE**：整函数原地保留（Button.new()@943 不动） | – |
| _build_terrain_tab | 970 | FACE → PanelTabs.build_terrain_tab | C |
| _build_block_tab | 1016 | FACE → PanelTabs.build_block_tab | C |
| _plant_btn | 1268 | MOVE → PanelTabs.plant_btn | C |
| _build_units_tab | 1283 | FACE → PanelTabs.build_units_tab | C |
| _build_history_tab | 1329 | FACE → PanelTabs.build_history_tab | C |
| _build_asset_tab | 1345 | FACE → PanelTabs.build_asset_tab | C |
| _build_preset_tab | 1360 | **SITE**+FACE：CheckButton.new()@1410 留在门面先构造，传参给 PanelTabs.build_preset_tab | C |
| _scan_prop_paths | 1249 | MOVE → PanelTabs.scan_prop_paths（编辑器存 _prop_paths） | C |
| _pixel_btn | 1581 | KEEP（共享工厂，模块经 ctx 调用） | – |
| _add_tool_btn | 1588 | MOVE → Overlays.add_tool_btn | D |
| _faction_btn | 1616 | MOVE → PanelTabs.faction_btn | C |
| _terrain_btn | 1637 | MOVE → PanelTabs.terrain_btn | C |
| _class_btn | 1656 | MOVE → PanelTabs.class_btn | C |
| _build_selection_popup | 2105 | **SITE**+FACE：OptionButton.new()@2124 留在门面先构造，传参给 Overlays.build_selection_popup | D |
| _build_region_endpoint_row | 2200 | MOVE → Overlays.build_region_endpoint_row | D |

### 簇：方块槽/最近选择（7）
| 函数 | 行 | 决策 | 去向/批 |
| --- | --- | --- | --- |
| _set_block_slot | 1080 | KEEP（钉死；含 current_terrain 副作用） | – |
| _swap_block_slots | 1095 | KEEP（7 行微函数） | – |
| _block_label | 1102 | MOVE → BlockPalette.label | C |
| _refresh_block_slot_ui | 1110 | MOVE → BlockPalette.refresh_slot_ui(ed) | C |
| _recent_picks_info | 1120 | KEEP（钉死，5 行） | – |
| _remember_recent_pick | 1128 | MOVE → BlockPalette.remember_pick(ed) | C |
| _recent_pick_short_label | 1142 | MOVE → BlockPalette.short_label | C |
| _recent_pick_texture | 1150 | MOVE → BlockPalette.texture(ed) | C |
| _refresh_recent_picks | 1169 | FACE（钉死）→ BlockPalette.refresh_recent_picks(ed) | C |
| _on_recent_pick_pressed | 1205 | KEEP（钉死） | – |

### 簇：取色/笔刷模型操作（4）
| 函数 | 行 | 决策 | 去向/批 |
| --- | --- | --- | --- |
| _apply_paint_block | 1217 | KEEP（9 行分发器） | – |
| _pick_block | 1229 | KEEP（状态密集） | – |
| fill_cell | 2071 | FACE（钉死公共）→ PaintOps.flood_fill_terrain（刷新/状态栏留门面） | B |
| _set_glyph | 2059 | KEEP（钉死；rows 手术+_canvas._refresh_cell 内联） | – |

### 簇：替换工具（13）
| 函数 | 行 | 决策 | 去向/批 |
| --- | --- | --- | --- |
| _replace_source_code | 823 | KEEP（钉死，5 行 meta 读） | – |
| _replace_dest_code | 829 | KEEP（钉死） | – |
| _replace_code_for_block | 835 | KEEP（5 行微函数） | – |
| _replace_code_at | 842 | MOVE → PaintOps.code_at(model, cell) | B |
| _select_replace_option | 852 | KEEP（钉死；UI meta 操作） | – |
| _open_replace_picker | 875 | KEEP（接线胶水） | – |
| _on_replace_picker_chosen | 884 | KEEP（接线胶水） | – |
| _reset_replace_popup | 893 | KEEP（调 PaintOps.code_at） | – |
| _set_replace_source_from_cell | 905 | KEEP（胶水） | – |
| _refresh_replace_scope | 916 | KEEP（6 行 UI 回显） | – |
| _apply_replace | 2347 | FACE → PaintOps.replace_cells（匹配/写入循环下沉；门禁+undo+状态留门面） | B |

### 簇：素材面板（10）— 全部 KEEP（§2.3）
_on_asset_selected 1422 / _rebuild_block_asset_grid 1434（钉死）/ _on_block_asset_btn_pressed 1474（钉死）/ _clear_block_asset_selection 1489 / _active_asset 1498 / _on_block_asset_ready 1510 / _flush_asset_thumbs 1528 / _clear_asset_selection 1535（钉死）/ _on_asset_library_changed 1546 / _update_asset_preview 1562。

### 簇：画布事件→工具（17）— 全部 KEEP（§2.3）
_on_tab_changed 1573 / _active_tool 1686（钉死）/ _on_cell_pressed 1708（钉死）/ _on_cell_dragged 1750（钉死）/ _on_cell_released 1784（钉死）/ _apply_tool 1867（钉死）/ _apply_height_brush 1913 / _select_cell 1934 / _on_hover_changed 1942（钉死）/ _update_cell_info 1955 / _sync_block_panel 1967 / _on_block_z_changed 1978 / _sync_selection_after_model_change 1993 / _set_prop 2004 / _set_tile_override 2020 / _set_prop_asset 2030 / _apply_asset_tool 2041。

### 簇：区域选择（14）
| 函数 | 行 | 决策 | 去向/批 |
| --- | --- | --- | --- |
| _open_selection_popup | 2220 | KEEP（钉死） | – |
| _close_selection_popup | 2229 | KEEP | – |
| _on_selection_mode_item | 2234 | KEEP（钉死） | – |
| _apply_region_click | 2245 | KEEP（钉死） | – |
| _on_selection_range_changed | 2263 | KEEP | – |
| _sync_region_marker | 2268 | KEEP（钉死） | – |
| _sync_region_boxes | 2288 | KEEP（UI 回显） | – |
| _on_region_box_changed | 2310 | KEEP | – |
| _apply_fill | 2334 | KEEP（钉死；路由器） | – |
| _fill_region | 2414 | FACE → PaintOps.fill_region（体填充/找平循环下沉） | B |
| _flood_fill_asset | 2457 | MOVE → PaintOps.flood_fill_asset（UI 尾巴并入 _apply_fill 成功分支） | B |
| _on_region_fill_pressed | 2487 | KEEP | – |
| _on_region_clear_pressed | 2495 | KEEP（钉死） | – |

### 簇：区域剪贴板/移动（14）
| 函数 | 行 | 决策 | 去向/批 |
| --- | --- | --- | --- |
| _commit_region_move | 1814 | KEEP（内核已在 region_clipboard.move） | – |
| _nudge_region | 1835 | KEEP | – |
| _move_delta_for | 1845 | KEEP | – |
| _update_move_preview | 1855 | KEEP | – |
| _region_2d_bounds | 2508 | KEEP（微函数） | – |
| _move_tool_bounds | 2519 | KEEP（微函数） | – |
| _on_region_copy_pressed | 2529 | KEEP（钉死） | – |
| _on_region_cut_pressed | 2544 | KEEP（钉死） | – |
| _on_region_paste_pressed | 2567 | KEEP（钉死） | – |
| _update_paste_preview | 2580 | KEEP（改调 EditorRegionClipboard.ghost_at） | A |
| _ghost_payload_at | 2593 | MOVE → region_clipboard.gd 新增 static ghost_at（编辑器删除原函数） | A |
| _commit_paste | 2621 | KEEP | – |
| _cancel_paste | 2641 | KEEP（钉死） | – |
| _on_move_tool_toggled | 2652 | KEEP | – |
| _set_move_tool | 2658 | KEEP | – |
| region_clipboard_info | 2881 | KEEP（钉死公共） | – |

### 簇：区域预设（13）— 全部 KEEP（钉死/胶水，内核已在 region_preset_store + region_clipboard）
_refresh_preset_list 2678（钉死）/ _selected_preset_id 2695 / _on_save_preset_pressed 2705（钉死）/ _on_fill_preset_pressed 2727（钉死）/ _on_place_preset_toggled 2758 / _on_place_preview_toggled 2777 / _preset_name_for_id 2788 / _update_place_preview 2798（改调 ghost_at）/ _commit_place_preset 2813 / _cancel_place_mode 2837 / _on_rename_preset_pressed 2847 / _on_delete_preset_pressed 2861（钉死）/ _on_refresh_preset_pressed 2876。

### 簇：单位/生成/尺寸（8）— 全部 KEEP
place_unit 2902（钉死公共）/ _remove_unit_at 2932 / apply_generate 2944（钉死公共）/ _generate 2968 / _on_resize 2972 / _refresh_canvas 2989（中枢）/ _on_tool_changed 2999（钉死）/ _update_cell_info 已计入画布簇。

### 簇：历史（10）
| 函数 | 行 | 决策 | 去向/批 |
| --- | --- | --- | --- |
| _init_history | 3024 | KEEP（调 History.snapshot） | A |
| _push_undo | 3034 | KEEP（钉死，3 行） | – |
| _seal_pending | 3040 | FACE（钉死）→ History.seal（快照/比较/截断/上限淘汰数学下沉，游标经返回值回写） | A |
| _undo | 3057 | KEEP（钉死；游标+restore+状态栏） | – |
| _redo | 3069 | KEEP（钉死） | – |
| _jump_history | 3082 | KEEP | – |
| _refresh_history | 3096 | KEEP（ItemList 重建） | – |
| _snapshot | 3112 | FACE → History.snapshot | A |
| _state_equal | 3131 | MOVE → History.state_equal（编辑器删） | A |
| _restore | 3139 | FACE → History.restore_into（模型深拷贝下沉；SpinBox 同步+_refresh_canvas 留门面） | A |

### 簇：存取档（6）
| 函数 | 行 | 决策 | 去向/批 |
| --- | --- | --- | --- |
| _refresh_load_box | 3166 | FACE → FileIo.refresh_load_box | E |
| _load_selected | 3177 | KEEP（5 行） | – |
| load_path | 3185 | FACE（钉死公共）→ FileIo.load_candidate（打开/解析/from_json_dict/校验下沉，返回 {ok,model,error}；门面做 undo/补 tag/回显/清理模式） | E |
| _save | 3228 | KEEP | – |
| save_current | 3237 | KEEP（钉死公共；改调 FileIo.sync_user_assets） | E |
| _sync_model_user_assets | 3253 | MOVE → FileIo.sync_user_assets(model, service)（编辑器删） | E |

### 簇：收尾（2）
_back_to_world 3276 KEEP；_status 3281 KEEP（中枢）。

**计数校验**：150 函数全部覆盖（MOVE 18 / FACE 17（含 2 个 SITE 门面）/ KEEP 115）。`_build_hint_bar` 计入 KEEP（SITE 整函数保留）。

## 5. 执行批次（5 批，每批独立验证 = 独立提交单元）

> 命令模板：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/<name>_contract.gd > /tmp/t.log 2>&1; echo $?`
> ⚠️ 必须全权限运行（沙箱内 headless 启动段错误，见 §1）。
> 每批固定动作：① 备份 `cp scripts/scenes/map_editor.gd /tmp/editor_split_backup/batch_<X>.gd.bak`；② 改码；③ 跑该批契约（绿契约须 exit=0）；④ `grep '^ERROR:' /tmp/<n>.log` 与 §1 基线主题逐条比对（map_editor_ui 6 条 / ui 3 条不变；行号/文件名变化可接受）；⑤ `grep '\[editor\]' map_editor_region_ops.log` 的 L1 埋点序列与基线 diff（行为等价的强证据）；⑥ 不过 → 回滚该批（恢复 .bak + 删新模块），记录原因再重试。

| 批 | 内容 | 新文件 | 预计抽走行数（净） | 契约 |
| --- | --- | --- | --- | --- |
| A | 历史内核 + ghost_at 归拢 | map_editor_history.gd + region_clipboard.gd 增 ghost_at | ~110（map_editor −85） | map_editor_region_ops、editor_region_clipboard、editor_selection、map_editor_ui（红对照）、ui（红对照） |
| B | 纯模型笔刷内核 | map_editor_paint_ops.gd | ~170 | map_editor_region_ops、user_asset_editor、map_editor_ui/ui（红对照） |
| C | 8 Tab 构建器 + 方块槽/最近选择辅助 + scan_prop_paths | map_editor_panel_tabs.gd、map_editor_block_palette.gd | ~380（最大批，CheckButton SITE 门面在此批） | map_editor_region_ops、user_asset_editor、map_editor_ui/ui（红对照） |
| D | 悬浮层构建器（工具栏/信息栏/最近条/替换弹窗/选区弹窗） | map_editor_overlays.gd | ~250（OptionButton SITE 门面在此批） | map_editor_region_ops、hint_bar、editor_block_picker、map_editor_ui/ui（红对照） |
| E | 存取档内核 | map_editor_file_io.gd | ~55 | user_asset_editor、map_editor_region_ops、map_editor_ui/ui（红对照） |
| 收尾 | 全家族复跑 + 行数/结构复核 | – | – | §1 全部 9 个契约 + map_editor_contract（模块级，免费复跑） |

预计总效果：map_editor.gd 3285 → 约 2320 行（净 −965，−29%），scripts/editor/ 新增 5 模块约 1050 行（含门面重复与模块头注释）。

批次排序理由：简报建议「提示栏先、工具/区域中、存取档最后」；本方案中提示栏簇（_build_hint_bar）因 SITE 决策原地保留（§2.2），故以「纯数据内核（A/B）→ 构建器（C/D）→ IO（E）」的低→高风险排序替代，存取档仍最后，符合简报纸意图。A 批最小且独立，作为门面模式的一次全链路验证。

## 6. 行为不变的关键保障（执行时逐条自查）

1. **构建顺序**：_build_ui 内构建器调用顺序不变；各构建器内部节点创建/add_child/信号连接顺序与原函数逐行一致；唯一允许偏差 = 两个 SITE 控件的裸构造提前到门面（属性/加树/接线时机不变）。
2. **信号 lambda**：随体移动后捕获 `ctx`（=编辑器实例），callable 语义等价。
3. **历史语义**：History.seal 返回新游标由门面回写 `_history_cursor`；pop_front 上限淘汰顺序、`_state_equal` 字段集合（rows/units/props/tile_overrides/block_layout）不变；UNDO_LIMIT 留在编辑器。
4. **_flood_fill_asset UI 尾巴**：早退分支（空 id/越界/起点已是目标）不得触发 _refresh_canvas/_status —— PaintOps 返回 -1 哨兵，_apply_fill 仅成功分支做刷新+状态，输出文本逐字保留（含 `素材填充 %s ×%d 格` 与 L1 埋点）。
5. **L1 埋点**：所有 `print("[editor] ...")` 文本与触发时机不动（region_ops 契约日志 diff 是验收证据）。
6. **模块头**：每个新文件 `## file.gd — 职责` + class_name + extends RefCounted + static；tab 缩进；不引入新 preload 依赖环（模块只 preload 叶子模块，编辑器经 ctx 传自身）。
7. **不改**：main.gd、ui/ 组件库、DESIGN.md、tests/、.tscn（节点全部代码构建，无场景文件改动）。

## 7. 风险与回滚

| 风险 | 缓解 |
| --- | --- |
| 契约钉死名意外移走 → 绿契约转红 | §4 表已逐名核对三个契约的成员清单；每批跑对应绿契约兜底 |
| 构建器搬家后节点树漂移（名字/父级/锚点） | 构建体逐行搬移不改字面量；map_editor_ui 6 条红主题=结构探针，主题漂移即报警 |
| ui 契约误转绿（3 处 .new() 离开扫描清单） | §2.2 SITE 决策：3 行留在 map_editor.gd；每批比对 ui 3 条主题 |
| GDScript 私有成员跨文件访问 | 下划线仅为约定，静态函数经 `ctx`（Object）动态访问合法；编译器不拦截 |
| 历史游标按值传递被改语义 | seal/snapshot 返回值由门面显式回写；A 批 region_ops 全量历史断言覆盖 |
| 回滚 | 不用 git（约束 6）；批前 .bak + 新模块文件删除即回滚；回滚后必须复跑该批契约确认回到基线 |

## 8. 待 Lead 决策

§2.2 备选：若坚持 3 处直建控件**物理**随簇移动（简报字面「原样随簇移动」），必须同步把新模块路径加进 tests/ui_contract.gd `_check_source` 清单（触碰「不改 tests/」边界）或接受 ui 契约转绿（与「仍会红、主题一致」矛盾）。默认按 §2.2 执行（3 行留 map_editor.gd，其余簇体照搬）；Lead 若选备选，C/D 两批按备选调整。
