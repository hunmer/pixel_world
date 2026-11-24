"""Split a generated N-frame strip into a sheet matching the reference cell layout.

usage: python pack.py SRC DST [--ref REF_SHEET] [--frames 4] [--cell 512]
                              [--target-w 470] [--bottom 445] [--no-hard-alpha]
With --ref, cell size / object width / baseline are measured from the reference sheet.
"""
import argparse
import sys

import numpy as np
from PIL import Image


def solid_bbox(img, thr=128, min_px=3):
    a = np.array(img.convert("RGBA"))[:, :, 3] >= thr
    rows = np.where(a.sum(axis=1) >= min_px)[0]
    cols = np.where(a.sum(axis=0) >= min_px)[0]
    if not len(rows) or not len(cols):
        return None
    return cols[0], rows[0], cols[-1] + 1, rows[-1] + 1


def measure_ref(path, frames):
    ref = Image.open(path).convert("RGBA")
    cell = ref.width // frames
    widths, bottoms = [], []
    for i in range(frames):
        bb = solid_bbox(ref.crop((i * cell, 0, (i + 1) * cell, ref.height)))
        if bb:
            widths.append(bb[2] - bb[0])
            bottoms.append(bb[3])
    return cell, ref.height, max(widths), round(sum(bottoms) / len(bottoms))


def split_frames(im, n):
    a = np.array(im)[:, :, 3]
    cols = (a > 16).sum(axis=0) > 0
    runs, start = [], None
    for x, v in enumerate(cols):
        if v and start is None:
            start = x
        elif not v and start is not None:
            runs.append((start, x))
            start = None
    if start is not None:
        runs.append((start, len(cols)))
    runs = [r for r in runs if r[1] - r[0] > 40]  # drop specks
    if len(runs) != n:
        sys.exit(f"ERROR: expected {n} frames, found {len(runs)} column groups {runs}; regenerate.")
    out = []
    for x0, x1 in runs:
        sub = im.crop((x0, 0, x1, im.height))
        out.append(sub.crop(solid_bbox(sub)))
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("src")
    p.add_argument("dst")
    p.add_argument("--ref")
    p.add_argument("--frames", type=int, default=4)
    p.add_argument("--cell", type=int, default=512)
    p.add_argument("--height", type=int)
    p.add_argument("--target-w", type=int, default=470)
    p.add_argument("--bottom", type=int, default=445)
    p.add_argument("--no-hard-alpha", action="store_true")
    a = p.parse_args()

    cell_w, cell_h, target_w, bottom = a.cell, a.height or a.cell, a.target_w, a.bottom
    if a.ref:
        cell_w, cell_h, target_w, bottom = measure_ref(a.ref, a.frames)

    im = Image.open(a.src).convert("RGBA")
    frames = split_frames(im, a.frames)
    scale = target_w / max(f.width for f in frames)  # one scale for all frames keeps them consistent
    sheet = Image.new("RGBA", (cell_w * a.frames, cell_h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        f = f.resize((round(f.width * scale), round(f.height * scale)), Image.LANCZOS)
        if not a.no_hard_alpha:
            arr = np.array(f)
            arr[:, :, 3] = np.where(arr[:, :, 3] >= 128, 255, 0)
            f = Image.fromarray(arr)
        x = i * cell_w + cell_w // 2 - f.width // 2
        y = max(0, bottom - f.height)
        sheet.alpha_composite(f, (x, y))
    sheet.save(a.dst)
    print(f"{a.dst}  cell={cell_w}x{cell_h} target_w={target_w} bottom={bottom} scale={scale:.3f}")


if __name__ == "__main__":
    main()
