# Breakpoint MCP — AI 上下文索引

## 模块简单介绍

`addons/breakpoint_mcp` 是一个 **vendored 第三方 Godot 编辑器插件**（作者 James Livingston，`plugin.cfg` v1.23.0，MIT）。它在启用时启动一个 **loopback TCP/JSON 桥**（`127.0.0.1:9080` 编辑器 / `9081` 运行时），把"活的 Godot 编辑器"和"正在运行的游戏"暴露给一个 MCP host，使外部 AI 助手能驱动引擎：场景/节点/资源 CRUD（全部带 undo/redo）、项目设置、ClassDB 查询、文档搜索、编辑器+游戏内截图，以及运行时桥（实时 SceneTree、属性读写、方法调用、信号、输入注入、Performance 监视器）。

技术栈：`@tool` EditorPlugin + `TCPServer`（`_process` 轮询，newline-delimited JSON）+ 自写 Variant⇄JSON 编解码 + 每项目密钥握手认证。要求 Godot 4.2+（4.4+ 推荐）。本项目（Godot 4.7）已在 `project.godot [editor_plugins]` **启用**。

> 这是**第三方组件**，改动应谨慎；优先参考其自带 [`README.md`](README.md)。本项目只是消费方，不维护其上游。

## 约定的规则

- **端口**：编辑器桥 `127.0.0.1:9080`，运行时桥 `9081`。分别用环境变量 `BREAKPOINT_BRIDGE_PORT` / `BREAKPOINT_RUNTIME_PORT` 覆盖，**必须在启动 Godot 之前设置**。
- **认证**：每项目 64 字符 hex 密钥存在 `res://.godot/breakpoint_mcp.secret`（`.godot/` 引擎管理、gitignore，不入版本库）。两桥与 host 读同一文件；host 可用 `BREAKPOINT_BRIDGE_SECRET`/`BREAKPOINT_RUNTIME_SECRET` 覆盖。常量时间比较。
- **安全边界**：仅绑定 loopback；mutation 操作经 host 的 elicitation 门控；**不要把端口暴露到 `127.0.0.1` 之外**。
- **主线程**：所有 handler 在主线程跑（socket 从 `_process` 轮询），无需 marshal。
- **协议**：每行一个 JSON 对象（`\n` 结尾），双向。方法名 1:1 对应 host 的 `editor_*`/`scene_*`/`node_*`/`runtime_*` 工具。

> 细节见 [claude/conventions.md](claude/conventions.md)。

## 文件索引

| 文件 | 用途 | 何时阅读 |
| --- | --- | --- |
| [README.md](README.md) | 插件官方说明（安装/状态 dock/协议/安全） | **先读** —— 权威来源 |
| [LICENSE](LICENSE) | 许可证 | 关心再分发时 |
| [claude/overview.md](claude/overview.md) | 本插件在本项目中的角色与运行形态 | 理解它如何被 pixel_world 用 |
| [claude/conventions.md](claude/conventions.md) | 端口/密钥/协议/安全约定 | 调试桥配置时 |
| [claude/entrypoints.md](claude/entrypoints.md) | 插件生命周期、autoload、文件职责 | 改/排查插件时 |
| [claude/public-interfaces.md](claude/public-interfaces.md) | JSON 协议、方法清单（editor/scene/node/runtime）、事件 | 写 MCP host 端 / 调用方法时 |
| [claude/faq.md](claude/faq.md) | 常见问题与定位 | 卡住时先查 |
| [claude/changelog.md](claude/changelog.md) | 本索引的生成/更新记录 | 查索引更新史 |

## 扫描状态

- **更新时间**：2026-07-28
- **已扫描**：`plugin.cfg`、`README.md`、全部 8 个 `.gd`（plugin / bridge_server / runtime_bridge / operations / variant_json / status_dock / pause_latch / bridge_secret）的结构与关键逻辑、`operations.gd` 的 28+ 个 dispatch 方法。
- **跳过**：`icon.png`。
- **覆盖率**：源码结构 ~100%；`operations.gd`（4614 行）与 `runtime_bridge.gd`（1012 行）仅扫了结构与头部，未逐方法展开。
- **下一步建议**：若要在 host 端新增工具调用，按 [claude/public-interfaces.md](claude/public-interfaces.md) 的方法清单对照 `operations.gd` 的 `_xxx` handler。
