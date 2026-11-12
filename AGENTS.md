# AGENTS.md

> 只记硬约束与索引；详细流程见 `rules/`、`claude/`。Godot 工程根 = 本文件目录（含 `project.godot`）。

## 项目

- Godot 4.7（GL Compatibility）/ Node2D 单体 2D 等距生态世界，内嵌回合制战棋；主场景 `res://main.tscn`，运行 `godot --path .`。
- 世界引擎集中在 `main.gd`。**不要往 `main.gd` 加分支**：新 biome / noise / surface / minimap 色 / weather tag 走 biome 模块 + `config/ecology/`。
- 确定性契约：内容 ID、`stream_key`、legacy `placement_seed`；文件路径和显示名绝不能当随机种子。
- 改代码后删 `.godot/editor` 再重启编辑器，否则跑旧脚本；tab 缩进，文件名 `snake_case.gd`。
- 测试：`godot --headless --path . --script res://tests/<name>_contract.gd`；战棋自测跑 `res://scenes/SkillTest.tscn`。

## Godot MCP（按需激活）

- 命名空间 `mcp__godot__*`（**双下划线**）。连接 `json-godot` 已改为**按会话启用**：默认不注入，先激活精确工具再调用，否则 tool not found。
- 激活：`mcp_connector_session_tools` 的 search → preview-activate → activate（`ttlMinutes` 1–30，下一轮推理生效）。298 个工具的完整分类、常用速查、现成配方见 @rules/godot-tools-map.md。
- 会话首条：激活并调用 `editor_ping`，返回 `pong:true` 才继续。`Cannot reach ... 9080` = 编辑器没开或 `Breakpoint MCP` 插件未启用。
- CLI 通道（`GODOT_BIN`）未配置，调试全走编辑器桥接（`dbg_*` / `runtime_*`）。
- `dbg_launch` 必传 `scene`，省略只会进默认主场景。

## 验证

- 代码改动要加 L1 日志 / L2 断言 / L3 断点，并用 `runtime_assert_*` 自动验证，不要 `print` 后肉眼判断。

## 场景（改哪跑哪）

| 改动 | `dbg_launch` 的 `scene` |
| --- | --- |
| `main.gd`、世界生态、表现层 | `res://main.tscn` |
| 战棋（`scripts/scenes/battle.gd`、`scripts/battle/`、`scripts/systems/`、`scripts/core/`、`scripts/iso/`） | 先 `res://main.tscn`，按 P 进 B1；`Battle.tscn` 依赖 `SceneArgs.battle_args`，不能直启 |
| 技能 / 物品系统 | `res://scenes/SkillTest.tscn` |
| 地图编辑器 | `res://scenes/MapEditor.tscn` |
| 标题 / 主菜单 | `res://scenes/Title.tscn` |
| 契约测试 | 不用 scene，headless 命令行跑 |
| 拿不准 | `res://main.tscn` |

## 文档索引

- @claude/overview.md — 架构总览；@claude/conventions.md — 命令 / 规范 / 禁忌
- @rules/godot-tools-map.md — 298 个 godot 工具地图（分类 / 速查 / 激活配方）
- @rules/mcp-debugging.md — MCP 调试流程 / 断点 / 已知坑
- @rules/image-viewing.md — 图片查看；@rules/autoplay-hosting.md — 托管自动战斗
- @rules/skill-item-system.md — 技能 / 物品 / MP / 冷却
