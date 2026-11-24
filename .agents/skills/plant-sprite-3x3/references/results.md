# Test results (2026-11-24)

Reference: 9 sprites from `meowa_tiles/plants`:
agave_small, flowering_barrel_cactus, dry_shrub_small, mushroom_cluster_red_large,
pink_lotus, snowy_grass_clump_green, wildflower_yellow, prickly_pear_cactus,
grass_tuft_lush. They were composed into a 1056x1056 sheet (44 px cells ×8).

The 9 `-Items` that were used, in order:

```text
a lush green fern with arching fronds
cattail reeds: a tall clump of thin green reeds with brown cattail heads
a small round blueberry bush with blue berries
a single tall sunflower with a big yellow flower head
a cluster of three red tulips
a cluster of glowing cyan-blue fantasy mushrooms
a tiny young pine tree sapling
a clump of white daisies with yellow centers
an aloe vera plant with thick spiky pale green leaves
```

| Model | Result |
| --- | --- |
| Lib Image 2.6 Pro (`high`, `2K`) | Dark outline and chunky pixels, closest to the reference. **Chosen.** Native sizes after `--ref-sheet` matching: 22–40 px. |
| Seedream 5.5 (`2K`) | Finer pixels, lighter outlines, more painterly. Acceptable, but less consistent with the set. |

Lessons learned:
- `--pixel auto` picked 13 and 31 on the two outputs, which is unreliable. Matching
  the median size of the reference sheet (`--ref-sheet`) is the robust default.
- MEDIANCUT with 16 colors erased the blueberries and turned the daisies cream.
  Palette reduction is now off by default and uses FASTOCTREE when enabled.

Output: `meowa_tiles/plants_gen/tiles/*.png`, plus `preview_lib.png` and
`compare_orig_lib_seedream.png` in the same folder.
