## ui/loading_screen.gd — 全局可共用加载遮罩（project.godot autoload: LoadingScreen）
##
## 全屏半透明遮罩 + 右下角加载文字，供任意场景在同步重活（特效预烘焙等）前后调用：
##   LoadingScreen.show_loading()                      # 默认文字「加载中…」
##   LoadingScreen.show_loading("编译地图…")            # 自定义文字
##   await get_tree().process_frame                    # 至少 1-2 帧，让遮罩真正上屏
##   …同步重活…
##   LoadingScreen.hide_loading()
##
## 约定：
##   - show/hide 幂等，重复调用无副作用；hide 后文字复位为默认值。
##   - 全树 MOUSE_FILTER_IGNORE：只反馈、不拦截输入，绝不卡死宿主场景输入。
##   - 不拥有任何业务状态；失败/取消路径由调用方负责 hide（战斗侧在 battle.gd _exit_tree 兜底）。
extends CanvasLayer

const DEFAULT_TEXT := "加载中…"

@onready var _backdrop: ColorRect = $Backdrop
@onready var _label: Label = $LoadingLabel

var _shown := false


func _ready() -> void:
	# autoload 常驻：进场即确保隐藏，任何场景（世界探索/标题/战斗）默认无遮罩。
	hide_loading()


## 显示遮罩。text 非空时覆盖当前文字（空串保留现有文字）；重复调用只更新文字。
func show_loading(text := "") -> void:
	if not text.is_empty():
		_label.text = text
	visible = true
	_shown = true


## 隐藏遮罩并复位文字。重复调用为 no-op。
func hide_loading() -> void:
	visible = false
	_shown = false
	if _label != null:
		_label.text = DEFAULT_TEXT


## 展示期间修改文字（等价 show_loading 的 text 参数，供长任务分阶段更新）。
func set_loading_text(text: String) -> void:
	if not text.is_empty():
		_label.text = text


## 运行态断言用：是否处于展示态。
func is_loading_shown() -> bool:
	return _shown and visible
