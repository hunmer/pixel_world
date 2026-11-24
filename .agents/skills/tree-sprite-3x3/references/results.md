# Test results (2026-11-24)

Reference: 9 trees from `meowa_tiles/trees`:
apple_tree, autumn_maple_tree, birch_tree_slender, blue_spruce_tree_small,
cherry_blossom_tree_small, dead_tree_tall, palm_tree_tall, snowy_pine_round, willow_tree.
They were composed into `meowa_tiles/trees_gen/ref_3x3.png` (×8, with a median tree size of 56 px).

## v1 (Lib Image 2.6 Pro vs Seedream 5.5, same prompt)

`-Items`:
```text
a big round green oak tree
an orange tree with small orange fruits
a golden yellow autumn ginkgo tree
a baobab tree with a thick bottle-shaped trunk and small flat canopy
a slim tall dark green cypress tree
a purple flowering jacaranda tree
a clump of green bamboo stalks with leaves
a burnt charred black dead tree
a magical fantasy tree with glowing teal leaves
```
Names: oak_round, orange_tree, ginkgo_autumn, baobab_tree, cypress_tall, jacaranda_tree,
bamboo_clump, charred_dead_tree, glowing_spirit_tree.

| Model | Result |
| --- | --- |
| Lib Image 2.6 Pro (`high`, `2K`) | Dark outline, clumped canopies and flared trunks, closest to the set. **Chosen.** Art pixel ≈ 10.1 output px, sprites 26–55 × 53–60 px. |
| Seedream 5.5 (`2K`) | No outline, finer and painterly; the bamboo looks like a vector illustration. Does not match. |

## v2 (Lib Image 2.6 Pro only, same cached reference)

The items were lemon tree, snowy birch, coconut palm, oak sapling, red autumn tree,
mossy stump with sprouts, round poplar, peach blossom tree and twisted purple
fantasy tree. All 9 cells were clean on the first try. The model drew the sapling
and stump smaller, and the median-matched split kept that (32×45 and 42×37 px).

## Lessons learned
- The transparent background was kept and the alpha output is clean, so key-white is not needed.
- The median-size matching (`--ref-sheet`) gave about 10 px per art pixel on both runs, which is stable.
- Falling petals and sparkles stay inside the sprite bbox. This is acceptable, but add
  "no particles" to the prompt if tight bboxes are needed.

Output: `meowa_tiles/trees_gen/tiles/*.png` (18 trees, from Lib Image), `tiles_seedream/` (comparison),
`preview_lib.png`, `preview_lib_v2.png`, `preview_seedream.png`, `compare_orig_lib_seedream.png`.

## v3: 1x4 @ 21:9 / 2K / high (new default)

Reference: `ref_1x4.png` (apple_tree, blue_spruce_tree_small, dead_tree_tall, willow_tree;
native cell 62x107, sheet 1984x856, same aspect as the 21:9 output).
Items: old oak, tall snowy fir, pear tree, weeping cherry. Output: 2016x864 per image.
That run accidentally had count=4 because of the `$count`/`$Count` collision, which is
now fixed, so it gave 4 variants: `raw/trees_gen_1x4_v1_{1..4}.png` →
`tiles_1x4/v{1..4}/`, `preview_1x4_v{1..4}.png`.

| | 3x3 @ 1:1 2K | 1x4 @ 21:9 2K |
| --- | --- | --- |
| Sheet | 2048x2048 | 2016x864 |
| Cell | 683x683 | 504x864 |
| Generated tree size (median) | ~570 px | ~505–545 px |
| Art pixel (output px) | ~10.1 | ~8.8–9.5 |

- All 4 variants were clean. The pear and snow details are crisper, and descriptions
  were followed closely.
- The art-pixel size is about the same as with 3x3, so most of the gain comes from
  fewer subjects per image, not more pixels per tree. Use `-Resolution 4K` for real
  extra pixels.
- **Clipping:** in all 4 variants the oak crossed the exact 1/4 line (x=504) by about
  30–70 px. `split_sprites.py` now snaps cuts to the nearest empty gap (cuts became
  roughly 560 / 995 / 1495), and the oak went from 53–54 px to 55–58 px wide, no longer clipped.
