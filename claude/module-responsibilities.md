# 模块职责

> 更新：2026-11-18（第四轮增量：新增 `scripts/campaign/` 6 .gd 冒险模式子域 + 建筑模块横跨 core/iso/editor/assets + 战斗扩展 facing/pincer/threat/action_history/level_up + 图标契约模块 + map_editor_buildings/units + ui_gallery 拆分 + skill_list；battle.gd 1557→2186、map_editor.gd 1028→1088；scripts 166→173 .gd〔不含根脚本〕）。

本仓库是**单体 Godot 游戏**。带 `plugin.cfg` 的独立模块只有 `addons/` 下 6 个 vendored 插件（breakpoint_mcp / panku_console / at-icons / pixelfx / gdtest / godot_autosim，中间两者插件未启用）。下表按**源码子域**划分职责，全部归属同一个 Godot 项目。

## 子域总览

| 子域 | 目录 | 职责一句话 | 关键脚本 |
| --- | --- | --- | --- |
| **世界引擎（装配层）** | 根 `main.gd` | 等距世界根节点：流式生成主循环、坐标变换、玩家、HUD、输入分发、战斗/编辑器入口；能力拆入 `scripts/world/`（`_configure_generation_services()`@485 统一装配） | `main.gd`（2280 行，不变） |
| 世界生成 | `scripts/world/`（20 .gd） | 噪声 / Voronoi / 地形采样 / 群系模块 / cell 上下文与状态 / 确定性 RNG / 材质 / 小地图 / 植被放置 / 动物流式 / 生态区匹配 / 物种选择 / 配置校验编译 / 表现装配 / 世界查询 | `terrain_sampler.gd`, `flora_spawner.gd`, `fauna_streamer.gd`, `ecosystem_match.gd`, `presentation_stage.gd` 等 |
| 生态 | `scripts/ecology/`（8 .gd） | 群落解析、注册表、成员组合、运行时/状态存储、legacy 解码、环境生物 | `ecology_registry.gd`(984), `ecology_resolver.gd`, `community_runtime.gd`(943) |
| 动物行为 | `scripts/animals/`（1 .gd） | 行为栈（水域/避雪/嗜雪/群体/避人）可组合注册表 | `animal_behavior_registry.gd` |
| **冒险模式** | `scripts/campaign/`（6 .gd）+ `scripts/scenes/campaign_*.gd`（7 .gd） | **（2026-11-18 新增）** 档案/进度/商店/出征结算会话 + 四屏一层的营地 UI；磁盘安全契约（出征前快照、settle 幂等、掉落独立 RNG） | `campaign_session.gd`(973, autoload), `campaign_profile_codec.gd`(435), `campaign_profile_store.gd`(329), `campaign_config.gd`(340), `campaign_roster.gd`(297), `shop_catalog.gd`(106)；scenes 侧 `campaign_main`(173 装配层)/`campaign_save_select`(437)/`campaign_hub`(416)/`campaign_format`(267)/`campaign_shop`(249)/`campaign_levels`(245)/`campaign_modal`(214) |
| 战棋核心（纯逻辑） | `scripts/core/`（18 .gd） | 战棋数据 / 规则 / 职业九键成长 / **技能与状态图标** / 世界→chapter 适配 / JSON 战场加载（含 victory/reinforcements/**buildings**）/ 存档编解码与落盘 / 增援刷入 / **建筑布局与室内布局** | `enums.gd`, `unit.gd`, `professions.gd`(九键 growths), `skill_icons.gd`(稳定 ID), `status_icons.gd`, `world_to_chapter.gd`, `battlefield_loader.gd`, `battle_save_codec.gd`, `battle_save_store.gd`, `block_layout.gd`, `building_layout.gd`(194), `building_interior.gd`(93), `reinforcement_spawner.gd` |
| 战棋系统 | `scripts/systems/`（14 .gd） | 战斗结算各子系统（全静态或独立 Node）+ AI 难度 + 攻击事件 + 注入式胜利判定 + 相邻交换 + **背击/夹击规则** + **威胁预测数据** | `grid_system.gd`, `combat_system.gd`, `skill_system.gd`, `item_system.gd`, `buff_system.gd`, `turn_manager.gd`, `enemy_ai.gd`, `player_ai.gd`, `ai_difficulty*.gd`, `attack_event.gd`, `trade_system.gd`, `facing_rules.gd`(背击), `pincer_rules.gd`(夹击追击), `battle_threat_data.gd`(只读威胁) |
| 等距/3D 渲染层 | `scripts/iso/`（17 .gd） | 主世界 3D 投影/相机/柱地形 + 战棋等距坐标 + JSON 战场方块渲染 + **建筑视图/室内/遮挡** + **单位状态徽章** + 角色面板 | `iso_projection_3d.gd`, `isometric_camera_3d.gd`, `isometric_terrain_3d.gd`, `battlefield_renderer.gd`(1058), `building_interior_view.gd`(97), `building_occlusion_controller.gd`(89), `unit_status_badges.gd` |
| 战棋场景编排 | `scripts/scenes/`（20 .gd）+ `scripts/battle/`（26 .gd 含 automation 3） | 战斗/标题/编辑器/会话/campaign 入口场景生命周期；UI / 范围层 / 回合编排 / 沉浸演出 / **行动历史** / **升级演出** / **出征桥接** / 声明式自动化；battle.gd 2026-11-18 扩到 **2186 行**（+行动历史【记录】Tab@619,651、campaign 结算接线） | `scenes/battle.gd`, `scenes/game_entry.gd`, `scenes/game_session.gd`, `battle/battle_ui.gd`, `battle/turn_director.gd`, `battle/battle_action_resolver.gd`★共享结算内核, `battle/battle_action_history.gd`, `battle/level_up_presentation.gd`, `battle/campaign_battle_bridge.gd`, `battle/automation/` |
| **战场编辑器** | `scripts/editor/`（28 .gd） | 编辑器文档模型 + 画布 + 用户素材面板 + 区域剪贴板/预设 + **建筑摆放** + **角色编辑（map_editor_units）** | `battlefield_doc.gd`, `editor_canvas.gd`, `asset_library_panel.gd`(983), `region_clipboard.gd`, `map_editor_buildings.gd`(120), `map_editor_units.gd` 等 15 `map_editor_*` 模块 |
| **用户素材系统** | `scripts/assets/`（5 .gd） | 本地导入（sha 去重 blob）/ 网络清单 / 素材→渲染适配 / **内置建筑素材目录**（watchtower/house） | `user_asset_service.gd`, `user_asset_catalog.gd`, `user_asset_visual_adapter.gd`, `builtin_building_assets.gd`, `builtin_house_assets.gd` |
| 音效 | `scripts/audio/game_sfx.gd` | autoload `Sfx`（UI/战斗/回合/胜负/脚步；`level_up_presentation` 经 `sound_requested` 信号接入不直连） | `game_sfx.gd` |
| 世界表现系统 | `scripts/`（散落根，17 .gd） | 天气 / 昼夜 / 阳光阴影 / 景深 / 世界音频 / 萤火虫 / 游荡动物 / 批量绘制 / 视角 / 光标 / 提示 | `weather_system.gd`, `day_night_system.gd`, `sunlight_system.gd`, `isometric_column_batch.gd`, `isometric_view.gd` |
| UI / 地图 | `scripts/`（散落根）+ `scripts/ui/` + `scripts/ui_gallery/`（6 .gd） | HUD / 小地图 / 大地图 / 侧栏 / 加载遮罩 / 组件画廊（2026-11-18 拆 6 模块） | `game_hud.gd`, `world_map_overlay.gd`, `ui/loading_screen.gd`, `ui_gallery/*` |
| **共享 UI 组件库** | `ui/`（28 .gd） | ComponentTheme（token 唯一实现）+ **27 个 Pixel* `@tool` 控件**（16 功能 + 5 新帧框/名牌/竖 Tab + 6 薄布局容器） | `ui/theme/component_theme.gd`, `ui/components/pixel_*.gd` |
| 对话系统（演示） | `scripts/scenes/dialogue_demo.gd` + `data/dialogue/` | 分支对话 JSON 演示 | `dialogue_demo.gd` |
| 技能图鉴 | `scripts/scenes/skill_list.gd`（190 行）+ `scenes/SkillList.tscn` | 27+ 技能卡片浏览（Title 按钮进入） | `skill_list.gd` |
| 调试命令 | `scripts/debug_console_commands.gd` | Panku `dbg.*` 命令集 | — |
| 自测 | `tests/`（115 .gd + 5 探针）+ `scripts/tests/` | headless 契约测试（**103 项 manifest 驱动**）+ gdtest 试点 + 基准/批量模拟 + Node 契约 | 见 `testing-and-quality.md` |
| vendored ×6 | `addons/` | breakpoint_mcp（调试桥）/ panku_console（REPL）/ at-icons（SVG）/ pixelfx（特效）/ gdtest（Rust CLI 运行时）/ godot_autosim（对局模拟） | 独立 README/CLAUDE.md |

## 三条数据流（理解全局必读）

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

### B. 战棋数据流（按 P / O / E / campaign 出征进入）

```
入口三选一：
  main.gd._unhandled_input
    ├─ KEY_P → _enter_battle() → WorldToChapter.world_to_chapter(...)
    │            → inline_mode ? B1(add_child) : B2(change_scene)
    ├─ KEY_O → BattlefieldPanel → _enter_battlefield(path)
    │            → BattlefieldLoader.load_battlefield(path)（含 buildings 层解析）
    └─ KEY_E → _open_map_editor()
  或 Campaign.prepare_battle(level_id) → campaign_battle_bridge
    → SceneArgs.battle_args{chapter/world/return_to/save_*/campaign_token}

battle.gd._ready 读 SceneArgs.battle_args
  → GridSystem + TurnManager + 单位 + IsoBoard/BattlefieldRenderer(+建筑) + UnitSprite(+状态徽章)
  → 状态机 Mode(...) → TurnDirector 编排 AI（threat 数据辅助）
  → 攻击结算出 AttackEvent（facing_rules 背击 / pincer_rules 夹击追击判定在 resolver 内）
    → BattlePresentation 驱动动画/特效(PixelFx)/音效(Sfx)
  → BattleActionHistory 记录整场行动（【记录】Tab 查看/回退，跨回合）
  → 升级时机 → LevelUpPresentation 演出（sound_requested → Sfx）
  → 回合结束 check_victory(enemies+未到点增援, ctx) 判 rout/defend_turns/seize
  → 行动边界：campaign_token ? bridge.settle→CampaignSession.settle_battle（先落盘）
             : GameSession.commit() 落盘 user://battle_saves/
  → battle_finished(result) → B1: main.gd._exit_battle；B2: change_scene(return_to)
```

### C. 启动路由数据流（冷启动）

```
project.godot main_scene = scenes/Campaign.tscn（默认玩家入口）
  → CampaignSession.list_profiles()
  → 有档案：存档选择屏（继续/新建/重命名/删除）→ 营地 Hub
  → 无档案：新建（名字 + AI 难度）→ 营地 Hub
  → 营地 → 出征/商店/关卡列表；旧入口（世界探索、战旗路由 Game.tscn）保留为开发用途
```

## `main.gd` 内部职责分区（按函数簇，行号为 2026-11-16 拆分后实测，2026-11-18 未变）

> 拆分后 main.gd 是**装配层 + 主循环 + 入口**：能力模块在 `scripts/world/`（RefCounted、Callable 注入、无反向依赖），main.gd 保留测试直调所需的同名薄委托。`_configure_generation_services()`@485 是统一装配点。

| 行段 | 职责簇 | 代表函数（@行号） |
| --- | --- | --- |
| 1–236 | 常量 / preload / 字段声明（含 B1 战斗与视角字段、world 模块句柄） | `TILE_W/H`, `ZOOM_LEVELS`, `_BattleScript` |
| 237–484 | 生态配置加载 / 编译 / 校验 | `_load_ecosystem_config`@240, `_compile_ecosystem_config`@292, `_compile_animal_behavior_stacks`@362, `_validate_ecosystem_config`@406 |
| 440–613 | 启动 / 服务装配 / 重生成 | `_ready`@440, **`_configure_generation_services`@485**, `_regenerate`@552 |
| 709–811 | 地形采样委托与统计 | `_sample_cell_context`@709, `_hash_u32`@722, `_voronoi`@743, `_biome`@765 |
| 812–975 | 流式生成 / cell 释放 / 水体块 | `_spawn_cell`@812, `_free_cell`@927, `_update_streaming`@944 |
| 976–1068 | 坐标变换 / 投影 / 排序 / 地表判定 | `_grid_to_world`@976, `_refresh_view_projection`@1003, `_is_beach`@1039 |
| 1069–1156 | 生态区匹配 / 物种选择 / 植被候选 | `_ecosystem_id_for_cell`@1069, `_pick_species`@1128 |
| 1157–1272 | 动物群落流式生成 / 逐帧行为 | `_spawn_fauna_for_stream`@1157, `_update_animals`@1273 |
| 1273–1477 | 玩家渲染 / 遮挡 / 移动 | `_setup_player`@1330, `_try_move`@1449 |
| 1478–1635 | 主循环 / 小地图 / 相机 / HUD | `_process`@1478, `_setup_minimap`@1540, `_setup_hud`@1576 |
| 1636–1737 | 输入分发 | `_unhandled_input`@1636（旋转/缩放/重生成/T/N/B/O/E/P） |
| 1738–1829 | 表现层系统装配 | `_setup_day_night`@1738 … `_setup_weather`@1769（→ presentation_stage） |
| 1830–1954 | 缩放 / 相机 / 截图 | `_zoom_step`@1830, `_shot_and_quit`@1905 |
| 1952–2280 | **战棋 / 战场 / 编辑器入口 + B1 相机与拾取** | `_enter_battle`@1952, `_enter_battlefield`@2005, `_open_map_editor`@2058, `_enter_battle_inline`@2068, `_exit_battle`@2104, `screen_to_cell`@2261 |

## 战棋子系统的依赖方向

```
scripts/core/  （纯逻辑，被所有人依赖；battlefield_loader / battle_save / block_layout / building_layout 也在此层）
     ▲
scripts/systems/  （调用 core，被 battle.gd / editor / automation / campaign 调用）
     ▲
scripts/iso/ + scripts/battle/ + scripts/editor/ + scripts/assets/  （渲染层与场景助手）
     ▲
scripts/scenes/battle.gd / map_editor.gd / campaign_*.gd / game_entry.gd  （编排者）
     ▲
main.gd._enter_battle* / CampaignSession.prepare_battle  （世界侧/冒险侧入口）
```

`world_to_chapter.gd` 是**世界 ↔ 战棋的唯一耦合点**（读 TerrainSampler/CellContext，输出 chapter Dictionary）。`battlefield_loader.gd` 是 JSON 战场侧的平行入口（campaign 关卡也走它加载 data/battlefields/*.json），二者互不依赖。`scripts/battle/automation/`、`battle.gd` 与 8 个战斗契约测试共享 `battle_action_resolver.gd` 结算内核（同一套规则做无表现回放，含背击/夹击/掉落）。

**模块契约（2026-11-16 拆分定形，2026-11-18 延续）**：`scripts/world/`、`scripts/editor/map_editor_*`、`scripts/battle/` 演出/UI 模块、`scripts/iso/` 绘制通道、**2026-11-18 新增的 `scripts/campaign/` 与 `campaign_*` 屏**均为 `class_name + extends RefCounted`（少量 static，或无 class_name 纯 preload），依赖只进不出（Callable 注入回调，无反向依赖 main.gd / 场景节点）。行为护栏：拆分期间 `terrain_generation` SHA-256 每批零漂移、`map_editor_region_ops` L1 埋点序列逐行一致。**继续拆分的规则**：新能力先进模块再挂装配层；装配层里保留的是测试直调所需的同名薄委托，不要内联回逻辑。
