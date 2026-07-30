# Rule: Godot MCP 调试流程

> 本规则是 `AGENTS.md`「关键约束」的展开。MCP 命名空间、scene 必传、CLI 不可用等硬约束见 AGENTS.md;本文讲**完整操作流程**。

## Godot MCP 工具集（Breakpoint MCP）

当前可用的 MCP 工具命名空间是 `mcp__godot__*`（**双下划线**，不是旧文档里的点号 `mcp__godot.*`）。所有工具按桥接通道分两类：

| 通道 | 依赖 | 典型工具 |
| --- | --- | --- |
| **编辑器桥接**（127.0.0.1:9080） | Godot 编辑器打开 + 启用 "Breakpoint MCP" 插件 | `editor_*`、`scene_*`、`node_*`、`runtime_*`、`dbg_*`（launch 模式）、`gd_*`、`vcs_*` |
| **CLI 直调** | `GODOT_BIN` 环境变量指向 godot.exe | `godot_run_project`、`godot_export`、`godot_import`、`godot_version` |

> 当前环境 **CLI 通道未配置**（`godot_version` 返回空），**所有调试都走编辑器桥接通道**——这也是功能更全的通道（断点、运行时变量、日志、截图都有）。

### 前置检查（每次会话开头跑一次）

```text
mcp__godot__editor_ping()         # 应返回 pong:true, addon_version, godot 版本
mcp__godot__editor_get_state()    # 看当前编辑的场景 / 选中的节点
```

如果 `editor_ping` 报 `Cannot reach the Godot editor bridge at 127.0.0.1:9080`：编辑器没开，或 `项目设置 → 插件 → Breakpoint MCP` 没启用。

## 调试流程

1. 先确认工程目录，不要把仓库根目录当 Godot 工程：

```bash
rg --files -g "project.godot" "D:/phaserjs"
```

预期结果：

```text
godot/project.godot
```

2. 启动游戏（走编辑器桥接的 debug launch），**必须显式传入 `scene` 参数指定要运行的场景**，不要省略。

   工程默认主场景是 `res://scenes/Title.tscn`（开始游戏界面，`project.godot` 里 `run/main_scene`）。省略 `scene` 会直接进入这个界面，无法到达调试场景。`dbg_launch` 支持可选 `scene` 参数覆盖默认主场景：

```text
mcp__godot__dbg_launch({ "scene": "<要运行的场景>", "stop_on_entry": false })
```

   **根据本次修改的文件决定启动哪个场景**（核心原则：改什么模块，就跑能覆盖该模块的最小场景）。场景对照表见 `AGENTS.md` 的「场景对照表」章节（高频查阅，留在主文件）。

   > ⚠️ 不要省略 `scene` 参数跑默认主场景——那只会进入开始游戏界面，达不到调试目的。如果一次改动跨多个模块，选覆盖面最广的那个（通常 `debug_test.gd`）。

   成功信息应类似：

```text
{ "session_id": "godot", "state": "running", "scene": "res://scenes/BattleTest.tscn" }
```

3. 读运行时输出/日志（两路互补）：

```text
# 引擎启动日志 + print 输出（最接近旧 get_debug_output）
mcp__godot__runtime_get_log()

# 只看 error/warning 级别
mcp__godot__runtime_get_log({ "levels": ["error", "warning"] })

# 增量读：只取 seq > 上次返回的 latest_seq 的新条目
mcp__godot__runtime_get_log({ "since_seq": <上次的 latest_seq> })
```

   正常应包含：`Godot Engine v4.7.1.stable...`、`Vulkan ... Forward+ ...`，且 `error/warning` 列表为空。

   > 还可以读**性能监控**（FPS / Draw Call / 节点数）：`mcp__godot__runtime_get_monitors()`

4. 如果 `dbg_launch` 报 `No active Godot process` 或桥接连不上：先 `editor_ping` 确认编辑器还在、插件还启用，再重新 launch。

5. 结束调试会话：`mcp__godot__dbg_restart`（重启用同一参数）或直接关游戏窗口（会话自动结束）。

## 断点调试（重点功能）

这是本 MCP 区别于普通 run-and-log 工具的核心能力，可以在攻击/技能/回合切换等关键函数停下来查看变量。

**流程**：先 `dbg_set_breakpoints`（断点会缓冲，launch 时一起应用）→ `dbg_launch` → 等 1-3 秒 → `dbg_stack_trace` 看是否命中。

```text
# 1. 设断点（res:// 路径，1-based 行号；可选 conditions/hit_conditions/log_messages）
mcp__godot__dbg_set_breakpoints({
  "path": "res://scripts/scenes/battle.gd",
  "lines": [461, 862]   # 461=_resolve_combat 玩家/托管攻击, 862=_resolve_combat_sync 敌方回合攻击
})

# 2. 启动（托管默认 true，会自动产生攻击触发断点）
mcp__godot__dbg_launch({ "scene": "res://scenes/BattleTest.tscn" })

# 3. 查调用栈（命中后 state=stopped）
mcp__godot__dbg_stack_trace()
# 期望返回类似：
#   frame 0: _resolve_combat_sync  battle.gd:862
#   frame 1: _enemy_act            turn_director.gd:249

# 4. 看局部变量（frame_id 从 stack_trace 拿）
mcp__godot__dbg_scopes({ "frame_id": 0 })          # 返回 Locals/Members/Globals 的 variables_ref
mcp__godot__dbg_variables({ "variables_ref": 1 })  # 展开 Locals：attacker/defender/result/...

# 5. 单步：over=不进函数 / in=进入 / out=跳出
mcp__godot__dbg_step({ "kind": "over" })

# 6. 继续，直到下一个断点
mcp__godot__dbg_continue()
```

**常用断点位置（battle.gd）**：

| 行号 | 函数 | 触发时机 |
| --- | --- | --- |
| 461 | `_resolve_combat` | 玩家方/托管方主动攻击（含 await 演出版） |
| 475 | 同上，`CombatSystem.execute` 调用处 | 攻击结算前，可看 result |
| 857 | `_resolve_combat_sync` | 敌方回合攻击（同步版） |
| 862 | 同上，`CombatSystem.execute` 调用处 | 敌方攻击结算前 |
| 529 | `_resolve_skill` | 技能演出 |
| 592 | `_resolve_item` | 物品演出 |
| 889 | `_check_battle_end` | 胜负判定 |

**运行时改值（不重启实验）**：

```text
# 把 variables_ref=1 里名为 defender 的 hp 改成 0，验证死亡分支
mcp__godot__dbg_set_variable({ "variables_ref": 1, "name": "defender.hp", "value": "0" })
```

> `dbg_set_variable` 是破坏性的（改了活游戏状态），改前先跟用户确认。

**条件断点 / 日志点**（adapter 支持时才生效，Godot 4.3 不支持条件断点，4.7 需实测）：

```text
mcp__godot__dbg_set_breakpoints({
  "path": "res://scripts/scenes/battle.gd",
  "lines": [461],
  "conditions": ["attacker.faction == \"player\""]   # 只在玩家方攻击时断
})
```

## 截图调试流程

> **优先用 MCP 内置截图**，比 Win32 桌面裁剪可靠得多（Vulkan 窗口用 `PrintWindow`/`CopyFromScreen` 常得到空白或极小 PNG）。如果用户有要求截图查看再使用，默认不使用。

### 方法 A：MCP 运行时截图（推荐）

游戏运行中截当前游戏帧（返回 PNG 内容，可直接查看）：

```text
mcp__godot__runtime_screenshot()
```

如果要和参考图做像素级回归比对（防渲染回退）：

```text
# 先存一张参考图到工程里（runtime_screenshot 返回的内容手动落盘到 res:// 或 user://）
mcp__godot__runtime_screenshot_diff({
  "reference": "res://tests/fixtures/battle_init.png",
  "tolerance": 0.02,            # 允许 2% 像素差异
  "per_channel_threshold": 8    # 每通道差值阈值
})
```

### 方法 B：编辑器视口截图

截 2D/3D 编辑器视口（需要对应编辑器 tab 处于激活状态）：

```text
mcp__godot__screenshot_editor({ "viewport": "3d" })   # 或 "2d"
```

### 方法 C：Windows 原生窗口裁剪（备用，MCP 截图失效时）

只有 MCP 截图不可用时才用这套。步骤：

1. 找到运行窗口：

```powershell
$p = Get-Process | Where-Object { $_.MainWindowTitle -like "*Tactics RPG (DEBUG)*" } | Select-Object -First 1
$p | Select-Object Id,ProcessName,MainWindowTitle,MainWindowHandle
```

2. 如果窗口最小化，先恢复窗口。最小化窗口常见坐标是 `-32000,-32000`，此时截图会是无效小图：

```powershell
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Win32Window {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
'@

[void][Win32Window]::ShowWindow($p.MainWindowHandle, 9)
[void][Win32Window]::SetForegroundWindow($p.MainWindowHandle)
Start-Sleep -Seconds 1
```

3. 截取窗口所在屏幕区域：

```powershell
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Win32Rect {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [StructLayout(LayoutKind.Sequential)] public struct RECT {
    public int Left; public int Top; public int Right; public int Bottom;
  }
}
'@

$rect = New-Object Win32Rect+RECT
[void][Win32Rect]::GetWindowRect($p.MainWindowHandle, [ref]$rect)
$w = $rect.Right - $rect.Left
$h = $rect.Bottom - $rect.Top

$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $w, $h))
$g.Dispose()

# 截图统一保存到 .screenshots 文件夹（已加入 .gitignore）
$dir = "D:/phaserjs/.screenshots"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$out = "$dir/godot_debug_window_desktopcrop.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Get-Item $out | Select-Object FullName,Length,LastWriteTime
```

有效截图通常应大于 1 MB；如果只有几百字节，先检查窗口是否最小化或被移动到屏幕外。

> 所有调试截图统一保存到 `D:/phaserjs/.screenshots/`，该目录已在 `.gitignore` 中忽略，不会入库。

## 已知坑

- MCP 工具名是 `mcp__godot__*`（**双下划线**），不是旧文档里的 `mcp__godot.*`（点号）。点号写法会报 "tool not found"。
- **CLI 通道（`godot_run_project` / `godot_version` 等）当前不可用**（`GODOT_BIN` 未配置），返回空。所有调试走编辑器桥接通道的 `dbg_launch` / `runtime_*` / `dbg_*`。
- `editor_ping` 报 `Cannot reach the Godot editor bridge at 127.0.0.1:9080`：编辑器没开，或 `项目设置 → 插件 → Breakpoint MCP` 没启用。
- 多次 `dbg_launch` 后可能留下多个 `Tactics RPG (DEBUG)` 窗口；截图前用 `Get-Process` 确认要截的窗口。
- Vulkan/Godot 窗口用 `PrintWindow` / `CopyFromScreen` 可能得到空白或极小 PNG；优先用 `mcp__godot__runtime_screenshot`。
- `dbg_set_variable` 会改活游戏状态，破坏性操作，改前跟用户确认。
- 断点不命中？检查：(1) `dbg_set_breakpoints` 返回的 `buffered: true`（已缓冲，等 launch 应用）；(2) 路径用 `res://` 前缀；(3) 行号是 1-based。
- 使用 powershell 读取文件乱码，是因为 powershell 里读取中文字符没有设置编码格式的问题，而不是代表文件是乱码。

## 验证优先级（代码测试 > 截图测试）

> 与 `AGENTS.md`「验证优先级」约束呼应。默认走代码断言，截图是需人工解读的侵入性手段，发起前必须先征得用户同意。

**默认只用代码测试**，按判定需求选工具：

| 想验证什么 | 首选工具（不截图） |
| --- | --- |
| 某节点某属性 == 期望值 | `runtime_assert_node_state`（支持数值 `tolerance`） |
| 场景树结构（节点存在/类型/缺失） | `runtime_assert_scene_structure` |
| 屏幕上有没有出现某段文字 | `runtime_assert_screen_text`（支持 `regex` / `present:false` / `min_count`） |
| 性能没退化 | `runtime_get_monitors` + `runtime_assert_perf`（先存基线再比对） |
| 等异步状态到位再断言 | `runtime_await_condition`（轮询直到满足/超时） |
| 纯逻辑自测 | 自测脚本 `*_test.gd`（见场景对照表）/ `debug_test.gd` |
| 查变量、跟调用栈 | `dbg_set_breakpoints` + `dbg_stack_trace` + `dbg_scopes`/`dbg_variables` |

**截图验证（`runtime_screenshot` / `runtime_screenshot_diff` / `screenshot_editor`）的启用条件**：

1. **先征得用户明确同意**（一次同意只对当前验证点有效，下个验证点要再问）。
2. 仅在代码断言无法判定时用——例如纯视觉回归、布局像素级检查、用户主动要求"看看效果"。
3. 同意后优先用 `runtime_screenshot_diff`（带参考图 + `tolerance`，像素级客观判定），而不是 `runtime_screenshot` 后靠人眼比对——前者本身就是一种"代码测试"，能给出 pass/fail。

> 原则：**能用断言判定的就绝不截图**。截图本节下面「截图调试流程」里的方法仅在满足上述条件时才调用。

## 最短验收

1. `mcp__godot__editor_ping` 返回 `pong: true`（桥接连通，插件启用）。
2. `mcp__godot__dbg_launch({ "scene": "res://scenes/BattleTest.tscn" })` 返回 `state: "running"`，且必须按 AGENTS.md 的场景对照表显式传入 `scene` 参数（不能省略，否则只进入默认开始界面 `res://scenes/Title.tscn`）。
3. `mcp__godot__runtime_get_log({ "levels": ["error", "warning"] })` 返回空列表。
4. **用代码断言验证改动效果**（见上「验证优先级」表），而非截图。如改的是渲染/布局、断言无法覆盖且**用户已同意**，才走 `runtime_screenshot()` / `runtime_screenshot_diff()`。
