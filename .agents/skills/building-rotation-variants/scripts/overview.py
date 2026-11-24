"""Stack sheets vertically on white for visual review.

usage: python overview.py OUT.png SHEET1.png [SHEET2.png ...] [--width 1024]
"""
import argparse

from PIL import Image

p = argparse.ArgumentParser()
p.add_argument("out")
p.add_argument("sheets", nargs="+")
p.add_argument("--width", type=int, default=1024)
a = p.parse_args()

ims = [Image.open(s).convert("RGBA") for s in a.sheets]
ims = [im.resize((a.width, round(im.height * a.width / im.width))) for im in ims]
canvas = Image.new("RGBA", (a.width, sum(im.height for im in ims)), (255, 255, 255, 255))
y = 0
for im in ims:
    canvas.alpha_composite(im, (0, y))
    y += im.height
canvas.convert("RGB").save(a.out)
print(a.out)
