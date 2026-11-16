## battle/battle_save.gd — 战旗持久化（完整行动边界提交；演出中退出回退上一完整快照）
##
## 职责：
##   - 收集恢复所需的运行态（回合/阶段/托管/偏好/胜负）
##   - 在完整行动边界提交（回合开始 / 行动收尾 / 终局），经 GameSession.commit 落盘
##   - 缓存最近一次完整快照：演出中途退出时用它补落盘（防半行动丢失，幂等）
##   - 持有恢复态 pending_state，由 battle.gd 在 _ready 末尾取走并驱动状态机
##
## 设计：从 scenes/battle.gd 抽出的 RefCounted（纯数据/IO，无树依赖）。turn/turn_director
## 由 battle.gd 在 setup() 注入；落盘失败提示经 toast_fn 回交（battle_ui.show_toast）。
## chapter 快照由 battle.gd 在 commit() 时传入（battle.gd 保留 _commit_snapshot 薄委托，
## turn_director.on_action_committed 注入面不变）。
##
## 公开 API（battle.gd 调用）：
##   setup(identity, pending_state, turn, turn_director, toast_fn)
##   consume_pending_state() -> Dictionary   # 取走并清空恢复态
##   capture(result) -> Dictionary           # 收集当前运行态
##   commit(chapter, result)                 # 提交 + 落盘
##   flush()                                 # 幂等补落盘（_exit_tree 用）

class_name BattleSave
extends RefCounted

## 非空 → 本场战斗在完整行动边界自动提交。
var identity: String = ""
## 非空 → 恢复进度（battle.gd _ready 末尾 consume 后驱动 _apply_resume_state）。
var pending_state: Dictionary = {}
## 最近一次完整快照：{chapter: Dictionary, state: Dictionary}。
var last_committed: Dictionary = {}

var _turn: TurnManager
var _turn_director: TurnDirector
var _toast_fn: Callable


func setup(
	p_identity: String,
	p_pending_state: Dictionary,
	p_turn: TurnManager,
	p_turn_director: TurnDirector,
	p_toast_fn: Callable
) -> void:
	identity = p_identity
	pending_state = p_pending_state
	_turn = p_turn
	_turn_director = p_turn_director
	_toast_fn = p_toast_fn


## 取走恢复态（一次性：取走即清空，防止重复恢复）。
func consume_pending_state() -> Dictionary:
	var state := pending_state
	pending_state = {}
	return state


## 收集恢复所需的运行态（回合/阶段/托管/偏好/胜负）。
func capture(result: StringName = &"") -> Dictionary:
	return {
		"turn_number": int(_turn.turn_number),
		"phase": _turn.phase,
		"hosting": _turn_director.is_hosting(),
		"prefs": _turn_director.get_prefs().duplicate(true),
		"result": result,
	}


## 在完整行动边界提交（回合开始 / 行动收尾 / 终局）。result 非空表示终局记录。
func commit(chapter: Dictionary, result: StringName = &"") -> void:
	if identity.is_empty():
		return
	last_committed = {
		"chapter": chapter.duplicate(true),
		"state": capture(result),
	}
	flush()


## 落盘最近一次完整快照（幂等；battle.gd _exit_tree 用它补防半途退出）。
func flush() -> void:
	if identity.is_empty() or last_committed.is_empty():
		return
	var res: Dictionary = GameSession.commit(last_committed["chapter"], last_committed["state"])
	if not res.get("ok", false):
		_toast_fn.call("保存失败：%s" % String(res.get("error", "")))
