"""Compose individual tile PNGs into an upscaled R x C reference sheet for image-to-image.

usage:
  python make_ref.py OUT.png TILE1.png TILE2.png ... [--cols 3] [--scale 8] [--pad 4]
  python make_ref.py OUT.png --dir E:/pixel_world/meowa_tiles/terrain [--pick a,b,c,...]
Tiles are cropped to their bbox, centered in equal cells, and upscaled with NEAREST
(keeps the pixel grid crisp so the model sees the true pixel size).
"""
import argparse
import glob
import os

from PIL import Image

p = argparse.ArgumentParser()
p.add_argument("out")
p.add_argument("tiles", nargs="*")
p.add_argument("--dir")
p.add_argument("--pick", help="comma separated file stems from --dir, in order")
p.add_argument("--cols", type=int, default=3)
p.add_argument("--count", type=int, default=9)
p.add_argument("--scale", type=int, default=8)
p.add_argument("--pad", type=int, default=4)
a = p.parse_args()

files = list(a.tiles)
if a.dir:
    if a.pick:
        files += [os.path.join(a.dir, s.strip() + ".png") for s in a.pick.split(",")]
    else:
        files += sorted(glob.glob(os.path.join(a.dir, "*.png")))
files = files[: a.count]
if not files:
    raise SystemExit("no tiles given")

tiles = []
for f in files:
    im = Image.open(f).convert("RGBA")
    tiles.append(im.crop(im.getbbox()))
cw = max(t.width for t in tiles) + 2 * a.pad
ch = max(t.height for t in tiles) + 2 * a.pad
cell = max(cw, ch)  # square cells -> square sheet for a 3x3
rows = (len(tiles) + a.cols - 1) // a.cols
sheet = Image.new("RGBA", (cell * a.cols, cell * rows), (0, 0, 0, 0))
for i, t in enumerate(tiles):
    r, c = divmod(i, a.cols)
    sheet.alpha_composite(t, (c * cell + (cell - t.width) // 2, r * cell + (cell - t.height) // 2))
sheet = sheet.resize((sheet.width * a.scale, sheet.height * a.scale), Image.NEAREST)
os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
sheet.save(a.out)
print(a.out, sheet.size, "tiles:", [os.path.basename(f) for f in files])
