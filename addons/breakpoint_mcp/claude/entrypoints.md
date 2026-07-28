# 入口与文件职责（breakpoint_mcp）

## 生命周期入口

- **`plugin.cfg`** — 插件清单（name/description/author/version=1.9.1/script=plugin.gd）。Godot 据此识别插件。
- **`plugin.gd`**（`@tool EditorPlugin`，83 行）— 唯一引擎入口。
  - `_enter_tree()`：起 `BridgeServer`（编辑器桥）→ 加 `StatusDock` → `add_autoload_singleton("BreakpointRuntimeBridge", runtime_bridge.gd)` → 监听 selection/scene_changed → 清 PauseLatch。
  - `_exit_tree()`：反向清理。
  - 选择/场景变化 → `_server.broadcast_event(...)` 推 `resources/updated`。

## 文件职责

| 文件 | 行数 | 职责 |
| --- | --- | --- |
| `plugin.gd` | 83 | EditorPlugin 入口；启停 server/dock/autoload；事件广播 |
| `bridge_server.gd` | 212 | 编辑器侧 `TCPServer`，`_process` 轮询，newline-JSON 帧，分发到 operations |
| `runtime_bridge.gd` | 1012 | 运行时 autoload（游戏内），端口 9081，同协议；暴露 SceneTree/属性/方法/信号/输入/Performance/截图/日志环；非 `@tool` |
| `operations.gd` | 4614 | 编辑器侧所有 `editor_*/scene_*/node_*` 请求处理；每个 mutation 包 `EditorUndoRedoManager` |
| `variant_json.gd` | 108 | Variant⇄JSON 编解码（Vector*/Color/Rect2/NodePath/Quaternion 等用 `{"__type__":...}` 标签对象） |
| `status_dock.gd` | 360 | 编辑器 dock：桥健康（editor/runtime/LSP/DAP）、端口、一键复制 MCP 配置 |
| `bridge_secret.gd` | 61 | 每项目密钥 load/mint/比较（常量时间） |
| `pause_latch.gd` | 65 | 会话 pause 状态（持久到文件，会话开始清掉残留） |
| `icon.png` | — | 插件图标 |

## autoload

启用插件时，`project.godot [autoload]` 会出现 `BreakpointRuntimeBridge="*uid://37hq7s0ufjxo"`（指向 runtime_bridge.gd）。它是**自动注册**的，不需要手改 project.godot —— 禁用插件会自动移除。

## 启动顺序

```
Godot 编辑器启动（本插件已 enabled）
 → plugin.gd._enter_tree
     → BridgeServer.new().setup(self)  →  listen 127.0.0.1:9080
     → StatusDock 挂到右侧 dock
     → add_autoload_singleton(BreakpointRuntimeBridge)
 ────────────────────────────────────────
运行游戏（F5）
 → BreakpointRuntimeBridge autoload 进场景树
     → runtime_bridge._ready  →  listen 127.0.0.1:9081
 ────────────────────────────────────────
host 连 9080（编辑器）/ 9081（运行时），握手密钥，开始 dispatch
```
