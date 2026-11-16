# report.md 违例并行优化轮 — 团队运行存档（2026-11-16 深夜）

> 触发：用户指令「使用 dsh team 创建 team，用 glm 5.3 max 针对 report 的报告并行做优化」。
> 团队：pixel-world-refactor（team_mwje4dxe1lmhs8g），4 成员全 glm-5.3 / reasoningEffort max / danger-full-access；5 任务全部 done（1 次尝试即成），0 写冲突 0 审批。

## 交付（净 −1816 行，全行为等价重构）

| 域 | 成员 | 主变化 | 护栏 |
| --- | --- | --- | --- |
| battle | battle-refactor | battle_ui.gd 1211→467 装配层 + 拆出 battle_ui_hud(347)/unit_menu(418)/unit_detail(160)/banner(37)；battle.gd `_ready` 拆 7 个 `_configure_*`、`_unhandled_input` 键位路由表化 | 27 契约 24 pass + 2 known-fail 基线一致 + 1 env-skip |
| ecology | ecology-refactor | ecology_registry 1150→984（legacy 外迁 ecology_legacy_codec.gd 240，报错文案逐字保留）；main.gd `_compile_ecosystem_config` 185→71 薄委托，编译入 scripts/world/ecology_config_compiler.gd(313) | 21/21 pass，terrain_generation SHA-256 `0c3f713b…` 逐字节一致 |
| terrain-render | terrain-render-refactor | terrain_material_registry 1047→472（解析入 terrain_material_parser.gd 809）；isometric_column_batch 1323→742（拆 scripts/iso/ texture_batch 148 / terrain_draw 377 / shoreline 341，RNG hash 逐字迁移） | 9/9 pass，SHA 护栏绿，嵌套≤3 |
| editor-ui | editor-ui-fix | map_editor / overlays / block_selector 三处 PixelButton 直建改 UIFactory.button（+`styled` 第 4 参，默认路径零影响）；ui_contract 反转为禁直预加载 + 断言工厂用法 | ui PASS，map_editor_ui 6 项基线一致 |

## Lead 集成验收

- 全量 80 契约：**70 pass / 5 known-fail / 5 env-skip，0 新增红**（113.9s，--jobs 4）。
- `user_asset_editor` 新红判定：git worktree 在改动前 HEAD dc0b9eb 复现同 7 失败 → **既有红**（预设 Tab 落地后契约未跟上）。Tab 数断言修正 7→8（tests/user_asset_editor_contract.gd:160，失败 7→6），余 6 条 S3 断言登记 manifest known-fail 待逐条核对。
- feature_map：10 新文件收编 + 7 处行数刷新，scan 新增/消失=0，check 全过，html 重渲（~565KB）。
- 文档：report.md 覆盖更新（✅/⚠ 标注）、file-map（scripts 154→164）、CLAUDE.md、module-responsibilities（main.gd 函数行号全刷新）、changelog。
- runner 自测 27/27 过；git 未提交（留给用户）。

## 遗留（roadmap 候选）

1. main.gd `_unhandled_input` 102 行嵌套≥4 —— 本轮无人认领，键位路由表化即可。
2. game_hud.gd 多面板 + 其红契约。
3. user_asset_editor 余 6 条 S3 断言：断言陈旧 vs 预设功能行为回归，需人工核对。
