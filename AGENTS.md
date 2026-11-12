# AGENTS.md

> 只记硬约束与索引；详细流程见 `rules/`、`claude/`。Godot 工程根 = 本文件目录（含 `project.godot`）。

## 项目

- Godot 4.7（GL Compatibility）/ Node2D 单体 2D 等距生态世界，内嵌回合制战棋；主场景 `res://main.tscn`，运行 `godot --path .`。
- 世界引擎集中在 `main.gd`。**不要往 `main.gd` 加分支**：新 biome / noise / surface / minimap 色 / weather tag 走 biome 模块 + `config/ecology/`。
- 确定性契约：内容 ID、`stream_key`、legacy `placement_seed`；文件路径和显示名绝不能当随机种子。
- 改代码后删 `.godot/editor` 再重启编辑器，否则跑旧脚本；tab 缩进，文件名 `snake_case.gd`。
- 测试：`godot --headless --path . --script res://tests/<name>_contract.gd`；战棋自测跑 `res://scenes/SkillTest.tscn`。

## Godot MCP（工具常驻）

- **要跑游戏 / 查报错 / 验证改动 / 看画面 / 进战斗 / 下断点 → 先读 skill `godot-debug`**（`.dsh/skills/godot-debug/SKILL.md`）：场景表、断言验收阶梯、断点链路、已知坑都在里面；工具签名与「意图 → 工具」表在 `tool-names.md`。
- 命名空间 `mcp__godot__*`（**双下划线**）。连接 `json-godot` 是**始终注入**，`BREAKPOINT_TOOLSETS=runtime,dap,knowledge` → **49 个工具常驻工具表，不需要激活，直接调**。
- 没被注入的组（`editor_*` 149 个、lsp/cslsp、cli、vcs、tabletop、assetgen、netcode、backend、csdap）：调了就是 tool not found，别试名字、也别改用 bash 跑 godot——改用 `runtime_*` / `dbg_*` 的等价手段，或让用户在编辑器里操作。`editor_ping` / `editor_get_state` 就在未注入之列。
- 找工具名**不要用 `mcp_connector_session_tools({action:"search"})` 逐个试**（单关键词子串匹配，多词必空），查 `tool-names.md` 一次拿全。
- 自检：`find_symbol`（索引通道，不依赖编辑器）+ `runtime_get_monitors`（有游戏在跑才有返回）；`Cannot reach ... 9081` = 还没 `dbg_launch`，属正常。
- `dbg_launch` 必传 `scene`，省略只会进默认主场景。CLI 通道（`GODOT_BIN`）未配置，调试全走编辑器桥接（`dbg_*` / `runtime_*`）。
- `runtime_get_log` **必须带 `levels`**，否则吐整个环形缓冲（实测 130KB+）。

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
- @rules/godot-tools-map.md — 298 个 godot 工具地图（分类 / 速查；旧口径，实际注册 295，49 个常驻）
- skill `godot-debug` — 调试 / 验证前必读：常驻工具清单、场景表、断言阶梯、坑
- @rules/mcp-debugging.md — MCP 调试流程 / 断点 / 已知坑
- @rules/image-viewing.md — 图片查看；@rules/autoplay-hosting.md — 托管自动战斗
- @rules/skill-item-system.md — 技能 / 物品 / MP / 冷却
- 本地godot文档大全 - F:\godot-docs-html-stable
