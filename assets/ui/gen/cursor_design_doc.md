# 中世纪战旗风格鼠标指针设计文档

> 参考图：`C:\Users\Administrator\Downloads\t+7EPy.png` (LPS Cursor & Pointer Pack)
> 风格规范：`story/13_art_style.md` — 日漫二次元赛璐璐 + 中世纪暗色史诗

---

## 1. 设计目标

为 Godot 4.7 战旗游戏设计一套**中世纪暗色史诗风格**的鼠标指针，满足：
- **风格统一**：日漫二次元赛璐璐（清晰线稿 + 平涂色块 + 硬边二级阴影）
- **色调**：暗色基调（铁灰 #2B2B3A / 夜墨 #1A1A24）+ 暗金点缀（#C9A227）
- **功能**：覆盖战旗游戏全部交互状态
- **技术**：透明背景 PNG，可拆分使用

---

## 2. 核心色板（对齐 `13_art_style.md` §2.1）

| 角色 | 色名 | HEX | 用途 |
|------|------|-----|------|
| 主色 | 铁灰 Iron Gray | `#2B2B3A` | 指针主体填充 |
| 主色 | 夜墨 Night Ink | `#1A1A24` | 线稿、最深阴影 |
| 强调 | 暗金 Dark Gold | `#C9A227` | 描边、高光、选中状态 |
| 强调 | 血红 Blood Red | `#8B1A1A` | 攻击/危险状态 |
| 功能 | 源脉蓝 Ley Blue | `#4A90E2` | 移动/魔法状态 |
| 功能 | 治愈绿 Heal Green | `#2ECC71` | 治疗/确认状态 |

---

## 3. 指针状态清单（10 个）

对齐 `13_art_style.md` §7.7 光标规范 + LPS 参考图布局：

### 3.1 基础导航（3 个）

| # | 状态 | 文件名 | 视觉描述 | 触发场景 |
|---|------|--------|----------|----------|
| 1 | **默认** | `cursor-normal.png` | 铁灰箭头 + 暗金描边，赛璐璐三阶色 | 主菜单/UI 通用 |
| 2 | **悬停** | `cursor-hover.png` | 金色箭头 + 微光高亮，亮度 +15% | 可交互元素悬停 |
| 3 | **按下** | `cursor-pressed.png` | 深铁灰箭头，内陷感，1px 下移 | 点击瞬间 |

### 3.2 战场操作（4 个）

| # | 状态 | 文件名 | 视觉描述 | 触发场景 |
|---|------|--------|----------|----------|
| 4 | **移动** | `cursor-move.png` | 蓝色菱形（源脉蓝 #4A90E2），与移动范围色一致 | 战场移动范围 |
| 5 | **攻击** | `cursor-attack.png` | 红色十字准星（血红 #8B1A1A）+ 旋转脉动 | 攻击目标选择 |
| 6 | **治疗** | `cursor-heal.png` | 绿色十字（治愈绿 #2ECC71）+ 柔光 | 治疗目标选择 |
| 7 | **技能/AOE** | `cursor-area.png` | 紫色菱形框（源晶紫 #7B4FC8） | AOE 技能范围 |

### 3.3 交互反馈（3 个）

| # | 状态 | 文件名 | 视觉描述 | 触发场景 |
|---|------|--------|----------|----------|
| 8 | **确认** | `cursor-confirm.png` | 金色对勾（暗金 #C9A227） | 关键操作确认 |
| 9 | **取消** | `cursor-cancel.png` | 暗红叉（血红 #8B1A1A） | 取消/关闭 |
| 10 | **不可用** | `cursor-unavailable.png` | 灰色禁止符（灰 #7A7A7A） | 不可点击目标 |

---

## 4. 视觉规范

### 4.1 渲染语言（赛璐璐三阶色）

```
基底 Base：铁灰 #2B2B3A（材质本色）
  ↓
影 Shadow：夜墨 #1A1A24（压暗 25-40%，冷偏蓝紫）
  ↓
高光 Highlight：暗金 #C9A227（提亮 20-35%，冷白偏移）
```

- **线稿**：1.5-2.5px 清晰线稿，色线用 `#1A1A24`（非纯黑）
- **阴影**：硬边二级阴影，边界锐利色块分界
- **高光**：形状化亮阶（金属棱边「一字高光」）

### 4.2 造型规范

| 项 | 规范 |
|----|------|
| 尺寸 | 48×48 px（游戏内显示），1024×1024 px（源文件） |
| 格式 | PNG 透明背景 |
| 朝向 | 箭头指向左上方（经典鼠标指针方向） |
| 锚点 | 箭头尖端为热点（hotspot） |
| 描边 | 外轮廓 2px 暗金描边，内部结构 1.5px 夜墨线 |

### 4.3 状态区分原则

- **颜色通道**：蓝=移动、红=攻击、绿=治疗、金=确认、紫=技能
- **形状通道**：箭头=导航、十字=目标选择、菱形=范围、对勾/叉=确认/取消
- **动效通道**：悬停=亮度+15%、按下=1px 下移、攻击=旋转脉动

---

## 5. 生图提示词模板

### 5.1 全局风格前缀（必须）

```
Japanese anime style, 2D cel shading, clean crisp lineart (colored line trace, no pure black),
flat base colors with hard-edged 2-tone shadows, dark fantasy medieval tone, desaturated grim palette.
NEGATIVE: photorealistic, oil painting, 3D render, pixel art, chibi, oversaturated neon.
```

### 5.2 单指针模板（以默认箭头为例）

```
[全局风格前缀]

SUBJECT: 中世纪战旗游戏鼠标指针，默认状态箭头
SHAPE: 经典斜向箭头，指向左上方，箭头尖端为热点
COLOR: 铁灰 #2B2B3A 主体填充，暗金 #C9A227 描边，夜墨 #1A1A24 线稿
SHADING: 赛璐璐三阶色（基底/影/高光），硬边阴影，西北 45° 光源
DETAILS: 金属质感，边缘一字高光，锤击纹理符号化
SIZE: 占画面约 50%，居中构图
BACKGROUND: 透明背景，不要底色、不要阴影、不要网格线、不要文字
```

### 5.3 素材表模板（2x4 布局，8 个状态）

```
[全局风格前缀]

生成一张 2 列 4 行（共 8 个）的鼠标指针素材表：
第 1 行：默认箭头（铁灰+暗金）+ 悬停箭头（金色高亮）
第 2 行：按下箭头（深铁灰内陷）+ 移动菱形（源脉蓝）
第 3 行：攻击十字（血红旋转）+ 治疗十字（治愈绿柔光）
第 4 行：确认对勾（暗金）+ 取消叉（血红）

每个指针独立完整，间距均匀，不要网格线、不要文字、不要底色。
```

---

## 6. 技术实现（Godot 4.7）

### 6.1 导入设置

```gdscript
# 项目设置 → 显示 → 鼠标光标
# 或代码动态设置

# 加载光标
var cursor_normal = load("res://assets/ui/cursors/cursor-normal.png")
var cursor_attack = load("res://assets/ui/cursors/cursor-attack.png")

# 设置默认光标
Input.set_custom_mouse_cursor(cursor_normal, Input.CURSOR_ARROW, Vector2(0, 0))

# 战场状态切换
func set_cursor_state(state: String):
    match state:
        "move": Input.set_custom_mouse_cursor(cursor_move, Input.CURSOR_ARROW, Vector2(16, 16))
        "attack": Input.set_custom_mouse_cursor(cursor_attack, Input.CURSOR_ARROW, Vector2(16, 16))
        "heal": Input.set_custom_mouse_cursor(cursor_heal, Input.CURSOR_ARROW, Vector2(16, 16))
        _: Input.set_custom_mouse_cursor(cursor_normal, Input.CURSOR_ARROW, Vector2(0, 0))
```

### 6.2 文件路径

```
res://assets/ui/cursors/
├── cursor-normal.png      # 默认箭头
├── cursor-hover.png       # 悬停
├── cursor-pressed.png     # 按下
├── cursor-move.png        # 移动
├── cursor-attack.png      # 攻击
├── cursor-heal.png        # 治疗
├── cursor-area.png        # 技能范围
├── cursor-confirm.png     # 确认
├── cursor-cancel.png      # 取消
└── cursor-unavailable.png # 不可用
```

---

## 7. 验收清单

对齐 `13_art_style.md` §12.2：

| 检查项 | 标准 |
|--------|------|
| ☐ 主题一致 | 暗色中世纪史诗，无萌系/过饱和 |
| ☐ 风格统一 | 日漫赛璐璐，无线稿缺失/写实厚涂 |
| ☐ 色阶规范 | 三阶色，阴影冷偏，线色非纯黑 |
| ☐ 尺寸规范 | 48×48 显示尺寸，1024×1024 源文件 |
| ☐ 功能色板 | 移动蓝/攻击红/治疗绿/确认金 |
| ☐ 剪影辨识 | 0.1 秒认出指针状态 |
| ☐ 透明背景 | PNG alpha 通道完整 |
| ☐ 无禁用元素 | 无像素风、无 3D 渲染、无照片写实 |

---

## 8. 参考图对照

### LPS Cursor & Pointer Pack（用户参考图）

| LPS 指针 | 本项目适配 | 改动 |
|----------|-----------|------|
| Cursor Arrow | cursor-normal.png | 铁灰+暗金，赛璐璐三阶色 |
| Cursor Arrow Blue | cursor-move.png | 源脉蓝，菱形替代箭头 |
| Cursor Arrow Gold | cursor-hover.png | 暗金高亮，亮度+15% |
| Cursor Banned | cursor-unavailable.png | 灰色禁止符 |
| Cursor Crosshair | cursor-attack.png | 血红十字，旋转脉动 |
| Cursor Crosshair R | （合并到 attack） | — |
| Cursor Grab | cursor-pressed.png | 内陷感，深铁灰 |
| Cursor Hand | cursor-confirm.png | 金色对勾替代手掌 |
| Cursor Help | （暂不需要） | — |
| Cursor Ibeam | （暂不需要） | — |
| Cursor Link | （暂不需要） | — |
| Cursor Magic | cursor-area.png | 源晶紫菱形框 |
| Cursor Move | cursor-move.png | 蓝色菱形 |
| Cursor Paint | （暂不需要） | — |
| Cursor Resize H/V/HV | （暂不需要） | — |
| Cursor Sword | （可扩展） | 攻击状态可用剑形替代十字 |
| Cursor Talk | （暂不需要） | — |
| Cursor Target | cursor-attack.png | 目标选择 |

---

*本文档为鼠标指针美术规范，所有产出必须对照 `story/13_art_style.md` 验收。*
