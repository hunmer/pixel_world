---
name: godot-debug
description: "pixel_world（Godot 4.7 / 2D）里凡是「把游戏跑起来看」「查报错/黑屏/没反应」「验证改完对不对」「看画面/像素」「进战斗 / 技能测试」「下断点」「截图」的任务，一律先读本 skill，走 godot MCP 桥接（dbg_launch → runtime_assert_*）。mcp__godot__* 里的 49 个工具已常驻工具表、不用激活；不要改用 bash 跑 godot，也不要 print 后肉眼判断。"
---

# Godot 调试说明（pixel_world）

> 目标：让"验证"变成一次可复现的 MCP 调用，而不是 `print` + 人眼。默认路径只有一条，照抄即可。

## 0. 先判断：这个任务要不要把游戏跑起来？

| 任务形态 | 走哪里 |
| --- | --- |
| 改 GDScript / 场景 / shader / 资源后要"看效果" | **本 skill**（MCP 桥接） |
| 报错、崩溃、黑屏、点了没反应、卡住 | **本 skill**（`runtime_get_log` 最快） |
| 问"现在游戏里是什么状态 / 某节点某属性是多少" | **本 skill**（`runtime_get_property` / 断言） |
| 纯逻辑、确定性、JSON 契约（不需要画面） | 命令行 `godot --headless --path . --script res://tests/<name>_contract.gd` |
| 只改文档 / 只读代码做解释 | 都不用跑 |

判断标准：**要看运行态就走 MCP；只看静态数据就走 headless。** 两者都不要"print 后肉眼确认"。

## 1. 工具已经常驻，不需要激活

连接 `json-godot` 的注入模式是 **always**，且用 `BREAKPOINT_TOOLSETS=runtime,dap,knowledge` 收缩过，所以工具表里**常驻这 49 个**（每轮都在，直接调）：

| 组 | 个数 | 干什么 |
| --- | --- | --- |
| `runtime_*` | 30 | 读活体状态、断言、注入输入、截图、多 peer 对拍 |
| `dbg_*` | 15 | 启动 / 重启 / 断点 / 单步 / 栈 / 变量（DAP） |
| `find_symbol` / `find_usages` / `project_search` / `example_snippet` | 4 | 项目索引与代码检索（不需要编辑器也不需要游戏） |

**没被注入的（别去调，会 tool not found）**：`editor_*` 149 个（含 `editor_ping`、`editor_get_state`、`scene_*`、`node_*`、`resource_*`、`ui_*`、`project_*`、`inputmap_*`、`theme_*`、`tileset_*` 等）、`lsp`/`cslsp`、`cli`、`tabletop`、`csdap`、`vcs`、`assetgen`、`netcode`、`backend`、`processes`、`hearing`。这是刻意的取舍：149 个 `editor_*` 常驻会让 schema 体积翻三倍，而调试根本不需要它们。

卡住的两种情况：

- **工具表里没有 `mcp__godot__*`** → 连接被停用或注入模式被改回去了。处理顺序：`mcp_connector_status` 看 `[json-godot]` 是否"已连接 / 始终注入" → `mcp_connector_set_enabled({key:"json-godot", enabled:true})` → 仍不对就用面板（MCP 连接器 → godot → 注入模式 → 始终注入）重新落一次。**不要**因为看不见工具就改用 bash 跑 godot。
- **报 `Host 尚未注册该 stdio Server 的工具`** → 是启动中的瞬时态，等几秒 `mcp_connector_health_check` 或 `mcp_connector_status` 复查；stdio 连接（codegraph / fff / godot）同时出现这条一般是 Host 在重连，不是配置坏了。

找工具名：**不要用 `mcp_connector_session_tools` 的 `search` 逐个试**（它是单关键词子串匹配，`"editor_ping runtime_get_log"` 这种多词查询必然 0 结果——上一个 agent 为此连查了 8 次）。49 个常驻工具的完整签名 + 「意图 → 工具」表在 `.dsh/skills/godot-debug/tool-names.md`，要用未注入的 `editor_*` 说明你走错路了。

**破坏性工具要带 `confirm:true`**：`runtime_set_property`、`runtime_call_method`、`runtime_inject_input`、`runtime_step_frames`、`runtime_time_scale`、`runtime_seed_rng`、`runtime_anim_play/stop`、`runtime_node_add/remove`、`dbg_evaluate`、`dbg_set_variable` 等。不带会触发客户端确认弹窗，在 DSH 上直接失败（返回 re-run with confirm:true）。只读的不带。

## 2. 连通自检（会话第一条，两秒）

```text
find_symbol({"name":"_battle_active","max_results":1})   # 项目索引通道，不依赖编辑器/游戏
runtime_get_monitors()                                   # 运行通道，需要游戏已在跑（很小，放心调）
```

| 返回 | 含义 | 处理 |
| --- | --- | --- |
| `find_symbol` 有命中 | 索引通道正常 | 继续 |
| `runtime_get_monitors` 有帧率 | 已有游戏实例在跑（可能是用户手动开的旧实例） | 注意别把它的状态当成你这次的改动结果 |
| `Cannot reach the runtime bridge at 127.0.0.1:9081` | 没有游戏在跑 | 正常，直接第 3 步 `dbg_launch` |
| `Cannot reach the Godot editor bridge at 127.0.0.1:9080` | 编辑器没开，或 `项目设置 → 插件 → Breakpoint MCP` 未启用 | 让用户打开编辑器并启用插件；`dbg_launch` 走这条通道 |
| 工具不存在 | 回第 1 步 | — |

自检失败就不要"改用 bash 跑一下试试"——bash 通道拿不到运行态、断点和断言。

## 3. 跑起来（`scene` 必传）

```text
dbg_launch({"scene":"res://main.tscn","stop_on_entry":false})
```

| 改动 | `scene` |
| --- | --- |
| `main.gd`、世界生态、表现层（天气/昼夜/光照/音效） | `res://main.tscn` |
| 战棋：`scripts/scenes/battle.gd`、`scripts/battle/`、`scripts/systems/`、`scripts/core/`、`scripts/iso/` | `res://main.tscn` 然后注入 P 进 B1 |
| 技能 / 物品 | `res://scenes/SkillTest.tscn` |
| 地图编辑器 | `res://scenes/MapEditor.tscn` |
| 标题 / 主菜单 | `res://scenes/Title.tscn` |
| 契约测试 | 不启场景，走 headless |
| 拿不准 | `res://main.tscn` |

进战斗（P 是 `main.gd` 里的裸键处理，`KEY_P = 80`，不在 InputMap）：

```text
runtime_inject_input({"confirm":true,"event":{"kind":"key","keycode":80,"physical_keycode":80,"pressed":true}})
runtime_inject_input({"confirm":true,"event":{"kind":"key","keycode":80,"physical_keycode":80,"pressed":false}})
```

两个易错点：

- **`res://scenes/Battle.tscn` 不能直启**：它读 `SceneArgs.battle_args["chapter"]`，只有 `main.gd` 的 `_enter_battle()` / `_enter_battlefield()` 会注入；直接 launch 拿到空 chapter 报错。
- `dbg_launch` 不传 `scene` 只会进 `project.godot` 的默认主场景，等于在赌。

## 4. 验收：断言优先，print 不算验证

改完的"完成"定义 = **一条通过的断言 + `error` 日志为空**。

| 想确认 | 工具 |
| --- | --- |
| 某节点某属性 == 期望 | `runtime_assert_node_state({path, expect:{hp:0}, tolerance:0.01})` |
| 节点存在 / 类型对 / 已消失 | `runtime_assert_scene_structure({expect:[{path:"...",type:"Sprite2D"},{path:"...",absent:true}]})` |
| 屏幕上出现/消失某段文字 | `runtime_assert_screen_text({text:"...", present:true, regex:false})` |
| 等异步状态到位 | `runtime_await_condition({path,property,value,op:"eq",timeout_ms:5000})` |
| 运行日志（先看这个） | `runtime_get_log({"levels":["error","warning"]})` |
| 增量日志 | `runtime_get_log({"since_seq":<上次 latest_seq>,"levels":["error"]})` |
| 性能没退化 | `runtime_get_monitors()` → `runtime_assert_perf({baseline, tolerance})` |

- **`runtime_get_log` 不带 `levels` 会吐整个环形缓冲**（实测一次 130KB+，把上下文冲掉）。**永远**带 `levels`，并带上一次的 `latest_seq` 做增量。
- **要算表达式 / 看私有字段：没有 `runtime_evaluate`**（运行时侧只有 `runtime_get_property` / `runtime_read_state` / `runtime_call_method`）。非求值不可时，`dbg_set_breakpoints` + `dbg_launch` 停住后 `dbg_evaluate({expression:"...","confirm":true})`——必须先 `stopped`，否则报 `not_stopped`。
- **截图（`runtime_screenshot` / `runtime_screenshot_diff`）属侵入性手段**：先在代码里问一遍"断言判不了吗"，仍判不了再**征得用户同意**；同意后用 `runtime_screenshot_diff`（带参考图 + tolerance）而不是靠人眼比对。像素级回归才值得截图。
- 截图/断言都基于**当前运行实例**；换了场景或重启过，要重新断言，不要复用旧的判断。

## 5. 断点（只在断言判不了时）

```text
dbg_set_breakpoints({"path":"res://scripts/scenes/battle.gd","lines":[672]})   # 缓冲，等 launch 应用
dbg_launch({"scene":"res://main.tscn"})                                      # + 注入 P
dbg_stack_trace()                                                            # 命中后 state=stopped
dbg_continue()                                                               # 放行
```

看变量：`dbg_scopes({"frame_id":0})` → `dbg_variables({"variables_ref":N})`。单步 `dbg_step({"kind":"over"})`。改活值 `dbg_set_variable` 是破坏性的，先问用户。

行号会随重构漂移：设断点前用 `find_symbol` / `find_usages` / `project_search` 确认目标函数当前行号（这三个不需要编辑器，很快）。

## 6. 已知坑（按踩到频率）

1. 工具名是 `mcp__godot__*`（**双下划线**）；写成点号 = tool not found。
2. 改了脚本但行为没变：删 `.godot/editor` 再重启编辑器；`dbg_restart` **不会**重新编译脚本。
3. `GODOT_BIN` 的 CLI 通道不可用（`godot_run_project` / `godot_version` 未注入），调试一律走 `dbg_launch` + `runtime_*`。
4. 多次 `dbg_launch` 会留下多个 `pixel_world` 窗口；截图/断言前先 `runtime_get_tree` 认准实例。
5. 日志洪水：`!std::isfinite(p_size.x)`（`scene/gui/control.cpp:1527`）是项目里的 Control 尺寸 NaN 问题，会刷满 ring buffer；看日志先按 `levels:["error"]` + `since_seq` 过滤，别把它当成你刚改出来的。
6. `game_hud_contract.gd` 在 HEAD 上本来就坏，别把它当回归。
7. `editor_*`（含 `editor_ping`、`editor_screenshot`）没被注入；需要编辑器侧操作时让用户动手，不要反复试工具名。

## 7. 深入索引（本文件不展开 49 个常驻工具，全在 tool-names.md）

- `.dsh/skills/godot-debug/tool-names.md` — 常驻工具签名 + 「意图 → 工具」表 + 295 个全量名字（标注了哪些没注入）+ 不存在的名字清单
- `rules/godot-tools-map.md` — 298 工具的分类地图（旧口径，实际注册 295）；其中 editor/lsp 部分对应本会话未注入的组
- `rules/mcp-debugging.md` 完整调试流程、断点位置表、截图方案对比
- `AGENTS.md`「场景（改哪跑哪）」与「验证」硬约束
- `addons/breakpoint_mcp/CLAUDE.md` 桥接插件本身（端口 / 版本 / 配置 / `BREAKPOINT_TOOLSETS`）
