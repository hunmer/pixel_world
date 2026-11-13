#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""slice_class_sheets.py — 把 AI 生成的角色网格图集切成角色精灵图。

针对 skills/class-turnaround-imagegen.md 产物（actions_*.png / classes_turnaround.png）：
网格由生成模型手绘，存在漂移（1254÷5 非整除），故不做裸等分切割：
  1) 对 alpha>8 做连通域分析（4 邻接）；
  2) 按质心落到名义格子 (row = cy//cell_h, col = cx//cell_w) 归属；
  3) 每格取其全部连通域的并集外接框，贴到统一画布（底部中心锚点，底边留 pad）。

子命令:
  slice  — 逐源图切片: 每格 PNG + 每行条带 + manifest 增量合并（中间产物，供 merge 输入）
  merge  — 按 manifest 把每角色各状态合成为单张水平精灵图（如 8 格 2304×288），
           生成棋盘预览，可选 --prune 删除帧/条带等冗余中间产物，并重写 manifest。
           输入既可以是 slice 的帧条目，也可以是之前 merge 写出的 sheet 条目（自动扁平化 cells）。
           加 --unify-scale 后做「本体视觉比例统一」：动作站姿格为基准 scale=1.0，
           三视图格按 k = 站姿高(动作ref)/站姿高(三视图ref) 最近邻等比放大，
           躺倒/奔跑等姿态格不缩放（只重新锚定），详见 README。

用法:
    python tools/slice_class_sheets.py slice --sheet assets/ui/gen/actions_A.png --grid 4x5 \
        --rows archer,assassin,berserker,knight --cols attack,hurt,run,downed,potion \
        --kind actions --out-root assets/ui/gen/split --canvas 288 --manifest assets/ui/gen/split/manifest.json
    python tools/slice_class_sheets.py merge --manifest assets/ui/gen/split/manifest.json \
        --out-root assets/ui/gen/split --canvas 288 \
        --order front,side,back,attack,hurt,run,downed,potion --prune

退出码: 0=全部通过; 1=空格/越界/跨格污染/缺格等失败。不写源图，只读。
"""
import argparse
import hashlib
import json
import shutil
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


def checker_bg(size):
    bg = Image.new("RGBA", size)
    px = bg.load()
    for y in range(size[1]):
        for x in range(size[0]):
            g = 200 if ((x // CHECKER + y // CHECKER) % 2 == 0) else 150
            px[x, y] = (g, g, g, 255)
    return bg


def paste_at(canvas, sprite, px, py):
    """底部中心锚点: px = W//2 - sw//2, py = H - pad - sh"""
    canvas.paste(sprite, (px, py))


# ---------------------------------------------------------------- slice

def cmd_slice(args):
    rows = [s.strip() for s in args.rows.split(",")]
    cols = [s.strip() for s in args.cols.split(",")]
    n_r, n_c = (int(v) for v in args.grid.lower().split("x"))
    assert len(rows) == n_r and len(cols) == n_c, "rows/cols 数量与 grid 不符"

    sheet_path = Path(args.sheet)
    img = Image.open(sheet_path).convert("RGBA")
    w, h = img.size
    cell_w, cell_h = w / n_c, h / n_r
    comps = find_components(img.getchannel("A"), w, h)

    cells = {}
    for bbox, count, cx, cy in comps:
        r, c = int(cy / cell_h), int(cx / cell_w)
        r = min(max(r, 0), n_r - 1)
        c = min(max(c, 0), n_c - 1)
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
    errors, entries = [], []

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
    for (r, c), b in boxes.items():
        for dr, dc, tag in ((0, 1, "右邻"), (1, 0, "下邻")):
            nb = boxes.get((r + dr, c + dc))
            if nb and not (b[2] < nb[0] or nb[2] < b[0] or b[3] < nb[1] or nb[3] < b[1]):
                overlap = (min(b[2], nb[2]) - max(b[0], nb[0]) + 1) * (min(b[3], nb[3]) - max(b[1], nb[1]) + 1)
                errors.append(f"格({rows[r]},{cols[c]}) 与{tag}并集框重叠 {overlap}px²")

    if errors:
        for e in errors:
            print(f"[error] {e}")
        sys.exit(1)

    src_sha = sha256(sheet_path)
    baseline = canvas - args.pad

    for r in range(n_r):
        strip = Image.new("RGBA", (n_c * canvas + (n_c - 1) * STRIP_GAP, canvas), (0, 0, 0, 0))
        for c in range(n_c):
            x0, y0, x1, y1 = boxes[(r, c)]
            sprite = img.crop((x0, y0, x1 + 1, y1 + 1))
            sw, sh = sprite.size
            frame = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
            px = canvas // 2 - sw // 2
            py = baseline - sh
            paste_at(frame, sprite, px, py)
            name = f"{rows[r]}_{cols[c]}.png"
            out = kind_dir / rows[r] / name
            out.parent.mkdir(parents=True, exist_ok=True)
            frame.save(out)
            amin, _ = frame.getchannel("A").getextrema()
            entries.append({
                "class": rows[r], "state": cols[c], "kind": args.kind,
                "source": str(sheet_path), "source_sha256": src_sha,
                "source_cell": {"row": r, "col": c},
                "source_bbox": [x0, y0, x1, y1],
                "out": str(out), "size": [canvas, canvas],
                "content_size": [sw, sh], "anchor": "bottom-center",
                "paste_xy": [px, py], "alpha_min": amin,
            })
            assert amin == 0, f"{name} 无透明背景"
            strip.paste(frame, (c * (canvas + STRIP_GAP), 0))
        strip_path = out_root / "strips" / f"{rows[r]}_{args.kind}.png"
        strip_path.parent.mkdir(parents=True, exist_ok=True)
        strip.save(strip_path)
        comp = checker_bg(strip.size)
        comp.alpha_composite(Image.open(strip_path).convert("RGBA"))
        comp.convert("RGB").save(preview_dir / f"{rows[r]}_{args.kind}_preview.png")

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
    print(f"[ok] slice {sheet_path}: {len(entries)} 格 -> {kind_dir}, manifest 更新 {mf_path}")


# ---------------------------------------------------------------- merge

def _flatten_frames(mf):
    """manifest -> [(class, state, entry)]；兼容帧条目与 sheet 条目（扁平化 cells），(class,state) 去重取首个。"""
    frames, seen = [], set()
    for f in mf.get("files", []):
        if "source_bbox" in f and "class" in f:
            items = [(f["class"], f["state"], f)]
        elif "cells" in f:
            items = [(f["class"], c["state"], c) for c in f["cells"]]
        else:
            continue
        for cls, st, e in items:
            if (cls, st) in seen:
                print(f"  [warn] 重复条目 {(cls, st)}，取首个")
                continue
            seen.add((cls, st))
            frames.append((cls, st, e))
    return frames


def cmd_merge(args):
    mf_path = Path(args.manifest)
    mf = json.loads(mf_path.read_text())
    order = [s.strip() for s in args.order.split(",")]
    canvas, pad = args.canvas, args.pad
    out_root = Path(args.out_root)
    sheets_dir = out_root / "sheets"
    preview_dir = out_root / "preview"
    sheets_dir.mkdir(parents=True, exist_ok=True)
    preview_dir.mkdir(parents=True, exist_ok=True)

    by_class = {}
    for cls, st, e in _flatten_frames(mf):
        by_class.setdefault(cls, {})[st] = e

    classes = sorted(by_class)
    if not classes:
        sys.exit("[error] manifest 中没有可合并的条目（先运行 slice 或提供 sheet cells）")

    # ---- 本体视觉比例统一: k = 站姿高(动作ref) / 站姿高(三视图ref) ----
    cache = {}

    def src_img(path):
        return cache.setdefault(path, Image.open(path).convert("RGBA"))

    def content_wh(e):
        x0, y0, x1, y1 = e["source_bbox"]
        return x1 - x0 + 1, y1 - y0 + 1

    scale_factors, measure, evidence = {}, {}, {}
    if args.unify_scale:
        ref_a, ref_t = (s.strip() for s in args.scale_ref.split(":"))
        scale_states = [s.strip() for s in args.scale_states.split(",")]
        for cls in classes:
            states = by_class[cls]
            for need in (ref_a, ref_t):
                if need not in states:
                    sys.exit(f"[error] {cls}: 缺基准格 {need}，无法 --unify-scale")
            _, ha = content_wh(states[ref_a])
            _, ht = content_wh(states[ref_t])
            k = round(ha / ht, 4)
            if not 1.2 <= k <= 2.2:
                sys.exit(f"[error] {cls}: 缩放因子 k={k} 超出合理区间 [1.2,2.2]，测量异常")
            scale_factors[cls] = {s: (k if s in scale_states else 1.0) for s in order}
            measure[cls] = {
                "method": "standing_height_parity",
                "ref_action_pose": ref_a,
                "ref_turnaround_pose": ref_t,
                "ref_height_px": {ref_t: ht, ref_a: ha},
                "factor": k,
                "scaled_states": scale_states,
                "unscaled_states": [s for s in order if s not in scale_states],
                "note": "动作站姿格为比例基准(scale=1.0)；三视图格按站姿高度比 k 最近邻等比放大；"
                        "躺倒/奔跑/攻击等姿态不强行拉到站姿高度；头部大小经红绿叠加目检校验。",
            }

    sheets, entries = [], []
    for cls in classes:
        states = by_class[cls]
        missing = [s for s in order if s not in states]
        extra = [s for s in states if s not in order]
        if missing or extra:
            sys.exit(f"[error] {cls}: 缺 {missing} 多 {extra}，与 --order 不符")
        sheet = Image.new("RGBA", (len(order) * canvas, canvas), (0, 0, 0, 0))
        cells_meta = []
        for i, st in enumerate(order):
            e = states[st]
            x0, y0, x1, y1 = e["source_bbox"]
            sprite = src_img(e["source"]).crop((x0, y0, x1 + 1, y1 + 1))  # bbox 含端
            sw, sh = sprite.size
            k = scale_factors.get(cls, {}).get(st, 1.0)
            if k != 1.0:
                nw, nh = max(1, round(sw * k)), max(1, round(sh * k))
                if nw + 2 * pad > canvas or nh + 2 * pad > canvas:
                    sys.exit(f"[error] {cls}/{st}: 缩放后 {nw}x{nh} 超出画布 {canvas}(pad={pad})")
                sprite = sprite.resize((nw, nh), Image.NEAREST)
            else:
                nw, nh = sw, sh
            px = canvas // 2 - nw // 2
            py = canvas - pad - nh
            if k == 1.0 and e.get("paste_in_cell") and [px, py] != e["paste_in_cell"]:
                sys.exit(f"[error] {cls}/{st}: 画布位置 {px, py} 与记录 {e['paste_in_cell']} 不一致")
            sheet.paste(sprite, (i * canvas + px, py))
            cells_meta.append({
                "index": i, "state": st,
                "source": e["source"], "source_cell": e["source_cell"],
                "source_bbox": e["source_bbox"],
                "scale": k,
                "content_size_source": [sw, sh],
                "content_size": [nw, nh],
                "cell_origin_in_sheet": i * canvas,
                "paste_in_cell": [px, py],
            })
            if k != 1.0:
                evidence.setdefault(cls, []).append((st, sh, nh, k))
        out = sheets_dir / f"{cls}_sheet.png"
        sheet.save(out)
        amin, _ = sheet.getchannel("A").getextrema()
        assert amin == 0, f"{out} 无透明背景"
        entry = {
            "class": cls, "out": str(out), "size": [sheet.width, sheet.height],
            "cell": [canvas, canvas], "cells_n": len(order), "order": order,
            "anchor": "bottom-center", "alpha_min": amin, "cells": cells_meta,
        }
        if cls in measure:
            entry["body_scale"] = measure[cls]
        entries.append(entry)
        sheets.append((cls, out, sheet))
        comp = checker_bg(sheet.size)
        comp.alpha_composite(sheet)
        comp.convert("RGB").save(preview_dir / f"{cls}_sheet_preview.png")
        print(f"[ok] {out} ({sheet.width}x{sheet.height}, {len(order)} 格)")

    # 全角色总览: 各 sheet 纵向堆叠
    contact = Image.new("RGBA", (sheets[0][2].width, sum(s[2].height for s in sheets)), (0, 0, 0, 0))
    y = 0
    for _, _, sh in sheets:
        contact.paste(sh, (0, y))
        y += sh.height
    comp = checker_bg(contact.size)
    comp.alpha_composite(contact)
    comp.convert("RGB").save(preview_dir / "all_sheets_contact.png")

    # 缩放前后证据表 + 站姿 parity 自动检查
    if args.unify_scale:
        ref_a = args.scale_ref.split(":")[0].strip()
        print("[unify] 本体比例统一证据 (content H: 缩放前→缩放后, k=factor):")
        for cls in classes:
            rows = evidence.get(cls, [])
            line = "  ".join(f"{st} {a}→{b}" for st, a, b, _ in rows)
            print(f"  {cls:10s} k={measure[cls]['factor']:<7} {line}")
            ha = measure[cls]["ref_height_px"][ref_a]
            front_after = dict((st, b) for st, a, b, _ in rows).get(ref_t := args.scale_ref.split(":")[1].strip())
            if front_after is None or abs(front_after - ha) > 2:
                sys.exit(f"[error] {cls}: 缩放后三视图ref高 {front_after} 与动作ref高 {ha} 偏差>2px")

    # manifest 重写为 sheet 条目（保留 sources 与溯源 cells）
    mf["files"] = entries
    mf["layout"] = {
        "sheet": f"{len(order)} 格水平, 每格 {canvas}x{canvas}, 总宽 {len(order) * canvas}",
        "order": order, "anchor": "bottom-center", "pad": pad,
        "body_scale_unified": bool(args.unify_scale),
        "note": ("动作格源分辨率 scale=1.0；三视图格按 files[].body_scale.factor "
                 "最近邻等比放大统一本体比例（测量依据见 body_scale）" if args.unify_scale
                 else "格内像素为源图原分辨率裁切，未缩放"),
    }
    mf_path.write_text(json.dumps(mf, ensure_ascii=False, indent=2))
    print(f"[ok] manifest 重写: {len(entries)} 张 sheet, {mf_path}")

    if args.prune:
        removed = []
        for name in ("actions", "turnaround", "strips"):
            d = out_root / name
            if d.is_dir() and d.parent.resolve() == out_root.resolve():
                shutil.rmtree(d)
                removed.append(str(d))
        for p in sorted(preview_dir.glob("*.png")):
            if p.name not in {f"{c}_sheet_preview.png" for c in classes} | {"all_sheets_contact.png"}:
                p.unlink()
                removed.append(str(p))
        for r in removed:
            print(f"[prune] 已删除 {r}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("slice", help="逐源图切片为独立帧/条带（中间产物）")
    s.add_argument("--sheet", required=True)
    s.add_argument("--grid", required=True, help="ROWSxCOLS, 如 4x5")
    s.add_argument("--rows", required=True)
    s.add_argument("--cols", required=True)
    s.add_argument("--kind", required=True)
    s.add_argument("--out-root", required=True)
    s.add_argument("--canvas", type=int, required=True)
    s.add_argument("--pad", type=int, default=DEFAULT_PAD)
    s.add_argument("--manifest", required=True)
    s.set_defaults(func=cmd_slice)

    m = sub.add_parser("merge", help="按角色合并为单张水平精灵图并清理冗余")
    m.add_argument("--manifest", required=True)
    m.add_argument("--out-root", required=True)
    m.add_argument("--canvas", type=int, required=True)
    m.add_argument("--pad", type=int, default=DEFAULT_PAD)
    m.add_argument("--order", required=True, help="水平帧序, 如 front,side,back,attack,hurt,run,downed,potion")
    m.add_argument("--prune", action="store_true", help="删除 actions/turnaround/strips 目录与旧 preview")
    m.add_argument("--unify-scale", action="store_true",
                   help="本体视觉比例统一：--scale-states 格按 --scale-ref 站姿高度比最近邻等比放大")
    m.add_argument("--scale-states", default="front,side,back",
                   help="参与缩放的状态列表（默认 front,side,back 三视图）")
    m.add_argument("--scale-ref", default="potion:front",
                   help="站姿高度基准 动作格状态:三视图格状态（默认 potion:front）")
    m.set_defaults(func=cmd_merge)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
