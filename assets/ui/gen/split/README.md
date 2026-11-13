# split/ — 角色水平精灵图（2026-11-14 本体比例统一版）

由 `tools/slice_class_sheets.py`（slice + merge 子命令）从三张 AI 生成源图切出、按角色合并并统一本体视觉比例；源图只读未改。

**正式产物 = 每角色一张水平精灵图**，不再保留独立帧/条带（已删除）。

## 规格

- 每张 **2304×288**：单行 8 格，每格 **288×288**，锚点 **bottom-center**（底边 pad=4，全格内容底边统一 y=284）
- 帧序固定：**front, side, back, attack, hurt, run, downed, potion**
- **本体比例已统一**：动作格（attack…potion）为比例基准 scale=1.0、源分辨率原样；三视图格（front/side/back）按每职业因子 k 最近邻（NEAREST）等比放大，使同一角色三视图与动作站姿的人物本体大小一致。画布 288 无需调整（缩放后最大内容高 239 ≤ 280）。
- alpha_min=0 真透明

## 8 张正式精灵图 `sheets/<class>_sheet.png`

archer / assassin / berserker / knight / lancer / mage / priest / swordsman

## 本体比例统一（测量依据，详见 manifest `files[].body_scale` 与 `cells[].scale`）

- 测量法 **standing_height_parity**：k = 站姿高(actions potion 格 bbox 高) ÷ 站姿高(turnaround front 格 bbox 高)，四舍五入到 4 位小数。potion 为最接近自然站姿的动作格；两者均为站姿，故总高≈本体高（举杯抬臂对两源影响一致，且红绿叠加目检确认头部大小在 k 下吻合）。
- 每职业统一一个 k（三视图格共用，保持三视图彼此一致）；**躺倒 downed / 奔跑 run / 攻击 attack / 受击 hurt 不缩放**，只按同一基线重新锚定——不把非站姿强行拉到站姿高度。
- 前后证据（content 高，缩放前→后；动作格不变）：

| class | k | front | side | back | potion(基准,不变) |
| --- | --- | --- | --- | --- | --- |
| archer | 1.635 | 137→224 | 137→224 | 136→222 | 224 |
| assassin | 1.5714 | 140→220 | 140→220 | 139→218 | 220 |
| berserker | 1.7071 | 140→239 | 140→239 | 140→239 | 239 |
| knight | 1.6286 | 140→228 | 138→225 | 138→225 | 228 |
| lancer | 1.6301 | 146→238 | 146→238 | 146→238 | 238 |
| mage | 1.6159 | 138→223 | 139→225 | 140→226 | 223 |
| priest | 1.6522 | 138→228 | 138→228 | 137→226 | 228 |
| swordsman | 1.6187 | 139→225 | 140→227 | 136→220 | 225 |

- lancer 为骑乘角色：potion/front 均为骑乘姿态，k 按「骑乘整体站姿高（含马体）」对齐，缩放后骑手与马体比例经目检与动作格一致。

## 来源映射（详见 manifest.json，每格含 source/源格/源bbox/scale）

| 来源 (sha256 前 8) | 提供格 |
| --- | --- |
| classes_turnaround.png (580d7a89) 8×3 | front, side, back（scale=k） |
| actions_A.png (1d32ad20) 4×5 | archer/assassin/berserker/knight 的 attack…potion（scale=1.0） |
| actions_B.png (55c772ae) 4×5 | lancer/mage/priest/swordsman 的 attack…potion（scale=1.0） |

## 预览

- `preview/<class>_sheet_preview.png` — 单角色棋盘格预览 ×8
- `preview/all_sheets_contact.png` — 8 张纵向堆叠总览（2304×2304）

## 已跑检查

- merge 时逐格校验：scale=1.0 格画布位置与记录一致；缩放格 fit 断言（≤280px）；front 缩放后与 potion 高度偏差 ≤2px 否则报错；缺格/多格即报错
- 逐格像素断言：每格与源图裁切（缩放格为 NEAREST 结果）逐位一致 → 动作格未动、三视图格无插值模糊
- alpha 范围 [0,255] ×8；内容底边统一 y=284
- `asset_report.py sheets/*.png --expect-size 2304x288 --require-alpha --json` → 8/8 通过，零 problems
- 目检 all_sheets_contact.png + berserker 单张（k 最大者）：三视图与动作姿态本体一致、武器/坐骑完整、无串格、downed/run 未被拉伸

## 已知备注

- k 为非整数，NEAREST 上采样存在固有的像素宽窄不均（2~3 源像素合并模式），属最近邻缩放的正常表现
- 源图部分像素 alpha≤254，原样保留；priest 两代生成有光环差异
- 目录内 `*.png.import` 为 Godot 编辑器自动生成的导入伴随文件
- 复现：先 slice 三张源图（命令见工具 docstring），再 merge --order front,side,back,attack,hurt,run,downed,potion --unify-scale --prune
