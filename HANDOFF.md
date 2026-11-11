# HANDOFF — pixel_world 快速入口目录

> 更新于 2026-11-11。目标：下个 agent 接新需求时先按本目录跳入口，少重读代码库。
> 当前工作区已有未提交改动（`addons/breakpoint_mcp/*`、`.zcode/plans/*` 删除）；不要回滚用户/前序 agent 改动。

## 当前状态

- Godot 工程目录：`E:/pixel_world`（**已从 G:/ 迁移**）；主场景 `res://main.tscn`
- Godot exe：`D:/Godot/Godot_v4.7.2-stable_win64_console.exe`（不在 PATH；用 `wmic process where "name like '%godot%'" get ExecutablePath,CommandLine` 查）
- 默认战斗模式：B1 就地战旗，按 `P` 从世界进入。
- B2 切场景模式仍保留：`res://scenes/Battle.tscn`，由 `Settings.battle_inline_mode=false` 切换；**JSON 战场固定走 B2**（自带地形与世界无关）。
- 新功能（2026-11-11 两个 feature commit）：按 `O` 打开 JSON 战场列表；按 `E` 打开战场地图编辑器。
- HUD 布局（同日调整）：战场/设置改为**左侧竖排图标按钮**（`HUDRoot/LeftBar`，无文字 42×42，悬停提示）；操作提示条移到**右下角**（`HUDRoot/BottomArea`，含 `SPACE+拖拽 平移地图` 提示）。战场 B1/B2 与编辑器画布均支持按住空格+左键拖拽平移（编辑器还支持右键拖拽）。
- **等距方块渲染重做（2026-11-11）**：B2 战场与编辑器画布均改为像素 Minecraft 式等距方块渲染（`BattlefieldRenderer`，复用世界渲染管线 ColumnBatch + TerrainMaterialRegistry 贴图 + 程序化水面），平面色块代码已删（`render_terrain_fallback`、`iso_board` 的块池/网格绘制）。
- 编辑器修复+图片调色板（同日）：画笔/橡皮单格刷新 bug 修复（`EditorCanvas._refresh_cell` 现先同步 renderer 的 GridSystem 再重建柱——此前模型更新但渲染网格还是旧地形导致视觉无变化）；地形调色板改为**图片缩略图**（`TilePreview` 画 `BattlefieldRenderer.preview_blocks(terrain)` 的等距方块柱，4 列 GridContainer，无文字，tooltip=地形名+图例）。
- Breakpoint MCP 编辑器桥可用（addon 1.23.0，`editor_ping`→pong；运行时桥端口 9081）。

## 需求入口索引

| 新需求/问题 | 先看文件 | 入口函数/字段 | 说明 |
|---|---|---|---|
| 按 `P` 进入战旗 / 退出恢复 | `main.gd` | `_enter_battle()` / `_enter_battle_inline()` / `_exit_battle()` | B1 实例化 `scripts/scenes/battle.gd` 为子节点；退出恢复相机/玩家 |
| JSON 战场列表（`O` 键） | `scripts/core/battlefield_loader.gd`, `scripts/game_hud.gd` | `BattlefieldLoader.list_battlefields()/load_battlefield()`, HUD `toggle_battlefield_panel()`, main `_enter_battlefield(path)` | 扫 `res://data/battlefields/` + `user://battlefields/`（res 优先、同名跳过）；坏 JSON 条目置灰显示 error |
| JSON 战场文件格式 | `data/battlefields/*.json` | 顶层 `rows`(图例字符画)/`map`(全名)+`legend`+`playerUnits`/`enemyUnits`+`hosting` | **rows 是顶层字段，不嵌在 terrain 下**；校验在 loader（地形名/行宽/职业/界内/standable/不重叠/双阵营≥1） |
| 地图编辑器（`E` 键） | `scripts/scenes/map_editor.gd`, `scripts/editor/battlefield_doc.gd`, `scripts/editor/editor_canvas.gd` | `apply_generate()/load_path()/save_current()/place_unit()`, `BattlefieldDoc.generate/resize/to_json_dict` | 种子确定性生成（水域/山脊/森林/村庄/要塞）；画笔/填充/橡皮/角色四工具；保存产出同 schema 且立即进 `O` 列表 |
| 等距方块地形渲染（B2+编辑器共用） | `scripts/iso/battlefield_renderer.gd` | `setup(grid)`, `stand_level(x,y)`, `coord_for(x,y)`, `sort_for(x,y)`, `pick_world(global_pos)`, `refresh_cell(x,y)` | plain/forest h2、water h1、village h2、fort h3、wall h4、mountain h5；贴图静态加载自 `config/ecology/world/base.json` 的 materials；`pick_world` 入参是**全局 canvas 坐标**（内部做 `global_transform.affine_inverse()`），走 `EditorCanvas._pick(canvas局部)` |
| 战场/编辑器单位站位高度 | `scripts/iso/unit_sprite.gd`, `scripts/scenes/battle.gd`, `scripts/battle/battle_ui.gd` | `us.setup(u, board, Callable(renderer,"stand_level"))`, `battle_ui.level_fn` | 单位站在 `to_screen(x,y,stand_level)`；菜单定位也用 level_fn；`_debug_print_unit_alignment` 已按 stand_level 对齐 |
| B1/B2 模式切换 | `scripts/settings.gd`, `scripts/game_hud.gd` | `Settings.battle_inline_mode` | HUD 设置面板切换；默认 B1 |
| 战旗相机拖拽/边缘滚屏/缩放 | `main.gd` | `_battle_cam_offset`, `_handle_battle_camera_input()`, `_update_battle_edge_pan()`, `_handle_battle_input()` | B1 相机归 `main.gd`；拖拽是中键或 `Space`+左键 |
| 鼠标拾取/高地光标偏移 | `main.gd`, `scripts/scenes/battle.gd` | `screen_to_cell()`, `screen_to_cell_in_rect()`, `_screen_to_battle_cell_unbounded()`, `_screen_to_battle_cell()` | hover 用全局拾取，可显示战场矩形外；点击/确认用矩形内拾取 |
| 移动/攻击范围描边 | `scripts/battle/range_overlay.gd`, `scripts/scenes/battle.gd` | `highlight_range()`, `_range_alpha_for_cell()`, `_higher_neighbor_count()`, `_b1_cell_level()` | B1/B2 均走 `setup_world()` 注入 coord/sort/level 三 fn（B2 由 BattlefieldRenderer 提供）；地形渲染不再归 range_overlay |
| 选中/移动/攻击逻辑 | `scripts/scenes/battle.gd`, `scripts/systems/grid_system.gd` | `_on_tile_click()`, `_select_unit()`, `_perform_move()`, `_perform_attack_from_current()` | 战斗规则在 `grid_system`/`combat_system`，不要放到渲染层 |
| 世界地形转战旗 chapter | `scripts/core/world_to_chapter.gd` | `world_to_chapter()`, `cell_context_to_terrain()`, `_find_standable_near()` | 21x21 战场，`world_origin` 是局部 `(0,0)` 对应世界 cell |
| 天气/昼夜/景深快捷键 | `main.gd` | `_unhandled_input()` key 分支 (`T`/`N`/`B`/`O`/`E`) | 战旗期间 `_handle_battle_input()` 只吞 `P`，其余放行 |
| 技能/物品/buff | `scripts/systems/*_system.gd`, `scripts/battle/battle_ui.gd` | `SkillSystem`, `ItemSystem`, `BuffSystem`, UI picker 方法 | 纯逻辑优先用 `res://scenes/SkillTest.tscn` |

## 本轮新增内容（2026-11-11）

- JSON 战场系统：`scripts/core/battlefield_loader.gd`（加载/校验/双目录扫描）+ 4 个示例（`arena_1v1`/`plains_skirmish`/`river_crossing`/`mountain_pass`）+ HUD `O` 面板（`scripts/game_hud.gd` `BattlefieldPanel`）+ `main.gd` `_enter_battlefield()` 固定 B2 + `scripts/core/professions.gd` `has_profession()`。
- 地图编辑器：`scripts/editor/battlefield_doc.gd`（模型/种子生成/JSON 往返/quick_validate/save_model 保存即回读校验）+ `scripts/editor/editor_canvas.gd`（等距方块画布：内嵌 BattlefieldRenderer+多高度拾取+右键平移+滚轮缩放）+ `scripts/scenes/map_editor.gd` + `scenes/MapEditor.tscn` + HUD「🛠 打开地图编辑器」按钮 + `main.gd` `KEY_E`。
- 等距渲染重做：`scripts/iso/battlefield_renderer.gd`（新，核心渲染器）+ `scripts/iso/unit_sprite.gd`（B2 高度感知站位）+ `scripts/iso/iso_board.gd`（重写为纯相机/坐标转换）+ `battle.gd`/`battle_ui.gd`/`range_overlay.gd` 接线 + 删平面渲染（`render_terrain_fallback` 等）。
- 契约测试：`tests/battlefields_contract.gd`、`tests/map_editor_contract.gd`、`tests/battlefield_render_contract.gd`（均通过，见下方命令）。

## 最短验证命令

```powershell
& "D:/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path "E:/pixel_world" --script "res://tests/battlefields_contract.gd"
& "D:/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path "E:/pixel_world" --script "res://tests/map_editor_contract.gd"
& "D:/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path "E:/pixel_world" --script "res://tests/battle_screen_pick_contract.gd"
& "D:/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path "E:/pixel_world" --script "res://tests/battlefield_render_contract.gd"
```

（console exe 的 stdout 全缓冲：管道里无输出≠没输出，用 `timeout N` 包裹重跑即可见。）

手动验收：

1. 运行 `main.tscn`，按 `O` 出战场列表（含 4 个示例），点「竞技场单挑」进 B2 战斗，回合/单位正确。
2. 按 `E` 进编辑器：🌱 生成（同种子同图）→ 画地形 → 选阵营+职业放角色 → 保存 → 回世界按 `O`，新图已在列表。
3. 按 `P` 进 B1 战旗（世界地形），旧验收项（高地光标/相机拖拽/范围描边）不受影响。

## 调试规则摘录

- 会话开头先 `mcp__godot__editor_ping()`（当前可用）；`dbg_launch` 必须传 scene。
- 验证优先 `runtime_assert_scene_structure/screen_text/await_condition`（屏幕文本 samples 还能反查控件真实路径）；`runtime_get_tree` 对世界场景是灾难（4235 子节点），先 `max_depth` 限制。
- 默认不用截图；能用脚本/断言就不用 `runtime_screenshot`。本地图片查看禁用 `view_image`。
- DAP 抓运行时异常很有效：`runtime_*` 超时提示 stopped at breakpoint → `dbg_continue` 看异常信息。
- git-bash（ops_bash）里 PowerShell `$_` 和 cmd `/PID` 会被吃掉：查进程用 `wmic`，杀进程用 `cmd //c "taskkill /PID xxx /F"`。
- dbg_launch 启动的游戏进程 `godot_stop` 管不了，用 wmic 找 `--scene` 的 PID 后 taskkill。

## 不要踩的坑

- B1 下 `battle.gd.board == null`，相机/缩放/平移必须在 `main.gd` 处理。
- hover 可以越出战场矩形；点击、确认、路径、信息面板必须继续 `grid.in_bounds()`。
- `RangeOverlay` 是渲染层，只改显示，不改移动/攻击规则。
- battlefield JSON：`rows` 是**顶层**字段；loader 是唯一权威校验点（编辑器 save_model 靠回读它校验）。
- `Dictionary.merge(meta)` 默认 overwrite=false；要覆盖显式传 `true`。
- 程序化同步多个 SpinBox 会触发 `value_changed` 竞态（读到另一半旧值）：用 `_syncing_boxes` 标志挂起回调（`map_editor.gd` 已有）。
- 切场景（change_scene 释放自身）前先 `set_input_as_handled()`：之后 `get_viewport()` 为 null。
- GDScript strict 推断敏感：`Variant.get()`、`rows.map().max()`、untyped Array 元素取子串等要显式标类型（`as int`/`as String`）；**Node2D 动态调用同理**（`var c := _renderer.coord_for(...)` 报 Parse Error，要 `var c: Vector2 = ...`）。
- `TerrainMaterialRegistry.set_texture_processor` 回调是**两参** `(raw_texture, texture_path)`；漏第二参会全部贴图 null → ColumnBatch 当场 `get_size()` 崩。
- `IsoCoords.to_cell` 用 **roundi**（非 floor），写 pick 相关契约/断言时按四舍五入推演。
- runtime 桥 9081 单实例：console exe 直跑场景与 dbg 游戏并存时后者报 `could not listen (error 22)`；抓 Parse Error 用 `console exe --path . res://场景.tscn` + timeout 包裹（`--script` 模式不加载场景测不出场景脚本编译错）。
- **`tests/game_hud_contract.gd` 在 HEAD 上本来就是坏的**（`--script` 模式无 autoload，`game_hud.gd` 引 `Settings` 编译错；已 git stash 验证非本轮引入），修它需先解决 HUD 的 autoload 依赖。
- 4.7 无 `DirAccess.remove_recursive*`；删目录=逐文件 `dir.remove(f)`。
- 现有 `.zcode/`、`.dsh/`、`AGENTS.md`、`CLAUDE.md`、`addons/breakpoint_mcp/*` 的未提交改动等不是本轮创建/修改，不要清理。

## 继续工作建议

- JSON 战场/编辑器 bug：先跑两个 contract 测试，再读 `battlefield_loader.gd`（校验）/`battlefield_doc.gd`（模型）/`map_editor.gd`（交互）。
- 编辑器 UI 扩展（撤销/重做、多选、复制粘贴单位）：参考 phaserjs 版 `D:/phaserjs/godot/scripts/scenes/map_editor.gd`（5 工具/历史/撤销，Node3D+IsoBoard，较重）。
- 交互 bug：先看 `main.gd` 输入分发，再看 `scripts/scenes/battle.gd` `_unhandled_input()`。
- 坐标 bug：先跑 `tests/battle_screen_pick_contract.gd`，再改 `screen_to_cell*`。
- 规则 bug：优先改 `scripts/systems/*`，不要把规则塞进 UI/渲染层。

## Suggested skills

- 编辑器桥调试（本仓库 `addons/breakpoint_mcp`）：会话开头 `mcp__godot__editor_ping`；详见 `AGENTS.md` 的 MCP 调试规范与 `rules/mcp-debugging.md`。
- 契约测试模板：`extends SceneTree` + `_initialize` → `call_deferred("_run")` + `_expect(cond,msg)` + 末尾 `print("XXX_CONTRACT_OK")`，参考 `tests/battlefields_contract.gd`。
