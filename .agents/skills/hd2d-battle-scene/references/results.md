# Results log

## 2026-11-24 — initial runs (General image Pro, 16:9, 2K → 2752×1536)

### Screenshot cleaning (style plate creation)
Source: Octopath Traveler 1 battle screenshots `ot-gui-10-ot1-battle-hud-2.jpg` (forest) and
`ot-gui-09-ot1-battle-hud.jpg` (beach ruins). A single image2image pass with the "remove ALL
characters ... and ALL GUI/HUD" prompt removed every sprite, slash effect and HUD element
cleanly and kept the camera. The forest result is `assets/style_forest_plate.png`.

### v1: plate-only reference (NO layout guide) — rejected
Snow / desert / cave / castle generated from the forest plate only.
- The foreground copied the plate: a tall blurred ledge / rubble in the bottom ~20–25%,
  so the walkable ground was only ~60–80% of the height. User feedback: "前景太高了...人物没地方站".
- The snow version reused the forest's tree positions and dirt-patch layout.

### v2: plate + layout guide (`layout_default.png`, horizon .40 / ground .52 / fg .94) — accepted
Output in `tmp/hd2d_battle_bg/`: `bg_desert_v2`, `bg_castle_v2`, `bg_snow_v2`, `bg_cave_v2`.
- Flat ground now covers about 55–90% of the height. The bottom strip is thin and blurred.
- Desert: smooth rippled sand, ruins pushed back. This is the best one.
- Castle: wide flat cobblestones, but small burning debris sits in the bottom strip. Use `-ExtraRules`.
- Snow: a real new location (ice cliffs + frozen waterfall). There is a small snowy-rock lip at the bottom ~12%.
- Cave: flat rock floor with small puddles. Crystals stay on the back walls.
