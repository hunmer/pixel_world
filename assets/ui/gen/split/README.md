# split/ — 角色动作与三视图切片产物（2026-11-14）

由 `tools/slice_class_sheets.py` 从三张 AI 生成源图切出；源图只读未改。
统一帧画布 **288×288 RGBA**，锚点 **bottom-center**（底边留 pad=4），所有帧同尺寸同基线。

## 来源 → 输出映射

| 源图 (sha256 前 8) | 网格 | 行（自上而下） | 列（自左而右） |
| --- | --- | --- | --- |
| actions_A.png (1d32ad20) | 4×5 | archer, assassin, berserker, knight | attack, hurt, run, downed, potion |
| actions_B.png (55c772ae) | 4×5 | lancer, mage, priest, swordsman | attack, hurt, run, downed, potion |
| classes_turnaround.png (580d7a89) | 8×3 | archer, assassin, berserker, knight, lancer, mage, priest, swordsman | front, side, back |

## 目录

- `actions/<class>/<class>_<state>.png` — 8 角色 × 5 动作 = 40 帧
- `turnaround/<class>/<class>_<view>.png` — 8 角色 × 3 视角 = 24 帧
- `strips/<class>_actions.png`（5 帧横条）、`strips/<class>_turnaround.png`（3 帧横条）= 16 条
- `preview/<class>_<kind>_preview.png` — 条带棋盘格预览；`preview/all_frames_contact.png` — 64 帧总览
- `manifest.json` — 每帧的源图、源格 (row,col)、源 bbox、画布位置、alpha 检查

## 已跑检查

- 连通域切分（alpha>8），噪点(<8px)丢弃；空格/跨格重叠检查 0 失败
- `asset_report.py --expect-size 288x288 --require-alpha --json`：64/64 通过
- 目检：all_frames_contact.png + 条带预览，内容与命名一致，无邻格串入

## 已知备注

- 源图生成 alpha 上限为 253–254（非纯 255），切片原样保留，引擎可用
- actions_B 的 priest 无光环，classes_turnaround 的 priest 有光环（两代生成差异）
- classes_turnaround 中 knight front 头顶有 11×1px 剑尖碎线，已随帧保留（属源图内容）
