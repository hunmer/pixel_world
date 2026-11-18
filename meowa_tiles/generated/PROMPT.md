# meowa_tiles 地形 tile 生成配方（libtv CLI）

> 来源：2026-11-14 terrain_6x6 透明素材表生成测试。
> 画布：LibTV「meowa_tiles_生成测试」（uuid `8f05da05e6c942508e62ce7b4fd35806`）
> 参考图节点：`meowa_grass_tile`（i-5trg8tBA8O）、`meowa_snow_tile`（i-oFKVL0sEuI）

## 环境准备

```bash
export PATH="$HOME/.libtv:$PATH"   # libtv.exe 装在 ~/.libtv，不在 PATH
cd /e/pixel_world                  # 已绑定画布（.libtv/project.json）
# 重新绑定：libtv project use 8f05da05e6c942508e62ce7b4fd35806
```

## 推荐模型：Seedream 5.5（原生真透明）

```bash
libtv node --x 1500 --y 100 create "<节点名>" -t image \
  --left "meowa_grass_tile" --left "meowa_snow_tile" \
  -s "model=Seedream 5.5" \
  -s modeType=image2image \
  -s ratio=1:1 \
  -s quality=2K \
  -s background=transparent \
  --prompt "<下面提示词模板>" \
  --run
```

- `background=transparent` 是关键参数：直接输出真透明 PNG，无需抠图。
- `quality` 只支持 `1.5K` / `2K`；`ratio` 支持 1:1/9:16/16:9/3:4/4:3/3:2/2:3/21:9。
- 参考图入边必须配合 `modeType=image2image`，否则校验失败（text2image 不允许图片入边）。

## 提示词模板（实测有效）

```
参考 {{Node "meowa_grass_tile"}} 与 {{Node "meowa_snow_tile"}} 的风格：等距（isometric）2.5D 像素风格地形方块 tile，立方柱体造型，顶面+两个可见侧面，描边清晰，像素颗粒感。生成一张 6x6 网格（6 行 6 列，共 36 个 tile）的素材表：每个格子一个不同的地形 tile 变体（草地、土壤、沙地、雪地、岩石、苔藓石、湿润土、枯土、草石混合等及其变体），格子之间留出均匀间距。透明背景，不要任何底色、不要网格线、不要文字标注。色调明快干净，与参考图完全一致的像素风格。
```

要点：
- `{{Node "节点名"}}` 占位符引用已连线的参考图（成对引号包节点名）。
- 「6x6 网格（6 行 6 列，共 36 个 tile）」+ 变体清单控制内容。
- 「不要任何底色、不要网格线、不要文字标注」防杂物。

## 备选：Lib Image 2.6 Fast（假透明，需后处理）

```bash
libtv node create "<节点名>" -t image \
  --left "meowa_grass_tile" --left "meowa_snow_tile" \
  -s "model=Lib Image 2.6 Fast" \
  -s modeType=image2image -s ratio=1:1 -s resolution=1K \
  -s output_format=png -s quality=high \
  --prompt "<同上模板>" --run
```

- 不支持真透明：会把棋盘格底纹画进像素（全图 alpha=255），需跑
  `remove_fake_transparency.py`（同目录）抠图后处理。
- 参数集：`resolution=1K|2K|4K`、`ratio` 含 auto 与更多比例、`output_format=png|jpeg|webp|svg`。

## 常用后续命令

```bash
# 查节点结果 URL
libtv node "<节点名>" | python -c "import sys,json; print(json.load(sys.stdin)['data']['url'][0])"

# 重新触发生成（换 seed 出新变体）
libtv node "<节点名>" --run

# 改提示词后重跑：libtv node "<节点名>" --prompt "<新提示词>" --run
```

## 植物素材表（plants_new_species，2026-11-14 实测通过）

参考图节点：`meowa_plant_ref1`（i-GoTgl2FVi1，saguaro_cactus）、`meowa_plant_ref2`（i-AuIpa16O5l，wildflower_pink）。
Seedream 5.5 / image2image / 1:1 / 2K / transparent → 2048x2048 原生真透明。

```
参考 {{Node "meowa_plant_ref1"}} 与 {{Node "meowa_plant_ref2"}} 的风格：等距视角 2.5D 像素风格植物单体 sprite，透明背景，描边清晰，像素颗粒感，色彩明快干净。生成一张 6x6 网格（6 行 6 列，共 36 株植物）的素材表，每格一株不同的新植物种类，不与参考图重复：<植物清单 36 项>。每株独立完整，间距均匀，不要网格线、不要文字、不要底色。
```

实测清单（全部按顺序生成）：向日葵、郁金香、薰衣草丛、竹子、蕨类、灌木丛、藤蔓、荷叶荷花、浆果丛、南瓜藤、小麦、胡萝卜、蘑菇树、多肉盆栽、芦苇、蒲公英、雏菊、玫瑰、风车草、冰晶花、雪松苗、枯木桩蘑菇、发光荧光蘑菇、仙人掌花、捕蝇草、棉花、四叶草、蓝铃花、蕨类盆栽、松树苗、樱花枝、紫藤、千层菜、龙舌兰、剑麻、苔藓球。

## 动物 spritesheet（animals_new_species，2026-11-14 实测）

参考图节点：`meowa_animal_ref1`（i-39QtF7p8pl，fox/idle spritesheet）、`meowa_animal_ref2`（i-nZNKiw6S4E，frog/idle）。
Seedream 5.5 / image2image / 1:1 / 2K / transparent → ⚠️ 本次实际输出 2048x2048 **白底 webp**（transparent 参数未生效），需 `remove_fake_transparency.py` 抠白底；动物有深色描边，连通抠图不会误伤白兔/绵羊等白色身体。

```
参考 {{Node "meowa_animal_ref1"}}（狐狸 spritesheet，一行多帧横排）与 {{Node "meowa_animal_ref2"}} 的风格：可爱 Q 版等距像素风动物，透明背景，描边清晰，像素颗粒感，色彩明快。生成一张 6 行 2 列的动物 spritesheet 素材表，共 12 种不同的新动物，每种占一整行、行内横排 2 个同种动作姿态（如站立+走路），不与参考图重复：白兔、梅花鹿、橘猫、绵羊、母鸡与小鸡、刺猬、松鼠、蝴蝶群、蜜蜂、鸭子、山羊、猫头鹰。每种动物独立一行、大小比例协调、间距均匀，风格与参考图完全一致。不要网格线、不要文字、不要底色。
```

实测注意：模型把「每种一行、行内 2 姿态」渲染成了 2 列布局（左列 2 态 + 右列 2 态），12 种齐全、质量好；白底已抠（animals_new_species_transparent.png）。

## 装饰物素材表（decorations_new_species，2026-11-14 实测通过）

参考图节点：`meowa_decor_ref1`（i-BtpcX6YaMJ，mossy_boulder_large）、`meowa_decor_ref2`（i-9ooPcnEcF4，snowy_tree_stump_tall）。
Seedream 5.5 / image2image / 1:1 / 2K / transparent → 2048x2048 原生真透明。
技巧：prompt 里用「第 N 行主题」逐行分组（岩石/木头/雪地/沙漠/功能/奇幻），模型严格按行渲染。

```
参考 {{Node "meowa_decor_ref1"}}（苔藓巨石）与 {{Node "meowa_decor_ref2"}}（雪覆树桩）的风格：等距视角 2.5D 像素风格地形装饰物单体 sprite，透明背景，描边清晰，像素颗粒感，色彩明快干净，尺寸小巧可摆放在地形方块上。生成一张 6x6 网格（6 行 6 列，共 36 个装饰物）的素材表，每格一个不同的装饰物种类，不与参考图重复，按行分组主题：第 1 行岩石类（…6 项）；第 2 行木头类（…）；第 3 行雪地类（…）；第 4 行沙漠类（…）；第 5 行功能类（…）；第 6 行奇幻类（…）。每个装饰物独立完整，间距均匀，不要网格线、不要文字、不要底色。
```

## 单体建筑（house_1to1，2026-11-14 实测通过）

Seedream 5.5 / image2image（参考 meowa_grass_tile + meowa_snow_tile）/ 1:1 / 2K / transparent → 2048x2048 原生真透明。
思路：让屋子长在与参考 tile 同款的草地立方柱底座上，建筑与地形风格自然统一。

```
参考 {{Node "meowa_grass_tile"}} 与 {{Node "meowa_snow_tile"}} 的风格：等距（isometric）2.5D 像素风格小屋子 sprite，立方柱体地形块上的小木屋：草地等距底座（与参考 tile 完全同款的立方柱），屋体为木质墙板，坡形屋顶带瓦片纹理与烟囱，门、窗、小台阶齐全，细节丰富但整体小巧可爱，描边清晰，像素颗粒感，色彩明快干净。单个完整小屋居中构图，占画面约 70%。透明背景，不要底色、不要阴影投影地面、不要网格线、不要文字标注。与参考图完全一致的像素风格。
```

实测教训（用户反馈）：v1 带「草地 tile 底座」且纹理偏高清插画，不符合需求。**建筑类不要加底座/地板**；必须强调「低分辨率复古像素艺术、大颗粒像素块、可见 tile 网格拼接痕迹、绝不能平滑矢量或高清插画质感」，纹理才会带拼接感。v2（house_1to1_v2.png）通过。

## 高耸建筑（watchtower / citywall，2026-11-14 实测）

- 竖长构图用 `ratio=9:16`（实际输出 1584x2816）。
- 「高度约为宽度的 4 倍（细高竖长造型）」写进 prompt 可得到细高造型，实测建筑本体高宽比约 2.2~2.6:1（画幅内极限），如需更夸张可后处理裁切或改用更高画幅分两段生成拼接。
- 瞭望塔：石砌围墙基座带大门垛口 + 细高塔身箭窗 + 木质瞭望台 + 红瓦顶。
- 城墙：石墙垛口 + 拱形箭窗 + 突出敌台木檐瞭望棚 + 青苔风化点缀。
- 同样遵守：无底座、粗颗粒像素拼接、透明背景。

- 城墙 v2 教训（用户反馈）：「不要突出方形敌台，后面要做多图拼接」——且只说「直墙段」模型仍会输出四方均匀的方柱塔楼。v3 通过的写法：**「细长的矩形棱柱墙体：平面轮廓长方形（长 3 单位、宽 1 单位），长侧面朝画面左前方完整展示，右后方只露出窄短端面——绝不是四方均匀的塔楼或方柱」**，并指明顶面狭长走道 + 连续垛口 + 长侧面 3 个等距箭窗。产出 citywall_1to9_v3.png 可横向多段拼接。

## 可拼接山体段（mountain_tileable，2026-11-14）

- v1 教训：只说「可拼接山段」模型会画成顶部收尖的独立山峰，拼出 V 形空隙。必须写「上下等宽均匀矩形棱柱、左右边缘完全垂直的笔直竖线、顶部绝不收窄收尖、顶部轮廓是水平线」。
- 山体 v2 教训（用户反馈）：等宽棱柱平顶版「像城墙不像山」。v3 通过的写法：**「天然山体标准段（不是城墙/建筑/无人工砌筑痕迹）+ 段内中央高耸山峰、左右山肩渐低的 n 形轮廓 + 左右两个竖直边缘笔直贯穿（边缘处山体被垂直切平、纹理自然延续）+ 无砖砌缝/垛口/窗户 + 雪盖沿山峰轮廓起伏」**。拼接后峰-谷-峰节奏自然连绵。
- 等距视角的固有结果：顶面必然是菱形，拼接后形成连续锯齿山脊线——这正好是连绵山脊效果。
- 段间左右边缘的深色描边在拼接处会形成竖直分割线，视觉上像山体裂缝；要完全无缝可后处理替换边缘描边色。
- 城墙 v3 的「长侧面朝左前、右后露窄端面」写法对山体同样有效。

## 宽屏山脉横幅（mountain_range_wide，2026-11-14 实测通过）

`ratio=21:9`（实际输出 3136x1344）、quality=2K、transparent → 单幅完整连绵山脉：中央偏左最高主峰 + 两侧 2 座略矮边缘峰（边缘垂直切平可继续扩展）+ 中间 3~4 座错落次峰，雪线沿峰形起伏、山谷云雾带、山脚草地与岩壁层理，粗像素拼接风格与 tile 一致。适合做世界地图装饰或远景层。提示词在 v3 山体模板基础上把「标准段」改为「完整连绵山脉横幅 + 指定峰位布局 + 左右边缘垂直切平」。

## 主城 Lobby 大场景（castle_lobby_4k，2026-11-14 实测通过）

- 模型切回 **Lib Image 2.6 Fast**：`ratio=21:9` + `resolution=4K` + `quality=max` → 实际 3808x1632（此组合是当前可用最大尺寸；Seedream 只有 2K 上限）。
- 全场景室内图不需要透明（输出 RGB 无 alpha 通道，属正常）。
- 场景模板：王座高台+红毯中轴、石柱列、纹章旗帜、彩窗体积光、火盆/吊灯暖光、二层回廊与楼梯、守卫雕像、角落木门与盆栽。粗像素拼接关键词照常附加。

## 城堡鸟瞰布局图（castle_birdview，2026-11-14 实测通过）

用户澄清（m00432）：「我指的是城堡的鸟瞰图，不必太精确，用于后续安排房屋放置」。配方：Seedream 2K 1:1、transparent、terrain 双参考。场景模板：**八角形石砌城墙全环绕（四角+边中点共 8 座方形角楼）+ 南城门吊桥跨护城河 + 城内石板街道网格划分街区 + 中央红顶王座大厅 + 多块平整草地空地（无建筑，供摆放房屋）+ 树木水井花坛点缀 + 背景连绵雪山呼应山脉素材**。实测输出 2048²、约 9% 透明（城外环境），核心城区完整不透明，可直接做主城底图。

## 山谷地形鸟瞰图（valley_birdview，2026-11-14 实测通过）

Seedream 2K 21:9、transparent、terrain 双参考。场景模板：**上下两列天然雪峰山脊夹中央谷地 + 大块平整绿色草甸（供摆放建筑）+ 蜿蜒河流对角穿谷（两岸沙滩浅滩）+ 成片松林/阔叶林/灌木/岩石 + 土路沿河蜿蜒**。实测 3136x1344，约 33% 透明（山体轮廓外），谷底完整。与 castle_birdview 同属「鸟瞰布局图」配方家族，只换场景模板。

## 八职业人形概念网格 + 身份锚（professions_8grid，2026-11-19 实测通过）

- Seedream 5.5 `image2image` 双参考：人形剪影参考 `assets/units/class-knight-idle.png`（384x48 战棋 sprite，锁人形站姿剪影）+ 风格参考 `meowa_tiles/heroes/fox/idle.png`（129x129，只借粗像素战棋风格，不借动物解剖）。
- 请求 `ratio=1:1` 实际输出 2816x1584（模型不保证 1:1；2816/4=704、1584/2=792 恰好整除 4x2 网格，cell 704x792 可整格切）。transparent、count=1、quality=2K。
- prompt 关键结构：2 行 4 列 8 职业严格顺序（行1 swordmaster/soldier/recruit_knight/paladin，行2 pegasus_knight/sniper/sage/bishop）+ 每角色独占一格互不重叠 + 骑士类含坐骑（马）、天马骑士含翼 + 低分辨率复古像素大颗粒深色描边 + 纯透明背景、无底座/网格线/文字。
- 画布节点：prof8_ref_knight=i-RRsxNBrq3k、prof8_ref_style=i-rv9TEWgin0、prof8_grid_v1=i-Af9ZRlTNil（libtv task 20261119035103397072737，一次通过未用修复额度）。
- 切片：`python3 tools/slice_profession_sheets.py --sheet meowa_tiles/generated/professions_8grid_v1.png --grid 2x4 --ids <行优先8名> --only <5非骑乘> --canvas 128 --pad 4 --out-dir meowa_tiles/heroes --manifest meowa_tiles/heroes/professions_static_manifest.json`。连通域质心归格 + 每格并集 bbox + 全局统一最近邻缩放（k=0.1899，五锚共用保相对体型）+ 底部中心锚定 + 4px 留白；manifest 记录 sha256/cell/bbox/scale/paste_xy 溯源。
- 身份映射：recruitKnight→recruit_knight、pegasusKnight→pegasus_knight 仅素材目录名，不改 story 侧 ID；骑乘三格（recruit_knight/paladin/pegasus_knight）只存在于网格，不切片派生。
- .import 注意：`meowa_tiles/generated/` 有 `.gdignore`，网格原稿不生成 `.png.import`（运行时不加载概念稿，属预期）；`meowa_tiles/heroes/` 下运行时锚点正常生成 `static.png.import` 且项目默认 `mipmaps/generate=false`。
- 教训：① 请求 1:1 不保证输出 1:1，切片前先验实际尺寸能否被行列整除；② 2K 输出边缘有抗锯齿碎屑噪点连通域，切片器 MIN_COMPONENT 阈值自动丢弃即可。

## 物品图标素材表（item_icons，2026-11-19 实测通过）

游戏物品 64x64 图标（入场目录 `assets/ui/items/`，物品 ID 见 `data/items.json`）。

直接参考节点（本轮上传的本项目 skills 实际 PNG，仅作风格参考）：`item_ref_blue_01`（i-AKbjQuvPNQ，skills/01.png）、`item_ref_green_09`（i-Wpv7IElvVU，09.png）、`item_ref_red_21`（i-ulnBon7t9N，21.png）、`item_ref_orange_25`（i-6UOeLXCJA7，25.png）。

Seedream 5.5 / image2image（4 参考入边）/ ratio=3:4 / quality=2K / background=transparent → 1776x2368 原生真透明 RGBA。

```bash
libtv node --x 4000 --y 200 create "item_icons_3x4_v2" -t image \
  --left "item_ref_blue_01" --left "item_ref_green_09" --left "item_ref_red_21" --left "item_ref_orange_25" \
  -s "model=Seedream 5.5" \
  -s modeType=image2image \
  -s ratio=3:4 \
  -s quality=2K \
  -s background=transparent \
  --prompt "<提示词模板，要点见下>" --run
```

提示词要点（完整 prompt 与参数快照已只读取回存本地 `item_icons/_v2_prompt.txt`，实际布局 **3 列 × 4 行**；画布节点 `item_icons_3x4_v2`，i-2TN5EzwOxg，读回命令 `~/.libtv/libtv node i-2TN5EzwOxg`；v1 节点 `item_icons_3x4_v1`，i-ShPLqXiyuc）：

- 布局与内容：「3 列 × 4 行共 12 格……每行恰好 3 个」+ 逐行清单（8 个游戏物品 + 4 张卷轴储备，卷轴不入游戏数据）。
- **关键约束（v1 教训）**：v1 只写「图标之间留出明显均匀的透明间隔」，模型在行 1–3 图标底下画了一整块不透明背板（全表连通成一片，无法切片）。v2 写明：「12 个圆角方形底框彼此完全独立，底框轮廓之外必须 100% 全透明，底框之间绝对不要任何背板、底板、桌面、木板、纸张、板条或任何相连的背景物——绝对不要把图标放在一块板子上」，实测 39.9% 全透明像素、连通域恰好 12 个。
- 风格锚：「深色圆角方形底框（近黑深色纹理底），框内中央高亮发光主体，边缘柔和泛光」与参考图标完全一致；「大颗粒像素点阵质感……绝不能是平滑矢量或高清插画质感」。
- 易混物品写明区分点：守护之戒=银戒身+盾形蓝宝石 vs 力量之戒=金戒身+剑形红宝石；生命药水=圆瓶+心形高光 vs 力量药水=锥形瓶+火焰高光。

切片与归一（入 64x64）：

1. `python3 tools/slice_ui_sheet.py meowa_tiles/generated/item_icons/item_icons_3x4_v2.png -o meowa_tiles/generated/item_icons/sliced_v2`（连通域自动模式；实测 4 行 × 3 列 = 12 张，与逐格语义核对无误——不盲信顺序，逐格看图确认后再映射 ID）。
2. 每张紧裁 alpha bbox → 最长边等比缩放到 64（NEAREST）→ 居中贴入 64x64 透明画布 → `assets/ui/items/01..08.png`；4 张卷轴储备切至 `meowa_tiles/generated/item_icons/reserves/`（不增游戏数据）。

| 文件 | 物品 ID / 名称（data/items.json） |
| --- | --- |
| assets/ui/items/01.png | hpPotion 生命药剂（红瓶心形高光） |
| assets/ui/items/02.png | mpPotion 法力药剂（蓝瓶星形高光） |
| assets/ui/items/03.png | antidote 解毒药（绿瓶草叶标记） |
| assets/ui/items/04.png | shuriken 手里剑（钢十字星） |
| assets/ui/items/05.png | bomb 炸弹（黑铁圆肚火花引信） |
| assets/ui/items/06.png | armorRing 守护之戒（银+蓝盾宝石） |
| assets/ui/items/07.png | powerRing 力量之戒（金+红剑纹宝石） |
| assets/ui/items/08.png | mightPotion 力量药水（橙锥形瓶） |
| item_icons/reserves/scroll_{fire,ice,heal,thunder}.png | 卷轴储备（不入 data/items.json） |

QA：`asset_report.py --expect-size 64x64 --require-alpha` exit 0（8/8 RGBA、alpha 0–255、圆角透明 125–197px、无 problems；留档 `_qa_asset_report.json`）；`_qa_compare.png` 与 `assets/ui/skills/01..08.png` 的 4x 放大 + 原尺寸并排对照，深底泛光风格一致、原尺寸可读；原始图 URL 留档 `_v1_url.txt` / `_v2_url.txt`。

## 装备图标素材表（equipment_icons，2026-11-19 实测通过）

游戏装备 64x64 图标（入场目录 `assets/ui/equipment/`，装备 ID 与 iconId 映射见 `data/equipment.json`，01–11 永不重排；UI 经 `scripts/core/equipment_icons.gd` 稳定 ID 目录取图）。风格目标：与 `assets/ui/skills/` 同族（物件+深蓝黑光晕+粗像素）但**光晕之外真透明、无方形卡框**（skills 原件实为 0% 透明烘焙底，勿照抄其 alpha 形态）。

直接参考节点（复用 item_icons 轮上传的 skills 实际 PNG，仅作风格参考）：`item_ref_blue_01`（i-AKbjQuvPNQ，01.png）、`item_ref_green_09`（i-Wpv7IElvVU，09.png）、`item_ref_red_21`（i-ulnBon7t9N，21.png）、`item_ref_orange_25`（i-6UOeLXCJA7，25.png）。

Seedream 5.5 / image2image（4 参考入边）/ ratio=3:4 / quality=2K / background=transparent → 1776x2368 原生真透明 RGBA，**一次通过**（task 20261119060503960122737；画布节点 `equip_icons_3x4_v1`，i-tMnfiWNTXd；完整 prompt 快照 `_v1_prompt.txt`，URL 留档 `_v1_url.txt`）。

提示词要点（完整原文见 `_v1_prompt.txt`）：

- 布局与内容：「3 列 × 4 行共 12 格……每行恰好 3 个」+ 逐行清单（11 件装备 + 1 张磨刀石储备，储备不入游戏数据）。
- 独立性约束沿用 item_icons v2 教训：**「图标及其光晕轮廓之外必须 100% 全透明，绝对不要任何背板/底板/桌面/板条/方形底框」**——本轮无背板粘连（52.7% 全透明，连通域 12+1 碎片）。
- 风格锚：「单个物件居中 + 物件周围一圈柔和深色光晕（与参考图标完全一致的深蓝黑泛光）+ 大颗粒像素点阵 + 清晰深色描边，绝不能平滑矢量或高清插画」。
- 易混装备写明区分点：铁剑=简朴宽刃棕柄 vs 钢剑=细长蓝光华丽护手；皮木圆盾=皮革蒙皮木框铆钉 vs 鸢形金属大盾=银铁框蓝色纹章漆面。
- 四槽语义：07 治愈法杖=staff、10 远征披风/11 幸运坠饰=relic（v2 四槽口径，图标只按 iconId 对号）。

切片与归一（入 64x64）：

1. `python3 tools/slice_ui_sheet.py meowa_tiles/generated/equipment_icons/equip_icons_3x4_v1.png -o meowa_tiles/generated/equipment_icons/sliced_v1`（连通域自动模式；实测报「5 行 13 张」——**行聚类与真实网格无关，别信行名**：1 张 27x27 噪点碎片（弃）+ 12 个图标按 prompt 行序完整对应，逐格看图确认后再映射 ID）。
2. 每张紧裁 alpha bbox → 最长边等比缩放到 64（NEAREST）→ 居中贴入 64x64 透明画布 → `assets/ui/equipment/01..11.png`；磨刀石储备切至 `equipment_icons/reserves/whetstone.png`；溯源清单 `_slice_manifest.json`（bbox/scale）。

| 文件 | 装备 ID / 名称（data/equipment.json） |
| --- | --- |
| assets/ui/equipment/01.png | ironSword 铁剑（简朴宽刃棕柄） |
| assets/ui/equipment/02.png | steelSword 钢剑（细长蓝光华丽护手） |
| assets/ui/equipment/03.png | ironLance 铁枪（长柄银头骑枪） |
| assets/ui/equipment/04.png | ironAxe 铁斧（短柄宽刃战斧） |
| assets/ui/equipment/05.png | ironBow 铁弓（木质弯弓绷弦） |
| assets/ui/equipment/06.png | fire 火焰（橙红火焰亮黄内芯） |
| assets/ui/equipment/07.png | heal 治疗杖（木杖绿光宝珠，staff） |
| assets/ui/equipment/08.png | leatherShield 皮盾（圆盾皮革铆钉） |
| assets/ui/equipment/09.png | kiteShield 鸢盾（鸢形银框蓝漆） |
| assets/ui/equipment/10.png | campaignCloak 远征披风（深蓝紫连帽金扣，relic） |
| assets/ui/equipment/11.png | luckyPendant 幸运坠饰（金链绿四叶草，relic） |
| equipment_icons/reserves/whetstone.png | 磨刀石储备（不入 data/equipment.json） |

QA：`asset_report.py --expect-size 64x64 --require-alpha` exit 0（11/11 RGBA、alpha 0–255、单图透明像素 1k+、problems 空；留档 `_qa_asset_report.json`）；`_qa_compare.png` 11 列 equipment vs skills 4x 对照（同族深底泛光、四类 weapon×6/staff×1/shield×2/relic×2 视觉对齐）；`_qa_contact_v1_indexed.png` 切片编号对照；`tests/equipment_icons_contract.gd` 资产就绪分支全过（11 路径禁兜底加载、campaign_ui 216 项 ALL PASS）。

## 实测产物

| 文件 | 说明 |
| --- | --- |
| terrain_6x6_seedream.png | Seedream 5.5，2048x2048，原生真透明（推荐） |
| terrain_6x6_test_transparent.png | 2.6 Fast，1024x1024，已抠透明 |
| terrain_6x6_test.png | 2.6 Fast 原始图（假透明，留档） |
| plants_new_species.png | 36 株新植物，2048x2048，原生真透明 |
| animals_new_species_transparent.png | 12 种新动物 spritesheet，2048x2048，已抠白底 |
| decorations_new_species.png | 36 个装饰物（6 主题行），2048x2048，原生真透明 |
| house_1to1.png | ❌ 已废弃：带草地底座、纹理偏插画（用户否决） |
| house_1to1_v2.png | ✅ 无底座粗像素拼接感小屋，2048x2048，真透明 |
| watchtower_1to9.png | 围墙瞭望塔，1584x2816，真透明，粗像素拼接 |
| citywall_1to9.png | ❌ 旧版含突出敌台（用户否决） |
| citywall_1to9_v2.png | ❌ 方柱塔楼造型，不可拼接（迭代淘汰） |
| citywall_1to9_v3.png | ✅ 细长矩形墙段（长侧+窄端面），可横向拼接，真透明 |
| mountain_tileable_v2.png | ❌ 平顶棱柱版，像城墙（用户否决） |
| mountain_tileable_v3.png | ✅ 天然山形轮廓可拼接山体（峰-谷节奏），1584x2816，真透明 |
| mountain_range_wide.png | ✅ 宽屏完整山脉横幅，3136x1344，真透明 |
| castle_lobby_4k.png | ✅ 中世纪城堡王座大厅 lobby 图，3808x1632，全场景不透明 |
| castle_birdview.png | ✅ 城堡全城鸟瞰布局图（城墙+街道+空地），2048²，可作房屋摆放底图 |
| valley_birdview.png | ✅ 山谷地形鸟瞰布局图（双山脊+河流+草甸），3136x1344，真透明 |
| item_icons/item_icons_3x4_v1.png | ❌ 行 1–3 底部连成不透明背板，无法切片（迭代淘汰） |
| item_icons/item_icons_3x4_v2.png | ✅ 12 格物品图标表（8 物品+4 卷轴），1776x2368，真透明，已切片入库 assets/ui/items/01..08.png |
| equipment_icons/equip_icons_3x4_v1.png | ✅ 12 格装备图标表（11 装备+1 储备），1776x2368，真透明，一次通过，已切片入库 assets/ui/equipment/01..11.png |
| professions_8grid_v1.png | ✅ 八职业人形 2x4 概念网格，2816x1584，真透明，粗像素（含三骑乘） |
| meowa_tiles/heroes/{swordmaster,soldier,sniper,sage,bishop}/static.png | ✅ 五个非骑乘身份锚，128x128，底部中心，NN 统一缩放 k=0.1899 |
