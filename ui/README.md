# Pixel World · UI 组件库（ui/）

新增的共享 UI 组件层：集中 Theme + 三个 `@tool` 自定义控件，全部复用现有
`scripts/ui/ui_theme.gd`（配色 / StyleBox）与 `scripts/ui/ui_factory.gd`（工厂方法），
不改它们的既有行为。

- 目录：`ui/theme/component_theme.gd`（ComponentTheme）、`ui/components/`（PixelButton / PixelTabs / PixelPanel）。
- 交互画廊：`scenes/UIComponentGallery.tscn`（脚本 `scripts/scenes/ui_component_gallery.gd`），
  在编辑器里 **F6** 独立运行，不依赖战斗参数，不修改默认启动场景；ESC 退出。
- 只新增文件：未改动 `main.gd`、默认启动、`config/startup.cfg`，也未迁移任何现有业务调用。

> 验证状态（2026-11-14）：T3 已通过 headless 契约（`tests/ui_components_contract.gd`）
> 与 MCP 画廊运行态验收（结构 / 节点状态 / 屏幕文字 / 真实点击与键盘输入 / 增量
> error 日志为空）；T4 为 PixelButton 补充 hover/click 音效，并扩展契约与 MCP 真实
> 悬停/点击验证。

## 1. ComponentTheme — 集中主题

`class_name ComponentTheme extends RefCounted`，纯静态工厂，**每次 `create()` 都新建独立 `Theme`**，
不在组件间共享可变主题实例。

```gdscript
const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")

# 独立主题（推荐给单个控件的 theme）
var theme: Theme = ComponentThemeScript.create()

# 语义 → Theme Type Variation 名
var variation: StringName = ComponentThemeScript.variation_for_semantic(
    ComponentThemeScript.ButtonSemantic.DANGER
)  # -> &"PixelButtonDanger"
```

提供的 Type Variation：

| Variation 常量 | 值 | 基类型 | 用途 |
| --- | --- | --- | --- |
| `BUTTON_PRIMARY` | `PixelButtonPrimary` | `Button` | 主操作，ACCENT 高亮 |
| `BUTTON_SECONDARY` | `PixelButtonSecondary` | `Button` | 次操作，低调深底 + BORDER |
| `BUTTON_DANGER` | `PixelButtonDanger` | `Button` | 危险操作，ERROR 红底/红边 |
| `TABS_VARIATION` | `PixelTabs` | `TabContainer` | 页签面板 + 内部 `TabBar` |
| `PANEL_VARIATION` | `PixelPanel` | `PanelContainer` | 卡片：深底 + 边框 + 阴影 |

同时定义了 `TabContainer`、`TabBar` 的 baseline 主题（选中下缘 ACCENT 2px）和
按钮常量：`DEFAULT_ICON_SIZE = 18`、`DEFAULT_FONT_SIZE = 12`、`TAB_FONT_SIZE = 13`。
配色全部取自 `UITheme`，无新增硬编码色板。

## 2. PixelButton — 语义按钮

`@tool class_name PixelButton extends Button`，继承 `Button` 的全部属性/信号/状态。

| 属性 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `semantic` | `int`（`@export_enum`） | `0` | 0 主操作 / 1 次操作 / 2 危险；setter 夹紧到 0..2 并刷新 |
| `icon_size` | `int`（`@export_range(0,128)`） | `0` | 图标最大宽度；0 用主题默认 18 |
| `hover_sfx` | `AudioStream` | `sfx_ui_cursor.mp3` | 悬停音效；`null` = 静默，可替换任意音频 |
| `click_sfx` | `AudioStream` | `sfx_ui_confirm.mp3` | 点击音效；`null` = 静默，可替换任意音频 |
| `hover_sfx_enabled` | `bool` | `true` | 悬停音效开关 |
| `click_sfx_enabled` | `bool` | `true` | 点击音效开关 |
| `hover_volume_db` | `float`（`@export_range(-60,6)`） | `-8.0` | 悬停音量（dB），默认比点击轻 |
| `click_volume_db` | `float`（`@export_range(-60,6)`） | `-3.0` | 点击音量（dB） |
| `sfx_bus` | `StringName` | `Master` | 输出总线；名称不存在时安全回退 `Master` |

行为：

- `_ready()` / 属性 setter 调 `_refresh()`：`theme` 为空时创建 `ComponentTheme`，
  设置 `theme_type_variation` 与 `icon_max_width` 覆盖；**幂等**，不新增节点/信号。
- 音效：`mouse_entered`（原生只在进入边界时发一次）播 hover，原生 `pressed`
  （鼠标点击与键盘 Enter/Space 都经过它）播 click；两个常驻 `AudioStreamPlayer`
  子节点 `HoverSfx` / `ClickSfx` 在 `_init` 创建、`_ready` 复用，重复入树不新增节点、
  不重复连接信号。编辑器 `@tool` 与 `disabled` 状态静默。
- 项目未定义 UI/SFX 音频总线（无 `default_bus_layout.tres`、`project.godot` 无
  `[audio]` 段），默认输出 `Master`；组件不新增/修改全局 bus layout 与音量策略，
  需要分类音量时由业务侧建 bus 后设置 `sfx_bus`。
- 无自定义信号，直接用原生 `pressed`、`toggled`、`button_down/up` 等；
  `disabled`、`focus_mode`、`toggle_mode` 保持原生行为。

```gdscript
const PixelButtonScript = preload("res://ui/components/pixel_button.gd")

var btn: Button = PixelButtonScript.new()
btn.text = "开始"
btn.set("semantic", 0)          # 0 主 / 1 次 / 2 危险
btn.set("icon_size", 24)        # 0 = 主题默认 18
btn.icon = preload("res://addons/at-icons/control/play.svg")
btn.pressed.connect(_on_start_pressed)
add_child(btn)
```

音效配置（全部可导出，也可运行时 `set`）：

```gdscript
btn.set("hover_volume_db", -12.0)      # 默认 -8
btn.set("click_volume_db", -4.0)       # 默认 -3
btn.set("hover_sfx_enabled", false)    # 单独关闭悬停音效
btn.set("click_sfx_enabled", false)    # 单独关闭点击音效
btn.set("sfx_bus", &"UI")              # 名称不存在时自动回退 Master
```

`hover_play_count` / `click_play_count` 是实际调用 `play()` 的只读计数，供调试、
契约与 MCP 运行态观测使用，不参与序列化。

## 3. PixelTabs — 页签容器

`@tool class_name PixelTabs extends TabContainer`，保留原生页签/滚动行为，并在内部
`TabBar` 上应用同一套主题。

| 成员 | 签名 | 说明 |
| --- | --- | --- |
| `add_pixel_tab` | `add_pixel_tab(tab_title: String, icon_name: String = "") -> VBoxContainer` | 追加一页；内部委托 `UIFactory.add_tab`，生成 `<标题>Scroll / <标题>Tab` 两级节点 |
| `theme_type_variation` | `StringName` | 固定为 `PixelTabs`（`TABS_VARIATION`） |

信号沿用 `TabContainer`：`tab_changed(tab)`、`tab_selected(tab)`、`tab_clicked(tab)`、
`tab_button_pressed(tab)` 等。

```gdscript
const PixelTabsScript = preload("res://ui/components/pixel_tabs.gd")

var tabs: TabContainer = PixelTabsScript.new()
add_child(tabs)
var page: VBoxContainer = tabs.call("add_pixel_tab", "按钮 Button", "star")
page.add_child(my_content)
tabs.tab_changed.connect(_on_tab_changed)
```

## 4. PixelPanel — 卡片

`@tool class_name PixelPanel extends PanelContainer`，由 `ui/components/pixel_panel.tscn`
提供固定子结构，脚本只做数据同步，不增删节点。

| 属性 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `title` | `String`（`@export`） | `""` | 标题；空则不显示，`TEXT_MAIN` 16px |
| `description` | `String`（`@export`） | `""` | 说明；自动换行，`TEXT_DIM` 12px |
| `icon` | `Texture2D`（`@export`） | `null` | 头部图标（24×24 槽位） |

| 方法 | 签名 | 说明 |
| --- | --- | --- |
| `get_content_slot` | `get_content_slot() -> Container` | 返回固定的内容槽 `VBox/ContentSlot`；内容由调用方注入 |

固定节点路径（契约用）：

- `VBox/Header` — 头部容器（无标题/说明/图标时隐藏）
- `VBox/Header/Icon` — `TextureRect`
- `VBox/Header/TitleBox/Title` — 标题 `Label`
- `VBox/Header/TitleBox/Description` — 说明 `Label`
- `VBox/ContentSlot` — 内容槽 `VBoxContainer`（始终存在）

```gdscript
const PixelPanelScene = preload("res://ui/components/pixel_panel.tscn")

var card: PanelContainer = PixelPanelScene.instantiate()
card.set("title", "设置")
card.set("description", "说明文字会自动换行。")
card.set("icon", preload("res://addons/at-icons/control/cog.svg"))
var slot: Container = card.call("get_content_slot")
slot.add_child(my_form)
add_child(card)
```

## 5. 与 UIFactory 的关系

`PixelButton` 是「语义变体 + 图标尺寸」的封装；`UIFactory.button()` 是原生主题按钮工厂，
两者可混用。`PixelTabs.add_pixel_tab` 直接复用 `UIFactory.add_tab`，节点命名/滚动容器
与既有调用完全一致。

画廊里同时展示了 `UIFactory` 的输入框 / 下拉 / 开关 / 标签 / 日志：

| 工厂方法 | 返回 | 说明 |
| --- | --- | --- |
| `UIFactory.line_edit(placeholder := "")` | `LineEdit` | 带清空按钮 |
| `UIFactory.option_button()` | `OptionButton` | 调用方 `add_item` / `select` |
| `UIFactory.check_button(text := "", tooltip := "")` | `CheckButton` | 开关 |
| `UIFactory.label(text, font_size, color)` | `Label` | 普通标签 |
| `UIFactory.log_label()` | `RichTextLabel` | 名字固定 `LogLabel`，bbcode + 滚动跟随 |
| `UIFactory.button(text, cb, icon_name)` | `Button` | 三态主题按钮 |

## 6. 主题接入方式

组件默认在自身 `theme == null` 时创建一个 `ComponentTheme` 实例（实例隔离，互不影响）。
如果希望整个界面共用一份主题：

```gdscript
var shared_theme: Theme = ComponentThemeScript.create()
$Root.theme = shared_theme   # 子控件继承；此时组件的 theme 非 null，不再自建
```

注意：不要在多个界面之间共享同一个可变 `Theme` 并做 `set_*` 原地修改，否则会串样式；
需要定制时新建一份。

## 7. 已知限制

- 音效依赖音频设备；`--headless` 下 `AudioStreamPlayer` 不实际出声，契约用
  `hover_play_count` / `click_play_count` 与播放器配置断言，不等价于听感验收。
- 项目没有 UI/SFX 音频总线，所有按钮音效走 `Master`；需要「UI 音量」滑杆时由业务侧
  新建 bus layout 并设置 `sfx_bus`，组件本身不接管全局音量。
- 组件不接入 `project.godot` 全局主题，也不改 `main.gd` / 默认启动；需要业务界面使用时
  自行 `add_child` 或挂到现有容器里。
- 运行期契约（实例化、主题解析、信号、焦点、音效触发）见
  `tests/ui_components_contract.gd`；改动组件后只跑该契约即可。
