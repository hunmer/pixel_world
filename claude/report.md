# 代码自检报告（2026-11-18，HEAD e7ed380）

> 证据口径：全部结论以本日实测为准 —— `wc -l` 行数、`grep -c '^func '` 函数数、grep 引用计数、缩进层级扫描；不采信设计文档宣称。对象为自有代码（scripts/ + main.gd + ui/ + scenes 脚本，不含 tests/ 与 addons/ vendored）。

## 1. 结构与职责

**✓ 好惯例**

- **三单体装配层形态保持**（2026-11-16 拆分后）：main.gd 2280 行 / map_editor.gd 1088 行 / battle.gd（装配部分）。能力模块 `scripts/world/` 20 件、`scripts/editor/` 28 件、`scripts/battle/` 26 件均为 RefCounted/静态 + Callable 注入、无反向依赖；主文件保留薄委托。
- **新增子系统沿用同法**：`scripts/campaign/` 6 件（session 973 / codec 435 / config 340 / store 329 / roster 297 / shop_catalog 106）+ `scripts/scenes/campaign_*.gd` 7 件（campaign_main.gd 仅 173 行装配层：装配 5 屏 + 转发 `changed` 信号，业务在 CampaignSession，渲染在屏脚本）——分层清晰，没有"上帝文件"形态。
- **battle_ui 四模块**（hud/unit_menu/unit_detail/banner）继续有效；**ui_gallery 六模块拆分**（basic_pages/battle_page/cursor_page/frame_pages/layout_page/widgets）复刻了同法。
- **战棋规则进 systems 不进演出**：背击 `facing_rules.gd`、夹击 `pincer_rules.gd` 是 systems 层纯逻辑，battle.gd / resolver 消费——结算与表现分离原则保持。
- **升级演出解耦**：`level_up_presentation.gd` 纯演出、`sound_requested` 信号不直连 Sfx。
- **建筑校验单点**：`BuildingLayout`（core 层）是编辑器保存与 loader 共用的占用/重叠唯一实现（grep 实测 10 文件消费），没有两份平行校验。
- 头部 `## file.gd — 职责` 注释约定延续到全部新文件（feature_map build 的 role 提取即靠它）。

**⚠ 违例/观察项**

| 项 | 证据 | 建议 |
| --- | --- | --- |
| battle.gd 回涨 | **2186 行 / 116 顶层 func**（2026-11-16 拆分后 1557；行动历史 Tab、campaign 接线、升级演出接线又内联进来） | 下一批增量前把【记录】Tab（@619,651 一带）与 campaign 结算接线拆出 `battle_history_panel` / 复用 bridge 薄委托，重走 2026-11-16 拆分法 |
| campaign_session.gd 偏重 | **973 行 / 38 func**，购买/结算/掉落/解锁/持久化全在 autoload | 把 `_settle_win`/`_victory_loot`/`_diff_level_ups` 一簇拆 `campaign_settlement.gd`（纯函数化），session 只留编排 |
| 大文件前八名 | main.gd 2280、battle.gd 2186、map_editor.gd 1088、battlefield_renderer.gd 1058、ecology_registry.gd 984、asset_library_panel.gd 983、campaign_session.gd 973、community_runtime.gd 943 | 均为已知装配层/注册表形态，超 P90 但职责单一；新功能勿再往里加 |
| 超长函数 | battle_scenario_loader.load_from_dict 165 行、world_audio_system.update_animal_sounds 152、campaign_hub._build 148、asset_library_panel._build_ui 141、map_editor_shortcuts.unhandled_input 128 | `_build*` 系列是声明式 UI 组装（惯例可接受）；`load_from_dict`/`update_animal_sounds` 建议按字段组拆 `_parse_*` helper |

## 2. 重复

**✓ 已提取的公共件**

- UI 工厂链：`ui_factory.gd` 被 **38 文件**消费（grep 实测，上轮 23）；ComponentTheme 同为 38。
- 共享结算内核：`battle_action_resolver.gd` 被 **10 文件**引用（battle.gd、battle_runner + backstab×2 / pincer×2 / battle_drop / campaign / battle_automation 等 8 契约）——演出、无头回放、契约测试三方同一套规则，背击/夹击/掉落判定没有第二实现。
- `BuildingLayout`：10 文件消费（loader / save_codec / grid_system / 编辑器 3 件 + 3 契约）。
- campaign 事务：`settle_battle`/`prepare_battle` 调用方 6 文件（bridge / session + 4 契约）。
- 增援 `reinforcement_spawner.gd` 演出/无头两链路共用（既有）。

**⚠ 重复点**

- B1/B2 平行入口（`_enter_battle` vs `_enter_battle_inline`）——历史设计性重复，B1 需世界现场恢复，合并收益低，保留但**勿再新增第三条入口**。
- `builtin_building_assets.gd` / `builtin_house_assets.gd`（87/75 行）两份内置素材表结构近似——素材继续增多时应合并为单一"内置建筑注册表 + recipe 路径表"，避免逐素材一个文件。

## 3. 可读性

**✓**：命名整体合格（`prepare_battle`/`settle_battle`/`growths_for`/`footprint_cells` 等自解释）；新文件延续中文头部职责注释；GDScript strict 类型标注保持。

**⚠**：

- 深嵌套（函数体内 ≥5 层控制流）实测清单：`ecology_config_validator.gd` 8 层（@42、@75）、`community_runtime.gd` 7 层（@816-819 legacy bundle 判定）、`building_occlusion_controller.gd` 6 层（@19-22，**新代码**）、`player_ai.gd` 6 层（@94-97）及 main.gd / world_to_chapter / community_spawner / editor_canvas / flora_spawner / world_audio_system / ecology_registry 各 6 层。建议：新代码嵌套 ≤3 层，validator/legacy 判定用提前 return + 条件提取。
- 长函数清单见 §1 违例表。

## 4. 可复用资产（grep 实测引用方）

| 资产 | 位置 | 实测复用方 |
| --- | --- | --- |
| UI 三层链（Pixel* 组件 27 + ComponentTheme + ui_factory/ui_theme） | `ui/` | campaign 七屏全量、map_editor 部分、ui_gallery；工厂链 38 文件 |
| 共享结算内核 | `scripts/battle/battle_action_resolver.gd` | battle.gd、battle_runner、8 个契约测试（10 文件） |
| 建筑占用校验 | `scripts/core/building_layout.gd` | loader / save_codec / grid_system / 编辑器 3 件 / 3 契约（10 文件） |
| campaign 事务 API | `scripts/campaign/campaign_session.gd` | campaign 屏 7 件、battle_bridge、4 契约 |
| 增援刷入 | `scripts/core/reinforcement_spawner.gd` | battle.gd（演出）+ battle_runner（无头） |
| 图标映射 | `scripts/core/skill_icons.gd` / `status_icons.gd` | skills.gd、skill_list.gd、unit_status_badges + 契约 |
| **可复用尚未消费**：`BattleThreatData`（`scripts/systems/battle_threat_data.gd`，只读范围/威胁预测）当前仅契约消费——写敌方 AI 预警/危险格叠加 UI 时优先用它，勿再写第四份范围计算 | | |
| **可复用尚未消费**：`BattleActionHistory`（跨回合快照回退内核）已支持整场累积回退——做"悔棋"或战报回放功能时直接消费，勿在 UI 层重造 | | |

### 复用守则

1. 新 UI 一律 Pixel* 组件 + ComponentTheme token（DESIGN.md），禁直建 `Button.new()` 等（`ui_contract` 静态扫描会 FAIL）。
2. 改战斗规则只改 `battle_action_resolver` + `scripts/systems/`，演出/UI 层不得复写结算。
3. 建筑占用/重叠校验只走 `BuildingLayout`；增援只走 `ReinforcementSpawner`。
4. 冒险模式结算只走 `CampaignSession.settle_battle`（幂等），掉落 RNG 用其独立种子接口。
5. 图标取用走 `skill_icons`/`status_icons` 稳定 ID 映射，勿直拼纹理路径。
6. 新能力先进 `scripts/<域>/` 模块再挂装配层；main.gd / battle.gd / map_editor.gd / campaign_session.gd 只留薄委托。
