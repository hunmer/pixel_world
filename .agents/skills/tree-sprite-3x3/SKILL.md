---
name: tree-sprite-3x3
description: >-
  Generates new pixel-art tree sprites (broadleaf, fruit, conifer, snowy, palm, dead,
  blossom, fantasy trees, bamboo) in the style of an existing sprite folder such as
  meowa_tiles/trees, using libtv image-to-image. Default: 4 existing trees are composed
  into a 1x4 21:9 reference sheet (true relative sizes, bottom-aligned), a new 1x4 sheet
  is generated at 21:9 / 2K / high quality, then split into native-resolution transparent
  sprites (about 45-60 px tall) whose sizes match the reference. A 3x3 / 1:1 layout is
  still supported via parameters. Use when the user asks for more / new / similar trees
  or large vegetation sprites in the style of an existing tree set.
---

# Tree sprite generation (libtv, default 1x4 @ 21:9)

This skill uses the same pipeline as `plant-sprite-3x3`, tuned for trees:
- **Default layout: 1 row × 4 trees on a 21:9 sheet** (Lib Image 2.6 Pro, `ratio=21:9`,
  `resolution=2K`, `quality=high`, which gives 2016×864 output). With 4 trees instead of
  9, the model follows each description more closely and draws fruit, bark and snow
  more cleanly. The art-pixel size is about the same as with 3×3 @ 2K (about 9 vs 10
  output px per art pixel, see [results.md](./references/results.md)). For a much
  larger render, pass `-Resolution 4K`.
- the trees in meowa_tiles/trees are about 26–55 px wide and 52–65 px tall, so
  the sprites are similar in size;
- the sprites are bottom-aligned on the trunk base, with no silhouette mask;
- the downscale factor is matched to the median sprite size of the reference sheet;
- palette reduction is off by default, so fruit, blossoms and sparkles survive.

Lib Image 2.6 Pro matches the set (dark outline, clumped canopies, flared trunks).
Seedream 5.5 draws without an outline and with painterly detail, so it does not match.
One generation takes about 1–2 minutes.

Requires `libtv` logged in and `.libtv/project.json` in the cwd (project root).
Run everything from the project root with `$S = ".agents/skills/tree-sprite-3x3/scripts"`.

## Steps

1. **Pick 4 varied reference trees** (round, conifer, bare/dead, weeping/palm). Avoid
   the 128 px `cherry_blossom_tree`, because it is about twice as large as the others.
   Several 64x64 files have padding, but `make_ref.py` trims it.
2. **Build the reference.** The defaults are `--cols 4 --count 4 --ratio 21:9`, so
   the sheet has the same aspect as the output:
   ```powershell
   python "$S/make_ref.py" meowa_tiles/trees_gen/ref_1x4.png --dir meowa_tiles/trees `
     --pick apple_tree,blue_spruce_tree_small,dead_tree_tall,willow_tree
   ```
3. **Generate.** Give 4 descriptions, left to right. The defaults are `-Rows 1 -Cols 4
   -Ratio 21:9 -Resolution 2K -Quality high -Count 1`:
   ```powershell
   & "$S/generate.ps1" -Ref meowa_tiles/trees_gen/ref_1x4.png -Name trees_1x4_v1 `
     -OutDir meowa_tiles/trees_gen/raw `
     -Items "a big old oak tree with a wide clumpy canopy","a tall snowy fir tree","a pear tree with small green pears","a weeping cherry tree with drooping pink blossom branches"
   ```
   - `-Count 4` returns 4 variants (`<Name>_1..4.png`) of the same prompt in one run,
     which is useful for picking the best one.
   - The template is [tree_prompt.txt](./templates/tree_prompt.txt) (`{COUNT}` and
     `{LAYOUT}` come from `-Rows/-Cols`). Use `-ExtraRules` for set-wide constraints.
   - The reference upload is cached by sha1 in `.libtv/ref_cache.json`.
   - For the old 3×3 layout, build the reference with `make_ref.py --cols 3 --count 9 --ratio 1:1`
     and generate with `-Rows 3 -Cols 3 -Ratio 1:1`.
   - For Seedream, use `-Model "Seedream 5.5" -Quality 2K -Resolution ""`.
4. **Check the raw sheet** (view it). It should show 4 separate trees with an empty
   gap between neighbours, no text or ground, and a dark outline.
5. **Split into native sprites** (defaults `--rows 1 --cols 4`):
   ```powershell
   python "$S/split_sprites.py" meowa_tiles/trees_gen/raw/trees_1x4_v1.png meowa_tiles/trees_gen/tiles `
     --names old_oak,snowy_fir,pear_tree,weeping_cherry --ref-sheet meowa_tiles/trees_gen/ref_1x4.png `
     --preview meowa_tiles/trees_gen/preview.png
   ```
   - Cuts snap to the nearest fully empty gap (printed as `x cuts:`). At 21:9 a cell is
     only 504 px wide, and wide trees often cross the exact 1/4 line, which equal
     splitting would clip. If it prints `WARNING: no empty gap`, two trees touch, so
     regenerate. `--no-snap` turns this off.
   - Use `--rows 3 --cols 3` for 3×3 sheets.
   - `--canvas 64x64` places each tree bottom-center on a fixed canvas.
   - `--colors 24..32` turns on palette reduction (never below 16).
   - `--pixel N` overrides the scale. Avoid `--pixel auto`, because it is unreliable.
6. **Verify.** Put the reference (on grey) next to `preview.png` at the same scale. Check
   that sizes are comparable, the outline is visible, accents survived, and no tree is
   clipped on its sides.

## Gotchas

- An image node with a reference input needs `modeType=image2image`; the script sets it.
- PowerShell variables are case-insensitive. Never add a variable like `$count` to
  `generate.ps1`, because it would overwrite the `-Count` parameter (this once
  produced 4 images per run).
- Windows PowerShell 5.1: `"` in prompts becomes `'`. libtv writes progress to
  stderr, and `*.stderr.log` shows it as a `NativeCommandError`. That is harmless.
- If the output is opaque, `split_sprites.py` keys out near-white, and snow or sparkle
  highlights can be lost. Keep `background=transparent` (the default).
- Loose particles (petals, sparkles) widen the sprite bbox and can also block the gap
  snapping. Add "no falling petals / particles" to the prompt if they appear.
- Write output to `meowa_tiles/trees_gen/` and never overwrite the source sprites.
