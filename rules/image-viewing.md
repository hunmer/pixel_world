# Rule: 图片查看

> 本规则是 `AGENTS.md`「关键约束」的展开。**禁用 `view_image`，用 CLI 识图（gemini 或 minimax）**——这是硬约束，详见 AGENTS.md。

查看或描述任意本地图片时，**禁止使用 `view_image` 工具**，必须使用 CLI 识图。可选两种方案，按可用性和效果择一。

工作目录统一为工程根 `/Users/Zhuanz/Documents/pixel_world`；截图/图片存 `tmp/screenshots/`（`/tmp/` 已在 `.gitignore` 忽略，不会污染仓库）。

## 方案 A：gemini CLI（默认）

```bash
gemini -y --skip-trust "请详细描述这张图片的内容: <图片绝对路径>"
```

示例：

```bash
gemini -y --skip-trust "描述: /Users/Zhuanz/Documents/pixel_world/tmp/screenshots/battle_init.png"
```

## 方案 B：minimax CLI（备选，opencode）

先 `cd` 到工程根，再用 opencode 调起 MiniMax-M3 模型。`--auto` 跳过确认直接跑完。

```bash
cd /Users/Zhuanz/Documents/pixel_world
opencode run -m minimax-cn-coding-plan/MiniMax-M3 --auto "请详细描述这张图片的内容: <图片绝对路径>"
```

示例：

```bash
opencode run -m minimax-cn-coding-plan/MiniMax-M3 --auto \
  "描述: /Users/Zhuanz/Documents/pixel_world/tmp/screenshots/battle_init.png"
```

> 何时用 minimax：gemini CLI 不可用、被限流、或对 UI 截图细节识别不佳时换用。模型 ID 带 `cn` 前缀走国内端点。

## 例外：MCP 截图无需走 CLI

MCP 返回的 PNG 内容（`mcp__godot__runtime_screenshot` / `mcp__godot__screenshot_editor`）会**直接进对话上下文**，agent 能直接看到，无需另存盘 + CLI 识图。

只有以下情况才需要走 CLI（gemini / minimax）：

- 本地已存在的图片文件（如 `tmp/screenshots/` 下的存档截图、参考图）。
- 系统级窗口截图（方法 C，见 @rules/mcp-debugging.md）保存到磁盘的 PNG。

截图获取方式的完整对比见 @rules/mcp-debugging.md 的「截图调试流程」。
