# -*- coding: utf-8 -*-
"""去除 AI 生成图中的假透明棋盘格背景，输出真透明 PNG。
用法: python remove_fake_transparency.py <in.png> <out.png>
从四角 flood-fill，棋盘两色(白~灰)及噪声容差内才扩展，遇到 tile 停止。
"""
import sys
from collections import deque
from PIL import Image

def is_bg(c):
    """中性浅色（棋盘白/灰及其阴影），max-min<=8 排除带色偏的雪/石/冰顶。"""
    r, g, b = c[0], c[1], c[2]
    return min(r, g, b) >= 185 and (max(r, g, b) - min(r, g, b)) <= 8

def main(inp, outp):
    img = Image.open(inp).convert("RGBA")
    w, h = img.size
    px = img.load()
    seen = [[False] * w for _ in range(h)]
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_bg(px[x, y]) and not seen[y][x]:
                q.append((x, y)); seen[y][x] = True
    for y in range(h):
        for x in (0, w - 1):
            if is_bg(px[x, y]) and not seen[y][x]:
                q.append((x, y)); seen[y][x] = True
    removed = 0
    while q:
        x, y = q.popleft()
        r, g, b, a = px[x, y]
        px[x, y] = (r, g, b, 0)
        removed += 1
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and is_bg(px[nx, ny]):
                seen[ny][nx] = True
                q.append((nx, ny))
    img.save(outp)
    print(f"removed {removed}/{w*h} px -> {outp}")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
