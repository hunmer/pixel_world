# 常见问题（FAQ）与定位路径

> 每条给出"问题 → 在哪找答案 / 在哪改"。

### Q1：项目到底是做什么的？两个子系统什么关系？
一个 Godot 4.7 等距像素**生态世界**（无限确定性流式生成 + 动植物/天气/昼夜/3D 阳光阴影），其中**嵌入了回合制战棋战斗**（从 phaserjs 迁移），按 P 在真实地形上战斗，或从 JSON 战场文件开战。两子系统唯一耦合是 `scripts/core/world_to_chapter.gd`；JSON 战场入口是 `battlefield_loader.gd`（产出同构 chapter）。详见 `overview.md` 与 `module-responsibilities.md`。

### Q2：为什么 `main.gd` 这么大（4099 行）？要不要拆？
世界引擎的逻辑高度集中在此单文件。**项目约定明确反对继续往里加分支**（新 biome/noise/surface/community 都走配置/模块）。函数簇分区见 `module-responsibilities.md` 的 main.gd 分区表。如要拆分，需谨慎保持流式生成与确定性的调用顺序。

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
- ⚠️ HANDOFF 记录 B2 世界地形路径未深度验证。详见 `module-responsibilities.md` 战棋数据流 + `testing-and-quality.md`。

### Q7：怎么加一个 JSON 战场 / 用编辑器做地图？
两条路：① 手写 JSON（抄 `data/battlefields/arena_1v1.json`，schema 见 `public-interfaces.md`——`rows` 是**顶层字段**；`BattlefieldLoader` 是唯一权威校验）；② 世界内按 `E` 开编辑器（`scripts/scenes/map_editor.gd` + `scripts/editor/`）：画笔/填充/橡皮/角色四工具，或种子一键生成，保存即回读校验并出现在 O 键列表。用户目录战场放 `user://battlefields/`。

### Q8：视角怎么旋转？为什么只有 4 个角度？
`Z`/`Q`/`←` 逆时针、`X`/`→`（战斗中 `E`）顺时针、中键拖拽平滑旋转；`R` 复位视角、`F` 复位缩放、`Ctrl+R` 才是重新生成世界。3D 正交迁移后**旋转只动 Camera3D**，不重建地形。只有 4 个正交角度（0/90/180/270，`isometric_view.gd SUPPORTED_ANGLES`）是因为素材逐角度验收仅通过四视角，其余角度有地形拼缝。

### Q9：为什么改了代码，调试时跑的还是旧逻辑？
**Godot 编辑器脚本缓存坑**：`dbg_restart` 不会重新编译脚本。改代码后必须删 `.godot/editor` 目录并重启编辑器。详见 `conventions.md`。

### Q10：怎么跑测试？
无测试框架。契约测试：`godot --headless --path . --script res://tests/<name>_contract.gd`（37 个；console 版 exe stdout 全缓冲，管道下无输出≠失败，看退出码或用 timeout 包裹）。战棋自测：编辑器运行 `scenes/SkillTest.tscn`（44/44）。地形测试用固化 SHA-256 快照检测回归。**`game_hud_contract.gd` 在 HEAD 上本来就坏**（--script 模式无 autoload）。详见 `testing-and-quality.md`。

### Q11：确定性被破坏了 / 测试 SHA-256 对不上？
检查是否动了 `DeterministicRng` / `_hash_u32` / `_cell_rand` / `_quantize` / `_seed_point`，或重排了 manifest / 改了稳定 ID / 用文件路径当种子。这些是"存档/世界契约"。详见 `conventions.md` + `data-model.md`。

### Q12：`config/ecosystems.json` 和 `config/ecology/manifest.json` 两套配置什么关系？
**双轨过渡**：`ecosystems.json` 是旧版"首次匹配 ecology"（运行时实际入口）；`ecology/manifest.json` + 模块化 biome/species/communities 是新版，由 `_compile_ecosystem_config` 一起编译。`legacy_bundles.json` 仅旧布局兼容，**新内容禁用**。详见 `dependencies-and-config.md`。

### Q13：`meowa_tiles/heroes/` 是什么？
角色素材目录，**尚未与 `data/professions.json` 的 8 个职业做映射**（已知待办）。

### Q14：调试用的 MCP 工具怎么用？
按 `AGENTS.md`：godot MCP 工具**默认不在工具表里**（连接已配置、注入模式「按会话启用」，实测激活 0 / 会话层隐藏 285），用前必须 `mcp_connector_session_tools` preview-activate → activate（`connectionKey: json-godot`，ttl 1–30 分钟，`confirmed:true` 由激活方自行设置、member 无需向 lead 申请；不跨会话继承）。`tool not found` / 看不见 `mcp__godot__*` **不等于没装 godot MCP**；自检用 `find_symbol` + `runtime_get_monitors`（`editor_ping` 不在可激活的 `runtime,dap,knowledge` 三组内）。`Cannot reach ... 9080` = 编辑器没开或插件未启用。`dbg_launch` 必传 `scene`。295 个工具地图与激活配方见 `rules/godot-tools-map.md`，调试流程见 `rules/mcp-debugging.md`，插件细节见 `addons/breakpoint_mcp/CLAUDE.md`。

### Q15：游戏内 `~` 控制台有什么命令？
Panku REPL（autoload `Panku`），项目命令集 `dbg.*` 注册于 `scripts/debug_console_commands.gd`：`help / list_battlefields / battlefield(id) / editor / enter_battle / battle_mode / player / time_scale`。加新命令 = 对象公共方法 + `_HELP_方法名` 常量，再 `Panku.gd_exprenv.register_env(name, obj)` 注册。

### Q16：`story/` 目录的内容能直接用吗？
**不能**。`story/` 是目标态设计 bible（13 职业/27 技能/25 道品/15 章），运行时事实是 `data/` 的 8 职业/8 技能/8 物品 + 4 个 JSON 战场。实现 story 内容时按 `story/` 规划改 `data/`，勿混用。

### Q17：项目有数据库 / 后端 / 网络吗？
**没有**。纯单机游戏。唯一持久化是 `Settings` 写的 `user://settings.cfg`（+编辑器产出的 `user://battlefields/*.json`）。唯一进程间接口是 breakpoint_mcp 的 loopback 调试桥（9080 编辑器 / 9081 运行时，运行时桥单实例）。

### Q18：在哪能看到代码与 TS 源的对应关系？
战棋部分脚本顶部注释普遍标注对应 TS 源（迁移自 phaserjs）。但 TS 源**不在本仓库**（外部 phaserjs 项目，编辑器 UI 扩展参考 `D:/phaserjs/godot/`）。本仓库是纯 GDScript。
