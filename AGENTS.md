# AGENTS.md

本文件只记**关键约束**和**文档索引**。详细操作流程见 `rules/`，踩坑记录见 `knowledges/`。

## 项目定位

- Godot 工程目录：`D:/phaserjs/godot`
- 工程文件：`D:/phaserjs/godot/project.godot`
- 主场景：`res://scenes/Title.tscn`
- 运行窗口标题通常是：`Tactics RPG (DEBUG)`

## 关键约束（必须遵守）

- **MCP 命名空间**：`mcp__godot__*`（**双下划线**，点号写法 `mcp__godot.*` 会报 tool not found）。CLI 通道（`godot_run_project` / `godot_version` 等）当前未配置（`GODOT_BIN` 缺失），**所有调试走编辑器桥接通道**（`dbg_launch` / `runtime_*` / `dbg_*`）。完整工具集与流程见 @rules/mcp-debugging.md。
- **前置检查**：每次会话开头先 `mcp__godot__editor_ping()`，返回 `pong:true` 才能继续。报 `Cannot reach ... 9080` = 编辑器没开 或 `项目设置→插件→Breakpoint MCP` 没启用。
- **启动必传 `scene`**：`dbg_launch({ "scene": "..." })` 不能省略 `scene` 参数——省略会只进默认主场景 `res://scenes/Title.tscn`（开始界面），达不到调试目的。按下面的「场景对照表」选场景。
- **调试与验证强制原则**：任何代码改动都要积极加调试埋点（L1 日志 / L2 断言 / L3 断点），并用 `runtime_assert_*` 组合做无人值守自动化验证，**而不是 `print` 完肉眼判断**。完整方法见 @knowledges/project-debug-and-auto-verification.md。
- **验证优先级（代码测试 > 截图测试）**：默认**只用代码测试**验证改动——`runtime_assert_*`（节点状态 / 场景结构 / 屏幕文本 / 性能）、自测脚本（`*_test.gd` / `debug_test.gd`）、断点 + `dbg_*` 变量检查。**截图验证**（`runtime_screenshot` / `runtime_screenshot_diff` / `screenshot_editor`）属侵入性、需人工解读的手段，**发起前必须先征求用户同意**，不得自行调用；能用断言判定的就绝不截图。
- **图片查看**：**禁用 `view_image` 工具**，本地图片文件用 CLI 识图——默认 `gemini`，备选 `opencode run -m minimax-cn-coding-plan/MiniMax-M3`（先 `cd` 到工作目录，加 `--auto`）。详见 @rules/image-viewing.md。（MCP 截图 `runtime_screenshot` 直接进上下文，无需 CLI；但作为**验证手段**时受「验证优先级」约束，需先经用户同意。）
- **托管默认开启**：经 MCP 启动 `BattleTest.tscn` 时 `hosting` 走默认 `true`，会自动跑完整场战斗。需关闭要用 Godot CLI 带参数。详见 @rules/autoplay-hosting.md。

## 场景对照表（改什么模块 → 跑什么场景）

核心原则：改什么模块，就跑能覆盖该模块的最小场景。一次改动跨多个模块时，选覆盖面最广的（通常 `debug_test.gd`）。

| 本次修改的文件 / 目录 | 应启动的 `scene` |
| --- | --- |
| `godot/scripts/tests/debug_test.gd`（Phase 1 自测，覆盖职业/地形/武器/战斗/AI/回合/经验） | `res://scripts/tests/debug_test.gd` |
| `godot/scripts/tests/battle_test.gd` 或 `godot/scenes/Battle.tscn`、`godot/scripts/scenes/battle.gd`（战斗渲染/玩法循环） | `res://scenes/BattleTest.tscn` |
| `godot/scripts/tests/test_skills.gd` 或 `godot/scripts/core/skills.gd`、`godot/scripts/core/items.gd`、`godot/scripts/systems/skill_system.gd`、`godot/scripts/systems/item_system.gd`、`godot/scripts/systems/buff_system.gd`、`godot/data/skills.json`、`godot/data/items.json`（技能/物品/MP/冷却/buff 纯逻辑自测） | `res://scenes/SkillTest.tscn` |
| `godot/scripts/tests/iso_preview.gd`、`godot/scripts/iso/*`（等距渲染/单位精灵/方块对齐） | `res://scenes/IsoPreview.tscn` |
| `godot/scripts/tests/editor_test.gd` 或 `godot/scripts/scenes/map_editor.gd`、`godot/scripts/editor/*`（地图编辑器） | `res://scenes/EditorTest.tscn` |
| `godot/scripts/scenes/map_editor.gd`（编辑器主流程，需进完整编辑器界面） | `res://scenes/MapEditor.tscn` |
| `godot/scripts/scenes/level_select.gd`（关卡选择） | `res://scenes/LevelSelect.tscn` |
| `godot/scripts/scenes/title.gd`（标题/主菜单） | `res://scenes/Title.tscn` |
| `godot/scripts/tests/e2e_test.gd`（编辑器→存储→战斗端到端，headless） | 用命令行跑：`godot --headless --script res://scripts/tests/e2e_test.gd`，不通过 MCP `scene` |
| 改的是核心逻辑但拿不准入口 | 优先 `res://scripts/tests/debug_test.gd`（跑全套自测） |

## 文档索引

### 调试与验证
- @rules/mcp-debugging.md — MCP 工具集 / 启动调试 / 断点 / 截图 / 已知坑 / 最短验收
- @rules/image-viewing.md — 图片查看（禁用 view_image，CLI 识图：gemini 默认 / minimax 备选）
- @knowledges/project-debug-and-auto-verification.md — 调试埋点强制原则（三层埋点 / 自动化验证 / 反例）

### 玩法系统
- @rules/autoplay-hosting.md — 托管自动调试（默认 hosting:true，偏好面板，自定义场景启用）
- @rules/skill-item-system.md — 技能/物品/MP/冷却/buff 系统（数据结构 / 效果类型 / 分配路径 / 自测入口）

### 已知踩坑（knowledges）
- 完整索引见 @knowledges/README.md（Godot 4 通用坑 + 本项目特定坑）
