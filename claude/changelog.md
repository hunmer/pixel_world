# 索引变更记录

> 本文件记录 `CLAUDE.md` 索引本身的生成 / 更新，**不是产品 Changelog**。仅保留最近 5 条（倒序）。

## 2026-11-12 — 增量更新（3D 正交迁移 + JSON 战场 / 编辑器 / 新增目录）

- **触发**：距上次扫描（2026-07-28）三个多月的密集演进，`git log` 显示 2026-11-11 起十余个功能提交。
- **重大变化**：
  - **世界渲染迁移 3D 正交**（33b7028）：`Camera3D` dimetric + chunk 3D 柱地形（`scripts/iso/iso_projection_3d.gd` / `isometric_camera_3d.gd` / `isometric_terrain_3d.gd`），动物改 `AnimatedSprite3D`，`_grid_to_world` 返回 `Vector3`；3D 阳光+地形阴影（3189caf，`sunlight_system.gd` + `config/sunlight.json`）。2D 旋转方案已废弃，踩坑存档 `handoff/2026-11-11-isometric-rotation.md`。
  - **JSON 战场系统**（b7b6881 起）：`core/battlefield_loader.gd`（唯一权威校验）+ `data/battlefields/` 4 示例 + O 键列表面板；`rows` 为顶层字段；固定走 B2。
  - **战场地图编辑器**（7fcb7d9 起）：`scripts/editor/`（battlefield_doc / editor_canvas / tile_preview）+ `scenes/MapEditor.tscn`；E 键入口；四工具 + 种子生成；保存即回读校验。
  - **HUD 改版**：左侧图标按钮栏 + 战场面板 + 设置（4f4dd2d、abb0d14、1337446）。
  - **新 vendored 插件**：panku_console v1.7.9（游戏内 `~` REPL + `dbg.*` 命令集）、at-icons v1.6.0（编辑器 UI 图标）；breakpoint_mcp 升级 v1.9.1→v1.23.0。
  - **战棋地形扩到 11 种**（+grass/sand/rocky/village 等），方块柱高度 h1–h5 规则。
  - **新目录**：`story/`（19 篇目标态设计 bible）、`rules/`（5 篇 agent 规则文档）、`handoff/`、根 `AGENTS.md`。
  - **测试 27→37 个契约**（+3D 渲染/阳光/视角/战棋 3D 拾取/战场/编辑器 10 个）；`game_hud_contract.gd` 确认在 HEAD 上本就损坏。
  - **项目迁移**：G:/ → E:/；Godot 4.7.2，autoload 增至 4 个（+Panku）。
- **更新文件**：`claude/` 全部 10 个详情文件重写/更新 + 根 `CLAUDE.md` 索引重写 + `addons/breakpoint_mcp/CLAUDE.md` 版本号修正。
- **覆盖率**：`main.gd` 函数级（4099 行/174 函数）、`scripts/` 文件级（75 .gd）、`tests/` 37 契约归类、`config/`+`data/` 逐文件、6 自有 `.tscn`、`story/`+`rules/`+`handoff/` 文档级。二进制素材仍仅统计。
- **缺口 / 下一步建议**：
  1. 37 个契约的当前通过状态**未逐一执行**（game_hud 已知坏）—— 建议跑一轮 headless 基线。
  2. `story/` 13 职业/27 技能与 `data/` 8/8 的差距未逐项列映射表 —— 开始实现剧情内容前补。
  3. `cell_context_to_terrain` 对 11 地形的覆盖度未复核。
  4. `meowa_tiles/heroes/` 职业映射待办未动。

## 2026-07-28 — 初始化（首次生成）

- **范围**：全仓库根目录 + 1 个 vendored 模块（`addons/breakpoint_mcp`）。
- **生成**：
  - 根 `CLAUDE.md`（轻量索引）+ `claude/` 下 10 个详情文件。
  - `addons/breakpoint_mcp/CLAUDE.md` + 其 `claude/`。
- **识别的"模块"判定**：仓库为单体 Godot 游戏；`scripts/` 各子目录是同应用内的源码子域，统一描述，避免过度碎片化。唯一带独立 `plugin.cfg` 的 `addons/breakpoint_mcp` 单列。
- **覆盖率**：源码层 104 个 `.gd` 全部纳入结构归纳；22 个 `.json` 配置逐文件结构化；4 个 `.tscn`、7 个 `.md`、4 个 `.gdshader` 已覆盖。未深度读取二进制素材与引擎生成物。
- **缺口 / 下一步建议**：契约测试通过状态未执行验证；战棋 `core/`/`systems/` 函数签名未逐行展开；shaders 参数未记录；外部 `phaserjs/` 源不在本仓库。
