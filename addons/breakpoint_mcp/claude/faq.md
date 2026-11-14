# 常见问题（breakpoint_mcp）

### Q1：host 连不上桥？
先确认：① 插件在 `project.godot [editor_plugins]` 已启用；② 编辑器已启动（编辑器桥 9080）/ 游戏已运行（运行时桥 9081）；③ 端口未被占用；④ host 读到了 `.godot/breakpoint_mcp.secret`。状态 dock（右侧）会显示各桥健康。

### Q2：端口怎么改？
启动 Godot **之前**设环境变量 `BREAKPOINT_BRIDGE_PORT`（编辑器）/ `BREAKPOINT_RUNTIME_PORT`（运行时）。脚本只在启动时读一次。

### Q3：密钥是什么 / 在哪？
`res://.godot/breakpoint_mcp.secret`（64 字符 hex，`.godot/` 被 gitignore 不入库）。`bridge_secret.gd.load_or_mint()` 自动生成/读取。host 端路径 `<projectPath>/.godot/breakpoint_mcp.secret`，或用 `BREAKPOINT_BRIDGE_SECRET`/`BREAKPOINT_RUNTIME_SECRET` 覆盖。

### Q4：这插件影响游戏逻辑吗？
不影响。它是调试基础设施；游戏代码不依赖它。禁用它 pixel_world 仍能正常运行（只是失去 AI 调试桥）。

### Q5：本项目 HANDOFF 里的 `editor_ping`/`dbg_launch`/`runtime_assert_*` 哪来的？
正是经此桥由**外部 MCP host** 暴露的工具（`mcp__godot__*`）。本仓库只提供桥（addon），不提供 host。host 在用户的 MCP 客户端侧配置。

> 在本仓库的 DSH 里，host 侧连接 `json-godot` 是**按会话启用**：默认工具表里没有 `mcp__godot__*`（实测激活 0 / 隐藏 285），要先激活；且只有 `BREAKPOINT_TOOLSETS=runtime,dap,knowledge` 的 49 个可激活（`editor_ping` 等 `editor_*` **不在**其中）。`tool not found` ≠ 没装。详见 `AGENTS.md` 与 `rules/godot-tools-map.md`。

### Q6：改了插件代码不生效？
插件是 `@tool`，改 `operations.gd` 等后可能需要在编辑器里重新加载插件（禁用→启用）或重启编辑器。运行时桥改动需重启游戏。

### Q7：能把它暴露到局域网让远程 AI 用吗？
**不要**。桥只绑 loopback 是刻意的访问控制；转发/暴露等于交出编辑器与游戏的完整控制权（含破坏性编辑操作）。

### Q8：方法参数 schema 在哪？
上游 `docs/TOOL_CATALOG.md`（本仓库未含）。本仓库 `operations.gd` 的 `_xxx(params)` handler 是实现侧权威；`public-interfaces.md` 归纳了能力清单。
