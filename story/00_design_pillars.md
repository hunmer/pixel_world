# 设计支柱（所有文档的统一前提）

> 本文件是整个 story 设计的**最高纲领**。所有 subagent 与后续文档都必须先读完本文件，确保世界观/职业/剧情/道具/技能在**主题一致性**（synergy-thematic-design）下协同。

---

## 一、游戏定位（一句话）

**这是一款以「古代魔法诸国争霸」为主题的战棋（SRPG）游戏。**
- 形态：关卡制单机战旗（参考《火焰纹章》《皇家骑士团》《最终幻想战略版》）
- 核心：回合制格子战、职业克制、技能/物品/MP 资源管理、分支剧情

## 二、三大设计支柱（用动作动词）

参考 `game-design-methodology`：支柱必须是玩家**反复做**的动作，不是美术/主题词。

1. **布阵**（Position） — 在格子地图上移动单位、抢占地形/高地/隘口
2. **交锋**（Clash） — 用职业克制与技能组合，在正确时机对正确目标造成最大效果
3. **抉择**（Choose） — 在剧情分支、角色生死、资源消耗之间做不可逆取舍

> 组合成一句话：**"玩家在布阵 → 交锋 → 抉择的循环中，决定一场古代魔法战争的走向。"**

## 三、核心循环（必须反复有趣）

```
战前整备（编队/装备/职业转职）
   → 布阵移动（抢占地形）
   → 交锋（攻击/技能/道具）
   → 战后结算（经验/物品/剧情分支）
   → 角色成长 → 回到战前整备
```

验证标准（来自 game-design-methodology）：每一环单独拿出来都要有直接反馈、易懂、可扩展。

## 四、世界基调（主题 ≠ 题材）

- **题材**：古代魔法 + 多国争霸
- **主题**：「**战争没有赢家，只有活下来的人**」——一场关于责任、牺牲、信念被权力碾碎的故事
- 基调关键词：庄重、史诗、灰色道德、有限魔法（魔法稀缺而珍贵，不是烂大街）
- **禁止**：日式轻小说吐槽风、卖萌、过度开挂爽文、魔法万能化

## 五、魔法体系硬约束（影响所有技能/道具/职业设计）

为避免「魔法万能」破坏战旗的策略性，世界设定**魔法是稀缺资源**：

- 魔法源于**「源脉」（Ley Lines）**——大地之下流淌的远古魔力之河
- 只有少数血脉 / 经历启悟者能引导魔法，且**每次施法消耗 MP（法力）**
- MP 是**稀缺、不可自动回满**的资源（参考现有 `skills.json` 的 `mpCost` 字段）
- 因此：**物理职业是战场主力，魔法职业是决定性但稀少的「王牌」**——这与战棋的职业克制设计天然契合

## 六、与现有代码库的对齐（subagent 必读）

现有数据结构（`godot/data/`），所有新设计**必须沿用现有字段命名**：

### 职业数据结构（`professions.json`）
```json
{
  "id": "swordsman", "name": "剑士", "title": "高敏捷近战",
  "hp": 24, "power": 7, "agility": 9, "skl": 7, "luk": 6, "def": 5, "res": 2,
  "attackRange": [1, 1], "weaponType": "sword", "moveType": "foot", "mov": 5
}
```
- `weaponType`: sword / lance / axe / bow / magic / staff ...
- `moveType`: foot（步）/ ride（骑）/ fly（飞）
- 属性：hp / power(力) / agility(速) / skl(技) / luk(运) / def(防) / res(魔防) / mov(移动力)

### 技能数据结构（`skills.json`）
```json
{
  "id": "fireball", "name": "火球术", "type": "damage", "element": "fire",
  "range": [1, 3], "targetType": "enemy", "mpCost": 6, "cooldown": 0, "power": 10, "hitBonus": 90
}
```
- `type`: damage / heal / buff / debuff / summon ...
- `element`: fire / water / earth / wind / light / dark / physical
- `targetType`: enemy / ally / self / all_enemies ...

### 道具数据结构（`items.json`）
```json
{
  "id": "hpPotion", "name": "生命药剂", "type": "consumable",
  "target": "ally", "effect": "heal_hp", "power": 20, "range": [0, 1], "uses": 3
}
```

## 七、输出规范（所有 subagent 遵守）

1. **每个文档开头**：用一句话说明本文档对应哪个支柱 / 哪类玩家循环
2. **引用原理**：建议时引用 Game Design Skill 里的具体原理名（如「心流框架」「三角性决策」）
3. **表格优先**：职业/技能/道具对比用表格
4. **可执行**：给具体数值、ID、关系图，不空谈
5. **交叉引用**：用 `[世界观](01_worldview.md)` 这种相对链接互相引用
6. **文件命名**：`NN_主题.md`（NN 是两位数字序号，决定阅读顺序）

## 八、文档地图

| 序号 | 文件 | 负责 subagent |
|------|------|--------------|
| 00 | design_pillars.md（本文件） | 主控（已写） |
| 01 | worldview.md（世界观） | A |
| 02 | nations.md（国家） | A |
| 03 | professions.md（职位/职业） | B |
| 04 | characters.md（角色设定） | B |
| 05 | story_branches.md（剧情分支） | C |
| 06 | items.md（道具设计） | D |
| 07 | skills.md（技能设计） | D |
| 08 | README.md（索引） | 主控 |
