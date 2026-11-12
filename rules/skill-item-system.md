# Rule: 技能 / 物品 / MP / 冷却 系统

> 本规则是 `AGENTS.md` 的展开，讲**数据结构、效果类型、装配路径与自测入口**。

每个单位有自己的技能集、背包、MP、冷却和 buff。静态数据用 JSON + 懒加载（仿 `professions.json`），战斗结算走独立系统；敌方 AI 与玩家托管都会自动使用技能/物品。

## 相关文件

| 文件 | 职责 |
| --- | --- |
| `data/skills.json` / `data/items.json` | 技能/物品静态数据（id/name/type/range/mpCost/cooldown/power/effect…） |
| `scripts/core/skills.gd`（`SkillData`）/ `scripts/core/items.gd`（`ItemData`） | JSON 懒加载 + 查询（`get_skill` / `usable_skills` / `usable_items`）；`DEFAULT_SKILLS_BY_WEAPON_TYPE`（skills.gd:122）、`DEFAULT_ITEMS`（items.gd:123） |
| `scripts/systems/skill_system.gd`（`SkillSystem`） | 技能结算：`can_use` / `targets_for` / `preview` / `execute`，伤害/治疗/AOE/buff |
| `scripts/systems/item_system.gd`（`ItemSystem`） | 物品结算：消耗品/投掷物/装备/buff 道具的 `execute` / `equip` |
| `scripts/systems/buff_system.gd`（`BuffSystem`） | buff 工具（`effective_stat` / `apply_buff` / `tick_buffs` / `cleanse`），零依赖，打破 CombatSystem↔SkillSystem 循环 |
| `scripts/core/enums.gd` | `SKILL_*`（L49-53）/ `ITEM_*`（L59-62）/ `TARGET_*`（L68-73）常量 |
| `scripts/core/unit.gd`（`UnitFactory`） | 单位创建与默认技能/物品装配（`create_random_unit` L40、`_apply_default_skills_and_items` L54） |
| `scripts/tests/test_skills.gd` | 自测脚本，挂在 `scenes/SkillTest.tscn` 上 |

## UnitData 扩展字段（`unit.gd:_base_unit` 起）

```text
mp: int                               # 当前 MP（上限 = stats.mp）
skills: [StringName]                  # 已学技能 id
skillCooldowns: {skillId -> int}      # 剩余冷却回合
items: [{id, uses}]                   # 背包（带耐久；装备后从背包移除）
buffs: [{stat, value, turns, label}]  # 临时属性修改（回合倒计时）
equipped: [StringName]                # 已装备物品 id（防重复装备）
```

MP 上限由职业推导（`unit.gd:default_max_mp_for`）：`anima`/`dark` 30、`staff` 24、其余 12。

## 技能效果类型（`type`）

- `damage` — 单体伤害（含命中判定，不被反击）
- `heal` — 单体治疗（不超 HP 上限）
- `aoe` — 范围伤害（对范围内所有合法目标各结算）
- `buff` — 增益（自身/友方，挂正面 buff）
- `debuff` — 减益（敌方，挂负面 buff）

## 物品类型（`type`）

- `consumable` — 消耗品（回 HP/MP/解毒，`uses -= 1`，归零从背包移除）
- `throwable` — 投掷物（固定伤害，有射程和 uses）
- `equip` — 装备类（`ItemSystem.equip()` 永久改 `stats`，记入 `equipped` 防重复，装备后移出背包）
- `buff` — buff 道具（挂临时 buff，如力量药水 `mightPotion`）

## 技能/物品从哪来（重要）

运行时只有**一条**装配路径：

```text
create_random_unit (unit.gd:40)
  → _base_unit + ProfessionData.apply_profession
  → _apply_default_skills_and_items (unit.gd:54)
      技能：professions.json 的 defaultSkills → 否则 SkillData.DEFAULT_SKILLS_BY_WEAPON_TYPE
      物品：professions.json 的 defaultItems → 否则 ItemData.DEFAULT_ITEMS
```

- **当前 `data/professions.json` 没有配置 `defaultSkills` / `defaultItems`**，所以实际全部走「武器类型推荐技能 + 默认消耗品」。
- 想给某职业固定技能/背包：在 `professions.json` 对应职业里加 `defaultSkills: ["id"...]` / `defaultItems: [{id, uses}]`，`_apply_default_skills_and_items` 会去重后写入。
- **`PlacedUnit.skillIds` / `itemIds` 不是运行时路径**：`unit.gd:130 create_placed_unit` 只在结构里保留这两个字段（L154-155），`reclass()`（L160）重建时也不传，全仓库没有代码把它们展开成 `skills`/`items`。旧文档说 `level_to_chapter.gd` 会展开——该文件与 `BattleTest` 均已不存在（B2 改造后战场由 `WorldToChapter` 从真实世界生成，`test_skills.gd` 的转换用例也已删空）。
- 测试里手动塞技能/物品：

```gdscript
unit[&"skills"].append(&"fireball")
unit[&"mp"] = int(unit[&"stats"][&"mp"])
unit[&"items"].append({ id = &"potion", uses = 3 })
```

## 自动化测试

**纯逻辑自测**：`scenes/SkillTest.tscn` → `scripts/tests/test_skills.gd`（38 条 `_ok` 断言），覆盖数据加载、技能伤害/治疗/AOE、冷却递减、MP 扣减、buff 生效与到期、物品消耗/装备/buff 药水、AI 决策含技能/物品。

```text
mcp__godot__dbg_launch({ "scene": "res://scenes/SkillTest.tscn" })
mcp__godot__runtime_get_log()
```

脚本只打印 `== 结果: N passed, M failed ==` 与 `[FAIL] ...`，**不设置退出码**；判定看日志里 failed 是否为 0。注意它会 `randomize()`，用例本身应容忍随机。

**托管实战**：没有 `BattleTest.tscn` 了。要跑整场战斗，按 @rules/autoplay-hosting.md 用 `main.tscn` 进战斗并开启托管（战场 JSON `"hosting": true` 最稳），观察敌方 AI 与玩家托管是否自动用技能/物品，战斗以 `[battle] 胜利！` / `[battle] 败北` 日志收尾。

## 已知坑

- 技能在 `skills` 里但 `mp` 不够 / 冷却未归零 → `can_use` 拒绝，AI 会改打普攻，看到「不用技能」先查这两个字段。
- `items` 条目是 `{id, uses}`，不是 id 字符串；`ItemSystem.execute` 需要条目字典。
- 装备类改的是 `stats` 基础值（永久），不是 buff；卸装逻辑目前没有，`equipped` 只防重复装备。
- buff 用 `turns` 倒计时，到期由 `BuffSystem.tick_buffs` 清理；`effective_stat` 是唯一正确的读属性入口（直接读 `stats` 会漏 buff）。
- 自测脚本 `_ready` 就跑完，不会自动 `quit`，headless 下需要外部超时或手动关。
