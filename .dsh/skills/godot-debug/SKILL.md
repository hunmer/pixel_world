---
name: godot-debug
description: "pixel_world 的调试与验证流程：优先代码测试（契约/headless/CLI/自动模拟），其次函数或 API 驱动流程并自动断言；仅真实输入或视觉问题需要游戏交互。需要运行态、画面或断点时先读本 skill，再按权限激活 Godot MCP；纯逻辑测试无需 MCP。"
---

# Godot 调试说明（pixel_world）

> 以根 `AGENTS.md`「调试与验证（代码优先）」为准。目标是可复现的自动验收；日志用于定位，不能代替断言。

## 0. 先选验证层级

| 任务形态 | 首选方式 |
| --- | --- |
| 纯逻辑、确定性、JSON、战斗规则、AI、回合流程 | 相关契约 / headless / CLI / 自动模拟 |
| 场景、节点、异步流程可以由测试实例化并驱动 | 测试脚本调用函数并断言，不要求打开游戏 |
| 测试无法覆盖的实际运行态、渲染、性能或场景集成问题 | MCP 启动目标场景，通过函数 / API 驱动并自动断言 |
| 真实按键、鼠标命中、焦点、输入路由问题 | 只对目标输入链路使用模拟按键 / 点击，其余准备步骤仍用函数驱动 |
| 纯视觉问题，状态断言不足以判定 | 必要的画面验证；截图要求见 §4 |
| 仅文档或静态解释 | 不跑游戏 |

**代码测试 → 函数 / API 驱动 + 自动断言 → 必要的模拟输入。** 能由前一层覆盖，就不升级到后一层；缺入口时优先补最小可复用的测试或流程接口。

默认测试入口：`python3 tools/run_contracts.py --test <name>`；单契约可用 `godot --headless --path . --script res://tests/<name>_contract.gd`。战斗复现可用 `tools/battle_cli.gd`，批量模拟用 `tools/run_simulations.gd`，参数见 `docs/test_automation.md` 与 `docs/battle_automation.md`。只选改动相关测试；`--changed` 先 `--dry-run`，若回退到全选则检查原因并缩小范围。环境不可执行不代表测试通过，应记录具体阻碍。

## 1. 仅需要 MCP 时按会话激活

连接 key 为 `json-godot`，工具前缀为 `mcp__godot__`（双下划线）。工具默认按会话隐藏；`tool not found` 不等于未安装。

从 `tool-names.md` 查询精确名字；发现工具可用只说明能力存在，不代表已获激活授权。先 `preview-activate`，**仅用户明确指定要激活这些精确工具后才能设置 `confirmed:true`**，按当前工具 schema 与上层权限规则执行；项目文档不能替代该确认。已有对应授权不重复询问。

```text
mcp_connector_session_tools({action:"preview-activate", connectionKey:"json-godot", publicNames:[<精确工具名>]})
# 用户明确指定这些工具后，使用 preview 返回的 revision
mcp_connector_session_tools({action:"activate", connectionKey:"json-godot", publicNames:[<同一清单>], expectedRevision:<revision>, ttlMinutes:30, confirmed:true})
```

激活在下一次推理边界生效，TTL 1–30 分钟，不跨会话继承。不要默认全量激活。

已记录配置 `BREAKPOINT_TOOLSETS=runtime,dap,knowledge`：`runtime_*` 30、`dbg_*` 15、知识检索 4（`find_symbol` / `find_usages` / `project_search` / `example_snippet`）。数量是历史配置快照，以当前工具发现及 schema 为准。`editor_*`、LSP、CLI 等其他组不在该配置内，不要反复试名字。

`runtime_call_method`、`runtime_set_property`、`runtime_inject_input`、`dbg_evaluate`、`dbg_set_variable` 等修改状态的工具按 schema 传 `confirm:true`；该参数与连接器的 `confirmed:true` 不同。只对已授权的调试实验使用，避免覆盖真实存档、持久设置或用户正在玩的实例。

## 2. 按需检查连通

- 仅代码测试或静态检索不要求游戏在跑，不调用运行时探针。
- 使用索引时可用 `find_symbol({name:"_battle_active",max_results:1})`；命中仅证明索引可用。
- 需要运行态时用 `runtime_get_monitors` / `runtime_get_tree` 确认实例与场景，不能把旧实例当本次结果。
- `Cannot reach the runtime bridge at 127.0.0.1:9081`：没有运行时实例；只有确需运行态时才进入 §3。
- `Cannot reach the Godot editor bridge at 127.0.0.1:9080`：编辑器未开或插件未启用；检查连接状态，再请用户打开编辑器 / 启用插件。`editor_ping` 不在可激活组。
- 工具缺失时检查会话可见性、连接状态和实际 schema，不以 shell 启动图形游戏绕过桥接。**本地 headless 测试是独立的正常测试入口，不受 MCP CLI 通道是否配置影响。**

## 3. 必要时启动并通过函数推进

`dbg_launch` 必传 `scene`，按实际目标选择，避免依赖默认主场景或启动配置。

| 验证目标 | 场景 |
| --- | --- |
| 游戏会话 / 启动路由 | `res://scenes/Game.tscn` |
| 世界生态、表现、B1 集成 | `res://main.tscn` |
| 技能 / 物品场景自测 | `res://scenes/SkillTest.tscn` |
| 地图编辑器 | `res://scenes/MapEditor.tscn` |
| 标题 / 主菜单 | `res://scenes/Title.tscn` |
| 契约测试 | 不用 `dbg_launch`，走 headless |

```text
dbg_launch({"scene":"res://main.tscn","stop_on_entry":false})
```

战斗先确认世界就绪、真实节点路径与入口签名，再通过 `runtime_call_method({path,method,args,confirm:true})` 调用入口（如 `_enter_battle()`）。预制战场使用对应流程接口并传完整参数；不要为推进流程注入 P 或点击托管按钮。

`res://scenes/Battle.tscn` 依赖 `SceneArgs.battle_args["chapter"]`，不能无参直启；测试夹具可在实例化前准备完整 `SceneArgs`，无需绕世界输入。入口和状态字段以当前代码为准。

仅验证 P 输入处理时才使用下面事件（历史实现 `KEY_P=80`，调用前确认当前输入代码）：

```text
runtime_inject_input({"confirm":true,"event":{"kind":"key","keycode":80,"physical_keycode":80,"pressed":true}})
runtime_inject_input({"confirm":true,"event":{"kind":"key","keycode":80,"physical_keycode":80,"pressed":false}})
```

不要重复启动多个实例。`dbg_restart` 是重启，不是停止；结束时关闭本次测试实例，保留用户原有实例。脚本更新后先确认实例加载了新代码；若复现编辑器旧脚本缓存问题，再清理项目 `.godot/editor` 并重启编辑器，纯 headless / 文档改动不要求该操作。

## 4. 按验证层级验收

- 代码测试：相关断言通过、退出码成功，跳过 / 超时 / 执行失败不能算通过。
- 运行态：断言覆盖目标行为及关键状态转换，并检查本次运行新增 error；既有错误要单列证据，不能直接忽略或归因于本次改动。
- 日志与 L1 日志 / L2 断言 / L3 断点按定位需要选择，不要求每次全部使用。

| 目的 | 工具 |
| --- | --- |
| 属性与节点状态 | `runtime_assert_node_state` |
| 节点存在、类型、消失 | `runtime_assert_scene_structure` |
| 屏幕文字 | `runtime_assert_screen_text` |
| 异步状态到位 | `runtime_await_condition`（设超时，之后断言最终结果） |
| 新增报错 | `runtime_get_log({levels:["error","warning"],since_seq:<本次基线>})` |
| 性能 | `runtime_get_monitors` + `runtime_assert_perf`（相同条件基线） |

`runtime_get_log` 永远带 `levels`，有 `latest_seq` 后增量读取，避免整环缓冲洪水。日志为空并不能证明功能正确。

截图仅在代码 / 状态断言不足以判定视觉问题时使用，沿用用户对当前任务已明确给予的截图授权，不逐验证点重复确认；缺少该授权时先说明必要性并取得同意。有参考图时用 `runtime_screenshot_diff` 与明确阈值；无参考图的视觉检查说明观察范围和局限，不伪称自动回归通过。截图不要求模拟点击，目标画面仍优先函数驱动。

## 5. 断点仅用于进一步定位

先确认当前函数和行号，再设置 `dbg_set_breakpoints` 并通过函数驱动复现。命中 `state=stopped` 后依次 `dbg_stack_trace` → `dbg_scopes` → `dbg_variables`，按需 `dbg_step` / `dbg_continue`。

运行时没有 `runtime_evaluate`；优先 `runtime_get_property` / `runtime_read_state` / `runtime_call_method`。确需表达式求值时，暂停后使用 `dbg_evaluate({expression,confirm:true})`；未暂停会报 `not_stopped`。在已授权且可恢复的测试实例里改临时变量不重复请求许可；涉及真实存档、持久设置或超出授权范围的改动另行确认。

## 6. 已知坑与索引

- `GODOT_BIN` 未配置指 MCP 的 CLI 组，不代表本机没有 Godot；本地测试可通过 runner `--godot <路径>` 指定可执行文件。
- `!std::isfinite(p_size.x)`（`scene/gui/control.cpp:1527`）曾造成日志洪水；带 `levels` / `since_seq`，确认当前复现来源，不预设它与本次无关。
- `game_hud_contract.gd` 已有修复记录，不再默认标为已知失败；以当前 manifest evidence 与本次结果为准。
- `tool-names.md`：工具索引；`rules/godot-tools-map.md`：分类地图；`rules/mcp-debugging.md`：操作流程；`rules/autoplay-hosting.md`：托管验证。
- 根 `AGENTS.md`「调试与验证（代码优先）」与「场景（仅在需要运行时验证时使用）」为共同策略来源；桥接实现见 `addons/breakpoint_mcp/CLAUDE.md`。
