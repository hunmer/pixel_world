# Rule: Godot 调试与验证流程

> 策略以 `AGENTS.md`「调试与验证（代码优先）」为准；具体 MCP 操作见 `.dsh/skills/godot-debug/SKILL.md`，精确工具名见该目录 `tool-names.md`。本文作为流程入口，不重复维护第二套启动 / 激活规则。

## 1. 先选最小验证方式

1. 检查现有相关契约、CLI、自动模拟能否覆盖；能覆盖就执行代码测试，不打开游戏模拟点击。
2. 确需真实场景集成或运行态时，通过测试夹具或 MCP 函数 / API 驱动流程，并自动断言。
3. 仅真实输入、焦点、鼠标命中、输入路由无法由前两层覆盖时，才模拟目标按键 / 点击。准备世界、进入战斗、开启托管等步骤仍优先函数驱动。
4. 视觉状态无法由断言判定时，按 skill 的截图授权规则做画面验证；截图与模拟输入是两个独立选择。

仅文档或静态解释不跑游戏。缺入口时优先补最小、可复用测试 / 流程接口，不直接转为坐标点击。

## 2. 代码测试路径

- 默认单契约：`python3 tools/run_contracts.py --test <name>`。
- 直接 headless：`godot --headless --path . --script res://tests/<name>_contract.gd`。
- 战斗复现 / 回归：`tools/battle_cli.gd`；批量模拟：`tools/run_simulations.gd`，参数见 `docs/battle_automation.md` 与 `docs/test_automation.md`。
- 只选改动相关测试；`--changed` 先用 `--dry-run` 检查，映射失败回退到全选时缩小范围。
- 以目标断言、退出码、结构化报告验收。超时、环境跳过或执行失败均不算该项验证通过，不能只凭 OK 日志判断。

MCP `godot_*` CLI 工具不可激活 / `GODOT_BIN` 未配置，**不等于本地 headless 测试不可用**。本地测试通过 runner `--godot <路径>` 或本机可执行文件运行，不需要 Godot MCP。不要用 shell 启动图形游戏绕过运行态桥接。

## 3. 确需 MCP 时

1. 先读 skill，按当前连接器 schema 发现精确工具并 preview；只有用户明确指定激活这些精确工具后才设置连接器 `confirmed:true`。已有同范围授权不重复问，项目文档不能替代工具要求的确认。
2. 按需自检：索引用 `find_symbol`；运行态用 `runtime_get_monitors` / `runtime_get_tree`。不为自检而启动游戏。
3. 确认当前实例、场景与代码版本；确需启动时 `dbg_launch` 必传目标 `scene`，场景表见根 `AGENTS.md`。`9081` 不通通常是无运行实例，`9080` 不通是编辑器桥未就绪；工具不可见先排查会话激活，不能直接认定未安装。
4. 通过 `runtime_call_method({path,method,args,confirm:true})` 调用已有入口，先读当前代码确认路径、签名、就绪条件，不猜节点名。
5. 战斗可从世界入口 `_enter_battle()` / 对应战场流程进入；无头夹具可直接准备完整 `SceneArgs.battle_args` 后实例化战斗。`Battle.tscn` 依赖 chapter，不能无参直启。P 是玩家输入入口，仅验证 P 输入处理时才注入该键。
6. 等待异步条件设超时，随后断言目标结果。不要固定等待若干秒再肉眼检查。

工具名使用 `mcp__godot__*` 双下划线；`editor_ping` / `screenshot_editor` 不在已记录的 `runtime,dap,knowledge` 可激活配置内，不要把不可用工具写进执行配方。端口 / 工具组是环境记录，现场状态以当前诊断结果为准。

## 4. 运行态验收与日志

| 目的 | 工具 |
| --- | --- |
| 节点属性达到期望 | `runtime_assert_node_state` |
| 节点存在 / 类型 / 消失 | `runtime_assert_scene_structure` |
| 屏幕文字 | `runtime_assert_screen_text` |
| 等异步状态 | `runtime_await_condition`，然后验证最终状态 |
| 性能回归 | `runtime_get_monitors` + `runtime_assert_perf`（先准备可比基线） |
| 新增错误 | `runtime_get_log`（始终带 `levels`，有序号后增量读） |

```text
mcp__godot__runtime_get_log({"levels":["error","warning"]})
# 后续只取上次 latest_seq 之后的条目
mcp__godot__runtime_get_log({"since_seq":<上次 latest_seq>,"levels":["error","warning"]})
```

断言覆盖目标行为、关键状态转换与结果，日志只辅助诊断。核对本次新增错误，既有错误单独列证据；日志为空不代表功能正确。切换场景或重启后重新断言，不能沿用旧实例结果。

## 5. 断点、截图与结束

- 日志 / 断言不足以定位时才使用断点。行号随重构变化，先查当前函数，不照抄历史行号。
- `dbg_set_breakpoints` → 启动 / 函数驱动复现 → 确认 `stopped` → `dbg_stack_trace` → `dbg_scopes` / `dbg_variables` → 按需单步 / 继续。
- 没有 `runtime_evaluate`；优先读取属性或调用已有方法。`dbg_evaluate` 必须暂停后使用，否则 `not_stopped`。
- 修改临时状态按 schema 传 `confirm:true`，限已授权、可恢复的测试实验；真实存档、持久配置或用户现有实例的额外改动另行确认。不要混淆工具 `confirm:true` 与连接器激活 `confirmed:true`。
- 代码 / 状态断言不足时才截图。沿用当前任务已有的明确截图授权，不逐验证点重复询问；尚未授权时说明必要性并取得同意。有参考图用 `runtime_screenshot_diff` 与明确阈值，无参考图如实报告视觉观察，不能宣称自动回归通过。
- 脚本更新后确认使用新版本；若出现编辑器旧脚本缓存问题，再清理项目 `.godot/editor` 并重启编辑器。纯 headless / 文档改动不要求清缓存或重启编辑器。
- `dbg_restart` 用于重启，不用于结束。完成后关闭本次测试实例，保留用户原有实例，报告所测范围、结果与未覆盖项。

## 6. 托管与进一步说明

托管复现同样遵守代码测试 → 函数驱动 → 必要输入的顺序，见 `rules/autoplay-hosting.md`。工具分类地图见 `rules/godot-tools-map.md`；验收策略与场景入口只在根 `AGENTS.md` 维护。
