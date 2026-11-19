# 索引变更记录

> 本文件记录 `CLAUDE.md` 索引本身的生成 / 更新，**不是产品 Changelog**。仅保留最近 5 条（倒序）。

## 2026-11-19（第五轮增量：装备系统 + 免费角色包/移动测试 + 沉浸舞台，110 契约基线）

- **触发**：`/init-project` 增量扫描。自 11-18 基线（e7ed380）以来 253 文件 +11770/−1275，四大主题：①装备系统（四槽 + campaign 装备屏）②免费角色包与职业切片工具 ③人物移动测试场景 ④ImmersiveStage 沉浸舞台 + 物品/装备图标两目录。
- **代码事实**：`core/equipment.gd`(456, EquipmentDataScript 全静态单一权威) + `data/equipment.json`(11 条) + `campaign_equipment.gd`(397 弹层)；`scripts/characters/`（FreeCharacterSheet 169 + Animator 124，20 角色 002..021）+ `tools/slice_profession_sheets.py`(+test)；`scenes/CharacterMovementTest.tscn`（extends main.gd 测试台 + terrain_3d/fauna_streamer 两个子类）；`battle/immersive_stage.gd`(528)+`layout`(208)+`ImmersiveStage.tscn`（SubViewport own_world_3d，battle.gd 2186→2273 接线，`Settings.battle_immersive_presentation` 开关）；图标 `item_icons`(01..08)/`equipment_icons`(01..11) 沿用 skill_icons 模式；campaign_session 973→1044（equip_item@512/unequip_item@540）。
- **feature_map**：新增顶级类 **characters 🧍**（pack + movement）；battle.present/battle.data/battle.icons/campaign.hub/campaign.session/debug.pipeline 扩容；**收录 447/447 = 100%**（`feature_map.py all` check 全过，HTML 582305 字节）。
- **测试口径**：manifest **103→110 项**（+equipment/equipment_integration/equipment_icons/item_icons/free_character_sheet/immersive_stage/character_movement_test，全过）；**macOS 全量基线 pass 105 / fail 0 / env-skip 5 / timeout 0**（Godot 4.7.1，HEAD e3df43b，`.tmp/init_baseline_2026-11-19/`）。**发现：盘上 119 个契约中 8 个未录 manifest**（清单见 faq.md Q34，runner 每次告警；campaign_battle_integration 在 probes 区属误报）。
- **report.md 重写**：装备单一权威零复写（8 文件消费）、新代码无 ≥100 行函数（最长 present 60）；观察项 battle.gd 2273/122 函数（连续两轮 +100 行级）、campaign_session 1044/_settle_win 93 建议抽 campaign_settlement；复用计数刷新（ui_factory 40、resolver 10、BuildingLayout 9、EquipmentDataScript 8、FreeCharacterSheet 5）。
- **文档更新 12 件**：file-map / testing-and-quality / report / data-model / public-interfaces / dependencies-and-config / entrypoints / module-responsibilities / overview / faq(+Q30-Q34) / conventions / CLAUDE.md；feature_map.json+.html。
- **环境事实**：`config/startup.cfg` last_scene=CharacterMovementTest.tscn；`handoff/immersive-battle-presentation.md` 已重写为舞台权威交接；`docs/roadmap.md` 11-19 清理版（P0-1/3、P1-3/4 前半、P3-13 第一波归档）。

## 2026-11-18（第四轮增量：冒险模式 + 建筑子系统入册，103 契约基线）

- **触发**：自上轮（11-17）起 36+ commits / 302 文件变更，最大两项=冒险模式子系统落地（主入口改 `Campaign.tscn`、autoload 8→9）与建筑/室内子系统。
- **后续补记（11-19）**：`docs/roadmap.md` 按本轮事实清理——P0-1/P0-3、P1-3（收口 103 项 pass 98/fail 0/env-skip 5）、P1-4 前半（3→7）、P1-6 大半、P2-10 战役结构、P3-13 第一波拆分**归档**；P2-10 改写为"战役扩容 6→15 章"、P3-13 改写为"装配层持续治理（battle.gd 2186 / campaign_session 973）"、P3-15 收敛为剩余 battle_ui/HUD 迁移面；新增暂不立项项（campaign 是否加 B1 变体）。

- **触发**：`/init-project` 增量扫描。自 2026-11-17 起 36+ commits（302 文件变更）：冒险模式（campaign 六件 + 七屏 + bridge + data）、建筑/室内子系统、背击/夹击规则、行动历史【记录】Tab、升级演出、九键成长、技能/状态图标、图鉴 SkillList、UI 组件 22→27、ui_gallery 六模块拆分、编辑器建筑摆放/角色编辑。
- **主入口变更**：`project.godot` main_scene → `res://scenes/Campaign.tscn`；autoload 8→9（第 3 位 CampaignSession）。全部文档口径同步（Game.tscn 降为开发入口）。
- **feature_map**：新增顶级类 campaign 🏕️（4 子节点）+ buildings 🏰（4 子节点）+ battle.icons + editor.units + ui.components +5 + ui.gallery +6 + assets.tooling +4；**收录 421/421 = 100%**（unmapped 18 条 = .tmp/ 等；`feature_map.py all` build/render/check 全过，HTML 578166 字节）。
- **测试口径**：manifest **103 项**（campaign 4 + 建筑 3 + 战斗规则/演出/图标约 15 新增）；**macOS 全量基线 pass 98 / fail 0 / env-skip 5 / timeout 0**（Godot 4.7.1，HEAD e7ed380，`.tmp/init_baseline_2026-11-18/`）。
- **report.md 重写**：四组自检实测——观察项 battle.gd 2186/116 函数（回涨）、campaign_session 973/38；复用计数刷新（ui_factory 38 文件、resolver 10 文件、BuildingLayout 10 文件）；新列 BattleThreatData/BattleActionHistory 为"可复用未消费"；复用守则 6 条。
- **文档更新 13 件**：overview/entrypoints/module-responsibilities/file-map 全文重写（新数据流 C=Campaign 主链、场景表 16 tscn、scripts 791 .gd 实测地图）；data-model（+冒险档案模型/facing/buildings 层/九键）、public-interfaces（+CampaignSession 接口表/建筑素材契约/图标 ID 契约/信号表）、dependencies-and-config（+campaign.json/shop.json/battlefields 8/buildings）、testing-and-quality（103 分类表+基线行）、conventions（+冒险磁盘安全约定+建筑/图标契约）、faq（+Q27-Q29）、CLAUDE.md。
- **环境事实**：本机 Godot 4.7.1（跨机 E:\pixel_world 同步开发）；docs/campaign_loop.md 与 docs/building_assets.md 为两新子系统权威文档。

## 2026-11-17（known-fail 清零轮：五项全部修复，基线 75/80 全绿）

- **触发**：用户指令「按照优先度和收益，继续派发给团队任务」；按 收益÷风险 排序选定修 5 个 known-fail（基线干净+可能藏真 bug）优先于纯结构拆分，4 成员文件域互斥并行，先定性再修、禁为绿而绿。
- **定性结论（全部实测取证）**：① `isometric_view`＝HUD 侧栏预留列（reserved 56/360px）把光轴平移到舞台中心，原契约"焦点=窗口中心"取样假设失效——探针实证投影/拾取数学无回归，契约改在 `unproject(焦点)` 实际渲染位取样并**新增**"焦点渲染在舞台中心 <0.25px"断言（强化）；② `battle_action_chain`＝飘字断言陈旧（pixelfx 接管后伤害=damage-number+health-bar-hit 两节点），helper 改 `_expected_float_node_count`；③ `battle_presentation_hooks`＝音效断言按素材优先设计改 either-or + 未映射 cue 探针守护程序化回退 + 密闭性修复（本机 `user://settings.cfg` 的 immersive 开关泄入 headless，`_pin/_restore` 固定），**附带修 `game_sfx.gd:84` Nil→Array 类型化赋值真 bug**；④ `map_editor_ui`＝6 项全部断言过时，按实现重锚（侧栏 ≥320 且=combined_minimum_size、单块 0..z 共 7 块、先关弹窗再断隐藏、历史断言前 `_seal_pending()`）；⑤ `user_asset_editor`＝`925fe0c` 吸管功能引入的**真行为回归**——`active_tool` PAINT 前置检查短路素材选中→`Tool.ASSET` 分支（植物素材完全无法放置）、`clear_asset_selection` 不回退前景槽；修复保留吸管特性。
- **验收**：全量 **pass 75 / fail 0 / env-skip 5**（80 契约），manifest 五条 `known_status` 摘除、evidence 记录依据；runner 27 单测绿（known-fail 夹具测试改为无夹具 skip）。
- **Lead 集成修复**：并行成员改同一 manifest 后写互踩（只剩 battle 两条幸存）——Lead 补齐另三条并验证；教训：共享 JSON 文件的并行编辑必须串行或由 Lead 统一收口。
- 同步：CLAUDE.md、docs/test_automation.md §4、claude/testing-and-quality.md（台账+风险节）、docs/roadmap.md（P0-3 ✅）。

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
