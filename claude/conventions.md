# 开发约定

> 本文件收集对 Agent 与人类贡献者最实用的命令、规范与禁忌。高优先级条目同时摘要在根 `CLAUDE.md`；agent 工作约束另见根 `AGENTS.md`。

## 运行与启动

```bash
# 打开并运行主场景（要求 Godot 4.6+，本项目用 4.7.2）
godot --path .
# 本机 exe（不在 PATH）：
D:/Godot/Godot_v4.7.2-stable_win64.exe --path E:/pixel_world

# headless 跑某个契约测试（extends SceneTree 类型，运行后自动退出）
godot --headless --path . --script res://tests/terrain_generation_contract.gd

# 从命令行带参运行场景（CmdArgs 解析 --key / --key=value / --no-key）
godot -d --path . res://main.tscn --seed=42
```

- **主场景**：`res://main.tscn`（`project.godot` 的 `run/main_scene`）。入口脚本 `main.gd`（项目已迁至 `E:\pixel_world`）。
- **标题场景**：`res://scenes/Title.tscn` → "进入世界" 按钮切到 main.tscn。
- **console 版 exe 的 stdout 是全缓冲的**：管道下无输出 ≠ 没输出；脚本化验证用 `timeout` 包裹或看退出码。

## 编辑器脚本缓存坑（重要兼容性提醒）

来自 `HANDOFF.md`，调试时极易踩：

> `dbg_restart` **不会重新编译脚本**。改完代码后必须清 `.godot/editor` 缓存并重启编辑器，否则跑的是旧脚本。
> Windows 上的等价操作：删除 `E:/pixel_world/.godot/editor` 目录，然后重开 Godot 编辑器。

## 测试

- **无第三方测试框架**。测试是 GDScript 自测脚本，两种形态：
  1. `tests/*_contract.gd`（37 个）：`extends SceneTree`，在 `_initialize` → `call_deferred("_run")` 中跑断言，失败用 `push_error` + `quit(1)`。**地形生成测试用固化的 SHA-256 快照检测回归**（改了确定性会挂）。
  2. `scripts/tests/*.gd`：`extends Node`，`_ready` 里自跑 `_ok/_pass/_fail/_print_summary`（仿 `debug_test.gd` 框架）。
- 已知通过状态（2026-11-11 HANDOFF）：`SkillTest.tscn` 44/44、`debug_test.gd` 35/35（历史）、battlefields / map_editor / battle_screen_pick / battlefield_render 契约绿。⚠️ `game_hud_contract.gd` **在 HEAD 上本来就坏**（`--script` 模式无 autoload，`game_hud.gd` 引 `Settings` 编译错）。
- **代码测试 > 截图**：调试时优先用断言 / 日志，不擅自截图（HANDOFF 明示约束）。验证等级：L1 日志 / L2 断言 / L3 断点 + `runtime_assert_*` 自动验证，不要 `print` 后肉眼判断（AGENTS.md）。

## 代码风格

- `.editorconfig`：仅规定 `charset = utf-8`（root）。全仓库实际统一用 **tab 缩进**（GDScript 惯例）—— 贡献者请保持 tab。
- GDScript 文件普遍带顶部 `## file.gd — 一句话职责` 文档注释（中文为主），并标注对应 TS 源（战棋部分）。**新文件请延续此风格**。
- 命名：文件名全小写 `snake_case.gd`；类用 `class_name PascalCase`；常量 `UPPER_SNAKE`；私有 `_leading_underscore`。
- 资源目录与 tile 文件统一英文小写 `snake_case`；稳定 species ID 尽量与目录名一致。
- **GDScript strict 显式类型**：新代码完整类型标注（HANDOFF 坑：漏标注在严格模式下直接编译错）。

## 配置 / 内容规范（最关键的"禁止事项"）

摘自 `config/README.md` 与 `config/ecology/README.md`：

- **不要往 `main.gd` 里加分支**：新的 biome ID、noise ID、surface ID、minimap color、weather tag 都应走 biome 模块 / 配置 / community，而不是在 main.gd 开 if。新算法进 biome 模块，可复用空间布局进 community。
- **新内容走新版模块化配置**：`config/ecology/manifest.json` + `species/` + `communities/` + `biomes/`。**禁止给新内容加 `metadata.legacy_placement_seed` 或写进 `legacy_bundles.json`**（那是兼容旧布局专用）。
- **确定性契约**：ID、`stream_key`、legacy `placement_seed` 是"存档/世界契约"。**文件路径、翻译后的显示名绝不能当随机种子**。重排 manifest 顺序或改稳定 ID 需要 world version 迁移。
- 新模块用唯一命名空间的 `stream_key`（如 `volcanic/fumaroles/member`），现有流保留旧数字 salt。
- **`story/` 是目标态设计 bible**（13 职业/27 技能/25 道具）；运行时事实是 `data/` 的 8 职业/8 技能/8 物品。实现 story 内容 = 改 `data/*.json`，勿混用两套数字。

## 战棋约定（B1 / B2 / JSON 战场 / 编辑器）

- 由 `Settings.battle_inline_mode`（autoload `Settings`，持久化到 `user://settings.cfg`）切换：`true=就地(B1)` / `false=独立场景(B2)`。默认 true。**JSON 战场（O 键）固定走 B2**。
- 改动 `main.gd` 时遵守"**新增不修改，分支注入**"：B1 逻辑一律 `if _battle_active:` 前置短路，false 时零影响；**不要动 B2 路径代码**。
- 战场坐标 `(0,0)` = 世界 `world_origin + (bx,by)`；`GridSystem` 完全不感知世界坐标，由 `UnitSprite` 渲染时加 origin 转换。
- **JSON 战场**：schema 与校验规则见 `public-interfaces.md`；`rows` 是**顶层字段**；`BattlefieldLoader` 是唯一权威校验点（编辑器 `quick_validate` 只是轻校验）。用户战场放 `user://battlefields/`（与 `res://data/battlefields/` 同名时 res 优先）。
- **编辑器扩展**参考 `D:/phaserjs/godot/scripts/scenes/map_editor.gd`（外部项目）；SpinBox 竞态用 `_syncing_boxes` 模式防。

## 视角 / 3D 渲染约定

- **只支持 4 个正交视角**（0/90/180/270，`isometric_view.gd SUPPORTED_ANGLES`）：素材逐角度验收仅四视角，其余角度有拼缝。**勿放开连续角度**。
- 旋转是**纯相机行为**（`IsometricCamera3D`），不重建地形；`R` 复位视角、`Ctrl+R` 才重新生成世界（勿混淆）。
- 2D 旋转渲染方案的踩坑存档在 `handoff/2026-11-11-isometric-rotation.md`，**已被 3D 迁移取代** —— 不要按它改代码，仅供回退时参考。

## 常见 API 坑（HANDOFF 摘录）

- `Dictionary.merge` 默认**不覆盖**已有键。
- `TerrainMaterialRegistry.set_texture_processor(raw_texture, texture_path)` **两参必传**，漏第二参整批贴图 null 崩。
- `IsoCoords.to_cell` 用 `roundi`（不是 floor/int()）。
- Godot 4.7 **无** `DirAccess.remove_recursive`，删目录自写递归。
- 切场景前先 `set_input_as_handled()`，防输入穿透到新场景。
- B1 下 `battle.gd.board == null`：相机归 `main.gd` 管；hover 可越界但点击必须 `in_bounds`。
- `RangeOverlay` 只负责显示，不参与任何判定。
- **不清理他人未提交的改动**（工作树纪律）。

## 调试（MCP 桥 / Panku 控制台）

- **MCP 工具按会话激活**（AGENTS.md）：`mcp_connector_session_tools` preview-activate → activate `confirmed:true`（`confirmed:true` 由激活方自行设置，member 无需向 lead 申请；`connectionKey: json-godot`，ttl 1–30 分钟，下一轮推理生效，不跨会话继承）。全集 295，其中 49 个可激活。工具地图见 `rules/godot-tools-map.md`；**不要用 `search` 找工具名**，查该文或 `tool-names.md`。
- 会话开头自检用 `find_symbol` + `runtime_get_monitors`；**不要用 `editor_ping`**（不在 `runtime,dap,knowledge` 三组内，激活也拿不到，`tool not found` 会误判成「没装」）。9080 不通 = 编辑器没开或插件未启用（由用户确认）。
- 启动调试：`dbg_launch({scene: "res://main.tscn"})`（**必须传 scene**，省略只会进默认主场景）。场景路由表见 AGENTS.md（改哪跑哪）。
- 编辑器桥 `127.0.0.1:9080`（`BREAKPOINT_BRIDGE_PORT` 覆盖）；运行时桥 `9081`（**单实例**，已有游戏在跑再启动会绑定失败）。
- 游戏内 `~` 呼出 **Panku REPL**（autoload `Panku`）：`dbg.*` 命令集见 `scripts/debug_console_commands.gd`；新命令 = 对象公共方法 + `_HELP_方法名` 常量 + `Panku.gd_exprenv.register_env` 注册。

## 安全与边界（本索引工具的自约束）

- 这些文档只读 / 写文档与索引，不改源代码。
- 默认忽略 `.godot/`、二进制大文件（`.png`/`.mp3`/`.import`）。
- 不主动执行 git 提交、分支、reset、checkout。
