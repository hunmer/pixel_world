# skill_icons_power_guard_haste 素材来源记录（2026-11-18，v2 当前版本）

## 产物（v2）

| 文件 | 说明 | 技能（data/skills.json） |
| --- | --- | --- |
| skill_icons_power_guard_haste.png | v2 生成原图 3136x1344 RGB（1 行 3 列网格） | — |
| assets/ui/skills/power_surge.png | v2 切片 64x64 RGBA（左格·金红能量拳） | powerSurge 力量觉醒（str buff） |
| assets/ui/skills/guard.png | v2 切片 64x64 RGBA（中格·蓝金符文盾） | guard 铁壁（def buff） |
| assets/ui/skills/haste.png | v2 切片 64x64 RGBA（右格·青绿风旋闪电） | haste 疾风（spd buff, wind） |
| _existing_sheet.png | 现有 50 图标合并参考图 1280x640（10x5，每格 128px，无标签） | — |
| _v2_slice_coords.json | v2 每格 bbox 与裁切坐标记录 | — |
| _qa_compare.png | 新旧图标风格对比图（QA 留档） | — |

## v2 生成参数（当前版本）

- 画布：LibTV「meowa_tiles_生成测试」uuid `8f05da05e6c942508e62ce7b4fd35806`（.libtv/project.json 绑定）
- 节点：`skill_icons_power_guard_haste_v2`（image 节点，status=2 / progress=100）
- 模型：Seedream 5.5，modeType=image2image，ratio=21:9，quality=2K，background 未设（深底不透明输出）
- 原图 URL：见 `_v2_url.txt`（libtv-res.liblib.art，随节点留档可回溯）

## v2 直接参考节点

| 节点名 | 节点 id | 内容 |
| --- | --- | --- |
| skill_ref_existing_50_sheet | i-WVG4JemAu7 | 本地 `meowa_tiles/generated/skill_icons/_existing_sheet.png`（当前 01..50.png 合并图，本项目提供参考）上传件 |

- 参考图说明：该合成图由本项目现有 50 张图标拼成，作为本轮风格直接参考上传至画布；仅说明「本项目提供参考」，不据此宣称任何版权归属。
- v1 曾另用 3 张单图参考节点（i-0CPyInB2gd / i-khWg1Xg0rn / i-SVGtYpQDqc）与画布旧表 i-TLBnkxLL0o，v2 未再挂用。

## v2 提示词全文

```
参考 {{Node "skill_ref_existing_50_sheet"}} 中 50 个技能图标的统一风格：回合制战棋游戏技能图标，深色暗背景底（近黑色），中央高亮发光的魔法效果主体，边缘柔和泛光，精致插画风，图标四周留有少量深色边距。生成一行 3 个技能图标（1 行 3 列，从左到右均匀排列，图标之间留出明显均匀间隔，每个图标为独立完整的方形构图，主体完整不超出各自格子）：第 1 个图标「力量觉醒」——发光的金红色能量拳头向上爆发，象征力量提升；第 2 个图标「铁壁」——发光的蓝金色魔法盾牌，盾面有符文光泽，象征防御提升；第 3 个图标「疾风」——青绿色旋转风纹与闪电尾迹，象征速度提升。三个图标与参考图标风格、质感、明暗完全一致，每个图标居中、大小一致、互不重叠。不要边框、不要网格线、不要文字标注、不要底座装饰。
```

## v2 切片方法与 QA（完整裁切，不截断）

1. 亮度阈值 28（低于该值为格间黑带 p50≈15，图标深底纹理 p25≈30）求每格内容 bbox，均不触碰三分格边界（无串格）：
   - power_surge: bbox x[86,1034] y[111,1249]（949x1139）
   - guard: bbox x[45,998] y[111,1248]（954x1138）
   - haste: bbox x[8,959] y[110,1247]（952x1138）
2. bbox 外扩 10px 裁出完整区域（含发光衰减边缘），完整保留主体不截断：
   - power_surge: region (76,101,1045,1260) 969x1159
   - guard: region (1080,101,2054,1259) 974x1158
   - haste: region (2091,100,3061,1258) 970x1158
3. 等比适配 padding：以区域边缘 6px 环带中位色（≈RGB(14,14,14)，与图标深底无缝）填充方形画布（1275x1275 / 1274x1274），内容居中贴入 → LANCZOS 缩放 64x64 → RGBA。
4. asset_report.py --expect-size 64x64：exit 0，ok=true，3/3 通过。
5. `_qa_compare.png` 视觉检查：主体与发光边缘完整（对比 v1 上下各截 ~50px），黑底高亮风格与现有 50 图标一致。

## v1 历史记录（已被 v2 覆盖）

- v1 节点 `skill_icons_power_guard_haste`（task 20261118191103297242737，Seedream 5.5 / 21:9 / 2K，3 单图参考+旧表），切片按格宽 1045 方形窗口垂直居中裁切，主体上下各截约 50px（bbox 高 1098 > 窗口 1045），故重制 v2。v1 原图 URL 仍在 v1 节点与 SOURCE 历史中可回溯。

## 权利与限制

- AI 生成素材（Seedream 5.5 via LibTV），开发期生成、随游戏发布——Steam 内容调查需按 AI 生成内容申报。
- 参考图（合并图与画布节点）均由本项目提供用于风格参考；本记录不宣称版权归属，如需商用授权信息请另行确认生成服务条款。
- 生成日期：2026-11-18；操作：team_mwm0ki6f1iica / icon-art（agent-2）。
