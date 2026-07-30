# Rule: 技能 / 物品 / MP / 冷却 系统

> 本规则是 `AGENTS.md`「关键约束」的展开。讲**技能/物品系统的数据结构、效果类型、分配路径与自测入口**。

每个单位都有自己的技能集、背包、MP 和冷却。技能/物品的静态数据用 JSON + 懒加载（仿 `professions.json`），战斗结算走独立系统，敌方 AI 和玩家托管都会自动使用技能/物品。

## 相关文件

| 文件 | 职责 |
| --- | --- |
| `godot/data/skills.json` / `godot/data/items.json` | 技能/物品静态数据（id/name/type/range/mpCost/cooldown/power/effect...） |
| `godot/scripts/core/skills.gd`（`SkillData`）/ `items.gd`（`ItemData`） | JSON 懒加载 + 查询（`get_skill`/`usable_skills`/`usable_items` 等） |
| `godot/scripts/systems/skill_system.gd`（`SkillSystem`） | 技能结算：`can_use`/`targets_for`/`preview`/`execute`，伤害/治疗/AOE/buff |
| `godot/scripts/systems/item_system.gd`（`ItemSystem`） | 物品结算：消耗品/投掷物/装备/buff 道具的 `execute`/`equip` |
| `godot/scripts/systems/buff_system.gd`（`BuffSystem`） | buff 工具（`effective_stat`/`apply_buff`/`tick_buffs`/`cleanse`），零依赖，打破 CombatSystem↔SkillSystem 循环 |
| `godot/scripts/core/enums.gd` | `SKILL_*`/`ITEM_*`/`TARGET_*` 枚举常量 |

## UnitData 扩展字段（在 `unit.gd:_base_unit`）

```text
mp: int                          # 当前 MP（上限 = stats.mp，类比 hp/stats.hp）
skills: [StringName]             # 已学技能 id 列表
skillCooldowns: {skillId -> int} # 剩余冷却回合
items: [{id, uses}]              # 背包（带耐久）
buffs: [{stat, value, turns, label}]  # 临时属性修改（回合制倒计时）
equipped: [StringName]           # 已装备物品 id（防重复装备）
```

## 技能效果类型（type）

- `damage` — 单体伤害（含命中判定，不被反击）
- `heal` — 单体治疗（不超 HP 上限）
- `aoe` — 范围伤害（对范围内所有合法目标各结算）
- `buff` — 增益（自身/友方，挂正面 buff）
- `debuff` — 减益（敌方，挂负面 buff）

## 物品类型（type）

- `consumable` — 消耗品（回 HP/MP/解毒，uses-=1，归零从背包移除）
- `throwable` — 投掷物（固定伤害，有射程和 uses）
- `equip` — 装备类（永久改 stats，走 `equip()`，不消耗 uses）
- `buff` — buff 道具（挂临时 buff）

## 自动化测试

- **纯逻辑自测**：跑 `res://scenes/SkillTest.tscn`（`test_skills.gd`，49 条断言，headless 友好，退出码反映成败）。覆盖数据加载、技能伤害/治疗/AOE、冷却递减、MP 扣减、buff 生效与到期、物品消耗/装备、AI 自动使用技能/物品、PlacedUnit→UnitData 转换。
- **托管实战**：跑 `res://scenes/BattleTest.tscn`（`hosting:true`），敌方 AI 和玩家托管会在战斗中自动决策使用技能/物品，跑完整场战斗至胜负判定。

## 在自定义场景给单位配技能/物品

技能/物品的分配有两条路径：
1. **职业默认**：`professions.json` 的可选字段 `defaultSkills`/`defaultItems`，`create_random_unit` 会自动塞入。
2. **编辑器持久化**：`PlacedUnit.skillIds`/`itemIds`（可选，向后兼容），`level_to_chapter.gd` 会展开成运行时 `skills`/`items`。未配置时回退到职业默认/通用消耗品。
