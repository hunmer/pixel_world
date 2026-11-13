# 入口与启动

## 引擎入口

- **`project.godot`** — Godot 工程配置。
  - `run/main_scene = "res://scenes/Game.tscn"` → 直接运行项目时进入**战旗会话入口**（默认自动续玩最近战旗，见下）。
  - `[autoload]` 注册 **5 个**全局单例（启动即存在，跨场景存活）：
    | Autoload | 脚本 | 作用 |
    | --- | --- | --- |
    | `SceneArgs` | `scripts/scenes/scene_args.gd` | 跨场景传参暂存（`battle_args`、`pending_level_id`、`map_editor_return_to`） |
    | `GameSession` | `scripts/scenes/game_session.gd` | 战旗会话路由：启动决策（`--battlefield` > 最近存档 > 默认 plains_skirmish）、稳定身份、分战场存档提交（详见下节） |
    | `Settings` | `scripts/settings.gd` | 用户偏好，`ConfigFile` 持久化到 `user://settings.cfg`（`battle_inline_mode`） |
    | `BreakpointRuntimeBridge` | `addons/breakpoint_mcp/runtime_bridge.gd`（uid） | 调试运行时桥（loopback 9081，插件启用时） |
    | `Panku` | `addons/panku_console/console.tscn` | 运行时调试控制台（`~` 呼出表达式 REPL） |
  - `[editor_plugins]` 启用 2 个：`breakpoint_mcp`、`panku_console`（at-icons 已 vendored 但**未启用**插件）。
  - `[input]` 定义 `confirm`(Z/Enter)、`cancel`(Esc)、`end_turn`(E) —— 供战棋 UI 用。
  - `[display]` 视口 1280×800，`stretch/mode = "canvas_items"`。
  - `[physics]` `3d/physics_engine = "Jolt Physics"`（3D 正交迁移后真实使用）。
  - `[rendering]` `gl_compatibility`。

- **运行环境**：Godot 4.7.2 stable；本机可执行文件 `D:/Godot/Godot_v4.7.2-stable_win64.exe`（不在 PATH；console 版为 `..._console.exe`）。项目目录 `E:/pixel_world`（**已从 G:/ 迁移**）。

## 场景入口（7 个 .tscn + 1 探针）

| `.tscn` | 脚本 | 角色 | 进入方式 |
| --- | --- | --- | --- |
| `scenes/Game.tscn` | `scripts/scenes/game_entry.gd` | **默认主入口**：冷启动自动续玩最近战旗；从战斗返回时显示战场列表 | `project.godot` 主场景；`Title` 的"开始"按钮 |
| `main.tscn` | `main.gd` | 世界根场景（Node2D "Main" + 子节点 "DebugConsoleCommands"） | `Game` 列表的"生态世界"按钮；编辑器手动运行 |
| `scenes/Title.tscn` | `scripts/scenes/title.gd` | 标题屏（Control） | 可选手动运行；按钮 → `change_scene_to_file("res://scenes/Game.tscn")` |
| `scenes/Battle.tscn` | `scripts/scenes/battle.gd` | 战斗独立场景（B2，世界地形） | `inline_mode=false` 按 P；**JSON 战场固定走此场景**（O 键选择） |
| `scenes/MapEditor.tscn` | `scripts/scenes/map_editor.gd` | 战场地图编辑器 | 世界内按 `E`；HUD 按钮；`MapEditor.tscn` 依赖编辑器参数，一般不直启 |
| `scenes/Isometric3DTest.tscn` | `scripts/scenes/isometric_3d_test.gd` | 最小 3D 柱网格 + 90° 相机旋转验证 | 编辑器手动运行 |
| `scenes/SkillTest.tscn` | `scripts/tests/test_skills.gd` | 技能/物品自测场景 | 编辑器手动运行（headless 测试入口） |
| `tests/flat_rotation_probe.tscn` | `tests/flat_rotation_probe.gd` | 平地旋转探针 | 调试用 |

> 注意：`main.tscn` 极简（Node2D + main.gd + DebugConsoleCommands），几乎所有子节点由 `main.gd._ready()` **程序化创建**。`Battle.tscn` 依赖 `SceneArgs.battle_args`，**不能直接运行**。

## main.gd 启动流程（`_ready` @ 951）

```
_ready()
 ├─ 读 @export 参数（seed=0 随机, stream_extent=32, sight_radius=12, move_time, ...）
 ├─ _load_ecosystem_config() + _compile_ecosystem_config()
 │     （加载 config/ecosystems.json + config/ecology/manifest.json，编译为运行时结构）
 ├─ _compile_animal_behavior_stacks()  （组合动物行为注册表）
 ├─ _validate_ecosystem_config()        （启动期配置校验，失败则 abort）
 ├─ 装配子系统：_setup_player / _setup_camera(3D) / _setup_hud / _setup_world_map
 │              _setup_day_night（同时创建 SunlightSystem）/ _setup_depth_of_field
 │              / _setup_audio / _setup_fireflies / _setup_weather
 ├─ _regenerate(seed)                    （首次地形生成 + 流式；Ctrl+R 重触发）
 └─ 进入主循环 _process / _unhandled_input
```

`_regenerate(new_seed)` 清理旧 cell/动物，重置 RNG，触发首轮 `_update_streaming`。

## 战斗 / 战场 / 编辑器入口

详见 `module-responsibilities.md` 的"战棋数据流"。关键：
- **冷启动（`Game.tscn`）**：`GameSession.prepare_entry()` 决策 → `--battlefield=<id|路径|文件名>` 显式指定 > 最近存档（`user://battle_saves/index.json`）> 默认 `plains_skirmish`；有进度则带 `save_state` 恢复进入 `Battle.tscn`。`--reset-battle[=id]` 一次性清目标档后新开（每个战旗独立档案，互不影响；进程内只消费一次）。最近是**世界就地战旗**（`world:seed/x/y`）时冷启动直接按档案快照以 B2 恢复。
- 从战斗退出（⏏ 按钮 / 胜负返回）回 `Game.tscn` 时因 `GameSession.in_session` 停在战场列表：继续最近 / 选择战场 / 重置 / 战场编辑器 / 生态世界。
- `main.gd._unhandled_input`：`KEY_P` → `_enter_battle()`（B1/B2 由 Settings 分流；先经 `GameSession.prepare_world_entry` —— 同身份（种子+起点）有档案则恢复进度，无则新开并 `open_battle` 登记）；`KEY_O` → HUD 战场列表面板（`battlefield_picked` → `_enter_battlefield(path)`，固定 B2）；`KEY_E`（非战斗时）→ `_open_map_editor()`。
- 编辑器保存的 JSON 进入 `res://data/battlefields/` 或 `user://battlefields/`，立即出现在 O 列表与 Game 列表。

## 构建与导出

- **无构建步骤**：Godot 项目即开即运行（GDScript 解释执行）。
- **导出**：`.gitignore` 排除 `/builds/`、`/exports/`、`/android/`。无 `export_presets.cfg`。打正式包时建议在排除清单加 `addons/at-icons/node*/`、`animation/`、`mesh/` 等未用色系目录（编辑器 UI 只用 `control/` 一组）。

## 运行时初始化注意

- **流式窗口**：`stream_extent`（默认 32）决定玩家周围多少格被实例化；移动时增量生成/释放。整个世界**永不预先生成**。
- **视角旋转是相机行为**：旋转（Z/Q/←、X/E/→、中键拖拽）只旋转 `Camera3D`，地形与生态状态不重建；`R` 复位视角、`Ctrl+R` 重新生成世界（新种子）、`F` 复位缩放。
- **截图退出**：`_shot_and_quit()` 提供运行后截图即退出的能力（生成 README 截图 / 测试用）。
