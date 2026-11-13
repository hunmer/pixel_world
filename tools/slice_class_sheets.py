#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""slice_class_sheets.py — 把 AI 生成的角色网格图集切成每角色每状态独立透明 PNG。

针对 skills/class-turnaround-imagegen.md 产物（actions_*.png / classes_turnaround.png）：
网格由生成模型手绘，存在漂移（1254÷5 非整除），故不做裸等分切割：
  1) 对 alpha>8 做连通域分析（4 邻接）；
  2) 按质心落到名义格子 (row = cy//cell_h, col = cx//cell_w) 归属；
  3) 每格取其全部连通域的并集外接框，贴到统一画布（底部中心锚点，底边留 pad）；
  4) 输出 每格 PNG + 每角色行条带 + 条带棋盘格预览 + manifest 增量合并。

用法（每张源图一次调用，--canvas 全程一致保证帧画布稳定）:
    python tools/slice_class_sheets.py \
        --sheet assets/ui/gen/actions_A.png --grid 4x5 \
        --rows archer,assassin,berserker,knight \
        --cols attack,hurt,run,downed,potion \
        --kind actions --out-root assets/ui/gen/split --canvas 360 --manifest assets/ui/gen/split/manifest.json

退出码: 0=全部通过; 1=存在空格/越界/跨格污染等失败。
不写源图，只读。
"""
import argparse
import hashlib
import json
import sys
from collections import deque
from pathlib import Path

from PIL import Image

ALPHA_TH = 8          # 与 tools/slice_ui_sheet.py 一致的不透明阈值
MIN_COMPONENT = 8     # 小于该像素数的连通域视为噪点丢弃（记录）
DEFAULT_PAD = 4       # 底边留白
STRIP_GAP = 8
CHECKER = 16


def sha256(path):
    h = hashlib.sha256()
    h.update(Path(path).read_bytes())
    return h.hexdigest()


def find_components(alpha, w, h):
    """4 邻接连通域，返回 [(bbox(x0,y0,x1,y1 含端), px_count, cx, cy), ...]"""
    pixels = alpha.load()
    visited = bytearray(w * h)
    comps = []
    for start in range(w * h):
        if visited[start] or pixels[start % w, start // w] <= ALPHA_TH:
            continue
        queue = deque([start])
        visited[start] = 1
        x0, y0, x1, y1, count, sx, sy = w, h, 0, 0, 0, 0, 0
        while queue:
            idx = queue.popleft()
            cx, cy = idx % w, idx // w
            count += 1
            sx += cx
            sy += cy
            if cx < x0: x0 = cx
            if cy < y0: y0 = cy
            if cx > x1: x1 = cx
            if cy > y1: y1 = cy
            for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    nidx = ny * w + nx
                    if not visited[nidx] and pixels[nx, ny] > ALPHA_TH:
                        visited[nidx] = 1
                        queue.append(nidx)
        if count >= MIN_COMPONENT:
            comps.append(((x0, y0, x1, y1), count, sx / count, sy / count))
        else:
            print(f"  [warn] 丢弃噪点连通域 {count}px @({x0},{y0})")
    return comps


def checker_bg(size, a=255):
    bg = Image.new("RGBA", size)
    px = bg.load()
    for y in range(size[1]):
        for x in range(size[0]):
            g = 200 if ((x // CHECKER + y // CHECKER) % 2 == 0) else 150
            px[x, y] = (g, g, g, a)
    return bg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", required=True)
    ap.add_argument("--grid", required=True, help="ROWSxCOLS, 如 4x5")
    ap.add_argument("--rows", required=True, help="逗号分隔角色名, 自上而下")
    ap.add_argument("--cols", required=True, help="逗号分隔列名, 自左而右")
    ap.add_argument("--kind", required=True, help="actions / turnaround 等分组名")
    ap.add_argument("--out-root", required=True)
    ap.add_argument("--canvas", type=int, required=True, help="统一正方画布边长")
    ap.add_argument("--pad", type=int, default=DEFAULT_PAD)
    ap.add_argument("--manifest", required=True)
    args = ap.parse_args()

    rows = [s.strip() for s in args.rows.split(",")]
    cols = [s.strip() for s in args.cols.split(",")]
    n_r, n_c = (int(v) for v in args.grid.lower().split("x"))
    assert len(rows) == n_r and len(cols) == n_c, "rows/cols 数量与 grid 不符"
    assert n_r * n_c <= 64

    sheet_path = Path(args.sheet)
    img = Image.open(sheet_path).convert("RGBA")
    w, h = img.size
    cell_w, cell_h = w / n_c, h / n_r
    comps = find_components(img.getchannel("A"), w, h)

    # 质心归属格子
    cells = {}
    stray = []
    for bbox, count, cx, cy in comps:
        r, c = int(cy / cell_h), int(cx / cell_w)
        r = min(max(r, 0), n_r - 1)
        c = min(max(c, 0), n_c - 1)
        # 质心离名义格中心过远视为漂移警告
        ccx, ccy = (c + 0.5) * cell_w, (r + 0.5) * cell_h
        if abs(cx - ccx) > cell_w * 0.45 or abs(cy - ccy) > cell_h * 0.45:
            print(f"  [warn] 连通域质心({cx:.0f},{cy:.0f}) 偏离格({r},{c})中心较远")
        cells.setdefault((r, c), []).append((bbox, count))

    out_root = Path(args.out_root)
    kind_dir = out_root / args.kind
    preview_dir = out_root / "preview"
    kind_dir.mkdir(parents=True, exist_ok=True)
    preview_dir.mkdir(parents=True, exist_ok=True)

    canvas = args.canvas
    errors, entries, strips = [], [], []

    # 先算每格并集外接框并做跨格检查
    boxes = {}
    for r in range(n_r):
        for c in range(n_c):
            lst = cells.get((r, c))
            if not lst:
                errors.append(f"空格子 ({rows[r]},{cols[c]}) 无内容")
                continue
            x0 = min(b[0] for b, _ in lst)
            y0 = min(b[1] for b, _ in lst)
            x1 = max(b[2] for b, _ in lst)
            y1 = max(b[3] for b, _ in lst)
            bw, bh = x1 - x0 + 1, y1 - y0 + 1
            if bw + 2 * args.pad > canvas or bh + 2 * args.pad > canvas:
                errors.append(f"({rows[r]},{cols[c]}) 内容 {bw}x{bh} 超出画布 {canvas}")
            boxes[(r, c)] = (x0, y0, x1, y1)
    # 相邻格并集框重叠 = 可能互相污染
    for (r, c), b in boxes.items():
        for dc in (1,):
            nb = boxes.get((r, c + dc))
            if nb and not (b[2] < nb[0] or nb[2] < b[0] or b[3] < nb[1] or nb[3] < b[1]):
                overlap = (min(b[2], nb[2]) - max(b[0], nb[0]) + 1) * (min(b[3], nb[3]) - max(b[1], nb[1]) + 1)
                errors.append(f"格({rows[r]},{cols[c]}) 与右邻并集框重叠 {overlap}px²")
        for dr in (1,):
            nb = boxes.get((r + dr, c))
            if nb and not (b[2] < nb[0] or nb[2] < b[0] or b[3] < nb[1] or nb[3] < b[1]):
                overlap = (min(b[2], nb[2]) - max(b[0], nb[0]) + 1) * (min(b[3], nb[3]) - max(b[1], nb[1]) + 1)
                errors.append(f"格({rows[r]},{cols[c]}) 与下邻并集框重叠 {overlap}px²")

    if errors:
        for e in errors:
            print(f"[error] {e}")
        sys.exit(1)

    src_sha = sha256(sheet_path)
    baseline = canvas - args.pad  # 底部基线 y(开区间)

    # 切片: 统一画布 + 底部中心锚点
    for r in range(n_r):
        strip = Image.new("RGBA", (n_c * canvas + (n_c - 1) * STRIP_GAP, canvas), (0, 0, 0, 0))
        for c in range(n_c):
            x0, y0, x1, y1 = boxes[(r, c)]
            sprite = img.crop((x0, y0, x1 + 1, y1 + 1))
            sw, sh = sprite.size
            frame = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
            px = canvas // 2 - sw // 2
            py = baseline - sh
            frame.paste(sprite, (px, py))
            name = f"{rows[r]}_{cols[c]}.png"
            out = kind_dir / rows[r] / name
            out.parent.mkdir(parents=True, exist_ok=True)
            frame.save(out)
            amin, amax = frame.getchannel("A").getextrema()
            opaque = sum(1 for v in frame.getchannel("A").getdata() if v > ALPHA_TH)
            entries.append({
                "class": rows[r], "state": cols[c], "kind": args.kind,
                "source": str(sheet_path), "source_sha256": src_sha,
                "source_cell": {"row": r, "col": c},
                "source_bbox": [x0, y0, x1, y1],
                "out": str(out), "size": [canvas, canvas],
                "content_size": [sw, sh], "anchor": "bottom-center",
                "paste_xy": [px, py],
                "alpha_min": amin, "opaque_px": opaque,
            })
            assert amin == 0, f"{name} 无透明背景"
            strip.paste(frame, (c * (canvas + STRIP_GAP), 0))
        strip_path = out_root / "strips" / f"{rows[r]}_{args.kind}.png"
        strip_path.parent.mkdir(parents=True, exist_ok=True)
        strip.save(strip_path)
        checker_bg(strip.size).alpha_composite(strip)
        prev_path = preview_dir / f"{rows[r]}_{args.kind}_preview.png"
        strip.convert("RGBA")
        Image.open(strip_path).convert("RGBA")
        comp = checker_bg(strip.size)
        comp.alpha_composite(Image.open(strip_path).convert("RGBA"))
        comp.convert("RGB").save(prev_path)
        strips.append(str(strip_path))

    # manifest 增量合并（按源图键覆盖）
    mf_path = Path(args.manifest)
    mf = {"sources": {}, "files": []}
    if mf_path.exists():
        mf = json.loads(mf_path.read_text())
    mf.setdefault("sources", {})[str(sheet_path)] = {
        "sha256": src_sha, "size": [w, h], "grid": f"{n_r}x{n_c}",
        "rows": rows, "cols": cols, "kind": args.kind,
    }
    mf["files"] = [f for f in mf.get("files", []) if f.get("source") != str(sheet_path)] + entries
    mf_path.parent.mkdir(parents=True, exist_ok=True)
    mf_path.write_text(json.dumps(mf, ensure_ascii=False, indent=2))

    print(f"[ok] {sheet_path}: {len(entries)} 格 -> {kind_dir}, 条带 {len(strips)} 条, manifest 更新 {mf_path}")


if __name__ == "__main__":
    main()
