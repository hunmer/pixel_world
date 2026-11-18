#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""slice_status_icons.py — 拆分 status_icons_2x3_raw.png（2行3列，真透明）为 6 张 64x64 图标。

方法（沿用 skill_icons v2 的等比适配 padding 思路，透明版）：
1. 网格按 3 列 x 2 行等分；每格用 alpha>8 求内容 bbox，检查不越格（无串格）。
2. bbox 外扩 12px 裁出完整区域（保留渐变描边衰减）。
3. 贴到方形透明画布（边长=长边）居中，LANCZOS 缩到 64x64 RGBA。
4. 记录每格 bbox/region 坐标到 _slice_coords.json。
"""
import json
import os

from PIL import Image

SRC = "meowa_tiles/generated/status_icons/status_icons_2x3_raw.png"
OUT_DIR = "assets/ui/status"
COORDS_OUT = "meowa_tiles/generated/status_icons/_slice_coords.json"
PAD = 12
ALPHA_TH = 8  # 串格检查用宽松阈值
BBOX_TH = 32  # 主体 bbox 阈值：排除边界孤立半透明噪点（实测第6格边界有 alpha=9 杂散像素）
TARGET = 64

NAMES = [
    ["power_up", "defense_up", "speed_up"],
    ["defense_down", "buff", "debuff"],
]

im = Image.open(SRC).convert("RGBA")
W, H = im.size
cols, rows = 3, 2
cell_w, cell_h = W // cols, H // rows
alpha = im.getchannel("A")

os.makedirs(OUT_DIR, exist_ok=True)
coords = {}

for r in range(rows):
    for c in range(cols):
        name = NAMES[r][c]
        x0, y0 = c * cell_w, r * cell_h
        x1, y1 = min((c + 1) * cell_w, W), min((r + 1) * cell_h, H)
        cell = im.crop((x0, y0, x1, y1))
        ca = cell.getchannel("A")
        bbox = ca.point(lambda p: 255 if p > BBOX_TH else 0).getbbox()
        assert bbox is not None, f"{name}: 单元格无内容"
        bx0, by0, bx1, by1 = bbox
        # 串格检查：内容不得触碰格边界（留至少 4px 间隙）
        assert bx0 >= 4 and by0 >= 4, f"{name}: 内容触上/左边界 bbox={bbox}"
        assert bx1 <= cell.width - 4 and by1 <= cell.height - 4, f"{name}: 内容触下/右边界 bbox={bbox}"

        # 外扩裁切（限制在格内）
        rx0 = max(0, bx0 - PAD)
        ry0 = max(0, by0 - PAD)
        rx1 = min(cell.width, bx1 + PAD)
        ry1 = min(cell.height, by1 + PAD)
        region = cell.crop((rx0, ry0, rx1, ry1))

        # 方形透明画布居中 + LANCZOS 缩放
        side = max(region.width, region.height)
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(region, ((side - region.width) // 2, (side - region.height) // 2), region)
        icon = canvas.resize((TARGET, TARGET), Image.LANCZOS)
        out_path = os.path.join(OUT_DIR, f"{name}.png")
        icon.save(out_path)

        coords[name] = {
            "cell": [x0, y0, x1, y1],
            "bbox_in_src": [x0 + bx0, y0 + by0, x0 + bx1, y0 + by1],
            "region_in_src": [x0 + rx0, y0 + ry0, x0 + rx1, y0 + ry1],
            "region_size": [region.width, region.height],
            "canvas_side": side,
            "alpha_threshold": ALPHA_TH,
            "bbox_threshold": BBOX_TH,
            "pad": PAD,
            "output": out_path.replace("\\", "/"),
        }
        print(f"{name}: bbox_src={coords[name]['bbox_in_src']} region={region.width}x{region.height} -> {out_path}")

with open(COORDS_OUT, "w", encoding="utf-8") as f:
    json.dump({"src": SRC, "src_size": [W, H], "grid": "2x3", "slices": coords}, f, ensure_ascii=False, indent=1)
print("coords saved:", COORDS_OUT)
