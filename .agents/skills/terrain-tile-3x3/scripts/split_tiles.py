"""Split a generated R x C tile sheet into game-ready native-size pixel tiles.

usage: python split_tiles.py SHEET.png OUTDIR --names a,b,c,... [--rows 3 --cols 3]
         [--size 32x26 | --like REF_TILE.png] [--mask REF_TILE.png] [--colors 16]
         [--preview PREVIEW.png] [--scale 8]

Per cell: crop the solid bbox -> downscale to the target size (BOX filter) -> hard alpha
-> per-tile palette reduction. --mask forces the exact silhouette of a reference tile
(recommended: all blocks then tile seamlessly). --like copies size/canvas from a tile.
"""
import argparse
import os

import numpy as np
from PIL import Image


def solid_bbox(arr_a, thr=128, min_px=2):
    m = arr_a >= thr
    rows = np.where(m.sum(axis=1) >= min_px)[0]
    cols = np.where(m.sum(axis=0) >= min_px)[0]
    if not len(rows) or not len(cols):
        return None
    return cols[0], rows[0], cols[-1] + 1, rows[-1] + 1


def fill_holes(rgb, have, need):
    """Copy colors from neighbouring pixels into masked pixels that have no color yet."""
    rgb, have = rgb.copy(), have.copy()
    for _ in range(64):
        todo = need & ~have
        if not todo.any():
            break
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            src_have = np.roll(np.roll(have, dy, 0), dx, 1)
            src_rgb = np.roll(np.roll(rgb, dy, 0), dx, 1)
            take = todo & src_have
            rgb[take] = src_rgb[take]
            have = have | take
            todo = need & ~have
    return rgb


def main():
    p = argparse.ArgumentParser()
    p.add_argument("sheet")
    p.add_argument("outdir")
    p.add_argument("--names", required=True)
    p.add_argument("--rows", type=int, default=3)
    p.add_argument("--cols", type=int, default=3)
    p.add_argument("--size", default="32x26")
    p.add_argument("--like")
    p.add_argument("--mask")
    p.add_argument("--colors", type=int, default=16)
    p.add_argument("--preview")
    p.add_argument("--scale", type=int, default=8)
    a = p.parse_args()

    names = [n.strip() for n in a.names.split(",")]
    tw, th = map(int, a.size.lower().split("x"))
    mask = None
    if a.like or a.mask:
        ref = Image.open(a.mask or a.like).convert("RGBA")
        ref = ref.crop(ref.getbbox())
        tw, th = ref.size
        if a.mask:
            mask = np.array(ref)[:, :, 3] >= 128

    im = Image.open(a.sheet).convert("RGBA")
    arr = np.array(im)
    # if background is opaque white, key it out
    if arr[:, :, 3].min() == 255:
        white = (arr[:, :, :3].astype(int).sum(axis=2) > 735)
        arr[white, 3] = 0
        im = Image.fromarray(arr)
    W, H = im.size
    cw, ch = W / a.cols, H / a.rows
    os.makedirs(a.outdir, exist_ok=True)
    tiles = []
    for i, name in enumerate(names[: a.rows * a.cols]):
        r, c = divmod(i, a.cols)
        cell = im.crop((round(c * cw), round(r * ch), round((c + 1) * cw), round((r + 1) * ch)))
        bb = solid_bbox(np.array(cell)[:, :, 3])
        if bb is None:
            raise SystemExit(f"ERROR: cell {i} ({name}) is empty")
        t = cell.crop(bb).resize((tw, th), Image.BOX)
        ta = np.array(t)
        have = ta[:, :, 3] >= 128
        need = mask if mask is not None else have
        rgb = fill_holes(ta[:, :, :3], have, need)
        # palette reduction on opaque pixels only
        q = Image.fromarray(rgb).quantize(colors=a.colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
        out = np.dstack([np.array(q), np.where(need, 255, 0).astype(np.uint8)])
        tile = Image.fromarray(out, "RGBA")
        path = os.path.join(a.outdir, f"{name}.png")
        tile.save(path)
        tiles.append(tile)
        print(path, tile.size)

    if a.preview:
        pad = 4
        cell = max(tw, th) + 2 * pad
        rows = (len(tiles) + a.cols - 1) // a.cols
        pv = Image.new("RGBA", (cell * a.cols, cell * rows), (200, 200, 200, 255))
        for i, t in enumerate(tiles):
            r, c = divmod(i, a.cols)
            pv.alpha_composite(t, (c * cell + (cell - tw) // 2, r * cell + (cell - th) // 2))
        pv.resize((pv.width * a.scale, pv.height * a.scale), Image.NEAREST).save(a.preview)
        print("preview:", a.preview)


if __name__ == "__main__":
    main()
