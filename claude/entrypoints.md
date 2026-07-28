# 入口与启动

## 引擎入口

- **`project.godot`** — Godot 工程配置。
  - `run/main_scene = "res://main.tscn"` → 直接运行项目时进入世界（**主入口**）。
  - `[autoload]` 注册 3 个全局单例（启动即存在，跨场景存活）：
    | Autoload | 脚本 | 作用 |
    | --- | --- | --- |
    | `SceneArgs` | `scripts/scenes/scene_args.gd` | 跨场景传参暂存（`battle_args`、`pending_level_id`） |
    | `Settings` | `scripts/settings.gd` | 用户偏好，`ConfigFile` 持久化到 `user://settings.cfg`（`battle_inline_mode`） |
    | `BreakpointRuntimeBridge` | `addons/breakpoint_mcp/runtime_bridge.gd`（uid） | 调试运行时桥（插件启用时） |
  - `[input]` 定义 `confirm`(Z/Enter)、`cancel`(Esc)、`end_turn`(E) —— 供战棋 UI 用。
  - `[display]` 视口 1280×800，`stretch/mode = "canvas_items"`。
  - `[rendering]` `gl_compatibility`（桌面 + 移动），像素级 2D snap 开启。

## 场景入口

| `.tscn` | 脚本 | 角色 | 进入方式 |
| --- | --- | --- | --- |
| `main.tscn` | `main.gd` | 世界根场景（Node2D） | `project.godot` 主场景；`Title` 的"进入世界"按钮 |
| `scenes/Title.tscn` | `scripts/scenes/title.gd` | 标题屏（Control） | （可选，非默认主场景）按钮 → `change_scene_to_file("res://main.tscn")` |
| `scenes/Battle.tscn` | `scripts/scenes/battle.gd` | 战斗独立场景（B2） | `Settings.battle_inline_mode=false` 时按 P 触发 |
| `scenes/SkillTest.tscn` | `scripts/tests/test_skills.gd` | 技能/物品自测场景 | 编辑器手动运行（headless 测试入口） |

> 注意：`main.tscn` 内容极简（仅一个挂 `main.gd` 的 Node2D），几乎所有子节点由 `main.gd._ready()` **程序化创建**。

## main.gd 启动流程（`_ready` @ 937）

```
_ready()
 ├─ 读 @export 参数（seed=0 随机, stream_extent=32, sight_radius=12, move_time, ...）
 ├─ _load_ecosystem_config() + _compile_ecosystem_config()
 │     （加载 config/ecosystems.json + config/ecology/manifest.json，编译为运行时结构）
 ├─ _compile_animal_behavior_stacks()  （组合动物行为注册表）
 ├─ _validate_ecosystem_config()        （启动期配置校验，失败则 abort）
 ├─ 装配子系统：_setup_player / _setup_camera / _setup_hud / _setup_world_map
 │              _setup_day_night / _setup_depth_of_field / _setup_audio
 │              _setup_fireflies / _setup_weather
 ├─ _regenerate(seed)                    （首次地形生成 + 流式）
 └─ 进入主循环 _process / _unhandled_input
```

`_regenerate(new_seed)` 清理旧 cell/动物，重置 RNG，触发首轮 `_update_streaming`。

## 战斗入口（按 P）

详见 `module-responsibilities.md` 的"战棋数据流"。关键：`main.gd._unhandled_input` 监听 `KEY_P` → `_enter_battle()`，根据 `Settings.battle_inline_mode` 分流 B1（`_enter_battle_inline`）/ B2（`change_scene_to_file`）。

## 构建与导出

- **无构建步骤**：Godot 项目即开即运行，无 npm / make / 编译阶段（GDScript 解释执行）。
- **导出**：`.gitignore` 排除 `/builds/`、`/exports/`、`/android/`，说明有导出产物但不在仓库。本索引未发现导出预设文件（`export_presets.cfg`），如需导出需在编辑器配置。

## 运行时初始化注意

- **流式窗口**：`stream_extent`（默认 32）决定玩家周围多少格被实例化；移动时 `_update_streaming` 增量生成/释放。整个世界**永不预先生成**。
- **相机平滑**：`camera_smoothing_speed`（8.0），像素安全（`2d/snap/snap_2d_transforms_to_pixel=true`）。
- **截图退出**：`_shot_and_quit()` 提供运行后截图即退出的能力（疑似用于生成 README 截图 / 测试）。
