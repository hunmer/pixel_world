# -*- coding: utf-8 -*-
"""Pixel-art version of the 10x5 evo sheets with Lib Image 2.6 Pro.

usage: python make_pixel.py fire [ice ...]   (env PIX_SUFFIX, default "_p1")
Reference = the painted evo sheet node of the same element (layout & evolution lines).
"""
import os, subprocess, sys
from make_nodes import SHEETS

FINAL = {"fire": "v2", "ice": "v3", "holy": "v2", "dark": "v2", "wind": "v2", "physical": "v3"}
SUFFIX = os.environ.get("PIX_SUFFIX", "_p1")

TEMPLATE = (
    '把 {{{{Node "{ref}"}}}} 重新绘制成复古像素风（pixel art）游戏技能图标表，保持原图的布局、每一格的主题和从左到右的进化顺序。'
    "严格 10 列 × 5 行网格，共 50 个图标，每一行恰好 10 个、每一列恰好 5 个，所有格子大小相同、严格对齐，"
    "格与格之间留出均匀的纯黑细间隔，每个图标是独立完整的方形，主体不超出格子。"
    "像素风要求：每个图标相当于 32×32 像素的低分辨率像素画等比放大，像素块清晰方正、硬边、无抗锯齿、无模糊、无渐变柔光，"
    "使用有限调色板（每个图标约 12~16 色），主体有 1 像素深色描边，光晕和发光用像素抖动（dithering）与阶梯色块表现，"
    "近黑色深色背景，类似 16-bit SNES/GBA 时代 RPG 的技能图标。"
    "每一行是一条技能进化线（「{name}系」）：第 1~3 列初级，像素图形简单、体积小、颜色少；第 4~7 列中级，细节与粒子增多；"
    "第 8~10 列高级到顶级，体积大、色彩丰富、加入金色与白色高光像素，第 10 列最华丽。"
    "五行分别为：{rows}。整张统一{color}色系。"
    "画面中绝对不要出现任何文字、数字、编号或角标，不要边框装饰、不要网格线、不要底座。"
)


def main():
    for key in sys.argv[1:] or list(SHEETS):
        name, color, rows = SHEETS[key]
        ref = os.environ.get("PIX_REF", "skill_evo_{key}_10x5_{ver}").format(key=key, ver=FINAL[key])
        rows_txt = "；".join(f"第 {n} 行「{r}」" for n, r in enumerate(rows, 1))
        prompt = TEMPLATE.format(ref=ref, name=name, color=color, rows=rows_txt)
        node = f"pixel_evo_{key}_10x5{SUFFIX}"
        cmd = ["libtv", "node", "create", node, "-t", "image",
               "-s", "model=Lib Image 2.6 Pro", "-s", "modeType=image2image",
               "-s", "ratio=2:1", "-s", "resolution=2K", "-s", "quality=high",
               "-s", "output_format=png", "-s", "background=opaque",
               "--prompt", prompt, "--left", ref, "--run"]
        print(">>", node, flush=True)
        r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                           errors="replace")
        print(r.stdout[-400:], r.stderr[-1500:], flush=True)


if __name__ == "__main__":
    main()
