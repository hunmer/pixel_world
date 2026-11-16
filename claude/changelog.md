# 索引变更记录

> 本文件记录 `CLAUDE.md` 索引本身的生成 / 更新，**不是产品 Changelog**。仅保留最近 5 条（倒序）。

## 2026-11-16（深夜收尾轮：report.md 违例清零）

- `main.gd` `_unhandled_input` 键位路由表化：主体 24 行守卫链嵌套=1 + `_key_route`/`_entry_key_route` 双路由表（physical 优先、keycode 兜底），2174→2280 行；terrain SHA 不变，6 契约验证。
- `game_hud.gd` 拆面板：359→178 行装配层，战场/设置面板拆至 `scripts/hud/`（battlefield_panel 134 + settings_panel 94），对外信号/方法名不变（main.gd 零改动）；game_hud/ui/hint_bar 契约全绿。
- feature_map：+2 文件、3 处行数/角色刷新，321/321=100%。
- 同步：module-responsibilities（main.gd 函数行号）、file-map（scripts 166、hud/ 段）、CLAUDE.md、ui_contract 头注释勘误。
- report.md 清理：已处理项移除（保留开放观察项与可复用资产清单），UIFactory 引用数刷新为实测 23 文件。
## 2026-11-16（深夜） — report.md 违例并行优化轮（dsh team / glm-5.3 max ×4）

- **触发**：用户指令「使用 dsh team 创建 team，用 glm 5.3 max 针对 report 的报告并行做优化」；4 成员（battle / ecology / terrain-render / editor-ui）文件域互斥并行行为等价重构，Lead 统一验收。
- **代码变化**（净 −1816 行，全 `RefCounted`+注入、嵌套≤3、`## file.gd — 职责` 头注释）：
  - **battle**：battle_ui.gd 1211→**467** 装配层 + 拆出 battle_ui_hud(347)/unit_menu(418)/unit_detail(160)/banner(37)；battle.gd `_ready` 拆 7 个 `_configure_*`、`_unhandled_input` 键位路由表化（1444→1557，+注释）。
  - **ecology**：ecology_registry.gd 1150→**984**（legacy 外迁 `ecology_legacy_codec.gd` 240 行，报错文案逐字保留）；main.gd `_compile_ecosystem_config` 185→71 薄委托，编译入 `scripts/world/ecology_config_compiler.gd`（313）；main.gd 2283→**2174**。
  - **terrain-render**：terrain_material_registry.gd 1047→**472**（解析入 `terrain_material_parser.gd` 809）；isometric_column_batch.gd 1323→**742**（按绘制通道拆 scripts/iso/ texture_batch(148)/terrain_draw(377)/shoreline(341)，RNG hash 逐字迁移）。
  - **editor-ui**：map_editor / map_editor_overlays / block_selector 三处 PixelButton 直建改 `UIFactory.button()`（第 4 参 `styled=false` 留 bare 观感）；`tests/ui_contract.gd` 反转为禁直预加载 + 断言工厂用法。
- **验收**：全量 80 契约 **70 pass / 5 known-fail / 5 env-skip，0 新增红**；terrain_generation SHA-256 逐字节一致（`0c3f713b…` samples=16641）；`user_asset_editor` 经 worktree 在改动前 HEAD 复现同 7 失败 → 判定**既有红**（预设 Tab 落地后契约未跟上），manifest 登记 known-fail，Tab 数断言修正 7→8 后余 6 条待核对（断言陈旧 vs 预设功能回归，见 manifest evidence）。
- **文档**：report.md 覆盖更新（违例标注 ✅/仍开放：main.gd `_unhandled_input`≥4、game_hud 多面板）；file-map（scripts 154→164）、CLAUDE.md（行数/口径 70/5/5/mermaid）、feature_map 收编 10 新文件 + 刷新 7 处行数（scan 新增/消失=0、check 全过、html 已重渲）；changelog 本条。
- **坑（成员实测）**：GDScript 4.7 调用点不支持命名参数；untyped 宿主上 `:=` 推断会 Parse Error；`run_contracts.py` 并行期必须显式 `--out`。

## 2026-11-16 — 增量更新（三单体拆分 + 测试自动化 + 代码自检 report.md + 图谱刷新）

- **触发**：/init-project 增量更新（上次 2026-11-15 二轮，HEAD=3ba4cf5 → 本轮 dc0b9eb）；用户新增自检项，随后扩展为四组规则并落到 **`claude/report.md`**（init-project skill 已同步加「代码自检」硬性交付物节）。
- **重大变化**：
  - **三单体拆分落地**（docs/plans/split_report_2026-11-15.md，SHA-256 零漂移）：main.gd 4319→2283 行/176→128 函数（+11 模块入 scripts/world/，全 RefCounted/静态 + Callable 注入，`_configure_generation_services()@594` 装配）；map_editor.gd 3285→1031 行（+15 个 map_editor_* 模块入 scripts/editor/）；battle.gd 1934→1444 行（+6 模块入 scripts/battle/：camera_kick/fx/pref_panel/result_stage/save/sfx）。
  - **测试自动化**：`tools/run_contracts.py` 统一契约 runner（manifest 80 契约+2 探针，pass 71/known-fail 4/env-skip 5，自带 27 单测）；`tools/run_simulations.gd`+`simulation_batch.gd` 批量模拟（1000 局 3.6s）；`tests/gdtest/` 试点 3 文件 8 test；`tests/benches/ecology_logic_bench.gd`；手册 `docs/test_automation.md`。
  - **vendored 4→6**：+`addons/gdtest`（Rust CLI 运行时侧）、+`addons/godot_autosim`（adapter+bot+runner+report 模拟框架）。
  - **规模**：scripts/ 122→154 .gd（world 12→23 / editor 11→26 / battle 10→16）、tests 80→86 .gd、addons 4→6。
- **自检交付物 `claude/report.md`**（四组，替代同日早先的 reusability.md——内容已并入 §4）：§1 结构与职责（⚠ isometric_column_batch 1323 / battle_ui 1211 / ecology_registry 1150 / terrain_material_registry 1047 / _compile_ecosystem_config 185 行等违例表）；§2 重复（⚠ ecology legacy 双轨、PixelButton 直用 2 处）；§3 可读性（⚠ _validate_legacy_rules 嵌套≥7、battle._unhandled_input ≥6 等实测清单）；§4 可复用资产 A–F（UI 三层链 17 业务文件 / 共享内核 6 件 / world 11 模块 14 测试直 preload / 编辑器组件 / 测试基础设施 / autoload 8 个）+ 复用守则 6 条。
- **更新文件**：`claude/` overview / module-responsibilities / public-interfaces / dependencies-and-config / file-map / faq / report（新建，合并并取代 reusability.md〔已删〕）/ entrypoints（行号勘误：_ready@549、battle.gd 1444）/ changelog + 根 `CLAUDE.md`；conventions 与 testing-and-quality 已由前次会话更新，本轮复核未动；data-model 抽查无陈旧引用，未改。
- **图谱**：`docs/feature_map.json` 收编 27 个新增文件、修正 3 处过期 desc、vendored 补录 gdtest/godot_autosim（4→6）；`feature_map.py all` 复核 **311/311 = 100% 覆盖**，check 全过，html 已重渲（~564KB）。
- **缺口 / 下一步建议**：① entrypoints.md / data-model.md 本轮仅抽查（无陈旧行号命中，未全文重写）；② `AGENTS.md` 仍写「世界引擎集中在 main.gd / 78 契约」属用户指令文件未动；③ known-fail 4 契约（ui / map_editor_ui 等）修复仍在 roadmap P0。

## 2026-11-15（二轮） — 增量更新（胜利/增援/交换 + 编辑器区域操作 + DESIGN.md/22 组件 + 全量基线）

- **触发**：/init-project 增量更新；上次扫描提交 386508c 之后 ~25 commits（HEAD=3ba4cf5），外加补记 4 张上次未入账的前置卡（game_hud 修复 e8fda38、trade 2a501c7、victory 2ec8acb、素材源 3a08327）。
- **重大变化**：
  - **玩法框架三件套**：胜利条件 `victory{type:rout|defend_turns|seize}`（turn_manager.gd check_victory）+ 按回合波次增援 `reinforcements`（core/reinforcement_spawner.gd spawn_due/pending_units，敌方回合开始刷入、已消费波次移除防重刷）+ 相邻单位物品交换（systems/trade_system.gd）；JSON schema 均为可选字段、loader 静态严校验；样例战场 +ambush_reinforce/last_stand（共 6）。
  - **世界→战场地形映射 3→7 种**：cell_context_to_terrain 现覆盖 water/mountain/snow/sand/rocky/grass/plain（契约 world_terrain_mapping 22 checks）；forest/village/fort/wall 仍不映射（roadmap）。
  - **编辑器区域操作波**（scripts/editor/ 6→11 .gd）：区域复制/剪切/粘贴/拖动移动/方向键 nudge（region_clipboard 五层 payload）+ 命名预设库（region_preset_store，user://editor_presets/presets.json，tmp+bak 原子写）+ 取色器（Alt 临时+前后景色）+ replace 工具 + 真实材质预览 + 方块选择弹窗（4 列画廊）+ 快捷键提示弹窗；map_editor.gd 膨胀到 3285 行/150 函数。
  - **DESIGN.md + UI 组件库成型**：根 DESIGN.md（201 行）成为 UI 设计规范单一事实来源（SPACE/CORNER/FONT/MARGIN token + 六薄容器 + 按钮六态 + 三档分辨率验收）；ui/ 16→22 组件（+6 布局容器），ui_components 契约 735→1062 checks；ui_contract 新增静态扫描：业务脚本禁直建 Button/CheckButton/OptionButton.new()。
  - **全量测试基线落地**：docs/testing_baseline_2026-11-15.md（62/72 过：6 败 4 超时），tools/run_contract_baseline.sh 单测超时 900s；本轮新增 6 契约全过、复跑 6 受影响契约 4 过 2 红（ui/map_editor_ui 待修）。
  - **素材源可配置**：user_asset_service 三档优先级（asset_source.cfg override > 库内 settings > DEFAULT 127.0.0.1:8076）+ 优雅降级。
  - **规模**：scripts/ 113→122 .gd（core 14/systems 12/editor 11）、tests 71→80 .gd（78 契约+2 探针）、ui/ 23 .gd。
- **更新文件**：`claude/` 全部 11 个文件（overview / module-responsibilities / public-interfaces / data-model / testing-and-quality / file-map / faq / conventions / entrypoints / changelog）+ 根 `CLAUDE.md` + `docs/roadmap.md` 状态标记。
- **覆盖率**：main.gd 函数级复核（4319/176 不变）、map_editor.gd 3285/150、scripts/ 122 .gd 文件级、tests 78 契约归类 + 运行态实测（新 6 + 复跑 6）、config/data 逐文件。二进制素材仅统计。
- **缺口 / 下一步建议**：① 契约回归红：`ui`（map_editor.gd 三处直建控件）、`map_editor_ui`（侧栏 320px/z 重建断言）→ 已进 roadmap 新 P0；② 基线余项：battle_action_chain/battle_presentation_hooks/isometric_view/sunlight_3d_gl 4 败未复跑 + 4 超时（3 个 autoload 依赖型 + user_asset_source_live）；③ map_editor.gd 单体膨胀（+~900 行）逼近 main.gd，拆分前兆；④ data/battlefields/contract_asset_map.json.bak 脏文件待清。

## 2026-11-15 — 增量更新（会话路由/存档 + 演出/自动化 + 用户素材 + UI 组件库 + macOS 迁移）

- **触发**：/init-project 增量更新；距上次扫描（2026-11-12）三个密集日演进，且项目从 Windows（E:/）迁至 macOS（/Users/Zhuanz/Documents/pixel_world）。
- **重大变化**：
  - **主入口变更**：`run/main_scene = res://scenes/Game.tscn`（战旗会话入口：冷启动自动续玩最近战旗）；`GameSession` 战旗会话路由 + `--battlefield` / `--reset-battle` 命令行；战旗逐战场存档（`core/battle_save_codec/store` → `user://battle_saves/`，tmp+bak 原子写）。
  - **沉浸演出层**：`battle/battle_presentation / turn_director / action_anim / result_presentation / immersive_camera / encounter_transition` + `battle_settings_tab` 沉浸开关 + 可快进（`*_finished(skipped)` 信号）；shared 结算内核 `battle/battle_action_resolver.gd`。
  - **战斗自动化**：`battle/automation/`（scenario_loader/runner/report）+ `tools/battle_cli.gd` 无头 CLI（events.jsonl/result.json/summary.txt，退出码 0–4）；手册 `docs/battle_automation.md`。
  - **UI 组件库**：`ui/` 16 个 Pixel* @tool 组件 + `component_theme.gd` + 304 行 README + 画廊 `scenes/UIComponentGallery.tscn`（F6）+ `tests/ui_contract.gd`（735 checks）；业务 UI 未迁移（roadmap）。
  - **用户素材系统**：`scripts/assets/`（user_asset_service 32KB / catalog / visual_adapter）+ HTTP 清单源（127.0.0.1:8076/blocks.json）+ 编辑器 `asset_library_panel` + `tools/build_blocks_manifest.mjs`（node:test 7 项）；落盘 `user://custom_assets/`。
  - **表现层 autoload 4→8**：+`GameCursor` / `Sfx`（全局音效池+按钮声自动挂接）/ `LoadingScreen`（幂等遮罩）；`shaders/` 自有 6 个（+encounter_warp）。
  - **调试启动配置**：`config/startup.cfg` + `scenes/startup_config.gd`（F5 直跳 last_scene；`--battlefield` 优先）；手册 `docs/startup_config.md`。
  - **对话演示**：`scenes/DialogueDemo.tscn` + `data/dialogue/demo_intro.json`（未接正式流程）。
  - **规模**：main.gd 4099→4319 行/176 函数；scripts/ 75→113 .gd；tests 37→71 个 .gd（69 契约+2 探针）；scenes 5→11 tscn；addons +pixelfx v0.3.0；新增 `ui/`、`docs/`、`tools/`、`plans/` 目录；根 HANDOFF.md 删除、handoff/ 增至 3 篇；rules/ 减至 4 篇（image-viewing.md 已删，AGENTS.md 引用未清——roadmap）。
- **更新文件**：`claude/` 全部 10 个详情文件 + 根 `CLAUDE.md` 索引 + 新建 **`docs/roadmap.md`**（第二交付物：后续完善项按优先级/前置依赖排列）。
- **覆盖率**：`main.gd` 函数级（4319/176）、`scripts/` 113 .gd 文件级、tests 69 契约归类、config/data 逐文件、16 自有 tscn、新子系统（automation/assets/ui）API 级 grep 验证。二进制素材仅统计。
- **缺口 / 下一步建议**：① macOS 上 69 契约 headless 基线未跑全（game_hud 据旧记录坏，未复验）；② 用户素材源绑死 127.0.0.1:8076（本机需重建）；③ `game_hud_contract.gd` 修复、`cell_context_to_terrain` 11 地形覆盖复核、双轨配置迁移收尾等 —— 全部进 `docs/roadmap.md` 分优先级跟踪。

