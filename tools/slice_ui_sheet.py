#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""slice_ui_sheet.py — 把 AI 生成的透明 UI 图集切成单张小图。

用法:
    python tools/slice_ui_sheet.py assets/ui/gen/element_icons.png -o assets/ui/icons/element
    python tools/slice_ui_sheet.py assets/ui/gen/xxx.png -o out_dir --grid 2x4   # 强制等分网格
    python tools/slice_ui_sheet.py assets/ui/gen/ -o assets/ui/icons             # 整个目录批量

逻辑:
    自动模式(默认): 对 alpha 通道做连通域分析, 每个不透明连通块视为一张图标;
    按行分组(行内按 x 排序, 行间按 y 排序), 命名为 <前缀>_r<行>c<列>.png。
    网格模式(--grid ROWSxCOLS): 跳过检测直接等分切割。
"""
import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("需要 Pillow: pip install pillow")


def load_alpha_mask(img):
    """返回 True=不透明 的布尔掩码。无 alpha 通道的图视为全部不透明。"""
    if img.mode in ("RGBA", "LA", "PA"):
        alpha = img.getchannel("A")
        return alpha.getdata(), alpha
    return None, None


def find_components(img, min_size):
    """连通域分析(4 邻接), 返回 [(x0,y0,x1,y1), ...] 外接框列表。"""
    w, h = img.size
    alpha = img.getchannel("A")
    pixels = alpha.load()
    visited = bytearray(w * h)
    boxes = []
    # BFS, 用简单队列; 图集尺寸中等(<=1536px)足够快
    for start in range(w * h):
        if visited[start] or pixels[start % w, start // w] <= 8:
            continue
        queue = [start]
        visited[start] = 1
        x0, y0, x1, y1, count = w, h, 0, 0, 0
        while queue:
            idx = queue.pop()
            cx, cy = idx % w, idx // w
            count += 1
            if cx < x0: x0 = cx
            if cy < y0: y0 = cy
            if cx > x1: x1 = cx
            if cy > y1: y1 = cy
            for nx, ny in ((cx-1, cy), (cx+1, cy), (cx, cy-1), (cx, cy+1)):
                if 0 <= nx < w and 0 <= ny < h:
                    nidx = ny * w + nx
                    if not visited[nidx] and pixels[nx, ny] > 8:
                        visited[nidx] = 1
                        queue.append(nidx)
        if count >= min_size:
            boxes.append((x0, y0, x1, y1))
    return boxes


def group_rows(boxes, y_tolerance):
    """按 y 中心分行, 行内按 x 排序。"""
    rows = []
    for b in sorted(boxes, key=lambda b: ((b[1] + b[3]) / 2, b[0])):
        cy = (b[1] + b[3]) / 2
        if rows and abs(cy - rows[-1][0]) <= y_tolerance:
            rows[-1][1].append(b)
        else:
            rows.append([cy, [b]])
    return [sorted(items, key=lambda b: b[0]) for _, items in rows]


def slice_auto(src, out_dir, prefix, min_size, pad, y_tolerance):
    img = Image.open(src).convert("RGBA")
    boxes = find_components(img, min_size)
    if not boxes:
        print(f"[跳过] {src.name}: 未检测到不透明内容")
        return []
    rows = group_rows(boxes, y_tolerance)
    saved = []
    for r, row in enumerate(rows):
        for c, (x0, y0, x1, y1) in enumerate(row):
            box = (max(0, x0 - pad), max(0, y0 - pad),
                   min(img.width, x1 + 1 + pad), min(img.height, y1 + 1 + pad))
            tile = img.crop(box)
            name = f"{prefix}_r{r+1}c{c+1}.png"
            tile.save(out_dir / name)
            saved.append(name)
    print(f"[完成] {src.name}: {len(rows)} 行, 共切出 {len(saved)} 张 -> {out_dir}")
    return saved


def slice_grid(src, out_dir, prefix, rows, cols):
    img = Image.open(src).convert("RGBA")
    tw, th = img.width // cols, img.height // rows
    saved = []
    for r in range(rows):
        for c in range(cols):
            tile = img.crop((c * tw, r * th, (c + 1) * tw, (r + 1) * th))
            alpha = tile.getchannel("A")
            if alpha.getextrema()[1] <= 8:
                continue  # 整格全透明, 跳过
            name = f"{prefix}_r{r+1}c{c+1}.png"
            tile.save(out_dir / name)
            saved.append(name)
    print(f"[完成] {src.name}: 网格 {rows}x{cols}, 切出 {len(saved)} 张 -> {out_dir}")
    return saved


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="输入 PNG 或目录")
    ap.add_argument("-o", "--out", required=True, help="输出目录")
    ap.add_argument("--grid", help="强制等分网格, 如 2x4")
    ap.add_argument("--min-size", type=int, default=64, help="最小不透明像素数, 过滤噪点 (默认 64)")
    ap.add_argument("--pad", type=int, default=4, help="裁切外扩像素 (默认 4)")
    ap.add_argument("--y-tolerance", type=int, default=None, help="行分组 y 容差, 默认为图高的 8%%")
    args = ap.parse_args()

    in_path = Path(args.input)
    if in_path.is_dir():
        sources = sorted(p for p in in_path.iterdir() if p.suffix.lower() == ".png")
    else:
        sources = [in_path]
    if not sources:
        sys.exit("没有找到输入 PNG")

    for src in sources:
        out_dir = Path(args.out)
        if in_path.is_dir():
            out_dir = out_dir / src.stem  # 目录批量时按文件名分子目录
        out_dir.mkdir(parents=True, exist_ok=True)
        prefix = src.stem
        if args.grid:
            rows, cols = map(int, args.grid.lower().split("x"))
            slice_grid(src, out_dir, prefix, rows, cols)
        else:
            tol = args.y_tolerance or max(24, int(Image.open(src).height * 0.08))
            slice_auto(src, out_dir, prefix, args.min_size, args.pad, tol)


if __name__ == "__main__":
    main()
