# 入口与启动

> 更新：2026-11-15（第二轮增量：编辑器能力扩充——区域操作/预设/取色器；autoload 与场景数不变 8/11）。

## 引擎入口

- **`project.godot`** — Godot 工程配置。
  - `run/main_scene = "res://scenes/Game.tscn"` → 直接运行项目时进入**战旗会话入口**（默认自动续玩最近战旗，可被 `config/startup.cfg` 改为其他场景，见下）。
  - `[autoload]` 注册 **8 个**全局单例（启动即存在，跨场景存活）：
    | Autoload | 脚本 | 作用 |
    | --- | --- | --- |
    | `SceneArgs` | `scripts/scenes/scene_args.gd` | 跨场景传参暂存（`battle_args`、`pending_level_id`、`map_editor_return_to`） |
    | `GameSession` | `scripts/scenes/game_session.gd` | 战旗会话路由：启动决策（`--battlefield` > 最近存档 > 默认 plains_skirmish）、稳定身份、分战场存档提交（详见下节） |
    | `Settings` | `scripts/settings.gd` | 用户偏好，`ConfigFile` 持久化到 `user://settings.cfg`（`battle_inline_mode` 等） |
    | `GameCursor` | `scripts/game_cursor.gd` | 全局游戏光标（纹理切换 / 战斗态光标） |
    | `Sfx` | `scripts/audio/game_sfx.gd` | 全局音效池：UI/战斗/回合/胜负/脚步；按钮声经 `node_added` 自动挂接 |
    | `LoadingScreen` | `scenes/LoadingScreen.tscn`（脚本 `scripts/ui/loading_screen.gd`） | 全局加载遮罩（幂等 show/hide；同步重活前弹一层反馈） |
    | `BreakpointRuntimeBridge` | `addons/breakpoint_mcp/runtime_bridge.gd`（uid） | 调试运行时桥（loopback 9081，插件启用时） |
    | `Panku` | `addons/panku_console/console.tscn` | 运行时调试控制台（`~` 呼出表达式 REPL） |
  - `[editor_plugins]` 启用：`breakpoint_mcp`、`panku_console`（at-icons、pixelfx 已 vendored 但插件未启用）。
  - `[input]` 定义 `confirm`(Z/Enter)、`cancel`(Esc)、`end_turn`(E) —— 供战棋 UI 用。
  - `[display]` 视口 1280×800，`stretch/mode = "canvas_items"`。
  - `[physics]` `3d/physics_engine = "Jolt Physics"`（3D 正交迁移后真实使用）。
  - `[rendering]` `gl_compatibility`。

- **运行环境**：Godot 4.7.2 stable。**本机（macOS）**：`/Applications/Godot.app/Contents/MacOS/Godot`；Windows 历史路径 `D:/Godot/Godot_v4.7.2-stable_win64.exe`（console 版 stdout 全缓冲）。项目历史路径 G:/ → E:/ → 当前 `/Users/Zhuanz/Documents/pixel_world`。

## 调试启动配置（`config/startup.cfg`，2026-11-14 新增）

`docs/startup_config.md` 是权威文档。要点：

- `[startup]` 三键：`auto_open_last_scene` / `last_scene` / `excluded_scenes`。
- 编辑器与本机调试读写 `res://config/startup.cfg`；导出后读写 `user://startup.cfg`。
- F5 默认入口 = `Game.tscn`；`auto_open_last_scene=true` 时启动直接跳 `last_scene`（当前默认 `Title.tscn`；切换场景时自动记录，`SkillTest` / `UIComponentGallery` 默认排除）。
- 显式 `--battlefield` / `--reset-battle` 参数优先于该配置；`Game.tscn` 中转不算最近场景。
- 只恢复入口，不恢复编辑器未保存内容 / 世界位置 / 战斗进度（战斗进度归 `user://battle_saves/`）。

## 场景入口（11 个 .tscn + 1 探针）

| `.tscn` | 脚本 | 角色 | 进入方式 |
| --- | --- | --- | --- |
| `scenes/Game.tscn` | `scripts/scenes/game_entry.gd` | **默认主入口**：冷启动自动续玩最近战旗；从战斗返回时显示战场列表 | `project.godot` 主场景；`Title` 的"开始"按钮；受 `startup.cfg` 影响 |
| `main.tscn` | `main.gd` | 世界根场景（Node2D "Main" + 子节点 "DebugConsoleCommands"） | `Game` 列表的"生态世界"按钮；`startup.cfg` 指定；编辑器手动运行 |
| `scenes/Title.tscn` | `scripts/scenes/title.gd` | 标题屏（Control） | `startup.cfg` 默认 `last_scene`；手动运行 |
| `scenes/Battle.tscn` | `scripts/scenes/battle.gd` | 战斗独立场景（B2，世界地形） | `inline_mode=false` 按 P；**JSON 战场固定走此场景**（O 键选择） |
| `scenes/MapEditor.tscn` | `scripts/scenes/map_editor.gd` | 战场地图编辑器（画笔/填充/橡皮/角色/replace + 区域复制-移动-命名预设 + 取色器 + 用户素材） | 世界内按 `E`；HUD 按钮；依赖编辑器参数，一般不直启 |
| `scenes/LoadingScreen.tscn` | `scripts/ui/loading_screen.gd` | 加载遮罩（**autoload，不作为普通场景运行**） | `LoadingScreen.show_loading()` 代码调用 |
| `scenes/SkillTest.tscn` | `scripts/tests/test_skills.gd` | 技能/物品自测场景 | 编辑器手动运行（headless 测试入口） |
| `scenes/UIComponentGallery.tscn` | `scripts/scenes/ui_component_gallery.gd` | UI 组件库交互画廊（16 组件，六页） | F6 独立运行；ESC 退出；默认排除出 startup 记录 |
| `scenes/PixelFxGallery.tscn` | `scripts/scenes/pixelfx_gallery.gd` | PixelFx 特效画廊 | 手动运行 |
| `scenes/DialogueDemo.tscn` | `scripts/scenes/dialogue_demo.gd` | 分支对话演示（`data/dialogue/demo_intro.json`） | 手动运行 |
| `scenes/HomeEntry.tscn` | `scripts/scenes/home_entry.gd` | 主页占位入口 | 手动运行 |
| `scenes/Isometric3DTest.tscn` | `scripts/scenes/isometric_3d_test.gd` | 最小 3D 柱网格 + 90° 相机旋转验证 | 编辑器手动运行 |
| `tests/flat_rotation_probe.tscn` | `tests/flat_rotation_probe.gd` | 平地旋转探针 | 调试用 |

> 注意：`main.tscn` 极简（Node2D + main.gd + DebugConsoleCommands），几乎所有子节点由 `main.gd._ready()` **程序化创建**。`Battle.tscn` 依赖 `SceneArgs.battle_args`，**不能直接运行**。

## main.gd 启动流程（`_ready` @ 975）

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
- **战斗内演出**：战斗设置页（`battle/battle_settings_tab.gd`）可开沉浸相机等表现开关；沉浸运镜预热时先弹 `LoadingScreen`（`battle.gd` @1238 一带）。

## 构建与导出

- **无构建步骤**：Godot 项目即开即运行（GDScript 解释执行）。
- **导出**：`.gitignore` 排除 `/builds/`、`/exports/`、`/android/`。无 `export_presets.cfg`。打正式包时建议在排除清单加 `addons/at-icons/node*/` 等未用色系目录，以及 `docs/`、`story/`、`tests/`、`plans/`。

## 运行时初始化注意

- **流式窗口**：`stream_extent`（默认 32）决定玩家周围多少格被实例化；移动时增量生成/释放。整个世界**永不预先生成**。
- **视角旋转是相机行为**：旋转（Z/Q/←、X/E/→、中键拖拽）只旋转 `Camera3D`，地形与生态状态不重建；`R` 复位视角、`Ctrl+R` 重新生成世界（新种子）、`F` 复位缩放。
- **截图退出**：`_shot_and_quit()` 提供运行后截图即退出的能力（生成 README 截图 / 测试用）。
- **首次 headless 运行**会先做资源导入，耗时偏长属正常（macOS 本机已验证）。
