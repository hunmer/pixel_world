---
name: skill-icon-evo-sheet
description: >-
  Generates RPG skill-icon sheets with libtv: one sheet per category (fire, ice, holy,
  dark, wind, physical, lightning, ...). Each sheet is a 10x5 grid of 50 icons, with 5
  skill lines per sheet and tier 1→10 evolution left to right. Supports a painted glow
  style (Seedream 5.5, 21:9) and a pixel-art style (Lib Image 2.6 Pro, 2:1). It then
  slices the sheet into 128px icons, or real 32x32 pixel icons. Also contains
  copy-paste prompts for the LibTV web UI and a list of 26 skill categories. Use when
  the user asks for skill / ability / spell icons, an icon evolution sheet, or skill
  icon prompts.
---

# Skill icon evolution sheet 10x5 (libtv)

Each sheet holds one category. **Rows are 5 skill lines** (single target → AoE →
buff/heal → debuff/control → ultimate/summon). **Columns are tiers 1→10.** Tiers 1–3 are
small and dim, tiers 4–7 add runes and particles, and tiers 8–10 are big, gold and white,
and ornate.

Requires `libtv` logged in and `.libtv/project.json` in the cwd. Run everything from
the project root with `$S = ".agents/skills/skill-icon-evo-sheet/scripts"` and an output
dir such as `$O = "meowa_tiles/generated/skill_icons/evo_sheets"`.
The style reference node `skill_ref_existing_50_sheet` (i-WVG4JemAu7, the 50 existing
icons, 1280x640) is already on the bound canvas.

## Proven settings

| Style | Model | ratio | other | Output |
| --- | --- | --- | --- | --- |
| Painted glow | Seedream 5.5 | **21:9** | quality=2K, background=opaque | 3136x1344 |
| Pixel art | Lib Image 2.6 Pro | **2:1** | resolution=2K, quality=high, output_format=png | 2048x1024 |

- Seedream does not support 2:1. With **16:9, square cells fit only 9 columns**, so rows 2–5
  came out with 9 icons. 21:9 fixed that.
- One generation takes about 30–60 s. Separate `python make_*.py <cat>` processes can run in parallel.

## Steps

1. **Define the category** in `SHEETS` in [make_nodes.py](./scripts/make_nodes.py):
   `key: (Chinese name, color scheme, [5 row descriptions])`. Each row description should
   say how it evolves, e.g. "火球（单体攻击，从小火苗进化到巨型陨石火球）". You can copy
   rows from [the skill list](./references/web_prompts_and_skill_list.md), section 三.
2. **Painted sheet** (Seedream 5.5, references `skill_ref_existing_50_sheet`):
   ```powershell
   $env:EVO_SUFFIX = "_v1"   # node = skill_evo_<cat>_10x5_v1
   python "$S/make_nodes.py" fire ice
   python "$S/fetch.py" skill_evo_fire_10x5_v1 skill_evo_ice_10x5_v1 --out $O
   ```
3. **Check the raw sheet** (view it): exactly 10 icons in each of the 5 rows, no
   numbers or text, and every object correct. If not, change the suffix and generate again.
   Make the failing row's prompt more explicit if needed.
4. **Slice** (gutters are found automatically; outer frames are trimmed):
   ```powershell
   python "$S/slice.py" "$O/skill_evo_fire_10x5_v1.png" fire          # -> $O/fire/*.png 128px + $O/fire_sheet_10x5_128.png
   ```
5. **Pixel version** (Lib Image 2.6 Pro, image2image from the painted sheet, so the layout matches cell for cell):
   - **Use the normalized 1280x640 sheet as the reference, not the raw painted sheet.**
     The raw sheet's last column is often wider, and the model copies that (it also
     produced 11 columns once). Upload the normalized sheet first:
     ```powershell
     libtv upload ref_norm_fire_10x5 -t image --resource "$O/fire_sheet_10x5_128.png"
     $env:PIX_REF = "ref_norm_{key}_10x5"; $env:PIX_SUFFIX = "_p1"
     python "$S/make_pixel.py" fire       # node = pixel_evo_fire_10x5_p1
     python "$S/fetch.py" pixel_evo_fire_10x5_p1 --out $O
     $env:PIXEL_GRID = "32"; python "$S/slice.py" "$O/pixel_evo_fire_10x5_p1.png" pixel_fire
     ```
   - Pixel mode pads wide cells with the background color instead of cropping them. Each
     icon is BOX-downsampled to `PIXEL_GRID`² and quantized to 24 colors with no dither.
     This writes `*_32px.png` (true pixels) plus a 128px NEAREST upscale.
   - `make_pixel.py` defaults to `PIX_REF=skill_evo_{key}_10x5_{ver}` with `FINAL`
     versions. Update `FINAL` or set `PIX_REF` for new categories.
   - For a pixel sheet of a new category with no painted sheet, use template A (below) in
     the web UI or adapt `make_pixel.py`, using an existing pixel sheet as the style reference.
6. **QA**: paste the `*_sheet_10x5_128.png` files into one contact sheet and view it.
   Check that each row is one evolving theme and that the icons are not cut off.

## Prompts

- [templates/](./templates): A = pixel art for a new category (style reference), B = painted
  → pixel conversion, C = painted glow style. The scripts embed the same wording.
- Required wording, which fixed real failures: "每一行恰好 10 个图标、每一列恰好 5 个图标，所有行与列严格对齐成规整矩阵" and
  "画面中绝对不要出现任何文字、数字、编号或角标". Without the second one, the physical sheet came out numbered 1–50.
- Name ambiguous objects explicitly. "木盾" was drawn as a wooden table. "一面简陋的圆形小木盾牌……整行每格都必须是盾牌" fixed it.
- For the LibTV web UI: [web_prompts_and_skill_list.md](./references/web_prompts_and_skill_list.md)
  has settings, the 3 templates, 26 categories × 5 rows with color schemes, and a troubleshooting table.

## Known results (2026-11-24)

- 6 categories were generated in both styles: fire, ice, holy, dark, wind, physical.
  Pixel art from Lib Image 2.6 Pro looked very good: clean outlines, dithered glows, and
  evolution preserved. The 16:9 Seedream attempt, ice_v2 (one row with 9 icons), and
  physical_v2 (11 columns, numbers) were rejected.
- The generated images were later deleted locally at the user's request. The canvas nodes
  (`skill_evo_*`, `pixel_evo_*`, `ref_norm_*`) still exist on canvas 8f05da05… and can be re-fetched with `fetch.py`.
