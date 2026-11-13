# Skill: 参考图生成职业三视图（gpt-image-2.6 via hyhawang）

> 用途：把现有角色小图（如 48×48 职业头像）作为参考，生成「正面/侧面/背面」三视图透明网格素材。本文件沉淀自 2026-11-13 的 classes_turnaround 实战。

## 工具链

- 生成脚本：`python C:/Users/Administrator/.dsh/skills/http-imagegen/scripts/imagegen_http.py`（子命令 `generate` / `edit`）
- 凭据在 Windows 用户级环境变量（DSH 进程不继承，需 powershell 注入）：
  ```bash
  export IMAGEGEN_OPENAI_API_KEY="$(powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('IMAGEGEN_OPENAI_API_KEY','User')")" \
         IMAGEGEN_OPENAI_BASE_URL="$(powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('IMAGEGEN_OPENAI_BASE_URL','User')")" \
         http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
  ```
- 端点 `https://api.hyhawang.com/v1` 只有 gpt-image 系列；**用 `gpt-image-2.6`**（实测优于 2.5-flare）。无 Gemini/nano-banana。
- 本机代理 `127.0.0.1:7890` 必须开着；`WinError 10061` / curl 000 = 代理没开，先让用户启动代理再重试。
- 返回可能是 WebP 容器（RIFF 头），保存后用 PIL 确认并转 PNG。

## 流程

### 1. 拼参考图（绿底、紧凑、无风格干扰）

```python
from PIL import Image
cell = 256
sheet = Image.new('RGB', (cell*2, cell*2), (0,180,0))  # 绿底
for i, f in enumerate(files):                            # 每次 4 个角色，2x2
    im = Image.open(f).convert('RGBA').crop(im.getbbox())  # 裁透明边
    scale = 200 / max(im.width, im.height)                 # 放大到 ~200px
    im = im.resize((int(im.width*scale), int(im.height*scale)), Image.NEAREST)
    sheet.paste(im, ((i%2)*cell + (cell-im.width)//2, (i//2)*cell + (cell-im.height)//2), im)
```

要点：
- **纯绿底 RGB(0,180,0)**，不要透明底——透明底会让模型「重新诠释」角色。
- **裁掉透明边 + 角色放大**，格内只留少量边距，间隙太大会稀释参考信号。
- **画布别太小**：≥ 512×512（推荐 1024 边长系列）。480×240 会因细节丢失导致整图崩坏（v3 教训）。

### 2. 生成三视图（edit，带参考图）

```bash
python .../imagegen_http.py edit --image <绿底参考图> --out <输出> \
  --model gpt-image-2.6 --size 1024x1024 --prompt "<见下>"
```

提示词模板（**不要加任何风格描述词**，让参考图自己说话）：

```
#1 contains N characters arranged in 2 rows by 2 columns: <名字和格子位置，逐个列出>.
Redraw this exact sheet as a character turnaround sheet: N rows by 3 columns strict grid,
one character per row, its three views in columns left-to-right: FRONT view, SIDE view
facing right, BACK view. Keep every character's pixel-art colors, outfit, weapon, face
and proportions EXACTLY identical to #1, same pixel-art style, do not redesign or
reinterpret them, do not add any style changes. Background fully transparent, each view
centered in its cell with wide gaps, no ground shadow, no text, no labels.
```

要点：
- **一次最多 4 个角色**。8 角色一张会细节减半且容易出偏差；4 角色/张质量最好。
- 提示词只写「保持一致 + 布局」，加 SNES 风格词反而会把角色带偏（实测）。
- 复杂角色（坐骑类，如 lancer）背面视角可能残缺，属已知限制，可单格重生成修补。

### 3. 检查与切片

- 先 `read_image` 目检：网格是否 N×3、三视角方向、配色/武器还原度、透明底是否干净。
- 确认 PNG：`python -c "from PIL import Image; p='<路径>'; img=Image.open(p); print(img.format); ..."`
- 切片：`python tools/slice_ui_sheet.py <网格图> -o <输出目录> --grid 4x3`（自动跳全透明格）。

## 实战产物（本仓库）

- 参考图：`assets/ui/gen/class_ref_green_A.png`（archer/assassin/berserker/knight）、`class_ref_green_B.png`（lancer/mage/priest/swordsman）
- 三视图：`assets/ui/gen/turnaround_A.png`、`turnaround_B.png`（各 1254×1254 透明底，4×3 网格）
- 历史版本：`classes_turnaround{,_v2,_v3,_v4}.png`（v3 为失败样本可作反例）

## 扩展：动作姿态表（attack/hurt/run/downed/potion）

参考图改传**三视图成品网格**（如 `turnaround_A.png`，多行、每行一人三视角），提示词结构：

```
#1 is a character turnaround sheet with N rows, one character per row (top to bottom: <名字>),
each row showing FRONT, SIDE and BACK views. Using these exact character designs, generate an
action pose sheet: N rows by 5 columns strict grid, one character per row (same order as #1),
the action poses in columns left-to-right: 1 ATTACKING (swinging weapon mid-strike),
2 HURT (flinching, leaning back in pain), 3 RUNNING (side-view running pose),
4 DOWNED (lying on the ground defeated), 5 DRINKING POTION (holding a small flask to the mouth).
Draw each pose in the FRONT view except running which is SIDE view facing right.
Keep every character's pixel-art colors, outfit, weapon, face and proportions EXACTLY
identical to #1, same pixel-art style, do not redesign or reinterpret them...（同上收尾）
```

- 坐骑角色（lancer）单独加注：`lancer shows the horse galloping` / `rider fallen beside the horse`。
- 实测一次 4 角色 × 5 动作 = 20 格出图质量良好（产物 `assets/ui/gen/actions_A.png`、`actions_B.png`）。

## 扩展：阶级升级表（1-4 阶进阶）

参考图同传三视图成品网格，提示词核心句式（实测出图质量高）：

```
generate a 4-tier class upgrade progression sheet: N rows by 4 columns strict grid, ...
TIER 1 = exactly the base design from #1, unchanged;
TIER 2 = slightly upgraded gear (finer details, small metal accents, one added piece);
TIER 3 = clearly veteran look (ornate armor with gold trim, cape upgrade, enriched weapon);
TIER 4 = master/epic look (radiant accents, glowing emblem, luxurious cape, legendary weapon).
The character must stay recognizable as the SAME person across all 4 tiers: same hair,
same face, same colors with progressive additions only. Draw all tiers in FRONT view.
```

- 递进阶梯「不变→小改→华丽→史诗」是关键，模型对这种梯度遵循度很好。
- 坐骑角色加注马铠递进：`lancer gets caparisoned horse armor` / `full royal barding`。
- 产物：`assets/ui/gen/tiers_A.png`、`tiers_B.png`。

## 扩展：UI 面板（背包/状态/属性/介绍）

用 `generate`（无参考图）+ 风格描述词一次一张，提示词骨架：

```
A game UI <xxx> panel window, classic SNES JRPG menu style pixel art: ornate royal-blue
panel frame with gold trim, dark blue inner background, <布局描述：格子/血条/空行/图标框>,
all text areas left empty, NO numbers or text. Flat colors, hard-edged pixels,
no anti-aliasing, no gradients, no text anywhere. Fully transparent background outside
the panel, panel centered with wide margins, no ground shadow.
```

- 实测产物：首批 4 张（背包/状态/属性/介绍）用户不满意已删除；模板与坑保留备用。
- **必须用 1024x1024 方幅**：1536x1024 宽幅实测必带不透明渐变背景（多次复现）。
- 方幅偶发不透明底时，用「从边缘泛洪抠底」：HSV 分类（蓝 hue 0.45–0.80 保护、亮金 ss>0.5&vv>0.75 保护、其余暗棕/黑清除），**蓝的 vv 阈值要按当图采样自适应**（每次生成的藏蓝深浅不同，固定阈值会整图误判）；清除前必须做矩形合理性检查（right-left>0.5w），不满足就中止，否则会把图裁废。
- 面板文字/数字一律后期代码叠加，图里只留空槽。

## 已知坑速查

| 症状 | 原因 | 对策 |
| --- | --- | --- |
| WinError 10061 连接被拒 | 本机代理 7890 没开 | 让用户开代理 |
| 整图崩坏/画风全变 | 参考图太小(<512)或带透明底 | 画布 ≥512、纯色底 |
| 角色被重新设计 | 参考图间隙太大 / 提示词带风格词 | 紧凑裁边；删风格词 |
| 细节糊、还原度低 | 一张图塞 8 角色 | 每张 ≤4 角色 |
| 输出是 WebP | 端点返回 RIFF 容器 | PIL 转 PNG |
