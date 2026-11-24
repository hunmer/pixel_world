#!/usr/bin/env python3
"""Tile a character image into an N x N grid with a per-cell safe area.

The character is auto-cropped from the (near-white) background, then scaled so
its bounding box fits inside `--fill` of the cell (e.g. 0.5 = character height
at most 50% of the cell), leaving margin around it for motion (attacks, jumps,
falling down...). Character is horizontally centered; its feet sit at
`--ground` (fraction of cell height from the top).

Usage:
  python3 make_grid.py side.png grid_side.png --n 3 --size 1440 --fill 0.5 --ground 0.78
  python3 make_grid.py front.png grid.png --plain   # old behavior: just tile the image
"""
import argparse
from PIL import Image, ImageChops

p = argparse.ArgumentParser()
p.add_argument("src")
p.add_argument("dst")
p.add_argument("--n", type=int, default=3)
p.add_argument("--size", type=int, default=1440, help="output side length in px")
p.add_argument("--fill", type=float, default=0.5, help="max character height/width as fraction of cell")
p.add_argument("--ground", type=float, default=0.78, help="feet y position as fraction of cell height")
p.add_argument("--xoff", type=float, default=0.0, help="horizontal offset as fraction of cell (negative=left)")
p.add_argument("--bg", default="white")
p.add_argument("--thresh", type=int, default=30, help="background difference threshold for auto-crop")
p.add_argument("--plain", action="store_true", help="no auto-crop/safe area, just tile")
p.add_argument("--guides", action="store_true", help="draw cell borders (debug only)")
a = p.parse_args()

src = Image.open(a.src).convert("RGB")
cell = a.size // a.n
out = Image.new("RGB", (cell * a.n, cell * a.n), a.bg)

if a.plain:
    w, h = src.size
    s = min(w, h)
    sq = src.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s))
    tile, pos = sq.resize((cell, cell), Image.LANCZOS), (0, 0)
else:
    bg = Image.new("RGB", src.size, (255, 255, 255))
    diff = ImageChops.difference(src, bg).convert("L").point(lambda v: 255 if v > a.thresh else 0)
    bbox = diff.getbbox()
    char = src.crop(bbox)
    mask = diff.crop(bbox)
    cw, ch = char.size
    k = min(cell * a.fill / ch, cell * a.fill / cw)
    nw, nh = max(1, round(cw * k)), max(1, round(ch * k))
    char = char.resize((nw, nh), Image.NEAREST)  # keep pixel-art crisp
    mask = mask.resize((nw, nh), Image.NEAREST)
    tile = Image.new("RGB", (cell, cell), a.bg)
    x = (cell - nw) // 2 + round(a.xoff * cell)
    y = round(a.ground * cell) - nh
    tile.paste(char, (x, y), mask)
    pos = (0, 0)
    print(f"char bbox {bbox} -> {nw}x{nh} in {cell}px cell (fill={a.fill}, ground={a.ground})")

for r in range(a.n):
    for c in range(a.n):
        out.paste(tile, (c * cell + pos[0], r * cell + pos[1]))

if a.guides:
    from PIL import ImageDraw
    d = ImageDraw.Draw(out)
    for i in range(1, a.n):
        d.line([(i * cell, 0), (i * cell, out.height)], fill=(200, 200, 200), width=2)
        d.line([(0, i * cell), (out.width, i * cell)], fill=(200, 200, 200), width=2)

out.save(a.dst)
print(f"saved {a.dst} {out.size} cell={cell}")
