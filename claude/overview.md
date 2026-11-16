# 架构总览

> 更新：2026-11-16（三单体拆分落地：main/map_editor/battle → 模块化装配层；新增 gdtest 与 godot-autosim 两个 vendored 测试插件；统一契约 runner `tools/run_contracts.py`；上一轮：胜利条件/增援/交换、编辑器区域操作、DESIGN.md 组件库、全量基线）。

## 一句话定位

Pixel World 是一个 **Godot 4.7.2（GL Compatibility 渲染 + 3D 正交相机）** 单体游戏：按固定种子实时、确定性、流式地生成一个"无限"像素生态世界（地形 / 生物群系 / 植物群落 / 动物 / 天气 / 昼夜与阳光阴影）。世界以 **3D 正交(dimetric 2:1)渲染**呈现并支持 4 个离散视角旋转；其中嵌入**回合制战棋**子系统——带**战旗会话路由与逐战场存档**（Game.tscn 冷启动自动续玩）、**胜利条件 / 回合增援 / 单位交换**等 FE 式玩法框架、**沉浸演出层**（开场/行动/结算演出 + 全局音效 + 加载遮罩）、**JSON 战场加载**（O）、**战场地图编辑器**（E，含**区域复制/移动/命名预设**与**用户素材库**）、**无头战斗自动化 CLI**、**22 组件像素 UI 组件库 + DESIGN.md 设计 token 规范**与 **Panku 运行时调试控制台**（~）。

## 关键技术栈

- **引擎**：Godot 4.7.2 stable，`renderer/rendering_method = "gl_compatibility"`；3D 物理引擎 Jolt Physics（3D 迁移后真实使用）。
- **渲染（双层形态）**：
  - **主世界**：Node2D 场景树 + `Camera3D` 正交 dimetric 相机（`scripts/iso/isometric_camera_3d.gd`——旋转只动相机、不重建地形）+ chunk 化真实 3D 柱地形（`scripts/iso/isometric_terrain_3d.gd`）+ `DirectionalLight3D` 阳光与地形阴影（`scripts/sunlight_system.gd`，时钟来自 DayNightSystem）。动物为 `AnimatedSprite3D`。
  - **战棋 B2 / 编辑器画布**：像素 Minecraft 式等距方块柱渲染（`scripts/iso/battlefield_renderer.gd`，复用世界管线 `isometric_column_batch` + `TerrainMaterialRegistry` 贴图 + 程序化水面）；旧平面色块 fallback 已删除。
  - 自写 `.gdshader`（仓库自有 6 个：水下动物 / 水深 / 景深 / 昼夜叠加 / 旋转地形 / 遭遇转场）。
- **表现层基础设施（autoload，共 8 个）**：`SceneArgs` / `GameSession` / `Settings` / `GameCursor` / `Sfx`（全局音效池，按钮声自动挂接）/ `LoadingScreen`（幂等遮罩）/ `BreakpointRuntimeBridge`（调试）/ `Panku`（REPL）。
- **数据格式**：JSON 驱动（`config/` 与 `data/`），运行时懒加载、零硬编码策略原则；用户素材走 HTTP 清单导入（`user://custom_assets/`）。
- **测试**：GDScript headless 契约脚本 **78 个**（`extends SceneTree`）+ 战棋自测场景 2 个（`extends Node`，44 checks）+ 2 个旋转/网格探针；无第三方测试框架。Node `--test` 用于素材清单生成器（7 项）。2026-11-15 已建立 macOS 全量基线（62/72 通过，`tools/run_contract_baseline.sh`）。
- **调试**：`addons/breakpoint_mcp`（loopback JSON 桥，编辑器 9080 / 运行时 9081，MCP 按会话激活）+ `addons/panku_console`（游戏内 `~` 表达式 REPL，`dbg.*` 命令集）。
- **工具链**：`tools/battle_cli.gd`（无头战斗自动化）、`tools/build_blocks_manifest.mjs`（素材清单生成，node:test 契约）、`tools/slice_*.py` + `tools/art|audio`（素材切片/生成脚本）。

## 运行时形态与边界

```text
启动 project.godot (main_scene = res://scenes/Game.tscn)
        │
        ▼
Game.tscn (game_entry.gd — 战旗会话入口)
        │  GameSession.prepare_entry(): --battlefield > 最近存档 > 默认 plains_skirmish
        │  有进度 → 带存档进 Battle.tscn；世界就地战旗 → 按档案快照 B2 恢复
        │  受 config/startup.cfg 影响（F5 直跳 last_scene 时跳过会话路由）
        ▼  或从 Game 列表进 "生态世界"
main.tscn (Node2D "Main" + "DebugConsoleCommands" 子节点)
        │
        ▼
main.gd (2283 行 / 128 函数)  ← 世界引擎装配层（2026-11-16 拆分后）
   │  ├─ 能力模块：scripts/world/ 23 .gd（植被 flora_spawner / 动物 fauna_streamer+animal_runtime /
   │  │     生态匹配 ecosystem_match / 物种 species_picker / 校验 ecology_config_validator /
   │  │     小地图 minimap_renderer / 遮挡 player_occlusion_controller / 表现装配 presentation_stage 等，
   │  │     全部 RefCounted + Callable 注入、无反向依赖；_configure_generation_services() 统一装配）
   │  ├─ 流式生成：stream_extent 窗口内按需 _spawn_cell / _free_cell（网格坐标不变，渲染走 3D）
   │  ├─ 生态：TerrainSampler → CellContext → EcologyResolver → CellState → 渲染
   │  ├─ 动物：CommunitySpawner + WanderingAnimal（AnimatedSprite3D，行为栈）
   │  ├─ 3D 表现：IsometricCamera3D(旋转/缩放) + IsometricTerrain3D(chunk 柱地形)
   │  │           + SunlightSystem(DirectionalLight3D) + weather / day_night / dof / audio / fireflies
   │  ├─ HUD / 小地图 / 大地图(world_map_overlay + map_snapshot_renderer)
   │  └─ 入口键：P→B1/B2 战斗 │ O→JSON 战场列表(固定 B2) │ E→地图编辑器
        │
        ├─ P 且 inline_mode=true  → battle.gd 挂 main 场景树下（B1 就地，相机归 main.gd）
        ├─ P 且 inline_mode=false → change_scene_to_file(Battle.tscn)（B2 世界地形）
        ├─ O 选 JSON 战场         → _enter_battlefield(path)（固定 B2，地形与世界无关）
        └─ E                      → MapEditor.tscn（种子生成/地形编辑/阵营角色放置/区域复制-移动-预设/取色器/保存 JSON）
                                   └─ AssetLibraryPanel：用户素材库（user://custom_assets）

战斗侧（Battle.tscn / battle.gd，2026-11-16 拆分后 1444 行装配层）
   ├─ 共享结算内核 battle_action_resolver.gd ──→ automation/ 无表现回放复用（CLI）
   ├─ 玩法框架：turn_manager.check_victory（rout/defend_turns/seize 注入式胜利判定）
   │            + core/reinforcement_spawner.gd（按回合波次增援，演出/无头两链路共用）
   │            + systems/trade_system.gd（相邻友军物品传递）
   ├─ 演出层：battle_presentation + turn_director + action_anim + immersive_camera
   │          + result_presentation + encounter_transition（LoadingScreen 预热）
   │          + battle_camera_kick / battle_fx / battle_result_stage / battle_sfx（拆分新增专项模块）
   ├─ battle_save.gd（行动边界快照）+ battle_pref_panel.gd（托管偏好）+ battle_ui + Sfx + range_overlay
   └─ GameSession.commit() 行动边界落盘 user://battle_saves/
```

### 两条并行子系统 + 一份设计 bible

1. **世界 / 生态子系统（原 pixel_world）**：`main.gd` 是**装配层与主循环**（2026-11-16 拆分后 2283 行）；`scripts/world/`（23 .gd）、`scripts/ecology/`、`scripts/animals/` 是它装配的能力模块（RefCounted、Callable 注入、无反向依赖）。设计原则是"**新增内容走配置/模块，不要往 main.gd 里加分支**"（见 `config/ecology/README.md`）；继续拆分的规则见 `docs/plans/main_split_plan.md`。
2. **战棋战斗子系统（从 phaserjs 迁移）**：`scripts/core/`（纯逻辑 + 存档 codec/store + 增援刷入）+ `scripts/systems/`（战斗结算 + AI 难度 + 交换）+ `scripts/iso/`（等距/3D 渲染层）+ `scripts/battle/`（演出/UI/自动化）+ `scripts/editor/`（战场编辑器模型/画布/区域剪贴板/预设存储/素材面板）。与世界的唯一耦合点是 `scripts/core/world_to_chapter.gd`。
3. **`story/`（19 个 .md）**：完整的"古代魔法 + 多国争霸"战旗**设计 bible**（世界観/4 国/13 职业/8 角色/15 章/27 技能/25 道具/UI/音频/成就/新手引导）。注意它是**目标态设计**——当前 `data/` 只实现 8 职业/8 技能/8 物品/4 预制战场，扩张时以 story 文档为准绳（差距清单见 `docs/roadmap.md`）。

## 重要设计取舍

- **坐标级确定性**：相同 seed + 相同 cell 永远产出相同结果。`DeterministicRng`、`_cell_rand`、`_quantize` 等是确定性契约核心，**改这些会挂固化 SHA-256 快照测试**（`tests/terrain_generation_contract.gd`）。
- **"新增不修改，分支注入"**：B1 就地战斗对 `main.gd` 的改动全是 `if _battle_active:` 前置短路；B2 路径不动。战场入口（O/E）同样以独立方法注入（`_enter_battlefield` / `_open_map_editor`），不侵入既有流程。
- **渲染演进（2026-11-11 → 11-12）**：先尝试 2D 可旋转投影（任意角度连续旋转），因素材只在 4 个正交视角下能通过拼缝验收，最终收敛为 **`SUPPORTED_ANGLES = [0°, 90°, 180°, 270°]` 离散视角**，随后整体迁移到 **3D 正交渲染**（commit `33b7028` + `3189caf`）：角度变化只旋转 Camera3D，地形、生态状态与连续网格坐标全部保持不变。踩坑记录见 `handoff/2026-11-11-isometric-rotation.md`。
- **配置分层（双轨）**：`config/ecosystems.json`（旧版，运行时实际读取入口）与 `config/ecology/manifest.json` + 模块化 biome/species/communities（新版，逐步迁移）并存，由 `_compile_ecosystem_config` 编译。`legacy_bundles.json` 仅为旧布局兼容，**新内容禁止使用**。
- **战场渲染统一**：B2 战场与编辑器画布共用 `BattlefieldRenderer`（等距方块柱），地形高度规则：water h1 / plain・forest・village h2 / fort h3 / wall h4 / mountain h5。世界就地战斗的地形映射 `cell_context_to_terrain` 覆盖 11 种中的 **7 种**（water/mountain/snow/sand/rocky/grass/plain；forest/village/fort/wall 无世界数据源不映射，roadmap P1-4）。
- **批量绘制优先**：水、岸浪、天气、飞鸟等高密度元素走批量绘制/受限呈现槽位，避免每格一个 `_process` 节点。
- **三单体拆分（2026-11-16）**：main.gd（4319→2283 行，−47.1%）、map_editor.gd（3285→1031 行，−68.6%）、battle.gd（1934→1444 行）从"功能全塞主文件"改为"**装配层 + RefCounted 能力模块**"（模块 Callable 注入、无反向依赖；main.gd 保留测试直调所需的同名薄委托）。行为护栏：拆分期间 `terrain_generation` SHA-256 每批零漂移、`map_editor_region_ops` L1 埋点序列逐行一致；终验 67/74 契约无新增红（`docs/plans/split_report_2026-11-15.md`）。三个装配层仍可按同法继续抽（roadmap P3-13 剩余项）。
- **结算内核与表现分离（2026-11）**：`battle_action_resolver.gd` 是 battle.gd 与无头自动化（`battle/automation/` + `tools/battle_cli.gd`）**共享的行动结算内核**——同一套规则既跑有人玩的演出局，也跑 CLI 事件流回放，保证自动化断言与真机行为一致。增援刷入同样双链路共用 `reinforcement_spawner.gd`（敌方回合开始同点位接线）。
- **演出可选可跳**：沉浸演出（开场/行动/结算）是**表现层增强**，非战斗逻辑依赖；battle 设置页可开关，播放中可快进（`*_finished(skipped)` 信号贯穿）；关演出不影响结算正确性。
- **胜利/增援走声明式 JSON**：chapter 可选 `victory`（rout / defend_turns / seize）与 `reinforcements`（按回合波次）字段，`battlefield_loader` 静态严校验、非法整卡拒绝；`check_victory(enemies, ctx)` 注入式判定 + 歼灭兜底，未到点增援并入敌存活集合防提前判胜。
- **UI 设计规范单一事实来源（DESIGN.md）**：间距/圆角/字号/边距 token（8/16/24 体系）唯一实现于 `ui/theme/component_theme.gd`，六个薄布局容器（PixelVBox/HBox/Grid/Margin/Center/Scroll）；新增界面**禁止裸数字样式值/自建 StyleBox/绝对定位/横向滚动**（正误例与验收命令见根 `DESIGN.md`）。
- **UI 组件库独立成库**：`ui/` 22 组件 + ComponentTheme（每次 create() 独立 Theme，不污染默认主题）先在画廊（F6）与契约测试（1062 checks）中成熟，**业务 UI（battle_ui/HUD）暂未迁移**——map_editor 已部分迁移（按钮走 Pixel 组件，但仍有 3 处直建控件被 `ui_contract` 抓红），两套并存，迁移是 roadmap 项。
- **用户素材走网络清单而非打包**：编辑器素材库从 HTTP 源导入 blob 到 `user://`，sha 去重幂等；源地址可配置（`asset_source.cfg [asset_source] source_url` 覆盖 > 库内 settings > 默认 `127.0.0.1:8076`），断源优雅降级（roadmap 验收项）。

## 仓库边界

- **项目位置**：`/Users/Zhuanz/Documents/pixel_world`（macOS；历史路径 G:/ → E:/ → 本机）。Godot 可执行文件 `/Applications/Godot.app/Contents/MacOS/Godot`（Windows 历史路径 `D:/Godot/Godot_v4.7.2-stable_win64.exe`）。
- **源项目引用**：战棋代码迁移自外部 phaserjs 项目（不在本仓库）。
- **文档分区**：`claude/`（本索引详情）、`rules/`（agent 规则 4 篇）、`story/`（目标态设计 bible）、`handoff/`（专题交接存档 3 篇）、`docs/`（运维与进度：battle_automation / startup_config / user_assets / gameplay_gap / roadmap / test_automation(+results) / testing_baseline_2026-11-15 / plans/{main,map_editor}_split_plan + split_report）、`plans/`（开发计划存档）、根 `DESIGN.md`（UI 设计规范唯一事实来源）。
- **不属于本仓库的内容**：`.godot/`（引擎生成物）、`/builds/`、`/exports/`、`/android/`。
