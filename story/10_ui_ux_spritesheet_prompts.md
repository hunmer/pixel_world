# UI/UX 雪碧图生成指令（可直接使用）

> 本文档为 [`10_ui_ux.md`](./10_ui_ux.md) 的**可直接执行的生图指令集**。把同族控件（共享笔触/光照/材质/配色）合并到**一张雪碧图**里生成——这是保证整套 UI 风格一致性的最有效手段。共 **8 张雪碧图**，每张配完整展开的 prompt（复制即用，无 `{PREFIX}` 占位符）+ 裁切坐标表 + 9-slice 边距。
>
> 配套单图清单见 [`10_ui_ux_assets_prompts.md`](./10_ui_ux_assets_prompts.md)。

---

## 0. 通用约定（所有 8 张图共用）

### 0.1 风格基调
- 古代魔法 + 庄重史诗（fantasy tactics RPG，ancient magic + solemn epic）
- 2D 手绘数字绘画，柔和色块阴影（soft cell shading），正交正面视角，无透视畸变
- 羊皮纸纹理底（`#E8D9B0` + 12% 噪声）/ 铁灰浮雕边框（`#2B2B3A`）/ 暗金描边（`#C9A227`）/ 魔法元素嵌源晶自发光

### 0.2 配色锁定（**禁止第 11 色**）
| 色 | 十六进制 | 用途 |
|---|---|---|
| 铁灰 `#2B2B3A` | 面板/边框底 | 夜墨 `#1A1A24` | 全屏遮罩 |
| 暗金 `#C9A227` | 描边/光标/标题 | 源脉蓝 `#408CFF` | 可移动/MP |
| 血红 `#B22222` | 低血/被占/攻击辅 | 源晶紫 `#BF59FF` | 攻击范围 |
| 翡翠绿 `#3CB371` | 治疗/buff | 烬橙 `#E07B2A` | 危险移动 |
| 羊皮 `#E8D9B0` | 正文/底 | 骨白 `#F2EDE0` | 标题文字 |

### 0.3 强约束（写进每条 prompt）
- **NO TEXT, NO LETTERS, NO NUMBERS, NO RUNES-AS-TEXT, NO CAPTIONS, NO WATERMARK** —— 文字一律由 Godot Label 渲染叠加。
- **透明背景 PNG** —— 用 `magic chroma key: pure magenta #FF00FF background`（生成后再用脚本抠成透明）。
- **9-slice 友好**：面板/按钮/条的装饰集中在四角和边缘 ≤24px 内，**中央为均质平铺纹理**，可直接 `NinePatchRect` 拉伸。
- **网格规整**：每张图内 cells 等间距网格排列，cells 之间留 16px 间隙（避免裁切串色）。

### 0.4 工作流
1. 用下方 prompt 生成雪碧图（建议分辨率：长边 ≤ 2048px，避免模型在超大画布上混乱）。
2. 用 §10 的 Python 脚本按坐标表自动裁切 + magic pink 抠透明。
3. 按「存放路径」放入 `godot/assets/ui/`，Godot 自动导入。
4. `NinePatchRect` 按「9-slice 边距」设 `patch_margin_*`。

---

## 雪碧图 ① 面板家族 `spritesheet-panels.png`

> **同类合并理由**：所有信息面板共享「羊皮纸底 + 铁灰边 + 暗金描边 + 角部纹章」的同一套质感，一张图生成能保证 11 个面板视觉完全统一。

- **画布**：2048 × 1536 px
- **网格**：4 列 × 3 行（cell 间距 16px）
- **背景**：纯品红 `#FF00FF`（magic chroma key，后处理抠透明）

### Prompt（复制即用）

```
A fantasy tactics RPG UI sprite sheet of ELEVEN rectangular panel and frame backgrounds, arranged in a neat 4-column by 3-row grid with 16px gutters between each panel, on a SOLID PURE MAGENTA (#FF00FF) background for chroma keying.

Style: ancient magic + solemn epic tone, 2D hand-painted digital art, soft cell shading, flat orthographic front-facing. Aged parchment texture base (#E8D9B0) with subtle 12% grain noise. Wrought-iron embossed borders in dark slate blue-gray (#2B2B3A). Antique gold (#C9A227) thin inner trim hairlines. Subtle arcane crystal glow only on magical accents.

Grid contents (left-to-right, top-to-bottom):
Row 1:
  [1] INFO PANEL 512x256 — parchment center, 8px iron-gray embossed frame, 2px gold inner hairline, small heraldic scrollwork flourishes confined to four 28px corner zones, uniform flat middle, soft inner edge shadow.
  [2] HUD TOP BAR 1024x120 (wide horizontal banner) — dark slate blue-gray (#2B2B3A) gradient to near-black (#1A1A24) bottom, 3px gold engraved top line with tiny ivy-leaf breaks, 2px darker iron bottom shadow, wrought-iron bracket crest ornaments confined to 60px left and right end caps, flat 900px middle.
  [3] ACTION MENU 320x360 — vertical pop-up, slightly tapered top, parchment center, iron-gray border with gold trim, one thin decorative gold horizontal notch at 40% height (no text), small iron hinge stud at bottom-right corner.
  [4] PICKER PANEL 560x420 — taller list panel, parchment center with very faint 1px horizontal pinstripes at 4% opacity suggesting ruled scroll, iron-gray border, gold inner hairline, top 40px header zone separated by gold double-rule, four corner rivets.
Row 2:
  [5] BATTLE FORECAST PANEL 640x420 — parchment body with a BAKED-IN vertical center divider (2px gold double-rule) splitting left/right columns, BAKED-IN horizontal divider at 70% height for warning footer, top 40px header band tinted darker slate, two small blank heraldic shield silhouettes as column headers (empty, no charges).
  [6] PREP TAB PANEL 960x640 — large preparation panel, parchment center with subtle woven-cloth grain, iron-gray border with corner rivets and small gold crest medallions confined to 32px corner zones, top 48px header band with double gold rule beneath.
  [7] SETTINGS PANEL 640x720 — tall panel, parchment body, iron-gray embossed border, gold inner trim, three faint 1px gold horizontal section dividers at 20% opacity (no labels), corner scrollwork.
  [8] DIALOGUE BOX 960x200 — wide dialogue text box, parchment center, ornate iron-gray border with gold trim, top edge shaped like an unrolled scroll with subtle rolled-end caps at left/right within 32px, small speech-bubble tail notch at bottom-center.
Row 3:
  [9] VICTORY SCROLL 1024x600 — unfurled vertical scroll, luminous parchment (#F2EDE0) center with faint golden glow, rendered wooden scroll rods with antique-gold caps confined to 80px left/right end zones, subtle rolled parchment edges top/bottom, thin gold double-border inset 20px, faint laurel-wreath watermarks at top-center and bottom-center.
  [10] DEFEAT SCROLL 1024x600 — same scroll form but parchment tinted toward ash-gray with cracks and burn marks at edges, blood-red (#B22222) inner border glow, darker chipped scroll rods, faint cracked-heraldic watermark at center, somber not gory.
  [11] RESULT BANNER 1024x160 — horizontal ribbon, dark slate (#2B2B3A) center, gold engraved top and bottom rules, tapered ribbon ends at left/right within 60px with small gold tassels, flat middle.
  [12] (empty magenta cell, leave blank for symmetry)

ABSOLUTE RULES: NO TEXT, NO LETTERS, NO NUMBERS, NO RUNES-AS-TEXT, NO LABELS, NO CAPTIONS, NO WATERMARK anywhere. All panel centers must be perfectly uniform and flat (suitable for 9-slice stretching and text overlay). Transparent-ready: solid magenta background only outside the panels. Each panel clearly separated by 16px magenta gutters. Crisp pixel boundaries.
```

### 裁切坐标表（cell 原点 = 左上角，单位 px；cell 间留 16px gutter）

| # | 名称 | cell 尺寸 | 行列 | 存放路径 | 9-slice (L/R/T/B) |
|---|---|---|---|---|---|
| 1 | panel-info | 512×256 | R1C1 | `ui/frames/panel-info.png` | 28/28/36/28 |
| 2 | hud-topbar | 1024×120 | R1C2 | `ui/frames/hud-topbar.png` | 60/60/0/0 |
| 3 | menu-action | 320×360 | R1C3 | `ui/frames/menu-action.png` | 24/24/28/24 |
| 4 | panel-picker | 560×420 | R1C4 | `ui/frames/panel-picker.png` | 28/28/40/28 |
| 5 | panel-battle-preview | 640×420 | R2C1 | `ui/frames/panel-battle-preview.png` | 28/28/40/28 |
| 6 | panel-prep-tab | 960×640 | R2C2 | `ui/frames/panel-prep-tab.png` | 32/32/48/32 |
| 7 | panel-settings | 640×720 | R2C3 | `ui/frames/panel-settings.png` | 28/28/40/28 |
| 8 | frame-dialogue | 960×200 | R2C4 | `ui/frames/frame-dialogue.png` | 32/32/32/40 |
| 9 | scroll-victory | 1024×600 | R3C1 | `ui/frames/scroll-victory.png` | 80/80/60/60 |
| 10 | scroll-defeat | 1024×600 | R3C2 | `ui/frames/scroll-defeat.png` | 80/80/60/60 |
| 11 | banner-result | 1024×160 | R3C3 | `ui/frames/banner-result.png` | 60/60/24/24 |

> ⚠️ 实际生成图各 cell 尺寸会有偏差，**裁切脚本应以「最大内切矩形 + 手动微调」为准**，不强求精确命中表内尺寸（Godot 端 `NinePatchRect` 对绝对尺寸不敏感，只看比例）。

---

## 雪碧图 ② 按钮家族 `spritesheet-buttons.png`

> **同类合并理由**：所有按钮共享同一套「羊皮纸/铁灰面 + 暗金斜面边」的浮雕语言，一张图统一光照方向与金边厚度。

- **画布**：1536 × 768 px
- **网格**：4 列 × 2 行（cell 间距 16px）
- **背景**：纯品红 `#FF00FF`

### Prompt

```
A fantasy tactics RPG UI sprite sheet of EIGHT button backgrounds arranged in a neat 4-column by 2-row grid with 16px gutters, on a SOLID PURE MAGENTA (#FF00FF) chroma-key background.

Style: ancient magic + solemn epic, 2D hand-painted digital art, soft cell shading, flat orthographic. Consistent light direction from top-left. Aged parchment (#E8D9B0) faces, wrought-iron gray (#2B2B3A) accents, antique gold (#C9A227) beveled borders. PALETTE LOCKED to: #2B2B3A, #1A1A24, #C9A227, #B22222, #BF59FF, #3CB371, #E8D9B0, #F2EDE0.

Grid contents:
Row 1:
  [1] CONFIRM BUTTON 260x60 — parchment face, raised gold (#C9A227) 3px beveled border, inner iron-gray thin line, top highlight + bottom shadow embossed feel, flat center.
  [2] CANCEL BUTTON 220x56 — iron-gray (#2B2B3A) face, thin dark gold 1px border, slightly muted vs primary, flat center.
  [3] MENU ITEM BUTTON 280x48 — slim horizontal row, parchment face, hairline gold top and bottom rules only (no side borders, open-ended), flat surface.
  [4] MENU ITEM RECOMMENDED 280x48 — same as menu item but brighter glowing gold 2px FULL border + soft inner gold halo at 8% opacity marking it as recommended, parchment face slightly warmer.
Row 2:
  [5] SKILL BUTTON 520x48 — list row, left 18px zone tinted faint arcane violet (#BF59FF) signaling magic, parchment body, hairline gold rules top/bottom, flat.
  [6] ITEM BUTTON 520x48 — list row, left 18px zone tinted faint emerald (#3CB371), parchment body, hairline gold rules, flat.
  [7] END TURN BUTTON 220x64 — larger prominent corner button, iron-gray face, THICK gold 3px beveled border, thin blood-red (#B22222) accent line on bottom edge, embossed.
  [8] TAB BUTTON 140x44 — inactive tab, parchment top half + iron-gray bottom half separated by hairline gold rule, slightly raised.

ABSOLUTE RULES: NO TEXT, NO LETTERS, NO NUMBERS, NO ICONS, NO GLYPHS, NO CAPTIONS, NO WATERMARK. All centers perfectly flat for label overlay. Solid magenta outside buttons. 16px magenta gutters between cells. Consistent emboss lighting across all eight.
```

### 裁切坐标表

| # | 名称 | cell 尺寸 | 行列 | 存放路径 | 9-slice (L/R/T/B) |
|---|---|---|---|---|---|
| 1 | btn-confirm | 260×60 | R1C1 | `ui/buttons/btn-confirm.png` | 24/24/20/20 |
| 2 | btn-cancel | 220×56 | R1C2 | `ui/buttons/btn-cancel.png` | 22/22/18/18 |
| 3 | btn-menu-item | 280×48 | R1C3 | `ui/buttons/btn-menu-item.png` | 16/16/14/14 |
| 4 | btn-menu-item-recommended | 280×48 | R1C4 | `ui/buttons/btn-menu-item-recommended.png` | 16/16/14/14 |
| 5 | btn-skill | 520×48 | R2C1 | `ui/buttons/btn-skill.png` | 18/18/14/14 |
| 6 | btn-item | 520×48 | R2C2 | `ui/buttons/btn-item.png` | 18/18/14/14 |
| 7 | btn-end-turn | 220×64 | R2C3 | `ui/buttons/btn-end-turn.png` | 24/24/22/22 |
| 8 | btn-tab | 140×44 | R2C4 | `ui/buttons/btn-tab.png` | 16/16/12/12 |

> **三态变体**（hover/pressed/disabled）建议用 Godot `Theme` 资源程序化叠色，不必额外出图。如必须出图，对每个按钮再生成一张同布局雪碧图，prompt 末追加：hover → `add subtle warm gold inner glow, slightly brighter face`；pressed → `face shifted darker, border compressed, subtle inset shadow`；disabled → `desaturated to 50% grayscale, reduced opacity, no glow`。

---

## 雪碧图 ③ 进度条家族 `spritesheet-bars.png`

> **同类合并理由**：HP/MP/EXP/池/滑块全部是「底槽 + 填充」结构，共享同一套端帽圆角与边框语言。

- **画布**：1024 × 512 px
- **网格**：自定义排版（见 prompt 描述，cells 尺寸不一）
- **背景**：纯品红 `#FF00FF`

### Prompt

```
A fantasy tactics RPG UI sprite sheet of progress bars and meter bars on a SOLID PURE MAGENTA (#FF00FF) chroma-key background. Each bar is shown as TWO separate strips stacked vertically with 12px gap: a FRAME (empty trough) above and a FILL (colored bar) below.

Style: ancient magic + solemn epic, 2D hand-painted, soft cell shading, flat orthographic. Iron-gray (#2B2B3A) troughs with thin borders, parchment (#E8D9B0) empty troughs, rounded end caps. PALETTE LOCKED to: #2B2B3A, #C9A227, #408CFF, #B22222, #BF59FF, #3CB371, #E8D9B0, #F2EDE0.

Layout (top-to-bottom, each item = frame strip + fill strip, 16px gutter between items):
  [1] HP BAR — frame 200x20 (iron-gray trough, gold #C9A227 thin border, inner bevel, parchment empty, rounded 8px end caps); fill 200x16 (emerald #3CB371 vertical gradient lighter top, rounded left end cap 8px, FLAT right edge for width stretching, thin darker bottom shadow).
  [2] HP BAR FILL GOLD VARIANT — fill only 200x16, antique gold (#C9A227), same form as [1] fill.
  [3] HP BAR FILL RED VARIANT — fill only 200x16, blood red (#B22222), same form, subtle danger feel.
  [4] MP BAR — frame 160x16 (iron-gray trough, arcane crystal violet #BF59FF thin border signaling magic, parchment empty, rounded ends); fill 160x12 (arcane violet #BF59FF with faint ley-line shimmer, lighter top gradient, rounded left cap, flat right).
  [5] EXP BAR — frame 240x12 (iron-gray trough, gold hairline border, parchment empty, rounded ends); fill 240x8 (bone-white #F2EDE0 to gold #C9A227 HORIZONTAL gradient, rounded left cap, flat right).
  [6] TEAM POOL BAR — frame 120x10 (very slim, iron-gray trough, gold hairline, parchment empty, rounded ends).
  [7] SLIDER TRACK — 240x12 (iron-gray channel with inner shadow, gold hairline edges, parchment center groove, rounded ends).
  [8] SLIDER THUMB — 24x28 (vertical knob, antique-gold #C9A227 rounded gem/bead with iron-gray base, subtle highlight, front-facing, separated not strip).

ABSOLUTE RULES: NO TEXT, NO NUMBERS, NO TICKS, NO LETTERS, NO CAPTIONS, NO WATERMARK. Fill bars must have FLAT right edges (uniform middle) so they can be width-stretched by code. Solid magenta background outside bars.
```

### 裁切说明

> 这张排版不规则（cells 尺寸差异大），**建议生成后用图像编辑器（PS/GIMP/Krita）手工框选裁切**，或用 §10 脚本的「按颜色连通域自动检测」模式。文件清单：

| # | 名称 | 尺寸 | 存放路径 | 9-slice (L/R/T/B) |
|---|---|---|---|---|
| 1a | bar-hp-frame | 200×20 | `ui/bars/bar-hp-frame.png` | 8/8/6/6 |
| 1b | bar-hp-fill-green | 200×16 | `ui/bars/bar-hp-fill-green.png` | 8/2/4/4 |
| 2 | bar-hp-fill-gold | 200×16 | `ui/bars/bar-hp-fill-gold.png` | 8/2/4/4 |
| 3 | bar-hp-fill-red | 200×16 | `ui/bars/bar-hp-fill-red.png` | 8/2/4/4 |
| 4a | bar-mp-frame | 160×16 | `ui/bars/bar-mp-frame.png` | 8/8/5/5 |
| 4b | bar-mp-fill | 160×12 | `ui/bars/bar-mp-fill.png` | 8/2/3/3 |
| 5a | bar-exp-frame | 240×12 | `ui/bars/bar-exp-frame.png` | 6/6/4/4 |
| 5b | bar-exp-fill | 240×8 | `ui/bars/bar-exp-fill.png` | 6/2/2/2 |
| 6 | bar-team-pool | 120×10 | `ui/bars/bar-team-pool.png` | 5/5/3/3 |
| 7 | slider-track | 240×12 | `ui/controls/slider-track.png` | 6/6/4/4 |
| 8 | slider-thumb | 24×28 | `ui/controls/slider-thumb.png` | — |

---

## 雪碧图 ④ 武器三角 + 元素图标 `spritesheet-icons-combat.png`

> **同类合并理由**：都是 64×64 小图标、共享纹章/符文线描风格，一张图保证线条粗细与金属质感一致。

- **画布**：640 × 256 px
- **网格**：10 列 × 3 行（每 cell 64×64 + 16px gutter），实际填充 1-2 行
- **背景**：纯品红 `#FF00FF`

### Prompt

```
A fantasy tactics RPG icon sprite sheet on a SOLID PURE MAGENTA (#FF00FF) chroma-key background. All icons are 64x64 pixels, arranged in a neat grid with 16px magenta gutters, front-facing flat orthographic, heraldic line-art style with soft cell shading.

Style: ancient magic + solemn epic, 2D hand-painted. Consistent stroke weight, consistent metallic sheen. PALETTE LOCKED to: #2B2B3A, #C9A227, #408CFF, #B22222, #BF59FF, #3CB371, #E07B2A, #F2EDE0.

Row 1 — WEAPON TRIANGLE (link to profession system):
  [1] HERALDIC SWORD pointing up — steel blade, antique-gold (#C9A227) hilt, simple emblematic.
  [2] HERALDIC BATTLE-AXE — steel head, wood-and-gold haft.
  [3] HERALDIC LANCE/SPEAR pointing up-right — steel tip, gold shaft.
  [4] GREEN UP-ARROW (emerald #3CB371) — favorable weapon-triangle advantage, simple heraldic.
  [5] RED DOWN-ARROW (blood red #B22222) — unfavorable weapon-triangle disadvantage.

Row 2 — ELEMENTS (link to skill system):
  [6] FIRE — small flame, warm orange-red gradient toward gold core.
  [7] WATER — water-drop, azure (#408CFF) with highlight.
  [8] WIND — swirling gust, pale parchment-white.
  [9] EARTH — stone/rock, iron-gray (#2B2B3A) with gold vein.
  [10] LIGHT — radiant sun-burst, bone-white-gold (#F2EDE0).

Row 3 — MORE ELEMENTS / UTILITY:
  [11] DARK — shadowy crescent, near-black (#1A1A24) with violet (#BF59FF) edge.
  [12] ADVANTAGE STAR — five-point antique-gold (#C9A227) star with subtle glow (for "recommended" mark).

ABSOLUTE RULES: NO TEXT, NO LETTERS, NO NUMBERS, NO RUNES-AS-TEXT, NO CAPTIONS, NO WATERMARK. Each icon clearly isolated in its 64x64 cell with magenta around it. Icons must read clearly at 32x32 display size (bold silhouettes, minimal fine detail).
```

### 裁切坐标表（10×3 网格，cell 64×64，gutter 16px，原点 16,16）

| # | 名称 | 行列 | 存放路径 |
|---|---|---|---|
| 1 | icon-wt-sword | R1C1 | `ui/icons/icon-wt-sword.png` |
| 2 | icon-wt-axe | R1C2 | `ui/icons/icon-wt-axe.png` |
| 3 | icon-wt-lance | R1C3 | `ui/icons/icon-wt-lance.png` |
| 4 | icon-wt-arrow-up | R1C4 | `ui/icons/icon-wt-arrow-up.png` |
| 5 | icon-wt-arrow-down | R1C5 | `ui/icons/icon-wt-arrow-down.png` |
| 6 | icon-elem-fire | R2C1 | `ui/icons/icon-elem-fire.png` |
| 7 | icon-elem-water | R2C2 | `ui/icons/icon-elem-water.png` |
| 8 | icon-elem-wind | R2C3 | `ui/icons/icon-elem-wind.png` |
| 9 | icon-elem-earth | R2C4 | `ui/icons/icon-elem-earth.png` |
| 10 | icon-elem-light | R2C5 | `ui/icons/icon-elem-light.png` |
| 11 | icon-elem-dark | R3C1 | `ui/icons/icon-elem-dark.png` |
| 12 | icon-star-recommend | R3C2 | `ui/icons/icon-star-recommend.png` |

---

## 雪碧图 ⑤ 状态与操作图标 `spritesheet-icons-status.png`

> **同类合并理由**：buff/debuff/警告/操作类图标，共享「纹章徽章 + 实心填充」语言，与图④的线描风格互补但内部一致。

- **画布**：640 × 256 px
- **网格**：8 列 × 3 行（cell 64×64 + 16px gutter），实际填 2 行
- **背景**：纯品红 `#FF00FF`

### Prompt

```
A fantasy tactics RPG icon sprite sheet on a SOLID PURE MAGENTA (#FF00FF) chroma-key background. All icons 64x64, neat grid with 16px magenta gutters, front-facing flat orthographic, solid-fill heraldic badge style with soft cell shading.

Style: ancient magic + solemn epic, 2D hand-painted. PALETTE LOCKED to: #2B2B3A, #1A1A24, #C9A227, #408CFF, #B22222, #3CB371, #E07B2A, #F2EDE0.

Row 1 — STATUS:
  [1] BUFF CHEVRON — upward chevron badge in emerald (#3CB371), heraldic.
  [2] DEBUFF CHEVRON — downward chevron badge in blood red (#B22222).
  [3] IDLE ALERT — bold gold (#C9A227) exclamation mark, heraldic banner style, vertical. (This is the ONLY allowed glyph-like mark; render as a stylized banner shape, not typography.)
  [4] KILL SKULL — heraldic skull, bone-white (#F2EDE0) with dark eye sockets, solemn not gory.
  [5] WARNING TRIANGLE — triangular warning sign, ember-orange (#E07B2A) border, dark interior, heraldic. INTERIOR BLANK (no exclamation inside).
  [6] AUTOSAVE — heraldic quill-and-scroll icon in gold (#C9A227).
  [7] PERMANENT DEATH — broken heraldic shield icon with blood-red (#B22222) cracks.

Row 2 — ACTIONS (for buttons/menus):
  [8] ATTACK — two crossed swords, steel + gold, heraldic.
  [9] SKILL — arcane crystal/orb, violet (#BF59FF) glow.
  [10] ITEM — small potion flask, parchment body, emerald (#3CB371) liquid.
  [11] WAIT — small hourglass, gold frame, parchment sand.
  [12] UNDO — small curved-arrow undo icon, gold (#C9A227).
  [13] END TURN — heraldic hourglass-with-banner, gold and iron-gray.
  [14] HOSTING/COMMAND — small crown-scepter icon, gold (#C9A227).

ABSOLUTE RULES: NO TEXT, NO LETTERS, NO NUMBERS, NO RUNES-AS-TEXT (the exclamation mark in [3] is a stylized heraldic banner shape, NOT typography), NO CAPTIONS, NO WATERMARK. Each icon isolated in 64x64 cell. Bold silhouettes readable at 32x32.
```

### 裁切坐标表（8×3 网格，cell 64×64，gutter 16px）

| # | 名称 | 行列 | 存放路径 |
|---|---|---|---|
| 1 | icon-status-buff | R1C1 | `ui/icons/icon-status-buff.png` |
| 2 | icon-status-debuff | R1C2 | `ui/icons/icon-status-debuff.png` |
| 3 | icon-alert-idle | R1C3 | `ui/icons/icon-alert-idle.png` |
| 4 | icon-kill-skull | R1C4 | `ui/icons/icon-kill-skull.png` |
| 5 | icon-warning | R1C5 | `ui/icons/icon-warning.png` |
| 6 | icon-autosave | R1C6 | `ui/icons/icon-autosave.png` |
| 7 | icon-death-permanent | R1C7 | `ui/icons/icon-death-permanent.png` |
| 8 | icon-action-attack | R2C1 | `ui/icons/icon-action-attack.png` |
| 9 | icon-action-skill | R2C2 | `ui/icons/icon-action-skill.png` |
| 10 | icon-action-item | R2C3 | `ui/icons/icon-action-item.png` |
| 11 | icon-action-wait | R2C4 | `ui/icons/icon-action-wait.png` |
| 12 | icon-action-undo | R2C5 | `ui/icons/icon-action-undo.png` |
| 13 | icon-end-turn | R2C6 | `ui/icons/icon-end-turn.png` |
| 14 | icon-hosting | R2C7 | `ui/icons/icon-hosting.png` |

---

## 雪碧图 ⑥ 光标与范围色块 `spritesheet-cursors.png`

> **同类合并理由**：金色光标 + 六色范围菱形 + 引导箭头，全部是等距战场贴地精灵，共享同一套菱形透视与描边粗细。**对齐 `range_overlay.gd` 的 `_make_flat_diamond_frame` / `_make_flat_quad` 机制**。

- **画布**：1024 × 512 px
- **网格**：4 列 × 2 行（cell 128×128 / 96×96 混排，gutter 16px）
- **背景**：纯品红 `#FF00FF`

### Prompt

```
A fantasy tactics RPG sprite sheet of battlefield tile overlays and cursors on a SOLID PURE MAGENTA (#FF00FF) chroma-key background.

Style: ancient magic + solemn epic, flat top-down ISOMETRIC perspective (diamond-shaped tiles matching an isometric grid), soft cell shading, hand-painted. PALETTE LOCKED to: #2B2B3A, #C9A227, #408CFF, #B22222, #BF59FF, #3CB371, #E07B2A.

Layout (4 columns x 2 rows, 16px gutters):
Row 1 — TILE OVERLAYS (each a flat isometric DIAMOND, 128x128, semi-transparent fills):
  [1] MOVABLE — ley-blue (#408CFF) fill at 35% opacity, brighter azure border.
  [2] BLOCKED — blood red (#B22222) fill at 35%, red border.
  [3] ATTACK — arcane crystal violet (#BF59FF) fill at 35%, violet border.
  [4] HEAL — emerald (#3CB371) fill at 35%, green border.
Row 2:
  [5] DANGER MOVE — ley-blue (#408CFF) base fill at 25% with ember-orange (#E07B2A) DIAGONAL HATCH STRIPES at 30% on top, orange border (pattern-based, colorblind-friendly).
  [6] GOLD CURSOR — isometric diamond-shaped tile cursor OUTLINE only, antique-gold (#C9A227) glowing wireframe border, transparent interior, subtle inner soft glow.
  [7] GOLD GUIDE ARROW — bold antique-gold (#C9A227) downward-pointing arrow, heraldic ribbon style, slight glow, 96x96.
  [8] RED COUNTDOWN ARROW — bold blood-red (#B22222) downward-pointing arrow, sharp, danger feel, 96x96.

ABSOLUTE RULES: NO TEXT, NO LETTERS, NO NUMBERS, NO CAPTIONS, NO WATERMARK. Diamonds must be clean isometric geometry (matching a 2:1 isometric grid). Solid magenta background outside the shapes.
```

### 裁切坐标表

| # | 名称 | 尺寸 | 行列 | 存放路径 |
|---|---|---|---|---|
| 1 | range-movable | 128×128 | R1C1 | `ui/cursors/range-movable.png` |
| 2 | range-blocked | 128×128 | R1C2 | `ui/cursors/range-blocked.png` |
| 3 | range-attack | 128×128 | R1C3 | `ui/cursors/range-attack.png` |
| 4 | range-heal | 128×128 | R1C4 | `ui/cursors/range-heal.png` |
| 5 | range-danger | 128×128 | R2C1 | `ui/cursors/range-danger.png` |
| 6 | cursor-gold | 128×128 | R2C2 | `ui/cursors/cursor-gold.png` |
| 7 | arrow-guide-gold | 96×96 | R2C3 | `ui/cursors/arrow-guide-gold.png` |
| 8 | arrow-countdown-red | 96×96 | R2C4 | `ui/cursors/arrow-countdown-red.png` |

---

## 雪碧图 ⑦ 装饰元素 `spritesheet-ornaments.png`

> **同类合并理由**：蔓藤分隔线、角花、鲁恩符文、卷轴端帽、四国徽记底——全部是「纹章/蔓藤/鲁恩」图形语言的装饰件，一张图统一藤蔓曲率与金线粗细。

- **画布**：1024 × 768 px
- **网格**：自定义排版（见 prompt）
- **背景**：纯品红 `#FF00FF`

### Prompt

```
A fantasy tactics RPG decorative ornament sprite sheet on a SOLID PURE MAGENTA (#FF00FF) chroma-key background.

Style: ancient magic + solemn epic, 2D hand-painted heraldic ornament, soft cell shading, flat orthographic. Antique gold (#C9A227) scrollwork with small ivy/vine leaves, wrought-iron gray (#2B2B3A) accents. PALETTE LOCKED to: #2B2B3A, #1A1A24, #C9A227, #408CFF, #BF59FF, #3CB371, #E07B2A, #F2EDE0.

Layout (16px gutters between items):
Row 1:
  [1] VINE DIVIDER 480x24 — horizontal decorative divider, thin gold (#C9A227) center rule, two small ivy leaf flourishes at left and right ends (within 40px), small center medallion, transparent above/below the rule.
  [2] CORNER CREST TOP-LEFT 64x64 — L-shaped heraldic corner ornament, gold scrollwork with small ivy leaves and a tiny rivet, for top-left corner of a panel, transparent outside the L.
  [3] CORNER CREST TOP-RIGHT 64x64 — mirror of [2].
  [4] CORNER CREST BOTTOM-LEFT 64x64 — vertical mirror of [2].
  [5] CORNER CREST BOTTOM-RIGHT 64x64 — mirror of [4].
Row 2:
  [6] RUNE MP UNIT 24x32 — a single small decorative rune glyph (PURELY ORNAMENTAL, NOT corresponding to any real-world alphabet or letter), carved-stone look with arcane violet (#BF59FF) etched glow.
  [7] SCROLL CAP LEFT 80x480 — vertical wooden scroll rod with antique-gold end caps, slightly aged, front-facing.
  [8] SCROLL CAP RIGHT 80x480 — mirror of [7].
Row 3 — NATION CREST BACKGROUNDS (blank shields, 64x64, for code to overlay character art):
  [9] BLACK IRON CREST — heraldic shield, iron-gray (#2B2B3A) field, gold border, blank center, tiny hammer-anvil silhouette at top.
  [10] VELANTHOR CREST — heraldic shield, deep ley-blue (#408CFF) field, silver-gold border, tiny crescent moon at top.
  [11] SHATTERED MOON CREST — heraldic shield, arcane violet (#BF59FF) field, silver border, tiny cracked-moon silhouette at top.
  [12] EMBERFOLK CREST — heraldic shield, ember-orange (#E07B2A) field, dark border, tiny flame silhouette at top.

ABSOLUTE RULES: NO TEXT, NO LETTERS, NO NUMBERS, NO RUNES-AS-REAL-ALPHABET (rune in [6] is purely decorative abstract glyph), NO CAPTIONS, NO WATERMARK. Solid magenta outside ornaments.
```

### 裁切说明

> 排版不规则，建议手工框选裁切。文件清单：

| # | 名称 | 尺寸 | 存放路径 | 9-slice (L/R/T/B) |
|---|---|---|---|---|
| 1 | divider-vine | 480×24 | `ui/ornaments/divider-vine.png` | 40/40/0/0 |
| 2 | corner-crest-tl | 64×64 | `ui/ornaments/corner-crest-tl.png` | — |
| 3 | corner-crest-tr | 64×64 | `ui/ornaments/corner-crest-tr.png` | — |
| 4 | corner-crest-bl | 64×64 | `ui/ornaments/corner-crest-bl.png` | — |
| 5 | corner-crest-br | 64×64 | `ui/ornaments/corner-crest-br.png` | — |
| 6 | rune-mp-unit | 24×32 | `ui/ornaments/rune-mp-unit.png` | — |
| 7 | scroll-cap-left | 80×480 | `ui/ornaments/scroll-cap-left.png` | — |
| 8 | scroll-cap-right | 80×480 | `ui/ornaments/scroll-cap-right.png` | — |
| 9 | crest-blackiron | 64×64 | `ui/ornaments/crest-blackiron.png` | — |
| 10 | crest-velanthor | 64×64 | `ui/ornaments/crest-velanthor.png` | — |
| 11 | crest-shattered-moon | 64×64 | `ui/ornaments/crest-shattered-moon.png` | — |
| 12 | crest-emberfolk | 64×64 | `ui/ornaments/crest-emberfolk.png` | — |

---

## 雪碧图 ⑧ 勾选框 / 单选 / Tab 激活态 等小控件 `spritesheet-controls.png`

> **同类合并理由**：checkbox / radio / tab-active / tab-inactive 都是小尺寸表单控件，共享同一套金边圆角语言，凑成最后一张小图。

- **画布**：512 × 256 px
- **网格**：自定义（cells 28-140 不等）
- **背景**：纯品红 `#FF00FF`

### Prompt

```
A fantasy tactics RPG form-control sprite sheet on a SOLID PURE MAGENTA (#FF00FF) chroma-key background.

Style: ancient magic + solemn epic, 2D hand-painted, soft cell shading, flat orthographic. PALETTE LOCKED to: #2B2B3A, #C9A227, #3CB371, #E8D9B0.

Layout (16px gutters):
Row 1:
  [1] CHECKBOX EMPTY 32x32 — iron-gray (#2B2B3A) square frame with gold (#C9A227) inner bevel, transparent center, slight emboss.
  [2] CHECKBOX CHECKED 32x32 — same frame with a bold gold (#C9A227) hand-painted checkmark stroke inside.
  [3] RADIO EMPTY 28x28 — iron-gray ring with gold inner bevel, transparent center.
  [4] RADIO SELECTED 28x28 — same ring with a solid gold (#C9A227) filled dot in the center.
Row 2:
  [5] TAB ACTIVE 140x44 — full parchment (#E8D9B0) face with bright gold (#C9A227) 2px border on TOP and SIDES (open bottom, connecting to a panel), subtle inner glow, flat center.

ABSOLUTE RULES: NO TEXT, NO LETTERS, NO NUMBERS, NO CAPTIONS, NO WATERMARK. Solid magenta outside controls.
```

### 裁切说明

| # | 名称 | 尺寸 | 存放路径 |
|---|---|---|---|
| 1 | checkbox | 32×32 | `ui/controls/checkbox.png` |
| 2 | checkbox-checked | 32×32 | `ui/controls/checkbox-checked.png` |
| 3 | radio | 28×28 | `ui/controls/radio.png` |
| 4 | radio-selected | 28×28 | `ui/controls/radio-selected.png` |
| 5 | btn-tab-active | 140×44 | `ui/buttons/btn-tab-active.png` |

---

## 9. 生成顺序建议

| 优先级 | 雪碧图 | 理由 |
|---|---|---|
| P0 | ① 面板家族 | UI 骨架，先有底板才能搭界面 |
| P0 | ② 按钮家族 | 交互可用 |
| P1 | ③ 进度条家族 | 战场核心反馈（HP/MP） |
| P1 | ④ 战斗图标 | 武器三角 + 元素，预测面板要用 |
| P2 | ⑥ 光标与范围 | 战场可视化（对齐 range_overlay.gd） |
| P2 | ⑤ 状态图标 | buff/警告，细节打磨 |
| P3 | ⑦ 装饰元素 | 质感提升，非阻塞 |
| P3 | ⑧ 小控件 | checkbox/radio，设置界面才用 |

---

## 10. 后处理：裁切 + 抠透明脚本

> 依赖：`pip install pillow numpy`.  用法：`python crop_spritesheet.py <spritesheet.png> <config.json> <output_dir>`

### 10.1 magic pink 抠透明（所有图通用）

```python
# chroma_key.py — 把 #FF00FF 抠成透明
from PIL import Image
import sys
src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGBA")
px = im.load()
w, h = im.size
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        # magic pink = (255, 0, 255)；容差吸收抗锯齿
        if r > 230 and g < 40 and b > 230:
            px[x, y] = (0, 0, 0, 0)
im.save(dst)
print(f"chroma-keyed {w}x{h} -> {dst}")
```

### 10.2 按坐标表批量裁切

```python
# crop_spritesheet.py — 按网格裁切雪碧图
# config.json 示例（图①面板）：
# {
#   "gutter": 16, "origin_x": 16, "origin_y": 16,
#   "cells": [
#     {"name":"panel-info",           "row":0,"col":0,"w":512,"h":256},
#     {"name":"hud-topbar",           "row":0,"col":1,"w":1024,"h":120},
#     ...
#   ]
# }
import json, sys
from PIL import Image

sheet = Image.open(sys.argv[1]).convert("RGBA")
cfg   = json.load(open(sys.argv[2]))
out   = sys.argv[3]
g, ox, oy = cfg["gutter"], cfg["origin_x"], cfg["origin_y"]

for c in cfg["cells"]:
    # 假设等宽网格；若不等宽需在 config 里写绝对 x/y
    x = ox + c["col"] * (c["w"] + g)
    y = oy + c["row"] * (c["h"] + g)
    cell = sheet.crop((x, y, x + c["w"], y + c["h"]))
    cell.save(f"{out}/{c['name']}.png")
    print(f"cropped {c['name']} at ({x},{y}) {c['w']}x{c['h']}")
```

### 10.3 自动检测连通域裁切（用于排版不规则的图③⑦）

```python
# auto_crop.py — 用颜色连通域自动框出每个独立元素
import numpy as np
from PIL import Image
from scipy import ndimage
import sys

im = np.array(Image.open(sys.argv[1]).convert("RGB"))
# magic pink mask
pink = (im[:,:,0] > 230) & (im[:,:,1] < 40) & (im[:,:,2] > 230)
objects = ~pink
labels, n = ndimage.label(objects)
print(f"found {n} objects")
for i in range(1, n + 1):
    ys, xs = np.where(labels == i)
    if len(xs) < 100:   # 过滤噪点
        continue
    x0, x1 = xs.min(), xs.max()
    y0, y1 = ys.min(), ys.max()
    pad = 2
    crop = Image.open(sys.argv[1]).convert("RGBA").crop(
        (max(0,x0-pad), max(0,y0-pad), x1+pad, y1+pad))
    crop.save(f"{sys.argv[2]}/obj_{i:02d}_{x1-x0}x{y1-y0}.png")
    print(f"obj {i}: {x1-x0}x{y1-y0} at ({x0},{y0})")
```

---

## 11. 各模型推荐参数

| 模型 | 推荐参数 | 备注 |
|---|---|---|
| **Midjourney v6+** | 末尾加 `--ar 4:3`（图①）/ `--ar 2:1`（图②③）/ `--ar 1:1`（图④⑤⑥⑧）/ `--ar 4:3`（图⑦），`--style raw`, `--stylize 250`, `--no text,font,letters,watermark` | `--no` 参数强化无文字；`--style raw` 减少MJ自有美化倾向 |
| **Stable Diffusion (SDXL)** | 正向 prompt + `no_text`, `english_text`, `watermark`, `signature` 在负向；采样 DPM++ 2M Karras，30 步，CFG 7 | 加 ControlNet `tile` 或 `canny` 配合草图网格更稳 |
| **DALL·E 3 / Gemini / Nano Banana** | 直接用 prompt，强调 `absolutely no text` | DALL·E 易出文字，需多次重抽 |
| **Flux.1** | 加 `no text` 在负向（若支持），不然正向强调 | Flux 还原 prompt 忠实度高 |

> **通用技巧**：所有 prompt 都已写 `NO TEXT, NO LETTERS...`，但 AI 模型仍可能漏出零星字符，**生成后必须人工过一遍**（特别是面板中央、卷轴水印位置）。漏字直接用魔棒/仿制图章擦掉，或局部 inpaint 重抽。

---

## 12. 交付前自检清单

- [ ] **8 张雪碧图**全部生成
- [ ] **magic pink 已抠透明**（背景 100% alpha=0）
- [ ] **无文字**：肉眼 + `tesseract` OCR 扫描复核
- [ ] **配色 ≤10 色**：用 PS/GIMP「索引颜色」或 `PIL.quantize` 验证调色板
- [ ] **9-slice 可拉伸**：用 `NinePatchRect` 在 Godot 里测 2× / 0.5× 拉伸无畸变
- [ ] **文件命名**严格按各表「存放路径」列（相对 `godot/assets/`）
- [ ] **风格统一**：羊皮纸 + 铁灰 + 暗金基调贯穿 8 张图，无科幻/赛博元素混入
- [ ] **HP 三色**（绿/金/<25%红）、**范围六色**（蓝/红/紫/金/绿/橙）严格命中十六进制

---

## 13. 与代码对接备忘

- **面板/按钮/条** → `NinePatchRect`，`patch_margin_*` = 各表「9-slice 边距」
- **按钮三态** → 优先 `Theme` 资源程序化叠色（`theme_set_stylebox` for `Button.normal/hover/pressed/disabled`），不额外出图
- **HP 条填充宽度** → `NinePatchRect.size.x = max_w * hp_ratio`，按 §3.4 规则切换绿/金/红三张填充图
- **光标与范围块** → 仍是 `range_overlay.gd` 的 `_make_flat_diamond_frame` / `_make_flat_quad` 程序生成路径；本文 PNG 作**可选美术替换**，代码加 `_USE_SPRITE_OVERLAY` 开关
- **图标路径拼接** → 按 `06_items.md` / `07_skills` 数据字段拼路径加载，命名已对齐（如 `icon-elem-{element}.png`）
