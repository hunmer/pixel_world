#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""slice_profession_sheets.py — 把 AI 生成的职业网格图集切成「static 身份锚」单帧。

与 tools/slice_class_sheets.py 同源的连通域归格思路（防生成漂移、武器等分离组件、
拒绝裸等分），新增本任务需要的两点：
  1) 全局统一最近邻缩放：所有输出格共用同一个 k = min(格内容适配比)，保持职业间
     相对体型不漂移；k 仅缩小不放大（k<MIN_SCALE 视为异常拒绝并建议更大画布）。
  2) 输出即身份锚：out_dir/<职业id>/static.png，统一画布、底部中心锚点、底边 pad 留白，
     manifest 记录源格 (row,col)、源 bbox、缩放、粘贴位置与 alpha 下限（溯源+帧序）。

用法:
    python3 tools/slice_profession_sheets.py \
        --sheet meowa_tiles/generated/professions_8grid_v1.png \
        --grid 2x4 \
        --ids swordmaster,soldier,recruit_knight,paladin,pegasus_knight,sniper,sage,bishop \
        --only swordmaster,soldier,sniper,sage,bishop \
        --canvas 128 --pad 4 \
        --out-dir meowa_tiles/heroes \
        --manifest meowa_tiles/heroes/professions_static_manifest.json

退出码: 0=全部通过; 1=空格/越界/相邻格重叠/缩放超限/缺 id 等失败。只读源图。
"""
import argparse
import hashlib
import json
import sys
from collections import deque
from pathlib import Path

from PIL import Image

ALPHA_TH = 8          # 不透明阈值，与 tools/slice_class_sheets.py 一致
MIN_COMPONENT = 8     # 小于该像素数的连通域视为噪点丢弃（记录）
DEFAULT_PAD = 4
MIN_SCALE = 0.15      # 全局缩放下限：再小则细节不可辨，属生成异常


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


def cell_of(cx, cy, cell_w, cell_h, n_r, n_c):
    """质心 -> 名义格 (row, col)，越界质心返回 None（不 clamp，直接拒绝）。"""
    r, c = int(cy / cell_h), int(cx / cell_w)
    if not (0 <= r < n_r and 0 <= c < n_c):
        return None
    return r, c


def slice_sheet(args):
    ids = [s.strip() for s in args.ids.split(",")]
    n_r, n_c = (int(v) for v in args.grid.lower().split("x"))
    if len(ids) != n_r * n_c:
        sys.exit(f"[error] --ids 数量 {len(ids)} 与 grid {n_r}x{n_c}={n_r * n_c} 不符")
    only = [s.strip() for s in args.only.split(",")] if args.only else ids
    unknown = [s for s in only if s not in ids]
    if unknown:
        sys.exit(f"[error] --only 含未在 --ids 中声明的 id: {unknown}")
    if args.pad < 0 or args.pad * 2 >= args.canvas:
        sys.exit(f"[error] pad={args.pad} 相对画布 {args.canvas} 非法")

    sheet_path = Path(args.sheet)
    img = Image.open(sheet_path).convert("RGBA")
    w, h = img.size
    cell_w, cell_h = w / n_c, h / n_r   # 浮点格：容忍非整除网格
    comps = find_components(img.getchannel("A"), w, h)

    # 质心归格（不 clamp：跨格越界的质心直接报错，防内容污染错格）
    cells = {}
    for bbox, count, cx, cy in comps:
        rc = cell_of(cx, cy, cell_w, cell_h, n_r, n_c)
        if rc is None:
            sys.exit(f"[error] 连通域质心({cx:.0f},{cy:.0f}) 落在网格外，疑似边框/杂物")
        r, c = rc
        ccx, ccy = (c + 0.5) * cell_w, (r + 0.5) * cell_h
        if abs(cx - ccx) > cell_w * 0.45 or abs(cy - ccy) > cell_h * 0.45:
            print(f"  [warn] 质心({cx:.0f},{cy:.0f}) 偏离格({r},{c})中心较远")
        cells.setdefault((r, c), []).append((bbox, count))

    # 每格并集外接框 + 拒绝条件
    boxes, errors = {}, []
    for i, pid in enumerate(ids):
        r, c = divmod(i, n_c)
        lst = cells.get((r, c))
        if not lst:
            errors.append(f"空格子 {pid} (row{r},col{c}) 无内容")
            continue
        x0 = min(b[0] for b, _ in lst)
        y0 = min(b[1] for b, _ in lst)
        x1 = max(b[2] for b, _ in lst)
        y1 = max(b[3] for b, _ in lst)
        boxes[(r, c)] = (x0, y0, x1, y1)
    for (r, c), b in boxes.items():
        for dr, dc, tag in ((0, 1, "右邻"), (1, 0, "下邻"), (0, -1, "左邻"), (-1, 0, "上邻")):
            nb = boxes.get((r + dr, c + dc))
            if nb and not (b[2] < nb[0] or nb[2] < b[0] or b[3] < nb[1] or nb[3] < b[1]):
                overlap = (min(b[2], nb[2]) - max(b[0], nb[0]) + 1) * (min(b[3], nb[3]) - max(b[1], nb[1]) + 1)
                errors.append(f"格{ids[r * n_c + c]} 与{tag}{ids[(r + dr) * n_c + (c + dc)]} 并集框重叠 {overlap}px²")

    # 全局统一缩放：只对 --only 的输出格计算，保证五个锚点相对体型一致
    scale = 1.0
    for rc in boxes:
        pid = ids[rc[0] * n_c + rc[1]]
        if pid not in only:
            continue
        x0, y0, x1, y1 = boxes[rc]
        bw, bh = x1 - x0 + 1, y1 - y0 + 1
        fit = min((args.canvas - 2 * args.pad) / bw, (args.canvas - 2 * args.pad) / bh)
        scale = min(scale, fit)
    if scale < MIN_SCALE:
        errors.append(f"全局缩放 k={scale:.3f} < {MIN_SCALE}，内容相对画布过大，请改用更大 --canvas")
    if errors:
        for e in errors:
            print(f"[error] {e}")
        sys.exit(1)

    # 输出
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    src_sha = sha256(sheet_path)
    entries = []
    for i, pid in enumerate(ids):
        if pid not in only:
            continue
        r, c = divmod(i, n_c)
        x0, y0, x1, y1 = boxes[(r, c)]
        sprite = img.crop((x0, y0, x1 + 1, y1 + 1))
        sw, sh = sprite.size
        nw, nh = max(1, round(sw * scale)), max(1, round(sh * scale))
        frame = Image.new("RGBA", (args.canvas, args.canvas), (0, 0, 0, 0))
        if (nw, nh) != (sw, sh):
            sprite = sprite.resize((nw, nh), Image.NEAREST)
        px = args.canvas // 2 - nw // 2
        py = args.canvas - args.pad - nh
        frame.paste(sprite, (px, py))
        out = out_dir / pid / "static.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        frame.save(out)
        amin, _ = frame.getchannel("A").getextrema()
        assert amin == 0, f"{out} 无透明背景"
        entries.append({
            "id": pid,
            "source": str(sheet_path), "source_sha256": src_sha,
            "source_cell": {"row": r, "col": c},
            "source_bbox": [x0, y0, x1, y1],
            "content_size_source": [sw, sh],
            "scale": round(scale, 6),
            "size": [args.canvas, args.canvas],
            "content_size": [nw, nh],
            "anchor": "bottom-center", "pad": args.pad,
            "paste_xy": [px, py], "alpha_min": amin,
            "out": str(out),
        })
        print(f"[ok] {pid}: 格(row{r},col{c}) bbox{x1 - x0 + 1}x{y1 - y0 + 1} -> {out} ({nw}x{nh}@{px},{py})")

    mf_path = Path(args.manifest)
    mf = {"sheets": {}, "files": []}
    if mf_path.exists():
        mf = json.loads(mf_path.read_text())
    mf.setdefault("sheets", {})[str(sheet_path)] = {
        "sha256": src_sha, "size": [w, h], "grid": f"{n_r}x{n_c}",
        "ids_row_major": ids, "only": only,
        "cell_size": [cell_w, cell_h], "scale": round(scale, 6),
        "anchor": "bottom-center", "pad": args.pad,
    }
    mf["files"] = [f for f in mf.get("files", []) if f.get("source") != str(sheet_path)] + entries
    mf_path.parent.mkdir(parents=True, exist_ok=True)
    mf_path.write_text(json.dumps(mf, ensure_ascii=False, indent=2))
    print(f"[ok] {len(entries)} 个身份锚 -> {out_dir}, manifest 更新 {mf_path}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--sheet", required=True)
    ap.add_argument("--grid", required=True, help="ROWSxCOLS, 如 2x4")
    ap.add_argument("--ids", required=True, help="行优先职业 id 序列")
    ap.add_argument("--only", default="", help="仅输出这些 id（默认全部）")
    ap.add_argument("--canvas", type=int, required=True)
    ap.add_argument("--pad", type=int, default=DEFAULT_PAD)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--manifest", required=True)
    args = ap.parse_args()
    slice_sheet(args)


if __name__ == "__main__":
    main()
