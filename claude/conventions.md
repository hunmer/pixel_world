# 开发约定

> 本文件收集对 Agent 与人类贡献者最实用的命令、规范与禁忌。高优先级条目同时摘要在根 `CLAUDE.md`。

## 运行与启动

```bash
# 打开并运行主场景（要求 Godot 4.6+，本项目用 4.7）
godot --path .

# headless 跑某个契约测试（extends SceneTree 类型，运行后自动退出）
godot --headless --path . --script res://tests/terrain_generation_contract.gd

# 从命令行带参运行场景（CmdArgs 解析 --key / --key=value / --no-key）
godot -d --path . res://main.tscn --seed=42
```

- **主场景**：`res://main.tscn`（`project.godot` 的 `run/main_scene`）。入口脚本 `main.gd`。
- **标题场景**：`res://scenes/Title.tscn` → "进入世界" 按钮切到 main.tscn。

## 编辑器脚本缓存坑（重要兼容性提醒）

来自 `HANDOFF.md`，调试时极易踩：

> `dbg_restart` **不会重新编译脚本**。改完代码后必须清 `.godot/editor` 缓存并重启编辑器，否则跑的是旧脚本。
> Windows 上的等价操作（本仓库实际路径是 `G:\pixel_world`）：
> 删除 `G:/pixel_world/.godot/editor` 目录，然后重开 Godot 编辑器。

## 测试

- **无第三方测试框架**。测试是 GDScript 自测脚本，两种形态：
  1. `tests/*_contract.gd`：`extends SceneTree`，在 `_initialize` → `call_deferred("_run")` 中跑断言，失败用 `push_error` + `quit(1)`。**地形生成测试用固化的 SHA-256 快照检测回归**（改了确定性会挂）。
  2. `scripts/tests/*.gd`：`extends Node`，`_ready` 里自跑 `_ok/_pass/_fail/_print_summary`（仿 `debug_test.gd` 框架）。
- 已知通过状态（来自 HANDOFF，2026-07-28）：`SkillTest.tscn` 44/44、`debug_test.gd` 35/35、`terrain_generation_contract` 快照绿。
- **代码测试 > 截图**：调试时优先用断言 / 日志，不擅自截图（HANDOFF 明示约束）。

## 代码风格

- `.editorconfig`：仅规定 `charset = utf-8`（root）。**无 tab/缩进硬约束写入文件**，但全仓库实际统一用 **tab 缩进**（GDScript 惯例）—— 贡献者请保持 tab。
- GDScript 文件普遍带顶部 `## file.gd — 一句话职责` 文档注释（中文为主），并标注对应 TS 源（战棋部分）。**新文件请延续此风格**。
- 命名：文件名全小写 `snake_case.gd`；类用 `class_name PascalCase`；常量 `UPPER_SNAKE`；私有 `_leading_underscore`。
- 资源目录与 tile 文件统一英文小写 `snake_case`；稳定 species ID 尽量与目录名一致。

## 配置 / 内容规范（最关键的"禁止事项"）

摘自 `config/README.md` 与 `config/ecology/README.md`：

- **不要往 `main.gd` 里加分支**：新的 biome ID、noise ID、surface ID、minimap color、weather tag 都应走 biome 模块 / 配置 / community，而不是在 main.gd 开 if。新算法进 biome 模块，可复用空间布局进 community。
- **新内容走新版模块化配置**：`config/ecology/manifest.json` + `species/` + `communities/` + `biomes/`。**禁止给新内容加 `metadata.legacy_placement_seed` 或写进 `legacy_bundles.json`**（那是兼容旧布局专用）。
- **确定性契约**：ID、`stream_key`、legacy `placement_seed` 是"存档/世界契约"。**文件路径、翻译后的显示名绝不能当随机种子**。重排 manifest 顺序或改稳定 ID 需要 world version 迁移。
- 新模块用唯一命名空间的 `stream_key`（如 `volcanic/fumaroles/member`），现有流保留旧数字 salt。

## 战棋双模式约定（B1 / B2）

- 由 `Settings.battle_inline_mode`（autoload `Settings`，持久化到 `user://settings.cfg`）切换：`true=就地(B1)` / `false=独立场景(B2)`。默认 true。
- 改动 `main.gd` 时遵守"**新增不修改，分支注入**"：B1 逻辑一律 `if _battle_active:` 前置短路，false 时零影响；**不要动 B2 路径代码**。
- 战场坐标 `(0,0)` = 世界 `world_origin + (bx,by)`；`GridSystem` 完全不感知世界坐标，由 `UnitSprite` 渲染时加 origin 转换。

## 调试（MCP 桥）

- 插件 `breakpoint_mcp`（`addons/`）默认在 project.godot 的 `[editor_plugins]` 中**已启用**。监听 `127.0.0.1:9080`（可用 `BREAKPOINT_BRIDGE_PORT` 环境变量覆盖，须在启动 Godot 前设）。
- HANDOFF 记录的 MCP 工具约定（可能依赖外部 MCP host，非本仓库自带）：
  - 每次会话开头先 `editor_ping()`，返回 `pong:true` 才继续。
  - 启动调试：`dbg_launch({scene: "res://main.tscn"})`（必须传 scene）。
  - 改代码后清 `.godot/editor` + 重启编辑器（见上）。

## 安全与边界（本索引工具的自约束）

- 这些文档只读 / 写文档与索引，不改源代码。
- 默认忽略 `.godot/`、二进制大文件（`.png`/`.mp3`/`.import`）。
- 不主动执行 git 提交、分支、reset、checkout。
