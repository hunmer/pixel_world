#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""test_slice_profession_sheets.py — slice_profession_sheets.py 最小契约测试。

覆盖: 非整除网格 / 分离武器组件并集 / 空格与跨格污染拒绝 / 底部中心锚点与行优先帧序。
纯 stdlib + Pillow，合成图无外部素材依赖。直接 `python3 tools/test_slice_profession_sheets.py` 运行。
"""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

TOOL = str(Path(__file__).resolve().parent / "slice_profession_sheets.py")


def blob(img, x0, y0, x1, y1, color=(200, 40, 40, 255)):
    """实心矩形色块（含端坐标）。"""
    px = img.load()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px[x, y] = color


def run_tool(args):
    return subprocess.run([sys.executable, TOOL] + args, capture_output=True, text=True)


class SliceProfessionSheetsTest(unittest.TestCase):
    def _sheet(self, size):
        img = Image.new("RGBA", size, (0, 0, 0, 0))
        return img

    def test_non_divisible_grid(self):
        """129x65 的 2x2 网格（格宽 64.5 / 格高 32.5，非整除）仍能正确归格与映射。"""
        img = self._sheet((129, 65))
        blob(img, 10, 5, 40, 25)      # (0,0)
        blob(img, 75, 5, 120, 25)     # (0,1)
        blob(img, 10, 40, 40, 60)     # (1,0)
        blob(img, 75, 40, 120, 60)    # (1,1)
        with tempfile.TemporaryDirectory() as td:
            sheet = str(Path(td) / "s.png")
            img.save(sheet)
            r = run_tool(["--sheet", sheet, "--grid", "2x2",
                          "--ids", "a,b,c,d", "--canvas", "32", "--pad", "2",
                          "--out-dir", f"{td}/out", "--manifest", f"{td}/m.json"])
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            mf = json.loads(Path(f"{td}/m.json").read_text())
            by_id = {e["id"]: e for e in mf["files"]}
            self.assertEqual(by_id["a"]["source_cell"], {"row": 0, "col": 0})
            self.assertEqual(by_id["d"]["source_cell"], {"row": 1, "col": 1})
            self.assertTrue(Path(f"{td}/out/a/static.png").exists())

    def test_weapon_separated_components_union(self):
        """同格内分离的「武器」组件并入该格并集外接框，不丢件不错格。"""
        img = self._sheet((200, 100))
        blob(img, 10, 30, 45, 90)     # a (0,0)
        blob(img, 160, 30, 195, 90)   # 本体 b (0,1)
        blob(img, 140, 10, 152, 22)   # 分离武器，与本体同格左上方
        with tempfile.TemporaryDirectory() as td:
            sheet = str(Path(td) / "s.png")
            img.save(sheet)
            r = run_tool(["--sheet", sheet, "--grid", "1x2",
                          "--ids", "a,b", "--canvas", "64", "--pad", "4",
                          "--out-dir", f"{td}/out", "--manifest", f"{td}/m.json"])
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            mf = json.loads(Path(f"{td}/m.json").read_text())
            by_id = {e["id"]: e for e in mf["files"]}
            self.assertEqual(by_id["b"]["source_bbox"], [140, 10, 195, 90])  # 并集框含武器

    def test_empty_cell_and_cross_cell_rejected(self):
        """空格拒绝；并集框跨格重叠（污染邻格）拒绝且不写输出。"""
        # 空格
        img = self._sheet((100, 50))
        blob(img, 10, 10, 40, 40)     # 只有 (0,0) 有内容
        with tempfile.TemporaryDirectory() as td:
            sheet = str(Path(td) / "s.png")
            img.save(sheet)
            r = run_tool(["--sheet", sheet, "--grid", "1x2",
                          "--ids", "a,b", "--canvas", "32", "--pad", "2",
                          "--out-dir", f"{td}/out", "--manifest", f"{td}/m.json"])
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("空格子", r.stdout)
            self.assertFalse(Path(f"{td}/out").exists())
        # 跨格重叠：a 的 L 形本体框与 b 的矩形框相交，但像素不相连（两组件）
        img = self._sheet((100, 50))
        blob(img, 10, 10, 60, 20)     # a 横臂
        blob(img, 10, 21, 20, 40)     # a 竖臂（与横臂相接成 L，同一连通域）
        blob(img, 30, 30, 90, 40)     # b 矩形，落在 a 的框内缺口处，像素不接触
        with tempfile.TemporaryDirectory() as td:
            sheet = str(Path(td) / "s.png")
            img.save(sheet)
            r = run_tool(["--sheet", sheet, "--grid", "1x2",
                          "--ids", "a,b", "--canvas", "64", "--pad", "2",
                          "--out-dir", f"{td}/out", "--manifest", f"{td}/m.json"])
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("重叠", r.stdout)
            self.assertFalse(Path(f"{td}/out").exists())

    def test_anchor_frame_order_and_alpha(self):
        """行优先 id 映射、底部中心锚点 + pad 留白、全局统一缩放、输出真透明。"""
        img = self._sheet((128, 64))
        blob(img, 5, 10, 25, 60)      # a (0,0) 高 51
        blob(img, 70, 30, 85, 60)     # b (0,1) 高 31（更矮）
        with tempfile.TemporaryDirectory() as td:
            sheet = str(Path(td) / "s.png")
            img.save(sheet)
            r = run_tool(["--sheet", sheet, "--grid", "1x2",
                          "--ids", "a,b", "--canvas", "32", "--pad", "4",
                          "--out-dir", f"{td}/out", "--manifest", f"{td}/m.json"])
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            mf = json.loads(Path(f"{td}/m.json").read_text())
            by_id = {e["id"]: e for e in mf["files"]}
            # 全局统一缩放 k 一致，相对体型保持
            self.assertEqual(by_id["a"]["scale"], by_id["b"]["scale"])
            ka = by_id["a"]["scale"]
            # a 高 51 -> 缩放后 32-8=24 上限
            self.assertEqual(by_id["a"]["content_size"][1], round(51 * ka))
            self.assertEqual(by_id["b"]["content_size"][1], round(31 * ka))
            for pid, canvas in (("a", 32), ("b", 32)):
                e = by_id[pid]
                out = Path(td) / "out" / pid / "static.png"
                fr = Image.open(out).convert("RGBA")
                self.assertEqual(fr.size, (canvas, canvas))
                a = fr.getchannel("A")
                amin, amax = a.getextrema()
                self.assertEqual(amin, 0)          # 真透明
                self.assertEqual(amax, 255)
                self.assertEqual(e["anchor"], "bottom-center")
                px, py = e["paste_xy"]
                self.assertEqual(py, canvas - e["pad"] - e["content_size"][1])  # 底边 pad 留白
                self.assertEqual(px, canvas // 2 - e["content_size"][0] // 2)   # 水平居中


if __name__ == "__main__":
    unittest.main(verbosity=2)
