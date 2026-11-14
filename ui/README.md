# Pixel World · UI 组件库（ui/）

新增的共享 UI 组件层：集中 Theme + 十六个 `@tool` 自定义控件（按钮 / 页签 / 卡片 +
输入框 / 下拉 / 开关 / 滑块 / 数值框 / 进度条 / 图片 / 图标 / 多行文本 / 动作菜单 /
弹层 / 音频容器 / 视频容器），全部复用现有
`scripts/ui/ui_theme.gd`（配色 / StyleBox）与 `scripts/ui/ui_factory.gd`（工厂方法），
不改它们的既有行为。

- 目录：`ui/theme/component_theme.gd`（ComponentTheme）、`ui/components/`（PixelButton / PixelTabs / PixelPanel
  与六类输入/数值组件、七类媒体/菜单组件）。
- 交互画廊：`scenes/UIComponentGallery.tscn`（脚本 `scripts/scenes/ui_component_gallery.gd`），
  只展示真实组件、短标签与真实值，不含用法/API/说明文字；在编辑器里 **F6** 独立运行，
  不依赖战斗参数，不修改默认启动场景；ESC 退出。
- 只新增文件：未改动 `main.gd`、默认启动、`config/startup.cfg`，也未迁移任何现有业务调用。

> 验证状态（2026-11-14）：T3 已通过 headless 契约（`tests/ui_components_contract.gd`）
> 与 MCP 画廊运行态验收；T4 为 PixelButton 补充 hover/click 音效并扩展契约；T5 新增
> 六类组件、精简画廊文字并更新契约（headless 457 checks）；T6 新增七类媒体/菜单组件、
> 六页画廊与真实 `.ogv` 视频样例（headless 735 checks）。

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
| `LINE_EDIT_VARIATION` | `PixelLineEdit` | `LineEdit` | 输入框 |
| `OPTION_BUTTON_VARIATION` | `PixelOptionButton` | `OptionButton` | 下拉 |
| `CHECK_BUTTON_VARIATION` | `PixelCheckButton` | `CheckButton` | 开关 |
| `SLIDER_VARIATION` | `PixelSlider` | `HSlider` | 滑块 |
| `SPIN_BOX_VARIATION` | `PixelSpinBox` | `SpinBox` | 数值框 |
| `PROGRESS_BAR_VARIATION` | `PixelProgressBar` | `ProgressBar` | 进度条 |
| `IMAGE_VARIATION` | `PixelImage` | `PanelContainer` | 图片容器 |
| `TEXT_AREA_VARIATION` | `PixelTextArea` | `TextEdit` | 多行文本 |
| `DROPDOWN_VARIATION` | `PixelDropdown` | `MenuButton` | 动作菜单 |
| `POPUP_VARIATION` | `PixelPopup` | `PopupPanel` | 弹层 |

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

## 5. 输入与数值组件

六个薄包装：只接管 `theme` 与 `theme_type_variation`，继承原生控件全部属性、
信号、取值范围、禁用/焦点/键盘行为；不复制业务状态，也不在每个组件重写样式。

| 组件 | 基类 | Variation | 常用原生信号 |
| --- | --- | --- | --- |
| `PixelLineEdit` | `LineEdit` | `PixelLineEdit` | `text_changed`、`text_submitted` |
| `PixelOptionButton` | `OptionButton` | `PixelOptionButton` | `item_selected`、`item_focused` |
| `PixelCheckButton` | `CheckButton` | `PixelCheckButton` | `toggled` |
| `PixelSlider` | `HSlider` | `PixelSlider` | `value_changed`、`drag_started/ended` |
| `PixelSpinBox` | `SpinBox` | `PixelSpinBox` | `value_changed`（内部 `LineEdit` 套 `PixelLineEdit`） |
| `PixelProgressBar` | `ProgressBar` | `PixelProgressBar` | 无（显示组件） |

```gdscript
const PixelLineEditScript = preload("res://ui/components/pixel_line_edit.gd")
const PixelSliderScript = preload("res://ui/components/pixel_slider.gd")

var name_edit: LineEdit = PixelLineEditScript.new()
name_edit.placeholder_text = "名称"
var volume: HSlider = PixelSliderScript.new()
volume.min_value = 0.0
volume.max_value = 100.0
volume.step = 1.0
volume.value_changed.connect(_on_volume_changed)
```

`PixelSpinBox` 的 `_refresh()` 会把内部 `LineEdit` 指向 `PixelLineEdit` 变体，
数值框外观仍由 `PixelSpinBox` 变体控制。

画廊「输入 / 数值」页直接使用这六个组件：文本输入实时更新预览值，下拉选择与
开关写反馈，滑块和数值框互相联动并驱动进度条，重置统一复位。

## 6. 媒体与菜单组件

图片/图标/多行文本/动作菜单/弹层为薄包装或简单组合；音频/视频容器由 `PanelContainer`
组合原生播放器与播放控制，统一复用 `PANEL_VARIATION` 卡片面。

| 组件 | 基类 | Variation | 导出/成员 | 常用信号 |
| --- | --- | --- | --- | --- |
| `PixelImage` | `PanelContainer` | `PixelImage` | `texture: Texture2D`、`image_size: Vector2i`、`stretch_mode: TextureRect.StretchMode` | 无 |
| `PixelIcon` | `TextureRect` | —（无变体） | `icon_size: int`（8..128，默认 24）、`icon_color: Color` | 无 |
| `PixelTextArea` | `TextEdit` | `PixelTextArea` | `placeholder: String` | 原生 `text_changed` 等 |
| `PixelDropdown` | `MenuButton` | `PixelDropdown` | `items: PackedStringArray`、`add_choice(text) -> int`、`get_choice_count() -> int` | 原生 `get_popup().id_pressed(id)` |
| `PixelPopup` | `PopupPanel` | `PixelPopup` | `open_for(opener: Control)` | 原生 `about_to_popup` / `popup_hide` |
| `PixelAudioPlayer` | 组合 `PanelContainer` | `PixelPanel` | `stream: AudioStream`、`volume_db`、`autoplay`、`play_sound()/pause_sound()/stop_sound()`、`get_player()`、`get_progress_slider()` | `playback_started` / `playback_paused` / `playback_stopped` |
| `PixelVideoPlayer` | 组合 `PanelContainer` | `PixelPanel` | `stream: VideoStream`、`video_size: Vector2i`、`autoplay`、`play_video()/pause_video()/stop_video()` | 同左 |

要点：

- `PixelImage` 固定内部 `Image` 子节点（`TextureRect`）；`image_size` 驱动最小尺寸，
  `stretch_mode` 支持等比适配（`KEEP_ASPECT_CENTERED`）与裁切（`KEEP_ASPECT_COVERED`）；
  重复进树不新增节点。
- `PixelIcon` 不挂 Theme 变体，直接用 `icon_size`（夹紧 8..128）与 `icon_color`（写入
  `modulate`）。
- `PixelTextArea` / `PixelDropdown` 只接管主题：多行编辑、换行、只读（`editable = false`）、
  菜单选择信号全部走原生。`PixelDropdown` 用 `items` 或 `add_choice` 建动作条目，与
  `PixelOptionButton`（单值选择）分工不同。
- `PixelPopup.open_for(opener)` 记录触发按钮，`popup_hide` 后自动 `grab_focus` 回该按钮；
  ESC 关闭由 `PopupPanel` 原生行为提供。
- 音频/视频容器首次 `_refresh` 建 `Player`/`Video`、`Progress`、`PositionLabel` 与
  「播放/暂停/停止」三个 `PixelButton`；空 `stream` 的播放请求被安全忽略；编辑器
  `@tool` 不自动播放；`_process` 只在播放时刷新进度。
- 视频格式：Godot 内置 `VideoStreamTheora`，使用 `.ogv`（Theora 编码）。仓库样例
  `assets/video/ui/ui_demo.ogv` 由 ffmpeg（`testsrc2` + `libtheora`）合成，无第三方素材；
  `.mp4/.webm` 需额外插件，不在支持范围。
- 音频容器沿用 `PixelButton` 的总线约定：默认 `Master`，业务侧可建 bus 后自行切换。

```gdscript
const PixelImageScript = preload("res://ui/components/pixel_image.gd")
const PixelAudioPlayerScript = preload("res://ui/components/pixel_audio_player.gd")
const PixelPopupScript = preload("res://ui/components/pixel_popup.gd")

var image: Control = PixelImageScript.new()
image.set("texture", preload("res://assets/markers/tile_box.png"))
image.set("image_size", Vector2i(240, 135))

var audio: Control = PixelAudioPlayerScript.new()
audio.set("stream", preload("res://assets/audio/sfx/ui/sfx_ui_confirm.mp3"))
audio.call("play_sound")

var popup: PopupPanel = PixelPopupScript.new()
add_child(popup)
popup.call("open_for", some_button)   # 关闭后焦点自动回 some_button
```

## 7. 与 UIFactory 的关系

`PixelButton` 是「语义变体 + 图标尺寸」的封装；`UIFactory.button()` 是原生主题按钮工厂，
两者可混用。`PixelTabs.add_pixel_tab` 直接复用 `UIFactory.add_tab`，节点命名/滚动容器
与既有调用完全一致。

画廊的按钮 / 卡片 / 输入 / 数值 / 媒体 / 菜单六页只展示真实组件与短标签，不显示 API 或用法说明；
以下 `UIFactory` 方法仍可在业务界面直接使用：

| 工厂方法 | 返回 | 说明 |
| --- | --- | --- |
| `UIFactory.line_edit(placeholder := "")` | `LineEdit` | 带清空按钮 |
| `UIFactory.option_button()` | `OptionButton` | 调用方 `add_item` / `select` |
| `UIFactory.check_button(text := "", tooltip := "")` | `CheckButton` | 开关 |
| `UIFactory.label(text, font_size, color)` | `Label` | 普通标签 |
| `UIFactory.log_label()` | `RichTextLabel` | 名字固定 `LogLabel`，bbcode + 滚动跟随 |
| `UIFactory.button(text, cb, icon_name)` | `Button` | 三态主题按钮 |

## 8. 主题接入方式

组件默认在自身 `theme == null` 时创建一个 `ComponentTheme` 实例（实例隔离，互不影响）。
如果希望整个界面共用一份主题：

```gdscript
var shared_theme: Theme = ComponentThemeScript.create()
$Root.theme = shared_theme   # 子控件继承；此时组件的 theme 非 null，不再自建
```

注意：不要在多个界面之间共享同一个可变 `Theme` 并做 `set_*` 原地修改，否则会串样式；
需要定制时新建一份。

## 9. 已知限制

- 音效依赖音频设备；`--headless` 下 `AudioStreamPlayer` 不实际出声，契约用
  `hover_play_count` / `click_play_count` 与播放器配置断言，不等价于听感验收。
- 音频/视频容器在 `--headless` 下同样以 `playing` / `paused` / `stream_position` 等
  可观察状态断言，不替代实际画面与声音验收。
- 视频只支持 Godot 内置的 Theora（`.ogv`）；其它编码需安装额外插件。
- 项目没有 UI/SFX 音频总线，所有按钮音效与音频容器默认走 `Master`；需要「UI 音量」
  滑杆时由业务侧新建 bus layout 并设置 `sfx_bus`，组件本身不接管全局音量。
- 组件不接入 `project.godot` 全局主题，也不改 `main.gd` / 默认启动；需要业务界面使用时
  自行 `add_child` 或挂到现有容器里。
- 运行期契约（实例化、主题解析、信号、焦点、音效触发、六类控件与画廊交互）见
  `tests/ui_components_contract.gd`；改动组件后只跑该契约即可。
