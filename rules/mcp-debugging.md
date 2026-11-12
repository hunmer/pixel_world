# Rule: Godot MCP 调试流程

> 本规则是 `AGENTS.md`「关键约束」的展开。MCP 命名空间、scene 必传、CLI 不可用等硬约束见 AGENTS.md；本文讲**完整操作流程**。

> **2026-11 更新：godot 连接已改为「按会话启用」**。298 个工具默认不注入上下文，必须先 `mcp_connector_session_tools` 激活本次要用的精确工具（connectionKey `json-godot`），再按本文调用；未激活直接调用会 tool not found。完整分类与激活配方见 `@rules/godot-tools-map.md`。下文为可读性省略 `mcp__godot__` 前缀，实际调用一律带全名。

## Godot MCP 工具集（Breakpoint MCP）

命名空间是 `mcp__godot__*`（**双下划线**，不是点号 `mcp__godot.*`）。所有工具按桥接通道分两类：

| 通道 | 依赖 | 典型工具 |
| --- | --- | --- |
| **编辑器桥接**（127.0.0.1:9080） | Godot 编辑器打开 + 启用 "Breakpoint MCP" 插件 | `editor_*`、`scene_*`、`node_*`、`runtime_*`、`dbg_*`（launch 模式）、`gd_*`、`vcs_*` |
| **CLI 直调** | `GODOT_BIN` 环境变量指向 Godot 可执行文件 | `godot_run_project`、`godot_export`、`godot_import`、`godot_version` |

> 当前环境 **CLI 通道未配置**（`godot_version` 返回空），**所有调试都走编辑器桥接通道**——这也是功能更全的通道（断点、运行时变量、日志、截图都有）。

### 前置检查（每次会话开头跑一次）

先按 @rules/godot-tools-map.md §0 激活 `editor_ping` + `editor_get_state`，再调用：

```text
mcp__godot__editor_ping()         # 应返回 pong:true, addon_version, godot 版本
mcp__godot__editor_get_state()    # 看当前编辑的场景 / 选中的节点
```

如果 `editor_ping` 报 `Cannot reach the Godot editor bridge at 127.0.0.1:9080`：编辑器没开，或 `项目设置 → 插件 → Breakpoint MCP` 没启用。

## 调试流程

1. 确认工程根就是仓库根（含 `project.godot`）：

```bash
rg --files -g "project.godot" .
```

预期只有一个结果：`project.godot`。**不要**再找 `godot/` 子目录——那是旧工程布局。

2. 启动游戏（走编辑器桥接的 debug launch），**必须显式传入 `scene`**。

   本工程默认主场景是 `res://main.tscn`（`project.godot` 的 `run/main_scene`），不是 `Title.tscn`。`dbg_launch` 支持可选 `scene` 覆盖：

```text
mcp__godot__dbg_launch({ "scene": "res://main.tscn", "stop_on_entry": false })
```

   按改动选场景（完整对照表见 `AGENTS.md` 的「场景」章节）。两个易错点：

   - **`res://scenes/Battle.tscn` 不能直接 launch**：它从 `SceneArgs.battle_args["chapter"]` 取战场数据，而该值只由 `main.gd` 的 `_enter_battle()` / `_enter_battlefield()` 注入。直接启动会拿到空 chapter 而报错。要调战斗：启动 `main.tscn`，用 `runtime_inject_input` 注入一次 `P` 键（或手动按 P）触发战斗；默认 B1 就地战斗（`Settings.battle_inline_mode=true`），改 false 则切到 B2。
   - **纯技能/物品逻辑**：`res://scenes/SkillTest.tscn` 自带测试数据，可直接启动。

   成功信息应类似：

```text
{ "session_id": "godot", "state": "running", "scene": "res://main.tscn" }
```

3. 读运行时输出/日志（两路互补）：

```text
# 引擎启动日志 + print 输出
mcp__godot__runtime_get_log()

# 只看 error/warning 级别
mcp__godot__runtime_get_log({ "levels": ["error", "warning"] })

# 增量读：只取 seq > 上次返回的 latest_seq 的新条目
mcp__godot__runtime_get_log({ "since_seq": <上次的 latest_seq> })
```

   正常应包含 `Godot Engine v4.7...` 与 **OpenGL / Compatibility** 渲染器行，且 `error/warning` 列表为空。

   > 还可以读**性能监控**（FPS / Draw Call / 节点数）：`mcp__godot__runtime_get_monitors()`

4. `dbg_launch` 报 `No active Godot process` 或桥接连不上：先 `editor_ping` 确认编辑器还在、插件还启用，再重新 launch。

5. 结束调试会话：`mcp__godot__dbg_restart`（重启用同一参数）或直接关游戏窗口（会话自动结束）。

## 断点调试（重点功能）

这是本 MCP 区别于普通 run-and-log 工具的核心能力，可以在攻击/技能/回合切换等关键函数停下来查看变量。

**流程**：先 `dbg_set_breakpoints`（断点会缓冲，launch 时一起应用）→ `dbg_launch` → 等运行到断点 → `dbg_stack_trace` 看是否命中。

```text
# 1. 设断点（res:// 路径，1-based 行号；可选 conditions/hit_conditions/log_messages）
mcp__godot__dbg_set_breakpoints({
  "path": "res://scripts/scenes/battle.gd",
  "lines": [672, 1084]   # 672=_resolve_combat 玩家/托管攻击, 1084=_resolve_combat_sync 敌方回合攻击
})

# 2. 启动主场景，再按 P 进战斗（B1 就地模式）
mcp__godot__dbg_launch({ "scene": "res://main.tscn" })

# 3. 查调用栈（命中后 state=stopped）
mcp__godot__dbg_stack_trace()
# 期望返回类似：
#   frame 0: _resolve_combat_sync  battle.gd:1084
#   frame 1: _enemy_act            turn_director.gd:xxx

# 4. 看局部变量（frame_id 从 stack_trace 拿）
mcp__godot__dbg_scopes({ "frame_id": 0 })          # 返回 Locals/Members/Globals 的 variables_ref
mcp__godot__dbg_variables({ "variables_ref": 1 })  # 展开 Locals：attacker/defender/result/...

# 5. 单步：over=不进函数 / in=进入 / out=跳出
mcp__godot__dbg_step({ "kind": "over" })

# 6. 继续，直到下一个断点
mcp__godot__dbg_continue()
```

**常用断点位置（`scripts/scenes/battle.gd`，行号会随重构漂移，用前先 `find_symbol` / grep 确认）**：

| 行号 | 函数 | 触发时机 |
| --- | --- | --- |
| 672 | `_resolve_combat` | 玩家方/托管方主动攻击（含 await 演出版） |
| 757 | `_resolve_skill` | 技能结算 |
| 818 | `_resolve_item` | 物品结算 |
| 1084 | `_resolve_combat_sync` | 敌方回合攻击（同步版） |
| 1116 | `_check_battle_end` | 胜负判定，可看 turn/存活数 |

**运行时改值（不重启实验）**：

```text
# 把 variables_ref=1 里名为 defender 的 hp 改成 0，验证死亡分支
mcp__godot__dbg_set_variable({ "variables_ref": 1, "name": "defender.hp", "value": "0" })
```

> `dbg_set_variable` 是破坏性的（改了活游戏状态），改前先跟用户确认。

**条件断点 / 日志点**（adapter 支持时才生效，Godot 4.7 需实测）：

```text
mcp__godot__dbg_set_breakpoints({
  "path": "res://scripts/scenes/battle.gd",
  "lines": [672],
  "conditions": ["attacker.faction == \"player\""]   # 只在玩家方攻击时断
})
```

## 截图调试流程

> **默认不截图**（见文末「验证优先级」）。确有需要时优先用 MCP 内置截图，比系统级窗口裁剪可靠。

### 方法 A：MCP 运行时截图（推荐）

游戏运行中截当前游戏帧（返回 PNG 内容，可直接查看）：

```text
mcp__godot__runtime_screenshot()
```

如果要和参考图做像素级回归比对（防渲染回退）：

```text
# 参考图放在工程内，例如 res://tests/fixtures/
mcp__godot__runtime_screenshot_diff({
  "reference": "res://tests/fixtures/battle_init.png",
  "tolerance": 0.02,            # 允许 2% 像素差异
  "per_channel_threshold": 8    # 每通道差值阈值
})
```

### 方法 B：编辑器视口截图

截 2D/3D 编辑器视口（需要对应编辑器 tab 处于激活状态）：

```text
mcp__godot__screenshot_editor({ "viewport": "2d" })
```

### 方法 C：系统级窗口截图（备用，MCP 截图失效时）

只在 MCP 截图不可用时用。截图统一存到仓库根的 `tmp/screenshots/`（`/tmp/` 已在 `.gitignore` 中忽略），文件名带时间戳：

- macOS：`screencapture -x -o -l <window-id> tmp/screenshots/<name>.png`（窗口 id 可用 `screencapture -l$(osascript -e 'tell app "System Events" to id of window 1 of process "Godot"')` 获取）。
- Windows：PowerShell `System.Drawing` 的 `CopyFromScreen` 按窗口 rect 裁剪。
- Linux：`import -window <id>` 或 `grim`。

有效截图通常远大于 100 KB；如果只有几百字节，先检查窗口是否最小化或被移到屏幕外。

## 已知坑

- MCP 工具名是 `mcp__godot__*`（**双下划线**）；点号写法会报 "tool not found"。
- 工具**按会话激活**：未激活时调用会 tool not found，先走 `mcp_connector_session_tools`；激活在**下一轮推理**生效。
- **CLI 通道不可用**（`GODOT_BIN` 未配置），`godot_run_project` / `godot_version` 返回空。所有调试走编辑器桥接的 `dbg_launch` / `runtime_*` / `dbg_*`。
- `editor_ping` 报 9080 不通：编辑器没开，或 `项目设置 → 插件 → Breakpoint MCP` 没启用。
- 多次 `dbg_launch` 后可能留下多个 `pixel_world` 窗口；截图前确认要截的窗口。
- 系统级窗口截图在 Godot 窗口上可能得到空白或极小 PNG；优先用 `runtime_screenshot`。
- `dbg_set_variable` 会改活游戏状态，破坏性操作，改前跟用户确认。
- 断点不命中？检查：(1) `dbg_set_breakpoints` 返回 `buffered: true`（已缓冲，等 launch 应用）；(2) 路径用 `res://` 前缀；(3) 行号是 1-based；(4) 启动的是 `main.tscn` 时，战斗要按 P 触发后才会走到 battle.gd。
- 改了脚本但行为没变：删 `.godot/editor` 缓存并重启编辑器（`dbg_restart` 不会重新编译脚本）。

## 验证优先级（代码测试 > 截图测试）

> 与 `AGENTS.md`「验证」约束呼应。默认走代码断言，截图是需人工解读的侵入性手段，发起前必须先征得用户同意。

**默认只用代码测试**，按判定需求选工具：

| 想验证什么 | 首选工具（不截图） |
| --- | --- |
| 某节点某属性 == 期望值 | `runtime_assert_node_state`（支持数值 `tolerance`） |
| 场景树结构（节点存在/类型/缺失） | `runtime_assert_scene_structure` |
| 屏幕上有没有出现某段文字 | `runtime_assert_screen_text`（支持 `regex` / `present:false` / `min_count`） |
| 性能没退化 | `runtime_get_monitors` + `runtime_assert_perf`（先存基线再比对） |
| 等异步状态到位再断言 | `runtime_await_condition`（轮询直到满足/超时） |
| 纯逻辑自测 | `res://tests/*_contract.gd`（headless）/ `scenes/SkillTest.tscn` |
| 查变量、跟调用栈 | `dbg_set_breakpoints` + `dbg_stack_trace` + `dbg_scopes`/`dbg_variables` |

**截图验证（`runtime_screenshot` / `runtime_screenshot_diff` / `screenshot_editor`）的启用条件**：

1. **先征得用户明确同意**（一次同意只对当前验证点有效，下个验证点要再问）。
2. 仅在代码断言无法判定时用——例如纯视觉回归、布局像素级检查、用户主动要求"看看效果"。
3. 同意后优先用 `runtime_screenshot_diff`（带参考图 + `tolerance`，像素级客观判定），而不是 `runtime_screenshot` 后靠人眼比对。

> 原则：**能用断言判定的就绝不截图**。

## 最短验收

1. `editor_ping` 返回 `pong: true`（桥接连通，插件启用）。
2. `dbg_launch({ "scene": "res://main.tscn" })` 返回 `state: "running"`；调试战斗则再注入 P 键进入 B1。
3. `runtime_get_log({ "levels": ["error", "warning"] })` 返回空列表。
4. **用代码断言验证改动效果**（见上表），而非截图；改的是渲染/布局且用户已同意时才截图。
