"""Split a generated R x C plant sheet into native-resolution pixel sprites.

usage: python split_sprites.py SHEET.png OUTDIR --names a,b,... [--rows 3 --cols 3]
         [--pixel auto|N] [--ref-cell 44] [--colors 16] [--canvas WxH]
         [--preview PREVIEW.png] [--scale 8]

The model draws "big pixels" of roughly constant size. The script estimates that size
(--pixel auto, via periodicity of colour edges; prints the value) and downsamples every
sprite by it, so relative plant sizes are preserved. Fallback / override:
  --pixel N        use N output pixels per art pixel
  --ref-cell C     assume the sheet keeps the reference grid: pixel = (W/cols)/C
Per sprite: largest connected blob (+ nearby parts) inside the cell -> trim -> BOX downscale
-> hard alpha -> palette reduction -> optional bottom-center placement on a fixed canvas.
"""
import argparse
import os

import numpy as np
from PIL import Image


def key_white(arr):
    if arr[:, :, 3].min() == 255:  # opaque output -> key out near-white background
        white = arr[:, :, :3].astype(int).sum(axis=2) > 735
        arr[white, 3] = 0
    return arr


def cell_sizes(arr, rows, cols):
    """max(w, h) of the solid content of every cell."""
    H, W = arr.shape[:2]
    out = []
    for r in range(rows):
        for c in range(cols):
            m = arr[round(r * H / rows):round((r + 1) * H / rows), round(c * W / cols):round((c + 1) * W / cols), 3] >= 128
            ys = np.where(m.sum(axis=1) >= 3)[0]
            xs = np.where(m.sum(axis=0) >= 3)[0]
            if len(ys) and len(xs):
                out.append(max(ys[-1] - ys[0] + 1, xs[-1] - xs[0] + 1))
    return out


def estimate_pixel(arr, lo=4, hi=48):
    """Estimate art-pixel size from periodicity of colour edges (both axes)."""
    rgb = arr[:, :, :3].astype(np.int32)
    solid = arr[:, :, 3] >= 128
    scores = np.zeros(hi + 1)
    for axis in (0, 1):
        d = np.abs(np.diff(rgb, axis=axis)).sum(axis=2)
        m = solid[1:, :] & solid[:-1, :] if axis == 0 else solid[:, 1:] & solid[:, :-1]
        d = np.where(m, d, 0)
        sig = d.sum(axis=1 - axis).astype(float)  # edge energy per row/column boundary
        if sig.sum() == 0:
            continue
        sig /= sig.mean()
        for p in range(lo, hi + 1):
            best = 0.0
            for ph in range(p):
                v = sig[ph::p].mean()
                best = max(best, v)
            scores[p] += best
    # multiples of the true period score about the same (or slightly higher due to noise),
    # divisors score about half -> take the smallest p within 75% of the best score
    top = scores[lo:].max()
    for p in range(lo, hi + 1):
        if scores[p] >= 0.75 * top:
            return p, scores
    return int(np.argmax(scores)), scores


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("outdir")
    ap.add_argument("--names", required=True)
    ap.add_argument("--rows", type=int, default=3)
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--pixel", default="auto")
    ap.add_argument("--ref-cell", type=int)
    ap.add_argument("--ref-sheet", help="reference sheet from make_ref.py: match its median sprite size")
    ap.add_argument("--ref-scale", type=int, default=8, help="upscale factor used by make_ref.py")
    ap.add_argument("--colors", type=int, default=0, help="palette size per sprite; 0 = off (small accents like berries survive)")
    ap.add_argument("--canvas", help="WxH: place each sprite bottom-center on a fixed canvas")
    ap.add_argument("--preview")
    ap.add_argument("--scale", type=int, default=8)
    a = ap.parse_args()

    names = [n.strip() for n in a.names.split(",")]
    arr = key_white(np.array(Image.open(a.sheet).convert("RGBA")))
    H, W = arr.shape[:2]
    if a.pixel != "auto":
        px = float(a.pixel)
    elif a.ref_sheet:
        ref = key_white(np.array(Image.open(a.ref_sheet).convert("RGBA")))
        ref_sizes = [s / a.ref_scale for s in cell_sizes(ref, a.rows, a.cols)]
        gen_sizes = cell_sizes(arr, a.rows, a.cols)
        px = float(np.median(gen_sizes) / np.median(ref_sizes))
        print(f"match ref: median ref sprite {np.median(ref_sizes):.1f}px, generated {np.median(gen_sizes):.0f}px")
    elif a.ref_cell:
        px = (W / a.cols) / a.ref_cell
    else:
        px, sc = estimate_pixel(arr)
        best = sorted(range(4, len(sc)), key=lambda p: -sc[p])[:5]
        print("pixel candidates (p:score):", ", ".join(f"{p}:{sc[p]:.1f}" for p in best))
    print(f"art pixel size = {px:.2f} output px")

    cw, ch = W / a.cols, H / a.rows
    os.makedirs(a.outdir, exist_ok=True)
    sprites = []
    for i, name in enumerate(names[: a.rows * a.cols]):
        r, c = divmod(i, a.cols)
        cell = arr[round(r * ch):round((r + 1) * ch), round(c * cw):round((c + 1) * cw)].copy()
        m = cell[:, :, 3] >= 128
        # drop specks: keep rows/cols that have a few solid pixels
        ys = np.where(m.sum(axis=1) >= 3)[0]
        xs = np.where(m.sum(axis=0) >= 3)[0]
        if not len(ys) or not len(xs):
            raise SystemExit(f"ERROR: cell {i} ({name}) is empty")
        crop = Image.fromarray(cell[ys[0]:ys[-1] + 1, xs[0]:xs[-1] + 1])
        nw, nh = max(1, round(crop.width / px)), max(1, round(crop.height / px))
        small = np.array(crop.resize((nw, nh), Image.BOX))
        alpha = small[:, :, 3] >= 128
        rgb = small[:, :, :3]
        if a.colors:
            # FASTOCTREE keeps small distinct accents better than MEDIANCUT
            rgb = np.array(Image.fromarray(rgb).quantize(colors=a.colors, method=Image.FASTOCTREE,
                                                         dither=Image.NONE).convert("RGB"))
        out = np.dstack([rgb, np.where(alpha, 255, 0).astype(np.uint8)])
        spr = Image.fromarray(out, "RGBA")
        spr = spr.crop(spr.getbbox())
        if a.canvas:
            cw_, ch_ = map(int, a.canvas.lower().split("x"))
            canvas = Image.new("RGBA", (cw_, ch_), (0, 0, 0, 0))
            canvas.alpha_composite(spr, ((cw_ - spr.width) // 2, max(0, ch_ - spr.height)))
            spr = canvas
        path = os.path.join(a.outdir, f"{name}.png")
        spr.save(path)
        sprites.append(spr)
        print(path, spr.size)

    if a.preview:
        pad = 4
        cell = max(max(s.width for s in sprites), max(s.height for s in sprites)) + 2 * pad
        rows = (len(sprites) + a.cols - 1) // a.cols
        pv = Image.new("RGBA", (cell * a.cols, cell * rows), (200, 200, 200, 255))
        for i, s in enumerate(sprites):
            r, c = divmod(i, a.cols)
            pv.alpha_composite(s, (c * cell + (cell - s.width) // 2, r * cell + cell - pad - s.height))
        pv.resize((pv.width * a.scale, pv.height * a.scale), Image.NEAREST).save(a.preview)
        print("preview:", a.preview)


if __name__ == "__main__":
    main()

