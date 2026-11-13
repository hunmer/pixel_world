# split/ — 角色水平精灵图（2026-11-14 用户纠正版）

由 `tools/slice_class_sheets.py`（slice + merge 子命令）从三张 AI 生成源图切出并按角色合并；源图只读未改。

**正式产物 = 每角色一张水平精灵图**，不再保留独立帧/条带（已删除）。

## 规格

- 每张 **2304×288**：单行 8 格，每格 **288×288**，锚点 **bottom-center**（底边 pad=4）
- 帧序固定：**front, side, back, attack, hurt, run, downed, potion**
- 格内像素为源图原分辨率裁切，未缩放；alpha_min=0 真透明

## 8 张正式精灵图 `sheets/<class>_sheet.png`

archer / assassin / berserker / knight / lancer / mage / priest / swordsman

## 来源映射（详见 manifest.json，每格含 source/源格/源bbox）

| 来源 (sha256 前 8) | 提供格 |
| --- | --- |
| classes_turnaround.png (580d7a89) 8×3 | front, side, back |
| actions_A.png (1d32ad20) 4×5 | archer/assassin/berserker/knight 的 attack…potion |
| actions_B.png (55c772ae) 4×5 | lancer/mage/priest/swordsman 的 attack…potion |

## 预览

- `preview/<class>_sheet_preview.png` — 单角色棋盘格预览 ×8
- `preview/all_sheets_contact.png` — 8 张纵向堆叠总览（2304×2304）

## 已跑检查

- merge 时逐格校验画布位置与 slice 记录一致；缺格/多格即报错
- `asset_report.py sheets/*.png --expect-size 2304x288 --require-alpha --json` → 8/8 通过，零 problems
- 目检 all_sheets_contact.png：行序/帧序正确、无串格、无截断

## 已知备注

- 三视图格（前 3 格）比动作格（后 5 格）小：源图 native 尺寸差异（turnaround ~140px vs actions ~210-270px），同一基线对齐
- 源图部分像素 alpha≤254，原样保留；priest 两代生成有光环差异
- 目录内 `*.png.import` 为 Godot 编辑器自动生成的导入伴随文件
- 复现：先 slice 三张源图（命令见工具 docstring），再 merge --order front,side,back,attack,hurt,run,downed,potion --prune
