# 开发约定（breakpoint_mcp）

## 端口与端点

| 桥 | 默认端口 | 覆盖环境变量 | 运行位置 |
| --- | --- | --- | --- |
| 编辑器桥 | `127.0.0.1:9080` | `BREAKPOINT_BRIDGE_PORT` | Godot 编辑器内（`@tool`） |
| 运行时桥 | `127.0.0.1:9081` | `BREAKPOINT_RUNTIME_PORT` | 运行中的游戏（autoload） |

> 环境变量必须在 **启动 Godot 之前** 设置（脚本读 `OS.get_environment` 一次）。

## 认证

- 每项目密钥：`bridge_secret.gd` 在 `res://.godot/breakpoint_mcp.secret` 生成并读取（64 字符 hex）。
- `.godot/` 由引擎管理且 gitignore —— 密钥不入版本库。
- 编辑器桥、运行时桥、host 三者读**同一文件**，零配置一致。
- host 端可用 `BREAKPOINT_BRIDGE_SECRET` / `BREAKPOINT_RUNTIME_SECRET` 环境变量覆盖（用于 host 启动子进程等高级场景）。
- 比较用常量时间；IO 不可恢复时返回空串 → 桥在**无认证 + 警告日志**下继续，而非阻塞。

## 协议

- **传输**：loopback TCP，每行一个 JSON 对象（`\n` 结尾），双向。
- **请求**：`{"id":"<string>","method":"node.add","params":{...}}`
- **响应**：`{"id":"...","ok":true,"result":{...}}` 或 `{"id":"...","ok":false,"error":{"code":"no_scene","message":"..."}}`
- **事件（服务器→客户端 push）**：如 `godot://editor-state`、`godot://scene-tree`、`resources/updated`（选择/场景变化时广播）。
- 方法名 1:1 对应 host 的 `editor_*` / `scene_*` / `node_*` / `runtime_*` 工具。

## 安全边界（重要）

- **仅 loopback**：两桥只绑 `127.0.0.1`。**绝不要把端口转发或暴露到 `127.0.0.1` 之外** —— 那等于把编辑器/游戏的完整控制权交出。
- mutation 操作的"破坏性确认"门控在 **host 端**（elicitation）；密钥握手把这层门控的"牙齿"补到 addon 侧，防本机其他进程直连 socket 绕过 host。
- 主线程执行：所有 handler 在引擎主线程（socket 从 `_process` 轮询），无需线程 marshal。

## 启用 / 禁用

- 本项目已在 `project.godot` 的 `[editor_plugins] enabled=PackedStringArray("res://addons/breakpoint_mcp/plugin.cfg")` **启用**。
- 启用时 `plugin.gd._enter_tree`：起 server + dock + 注册运行时 autoload + 清 PauseLatch。
- 禁用时 `_exit_tree`：拆 dock、移除 autoload、`server.shutdown()`、清 PauseLatch。

## 改动建议

- 这是 **vendored 第三方代码**（v1.9.1）。改它会影响升级路径，优先在 host 端或游戏侧解决。
- 若必须改：所有 mutation handler 仍要走 `EditorUndoRedoManager`；新增 method 在 `operations.gd` 加 `_xxx(params)` 并在 `dispatch()` 注册。
