## autosim_battle_adapter.gd — godot-autosim 最小接入适配器：把 BattleRunner 战斗桥接为单动作博弈
#
# 接入模型（最小试点，证明 godot-autosim 0.2.0 在 Godot 4.7 可跑）：
#   - 一次"游戏" = 一整场战斗（BattleRunner 全 AI 自动对局，回合内决策由战斗侧 AI 完成）；
#   - 唯一动作 "auto_play" = 执行整场；框架侧 bot 只负责点下这一步；
#   - 每次迭代用顺序 seed（BASE_SEED + 迭代号）重新加载场景 JSON —— 与
#     tools/simulation_batch.gd 相同的深态隔离策略；
#   - 胜率统计（player 视角）与 turns/steps 指标由 AutoSimBalanceReport 汇总。
#
# 用法（CLI）：
#   godot --headless --path . --script addons/godot_autosim/cli/cli.gd -- \
#     --adapter=res://tools/autosim_battle_adapter.gd \
#     --strategy=res://tools/autosim_first_action_bot.gd \
#     --iterations=8 --seed=42 --output=<dir>/balance_report.json
extends AutoSimGameAdapter


const Loader := preload("res://scripts/battle/automation/battle_scenario_loader.gd")
const Runner := preload("res://scripts/battle/automation/battle_runner.gd")

const SCENARIO_PATH := "res://tests/fixtures/battle_scenarios/quick_duel.json"
const BASE_SEED := 42

var _run_index: int = -1


func _next_seed() -> int:
	_run_index += 1
	return BASE_SEED + _run_index


func create_initial_state() -> Variant:
	var seed_value := _next_seed()
	var loaded := Loader.load_from_file(SCENARIO_PATH, seed_value)
	if not bool(loaded.get("ok", false)):
		push_error("autosim_battle_adapter: 场景加载失败: %s" % String(loaded.get("error", "")))
		return null
	return {
		"scenario": loaded["scenario"],
		"result": null,
	}


func get_roles() -> Array[String]:
	return ["player"]


func get_current_role(_state: Variant) -> String:
	return "player"


func get_available_actions(state: Variant) -> Array:
	var s: Dictionary = state as Dictionary
	if s["result"] == null:
		return ["auto_play"]
	return []


func apply_action(state: Variant, _action: Variant) -> Variant:
	var s: Dictionary = state as Dictionary
	if s["result"] != null:
		return state
	var run := Runner.run(s["scenario"] as Dictionary)
	if not bool(run.get("ok", false)):
		push_error("autosim_battle_adapter: runner 失败: %s" % String(run.get("error", "")))
		return state
	s["result"] = run["result"]
	return s


func is_game_over(state: Variant) -> bool:
	return (state as Dictionary)["result"] != null


func get_winner(state: Variant) -> String:
	var s: Dictionary = state as Dictionary
	if s["result"] == null:
		return ""
	var outcome: Dictionary = (s["result"] as Dictionary).get("outcome", {})
	if String(outcome.get("winner", &"")) == "player":
		return "player"
	if String(outcome.get("winner", &"")) == "enemy":
		return "enemy"
	return ""


func get_run_metrics(state: Variant) -> Dictionary:
	var s: Dictionary = state as Dictionary
	if s["result"] == null:
		return {}
	var outcome: Dictionary = (s["result"] as Dictionary).get("outcome", {})
	return {
		"turns": float(int(outcome.get("turns", 0))),
		"steps": float(int(outcome.get("steps", 0))),
	}


func cleanup_state(_state: Variant) -> void:
	# 状态是纯 Dictionary（无 Node 资源），无需清理
	pass
