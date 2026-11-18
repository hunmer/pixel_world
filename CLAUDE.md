# Pixel World — AI 上下文索引

## 项目简单介绍

Pixel World 是一个 **Godot 4.7.2（GL Compatibility）/ Node2D** 单体 2D 游戏：在 3D 正交（dimetric）视口下，按固定种子实时、确定性、流式生成一个"无限"像素生态世界 —— 地形、生物群系（温带/沙漠/雪地/水域/岸）、植物群落、动物（狼群/猪家/蛙群/金鱼/鸟等，13 种）、天气（雨/雪）、昼夜与月光、3D 阳光与地形阴影、萤火虫、音乐与空间音效。渲染为 chunk 化 3D 柱地形 + Camera3D（视角旋转只动相机）。

世界中嵌入了从另一个项目（phaserjs）迁移来的**回合制战棋战斗**系统：主入口 `res://scenes/Game.tscn` 提供战旗会话路由（冷启动自动续玩最近战旗，逐战场独立存档）；按 `P` 在玩家所在真实地形"就地战斗"（B1）或切独立场景（B2）；按 `O` 从 `data/battlefields/*.json` 选**预制 JSON 战场**开战（固定 B2，支持**胜利条件 rout/defend_turns/seize**与**按回合波次增援**）；按 `E` 打开**战场地图编辑器**（画笔/填充/橡皮/角色 + 种子生成 + **区域复制/移动/命名预设** + 取色器 + 用户素材库，保存即校验入列）。战棋地形 11 种，等距方块柱渲染；战斗场景 `battle.gd`（1557 行，`_ready`/输入已路由化）+ `scripts/battle/` 20 模块（含 battle_ui 拆出 4 件）、编辑器 `map_editor.gd`（1028 行 + `scripts/editor/` 26 模块）同为此轮拆分；战斗带**沉浸演出层**（开场/行动/结算，可开关可快进）、**相邻单位物品交换**与**无头自动化 CLI**（`tools/battle_cli.gd`）。两个子系统的唯一耦合点是 `scripts/core/world_to_chapter.gd`；JSON 战场由 `scripts/core/battlefield_loader.gd` 平行供给。UI 层有 **22 组件像素组件库 + DESIGN.md 设计 token 规范**（`ui/`，token 唯一实现 `ComponentTheme`）。

世界引擎装配层在 `main.gd`（2026-11-16 拆分后 2280 行；生成/生态/表现能力拆入 `scripts/world/` 25 个模块，`_configure_generation_services()` 统一装配）。运行 `godot --path .`。纯单机：磁盘持久化 = `user://settings.cfg`、`user://battle_saves/`（战旗存档）、`user://battlefields/`、`user://custom_assets/`（用户素材）与调试用 `config/startup.cfg`。

## 约定的规则（高优先级）

- **运行**：`godot --path .`。本机（macOS）`/Applications/Godot.app/Contents/MacOS/Godot`（Windows 历史路径 `D:/Godot/Godot_v4.7.2-stable_win64.exe`；console 版 stdout 全缓冲：管道无输出 ≠ 没输出）。主场景 `res://scenes/Game.tscn`（战旗会话入口）；`config/startup.cfg` 可让 F5 直跳最近场景。
- **测试**：默认入口 `python3 tools/run_contracts.py`（manifest 驱动 80 契约 + 2 探针；当前口径 **pass 75 / known-fail 0 / env-skip 5**——2026-11-17 五项 known-fail 全部修复清零，依据见 manifest evidence）；单契约直跑 `godot --headless --path . --script res://tests/<name>_contract.gd`；批量模拟 `tools/run_simulations.gd`（详见 `docs/test_automation.md` 与 `claude/testing-and-quality.md`）；战棋自测跑 `scenes/SkillTest.tscn`（44/44）。**地形测试用固化 SHA-256 快照检测回归** —— 改确定性会挂。素材清单生成器用 `node --test`。
- **编辑器缓存坑**：运行态验证先确认新代码已加载；出现旧脚本缓存问题时再清理 `.godot/editor` 并重启编辑器，纯 headless / 文档改动无需此步骤。tab 缩进；文件名 `snake_case.gd`；顶部带 `## file.gd — 职责` 注释。
- **不要往 `main.gd` 加分支**：新 biome / noise / surface / minimap 色 / weather tag 一律走 biome 模块 + 配置 + community；新内容用 `config/ecology/`，**禁用 `legacy_bundles.json` 与 `metadata.legacy_placement_seed`**。
- **确定性契约**：内容 ID / `stream_key` / legacy `placement_seed` 是存档/世界契约；文件路径与显示名绝不能当随机种子；重排 manifest / 改稳定 ID 需 world version 迁移。
- **战棋双模式**：`Settings.battle_inline_mode`（默认 true）切 B1/B2；JSON 战场固定 B2。改 `main.gd` 遵守"新增不修改，分支注入"：B1 逻辑一律 `if _battle_active:` 前置短路。战斗结算与表现分离：`battle_action_resolver.gd` 是共享结算内核，勿在演出层复写结算。
- **视角只支持 4 正交角度**（0/90/180/270，`isometric_view.gd`）：素材其余角度有拼缝，勿放开连续角度。
- **MCP 运行态调试按会话激活**（见 `AGENTS.md`）：先选代码测试；确需运行态时再激活对应 Godot 工具。工具默认不在工具表里，按 `mcp_connector_session_tools` preview-activate → activate；`tool not found` ≠ 没装 MCP。`dbg_launch` 必传 `scene`；运行态验证通过函数/API 控制并用 `runtime_assert_*` 自动验收，不要 `print` 后肉眼判断。
- **UI 走 DESIGN.md + 组件库**：新界面一律用 `ui/` 的 Pixel* 组件（22 个）+ `ComponentTheme` token，禁裸数字样式值 / 自建 StyleBox / 绝对定位 / 横向滚动（规范见根 `DESIGN.md`）；`tests/ui_contract.gd` 静态扫描业务脚本禁直建 `Button/CheckButton/OptionButton.new()`。
- **`story/` 是目标态设计 bible**（13 职业/27 技能/25 道具/15 章），运行时事实是 `data/` 的 8/8/8 + 6 战场 —— 勿混用；差距与推进顺序见 `docs/roadmap.md` 与 `docs/gameplay_gap.md`。

> 详细命令、规范与禁忌见 [conventions.md](claude/conventions.md)；agent 工作约束见根 `AGENTS.md`。

## 文件索引

| 文件 | 用途 | 何时阅读 |
| --- | --- | --- |
| [claude/overview.md](claude/overview.md) | 架构总览、运行时形态、关键设计取舍、仓库边界 | **先读** —— 建立全局认知 |
| [claude/conventions.md](claude/conventions.md) | 命令、代码风格、配置/内容规范、调试方法、安全边界 | 动手改代码 / 加内容前 |
| [claude/module-responsibilities.md](claude/module-responsibilities.md) | 子域职责划分、数据流、main.gd 函数簇分区、依赖方向 | 定位"某逻辑在哪/该改哪" |
| [claude/entrypoints.md](claude/entrypoints.md) | 引擎入口、8 autoload、场景表、Game/main 启动流程、战斗/编辑器入口 | 理解启动 / 入口 |
| [claude/public-interfaces.md](claude/public-interfaces.md) | 玩家输入映射、SceneArgs/Settings/GameSession 契约、素材服务/组件库/CLI 接口、JSON 战场 schema、信号 | 理解跨场景/跨模块接口 |
| [claude/dependencies-and-config.md](claude/dependencies-and-config.md) | 依赖（6 vendored 插件）、全部配置文件、素材源、命令行参数 | 改配置 / 加物种 / 排查版本 |
| [claude/data-model.md](claude/data-model.md) | CellContext/CellState/确定性RNG、3D 渲染结构、群落模型、战棋 UnitData/chapter、存档/素材/对话模型 | 理解运行时数据结构 |
| [claude/testing-and-quality.md](claude/testing-and-quality.md) | 测试机制（80 契约 + 统一 runner + gdtest/autosim）、基线状态、Lint、质量风险 | 跑测试 / 评估改动风险 |
| [claude/file-map.md](claude/file-map.md) | 完整目录树、scripts/ 文件级地图、快速定位表 | 找具体文件 |
| [claude/faq.md](claude/faq.md) | 常见问题与定位路径 | 卡住时先查 |
| [claude/report.md](claude/report.md) | **代码自检报告**：结构与职责 / 重复 / 可读性 / 可复用资产（UI 三层链 / 共享内核 / world 模块 / 编辑器组件 / autoload）+ 复用守则 | 写新功能前先查"有没有现成的"；排查质量问题时 |
| [claude/changelog.md](claude/changelog.md) | 本索引自身的生成/更新记录（最近 5 条） | 查索引何时/how 更新 |
| [DESIGN.md](DESIGN.md) | **UI 设计规范单一事实来源**：token 体系、六薄容器、禁忌、三档分辨率验收 | 写任何新 UI 前 |
| [docs/roadmap.md](docs/roadmap.md) | **后续完善项清单**：按优先级分层 + 前置依赖 + 验收方式 | 规划下一步工作 |

另有专题文档：`rules/`（4 篇 agent 规则：godot-tools-map 295 工具 / 49 可激活地图、mcp-debugging、autoplay-hosting、skill-item-system）、`story/`（19 篇目标态设计 bible）、`handoff/`（3 篇专题交接踩坑：isometric-rotation / game-sfx-system / immersive-battle-presentation）、`docs/`（battle_automation / test_automation / startup_config / user_assets / gameplay_gap 玩法差距矩阵 / feature_map 功能图谱 / testing_baseline 全量基线）、`plans/`（开发计划存档）、`ui/README.md`（UI 组件库）。

## 模块索引

本仓库是**单体 Godot 游戏**，无多 `package.json` 级子工作区。源码子域（`scripts/core`、`systems`、`iso`、`editor`、`battle`、`scenes`、`assets`、`audio`、`ui`、`world`、`ecology`、`animals` 等）属同一应用，统一在 [claude/module-responsibilities.md](claude/module-responsibilities.md) 描述，不单独建 CLAUDE.md。

独立成册的 vendored 模块（`addons/`）：

| 模块 | 职责 | 索引 |
| --- | --- | --- |
| `addons/breakpoint_mcp/` | vendored 调试插件（loopback JSON 桥接编辑器 9080 / 运行时 9081 给 MCP host，v1.23.0） | [addons/breakpoint_mcp/CLAUDE.md](addons/breakpoint_mcp/CLAUDE.md) |
| `addons/panku_console/` | vendored 游戏内 `~` REPL 控制台 v1.7.9（autoload `Panku`；项目 `dbg.*` 命令集在 `scripts/debug_console_commands.gd`） | 上游 README |
| `addons/at-icons/` | vendored SVG 图标库 v1.6.0（700+，MIT；编辑器 UI 只用 `control/` 色系；插件未启用） | 上游 README |
| `addons/pixelfx/` | vendored 像素特效库 v0.3.0（244 个代码绘制特效，24 类：fire/ice/explosions/melee/moves/pickups 等；`PixelFx2D` BAKED/LIVE 双模式 + `PixelFxAct2D` 演出节点，MIT；契约 `tests/pixelfx_contract.gd`） | 上游 README |
| `addons/gdtest/` | vendored gdtest Rust CLI 的运行时侧（worker + Gdt 断言/mock/快照 helper + gdUnit4 兼容层；试点 `tests/gdtest/`，2026-11-16） | 上游 README |
| `addons/godot_autosim/` | vendored 通用对局模拟框架（adapter+bot+runner+report；接入 `tools/autosim_*.gd`，2026-11-16） | 上游 README |

### 子系统关系

```mermaid
graph TD
    subgraph 世界生态子系统（3D 正交）
        Main[main.gd 装配层<br/>2280 行/_configure_generation_services]
        World[scripts/world/ 25 模块<br/>地形采样/CellContext/确定RNG/biomes<br/>flora/fauna/minimap/表现装配/配置编译/材质解析]
        Eco[scripts/ecology/<br/>群落解析/spawner/state]
        Anim[scripts/animals/<br/>行为栈]
        Iso3D[scripts/iso/<br/>Camera3D/柱地形/投影]
        Present[表现层模块<br/>scripts/world/presentation_stage 装配<br/>weather/day_night/sunlight/dof/audio/sfx/firefly]
    end
    subgraph 战棋战斗子系统
        Session[Game.tscn + GameSession<br/>会话路由/存档]
        Core[scripts/core/<br/>纯逻辑+battlefield_loader+存档codec]
        Sys[scripts/systems/<br/>战斗结算+AI难度]
        Battle[scripts/scenes/battle.gd<br/>+scripts/battle/ 演出/自动化]
        Editor[scripts/editor/<br/>战场编辑器+素材面板]
        Assets[scripts/assets/<br/>用户素材服务]
    end

    Game[scenes/Game.tscn 主入口] --> Session
    Main --> World --> Eco --> Anim
    Main --> Iso3D
    Main --> Present
    Main -- "按 P + Settings.inline_mode" --> Battle
    Main -- "按 O（JSON 战场）" --> Battle
    Main -- "按 E" --> Editor
    Editor --> Core
    Editor --> Assets
    Battle --> Sys --> Core
    Battle --> Sys
    Core -. "world_to_chapter<br/>（唯一耦合）" .-> World
```

## 扫描状态

- **更新时间**：2026-11-16（第三轮增量：**三单体拆分**〔main/map_editor/battle → 装配层+能力模块〕、测试自动化〔run_contracts.py / run_simulations / gdtest / autosim〕、vendored 4→6、代码自检报告〔claude/report.md，四组：结构/重复/可读性/可复用〕、feature_map 图谱刷新 321 文件 100% 覆盖）。
- **已扫描**：根目录全部源码结构（`main.gd` 拆分后 2280 行、`map_editor.gd` 1028 行、`battle.gd` 1557 行、`scripts/` 文件级 166 `.gd`〔world 25 / editor 26 / battle 20 / iso 14 / ecology 10 / hud 2〕、`tests/` 86 `.gd`〔80 契约 + 2 探针 + gdtest 3 + benches 1〕归类、`config/`+`data/` JSON、16 仓库自有 `.tscn`、6 自有 `.gdshader`、6 addons 全量、automation/assets/ui/editor/world 子系统 API 级、`DESIGN.md`+`story/`+`rules/`+`handoff/`+`docs/` 文档级）。
- **运行态验证**：拆分护栏 = terrain_generation SHA-256 零漂移（`docs/plans/split_report_2026-11-15.md`）；统一 runner 口径 **pass 75 / known-fail 0 / env-skip 5**（`docs/test_automation.md`，2026-11-17 known-fail 清零）；批量模拟 1000 局 3.6s。2026-11-16 深夜优化轮（4 成员并行行为等价重构 report.md 违例）后 0 新增红，terrain_generation SHA 逐字节一致。
- **跳过**：`.godot/`（引擎生成，gitignore）；二进制素材 `.png`/`.mp3`；引擎生成物 `.import`/`.uid`。
- **覆盖率**：源码与配置结构 ~100%（feature_map 321/321 = 100%）；二进制素材内容 0%（仅统计）。
- **下一步建议**：已全部整理进 [docs/roadmap.md](docs/roadmap.md)（按优先级 P0–P3 + 前置依赖），不再在此重复。
