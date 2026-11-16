## battle/battle_ui_banner.gd — 结果横幅（从 battle_ui.gd 拆出）
##
## 职责：
##   - 胜利/失败结果横幅（旧 show_result_banner 兼容入口；新集成请用 play_result 演出）
##   - 显示横幅时禁用结束回合按钮（经宿主 end_turn_btn 别名）
##
## 设计：RefCounted 能力模块（battle_ui 拆分件）。宿主 BattleUI（CanvasLayer）经
## setup() 注入为 _ui：横幅挂载（_ui.add_child）与 end_turn_btn 禁用
## （_ui.end_turn_btn.disabled）经宿主 duck-typed 动态访问（与拆分前等价）。
##
## 公开 API（battle_ui 装配层调用）：
##   setup(ui)
##   show_result_banner(text, color)
class_name BattleUiBanner
extends RefCounted

## 宿主 BattleUI（CanvasLayer；duck-typed 动态访问 add_child/end_turn_btn）
var _ui = null


func setup(p_ui) -> void:
	_ui = p_ui


## 显示结果横幅 + 禁用结束回合按钮。5 秒后切场景由根节点 battle.gd 负责
## （子 CanvasLayer 可能在 timer 触发时已 free，直接 get_tree() 会拿到 null）。
func show_result_banner(text: String, color: Color) -> void:
	var banner := Label.new()
	banner.text = text
	banner.add_theme_font_size_override("font_size", 64)
	banner.add_theme_color_override("font_color", color)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 8)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.position -= Vector2(100, 40)
	_ui.add_child(banner)
	_ui.end_turn_btn.disabled = true
