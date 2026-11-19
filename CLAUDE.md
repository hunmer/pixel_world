# Pixel World — AI 上下文索引

## 项目简单介绍

Pixel World 是一个 **Godot 4.7（GL Compatibility）/ Node2D** 单体 2D 游戏：在 3D 正交（dimetric）视口下，按固定种子实时、确定性、流式生成一个"无限"像素生态世界 —— 地形、生物群系（温带/沙漠/雪地/水域/岸）、植物群落、动物（13 种）、天气（雨/雪）、昼夜与月光、3D 阳光与地形阴影、萤火虫、音乐与空间音效。渲染为 chunk 化 3D 柱地形 + Camera3D（视角旋转只动相机）。

世界中嵌入了从另一个项目（phaserjs）迁移来的**回合制战棋战斗**系统；战棋外围再包一层**冒险模式**（营地/关卡/商店/装备/掉落/成长，`scripts/campaign/`）作为**当前默认主入口** `res://scenes/Campaign.tscn`：存档选择 → 营地 Hub → 关卡列表 → 出征（先落盘快照再进战斗）→ 结算（首通/重复奖励 + 独立 RNG 掉落 + 升级差分演出）→ 回营地（权威文档 `docs/campaign_loop.md`）。旧入口 `res://scenes/Game.tscn` 保留为开发用途（战旗会话路由，按 `P` 就地战斗 B1 / 切场景 B2、按 `O` 选 JSON 预制战场、按 `E` 开战场地图编辑器）。战棋含**胜利条件 rout/defend_turns/seize、按回合波次增援、背击/夹击规则、行动历史【记录】Tab 跨回合回退、战斗内升级演出、可选沉浸舞台演出（ImmersiveStage，纯表现）**；**装备四槽**（weapon/shield/staff/relic，`core/equipment.gd` 单一权威 + 双口径加成）经营地装备屏操作；编辑器支持画笔/填充/橡皮/角色 + 种子生成 + 区域复制/移动/命名预设 + 取色器 + 用户素材库 + **建筑摆放（四方向精灵图）/角色编辑**，保存即校验入列。战棋地形 11 种，等距方块柱渲染（含建筑层与室内战场）。两个子系统的唯一耦合点是 `scripts/core/world_to_chapter.gd`；JSON 战场由 `scripts/core/battlefield_loader.gd` 平行供给。UI 层有 **27 组件像素组件库 + DESIGN.md 设计 token 规范**（`ui/`，token 唯一实现 `ComponentTheme`；冒险模式七屏是首个全量消费者）。另有 `scenes/CharacterMovementTest.tscn` 人物移动测试台（extends main.gd，消费免费角色包 `scripts/characters/` 20 角色；当前 startup.cfg 直跳目标）。

世界引擎装配层在 `main.gd`（2026-11-16 拆分后 2280 行；生成/生态/表现能力拆入 `scripts/world/` 模块，`_configure_generation_services()` 统一装配）。运行 `godot --path .`（主场景 Campaign.tscn）。纯单机：磁盘持久化 = `user://settings.cfg`、`user://campaign_saves/`（冒险档案）、`user://battle_saves/`（战旗存档）、`user://battlefields/`、`user://custom_assets/`（用户素材）与调试用 `config/startup.cfg`。

## 约定的规则（高优先级）

- **运行**：`godot --path .`。本机（macOS）`/Applications/Godot.app/Contents/MacOS/Godot`（实测 4.7.1；Windows 历史路径 `D:/Godot/Godot_v4.7.2-stable_win64.exe`；console 版 stdout 全缓冲：管道无输出 ≠ 没输出）。主场景 `res://scenes/Campaign.tscn`（冒险模式）；`config/startup.cfg` 可让 F5 直跳最近场景。
- **测试**：默认入口 `python3 tools/run_contracts.py`（manifest 驱动 **110 项**；当前口径 **pass 105 / fail 0 / env-skip 5**——2026-11-19 macOS 全量基线，HEAD e3df43b）；单契约直跑 `godot --headless --path . --script res://tests/<name>_contract.gd`；批量模拟 `tools/run_simulations.gd`（详见 `docs/test_automation.md` 与 `claude/testing-and-quality.md`）；战棋自测跑 `scenes/SkillTest.tscn`（44/44）。**地形测试用固化 SHA-256 快照检测回归** —— 改确定性会挂。素材清单/切片生成器用 `node --test`。已知盘上 8 个契约未录 manifest（清单见 `claude/faq.md` Q34），runner 每次告警属已知状态。
- **编辑器缓存坑**：运行态验证先确认新代码已加载；出现旧脚本缓存问题时再清理 `.godot/editor` 并重启编辑器，纯 headless / 文档改动无需此步骤。tab 缩进；文件名 `snake_case.gd`；顶部带 `## file.gd — 职责` 注释。
- **不要往 `main.gd` 加分支**：新 biome / noise / surface / minimap 色 / weather tag 一律走 biome 模块 + 配置 + community；新内容用 `config/ecology/`，**禁用 `legacy_bundles.json` 与 `metadata.legacy_placement_seed`**。
- **确定性契约**：内容 ID / `stream_key` / legacy `placement_seed` 是存档/世界契约；文件路径与显示名绝不能当随机种子；重排 manifest / 改稳定 ID 需 world version 迁移。**冒险模式掉落用独立 RNG**（种子=战场 id+出征令牌），不触战斗随机流；**图标 iconId '01'..'53' 永不重排**（物品 '01'..'08' / 装备 '01'..'11' 图标目录同此契约）。
- **装备单一权威 + 双口径**（2026-11-19 新增）：装备规则（四槽/职业限制/加成/容量）只改 `scripts/core/equipment.gd`（EquipmentDataScript 全静态）；战斗 buff 加成 = base + `stat_bonus`，HP/MP 容量 = base + 装备（**不含 buff**），两口径勿混用；实际武器一律 `WeaponData.unit_weapon()`（装备槽优先，空装回退 `unit.weapon`）；equip/unequip 先落盘后内存、幂等。
- **冒险模式磁盘安全**（`docs/campaign_loop.md`）：出征先落盘快照+attempt 再进战斗；`settle_battle(token)` 幂等；购买先落盘后内存；限购周期=通关数；campaign 存档 `user://campaign_saves/` 与 `battle_saves/` 隔离（出征 `save_identity` 留空）。
- **战棋双模式**：`Settings.battle_inline_mode`（默认 true）切 B1/B2；JSON 战场固定 B2。改 `main.gd` 遵守"新增不修改，分支注入"：B1 逻辑一律 `if _battle_active:` 前置短路。战斗结算与表现分离：`battle_action_resolver.gd` 是共享结算内核，勿在演出层复写结算；沉浸舞台（ImmersiveStage，`Settings.battle_immersive_presentation` 开关）同此约束——纯表现，不碰结算。建筑占用/重叠校验只走 `BuildingLayout`。
- **视角只支持 4 正交角度**（0/90/180/270，`isometric_view.gd`）：素材其余角度有拼缝，勿放开连续角度。
- **MCP 运行态调试按会话激活**（见 `AGENTS.md`）：先选代码测试；确需运行态时再激活对应 Godot 工具。工具默认不在工具表里，按 `mcp_connector_session_tools` preview-activate → activate；`tool not found` ≠ 没装 MCP。`dbg_launch` 必传 `scene`；运行态验证通过函数/API 控制并用 `runtime_assert_*` 自动验收，不要 `print` 后肉眼判断。
- **UI 走 DESIGN.md + 组件库**：新界面一律用 `ui/` 的 Pixel* 组件（27 个）+ `ComponentTheme` token，禁裸数字样式值 / 自建 StyleBox / 绝对定位 / 横向滚动（规范见根 `DESIGN.md`）；`tests/ui_contract.gd` 静态扫描业务脚本禁直建 `Button/CheckButton/OptionButton.new()`。
- **`story/` 是目标态设计 bible**（13 职业/27 技能/25 道具/15 章），运行时事实是 `data/` 的 8/8/8 + 8 JSON 战场 + campaign 6 关 —— 勿混用；差距与推进顺序见 `docs/roadmap.md` 与 `docs/gameplay_gap.md`。

> 详细命令、规范与禁忌见 [conventions.md](claude/conventions.md)；agent 工作约束见根 `AGENTS.md`。

## 文件索引

| 文件 | 用途 | 何时阅读 |
| --- | --- | --- |
| [claude/overview.md](claude/overview.md) | 架构总览、运行时形态、关键设计取舍、仓库边界 | **先读** —— 建立全局认知 |
| [claude/conventions.md](claude/conventions.md) | 命令、代码风格、配置/内容规范、调试方法、安全边界 | 动手改代码 / 加内容前 |
| [claude/module-responsibilities.md](claude/module-responsibilities.md) | 子域职责划分、数据流、main.gd 函数簇分区、依赖方向 | 定位"某逻辑在哪/该改哪" |
| [claude/entrypoints.md](claude/entrypoints.md) | 引擎入口、9 autoload、场景表、Campaign/Game/main 启动流程、战斗/编辑器入口 | 理解启动 / 入口 |
| [claude/public-interfaces.md](claude/public-interfaces.md) | 玩家输入映射、SceneArgs/Settings/GameSession/CampaignSession 契约、素材服务/组件库/CLI 接口、JSON 战场 schema、信号 | 理解跨场景/跨模块接口 |
| [claude/dependencies-and-config.md](claude/dependencies-and-config.md) | 依赖（6 vendored 插件）、全部配置文件、素材源、命令行参数 | 改配置 / 加物种 / 排查版本 |
| [claude/data-model.md](claude/data-model.md) | CellContext/CellState/确定性RNG、3D 渲染结构、群落模型、战棋 UnitData/chapter、冒险档案模型、存档/素材/对话模型 | 理解运行时数据结构 |
| [claude/testing-and-quality.md](claude/testing-and-quality.md) | 测试机制（110 契约 + 统一 runner + gdtest/autosim）、基线状态、Lint、质量风险 | 跑测试 / 评估改动风险 |
| [claude/file-map.md](claude/file-map.md) | 完整目录树、scripts/ 文件级地图、快速定位表 | 找具体文件 |
| [claude/faq.md](claude/faq.md) | 常见问题与定位路径 | 卡住时先查 |
| [claude/report.md](claude/report.md) | **代码自检报告**：结构与职责 / 重复 / 可读性 / 可复用资产（UI 三层链 / 共享内核 / world 模块 / 编辑器组件 / autoload）+ 复用守则 | 写新功能前先查"有没有现成的"；排查质量问题时 |
| [claude/changelog.md](claude/changelog.md) | 本索引自身的生成/更新记录（最近 5 条） | 查索引何时/how 更新 |
| [DESIGN.md](DESIGN.md) | **UI 设计规范单一事实来源**：token 体系、六薄容器、禁忌、三档分辨率验收 | 写任何新 UI 前 |
| [docs/roadmap.md](docs/roadmap.md) | **后续完善项清单**：按优先级分层 + 前置依赖 + 验收方式 | 规划下一步工作 |

另有专题文档：`rules/`（4 篇 agent 规则：godot-tools-map 295 工具 / 49 可激活地图、mcp-debugging、autoplay-hosting、skill-item-system）、`story/`（19 篇目标态设计 bible）、`handoff/`（3 篇专题交接踩坑：isometric-rotation / game-sfx-system / immersive-battle-presentation）、`docs/`（campaign_loop 冒险模式权威文档 / building_assets 建筑素材契约 / battle_automation / test_automation / startup_config / user_assets / gameplay_gap 玩法差距矩阵 / feature_map 功能图谱 / testing_baseline 全量基线）、`plans/`（开发计划存档）、`ui/README.md`（UI 组件库）。

## 模块索引

本仓库是**单体 Godot 游戏**，无多 `package.json` 级子工作区。源码子域（`scripts/core`、`systems`、`iso`、`editor`、`battle`、`campaign`、`scenes`、`assets`、`audio`、`ui`、`world`、`ecology`、`animals` 等）属同一应用，统一在 [claude/module-responsibilities.md](claude/module-responsibilities.md) 描述，不单独建 CLAUDE.md。

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
    subgraph 冒险模式子系统（当前主入口）
        Camp[Campaign.tscn + CampaignSession autoload<br/>存档/营地/关卡/商店/装备/出征结算]
        CampScr[scripts/scenes/campaign_*.gd<br/>七屏 UI 全 Pixel* 组件]
    end
    subgraph 世界生态子系统（3D 正交）
        Main[main.gd 装配层<br/>2280 行/_configure_generation_services]
        World[scripts/world/ 20 模块<br/>地形采样/CellContext/确定RNG/biomes<br/>flora/fauna/minimap/表现装配/配置编译/材质解析]
        Eco[scripts/ecology/<br/>群落解析/spawner/state]
        Anim[scripts/animals/<br/>行为栈]
        Iso3D[scripts/iso/<br/>Camera3D/柱地形/投影/建筑视图]
        Present[表现层模块<br/>weather/day_night/sunlight/dof/audio/sfx/firefly]
        MoveTest[scenes/CharacterMovementTest.tscn<br/>extends main.gd 人物移动测试台]
    end
    subgraph 战棋战斗子系统
        Session[Game.tscn + GameSession<br/>会话路由/存档（开发入口）]
        Core[scripts/core/<br/>纯逻辑+battlefield_loader+存档codec<br/>+BuildingLayout/室内/图标/装备]
        Sys[scripts/systems/<br/>战斗结算+AI难度+背击/夹击+威胁+交换]
        Battle[scripts/scenes/battle.gd + scripts/battle/<br/>演出/自动化/行动历史/升级演出/出征桥/沉浸舞台]
        Editor[scripts/editor/<br/>战场编辑器+素材面板+建筑+角色编辑]
        Assets[scripts/assets/<br/>用户素材服务+内置建筑素材]
    end

    Campaign[scenes/Campaign.tscn 主入口] --> Camp --> CampScr
    Camp -- "prepare_battle/settle_battle<br/>campaign_battle_bridge" --> Battle
    Game[scenes/Game.tscn 开发入口] --> Session
    Main --> World --> Eco --> Anim
    Main --> Iso3D
    Main --> Present
    MoveTest -. 继承装配 .-> Main
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

- **更新时间**：2026-11-19（第五轮增量：**装备系统**〔`core/equipment.gd` 四槽单一权威 + `data/equipment.json` 11 条 + 营地装备屏 `campaign_equipment.gd` + buff/weapons/roster 三消费方一行委托〕、**免费角色包与职业切片**〔`scripts/characters/` 2 件 + `tools/slice_profession_sheets.py`〕、**人物移动测试台**〔`scenes/CharacterMovementTest.tscn` 三件套，extends main.gd 真实生态〕、**ImmersiveStage 沉浸舞台**〔`battle/immersive_stage.gd`+`layout` + battle.gd 接线，纯表现〕、**物品/装备图标两目录**〔`assets/ui/items/` 8 + `assets/ui/equipment/` 11〕、契约 103→110〔**macOS 全量基线 pass 105 / fail 0 / env-skip 5**，HEAD e3df43b〕）。
- **已扫描**：根目录全部源码结构（`main.gd` 2280 行、`map_editor.gd` 1088 行、`battle.gd` 2273 行/122 函数、`campaign_session.gd` 1044 行/41 函数、`scripts/` 文件级 206 `.gd`〔campaign 6 / editor 28 / battle 28 / core 21 / systems 14 / iso 17 / scenes 24 / world 20 / ecology 8 / assets 5 / ui_gallery 6 / characters 2 / debug 等其余〕、`tests/` 122 `.gd`〔manifest 110 契约 + 3 探针 + gdtest + benches〕、`config/`+`data/` JSON〔含 equipment.json / battlefields 8〕、`scenes/` 15 `.tscn`、6 自有 `.gdshader`、6 addons 全量、automation/assets/ui/editor/world/campaign/equipment/characters 子系统 API 级、`DESIGN.md`+`story/`+`rules/`+`handoff/`+`docs/` 文档级）。
- **运行态验证**：统一 runner 口径 **pass 105 / known-fail 0 / env-skip 5**（`.tmp/init_baseline_2026-11-19/`，2026-11-19，Godot 4.7.1，HEAD e3df43b）；7 个新契约（equipment/equipment_icons/equipment_integration/item_icons/free_character_sheet/immersive_stage/character_movement_test）全过；拆分护栏 = terrain_generation SHA-256 零漂移（`docs/plans/split_report_2026-11-15.md`）；批量模拟 1000 局 3.6s。
- **功能依赖图谱**：`docs/feature_map.json` + `feature_map.html` 本轮已更新 —— **12 顶级功能类**（新增 characters🧍）、**447/447 = 100% 覆盖**、unmapped 18（.tmp/ 等）、vendored 6；`feature_map.py all` check 全过。
- **代码自检**：`claude/report.md` 已按 2026-11-19 实测重写（观察项 battle.gd 2273/122 连续两轮 +100 行级增长、campaign_session.gd 1044 / `_settle_win` 93 行；复用计数 ui_factory 40 文件 / resolver 10 / BuildingLayout 9 / EquipmentDataScript 8；复用守则 6 条）。
- **跳过**：`.godot/`（引擎生成，gitignore）；`.tmp/`（跨机调试工作目录）；二进制素材 `.png`/`.mp3`；引擎生成物 `.import`/`.uid`。
- **覆盖率**：源码与配置结构 ~100%（feature_map 447/447）；二进制素材内容 0%（仅统计）。
- **下一步建议**：功能项已整理进 [docs/roadmap.md](docs/roadmap.md)（2026-11-19 清理版）；本轮新增工程建议——**manifest 补录 8 个缺录契约**（清单见 `claude/faq.md` Q34，缺录项不进默认跑与 `--changed` 闭包）、battle.gd 记录 Tab 拆分、`campaign_settlement` 抽取（`claude/report.md` §1）。
