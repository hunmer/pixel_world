# 架构总览

> 更新：2026-11-19（第五轮增量：**装备系统**（四槽+双口径）+ **免费角色包/移动测试场景** + **ImmersiveStage 沉浸舞台** + 物品/装备图标目录；契约 110 项）。上一轮：冒险模式 + 建筑室内子系统；主入口 `Campaign.tscn`。

## 一句话定位

Godot 4.7（GL Compatibility）/ Node2D 单体 2D 游戏：3D 正交（dimetric）视口下按固定种子**实时、确定性、流式**生成的"无限"像素生态世界，内嵌**回合制战棋战斗**，外围再包一层**冒险模式（营地/关卡/商店/掉落/成长）**作为默认玩家入口。世界、战棋、冒险三层的关系：冒险层消费战棋（出征→战斗→结算回营地），战棋可脱离冒险独立运行（开发用途），世界是就地战斗（B1）的地形来源。

## 运行时形态（默认一局）

```
scenes/Campaign.tscn（project.godot 主场景）
  ├─ 存档选择屏（user://campaign_saves/ 多档案）
  ├─ 营地 Hub：金币 / 公共库存 / 固定队伍（roster）/ 关卡进度
  ├─ 关卡列表（data/campaign.json 6 关，线性解锁）
  ├─ 营地商店（data/shop.json；金币购买，按通关数限购）
  ├─ 装备屏（campaign_equipment）★：四槽 weapon/shield/staff/relic，
  │   data/equipment.json 11 条；equip/unequip 先落盘（2026-11-19）
  └─ 出征 → campaign_battle_bridge → SceneArgs.battle_args{campaign_token}
        → scenes/Battle.tscn（战棋 B2）→ 胜/负/弃 → CampaignSession.settle_battle
        → 首通/重复奖励 + loot_table 掉落 + 升级差分 level_ups → 回营地

世界场景 main.tscn（旧探索入口，Game.tscn 列表进入 / startup.cfg 直跳）
  ├─ TerrainSampler 采样 + 生态群落 → CellState → chunk 3D 柱地形
  ├─ Camera3D 4 正交视角旋转 / 昼夜 / 天气 / 阳光阴影 / 萤火虫 / 音效
  ├─ P → B1 就地战斗（world_to_chapter）｜O → JSON 战场（B2）｜E → 编辑器
  └─ CharacterMovementTest.tscn★（2026-11-19）：extends main.gd 的移动测试台
     （WASD 网格移动 + K/L 切角色包 20 角色 + 动作预览；P/O/E 隔离）

战棋战斗（battle.gd 装配层 + scripts/battle/ 演出/自动化）
  ├─ core/systems 纯逻辑：GridSystem / TurnManager / CombatSystem / 增援 / 胜利条件
  │   + facing_rules（背击）+ pincer_rules（夹击追击）+ EquipmentDataScript（装备四槽）
  ├─ 演出层：battle_presentation + turn_director + action_anim + immersive_camera
  │          + result_presentation + level_up_presentation（升级弹窗）
  │          + ImmersiveStage★（SubViewport 独立世界沉浸演出，可开关，纯表现）
  ├─ 行动历史 BattleActionHistory（【记录】Tab，跨回合回退）
  ├─ battle_save.gd（行动边界快照）+ GameSession.commit()（旧逐战场存档）
  └─ 战场渲染：BattlefieldRenderer + 建筑层（BuildingLayout/室内/遮挡）
```

## 三条并行子系统 + 一份设计 bible

1. **世界 / 生态子系统（原 pixel_world）**：`main.gd` 是**装配层与主循环**（2026-11-16 拆分后 2280 行）；`scripts/world/`（20 .gd）、`scripts/ecology/`、`scripts/animals/` 是它装配的能力模块（RefCounted、Callable 注入、无反向依赖）。设计原则是"**新增内容走配置/模块，不要往 main.gd 里加分支**"（见 `config/ecology/README.md`）。
2. **战棋战斗子系统（从 phaserjs 迁移）**：`scripts/core/`（纯逻辑 + 存档 codec/store + 增援刷入 + 建筑/室内布局 + **装备四槽 EquipmentDataScript** + **技能/状态/物品/装备四图标目录**）+ `scripts/systems/`（战斗结算 + AI 难度 + 交换 + 背击/夹击规则）+ `scripts/iso/`（等距/3D 渲染层）+ `scripts/battle/`（演出/UI/自动化/出征桥接/**沉浸舞台**）+ `scripts/editor/`（战场编辑器模型/画布/区域剪贴板/预设存储/素材面板/建筑/角色编辑）+ `scripts/characters/`（**免费角色包**切片表与帧动画，2026-11-19）。与世界的唯一耦合点是 `scripts/core/world_to_chapter.gd`。
3. **冒险模式子系统（2026-11-17/18 新增，当前默认入口）**：`scripts/campaign/`（CampaignSession autoload + 档案 codec/store + 关卡配置 + 队伍 + 商店目录）+ `scripts/scenes/campaign_*.gd`（四屏一层的营地 UI）。权威文档 `docs/campaign_loop.md`：出征令牌 settle 一次、磁盘永远是安全态、掉落独立 RNG、限购周期=通关数。
4. **`story/`（19 个 .md）**：完整的"古代魔法 + 多国争霸"战旗**设计 bible**（世界観/4 国/13 职业/8 角色/15 章/27 技能/25 道具/UI/音频/成就/新手引导）。注意它是**目标态设计**——当前 `data/` 实现 8 职业/8 技能/8 物品/8 JSON 战场 + campaign 6 关卡，扩张时以 story 文档为准绳（差距清单见 `docs/roadmap.md` 与 `docs/gameplay_gap.md`）。

## 重要设计取舍

- **坐标级确定性**：相同 seed + 相同 cell 永远产出相同结果。`DeterministicRng`、`_cell_rand`、`_quantize` 等是确定性契约核心，**改这些会挂固化 SHA-256 快照测试**（`tests/terrain_generation_contract.gd`）。
- **"新增不修改，分支注入"**：B1 就地战斗对 `main.gd` 的改动全是 `if _battle_active:` 前置短路；B2 路径不动。战场入口（O/E）同样以独立方法注入（`_enter_battlefield` / `_open_map_editor`），不侵入既有流程。
- **渲染演进（2026-11-11 → 11-12）**：先尝试 2D 可旋转投影（任意角度连续旋转），因素材只在 4 个正交视角下能通过拼缝验收，最终收敛为 **`SUPPORTED_ANGLES = [0°, 90°, 180°, 270°]` 离散视角**，随后整体迁移到 **3D 正交渲染**：角度变化只旋转 Camera3D，地形、生态状态与连续网格坐标全部保持不变。踩坑记录见 `handoff/2026-11-11-isometric-rotation.md`。
- **配置分层（双轨）**：`config/ecosystems.json`（旧版，运行时实际读取入口）与 `config/ecology/manifest.json` + 模块化 biome/species/communities（新版，逐步迁移）并存，由 `_compile_ecosystem_config` 编译。`legacy_bundles.json` 仅为旧布局兼容，**新内容禁止使用**。
- **战场渲染统一**：B2 战场与编辑器画布共用 `BattlefieldRenderer`（等距方块柱），地形高度规则：water h1 / plain・forest・village h2 / fort h3 / wall h4 / mountain h5。世界就地战斗的地形映射 `cell_context_to_terrain` 覆盖 11 种中的 **7 种**（roadmap P1-4）。
- **冒险模式的磁盘安全契约（2026-11-18）**：出征 = 先落盘"出征前快照 + attempt 标记"再进战斗；重载即恢复出征前。`settle_battle(token)` 一个令牌只结算一次（幂等），胜利 receipt 带 `level_ups` 升级差分。商店购买**先落盘后内存**（原子性），限购周期 = `completed_levels.size()`。掉落用**独立 RNG**（种子 = 战场 id + 出征令牌），不触战斗全局随机流。存档在 `user://campaign_saves/`，与旧 `battle_saves/` 完全隔离（campaign 出征 `save_identity` 留空，不写旧档）。
- **建筑四方向精灵图契约（2026-11-18）**：4:1 横排 sheet（`direction_mode=four_directions`），帧选择 `posmod(camera_quadrant - rotation, 4)`；footprint 1..8，占用格由素材派生（奇数旋转交换 w/h）；`BuildingLayout` 是编辑器保存与 loader 共用的占用/重叠唯一校验实现；sheet 内容 SHA-256 固化在 `docs/building_assets.md`。
- **图标稳定 ID 契约（2026-11-18，2026-11-19 扩到四目录）**：`skill_icons.gd` 的 iconId `'01'..'53'` 与文件**绑定永不重排**，未知 ID 显式回退 `DEFAULT_ICON_ID` + push_warning（不返回 null）；`status_icons.gd` 由 buff 属性推导图标 ID；**物品 `item_icons.gd`（'01'..'08'→assets/ui/items/）与装备 `equipment_icons.gd`（'01'..'11'→assets/ui/equipment/）沿用同一模式**（稳定 ID→显式路径映射 + 缓存 + DEFAULT 兜底）。
- **装备四槽与双口径（2026-11-19）**：`data/equipment.json`（11 条）+ `core/equipment.gd`（EquipmentDataScript 全静态，**单一权威**：catalog/can_equip/stat_bonus/capacity/equip/unequip/normalize）。三消费方三种口径各一行委托：战斗 buff 加成 = base+stat_bonus（buff_system）、实际武器 = unit_weapon 装备槽优先回退（weapons）、HP/MP 容量 = base+装备不含 buff（campaign_roster）。**勿在演出/UI 层复写装备规则**。
- **沉浸舞台是纯表现（2026-11-19）**：`ImmersiveStage.tscn`（SubViewport own_world_3d 独立世界）挂 battle.gd，`Settings.battle_immersive_presentation` 可开关；演出走 `await _immersive_stage.present()`，但**结算永远在 battle_action_resolver**，关舞台/关开关对结算零影响。单位入舞台走 `unit_sprite.setup_stage()` 第三初始化路径。交接 `handoff/immersive-battle-presentation.md`。
- **批量绘制优先**：水、岸浪、天气、飞鸟等高密度元素走批量绘制/受限呈现槽位，避免每格一个 `_process` 节点。
- **三单体拆分（2026-11-16）**：main.gd（4319→2280 行）、map_editor.gd（3285→1088 行）、battle.gd 从"功能全塞主文件"改为"**装配层 + RefCounted 能力模块**"（模块 Callable 注入、无反向依赖；主文件保留测试直调所需的同名薄委托）。行为护栏：拆分期间 `terrain_generation` SHA-256 每批零漂移、`map_editor_region_ops` L1 埋点序列逐行一致（`docs/plans/split_report_2026-11-15.md`）。
- **结算内核与表现分离（2026-11）**：`battle_action_resolver.gd` 是 battle.gd、无头自动化（`battle/automation/` + `tools/battle_cli.gd`）与战斗契约测试**共享的行动结算内核**（背击/夹击/掉落判定都进 resolver）。增援刷入同样双链路共用 `reinforcement_spawner.gd`。
- **演出可选可跳**：沉浸演出（开场/行动/结算/升级弹窗）是**表现层增强**，非战斗逻辑依赖；battle 设置页可开关，播放中可快进（`*_finished(skipped)` 信号贯穿）；关演出不影响结算正确性。`level_up_presentation.gd` 用 `sound_requested` 信号解耦，不直连 Sfx。
- **胜利/增援走声明式 JSON**：chapter 可选 `victory`（rout / defend_turns / seize）与 `reinforcements`（按回合波次）字段，`battlefield_loader` 静态严校验、非法整卡拒绝；`check_victory(enemies, ctx)` 注入式判定 + 歼灭兜底，未到点增援并入敌存活集合防提前判胜。
- **UI 设计规范单一事实来源（DESIGN.md）**：间距/圆角/字号/边距 token 唯一实现于 `ui/theme/component_theme.gd`，六个薄布局容器（PixelVBox/HBox/Grid/Margin/Center/Scroll）；新增界面**禁止裸数字样式值/自建 StyleBox/绝对定位/横向滚动**。**冒险模式 UI（campaign_*.gd）是首个全 Pixel* 组件 + 锚点布局的正经业务消费者**；map_editor 已部分迁移；battle_ui/HUD 仍是老 UI（迁移是 roadmap 项）。
- **用户素材走网络清单而非打包**：编辑器素材库从 HTTP 源导入 blob 到 `user://`，sha 去重幂等；源地址可配置（`asset_source.cfg [asset_source] source_url` 覆盖 > 库内 settings > 默认 `127.0.0.1:8076`），断源优雅降级。

## 仓库边界

- **项目位置**：`/Users/Zhuanz/Documents/pixel_world`（macOS；历史路径 G:/ → E:/ → 本机）。Godot 可执行文件 `/Applications/Godot.app/Contents/MacOS/Godot`（本机实测 4.7.1；Windows 历史路径 `D:/Godot/Godot_v4.7.2-stable_win64.exe`）。项目跨机同步开发（E:\pixel_world 亦有产出）。
- **源项目引用**：战棋代码迁移自外部 phaserjs 项目（不在本仓库）。
- **文档分区**：`claude/`（本索引详情）、`rules/`（agent 规则 4 篇）、`story/`（目标态设计 bible）、`handoff/`（专题交接存档 3 篇）、`docs/`（campaign_loop / building_assets / battle_automation / test_automation / startup_config / user_assets / gameplay_gap / roadmap / feature_map.json+.html / plans/ 等）、`plans/`（开发计划存档）、根 `DESIGN.md`（UI 设计规范唯一事实来源）。
- **不属于本仓库的内容**：`.godot/`（引擎生成物）、`/builds/`、`/exports/`、`/android/`、`.tmp/`（跨机调试工作目录，含 recovered 恢复现场）。
