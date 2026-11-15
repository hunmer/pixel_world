# Pixel World · UI 设计规范（DESIGN.md）

> 固定 UI 审美风格的单一事实来源。实现位于 `ui/theme/component_theme.gd`（token 与
> StyleBox 工厂），组件位于 `ui/components/`，画廊 `scenes/UIComponentGallery.tscn`。
> 任何 AI / 人新增界面都必须遵守本文件；改动 token 前先改这里，再同步实现与契约。

## 1. 总则

- **唯一取值来源**：间距、圆角、字号、内容边距一律从 `ComponentTheme` 的 token 常量
  取值（`SPACE_*` / `CORNER_*` / `FONT_*` / `*_MARGIN_*`），禁止在组件或业务 UI 里
  写裸数字样式值。
- **色板唯一来源**：`scripts/ui/ui_theme.gd`（`UITheme`）的 `BG / PANEL_BORDER /
  TEXT_MAIN / TEXT_DIM / ACCENT / ERROR / BTN_BG(_HOVER/_PRESSED) / HELP_BG / BORDER`
  常量；组件层不新增硬编码颜色。
- **主题实例隔离**：`ComponentTheme.create()` 每次返回全新 `Theme`；控件默认在自身
  `theme == null` 时自建一份，互相不影响；整界面共享主题时把实例挂在根节点上。
- **Type Variation 复用**：所有样式经 Theme Type Variation 下发
  （`PixelButtonPrimary` 等，见 `ui/README.md` 变体表），控件脚本只挂变体名，
  不自带 StyleBox。

## 2. 设计 token（`ui/theme/component_theme.gd`）

### 间距（8/16/24 体系）

| token | 值 | 用途 |
| --- | --- | --- |
| `SPACE_XS` | 4 | 紧凑半步：图标与文字间隙、徽标内边距、token 微调步长 |
| `SPACE_SM` | 8 | 小间距：紧凑行内控件、token 微调（如 16+8=24） |
| `SPACE_MD` | 16 | 分组节奏：`PixelVBox`/`PixelHBox`/`PixelGrid` 默认 gap、页内 separation |
| `SPACE_LG` | 24 | 页面级外边距：`PixelMargin` 默认边距 / 大区块分隔 |

### 圆角

| token | 值 | 用途 |
| --- | --- | --- |
| `CORNER_TAB` | 4 | 页签 |
| `CORNER_CONTROL` | 6 | 输入框 / 下拉 / 弹层等输入类控件 |
| `CORNER_BUTTON` | 8 | 按钮（六态统一） |
| `CORNER_CARD` | 8 | 卡片（`PixelPanel` 面） |

### 字体层级（标题 28–36 / 正文 16–18 / 辅助 12–14）

| token | 值 | 用途 |
| --- | --- | --- |
| `FONT_CAPTION` | 12 | 说明 / 辅助文字（辅助区间 12–14 的下限） |
| `FONT_BODY` | 16 | 正文（默认字号；旧常量 `DEFAULT_FONT_SIZE` 是它的别名） |
| `FONT_TAB` | 16 | 页签文字（旧常量 `TAB_FONT_SIZE` 别名；与正文同档） |
| `FONT_TITLE` | 28 | 卡片标题 / 区块标题（标题区间 28–36 的下限） |
| `FONT_DISPLAY` | 36 | 展示级大标题（标题区间上限） |

> 中间档取值（如正文 18、标题 32）必须以 token 为基准显式换算并在组件注释里注明
> 来源，禁止无来源数字。

### 内容边距

| token | 值 | 用途 |
| --- | --- | --- |
| `BUTTON_MARGIN_X` | 20 | 按钮左右内边距 |
| `BUTTON_MARGIN_Y` | 12 | 按钮上下内边距 |
| `CARD_MARGIN` | 12 | 卡片内容边距 |
| `CONTROL_MARGIN` | 8 | 输入类控件内边距 |

## 3. 按钮状态规范

`ComponentTheme._define_button` 为三个语义变体（Primary / Secondary / Danger）各自
定义**完整六态**，全部走 `_button_stylebox(bg, border)` 同一工厂，几何完全一致：
四角圆角 `CORNER_BUTTON`(8)，内容边距左/右 `BUTTON_MARGIN_X`(20)、上/下
`BUTTON_MARGIN_Y`(12)。

| 状态 | 规则 |
| --- | --- |
| `normal` | 常态底色 + `PANEL_BORDER`/`BORDER` 细边 |
| `hover` | 提亮底色（`BTN_BG_HOVER`） |
| `pressed` | 按下底色（`BTN_BG_PRESSED` 或加深色） |
| `hover_pressed` | 按下态悬停（toggle 按钮悬停在按下位置） |
| `focus` | **透明底 + ACCENT 1px 边**（只描边不填充，叠加在当前状态之上） |
| `disabled` | 低对比底 + `TEXT_DIM` 文字 |

- 语义分工：Primary=主操作（ACCENT 高亮）、Secondary=次操作（低调深底）、
  Danger=危险操作（ERROR 红系）。
- 字号 `FONT_BODY`；图标默认最大宽 `DEFAULT_ICON_SIZE`(18)，可用 `PixelButton.icon_size`
  覆盖。
- 音效：hover / click 各自可关、可换、可调音量，默认走 `Master` 总线（详见
  `ui/README.md` §2）。

## 4. 容器锚点（六个布局容器）

全部 `@tool` 薄容器：只管间距/边距/滚动行为默认值，**不隐式添加子节点、不拦截
原生属性**；间距/边距 setter 非负夹紧（`maxi(value, 0)`）且幂等。脚本位于
`ui/components/pixel_*.gd`，`snake_case` 文件名、tab 缩进。

| 组件 | 基类 | 默认值（token） | 导出 | 约定 |
| --- | --- | --- | --- | --- |
| `PixelVBox` | `VBoxContainer` | gap = `SPACE_MD`(16) | `gap: int` | 纵向排布的唯一容器 |
| `PixelHBox` | `HBoxContainer` | gap = `SPACE_MD`(16) | `gap: int` | 横向排布的唯一容器 |
| `PixelGrid` | `GridContainer` | h/v 间距 = `SPACE_MD`(16) | `h_gap: int`、`v_gap: int` | 列数用原生 `columns` |
| `PixelMargin` | `MarginContainer` | 四向 = `SPACE_LG`(24) | `margin_left_v/top_v/right_v/bottom_v: int`、`set_margin_all(v)` | 页面外边距统一 24；属性名避开原生 `margin_*` |
| `PixelCenter` | `CenterContainer` | —（零导出） | — | 单子项居中 |
| `PixelScroll` | `ScrollContainer` | 横向滚动禁用 / 纵向 `SCROLL_MODE_AUTO` | 无（构造时写死） | 双向 `SIZE_EXPAND_FILL` + `follow_focus = true` |

锚点规则：

- **横向内容永远 `PixelHBox`，纵向永远 `PixelVBox`**：页面结构
  `PixelMargin` →（`PixelVBox` 分组）→ 组内 `PixelHBox` 行 / `PixelGrid` 网格。
- **超出即滚动**：内容可能超出视口的区块套 `PixelScroll`（只允许纵向滚动；
  横向溢出视为布局错误，应改用 `PixelHBox` 换行或缩短内容）。
- **居中只靠 `PixelCenter`**：不要用 `size_flags` + 手算偏移居中。
- 容器不做样式（无边框/底色）；需要卡片外观时包 `PixelPanel`。

## 5. 响应式布局

- 页面骨架：根 `Control`（铺满）→ `PixelMargin`（外边距 24）→ `PixelVBox`
  （分组，gap 16）→ 行内 `PixelHBox`（gap 16）。
- 填满剩余空间：显式设 `size_flags_horizontal/vertical = Control.SIZE_EXPAND_FILL`
  （`PixelScroll` 默认双向 Expand Fill）。
- 最小尺寸用 `custom_minimum_size`，**不用绝对 position 摆放**；容器自动布局是
  唯一布局方式。
- 验收基准三档：`1024x640` / `1280x800` / `1920x1080`。契约在每档断言画廊铺满视口、
  关键容器尺寸有效、布局页滚动/居中不塌陷。新增响应式 UI 时至少在 1024 与 1920 两档
  目检一次。

## 6. 焦点规范

- 按钮 `focus` 态 = 透明底 + `ACCENT` 1px 描边（圆角同按钮 8），保证键盘焦点可见
  且不改变按钮占位。
- `PixelScroll.follow_focus = true`：焦点进入屏外子项时滚动容器自动跟随。
- 交互控件的 `focus_mode` 保持原生；弹层关闭后焦点交还触发按钮
  （`PixelPopup.open_for` 的约定）。
- 页面级快捷键（如画廊 ESC 退出）走 `_unhandled_input` + 原生 action
  （`ui_cancel`），不抢控件焦点。

## 7. 正误例

```gdscript
# ✗ 错误：裸数字样式、自造间距、绝对定位
var box := VBoxContainer.new()
box.add_theme_constant_override("separation", 10)   # ✗ 脱离 8/16/24 体系
btn.add_theme_stylebox_override("normal", my_sb)    # ✗ 绕过 Type Variation
child.position = Vector2(100, 50)                   # ✗ 容器内绝对定位

# ✓ 正确：token 取值 + 薄容器 + 主题变体
const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")
const PixelVBoxScript = preload("res://ui/components/pixel_v_box.gd")
const PixelButtonScript = preload("res://ui/components/pixel_button.gd")

var page := PixelVBoxScript.new()          # gap 默认 SPACE_MD(16)
var row := preload("res://ui/components/pixel_h_box.gd").new()  # gap 默认 SPACE_MD(16)
var btn: Button = PixelButtonScript.new()
btn.text = "开始"
btn.set("semantic", 0)                     # 0 主 / 1 次 / 2 危险
row.add_child(btn)
page.add_child(row)
add_child(page)

# ✓ 需要微调间距时，以 token 为基准做加减，不写无来源数字
row.gap = ComponentThemeScript.SPACE_SM + ComponentThemeScript.SPACE_XS  # 12
```

```gdscript
# ✗ 错误：横向滚动兜底溢出、MarginContainer 手写四个 override
var scroll := ScrollContainer.new()
scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS  # ✗ 违反纵向唯一约定

var margin := MarginContainer.new()
margin.add_theme_constant_override("margin_left", 15)   # ✗ 手写边距

# ✓ 正确
var scroll := preload("res://ui/components/pixel_scroll.gd").new()  # 横向已禁用、可跟随焦点
var margin := preload("res://ui/components/pixel_margin.gd").new()  # 四向默认 24
margin.call("set_margin_all", ComponentThemeScript.SPACE_LG)        # 页面级 24
```

## 8. AI 提示词（生成新界面时整段携带）

> 本项目 UI 必须使用 `ui/` 组件库：布局只用 `PixelVBox / PixelHBox / PixelGrid /
> PixelMargin / PixelCenter / PixelScroll` 六个薄容器（`ui/components/pixel_*.gd`），
> 按钮用 `PixelButton`（semantic 0/1/2），卡片用 `PixelPanel`，输入/数值/媒体/菜单
> 组件见 `ui/README.md`。间距、圆角、字号、内容边距一律取 `ui/theme/component_theme.gd`
> 的 token 常量（SPACE_* 8/16/24 体系、CORNER_*、FONT_* 标题 28–36 / 正文 16–18 /
> 辅助 12–14、BUTTON_MARGIN_* / CARD_MARGIN / CONTROL_MARGIN），颜色一律取
> `scripts/ui/ui_theme.gd` 色板常量；样式经 Theme Type Variation 下发，禁止自建
> StyleBox、禁止裸数字样式值、禁止容器内绝对定位、禁止横向滚动兜底溢出。页面骨架：
> PixelMargin(24) → PixelVBox(gap16) → 分组，行内 PixelHBox(gap16)。需要在
> 1024x640 / 1280x800 / 1920x1080 三档下不塌陷、无裁切。

## 9. 验证命令

```bash
# 契约（token、按钮六态几何、六容器、全部 Theme 类型、画廊布局页、多尺寸响应式）
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
	--script res://tests/ui_components_contract.gd
# 期望输出：UI_COMPONENTS_CONTRACT_OK checks=N（N ≥ 1062）

# 运行态目检：编辑器 F6 或调试器启动画廊（ESC 退出）
# 场景 res://scenes/UIComponentGallery.tscn —— 第 7 页「布局」展示六个容器
```

验收要点：契约 0 失败；画廊七个页签齐全且原六页不回归；布局页六张卡（横排/竖排/
网格/边距/居中/滚动）几何正确（HBox 第二子 x=56、VBox 第二子 y=36、网格 2 列、
边距子项 (24,24)、居中按钮居中、滚动仅纵向）；标题 36 / 页签 16 / 卡片标题 28 /
按钮文字 16 在三档视口无裁切；运行日志无组件相关 error。
