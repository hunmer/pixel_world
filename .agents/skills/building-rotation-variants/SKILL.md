---
name: building-rotation-variants
description: >-
  Generates new style/material variants of an existing multi-direction building
  sprite sheet (e.g. assets/buildings/<name>/sheet.png, 4 frames rotated 90° clockwise,
  top-down orthographic isometric camera) through the libtv CLI, keeping each frame's
  rotation correct, then repacks the output into the same cell layout as the reference.
  Use when the user asks for more variants / reskins / different styles of a building
  sheet, or for rotation-consistent multi-view sprites generated with libtv.
---

# Building rotation-sheet variants (libtv)

Re-skins a reference rotation sheet via image-to-image while preserving geometry,
camera and per-frame rotation. Proven settings: model **Lib Image 2.6 Pro**,
`modeType=image2image`, `ratio=21:9`, `quality=high`, `resolution=2K`,
`background=transparent`; one generation takes about 1 minute.

Requires `libtv` logged in (`libtv account info`) and the working directory to be
bound to a canvas (`.libtv/project.json`; otherwise run `libtv project use <uuid>`).
For libtv details read the global `libtv-cli` skill.

## Steps

1. **Analyse the reference** (view the image). Name its faces (door gable, back
   gable, long walls) and write down which face is front-left / front-right in every
   frame. For the bundled house sheet, clockwise from above, the door gable goes
   front-left → hidden → hidden → front-right. Fill in that per-frame list in
   [rotation_prompt.txt](./templates/rotation_prompt.txt) if the building differs.
2. **Generate.** Run this from the project root, once per style. You can run several
   in parallel with `Start-Job`:
   ```powershell
   $S = ".agents/skills/building-rotation-variants/scripts"
   & "$S/generate.ps1" -Ref assets/buildings/spacious_house/sheet.png `
     -Name house_var_brick -OutDir assets/buildings/spacious_house/variants/raw `
     -Style "a red BRICK house with a terracotta TILE roof, white quoins, blue door"
   ```
   - `-Ref` accepts a local file (it is uploaded once and its node key is cached in
     `.libtv/ref_cache.json`), or an existing node key / name.
   - Optional: `-ExtraRules` (per-frame rules for asymmetric parts), `-Model`,
     `-Ratio`, `-Count`, `-PromptFile` (your own template), `-Y` (canvas position).
   - The script prints the downloaded PNG path(s).
3. **Verify the rotation for every frame** (view the PNG). Check that:
   - the door, chimney and other asymmetric parts are on the expected face in each frame;
   - nothing is mirrored and the frame order is unchanged;
   - the camera angle and size are the same in all frames.
4. **If a frame is wrong**, add explicit per-frame placement to `-ExtraRules`, for example:
   `"Frame 3: chimney at the NEAR front-left end of the ridge (NOT the far end)."`
   Also state the invariant, for example "always above the doorless back gable".
   Then regenerate with `-Count 2` and keep a correct one. If it still fails, try
   another model (`libtv model search --type image`, e.g. `Seedream 5.5`,
   `MiniMax H3 Image`).
5. **Repack** into the reference layout. The script reads the cell size, house width
   and baseline from the reference:
   ```powershell
   python "$S/pack.py" raw/house_var_brick.png variants/sheet_brick.png --ref assets/buildings/spacious_house/sheet.png
   ```
   It fails if it cannot find exactly `--frames` separate objects; if so, regenerate.
6. **Review**: `python "$S/overview.py" out.png ref_sheet.png variants/sheet_*.png`,
   then view `out.png` to compare all sheets side by side.

## Gotchas

- An image node with a reference input **must** have `-s modeType=image2image`, or
  creation fails validation.
- Windows PowerShell 5.1 corrupts `"` inside native-exe arguments, so the script
  converts `"` to `'` in prompts and references the input as `{{Node <nodeKey>}}`.
- Strong wording that works: "Keep EXACTLY the same building geometry … Only change
  the materials/style", together with an explicit per-frame face list and "do not
  mirror, do not reorder".
- Adding parts such as chimneys or porches is the riskiest change. Always give their
  position frame by frame.
