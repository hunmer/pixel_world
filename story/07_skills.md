# 07 技能设计（Skills）

> 本文档服务于**「交锋」**支柱——技能是玩家在格子战场上**用资源换效果**的核心动作；同时通过 MP 经济约束，落实 [00 设计支柱·二元魔法](00_design_pillars.md#五魔法体系硬约束影响所有技能道具职业设计) 的「普通魔法常规可用、神级魔法决定性但稀有」手感。

> 元素/系别对应世界观中的魔法体系，详见 [01 世界观·魔法体系](01_worldview.md)；技能学习职业与 `weaponType` 对应关系详见 [03 职业](03_professions.md)。
>
> 说明：本设定为**二元魔法**——**普通魔法** MP 经济放宽（可常规回复、mpCost 较低）、法师可频繁交锋；**神级魔法（卷轴习得）**为「决定性但稀有」的稀缺王牌，沿用高 mpCost + 三重代价。§五「MP 经济设计」与 §九自检 9.1 中凡「魔法 / 法师」相关约束，均按二元结构理解为仅指神级魔法层。详见 [00 设计支柱](00_design_pillars.md#五魔法体系硬约束影响所有技能道具职业设计)。

---

## 一、设计原则（引用 Game Design Skill）

| 原理 | 在本设计中的体现 |
|------|------------------|
| **reinforcement-feedback-systems** | 魔法技能 mpCost 高 = 施法即**消耗稀缺奖励**（负惩罚），逼玩家只在「决定性时机」出手；物理技能 mpCost 低/0 = 鼓励频繁交锋（正强化）。 |
| **character-optimization-design** | 元素克制循环（fire→wind→earth→water→fire）+ 光暗互克 = **互联属性**，防止单一系别 build 通吃（no dominant strategy）。 |
| **doubling-halving-balance** | power 区间用 8/10/12/15 四档定锚；mpCost 用 0/4/6/9/12 五档。第九节对 3 个高风险技能做极端测试。 |
| **flow-state-design-framework** | 技能随等级/转职**渐进解锁**：每章引入 1-2 个新机制（AOE / 召唤 / 传送），避免一上来全图鉴造成「技能过高→焦虑」。 |

---

## 二、字段约定（严格对齐 skills.json）

沿用 `godot/data/skills.json`：`id / name / desc / type / element / range[min,max] / targetType / mpCost / cooldown / power / hitBonus`。

### 2.1 type 扩展约定（新增 buff/debuff/utility/summon 的效果字段）

现有数据已用 `stat / buffValue / buffTurns` 承载 buff（见 `powerSurge`），本设计沿用：

| type | 效果字段 | 说明 |
|------|----------|------|
| damage | power / hitBonus | 单体/范围伤害 |
| heal | power | 恢复 HP |
| aoe | power / hitBonus | 范围伤害（沿用现有 `blizzard` 的 type="aoe"）|
| buff | stat / buffValue(正) / buffTurns | 友方增益 |
| debuff | stat / buffValue(负) / buffTurns | 敌方减益 |
| utility | special | 传送/侦察/隐身等，用 `special` 字段描述机制 |
| summon | summonId / summonTurns | 召唤临时单位 |

> **stat 字段统一对齐 professions.json**：`power / agility / skl / luk / def / res / mov`（旧数据 `str/spd` 需迁移，见 [03 职业](03_professions.md)）。

### 2.2 element 取值
`fire / water / earth / wind / light / dark / physical`（physical 表示纯物理，不参与魔法克制）。

---

## 三、元素克制循环（链到源脉世界观）

> 四源脉（fire/water/earth/wind）构成**循环克制**，光暗**互克**，physical **无克制**。这呼应 [01 世界观](01_worldview.md) 的源脉分支——同源互斥、异源相生。

```
        fire ──→ wind
         ↑         │
         │         ↓
        water ←── earth

      light ←→ dark  （互克）

      physical  （不参与，伤害恒定）
```

| 攻方 → 守方 | 倍率 | 说明 |
|-------------|------|------|
| fire → wind | ×1.5 | 火借风势 |
| wind → earth | ×1.5 | 风蚀沙崩 |
| earth → water | ×1.5 | 土掩水势 |
| water → fire | ×1.5 | 水灭火 |
| light ↔ dark | ×1.5 | 互克 |
| physical → any | ×1.0 | 物理稳定输出 |
| 同元素 | ×0.75 | 同源抗性 |
| 反向（wind→fire 等）| ×0.75 | 被克 |

> **设计意图（doubling-halving）**：克制倍率先试 ×2（过强，玩家只练克制系）→ ×1.5 收敛。1.5 足以让「换人打克制」值得，但不至于让被克方毫无还手之力。

---

## 四、技能分类总表（27 个）

### 4.1 物理技能（主流，低/零 MP）— 9 个

| id | 中文名 | type | element | range | targetType | mpCost | cd | power | hitBonus | 职业 | 稀有 |
|----|--------|------|---------|-------|-----------|--------|-----|-------|----------|------|------|
| smite | 重击 | damage | physical | [1,1] | enemy | 4 | 1 | 8 | 95 | 剑士/刺客 | 普通 |
| charge | 突击 | damage | physical | [1,2] | enemy | 5 | 2 | 12 | 85 | 枪骑兵 | 普通 |
| preciseShot | 精准射击 | damage | physical | [2,3] | enemy | 3 | 0 | 9 | 100 | 猎手 | 普通 |
| rapidFire | 连射 | damage | physical | [2,3] | enemy | 6 | 2 | 7×2 | 80 | 猎手 | 精良 |
| whirlwind | 旋风斩 | aoe | physical | [1,1] | aoe_enemy | 8 | 3 | 9 | 85 | 狂战士 | 精良 |
| heavySmash | 重砸 | damage | physical | [1,1] | enemy | 6 | 2 | 14 | 75 | 重骑士/狂战士 | 精良 |
| backstab | 背刺 | damage | physical | [1,1] | enemy | 5 | 2 | 10 | 90 | 刺客 | 精良 |
| counter | 反击架势 | buff | physical | [0,0] | self | 3 | 3 | 0 | — | 剑士/重骑士 | 普通 |
| warCry | 战吼 | debuff | physical | [1,2] | aoe_enemy | 4 | 3 | 0 | — | 狂战士 | 普通 |

> `backstab`：`special:"从目标背后攻击命中 ×1.5"`（位置条件）。`counter`：`stat:"def", buffValue:+5, buffTurns:1, special:"受攻击时反击"`。`warCry`：`stat:"power", buffValue:-3, buffTurns:2`。

### 4.2 魔法技能（稀有王牌，高 MP，按元素分系）— 10 个

#### 火系 fire（爆发伤害）

| id | 中文名 | type | element | range | targetType | mpCost | cd | power | hitBonus | 职业 | 稀有 |
|----|--------|------|---------|-------|-----------|--------|-----|-------|----------|------|------|
| fireball | 火球术 | damage | fire | [1,3] | enemy | 6 | 0 | 10 | 90 | 魔导师 | 普通（已有）|
| infernoBlade | 炎刃斩 | damage | fire | [1,2] | enemy | 9 | 2 | 15 | 85 | 魔导师 | 史诗 |

> `infernoBlade`：火系奥义，对 `oiled`（油罐）目标触发 ×1.5 联动后总伤可达 ~22，是单体爆发天花板，但 mpCost 9 让法师一关只能放 1-2 次。

#### 水系 water（控制+治疗）

| id | 中文名 | type | element | range | targetType | mpCost | cd | power | hitBonus | 职业 | 稀有 |
|----|--------|------|---------|-------|-----------|--------|-----|-------|----------|------|------|
| frostBite | 寒霜咬 | damage | water | [1,3] | enemy | 6 | 1 | 8 | 90 | 魔导师 | 普通 |
| icePrison | 冰牢 | debuff | water | [1,3] | enemy | 8 | 3 | 0 | 80 | 魔导师 | 精良 |
| springTide | 春潮 | heal | water | [1,2] | ally | 5 | 0 | 15 | — | 牧师 | 普通 |

> `icePrison`：`stat:"mov", buffValue:-99, buffTurns:1`（定身一回合）。`springTide`：水系治疗，比光系 `heal` 多 0 mpCost 但少 1 射程（互补设计，防止单一治疗通吃）。

#### 地系 earth（防御+反伤）

| id | 中文名 | type | element | range | targetType | mpCost | cd | power | hitBonus | 职业 | 稀有 |
|----|--------|------|---------|-------|-----------|--------|-----|-------|----------|------|------|
| stoneWall | 石壁 | buff | earth | [0,0] | self | 5 | 3 | 0 | — | 重骑士/牧师 | 普通 |
| quake | 震击 | aoe | earth | [1,2] | aoe_enemy | 9 | 3 | 9 | 80 | 魔导师 | 精良 |

> `stoneWall`：`stat:"def", buffValue:+8, buffTurns:2`（最强单体防御）。`quake`：地系 AOE，配合 water 克制循环（earth→water）打水系敌人。

#### 风系 wind（机动+骚扰）

| id | 中文名 | type | element | range | targetType | mpCost | cd | power | hitBonus | 职业 | 稀有 |
|----|--------|------|---------|-------|-----------|--------|-----|-------|----------|------|------|
| gust | 强风 | damage | wind | [1,3] | enemy | 5 | 0 | 8 | 95 | 魔导师 | 普通 |
| blink | 闪烁 | utility | wind | [0,0] | self | 6 | 3 | 0 | — | 刺客/魔导师 | 精良 |

> `gust`：稳定低伤高命中，新手友好（flow-state 入门）。`blink`：`special:"传送至视野内任一空格（≤4 格）"`——战术机动神技，但 mpCost 6 + cd 3 限制滥用。

#### 光/暗系 light/dark（神圣/诅咒）

| id | 中文名 | type | element | range | targetType | mpCost | cd | power | hitBonus | 职业 | 稀有 |
|----|--------|------|---------|-------|-----------|--------|-----|-------|----------|------|------|
| heal | 治疗术 | heal | light | [1,2] | ally | 5 | 0 | 15 | — | 牧师 | 普通（已有）|
| smite_holy | 圣裁 | damage | light | [1,2] | enemy | 8 | 2 | 12 | 90 | 牧师 | 精良 |
| weaken | 虚弱术 | debuff | dark | [1,3] | enemy | 5 | 2 | 0 | — | 魔导师/刺客 | 普通（已有）|
| shadowBind | 暗缚 | debuff | dark | [1,3] | enemy | 7 | 3 | 0 | 85 | 刺客 | 精良 |

> `smite_holy`：光系对暗系敌人（亡灵/诅咒系）触发 ×1.5，是牧师唯一的进攻手段。`shadowBind`：`stat:"agility", buffValue:-5, buffTurns:2`（降速，让己方先手）。

### 4.3 辅助技能（buff/debuff/utility）— 5 个

| id | 中文名 | type | element | range | targetType | mpCost | cd | power | hitBonus | 职业 | 稀有 |
|----|--------|------|---------|-------|-----------|--------|-----|-------|----------|------|------|
| powerSurge | 力量觉醒 | buff | physical | [0,0] | self | 4 | 3 | 0 | — | 剑士/狂战士 | 普通（已有）|
| guard | 铁壁 | buff | physical | [0,0] | self | 3 | 3 | 0 | — | 重骑士 | 普通（已有）|
| haste | 疾风 | buff | wind | [1,2] | ally | 5 | 3 | 0 | — | 牧师/魔导师 | 普通（已有）|
| bless | 祝福 | buff | light | [1,2] | ally | 6 | 3 | 0 | — | 牧师 | 精良 |
| scoutEye | 侦察之眼 | utility | physical | [0,0] | self | 2 | 2 | 0 | — | 猎手 | 普通 |

> `bless`：`stat:"res", buffValue:+4, buffTurns:3`（应对 BOSS 魔法）。`scoutEye`：`special:"揭示视野内 5 格范围敌人 2 回合"`（迷雾关卡用）。

### 4.4 必杀/奥义（冷却长、效果强，每系别 1 个标志性）— 3 个

| id | 中文名 | type | element | range | targetType | mpCost | cd | power | hitBonus | 职业 | 稀有 |
|----|--------|------|---------|-------|-----------|--------|-----|-------|----------|------|------|
| dragonSlash | 龙牙断 | damage | physical | [1,1] | enemy | 0 | 5 | 18 | 90 | 剑士（转职后）| 史诗 |
| cataclysm | 天崩 | aoe | earth | [1,3] | aoe_enemy | 12 | 5 | 14 | 80 | 魔导师（高阶）| 传说 |
| resurrection | 复活术 | heal | light | [1,1] | ally | 12 | 6 | 50%HP | — | 牧师（高阶）| 传说 |

> **奥义设计哲学**：mpCost 12 = 法师 MP 池的接近一半（见第五节 MP 经济），cd 5-6 = 一关只能放 1 次。`dragonSlash` 是物理系唯一奥义，mpCost 0 让物理职业也有「大招」手感，但 cd 5 限制滥用。

---

## 五、MP 经济设计（核心 / 呼应二元魔法）

> 本节分两层理解：**普通魔法** MP 经济放宽（池量上调、可常规回复，法师频繁交锋）；**神级魔法**（卷轴技能）MP 极稀缺（高 mpCost + 三重代价，沿用「肉痛但改变战局」手感）。下方 5.1-5.3 的池量表与「不设回 MP 手段」等约束，均按二元结构理解为仅适用于神级魔法层。

> 这是整个技能系统对 [00 支柱·二元魔法](00_design_pillars.md) 的表达。目标（神级魔法层）：让玩家每次放神级魔法都**肉痛**，但放了之后**改变战局**。

### 5.1 MP 总量水平

| 职业 | MP 池（满级）| 一关可用魔法次数（不补 MP）|
|------|-------------|--------------------------|
| 魔导师 | 20-24 | 2-3 个大招（infernoBlade×2 + fireball×1）|
| 牧师 | 16-20 | 3-4 次 heal + 1 次 smite_holy |
| 剑士/刺客/猎手 | 8-12 | 仅辅助技能（counter/haste 偶尔用）|
| 重骑士/狂战士 | 4-8 | 几乎不放魔法，纯物理 |

> 法师 MP 池刻意压在 20 左右——足够放 2 个决定性大招，但不够「无脑刷魔法」。这是 doubling-halving 的收敛点：试过 MP=40（法师变成 AOE 制造机，破坏稀缺感）和 MP=10（法师一关只能放 1 次，过于憋屈）。

### 5.2 MP 回复手段（刻意稀缺）

| 手段 | 回复量 | 获取难度 | 设计意图 |
|------|--------|----------|----------|
| 关卡结束自动回满 | 100% | 免费 | 保证每关起点公平（关卡是独立经济单元）|
| mpPotion | 10 | 商店限量 2 个/章 | 主力回复，但限量 = 总量上限 |
| elixir | 15 | 史诗 uses=1 | 救急，非续航 |
| 源脉碎片 sourceVeinShard | 回满 | 传说 uses=1，**永久 -1 res** | 绝境牌，有代价 |
| 牧师无 MP 回复技能 | — | — | **刻意不给**「回复 MP 的技能」，否则稀缺感崩塌 |

> **关键决策**：本作**不设**「吸魔」「冥想」之类回 MP 的技能/被动。MP 只能靠道具或关卡结算回复。这是 MP 经济的硬底线，任何后续设计不得突破（呼应 character-optimization-design 的「防 dominant strategy」）。

### 5.3 一关能放几个大招？（玩家心智模型）

以满级魔导师（MP 22）为例：
- 起手 `fireball`(6) ×2 = 12 MP → 剩 10
- BOSS 战 `infernoBlade`(9) ×1 = 9 MP → 剩 1
- **共 3 个魔法，其中 1 个是大招**
- 若带上 1 个 mpPotion(+10)，则可多放 1 个 fireball 或攒到第 2 个 infernoBlade
- 若喝下源脉碎片（回满），可再多 1 个大招，但永久 -1 res

**结论**：魔法师一关 = **3-4 个常规魔法 + 1 个王牌大招**。这让魔法「决定性但稀有」的手感成立——玩家会盯着 BOSS 血量，等到 1/3 血时才舍得放 infernoBlade。

---

## 六、物理技能代表作深入

### 6.1 突击 charge（枪骑兵 / 机动爆发）
- **战术定位**：range [1,2] 让枪骑兵（mov 7）能突进 2 格外目标，是「布阵→交锋」转换的核心。mpCost 5 对枪骑兵（MP 8-12）是中等消耗，一关用 2 次。
- **典型连招**：枪骑兵 `charge` 突进 → 剑士 `smite` 补刀 → 牧师 `haste` 让枪骑兵再动撤退。
- **MP 经济**：5 MP 在物理职业里算贵，但换来 12 power 的爆发（高于普攻），值得。

### 6.2 连射 rapidFire（猎手 / 双段输出）
- **战术定位**：`power 7×2`，对高 res 低 hp 法师威胁极大。但 hitBonus 80 + mpCost 6，让猎手必须配 `preciseShot` 先破盾再连射。
- **反 min/max**：双段伤害受 def 双减，打重甲（def 11）几乎刮痧——强制猎手选目标，不能无脑连射。

### 6.3 背刺 backstab（刺客 / 位置博弈）
- **战术定位**：从目标背后 ×1.5，配合刺客高 agility（先手）和 `blink` 传送绕后，是秒杀法师的连招。
- **典型连招**：刺客 `blink`(6 MP) 绕后 → `backstab`(5 MP) → 共 11 MP，刺客 MP 池 8-12 刚好够一次。**一关一次的刺杀秀**。

---

## 七、魔法技能代表作深入

### 7.1 炎刃斩 infernoBlade（火系奥义 / 单体爆发天花板）
- **战术定位**：power 15 + 火系对风系 ×1.5 = 理论 22.5 伤，秒杀多数非坦克。mpCost 9 = 法师 MP 的近半。
- **典型连招**：刺客 `oilFlask`（投掷，打 oiled 标记）→ 魔导师 `infernoBlade`（火系 ×1.5 联动）→ 总伤 ~33。**这是本作最高单体爆发连招，但需要 2 个单位 + 稀缺道具 + 大招 MP**，完全符合「决定性但稀有」。
- **MP 经济**：9 MP + 联动占用，意味着这一发打完法师基本空蓝，后续只能普攻。

### 7.2 冰牢 icePrison（水系控制 / 战场分割）
- **战术定位**：定身 1 回合，用来冻结敌方主力、分割战场。mpCost 8 + cd 3，一关用 1-2 次。
- **典型连招**：魔导师 `icePrison` 冻住敌方重骑士 → 己方集火其脆皮后排。
- **反 min/max**：定身对 fly 移动类型无效（设定：风系免疫水系定身），防止「一个技能控全场」。

### 7.3 闪烁 blink（风系机动 / 战术枢纽）
- **战术定位**：传送至视野内任一空格，是「布阵」支柱在技能层的延伸——能瞬间改变阵型。mpCost 6 + cd 3。
- **典型连招**：刺客 `blink` 绕后 → `backstab`；或魔导师 `blink` 登高台抢占射程。
- **MP 经济**：6 MP 对刺客是大投入（MP 8-12），一关 1-2 次，每次都得想清楚落点。

---

## 八、技能解锁与成长（flow-state-design-framework）

> 按 flow-state 三阶段：Introduction（入门）→ Practice（练习）→ Flow（精通），技能随**等级/转职**渐进解锁，每章引入 1-2 个新机制。

| 章节 | 玩家阶段 | 新解锁技能 | 引入的新机制 | 引用 flow-state |
|------|----------|-----------|-------------|----------------|
| 第 1 章 | Introduction | smite / fireball / heal / preciseShot | 基础伤害与治疗 | Stage 1：零技能，降难度 |
| 第 2 章 | Introduction→Practice | powerSurge / guard / frostBite | buff/debuff 概念 | 渐进引入机制 |
| 第 3 章 | Practice | charge / backstab / icePrison | 位置条件、定身控制 | 任务略高于当前技能 |
| 第 4 章 | Practice | blink / rapidFire / scoutEye | 传送、多段、迷雾侦察 | 鼓励技能组合 |
| 第 5 章 | Practice→Flow | infernoBlade / quake / shadowBind | 元素联动（oiled）、AOE | 接近精通 |
| 第 6 章+ | Flow | dragonSlash / cataclysm / resurrection | 奥义、复活、转职大招 | 精通期精准调难度 |

> **设计约束**：每章新机制 ≤2 个，避免认知过载（flow-state 警告：技能过高→焦虑）。转职（第 6 章）是技能体系的「二次入门」，重新走一遍 Introduction→Flow 循环。

---

## 九、平衡自检（doubling-halving-balance）

以下 3 个技能是**高风险破坏平衡点**，开发期各做 ×2/×0.5 极端测试：

### 9.1 infernoBlade（power 15 / mpCost 9）
- ×2 power=30：秒杀一切，BOSS 战失去意义 → 确认 power 是关键变量。
- ×0.5 mpCost=4：法师一关能放 4-5 次 → 破坏魔法稀缺。
- **收敛值**：power 15（单体天花板但不破防坦克）、mpCost 9（法师 MP 的 ~45%）。

### 9.2 blink（utility / mpCost 6）
- ×0.5 mpCost=3：刺客每关闪烁 3-4 次，地图机动性崩坏（布阵失去意义）。
- ×2 cd=6：几乎用不上，道具形同虚设。
- **收敛值**：mpCost 6 + cd 3，一关 1-2 次，每次都痛。

### 9.3 resurrection（power 50%HP / mpCost 12 / cd 6）
- 这是**整个技能系统最锋利的平衡点**。若与 [06 道具·phoenixDown](06_items.md)（uses=1 复活）叠加，可能出现「无限复活」流。
- ×2 cd=12：基本一关用不上，浪费设计。
- ×0.5 mpCost=6：牧师每关复活 2 人，永久死亡失去威慑（违反 [00 支柱·抉择](00_design_pillars.md)）。
- **收敛值 + 硬约束**：mpCost 12 + cd 6，且**复活者当关 HP 上限锁定为 50%**（防止满血复活）。同时 resurrection 与 phoenixDown 在同一关**不可对同一单位叠加**（设计硬规则）。

### 9.4 元素克制的整体自检
- 若把克制倍率 ×2（=3.0）：玩家只练克制系，build 多样性归零（character-optimization 的 dominant strategy）。
- 若 ×0.5（=0.75）：克制形同虚设，元素设计失去意义。
- **收敛**：×1.5——足以奖励「换人打克制」，但不至于让被克方无解。

---

## 十、与其他文档的引用

- 元素/源脉主题：[01 世界观·源脉体系](01_worldview.md)
- 技能学习职业、`weaponType`、stat 字段：[03 职业](03_professions.md)
- 道具联动（oilFlask 的 oiled 标记、源脉法杖的 mpCost -2、源脉碎片回 MP）：[06 道具](06_items.md)
- 永久死亡与复活代价：[00 设计支柱·抉择](00_design_pillars.md)、[05 剧情分支](05_story_branches.md)

---

## 附：数据迁移备忘（对齐现有 skills.json）

1. `heal` 的 `element` 现为 `"holy"`，本设计统一为 `"light"`（对齐支柱定义），需迁移。
2. `blizzard` 的 `element:"ice"` 归入 `water` 系（ice 是 water 的子主题），或保留 ice 作为独立子系——建议主控决策。本设计暂按 water 系处理（`frostBite/icePrison` 用 water）。
3. `powerSurge/guard/weaken/haste` 的 `stat` 字段：`str/spd` 需迁移为 `power/agility`（对齐 professions.json）。
4. 新增 type：`utility / summon` 及对应 `special / summonId / summonTurns` 字段，建议在 skills.json schema 中登记。
5. 物理奥义 `dragonSlash` 的 mpCost=0 是有意为之（物理职业也有大招手感），实现时注意 UI 上 0 MP 技能的展示（建议显示「无消耗 / 冷却 5」）。
