# AGENTS.md

> 只记硬约束与索引；详细流程见 `rules/`、`claude/`。Godot 工程根 = 本文件目录（含 `project.godot`）。

## 项目

- Godot 4.7（GL Compatibility）/ Node2D 单体 2D 等距生态世界，内嵌回合制战棋；主场景 `res://main.tscn`，运行 `godot --path .`。
- 世界引擎集中在 `main.gd`。**不要往 `main.gd` 加分支**：新 biome / noise / surface / minimap 色 / weather tag 走 biome 模块 + `config/ecology/`。
- 确定性契约：内容 ID、`stream_key`、legacy `placement_seed`；文件路径和显示名绝不能当随机种子。
- 改代码后删 `.godot/editor` 再重启编辑器，否则跑旧脚本；tab 缩进，文件名 `snake_case.gd`。
- 测试：`godot --headless --path . --script res://tests/<name>_contract.gd`；战棋自测跑 `res://scenes/SkillTest.tscn`。

## Godot MCP（按会话激活，不是常驻）

- **要跑游戏 / 查报错 / 验证改动 / 看画面 / 进战斗 / 下断点 → 先读 skill `godot-debug`**（`.dsh/skills/godot-debug/SKILL.md`）：激活步骤、场景表、断言验收阶梯、断点链路、已知坑都在里面；工具签名与「意图 → 工具」表在 `tool-names.md`。
- 命名空间 `mcp__godot__*`（**双下划线**）。连接 `json-godot` **已配置且已连接**（stdio/npx、scope=project `pixel_world`、`BREAKPOINT_TOOLSETS=runtime,dap,knowledge`），但注入模式是 **「按会话启用」**：**工具默认不在工具表里**（2026-11-14 实测 `session_tools status` = 已激活 0 / 会话层隐藏 285）。**未激活直接调用必然 `tool not found`——这不等于没装 godot MCP，也不允许因此改用 bash 跑 godot。**
- 用前先激活（完整配方见 `rules/godot-tools-map.md`）：① `mcp_connector_session_tools({action:"preview-activate", connectionKey:"json-godot", publicNames:["mcp__godot__dbg_launch", ...]})` → ② 按返回的 revision 直接 `{action:"activate", connectionKey:"json-godot", publicNames:[...], expectedRevision:<preview 返回>, ttlMinutes:30, confirmed:true}`。**agent / team member / subagent 都可按任务需要自主决定激活哪些工具并自行设置 `confirmed:true`，无需向 lead 申请或等用户点名**。激活在**下一次推理边界**生效，且**不跨会话继承**：新会话与 team 成员在各自会话里重新激活即可。
- 激活只覆盖 `BREAKPOINT_TOOLSETS` 里的组（`runtime_*`、`dbg_*`、`find_symbol` / `find_usages` / `project_search` / `example_snippet`）。`editor_*` 149 个（含 `editor_ping`、`editor_get_state`、`scene_*`、`node_*`、`resource_*`、`ui_*`、`project_*`、`inputmap_*`、`theme_*`、`tileset_*`）、lsp/cslsp、cli、vcs、tabletop、assetgen、netcode、backend、csdap **没纳入这组**：激活也拿不到，别试名字、也别改用 bash 跑 godot——改用 `runtime_*` / `dbg_*` 的等价手段，或让用户在编辑器里操作。
- 找工具名**不要用 `mcp_connector_session_tools({action:"search"})` 逐个试**（单关键词子串匹配，多词必空；`mcp_connector_tool_search` 只能看缓存里有什么名字），查 `.dsh/skills/godot-debug/tool-names.md` 一次拿全，再按 publicName 激活。
- 自检：`find_symbol`（索引通道，不依赖编辑器）+ `runtime_get_monitors`（有游戏在跑才有返回）；`Cannot reach ... 9081` = 还没 `dbg_launch`，属正常；`Cannot reach ... 9080` = 编辑器没开或 Breakpoint MCP 插件未启用。
- `dbg_launch` 必传 `scene`，省略只会进默认主场景。CLI 通道（`GODOT_BIN`）未配置，调试全走编辑器桥接（`dbg_*` / `runtime_*`）。
- `runtime_get_log` **必须带 `levels`**，否则吐整个环形缓冲（实测 130KB+）。

## 验证

- 代码改动要加 L1 日志 / L2 断言 / L3 断点，并用 `runtime_assert_*` 自动验证，不要 `print` 后肉眼判断。
- 只跑修改过的测试，不盲目跑全量测试

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
- @rules/godot-tools-map.md — godot 工具分类地图 + **按会话激活配方**（全集 295，旧口径 298；`BREAKPOINT_TOOLSETS=runtime,dap,knowledge` 决定哪 49 个可激活）
- skill `godot-debug` — 调试 / 验证前必读：按会话激活步骤、可激活工具清单、场景表、断言阶梯、坑
- @rules/mcp-debugging.md — MCP 调试流程 / 断点 / 已知坑
- @rules/image-viewing.md — 图片查看；@rules/autoplay-hosting.md — 托管自动战斗
- @rules/skill-item-system.md — 技能 / 物品 / MP / 冷却
- 本地godot文档大全 - F:\godot-docs-html-stable
