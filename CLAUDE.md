# Pixel World — AI 上下文索引

## 项目简单介绍

Pixel World 是一个 **Godot 4.7.2（GL Compatibility）/ Node2D** 单体 2D 游戏：在 3D 正交（dimetric）视口下，按固定种子实时、确定性、流式生成一个"无限"像素生态世界 —— 地形、生物群系（温带/沙漠/雪地/水域/岸）、植物群落、动物（狼群/猪家/蛙群/金鱼/鸟等，13 种）、天气（雨/雪）、昼夜与月光、3D 阳光与地形阴影、萤火虫、音乐与空间音效。渲染为 chunk 化 3D 柱地形 + Camera3D（视角旋转只动相机）。

世界中嵌入了从另一个项目（phaserjs）迁移来的**回合制战棋战斗**系统：按 `P` 在玩家所在真实地形"就地战斗"（B1）或切独立场景（B2）；按 `O` 从 `data/battlefields/*.json` 选**预制 JSON 战场**开战（固定 B2）；按 `E` 打开**战场地图编辑器**（画笔/填充/橡皮/角色 + 种子生成，保存即校验入列）。战棋地形 11 种，等距方块柱渲染。两个子系统的唯一耦合点是 `scripts/core/world_to_chapter.gd`；JSON 战场由 `scripts/core/battlefield_loader.gd` 平行供给。

世界引擎逻辑集中在 `main.gd`（4099 行 / 174 函数）。运行 `godot --path .`（主场景 `res://main.tscn`）。纯单机：唯一磁盘持久化是 `user://settings.cfg` 与编辑器产出的 `user://battlefields/`。

## 约定的规则（高优先级）

- **运行**：`godot --path .`。本机 exe `D:/Godot/Godot_v4.7.2-stable_win64.exe`（console 版 stdout 全缓冲：管道无输出 ≠ 没输出）。
- **测试**：无框架。`godot --headless --path . --script res://tests/<name>_contract.gd`（37 个；⚠️ `game_hud_contract.gd` 在 HEAD 上本就坏）；战棋自测跑 `scenes/SkillTest.tscn`（44/44）。**地形测试用固化 SHA-256 快照检测回归** —— 改确定性会挂。
- **编辑器缓存坑**：改代码后必须删 `.godot/editor` 目录再重启编辑器，否则跑旧脚本。tab 缩进；文件名 `snake_case.gd`；顶部带 `## file.gd — 职责` 注释。
- **不要往 `main.gd` 加分支**：新 biome / noise / surface / minimap 色 / weather tag 一律走 biome 模块 + 配置 + community；新内容用 `config/ecology/`，**禁用 `legacy_bundles.json` 与 `metadata.legacy_placement_seed`**。
- **确定性契约**：内容 ID / `stream_key` / legacy `placement_seed` 是存档/世界契约；文件路径与显示名绝不能当随机种子；重排 manifest / 改稳定 ID 需 world version 迁移。
- **战棋双模式**：`Settings.battle_inline_mode`（默认 true）切 B1/B2；JSON 战场固定 B2。改 `main.gd` 遵守"新增不修改，分支注入"：B1 逻辑一律 `if _battle_active:` 前置短路。
- **视角只支持 4 正交角度**（0/90/180/270，`isometric_view.gd`）：素材其余角度有拼缝，勿放开连续角度。
- **MCP 调试按会话激活**（见 `AGENTS.md`）：godot 工具**默认不在工具表里**（注入模式「按会话启用」，实测激活 0 / 隐藏 285），先 `mcp_connector_session_tools` preview-activate → activate（`confirmed:true` 由激活方自行设置，member 无需向 lead 申请）；`tool not found` ≠ 没装 godot MCP，别改用 bash 跑 godot。自检用 `find_symbol` + `runtime_get_monitors`（`editor_ping` 不在可激活组）；`dbg_launch` 必传 `scene`；验证用 `runtime_assert_*`，不要 `print` 肉眼判断。
- **`story/` 是目标态设计 bible**（13 职业/27 技能/25 道具），运行时事实是 `data/` 的 8/8/8 —— 勿混用。

> 详细命令、规范与禁忌见 [conventions.md](claude/conventions.md)；agent 工作约束见根 `AGENTS.md`。

## 文件索引

| 文件 | 用途 | 何时阅读 |
| --- | --- | --- |
| [claude/overview.md](claude/overview.md) | 架构总览、运行时形态、关键设计取舍、仓库边界 | **先读** —— 建立全局认知 |
| [claude/conventions.md](claude/conventions.md) | 命令、代码风格、配置/内容规范、调试方法、安全边界 | 动手改代码 / 加内容前 |
| [claude/module-responsibilities.md](claude/module-responsibilities.md) | 子域职责划分、两条数据流、main.gd 函数簇分区、依赖方向 | 定位"某逻辑在哪/该改哪" |
| [claude/entrypoints.md](claude/entrypoints.md) | 引擎入口、4 autoload、场景、main.gd 启动流程、战斗/编辑器入口 | 理解启动 / 入口 |
| [claude/public-interfaces.md](claude/public-interfaces.md) | 玩家输入映射、SceneArgs/Settings 契约、world_to_chapter、JSON 战场 schema、编辑器契约、信号、调试桥 | 理解跨场景/跨模块接口 |
| [claude/dependencies-and-config.md](claude/dependencies-and-config.md) | 依赖（3 vendored 插件）、全部配置文件、环境变量、命令行参数、资源目录约定 | 改配置 / 加物种 / 排查版本 |
| [claude/data-model.md](claude/data-model.md) | CellContext/CellState/确定性RNG、3D 渲染结构、群落模型、战棋 UnitData/Weapon/chapter、JSON 战场文档模型、高度规则 | 理解运行时数据结构 |
| [claude/testing-and-quality.md](claude/testing-and-quality.md) | 测试机制（37 契约分类）、已知验证状态、Lint、质量风险 | 跑测试 / 评估改动风险 |
| [claude/file-map.md](claude/file-map.md) | 完整目录树、scripts/ 文件级地图、快速定位表、文件类型统计 | 找具体文件 |
| [claude/faq.md](claude/faq.md) | 18 条常见问题与定位路径 | 卡住时先查 |
| [claude/changelog.md](claude/changelog.md) | 本索引自身的生成/更新记录（最近 5 条） | 查索引何时/how 更新 |

另有三处专题文档：`rules/`（5 篇 agent 规则：godot-tools-map 295 工具 / 49 可激活地图、mcp-debugging、image-viewing、autoplay-hosting、skill-item-system）、`story/`（19 篇目标态设计 bible）、`HANDOFF.md` + `handoff/`（战棋融合交接与踩坑存档，改战棋前必读）。

## 模块索引

本仓库是**单体 Godot 游戏**，无多 `package.json` 级子工作区。源码子域（`scripts/core`、`systems`、`iso`、`editor`、`battle`、`scenes`、`world`、`ecology`、`animals` 等）属同一应用，统一在 [claude/module-responsibilities.md](claude/module-responsibilities.md) 描述，不单独建 CLAUDE.md。

独立成册的 vendored 模块（`addons/`）：

| 模块 | 职责 | 索引 |
| --- | --- | --- |
| `addons/breakpoint_mcp/` | vendored 调试插件（loopback JSON 桥接编辑器 9080 / 运行时 9081 给 MCP host，v1.23.0） | [addons/breakpoint_mcp/CLAUDE.md](addons/breakpoint_mcp/CLAUDE.md) |
| `addons/panku_console/` | vendored 游戏内 `~` REPL 控制台 v1.7.9（autoload `Panku`；项目 `dbg.*` 命令集在 `scripts/debug_console_commands.gd`） | 上游 README |
| `addons/at-icons/` | vendored SVG 图标库 v1.6.0（700+，MIT；编辑器 UI 只用 `control/` 色系；插件未启用） | 上游 README |
| `addons/pixelfx/` | vendored 像素特效库 v0.3.0（244 个代码绘制特效，24 类：fire/ice/explosions/melee/moves/pickups 等；`PixelFx2D` BAKED/LIVE 双模式 + `PixelFxAct2D` 演出节点，MIT；契约 `tests/pixelfx_contract.gd`） | 上游 README |

### 子系统关系

```mermaid
graph TD
    subgraph 世界生态子系统（3D 正交）
        Main[main.gd 世界引擎]
        World[scripts/world/<br/>地形采样/CellContext/确定RNG/biomes]
        Eco[scripts/ecology/<br/>群落解析/spawner/state]
        Anim[scripts/animals/<br/>行为栈]
        Iso3D[scripts/iso/<br/>Camera3D/柱地形/投影]
        Present[表现层<br/>weather/day_night/sunlight/dof/audio/firefly]
    end
    subgraph 战棋战斗子系统
        Core[scripts/core/<br/>纯逻辑+枚举+battlefield_loader]
        Sys[scripts/systems/<br/>战斗结算]
        Iso[scripts/iso/<br/>battlefield_renderer/iso_coords]
        Editor[scripts/editor/<br/>战场编辑器]
        Battle[scripts/scenes/battle.gd<br/>+scripts/battle/]
    end

    Main --> World --> Eco --> Anim
    Main --> Iso3D
    Main --> Present
    Main -- "按 P + Settings.inline_mode" --> Battle
    Main -- "按 O（JSON 战场）" --> Battle
    Main -- "按 E" --> Editor
    Editor --> Core
    Battle --> Sys --> Core
    Battle --> Iso
    Editor --> Iso
    Core -. "world_to_chapter<br/>（唯一耦合）" .-> World
```

## 扫描状态

- **更新时间**：2026-11-12
- **已扫描**：根目录全部源码结构（`main.gd` 函数级 4099 行 / 174 函数、`scripts/` 文件级 75 `.gd`、`tests/` 37 契约脚本归类、`config/`+`data/` 29 JSON 顶层结构、6 仓库自有 `.tscn`、5 仓库自有 `.gdshader`、3 addons 全量、`story/`+`rules/`+`handoff/`+`HANDOFF.md`+`AGENTS.md` 文档级）。
- **跳过**：`.godot/`（引擎生成，gitignore）；二进制素材 `.png`(198)/`.mp3`(8)；引擎生成物 `.import`/`.uid`。
- **覆盖率**：源码与配置结构 ~100%；二进制素材内容 0%（仅统计）。
- **未执行**：37 个契约测试的运行态验证（需 Godot 环境，`game_hud_contract.gd` 已知在 HEAD 上损坏）。
- **下一步建议**：① 跑一轮 `tests/*_contract.gd` headless 确认基线；② 补 `story/` 目标态与 `data/` 现状的逐项映射表（13 职业 vs 8 职业）；③ 复核 `cell_context_to_terrain` 对 11 地形的覆盖度；④ 推进 `meowa_tiles/heroes/` 职业映射。详见 [claude/changelog.md](claude/changelog.md)。
