# 架构总览（breakpoint_mcp）

## 角色

`breakpoint_mcp` 不是游戏逻辑，而是**调试基础设施**：让一个外部的 MCP host（AI 助手运行的地方）能通过本地 TCP 操控 Godot 编辑器与运行中的游戏。在本项目中，`HANDOFF.md` 提到的 `mcp__godot__*` 工具（`editor_ping` / `dbg_launch` / `runtime_assert_*` / `runtime_get_log` 等）正是经此桥由外部 host 暴露的。

## 运行形态

```text
启用插件（project.godot [editor_plugins]）
  → plugin.gd._enter_tree()
      ├─ bridge_server.gd (Node)      编辑器桥，监听 127.0.0.1:9080
      │     └─ operations.gd          所有 editor_*/scene_*/node_* 请求处理（带 undo/redo）
      ├─ status_dock.gd (Control)     编辑器右侧 dock：桥健康/端口/复制 MCP 配置
      ├─ add_autoload_singleton("BreakpointRuntimeBridge", runtime_bridge.gd)
      │     → 项目运行时，runtime_bridge.gd 监听 127.0.0.1:9081，同协议
      │        暴露 runtime_*（SceneTree/属性/方法/信号/输入/Performance/截图/日志环）
      ├─ 监听 EditorInterface.selection + scene_changed → 广播 resource.changed 事件
      └─ PauseLatch.set_paused(false)  会话开始清掉残留 pause
```

关键设计取舍：

- **双桥、同协议**：编辑器桥（9080，`@tool`，跑在编辑器）与运行时桥（9081，autoload，跑在游戏内）用**同一种 newline-delimited JSON 协议**，host 用同套客户端代码。运行时桥**故意不是 `@tool`** —— 它必须在游戏里跑，不在编辑器。
- **每项目密钥**：`bridge_secret.gd` 在 `res://.godot/breakpoint_mcp.secret` mint 一个 64 字符 hex 密钥（`.godot/` 被 gitignore，不入库）。两桥 + host 读同一文件，零配置一致。这是对 loopback 之外"本机其他进程也能驱动桥"的防御纵深。
- **mutation 全部包 `EditorUndoRedoManager`**：`operations.gd` 里每个改动都进 undo/redo，host 的 elicitation 门控在更上层。
- **Godot 版本兼容**：`runtime_bridge.gd` 把 Logger 子类源码存成字符串，仅在 4.5+ 运行时编译 —— 保证 4.3/4.4 parse-clean。

## 在本项目中的边界

- 本项目**只是消费方**：用此桥做 AI 辅助调试（HANDOFF 记录的 `editor_ping`/`dbg_launch` 流程）。游戏运行逻辑本身**不依赖**此插件 —— 即便禁用它，pixel_world 仍可正常运行。
- `project.godot` 的 `[autoload]` 含 `BreakpointRuntimeBridge`（uid 形式），这是插件启用时由 `plugin.gd` **自动注册**的，不是手写。
