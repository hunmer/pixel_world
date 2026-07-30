# Story 设计文档总索引

> 一款「古代魔法 + 多国争霸」主题战旗游戏的完整叙事与系统设计 bible。
> 所有文档服从统一的设计支柱与主题：**「战争没有赢家，只有活下来的人」**。

---

## 📖 阅读顺序

新加入的策划 / 美术 / 程序**必须按编号顺序阅读**，00 是最高纲领。

| # | 文档 | 内容 | 支柱映射 |
|---|------|------|----------|
| 00 | [design_pillars.md](00_design_pillars.md) | 设计支柱、核心循环、魔法硬约束、代码库对齐规范 | 全局 |
| 01 | [worldview.md](01_worldview.md) | 艾尔迦德大陆、四大纪元、**源脉魔法体系**、种族、信仰、环境叙事落点 | 抉择 |
| 02 | [nations.md](02_nations.md) | 4 国设定（黑铁帝国/维兰瑟神权国/碎月联邦/烬民游群）、关系矩阵、作战风格克制环 | 交锋 / 抉择 |
| 03 | [professions.md](03_professions.md) | 13 个职业、武器三角、转职树、魔法稀缺在职业层的落地 | 布阵 / 交锋 |
| 04 | [characters.md](04_characters.md) | 8 个主要角色（7 同伴 + 1 反派）、人物弧光、永久死亡条件、关系图 | 抉择 |
| 05 | [story_branches.md](05_story_branches.md) | 15 章三幕结构、3+1 个实质分支、4 个结局（无完美结局）、环境叙事关卡 | 抉择 |
| 06 | [items.md](06_items.md) | 25 个道具（消耗/投掷/装备/任务）、4 级稀有度、源脉传说道具、反 min/max | 布阵 |
| 07 | [skills.md](07_skills.md) | 27 个技能、元素克制循环、**MP 经济硬底线**、平衡自检 | 交锋 |
| 08 | [gameplay_mechanics.md](08_gameplay_mechanics.md) | 战斗流程、回合制、移动/地形系统、武器三角、**伤害命中公式**、托管 AI | 布阵 / 交锋 |
| 09 | [levels_and_scenes.md](09_levels_and_scenes.md) | 15 章+5 支线关卡、**ASCII 地图**、地形叙事模板、难度曲线 | 布阵 |
| 10 | [ui_ux.md](10_ui_ux.md) | 全界面流程、战场 HUD、战前整备、**ASCII 线框图**、容错设计 | 布阵 / 交锋 |
| 11 | [balance_and_progression.md](11_balance_and_progression.md) | 属性成长表、**MP 经济模型**、敌方曲线、动态难度、平衡自检 | 交锋 |
| 12 | [audio_design.md](12_audio_design.md) | 9 音乐动机、23 BGM、50 SFX、Bus 架构、源脉/灰潮特色音频 | 交锋（反馈）/ 抉择（情绪） |
| 13 | [art_style.md](13_art_style.md) | 色板、iso 渲染规范（128×64 菱形/30°俯角）、职业角色美术卡、特效 | 全局（主题协同） |
| 14 | [achievements.md](14_achievements.md) | 52 成就、玩家记录、章节解锁、图鉴系统、PlayerProgress 单例 | 抉择（沉淀） |
| 15 | [onboarding.md](15_onboarding.md) | 22 个教学 beat、8 种提示组件、渐进 UI 解锁、容错设计、TutorialDirector | 布阵/交锋/抉择（教会） |

---

## 🎯 一句话游戏定位

> **玩家在「布阵 → 交锋 → 抉择」的循环中，决定一场古代魔法战争的走向——而每一场胜利都让胜利者离覆灭更近一步。**

## 三大设计支柱

1. **布阵（Position）** — 在格子地图上移动单位、抢占地形/高地/隘口
2. **交锋（Clash）** — 用职业克制与技能组合，在正确时机对正确目标造成最大效果
3. **抉择（Choose）** — 在剧情分支、角色生死、资源消耗之间做不可逆取舍

---

## 🔗 核心设定速查（供快速定位）

### 世界
- **大陆**：艾尔迦德（Eregaard）
- **当前纪元**：第四纪元·黄昏纪（源脉将尽、灰潮蔓延）
- **魔法体系**：源脉（Ley Lines）+ 源井（不可再生）+ 源裔（万分之一血脉）→ **魔法稀缺是铁律**
- **核心矛盾**：源脉将尽 + 灰潮蔓延 + 信仰死斗（《源典》vs《镇渊律》）

### 国家（4 方，克制环）
```
重甲坦克(黑铁帝国) →碾压→ 工事远程(碎月联邦) →风筝→ 狂化冲锋(烬民) →贴脸→ 稀有法师(维兰瑟) →爆发→ 重甲坦克
```

### 职业（13 个，6 大类）
步兵系(4) / 骑兵系(3) / 飞行系(1) / 远程系(2) / 魔法系(2) / 辅助系(2)
- 武器三角：剑→斧→枪→剑 + 弓/魔对特定职业加成
- 魔法职业占比 15%，MP 浅（单场 2-3 常规 + 1 大招）

### 角色（8 个）
主角凯尔 / 魔导师莉雅 / 叛逃骑士希尔德 / 佣兵艾尔文 / 天马骑士瑟兰 / 古源司祭摩根 / 刺客塞拉芬娜 / **反派维克托（主角舅父，非脸谱恶）**

### 剧情
- 15 章 / 三幕（开端 1-4 / 发展 5-11 / 结局 12-15）
- 3 实质分支 + 1 二阶分支
- **4 个结局，无完美结局**：灰烬之王 / 断裂的和约 / 沉脉 / 孤行之证

### 系统
- 技能 27 个，元素克制：fire→wind→earth→water→fire（×1.5）+ light↔dark
- 道具 25 个，4 级稀有度（普通/精良/史诗/传说，传说必有代价）
- **MP 经济硬底线**：不设任何回 MP 技能/被动，MP 仅靠限量药剂或代价道具

---

## 🎨 主题一致性自检清单

任何新增设计（职业/技能/道具/关卡/角色）必须能回答 ✅：

- [ ] 它是否服务「战争没有赢家」主题？
- [ ] 它是否遵守「魔法稀缺」（不滥用魔法、魔法有代价）？
- [ ] 它是否落在古代冷兵器 + 稀有魔法的文明边界内（无火药/蒸汽/量产魔法）？
- [ ] 它的数据字段是否对齐 `godot/data/*.json`（professions/skills/items）？
- [ ] 它是否引用了 Game Design Skill 的具体原理？

> 参考方法论：`C:/Users/Administrator/Downloads/Game Design Skill/`

---

## 📂 与代码库的对接

本设计 bible 的数据结构**严格对齐现有 Godot 工程**：

| 设计文档 | 对应数据文件 | 关键字段 |
|----------|-------------|----------|
| 03 职业 | `godot/data/professions.json` | id/name/hp/power/agility/skl/luk/def/res/mov/attackRange/weaponType/moveType |
| 07 技能 | `godot/data/skills.json` | id/name/type/element/range/targetType/mpCost/cooldown/power/hitBonus |
| 06 道具 | `godot/data/items.json` | id/name/type/target/effect/power/range/uses |

落地新内容时，直接按文档中的表格 JSON 化写入对应 `.json` 即可。

### 美术与音频
- **色板**：暖底（铁灰/夜墨/血红 50%）+ 冷锋（源脉蓝 #7FDBFF / 源晶紫）点缀；四国色指纹（黑铁黑红铁灰 / 维兰瑟圣金象牙白深紫 / 碎月海蓝帆白桐木棕 / 烬民灰褐凝固血红）
- **iso 渲染硬规范**：block 菱形 128×64 像素、内容须在菱形内、相机俯角 **30°**（2:1 菱形要求，非 35.264°）、偏航 45°、单位 Sprite3D billboard + 48×48 横排 sprite sheet
- **音频动机**：9 个 leitmotif（主角/源脉/4 国/反派/灰潮/挽歌），反派动机是主角动机的扭曲小调版
- **音频系统**（代码库现 0 音频）：Master→BGM/SFX/Voice/Ambience 四 bus，AudioManager autoload 单例，BGM -16 LUFS

### 进度与引导
- **成就**：52 个（剧情8/战斗10/角色8/职业6/探索8/趣味12），含 6 隐藏；反斯金纳箱底线（无跨周目刷数成就）
- **进度系统**：`user://player_progress.json`（跨周目：成就/图鉴/称号）+ `user://player_records.json`（单周目：通关/统计/评分）
- **章节解锁**：15 章线性解锁，分支章记 path_taken，支线按条件解锁（ChapterUnlock autoload）
- **图鉴**：角色/职业/物品/敌人/地点/音乐 6 类
- **新手引导**：第 1 章 22 个 beat（逐个教移动→攻击→地形→撤退），8 种提示组件，渐进 UI 解锁（ch1 菜单 3 项→ch6 全 5 项），数据驱动 `res://data/tutorial/beats_ch1.json`

### 玩法（对齐代码库）
- **地形**：7 类（plain/forest/mountain/water/fort/village/wall），各有 def_bonus/avoid_bonus/move_cost（99=不可通行）
- **移动**：Dijkstra 算移动范围（累加地形消耗），A* 显示寻路；攻击范围与移动范围**解耦**
- **武器三角**：sword→axe→lance→sword（+15% 命中/伤害），bow 克 flying（×1.5），魔法 anima↔dark
- **回合**：player/enemy 两阶段，每单位每回合 hasMoved+hasActed 各一次
- **伤害公式**：max(0, str/mag + weapon.might − def/res − 地形def) × 克制 × 技能倍率；双击条件=速度差≥4

---

## 🚧 待办 / 已知 gap（第四轮补充后）

- [ ] 05 剧情文档中的国家/角色实名占位符（`[国家A]`、`主角`）待与 02/04 回填
- [ ] 03 职业新增 `moveType: "fly"` 需在 `professions.json` 数据层与移动系统补丁
- [ ] 07 技能扩展的 `buff/debuff/utility` 类型需在 `skill_system.gd` 补 effect 分支
- [ ] 08 标注的「建议新增需改代码」清单：弓克飞行、魔法三角、武器耐久、boss AI、新地形、治疗经验
- [ ] 09 新增语义标记 `V!`/`.*`/`Ta` 需用 eventTiles 旁路表落地（不改 terrain.gd）
- [ ] 09 指出 `CATEGORY_TO_TERRAIN` 缺 village/fort 前缀映射的落地缺口
- [ ] 11 发现 combat_system.gd 公式下裸装普攻伤害偏高（应压 weapon.might 至 2-5）
- [ ] 11 属性命名迁移 debt：str/spd/mag ↔ professions.json 的 power/agility
- [ ] 12 音频：代码库 0 音频代码，需搭建 AudioManager autoload + bus_layout + 在 battle/turn_manager/combat_system 集成 hook
- [ ] 13 美术：相机俯角代码实际是 30°（iso_coords.gd L53），iso_coords.gd L7 的「35.264°」注释有误导性，建议修正注释
- [ ] 13 美术：待产 52 套职业动画（13 职业×4 动画，仅 knight-idle 已存）+ 8 角色立绘 + 13 职业立绘
- [ ] 14 进度：需搭建 PlayerProgress + ChapterUnlock 两个 autoload 单例；title.gd 加「记录」按钮；level_select 接章节解锁；chapter_data 补 15 章序列
- [ ] 15 引导：需搭建 TutorialDirector autoload + `res://data/tutorial/beats_chN.json` 数据驱动；8 处埋点 hook（battle.gd Mode/battle_ui 菜单等）
- [ ] 各文档间交叉引用的「待补」标记需在五轮迭代时清理

---

*文档由 12 个 subagent 分四轮并行创作（第一轮：世界观/职业/剧情/道具技能；第二轮：玩法/关卡/UI/数值；第三轮：音频/美术；第四轮：成就/新手引导），统一服从 `00_design_pillars.md` 约束。*
