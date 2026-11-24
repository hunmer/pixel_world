"""Build a flat-colour 16:9 layout guide for an HD-2D side-view battle background.

The guide only tells the model WHERE things go (sky / backdrop / walkable ground /
thin foreground strip). Bands are given as fractions of the image height.

  python make_layout.py out/layout.png                      # defaults
  python make_layout.py out/layout.png --horizon 0.42 --ground 0.52 --fg 0.95
"""
import argparse
from PIL import Image, ImageDraw

p = argparse.ArgumentParser()
p.add_argument("out")
p.add_argument("--size", default="1920x1080")
p.add_argument("--horizon", type=float, default=0.40, help="sky ends / backdrop starts")
p.add_argument("--ground", type=float, default=0.52, help="backdrop ends / walkable ground starts")
p.add_argument("--fg", type=float, default=0.94, help="walkable ground ends / foreground strip starts")
p.add_argument("--zones", action="store_true", help="draw dashed enemy/party standing zones")
a = p.parse_args()

w, h = map(int, a.size.lower().split("x"))
im = Image.new("RGB", (w, h))
d = ImageDraw.Draw(im)
y = lambda f: int(round(f * h))
d.rectangle([0, 0, w, y(a.horizon)], fill=(150, 190, 230))            # sky
d.rectangle([0, y(a.horizon), w, y(a.ground)], fill=(70, 95, 80))      # backdrop scenery
d.rectangle([0, y(a.ground), w, y(a.fg)], fill=(196, 170, 120))        # walkable flat ground
d.rectangle([0, y(a.fg), w, h], fill=(60, 45, 35))                     # thin blurred foreground strip
if a.zones:
    for x0, x1 in ((0.05, 0.45), (0.55, 0.95)):
        box = [int(x0 * w), y(a.ground + 0.04), int(x1 * w), y(a.fg - 0.03)]
        for i in range(box[0], box[2], 24):
            d.line([i, box[1], min(i + 12, box[2]), box[1]], fill=(120, 100, 70), width=3)
            d.line([i, box[3], min(i + 12, box[2]), box[3]], fill=(120, 100, 70), width=3)
im.save(a.out)
print(a.out, f"{w}x{h}", f"horizon={a.horizon} ground={a.ground} fg={a.fg}")
