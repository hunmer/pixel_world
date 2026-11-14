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
