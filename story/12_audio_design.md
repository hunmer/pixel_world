# 音乐与音效设计（12_audio_design.md）

> **对应设计支柱**：本文档服务三大支柱中的 **「交锋」（Clash）** 与 **「抉择」（Choose）**——音效是「交锋」的即时操作反馈（`reinforcement-feedback-systems`：每一次挥剑、命中、暴击必须 < 100ms 听见），BGM 是「抉择」的情绪配重（`experience-pacing-structure`：过山车曲线决定何时该让玩家紧张、何时该沉默）。所有听觉设计严格服从 [00 设计支柱](00_design_pillars.md) 的「战争没有赢家，只有活下来的人」基调——**禁止 Glory 调性音乐盖在 Horrible 画面上**（音画一致性，[05 剧情分支](05_story_branches.md) §9 明列禁止）。
>
> **现状基线**：当前代码库 0 音频代码（`grep "AudioStream|play_sound|bgm|sfx" godot/scripts/` 为空），`project.godot` 无 `[audio]` 段、无 `default_bus_layout.tres`。本文档第 6 节给出从零搭建的 Godot 4 落地方案。

---

## 一、音频设计总纲

### 1.1 三大设计原则（每条引一个原理）

| # | 原则 | 一句话 | 引用原理 | 落地手法 |
|---|------|--------|----------|----------|
| 1 | **动机统一（Leitmotif Consistency）** | 同一旋律在 BGM 中变奏重现，让玩家「听见」主题。 | `synergy-thematic-design`（1+1>2：音乐+世界观+剧情协同） | 第 2 节的 9 个动机贯穿全曲库；主角动机在结局一被扭曲成反派动机（§2.7） |
| 2 | **即时反馈（Instant Feedback）** | 每个玩家动作必有对应音效，延迟 < 100ms。 | `reinforcement-feedback-systems`（操作-反馈闭环塑造行为） | 第 4 节 SFX 表；SFX 用 `.wav` 低延迟（§6.4） |
| 3 | **情绪引导（Emotional Pacing）** | BGM 的 BPM/调性/乐器密度随战局与剧情峰谷起伏。 | `experience-pacing-structure`（Rollercoaster 过山车模型） | 第 3 节 BGM 曲目表按 15 章紧张度曲线编排；玩家回合优势↔劣势垂直分层（§8.1） |

### 1.2 听觉主题定位（一句话声音身份）

> **「冷兵器金属碰撞 + 源脉空灵回响 + 战争挽歌」**
> —— 这是一个听得见钢铁锈蚀、听得见大地流血、听得见挽歌无人合唱的世界。

- **冷兵器金属碰撞**：剑/枪/斧/弓的物理撞击是战场主旋律，对应 [01 世界观](01_worldview.md) §七「无火药、无蒸汽、冷兵器为主」的科技边界。
- **源脉空灵回响**：魔法施放时的「源脉共鸣嗡鸣」是本作区别于其他战旗的听觉签名，对应 [01 世界观](01_worldview.md) §四源脉魔法体系。
- **战争挽歌**：贯穿全曲库的「战争挽歌」总主题（§2.9）在片头与四结局中变奏重现，呼应 [05 剧情分支](05_story_branches.md) 的「战争没有赢家」中心命题。

### 1.3 与视觉风格的协同

呼应美术的暗金/铁灰/血红/源脉蓝四色调色板（见 [10_ui_ux](10_ui_ux.md) / 待补 13_art_style），每个色域映射一种音色：

| 美术色域 | 出现场景 | 对应音色 | 音频手段 |
|----------|----------|----------|----------|
| **暗金**（神圣/权力） | 圣城、神权国、结局 | 管风琴 + 圣咏合唱 | 维兰瑟动机（§2.4） |
| **铁灰**（战争/钢铁） | 黑铁要塞、帝国、战场 | 低音铜管 + 定音鼓 + 铁砧采样 | 黑铁帝国动机（§2.3） |
| **血红**（牺牲/暴力） | 焦土、灰潮、血祭 | 滴答的滴答计时器 + 不和谐弦 | 灰潮动机（§2.8） |
| **源脉蓝**（魔法/神秘） | 源井、施法、回声深渊 | 玻璃琴 + 空灵女声 + 低频 drone | 源脉动机（§2.2） |

---

## 二、音乐动机（Leitmotif）系统

> **原理**：`synergy-thematic-design` 的「主题协同」——同一动机在不同场景以不同配器/调性变奏重现，让玩家在潜意识中建立「听到这段 = 这个角色/势力在场」的联想。这是瓦格纳式 Leitmotif 技法在战棋 BGM 中的落地。
>
> **命名规范**：动机 id 统一用 `motif_` 前缀；BGM 曲目表（§3）的「用到哪个动机」列引用这些 id。

### 2.1 动机总表

| 动机 id | 动机名 | 调性 | 主乐器 | 情绪关键词 | 出现场景（对应曲目见 §3） |
|---------|--------|------|--------|-----------|--------------------------|
| `motif_kyle` | 凯尔之诺 | D 小调，中板 80 BPM | 大提琴独奏 + 钢琴 | 责任、犹豫、学者的清醒 | 标题曲、玩家回合曲、凯尔独白曲、所有结局 |
| `motif_ley` | 源脉回响 | 利底亚调式，缓板 60 BPM | 玻璃琴 + 空灵女声 + 低频 drone | 神秘、危险、古老 | 施法曲、源井探索曲、第 9/12 章 |
| `motif_iron` | 黑铁进行曲 | C 小调，进行曲 120 BPM | 低音铜管（大号/长号）+ 定音鼓 + 铁砧 | 压迫、沉重、碾压 | 帝国相关战斗曲（第 6/14）、敌方回合曲 |
| `motif_velanthe` | 圣座颂歌 | G 大调，庄严 70 BPM | 管风琴 + 混声合唱 | 虔诚、肃穆、伪善 | 神权国相关曲（第 1/12）、圣城环境 |
| `motif_moon` | 碎月谣 | E 小调，船歌 90 BPM | 琉特琴 + 海浪采样 + 长笛 | 自由、市井、海风 | 联邦相关曲（第 8/13）、碎月港环境 |
| `motif_ashen` | 烬民低语 | 无调性，自由节拍 | prepared piano（异物钢琴）+ 弓拉弦乐 + 长沉默 | 悲苦、被弃、真相 | 烬民相关曲（第 4/11）、烬海环境 |
| `motif_victor` | 维克托之影 | D 小调（`motif_kyle` 的扭曲小调版），急板 140 BPM | 刺耳铜管 + 失真弦乐 | 扭曲、复仇、镜像 | 反派登场曲、boss 战曲、结局一 |
| `motif_graytide` | 灰潮 | 极低频 drone（~40Hz）+ 机械滴答 + 碎裂采样 | （无旋律，纯音色） | 死亡、石化、不可逆 | 灰潮前线环境、死亡音、第 11 章决战 |
| `motif_elegy` | 战争挽歌（总主题） | F 小调，挽歌 50 BPM | 独奏双簧管 + 弦乐四重奏 + 远处合唱 | 哀悼、无赢家 | 片头、四结局、第 15 章反高潮 |

### 2.2 源脉动机（`motif_ley`）详解——本作听觉签名

源脉动机是本作区别于其他战棋的核心听觉资产（对应 [01 世界观](01_worldview.md) §四）。设计要点：

- **音色配方**：玻璃琴（glass harmonica）奏出利底亚调式（#4 音）的悬浮感旋律 + 空灵女声哼鸣 + 40-60Hz 的低频 drone 作「地脉流淌」底色。
- **变奏层级**：
  - L1（平静源井）：仅 drone + 偶发玻璃琴音 → 用于第 9 章探索、源井旁冥想。
  - L2（施法中）：加入女声旋律 + 混响放大 → 用于技能释放 SFX 的「源脉共鸣尾音」。
  - L3（源脉躁动/枯竭）：drone 失谐 + 加入不和谐弦 → 用于第 12 章地脉之鸣、结局三沉脉。
- **听觉意象**：让玩家「听见地底有东西在流」，呼应 [01](01_worldview.md) §4.1「固态-液态混合的魔力之河」。

### 2.3 黑铁帝国动机（`motif_iron`）

- **音色**：4 支大号 + 8 支长号的低音铜管齐奏，节奏型为「短-短-长」进行曲动机，叠加真实铁砧敲击采样（C4 重击）。
- **调性**：C 小调，坚定下行的四音动机（C-Bb-Ab-G）。
- **情绪**：不可撼动的钢铁碾压感，对应 [02 国家](02_nations.md) §1.6「重甲坦克流」。

### 2.4 维兰瑟神权国动机（`motif_velanthe`）

- **音色**：管风琴（organ，用教堂长混响）+ 16 人混声合唱（拉丁语伪经文式和声）。
- **调性**：G 大调，但和声进行刻意用「伪终止」（deceptive cadence）暗示伪善。
- **情绪**：表面神圣肃穆，底下暗藏不安——对应 [02](02_nations.md) §2.6「看似正义实则掠夺」。

### 2.5 碎月联邦动机（`motif_moon`）

- **音色**：琉特琴（lute）分解和弦 + 长笛主旋律 + 海浪/帆布采样底噪。
- **调性**：E 小调，6/8 拍船歌节奏（摇晃感）。
- **情绪**：自由市井的烟火气，对应 [02](02_nations.md) §3.6「弓弩工事流、商贸城邦」。

### 2.6 烬民动机（`motif_ashen`）

- **音色**：prepared piano（在琴弦间塞异物产生的闷响）+ 弓拉弦乐（bowed strings，锯齿般哀鸣）+ 大段沉默（negative space，留白即叙事）。
- **调性**：无调性，微音程（quarter-tone）滑动。
- **情绪**：被世界遗弃者的破碎呢喃，对应 [02](02_nations.md) §4.6「狂化消耗流」与 §4 主题「上一场战争的输家后裔」。

### 2.7 反派维克托动机（`motif_victor`）——主角动机的扭曲

- **设计核心**：`motif_victor` = `motif_kyle`（D 小调大提琴旋律）**转成半音下行的失真版**——同一条旋律，用刺耳铜管 + 失真弦乐奏出，急板 140 BPM。
- **主题映射**：反派是「主角若做了不同选择就会变成的样子」（[05](05_story_branches.md) 结局一灰烬之王即主角镜像）。听觉上用「同旋律不同配器」直接传达这层镜像关系——这是 `synergy-thematic-design` 1+1>2 的极致体现。

### 2.8 灰潮/死亡动机（`motif_graytide`）

- **音色**：无旋律。仅 40Hz 极低频 drone + 机械滴答声（隐喻石化倒计时）+ 随机碎裂采样（玻璃/冰/骨的碎裂）。
- **用法**：叠加在战斗 BGM 之上作「危险层」——当灰潮单位出现、单位死亡、或地图上有 `.*` 源脉黑斑时（[09 关卡](09_levels_and_scenes.md) §〇），灰潮层音量渐升。这是 vertical layering（§8.1）的核心层。

### 2.9 战争挽歌总主题（`motif_elegy`）

- **音色**：独奏双簧管（oboe，最具「哀悼」音色的乐器）奏主旋律 + 弦乐四重奏铺底 + 远处若有若无的混声合唱（从不清晰，永远「差一句没唱完」）。
- **调性**：F 小调，50 BPM 极缓。
- **出现**：片头完整版（2-3 分钟）、四结局各一变奏、第 15 章反高潮长镜头（[05](05_story_branches.md) §2）。
- **主题锚定**：这是「战争没有赢家」的可听化身。每次它响起，玩家都该感到一阵凉意。

---

## 三、BGM 曲目表（对齐 15 章 + 4 结局）

> **分类**：界面 BGM / 战斗 BGM / 剧情 BGM / 结局 BGM。
> **命名规范**：`bgm_<分类>_<用途>.ogg`，如 `bgm_menu_title.ogg`、`bgm_battle_ch06.ogg`。
> **循环**：除结局外均 loop=true（循环点已在曲式标注）。
> **紧张度**列对齐 [05 剧情分支](05_story_branches.md) §3 与 [09 关卡](09_levels_and_scenes.md) §2.1 的章节紧张度。

### 3.1 界面 BGM（5 首）

| 曲目 id | 文件名 | 场景用途 | 情绪定位 | BPM | 调性 | 主乐器 | 时长 | loop | 用到的动机 |
|---------|--------|----------|----------|-----|------|--------|------|------|-----------|
| `bgm_menu_title` | `bgm_menu_title.ogg` | 标题画面（首次启动） | 史诗/悬念/挽歌 | 60 | F 小调 | 双簧管+弦乐四重奏+合唱 | 3:00 | 是 | `motif_elegy` + `motif_kyle` |
| `bgm_menu_main` | `bgm_menu_main.ogg` | 主菜单（继续/新游戏） | 安静/抉择预感 | 70 | D 小调 | 钢琴+大提琴 | 2:30 | 是 | `motif_kyle` |
| `bgm_menu_chapter_select` | `bgm_menu_chapter_select.ogg` | 关卡选择/章节回顾 | 回忆/苍凉 | 80 | A 小调 | 琉特琴+长笛 | 2:00 | 是 | `motif_moon` + `motif_elegy` |
| `bgm_prep_camp` | `bgm_prep_camp.ogg` | 战前整备/编队/商店/转职 | 整备/短暂安宁 | 90 | G 大调 | 琉特琴+古典吉他 | 2:30 | 是 | `motif_moon` |
| `bgm_result_victory` / `bgm_result_defeat` | `bgm_result_victory.ogg` / `bgm_result_defeat.ogg` | 战后结算（胜/败各一） | 胜=疲惫的释然；败=沉痛 | 胜 90 / 败 50 | 胜 D 小调 / 败 D 小调 | 弦乐四重奏 | 1:30 | 否 | 胜 `motif_kyle`；败 `motif_elegy` |

> **设计注**：标题曲完整奏出 `motif_elegy`，是全曲库的「动机源头」。玩家第一次进游戏就听到挽歌——在还不知道什么是战争之前，就已经为它哀悼。这是 `experience-pacing-structure` 的 advance organizer（预告组织者）。

### 3.2 战斗 BGM（8 首）

| 曲目 id | 文件名 | 场景用途（对应章节） | 情绪定位 | BPM | 调性 | 主乐器 | 时长 | loop | 用到的动机 | 紧张度 |
|---------|--------|----------|----------|-----|------|--------|------|------|-----------|--------|
| `bgm_battle_player_adv` | `bgm_battle_player_adv.ogg` | 玩家回合·优势（多数关卡默认） | 从容推进 | 110 | D 小调 | 弦乐+古典吉他+轻打击 | 2:30 | 是 | `motif_kyle` + `motif_moon` | 2-3 |
| `bgm_battle_player_dis` | `bgm_battle_player_dis.ogg` | 玩家回合·劣势（单位大量阵亡/HP 低） | 紧张/危机 | 130 | D 小调（转半音上行） | 弦乐颤音+定音鼓+失真 | 2:00 | 是 | `motif_kyle`（急促版）+ `motif_graytide` 层 | 4-5 |
| `bgm_battle_enemy` | `bgm_battle_enemy.ogg` | 敌方回合（所有关卡） | 压迫/威胁 | 120 | C 小调 | 低音铜管+定音鼓+铁砧 | 2:30 | 是 | `motif_iron` + `motif_victor` | 3-4 |
| `bgm_battle_ch01_tutorial` | `bgm_battle_ch01_tutorial.ogg` | 第 1 章撤退战（教学） | 仓皇撤离 | 100 | A 小调 | 弦乐+钢琴+远处钟声 | 2:30 | 是 | `motif_kyle` + `motif_velanthe`（崩解版） | 2 |
| `bgm_battle_ch06_siege` | `bgm_battle_ch06_siege.ogg` | 第 6 章攻坚战（第一幕峰） | 攻坚/惨烈 | 125 | C 小调 | 全铜管+合唱+铁砧 | 3:00 | 是 | `motif_iron` + `motif_elegy` 片段 | 5 |
| `bgm_battle_ch11_blood` | `bgm_battle_ch11_blood.ogg` | 第 11 章血祭决战 | 道德坠落/惨烈 | 135 | F 小调 | 失真弦乐+合唱+滴答声 | 3:00 | 是 | `motif_graytide` + `motif_victor` + `motif_elegy` 片段 | 5 |
| `bgm_battle_boss` | `bgm_battle_boss.ogg` | 通用 boss 战（第 13/14/15 各 Boss） | 对决/宿命 | 140 | D 小调 | 刺耳铜管+失真弦乐+定音鼓 | 2:30 | 是 | `motif_victor` + `motif_kyle`（对抗） | 5 |
| `bgm_battle_finale_push` | `bgm_battle_finale_push.ogg` | 第 15 章决战线（结局前最后推进） | 终局/无退路 | 145 | F 小调 | 全编制+合唱+铁砧 | 3:00 | 是 | `motif_elegy`（进行曲化）+ 全部势力动机碎片 | 5 |

> **垂直分层（vertical layering，详见 §8.1）**：`bgm_battle_player_adv` 与 `bgm_battle_player_dis` 共享同一基础和声进行，区别仅在叠加的「紧张层」（鼓组/失真弦乐/灰潮层）。实现时可作为同一首曲的 3 个音轨（base / perc / tension），按战况推拉音量，而非两首独立曲。

### 3.3 剧情 BGM（6 首）

| 曲目 id | 文件名 | 场景用途 | 情绪定位 | BPM | 调性 | 主乐器 | 时长 | loop | 用到的动机 |
|---------|--------|----------|----------|-----|------|--------|------|------|-----------|
| `bgm_story_sad` | `bgm_story_sad.ogg` | 同伴之死、村庄焚毁独白 | 哀恸 | 50 | D 小调 | 独奏大提琴+钢琴 | 2:30 | 是 | `motif_elegy` + `motif_kyle` |
| `bgm_story_choice` | `bgm_story_choice.ogg` | 抉择时刻（第 7/10/11 分支点） | 悬念/道德重压 | 60 | 无调性→解决到 D 小调 | prepared piano+弦乐颤音+滴答 | 2:00 | 是 | `motif_ashen` + `motif_graytide` |
| `bgm_story_reveal` | `bgm_story_reveal.ogg` | 真相揭露（第 9/12/13 章封印/导师过去） | 震惊/宿命 | 70 | 利底亚→半音阶 | 玻璃琴+合唱+管风琴 | 2:30 | 是 | `motif_ley` + `motif_velanthe` |
| `bgm_story_bond` | `bgm_story_bond.ogg` | 同伴支援对话、营地温情 | 短暂温暖 | 80 | G 大调 | 琉特琴+长笛+古典吉他 | 2:00 | 是 | `motif_moon` + `motif_kyle`（大调版） |
| `bgm_story_bloodrite` | `bgm_story_bloodrite.ogg` | 血祭场景（第 11 章选 A 时） | 坠落/诅咒 | 55 | F 小调 | 失真弦乐+低频 drone+合唱 | 2:30 | 否 | `motif_victor` + `motif_graytide` |
| `bgm_story_kyle_solo` | `bgm_story_kyle_solo.ogg` | 凯尔独白/内心戏 | 孤独/自省 | 70 | D 小调 | 独奏大提琴+钢琴 | 2:00 | 是 | `motif_kyle`（独奏版） |

### 3.4 结局 BGM（4 首，不循环）

> 每首结局曲都以 `motif_elegy` 为骨架，根据结局情绪做变奏。**禁止任何结局出现 Glory 调性的胜利庆典**（[05](05_story_branches.md) §9）。

| 曲目 id | 文件名 | 结局 | 情绪定位 | BPM | 调性 | 主乐器 | 时长 | 用到的动机 |
|---------|--------|------|----------|-----|------|--------|------|-----------|
| `bgm_end_ashen_king` | `bgm_end_ashen_king.ogg` | 结局一·灰烬之王（最苦涩） | 空洞的胜利/自我镜像 | 50→140→50 | D 小调（`motif_kyle` 被扭曲成 `motif_victor`） | 刺耳铜管渐强后骤寂，剩独奏大提琴 | 3:30 | `motif_kyle` → `motif_victor` → `motif_elegy` |
| `bgm_end_broken_pact` | `bgm_end_broken_pact.ogg` | 结局二·断裂的和约（最希望但苦涩） | 疲惫的停火/脆弱 | 70 | D 小调→D 大调（小调转大调） | 弦乐四重奏+琉特琴+远处合唱 | 3:00 | `motif_elegy` + `motif_kyle`（大调解决）+ `motif_moon` |
| `bgm_end_severed_ley` | `bgm_end_severed_ley.ogg` | 结局三·沉脉（自我献祭） | 壮烈/终结/静默 | 60→渐无 | F 小调→静默 | 全编制渐弱至只剩风声 | 3:30 | `motif_ley`（碎裂消散）+ `motif_elegy` |
| `bgm_end_lone_witness` | `bgm_end_lone_witness.ogg` | 结局四·孤行之证（隐藏/空洞） | 冷的讽刺/无人合唱 | 50 | D 小调（无合唱，仅独奏） | 独奏双簧管+独奏大提琴，无伴奏 | 2:30 | `motif_elegy`（剥离合唱版） |

> **结局三设计注**：`bgm_end_severed_ley` 的核心是「音乐本身被杀死」——随着主角击碎源脉，全编制乐器逐个静默（先合唱消失、再弦乐消失、最后只剩风声）。这是 `synergy-thematic-design` 的最高形式：**机制（魔法消失）= 叙事（文明枯竭）= 听觉（音乐消亡）**。

### 3.5 BGM 总数与统计

| 分类 | 数量 |
|------|------|
| 界面 BGM | 5（含胜/败结算各 1） |
| 战斗 BGM | 8 |
| 剧情 BGM | 6 |
| 结局 BGM | 4 |
| **合计** | **23 首** |

---

## 四、SFX（音效）设计表

> **原理**：`reinforcement-feedback-systems`——音效是玩家动作的即时反馈，延迟须 < 100ms，故全部用 `.wav` 格式（§6.4）。每个 SFX 都应回答「我刚才做了什么/发生了什么」。
> **命名规范**：`sfx_<分类>_<具体>.wav`，如 `sfx_ui_cursor.wav`、`sfx_sword_swing.wav`。

### 4.1 UI 音效（10 个）

> 服务 `reinforcement-feedback-systems` 的即时性：每次按键必有声，且不同动作的音色要有明确区分（参考 Hick's Law——可辨听的反馈降低认知负荷）。

| SFX id | 文件名 | 触发事件 | 音色设计 | 时长 |
|--------|--------|----------|----------|------|
| `sfx_ui_cursor` | `sfx_ui_cursor.wav` | 光标移动/选项切换 | 短促「咔」——薄木片轻敲 | 0.05s |
| `sfx_ui_select` | `sfx_ui_select.wav` | 选中单位/确认选项 | 清脆「叮」——金属片共鸣 | 0.15s |
| `sfx_ui_confirm` | `sfx_ui_confirm.wav` | 确认行动（移动/攻击下令） | 低沉「咚」——皮革鼓单击 | 0.2s |
| `sfx_ui_cancel` | `sfx_ui_cancel.wav` | 取消/返回 | 短「嗤」——布料摩擦 | 0.1s |
| `sfx_ui_menu_open` | `sfx_ui_menu_open.wav` | 打开菜单/行动菜单 | 纸张展开声 + 远处铁砧轻击 | 0.3s |
| `sfx_ui_menu_close` | `sfx_ui_menu_close.wav` | 关闭菜单 | 纸张合拢声 | 0.2s |
| `sfx_ui_error` | `sfx_ui_error.wav` | 非法操作（MP 不足/超范围） | 低频「嗡」+ 短暂不和谐双音 | 0.25s |
| `sfx_ui_turn_end` | `sfx_ui_turn_end.wav` | 结束回合按钮 | 号角短鸣（单音） | 0.4s |
| `sfx_ui_equip` | `sfx_ui_equip.wav` | 装备武器/道具 | 金属环扣声（剑入鞘感） | 0.2s |
| `sfx_ui_levelup` | `sfx_ui_levelup.wav` | 单位升级 | 上升大三和弦琶音（钢片琴） | 0.5s |

### 4.2 战斗音效（20 个）

> 每种武器类型（sword/lance/axe/bow/magic/staff，对齐 [03 职业](03_professions.md) weaponType）有独立的挥动音，命中按伤害类型分。暴击与 miss 必须有显著差异（即时反馈区分操作结果）。

| SFX id | 文件名 | 触发事件 | 音色设计 | 时长 |
|--------|--------|----------|----------|------|
| `sfx_sword_swing` | `sfx_sword_swing.wav` | 剑类挥动 | 空气切割「嗖」+ 钢材微振 | 0.2s |
| `sfx_lance_swing` | `sfx_lance_swing.wav` | 枪类挥动 | 沉闷「呼」+ 木质共振 | 0.25s |
| `sfx_axe_swing` | `sfx_axe_swing.wav` | 斧类挥动 | 重物破风「呜」 | 0.3s |
| `sfx_bow_draw` | `sfx_bow_draw.wav` | 弓类拉弦 | 弓弦绷紧「吱」 | 0.4s |
| `sfx_bow_release` | `sfx_bow_release.wav` | 弓类释放 | 弦回弹「啪」+ 箭离身 | 0.15s |
| `sfx_hit_blade` | `sfx_hit_blade.wav` | 刀剑命中 | 钢对钢「铛」+ 余振 | 0.3s |
| `sfx_hit_pierce` | `sfx_hit_pierce.wav` | 穿刺命中（枪/箭） | 肉体刺入「噗」+ 骨裂 | 0.25s |
| `sfx_hit_blunt` | `sfx_hit_blunt.wav` | 钝器命中（斧/锤） | 沉闷「咚」+ 护甲变形 | 0.3s |
| `sfx_crit` | `sfx_crit.wav` | 暴击 | 上述命中音 + 玻璃碎裂叠层 + 低频冲击 | 0.5s |
| `sfx_miss` | `sfx_miss.wav` | 攻击未命中 | 空气「嗖」+ 布料拂过（无撞击） | 0.3s |
| `sfx_unit_death` | `sfx_unit_death.wav` | 单位死亡 | 短促人声闷哼 + 护甲倒地 + `motif_graytide` 碎裂音 | 0.8s |
| `sfx_unit_damaged` | `sfx_unit_damaged.wav` | 单位受击（非致命） | 人声短促痛呼 + 护甲刮擦 | 0.4s |
| `sfx_counter` | `sfx_counter.wav` | 反击触发 | 命中音 + 短促金属回响 | 0.35s |
| `sfx_skill_fire` | `sfx_skill_fire.wav` | 火系技能 | 爆燃「轰」+ 噼啪 + 源脉共鸣尾音 | 0.6s |
| `sfx_skill_water` | `sfx_skill_water.wav` | 水系技能 | 水流涌动 + 冰晶碎裂 | 0.6s |
| `sfx_skill_earth` | `sfx_skill_earth.wav` | 地系技能 | 岩石崩裂 + 大地闷响 | 0.6s |
| `sfx_skill_wind` | `sfx_skill_wind.wav` | 风系技能 | 气流呼啸 + 树叶沙沙 | 0.5s |
| `sfx_skill_light` | `sfx_skill_light.wav` | 光系技能 | 圣咏短促哼鸣 + 钟声 + 源脉共鸣 | 0.6s |
| `sfx_skill_dark` | `sfx_skill_dark.wav` | 暗系技能 | 低频倒吸 + 耳语 + 不和谐弦 | 0.7s |
| `sfx_heal` | `sfx_heal.wav` | 治疗（staff） | 上升琶音 + 温暖弦乐 + 源脉共鸣 | 0.6s |

> **源脉共鸣尾音**：所有魔法类技能（fire/water/earth/wind/light/dark）与治疗，在主音效末尾叠加一段 0.2-0.3s 的 `motif_ley` 玻璃琴尾音，作为本作施法的听觉统一签名。

### 4.3 地形/环境脚步音（8 个）

> 服务 `environmental-storytelling-technique`：脚步音随地形变化，让玩家「听出」自己在什么地形上行军。移动音用 AudioStreamPlayer2D/3D 带空间定位（§6.2）。

| SFX id | 文件名 | 地形（→09 §〇 TerrainType） | 音色设计 |
|--------|--------|--------------------------|----------|
| `sfx_step_plain` | `sfx_step_plain.wav` | `.` 平原 / `V` 村 | 草地踩踏「沙沙」 |
| `sfx_step_forest` | `sfx_step_forest.wav` | `F` 森林 | 枯叶碎裂 + 树枝折断 |
| `sfx_step_mountain` | `sfx_step_mountain.wav` | `M` 山地 | 碎石滚落 + 沉闷回响 |
| `sfx_step_snow` | `sfx_step_snow.wav` | 雪地（霜落/冰原） | 雪壳压紧「咯吱」 |
| `sfx_step_fort` | `sfx_step_fort.wav` | `T` 要塞 | 石板回响 + 护甲叮当 |
| `sfx_step_water` | `sfx_step_water.wav` | `W` 水域（仅 fly 越过） | 水花溅起 |
| `sfx_river_loop` | `sfx_river_loop.ogg` | 银泪河/护城河背景 | 流水持续底噪（loop） |
| `sfx_wind_loop` | `sfx_wind_loop.ogg` | 开阔地/高地背景 | 风声持续底噪（loop） |

### 4.4 源脉特色音效（5 个）——本作听觉签名

> 直接服务 [01 世界观](01_worldview.md) §四源脉魔法体系与灰潮设定。这些是其他战旗没有的差异化音频资产。

| SFX id | 文件名 | 触发事件 | 音色设计 | 时长 |
|--------|--------|----------|----------|------|
| `sfx_ley_resonance` | `sfx_ley_resonance.wav` | 施法瞬间的「源脉共鸣」嗡鸣 | 60-200Hz 共振嗡鸣 + 玻璃琴泛音（叠加在元素技能音之上） | 0.4s |
| `sfx_ley_well_pulse` | `sfx_ley_well_pulse.ogg` | 源井附近的脉动（loop） | 心跳节奏的低频脉冲 + 偶发玻璃琴音（每 3 秒一次） | loop |
| `sfx_graytide_crack` | `sfx_graytide_crack.wav` | 灰潮石化碎裂（单位感染/地形 `.*` 出现） | 玻璃/冰/骨的渐进碎裂 + 滴答声加速 | 0.8s |
| `sfx_source_scar_drain` | `sfx_source_scar_drain.wav` | 法师站 `.*` 黑斑上 MP 不回复的提示 | 倒吸的真空感 + 源脉嗡鸣失谐 | 0.5s |
| `sfx_seal_weaken` | `sfx_seal_weaken.wav` | 封印松动（第 9/12 章） | 低频轰鸣 + 石门摩擦 + 远处回声 | 1.0s |

### 4.5 系统音效（7 个）

| SFX id | 文件名 | 触发事件 | 音色设计 | 时长 |
|--------|--------|----------|----------|------|
| `sfx_turn_start_player` | `sfx_turn_start_player.wav` | 玩家回合开始 | 上升号角 + 鼓点（D 小调主和弦） | 0.6s |
| `sfx_turn_start_enemy` | `sfx_turn_start_enemy.wav` | 敌方回合开始 | 下降号角 + 铁砧（C 小调） | 0.6s |
| `sfx_victory` | `sfx_victory.wav` | 关卡胜利 | 疲惫的释然——弦乐短促解决 + 远处合唱（**非庆典**） | 1.5s |
| `sfx_defeat` | `sfx_defeat.wav` | 关卡失败 | 沉降的低频 + 单声钟鸣 | 1.5s |
| `sfx_save` | `sfx_save.wav` | 存档成功 | 墨水落纸 + 书页合拢 | 0.4s |
| `sfx_promote` | `sfx_promote.wav` | 职业转职 | 上升和弦 + 源脉共鸣 + 短号角 | 0.8s |
| `sfx_low_hp_alarm` | `sfx_low_hp_alarm.wav` | 单位 HP < 25% 警告（每回合开始） | 心跳声 + 微弱滴答（叠 `motif_graytide` 色） | 0.5s |

### 4.6 SFX 总数

| 分类 | 数量 |
|------|------|
| UI 音效 | 10 |
| 战斗音效 | 20 |
| 地形/环境脚步 | 8 |
| 源脉特色音效 | 5 |
| 系统音效 | 7 |
| **合计** | **50 个** |

> 另有 §5 的 8 个环境音轨（ambience，多为 loop 底噪），与 SFX 分轨管理（独立 bus，见 §6.1）。

---

## 五、环境音轨（Ambience）——对齐 09 的 8 个地点

> **原理**：`environmental-storytelling-technique`（世界作为角色）+ `experience-pacing-structure`（advance organizer）。每个地点用分层环境音让玩家「未战先感」。
> **分层配方**：每地点 = **基础底噪**（持续 loop）+ **事件音**（间歇性 loop）+ **偶发音**（随机触发的非循环音）。
> 地点编号与 [01 世界观](01_worldview.md) §九、[09 关卡](09_levels_and_scenes.md) §三对齐。

| # | 地点 | 基础底噪 | 事件音 | 偶发音 | 对应 ambience 文件 |
|---|------|----------|--------|--------|---------------------|
| 1 | **圣城艾尔萨** | 远处圣咏哼鸣（混声，极弱）+ 大理石回声底 | 风过神殿穹顶的呼啸（每 8 秒） | 源脉低鸣脉冲（`motif_ley` drone，每 20 秒） | `amb_holy_city.ogg` |
| 2 | **黑铁要塞** | 铁砧节奏性敲击底（远，像心跳）+ 火炉持续噼啪 | 远处号角回声（每 15 秒） | 铁链拖地 + 断剑落地的金属叮当 | `amb_blackiron_hold.ogg` |
| 3 | **烬海石林** | 风蚀石洞的空洞呼啸底（带长混响） | 沙粒滚动的细碎沙沙（持续） | 石化碎裂声（`sfx_graytide_crack`，每 30 秒随机） | `amb_ashen_pillars.ogg` |
| 4 | **回声深渊** | 洞穴回声底（滴水带长尾混响） | 熔岩咕嘟冒泡（每 5 秒） | 钟乳石坠落碎裂 + 源脉蓝光渗出的嗡鸣 | `amb_echoing_deep.ogg` |
| 5 | **碎月自由港** | 海浪拍岸底（loop）+ 帆布拍打 | 码头喧嚣（人声模糊、绳索摩擦、木桶滚动） | 海鸥叫声 + 远处商船号角 | `amb_freeport.ogg` |
| 6 | **霜落祭坛** | 寒风呼啸底（尖锐高频） | 冰层断裂的脆响（每 10 秒） | 压抑的沉默（突然静音 2 秒，制造不安）+ 极远处哀嚎 | `amb_frostfall_altar.ogg` |
| 7 | **灰潮前线** | 极低频 drone（40Hz，`motif_graytide`）+ 大地持续微震 | 大地碎裂的轰鸣（每 12 秒，渐强） | 不安静默（随机 3-5 秒完全无声，突出绝望）+ 滴答声 | `amb_graytide_front.ogg` |
| 8 | **银泪渡口** | 流水潺潺底（loop）+ 芦苇沙沙 | 雾气中水珠滴落（每 6 秒） | 远处桨声 + 晨鸟啼鸣（仅白昼关卡） | `amb_silver_tear_ford.ogg` |

> **灰潮前线设计注**（`amb_graytide_front.ogg`）：这是全曲库最极端的环境音——**故意制造「不安静默」**（随机完全静音）。这对应 [01](01_worldview.md) §九「地面实时石化」与 [09](09_levels_and_scenes.md) §3.8「你脚下的世界正在死」。当声音本身都在死去，玩家会本能感到不安——这是 `environmental-storytelling-technique` 的听觉极致。

---

## 六、音频系统架构（Godot 实现方案）

> **现状**：代码库 0 音频（`grep` 确认），`project.godot` 无 `[audio]` 段、无 `default_bus_layout.tres`。本节给出从零搭建的完整方案，对齐 Godot 4.x（项目 `config/features=PackedStringArray("4.7", ...)`）。

### 6.1 Bus 结构（AudioServer layout）

设计 `res://default_bus_layout.tres`，Master 下挂 4 个子 bus：

| Bus 名 | 用途 | 推荐音量 (dB) | 路由 | 说明 |
|--------|------|---------------|------|------|
| **Master** | 总输出 | 0 dB（基准） | → 系统输出 | 全局总控；设置菜单的「主音量」滑块绑此 |
| **BGM** | 背景音乐 | -6 dB | → Master | 标题/战斗/剧情曲；设置菜单「音乐」滑块绑此 |
| **SFX** | 音效（UI/战斗/系统） | -3 dB | → Master | 瞬时反馈音；设置菜单「音效」滑块绑此 |
| **Voice** | 语音/人声（预留） | -3 dB | → Master | 未来配音；当前可空 |
| **Ambience** | 环境音轨 | -12 dB | → Master | 地点底噪；设置菜单「环境」滑块绑此 |

> **优先级（冲突时谁让位）**：UI SFX > 战斗 SFX > Voice > BGM > Ambience。当战斗 SFX 密集触发时，可通过 sidechain compression 让 BGM 短暂降低 2-3 dB（Godot 可用 AudioEffectCompressor 实现）。

**落地命令**（Godot 编辑器或 MCP）：
1. `audio_bus_add` 创建 BGM / SFX / Voice / Ambience 四个 bus，send 均为 Master。
2. `audio_bus_set_volume` 设定各 bus 初始 dB。
3. `audio_set_bus_layout` 保存为 `res://default_bus_layout.tres`（项目启动自动加载）。

### 6.2 AudioStreamPlayer 节点方案

#### 6.2.1 全局 AudioManager（autoload 单例）

新增 autoload `AudioManager`（`res://scripts/autoload/audio_manager.gd`），在 `project.godot` 的 `[autoload]` 段注册（与现有 `SceneArgs`、`BreakpointRuntimeBridge` 并列）：

```gdscript
# res://scripts/autoload/audio_manager.gd（建议骨架，本文档只给设计，不落代码）
extends Node
# 持有跨场景持久的 player
var _bgm_player: AudioStreamPlayer          # 当前 BGM（bus="BGM"）
var _bgm_next: AudioStreamPlayer            # 交叉淡入用第二 player
var _ui_player: AudioStreamPlayer           # UI SFX（bus="SFX"，单声道即可）
var _sfx_pool: Array[AudioStreamPlayer] = [] # 战斗 SFX 池（8 个，轮转复用，防叠播爆音）
var _ambience_player: AudioStreamPlayer     # 当前环境音（bus="Ambience"）

# 对外 API（建议）
func play_bgm(stream: AudioStream, fade: float = 0.5) -> void  # 带淡入淡出切换
func stop_bgm(fade: float = 0.5) -> void
func play_ambience(stream: AudioStream, fade: float = 1.0) -> void
func play_ui(sfx_id: StringName) -> void
func play_sfx(sfx_id: StringName, pos: Vector2 = Vector2.ZERO) -> void  # pos 用于 3D 空间
func set_bus_volume(bus: String, db: float) -> void  # 绑设置菜单
func set_layer_active(layer: String, active: bool) -> void  # 垂直分层（§8.1）
```

#### 6.2.2 战场场景节点

- **UI SFX**：由全局 `AudioManager.play_ui()` 处理，battle.gd 不需要本地 player。
- **战斗 SFX**（挥剑/命中/技能）：用 `AudioManager._sfx_pool`（8 个 AudioStreamPlayer，bus=SFX）轮转复用。命中音若需空间感，改用 AudioStreamPlayer2D（等距场景 2D 足够；若为真 3D 等距，用 AudioStreamPlayer3D + position）。
- **Ambience**：每个 BattleScene 启动时根据地点（[09](09_levels_and_scenes.md) §三的 8 地点）调用 `AudioManager.play_ambience(amb_<location>)`，场景退出时淡出。

#### 6.2.3 位置音效（脚步/命中）

- 等距场景本质是 2D 投影的 3D，**推荐 AudioStreamPlayer2D**（实现简单，衰减足够）。只有当项目改为真 3D 透视时才升级到 AudioStreamPlayer3D。
- 脚步音（§4.3）在单位移动结束时触发，位置 = 单位当前 tile 坐标。

### 6.3 音频资源组织（目录与命名规范）

```
res://assets/audio/
├── bgm/
│   ├── bgm_menu_title.ogg
│   ├── bgm_menu_main.ogg
│   ├── bgm_menu_chapter_select.ogg
│   ├── bgm_prep_camp.ogg
│   ├── bgm_result_victory.ogg
│   ├── bgm_result_defeat.ogg
│   ├── bgm_battle_player_adv.ogg
│   ├── bgm_battle_player_dis.ogg
│   ├── bgm_battle_enemy.ogg
│   ├── bgm_battle_ch01_tutorial.ogg
│   ├── bgm_battle_ch06_siege.ogg
│   ├── bgm_battle_ch11_blood.ogg
│   ├── bgm_battle_boss.ogg
│   ├── bgm_battle_finale_push.ogg
│   ├── bgm_story_sad.ogg
│   ├── bgm_story_choice.ogg
│   ├── bgm_story_reveal.ogg
│   ├── bgm_story_bond.ogg
│   ├── bgm_story_bloodrite.ogg
│   ├── bgm_story_kyle_solo.ogg
│   ├── bgm_end_ashen_king.ogg
│   ├── bgm_end_broken_pact.ogg
│   ├── bgm_end_severed_ley.ogg
│   └── bgm_end_lone_witness.ogg
├── sfx/
│   ├── ui/        (sfx_ui_*.wav，10 个)
│   ├── combat/    (sfx_sword/lance/axe/bow/hit/crit/miss/death...，20 个)
│   ├── terrain/   (sfx_step_*.wav + sfx_river/wind_loop.ogg，8 个)
│   ├── ley/       (sfx_ley_*.wav + sfx_graytide_*.wav，5 个源脉特色)
│   └── system/    (sfx_turn_*/victory/defeat/save/promote/low_hp，7 个)
└── ambience/
    ├── amb_holy_city.ogg
    ├── amb_blackiron_hold.ogg
    ├── amb_ashen_pillars.ogg
    ├── amb_echoing_deep.ogg
    ├── amb_freeport.ogg
    ├── amb_frostfall_altar.ogg
    ├── amb_graytide_front.ogg
    └── amb_silver_tear_ford.ogg
```

**命名规范**：
- BGM：`bgm_<分类>_<用途>.ogg`
- SFX：`sfx_<分类>_<具体>.wav`（源脉特色归 `ley/` 子目录）
- Ambience：`amb_<地点英文名>.ogg`
- 全部小写 + 下划线，避免空格与中文（Godot 资源路径友好）。

**资源注册表**：建议新增 `res://scripts/data/audio_registry.gd`，用字典集中映射 `sfx_id → AudioStream`，避免散落的 `load()` 调用：

```gdscript
# res://scripts/data/audio_registry.gd（设计示意，不落代码）
const SFX: Dictionary = {
    &"ui_cursor": preload("res://assets/audio/sfx/ui/sfx_ui_cursor.wav"),
    &"sword_swing": preload("res://assets/audio/sfx/combat/sfx_sword_swing.wav"),
    &"ley_resonance": preload("res://assets/audio/sfx/ley/sfx_ley_resonance.wav"),
    # ... 全部 50 个
}
const BGM: Dictionary = { &"menu_title": preload("res://assets/audio/bgm/bgm_menu_title.ogg"), ... }
const AMBIENCE: Dictionary = { &"holy_city": preload("res://assets/audio/ambience/amb_holy_city.ogg"), ... }
```

### 6.4 格式建议

| 用途 | 格式 | 理由 |
|------|------|------|
| BGM | `.ogg`（Ogg Vorbis） | 压缩率高、循环友好（Godot 的 AudioStreamOggVorbis 支持 `loop=true`），文件小 |
| SFX | `.wav`（PCM 16/24-bit） | 无解码延迟，保证 < 100ms 即时反馈（`reinforcement-feedback-systems` 硬要求） |
| Ambience | `.ogg` | 长时长的底噪，压缩省空间；loop 友好 |

> **导入设置**（Godot Reimport）：BGM/Ambience 在 `.import` 中设 `loop: true`；SFX 保持 `loop: false`。BPM 与循环点信息可写入文件元数据或单独的 `audio_metadata.json`，供 `AudioManager` 做同步切层。

### 6.5 BGM 过渡与战斗紧张度切换

- **淡入淡出（crossfade）**：用 Godot `Tween` 对两个 AudioStreamPlayer 的 `volume_db` 做线性插值（如 0.5 秒），实现曲目切换无爆音。`AudioManager.play_bgm(stream, fade)` 封装此逻辑。
- **垂直分层（vertical layering）**：将 `bgm_battle_player_adv/dis` 拆为同一和声进行的多个音轨文件（`base.ogg` / `perc.ogg` / `tension.ogg`），用多个 player 同步播放，按战况推拉各层音量（详见 §8.1）。

---

## 七、音频与玩法的集成点（对齐代码）

> 本节**不改代码**，只标注音频应在哪些现有 hook 触发。引用的函数/信号/枚举均来自当前代码库（已核实）。

### 7.1 battle.gd 的 Mode 状态机

`battle.gd` L30：`enum Mode { IDLE, UNIT_SELECTED, MOVING, MENU, ENEMY_TURN, ANIMATING }`。音频触发点：

| Mode 转换（代码行） | 触发音频 |
|---------------------|----------|
| `IDLE → UNIT_SELECTED`（L432 `mode = Mode.UNIT_SELECTED`） | `sfx_ui_select`（单位选中叮） |
| `→ MOVING`（移动下令时） | `sfx_ui_confirm`（下令咚）+ 移动到达后 `sfx_step_<terrain>` |
| `→ MENU`（行动菜单打开） | `sfx_ui_menu_open`；关闭时（L171-172）`sfx_ui_menu_close` |
| `→ ANIMATING`（L510/544/615/678/940，战斗动画播放） | 触发战斗 SFX 链（挥动→命中→受击/死亡，见 §7.3） |
| `→ ENEMY_TURN`（L197/963） | `sfx_turn_start_enemy` + BGM 切换到 `bgm_battle_enemy` |
| ENEMY_TURN → IDLE（回合开始） | `sfx_turn_start_player` + BGM 切回 `bgm_battle_player_adv` |

### 7.2 turn_manager.gd 的回合信号

`turn_manager.gd` L8-9：`signal phase_player(turn_number)` / `signal phase_enemy(turn_number)`，在 `battle.gd` L95-96 已 connect 到 `_on_player_phase` / `_on_enemy_phase`。

| 信号 | 在 `_on_player_phase` / `_on_enemy_phase` 中触发 |
|------|------------------------------------------------|
| `phase_player` | `sfx_turn_start_player` + `AudioManager.play_bgm(bgm_battle_player_adv)` + 重置垂直分层为优势层 |
| `phase_enemy` | `sfx_turn_start_enemy` + `AudioManager.play_bgm(bgm_battle_enemy)` |

### 7.3 combat_system.gd 的伤害结算

`combat_system.gd` 提供 `preview()`（L13）与 `execute()`（L46）静态函数，内含 `_damage()`（L111）、`_crit_chance()`（L123）。建议在 `battle.gd` 调用 `execute()` 后、根据返回结果触发：

| 结算结果 | 触发音频 |
|----------|----------|
| 命中（普通） | `sfx_<weapon>_swing` → 0.05s 后 `sfx_hit_<blade/pierce/blunt>` + `sfx_unit_damaged` |
| 暴击（`_crit_chance` 命中） | 上述 + 叠加 `sfx_crit`（玻璃碎裂层） |
| Miss | `sfx_<weapon>_swing` → `sfx_miss`（无撞击） |
| 反击触发 | `sfx_counter` |
| 目标 HP ≤ 0（死亡） | `sfx_unit_death` + BGM 短暂低落（垂直分层切入 tension 层 1 秒）+ 若是灰潮单位叠加 `sfx_graytide_crack` |

### 7.4 skill_system.gd 的技能释放

`skill_system.gd` 的 `execute()`（L132）读取 `sk[&"element"]`（L171 `_is_magic_element`）。建议按 `element` 字段（对齐 [03](03_professions.md) / `skills.json` 的 fire/water/earth/wind/light/dark/physical）触发：

| `sk[&"element"]` | 触发音频 | 备注 |
|-----------------|----------|------|
| `fire` | `sfx_skill_fire` + `sfx_ley_resonance` 尾音 | 叠加源脉共鸣 |
| `water` | `sfx_skill_water` + `sfx_ley_resonance` | |
| `earth` | `sfx_skill_earth` + `sfx_ley_resonance` | |
| `wind` | `sfx_skill_wind` + `sfx_ley_resonance` | |
| `light` | `sfx_skill_light` + `sfx_ley_resonance` | |
| `dark` | `sfx_skill_dark` + `sfx_ley_resonance` | |
| `physical` | 对应武器挥动音（sword/axe…） | 非魔法，无源脉共鸣 |
| 技能 `type == heal`（L153-154） | `sfx_heal` + `sfx_ley_resonance` | staff 治疗 |

> 此外，`skill_system.execute` L141 扣 MP（`caster[&"mp"]`），若扣后 MP < 30% 可触发微弱的 `sfx_source_scar_drain` 提示法师「法力将竭」——呼应 [01](01_worldview.md) §4.2「MP 不可自动回满」的稀缺压力。

### 7.5 单位死亡 → BGM 短暂低落

任一单位（玩家或敌方）死亡时：
- 触发 `sfx_unit_death`。
- `AudioManager` 将战斗 BGM 的 tension 层（垂直分层）切入 1.0 秒，制造「战场一沉」的瞬间——服务 `reinforcement-feedback-systems` 让玩家感知「有人死了」的重量（对应 [05](05_story_branches.md) 永久死亡的叙事重量）。

---

## 八、动态音频（进阶）

### 8.1 垂直分层（Vertical Remix / Layering）

**适用曲**：`bgm_battle_player_adv` / `bgm_battle_player_dis`（本质是同一首曲的 3 层）。

| 层 id | 内容 | 触发条件（推音量） |
|-------|------|-------------------|
| `layer_base` | 弦乐和声进行 + 旋律（`motif_kyle`） | 默认满音量（始终在） |
| `layer_perc` | 古典吉他 + 轻打击（稳定节奏） | 玩家回合且场上玩家单位 ≥ 60% 存活 |
| `layer_tension` | 失真弦乐颤音 + 定音鼓 + `motif_graytide` 滴答 | 玩家单位存活 < 40%，或任一单位 HP < 25%，或 boss 战 |

**实现**：3 个 AudioStreamPlayer 同步播放同一 BPM 的 3 个文件，`AudioManager.set_layer_active(layer, active)` 用 Tween 推拉各 player 的 `volume_db`（激活 -3dB，静音 -80dB）。需保证 3 文件 sample-accurate 对齐（同 BPM、同起点）。

### 8.2 水平重新编排（Horizontal Resequencing）

**适用**：根据战局进度在 BGM 段落间过渡。例如 `bgm_battle_finale_push`（第 15 章决战线）分 3 段：
- 段 A（推进）：`motif_elegy` 进行曲化，玩家推进时播放。
- 段 B（Boss 显形）：切入 `motif_victor`，Boss 登场时播放。
- 段 C（终局）：全编制 + 合唱，Boss HP < 30% 时播放。

**实现**：用 Godot 的 AudioStreamInteractive（Godot 4.x 新增）或手动管理多个 player，在段落边界（beat 同步点）切换。

### 8.3 灰潮/源脉的环境响应（滤波）

当战场上存在源脉节点（`.*` 黑斑，[09](09_levels_and_scenes.md) §〇）或灰潮单位时：
- 对附近的 AudioStreamPlayer2D（脚步/命中音）施加 **BandPassFilter**（AudioEffectBandPassFilter），模拟「源脉共鸣滤波」——声音带上一层空灵的金属泛音。
- 距源脉节点越近，滤波器 Q 值越高、共振越强。
- 这是 `motif_ley` 在 SFX 层的渗透，让玩家「听见自己靠近源脉」。

---

## 九、音量平衡与混音指南

### 9.1 推荐音量（dB）

| Bus | 推荐 dB | 理由 |
|-----|---------|------|
| Master | 0 | 基准 |
| BGM | -6 | 略低于 SFX，不喧宾夺主 |
| SFX | -3 | 即时反馈优先，最响 |
| Voice | -3 | 与 SFX 平齐（未来配音） |
| Ambience | -12 | 底层氛围，不干扰 |

### 9.2 响度标准（LUFS）

| 类型 | 目标响度 | 依据 |
|------|----------|------|
| BGM | -16 LUFS（integrated） | 流媒体标准（Spotify/Apple Music），避免过响被平台惩罚性降音量 |
| SFX | -10 LUFS 瞬时，峰值 -1 dBTP | 瞬态需突出，但峰值不削波 |
| Ambience | -23 LUFS | 背景层，远低于 BGM |

### 9.3 优先级与侧链

- **优先级**（冲突时让位顺序）：UI SFX > 战斗 SFX > Voice > BGM > Ambience。
- **侧链压缩**：在 BGM bus 上挂 AudioEffectCompressor，sidechain 接 SFX bus。当 SFX 密集触发（如暴击连击），BGM 自动下降 2-3 dB，让出空间——混音更干净。

---

## 十、无障碍与设置

### 10.1 音量分轨调节

设置菜单（对齐 [10_ui_ux](10_ui_ux.md)）提供 5 个独立滑块，各绑一个 bus 的 `volume_db`：

| 滑块 | 绑定 Bus | 范围 | 默认 |
|------|----------|------|------|
| 主音量 | Master | -60 ~ 0 dB | 0 |
| 音乐 | BGM | -60 ~ 0 dB | -6 |
| 音效 | SFX | -60 ~ 0 dB | -3 |
| 语音 | Voice | -60 ~ 0 dB | -3 |
| 环境 | Ambience | -60 ~ 0 dB | -12 |

> `AudioManager.set_bus_volume(bus, db)` 统一封装，滑块 onChange 即调。

### 10.2 字幕系统

重要剧情台词与关键音效配字幕（对齐 [10_ui_ux](10_ui_ux.md) 的对话系统）：
- **剧情台词**：标准对话框（已有设计）。
- **音效字幕**：用方括号标注，如 `[源脉共鸣]`、`[远处号角]`、`[灰潮碎裂]`、`[单位阵亡]`。
- **开关**：设置菜单提供「音效字幕」开关（默认开，服务听障玩家）。

### 10.3 听障玩家的视觉替代

关键音效配视觉反馈，确保听障玩家不依赖声音也能获取信息：

| 音效 | 视觉替代 |
|------|----------|
| 命中/暴击 | 屏幕震动（暴击震动幅度更大） |
| 单位 HP < 25%（`sfx_low_hp_alarm`） | 单位头像闪红边框 + 屏幕边缘血红 vignette |
| 回合开始/结束 | 屏幕中央大字提示（已有 UI） |
| 源脉施法 | 法术特效本身已是视觉的（无需额外） |
| 灰潮石化 | 地图 `.*` 格子有视觉裂纹（[09](09_levels_and_scenes.md) 已设计） |

### 10.4 BGM 暂停规则

- **失焦（窗口非激活）**：Master 自动降至 -12 dB（`get_tree().get_root().focus_exited` 信号触发），避免后台扰人。
- **游戏暂停（Pause）**：BGM 与 Ambience 暂停（`Stream.player.stream_paused = true`），SFX 静音。恢复时淡入。
- **设置菜单打开**：BGM 保持（不暂停），但 SFX 静音（避免试听滑块时被战斗音干扰）。

---

## 十一、资源清单（采购/制作）

### 11.1 数量汇总

| 类型 | 数量 | 单均时长 | 总时长 |
|------|------|----------|--------|
| BGM | 23 首 | 2-3 分钟 | 约 55 分钟 |
| SFX | 50 个 | 0.05-1.5 秒 | — |
| Ambience | 8 轨 | 2-3 分钟 loop | 约 20 分钟 |

### 11.2 获取策略（自制 vs 免版权 vs 外包）

| 类型 | 推荐策略 | 理由 |
|------|----------|------|
| **BGM**（23 首） | **外包给作曲家**（主力）+ 关键曲（标题/结局）定制 | Leitmotif 系统需要动机统一，必须由一位作曲家统筹；免版权素材库无法保证动机贯穿 |
| **UI SFX**（10 个） | **免版权素材库**（freesound.org / Kenney.nl CC0）+ 微调 | UI 音通用性强，CC0 素材充足，省成本 |
| **战斗 SFX**（20 个） | **混合**：武器挥动/命中用免版权（freesound 的 Foley 类）；暴击/死亡等特色音外包定制或合成 | 通用部分省成本，特色部分保差异化 |
| **源脉特色 SFX**（5 个） | **外包定制 / 合成器自制** | 本作听觉签名，必须独家；玻璃琴+drone 需专门合成 |
| **Ambience**（8 轨） | **免版权 + 自制混合**：自然底噪（风/水/火）用 freesound；圣咏/铁砧/源脉脉冲层自制叠加 | 分层配方中底噪可复用 CC0，事件音/偶发音需定制 |
| **环境脚步**（8 个） | **免版权**（freesound Foley 类充足） | 标准 Foley，无需定制 |

**免版权素材库推荐**：
- freesound.org（CC0/CC-BY，最大 Foley 库）
- Kenney.nl（CC0，游戏 UI/SFX 专用包）
- OpenGameArt.org（CC0/CC-BY，BGM 与 SFX 都有）
- Incompetech.com（Kevin MacLeod，CC-BY，BGM）

**外包建议**：
- 优先外包 BGM 的 9 个动机原型（§2）+ 标题曲 + 4 结局曲 = 约 6-8 首核心曲，其余变奏曲可由同一作曲家批量产出（共享动机降低单首成本）。
- 源脉特色 SFX（5 个）单独外包给 sound designer，明确要求「玻璃琴 + 40Hz drone + 碎裂采样」配方。

### 11.3 优先级（MVP 落地顺序）

若资源受限，按以下优先级分批落地：

| 批次 | 内容 | 理由 |
|------|------|------|
| **P0（MVP）** | bus 结构 + AudioManager + 5 个 UI SFX + 1 首战斗 BGM（`player_adv`）+ 1 首敌方回合 BGM + 胜/败结算音 | 跑通「按键有声、战斗有声、回合切换有声」的最小闭环 |
| **P1** | 全部 50 SFX + 8 战斗 BGM + 4 结局 BGM | 覆盖全部玩法事件 |
| **P2** | 全部剧情 BGM（6 首）+ 8 Ambience + 垂直分层 + 源脉特色 SFX | 完整情绪与氛围体验 |
| **P3** | 字幕系统 + 无障碍视觉替代 + 水平重新编排 | 打磨与无障碍 |

---

## 十二、设计自检（对齐 00 设计支柱与禁止清单）

| 自检项 | 结果 |
|--------|------|
| 是否有 Glory 调性音乐盖在 Horrible 画面上？ | 否。胜利用「疲惫的释然」弦乐，非庆典；结局无一圆满（[05](05_story_branches.md) §9） |
| 是否有「魔法万能」的听觉表现？ | 否。源脉施法叠 `motif_graytide` 色；血祭曲（`bgm_story_bloodrite`）是诅咒音；MP 低提示 `sfx_source_scar_drain` |
| 动机是否贯穿主题？ | 是。9 个动机在 23 首 BGM 中变奏重现；主角动机在结局一扭曲成反派动机（§2.7） |
| 音效是否服务即时反馈？ | 是。全部 SFX 用 `.wav`，< 100ms；每个 Mode 转换/信号都有对应音（§7） |
| BGM 是否服务情绪节奏？ | 是。曲目表对齐 15 章紧张度曲线（§3.2）；垂直分层响应战况（§8.1） |
| 环境音是否服务环境叙事？ | 是。8 地点分层配方让玩家「听出」地点（§5）；灰潮前线用「不安静默」传达绝望 |
| 是否与代码库 hook 对齐？ | 是。引用 `battle.gd` Mode 枚举、`turn_manager` 信号、`combat_system`/`skill_system` 函数（§7，已核实行号） |
| 无障碍是否到位？ | 是。5 轨音量滑块 + 音效字幕 + 视觉替代（§10） |

---

## 十三、文档关联

- 上游约束：[00 设计支柱](00_design_pillars.md)（三大支柱、魔法硬约束、禁止清单）
- 世界基底：[01 世界观](01_worldview.md)（源脉/灰潮/信仰——音频核心意象来源）
- 国家动机：[02 国家](02_nations.md)（四国作战风格 → 四国音乐动机 §2.3-2.6）
- 章节情绪：[05 剧情分支](05_story_branches.md)（15 章紧张度 + 4 结局 → BGM 曲目表 §3）
- 地点环境：[09 关卡](09_levels_and_scenes.md)（8 地点 → 环境音配方 §5）
- 视觉协同：[10_ui_ux](10_ui_ux.md)（暗金/铁灰/血红/源脉蓝四色 → 音色映射 §1.3；字幕/设置菜单 §10）
- 代码落地：`godot/scripts/scenes/battle.gd`（Mode 状态机）、`godot/scripts/systems/turn_manager.gd`（phase 信号）、`godot/scripts/systems/combat_system.gd`、`godot/scripts/systems/skill_system.gd`（§7 集成点）

---

*本文档为音乐与音效设计总纲。BGM 曲式细节（小节数/和声进行/配器总谱）与 SFX 的精确频谱参数需在制作阶段与作曲家/sound designer 联调；AudioManager 的 GDScript 实现需与程序确认 autoload 注册与 pool 大小。*
