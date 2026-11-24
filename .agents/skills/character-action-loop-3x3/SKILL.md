---
name: character-action-loop-3x3
description: >-
  Turns one character image (pixel-art hero, enemy, NPC) into a looping SRPG / tactics
  action sheet video using libtv. It generates a 45-degree (or pure side) full-body view
  with Lib Image 2.6 Pro, tiles it into a 3x3 grid with a per-cell safe area, then
  animates all 9 cells at once with Wan 3.0 (idle, run, attack, skill, damage, defend,
  death, weak, win). Every cell acts in place and returns to the start pose for a
  seamless loop. Use when the user asks for character battle animations, an action
  sheet, sprite motion loops, idle/attack/death animations, or a 3x3 animated grid of
  a character.
---

# Character 3×3 action loop (libtv)

Pipeline: **character image → 45°/side view (1:1) → 3×3 safe-area grid → Wan 3.0 video
(5 s) → seamless loop + per-cell timeline check.** It takes about 4–6 minutes in total.

Requires `libtv` logged in and `.libtv/project.json` in the cwd (project root). Run
everything from the project root with `S=.agents/skills/character-action-loop-3x3/scripts`.

## One command

```bash
bash $S/generate.sh --image path/to/char.png --name thief --char 盗贼 --weapon 匕首 \
  --view 45 --duration 5 --resolution 480P --outdir .tmp/action_loop/thief
```
The output folder contains `view.png`, `grid.png`, `anim.mp4` (raw), `seamless.mp4`
(the one to use for looping) and `timeline.png`.

| Flag | Default | Notes |
| --- | --- | --- |
| `--view` | `45` | `45` = 3/4 view facing right-front; `side` = pure right profile |
| `--duration` | `5` | 3 s is too short for 9 actions incl. death; 5 s worked well |
| `--resolution` | `480P` | Wan 3.0: `480P` / `720P` / `1080P` |
| `--model` | `Wan 3.0` | see model notes below before changing |
| `--fill` / `--ground` / `--xoff` | `0.5` / `0.78` / `-0.05` | safe area: char height = 50% of cell, feet at 78% of cell height, shifted slightly left (faces right) |
| `--skip-view view.png` | — | reuse an existing view image and skip step 1 |

## Steps (what the script does, run manually if needed)

1. **View image.** Upload the source as `<name>_ref_<ts>`. Then create an image node with
   `model=Lib Image 2.6 Pro`, `modeType=image2image` (**required**, or edges are rejected),
   `ratio=1:1`, `resolution=2K`, `quality=high`, using
   [view_prompt.txt](./templates/view_prompt.txt). It asks for a white background, lots of
   margin and no shadow.
2. **Grid.** Run `make_grid.py view.png grid.png --fill 0.5 --ground 0.78 --xoff -0.05`.
   It auto-crops the character from the white bg (threshold 30), scales it with NEAREST
   so the pixels stay crisp, and pastes it into every 480 px cell of a 1440 px grid.
   Add `--guides` for a debug copy with cell borders, but never upload that one.
3. **Video.** Upload the grid, then create a video node with `model=Wan 3.0`,
   `modeType=mixed2video`, `ratio=1:1`, `resolution=480P`, `duration=5`,
   `enableSound=off`, and edge `--left <grid>`. The prompt is
   [video_prompt.txt](./templates/video_prompt.txt): the grid is used as the first frame,
   with hard in-place / no cell crossing / return-to-pose rules and one action per
   cell, named by row and column.
4. **Check.** Run `postprocess.py anim.mp4 outdir`. It prints the first/last frame diff
   (below about 4 means a clean loop), writes `timeline.png` (one row per cell, 12
   samples), and writes `seamless.mp4` (the last 0.3 s fades back to frame 0). **View
   `timeline.png`** and confirm that each cell performs its own action.

## Action layout (default template)

| | col 1 | col 2 | col 3 |
| --- | --- | --- | --- |
| row 1 | idle 待机 | run 原地跑步 | attack 斩击 |
| row 2 | skill 蓄力突刺 | damage 受击闪红 | defend 格挡 |
| row 3 | death 倒地平躺→起身 | weak 单膝跪地喘息 | win 举武器欢呼 |

To change an action, edit the line in `video_prompt.txt`. Always phrase it as **原地**
(in place). For actions that end in a different pose (death, kneel), explicitly add
"然后原地站起" so the loop closes.

## Model notes (tested 2026-11, see [results.md](./references/results.md))

- **Wan 3.0 mixed2video**: best result. Each cell does a different action, stays in
  place, and the last frame returns to frame 0 (diff ≈ 2–3).
- **Wan 3.0 / Wan 3.0 Prime frames2video** (first+last frame) **fails instantly**
  server-side, with "视频生成失败，积分已返还", for any image. Do not use it.
- **MiniMax H3** frames2video works, but only at 5–15 s and 768P/2K. Cells act
  differently, but some cells may not return to the pose, so use `seamless.mp4`.
- **Kling 4.0 Flash**: no frames2video mode. With singleImage2video, all 9 cells play
  the **same** action in sync, so it is not usable for action sheets.
- Kling 4.0 (not Flash) has `multiFrame2video` (1–10 frames), which is untested.
- Seedance is excluded per user preference.
