# AGENTS.md

> 只记硬约束与索引；详细流程见 `rules/`、`claude/`。Godot 工程根 = 本文件目录（含 `project.godot`）。

## 项目

- Godot 4.7（GL Compatibility）/ Node2D 单体 2D 等距生态世界，内嵌回合制战棋；主入口 `res://scenes/Game.tscn`，世界场景 `res://main.tscn`，运行 `godot --path .`。
- 世界引擎集中在 `main.gd`。**不要往 `main.gd` 加分支**：新 biome / noise / surface / minimap 色 / weather tag 走 biome 模块 + `config/ecology/`。
- 确定性契约：内容 ID、`stream_key`、legacy `placement_seed`；文件路径和显示名绝不能当随机种子。
- 运行态验证先确认已加载新代码；若出现编辑器旧脚本缓存问题，再清理 `.godot/editor` 并重启编辑器，纯 headless / 文档改动无需此步骤；tab 缩进，文件名 `snake_case.gd`。
- 测试优先 `python3 tools/run_contracts.py --test <name>`，单契约可用 `godot --headless --path . --script res://tests/<name>_contract.gd`；`res://scenes/SkillTest.tscn` 为历史场景自测入口，自动验收限制见 `rules/skill-item-system.md`。

## Godot MCP（按会话激活，不是常驻）

- **需要游戏运行态 / 画面 / 断点验证 → 先读 skill `godot-debug`**（`.dsh/skills/godot-debug/SKILL.md`）：按代码测试、函数驱动、交互验证的顺序选择方式；激活步骤、断言阶梯、断点链路与已知坑见该 skill，工具签名及「意图 → 工具」表见 `tool-names.md`。纯逻辑、契约测试和静态代码检查按项目测试入口执行，不要求先激活 Godot MCP。
- 命名空间 `mcp__godot__*`（**双下划线**）。连接 `json-godot` **已配置且已连接**（stdio/npx、scope=project `pixel_world`、`BREAKPOINT_TOOLSETS=runtime,dap,knowledge`），但注入模式是 **「按会话启用」**：**工具默认不在工具表里**（2026-11-14 实测 `session_tools status` = 已激活 0 / 会话层隐藏 285）。**未激活直接调用必然 `tool not found`——这不等于没装 godot MCP，也不允许因此改用 bash 跑 godot。**
- 用前先激活（完整配方见 `rules/godot-tools-map.md`）：① `mcp_connector_session_tools({action:"preview-activate", connectionKey:"json-godot", publicNames:["mcp__godot__dbg_launch", ...]})` → ② 取得对应工具激活授权后，按返回的 revision `{action:"activate", connectionKey:"json-godot", publicNames:[...], expectedRevision:<preview 返回>, ttlMinutes:30, confirmed:true}`。仅在用户明确指定激活这些精确工具后设置 `confirmed:true`，遵循当前工具 schema 与上层权限规则；已有对应授权不重复询问。激活在**下一次推理边界**生效，且**不跨会话继承**：新会话与 team 成员在各自会话里重新激活即可。
- 激活只覆盖 `BREAKPOINT_TOOLSETS` 里的组（`runtime_*`、`dbg_*`、`find_symbol` / `find_usages` / `project_search` / `example_snippet`）。`editor_*` 149 个（含 `editor_ping`、`editor_get_state`、`scene_*`、`node_*`、`resource_*`、`ui_*`、`project_*`、`inputmap_*`、`theme_*`、`tileset_*`）、lsp/cslsp、cli、vcs、tabletop、assetgen、netcode、backend、csdap **没纳入这组**：激活也拿不到，别试名字、也别改用 bash 跑 godot——改用 `runtime_*` / `dbg_*` 的等价手段，或让用户在编辑器里操作。
- 找工具名**不要用 `mcp_connector_session_tools({action:"search"})` 逐个试**（单关键词子串匹配，多词必空；`mcp_connector_tool_search` 只能看缓存里有什么名字），查 `.dsh/skills/godot-debug/tool-names.md` 一次拿全，再按 publicName 激活。
- 自检：`find_symbol`（索引通道，不依赖编辑器）+ `runtime_get_monitors`（有游戏在跑才有返回）；`Cannot reach ... 9081` = 还没 `dbg_launch`，属正常；`Cannot reach ... 9080` = 编辑器没开或 Breakpoint MCP 插件未启用。
- `dbg_launch` 必传 `scene`，省略只会进默认主场景。MCP CLI 通道（`GODOT_BIN`）未配置仅影响 MCP `godot_*` 工具；本地 headless / runner 测试照常使用，图形运行态调试走编辑器桥接（`dbg_*` / `runtime_*`）。
- `runtime_get_log` **必须带 `levels`**，否则吐整个环形缓冲（实测 130KB+）。

## 调试与验证（代码优先）

- **优先级：代码测试（单元 / 契约 / headless / 自动模拟）→ 函数或 API 驱动流程 + 自动断言 → 游戏内模拟点击 / 按键。** 能用代码测试覆盖的问题，不打开游戏做模拟点击验证；能通过函数调用、流程接口或自动化脚本控制的游戏流程，不用模拟点击 / 按键推进。
- 优先复用现有测试、CLI、模拟器与流程接口；缺少入口时，优先补最小、可复用的测试或函数驱动入口。只有前两层无法覆盖的真实输入交互、焦点、命中区域或视觉表现问题，才打开对应场景做必要的交互 / 画面验证，并说明需要这一层验证的原因。
- 代码测试以自动断言和退出码验收；确需运行时验证时，先读 `godot-debug`，通过函数 / API 驱动目标流程，用 `runtime_assert_*` 自动验证。按需使用 L1 日志 / L2 断言 / L3 断点定位，不要 `print` 后肉眼判断，也不要为纯逻辑验证强制启动游戏或下断点。
- headless 契约测试走项目测试命令，不因 MCP 未激活而改成打开游戏；MCP 桥接与场景表适用于确需编辑器 / 游戏运行时的验证。
- 只跑与改动相关的测试，不盲目跑全量测试。

## 场景（仅在需要运行时验证时使用）

| 改动 | `dbg_launch` 的 `scene` |
| --- | --- |
| `main.gd`、世界生态、表现层 | `res://main.tscn` |
| 战棋（`scripts/scenes/battle.gd`、`scripts/battle/`、`scripts/systems/`、`scripts/core/`、`scripts/iso/`） | 先 `res://main.tscn`，优先通过函数 / 流程接口进入 B1（玩家入口为 P，仅验证该输入时模拟按键）；`Battle.tscn` 依赖 `SceneArgs.battle_args`，不能无参直启 |
| 技能 / 物品系统 | `res://scenes/SkillTest.tscn` |
| 地图编辑器 | `res://scenes/MapEditor.tscn` |
| 标题 / 主菜单 | `res://scenes/Title.tscn` |
| 契约测试 | 不用 scene，headless 命令行跑 |
| 会话 / 启动路由 | `res://scenes/Game.tscn` |
| 拿不准 | 先明确验证目标，不默认启动游戏 |

## 文档索引

- @claude/overview.md — 架构总览；@claude/conventions.md — 命令 / 规范 / 禁忌
- @rules/godot-tools-map.md — godot 工具分类地图 + **按会话激活配方**（全集 295，旧口径 298；`BREAKPOINT_TOOLSETS=runtime,dap,knowledge` 决定哪 49 个可激活）
- skill `godot-debug` — 运行态 / 画面 / 断点验证前必读：按会话激活步骤、可激活工具清单、场景表、断言阶梯、坑
- @rules/mcp-debugging.md — MCP 调试流程 / 断点 / 已知坑
- @rules/autoplay-hosting.md — 托管自动战斗；截图约束见 @rules/mcp-debugging.md
- @rules/skill-item-system.md — 技能 / 物品 / MP / 冷却
- 本地godot文档大全 - F:\godot-docs-html-stable
