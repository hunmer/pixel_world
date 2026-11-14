## pixel_button.gd — 组件库按钮：主/次/危险三种 Theme 语义 + 图标尺寸 + 悬停/点击音效
##
## 只负责选择 Theme Type Variation、图标最大宽度与两个 UI 音效；disabled / focus /
## toggle_mode 等一律保留 Button 原生行为，不接管输入。主题实例来自
## ComponentTheme.create()，每个按钮实例持有独立 Theme（主题实例隔离）；外部显式
## 设置 theme 时优先尊重。
##
## 音效：悬停播 sfx_ui_cursor、点击（原生 pressed，鼠标与键盘 Enter/Space 都经过它）
## 播 sfx_ui_confirm；两个 AudioStreamPlayer 子节点常驻且幂等创建，重复入树不重复
## 连接信号。编辑器（Engine.is_editor_hint()）与 disabled 状态静默；资源/开关/音量/
## 总线均可导出替换。项目未定义 UI/SFX 音频总线，默认输出 Master（不新增 bus
## layout、不改全局音量策略），总线名无效时安全回退 Master。
@tool
class_name PixelButton
extends Button

const ComponentThemeScript = preload("res://ui/theme/component_theme.gd")

## 默认悬停音效：项目现有 UI 光标音效（短促、轻）。
const DEFAULT_HOVER_SFX: AudioStream = preload("res://assets/audio/sfx/ui/sfx_ui_cursor.mp3")
## 默认点击音效：项目现有 UI 确认音效。
const DEFAULT_CLICK_SFX: AudioStream = preload("res://assets/audio/sfx/ui/sfx_ui_confirm.mp3")
## 悬停/点击播放器节点名（契约与运行时观测用，固定不随实例变化）。
const HOVER_PLAYER_NAME: StringName = &"HoverSfx"
const CLICK_PLAYER_NAME: StringName = &"ClickSfx"
## 每个播放器的最大复音数：快速连续悬停/点击时不新增节点、不叠成噪声墙。
const MAX_POLYPHONY: int = 2

## 按钮语义：主操作 / 次操作 / 危险操作（对应 ComponentTheme 的三种变体）。
@export_enum("主操作", "次操作", "危险") var semantic: int = 0:
	set(value):
		semantic = clampi(value, 0, 2)
		_refresh()

## 图标最大宽度（像素）；0 = 使用 ComponentTheme.DEFAULT_ICON_SIZE。
@export_range(0, 128, 1) var icon_size: int = 0:
	set(value):
		icon_size = maxi(value, 0)
		_refresh()

## 悬停音效资源；null 表示静默。可替换为任意 AudioStream。
@export var hover_sfx: AudioStream = DEFAULT_HOVER_SFX:
	set(value):
		hover_sfx = value
		_refresh_sfx()

## 点击音效资源；null 表示静默。可替换为任意 AudioStream。
@export var click_sfx: AudioStream = DEFAULT_CLICK_SFX:
	set(value):
		click_sfx = value
		_refresh_sfx()

## 悬停音效开关：关闭后鼠标进入边界不再播放。
@export var hover_sfx_enabled: bool = true:
	set(value):
		hover_sfx_enabled = value
		_refresh_sfx()

## 点击音效开关：关闭后 pressed 不再播放。
@export var click_sfx_enabled: bool = true:
	set(value):
		click_sfx_enabled = value
		_refresh_sfx()

## 悬停音量（dB）；默认比点击更轻 5 dB。
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var hover_volume_db: float = -8.0:
	set(value):
		hover_volume_db = value
		_refresh_sfx()

## 点击音量（dB）。
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var click_volume_db: float = -3.0:
	set(value):
		click_volume_db = value
		_refresh_sfx()

## 输出音频总线名；项目没有 UI/SFX 总线时默认 Master，名称无效时回退 Master。
@export var sfx_bus: StringName = &"Master":
	set(value):
		sfx_bus = value
		_refresh_sfx()

## 实际调用 play() 的次数（调试 / 契约 / MCP 可观察证据，不参与序列化）。
var hover_play_count: int = 0
var click_play_count: int = 0

var _hover_player: AudioStreamPlayer
var _click_player: AudioStreamPlayer


func _init() -> void:
	# new() 后即带主题与音效播放器，不依赖入树；_ready 再刷新一次保证 @tool 预览一致。
	_refresh()
	_ensure_sfx_players()
	_ensure_sfx_connections()
	_refresh_sfx()


func _ready() -> void:
	_refresh()
	_ensure_sfx_players()
	_ensure_sfx_connections()
	_refresh_sfx()


## 幂等应用主题：重复调用只覆盖同键主题项，不新增子节点/信号。
func _refresh() -> void:
	if theme == null:
		theme = ComponentThemeScript.create()
	theme_type_variation = ComponentThemeScript.variation_for_semantic(semantic)
	var resolved_size: int = (
		icon_size if icon_size > 0 else ComponentThemeScript.DEFAULT_ICON_SIZE
	)
	add_theme_constant_override("icon_max_width", resolved_size)


## 幂等创建两个常驻播放器：重复进树复用同名子节点，不新增。
func _ensure_sfx_players() -> void:
	_hover_player = _get_or_create_player(HOVER_PLAYER_NAME)
	_click_player = _get_or_create_player(CLICK_PLAYER_NAME)


func _get_or_create_player(player_name: StringName) -> AudioStreamPlayer:
	var existing: AudioStreamPlayer = (
		get_node_or_null(NodePath(String(player_name))) as AudioStreamPlayer
	)
	if existing != null:
		return existing
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.max_polyphony = MAX_POLYPHONY
	add_child(player)
	return player


## 幂等连接原生信号：重复进树/重复调用不会重复接线（否则一次 hover 播两次）。
func _ensure_sfx_connections() -> void:
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not pressed.is_connected(_on_pressed_sfx):
		pressed.connect(_on_pressed_sfx)


## 把导出配置同步到播放器；player 尚未创建时（属性初始化期）安全跳过。
func _refresh_sfx() -> void:
	if _hover_player == null or _click_player == null:
		return
	_apply_player_settings(_hover_player, hover_sfx, hover_volume_db)
	_apply_player_settings(_click_player, click_sfx, click_volume_db)


func _apply_player_settings(
	player: AudioStreamPlayer, stream: AudioStream, volume_db: float
) -> void:
	player.stream = stream
	player.volume_db = volume_db
	player.bus = _resolve_bus()


## 总线名有效则用导出值，否则回退 Master（项目当前没有自定义 bus layout）。
func _resolve_bus() -> StringName:
	if not sfx_bus.is_empty() and AudioServer.get_bus_index(sfx_bus) >= 0:
		return sfx_bus
	return &"Master"


## 鼠标首次进入按钮边界：原生 mouse_entered 只在进入时发一次。
func _on_mouse_entered() -> void:
	if not _can_play(hover_sfx_enabled, hover_sfx):
		return
	hover_play_count += 1
	_hover_player.play()


## 原生 pressed：鼠标点击与键盘 Enter/Space 都走这里，每次按下只播一次。
func _on_pressed_sfx() -> void:
	if not _can_play(click_sfx_enabled, click_sfx):
		return
	click_play_count += 1
	_click_player.play()


## 统一静默条件：编辑器 / 禁用 / 开关关闭 / 无资源 / 播放器缺失 / 未入树。
func _can_play(enabled: bool, stream: AudioStream) -> bool:
	return (
		enabled
		and not disabled
		and stream != null
		and _hover_player != null
		and _click_player != null
		and is_inside_tree()
		and not Engine.is_editor_hint()
	)
