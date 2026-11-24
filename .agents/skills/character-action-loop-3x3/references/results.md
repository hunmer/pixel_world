# Results log

Test character: pixel-art thief (`盗贼thief-男性_cropped.png`, front/side/back sheet).
Canvas: libtv project `f5c3477eb0a4418a8738bad24042f732` ("盗贼循环动作").

| # | View | Model / mode | Settings | Outcome |
| - | ---- | ------------ | -------- | ------- |
| 1 | front, grid without safe area | Wan 3.0 frames2video | 1:1 480P 3s | **failed instantly** (5 retries, also 720P/5s, single image, Wan 3.0 Prime) |
| 2 | front | MiniMax H3 frames2video | adaptive 768P 5s | ok. Middle and bottom rows clearly animated, top row barely moved |
| 3 | side, safe area 0.5 | MiniMax H3 frames2video | 768P 5s | ok, stays in cells. Last frame: 2 cells not back in pose, so seamless fade needed |
| 4 | 45°, safe area 0.5 | Kling 4.0 Flash singleImage2video | 720p 5s (960²) | in place and loops (diff 1.5), **but all cells do the same action in sync** |
| 5 | 45° | Wan 3.0 frames2video | 480P 3s | failed instantly again |
| 6 | 45° | Wan 3.0 mixed2video | 1:1 480P 3s (640²) | **good**. Different actions per cell, in place, loops (diff 3.0). Walk came out as a stance, dodge as a 2nd attack |
| 7 | 45° | Wan 3.0 mixed2video | 1:1 480P **5s** | **best**. run, full death fall (lies flat, gets up), weak kneel, win, attack, skill, damage, defend all visible; diff 2.3. Idle is very subtle; actions are front-loaded in the first ~3 s |

Lessons:
- A safe area of character height ≈ 50% of the cell is enough. Nothing crossed cell borders.
- Phrase every action as 原地 (in place). Unconstrained "dodge / walk" makes the model drift or
  substitute another action.
- Name cells as "第N行左/中/右" and add "动作各不相同、互不同步", or some models sync all cells.
