# 代码自检报告（2026-11-16 深夜优化轮后，HEAD dc0b9eb + 团队重构）

> /init-project 自检项：四组规则（结构与职责 / 重复 / 可读性 / 可复用性）统一收在本报告。证据口径：行数与嵌套为脚本实测（`wc -l` + 缩进层级扫描），复用为全仓 grep 实际引用，非设计宣称。
>
> **2026-11-16 深夜**：dsh team（4 成员 glm-5.3 max）针对本报告 §1–§3 违例做行为等价重构，全部落地且 0 新增红（全量 80 契约 70 pass / 5 known-fail / 5 env-skip；terrain_generation SHA-256 逐字节一致）。已修复项保留 ✅ 记录，未动项维持 ⚠。

## 1. 结构与职责

**✓ 好惯例**
- **三单体已拆成"装配层 + 能力模块"**（2026-11-16）：main.gd 4319→**2280** 行（装配层；输入路由表化 +106）、map_editor.gd 3285→1028、battle.gd 1934→1557（+拆分注释，目标是降嵌套非减行）；新模块全 `RefCounted`/静态 + Callable 注入、无反向依赖，装配点 `_configure_generation_services()`@main.gd。
- **战棋业务与 UI 分离彻底**：`scripts/core/` 纯逻辑零渲染依赖；结算内核（battle_action_resolver）与演出层分离，改规则不动 UI。
- **✅ 战斗 UI 多职责已拆**（本轮）：battle_ui.gd 1211→**467** 行装配层 + `battle_ui_hud`(347) / `battle_ui_unit_menu`(418) / `battle_ui_unit_detail`(160) / `battle_ui_banner`(37) 四模块，对外方法名/信号/测试直戳成员零变化。
- **✅ 生态双轨与巨型编译函数已拆**（本轮）：ecology_registry.gd 1150→**984**（legacy 整体外迁 `ecology_legacy_codec.gd` 240 行，报错文案逐字保留）；main.gd `_compile_ecosystem_config` 185→**71** 行薄委托，编译入 `scripts/world/ecology_config_compiler.gd`（313 行纯静态，typed 数组返回）。
- **✅ 材质注册与柱体绘制已拆**（本轮）：terrain_material_registry.gd 1047→**472** 装配层（解析/规范化入 `scripts/world/terrain_material_parser.gd` 809 行 static helper + 回调注入）；isometric_column_batch.gd 1323→**742**（按绘制通道拆 `scripts/iso/` texture_batch(148) / terrain_draw(377) / shoreline(341)，确定性 RNG hash 逐字迁移，常量别名保留、消费方零改动）。
- 全仓 `.gd` 头部职责注释约定（`## file.gd — 职责`）覆盖率高，feature_map 的 role 抽取即依赖它。

**⚠ 违例（按影响排序，附建议）**
| 文件 / 函数 | 实测 | 问题 | 建议 |
| --- | --- | --- | --- |
| `main.gd` | 2280 行 | 装配层性质但仍偏大：`_unhandled_input` 102 行（嵌套≥4）未路由化 | ✅ 已收口（深夜优化轮）：24 行守卫链嵌套=1 + `_key_route`/`_entry_key_route` 双路由表，terrain SHA 不变 |
| `scripts/game_hud.gd`（scripts 根） | HUD+战场面板+设置 | UI 容器多面板混合，且契约在 HEAD 上红 | 随 ui/map_editor_ui 修复一并拆面板 |
| `scripts/editor/asset_library_panel.gd` 919 行 / `editor_canvas.gd` 908 行 | 编辑器面板偏大 | 尚可接受，继续观察 | 暂不动 |
| `scripts/ecology/ecology_registry.gd` 984 行 | 拆后仍近千行（manifest 主轨+校验） | world version 迁移后 legacy codec 可整体删除 | 观察即可 |

## 2. 重复

**✓ 已提取的公共件**：UI 工厂（**18 个业务文件**，本轮 +block_selector）、结算内核三方共享、`simulation_batch.gd` 三方共用、`region_clipboard`→preset/replace/clipboard 复用链、`battlefield_doc` 被 6 编辑器模块共用（明细见 §4）。

**⚠ 重复点**
| 位置 | 实测 | 建议 |
| --- | --- | --- |
| B1/B2 双战斗链路 + `world_to_chapter`/`battlefield_loader` 平行入口 | 设计性平行（"新增不修改"原则），非事故重复 | 不合并；但**勿再开第三条入口** |

**✅ 已清零（本轮）**
- ~~ecology legacy 双轨~~：legacy 解析收敛到 `ecology_legacy_codec.gd` 单文件（`load_legacy` 只剩一行委托），world version 迁移后整文件可删。
- ~~PixelButton 直用绕过工厂~~：map_editor / map_editor_overlays / block_selector 三处全部改 `UIFactory.button()`（第 4 参 `styled=false` 保留编辑器 bare 观感）；`tests/ui_contract.gd` 反转为**禁直预加载** + 断言工厂用法，block_selector 纳入扫描循环。

## 3. 可读性

**✓** 命名总体合格：函数动词开头、snake_case、`is_`/`has_` 布尔前缀常见；配合头部职责注释，定位成本低。

**⚠ 嵌套超 3 层**
| 函数 | 最深嵌套 | 状态 |
| --- | --- | --- |
| `main.gd::_unhandled_input` | ≥4（102 行） | ✅ 已收口（深夜优化轮）：主体 24 行嵌套=1，双路由表保原 elif 语义，6 契约验证 |

**✅ 已清零（本轮，控制流实测 ≤3）**
- `ecology_registry::_validate_legacy_rules` ≥7 → codec 内拆 `_validate_rule_list`/`_validate_rule`/`_validate_fauna_substitution`。
- `battle.gd::_unhandled_input` ≥6 → `_key_route()` 键盘路由表 + `_handle_mouse_*` 分发 + 提前 return。
- `terrain_material_registry::load_materials`/`_parse_texture_spec` ≥6 → parser 模块独立函数。
- `isometric_column_batch::_draw_shoreline_frame`/`_draw` ≥5 → 按绘制通道拆三模块。
- `battle.gd::_ready` 153 行 → 7 个 `_configure_*`（执行顺序逐句一致，含 `start_player_phase` 先于 `battle_ready.emit` 的关键次序）。

**长函数残余**：`terrain_material_parser.gd` 内 `_canonicalize_definition` 等解析函数仍长（177 行级），但已独占一文件、职责单一，嵌套≤3——可接受，暂不强制再拆。

## 4. 可复用资产（组件与函数）

### A. UI 复用链（三层，新界面必须从这进）

| 层 | 位置 | 复用证据 |
| --- | --- | --- |
| **组件层** | `ui/components/` 22 个 `Pixel*` @tool 控件（1356 行）+ 六薄布局容器 | 画廊 `scenes/UIComponentGallery.tscn`（F6）+ `tests/ui_components_contract.gd`（1062 checks） |
| **token 层** | `ui/theme/component_theme.gd`（DESIGN.md token 唯一实现）+ `scripts/ui/ui_theme.gd` | 所有 Pixel 组件内部消费；业务禁裸数字样式值 |
| **工厂层** | `scripts/ui/ui_factory.gd`（全静态，"怎么造"唯一权威；`button()` 第 4 参 `styled=false` 为编辑器 bare 变体留口） | **18 个业务文件调用**：battle 8（battle_ui / battle_ui_hud / battle_ui_unit_menu / battle_ui_unit_detail / battle_fx / battle_pref_panel / battle_settings_tab / result_presentation）、editor 4（map_editor / map_editor_overlays / map_editor_panel_tabs / asset_library_panel / +block_selector）、scenes 7（title / home_entry / game_entry / dialogue_demo / map_editor / 两个 gallery）、game_hud / side_panel |

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

### C. 拆分出的可复用世界/生态模块（`scripts/world/` 25 件 + `scripts/ecology/` codec）

设计即复用：全 `RefCounted`/静态、Callable 注入、无反向依赖——任何场景/工具/测试可直接实例化。

| 模块 | 复用形态 |
| --- | --- |
| `ecology_config_validator.gd`（424 行） | **纯函数集**，零状态零依赖 |
| `ecology_config_compiler.gd`（313 行，本轮新增） | **纯静态编译器**：`compile_generation()`/`compile_ecosystems()` 返回 `{"ok","error","values"}`，typed 数组，可独立单测 |
| `terrain_material_parser.gd`（809 行，本轮新增） | 解析/规范化 static helper 集，`reporter`/`texture_loader` 回调注入，可脱离场景测试 |
| `species_picker.gd`（43 行） | **static 模块**，直调 |
| `ecosystem_match.gd` / `world_query_service.gd` / `terrain_texture_catalog.gd` | 纯逻辑/查询/目录，无节点依赖 |
| `flora_spawner` / `fauna_streamer` / `animal_runtime` / `minimap_renderer` / `player_occlusion_controller` / `presentation_stage` | RefCounted 服务，main.gd 装配 |
| `scripts/ecology/ecology_legacy_codec.gd`（240 行，本轮新增） | legacy 包解码/校验纯函数 + host 注入，迁移完成后整体可删 |

纯逻辑可脱离场景测试：14+ 个测试文件直接 `preload("res://scripts/world/...")`（含 gdtest 试点 2 件）；main.gd 内同名薄委托仅为测试兼容，复用优先直接用模块。

### C2. 拆分出的战斗 UI 模块（`scripts/battle/`，本轮新增 4 件）

`battle_ui_hud` / `battle_ui_unit_menu` / `battle_ui_unit_detail` / `battle_ui_banner`——全 RefCounted + `setup()` 注入宿主，battle_ui.gd 只做装配；换皮/做新战斗界面时可直接复用整套菜单与详情面板。

### C3. 拆分出的绘制模块（`scripts/iso/`，本轮新增 3 件）

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
