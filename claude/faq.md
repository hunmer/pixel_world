# 常见问题（FAQ）与定位路径

> 更新：2026-11-18（+Q27 冒险模式存档/结算、Q28 建筑素材契约、Q29 技能图鉴；更新 Q1/Q10/Q16/Q17/Q19 与计数）。每条给出"问题 → 在哪找答案 / 在哪改"。

### Q1：项目到底是做什么的？几个子系统什么关系？
一个 Godot 4.7 等距像素**生态世界**（无限确定性流式生成 + 动植物/天气/昼夜/3D 阳光阴影），其中**嵌入了回合制战棋战斗**（从 phaserjs 迁移），外围再包一层**冒险模式**（营地/关卡/商店/掉落/成长，`scripts/campaign/`，**当前默认主入口 `Campaign.tscn`**）。战棋按 P 在真实地形上战斗，或从 JSON 战场文件开战；冒险模式消费战棋（出征→战斗→结算回营地）。世界↔战棋唯一耦合是 `scripts/core/world_to_chapter.gd`；JSON 战场入口是 `battlefield_loader.gd`（产出同构 chapter）。详见 `overview.md` 与 `module-responsibilities.md`。

### Q2：`main.gd` / `map_editor.gd` / `battle.gd` 还能继续拆吗？
**2026-11-16 已完成第一轮拆分**：main.gd 4319→2283 行（能力拆入 `scripts/world/` 11 个 RefCounted 模块，`_configure_generation_services()` 装配）、map_editor.gd 3285→1031 行（拆入 `scripts/editor/` 15 个 `map_editor_*` 模块）、battle.gd 1934→1444 行（演出/存档拆入 `scripts/battle/` 6 模块）。三者现在是"装配层 + 能力模块"形态，仍可按同法继续抽（roadmap P3-13 剩余项）。**约定不变：新能力先进模块再挂装配层，主文件里只留测试直调所需的同名薄委托**；任何拆分需保持流式生成与确定性的调用顺序（拆分护栏：terrain_generation SHA-256 零漂移 + L1 埋点序列一致，见 `docs/plans/split_report_2026-11-15.md`）。哪些模块能直接复用、以及结构/重复/可读性自检见 `report.md`。

### Q3：世界是怎么"无限"生成的？会卡吗？
固定 seed + 流式窗口（`stream_extent` 默认 32）：只生成玩家附近的格，移动时增量生成/释放（`_update_streaming`）。永不预生成整个世界。同 seed+同 cell 永远同结果。chunk 化 3D 地形 + 批量绘制避免每格/每鸟一个节点。详见 `overview.md` + `data-model.md`。

### Q4：怎么加一个新 biome（比如火山）？
**不要改 `main.gd`**。步骤：① 写 `scripts/world/biomes/volcanic_biome.gd`（继承 biome_module）；② 在 `config/ecology/biomes/catalog.json` 注册；③ 配置材质/噪声/minimap 色/weather tag；④ 把想要的 community 挂到该 biome（additive）。完整范例见 `tests/fixtures/volcanic_biome.gd` + `tests/module_extension_contract.gd`。约定见 `config/ecology/README.md`。

### Q5：怎么加一个新动物 / 群落？
① 在 `config/ecology/species/animals.json` 定义物种（资源目录 + actions + movement + behavior）；② 在 `config/ecology/communities/core.json` 定义群落（habitat + distribution + 成员权重）；③ 挂到 biome。**自动走 `CommunitySpawner` + `MemberComposer`，无需写放置代码**。约定见 `config/README.md`。

### Q6：B1（就地战斗）和 B2（切场景）有什么区别？怎么切？
- B1：战斗挂在 `main` 场景树下，相机由 main.gd 接管聚焦战场，不切场景。`Settings.battle_inline_mode=true`（默认）。
- B2：`change_scene_to_file(Battle.tscn)`，战棋作为独立场景。`Settings.battle_inline_mode=false`。
- 切换：游戏内设置面板（`game_hud.gd`），或改 `user://settings.cfg` 的 `[battle] inline_mode`。
- **JSON 战场（O 键列表）固定走 B2**，无论该设置为何。
- ⚠️ B2 世界地形路径未深度验证（历史交接记录）。详见 `module-responsibilities.md` 战棋数据流 + `testing-and-quality.md`。

### Q7：怎么加一个 JSON 战场 / 用编辑器做地图？
两条路：① 手写 JSON（抄 `data/battlefields/arena_1v1.json`，schema 见 `public-interfaces.md`——`rows` 是**顶层字段**，可选 `victory` / `reinforcements` 玩法字段；`BattlefieldLoader` 是唯一权威校验）；② 世界内按 `E` 开编辑器（`scripts/scenes/map_editor.gd` + `scripts/editor/`）：画笔/填充/橡皮/角色/replace 五工具 + **区域复制/剪切/拖动移动/方向键 nudge**，或种子一键生成，保存即回读校验并出现在 O 键列表。用户目录战场放 `user://battlefields/`。编辑器还可从**用户素材库**（AssetLibraryPanel）选导入的方块图当地形贴图，取色器（Alt）可临时吸取画布颜色。

### Q8：视角怎么旋转？为什么只有 4 个角度？
`Z`/`Q`/`←` 逆时针、`X`/`→`（战斗中 `E`）顺时针、中键拖拽平滑旋转；`R` 复位视角、`F` 复位缩放、`Ctrl+R` 才是重新生成世界。3D 正交迁移后**旋转只动 Camera3D**，不重建地形。只有 4 个正交角度（0/90/180/270，`isometric_view.gd SUPPORTED_ANGLES`）是因为素材逐角度验收仅通过四视角，其余角度有地形拼缝。

### Q9：为什么改了代码，调试时跑的还是旧逻辑？
**Godot 编辑器脚本缓存坑**：`dbg_restart` 不会重新编译脚本。改代码后必须删 `.godot/editor` 目录并重启编辑器。详见 `conventions.md`。

### Q10：怎么跑测试？
**统一入口 `python3 tools/run_contracts.py`**（manifest 驱动 **103 项** = 98 默认跑 + 5 environment-skip；`--test/--group/--changed/--all/--jobs/--junit`；2026-11-18 macOS 全量基线 **pass 98 / fail 0 / env-skip 5**）。legacy 单契约：`godot --headless --path . --script res://tests/<name>_contract.gd`（macOS 可执行 `/Applications/Godot.app/Contents/MacOS/Godot`；Windows console 版 exe stdout 全缓冲，管道下无输出≠失败，看退出码）。战棋自测：编辑器运行 `scenes/SkillTest.tscn`（44/44）。另有探针（flat_rotation / mesh_draw 等）与 Node `--test`（素材清单 7 项）。地形测试用固化 SHA-256 快照检测回归。详见 `testing-and-quality.md`。

### Q11：确定性被破坏了 / 测试 SHA-256 对不上？
检查是否动了 `DeterministicRng` / `_hash_u32` / `_cell_rand` / `_quantize` / `_seed_point`，或重排了 manifest / 改了稳定 ID / 用文件路径当种子。这些是"存档/世界契约"。详见 `conventions.md` + `data-model.md`。

### Q12：`config/ecosystems.json` 和 `config/ecology/manifest.json` 两套配置什么关系？
**双轨过渡**：`ecosystems.json` 是旧版"首次匹配 ecology"（运行时实际入口）；`ecology/manifest.json` + 模块化 biome/species/communities 是新版，由 `_compile_ecosystem_config` 一起编译。`legacy_bundles.json` 仅旧布局兼容，**新内容禁用**。收尾计划见 `docs/roadmap.md`。详见 `dependencies-and-config.md`。

### Q13：`meowa_tiles/heroes/` 是什么？
角色素材目录（24 png），**尚未与 `data/professions.json` 的 8 个职业做映射**（已知待办，见 `docs/roadmap.md`）。

### Q14：调试用的 MCP 工具怎么用？
按 `AGENTS.md`：godot MCP 工具**默认不在工具表里**（连接已配置、注入模式「按会话启用」，实测激活 0 / 会话层隐藏 285），用前必须 `mcp_connector_session_tools` preview-activate → activate（`connectionKey: json-godot`，ttl 1–30 分钟，`confirmed:true` 由激活方自行设置、member 无需向 lead 申请；不跨会话继承）。`tool not found` / 看不见 `mcp__godot__*` **不等于没装 godot MCP**；自检用 `find_symbol` + `runtime_get_monitors`（`editor_ping` 不在可激活的 `runtime,dap,knowledge` 三组内）。`Cannot reach ... 9080` = 编辑器没开或插件未启用。`dbg_launch` 必传 `scene`。295 个工具地图与激活配方见 `rules/godot-tools-map.md`，调试流程见 `rules/mcp-debugging.md`，插件细节见 `addons/breakpoint_mcp/CLAUDE.md`。

### Q15：游戏内 `~` 控制台有什么命令？
Panku REPL（autoload `Panku`），项目命令集 `dbg.*` 注册于 `scripts/debug_console_commands.gd`：`help / list_battlefields / battlefield(id) / editor / enter_battle / battle_mode / player / time_scale`。加新命令 = 对象公共方法 + `_HELP_方法名` 常量，再 `Panku.gd_exprenv.register_env(name, obj)` 注册。

### Q16：`story/` 目录的内容能直接用吗？
**不能**。`story/` 是目标态设计 bible（13 职业/27 技能/25 道具/15 章），运行时事实是 `data/` 的 8 职业/8 技能/8 物品 + 8 个 JSON 战场 + campaign 6 关卡。实现 story 内容时按 `story/` 规划改 `data/`，勿混用。逐项差距与推进顺序见 `docs/roadmap.md`。

### Q17：项目有数据库 / 后端 / 网络吗？
**没有后端**。纯单机。磁盘持久化全清单：`user://settings.cfg`（偏好）、`user://campaign_saves/`（**冒险模式档案**）、`user://battle_saves/`（战旗存档）、`user://battlefields/`（自定义战场）、`user://editor_presets/`（编辑器区域命名预设）、`user://custom_assets/`（用户素材 blob）、`user://startup.cfg`（导出后的调试启动配置）。进程间接口：breakpoint_mcp loopback 调试桥（9080 编辑器 / 9081 运行时，单实例）；**用户素材清单源**是唯一出站 HTTP（默认 `http://127.0.0.1:8076/blocks.json` 本机回环；优先级 `asset_source.cfg [asset_source] source_url` 覆盖 > 库内 settings > 默认，断源优雅降级）。

### Q18：在哪能看到代码与 TS 源的对应关系？
战棋部分脚本顶部注释普遍标注对应 TS 源（迁移自 phaserjs）。但 TS 源**不在本仓库**（外部 phaserjs 项目）。本仓库是纯 GDScript。

### Q19：UI 组件库是什么？为什么界面上有两套 UI？
`ui/` 下 21 个 `@tool` 像素功能组件（PixelButton/PixelPanel/…，含 2026-11-18 新增 5 件帧框/名牌/竖 Tab）+ 6 薄布局容器 + `ui/theme/component_theme.gd`。交互画廊 F6（`scenes/UIComponentGallery.tscn`，ESC 退）。**业务迁移现状**：冒险模式 campaign 七屏是首个全 Pixel* 消费者（2026-11-18）；map_editor 已部分迁移；battle_ui / HUD 仍是老 UI——迁移计划见 `docs/roadmap.md`。组件文档：`ui/README.md`。

### Q20：用户素材（自定义方块图）怎么进游戏？
编辑器 → 素材库面板（AssetLibraryPanel）。链路：本机 HTTP 清单源（默认 `http://127.0.0.1:8076/blocks.json`）→ `UserAssetService` 导入（sha 去重幂等）→ `user://custom_assets/` blob → `UserAssetVisualAdapter` 烘焙贴图 → 编辑器/战场渲染。**素材源已可配置**：`asset_source.cfg [asset_source] source_url` 覆盖 > 库内 settings.source_url > 默认，断源优雅降级；换机器改配置或自建源即可（`docs/user_assets.md`）。

### Q21：为什么 F5 直接进了上次的场景？
`config/startup.cfg` 的调试启动配置：`auto_open_last_scene=true` 时启动从 `Game.tscn` 直跳 `last_scene`（`SkillTest` / `UIComponentGallery` 默认排除）。`--battlefield` / `--reset-battle` 命令行优先。想每次都走正常入口就把它关掉。详见 `docs/startup_config.md`。

### Q22：怎么无头跑一场战斗 / 做自动化回归？
`tools/battle_cli.gd`：`godot --headless --path . --script res://tools/battle_cli.gd -- --scenario res://tests/fixtures/battle_scenarios/quick_duel.json [--seed N] [--out DIR]`。产物 events.jsonl / result.json / summary.txt；退出码 0=过 1=断言失败 2=输入错 3=僵持 4=运行错。场景 JSON 支持脚本驱动（script）与 AI 对轰（ai）两种 faction 模式 + 断言。手册：`docs/battle_automation.md`。

### Q23：战斗进度存在哪？换战场会互相覆盖吗？
`user://battle_saves/`，**每个战旗独立档案**（身份 `bf:res|user/<id>` 或 `world:<seed>/<x>/<y>`，文件名=身份+sha1 前缀），互不覆盖；完整行动边界 `GameSession.commit()` 落盘，tmp+bak 原子写，主档损坏自动回退。`--reset-battle[=id]` 只重置目标档案。新版本存档拒绝恢复但不覆盖。冷启动 `Game.tscn` 自动续玩最近战旗。

### Q24：后续要完善的东西在哪看优先级和前置？
`docs/roadmap.md`（2026-11-15 起）：按优先级分层（P0 修坏→P1 补基线→P2 内容扩张→P3 重构/打磨），每项标注前置依赖、验收方式与预估规模；玩法与 story/ 目标态的差距矩阵另见 `docs/gameplay_gap.md`。

### Q25：怎么给战场配胜利条件 / 增援？
战场 JSON 顶层可选字段：`victory: {type: "rout"|"defend_turns"|"seize", turns?: N}`（缺省 rout 歼灭）；`reinforcements: [{turn: N≥1, units: [同 enemyUnits 条目但无 x/y], positions: [{x,y}] 与 units 等长}]`。运行时由 `TurnManager.check_victory` 与 `ReinforcementSpawner.spawn_due`（敌方回合开始刷入，已消费波次从 chapter 移除防存档恢复重刷）消费；样例 `data/battlefields/ambush_reinforce.json` / `last_stand.json`；schema 细节见 `public-interfaces.md`。

### Q26：编辑器的区域预设 / 复制的地形存哪？
区域剪贴板在内存（`EditorRegionClipboard` 五层 payload）；**命名预设**落盘 `user://editor_presets/presets.json`（单文件 + tmp/bak 原子写，`EditorRegionPresetStore` 管理 list/save/load/rename/delete）。两者坐标都相对选区左上角，粘贴时平移。

### Q27：冒险模式的存档和结算怎么工作的？（2026-11-18 新增）
权威文档 `docs/campaign_loop.md`，要点：存档 `user://campaign_saves/`（与旧 `battle_saves/` 隔离，多档案）；出征 `prepare_battle` 先落盘"出征前快照 + attempt 标记"再进战斗（**磁盘永远是安全态**，重载即恢复出征前）；`settle_battle(token)` 一个令牌只结算一次（幂等），胜利 = 首通/重复奖励 + `loot_table` 掉落（**独立 RNG**，种子 = 战场 id + 令牌，不触战斗随机流）+ `level_ups` 升级差分（战斗内演出）；商店购买先落盘后内存，限购周期 = `completed_levels.size()`。旧入口 `Game.tscn` 保留为开发用途。验证：`tests/campaign_contract.gd` 等 4 个契约。

### Q28：建筑素材（四方向精灵图）的契约是什么？（2026-11-18 新增）
`docs/building_assets.md`：4:1 横排 sheet（direction_mode=four_directions），帧选择 `posmod(camera_quadrant - rotation, 4)`；footprint 1..8 格，占用格由 `BuildingLayout.footprint_cells()` 派生（奇数旋转交换 w/h），占用/重叠校验只走 `BuildingLayout`（编辑器保存与 loader 共用唯一实现）；sheet SHA-256 固化在文档。内置素材 `medieval_watchtower` / `spacious_house`（`assets/buildings/*/recipe.json`）；示例战场 `data/battlefields/building_demo.json` / `house_interior_demo.json`。

### Q29：技能图鉴从哪进？（2026-11-18 新增）
标题屏（`scenes/Title.tscn`）的技能图鉴按钮（`SkillListButton`）→ `scenes/SkillList.tscn`（`scripts/scenes/skill_list.gd`）。技能图标走 `scripts/core/skill_icons.gd` 的**稳定 iconId `'01'..'53'`**（永不重排、未知回退默认图标 + warning）；状态图标走 `status_icons.gd`（buff 属性推导）。契约 `tests/skill_icons_contract.gd` / `skill_list`。
