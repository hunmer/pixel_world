# UI/UX 雪碧图生成提示词列表

> 本文档为 [`10_ui_ux.md`](./10_ui_ux.md) 的**美术资源生产配套**。所有提示词严格服从该文档的「古代魔法 + 庄重史诗」基调与配色表，**全部不含文字**（文字一律由 Godot 端 Label/RichTextLabel 渲染叠加，避免位图字体锯齿与多语言问题），并优先设计为**九宫格可拉伸（9-slice stretchable）**控件。

---

## 0. 使用说明

### 0.1 工作流

1. 将每条「Prompt」原文喂给图像生成模型（Midjourney / Stable Diffusion / DALL·E / Gemini / Nano Banana 等，**英文提示词兼容性最好**）。
2. 生成后**人工复核**：①无任何文字 ②配色命中（见 0.3）③中部为均质纹理（9-slice 前提）④PNG 透明背景。
3. 裁切到指定 `尺寸`，按 `存放路径` 放入 `godot/assets/ui/`，并在 Godot 中导入。
4. 引用时设置 `TextureRect` / `NinePatchRect` 的 `patch_margin_left/right/top/bottom` = 文中标注的 `9-slice 边距`。

### 0.2 通用约束（每条提示词都隐含包含）

- **无文字 / 无字母 / 无数字 / 无符号字形**（`no text, no letters, no numbers, no runes-as-text, no captions, watermark forbidden`）。鲁恩符文仅作为**装饰性图案**，且与任何已知字母体系**不一一对应**。
- **透明背景 PNG**（`transparent background, alpha channel, isolated asset, no backdrop`）。
- **9-slice 友好**：装饰集中在四角和边缘 ≤24px 内，**中央为均质平铺纹理**（`uniform flat center, seamless, tileable middle, decorations confined to corners and borders`）。
- **正交正面视角**，无透视畸变（`front-facing, flat orthographic, game UI sprite`）。
- **2D 风格**，非写实照片（`2D digital painting, hand-painted fantasy game UI, soft cell shading, no photorealism`）。
- **配色锁定**：只能用 0.3 表中的 10 色，禁止第 11 色。

### 0.3 全局配色表（来自 10_ui_ux.md §1.2，**禁止引入第 11 色**）

| 代号 | 色名 | 十六进制 | RGB | 英文描述（写入提示词） |
|---|---|---|---|---|
| G1 | 铁灰 iron-gray | `#2B2B3A` | 43,43,58 | `dark slate blue-gray (#2B2B3A)` |
| G2 | 夜墨 night-ink | `#1A1A24` | 26,26,36 | `near-black ink (#1A1A24)` |
| A1 | 暗金 dark-gold | `#C9A227` | 201,162,39 | `antique gold / dark gold (#C9A227)` |
| A2 | 源脉蓝 ley-blue | `#408CFF` | 64,140,255 | `ley-line azure blue (#408CFF)` |
| D1 | 血红 blood-red | `#B22222` | 178,34,34 | `deep blood red (#B22222)` |
| D2 | 源晶紫 crystal-violet | `#BF59FF` | 191,89,255 | `arcane crystal violet (#BF59FF)` |
| H1 | 翡翠绿 emerald | `#3CB371` | 60,179,113 | `emerald green (#3CB371)` |
| W1 | 烬橙 ember-orange | `#E07B2A` | 224,123,42 | `ember orange (#E07B2A)` |
| T1 | 羊皮 parchment | `#E8D9B0` | 232,217,176 | `aged parchment (#E8D9B0)` |
| T2 | 骨白 bone-white | `#F2EDE0` | 242,237,224 | `bone white (#F2EDE0)` |

### 0.4 全局风格前缀（每条提示词开头拼接）

```
Fantasy tactics RPG UI element, ancient magic + solemn epic tone,
2D hand-painted digital art, soft cell shading, front-facing flat orthographic,
aged parchment texture base with subtle 12% grain noise, wrought-iron embossed borders,
antique gold trim, subtle arcane crystal glow where magical,
PALETTE LOCKED to dark slate blue-gray (#2B2B3A), near-black ink (#1A1A24), antique gold (#C9A227),
ley-line azure (#408CFF), blood red (#B22222), crystal violet (#BF59FF), emerald (#3CB371),
ember orange (#E07B2A), parchment (#E8D9B0), bone white (#F2EDE0).
NO TEXT, NO LETTERS, NO NUMBERS, NO RUNES-AS-TEXT, NO CAPTIONS, NO WATERMARK.
Transparent background PNG, isolated asset, seamless tileable center, 9-slice stretchable.
```

---

## 1. 面板与框架（9-slice Panels）

> 用 `NinePatchRect`。装饰集中在四角（纹章角花/铆钉），中央为羊皮纸纹理，边缘 ≤24px。

### 1.1 通用信息面板 `panel-info`
- **用途**：单位详情、目标提示、通用浮窗（§3.5）。
- **尺寸**：512×256 px。**9-slice 边距**：L/R 28、T 36、B 28。
- **存放**：`godot/assets/ui/frames/panel-info.png`
- **Prompt**：
  ```
  {PREFIX} A rectangular info panel background. Center: aged parchment (#E8D9B0) with faint grain.
  Border: 8px wrought-iron gray (#2B2B3A) embossed frame, inner 2px antique-gold (#C9A227) hairline.
  Four corners: small subtle heraldic scrollwork flourishes in dark gold, kept within 28px corner zones.
  Middle area perfectly flat and uniform for text overlay. Soft inner shadow at edges.
  ```

### 1.2 顶部 HUD 条 `hud-topbar`
- **用途**：§3.1 回合/计数/目标横条。
- **尺寸**：1920×120 px（横长条，仅左右拉伸）。**9-slice 边距**：L/R 60、T 0、B 0。
- **存放**：`godot/assets/ui/frames/hud-topbar.png`
- **Prompt**：
  ```
  {PREFIX} A wide horizontal HUD top bar banner. Base: dark slate blue-gray (#2B2B3A) gradient to near-black (#1A1A24) bottom.
  Top edge: 3px antique-gold (#C9A227) engraved line with tiny ivy-leaf breaks.
  Bottom edge: 2px darker iron shadow. Left and right ends capped with small wrought-iron bracket ornaments
  (heraldic crest hints) confined to 60px end zones. Center 1800px perfectly flat horizontal gradient, no ornaments.
  ```

### 1.3 单位行动菜单背景 `menu-action`
- **用途**：§3.2 攻击/技能/物品/等待/撤销 5 项菜单底板。
- **尺寸**：320×360 px。**9-slice 边距**：L/R 24、T 28、B 24。
- **存放**：`godot/assets/ui/frames/menu-action.png`
- **Prompt**：
  ```
  {PREFIX} A vertical pop-up menu panel, slightly tapered top. Parchment center (#E8D9B0).
  Iron-gray (#2B2B3A) embossed border with gold (#C9A227) inner trim. A single thin gold horizontal divider rule
  baked at 40% from top (decorative notch, no text). Bottom-right corner: tiny wrought-iron hinge stud.
  Flat uniform middle for stacked menu rows. Soft drop shadow outside.
  ```

### 1.4 技能 / 道具选择器面板 `panel-picker`
- **用途**：§3.3 技能/道具列表底板。
- **尺寸**：560×420 px。**9-slice 边距**：L/R 28、T 40、B 28。
- **存放**：`godot/assets/ui/frames/panel-picker.png`
- **Prompt**：
  ```
  {PREFIX} A taller list panel background for skill/item pickers. Parchment (#E8D9B0) center with very faint horizontal pinstripes
  (1px, 4% opacity) to suggest ruled scroll. Iron-gray border, gold inner hairline. Top header zone (40px) separated by a
  gold double-rule, reserved for title (no text rendered). Corner studs at four corners. Uniform list body for row overlay.
  ```

### 1.5 战斗预测面板 `panel-battle-preview`
- **用途**：§3.4 双栏 HP/命中/伤害预测（SRPG 灵魂面板）。
- **尺寸**：640×420 px。**9-slice 边距**：L/R 28、T 40、B 28。
- **存放**：`godot/assets/ui/frames/panel-battle-preview.png`
- **Prompt**：
  ```
  {PREFIX} A battle forecast panel with a baked-in vertical center divider (2px gold double-rule) splitting left/right columns,
  and a baked-in horizontal divider at 70% height for the warning footer zone. Parchment (#E8D9B0) body.
  Iron-gray embossed border, gold trim. Top header band (40px) tinted slightly darker slate.
  Two small heraldic shield silhouettes (empty, blank) as column headers. NO numbers, NO text anywhere.
  ```

### 1.6 整备 Tab 面板 `panel-prep-tab`
- **用途**：§4 编队/装备/技能/转职/物品主操作区。
- **尺寸**：960×640 px。**9-slice 边距**：L/R 32、T 48、B 32。
- **存放**：`godot/assets/ui/frames/panel-prep-tab.png`
- **Prompt**：
  ```
  {PREFIX} A large pre-battle preparation panel background. Parchment (#E8D9B0) center with subtle woven-cloth grain.
  Iron-gray border with corner rivets and small gold crest medallions at four corners (within 32px zones).
  Top header band (48px) with double gold rule beneath, reserved for tab bar overlay. Flat uniform body for tab content.
  ```

### 1.7 设置面板 `panel-settings`
- **用途**：§7 设置界面。
- **尺寸**：640×720 px。**9-slice 边距**：L/R 28、T 40、B 28。
- **存放**：`godot/assets/ui/frames/panel-settings.png`
- **Prompt**：
  ```
  {PREFIX} A tall settings panel. Parchment (#E8D9B0) body. Iron-gray embossed border, gold inner trim.
  Three faint horizontal section dividers (1px gold, 20% opacity) suggesting Display/Game/Audio groupings, no labels.
  Corner scrollwork. Flat uniform sections for option rows.
  ```

### 1.8 对话框 `frame-dialogue`
- **用途**：剧情对话、教学气泡（§6.1）。
- **尺寸**：960×200 px。**9-slice 边距**：L/R 32、T 32、B 40。
- **存放**：`godot/assets/ui/frames/frame-dialogue.png`
- **Prompt**：
  ```
  {PREFIX} A wide dialogue text box. Parchment (#E8D9B0) center. Ornate iron-gray border with gold trim,
  top edge shaped like an unrolled scroll with subtle rolled-end caps at left and right (within 32px zones).
  Small tail/notch at bottom-center suggesting a speech bubble pointer. Flat middle for text.
  ```

### 1.9 胜利卷轴 `scroll-victory`
- **用途**：§5.1 胜利结算展开卷轴。
- **尺寸**：1280×720 px。**9-slice 边距**：L/R 80、T 60、B 60。
- **存放**：`godot/assets/ui/frames/scroll-victory.png`
- **Prompt**：
  ```
  {PREFIX} An unfurled vertical scroll panel for victory results. Center: luminous parchment (#F2EDE0) with faint golden glow.
  Left and right ends: rendered wooden scroll rods with antique-gold (#C9A227) caps (within 80px end zones).
  Top and bottom: subtle rolled parchment edges. A thin gold double-border frame inset 20px.
  Faint laurel-wreath watermarks at top-center and bottom-center (decorative only, no text). Flat body for content overlay.
  ```

### 1.10 失败卷轴 `scroll-defeat`
- **用途**：§5.2 全军覆没。
- **尺寸**：1280×720 px。**9-slice 边距**：L/R 80、T 60、B 60。
- **存放**：`godot/assets/ui/frames/scroll-defeat.png`
- **Prompt**：
  ```
  {PREFIX} A battle-scarred scroll panel for defeat screen. Same form as a victory scroll but: parchment tinted toward ash-gray
  with cracks and burn marks at edges, blood-red (#B22222) inner border glow, scroll rods darker and slightly chipped.
  Faint cracked-heraldic watermark at center (no text). Somber, not humiliating. Flat body for content.
  ```

### 1.11 结果横幅 `banner-result`
- **用途**：现有 `show_result_banner` 升级，胜负共用底。
- **尺寸**：1024×160 px。**9-slice 边距**：L/R 60、T 24、B 24。
- **存放**：`godot/assets/ui/frames/banner-result.png`
- **Prompt**：
  ```
  {PREFIX} A horizontal result banner ribbon. Center dark slate (#2B2B3A). Gold (#C9A227) engraved top and bottom rules.
  Tapered ribbon ends at left/right (within 60px) with small gold tassels. Flat middle for big title text overlay.
  ```

---

## 2. 按钮（9-slice Buttons）

> 全部 9-slice，三态可共用底图 + 程序化叠色，或分别出 hover/pressed/disabled。下表给出**底图（normal 态）**；其余态在 §2.13 统一说明。推荐 `NinePatchRect`/`Button` 配合 `Theme` 资源使用。

### 2.1 主确认按钮 `btn-confirm`
- **用途**：出击、确认攻击（§3.4 §4）。**尺寸**：260×60 px。**9-slice**：L/R 24、T 20、B 20。
- **存放**：`godot/assets/ui/buttons/btn-confirm.png`
- **Prompt**：
  ```
  {PREFIX} A primary confirmation button background. Parchment (#E8D9B0) face with a raised gold (#C9A227) beveled border (3px)
  and inner iron-gray (#2B2B3A) thin line. Subtle top highlight, bottom shadow for embossed feel.
  Center perfectly flat for label. NO text.
  ```

### 2.2 取消按钮 `btn-cancel`
- **用途**：取消、撤销移动（§3.2）。**尺寸**：220×56 px。**9-slice**：L/R 22、T 18、B 18。
- **存放**：`godot/assets/ui/buttons/btn-cancel.png`
- **Prompt**：
  ```
  {PREFIX} A secondary cancel button. Iron-gray (#2B2B3A) face with dark gold (#C9A227) thin border (1px).
  Slightly muted/desaturated vs primary. Flat center, no text.
  ```

### 2.3 菜单项按钮 `btn-menu-item`
- **用途**：§3.2 菜单每一行（攻击/技能/物品/等待/撤销）。
- **尺寸**：280×48 px。**9-slice**：L/R 16、T 14、B 14。
- **存放**：`godot/assets/ui/buttons/btn-menu-item.png`
- **Prompt**：
  ```
  {PREFIX} A menu row button background, slim and horizontal. Parchment (#E8D9B0) face with hairline gold (#C9A227) top and bottom rules,
  no side borders (open-ended). Flat uniform surface. No text, no icons.
  ```

### 2.4 推荐高亮按钮 `btn-menu-item-recommended`
- **用途**：§3.2 推荐项描暗金边。
- **尺寸**：280×48 px。**9-slice**：L/R 16、T 14、B 14。
- **存放**：`godot/assets/ui/buttons/btn-menu-item-recommended.png`
- **Prompt**：
  ```
  {PREFIX} Same as menu item button but with a brighter glowing gold (#C9A227) full 2px border and a soft inner gold halo (8% opacity)
  to mark it as recommended. Parchment face slightly warmer. No text.
  ```

### 2.5 技能按钮 `btn-skill`
- **用途**：§3.3 技能行、整备技能槽。
- **尺寸**：520×48 px。**9-slice**：L/R 18、T 14、B 14。
- **存放**：`godot/assets/ui/buttons/btn-skill.png`
- **Prompt**：
  ```
  {PREFIX} A skill list row button. Left zone (18px) tinted faint arcane violet (#BF59FF) to signal magic.
  Parchment body, hairline gold rules top/bottom. Flat for label + cost columns. No text.
  ```

### 2.6 物品按钮 `btn-item`
- **用途**：§3.3 道具行、整备物品库。
- **尺寸**：520×48 px。**9-slice**：L/R 18、T 14、B 14。
- **存放**：`godot/assets/ui/buttons/btn-item.png`
- **Prompt**：
  ```
  {PREFIX} An item list row button. Left zone (18px) tinted faint emerald (#3CB371). Parchment body, hairline gold rules.
  Flat for label + count. No text.
  ```

### 2.7 攻击按钮 `btn-attack`
- **用途**：§3.2 攻击项专用（可选，也可复用 btn-menu-item）。
- **尺寸**：280×48 px。**9-slice**：L/R 16、T 14、B 14。
- **存放**：`godot/assets/ui/buttons/btn-attack.png`
- **Prompt**：
  ```
  {PREFIX} An attack action menu button. Left zone (16px) tinted blood-red (#B22222). Parchment body, gold hairline rules.
  Flat center. No text.
  ```

### 2.8 结束回合按钮 `btn-end-turn`
- **用途**：§3 右下角高频按钮（Fitts 贴角）。
- **尺寸**：220×64 px。**9-slice**：L/R 24、T 22、B 22。
- **存放**：`godot/assets/ui/buttons/btn-end-turn.png`
- **Prompt**：
  ```
  {PREFIX} A prominent end-turn button, larger and corner-anchored feel. Iron-gray (#2B2B3A) face with thick gold (#C9A227) beveled border (3px)
  and a thin blood-red (#B22222) accent line on the bottom edge. Embossed. Flat center, no text.
  ```

### 2.9 Tab 按钮 `btn-tab`
- **用途**：§4 编队/装备/技能/转职/物品 5 个 Tab。
- **尺寸**：140×44 px。**9-slice**：L/R 16、T 12、B 12。
- **存放**：`godot/assets/ui/buttons/btn-tab.png`
- **Prompt**：
  ```
  {PREFIX} A tab button background (inactive state). Parchment (#E8D9B0) top half, iron-gray (#2B2B3A) bottom half,
  separated by a hairline gold rule. Slightly raised. Flat for label. No text.
  ```

### 2.10 Tab 按钮（激活态）`btn-tab-active`
- **用途**：当前选中 Tab。**尺寸/9-slice** 同上。
- **存放**：`godot/assets/ui/buttons/btn-tab-active.png`
- **Prompt**：
  ```
  {PREFIX} Active tab button. Full parchment (#E8D9B0) face with a bright gold (#C9A227) 2px border on top and sides
  (open bottom, connecting to panel). Subtle inner glow. Flat center, no text.
  ```

### 2.11 勾选框 `checkbox`
- **用途**：§4 编队勾选上场单位。
- **尺寸**：32×32 px（固定，非拉伸）。**9-slice**：无（固定尺寸）。
- **存放**：`godot/assets/ui/controls/checkbox.png`（未勾选）、`checkbox-checked.png`（勾选）
- **Prompt（未勾选）**：
  ```
  {PREFIX} A small empty checkbox, 32x32. Iron-gray (#2B2B3A) square frame with gold (#C9A227) inner bevel, transparent center.
  Slight emboss. No text, no checkmark.
  ```
- **Prompt（勾选）**：
  ```
  {PREFIX} Same checkbox frame but with a bold gold (#C9A227) hand-painted checkmark stroke inside. No text.
  ```

### 2.12 单选项圆点 `radio`
- **用途**：§7 设置项（文字大小/色盲模式/永久死亡等单选）。
- **尺寸**：28×28 px（固定）。**存放**：`godot/assets/ui/controls/radio.png`、`radio-selected.png`
- **Prompt（未选）**：
  ```
  {PREFIX} A small empty radio circle, 28x28. Iron-gray ring with gold inner bevel, transparent center. No text.
  ```
- **Prompt（选中）**：
  ```
  {PREFIX} Same radio ring with a solid gold (#C9A227) filled dot in the center. No text.
  ```

### 2.13 按钮三态通用变体（可选，若不用程序化叠色）

> 若希望逐态出图，对每个按钮再产出 `*-hover.png` / `*-pressed.png` / `*-disabled.png`：
> - **hover**：在 Prompt 末加 `add a subtle warm gold (#C9A227) inner glow, slightly brighter face`。
> - **pressed**：加 `face shifted darker, border compressed, subtle inset shadow`。
> - **disabled**：加 `desaturated to 50% grayscale, opacity reduced, no glow`。

---

## 3. 进度条与计量条（9-slice Bars）

> 结构：**底槽（9-slice）** + **填充（程序化宽度，左对齐拉伸）**。填充颜色由代码按 §3.4 规则（>50% 绿/25-50% 金/<25% 红）切换，故只出底槽 + 各色填充条端帽。

### 3.1 HP 条底槽 `bar-hp-frame`
- **用途**：§3.4 双方 HP 条。**尺寸**：200×20 px。**9-slice**：L/R 8、T 6、B 6。
- **存放**：`godot/assets/ui/bars/bar-hp-frame.png`
- **Prompt**：
  ```
  {PREFIX} A horizontal HP bar frame/background slot. Iron-gray (#2B2B3A) trough with gold (#C9A227) thin border and inner bevel.
  Parchment (#E8D9B0) empty trough fill. Rounded left and right end caps (within 8px). Flat interior for fill overlay. No text.
  ```

### 3.2 HP 条填充（三色端帽）`bar-hp-fill-*`
- **用途**：填充部分，左端为圆头端帽，右端平直（程序化裁切）。**尺寸**：200×16 px（满宽，宽度由代码缩放）。**9-slice**：L 8（端帽）、R 2、T 4、B 4。
- **存放**：`godot/assets/ui/bars/bar-hp-fill-green.png` / `-gold.png` / `-red.png`
- **Prompt（绿，HP>50%）**：
  ```
  {PREFIX} A horizontal HP fill bar, emerald green (#3CB371) with a subtle vertical gradient (lighter top). Rounded left end cap (8px),
  flat right edge. Thin darker green bottom shadow. Uniform middle for width stretch. No text.
  ```
- **Prompt（金，25-50%）**：同上，颜色换 `antique gold (#C9A227)`。
- **Prompt（红，<25%）**：同上，颜色换 `blood red (#B22222)`，加 `subtle pulsing-danger feel (static image, just visual cue)`。

### 3.3 MP 条 `bar-mp-*`
- **用途**：§3.3 §4 MP 总量（呼应魔法稀缺）。
- **尺寸**：底槽 160×16；填充 160×12。**9-slice**：底 L/R 8、T 5、B 5；填充 L 8、R 2、T 3、B 3。
- **存放**：`godot/assets/ui/bars/bar-mp-frame.png`、`bar-mp-fill.png`
- **Prompt（底槽）**：
  ```
  {PREFIX} An MP bar frame. Iron-gray trough, arcane crystal violet (#BF59FF) thin border to signal magic.
  Parchment empty trough. Rounded ends. No text.
  ```
- **Prompt（填充）**：
  ```
  {PREFIX} An MP fill bar, arcane crystal violet (#BF59FF) with faint ley-line shimmer (static), lighter top gradient.
  Rounded left cap, flat right. Uniform middle. No text.
  ```

### 3.4 EXP 条 `bar-exp-*`
- **用途**：§3.5 §5.1 经验条。
- **尺寸**：底槽 240×12；填充 240×8。**9-slice**：底 L/R 6、T 4、B 4；填充 L 6、R 2、T 2、B 2。
- **存放**：`godot/assets/ui/bars/bar-exp-frame.png`、`bar-exp-fill.png`
- **Prompt（底槽）**：`{PREFIX} A slim EXP bar frame. Iron-gray trough, gold hairline border. Parchment empty. Rounded ends. No text.`
- **Prompt（填充）**：`{PREFIX} An EXP fill bar, bone-white (#F2EDE0) to gold (#C9A227) horizontal gradient. Rounded left cap. Uniform middle. No text.`

### 3.5 友军 HP 池（迷你）`bar-team-pool`
- **用途**：§3.1 顶部 HUD「友军存活/总数」迷你池。
- **尺寸**：120×10 px。**9-slice**：L/R 5、T 3、B 3。
- **存放**：`godot/assets/ui/bars/bar-team-pool.png`
- **Prompt**：
  ```
  {PREFIX} A tiny team HP pool bar frame, very slim. Iron-gray trough, gold hairline border, parchment empty.
  Rounded ends. Flat interior. No text. (Fill color applied programmatically.)
  ```

### 3.6 滑块轨道 `slider-track`
- **用途**：§7 音量滑块。
- **尺寸**：240×12 px。**9-slice**：L/R 6、T 4、B 4。
- **存放**：`godot/assets/ui/controls/slider-track.png`
- **Prompt**：
  ```
  {PREFIX} A horizontal slider track groove. Iron-gray (#2B2B3A) channel with inner shadow, gold (#C9A227) hairline edges.
  Parchment center groove. Rounded ends. No text.
  ```

### 3.7 滑块手柄 `slider-thumb`
- **用途**：§7 音量手柄。**尺寸**：24×28 px（固定）。
- **存放**：`godot/assets/ui/controls/slider-thumb.png`
- **Prompt**：
  ```
  {PREFIX} A vertical slider thumb/knob. Small antique-gold (#C9A227) rounded gem or bead with iron-gray base,
  subtle highlight. Front-facing. No text.
  ```

---

## 4. 图标（Icons，独立小尺寸，**无文字**）

> 全部 64×64 px 透明 PNG，正交正面。用于行尾元素标识、buff、状态。

### 4.1 武器三角（克制关系，链 03）
| 文件 | 存放 | Prompt 关键词 |
|---|---|---|
| `icon-wt-sword.png` | `godot/assets/ui/icons/` | `{PREFIX} A simple heraldic sword icon pointing up, steel blade, gold hilt, on transparent bg. 64x64. No text.` |
| `icon-wt-axe.png` | 同上 | `{PREFIX} A simple heraldic battle-axe icon, steel head, wood-and-gold haft. 64x64. No text.` |
| `icon-wt-lance.png` | 同上 | `{PREFIX} A simple heraldic lance/spear icon pointing up-right, steel tip, gold shaft. 64x64. No text.` |
| `icon-wt-arrow-up.png` | 同上 | `{PREFIX} A small green emerald (#3CB371) upward advantage arrow (favorable weapon triangle). 64x64. No text.` |
| `icon-wt-arrow-down.png` | 同上 | `{PREFIX} A small blood-red (#B22222) downward disadvantage arrow (unfavorable weapon triangle). 64x64. No text.` |

### 4.2 元素图标（链 07 技能元素）
| 文件 | Prompt 关键词 |
|---|---|
| `icon-elem-fire.png` | `{PREFIX} A small flame icon, warm orange-red gradient toward gold core. 64x64. No text.` |
| `icon-elem-water.png` | `{PREFIX} A small water-drop icon, azure (#408CFF) with highlight. 64x64. No text.` |
| `icon-elem-wind.png` | `{PREFIX} A small swirling wind/gust icon, pale parchment-white. 64x64. No text.` |
| `icon-elem-earth.png` | `{PREFIX} A small stone/rock icon, iron-gray with gold vein. 64x64. No text.` |
| `icon-elem-light.png` | `{PREFIX} A small radiant sun-burst icon, bone-white-gold. 64x64. No text.` |
| `icon-elem-dark.png` | `{PREFIX} A small shadowy crescent icon, near-black with violet edge. 64x64. No text.` |

### 4.3 状态与提示图标（§3 §5 §6）
| 文件 | 用途 | Prompt 关键词 |
|---|---|---|
| `icon-status-buff.png` | §3.5 buff 标记 | `{PREFIX} A small upward chevron badge in emerald (#3CB371), heraldic. 64x64. No text.` |
| `icon-status-debuff.png` | debuff 标记 | `{PREFIX} A small downward chevron badge in blood-red (#B22222). 64x64. No text.` |
| `icon-alert-idle.png` | §6.2 未行动单位头顶金色叹号 | `{PREFIX} A bold gold (#C9A227) exclamation mark, heraldic banner style, vertical. 64x64. No other text.` |
| `icon-kill-skull.png` | §5.1 击杀/阵亡 | `{PREFIX} A small heraldic skull icon, bone-white with dark eye sockets, solemn not gory. 64x64. No text.` |
| `icon-warning.png` | §3.4 §6.2 危险预警 ⚠ | `{PREFIX} A triangular warning sign, ember-orange (#E07B2A) border, dark interior, heraldic. 64x64. No text, no exclamation inside.` |
| `icon-star-recommend.png` | §3.2 §3.3 推荐 ★ | `{PREFIX} A small five-point antique-gold (#C9A227) star with subtle glow. 64x64. No text.` |
| `icon-autosave.png` | §5.2 自动存档提示 | `{PREFIX} A small heraldic quill-and-scroll icon in gold. 64x64. No text.` |
| `icon-death-permanent.png` | §5.1 永久死亡标记 | `{PREFIX} A small broken-heraldic-shield icon, blood-red cracks. 64x64. No text.` |

### 4.4 操作图标（按钮上的小图，非文字）
| 文件 | 用途 | Prompt 关键词 |
|---|---|---|
| `icon-action-attack.png` | 攻击 | `{PREFIX} Two crossed swords icon, steel + gold, heraldic. 64x64. No text.` |
| `icon-action-skill.png` | 技能 | `{PREFIX} An arcane crystal/orb icon, violet (#BF59FF) glow. 64x64. No text.` |
| `icon-action-item.png` | 物品 | `{PREFIX} A small potion flask icon, parchment body, emerald liquid. 64x64. No text.` |
| `icon-action-wait.png` | 等待 | `{PREFIX} A small hourglass icon, gold frame, parchment sand. 64x64. No text.` |
| `icon-action-undo.png` | 撤销移动 | `{PREFIX} A small curved-arrow undo icon, gold. 64x64. No text.` |
| `icon-end-turn.png` | 结束回合 | `{PREFIX} A small heraldic hourglass-with-banner icon, gold and iron-gray. 64x64. No text.` |
| `icon-hosting.png` | 托管 | `{PREFIX} A small crown-scepter "command" icon, gold. 64x64. No text.` |

---

## 5. 光标与范围色块（对齐 range_overlay.gd §3.6）

> 这些**不是 9-slice 控件**，是等距战场上贴地的菱形/方块精灵，文档要求沿用 `_make_flat_diamond_frame` / `_make_flat_quad` 机制。

### 5.1 金色光标 `cursor-gold`
- **用途**：§3.6 浮动呼吸光标（对齐 `_CURSOR_COLOR`）。
- **尺寸**：128×128 px（等距菱形）。**存放**：`godot/assets/ui/cursors/cursor-gold.png`
- **Prompt**：
  ```
  {PREFIX} An isometric diamond-shaped tile cursor outline, antique-gold (#C9A227) glowing wireframe border, transparent interior,
  subtle inner soft glow. Flat top-down isometric perspective. No fill texture, no text. 128x128.
  ```

### 5.2 范围色块（贴地描边/半透明填充）
> 六色，每色一张菱形/方块。代码层组合使用。尺寸统一 128×128。
| 文件 | 含义 | Prompt |
|---|---|---|
| `range-movable.png` | 蓝色可移动 §3.6 | `{PREFIX} Flat isometric diamond tile overlay, semi-transparent ley-blue (#408CFF) fill 35% opacity, brighter azure border. No text. 128x128.` |
| `range-blocked.png` | 红色被占 | `{PREFIX} ... blood-red (#B22222) fill 35%, red border ...` |
| `range-attack.png` | 紫色攻击 | `{PREFIX} ... arcane crystal violet (#BF59FF) fill 35%, violet border ...` |
| `range-heal.png` | 绿色治疗（新） | `{PREFIX} ... emerald (#3CB371) fill 35%, green border ...` |
| `range-danger.png` | 橙色危险移动（新） | `{PREFIX} Flat isometric diamond tile overlay: ley-blue (#408CFF) base 25% fill with ember-orange (#E07B2A) diagonal hatch stripes 30% on top, orange border. No text. 128x128.` |
| `range-selected.png` | 金色选中底 | `{PREFIX} ... antique-gold (#C9A227) fill 20%, gold border ...` |

### 5.3 引导箭头（§6.1 新手引导）
| 文件 | 用途 | Prompt |
|---|---|---|
| `arrow-guide-gold.png` | 首次移动指向任务点的金色箭头 | `{PREFIX} A bold antique-gold (#C9A227) downward-pointing arrow, heraldic ribbon style, slight glow. 96x96. No text.` |
| `arrow-countdown-red.png` | 敌人头顶红色倒计时箭头 | `{PREFIX} A bold blood-red (#B22222) downward-pointing arrow, sharp, danger feel. 96x96. No text.` |

---

## 6. 装饰元素（Ornaments，用于面板/分隔）

### 6.1 蔓藤分隔线 `divider-vine`
- **用途**：§3.2 §1.2 分组分隔线（横向）。
- **尺寸**：480×24 px。**9-slice**：L/R 40（端叶）、T 0、B 0。
- **存放**：`godot/assets/ui/ornaments/divider-vine.png`
- **Prompt**：
  ```
  {PREFIX} A horizontal decorative divider: a thin gold (#C9A227) center rule with two small ivy/vine leaf flourishes
  at left and right ends (within 40px), small center medallion. Transparent middle above/below the rule. 480x24. No text.
  ```

### 6.2 纹章角花 `corner-crest`
- **用途**：面板四角装饰（也可单独贴）。
- **尺寸**：64×64 px（固定）。**存放**：`godot/assets/ui/ornaments/corner-crest-tl.png`（左上）、`-tr` / `-bl` / `-br` 镜像。
- **Prompt（左上）**：
  ```
  {PREFIX} An L-shaped heraldic corner ornament, antique-gold (#C9A227) scrollwork with small ivy leaves and a tiny rivet,
  for top-left corner of a panel. 64x64. Transparent outside the L. No text.
  ```

### 6.3 鲁恩符文 MP 单位 `rune-mp-unit`
- **用途**：§1.2 MP 用鲁恩符文做单位（装饰性，§0.2 已要求与字母不对应）。
- **尺寸**：24×32 px（固定）。**存放**：`godot/assets/ui/ornaments/rune-mp-unit.png`
- **Prompt**：
  ```
  {PREFIX} A single small decorative rune glyph (purely ornamental, NOT corresponding to any real alphabet),
  carved-stone look with arcane violet (#BF59FF) etched glow. 24x32. No text caption.
  ```

### 6.4 卷轴端帽 `scroll-cap`
- **用途**：§5.1 卷轴两端木轴（若 1.9 单独出图不便）。
- **尺寸**：80×720 px（固定，贴在卷轴左右）。**存放**：`godot/assets/ui/ornaments/scroll-cap-left.png`、`-right.png`
- **Prompt（左）**：
  ```
  {PREFIX} A vertical wooden scroll rod with antique-gold (#C9A227) end caps, slightly aged, front-facing. 80x720. No text.
  ```

### 6.5 国徽底（四国，链 02）
> 每国一枚空徽记底，便于代码叠字符立绘。64×64。
| 文件 | Prompt |
|---|---|
| `crest-blackiron.png` | `{PREFIX} A heraldic shield crest background for a nation themed "Black Iron" — iron-gray (#2B2B3A) field, gold (#C9A227) border, blank center, tiny hammer-anvil silhouette top. 64x64. No text.` |
| `crest-velanthor.png` | `{PREFIX} ... "Velanthor" — deep blue field, silver-gold border, tiny crescent moon top ...` |
| `crest-shattered-moon.png` | `{PREFIX} ... "Shattered Moon" — violet field, silver border, tiny cracked-moon top ...` |
| `crest-emberfolk.png` | `{PREFIX} ... "Emberfolk" — ember-orange (#E07B2A) field, dark border, tiny flame top ...` |

---

## 7. 生成批次建议（实操顺序）

1. **批次 1 — 面板骨架**（§1.1–1.8）：先有底板，UI 才能搭起来。
2. **批次 2 — 按钮**（§2.1–2.12）：交互可用。
3. **批次 3 — 计量条**（§3）：HP/MP/EXP，核心战场反馈。
4. **批次 4 — 图标**（§4）：分两组并行：武器三角+元素 / 状态+操作。
5. **批次 5 — 光标与范围**（§5）：战场可视化。
6. **批次 6 — 装饰**（§6）：打磨质感。

---

## 8. 交付前自检清单（服从 10_ui_ux.md §附录B + 本文 §0.2）

- [ ] **无文字**：每张图肉眼/识图复核，无字母数字符号字形（装饰性鲁恩符文除外且不对应真实字母）。
- [ ] **配色 ≤10 色**：仅用 §0.3 表，无第 11 色。
- [ ] **9-slice 可拉伸**：装饰集中在边角 ≤24px，中央均质；用 `NinePatchRect` 测试 2× 和 0.5× 拉伸无畸变。
- [ ] **透明背景 PNG**：非全屏元素必须透明；全屏卷轴可保留自有背景。
- [ ] **正交正面**：无透视畸变（光标/范围块按等距菱形视角除外）。
- [ ] **命名一致**：文件名严格按本文「存放路径」列，便于代码引用与 `theme_create`/`theme_set_stylebox` 对齐。
- [ ] **风格统一**：羊皮纸 + 铁灰 + 暗金基调贯穿，无科幻/现代/赛博元素混入。
- [ ] **对齐文档**：HP 三色（绿/金/<25% 红）、范围六色（蓝/红/紫/金/绿/橙）严格命中。

---

## 9. 与代码对接备忘（给实现阶段）

- 面板/按钮/条 → `NinePatchRect`，`patch_margin_*` 取本文「9-slice 边距」。
- 按钮 hover/pressed/disabled 三态建议用 `Theme` 资源（`theme_set_stylebox` for `Button.normal/hover/pressed/disabled`），而非每态一张图——除非按 §2.13 显式出图。
- HP 条填充宽度 = `NinePatchRect` 或 `TextureRect` + `size.x = max_w * hp_ratio`，颜色按 §3.4 切换三张填充图。
- 光标与范围块仍是 `range_overlay.gd` 的 `_make_flat_diamond_frame` / `_make_flat_quad` 程序生成路径；本文 §5 的 PNG 作为**可选美术替换**，需在代码中加 `_USE_SPRITE_OVERLAY` 开关。
- 图标统一放 `godot/assets/ui/icons/`，命名与 `06_items.md` / `07_skills` 数据字段对齐，便于按 id 拼路径加载。
