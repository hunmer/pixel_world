# main.gd / map_editor.gd 拆分终验报告 — 2026-11-15

> 终验人：main-split（pixel-split 团队）。回归执行时间 2026-11-15 21:16–21:37（macOS headless）。
> 结论先行：**main-split 无新增红**；确定性 SHA-256 全程未漂移；map_editor.gd 侧 user_asset_editor 的失败已由 editor-split 收口归因：**2026-11-15 午后编辑器功能提交轮（09:41–18:58 共 16 提交）造成的过期断言红，非 editor-split 拆分引入，也与 main-split 无关**（详见 §3.3）。

## 1. 回归范围与执行

- 现存契约全集：`tests/*_contract.gd` 共 **78** 个；按任务约束排除 4 个挂起契约（`action_anim` / `immersive_battle_camera` / `world_map_overlay` / `user_asset_source_live`，会挂 900s+），**实跑 74 个**，每契约 600s 看门狗。
- 基线口径：`docs/testing_baseline_2026-11-15.md`（62/72 通过；6 失败 + 4 超时）。基线后新增契约（editor 族等）两侧均不在失败集，不影响对比。
- 结果文件：`/tmp/final_baseline/summary.tsv`（逐契约 exit code / 秒数 / 状态 + 每契约独立 .log）。

## 2. 回归结果总表

| 指标 | 基线（拆分前） | 本次（拆分后工作区） |
|---|---|---|
| 通过 | 62 / 72 | **67 / 74** |
| 失败 | 6（+4 超时未计） | 7 |
| 确定性 SHA-256（terrain_generation, seed=42, 16641 采样） | `0c3f713b…bfc2f` | **`0c3f713b…bfc2f`（逐字节一致）** |

### 2.1 本次 7 个失败逐条归因

| 契约 | exit | 基线状态 | 归因结论 |
|---|---|---|---|
| battle_action_chain | 1 | ✗ 基线即红（B1 普攻 impact/飘字数量不一致） | **主题一致，非新增红** |
| battle_presentation_hooks | 1 | ✗ 基线即红（名牌 cue 未生成程序化音频） | **主题一致，非新增红** |
| isometric_view | 1 | ✗ 基线即红（多角度鼠标拾取偏移断言） | **主题一致，非新增红** |
| ui | 1 | ✗ 基线即红（map_editor.gd 直建 Button/OptionButton 违约） | **主题一致（指向 scripts/scenes/map_editor.gd，editor-split 域）** |
| map_editor_ui | 1 | ✗ 基线即红（选择模式菜单/虚线框/素材历史断言） | **主题一致，非新增红** |
| sunlight_3d_gl | 2 | ✗ 基线即败（headless 环境限制，基线文档明记） | **环境限制，非回归** |
| user_asset_editor | 1 | ✓ 基线通过（04:36 文档基线） | **当日午后编辑器功能轮所致的过期断言红（§3.3 已收口）：editor-split 动手前即红，与 main-split / editor-split 拆分工序均无关** |

### 2.2 基线失败→本次状态的完备映射

基线 6 失败中：5 个复跑仍红且主题一致（见上表）；`user_asset_source_live` 属 4 挂起契约，按约束未跑（基线即挂起 + 越界缺陷）。基线 4 超时中其余 3 个同为挂起契约未跑。**基线绿→本次红的唯一项 = user_asset_editor** —— 注意基线文档生成于 04:36（386508c），早于当日 09:41–18:58 的编辑器功能提交轮；editor-split 在动手改码前（20:14–20:23）的纯净捕获中该契约已 exit=1 / 7 FAIL。终局归因见 §3.3。

### 2.3 交叉证据

- 7 个失败契约的日志中，`grep main.gd|scripts/world/` **零命中**——失败链路不经过 main-split 的任何改动文件。
- main-split 六个批次（B1–B6）各自批内契约（合计 60+ 契约次）当时全部绿、零 SCRIPT ERROR；B7 全量与本表一致。

## 3. 拆分行数与方案执行偏差

### 3.1 行数对比（任务验收线：main.gd 至少抽走 ~1000 行，目标 ≤3300，理想 ≤3000）

| 文件 | 拆分前 | 拆分后 | 变化 | 验收 |
|---|---|---|---|---|
| main.gd | 4319 行 / 176 函数 | **2283 行 / 128 函数** | **-2036（-47.1%）** | ✅ 超理想线 |
| scripts/scenes/map_editor.gd | 3285 行 / 150 函数 | 2295 行（editor-split 进行中） | -990（-30.1%） | editor-split 域，其方案 5 批执行中 |

main-split 新增 12 模块（全部 `scripts/world/`，`class_name + extends RefCounted`，Callable 注入、无反向依赖），合计 3037 行：

| 模块 | 行数 | 批次 | 模块 | 行数 | 批次 |
|---|---|---|---|---|---|
| ecology_config_validator | 424 | B1 | world_query_service | 99 | B4 |
| terrain_texture_catalog | 192 | B1 | flora_spawner | 551 | B4 |
| minimap_renderer | 98 | B2 | fauna_streamer | 572 | B5 |
| player_occlusion_controller | 220 | B2 | animal_runtime | 575 | B6 |
| presentation_stage | 131 | B3 | ecosystem_match | 132 | B3 |
| species_picker | 43 | B4 | | | |

### 3.2 main_split_plan.md 执行偏差说明

1. **批次全部执行，无未执行批次**；B1–B6 契约清单按方案 §5 原样跑全，每批额外复跑 terrain_generation SHA。
2. **预估终态 1800±80 vs 实际 2283**：偏差源于方案内部矛盾——§5 预估行数按"全簇抽取"估算，而 §9 决策#3 明确不抽簇17（战棋入口，测试直调密集）且 #4 保留簇4/5/6（地形薄包装/流式红线/投影排序）。实际执行遵循决策（正确取舍），终态与决策自洽；验收线（≤3000）远超达标。
3. **每批实际抽取行数低于方案预估值**（如 B3 预估 ~270 实际 -75+B4 修正）：因测试直访面（tests/ 直调 34+ 个 main 私有函数/字段）必须保留同名薄委托，且部分常量/字段因跨簇引用留守。委托保留是契约兼容的硬约束，非执行遗漏。
4. **模块归属微调**：`_noise_instance_for_field` 方案归簇2（B1），实际因唯一调用方在植被簇而随 B4 迁入 flora_spawner；`species_picker` 从 M8 拆出独立 static 模块（方案 M9a 预留位）。
5. **B3 的 sunlight_3d_gl**：方案列入验证清单，实际按基线文档确认为环境限制必败项，不作为回归判据（已记录于方案 §8）。

### 3.3 user_asset_editor 失败归因（editor-split 收口，2026-11-15 21:41 终验）

- **结论：过期断言红 —— 由 2026-11-15 午后编辑器功能提交轮（09:41–18:58，`039f8c4..4c41c73` 共 16 提交）造成；非 editor-split 拆分引入，非 main-split 引入，非环境漂移。**
- 失败内容：`S3 应有 7 个 Tab` 等 7 项断言（65 checks 中 7 FAILURES），全部位于 S3 编辑器接入段（画笔/素材覆盖/工具互斥）。
- **证据链**（四步，均可复验）：
  1. **重构前后零变化**：editor-split 在动手改码前（20:14 起，工作区 = `4c41c73` 原版 + 仅 `docs/plans/` 未跟踪，`/tmp/editor_split_backup/batch_0_original.gd.bak` 与 `git show 4c41c73` 逐字节一致）捕获该契约已 exit=1 / 同样 7 FAIL（`/tmp/editor_split_baseline/user_asset_editor_before.log`，mtime 20:23）；21:41 复跑 7 条 FAIL 与该捕获逐条 IDENTICAL。⇒ 红先于 editor-split 一切改动。
  2. **文档基线为何记绿**：`docs/testing_baseline_2026-11-15.md` 生成于 04:36（`386508c`），彼时 map_editor.gd 只有 7 个 Tab（无预设 Tab）。契约断言 `tabs.get_tab_count() == 7`（tests/user_asset_editor_contract.gd:160）与旧 `_active_tool` 语义。
  3. **翻转点在午后功能轮**：04:36 基线后、20:08 editor-split 接手前，map_editor.gd 连续 16 个功能提交：`e61fd5f`(12:22) 新增第 8 个预设 Tab ⇒ "应有 7 个 Tab" 必红；`b213382/7af5201`（移动工具解耦+第 8 工具钮）、`925fe0c`（吸管前景/背景）、`9cc17c9`（真实材质预览）等重排 `_active_tool` 优先级（HEIGHT/REPLACE/PICK 前置 + 地形页 PLANT 路由）与素材通道语义 ⇒ 其余 6 条断言过期。
  4. **非环境漂移**：S3 段显式"换入隔离的 service/adapter"（契约 :147），无 8076 素材源 / `user://custom_assets` / 系统时间依赖；在纯净提交态即可稳定复现同主题失败。
- 处置建议：该契约属"测试滞后于功能"（与 map_editor_ui 6 条同理），归 P0-3/编辑器契约刷新批次统一整改断言，不属拆分回归；editor-split 拆分期间已按"红对照"基线管理，主题全程一致。

## 4. 工作区改动文件清单（git status --short）

```
 M main.gd                                  ← main-split（B1–B6 集成）
 M scripts/editor/region_clipboard.gd        ← editor-split
 M scripts/scenes/map_editor.gd              ← editor-split
?? docs/plans/                               ← main_split_plan.md + map_editor_split_plan.md + 本报告
?? scripts/editor/map_editor_block_palette.gd     ← editor-split
?? scripts/editor/map_editor_file_io.gd           ← editor-split
?? scripts/editor/map_editor_history.gd           ← editor-split
?? scripts/editor/map_editor_overlays.gd          ← editor-split
?? scripts/editor/map_editor_paint_ops.gd         ← editor-split
?? scripts/editor/map_editor_panel_tabs.gd        ← editor-split
?? scripts/world/animal_runtime.gd          ← main-split B6
?? scripts/world/ecology_config_validator.gd     ← main-split B1
?? scripts/world/ecosystem_match.gd         ← main-split B3
?? scripts/world/fauna_streamer.gd          ← main-split B5
?? scripts/world/flora_spawner.gd           ← main-split B4
?? scripts/world/minimap_renderer.gd        ← main-split B2
?? scripts/world/player_occlusion_controller.gd   ← main-split B2
?? scripts/world/presentation_stage.gd      ← main-split B3
?? scripts/world/species_picker.gd          ← main-split B4
?? scripts/world/terrain_texture_catalog.gd ← main-split B1
?? scripts/world/world_query_service.gd     ← main-split B4
```

按任务约束未执行任何 git commit / branch / reset；全部改动留工作区待审。

## 5. 终验结论

1. **main-split 拆分行为不变成立**：确定性 SHA-256 每批复验 + 终态一致；受影响契约 60+ 契约次全绿；全量 74 契约中 main-split 相关失败为零。
2. **无新增红（对照基线）**：6 项基线即红/环境限制项主题全部一致；唯一"绿→红"项 user_asset_editor 经 §3.3 收口：为当日午后编辑器功能轮的过期断言红，与两个拆分工序均无关。
3. main.gd 4319→2283（-47.1%），超额完成验收线；模块化目标达成（12 模块、无反向依赖、薄委托兼容契约直访面）。
