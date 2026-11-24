# Proven style prompts (`-Style`) and extra rules

All of these passed the per-frame rotation check on the first try with Lib Image 2.6 Pro.
The exception is the brick house with a chimney, which needed the `-ExtraRules` below.

| Variant | `-Style` |
| --- | --- |
| thatch | a rustic medieval cottage with a thick golden straw THATCHED roof, cream white plaster walls with dark brown timber framing, a low rough fieldstone base, small wooden shuttered windows, a green wooden front door with a small stone step. |
| logcabin | a snowy winter LOG CABIN: walls made of stacked round dark-brown pine logs with notched log ends at the corners, a dark wooden plank roof covered with a thick layer of white SNOW with small icicles along the eaves, a grey stone base with a bit of snow, small warm-lit windows with wooden frames, a sturdy wooden front door with a small snowy stone step. |
| desert | a desert ADOBE house: smooth sandy beige mud-brick plaster walls with exposed wooden beam ends, a turquoise-teal glazed ceramic TILE roof, a sandstone base, small arched windows with wooden lattice, a carved wooden front door with a small sandstone step, a terracotta pot next to the door. |
| mossy | an old abandoned forest house: weathered grey stone walls partly covered with green moss and climbing ivy, a dark slate roof with patches of green moss and a few missing slates, a mossy cobblestone base, boarded-up wooden windows, a worn brown wooden front door with a small mossy stone step. |
| brick (+chimney) | a red BRICK townhouse with an orange-red terracotta clay TILE roof, white stone window sills and corner quoins, a grey stone base, white-framed glass windows, a dark blue wooden front door with a small stone step, and a single red brick CHIMNEY rising from the roof ridge right above the BACK gable end (the gable end opposite the door). |
| tudor  | a half-timbered Tudor house: dark oak wooden SHINGLE roof, ochre yellow plaster walls with black timber beams, a red brick base, leaded diamond-pane windows, a red front door with a small stone step. |

## `-ExtraRules` for a chimney above the back gable (4 frames, clockwise)

```text
The chimney is attached to the house, so it rotates with it and is always above the doorless back gable; it is NEVER above the door.
Frame 1: chimney at the FAR back-right end of the ridge (top right of the roof).
Frame 2: chimney at the NEAR front-right end of the ridge, directly above the right gable.
Frame 3: chimney at the NEAR front-left end of the ridge, directly above the left gable (NOT at the far end).
Frame 4: chimney at the FAR back-left end of the ridge (top left of the roof).
```

Use the same approach for any asymmetric part, such as a porch, side shed or sign:
1. Work out the part's face or corner in frame 1.
2. Rotate it 90° clockwise for each following frame (front-left → back-left →
   back-right → front-right → front-left …).
3. Write one line per frame.
