# 成就系统与玩家进度记录（14_achievements.md）

> **对应设计支柱**：本文档服务三大支柱中的 **「抉择（Choose）」**——成就与进度记录是把玩家每一次不可逆抉择的后果「沉淀」为可回顾、可比较、可炫耀的长效反馈，从而激发重玩动机与风格化游玩（见 [00 设计支柱](00_design_pillars.md) §二）。主题严格服从 **「战争没有赢家，只有活下来的人」**：成就体系刻意混合「沉重成就」「趣味成就」「探索成就」，避免沦为「光荣通关榜」。
>
> 依赖：[00 设计支柱](00_design_pillars.md) · [03 职业](03_professions.md) · [04 角色](04_characters.md) · [05 剧情分支](05_story_branches.md) · [06 道具](06_items.md) · [07 技能](07_skills.md) · [09 关卡](09_levels_and_scenes.md) · [10 UI/UX](10_ui_ux.md) · [12 音频](12_audio_design.md)
>
> **代码库实参（关键）**：现有持久化 `godot/scripts/core/level_storage.gd` 仅用 `user://levels/<id>.json` 存**编辑器关卡**（FileAccess + JSON.stringify，见 L47-53），**不存玩家通关进度/成就**；`godot/scripts/scenes/title.gd` 主菜单只有「开始游戏 / 地图编辑器」两按钮（L36-46），**无「成就 / 记录 / 图鉴」入口**；`godot/scripts/scenes/level_select.gd` 关卡列表从 LevelStorage 读，**无章节解锁/通关标记**；`godot/scripts/data/chapter_data.gd` 只有 `chapter_1()`，无章节序列与解锁逻辑。`grep -rl "achievement\|Achievement\|trophy\|unlock" godot/scripts/` **返回空**——本作目前**完全没有成就系统**。本文档设计的是从零搭建的整套体系。

---

## 〇、设计哲学（先读这段）

本成就系统服务的核心命题是：**「成就不是通关打卡表，而是一面让玩家看清自己战争模样的镜子。」**

为忠实于 [00 设计支柱](00_design_pillars.md) 的灰色道德基调与「战争没有赢家」主题，本系统遵循三条铁律：

1. **奖励多样游玩风格，不只「全通关」** —— 有「全员存活」的成就，也有「至少有一名同伴死亡」的成就；有「零道具通关」的成就，也有「用过 mpPotion 后仍失败」的自嘲成就。**没有唯一正确的游玩方式**（呼应 [player-psychology-decisions](player-psychology-decisions.md) 的 Triangularity）。
2. **不打断心流** —— 战斗中解锁的成就**只入队**，战后结算页批量弹窗（见 [§7.2](#72-解锁弹窗非侵入式)）；主菜单成就大厅是「事后回顾」场所，不是「战中分心」场所（`experience-pacing-structure` 的 7-10 分钟注意力窗口保护）。
3. **尊重主题** —— 既有「集齐所有传说道具」的收集向成就，也有「完成一次有同伴死亡的通关」的沉重成就；**禁止**「杀光所有敌人」这种与「战争没有赢家」冲突的成就。

### 引用的设计原理

| 原理 | 出处 | 在本系统的体现 |
|------|------|----------------|
| **Fixed vs Variable Reward（固定奖励 vs 变动奖励）** | `reinforcement-feedback-systems` | 成就解锁本身是 **Fixed Reward**（条件明确、可知），但「隐藏成就」引入 **Variable Reward** 的惊喜感——玩家不知道达成什么会「叮」一下，刺激探索与重玩。两者混用避免纯固定奖励的枯燥（见 [§1.2](#12-反斯金纳箱底线)）。 |
| **Permadeath Mitigation** | `reinforcement-feedback-systems`（Punishment Models） | 永久死亡是 High Severity 惩罚，易致玩家弃游。成就系统通过「把死亡转化为有意义的记录」（如「为倒下的同伴完成战役」成就）做 **emotional mitigation**——不是抵消失去，而是赋予失去以叙事重量。 |
| **Rollercoaster Pacing + 反高潮** | `experience-pacing-structure` | 成就解锁节奏服从 [05 剧情分支](05_story_branches.md) 的过山车曲线：峰章节（6/10/11/14）多给「战斗技巧」类成就，谷章节（8 营地之夜）多给「角色与羁绊」「探索」类成就，让反馈节奏也做峰谷。第 15 章通关成就刻意不给「光荣胜利」文案。 |
| **Hoarding / Completionism** | `player-psychology-decisions` | 玩家有「囤积/收集/完成度」的天然动机（收集图鉴、刷满百分比）。本系统**利用**这股动机驱动探索（访问所有村庄、集齐传说道具），但**严防**它变成「强迫刷数」的牢笼（见 [§1.2](#12-反斯金纳箱底线)）。 |
| **Kuleshov / Framing** | `player-psychology-decisions` | 同一个事件，用不同文案框定会改变玩家感受。如「同伴死亡」用「沉重的代价」框定而非「你失败了」——成就文案是主题的最后落地。 |

---

## 1. 成就系统总纲

### 1.1 设计目标三原则

| # | 原则 | 一句话 | 引用原理 | 落地手法 |
|---|------|--------|----------|----------|
| 1 | **奖励多样游玩风格** | 让「速通流」「零伤流」「收集流」「挑战流」「叙事流」都能拿到专属成就，而不是只有「全通关」一条路。 | `player-psychology-decisions`（Triangularity：Low/High Risk-Reward 并存） | 6 大分类各占约 1/6（见 [§2](#2-成就分类与总表)）；同一章节有「速通」「零伤」「零道具」三个互斥技巧成就，鼓励不同周目走不同风格。 |
| 2 | **不打断心流** | 战斗中解锁的成就只入队，战后结算页批量弹窗；主菜单成就大厅是事后回顾场所。 | `experience-pacing-structure`（7-10 分钟注意力窗口） | 战中 `unlock_achievement()` 只写 JSON + 播一个极轻的「叮」音效（不弹窗、不停顿）；战后结算页「新解锁」区域统一展示（见 [§7.3](#73-章节结算页)）。 |
| 3 | **尊重主题** | 服务「战争没有赢家」，有沉重成就也有趣味成就；禁止「杀光/屠戮/全灭」这种 Glory 调性的成就文案与条件。 | `synergy-thematic-design` | 通关成就文案是「你走到了尽头」而非「胜利」；同伴死亡成就是「沉重的代价」而非「失败」（见 [§3 重点成就](#3-重点成就详细设计)）。 |

### 1.2 反斯金纳箱底线（关键）

参考 `reinforcement-feedback-systems` 的明确警告：**Variable Reward（变动奖励）会刺激 pattern seeking（斯金纳箱效应），导致玩家为「刷成就」而重复劳动**。本系统设下三条反斯金纳箱底线：

| 底线 | 含义 | 具体约束 |
|------|------|----------|
| **不设「累计刷数」成就** | 禁止「击杀 1000 个敌人」「施法 500 次」这种**逼玩家重复劳动**的成就。 | 所有击杀/施法类成就的阈值 ≤ 单周目自然可达（如「首次暴击」「一关击杀 10 个」），不设跨周目累计。 |
| **明确「自然获得」vs「挑战向」** | 每个成就标注 `tier: natural / challenge / hidden`。`natural` = 正常通关必得或极易得；`challenge` = 需刻意尝试；`hidden` = 玩家不知条件。 | 玩家可在成就大厅看到 `natural` 的完整列表（给「完成度安全感」），`hidden` 只显示占位符（给「惊喜感」）。`challenge` 数量严格控制在总量的 30% 以下。 |
| **完成度不锁内容** | 成就完成度百分比**不解锁任何数值/关卡**。100% 完成度的奖励是**纯展示性**（称号「战役见证者」+ 一张美术原画）。 | 防止「为了解锁 X 必须刷满成就」的强迫感（`player-psychology-decisions`：避免完美主义牢笼）。 |

> **取舍说明**：我们不禁止玩家「为了成就而换种玩法」（这是健康的重玩动机），但我们禁止「为了成就而重复无意义劳动」。前者是「换风格」，后者是「刷数字」——界限在「是否需要跨周目累计」与「是否需要刻意违背正常游玩」。

### 1.3 与永久死亡的张力（关键设计）

永久死亡（permadeath，见 [04 角色](04_characters.md) §五、[05 剧情分支](05_story_branches.md) §7）是本作 High Severity 惩罚。成就系统与之的关系必须精心处理，**否则会变成「惩罚活下来的人」或「鼓励读档规避死亡」**。

| 设计原则 | 具体做法 | 反例（禁止） |
|----------|----------|--------------|
| **死亡可以被记录，但不被「要求」** | 有「完成一次有同伴死亡的通关」成就（承认死亡是战争的一部分），但**没有**「全程无人死亡」的强制成就（那会逼玩家 S/L）。 | ❌ 设计「Zero Death 通关」成就——这会鼓励读档文化，与「抉择不可逆」支柱冲突。 |
| **「全员存活」是 challenge 向，不是 natural 向** | 「全员存活通关」存在，但标注 `tier: challenge`，且文案是「你守住了每一个人」而非「完美通关」——承认这是**刻意努力的结果**，不是「正常玩法」。 | ❌ 把「全员存活」设为 natural——那会让有死亡的玩家觉得自己「玩错了」。 |
| **死亡成就的服务对象是死者，不是玩家** | 「为倒下的同伴完成战役」这类成就，解锁条件是「某同伴死亡后，仍通关至第 15 章」。文案聚焦「背负着死者的份走下去」，而非「你失去了一个人」。 | ❌ 「X 角色死亡」单独成成就且文案是「你失去了 X」——那是惩罚，不是记录。 |
| **图鉴保留死者档案** | 角色图鉴中阵亡角色**不会消失**，而是标记「已阵亡」并解锁其「遗书/最后独白」（见 [§6.1](#61-角色图鉴characters)）。 | ❌ 死亡角色从图鉴抹除——那是二次失去。 |

> 这套原则直接落地为 [§2 总表](#2-成就分类与总表) 中的「角色与羁绊类」成就设计。

---

## 2. 成就分类与总表

全表共 **52 个成就**，分 6 类。分布：剧情进度 8 / 战斗技巧 10 / 角色与羁绊 8 / 职业与成长 6 / 探索与收集 8 / 挑战与趣味 12（含 2 个隐藏）。

> **字段说明**：
> - `id`：英文蛇形命名，代码层直接用作 key。
> - `分类`：6 大类之一。
> - `tier`：`natural`（正常游玩自然可得）/ `challenge`（需刻意尝试）/ `hidden`（玩家不可见条件）。
> - `隐藏?`：是 = 玩家在成就大厅只看到「???」占位；否 = 玩家可见条件描述。
> - `奖励`：详见 [§8](#8-奖励设计轻量不破坏平衡)；此处只标类型（称号/图鉴/BGM/原画/新游戏+）。
> - `主题服务点`：一句话说明该成就如何服务「战争没有赢家」。

### 2.1 剧情进度类（8 个）

| id | 中文名 | tier | 隐藏? | 解锁条件（精确判定） | 奖励 | 主题服务点 |
|----|--------|------|-------|----------------------|------|------------|
| `story_ch1_complete` | 战火初临 | natural | 否 | `chapter_completed == "ch1"` | — | 故事的开始，不是庆典。 |
| `story_ch5_complete` | 立场初裂 | natural | 否 | `chapter_completed == "ch5"` | 图鉴：第 5 章立绘 | 阵营裂痕显现。 |
| `story_ch10_complete` | 暗夜抉择 | natural | 否 | `chapter_completed == "ch10"` | BGM：暗夜车队主题 | 第一次「忠诚 vs 平民」的撕裂。 |
| `story_ch15_complete` | 你走到了尽头 | natural | 否 | `ending_reached in ["ashen_king","broken_pact","silent_vein","lone_proof"]` | 称号「走过战争的人」+ 结局原画 | **文案刻意不用「胜利」**——战争没有赢家，只有走到尽头的人。 |
| `story_all_endings` | 四种终局 | challenge | 否 | `endings_reached.count == 4`（跨周目累计，存于 PlayerProgress） | 称号「命运的见证者」+ 全结局原画集 | 鼓励重玩体验「没有完美结局」。 |
| `story_all_branches_seen` | 殊途同归 | challenge | 否 | `(branch1_seen && branch2_seen && branch3_seen)` 跨周目累计 | 图鉴：分支树全图 | 鼓励体验所有三角抉择。 |
| `story_all_sidequests` | 战场之外 | challenge | 否 | `sidequests_completed.count == 5`（S1-S5，见 [09 关卡](09_levels_and_scenes.md) §四） | 图鉴：支线人物立绘 | 奖励探索战场之外的人。 |
| `story_first_death_run` | 沉重的代价 | challenge | 否 | `playthrough_completed == true && companions_died.count >= 1` | 称号「背负者」 | 承认死亡是战争的一部分，不是「玩错了」（见 [§1.3](#13-与永久死亡的张力关键设计)）。 |

### 2.2 战斗技巧类（10 个）

| id | 中文名 | tier | 隐藏? | 解锁条件（精确判定） | 奖励 | 主题服务点 |
|----|--------|------|-------|----------------------|------|------------|
| `battle_first_crit` | 致命一击 | natural | 否 | `total_crits >= 1`（全局累计，单次即触发） | — | 战斗的残酷开端。 |
| `battle_first_double` | 追击 | natural | 否 | `total_doubles >= 1`（agility 差 ≥4 触发追击） | — | 高敏捷的回报。 |
| `battle_first_kill` | 第一次夺人性命 | natural | 否 | `total_kills >= 1` | — | **文案不庆祝**——「夺人性命」而非「首杀」。 |
| `battle_no_damage_chapter` | 无伤之关 | challenge | 否 | 任一战斗章节 `damage_taken == 0 && chapter_completed` | 称号「滴水不漏」 | 极限操作的奖赏。 |
| `battle_speedrun_ch6` | 闪电破城 | challenge | 否 | `chapter_id == "ch6" && turn_count <= 6 && chapter_completed` | 图鉴：黑铁要塞速攻原画 | 对应 [09](09_levels_and_scenes.md) 第 6 章高手挑战点。 |
| `battle_no_items_chapter` | 锱铢必较 | challenge | 否 | 任一战斗章节 `items_used == 0 && chapter_completed` | 称号「精打细算者」 | 资源管理的高光。 |
| `battle_physical_only_chapter` | 凡人之力 | challenge | 否 | 任一战斗章节 `magic_skills_used == 0 && chapter_completed && chapter_has_mage_in_party` | 称号「不依赖奇迹的人」 | **核心主题成就**：呼应 [魔法稀缺](03_professions.md#六魔法职业特别说明核心主题服务)，奖励「不靠魔法也能赢」的凡人战术。 |
| `battle_weapon_triangle_5` | 克制大师 | natural | 否 | 单场战斗 `weapon_triangle_hits >= 5`（用克制武器命中 5 次） | — | 鼓励理解武器三角。 |
| `battle_terrain_bonus_10` | 据地而战 | natural | 否 | 单场战斗 `terrain_avoid_total >= 100`（累计地形闪避加成） | — | 鼓励「布阵」支柱。 |
| `battle_low_level_clear` | 以弱胜强 | challenge | 否 | 任一战斗章节 `max_party_level <= 3 && chapter_id in ["ch3","ch4"] && chapter_completed` | 称号「弱者之刃」 | 鼓励低练度挑战。 |

### 2.3 角色与羁绊类（8 个）

| id | 中文名 | tier | 隐藏? | 解锁条件（精确判定） | 奖励 | 主题服务点 |
|----|--------|------|-------|----------------------|------|------------|
| `bond_all_survive` | 你守住了每一个人 | challenge | 否 | `playthrough_completed && companions_died.count == 0` | 称号「守护者」+ 全员存活原画 | 承认这是**刻意努力**，不是「正常玩法」（见 [§1.3](#13-与永久死亡的张力关键设计)）。 |
| `bond_char_max_level` | 登峰造极 | challenge | 否 | 任一角色 `level == 20`（转职后高阶上限） | 图鉴：该角色满级立绘 | 长线养成的回报。 |
| `bond_recruit_seraphina` | 夜莺归巢 | natural | 否 | `seraphina_recruited == true`（第 10 章分支二 A 线或特定条件） | 图鉴：塞拉芬娜档案 | 招募隐藏角色。 |
| `bond_support_conversation` | 营火之夜 | natural | 否 | `support_conversations_seen.count >= 1`（任一支援对话触发） | — | 角色关系的温度。 |
| `bond_support_max_pair` | 生死之交 | challenge | 否 | 任一角色对 `support_level == "A"`（最高支援等级） | 称号「知己」+ 该对角色双人立绘 | 深度关系的奖赏。 |
| `bond_kael_vs_viktor_spared` | 不杀 | hidden | 是 | 第 15 章 `kael_solo_vs_viktor == true && viktor_spared == true`（说服条件：莉雅在场 + 持有信物） | 称号「不杀之人」+ 隐藏原画「舅父与外甥」 | 最难达成的和平结局，主题最重（见 [04 角色](04_characters.md) 维克托死亡条件②）。 |
| `bond_companion_fallen` | 沉重的告别 | natural | 否 | `companions_died.count >= 1`（首次有同伴永久死亡） | — | **文案聚焦「告别」而非「失败」**——图鉴解锁该角色遗书（见 [§6.1](#61-角色图鉴characters)）。 |
| `bond_carry_their_memory` | 替他们走下去 | challenge | 否 | `companions_died.count >= 1 && playthrough_completed` | 称号「背负者」 | 死亡之后仍完成战役——emotional mitigation（见 [§1.3](#13-与永久死亡的张力关键设计)）。 |

### 2.4 职业与成长类（6 个）

| id | 中文名 | tier | 隐藏? | 解锁条件（精确判定） | 奖励 | 主题服务点 |
|----|--------|------|-------|----------------------|------|------------|
| `class_first_promotion` | 蜕变 | natural | 否 | `total_promotions >= 1`（首次转职） | 图鉴：转职树 | 养成里程碑。 |
| `class_all_professions_seen` | 武学百家 | challenge | 否 | `professions_seen.count == 13`（见过全部 13 个职业，见 [03](03_professions.md#二职业总表master-table)） | 称号「武学百家」+ 职业图鉴全图 | 鼓励接触所有职业。 |
| `class_mage_kill_50` | 魔导之威 | challenge | 否 | 全局累计 `mage_kills >= 50`（魔法职业击杀） | — | 承认稀缺单位的战略价值。 |
| `class_knight_tank_500` | 移动城墙 | challenge | 否 | 全局累计 `knight_damage_tanked >= 500`（重骑士累计承受伤害） | 称号「铁壁」 | 坦克定位的奖赏。 |
| `class_mage_no_spell_chapter` | 藏锋 | challenge | 否 | 任一战斗章节 `mage_in_party == true && mage_spells_used == 0 && chapter_completed` | 称号「藏锋者」 | **核心主题成就**：法师在场却不施法，呼应「魔法是决定性但稀少」——真正的强者知道何时不出手。 |
| `class_paladin_unlocked` | 圣骑之路 | challenge | 否 | `paladin_unlocked == true`（凯尔或任一骑兵线转职至 paladin，见 [03](03_professions.md#43-圣骑之路王牌流三段)） | 图鉴：圣骑士立绘 | 王牌单位的达成。 |

### 2.5 探索与收集类（8 个）

| id | 中文名 | tier | 隐藏? | 解锁条件（精确判定） | 奖励 | 主题服务点 |
|----|--------|------|-------|----------------------|------|------------|
| `explore_all_legendary_items` | 源脉的馈赠 | challenge | 否 | `legendary_items_acquired.count == 3`（sourceVeinStaff / sourceVeinShard / voidChalice，见 [06](06_items.md#六源脉相关稀有道具专题--呼应魔法稀缺)） | 称号「源脉追寻者」+ 传说道具原画集 | 奖励对「魔法有代价」主题的深度探索。 |
| `explore_all_villages` | 踏遍山河 | challenge | 否 | `villages_visited.count == ALL`（访问所有 `V` 村庄地块） | 图鉴：地点图鉴全图 | 鼓励地图探索。 |
| `explore_all_source_wells` | 源脉的低语 | hidden | 是 | `source_wells_found.count == ALL`（发现所有源井，散布于 [09 关卡](09_levels_and_scenes.md) 各章 `.*` 黑斑处） | 称号「源脉倾听者」+ 隐藏 BGM「源脉之歌」 | 隐藏探索成就，奖励细心玩家。 |
| `explore_ashen_ruins` | 烬海的秘密 | hidden | 是 | 第 4 章 `ashen_ruins_secret_found == true`（在烬海石林找到隐藏废墟，需飞行单位飞越 `M` 石林） | 图鉴：烬海废墟背景故事 | 奖励飞行单位的探索用途（见 [03](03_professions.md#卡片-3天马骑士-pegasusknight--无视地形的奇兵)）。 |
| `explore_codex_100` | 博闻强识 | challenge | 否 | `codex_completion >= 1.0`（全图鉴 100%，见 [§6](#6-图鉴系统codex--gallery)） | 称号「博学者」+ 全图鉴原画 | 完成度驱动（防完美主义牢笼：此成就**不锁任何数值**）。 |
| `explore_mural_4` | 沉睡的预言 | natural | 否 | 第 9 章 `murals_investigated.count == 4`（集齐 4 处壁画，见 [05](05_story_branches.md#3-沉睡之名探索护卫) §8 落点 3） | 图鉴：壁画预言碎片 | 环境叙事的收集。 |
| `explore_environmental_6` | 战地的眼睛 | challenge | 否 | `environmental_storytelling_triggered.count == 6`（触发全部 6 个环境叙事落点，见 [05](05_story_branches.md#8-环境叙事落点environmental-storytelling-technique)） | 称号「见证者」 | 奖励「把世界当作角色」的玩家。 |
| `explore_bgm_unlocked_all` | 战歌典藏 | challenge | 否 | `bgm_unlocked.count == ALL`（解锁全部 BGM，见 [12 音频](12_audio_design.md)） | BGM 播放器全解锁 | 音乐图鉴驱动。 |

### 2.6 挑战与趣味类（12 个，含 2 隐藏）

| id | 中文名 | tier | 隐藏? | 解锁条件（精确判定） | 奖励 | 主题服务点 |
|----|--------|------|-------|----------------------|------|------------|
| `fun_boss_friendly_fire` | 借刀杀人 | hidden | 是 | 单场战斗 `boss_killed_by_ally == true`（让 boss 被其友军误杀，如血祭 AOE 误伤） | 称号「渔翁」+ 趣味原画 | 战术创意的惊喜。 |
| `fun_all_hold_one_turn` | 静默之关 | challenge | 否 | 单场战斗 `units_moved_this_turn == 0 && turn_survived == true`（全员一回合不动且无人死亡） | 称号「不动如山」 | 趣味挑战。 |
| `fun_mp_potion_then_lose` | 白喝了 | challenge | 否 | 任一战斗章节 `mpPotion_used == true && chapter_failed == true` | 称号「乐观主义者」 | **自嘲成就**：用过 mpPotion 还是输了——幽默缓解挫败感（`reinforcement-feedback-systems` mitigation）。 |
| `fun_level_1_clear` | 赤手空拳 | challenge | 否 | 任一战斗章节 `max_party_level == 1 && chapter_completed`（全员 1 级通关某关） | 称号「赤子」 | 极限挑战。 |
| `fun_kael_solo_kill_boss` | 孤勇 | challenge | 否 | 单场战斗 `boss_killed_by == "kael" && kael_solo_in_range == true`（凯尔单挑击杀 boss，无友军相邻支援） | 称号「孤勇者」 | 主角的高光。 |
| `fun_terrain_kill` | 地利之杀 | hidden | 是 | 单场战斗 `enemy_killed_by_terrain == true`（若有推下悬崖/岩浆机制，用地形击杀敌人；若无可标记为「未来扩展」） | 称号「借地者」 | 战术创意（依赖地形击杀机制落地）。 |
| `fun_phoenix_down_clutch` | 起死回生 | natural | 否 | `phoenixDown_used == true && target_survived_to_chapter_end == true` | — | 稀有道具的关键时刻。 |
| `fun_voidChalice_used` | 饮鸩止渴 | challenge | 否 | `voidChalice_used == true`（使用传说道具虚圣杯，承受永久 -2 代价，见 [06](06_items.md#63-虚圣杯-voidchalice传说消耗品--双刃满血)） | 图鉴：虚圣杯背景故事 | 承认「魔法有代价」的抉择。 |
| `fun_weapon_triangle_cycle` | 三角闭环 | challenge | 否 | 单场战斗 `triangle_hits_with_sword >= 1 && triangle_hits_with_lance >= 1 && triangle_hits_with_axe >= 1`（一关内用齐剑/枪/斧三种克制） | 称号「兵器精通」 | 鼓励理解完整武器三角。 |
| `fun_kael_viktor_adjacent_no_attack` | 不忍下手 | hidden | 是 | 第 15 章 `kael_adjacent_to_viktor == true && kael_did_not_attack_viktor_this_turn == true`（凯尔与维克托相邻一回合不攻击） | 图鉴：舅父与外甥的隐藏对话 | 主题最重的隐藏成就——血缘的犹豫（见 [04](04_characters.md) 维克托「他无法下手」）。 |
| `fun_no_retreat_ch11_b` | 绝境不退 | challenge | 否 | 第 11 章分支 B（拒绝血祭）`chapter_completed && no_unit_retreated == true` | 称号「不退者」 | 对应 [05](05_story_branches.md#分支三--第-11-章血祭之野) 最难的义务论选择。 |
| `fun_seen_all_kael_monologues` | 沉默的独白 | challenge | 否 | `kael_monologues_seen.count == ALL`（触发凯尔全部营地独白，见 [04](04_characters.md) §五「核心叙事装置」） | 图鉴：凯尔独白集 | 主角内心戏的完整收集。 |

### 2.7 总表统计

| 分类 | 数量 | natural | challenge | hidden |
|------|------|---------|-----------|--------|
| 剧情进度 | 8 | 4 | 4 | 0 |
| 战斗技巧 | 10 | 5 | 5 | 0 |
| 角色与羁绊 | 8 | 4 | 3 | 1 |
| 职业与成长 | 6 | 1 | 5 | 0 |
| 探索与收集 | 8 | 2 | 4 | 2 |
| 挑战与趣味 | 12 | 2 | 7 | 3 |
| **合计** | **52** | **18** | **28** | **6** |

> **分布自检**：
> - `challenge` 占 54%——偏高，但因 `challenge` 不锁内容（见 [§1.2](#12-反斯金纳箱底线)），不会变成强迫刷数。
> - `hidden` 共 6 个（>要求的 2 个），分布在角色/探索/趣味三类，保证「惊喜感」覆盖多种玩法。
> - 「全员存活」是 challenge 而非 natural，「有同伴死亡」是 challenge + natural 组合——严守 [§1.3](#13-与永久死亡的张力关键设计) 的 permadeath 张力原则。
> - 无任何「杀光/全灭/屠戮」Glory 调性成就。

---

## 3. 重点成就详细设计

选 10 个深入写：覆盖 4 类 + 至少 2 个隐藏 + 至少 2 个主题核心。

### 3.1 `story_ch15_complete` · 你走到了尽头

| 维度 | 内容 |
|------|------|
| **解锁条件（精确判定）** | `ending_reached in ["ashen_king","broken_pact","silent_vein","lone_proof"]`（任一结局达成即解锁，见 [05 剧情分支](05_story_branches.md) §6 四结局）。 |
| **触发时机** | **战后结算**（第 15 章结算页加载时判定）。不在结局动画播放中弹窗，避免破坏反高潮长镜头（`experience-pacing-structure`）。 |
| **弹窗文案** | 标题：「你走到了尽头」 / 副文：「战争没有赢家，只有活下来的人。」 |
| **主题呼应** | **核心主题成就**。文案刻意不用「胜利」「通关」「征服」——用「走到了尽头」承认这是一段没有赢家的旅程。对应 [05](05_story_branches.md) §6 所有结局都是苦涩的。 |
| **埋点数据** | `PlayerProgress.endings_reached[]`（数组，跨周目累计）、`PlayerRecords.current_run.ending`（本局结局 id）。由 `battle.gd` 战斗结束 hook 写入（见 [§9.2](#92-埋点-hook-清单不改代码标注该在哪-hook)）。 |

### 3.2 `battle_physical_only_chapter` · 凡人之力

| 维度 | 内容 |
|------|------|
| **解锁条件（精确判定）** | 任一战斗章节：`chapter_completed == true && magic_skills_used == 0 && chapter_has_mage_in_party == true`（法师在场却整关不施法，且通关）。 |
| **触发时机** | **战后结算**。 |
| **弹窗文案** | 标题：「凡人之力」 / 副文：「你没有呼唤奇迹，他们也活了下来。」 |
| **主题呼应** | **核心主题成就**。呼应 [00 支柱](00_design_pillars.md) §五「魔法稀缺」与 [03 职业](03_professions.md#六魔法职业特别说明核心主题服务) §6.4「服务主题」——奖励玩家「不依赖魔法也能赢」的凡人战术。这是对「魔法万能化」禁区的正面价值观引导。 |
| **埋点数据** | `PlayerRecords.current_run.chapters[chN].magic_skills_used`（本章魔法技能使用计数）、`party_composition`（含 mage 标记）。由 `skill_system.gd` 技能释放 hook 累计、`battle.gd` 战斗结束 hook 判定。 |

### 3.3 `bond_kael_vs_viktor_spared` · 不杀（隐藏）

| 维度 | 内容 |
|------|------|
| **解锁条件（精确判定）** | 第 15 章：`kael_solo_vs_viktor == true && viktor_spared == true && lyra_in_party == true && has_royalSeal == true`（凯尔单挑维克托 + 满足说服条件：莉雅在场 + 持有王室印玺 royalSeal，见 [04 角色](04_characters.md) 维克托死亡条件②、[06 道具](06_items.md) royalSeal）。 |
| **触发时机** | **战后结算**（第 15 章）。玩家在战中不会看到任何提示——这是纯粹的隐藏惊喜。 |
| **弹窗文案** | 标题：「不杀」 / 副文：「有些战争，可以用放下武器结束。虽然很少。」 |
| **主题呼应** | **全作最难达成的和平结局**（见 [04](04_characters.md) 维克托死亡条件②「最难达成的和平结局」）。文案「很少」承认这是例外，不是常态——避免「道德最优解」错觉（`player-psychology-decisions` Triangularity）。 |
| **埋点数据** | `PlayerRecords.current_run.ch15.kael_solo_vs_viktor`、`viktor_spared`、`party_composition`（含 lyra）、`inventory`（含 royalSein）。由 `battle.gd` 第 15 章特殊判定 hook 写入。 |

### 3.4 `bond_carry_their_memory` · 替他们走下去

| 维度 | 内容 |
|------|------|
| **解锁条件（精确判定）** | `companions_died.count >= 1 && playthrough_completed == true`（有同伴永久死亡后，仍通关至任一结局）。 |
| **触发时机** | **战后结算**（第 15 章，与 `story_ch15_complete` 同批弹窗）。 |
| **弹窗文案** | 标题：「替他们走下去」 / 副文：「你失去了他们。但你带着他们的份，走到了这里。」 |
| **主题呼应** | **permadeath emotional mitigation 的核心**（见 [§1.3](#13-与永久死亡的张力关键设计)）。不是「补偿失去」，而是「赋予失去以意义」——把死亡从「失败」重新框定为「背负」（Kuleshov/Framing）。这是本系统对 [04 角色](04_characters.md) §五「核心叙事装置：凯尔独白『我以为我能救所有人』」的系统层呼应。 |
| **埋点数据** | `PlayerProgress.companions_died[]`（跨周目累计的死亡角色 id 列表）、`PlayerRecords.current_run.ending`。 |

### 3.5 `fun_kael_viktor_adjacent_no_attack` · 不忍下手（隐藏）

| 维度 | 内容 |
|------|------|
| **解锁条件（精确判定）** | 第 15 章：某回合 `kael_adjacent_to_viktor == true && kael_did_not_attack_viktor_this_turn == true && turn_ended_normally == true`（凯尔与维克托相邻一回合，选择不攻击并正常结束回合）。 |
| **触发时机** | **战中入队**（不弹窗，只播极轻的「叮」），战后结算页显示。 |
| **弹窗文案** | 标题：「不忍下手」 / 副文：「血缘是最后的犹豫。哪怕只有一回合。」 |
| **主题呼应** | **隐藏成就，主题最重**。对应 [04 角色](04_characters.md) 维克托「面对『敌方』，而是『我妹妹的儿子和一个像我爱过的妻子一样会魔法的女孩』」——玩家在战场上亲手「不忍」，比任何过场都更有力。这是把叙事装置翻译成玩家动作的典范。 |
| **埋点数据** | `PlayerRecords.current_run.ch15.kael_viktor_adjacent_turns`、`kael_attacked_viktor`（bool）。由 `battle.gd` 回合结束 hook 判定。 |

### 3.6 `explore_all_source_wells` · 源脉的低语（隐藏）

| 维度 | 内容 |
|------|------|
| **解锁条件（精确判定）** | `source_wells_found.count == ALL`（发现所有源井，散布于 [09 关卡](09_levels_and_scenes.md) 各章 `.*` 黑斑处，需单位踏入触发调查）。预计 5-7 处，分布于第 4/6/9/12/15 章。 |
| **触发时机** | **战中入队**（最后一处源井发现时）。 |
| **弹窗文案** | 标题：「源脉的低语」 / 副文：「你听到了大地之下的河。它也在流血。」 |
| **主题呼应** | 隐藏探索成就，奖励细心玩家。呼应 [00 支柱](00_design_pillars.md) §五「源脉」世界观与 [05](05_story_branches.md) §8 落点 2「地也会流血」——把环境叙事的收集转化为对「魔法稀缺=大地在流血」的主题共鸣。 |
| **埋点数据** | `PlayerProgress.source_wells_found[]`（跨周目累计的源井 id 列表）。由 `battle.gd` 单位移动结束 hook + `eventTiles` 查表判定（见 [09](09_levels_and_scenes.md) §6.5 eventTag）。 |

### 3.7 `class_mage_no_spell_chapter` · 藏锋

| 维度 | 内容 |
|------|------|
| **解锁条件（精确判定）** | 任一战斗章节：`mage_in_party == true && mage_spells_used == 0 && chapter_completed == true`（法师在场却整关不施法，且通关）。 |
| **触发时机** | **战后结算**。 |
| **弹窗文案** | 标题：「藏锋」 / 副文：「最强的法师，知道何时不出手。」 |
| **主题呼应** | 与 [§3.2](#32-battle_physical_only_chapter--凡人之力) 互补——`凡人之力` 是「整队不用魔法」，`藏锋` 是「法师在场却克制」。两者共同强化「魔法是决定性但稀少的王牌，不是滥用的工具」主题（[03](03_professions.md#六魔法职业特别说明核心主题服务) §6.4）。 |
| **埋点数据** | `PlayerRecords.current_run.chapters[chN].mage_spells_used`、`party_composition`（含 mage 标记）。 |

### 3.8 `fun_mp_potion_then_lose` · 白喝了

| 维度 | 内容 |
|------|------|
| **解锁条件（精确判定）** | 任一战斗章节：`mpPotion_used == true && chapter_failed == true`（用过法力药剂 mpPotion 后，该关仍失败）。 |
| **触发时机** | **Game Over 结算页**（失败也有结算页，见 [§7.3](#73-章节结算页)）。 |
| **弹窗文案** | 标题：「白喝了」 / 副文：「有时候，再多一口魔法也救不了一场必败的仗。」 |
| **主题呼应** | **自嘲成就，挫败感 mitigation**（`reinforcement-feedback-systems`）。用幽默化解「输了还浪费了稀有道具」的双重挫败——让玩家在 Game Over 时也能笑出来。这是对「严肃主题」的必要调剂（避免全程沉重导致弃游）。 |
| **埋点数据** | `PlayerRecords.current_run.chapters[chN].mpPotion_used`、`chapter_failed`。 |

### 3.9 `story_all_endings` · 四种终局

| 维度 | 内容 |
|------|------|
| **解锁条件（精确判定）** | `endings_reached.count == 4`（跨周目累计见过全部 4 个结局：ashen_king / broken_pact / silent_vein / lone_proof，见 [05](05_story_branches.md) §6）。 |
| **触发时机** | **战后结算**（第 4 个结局达成时）。 |
| **弹窗文案** | 标题：「四种终局」 / 副文：「你看过战争的所有面孔。没有一张是赢家的脸。」 |
| **主题呼应** | 鼓励重玩体验「没有完美结局」（[05](05_story_branches.md) §6「无完美结局」）。文案「没有一张是赢家的脸」直接敲击主题。 |
| **埋点数据** | `PlayerProgress.endings_reached[]`（跨周目数组，去重）。 |

### 3.10 `bond_all_survive` · 你守住了每一个人

| 维度 | 内容 |
|------|------|
| **解锁条件（精确判定）** | `playthrough_completed == true && companions_died.count == 0`（通关且全程无同伴死亡）。 |
| **触发时机** | **战后结算**（第 15 章）。 |
| **弹窗文案** | 标题：「你守住了每一个人」 / 副文：「这不是理所当然的结果。是你一回合一回合换来的。」 |
| **主题呼应** | **challenge 向，非 natural**（见 [§1.3](#13-与永久死亡的张力关键设计)）。文案「不是理所当然」明确承认这是**刻意努力**，避免让有死亡的玩家觉得「玩错了」。与 `bond_carry_their_memory`（替他们走下去）形成对照——两条路都被尊重。 |
| **埋点数据** | `PlayerRecords.current_run.companions_died`（本局死亡列表）、`ending`。 |

---

## 4. 玩家进度记录系统（PlayerRecords）

**比成就更细的统计档案**。成就只记「是否达成」，PlayerRecords 记「怎么达成的、达成了多少、用了什么风格」。这是玩家回顾自己战役的「日记本」。

### 4.1 数据结构总览

`PlayerRecords` 分四块：

| 模块 | 内容 | 用途 |
|------|------|------|
| **通关进度** `chapter_progress` | 每章完成状态、用时、回合数、单位存活、分支选择路径 | 章节解锁判定（见 [§5](#5-章节解锁机制)）+ 重玩回顾 |
| **全局统计** `global_stats` | 总击杀、总受伤、技能使用排行、道具使用、法师 MP 总消耗、最长连击、暴击率 | 成就判定 + 玩家自我审视 |
| **角色档案** `character_archives` | 每个角色的等级、击杀数、存活状态、关键事件标记 | 角色图鉴数据源（见 [§6.1](#61-角色图鉴characters)） |
| **章节评分** `chapter_ranks` | 每章 S/A/B/C/D 评级 | 可重玩刷分 |

### 4.2 `user://player_records.json` JSON Schema

> **存储路径**：`user://player_records.json`（单周目当前进度）+ `user://player_progress.json`（跨周目累计，见 [§9](#9-数据架构与落地godot-实现)）。本节是前者。
> **持久化模式**：严格对齐 `level_storage.gd` 的 FileAccess + JSON.stringify（见 L47-53）。每个 JSON 文件一个根对象。

```jsonc
// user://player_records.json（单周目当前进度）
{
  "schema_version": 1,
  "run_id": "run_1718000000_abc123",      // 单次战役的唯一 id（启动新游戏时生成）
  "created_at": 1718000000,                // Unix 时间戳（对齐 level_storage 的 createdAt）
  "last_updated": 1718001234,

  // —— 1. 通关进度 ——
  "chapter_progress": {
    "ch1":  { "completed": true, "rank": "S", "turn_count": 5, "time_sec": 480, "survivors": ["kael","mentor"], "path_taken": null },
    "ch2":  { "completed": true, "rank": "A", "turn_count": 8, "time_sec": 620, "survivors": ["kael","mentor","hilde","alwyn"], "path_taken": null },
    // ...
    "ch7":  { "completed": true, "rank": "B", "turn_count": null, "time_sec": 60, "survivors": [...], "path_taken": "A" },  // 抉择关：path_taken = "A"/"B"
    "ch15": { "completed": true, "rank": "S", "turn_count": 12, "time_sec": 1500, "survivors": [...], "ending": "broken_pact" }
  },

  // —— 2. 全局统计 ——
  "global_stats": {
    "total_kills": 147,
    "total_damage_dealt": 4280,
    "total_damage_taken": 2150,
    "total_crits": 38,
    "total_doubles": 52,                   // 追击次数
    "crit_rate": 0.18,                     // 暴击率 = total_crits / total_attacks
    "longest_combo": 3,                    // 最长连击（同回合连续击杀）
    "skill_usage": {                       // 技能使用次数排行
      "fireball": 12, "heal": 28, "guard": 8, "infernoBlade": 3
    },
    "item_usage": {                        // 道具使用次数
      "hpPotion": 14, "mpPotion": 5, "phoenixDown": 1
    },
    "mage_mp_spent": 180,                  // 法师 MP 总消耗（呼应魔法稀缺主题）
    "weapon_triangle_hits": 45,            // 武器三角克制命中数
    "terrain_avoid_total": 320,            // 地形闪避累计加成
    "chapters_no_damage": ["ch3"],         // 无伤通关章节列表
    "chapters_no_items": ["ch2"],          // 零道具通关章节列表
    "chapters_physical_only": [],          // 纯物理通关章节列表
    "environmental_storytelling_triggered": ["ch4_village","ch6_blackscar"]  // 环境叙事触发记录
  },

  // —— 3. 角色档案 ——
  "character_archives": {
    "kael":  { "level": 18, "class": "paladin", "kills": 22, "damage_tanked": 480, "status": "alive", "key_events": ["promoted_to_paladin","ch13_spared_mentor"] },
    "lyra":  { "level": 15, "class": "sage", "kills": 14, "damage_tanked": 90, "status": "alive", "key_events": ["promoted_to_sage","revealed_source"] },
    "hilde": { "level": 12, "class": "knight", "kills": 18, "damage_tanked": 720, "status": "fallen", "key_events": ["ch11_fell_in_battle"], "fallen_chapter": "ch11" },
    // ... 其余角色
    "viktor": { "level": 20, "class": "knight_boss", "kills": 0, "status": "spared", "key_events": ["ch15_spared_by_kael"] }  // 反派也记录
  },

  // —— 4. 章节评分明细（可选，默认由 chapter_progress.rank 派生）——
  "chapter_ranks": {
    "ch1": { "rank": "S", "score_breakdown": { "turn": 95, "survival": 100, "economy": 90 }, "total_score": 285 }
  }
}
```

### 4.3 章节评分算法（S/A/B/C/D）

每章战斗结束后，基于三个维度评分，总分映射到等级：

| 维度 | 权重 | 满分条件 | 扣分规则 |
|------|------|----------|----------|
| **回合数 `turn`** | 35% | `turn_count <= par_turns`（每章有基准回合数，如 ch1=5, ch6=10） | 每超 1 回合扣 10 分，扣完为止 |
| **存活 `survival`** | 40% | `units_lost == 0`（本章无人倒下） | 每倒 1 人扣 25 分（permadeath 主题：存活权重最高） |
| **经济 `economy`** | 25% | `items_used == 0`（零道具） | 每用 1 个道具扣 8 分；mpPotion 双倍扣分（魔法稀缺主题加权） |

| 总分 | 等级 | 含义 |
|------|------|------|
| ≥ 270 | **S** | 完美战役 |
| 240-269 | **A** | 优秀 |
| 200-239 | **B** | 合格 |
| 150-199 | **C** | 勉强 |
| < 150 | **D** | 惨胜 |

> **设计意图**：评分**可重玩刷分**（玩家可回看每章历史最佳评分），但**评分不锁任何内容**（防完美主义牢笼，见 [§1.2](#12-反斯金纳箱底线)）。评分只是「自我挑战」的镜子，不是「解锁门」。
> **主题加权**：存活权重 40% 最高（permadeath）、mpPotion 双倍扣分（魔法稀缺）——评分算法本身也在服务主题。

---

## 5. 章节解锁机制（对齐 level_select.gd 现状缺口）

### 5.1 现状缺口

| 文件 | 现状 | 缺口 |
|------|------|------|
| `godot/scripts/scenes/level_select.gd` | 从 `LevelStorage.load_levels()` 读**编辑器关卡**列表，所有关卡可见（L14, L57-63） | **无章节解锁/通关标记**；主线 15 章与编辑器自制关卡混在一起 |
| `godot/scripts/data/chapter_data.gd` | 只有 `chapter_1()`（L49-71），无章节序列 | **无 ch2-ch15 的章节定义**，无章节间解锁逻辑 |
| `godot/scripts/scenes/title.gd` | 「开始游戏」直接进 LevelSelect（L58-61） | **无「继续战役」「新游戏」「章节选择」分流** |

### 5.2 解锁规则设计

**主线 15 章线性解锁**（对齐 [05 剧情分支](05_story_branches.md) §3）：

| 章 | 解锁条件 | 解锁后续 |
|----|----------|----------|
| ch1 | 新游戏默认解锁 | 完成 ch1 → 解锁 ch2 |
| ch2 | ch1 completed | → ch3 |
| ch3 | ch2 completed | → ch4 |
| ch4 | ch3 completed | → ch5 |
| ch5 | ch4 completed | → ch6 |
| ch6 | ch5 completed | → ch7 |
| ch7（分支一） | ch6 completed | 抉择后 → ch8（无论 A/B） |
| ch8 | ch7 completed | → ch9 |
| ch9 | ch8 completed | → ch10 |
| ch10（分支二） | ch9 completed | 抉择后 → ch11（无论 A/B） |
| ch11（分支三） | ch10 completed | 抉择后 → ch12（无论 A/B） |
| ch12 | ch11 completed | → ch13 |
| ch13 | ch12 completed | → ch14 |
| ch14 | ch13 completed | → ch15 |
| ch15 | ch14 completed | 通关 → 结局 |

**分支章节的解锁差异**：

| 分支章 | A 线解锁 | B 线解锁 |
|--------|----------|----------|
| ch7 | 无后续差异（都进 ch8） | 同 |
| ch10 | A 线：旧友入队 → 影响 ch14 敌方编成 | B 线：旧友死/敌 → 影响 ch14 |
| ch11 | A 线（血祭）：锁定结局一 ashen_king；ch12 难度下降 | B 线（拒绝）：解锁结局二/三路径；ch12 难度上升；解锁支线 S5 |

**支线章节解锁条件**（对齐 [09 关卡](09_levels_and_scenes.md) §四）：

| 支线 | 解锁条件 |
|------|----------|
| S1 净魔夜 | ch8 营地，与王女对话（若王女存活） |
| S2 石林拾遗 | ch9 完成后，地图自由探索 |
| S3 断剑墙 | ch6 完成后，老兵在队 |
| S4 走私客 | ch13 前后，碎月声望 ≥ 中立 |
| S5 灰潮撤离 | ch11 分支 B（拒绝血祭）后，**B 线限定** |

### 5.3 数据结构

```jsonc
// user://player_progress.json（跨周目累计 + 章节解锁状态）
{
  "schema_version": 1,
  "chapters": {
    "ch1":  { "unlocked": true,  "completed": true,  "rank": "S", "path_taken": null },
    "ch2":  { "unlocked": true,  "completed": true,  "rank": "A", "path_taken": null },
    // ...
    "ch7":  { "unlocked": true,  "completed": true,  "rank": "B", "path_taken": "A" },  // 分支关记 path
    "ch15": { "unlocked": true,  "completed": false, "rank": null, "path_taken": null },
    "ch_S1":{ "unlocked": true,  "completed": true,  "rank": "A" },                     // 支线
    "ch_S5":{ "unlocked": false, "completed": false, "rank": null }                      // B 线限定，未解锁
  },
  "endings_reached": ["broken_pact"],           // 跨周目累计结局
  "achievements_unlocked": ["story_ch1_complete", ...],  // 跨周目成就 id 列表
  "codex_seen": { "characters": [...], "professions": [...], ... },  // 图鉴（见 §6）
  "titles_unlocked": ["走过战争的人"],           // 称号
  "new_game_plus_unlocked": false,               // 新游戏+解锁（见 §8.2）
  "selected_title": null                          // 当前展示称号
}
```

### 5.4 `chapter_unlock.gd` 设计草图（autoload 单例）

> **对齐 level_storage.gd 风格**：RefCounted 静态方法 + FileAccess + JSON。建议注册为 autoload 单例 `ChapterUnlock`。

```gdscript
## core/chapter_unlock.gd — 章节解锁状态管理（autoload 单例）
## 对齐 level_storage.gd 的 FileAccess + JSON 持久化模式。
## 存储路径：user://player_progress.json

extends Node

const PROGRESS_PATH := "user://player_progress.json"
const SCHEMA_VERSION := 1

# 章节依赖表（id → 解锁所需的前置章节 id）
const CHAPTER_PREREQ := {
    &"ch1":  [],       &"ch2":  [&"ch1"],  &"ch3":  [&"ch2"],
    &"ch4":  [&"ch3"], &"ch5":  [&"ch4"],  &"ch6":  [&"ch5"],
    &"ch7":  [&"ch6"], &"ch8":  [&"ch7"],  &"ch9":  [&"ch8"],
    &"ch10": [&"ch9"], &"ch11": [&"ch10"], &"ch12": [&"ch11"],
    &"ch13": [&"ch12"],&"ch14": [&"ch13"], &"ch15": [&"ch14"],
}
# 支线解锁条件（id → 条件函数名，由 is_sidequest_unlocked 实现）
const SIDEQUEST_COND := {
    &"ch_S1": "ch8_done_and_seraphina_alive",
    &"ch_S2": "ch9_done",
    &"ch_S3": "ch6_done_and_alwyn_in_party",
    &"ch_S4": "ch13_near_and_freeport_neutral",
    &"ch_S5": "ch11_b_path",
}

var _data: Dictionary = {}   # 内存中的进度数据

func _ready() -> void:
    _load()

## 读取进度
func _load() -> void:
    if not FileAccess.file_exists(PROGRESS_PATH):
        _data = _default_data()
        _save()
        return
    var f := FileAccess.open(PROGRESS_PATH, FileAccess.READ)
    if f == null:
        _data = _default_data()
        return
    var json := JSON.new()
    if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
        _data = json.data
    else:
        _data = _default_data()

## 写入进度
func _save() -> void:
    _data["last_updated"] = Time.get_unix_time_from_system()
    var f := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify(_data))
        f.close()

func _default_data() -> Dictionary:
    var chapters := {}
    for cid in CHAPTER_PREREQ.keys():
        chapters[String(cid)] = { "unlocked": (cid == &"ch1"), "completed": false, "rank": "", "path_taken": "" }
    return {
        "schema_version": SCHEMA_VERSION,
        "chapters": chapters,
        "endings_reached": [],
        "achievements_unlocked": [],
        "codex_seen": {},
        "titles_unlocked": [],
        "new_game_plus_unlocked": false,
        "selected_title": null,
    }

## 章节是否解锁
func is_chapter_unlocked(chapter_id: String) -> bool:
    var ch: Dictionary = _data.get("chapters", {}).get(chapter_id, {})
    if ch.is_empty():
        return false
    return bool(ch.get("unlocked", false))

## 章节是否完成
func is_chapter_completed(chapter_id: String) -> bool:
    return bool(_data.get("chapters", {}).get(chapter_id, {}).get("completed", false))

## 完成章节（写入完成状态 + 评分 + 解锁下一章）
func complete_chapter(chapter_id: String, rank: String, path_taken: String = "") -> void:
    var ch: Dictionary = _data.get("chapters", {}).get(chapter_id, {})
    ch["completed"] = true
    ch["rank"] = rank
    if path_taken != "":
        ch["path_taken"] = path_taken
    _data["chapters"][chapter_id] = ch
    # 解锁下一章
    for next_id in _get_next_chapters(chapter_id):
        _data["chapters"][next_id]["unlocked"] = true
    _save()

## 递归查「谁以本章为前置」
func _get_next_chapters(chapter_id: String) -> Array:
    var out: Array = []
    for cid in CHAPTER_PREREQ.keys():
        if chapter_id in CHAPTER_PREREQ[cid]:
            out.push_back(String(cid))
    return out

## 新游戏：重置章节进度（保留跨周目成就/结局/图鉴）
func start_new_game() -> void:
    var preserved := {
        "endings_reached": _data.get("endings_reached", []),
        "achievements_unlocked": _data.get("achievements_unlocked", []),
        "codex_seen": _data.get("codex_seen", {}),
        "titles_unlocked": _data.get("titles_unlocked", []),
        "new_game_plus_unlocked": _data.get("new_game_plus_unlocked", false),
    }
    _data = _default_data()
    _data.merge(preserved, true)
    _save()
```

---

## 6. 图鉴系统（Codex / Gallery）

图鉴是「见过即记录」的收集档案，与成就（达成条件）和 PlayerRecords（统计数据）三者互补。

### 6.1 角色图鉴（Characters）

| 条目类型 | 解锁条件 | 内容 |
|----------|----------|------|
| **见过** `encountered` | 战场上遭遇过（敌方或友方） | 姓名 + 立绘（剪影） + 国家 + 职业基础信息 |
| **招募** `recruited` | 加入玩家队伍 | 完整立绘 + 背景故事 + 性格 + 战斗定位 |
| **阵亡** `fallen` | 永久死亡（见 [04 角色](04_characters.md) §五） | 解锁**遗书/最后独白** + 阵亡章节标记 + 死亡条件说明 |
| **反派** `antagonist` | 遭遇敌方统帅（如维克托） | 立绘 + 立场说明（**不脸谱化**，见 [04](04_characters.md) §〇）+ 「他为何而战」独白 |

**数据存储**：`PlayerProgress.codex_seen.characters[]`（跨周目累计的角色 id 列表，含状态标记）。

```jsonc
"codex_seen": {
  "characters": {
    "kael":   { "encountered": true, "recruited": true, "fallen": false, "fallen_chapter": null },
    "lyra":   { "encountered": true, "recruited": true, "fallen": false, "fallen_chapter": null },
    "hilde":  { "encountered": true, "recruited": true, "fallen": true,  "fallen_chapter": "ch11" },
    "viktor": { "encountered": true, "recruited": false, "fallen": false, "antagonist": true }
  }
}
```

### 6.2 职业图鉴（Professions）

| 条目 | 解锁条件 | 内容 |
|------|----------|------|
| 职业条目（13 个，见 [03 职业](03_professions.md#二职业总表master-table)） | 队伍中**出现过**该职业的单位（玩家或敌方） | 职业立绘 + 属性范围 + 武器类型 + 克制关系 + 转职树 |

**数据存储**：`PlayerProgress.codex_seen.professions[]`。

### 6.3 物品图鉴（Items）

| 条目 | 解锁条件 | 内容 |
|------|----------|------|
| 道具条目（25 个，见 [06 道具](06_items.md#三道具分类总表25-个)） | **获得过**该道具（背包曾持有） | 道具图标 + 名称 + 效果 + 稀有度 + 获取方式提示 |

**数据存储**：`PlayerProgress.codex_seen.items[]`。

### 6.4 敌人图鉴（Enemies）

| 条目 | 解锁条件 | 内容 |
|------|----------|------|
| 敌方单位条目 | 战场上**遭遇过**该敌方单位类型（按 profession + level 分档） | 立绘 + 属性 + 出现章节 + 战术提示 |

**数据存储**：`PlayerProgress.codex_seen.enemies[]`（按 `enemy_type_id` 去重）。

### 6.5 地点图鉴（Locations）

| 条目 | 解锁条件 | 内容 |
|------|----------|------|
| 地点条目（8 个，见 [01 世界观](01_worldview.md) §九、[09 关卡](09_levels_and_scenes.md) §三） | **到过**该地点的关卡 | 地点全景图 + 环境叙事签名 + 适合关卡类型 |

**数据存储**：`PlayerProgress.codex_seen.locations[]`。

### 6.6 音乐图鉴（Music）

| 条目 | 解锁条件 | 内容 |
|------|----------|------|
| BGM 条目（见 [12 音频](12_audio_design.md)） | **听过**该 BGM（对应章节/场景播放过） | BGM 名称 + 作曲风格说明 + **可重听**（播放器） |

**数据存储**：`PlayerProgress.codex_seen.music[]`。对应成就 `explore_bgm_unlocked_all`。

### 6.7 图鉴完成度

图鉴总完成度 = (所有 6 类已解锁条目数) / (所有 6 类总条目数)。对应成就 `explore_codex_100`（**不锁数值**，见 [§1.2](#12-反斯金纳箱底线)）。

---

## 7. 成就 UI 设计

### 7.1 成就大厅界面

**主菜单新增「记录」入口**（对齐 `title.gd` 现状：目前只有「开始游戏」「地图编辑器」两按钮，见 L36-46。建议在两按钮之间或下方加第 3 个按钮「记录 / Records」）。

**布局**：成就网格 + 完成度百分比 + 分类筛选 + 标签页切换（成就 / 图鉴 / 战役记录 / 称号）。

```
┌─────────────────────────────────────────────────────────────────────┐
│  记 录 · RECORDS                                          [X 关闭]   │
│  ─────────────────────────────────────────────────────────────────  │
│  [成就] [图鉴] [战役记录] [称号]           完成度: 23/52 (44%)      │
│  ─────────────────────────────────────────────────────────────────  │
│  筛选: [全部] [剧情] [战斗] [角色] [职业] [探索] [趣味] [已解锁]   │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐               │
│  │ ★ 战火   │ │ ★ 致命   │ │ ☆ 凡人   │ │ ???      │               │
│  │   初临   │ │   一击   │ │   之力   │ │ (隐藏)   │               │
│  │ 剧情进度 │ │ 战斗技巧 │ │ 战斗技巧 │ │ 角色??   │               │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘               │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐               │
│  │ ★ 蜕变   │ │ ☆ 守住   │ │ ???      │ │ ☆ 白喝了 │               │
│  │          │ │   每个人 │ │ (隐藏)   │ │          │               │
│  │ 职业成长 │ │ 角色羁绊 │ │ 探索??   │ │ 挑战趣味 │               │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘               │
│  ...                                                                │
│  ─────────────────────────────────────────────────────────────────  │
│  当前称号: [走过战争的人 ▼]                                         │
└─────────────────────────────────────────────────────────────────────┘
```

> **图标约定**：★ = 已解锁（亮色立绘）；☆ = challenge 向未解锁（灰显但条件可见）；??? = hidden 未解锁（完全隐藏条件）。
> **配色**：严格沿用 [10 UI/UX](10_ui_ux.md) §1.2 的 10 色配色表（暗金 `#C9A227` 标题、铁灰 `#2B2B3A` 面板底、羊皮 `#E8D9B0` 正文）。

### 7.2 解锁弹窗（非侵入式）

**战中**：完全不弹窗。`unlock_achievement()` 只写 JSON + 播一个极轻的「叮」音效（见 [12 音频](12_audio_design.md)），成入「待展示队列」。**战斗结算页**批量显示（见 [§7.3](#73-章节结算页)）。

**主菜单/非战斗场景**：右下角滑入式 toast，3 秒自动消失。

```
                                              战斗中: 不显示
┌────────────────────────────────┐
│  ★ 成就解锁                    │ ← 右下角滑入，3 秒后滑出
│  ─────────────────────────     │
│  凡人之力                      │
│  你没有呼唤奇迹，他们也活了下来 │
└────────────────────────────────┘
```

> **对齐 10_ui_ux 的非打扰原则**：成就是「事后反馈」，不是「即时反馈」。即时反馈（暴击数字、命中动画）由 SFX/粒子承担（见 [reinforcement-feedback-systems](reinforcement-feedback-systems.md) 区分）；成就是长效反馈，必须等心流窗口（7-10 分钟，`experience-pacing-structure`）结束后再结算。

### 7.3 章节结算页

战斗胜利/失败后，显示结算页（**不是**直接回主菜单）：

```
┌─────────────────────────────────────────────────────────────────────┐
│  第 6 章 · 河谷围城 · 结算                                          │
│  ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│       评 级 :  [ S ]   完美战役                                     │
│                                                                     │
│       回合数: 6/10 (par)     ████████████░░  95                     │
│       存  活: 8/8            ████████████████ 100                    │
│       经  济: 1 道具         █████████████░░░  92                    │
│       总  分: 287                                                  │
│                                                                     │
│  ─────────────────────────────────────────────────────────────────  │
│  新解锁:                                                             │
│    ★ 闪电破城  (战斗技巧)   —— 第 6 章 6 回合内通关                 │
│    ★ 借刀杀人  (隐藏·趣味)  —— 让 boss 被友军误杀                   │
│  ─────────────────────────────────────────────────────────────────  │
│  图鉴新增:  黑铁要塞(地点) · 要塞司令(敌人) · 银弓(物品)            │
│  ─────────────────────────────────────────────────────────────────  │
│            [ 继续战役 ]   [ 回顾本章 ]   [ 返回主菜单 ]             │
└─────────────────────────────────────────────────────────────────────┘
```

> **失败结算页**：同样显示，但评级为 D，且可能触发 `fun_mp_potion_then_lose`（白喝了）等自嘲成就——用幽默缓解挫败（见 [§3.8](#38-fun_mp_potion_then_lose--白喝了)）。

---

## 8. 奖励设计（轻量，不破坏平衡）

### 8.1 奖励原则

| 原则 | 说明 | 引用原理 |
|------|------|----------|
| **以展示性/收藏性为主** | 称号、立绘皮肤、图鉴条目、BGM 解锁、原画集——**纯收藏**，不影响战斗数值。 | `character-optimization-design`（防 min/max：成就奖励不能成为 build 的一部分） |
| **避免数值奖励** | **禁止**奖励金币、经验、稀有道具、属性点——否则玩家会「为奖励而刷成就」，破坏平衡与主题。 | `player-psychology-decisions`（避免完美主义牢笼） |
| **少量新游戏+** | 通关后二周目解锁**新内容**（新职业/新道具/难度选项），不是数值强化。 | 鼓励重玩，不是「变强碾压」（见 [§8.2](#82-新游戏-轻量)） |

### 8.2 新游戏+（轻量）

通关任一结局后，`new_game_plus_unlocked = true`。二周目可解锁：

| 解锁项 | 来源 | 说明 |
|--------|------|------|
| **新职业**：剑豪 `swordmaster` 可作为初始职业之一 | [03 职业](03_professions.md#41-剑之路技巧流) | 二周目玩家已有基础，可尝试高技巧职业 |
| **新道具**：源脉法杖 `sourceVeinStaff` 在第 8 章营地商店有售 | [06 道具](06_items.md#61-源脉法杖-sourceveinstaff传说装备) | 传说道具提前体验（但仍带永久代价） |
| **难度选项**：噩梦难度（敌方属性 +20%、增援 +1 波） | — | 给 challenge 向玩家 |
| **称号系统**：可在主菜单选一个已解锁称号展示 | 见 [§8.3](#83-称号系统) | 纯展示 |

> **禁止**：二周目继承等级/金币/道具库存——那会变成「碾压一周目」，破坏主题与平衡。

### 8.3 称号系统

玩家在主菜单「记录 → 称号」页可选择一个已解锁称号，显示在：
- 主菜单玩家头像旁
- 多人/云存档（若实现）的玩家名片
- 战役结算页角落

称号列表（示例，由成就解锁）：

| 称号 | 解锁来源 |
|------|----------|
| 走过战争的人 | `story_ch15_complete` |
| 命运的见证者 | `story_all_endings` |
| 守护者 | `bond_all_survive` |
| 背负者 | `bond_carry_their_memory` |
| 凡人之力 | `battle_physical_only_chapter` |
| 藏锋者 | `class_mage_no_spell_chapter` |
| 不杀之人 | `bond_kael_vs_viktor_spared`（隐藏） |
| 源脉倾听者 | `explore_all_source_wells`（隐藏） |
| 战役见证者 | 全成就 100% 完成 |
| 乐观主义者 | `fun_mp_potion_then_lose`（自嘲） |

---

## 9. 数据架构与落地（Godot 实现）

### 9.1 PlayerProgress autoload 单例

> **对齐 level_storage.gd**：RefCounted/Node + FileAccess + JSON。建议注册为 autoload 单例 `PlayerProgress`，与 `ChapterUnlock`（[§5.4](#54-chapter_unlockgd-设计草图autoload-单例)）协同。

```gdscript
## core/player_progress.gd — 玩家进度总管（autoload 单例）
## 管理成就解锁 + 图鉴 + 跨周目累计 + 称号。
## 存储路径：user://player_progress.json（跨周目）
##           user://player_records.json（单周目详细统计，见 §4.2）

extends Node

const PROGRESS_PATH := "user://player_progress.json"
const RECORDS_PATH := "user://player_records.json"

# 成就定义表（从 res://data/achievements.json 加载，见 §9.3）
var achievements_def: Dictionary = {}
var _progress: Dictionary = {}    # 跨周目进度
var _records: Dictionary = {}     # 单周目记录
var _pending_unlocks: Array = []  # 战中待展示的成就队列

func _ready() -> void:
    _load_achievements_def()
    _load_progress()
    _load_records()

## —— 成就 API ——
func unlock_achievement(id: String) -> bool:
    if _is_unlocked(id):
        return false
    # 校验 id 合法
    if not achievements_def.has(id):
        push_warning("Unknown achievement: %s" % id)
        return false
    _progress["achievements_unlocked"].append(id)
    _pending_unlocks.append(id)
    # 播极轻「叮」音效（不弹窗）
    _play_unlock_sfx()
    _save_progress()
    # 解锁关联奖励（称号/图鉴/新游戏+）
    _grant_rewards(id)
    return true

func _is_unlocked(id: String) -> bool:
    return id in _progress.get("achievements_unlocked", [])

func get_pending_unlocks() -> Array:
    var out := _pending_unlocks.duplicate()
    _pending_unlocks.clear()
    return out

## —— 统计 API（写入 PlayerRecords）——
func record_stat(key: String, value, chapter_id: String = "") -> void:
    # 累加全局统计，如 total_kills += 1
    var stats: Dictionary = _records.get("global_stats", {})
    if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
        stats[key] = stats.get(key, 0) + value
    _records["global_stats"] = stats
    _save_records()

func record_chapter_complete(chapter_id: String, rank: String, turn_count: int, survivors: Array, path_taken: String = "") -> void:
    var ch: Dictionary = _records.get("chapter_progress", {}).get(chapter_id, {})
    ch["completed"] = true
    ch["rank"] = rank
    ch["turn_count"] = turn_count
    ch["survivors"] = survivors
    if path_taken != "":
        ch["path_taken"] = path_taken
    _records["chapter_progress"][chapter_id] = ch
    _save_records()
    # 联动 ChapterUnlock
    ChapterUnlock.complete_chapter(chapter_id, rank, path_taken)

## —— 图鉴 API ——
func codex_add(category: String, entry_id: String, extra: Dictionary = {}) -> void:
    var codex: Dictionary = _progress.get("codex_seen", {})
    var cat: Dictionary = codex.get(category, {})
    cat[entry_id] = extra if not extra.is_empty() else { "seen": true }
    codex[category] = cat
    _progress["codex_seen"] = codex
    _save_progress()

## —— 持久化（对齐 level_storage.gd 的 FileAccess 模式）——
func _load_progress() -> void:
    if not FileAccess.file_exists(PROGRESS_PATH):
        _progress = _default_progress()
        _save_progress()
        return
    var f := FileAccess.open(PROGRESS_PATH, FileAccess.READ)
    if f and JSON.new().parse(f.get_as_text()) == OK:
        _progress = JSON.new().data
    else:
        _progress = _default_progress()

func _save_progress() -> void:
    var f := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
    if f:
        f.store_string(JSON.stringify(_progress))
        f.close()

func _default_progress() -> Dictionary:
    return {
        "schema_version": 1,
        "endings_reached": [],
        "achievements_unlocked": [],
        "codex_seen": {},
        "titles_unlocked": [],
        "new_game_plus_unlocked": false,
        "selected_title": null,
    }
# _load_records / _save_records / _default_records 同理（结构见 §4.2）
```

### 9.2 埋点 hook 清单（不改代码，标注该在哪 hook）

> 本节是「实现待办清单」——标注现有代码的哪些位置应该插入 `PlayerProgress.record_*()` 调用，**不修改现有逻辑**，只在关键节点加埋点。

| 现有文件 | 现有函数/位置 | 应加的 hook | 写入的数据 |
|----------|--------------|-------------|------------|
| `godot/scripts/scenes/battle.gd` | 战斗结束（胜利/失败判定） | `PlayerProgress.record_chapter_complete(chapter_id, rank, turn_count, survivors, path_taken)` + 判定章节成就（如 `battle_speedrun_ch6`、`battle_no_damage_chapter`） | 章节完成状态、评分、存活、分支选择 |
| `godot/scripts/core/combat_system.gd` | 伤害结算（`resolve_attack` 或类似） | `PlayerProgress.record_stat("total_kills", 1)`（击杀时）、`record_stat("total_crits", 1)`（暴击时）、`record_stat("total_doubles", 1)`（追击时） | 击杀数、暴击数、追击数 |
| `godot/scripts/core/skill_system.gd` | 技能释放（`use_skill` 或类似） | `PlayerProgress.record_skill_used(skill_id, mp_spent)` + 若为魔法技能累计 `mage_mp_spent` + 判定 `class_mage_no_spell_chapter`（章末检查） | 技能使用次数、MP 消耗 |
| `godot/scripts/core/item_system.gd`（若存在）或 `battle.gd` 道具使用 | 道具使用 | `PlayerProgress.record_item_used(item_id)` + 判定 `fun_mp_potion_then_lose`（章末若失败） | 道具使用次数 |
| 角色升级/转职逻辑 | 升级/转职函数 | `PlayerProgress.record_promotion(char_id, new_class)` + 判定 `class_first_promotion` | 转职记录 |
| 角色死亡逻辑（permadeath） | HP 归零且无复活 | `PlayerProgress.record_companion_fallen(char_id, chapter_id)` + 判定 `bond_companion_fallen` + 图鉴标记 `fallen` | 死亡角色、章节 |
| `godot/scripts/scenes/battle.gd` | 单位移动结束（查 eventTiles） | `PlayerProgress.codex_add("locations", location_id)` + 源井/壁画/环境叙事判定 | 地点图鉴、探索成就 |
| `godot/scripts/scenes/title.gd` | `_ready`（L9） | 新增「记录」按钮，连接到 `AchievementsScene.tscn`（新建） | — |

### 9.3 `res://data/achievements.json` 数据表

> 建议把 [§2 总表](#2-成就分类与总表) 的 52 个成就写成 JSON 数据表，运行时由 `PlayerProgress._load_achievements_def()` 加载。**不硬编码在 GDScript 里**，便于策划增删。结构示例：

```jsonc
// res://data/achievements.json
{
  "story_ch1_complete": {
    "name": "战火初临", "category": "story", "tier": "natural", "hidden": false,
    "desc": "完成第 1 章", "reward": { "type": "none" },
    "check": "chapter_completed == 'ch1'"
  },
  "battle_physical_only_chapter": {
    "name": "凡人之力", "category": "combat", "tier": "challenge", "hidden": false,
    "desc": "法师在场却整关不施法通关", "reward": { "type": "title", "id": "凡人之力" },
    "check": "any_chapter: chapter_completed && magic_skills_used == 0 && chapter_has_mage"
  }
  // ... 其余 50 个
}
```

> `check` 字段是**声明式判定表达式**，由 `PlayerProgress` 的判定引擎解释执行（避免散落在各处 if-else）。这是从「硬编码成就」到「数据驱动成就」的关键架构决策。

### 9.4 多存档槽设计（可选，给建议）

| 方案 | 优点 | 缺点 | 建议 |
|------|------|------|------|
| **单存档**（当前 level_storage 模式） | 实现最简；跨周目成就/图鉴天然共享；玩家不会「丢失某个存档的进度」 | 无法同时保留多个战役进度；家人共用设备会互相覆盖 | **MVP 首选** |
| **3 存档槽** | 可同时进行多个战役（不同结局路线）；家人/朋友可分槽 | 成就/图鉴是否跨槽共享？若共享则复杂；若不共享则失去「跨周目累计」价值 | **v2 扩展**：战役进度分槽（`user://save_slot_1/records.json`），但**成就/图鉴/称号跨槽共享**（`user://player_progress.json` 全局） |

> **取舍建议**：MVP 用单存档（对齐现有 level_storage 单文件模式，实现成本最低）。多存档作为 v2 扩展，且**成就必须跨槽共享**——否则 `story_all_endings`（需 4 周目）会变成地狱。

---

## 10. 防作弊与边界

### 10.1 单机本地解锁的取舍

本作是**单机游戏**，成就在本地解锁，**不做服务器校验**。

| 取舍维度 | 决定 | 理由 |
|----------|------|------|
| 服务器校验 | **不做** | 单机游戏无在线对战，成就不影响他人；服务器成本高、维护重；玩家修改自己的存档是「自己的事」 |
| 成就展示 | 本地 | 不接入 Steam/PSN 等平台成就（MVP 阶段）；未来若上架可对接平台 SDK |

### 10.2 防止「修改 JSON 解锁全部」

| 方案 | 效果 | 取舍 |
|------|------|------|
| **接受单机可改**（推荐 MVP） | 玩家若想改 JSON 解锁全部成就，那是他的选择——不影响他人，不破坏他人体验 | 单机游戏的「成就纯洁性」不是核心价值；主题体验才是 |
| 简单混淆（XOR / base64 / checksum） | 提高修改门槛，但无法阻止决心改的人 | 增加 5% 实现成本，换取 80% 的「随手改不了」——**v2 可选** |
| 签名校验（HMAC） | 真正防篡改 | 单机游戏过度设计；密钥终会被逆向；**不推荐** |

> **结论**：MVP 接受「单机可改」。若 v2 接入平台成就（Steam Achievement），则由平台 SDK 负责校验，本作只需调用 `Steam.set_achievement(id)`。

### 10.3 云存档前瞻（可选）

未来若实现云存档：

| 维度 | 设计 |
|------|------|
| 同步范围 | `player_progress.json`（成就/图鉴/称号）+ `player_records.json`（当前战役） |
| 冲突处理 | 以「成就解锁数更多」的一方为准（成就只增不减）；当前战役以「最后修改时间」为准 |
| 平台 | Godot 的 `CloudSave`（若上架 Steam/Epic）或自建（需服务器，v3+） |

> **MVP 不做云存档**。本地 FileAccess 足够。

---

## 11. 与其他文档的交叉引用速查

| 本文档章节 | 引用上游 | 引用点 |
|------------|----------|--------|
| §0 哲学 | [00 设计支柱](00_design_pillars.md) | 三大支柱、魔法稀缺、战争没有赢家 |
| §1.3 permadeath 张力 | [04 角色](04_characters.md) §五 | 永久死亡机制、核心叙事装置 |
| §2.1 剧情成就 | [05 剧情分支](05_story_branches.md) §3, §6 | 15 章节、4 结局 |
| §2.2 战斗成就 | [03 职业](03_professions.md) §三 | 武器三角、魔法特攻 |
| §2.3 角色成就 | [04 角色](04_characters.md) | 8 角色、维克托死亡条件 |
| §2.4 职业成就 | [03 职业](03_professions.md) §四 | 转职树、paladin/sage |
| §2.5 探索成就 | [05](05_story_branches.md) §8, [09 关卡](09_levels_and_scenes.md) | 环境叙事落点、源井 |
| §3 重点成就 | [05](05_story_branches.md), [06 道具](06_items.md) | 结局、royalSeal、voidChalice |
| §4 PlayerRecords | `level_storage.gd` | FileAccess + JSON 模式 |
| §5 章节解锁 | [05](05_story_branches.md) §3, `level_select.gd`, `chapter_data.gd` | 章节序列、现状缺口 |
| §6 图鉴 | [01 世界观](01_worldview.md) §九, [12 音频](12_audio_design.md) | 地点、BGM |
| §7 UI | [10 UI/UX](10_ui_ux.md) §1.2 | 10 色配色、非打扰原则 |
| §9 落地 | `battle.gd`, `combat_system.gd`, `skill_system.gd`, `title.gd` | 埋点 hook |
| §10 防作弊 | — | 单机取舍 |

---

## 12. 设计自检（对齐 00 设计支柱禁止清单）

| 自检项 | 结果 |
|--------|------|
| 是否有「杀光/全灭/屠戮」Glory 调性成就？ | **否**。`battle_first_kill` 文案是「夺人性命」而非「首杀」；无任何「全灭敌方」成就。 |
| 是否有「魔法万能」桥段？ | **否**。`battle_physical_only_chapter`（凡人之力）和 `class_mage_no_spell_chapter`（藏锋）反而**奖励不滥用魔法**。 |
| 是否有「完美通关」强制成就？ | **否**。「全员存活」是 challenge 向，非 natural；「Zero Death 通关」**不存在**（避免鼓励读档）。 |
| 成就是否打断心流？ | **否**。战中只入队不弹窗，战后结算页批量显示（`experience-pacing-structure`）。 |
| 成就是否变成斯金纳箱？ | **否**。无跨周目累计刷数成就；challenge 不锁内容；完成度不解锁数值（[§1.2](#12-反斯金纳箱底线)）。 |
| permadeath 是否被「惩罚活下来的人」？ | **否**。死亡成就服务死者（`bond_carry_their_memory`）；图鉴保留死者档案解锁遗书（[§1.3](#13-与永久死亡的张力关键设计)）。 |
| 是否对齐代码库现状？ | **是**。FileAccess + JSON 持久化（对齐 `level_storage.gd`）；autoload 单例（新增 `PlayerProgress` / `ChapterUnlock`）；title.gd 加第 3 按钮；埋点 hook 标注现有文件位置。 |

---

*本文档为成就系统与玩家进度记录总纲。具体成就判定表达式的实现、UI 场景搭建、埋点 hook 接入需在实现阶段与程序联调；achievements.json 数据表需策划与叙事联调文案。*
