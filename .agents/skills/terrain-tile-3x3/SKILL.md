---
name: terrain-tile-3x3
description: >-
  Generates new pixel-art tiles (isometric terrain blocks, ground tiles, icons, etc.)
  in the same style as an existing set of small tile PNGs, using libtv image-to-image.
  The script first composes the existing tiles into a 3x3 reference sheet, then
  generates a new 3x3 sheet, and finally splits and downsamples it back into
  game-ready native-size tiles (e.g. 32x26) with the same silhouette and a reduced
  palette. Use when the user asks for more / new / similar tiles in the style of a
  tile folder such as meowa_tiles/terrain, or for a 3x3 pixel tile sheet via libtv.
---

# Pixel tile 3x3 generation (libtv)

Proven on `meowa_tiles/terrain` (32x26 isometric blocks). **Lib Image 2.6 Pro** gave
the closest block shape and lighting. Seedream 5.5 also works, but its blocks come out
taller and decorations (e.g. crystals) stick out of the block. One generation takes
about 1–2 minutes. Requires `libtv` logged in and `.libtv/project.json` in the cwd
(project root). For CLI details see the global `libtv-cli` skill.

Run all commands from the project root, with `$S = ".agents/skills/terrain-tile-3x3/scripts"`.

## Steps

1. **Inspect the source tiles.** Check their sizes and choose 9 for the reference.
   Prefer tiles that share the same canvas size and silhouette.
   ```powershell
   python -c "from PIL import Image;import glob;[print(f,Image.open(f).size) for f in glob.glob('meowa_tiles/terrain/*.png')]"
   ```
2. **Build the 3x3 reference.** Tiles are cropped, centered and upscaled with NEAREST
   ×8, which keeps the pixel grid visible to the model:
   ```powershell
   python "$S/make_ref.py" meowa_tiles/terrain_gen/ref_3x3.png --dir meowa_tiles/terrain `
     --pick moist_soil,parched_soil,rock,rock_with_grass,rock_with_moss,sand,snow,soil_with_grass,soil_with_little_grass
   ```
3. **Generate.** Give one description per cell, in reading order:
   ```powershell
   & "$S/generate.ps1" -Ref meowa_tiles/terrain_gen/ref_3x3.png -Name terrain_gen_v1 `
     -OutDir meowa_tiles/terrain_gen/raw -Quality high -Resolution 2K `
     -Items "lava rock ...","cracked blue ice", ... (9 items)
   ```
   - `-Quality` and `-Resolution` are model-specific. Lib Image uses `high` + `2K`.
     For Seedream, pass `-Model "Seedream 5.5" -Quality 2K` and no `-Resolution`.
     Check any model with `libtv model <modelKey>`.
   - To compare models, run them in parallel with `Start-Job`. Start the second job
     about 20 s after the first, so the reference upload is already cached in
     `.libtv/ref_cache.json`. Otherwise both jobs upload it.
   - Use `-ExtraRules` for extra constraints, and `-PromptFile` for a different
     template (e.g. flat top-down tiles instead of isometric blocks). The default
     template is [tile_prompt.txt](./templates/tile_prompt.txt).
4. **Check the raw sheet** (view the image): there must be 9 separate blocks with the
   same camera and similar size, no text, and a transparent or white background.
   If not, regenerate, tighten the prompt, or switch models.
5. **Split to native tiles.** Use the same names as the items:
   ```powershell
   python "$S/split_tiles.py" meowa_tiles/terrain_gen/raw/terrain_gen_v1.png meowa_tiles/terrain_gen/tiles `
     --names lava_rock,cracked_ice,... --mask meowa_tiles/terrain/soil.png --preview meowa_tiles/terrain_gen/preview.png
   ```
   - `--mask TILE` forces the exact silhouette and size of a reference tile, which
     is best for tiles that must line up. `--like TILE` copies only the size; use it
     when tiles have parts sticking out, such as crystals or trees.
   - `--colors N` sets the per-tile palette size (default 16). `--size WxH` is used
     when there is no reference tile.
6. **Verify.** View the preview, and compare it with the originals at the same scale.
   For example, compose the `make_ref.py` output next to `preview.png`, as in
   [results.md](./references/results.md). Look for:
   - readable material;
   - top face brightest, right face darkest;
   - no stray pixels outside the silhouette.

## Gotchas

- An image node with a reference input needs `modeType=image2image`; the script sets it.
- Windows PowerShell 5.1: `"` in prompts is replaced with `'`, and libtv's stderr
  progress output is tolerated. Don't call `libtv` directly with
  `$ErrorActionPreference = "Stop"`.
- `split_tiles.py` splits the sheet into equal thirds. If the model shifts blocks
  across cell borders, regenerate rather than hand-fix.
- Keep the source tiles untouched. Write output to a separate folder
  (e.g. `meowa_tiles/terrain_gen/`).
