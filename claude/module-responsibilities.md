# 模块职责

> 更新：2026-11-15（第二轮增量：scripts 113→122 .gd；新增编辑器区域剪贴板/预设、增援刷入、单位交换；ui 组件 16→22）。

本仓库是**单体 Godot 游戏**。带 `plugin.cfg` 的独立模块只有 `addons/` 下 4 个 vendored 插件（breakpoint_mcp / panku_console / at-icons / pixelfx，后两者插件未启用）。下表按**源码子域**划分职责，对应 `scripts/`、`ui/` 下的目录（合计 122 + 23 .gd），全部归属同一个 Godot 项目。

## 子域总览

| 子域 | 目录 | 职责一句话 | 关键脚本 |
| --- | --- | --- | --- |
| **世界引擎（中枢）** | 根 `main.gd` | 等距世界根节点：流式生成、坐标变换、玩家、动物、生态渲染、3D 相机与视角、HUD、天气/昼夜/阳光、战斗与编辑器入口 | `main.gd`（4319 行 / 176 函数） |
| 世界生成 | `scripts/world/`（12 .gd） | 噪声 / Voronoi / 地形采样 / 群系模块 / cell 上下文与状态 / 确定性 RNG / 材质注册 / 大地图快照 | `terrain_sampler.gd`, `biomes/`, `cell_context.gd`, `cell_state.gd`, `deterministic_rng.gd`, `terrain_material_registry.gd`, `map_snapshot_renderer.gd` |
| 生态 | `scripts/ecology/`（9 .gd） | 群落解析、注册表、成员组合、运行时/状态存储、环境生物(鸟/萤火虫) | `ecology_registry.gd`, `ecology_resolver.gd`, `community_runtime.gd`, `community_spawner.gd`, `community_state_store.gd`, `member_composer.gd`, `ambient_registry.gd` |
| 动物行为 | `scripts/animals/` | 动物行为栈（水域偏好/避雪/嗜雪/群体/避人）的可组合注册表 | `animal_behavior_registry.gd` |
| 战棋核心（纯逻辑） | `scripts/core/`（14 .gd） | 战棋数据 / 规则 / 地形适配 / 世界→chapter 适配 / JSON 战场加载（含 victory/reinforcements 解析）/ **战旗存档编解码与落盘** / **按回合增援刷入** / 用户素材布局 | `enums.gd`, `unit.gd`, `professions.gd`, `skills.gd`, `items.gd`, `weapons.gd`, `terrain.gd`, `cmd_args.gd`, `world_to_chapter.gd`, `battlefield_loader.gd`, `battle_save_codec.gd`, `battle_save_store.gd`, `block_layout.gd`, `reinforcement_spawner.gd` |
| 战棋系统 | `scripts/systems/`（12 .gd） | 战斗结算各子系统（全静态或独立 Node）+ **AI 难度分级** + 攻击事件结构 + **注入式胜利判定** + **相邻单位交换** | `grid_system.gd`, `combat_system.gd`, `skill_system.gd`, `item_system.gd`, `buff_system.gd`, `turn_manager.gd`(`check_victory`), `enemy_ai.gd`, `player_ai.gd`, `ai_difficulty.gd`, `ai_difficulty_scoring.gd`, `attack_event.gd`, `trade_system.gd` |
| 等距/3D 渲染层 | `scripts/iso/`（11 .gd） | 主世界 3D 投影/相机/地形 + 战棋等距坐标 + JSON 战场等距方块渲染器 + 角色面板/遮挡/相机导航 | `iso_projection_3d.gd`, `isometric_camera_3d.gd`, `isometric_terrain_3d.gd`, `battlefield_renderer.gd`, `iso_coords.gd`, `iso_board.gd`, `unit_sprite.gd`, `profession_visual.gd`, `character_sheet.gd`, `battle_occluder.gd`, `world_camera_navigation.gd` |
| 战棋场景编排 | `scripts/scenes/`（12 .gd）+ `scripts/battle/`（10+automation 3 .gd） | 战斗/标题/编辑器/会话入口场景生命周期，UI / 范围层 / 回合编排 / **沉浸演出** / **声明式自动化**；`map_editor.gd` 已长到 **3285 行 / 150 函数**（区域操作/预设/取色器/移动工具全在此编排） | `scenes/battle.gd`, `scenes/game_entry.gd`, `scenes/game_session.gd`(autoload), `scenes/startup_config.gd`, `scenes/map_editor.gd`, `battle/battle_ui.gd`, `battle/turn_director.gd`, `battle/battle_action_resolver.gd`, `battle/battle_presentation.gd`, `battle/immersive_camera.gd`, `battle/automation/` |
| **战场编辑器** | `scripts/editor/`（11 .gd） | 编辑器文档模型 + 等距方块画布 + **用户素材库面板** + **区域剪贴板内核（五层数据）** + **区域命名预设持久化** + 方块列表/选择弹窗 + 快捷键提示弹窗 | `battlefield_doc.gd`, `editor_canvas.gd`, `tile_preview.gd`, `asset_library_panel.gd`, `block_selector.gd`, `selection_range.gd`, `region_clipboard.gd`, `region_preset_store.gd`, `editor_block_list.gd`, `editor_block_picker_dialog.gd`, `shortcut_hints_dialog.gd` |
| **用户素材系统** | `scripts/assets/`（3 .gd） | 本地导入（sha256 去重 blob）/ 网络清单拉取校验 / 素材→渲染适配（`docs/user_assets.md`） | `user_asset_service.gd`, `user_asset_catalog.gd`, `user_asset_visual_adapter.gd` |
| **音效** | `scripts/audio/game_sfx.gd` | autoload `Sfx`：UI/战斗/回合/胜负/脚步音效池，按钮声经 `SceneTree.node_added` 自动挂接 | `game_sfx.gd` |
| 世界表现系统 | `scripts/`（散落根，17 .gd） | 天气 / 昼夜 / 阳光阴影 / 景深 / 世界音频 / 萤火虫 / 游荡动物 / 等距批量绘制与深度排序 / 视角控制 / 光标 / 提示条 / 侧栏 | `weather_system.gd`, `day_night_system.gd`, `sunlight_system.gd`, `depth_of_field_system.gd`, `world_audio_system.gd`, `firefly_field.gd`, `wandering_animal.gd`, `isometric_column_batch.gd`, `isometric_depth_sort.gd`, `isometric_view.gd`, `game_cursor.gd`(autoload) |
| UI / 地图 | `scripts/`（散落根）+ `scripts/ui/` | HUD（战场面板/设置）/ 小地图 / 大地图叠加 / 侧栏 / 提示条 / **加载遮罩** | `game_hud.gd`, `world_map_overlay.gd`, `side_panel.gd`, `hint_bar.gd`, `ui/loading_screen.gd` |
| **共享 UI 组件库** | `ui/`（23 .gd） | ComponentTheme（DESIGN.md token 唯一实现）+ 22 个 Pixel* `@tool` 控件（按钮/输入/媒体/菜单 + **六个薄布局容器** VBox/HBox/Grid/Margin/Center/Scroll），复用老 ui_theme/ui_factory（`ui/README.md`、规范见根 `DESIGN.md`） | `ui/theme/component_theme.gd`, `ui/components/pixel_*.gd` |
| 对话系统（演示） | `scripts/scenes/dialogue_demo.gd` + `data/dialogue/` | 分支对话 JSON 演示（尚未接入正式剧情流程） | `dialogue_demo.gd`, `demo_intro.json` |
| 调试命令 | `scripts/debug_console_commands.gd` | Panku 控制台 `dbg.*` 命令集（入口转发 + 只读查询，零业务逻辑） | — |
| 自测 | `tests/` + `scripts/tests/` | headless 契约测试（78 个）、Node 契约（7 项）、战棋自测（2 场景） | 见 `testing-and-quality.md` |
| 调试桥（vendored） | `addons/breakpoint_mcp/` | loopback JSON 桥接编辑器(9080)/运行时(9081)给 MCP host | 独立 `CLAUDE.md` |
| 调试控制台（vendored） | `addons/panku_console/` | 上游 v1.7.9；游戏内 `~` 表达式 REPL（autoload `Panku`） | — |
| 图标库（vendored） | `addons/at-icons/` | 上游 v1.6.0 SVG 图标（700+，编辑器 UI 用 `control/` 色系）；插件未启用 | — |
| 像素特效库（vendored） | `addons/pixelfx/` | v0.3.0，244 个代码绘制特效；战斗伤害/演出特效消费；契约 `tests/pixelfx_contract.gd` | — |

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
       → 区域操作：EditorRegionClipboard.extract/paste/move（五层 payload）；
         命名预设 EditorRegionPresetStore → user://editor_presets/presets.json
       → 保存产出 data/battlefields/*.json（user://battlefields/ 亦可），立即进 O 列表

battle.gd._ready 读 SceneArgs.battle_args{chapter, world, return_to, save_*}
   → GridSystem + TurnManager + 单位 + IsoBoard/BattlefieldRenderer + UnitSprite + RangeOverlay + BattleUI
   → 状态机 Mode(IDLE/UNIT_SELECTED/MOVING/MENU/ENEMY_TURN/ANIMATING) → TurnDirector 编排 AI
   → 敌方回合开始：ReinforcementSpawner.spawn_due 刷到点增援（battle.gd 补 sprite+快照；
     battle_runner.gd 无头链路同点位发 reinforce 事件入战报）
   → 攻击结算出 AttackEvent → BattlePresentation 驱动动画/特效(PixelFx)/音效(Sfx)
     （可选）ImmersiveCamera 沉浸运镜（战斗设置页开关；预热时 LoadingScreen 遮罩）
   → 回合结束 check_victory(enemies+未到点增援, ctx) 判 rout/defend_turns/seize
   → 行动边界 GameSession.commit() 落盘 user://battle_saves/
  → battle_finished(result) → B1: main.gd._exit_battle 恢复；B2: change_scene(return_to)
```

### C. 启动路由数据流（冷启动）

```
project.godot main_scene = scenes/Game.tscn (game_entry.gd)
  → StartupConfig 读 config/startup.cfg（auto_open_last_scene / last_scene / excluded_scenes）
  → GameSession.prepare_entry()：--battlefield > 最近存档(user://battle_saves/) > 默认 plains_skirmish
  → 有档案 → 带 save_state 恢复进 Battle.tscn；否则停在战场列表
  → 列表可选：继续最近 / 选战场 / 重置 / 编辑器 / 生态世界(main.tscn)
```

## `main.gd` 内部职责分区（按函数簇，行号为 2026-11-15 实测近似定位）

| 行段 | 职责簇 | 代表函数（@行号） |
| --- | --- | --- |
| 1–265 | 常量 / preload / B1 战斗与视角字段声明 | `TILE_W/H`, `ZOOM_LEVELS`, `_BattleScript`，B1 字段 |
| 266–542 | 生态配置加载与编译 | `_load_ecosystem_config`@266, `_compile_ecosystem_config`@315, `_compile_animal_behavior_stacks`@500 |
| 543–974 | 配置校验 + 辅助 | `_validate_ecosystem_config`@543 |
| 975–1071 | 启动与重生成 | `_ready`@975, `_regenerate`@1022（Ctrl+R 触发） |
| 1072–1174 | 地形生成核心 | `_sample_cell_context`@1072, `_hash_u32`, `_voronoi`, `_modules`, `_quantize`, `_biome` |
| 1175–1340 | 流式生成 / cell 释放 | `_spawn_cell`@1175, `_free_cell`, `_update_streaming`@1308 |
| 1341–1504 | 坐标变换 / 视角投影 / 排序 | `_grid_to_world`(→Vector3)@1341, `_grid_to_screen`, `_column_sort_y` |
| 1505–2512 | 材质 / 纹理 / 植被与动物生成 / 环境生物 | `_pick_species`@1505, `_flora_candidates_for_cell`, `_place_flora`, `_spawn_ambient_for_cell` |
| 2513–3045 | 动物群体 / 行为 / 移动 | `_spawn_animal`@2513, `_update_animals`@2697, `_animal_behavior_decision` |
| 3046–3120 | 水体 / 水下纹理 / 材质处理 | `_make_water_face_texture`@3046, `_process_terrain_material_texture`@3097 |
| 3121–3462 | 玩家渲染 / 遮挡 / 移动 / 主循环 | `_setup_player`@3121, `_update_player_occlusion`, `_try_move`@3372, `_process`@3401 |
| 3463–3538 | 小地图 | `_setup_minimap`@3463, `_reveal`, `_map_color_for_context` |
| 3539–3607 | 相机 / HUD / 大地图 | `_setup_camera`(3D)@3539, `_setup_hud`@3548, `_setup_world_map`@3559 |
| 3608–3709 | 输入分发（视角旋转/缩放/快捷键） | `_unhandled_input`@3608（Z/Q/← 与 X/E/→ 旋转、R 复位、Ctrl+R 重生成、F 复位缩放、T/N/B/O/E/P） |
| 3710–3865 | 表现层系统装配 | `_setup_day_night`@3710(同时创建 SunlightSystem), `_setup_depth_of_field`, `_setup_audio`@3761, `_setup_fireflies`, `_setup_weather` |
| 3866–3990 | 缩放 / 相机位置 / HUD 刷新 / 截图 | `_zoom_step`@3866, `_apply_zoom`, `_set_camera_position`, `_shot_and_quit` |
| 3991–4319 | **战棋 / 战场 / 编辑器入口 + B1 相机与拾取** | `_enter_battle`@3991, `_enter_battlefield`@4044, `_open_map_editor`@4097, `_enter_battle_inline`@4107, `_exit_battle`@4143, `cell_stand_level`@4295, `screen_to_cell`@4300 |

## 战棋子系统的依赖方向

```
scripts/core/  （纯逻辑，被所有人依赖；battlefield_loader / battle_save / block_layout 也在此层）
     ▲
scripts/systems/  （调用 core，被 battle.gd / editor / automation 调用）
     ▲
scripts/iso/ + scripts/battle/ + scripts/editor/ + scripts/assets/  （渲染层与场景助手）
     ▲
scripts/scenes/battle.gd / map_editor.gd / game_entry.gd  （编排者）
     ▲
main.gd._enter_battle* / _enter_battlefield / _open_map_editor  （世界侧入口）
```

`world_to_chapter.gd` 是**世界 ↔ 战棋的唯一耦合点**（读 TerrainSampler/CellContext，输出 chapter Dictionary）。`battlefield_loader.gd` 是 JSON 战场侧的平行入口，输出与 world_to_chapter 同构的 chapter，二者互不依赖。`scripts/battle/automation/` 与 `battle.gd` 共享 `battle_action_resolver.gd` 结算内核（同一套规则做无表现回放）。
