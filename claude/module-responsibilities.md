# 模块职责

本仓库是**单体 Godot 游戏**。带 `plugin.cfg` 的独立模块只有 `addons/` 下 3 个 vendored 插件（breakpoint_mcp / panku_console / at-icons，后者未启用插件）。下表按**源码子域**划分职责，对应 `scripts/` 下的目录（75 个 .gd），全部归属同一个 Godot 项目。

## 子域总览

| 子域 | 目录 | 职责一句话 | 关键脚本 |
| --- | --- | --- | --- |
| **世界引擎（中枢）** | 根 `main.gd` | 等距世界根节点：流式生成、坐标变换、玩家、动物、生态渲染、3D 相机与视角、HUD、天气/昼夜/阳光、战斗与编辑器入口 | `main.gd`（4099 行 / 174 函数） |
| 世界生成 | `scripts/world/`（12 .gd） | 噪声 / Voronoi / 地形采样 / 群系模块 / cell 上下文与状态 / 确定性 RNG / 材质注册 / 大地图快照 | `terrain_sampler.gd`, `biomes/`, `cell_context.gd`, `cell_state.gd`, `deterministic_rng.gd`, `terrain_material_registry.gd`, `map_snapshot_renderer.gd` |
| 生态 | `scripts/ecology/`（9 .gd） | 群落解析、注册表、成员组合、运行时/状态存储、环境生物(鸟/萤火虫) | `ecology_registry.gd`, `ecology_resolver.gd`, `community_runtime.gd`, `community_spawner.gd`, `community_state_store.gd`, `member_composer.gd`, `ambient_registry.gd` |
| 动物行为 | `scripts/animals/` | 动物行为栈（水域偏好/避雪/嗜雪/群体/避人）的可组合注册表 | `animal_behavior_registry.gd` |
| 战棋核心（纯逻辑） | `scripts/core/`（10 .gd） | 战棋数据 / 规则 / 地形适配 / 世界→chapter 适配 / **JSON 战场加载** | `enums.gd`, `unit.gd`, `professions.gd`, `skills.gd`, `items.gd`, `weapons.gd`, `terrain.gd`, `cmd_args.gd`, `world_to_chapter.gd`, `battlefield_loader.gd` |
| 战棋系统 | `scripts/systems/`（8 .gd） | 战斗结算各子系统（全静态或独立 Node） | `grid_system.gd`, `combat_system.gd`, `skill_system.gd`, `item_system.gd`, `buff_system.gd`, `turn_manager.gd`, `enemy_ai.gd`, `player_ai.gd` |
| 等距/3D 渲染层 | `scripts/iso/`（8 .gd） | 主世界 3D 投影/相机/地形 + 战棋等距坐标 + **JSON 战场等距方块渲染器** | `iso_projection_3d.gd`(2:1 dimetric 3D 投影), `isometric_camera_3d.gd`(正交相机), `isometric_terrain_3d.gd`(chunk 3D 柱地形), `battlefield_renderer.gd`(B2/编辑器共用), `iso_coords.gd`(B1/B2 2D 等距), `iso_board.gd`(纯相机/坐标), `unit_sprite.gd`(高度感知站位), `profession_visual.gd` |
| 战棋场景编排 | `scripts/scenes/`（5 .gd）+ `scripts/battle/`（3 .gd） | 战斗/标题/编辑器场景生命周期，UI / 范围层 / 回合编排助手 | `scenes/battle.gd`, `scenes/title.gd`, `scenes/map_editor.gd`, `scenes/isometric_3d_test.gd`, `scenes/scene_args.gd`, `battle/battle_ui.gd`, `battle/range_overlay.gd`, `battle/turn_director.gd` |
| **战场编辑器** | `scripts/editor/`（3 .gd） | 编辑器文档模型（种子生成/JSON 往返/校验）+ 等距方块画布 | `battlefield_doc.gd`, `editor_canvas.gd`, `tile_preview.gd` |
| 世界表现系统 | `scripts/`（散落根，14 .gd） | 天气 / 昼夜 / **阳光阴影** / 景深 / 世界音频 / 萤火虫 / 游荡动物 / 等距批量绘制与深度排序 / **视角控制器** | `weather_system.gd`, `day_night_system.gd`, `sunlight_system.gd`, `depth_of_field_system.gd`, `world_audio_system.gd`, `firefly_field.gd`, `wandering_animal.gd`, `isometric_column_batch.gd`, `isometric_depth_sort.gd`, `isometric_view.gd`(离散视角) |
| UI / 地图 | `scripts/`（散落根） | 左侧图标按钮 HUD（战场面板/设置）/ 小地图 / 大地图叠加 | `game_hud.gd`, `world_map_overlay.gd` |
| 调试命令 | `scripts/debug_console_commands.gd` | Panku 控制台 `dbg.*` 命令集（入口转发 + 只读查询，零业务逻辑） | — |
| 自测 | `tests/` + `scripts/tests/` | headless 契约测试（37 个）与战棋逻辑自测 | 见 `testing-and-quality.md` |
| 调试桥（vendored） | `addons/breakpoint_mcp/` | loopback JSON 桥接编辑器(9080)/运行时(9081)给 MCP host | 独立 `CLAUDE.md` |
| 调试控制台（vendored） | `addons/panku_console/` | 上游 v1.7.9；游戏内 `~` 表达式 REPL（autoload `Panku`） | — |
| 图标库（vendored） | `addons/at-icons/` | 上游 v1.6.0 SVG 图标（700+，编辑器 UI 用 `control/` 色系）；插件未启用 | — |

## 两条数据流（理解全局必读）

### A. 世界 / 生态数据流（探索模式）

```
玩家位置变化
 → _update_streaming()：流式窗口内 _spawn_cell / _free_cell
   → _sample_cell_context(cell)：TerrainSampler 采样得到 CellContext
   → 生态解析：EcologyResolver 应用所有 habitat 匹配的 community
   → CellState（flora / 水体块 / 材质决策）→ IsometricTerrain3D chunk / ColumnBatch 渲染
   → 动物：CommunitySpawner 生成 WanderingAnimal（AnimatedSprite3D + 行为栈）
   → 3D 表现：IsometricCamera3D（旋转/缩放）+ SunlightSystem + weather / dof / audio / fireflies
```

### B. 战棋数据流（按 P / O / E 进入）

```
main.gd._unhandled_input
 ├─ KEY_P → _enter_battle()
 │    → WorldToChapter.world_to_chapter(_terrain_sampler, _player_cell, 10, seed)
 │    → inline_mode ? _enter_battle_inline(chapter)   # B1：add_child(battle.gd)，相机归 main.gd
 │                : change_scene_to_file(Battle.tscn)  # B2：世界地形独立场景
 ├─ KEY_O → HUD BattlefieldPanel → battlefield_picked(path) → _enter_battlefield(path)
 │    → BattlefieldLoader.load_battlefield(path) 产出与 world_to_chapter 同构的 chapter
 │    → 固定走 B2（JSON 战场地形与世界无关）
 └─ KEY_E → _open_map_editor() → MapEditor.tscn
      → BattlefieldDoc.generate(seed)/to_json_dict() ⇄ EditorCanvas（BattlefieldRenderer 渲染）
      → 保存产出 data/battlefields/*.json（user://battlefields/ 亦可），立即进 O 列表

battle.gd._ready 读 SceneArgs.battle_args{chapter, world, return_to}
   → GridSystem + TurnManager + 单位 + IsoBoard/BattlefieldRenderer + UnitSprite + RangeOverlay + BattleUI
   → 状态机 Mode(IDLE/UNIT_SELECTED/MOVING/MENU/ENEMY_TURN/ANIMATING) → TurnDirector 编排 AI
 → battle_finished(result) → B1: main.gd._exit_battle 恢复；B2: change_scene(return_to)
```

## `main.gd` 内部职责分区（按函数簇，行号为近似定位）

| 行段 | 职责簇 | 代表函数 |
| --- | --- | --- |
| 1–241 | 常量 / preload / B1 战斗与视角字段声明 | `TILE_W/H`, `ZOOM_LEVELS`, `_BattleScript`，B1 字段（205 起） |
| 242–950 | 生态配置加载与编译 + 校验 | `_load_ecosystem_config`, `_compile_ecosystem_config`, `_validate_ecosystem_config`, `_compile_animal_behavior_stacks` |
| 951–1044 | 启动与重生成 | `_ready`, `_regenerate`（Ctrl+R 触发） |
| 1045–1147 | 地形生成核心 | `_sample_cell_context`, `_hash_u32`, `_voronoi`, `_modules`, `_quantize`, `_biome` |
| 1148–1312 | 流式生成 / cell 释放 | `_spawn_cell`, `_free_cell`, `_update_streaming`, `_in_stream` |
| 1313–1350 | 坐标变换 / 视角投影 / 排序 | `_grid_to_world`(→Vector3), `_grid_to_screen`, `_column_sort_y`, `_refresh_view_projection` |
| ~1350–2340 | 材质 / 纹理 / 植被与动物生成 / 环境生物 | `_pick_species`, `_flora_candidates_for_cell`, `_place_flora`, `_spawn_ambient_for_cell`, `_create_animal_group` |
| 2344–3009 | 动物群体 / 行为 / 移动 | `_animal_group_spawn_cells`, `_spawn_animal`(→AnimatedSprite3D), `_update_animals`, `_animal_behavior_decision` |
| 3010–3076 | 水体 / 水下纹理 | `_make_water_face_texture`, `_make_underwater_ground_texture` |
| 3077–3359 | 玩家渲染 / 遮挡 / 移动 / 主循环 | `_setup_player`, `_update_player_occlusion`, `_try_move`, `_process` |
| 3360–3434 | 小地图 | `_setup_minimap`, `_reveal`, `_map_color_for_context` |
| 3435–3502 | 相机 / HUD / 大地图 | `_setup_camera`(3D), `_setup_hud`, `_setup_world_map`, `_handle_world_map_input` |
| 3503–3593 | 输入分发（视角旋转/缩放/快捷键） | `_unhandled_input`（Z/Q/← 与 X/E/→ 旋转、R 复位、Ctrl+R 重生成、F 复位缩放、T/N/B/O/E/P） |
| 3594–3749 | 表现层系统装配 | `_setup_day_night`(同时创建 SunlightSystem), `_setup_depth_of_field`, `_setup_audio`, `_setup_fireflies`, `_setup_weather` |
| 3750–3792 | 缩放 / 相机位置 / 截图 | `_zoom_step`, `_apply_zoom`, `_set_camera_position`, `_shot_and_quit` |
| 3793–3842 | HUD 面板与文本刷新 | — |
| 3843–4098 | **战棋 / 战场 / 编辑器入口 + B1 相机与拾取** | `_enter_battle`, `_enter_battlefield`, `_on_battlefield_picked`, `_open_map_editor`, `_enter_battle_inline`, `_exit_battle`, `_handle_battle_camera_input`, `_update_battle_edge_pan`, `cell_stand_level`, `screen_to_cell` |

## 战棋子系统的依赖方向

```
scripts/core/  （纯逻辑，被所有人依赖；battlefield_loader 也在此层）
     ▲
scripts/systems/  （调用 core，被 battle.gd / editor 调用）
     ▲
scripts/iso/ + scripts/battle/ + scripts/editor/  （渲染层与场景助手）
     ▲
scripts/scenes/battle.gd / map_editor.gd  （编排者）
     ▲
main.gd._enter_battle* / _enter_battlefield / _open_map_editor  （世界侧入口）
```

`world_to_chapter.gd` 是**世界 ↔ 战棋的唯一耦合点**（读 TerrainSampler/CellContext，输出 chapter Dictionary）。`battlefield_loader.gd` 是 JSON 战场侧的平行入口，输出与 world_to_chapter 同构的 chapter，二者互不依赖。
