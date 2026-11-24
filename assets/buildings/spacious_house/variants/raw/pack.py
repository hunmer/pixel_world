"""Split a generated 4-frame strip into a 2048x512 sheet matching the reference layout."""
import sys
import numpy as np
from PIL import Image

CELL = 512
TARGET_W = 470      # reference house width in a cell (~469px)
BOTTOM = 445        # reference bottom y in a cell
CENTER_X = 256


def split_frames(im):
    a = np.array(im)[:, :, 3]
    cols = (a > 16).sum(axis=0) > 0
    runs, start = [], None
    for x, v in enumerate(cols):
        if v and start is None:
            start = x
        elif not v and start is not None:
            runs.append((start, x)); start = None
    if start is not None:
        runs.append((start, len(cols)))
    runs = [r for r in runs if r[1] - r[0] > 40]  # drop specks
    if len(runs) != 4:
        raise SystemExit(f"expected 4 frames, found {len(runs)}: {runs}")
    frames = []
    for x0, x1 in runs:
        sub = im.crop((x0, 0, x1, im.height))
        sa = np.array(sub)[:, :, 3]
        # bbox from solid pixels only, ignoring rows with only a few stray pixels
        rows = np.where((sa >= 128).sum(axis=1) >= 3)[0]
        cs = np.where((sa >= 128).sum(axis=0) >= 3)[0]
        frames.append(sub.crop((cs[0], rows[0], cs[-1] + 1, rows[-1] + 1)))
    return frames


def main(src, dst):
    im = Image.open(src).convert("RGBA")
    frames = split_frames(im)
    scale = TARGET_W / max(f.width for f in frames)
    sheet = Image.new("RGBA", (CELL * 4, CELL), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        f = f.resize((round(f.width * scale), round(f.height * scale)), Image.LANCZOS)
        arr = np.array(f)
        arr[:, :, 3] = np.where(arr[:, :, 3] >= 128, 255, 0)
        f = Image.fromarray(arr)
        x = i * CELL + CENTER_X - f.width // 2
        y = BOTTOM - f.height
        sheet.alpha_composite(f, (x, max(0, y)))
    sheet.save(dst)
    print(dst, [f.size for f in frames], round(scale, 3))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
