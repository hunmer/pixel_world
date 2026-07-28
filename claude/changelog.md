# 索引变更记录

> 本文件记录 `CLAUDE.md` 索引本身的生成 / 更新，**不是产品 Changelog**。仅保留最近 5 条（倒序）。

## 2026-07-28 — 初始化（首次生成）

- **范围**：全仓库根目录 + 1 个 vendored 模块（`addons/breakpoint_mcp`）。
- **生成**：
  - 根 `CLAUDE.md`（轻量索引）+ `claude/` 下 10 个详情文件（overview / conventions / module-responsibilities / entrypoints / public-interfaces / dependencies-and-config / data-model / testing-and-quality / file-map / faq）。
  - `addons/breakpoint_mcp/CLAUDE.md` + 其 `claude/`（overview / conventions / entrypoints / interfaces / faq / changelog）。
- **识别的"模块"判定**：仓库为单体 Godot 游戏，无 `package.json`/多 `plugin.cfg` 子工作区；`scripts/` 各子目录是同应用内的源码子域，归入根 `claude/module-responsibilities.md` 与 `file-map.md` 统一描述，避免过度碎片化。唯一带独立 `plugin.cfg` 的 `addons/breakpoint_mcp` 单列。
- **覆盖率**：源码层 104 个 `.gd` 全部纳入结构归纳（`main.gd` 函数级、`scripts/` 文件级、`tests/` 逐脚本归类）；22 个 `.json` 配置逐文件结构化；4 个 `.tscn`、7 个 `.md`、4 个 `.gdshader` 已覆盖。**未深度读取**：`.png`(197)/`.mp3`(8) 二进制素材、`.import`(180)/`.uid`(108) 引擎生成物、`.obj`/`.mtl`(2+2) 网格。
- **缺口 / 下一步建议**：
  1. `tests/` 27 个契约脚本的当前通过状态**未执行验证**（需 Godot 运行环境）—— 建议跑一轮 `godot --headless --script` 确认基线。
  2. 战棋 `scripts/core/`、`scripts/systems/` 的函数精确签名未逐行展开（仅文档化职责与对外接口形态）—— 若要重构建议补扫。
  3. `shaders/*.gdshader` 着色器参数未记录细节 —— 若调整视觉表现建议补扫。
  4. `config/ecology/` 各 JSON 的完整字段 schema 未逐键列出（仅记录顶层结构）—— 加新内容时按 `config/README.md` 与 `config/ecology/README.md` 为准。
  5. HANDOFF 引用的外部 `phaserjs/` 源项目不在本仓库，战棋代码溯源需回外部项目。
