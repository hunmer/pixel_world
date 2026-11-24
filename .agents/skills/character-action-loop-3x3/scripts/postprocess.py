#!/usr/bin/env python3
"""Post-process a 3x3 action-loop video.

- <out>/seamless.mp4 : the last `--fade` seconds fade back into frame 0, so the
  loop has no visible jump even if some cells did not fully return to the pose.
- <out>/timeline.png : one row per cell, `--samples` evenly spaced frames, used
  to check which action each cell actually performs.
- prints the mean abs diff between the first and last frame (0-255 grey;
  below about 4 means the raw video already loops cleanly).

Usage: python3 postprocess.py anim.mp4 outdir [--n 3] [--samples 12] [--fade 0.3]
Requires ffmpeg/ffprobe on PATH and Pillow.
"""
import argparse, os, subprocess
from PIL import Image, ImageChops, ImageDraw, ImageStat

p = argparse.ArgumentParser()
p.add_argument("video"); p.add_argument("out")
p.add_argument("--n", type=int, default=3)
p.add_argument("--samples", type=int, default=12)
p.add_argument("--fade", type=float, default=0.3)
a = p.parse_args()
os.makedirs(a.out, exist_ok=True)
tmp = os.path.join(a.out, "_frames"); os.makedirs(tmp, exist_ok=True)

def probe(args):
    return subprocess.check_output(["ffprobe", "-v", "error"] + args + [a.video]).decode().strip()

n = int(probe(["-count_frames", "-select_streams", "v", "-show_entries", "stream=nb_read_frames", "-of", "csv=p=0"]))
dur = float(probe(["-show_entries", "format=duration", "-of", "csv=p=0"]))
idx = sorted({round(i * (n - 1) / (a.samples - 1)) for i in range(a.samples)})
sel = "+".join(f"eq(n\\,{i})" for i in idx)
subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", a.video, "-vf", f"select='{sel}'",
                "-vsync", "0", os.path.join(tmp, "t%03d.png")], check=True)
frames = [Image.open(os.path.join(tmp, f"t{k + 1:03d}.png")).convert("RGB") for k in range(len(idx))]

diff = ImageStat.Stat(ImageChops.difference(frames[0].convert("L"), frames[-1].convert("L"))).mean[0]
print(f"frames={n} duration={dur:.2f}s first/last mean diff={diff:.2f}")

# timeline sheet
W = frames[0].width // a.n
h = W // 2
sheet = Image.new("RGB", (h * len(frames), h * a.n * a.n), "white")
for c in range(a.n * a.n):
    r, col = divmod(c, a.n)
    for t, f in enumerate(frames):
        sheet.paste(f.crop((col * W, r * W, (col + 1) * W, (r + 1) * W)).resize((h, h)), (t * h, c * h))
d = ImageDraw.Draw(sheet)
for c in range(a.n * a.n):
    d.text((4, c * h + 4), f"cell{c + 1}", fill="black")
sheet.save(os.path.join(a.out, "timeline.png"))

# seamless loop: fade frame 0 back in over the tail
first = os.path.join(tmp, "t001.png")
st = max(0.0, dur - a.fade - 0.05)
subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", a.video, "-loop", "1", "-i", first,
                "-filter_complex",
                f"[1:v]format=yuva420p,fade=t=in:st={st:.3f}:d={a.fade}:alpha=1[f];[0:v][f]overlay=shortest=1,format=yuv420p",
                "-an", "-c:v", "libx264", "-crf", "16", os.path.join(a.out, "seamless.mp4")], check=True)
print("wrote", os.path.join(a.out, "timeline.png"), os.path.join(a.out, "seamless.mp4"))
