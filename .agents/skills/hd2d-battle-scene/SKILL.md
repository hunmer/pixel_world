---
name: hd2d-battle-scene
description: >-
  Generates empty widescreen (16:9) side-view JRPG battle backgrounds in the HD-2D /
  Octopath Traveler style (pixel-art diorama, tilt-shift depth of field, god rays, bloom)
  through the libtv CLI. A style plate and a flat-colour layout guide are fed to
  image-to-image, so every new location keeps the same camera and a LOW foreground with a
  wide flat walkable ground for character sprites. Use when the user asks for battle
  backgrounds / battle scenes / 战斗背景 / 八方旅人风格场景, new locations in that style,
  or to clean characters + HUD out of a battle screenshot.
---

# HD-2D battle background (libtv)

Proven settings: model **General image Pro** (`nebula-ultra`), `modeType=image2image`,
`ratio=16:9`, `quality=2K`. This gives 2752×1536 output in about 1 minute per image.

The pipeline has two references:
- **Style plate** [assets/style_forest_plate.png](./assets/style_forest_plate.png): a clean
  Octopath battle background (characters and HUD removed). It provides the rendering style
  and the low side-view camera only.
- **Layout guide** [assets/layout_default.png](./assets/layout_default.png), built by
  `make_layout.py`. It has flat bands for sky / backdrop / walkable ground / thin
  foreground strip. **This band fixes the "foreground too high, characters have no room"
  problem.** If only the style plate is used, the model copies its tall blurred grass
  ledge (about the bottom 20%). With the guide plus the stage rules in
  [scene_prompt.txt](./templates/scene_prompt.txt), the ground covers about 55–90% of the
  height and the foreground stays a thin strip.

Requires `libtv` logged in and `.libtv/project.json` in the cwd (project root).
Run everything from the project root with `$S = ".agents/skills/hd2d-battle-scene/scripts"`.
Write output to `tmp/hd2d_battle_bg/`. Move approved images into game assets only when
the user asks.

## Steps

1. **(Optional) custom layout.** The defaults are `--horizon 0.40 --ground 0.52 --fg 0.94`:
   ```powershell
   python "$S/make_layout.py" tmp/hd2d_battle_bg/layout_low.png --horizon 0.38 --ground 0.50 --fg 0.96
   ```
   If you change the bands, pass the same `-Horizon/-Ground/-Fg` values to `generate.ps1`
   so the prompt percentages match.
2. **Generate** one location per call. You can run several calls in parallel with
   `Start-Job`, but stagger the first one by about 20 s so the reference upload cache is
   written once:
   ```powershell
   $A = ".agents/skills/hd2d-battle-scene/assets"
   & "$S/generate.ps1" -StyleRef "$A/style_forest_plate.png" -LayoutRef "$A/layout_default.png" `
     -Name bg_desert_v2 -OutDir tmp/hd2d_battle_bg `
     -Scene "vast desert canyon at sunset, crumbling sandstone temple ruins with broken pillars standing far back, smooth wind-rippled sand floor"
   ```
   - Describe the **floor explicitly as flat** ("flat cobblestone courtyard floor",
     "flat packed-snow floor"). Put tall props "far back" or "at the far left/right edges".
   - `-Count 4` gives 4 variants (`<Name>_1..4.png`).
   - `-Quality 4K` gives a larger render.
   - `-ExtraRules` adds set-wide constraints, e.g. "no fire in the foreground".
   - `-Name` must be unique on the canvas. Use a `_v2`, `_v3` suffix.
3. **Check** the image (view it). The flat open ground should run from about the middle
   to near the bottom. The bottom strip should be ≤ about 8% and have no rocks, rubble,
   plants or walls. There should be no characters, text or UI. If a prop intrudes,
   regenerate with a stricter `-ExtraRules`, or lower `--fg` in the layout.

## Cleaning a real screenshot (characters + HUD → empty plate)

To create a new style plate from a game screenshot, upload it and run a single
image2image node (same model / settings) with the prompt: "Remove ALL characters,
monsters, attack effects and ALL GUI/HUD elements (portraits, turn-order bar, HP/SP,
names, WEAK/shield icons, skill label, any text). Output a clean empty battle background.
Keep exactly the same camera, composition and HD-2D rendering." Example from
Octopath 1 forest/beach screenshots: [references/results.md](./references/results.md).

## Gotchas

- An image node with image inputs needs `modeType=image2image`. Otherwise libtv rejects
  the edges with "须为图生图模式". The script sets it.
- Without the layout guide, image2image from a plate copies the plate's foreground height
  and even its dirt-patch layout (a "snow" version looked like the forest with snow).
- Night / fire scenes tend to put embers or burning debris in the bottom strip. Add
  `-ExtraRules "no fire or debris in the bottom of the image"` if needed.
- Windows PowerShell 5.1: `"` in prompts becomes `'`. libtv writes progress to
  stderr, and `*.stderr.log` shows it as a `NativeCommandError`. That is harmless.
- Reference uploads are cached by sha1 in `.libtv/ref_cache.json`. This cache is shared
  with the other libtv skills.
