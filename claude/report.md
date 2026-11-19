# 代码自检报告（2026-11-19，HEAD e3df43b）

> 证据口径：行数 / 函数数 / 复用计数均为本轮 grep·wc 实测；不采信设计文档宣称。聚焦本轮四大新增（装备 / 免费角色包 / 人物移动测试 / ImmersiveStage）+ 既有观察项复核。

## 1. 结构与职责

- ✓ **新模块尺寸全部健康**：`scripts/core/equipment.gd`（456 行 / 全静态）、`scripts/battle/immersive_stage.gd`（528/30 函数）+ `immersive_stage_layout.gd`（208）、`scripts/characters/free_character_sheet.gd`（169）+ `free_character_animator.gd`（124）、`scripts/scenes/campaign_equipment.gd`（397）、`character_movement_test.gd`（532/47，extends main.gd 继承而非复制装配逻辑）——无一个上帝文件，全部延续"模块 + Callable 注入"契约。
- ✓ **装备系统单一权威**：装备数据/校验/加成/容量/归一**全部收敛在 `EquipmentDataScript` 静态接口**（catalog_for/can_equip/stat_bonus/capacity_hp/capacity_mp/normalize_unit_equipment），消费方（campaign_session、campaign_roster、buff_system、weapons、campaign_equipment 弹层）只调不写——grep 实测 8 文件消费、零处内联复写装备规则。
- ✓ **图标三目录同构**：`skill_icons` / `item_icons` / `equipment_icons` 三套目录同一模式（稳定 ID→显式路径映射 + 缓存 + DEFAULT_ICON_ID 应急兜底 + 未知 ID push_warning 不返回 null），各有独立契约。
- ⚠ **battle.gd 继续回涨**：2186→**2273 行 / 122 函数**（+ImmersiveStage 接线 137 行：preload 场景、4 个演出信号、`_use_immersive_stage()`、`await _immersive_stage.present()`）。接线本身符合"装配层"定位，但已连续两轮 +100 行级增长；**建议**：下一批增量前把【记录】Tab（@619,651 附近）与 campaign 结算接线拆入 `scripts/battle/` 模块。
- ⚠ **campaign_session.gd 973→1044 行 / 41 函数**（+equip_item@512 / unequip_item@540，装备接口本身薄、走 codec 落盘正确）；最长函数 `_settle_win` 93 行、`buy_item` 72 行、`prepare_battle` 62 行——settle 结算流程已可抽 `campaign_settlement.gd`（roadmap 已列）。
- ⚠ Top 行数榜（scripts+main.gd 共 63872 行）：main.gd 2280 / battle.gd 2273 / map_editor.gd 1088 / battlefield_renderer.gd 1058 / campaign_session.gd 1044——前两名为装配层属预期，后三名是下一步拆分候选。

## 2. 重复

- ✓ **装备规则零重复**：加成口径（`buff_system.gd`：加成=base+EquipmentData.stat_bonus，容量独立口径 base+装备不含 buff）、武器选择（`weapons.gd unit_weapon()`：装备槽优先、空装回退 unit.weapon）、容量补满（`campaign_roster` 走 capacity_hp/capacity_mp）——三处消费三种口径，各自一行委托，无复制粘贴。
- ✓ **免费角色包读取单点**：`FreeCharacterSheet`（class_name）统一帧表加载/帧解析，移动测试场景 + 动画器 + 契约测试 5 文件消费同一实现；素材归档 upstream_example/ 带 .gdignore 不参与导入。
- ✓ **图标目录三件套**是"复制一份再改一点"的**良性模板复用**（ID 空间与目录不同，模式必然同构）；后续再加目录沿用同模板即可。
- ⚠ 移动测试场景三件（terrain_3d 52 行 / fauna_streamer 168 行 / 主脚本 532 行）用**继承**扩展 main.gd 生态——是刻意复用真实世界的测试台，不算重复，但**勿把该模式扩散到正式玩法场景**（继承 main.gd 意味着吃进全部装配字段）。

## 3. 可读性

- ✓ 新代码命名直白（`unit_weapon` / `capacity_hp` / `normalize_unit_equipment` / `setup_stage`），顶部均有 `## file.gd — 职责` 注释。
- ✓ **本轮新增代码无 ≥100 行函数**：最长 immersive_stage.present 60 行、character_movement_test._setup_test_ui 37 行。
- ⚠ 既有长函数（未恶化、待拆）：battle.gd `_apply_history_snapshot` 74 / `_process` 72 / `_configure_action_modules` 72 / `_resolve_item` 56；campaign_session `_settle_win` 93 / `buy_item` 72。均 <100 行红线但 `_settle_win` 与 `_process` 多职责混合（结算+演出+落盘 / 输入+光标+刷新），下次触碰时顺手提取 helper。

## 4. 可复用资产

| 资产 | 位置 | 实测复用方（grep） | 备注 |
| --- | --- | --- | --- |
| `ui_factory` | scripts/ui/ui_factory.gd | **40 文件** | 老 UI 工厂，battle_ui/HUD 系 |
| `battle_action_resolver` | scripts/battle/battle_action_resolver.gd | **10 文件** | 结算内核（battle.gd/automation/契约） |
| `BuildingLayout` | scripts/core/building_layout.gd | **9 文件** | 建筑占用唯一校验 |
| `EquipmentDataScript`★ | scripts/core/equipment.gd | **8 文件** | 装备系统唯一权威（本轮新增即 8 消费） |
| `FreeCharacterSheet`★ | scripts/characters/free_character_sheet.gd | **5 文件** | 免费角色包帧表 |
| `equipment_icons`★ | scripts/core/equipment_icons.gd | 3 文件 | 装备图标目录 |
| `item_icons`★ | scripts/core/item_icons.gd | 2 文件 | 物品图标目录（items.gd + 契约） |
| `immersive_stage.gd` | scripts/battle/immersive_stage.gd | 1 文件（battle.gd 独占） | 沉浸舞台——按设计即单宿主 |

**按可复用设计但尚未被二次消费**：`character_movement_fauna_streamer.gd` / `character_movement_terrain_3d.gd`（继承扩展示范，可为将来"世界内新玩法场景"参考）；`slice_profession_sheets.py`（职业切片 CLI，story 扩容做职业精灵时会再用）。

## 复用守则（6 条）

1. **新 UI 必走组件工厂**：Pixel* 组件 + ComponentTheme（详见 DESIGN.md）；老代码区用 ui_factory。
2. **改战斗规则只改共享内核**：`battle_action_resolver.gd` + `scripts/systems/`，演出层勿复写结算。
3. **装备规则只改 `equipment.gd`**：加成/容量/归一/校验一律走 EquipmentDataScript 静态接口，勿在消费方内联复写。
4. **建筑占用/重叠校验只走 `BuildingLayout`**；图标 ID 三目录（skill/item/equipment）永不重排、未知 ID 走兜底。
5. **世界新内容走 biome 模块 + `config/ecology/`**，不往 main.gd 加分支；素材/内容 ID 勿当随机种子。
6. **装配层只留接线**：battle.gd / campaign_session / main.gd 新增能力先入 `scripts/` 模块再薄委托。
