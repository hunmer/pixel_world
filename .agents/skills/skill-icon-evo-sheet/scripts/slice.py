# -*- coding: utf-8 -*-
"""Slice a generated 10x5 evo sheet into 50 square icons + a normalized 1280x640 sheet.

usage: python slice.py <sheet.png> <element> [size=128]
Gutters found by DP on a "dark & uniform" line signal over the whole sheet,
with a soft prior towards equal cell sizes. Outer decorative frames are trimmed.
"""
import os, sys
import numpy as np
from PIL import Image

COLS, ROWS = 10, 5


def smooth(a, r=4):
    k = np.ones(2 * r + 1) / (2 * r + 1)
    return np.convolve(a, k, mode="same")


def signal(lum, axis):
    """Low where lines are dark AND uniform (gutters). Normalised ~0..1."""
    p = smooth(lum.mean(axis=axis)) + smooth(lum.std(axis=axis))
    a, b = np.percentile(p, 3), np.percentile(p, 97)
    return np.clip((p - a) / max(b - a, 1e-6), 0, 1.5)


def trim_frame(lum, axis, max_frac=0.03):
    """Leading/trailing uniform lines = decorative outer frame."""
    st = lum.std(axis=axis)
    n = len(st)
    lim = int(n * max_frac)
    a = 0
    while a < lim and st[a] < 6:
        a += 1
    b = n
    while n - b < lim and st[b - 1] < 6:
        b -= 1
    return a, b


def find_cuts(profile, n_cells, min_frac=0.55, max_frac=2.0, step=2, lam=0.6):
    L = len(profile)
    avg = L / n_cells
    lo, hi = int(avg * min_frac), int(avg * max_frac)
    xs = list(range(0, L, step))
    INF = float("inf")
    n = len(xs)
    dp = np.full((n_cells, n), INF)
    back = np.full((n_cells, n), -1, dtype=int)
    dp[0][0] = 0.0
    for k in range(1, n_cells):
        for i, x in enumerate(xs):
            best, arg = INF, -1
            for j in range(i - 1, -1, -1):
                w = x - xs[j]
                if w < lo:
                    continue
                if w > hi:
                    break
                v = dp[k - 1][j] + lam * ((w - avg) / avg) ** 2
                if v < best:
                    best, arg = v, j
            if arg >= 0:
                dp[k][i] = best + profile[x]
                back[k][i] = arg
    best, arg = INF, -1
    for i, x in enumerate(xs):
        w = L - x
        if lo <= w <= hi:
            v = dp[n_cells - 1][i] + lam * ((w - avg) / avg) ** 2
            if v < best:
                best, arg = v, i
    cuts = [L]
    k, i = n_cells - 1, arg
    while k > 0:
        cuts.append(xs[i])
        i = back[k][i]
        k -= 1
    cuts.append(0)
    return sorted(cuts)


def pixel_icon(cell, grid=32, colors=24):
    """Pad to square with bg colour, snap to a grid x grid pixel image, reduce palette."""
    h, w = cell.shape[:2]
    s = max(h, w)
    edge = np.concatenate([cell[0], cell[-1], cell[:, 0], cell[:, -1]])
    bg = tuple(int(v) for v in np.median(edge, axis=0))
    sq = Image.new("RGB", (s, s), bg)
    sq.paste(Image.fromarray(cell.astype(np.uint8)), ((s - w) // 2, (s - h) // 2))
    # box-downsample = average of each source pixel block, then palette quantise
    small = sq.resize((grid, grid), Image.BOX)
    return small.quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")


def main():
    path, element = sys.argv[1], sys.argv[2]
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 128
    grid = int(os.environ.get("PIXEL_GRID", "0"))  # >0 => pixel-art mode
    arr = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    lum = arr.mean(axis=2)
    ya, yb = trim_frame(lum, 1)
    xa, xb = trim_frame(lum, 0)
    arr, lum = arr[ya:yb, xa:xb], lum[ya:yb, xa:xb]

    row_cuts = find_cuts(signal(lum, 1), ROWS)
    col_cuts = find_cuts(signal(lum, 0), COLS)
    base = os.path.dirname(os.path.abspath(path))
    out_dir = os.path.join(base, element)
    os.makedirs(out_dir, exist_ok=True)
    sheet = Image.new("RGB", (COLS * size, ROWS * size), (8, 8, 10))
    m = 8  # inset to drop gutter rims; keeps tier size progression intact
    for r in range(ROWS):
        y0, y1 = row_cuts[r] + m, row_cuts[r + 1] - m
        for c in range(COLS):
            x0, x1 = col_cuts[c] + m, col_cuts[c + 1] - m
            cell = arr[y0:y1, x0:x1]
            if grid:
                small = pixel_icon(cell, grid)
                small.save(os.path.join(out_dir, f"{element}_r{r + 1}_t{c + 1:02d}_{grid}px.png"))
                icon = small.resize((size, size), Image.NEAREST)
                icon.save(os.path.join(out_dir, f"{element}_r{r + 1}_t{c + 1:02d}.png"))
                sheet.paste(icon, (c * size, r * size))
                continue
            h, w = cell.shape[:2]
            s = min(h, w)
            oy, ox = (h - s) // 2, (w - s) // 2
            sq = Image.fromarray(cell[oy:oy + s, ox:ox + s].astype(np.uint8))
            icon = sq.resize((size, size), Image.LANCZOS)
            icon.save(os.path.join(out_dir, f"{element}_r{r + 1}_t{c + 1:02d}.png"))
            sheet.paste(icon, (c * size, r * size))
    sheet.save(os.path.join(base, f"{element}_sheet_{COLS}x{ROWS}_{size}.png"))
    print(f"frame x[{xa},{xb}] y[{ya},{yb}] rows {row_cuts} cols {col_cuts}")


if __name__ == "__main__":
    main()
