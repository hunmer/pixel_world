---
name: plant-sprite-3x3
description: >-
  Generates new small pixel-art plant / vegetation sprites (flowers, bushes, cacti,
  mushrooms, grass tufts, saplings, water plants) in the style of an existing sprite
  folder such as meowa_tiles/plants, using libtv image-to-image. The script composes 9
  existing sprites into a 3x3 reference sheet (true relative sizes, bottom-aligned),
  generates a new 3x3 sheet, then splits it into native-resolution transparent sprites
  whose sizes match the reference. Use when the user asks for more / new / similar
  plants, flora, foliage or decoration sprites in the style of an existing plant set.
---

# Plant sprite 3x3 generation (libtv)

Unlike terrain blocks, plants have **variable sizes and silhouettes**, so this skill
handles them differently:
- no silhouette mask;
- sprites are bottom-aligned (they stand on the ground);
- the downscale factor comes from the median sprite size of the reference sheet;
- palette reduction is off by default, so small accents (berries, flower centers)
  survive.

Proven settings: **Lib Image 2.6 Pro** (`-Quality high -Resolution 2K`). Its dark
outline and chunky pixels match meowa_tiles/plants best. Seedream 5.5 is a usable
alternative with lighter outlines and finer detail. One generation takes about 1–2 minutes.

Requires `libtv` logged in and `.libtv/project.json` in the cwd (project root).
Run everything from the project root with `$S = ".agents/skills/plant-sprite-3x3/scripts"`.

## Steps

1. **Inspect the sprites** (sizes vary, e.g. 14–56 px) and pick 9 varied, mid-sized
   ones. Very tall sprites (saguaro) make every other sprite small in the reference,
   so avoid them unless needed.
2. **Build the reference.** Native relative sizes are kept and sprites are
   bottom-aligned, upscaled ×8 with NEAREST:
   ```powershell
   python "$S/make_ref.py" meowa_tiles/plants_gen/ref_3x3.png --dir meowa_tiles/plants `
     --pick agave_small,flowering_barrel_cactus,dry_shrub_small,mushroom_cluster_red_large,pink_lotus,snowy_grass_clump_green,wildflower_yellow,prickly_pear_cactus,grass_tuft_lush
   ```
3. **Generate.** Give one description per cell, in reading order:
   ```powershell
   & "$S/generate.ps1" -Ref meowa_tiles/plants_gen/ref_3x3.png -Name plants_gen_v1 `
     -OutDir meowa_tiles/plants_gen/raw -Quality high -Resolution 2K `
     -Items "a lush green fern with arching fronds","a cluster of three red tulips", ...
   ```
   - For Seedream use `-Model "Seedream 5.5" -Quality 2K`, with no `-Resolution`.
   - When comparing models in parallel jobs, start the second about 20 s later so the
     reference upload is already cached.
   - The template is [plant_prompt.txt](./templates/plant_prompt.txt). Use
     `-ExtraRules` for extra constraints (e.g. "all plants must be desert plants").
4. **Check the raw sheet** (view it): 9 separate plants, none crossing cell borders,
   no text, and the same outline/pixel style. Models draw the plants large and fill
   the cells; that is expected, because step 5 rescales them.
5. **Split into native sprites.** The scale is matched to the reference's median sprite size:
   ```powershell
   python "$S/split_sprites.py" meowa_tiles/plants_gen/raw/plants_gen_v1.png meowa_tiles/plants_gen/tiles `
     --names fern,red_tulips,... --ref-sheet meowa_tiles/plants_gen/ref_3x3.png --preview meowa_tiles/plants_gen/preview.png
   ```
   - Other ways to set the scale: `--pixel N` (fixed art-pixel size in output px);
     `--pixel auto` (period detection, unreliable on AI output, check the printed
     candidates); `--ref-cell C`.
   - `--colors N` turns on palette reduction (FASTOCTREE). Use 24–32, never below
     16, or berries and flower centers disappear.
   - `--canvas WxH` places each sprite bottom-center on a fixed canvas, e.g. `32x32`
     like the water plants.
6. **Verify.** Place the reference sheet (on grey) next to `preview.png` at the same
   scale. Check that:
   - sizes are comparable;
   - the outline is visible;
   - accents survived;
   - there are no stray pixels.

   Results and model comparison: [results.md](./references/results.md).

## Gotchas

- An image node with a reference input needs `modeType=image2image`; the script sets it.
- Windows PowerShell 5.1: prompts have `"` replaced with `'`, and libtv's stderr
  progress output is tolerated inside the script.
- `split_sprites.py` splits the sheet into equal thirds. If a plant crosses a cell
  border, regenerate.
- Write output to a separate folder (e.g. `meowa_tiles/plants_gen/`) and never
  overwrite the source sprites.
