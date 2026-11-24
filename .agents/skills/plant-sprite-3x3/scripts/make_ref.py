"""Compose plant sprites into an upscaled R x C reference sheet (same pixel scale for all).

usage:
  python make_ref.py OUT.png --dir meowa_tiles/plants --pick agave_small,cactus,... [--cols 3]
         [--scale 8] [--pad 4] [--align bottom|center] [--bg none|#c8c8c8]
  python make_ref.py OUT.png a.png b.png ...
Sprites keep their native relative sizes (no per-sprite scaling), are trimmed to their bbox,
placed bottom-center (they stand on the ground) in equal square cells, then upscaled with NEAREST.
Prints the native cell size; split_sprites.py can use it as the fallback scale.
"""
import argparse
import os

from PIL import Image

p = argparse.ArgumentParser()
p.add_argument("out")
p.add_argument("sprites", nargs="*")
p.add_argument("--dir")
p.add_argument("--pick", help="comma separated file stems from --dir, in order")
p.add_argument("--cols", type=int, default=3)
p.add_argument("--count", type=int, default=9)
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
cell = max(max(s.width for s in spr), max(s.height for s in spr)) + 2 * a.pad
rows = (len(spr) + a.cols - 1) // a.cols
bg = (0, 0, 0, 0) if a.bg == "none" else Image.new("RGBA", (1, 1), a.bg).getpixel((0, 0))
sheet = Image.new("RGBA", (cell * a.cols, cell * rows), bg)
for i, s in enumerate(spr):
    r, c = divmod(i, a.cols)
    x = c * cell + (cell - s.width) // 2
    y = r * cell + (cell - a.pad - s.height if a.align == "bottom" else (cell - s.height) // 2)
    sheet.alpha_composite(s, (x, y))
sheet = sheet.resize((sheet.width * a.scale, sheet.height * a.scale), Image.NEAREST)
os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
sheet.save(a.out)
print(f"{a.out} {sheet.size} native_cell={cell} scale={a.scale}")
for f, s in zip(files, spr):
    print(f"  {os.path.basename(f)} {s.size}")
