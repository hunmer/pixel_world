# 代码自检报告（2026-11-17，HEAD d754fd5）

> /init-project 自检项：四组规则（结构与职责 / 重复 / 可读性 / 可复用性）统一收在本报告。证据口径：行数与嵌套为脚本实测（`wc -l` + 缩进层级扫描），复用为全仓 grep 实际引用，非设计宣称。已处理项从报告移除（历史见 git 与 changelog），只保留当前仍成立的事实与开放项。

## 1. 结构与职责

**✓ 好惯例**
- **三单体为"装配层 + 能力模块"形态**：main.gd 4319→2280 行（装配层，`_configure_generation_services()` 统一装配）、map_editor.gd 3285→1028 + `scripts/editor/` 26 模块、battle.gd 1934→1557 + `scripts/battle/` 20 模块；新模块全 `RefCounted`/静态 + Callable 注入、无反向依赖。
- **战斗 UI 为装配层 + 四模块**：battle_ui.gd 467 行 + `battle_ui_hud`(347) / `battle_ui_unit_menu`(418) / `battle_ui_unit_detail`(160) / `battle_ui_banner`(37)，对外方法名/信号/测试直戳成员零变化。
- **生态配置编译独立**：`scripts/world/ecology_config_compiler.gd`（313 行纯静态，typed 数组返回），main.gd 只留 71 行薄委托。
- **legacy 生态轨收敛单文件**：`scripts/ecology/ecology_legacy_codec.gd`（240 行，报错文案逐字保留）；world version 迁移后整文件可删。
- **材质与柱体绘制分层**：terrain_material_registry.gd 472 装配层 + `terrain_material_parser.gd`（809 行 static helper + 回调注入）；isometric_column_batch.gd 742 + `scripts/iso/` 绘制三模块（texture_batch / terrain_draw / shoreline）。
- **世界 HUD 装配层**：game_hud.gd 178 行，战场面板与设置面板在 `scripts/hud/`（battlefield_panel 134 / settings_panel 94）。
- **战棋业务与 UI 分离彻底**：`scripts/core/` 纯逻辑零渲染依赖；结算内核（battle_action_resolver）与演出层分离，改规则不动 UI。
- 全仓 `.gd` 头部职责注释约定（`## file.gd — 职责`）覆盖率高，feature_map 的 role 抽取即依赖它。

**⚠ 违例（按影响排序，附建议）**
| 文件 / 函数 | 实测 | 问题 | 建议 |
| --- | --- | --- | --- |
| `scripts/editor/asset_library_panel.gd` 919 行 / `editor_canvas.gd` 908 行 | 编辑器面板偏大 | 尚可接受，继续观察 | 暂不动 |
| `scripts/ecology/ecology_registry.gd` 984 行 | 拆后仍近千行（manifest 主轨+校验） | world version 迁移后 legacy codec 可整体删除 | 观察即可 |

## 2. 重复

**✓ 已提取的公共件**：UI 工厂（**23 个业务文件**实测引用）、结算内核三方共享、`simulation_batch.gd` 三方共用、`region_clipboard`→preset/replace/clipboard 复用链、`battlefield_doc` 被 6 编辑器模块共用（明细见 §4）。PixelButton 直建已清零（`tests/ui_contract.gd` 静态守护禁直预加载）。

**⚠ 重复点**
| 位置 | 实测 | 建议 |
| --- | --- | --- |
| B1/B2 双战斗链路 + `world_to_chapter`/`battlefield_loader` 平行入口 | 设计性平行（"新增不修改"原则），非事故重复 | 不合并；但**勿再开第三条入口** |

## 3. 可读性

**✓** 命名总体合格：函数动词开头、snake_case、`is_`/`has_` 布尔前缀常见；配合头部职责注释，定位成本低。

**⚠ 嵌套超 3 层**：当前无（全仓控制流实测 ≤3；新增代码守 ≤3）。

**长函数残余**：`terrain_material_parser.gd` 内 `_canonicalize_definition` 等解析函数仍长（177 行级），但已独占一文件、职责单一，嵌套≤3——可接受，暂不强制再拆。

## 4. 可复用资产（组件与函数）

### A. UI 复用链（三层，新界面必须从这进）

| 层 | 位置 | 复用证据 |
| --- | --- | --- |
| **组件层** | `ui/components/` 22 个 `Pixel*` @tool 控件（1356 行）+ 六薄布局容器 | 画廊 `scenes/UIComponentGallery.tscn`（F6）+ `tests/ui_components_contract.gd`（1062 checks） |
| **token 层** | `ui/theme/component_theme.gd`（DESIGN.md token 唯一实现）+ `scripts/ui/ui_theme.gd` | 所有 Pixel 组件内部消费；业务禁裸数字样式值 |
| **工厂层** | `scripts/ui/ui_factory.gd`（全静态，"怎么造"唯一权威；`button()` 第 4 参 `styled=false` 为编辑器 bare 变体留口） | **23 个业务文件调用**（grep 实测）：battle 8（battle_ui / battle_ui_hud / battle_ui_unit_menu / battle_ui_unit_detail / battle_fx / battle_pref_panel / battle_settings_tab / result_presentation）、editor 4（map_editor_overlays / map_editor_panel_tabs / asset_library_panel / block_selector）、hud 3（game_hud + scripts/hud/ 拆出 2 件）、scenes 7（title / home_entry / game_entry / dialogue_demo / map_editor / 两个 gallery）、side_panel |

复用规则：业务代码 → `UIFactory.button/...` → Pixel 组件（返回基类类型，调用方零改动）；`tests/ui_contract.gd` 静态扫描禁直建 `Button/CheckButton/OptionButton.new()` 且禁直预加载 `pixel_button.gd`；组件音效统一走全局 `Sfx`。

### B. 共享结算 / 规则内核（改规则只改这里）

| 内核 | 复用方（实测引用） |
| --- | --- |
| `scripts/battle/battle_action_resolver.gd` | **三方共享**：battle.gd（演出局）+ automation/battle_runner.gd（无头）+ tests/battle_automation_contract.gd —— 自动化断言与真机同一套规则 |
| `scripts/systems/turn_manager.gd` | **6 使用方**：battle_ui / battle_save / battle_runner / turn_director / battle.gd / reinforcement_spawner（`check_victory` 注入式） |
| `scripts/core/reinforcement_spawner.gd` | 演出（battle.gd 补 sprite+快照）与无头（runner 同点位发事件）双链路 |
| `world_to_chapter.gd` + `battlefield_loader.gd` | 同构 chapter 双入口，下游 11 文件（main / automation / editor / core / debug_console / game_hud…） |
| `battle_save_codec.gd` + `battle_save_store.gd` + `scripts/battle/battle_save.gd` | 战旗逐战场存档三层（编解码/原子落盘/行动边界快照） |
| `tools/simulation_batch.gd` | **三方共用核心**（RefCounted 即为此设计）：CLI + autosim adapter + tests/simulation_contract.gd |

### C. 可复用世界/生态模块（`scripts/world/` 25 件 + `scripts/ecology/` codec）

设计即复用：全 `RefCounted`/静态、Callable 注入、无反向依赖——任何场景/工具/测试可直接实例化。

| 模块 | 复用形态 |
| --- | --- |
| `ecology_config_validator.gd`（424 行） | **纯函数集**，零状态零依赖 |
| `ecology_config_compiler.gd`（313 行） | **纯静态编译器**：`compile_generation()`/`compile_ecosystems()` 返回 `{"ok","error","values"}`，typed 数组，可独立单测 |
| `terrain_material_parser.gd`（809 行） | 解析/规范化 static helper 集，`reporter`/`texture_loader` 回调注入，可脱离场景测试 |
| `species_picker.gd`（43 行） | **static 模块**，直调 |
| `ecosystem_match.gd` / `world_query_service.gd` / `terrain_texture_catalog.gd` | 纯逻辑/查询/目录，无节点依赖 |
| `flora_spawner` / `fauna_streamer` / `animal_runtime` / `minimap_renderer` / `player_occlusion_controller` / `presentation_stage` | RefCounted 服务，main.gd 装配 |
| `scripts/ecology/ecology_legacy_codec.gd`（240 行） | legacy 包解码/校验纯函数 + host 注入，迁移完成后整体可删 |

纯逻辑可脱离场景测试：14+ 个测试文件直接 `preload("res://scripts/world/...")`（含 gdtest 试点 2 件）；main.gd 内同名薄委托仅为测试兼容，复用优先直接用模块。

### C2. 战斗 UI 模块（`scripts/battle/` 4 件）

`battle_ui_hud` / `battle_ui_unit_menu` / `battle_ui_unit_detail` / `battle_ui_banner`——全 RefCounted + `setup()` 注入宿主，battle_ui.gd 只做装配；换皮/做新战斗界面时可直接复用整套菜单与详情面板。

### C3. 绘制模块（`scripts/iso/` 3 件）

`isometric_column_texture_batch`（UV 常量+投影批次）/ `isometric_column_terrain_draw`（普通柱/贴图/投影网格）/ `isometric_column_shoreline`（岸线泡沫+水波纹，确定性 RNG）——绘制通道分离，新增 biome 特殊绘制时挂新模块即可，勿回填主文件。

### D. 编辑器复用组件（`scripts/editor/` 26 .gd）

| 组件 | 复用证据 |
| --- | --- |
| `battlefield_doc.gd` | 文档模型被 cell_tools / region_select / replace / region_clipboard / file_io / model_ops 共用 |
| `region_clipboard.gd`（五层数据内核） | 被 region_preset_store / map_editor_replace / map_editor_clipboard 复用 |
| `map_editor_model_ops.gd` | 模型写操作原语，被替换/预设/剪贴板等操作类复用 |
| `block_selector` / `editor_block_list` / `editor_block_picker_dialog` / `shortcut_hints_dialog` | 独立弹窗/列表组件，可挂任意编辑器面板 |
| `map_editor_*` 15 个拆分模块 | 与主文件解耦（preload 注入），可单独测试重组 |

### E. 模拟与测试基础设施（跨项目可移植）

| 资产 | 说明 |
| --- | --- |
| `addons/gdtest/`（vendored） | gdtest Rust CLI 运行时侧：worker + `Gdt` 断言/mock/快照 helper + gdUnit4 兼容层；试点 `tests/gdtest/`（3 文件 8 test） |
| `addons/godot_autosim/`（vendored） | 通用对局模拟/平衡框架（adapter+bot+runner+report）；接入件 `tools/autosim_battle_adapter.gd` + `autosim_first_action_bot.gd` |
| `tools/run_contracts.py`（仅标准库） | 统一契约 runner（manifest 80 契约+2 探针）；自带 27 单测 |
| `tests/contract_manifest.json` + `tests/fixtures/simulations/*.json` | 用例元数据 + 批量模拟夹具 |

### F. 全局服务（autoload，天然全场景复用）

`Sfx`（音效池 + 按钮声自动挂接）、`LoadingScreen`（幂等遮罩）、`GameCursor`、`GameSession`、`Settings`、`Panku` 等 8 个——直接用，勿重建平行机制。

## 复用守则（新增开发从哪进）

1. **新 UI**：`UIFactory.*` / Pixel 组件 + ComponentTheme token；禁直建控件与裸样式（契约会抓）。
2. **新世界能力**：写成 `scripts/world/` RefCounted 模块再由装配层挂接，不往 main.gd 加逻辑。
3. **战斗规则改动**：只落 `battle_action_resolver.gd` / `turn_manager.gd`，勿在演出层复写结算。
4. **批量验证/平衡调参**：`tools/simulation_batch.gd` + autosim adapter + `run_simulations.gd`，勿手写循环。
5. **跑测试**：`python3 tools/run_contracts.py --changed`（影响闭包），勿逐个手跑。
6. **纯逻辑模块**（validator/picker/match/query/compiler/parser）可在任何工具/测试直接实例化，无需场景树。
