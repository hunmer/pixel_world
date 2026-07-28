# 模块职责

本仓库是**单体 Godot 游戏**，没有多个 `package.json` / `plugin.cfg` 级别的子模块工作区（唯一带 `plugin.cfg` 的是 vendored 的 `addons/breakpoint_mcp`）。下表按**源码子域**划分职责，对应 `scripts/` 下的目录，全部归属同一个 Godot 项目。

## 子域总览

| 子域 | 目录 | 职责一句话 | 关键脚本 |
| --- | --- | --- | --- |
| **世界引擎（中枢）** | 根 `main.gd` | 等距世界根节点：流式生成、坐标变换、玩家、动物、生态渲染、相机、HUD、战斗入口 | `main.gd`（3886 行） |
| 世界生成 | `scripts/world/` | 噪声 / Voronoi / 地形采样 / 群系模块 / cell 上下文与状态 / 确定性 RNG / 材质注册 | `terrain_sampler.gd`, `biomes/`, `cell_context.gd`, `cell_state.gd`, `deterministic_rng.gd` |
| 生态 | `scripts/ecology/` | 群落解析、注册表、成员组合、运行时/状态存储、环境生物(鸟/萤火虫) | `ecology_registry.gd`, `ecology_resolver.gd`, `community_runtime.gd`, `community_spawner.gd`, `community_state_store.gd`, `member_composer.gd`, `ambient_registry.gd` |
| 动物行为 | `scripts/animals/` | 动物行为栈（水域偏好/避雪/嗜雪/群体/避人）的可组合注册表 | `animal_behavior_registry.gd` |
| 战棋核心（纯逻辑） | `scripts/core/` | 战棋数据 / 规则 / 地形适配，概念上零渲染依赖（迁移自 phaserjs） | `enums.gd`, `unit.gd`, `professions.gd`, `skills.gd`, `items.gd`, `weapons.gd`, `terrain.gd`, `cmd_args.gd`, `world_to_chapter.gd` |
| 战棋系统 | `scripts/systems/` | 战斗结算各子系统（全静态或独立 Node） | `grid_system.gd`, `combat_system.gd`, `skill_system.gd`, `item_system.gd`, `buff_system.gd`, `turn_manager.gd`, `enemy_ai.gd`, `player_ai.gd` |
| 战棋渲染层 | `scripts/iso/` | 2D 等距棋盘 / 单位立绘 / 坐标变换（从 3D 重写） | `iso_coords.gd`, `iso_board.gd`, `unit_sprite.gd`, `profession_visual.gd` |
| 战棋场景编排 | `scripts/scenes/` + `scripts/battle/` | 战斗场景生命周期 / 状态机 / 输入，及抽出的 UI / 范围层 / 回合编排助手 | `scenes/battle.gd`, `scenes/title.gd`, `scenes/scene_args.gd`, `battle/battle_ui.gd`, `battle/range_overlay.gd`, `battle/turn_director.gd` |
| 世界表现系统 | `scripts/`（散落根） | 天气 / 昼夜 / 景深 / 世界音频 / 萤火虫 / 游荡动物 / 等距批量绘制与深度排序 | `weather_system.gd`, `day_night_system.gd`, `depth_of_field_system.gd`, `world_audio_system.gd`, `firefly_field.gd`, `wandering_animal.gd`, `isometric_column_batch.gd`, `isometric_depth_sort.gd` |
| UI / 地图 | `scripts/`（散落根） | 顶部 HUD / 小地图 / 大地图叠加 | `game_hud.gd`, `world_map_overlay.gd`, `world/world_map_overlay_renderer?`(见文件清单) |
| 自测 | `tests/` + `scripts/tests/` | headless 契约测试与战棋逻辑自测 | 见 `testing-and-quality.md` |
| 调试桥（vendored 第三方） | `addons/breakpoint_mcp/` | loopback JSON 桥接 Godot 编辑器/运行时给 MCP host | 独立 `CLAUDE.md` |

## 两条数据流（理解全局必读）

### A. 世界 / 生态数据流（探索模式）

```
玩家位置变化
 → _update_streaming()：流式窗口内 _spawn_cell / _free_cell
   → _sample_cell_context(cell)：TerrainSampler 采样得到 CellContext
     （biome / landform / elevation / water_depth / shoreline / surface）
   → 生态解析：EcologyResolver 应用所有 habitat 匹配的 community
   → CellState（含 flora / fauna 决策）→ 等距批量渲染（ColumnBatch）
   → 动物：CommunitySpawner 生成 WanderingAnimal（带行为栈 + 逃跑/群体）
   → 表现层：weather / day_night / dof / audio / fireflies 各自 update
```

### B. 战棋数据流（按 P 进入战斗）

```
main.gd._unhandled_input 收到 KEY_P
 → _enter_battle()
   → WorldToChapter.world_to_chapter(_terrain_sampler, _player_cell, 10, seed)
     （cell_context_to_terrain: water/mountain/plain；_find_nearest_land；_is_standable）
   → 若 Settings.battle_inline_mode:
       _enter_battle_inline(chapter)  # 备份相机/zoom/玩家可见性，add_child(battle.gd)
     否则:
       change_scene_to_file(Battle.tscn)  # B2 独立场景
 → battle.gd._ready 读 SceneArgs.battle_args{chapter, world, return_to}
   → GridSystem + TurnManager + 单位 + IsoBoard/UnitSprite + RangeOverlay + BattleUI
   → 状态机 Mode(IDLE/UNIT_SELECTED/MOVING/MENU/ENEMY_TURN/ANIMATING)
   → TurnDirector 编排敌方 AI / 玩家托管
 → 战斗结束 battle.gd 发 battle_finished(result)
   → B1: main.gd._exit_battle 恢复相机/玩家/输入
   → B2: change_scene(return_to_scene)
```

## `main.gd` 内部职责分区（按函数簇，行号为近似定位）

`main.gd` 是单文件巨石，按函数簇可读出内部分区（无 `#region` 标记，以下为归纳）：

| 行段 | 职责簇 | 代表函数 |
| --- | --- | --- |
| 1–230 | 常量 / preload / 战棋字段声明 | `const TILE_W/H`, `ZOOM_LEVELS`, `_BattleScript` |
| 228–935 | 生态配置加载与编译 + 校验 | `_load_ecosystem_config`, `_compile_ecosystem_config`, `_validate_ecosystem_config`, `_compile_animal_behavior_stacks` |
| 937–1092 | 启动与地形核心 | `_ready`, `_regenerate`, `_sample_cell_context`, `_quantize`, `_biome`, `_modules`, `_landform_type`, `_voronoi` |
| 1135–1290 | 流式生成 / cell 释放 | `_spawn_cell`, `_free_cell`, `_update_streaming`, `_in_stream` |
| 1293–1335 | 坐标变换与深度排序 | `_grid_to_screen`, `_column_sort_y`, `_ensure_sort_origin` |
| 1341–1905 | 材质 / 纹理 / 植被候选与放置 | `_is_beach`, `_desert_surface_kind`, `_pick_species`, `_flora_candidates_for_cell`, `_place_flora` |
| 1906–2600 | 环境生物 / 动物生成与生命周期 | `_spawn_ambient_for_cell`, `_spawn_fauna_for_stream`, `_create_animal_group`, `_spawn_animal`, `_underwater_animal_material_for_depth` |
| 2607–2970 | 动物行为与移动 | `_update_animals`, `_begin_animal_move`, `_animal_move_score`, `_animal_behavior_decision`, `_animal_social_center` |
| 2969–3235 | 水体纹理 / 玩家渲染与遮挡 | `_make_water_face_texture`, `_setup_player`, `_update_player_occlusion` |
| 3239–3530 | 输入 / 主循环 / 小地图 / 大地图 | `_input_dir`, `_try_move`, `_process`, `_setup_minimap`, `_unhandled_input` |
| 3533–3700 | 表现层系统装配 | `_setup_day_night`, `_setup_weather`, `_setup_audio`, `_setup_fireflies`, `_setup_depth_of_field` |
| 3702–3790 | 相机 / 截图 | `_zoom_step`, `_apply_zoom`, `_snap_camera_position`, `_shot_and_quit` |
| 3792–3887 | **战棋入口（B1/B2）** | `_enter_battle`, `_enter_battle_inline`, `_exit_battle`, `_handle_battle_input`, `cell_stand_level`, `screen_to_cell` |

## 战棋子系统的依赖方向

```
scripts/core/  （纯逻辑，被所有人依赖）
     ▲
scripts/systems/  （调用 core，被 battle.gd 调用）
     ▲
scripts/iso/ + scripts/battle/  （渲染层与场景助手，调用 systems + core）
     ▲
scripts/scenes/battle.gd  （编排者，组合上述三者）
     ▲
main.gd._enter_battle*  （世界侧入口，通过 world_to_chapter 适配 + SceneArgs 注入）
```

`world_to_chapter.gd` 是**世界 ↔ 战棋的唯一耦合点**：它读取世界的 `TerrainSampler` / `CellContext`，输出战棋 `chapter`（StringName 二维地形矩阵 + 单位）。除此之外两个子系统互不感知。
