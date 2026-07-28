# 常见问题（FAQ）与定位路径

> 每条给出"问题 → 在哪找答案 / 在哪改"。

### Q1：项目到底是做什么的？两个子系统什么关系？
一个 Godot 4.7 等距像素**生态世界**（无限确定性流式生成 + 动植物/天气/昼夜），其中**嵌入了回合制战棋战斗**（从 phaserjs 迁移），按 P 在真实地形上战斗。两子系统唯一耦合是 `scripts/core/world_to_chapter.gd`。详见 `overview.md` 与 `module-responsibilities.md`。

### Q2：为什么 `main.gd` 这么大（3886 行）？要不要拆？
世界引擎的逻辑高度集中在此单文件。**项目约定明确反对继续往里加分支**（新 biome/noise/surface/community 都走配置/模块）。函数簇分区见 `module-responsibilities.md` 的 main.gd 分区表。如要拆分，需谨慎保持流式生成与确定性的调用顺序。

### Q3：世界是怎么"无限"生成的？会卡吗？
固定 seed + 流式窗口（`stream_extent` 默认 32）：只生成玩家附近的格，移动时增量生成/释放（`_update_streaming`）。永不预生成整个世界。同 seed+同 cell 永远同结果。批量绘制避免每格/每鸟一个节点。详见 `overview.md` + `data-model.md`。

### Q4：怎么加一个新 biome（比如火山）？
**不要改 `main.gd`**。步骤：① 写 `scripts/world/biomes/volcanic_biome.gd`（继承 biome_module）；② 在 `config/ecology/biomes/catalog.json` 注册；③ 配置材质/噪声/minimap 色/weather tag；④ 把想要的 community 挂到该 biome（additive）。完整范例见 `tests/fixtures/volcanic_biome.gd` + `tests/module_extension_contract.gd`。约定见 `config/ecology/README.md`。

### Q5：怎么加一个新动物 / 群落？
① 在 `config/ecology/species/animals.json` 定义物种（资源目录 + actions + movement + behavior）；② 在 `config/ecology/communities/core.json` 定义群落（habitat + distribution + 成员权重）；③ 挂到 biome。**自动走 `CommunitySpawner` + `MemberComposer`，无需写放置代码**。约定见 `config/README.md`。

### Q6：B1（就地战斗）和 B2（切场景）有什么区别？怎么切？
- B1：单位挂在 `main` 场景树下，相机固定聚焦战场，不切场景。`Settings.battle_inline_mode=true`（默认）。
- B2：`change_scene_to_file(Battle.tscn)`，战棋作为独立场景。`Settings.battle_inline_mode=false`。
- 切换：游戏内"⚙ 设置"面板（`game_hud.gd`），或改 `user://settings.cfg` 的 `[battle] inline_mode`。
- ⚠️ HANDOFF 记录 **B2 模式未深度验证**。详见 `module-responsibilities.md` 战棋数据流 + `testing-and-quality.md`。

### Q7：为什么改了代码，调试时跑的还是旧逻辑？
**Godot 编辑器脚本缓存坑**：`dbg_restart` 不会重新编译脚本。改代码后必须删 `.godot/editor` 目录并重启编辑器。详见 `conventions.md` 的"编辑器脚本缓存坑"。

### Q8：怎么跑测试？
无测试框架。契约测试：`godot --headless --path . --script res://tests/<name>_contract.gd`。战棋自测：编辑器运行 `scenes/SkillTest.tscn`（headless）。地形测试用固化 SHA-256 快照检测回归。详见 `testing-and-quality.md`。

### Q9：确定性被破坏了 / 测试 SHA-256 对不上？
检查是否动了 `DeterministicRng` / `_hash_u32` / `_cell_rand` / `_quantize` / `_seed_point`，或重排了 manifest / 改了稳定 ID / 用文件路径当种子。这些是"存档/世界契约"。详见 `conventions.md` 的"配置/内容规范" + `data-model.md`。

### Q10：`config/ecosystems.json` 和 `config/ecology/manifest.json` 两套配置什么关系？
**双轨过渡**：`ecosystems.json` 是旧版"首次匹配 ecology"（运行时实际入口，`_load_ecosystem_config` 读取）；`ecology/manifest.json` + 模块化 biome/species/communities 是新版，由 `_compile_ecosystem_config` 一起编译。`legacy_bundles.json` 仅旧布局兼容，**新内容禁用**。详见 `dependencies-and-config.md`。

### Q11：`meowa_tiles/heroes/` 是什么？
当前是 `animals/` 的副本，**尚未与 `data/professions.json` 的职业做映射**（已知待办）。见 HANDOFF 中优先级待办 #5。

### Q12：调试用的 MCP 工具怎么用？
`addons/breakpoint_mcp`（已启用）在 `127.0.0.1:9080` 提供 loopback JSON 桥，需外部 MCP host 配合。HANDOFF 记录的约定：先 `editor_ping()` 返回 `pong:true` 才继续；`dbg_launch({scene:"res://main.tscn"})`。详见 `addons/breakpoint_mcp/README.md` 与其独立 `CLAUDE.md`。

### Q13：项目有数据库 / 后端 / 网络吗？
**没有**。纯单机游戏。唯一持久化是 `Settings` 写的 `user://settings.cfg`。唯一进程间接口是 breakpoint_mcp 的 loopback 调试桥。

### Q14：在哪能看到代码与 TS 源的对应关系？
战棋部分脚本顶部注释普遍标注"对应 src/xxx.ts"（迁移自 phaserjs）。但 **`src/` 不在本仓库**（那是外部 phaserjs 项目）。本仓库是纯 GDScript。
