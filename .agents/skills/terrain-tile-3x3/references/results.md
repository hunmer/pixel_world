# Test results (2026-11-24)

Reference: 9 tiles from `meowa_tiles/terrain`, composed by `make_ref.py`
(960x960, 40px cells ×8).

The 9 `-Items` that were used, in order:

```text
lava rock: dark basalt block with glowing orange lava cracks on top
cracked blue ice
wet mud with small water puddles
grey cobblestone pavement
red clay
loose grey gravel
grass covered with orange autumn leaves
murky green swamp water with lily pads on a dark soil block
purple amethyst crystal rock
```

| Model | Settings | Result |
| --- | --- | --- |
| Lib Image 2.6 Pro | `-Quality high -Resolution 2K`, 1:1, transparent | Closest block proportion (2:1 top, low height) and lighting; clean 3x3 cells. Split with `--mask soil.png`. **Chosen.** |
| Seedream 5.5 | `-Quality 2K`, 1:1, transparent | Good pixel look, but taller cube-like blocks; crystals stick out of the silhouette (use `--like`, not `--mask`). |

Output: `meowa_tiles/terrain_gen/tiles/*.png` (32x26), preview
`meowa_tiles/terrain_gen/preview_lib.png`.
