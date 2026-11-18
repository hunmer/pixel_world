# status_icons 状态图标素材来源记录（2026-11-18）

## 产物

| 文件 | 说明 | 语义 |
| --- | --- | --- |
| assets/ui/status/power_up.png | 切片 64x64 RGBA，橙金菱形+白色上箭头与握拳 | 力量增强 |
| assets/ui/status/defense_up.png | 切片 64x64 RGBA，蓝色菱形+白色盾牌 | 防御增强 |
| assets/ui/status/speed_up.png | 切片 64x64 RGBA，青绿菱形+白色双箭头风纹 | 速度增强 |
| assets/ui/status/defense_down.png | 切片 64x64 RGBA，灰色菱形+白色碎裂盾牌 | 防御削弱 |
| assets/ui/status/buff.png | 切片 64x64 RGBA，绿色菱形+白色上箭头四角星 | 通用增益（其他属性/旧存档） |
| assets/ui/status/debuff.png | 切片 64x64 RGBA，紫色菱形+白色向下箭头 | 通用减益（其他属性/旧存档） |

图标无文字；回合数角标由运行时绘制。6 图均通过 `asset_report.py --expect-size 64x64 --require-alpha`（exit 0）。

## 流程产物（meowa_tiles/generated/status_icons/）

| 文件 | 说明 |
| --- | --- |
| status_flags_ref_8.png | 单张合并参考图 680x340（8 张原素材 4x2 网格原尺寸居中贴入，透明底） |
| status_icons_2x3_raw.png | LibTV 生成原始网格 2496x1664 RGBA（真透明，77% 透明像素） |
| _slice_coords.json | 每格 bbox/region 裁切坐标记录 |
| status_icons_preview.png | 6 图棋盘格预览图 648x480（build_preview_sheet.py 生成） |
| slice_status_icons.py | 切片脚本（可复跑） |
| gen_2x3.sh | libtv 生成命令脚本（可复跑） |
| SOURCE.md | 本记录 |

## 生成参数

- 画布：LibTV「meowa_tiles_生成测试」uuid `8f05da05e6c942508e62ce7b4fd35806`（.libtv/project.json 绑定）
- 节点：`status_icons_2x3`（key `i-MjP1wcR6y0`，taskId `20261118201803899012737`，status=2 / progress=100，一次生成通过）
- 模型：Seedream 5.5（doubao-seedream-5-5），modeType=image2image，ratio=3:2，quality=2K，background=transparent → 2496x1664 原生真透明
- 原图 URL：`https://libtv-res.liblib.art/sd-gen-save-img/genius_playground/image/0da50723360b4f9cbaaa5fd54e8eb04b/1028813504_ed115fd4845c4744a2c755ddec8693dd.png`（随节点留档可回溯）

## 直接参考节点

| 节点名 | 节点 id | 内容 |
| --- | --- | --- |
| status_ref_8_flags | i-EJcFOkRKBZ | 本地 `meowa_tiles/generated/status_icons/status_flags_ref_8.png` 上传件（assets/ui/tmp/ui/状态标志 8 张 PNG 的 4x2 合并图，本项目提供参考） |

- 参考图仅说明「本项目提供参考」，不据此宣称任何版权归属；原 tmp/ui 8 张素材未做任何修改。
- 本轮未复用旧技能图标，6 图全部为新一次生成。

## 提示词全文

```
参考 {{Node "status_ref_8_flags"}} 中 8 个状态图标的统一风格：回合制战棋游戏状态图标，菱形徽章底（旋转45度的正方形），徽章带深色描边、表面为同色系渐变立体感，中央为白色粗剪影符号，符号简洁醒目、高对比，透明背景。生成一张 2 行 3 列（2 行 3 列，共 6 个图标）的状态图标素材表，每个图标为独立完整的菱形徽章，大小一致、间距均匀、互不重叠：第 1 行第 1 个——力量提升：橙金色菱形+白色粗壮向上箭头与握拳剪影，象征力量增强；第 1 行第 2 个——防御提升：蓝色菱形+白色盾牌剪影，象征防御增强；第 1 行第 3 个——速度提升：青绿色菱形+白色双重向右箭头与风纹剪影，象征速度增强；第 2 行第 1 个——防御削弱：灰色菱形+白色碎裂盾牌剪影（盾面带裂纹），象征防御削弱；第 2 行第 2 个——通用增益：绿色菱形+白色向上箭头与四角小星星剪影，象征任意属性获得增益；第 2 行第 3 个——通用减益：紫色菱形+白色向下箭头剪影，象征任意属性受到减益。6 个图标的徽章造型、描边粗细、白色剪影质感与参考图中 8 个图标的风格完全一致。不要边框、不要网格线、不要文字标注、不要底座、不要投影、不要任何底色。
```

## 切片方法与 QA

1. 网格 3 列 x 2 行等分（每格 832x832）；每格用 alpha>32 求主体 bbox，串格检查通过（内容不触格边界，间隙 ≥4px）。
   - 注：第 6 格（debuff）边界曾有孤立 alpha=9 杂散噪点各 1 像素，主体 bbox 阈值取 32 排除；其余 5 格边界干净。
2. bbox 外扩 12px 裁出完整区域（保留描边渐变衰减），region 约 583~595 x 571~579。
3. 贴到方形透明画布（边长=长边）居中 → LANCZOS 缩放 64x64 RGBA，全图无色底填充、无假透明。
4. `asset_report.py --expect-size 64x64 --require-alpha`：6/6 ok=true，exit 0。
5. `build_preview_sheet.py` 棋盘格预览（3 列 x 192px 格）+ read_image 视觉复核：主体完整居中、符号清晰可读、风格与 8 张参考一致。

## 权利与限制

- AI 生成素材（Seedream 5.5 via LibTV），开发期生成、随游戏发布——Steam 内容调查需按 AI 生成内容申报。
- 参考图（合并图与画布节点）均由本项目提供用于风格参考；本记录不宣称版权归属，商用授权信息请另行确认生成服务条款。
- 生成日期：2026-11-18；操作：team_mwm32kex2308zr / status-art（agent-3）。
