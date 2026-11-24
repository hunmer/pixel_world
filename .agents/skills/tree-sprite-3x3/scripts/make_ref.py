"""Compose tree sprites into an upscaled R x C reference sheet (same pixel scale for all).

usage:
  python make_ref.py OUT.png --dir meowa_tiles/trees --pick apple_tree,pine_tree_dense,... [--cols 4]
         [--count 4] [--ratio 21:9|none] [--scale 8] [--pad 4] [--align bottom|center] [--bg none|#c8c8c8]
  python make_ref.py OUT.png a.png b.png ...
Default layout: 1 row x 4 columns on a 21:9 sheet (same aspect as the generation), so the model
keeps the cell layout. Sprites keep their native relative sizes (no per-sprite scaling), are trimmed
to their bbox, placed bottom-center (they stand on the ground) in equal cells (widened / heightened
to reach --ratio), then upscaled with NEAREST.
"""
import argparse
import math
import os

from PIL import Image

p = argparse.ArgumentParser()
p.add_argument("out")
p.add_argument("sprites", nargs="*")
p.add_argument("--dir")
p.add_argument("--pick", help="comma separated file stems from --dir, in order")
p.add_argument("--cols", type=int, default=4)
p.add_argument("--count", type=int, default=4)
p.add_argument("--ratio", default="21:9", help="sheet aspect W:H to match the generation ratio, or 'none' (square cells)")
p.add_argument("--scale", type=int, default=8)
p.add_argument("--pad", type=int, default=4)
p.add_argument("--align", choices=["bottom", "center"], default="bottom")
p.add_argument("--bg", default="none")
a = p.parse_args()

files = list(a.sprites)
if a.dir and a.pick:
    files += [os.path.join(a.dir, s.strip() + ".png") for s in a.pick.split(",")]
files = files[: a.count]
if not files:
    raise SystemExit("no sprites given (use --dir with --pick, or list files)")

spr = []
for f in files:
    im = Image.open(f).convert("RGBA")
    spr.append(im.crop(im.getbbox()))
rows = (len(spr) + a.cols - 1) // a.cols
cw = max(s.width for s in spr) + 2 * a.pad
ch = max(s.height for s in spr) + 2 * a.pad
if a.ratio.lower() == "none":
    cw = ch = max(cw, ch)
else:
    rw, rh = map(float, a.ratio.split(":"))
    R = rw / rh
    if a.cols * cw / (rows * ch) < R:
        cw = math.ceil(R * rows * ch / a.cols)
    else:
        ch = math.ceil(a.cols * cw / (R * rows))
bg = (0, 0, 0, 0) if a.bg == "none" else Image.new("RGBA", (1, 1), a.bg).getpixel((0, 0))
sheet = Image.new("RGBA", (cw * a.cols, ch * rows), bg)
for i, s in enumerate(spr):
    r, c = divmod(i, a.cols)
    x = c * cw + (cw - s.width) // 2
    y = r * ch + (ch - a.pad - s.height if a.align == "bottom" else (ch - s.height) // 2)
    sheet.alpha_composite(s, (x, y))
sheet = sheet.resize((sheet.width * a.scale, sheet.height * a.scale), Image.NEAREST)
os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
sheet.save(a.out)
print(f"{a.out} {sheet.size} grid={rows}x{a.cols} native_cell={cw}x{ch} scale={a.scale}")
for f, s in zip(files, spr):
    print(f"  {os.path.basename(f)} {s.size}")
