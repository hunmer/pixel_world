# 索引变更记录（breakpoint_mcp）

> 本文件记录本模块 `CLAUDE.md` 索引的生成 / 更新。仅保留最近 5 条（倒序）。

## 2026-07-28 — 初始化（首次生成）

- **范围**：`addons/breakpoint_mcp/`（vendored 第三方调试插件 v1.9.1）。
- **生成**：`CLAUDE.md`（轻量索引）+ `claude/` 下 6 个详情文件（overview / conventions / entrypoints / public-interfaces / faq / changelog）。
- **省略的详情文件**：module-responsibilities / dependencies-and-config / data-model / testing-and-quality / file-map —— 该模块体量小且自带 `README.md`，上述内容已并入 overview/entrypoints/conventions，单独成文价值低（遵循"无事实依据可省略"原则）。
- **覆盖率**：`plugin.cfg`、`README.md`、8 个 `.gd`（plugin/bridge_server/runtime_bridge/operations/variant_json/status_dock/pause_latch/bridge_secret）结构与关键逻辑已扫；`operations.gd`(4614 行) 与 `runtime_bridge.gd`(1012 行) 仅扫结构+头部，未逐方法展开。
- **跳过**：`icon.png`。
- **下一步建议**：若需在 host 端调用具体方法，按 `public-interfaces.md` 的能力清单对照 `operations.gd` 的 `_xxx` handler，或回上游 `docs/TOOL_CATALOG.md` 查参数 schema（本仓库未含）。
