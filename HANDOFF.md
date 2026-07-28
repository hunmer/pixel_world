# HANDOFF — pixel_world 快速入口目录

> 更新于 2026-07-28。目标：下个 agent 接新需求时先按本目录跳入口，少重读代码库。
> 当前工作区已有未提交改动；不要回滚用户/前序 agent 改动。

## 当前状态

- Godot 工程：`G:/pixel_world`
- 主场景：`res://main.tscn`
- 默认战斗模式：B1 就地战旗，按 `P` 从世界进入。
- B2 切场景模式仍保留：`res://scenes/Battle.tscn`，由 `Settings.battle_inline_mode=false` 切换。
- 最近验证：
  - `& "C:/Program Files/Godot/Godot.exe" --headless --path "G:/pixel_world" --script "res://tests/battle_screen_pick_contract.gd"`
  - `& "C:/Program Files/Godot/Godot.exe" --headless --path "G:/pixel_world" --quit-after 1`
- 已知环境警告：Breakpoint MCP runtime 端口 `9081` 可能占用；不是脚本编译错误。

## 需求入口索引

| 新需求/问题 | 先看文件 | 入口函数/字段 | 说明 |
|---|---|---|---|
| 按 `P` 进入战旗 / 退出恢复 | `main.gd` | `_enter_battle()` / `_enter_battle_inline()` / `_exit_battle()` | B1 实例化 `scripts/scenes/battle.gd` 为子节点；退出恢复相机/玩家 |
| B1/B2 模式切换 | `scripts/settings.gd`, `scripts/game_hud.gd` | `Settings.battle_inline_mode` | HUD 设置面板切换；默认 B1 |
| 战旗相机拖拽/边缘滚屏/缩放 | `main.gd` | `_battle_cam_offset`, `_handle_battle_camera_input()`, `_update_battle_edge_pan()`, `_handle_battle_input()` | B1 相机归 `main.gd`；拖拽是中键或 `Space`+左键 |
| 鼠标拾取/高地光标偏移 | `main.gd`, `scripts/scenes/battle.gd` | `screen_to_cell()`, `screen_to_cell_in_rect()`, `_screen_to_battle_cell_unbounded()`, `_screen_to_battle_cell()` | hover 用全局拾取，可显示战场矩形外；点击/确认用矩形内拾取 |
| 黄色光标显示 | `scripts/battle/range_overlay.gd`, `scripts/scenes/battle.gd` | `create_cursor_particles()`, `update_cursor_particles()`, `_unhandled_input()` mouse motion 分支 | 矩形外只显示光标，不跑格子信息/路径 |
| 移动/攻击范围描边 | `scripts/battle/range_overlay.gd`, `scripts/scenes/battle.gd` | `highlight_range()`, `_range_alpha_for_cell()`, `_higher_neighbor_count()`, `_b1_cell_level()` | B1 按高度层和四邻更高格降低 alpha；B2 无高度函数时保持原样 |
| 选中/移动/攻击逻辑 | `scripts/scenes/battle.gd`, `scripts/systems/grid_system.gd` | `_on_tile_click()`, `_select_unit()`, `_perform_move()`, `_perform_attack_from_current()` | 战斗规则在 `grid_system`/`combat_system`，不要放到渲染层 |
| 右键单位详情 | `scripts/scenes/battle.gd`, `scripts/battle/battle_ui.gd` | 右键分支, `open_unit_detail()`, `close_unit_detail()`, `is_unit_detail_open()` | ESC/左键地图先关闭详情 |
| 单位立绘尺寸/定位 | `scripts/iso/unit_sprite.gd`, `scripts/scenes/battle.gd` | `UNIT_VISUAL_PX`, `setup_world()`, `_apply_render_proxy()`, `_spawn_unit_sprite()` | 当前 `UNIT_VISUAL_PX=32.0` |
| 世界地形转战旗 chapter | `scripts/core/world_to_chapter.gd` | `world_to_chapter()`, `cell_context_to_terrain()`, `_find_standable_near()` | 21x21 战场，`world_origin` 是局部 `(0,0)` 对应世界 cell |
| 天气/昼夜/景深快捷键 | `main.gd` | `_unhandled_input()` key 分支 (`T`/`N`/`B`) | 战旗期间 `_handle_battle_input()` 只吞 `P`，其余放行 |
| 技能/物品/buff | `scripts/systems/*_system.gd`, `scripts/battle/battle_ui.gd` | `SkillSystem`, `ItemSystem`, `BuffSystem`, UI picker 方法 | 纯逻辑优先用 `res://scenes/SkillTest.tscn` |

## 最近已修复内容

- `scripts/iso/unit_sprite.gd`：缩小 hero 立绘，`UNIT_VISUAL_PX` 从 64 改为 32。
- `main.gd`：B1 相机支持滚轮/`+`/`-`/`F`、中键拖拽、`Space`+左键拖拽、边缘滚屏。
- `main.gd`：`screen_to_cell()` 改为多高度候选拾取，修复高地 Y 偏移。
- `main.gd`：新增 `screen_to_cell_in_rect()`，点击/确认限制在 21x21 战场内。
- `scripts/scenes/battle.gd`：hover 改用全局拾取，战场矩形外也能显示黄色光标。
- `scripts/battle/range_overlay.gd`：移动/攻击范围描边按高度和邻近遮挡降低透明度。
- `scripts/scenes/battle.gd` + `scripts/battle/battle_ui.gd`：右键查看单位详情面板。
- `tests/battle_screen_pick_contract.gd`：新增坐标拾取合约，覆盖高地中心和 rect 内拾取。

## 最短验证命令

```powershell
& "C:/Program Files/Godot/Godot.exe" --headless --path "G:/pixel_world" --script "res://tests/battle_screen_pick_contract.gd"
& "C:/Program Files/Godot/Godot.exe" --headless --path "G:/pixel_world" --quit-after 1
```

手动验收：

1. 运行 `main.tscn`，按 `P` 进战旗。
2. 高地 hover/点击：黄色光标应贴鼠标格，不随高度 Y 偏移。
3. `Space`+左键拖拽：相机移动，松手不误点击。
4. 拖到战场边缘外：黄色光标仍跟随；点击/确认不越界触发战斗。
5. 选中单位：移动/攻击范围描边在低处、四邻有更高地形处更透明。
6. 按 `T` 切天气，`+`/`-`/`F` 缩放/复位。

## 调试规则摘录

- 会话开头优先 `mcp__godot_breakpoint.editor_ping()`；当前可能失败，失败时用 headless 命令验证编译。
- `dbg_launch` 必须传 scene：`res://main.tscn`。
- 默认不用截图；能用脚本/断言就不用 `runtime_screenshot`。
- 本地图片查看禁用 `view_image`。
- CodeGraph 当前未初始化；查结构用 `rg`。

## 不要踩的坑

- B1 下 `battle.gd.board == null`，相机/缩放/平移必须在 `main.gd` 处理。
- hover 可以越出战场矩形；点击、确认、路径、信息面板必须继续 `grid.in_bounds()`。
- `screen_to_cell()` 是世界全局拾取；战斗操作要用 `screen_to_cell_in_rect()`。
- `RangeOverlay` 是渲染层，只改显示，不改移动/攻击规则。
- GDScript strict 推断敏感；`Variant.get()`、动态 `Callable.call()` 结果尽量显式标类型。
- 现有 `.zcode/`、`AGENTS.md`、`CLAUDE.md`、`addons/breakpoint_mcp/CLAUDE.md` 等未跟踪文件不是本轮创建，不要清理。

## 继续工作建议

- 交互 bug：先看 `main.gd` 输入分发，再看 `scripts/scenes/battle.gd` `_unhandled_input()`。
- 坐标 bug：先跑 `tests/battle_screen_pick_contract.gd`，再改 `screen_to_cell*`。
- 视觉层级 bug：优先改 `range_overlay.gd` 或 `unit_sprite.gd`，不要碰 `GridSystem`。
- 规则 bug：优先改 `scripts/systems/*`，不要把规则塞进 UI/渲染层。
