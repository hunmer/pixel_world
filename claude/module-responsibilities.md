# 模块职责

> 更新：2026-11-16（三单体拆分 + 深夜优化轮：main.gd 4319→2174 行（装配层），能力拆入 `scripts/world/` 25 个 RefCounted/静态模块；map_editor.gd 3285→1028 行拆入 `scripts/editor/` 26 .gd；battle.gd 1934→1557 行 + `scripts/battle/` 23 .gd 含 automation（battle_ui 拆出 4 件）；`scripts/iso/` 11→14；scripts 122→164 .gd；vendored 4→6）。

本仓库是**单体 Godot 游戏**。带 `plugin.cfg` 的独立模块只有 `addons/` 下 6 个 vendored 插件（breakpoint_mcp / panku_console / at-icons / pixelfx / **gdtest** / **godot_autosim**，中间两者插件未启用）。下表按**源码子域**划分职责，对应 `scripts/`、`ui/` 下的目录（合计 154 + 23 .gd），全部归属同一个 Godot 项目。

## 子域总览

| 子域 | 目录 | 职责一句话 | 关键脚本 |
| --- | --- | --- | --- |
| **世界引擎（装配层）** | 根 `main.gd` | 等距世界根节点：流式生成主循环、坐标变换、玩家、HUD、输入分发、战斗与编辑器入口；能力已拆入 `scripts/world/` 模块（**2026-11-16 拆分 4319→2283；深夜优化轮再 2283→2174 行**（生态配置编译外迁），`_configure_generation_services()`@485 统一装配） | `main.gd`（2174 行） |
| 世界生成 | `scripts/world/`（23 .gd） | 噪声 / Voronoi / 地形采样 / 群系模块 / cell 上下文与状态 / 确定性 RNG / 材质注册 / 大地图快照 + **拆分新增 11 模块**：植被放置 / 动物流式与逐帧行为 / 生态区匹配 / 物种选择 / 配置校验 / 小地图 / 玩家遮挡 / 表现装配 / 贴图目录 / 世界查询 | 原 12 件 + `flora_spawner.gd`, `fauna_streamer.gd`, `animal_runtime.gd`, `ecosystem_match.gd`, `species_picker.gd`, `ecology_config_validator.gd`, `minimap_renderer.gd`, `player_occlusion_controller.gd`, `presentation_stage.gd`, `terrain_texture_catalog.gd`, `world_query_service.gd` |
| 生态 | `scripts/ecology/`（9 .gd） | 群落解析、注册表、成员组合、运行时/状态存储、环境生物(鸟/萤火虫) | `ecology_registry.gd`, `ecology_resolver.gd`, `community_runtime.gd`, `community_spawner.gd`, `community_state_store.gd`, `member_composer.gd`, `ambient_registry.gd` |
| 动物行为 | `scripts/animals/` | 动物行为栈（水域偏好/避雪/嗜雪/群体/避人）的可组合注册表 | `animal_behavior_registry.gd` |
| 战棋核心（纯逻辑） | `scripts/core/`（14 .gd） | 战棋数据 / 规则 / 地形适配 / 世界→chapter 适配 / JSON 战场加载（含 victory/reinforcements 解析）/ **战旗存档编解码与落盘** / **按回合增援刷入** / 用户素材布局 | `enums.gd`, `unit.gd`, `professions.gd`, `skills.gd`, `items.gd`, `weapons.gd`, `terrain.gd`, `cmd_args.gd`, `world_to_chapter.gd`, `battlefield_loader.gd`, `battle_save_codec.gd`, `battle_save_store.gd`, `block_layout.gd`, `reinforcement_spawner.gd` |
| 战棋系统 | `scripts/systems/`（12 .gd） | 战斗结算各子系统（全静态或独立 Node）+ **AI 难度分级** + 攻击事件结构 + **注入式胜利判定** + **相邻单位交换** | `grid_system.gd`, `combat_system.gd`, `skill_system.gd`, `item_system.gd`, `buff_system.gd`, `turn_manager.gd`(`check_victory`), `enemy_ai.gd`, `player_ai.gd`, `ai_difficulty.gd`, `ai_difficulty_scoring.gd`, `attack_event.gd`, `trade_system.gd` |
| 等距/3D 渲染层 | `scripts/iso/`（11 .gd） | 主世界 3D 投影/相机/地形 + 战棋等距坐标 + JSON 战场等距方块渲染器 + 角色面板/遮挡/相机导航 | `iso_projection_3d.gd`, `isometric_camera_3d.gd`, `isometric_terrain_3d.gd`, `battlefield_renderer.gd`, `iso_coords.gd`, `iso_board.gd`, `unit_sprite.gd`, `profession_visual.gd`, `character_sheet.gd`, `battle_occluder.gd`, `world_camera_navigation.gd` |
| 战棋场景编排 | `scripts/scenes/`（12 .gd）+ `scripts/battle/`（23 .gd 含 automation 3） | 战斗/标题/编辑器/会话入口场景生命周期，UI / 范围层 / 回合编排 / **沉浸演出** / **声明式自动化**；**2026-11-16 拆分**：battle.gd 1934→1444 行（演出镜头踢击/特效/结算视觉/音效/存档/偏好面板拆出为 `battle_camera_kick/fx/result_stage/sfx/save/pref_panel`）；**深夜优化轮**：`_ready` 拆 7 个 `_configure_*`、`_unhandled_input` 键位路由表化（1444→1557），battle_ui.gd 1211→467 装配层 + `battle_ui_hud/unit_menu/unit_detail/banner` 4 模块 | `scenes/battle.gd`, `scenes/game_entry.gd`, `scenes/game_session.gd`(autoload), `scenes/startup_config.gd`, `scenes/map_editor.gd`, `battle/battle_ui.gd`, `battle/turn_director.gd`, `battle/battle_action_resolver.gd`, `battle/battle_presentation.gd`, `battle/battle_save.gd`, `battle/automation/` |
| **战场编辑器** | `scripts/editor/`（26 .gd） | 编辑器文档模型 + 等距方块画布 + **用户素材库面板** + 区域剪贴板内核（五层数据）+ 区域命名预设持久化 + 方块列表/选择弹窗 + 快捷键提示弹窗；**2026-11-16 拆分**：map_editor.gd 3285→1028 行（画布交互/格子工具/剪贴板/生成/模型写原语/预设/区域选择/替换/快捷键/素材/面板 Tab 等拆出为 `map_editor_*` 15 模块） | `battlefield_doc.gd`, `editor_canvas.gd`, `asset_library_panel.gd`, `region_clipboard.gd`, `region_preset_store.gd`, `map_editor_model_ops.gd`, `map_editor_cell_tools.gd`, `map_editor_shortcuts.gd` 等 |
| **用户素材系统** | `scripts/assets/`（3 .gd） | 本地导入（sha256 去重 blob）/ 网络清单拉取校验 / 素材→渲染适配（`docs/user_assets.md`） | `user_asset_service.gd`, `user_asset_catalog.gd`, `user_asset_visual_adapter.gd` |
| **音效** | `scripts/audio/game_sfx.gd` | autoload `Sfx`：UI/战斗/回合/胜负/脚步音效池，按钮声经 `SceneTree.node_added` 自动挂接 | `game_sfx.gd` |
| 世界表现系统 | `scripts/`（散落根，17 .gd） | 天气 / 昼夜 / 阳光阴影 / 景深 / 世界音频 / 萤火虫 / 游荡动物 / 等距批量绘制与深度排序 / 视角控制 / 光标 / 提示条 / 侧栏 | `weather_system.gd`, `day_night_system.gd`, `sunlight_system.gd`, `depth_of_field_system.gd`, `world_audio_system.gd`, `firefly_field.gd`, `wandering_animal.gd`, `isometric_column_batch.gd`, `isometric_depth_sort.gd`, `isometric_view.gd`, `game_cursor.gd`(autoload) |
| UI / 地图 | `scripts/`（散落根）+ `scripts/ui/` | HUD（战场面板/设置）/ 小地图 / 大地图叠加 / 侧栏 / 提示条 / **加载遮罩** | `game_hud.gd`, `world_map_overlay.gd`, `side_panel.gd`, `hint_bar.gd`, `ui/loading_screen.gd` |
| **共享 UI 组件库** | `ui/`（23 .gd） | ComponentTheme（DESIGN.md token 唯一实现）+ 22 个 Pixel* `@tool` 控件（按钮/输入/媒体/菜单 + **六个薄布局容器** VBox/HBox/Grid/Margin/Center/Scroll），复用老 ui_theme/ui_factory（`ui/README.md`、规范见根 `DESIGN.md`） | `ui/theme/component_theme.gd`, `ui/components/pixel_*.gd` |
| 对话系统（演示） | `scripts/scenes/dialogue_demo.gd` + `data/dialogue/` | 分支对话 JSON 演示（尚未接入正式剧情流程） | `dialogue_demo.gd`, `demo_intro.json` |
| 调试命令 | `scripts/debug_console_commands.gd` | Panku 控制台 `dbg.*` 命令集（入口转发 + 只读查询，零业务逻辑） | — |
| 自测 | `tests/` + `scripts/tests/` | headless 契约测试（80 个，manifest 驱动）+ gdtest 试点（3 文件 8 test）+ 基准/批量模拟 + Node 契约（7 项） | 见 `testing-and-quality.md` |
| 调试桥（vendored） | `addons/breakpoint_mcp/` | loopback JSON 桥接编辑器(9080)/运行时(9081)给 MCP host | 独立 `CLAUDE.md` |
| 调试控制台（vendored） | `addons/panku_console/` | 上游 v1.7.9；游戏内 `~` 表达式 REPL（autoload `Panku`） | — |
| 图标库（vendored） | `addons/at-icons/` | 上游 v1.6.0 SVG 图标（700+，编辑器 UI 用 `control/` 色系）；插件未启用 | — |
| 像素特效库（vendored） | `addons/pixelfx/` | v0.3.0，244 个代码绘制特效；战斗伤害/演出特效消费；契约 `tests/pixelfx_contract.gd` | — |
| **gdtest 运行时（vendored，2026-11-16 新增）** | `addons/gdtest/` | gdtest Rust CLI 的 Godot 运行时侧：worker 入口 + `Gdt` 断言/mock/快照/属性测试 helper + gdUnit4 迁移兼容层；试点 `tests/gdtest/`（3 文件 8 test） | — |
| **godot-autosim（vendored，2026-11-16 新增）** | `addons/godot_autosim/` | 通用对局模拟/平衡测试框架（adapter+bot+runner+report，headless 千局秒级）；本项目接入 `tools/autosim_battle_adapter.gd` + `autosim_first_action_bot.gd` | — |

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

## `main.gd` 内部职责分区（按函数簇，行号为 2026-11-16 拆分后实测）

> 拆分后 main.gd 是**装配层 + 主循环 + 入口**：能力模块在 `scripts/world/`（RefCounted、Callable 注入、无反向依赖），main.gd 保留测试直调所需的同名薄委托。`_configure_generation_services()`@485 是统一装配点。

| 行段 | 职责簇 | 代表函数（@行号） |
| --- | --- | --- |
| 1–236 | 常量 / preload / 字段声明（含 B1 战斗与视角字段、world 模块句柄） | `TILE_W/H`, `ZOOM_LEVELS`, `_BattleScript` |
| 237–484 | 生态配置加载 / 编译 / 校验 | `_load_ecosystem_config`@240, `_compile_ecosystem_config`@292（薄委托 → `ecology_config_compiler` 模块）, `_compile_animal_behavior_stacks`@362, `_validate_ecosystem_config`@406（→ `ecology_config_validator` 模块） |
| 440–613 | 启动 / 服务装配 / 重生成 | `_ready`@440, **`_configure_generation_services`@485（装配 world 模块）**, `_regenerate`@552 |
| 709–811 | 地形采样委托与统计 | `_sample_cell_context`@709（→ TerrainSampler）, `_hash_u32`@722, `_voronoi`@743, `_biome`@765, `_print_stats`@770 |
| 812–975 | 流式生成 / cell 释放 / 水体块 | `_spawn_cell`@812, `_free_cell`@927, `_update_streaming`@944 |
| 976–1068 | 坐标变换 / 投影 / 排序 / 地表判定 | `_grid_to_world`@976, `_column_sort_y`@990, `_refresh_view_projection`@1003, `_is_beach`@1039, `_desert_surface_kind`@1043 |
| 1069–1156 | 生态区匹配 / 物种选择 / 植被候选 | `_ecosystem_id_for_cell`@1069（→ `ecosystem_match`）, `_pick_species`@1128（→ `species_picker`）, `_flora_candidates_for_cell`@1132（→ `flora_spawner`） |
| 1157–1272 | 动物群落流式生成 | `_spawn_fauna_for_stream`@1157（→ `fauna_streamer`：锚点/群体规划/成员恢复） |
| 1273–1323 | 动物逐帧行为 / 材质纹理 | `_update_animals`@1273（→ `animal_runtime`）, `_process_terrain_material_texture`@1316（→ `terrain_texture_catalog`） |
| 1324–1477 | 玩家渲染 / 遮挡 / 移动 | `_setup_player`@1330, `_update_player_occlusion`@1410（→ `player_occlusion_controller`）, `_try_move`@1449 |
| 1478–1539 | 主循环 | `_process`@1478 |
| 1540–1566 | 小地图 | `_setup_minimap`@1540（→ `minimap_renderer`）, `_reveal`@1546, `_minimap_color`@1559 |
| 1567–1635 | 相机 / HUD / 大地图 | `_setup_camera`@1567, `_setup_hud`@1576, `_setup_world_map`@1587, `_world_map_snapshot`@1611 |
| 1636–1737 | 输入分发 | `_unhandled_input`@1636（Z/Q/← 与 X/E/→ 旋转、R 复位、Ctrl+R 重生成、F 复位缩放、T/N/B/O/E/P） |
| 1738–1829 | 表现层系统装配 | `_setup_day_night`@1738, `_setup_depth_of_field`@1744, `_setup_audio`@1757, `_setup_fireflies`@1761, `_setup_weather`@1769（→ `presentation_stage` builder）, `_sync_weather_*` |
| 1830–1954 | 缩放 / 相机位置 / 截图 | `_zoom_step`@1830, `set_battle_camera_kick`@1886, `_shot_and_quit`@1905 |
| 1846–2174 | **战棋 / 战场 / 编辑器入口 + B1 相机与拾取** | `_enter_battle`@1846, `_enter_battlefield`@1899, `_open_map_editor`@1952, `_enter_battle_inline`@1962, `_exit_battle`@1998, `cell_stand_level`@2150, `screen_to_cell`@2155 |

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

**拆分后的模块契约（2026-11-16 起，含深夜优化轮）**：`scripts/world/` 13 个拆出模块（11 + 配置编译/材质解析）、`scripts/editor/` 15 个 `map_editor_*` 模块、`scripts/battle/` 10 个拆出模块（6 演出/存档 + 4 battle_ui）、`scripts/iso/` 3 个绘制通道模块均为 `class_name + extends RefCounted`（少量 static，或无 class_name 纯 preload），依赖只进不出（Callable 注入回调，无反向依赖 main.gd / 场景节点）。行为护栏：拆分期间 `terrain_generation` SHA-256 每批零漂移、`map_editor_region_ops` L1 埋点序列逐行一致（终验 67/74 契约无新增红，见 `docs/plans/split_report_2026-11-15.md`）。**继续拆分的规则**：新能力先进模块再挂装配层；main.gd / map_editor.gd / battle.gd 里保留的是测试直调所需的同名薄委托，不要内联回逻辑。
